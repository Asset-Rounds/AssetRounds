import CryptoKit
import Foundation
import SwiftData

enum FinalizationServiceError: Error, Equatable {
    case invalidGeneration
    case invalidDraft
    case invalidEvidence
    case invalidSelection
    case preconditionFailed
    case journalFailed
    case saveFailed
    case cleanupFailed
    /// The exact correction database authority described by this frozen
    /// outcome was committed, but delivery must wait for clean-context journal
    /// recovery instead of being presented as a precommit failure.
    case committedRecoveryRequired(ReportCorrectionFinalizationOutcome)
}

struct FinalizationServiceInput {
    let draft: WorkflowRecord
    let asset: Asset
    let site: Site
    let evidence: [EvidenceFile]
    let outcomeKey: String
    let outcomeDisplay: String
    let issueLabel: SignPack.RegistryEntry?
    let couldNotVerify: SignPack.RegistryEntry?
    let note: String?
    let completedAt: Date
    let snapshotCreatedAt: Date
    let sourceApp: SourceAppSnapshotV1
    let identifiers: FinalizationIdentifiers
}

struct FinalizationServiceOutcome: Equatable, Sendable {
    let result: FinalizationResult
    let createdAuthority: Bool
}

struct ReportCorrectionFinalizationInput {
    let currentRecord: WorkflowRecord
    let packet: Packet
    let currentReport: Report
    let currentSnapshot: ReportSnapshotV1
    let note: String?
    let snapshotCreatedAt: Date
    let sourceApp: SourceAppSnapshotV1
    let identifiers: ReportCorrectionIdentifiers
}

struct ReportCorrectionFinalizationOutcome: Equatable, Sendable {
    let recordID: UUID
    let packetID: UUID
    let stableRootID: UUID
    let reportID: UUID
    let priorReportID: UUID
    let snapshotRelativePath: String
    let snapshotSHA256: String
    let createdAuthority: Bool
}

enum FinalizationServiceFailurePoint: Equatable, Sendable {
    case modelSave
}

@MainActor
final class FinalizationServiceFailureInjection {
    private var failurePoint: FinalizationServiceFailurePoint?

    init(failOnceAt failurePoint: FinalizationServiceFailurePoint) {
        self.failurePoint = failurePoint
    }

    func removeFailure() {
        failurePoint = nil
    }

    fileprivate func consume(_ point: FinalizationServiceFailurePoint) -> Bool {
        guard failurePoint == point else { return false }
        failurePoint = nil
        return true
    }
}

/// Test-only synchronization at the correction database-commit boundary.
/// Production callers leave this nil. The handler runs synchronously on the
/// main actor and may be used to prove that unrelated dirty context is neither
/// saved nor rolled back after the correction authority has committed.
@MainActor
final class FinalizationServiceOperationBarrier {
    enum Boundary: Equatable, Sendable {
        case afterCorrectionDatabaseCommit
    }

    private let handler: (Boundary) -> Void

    init(_ handler: @escaping (Boundary) -> Void) {
        self.handler = handler
    }

    fileprivate func reach(_ boundary: Boundary) {
        handler(boundary)
    }
}

@MainActor
final class FinalizationService {
    private let modelContext: ModelContext
    private let signPack: SignPack
    private let generationRootURL: URL
    private let generationID: UUID
    private let rootIdentity: ReportPDFAnchoredFile.RootIdentity
    private let intentStore: FinalizationIntentStore
    private let failureInjection: FinalizationServiceFailureInjection?
    private let operationBarrier: FinalizationServiceOperationBarrier?

    init(
        modelContext: ModelContext,
        signPack: SignPack,
        generationRootURL: URL,
        intentStoreFailureInjection: FinalizationIntentStoreFailureInjection? = nil,
        failureInjection: FinalizationServiceFailureInjection? = nil,
        operationBarrier: FinalizationServiceOperationBarrier? = nil,
        expectedRootIdentity: ReportPDFAnchoredFile.RootIdentity? = nil
    ) throws {
        let root = generationRootURL.standardizedFileURL
        guard root.deletingLastPathComponent().lastPathComponent == "generations",
              root.deletingLastPathComponent().deletingLastPathComponent()
                .lastPathComponent == "FieldEvidenceData",
              let generationID = UUID(uuidString: root.lastPathComponent),
              generationID.uuidString.lowercased() == root.lastPathComponent else {
            throw FinalizationServiceError.invalidGeneration
        }
        self.modelContext = modelContext
        self.signPack = signPack
        self.generationRootURL = root
        self.generationID = generationID
        let capturedRootIdentity: ReportPDFAnchoredFile.RootIdentity
        do {
            let observedRootIdentity = try ReportPDFAnchoredFile.rootIdentity(at: root)
            guard expectedRootIdentity.map({ $0 == observedRootIdentity }) ?? true else {
                throw FinalizationServiceError.invalidGeneration
            }
            capturedRootIdentity = expectedRootIdentity ?? observedRootIdentity
            self.rootIdentity = capturedRootIdentity
        } catch {
            throw FinalizationServiceError.invalidGeneration
        }
        self.intentStore = FinalizationIntentStore(
            generationRootURL: root,
            failureInjection: intentStoreFailureInjection,
            expectedGenerationRootIdentity: capturedRootIdentity
        )
        self.failureInjection = failureInjection
        self.operationBarrier = operationBarrier
    }

    func finalize(_ input: FinalizationServiceInput) async throws -> FinalizationServiceOutcome {
        guard !modelContext.hasChanges else {
            throw FinalizationServiceError.preconditionFailed
        }
        if let replay = try replayedFinalization(input) {
            return FinalizationServiceOutcome(
                result: replay,
                createdAuthority: false
            )
        }
        try validateFrozenInput(input)
        try validateEvidenceFiles(input.evidence)
        let frozen = try freeze(input)

        let prepared: PreparedFinalization
        let promoted: PromotedFinalization
        let snapshotPromoted: PromotedFinalization
        let priorDraftState = DraftMutationState(input.draft)
        let priorIssueState = frozen.recheckPlan.flatMap { _ in
            frozen.issue.map(IssueMutationState.init)
        }
        do {
            try requireFrozenRootIdentity()
            prepared = try await intentStore.prepare(
                intent: frozen.intent,
                snapshot: frozen.encodedSnapshot
            )
            try requireFrozenRootIdentity()
            promoted = try await intentStore.promoteSnapshot(prepared)
            try requireFrozenRootIdentity()
            snapshotPromoted = try await intentStore.advance(
                promoted,
                to: .snapshotPromoted
            )
            try requireFrozenRootIdentity()
        } catch {
            throw FinalizationServiceError.journalFailed
        }

        var didBeginDatabaseMutation = false
        do {
            guard !modelContext.hasChanges else {
                throw FinalizationServiceError.preconditionFailed
            }
            try validateFrozenInput(input)
            try validateEvidenceFiles(input.evidence)
            try validateDatabasePreconditions(input)
            let currentPayload = try makePayload(
                input,
                issue: frozen.issue,
                packet: frozen.packet,
                report: frozen.report
            )
            guard currentPayload == frozen.intent.finalizationPayload else {
                throw FinalizationServiceError.preconditionFailed
            }
            let currentSnapshot = try makeSnapshot(
                input,
                issue: frozen.issue
            )
            let currentEncodedSnapshot = try ReportSnapshotEncoderV1().encode(
                currentSnapshot
            )
            guard currentEncodedSnapshot == frozen.encodedSnapshot else {
                throw FinalizationServiceError.preconditionFailed
            }
            didBeginDatabaseMutation = true
            applyDatabaseMutation(input, frozen: frozen)
            if failureInjection?.consume(.modelSave) == true {
                throw FinalizationServiceError.saveFailed
            }
            try modelContext.save()
        } catch {
            if didBeginDatabaseMutation {
                // Restore the mutated draft while the transaction is still
                // pending so rollback leaves both storage and held state at
                // the exact prior authority.
                priorDraftState.restore(input.draft)
                if let issue = frozen.issue {
                    priorIssueState?.restore(issue)
                }
                modelContext.rollback()
            }
            do {
                try requireFrozenRootIdentity()
                try await intentStore.rollbackUncommitted(snapshotPromoted)
                try requireFrozenRootIdentity()
            } catch {
                throw FinalizationServiceError.cleanupFailed
            }
            if error is FinalizationServiceError {
                throw error
            }
            throw FinalizationServiceError.saveFailed
        }

        let committed: PromotedFinalization
        do {
            try requireFrozenRootIdentity()
            committed = try await intentStore.advance(
                snapshotPromoted,
                to: .databaseCommitted
            )
            try requireFrozenRootIdentity()
            try await intentStore.cleanupCommitted(committed)
            try requireFrozenRootIdentity()
        } catch {
            throw FinalizationServiceError.cleanupFailed
        }

        return FinalizationServiceOutcome(
            result: FinalizationResult(
                recordID: input.draft.id,
                packetID: input.identifiers.packetID,
                stableRootID: input.identifiers.stableRootID,
                reportID: input.identifiers.reportID,
                issueID: input.identifiers.issueID,
                snapshotRelativePath: frozen.snapshotRelativePath,
                snapshotSHA256: frozen.encodedSnapshot.sha256
            ),
            createdAuthority: true
        )
    }

    /// Atomically appends a note-only correction beneath the existing Packet.
    /// The immediately prior record/report remain immutable; only the Packet's
    /// current-record pointer advances before the pending replacement renders.
    func finalizeCorrection(
        _ input: ReportCorrectionFinalizationInput
    ) async throws -> ReportCorrectionFinalizationOutcome {
        guard !modelContext.hasChanges else {
            throw FinalizationServiceError.preconditionFailed
        }
        if let replay = try replayedCorrection(input) {
            return replay
        }
        let frozen = try freezeCorrection(input)
        let committedOutcome = ReportCorrectionFinalizationOutcome(
            recordID: frozen.plan.recordAfter.id,
            packetID: frozen.plan.packetAfter.id,
            stableRootID: frozen.plan.packetAfter.stableRootID,
            reportID: frozen.plan.reportInsert.id,
            priorReportID: input.currentReport.id,
            snapshotRelativePath: frozen.plan.reportInsert.snapshotRelativePath,
            snapshotSHA256: frozen.plan.reportInsert.snapshotSHA256,
            createdAuthority: true
        )

        let prepared: PreparedFinalization
        let promoted: PromotedFinalization
        let snapshotPromoted: PromotedFinalization
        do {
            try requireFrozenRootIdentity()
            prepared = try await intentStore.prepare(
                intent: frozen.intent,
                snapshot: frozen.encodedSnapshot
            )
            try requireFrozenRootIdentity()
            promoted = try await intentStore.promoteSnapshot(prepared)
            try requireFrozenRootIdentity()
            snapshotPromoted = try await intentStore.advance(
                promoted,
                to: .snapshotPromoted
            )
            try requireFrozenRootIdentity()
        } catch {
            throw FinalizationServiceError.journalFailed
        }

        let packetCurrentBefore = input.packet.currentRecordID
        var didBeginDatabaseMutation = false
        do {
            guard !modelContext.hasChanges else {
                throw FinalizationServiceError.preconditionFailed
            }
            let current = try freezeCorrection(input)
            let revalidatedSource = try ReportDeliveryCoordinator(
                modelContext: modelContext,
                generationRootURL: generationRootURL,
                signPack: signPack,
                expectedRootIdentity: rootIdentity
            ).validatedReadyReport(id: input.currentReport.id)
            guard current.intent == frozen.intent,
                  current.encodedSnapshot == frozen.encodedSnapshot,
                  revalidatedSource.snapshot == input.currentSnapshot,
                  try anchoredSnapshotData(
                    frozen.plan.reportInsert.snapshotRelativePath
                  ) == frozen.encodedSnapshot.data else {
                throw FinalizationServiceError.preconditionFailed
            }
            try validateCorrectionDatabasePreconditions(input, plan: frozen.plan)
            didBeginDatabaseMutation = true
            try applyCorrection(frozen.plan, packet: input.packet)
            if failureInjection?.consume(.modelSave) == true {
                throw FinalizationServiceError.saveFailed
            }
            try modelContext.save()
        } catch {
            if didBeginDatabaseMutation {
                // Restore the sole mutated preexisting field before rollback;
                // SwiftData does not promise to refresh held model instances.
                input.packet.currentRecordID = packetCurrentBefore
                modelContext.rollback()
            }
            do {
                try requireFrozenRootIdentity()
                try await intentStore.rollbackUncommitted(snapshotPromoted)
                try requireFrozenRootIdentity()
            } catch {
                throw FinalizationServiceError.cleanupFailed
            }
            if error is FinalizationServiceError { throw error }
            throw FinalizationServiceError.saveFailed
        }

        operationBarrier?.reach(.afterCorrectionDatabaseCommit)
        guard !modelContext.hasChanges else {
            throw FinalizationServiceError.committedRecoveryRequired(committedOutcome)
        }
        do {
            try requireFrozenRootIdentity()
            let committed = try await intentStore.advance(
                snapshotPromoted,
                to: .databaseCommitted
            )
            guard !modelContext.hasChanges else {
                throw FinalizationServiceError.committedRecoveryRequired(committedOutcome)
            }
            try requireFrozenRootIdentity()
            try await intentStore.cleanupCommitted(committed)
            guard !modelContext.hasChanges else {
                throw FinalizationServiceError.committedRecoveryRequired(committedOutcome)
            }
            try requireFrozenRootIdentity()
        } catch {
            if let serviceError = error as? FinalizationServiceError,
               case .committedRecoveryRequired = serviceError {
                throw serviceError
            }
            throw FinalizationServiceError.committedRecoveryRequired(committedOutcome)
        }

        return committedOutcome
    }

    private func replayedFinalization(
        _ input: FinalizationServiceInput
    ) throws -> FinalizationResult? {
        let mutationID = input.identifiers.mutationID
        let mutationRecords = try modelContext.fetch(
            FetchDescriptor<WorkflowRecord>(
                predicate: #Predicate { $0.finalizationMutationID == mutationID }
            )
        )
        guard mutationRecords.count <= 1 else {
            throw FinalizationServiceError.preconditionFailed
        }
        guard let record = mutationRecords.first else { return nil }
        if record.stage == WorkflowStage.recheck.rawValue {
            return try replayedRecheckFinalization(input, record: record)
        }

        let packets = try modelContext.fetch(FetchDescriptor<Packet>()).filter {
            $0.id == input.identifiers.packetID
                || $0.stableRootID == input.identifiers.stableRootID
                || $0.currentRecordID == record.id
        }
        let reports = try modelContext.fetch(FetchDescriptor<Report>()).filter {
            $0.id == input.identifiers.reportID
                || $0.packetID == input.identifiers.packetID
                || $0.sourceRecordID == record.id
        }
        let issues = try modelContext.fetch(FetchDescriptor<Issue>()).filter { issue in
            (input.identifiers.issueID.map { $0 == issue.id } ?? false)
                || issue.openedByRecordID == record.id
        }
        guard record === input.draft,
              packets.count == 1,
              reports.count == 1,
              issues.count == (input.identifiers.issueID == nil ? 0 : 1) else {
            throw FinalizationServiceError.preconditionFailed
        }
        let packet = packets[0]
        let report = reports[0]
        let issue = issues.first
        let sortedEvidence = input.evidence.sorted(by: evidenceOrder)
        guard record.id == input.draft.id,
              record.assetID == input.asset.id,
              input.asset.siteID == input.site.id,
              record.revisionKind == WorkflowRevisionKind.original.rawValue,
              record.stage == WorkflowStage.check.rawValue,
              record.parentRecordID == nil,
              record.recordRevisionRootID == record.id,
              record.revisesRecordID == nil,
              record.evidenceSourceRecordID == nil,
              record.state == WorkflowState.completed.rawValue,
              record.draftStepKey == nil,
              record.completedAt == input.completedAt,
              record.outcomeKey == input.outcomeKey,
              record.couldNotVerifyKey == input.couldNotVerify?.key,
              record.couldNotVerifyDisplaySnapshot == input.couldNotVerify?.display,
              record.couldNotVerifyRegistryVersion == input.couldNotVerify.map { _ in signPack.couldNotVerifyReasons.version },
              record.note == input.note,
              record.packID == signPack.packID,
              record.packSchemaVersion == signPack.schemaVersion,
              record.packContentVersion == signPack.contentVersion,
              record.pdfTemplateID == "field.evidence.pdf.worklight.v1",
              record.pdfTemplateVersion == 1,
              record.packetID == packet.id,
              record.issueID == issue?.id,
              validCouldNotVerifySelection(input),
              (input.outcomeKey == "could_not_verify"
                ? (sortedEvidence.count <= 2
                    && Set(sortedEvidence.map(\.purposeKey)).count == sortedEvidence.count
                    && sortedEvidence.allSatisfy { $0.purposeKey == "wide_context" || $0.purposeKey == "close_detail" })
                : sortedEvidence.map(\.purposeKey) == ["wide_context", "close_detail"]),
              sortedEvidence.allSatisfy({
                  $0.recordID == record.id
                    && $0.mimeType == MediaContractV1.durableMIMEType
              }),
              purposeDisplay("wide_context") != nil,
              purposeDisplay("close_detail") != nil,
              packet.id == input.identifiers.packetID,
              packet.stableRootID == input.identifiers.stableRootID,
              packet.currentRecordID == record.id,
              packet.evaluationCounted,
              packet.contentDeletedAt == nil,
              packet.createdAt == input.completedAt,
              report.id == input.identifiers.reportID,
              report.packetID == packet.id,
              report.sourceRecordID == record.id,
              report.snapshotSchemaVersion == 1,
              report.snapshotRelativePath
                == "snapshots/\(report.id.uuidString.lowercased()).json",
              report.pdfState == ReportPDFState.pending.rawValue,
              report.pdfRelativePath == nil,
              report.pdfSHA256 == nil,
              report.createdAt == input.snapshotCreatedAt,
              report.replacesReportID == nil,
              replayIssueMatches(issue, input: input) else {
            throw FinalizationServiceError.preconditionFailed
        }

        try validateEvidenceFiles(input.evidence)
        let expectedSnapshot = try ReportSnapshotEncoderV1().encode(
            makeSnapshot(input, issue: issue)
        )
        guard expectedSnapshot.sha256 == report.snapshotSHA256,
              try anchoredSnapshotData(report.snapshotRelativePath) == expectedSnapshot.data else {
            throw FinalizationServiceError.preconditionFailed
        }
        return FinalizationResult(
            recordID: record.id,
            packetID: packet.id,
            stableRootID: packet.stableRootID,
            reportID: report.id,
            issueID: issue?.id,
            snapshotRelativePath: report.snapshotRelativePath,
            snapshotSHA256: report.snapshotSHA256
        )
    }

    private func replayedRecheckFinalization(
        _ input: FinalizationServiceInput,
        record: WorkflowRecord
    ) throws -> FinalizationResult {
        guard record === input.draft,
              record.assetID == input.asset.id,
              record.outcomeKey == input.outcomeKey,
              record.note == input.note,
              record.completedAt == input.completedAt,
              record.finalizationMutationID == input.identifiers.mutationID,
              record.packetID == input.identifiers.packetID,
              record.issueID == input.identifiers.issueID,
              let issueID = record.issueID,
              let parentID = record.parentRecordID else {
            throw FinalizationServiceError.preconditionFailed
        }
        let issues = try modelContext.fetch(FetchDescriptor<Issue>()).filter {
            $0.id == issueID
        }
        let parents = try modelContext.fetch(FetchDescriptor<WorkflowRecord>()).filter {
            $0.id == parentID
        }
        let packets = try modelContext.fetch(FetchDescriptor<Packet>()).filter {
            $0.id == input.identifiers.packetID
                || $0.stableRootID == input.identifiers.stableRootID
                || $0.currentRecordID == record.id
        }
        let reports = try modelContext.fetch(FetchDescriptor<Report>()).filter {
            $0.id == input.identifiers.reportID
                || $0.packetID == input.identifiers.packetID
                || $0.sourceRecordID == record.id
        }
        guard issues.count == 1, parents.count == 1,
              packets.count == 1, reports.count == 1 else {
            throw FinalizationServiceError.preconditionFailed
        }
        let issueAfter = issuePayload(issues[0])
        let issueBefore = IssuePayloadV1(
            id: issueAfter.id,
            schemaVersion: issueAfter.schemaVersion,
            assetID: issueAfter.assetID,
            openedByRecordID: issueAfter.openedByRecordID,
            labelKey: issueAfter.labelKey,
            labelDisplaySnapshot: issueAfter.labelDisplaySnapshot,
            status: IssueStatus.recheckDue.rawValue,
            resolvedByRecordID: nil,
            createdAt: issueAfter.createdAt,
            updatedAt: parents[0].completedAt ?? issueAfter.createdAt
        )
        let plan = try RecheckOutcomeRule.makePlan(RecheckOutcomeRuleInput(
            draft: recheckDraftBefore(record),
            parent: recordPayload(parents[0]),
            issue: issueBefore,
            outcomeKey: input.outcomeKey,
            note: input.note,
            completedAt: input.completedAt,
            mutationID: input.identifiers.mutationID,
            packetID: input.identifiers.packetID
        ))
        let packet = packets[0]
        let report = reports[0]
        guard recordPayload(record) == plan.recordAfter,
              issueAfter == plan.issueAfter,
              packet.stableRootID == input.identifiers.stableRootID,
              packet.currentRecordID == record.id,
              packet.evaluationCounted,
              packet.contentDeletedAt == nil,
              report.id == input.identifiers.reportID,
              report.packetID == packet.id,
              report.sourceRecordID == record.id,
              report.snapshotSchemaVersion == 1,
              report.snapshotRelativePath
                == "snapshots/\(report.id.uuidString.lowercased()).json",
              report.createdAt == input.snapshotCreatedAt,
              report.replacesReportID == nil,
              report.pdfState == ReportPDFState.pending.rawValue,
              report.pdfRelativePath == nil,
              report.pdfSHA256 == nil,
              let snapshotData = try? anchoredSnapshotData(report.snapshotRelativePath),
              sha256(snapshotData) == report.snapshotSHA256 else {
            throw FinalizationServiceError.preconditionFailed
        }
        do {
            _ = try SnapshotValidatorV1(
                modelContext: modelContext,
                generationRootURL: generationRootURL,
                signPack: signPack
            ).validate(report: report)
        } catch {
            throw FinalizationServiceError.preconditionFailed
        }
        return FinalizationResult(
            recordID: record.id,
            packetID: packet.id,
            stableRootID: packet.stableRootID,
            reportID: report.id,
            issueID: issueAfter.id,
            snapshotRelativePath: report.snapshotRelativePath,
            snapshotSHA256: report.snapshotSHA256
        )
    }

    private func recheckDraftBefore(_ record: WorkflowRecord) -> WorkflowRecordPayloadV1 {
        let value = recordPayload(record)
        return WorkflowRecordPayloadV1(
            id: value.id, schemaVersion: value.schemaVersion,
            assetID: value.assetID, packetID: nil,
            issueID: value.issueID, parentRecordID: value.parentRecordID,
            recordRevisionRootID: value.recordRevisionRootID,
            revisesRecordID: value.revisesRecordID,
            evidenceSourceRecordID: value.evidenceSourceRecordID,
            revisionKind: value.revisionKind, stage: value.stage,
            state: WorkflowState.draft.rawValue,
            draftStepKey: WorkflowDraftStep.outcome.rawValue,
            startedAt: value.startedAt, completedAt: nil,
            observedAtUTC: value.observedAtUTC, timeZoneID: value.timeZoneID,
            utcOffsetMinutes: value.utcOffsetMinutes,
            localDate: value.localDate, localTime: value.localTime,
            afterDarkAcknowledgementKey: value.afterDarkAcknowledgementKey,
            afterDarkAcknowledgementCopy: value.afterDarkAcknowledgementCopy,
            afterDarkAcknowledgementVersion: value.afterDarkAcknowledgementVersion,
            afterDarkAcknowledgementAccepted: value.afterDarkAcknowledgementAccepted,
            safePositionAcknowledgementKey: value.safePositionAcknowledgementKey,
            safePositionAcknowledgementCopy: value.safePositionAcknowledgementCopy,
            safePositionAcknowledgementVersion: value.safePositionAcknowledgementVersion,
            safePositionAcknowledgementAccepted: value.safePositionAcknowledgementAccepted,
            packID: value.packID, packSchemaVersion: value.packSchemaVersion,
            packContentVersion: value.packContentVersion,
            pdfTemplateID: value.pdfTemplateID,
            pdfTemplateVersion: value.pdfTemplateVersion,
            outcomeKey: nil, couldNotVerifyKey: nil,
            couldNotVerifyDisplaySnapshot: nil,
            couldNotVerifyRegistryVersion: nil,
            workPerformedLocalDate: nil, workDescription: nil,
            note: nil, finalizationMutationID: nil
        )
    }

    private func replayIssueMatches(
        _ issue: Issue?,
        input: FinalizationServiceInput
    ) -> Bool {
        guard let label = input.issueLabel else { return issue == nil }
        guard let issue else { return false }
        return issue.assetID == input.asset.id
            && issue.openedByRecordID == input.draft.id
            && issue.labelKey == label.key
            && issue.labelDisplaySnapshot == label.display
            && issue.status == IssueStatus.open.rawValue
            && issue.resolvedByRecordID == nil
            && issue.createdAt == input.completedAt
            && issue.updatedAt == input.completedAt
    }

    private func readFinalSnapshot(_ relativePath: String) throws -> Data {
        try anchoredSnapshotData(relativePath)
    }

    private func anchoredSnapshotData(_ relativePath: String) throws -> Data {
        guard relativePath.hasPrefix("snapshots/"),
              relativePath.split(separator: "/").count == 2 else {
            throw FinalizationServiceError.preconditionFailed
        }
        do {
            return try ReportPDFAnchoredFile.readRegularFile(
                at: generationRootURL.appendingPathComponent(relativePath),
                within: generationRootURL,
                rootIdentity: rootIdentity
            )
        } catch {
            throw FinalizationServiceError.preconditionFailed
        }
    }

    private func requireFrozenRootIdentity() throws {
        do {
            guard try ReportPDFAnchoredFile.rootIdentity(at: generationRootURL)
                    == rootIdentity else {
                throw FinalizationServiceError.preconditionFailed
            }
        } catch {
            throw FinalizationServiceError.preconditionFailed
        }
    }

    private struct FrozenCorrection {
        let encodedSnapshot: EncodedReportSnapshotV1
        let intent: FinalizationIntentV1
        let plan: ReportCorrectionRulePlan
    }

    private func freezeCorrection(
        _ input: ReportCorrectionFinalizationInput,
        packetCurrentRecordID: UUID? = nil
    ) throws -> FrozenCorrection {
        let packetValue = PacketPayloadV1(
            id: input.packet.id,
            schemaVersion: input.packet.schemaVersion,
            stableRootID: input.packet.stableRootID,
            currentRecordID: packetCurrentRecordID ?? input.packet.currentRecordID,
            evaluationCounted: input.packet.evaluationCounted,
            contentDeletedAt: input.packet.contentDeletedAt,
            createdAt: input.packet.createdAt
        )
        let plan: ReportCorrectionRulePlan
        do {
            plan = try ReportCorrectionRule().makePlan(
                source: ReportCorrectionRuleSource(
                    currentRecord: recordPayload(input.currentRecord),
                    packet: packetValue,
                    currentReport: reportPayload(input.currentReport),
                    currentSnapshot: input.currentSnapshot
                ),
                request: ReportCorrectionRuleRequest(
                    note: input.note,
                    snapshotCreatedAt: input.snapshotCreatedAt,
                    sourceApp: input.sourceApp,
                    identifiers: input.identifiers
                )
            )
        } catch let error as ReportCorrectionRuleError {
            switch error {
            case .invalidAuthority:
                throw FinalizationServiceError.preconditionFailed
            case .invalidNote:
                throw FinalizationServiceError.invalidSelection
            }
        }
        let encodedSnapshot: EncodedReportSnapshotV1
        do {
            encodedSnapshot = try ReportSnapshotEncoderV1().encode(plan.snapshot)
        } catch {
            throw FinalizationServiceError.preconditionFailed
        }
        guard encodedSnapshot.sha256 == plan.reportInsert.snapshotSHA256,
              let completedAt = plan.recordAfter.completedAt else {
            throw FinalizationServiceError.preconditionFailed
        }
        let payload = FinalizationPayloadV1(
            issueInsert: nil,
            issueTransition: nil,
            packetAfter: plan.packetAfter,
            packetBefore: plan.packetBefore,
            reportInsert: plan.reportInsert,
            workflowRecordAfter: plan.recordAfter
        )
        let encodedPayload: EncodedFinalizationContractV1
        do {
            encodedPayload = try FinalizationContractEncoderV1().encodePayload(payload)
        } catch {
            throw FinalizationServiceError.preconditionFailed
        }
        let intent = FinalizationIntentV1(
            completedAt: completedAt,
            finalizationMutationID: input.identifiers.mutationID,
            finalizationPayload: payload,
            finalizationPayloadSHA256: encodedPayload.sha256,
            generationID: generationID,
            packetID: plan.packetAfter.id,
            phase: .prepared,
            recordID: plan.recordAfter.id,
            reportID: plan.reportInsert.id,
            schemaVersion: 1,
            snapshotCreatedAt: plan.reportInsert.createdAt,
            snapshotFinalRelativePath: plan.reportInsert.snapshotRelativePath,
            snapshotSHA256: encodedSnapshot.sha256,
            snapshotStagingRelativePath: ".staging/\(plan.reportInsert.snapshotRelativePath)",
            stableRootID: plan.packetAfter.stableRootID
        )
        return FrozenCorrection(
            encodedSnapshot: encodedSnapshot,
            intent: intent,
            plan: plan
        )
    }

    private func replayedCorrection(
        _ input: ReportCorrectionFinalizationInput
    ) throws -> ReportCorrectionFinalizationOutcome? {
        let records = try modelContext.fetch(FetchDescriptor<WorkflowRecord>()).filter {
            $0.finalizationMutationID == input.identifiers.mutationID
        }
        guard records.count <= 1 else {
            throw FinalizationServiceError.preconditionFailed
        }
        guard let record = records.first else { return nil }
        let frozen = try freezeCorrection(
            input,
            packetCurrentRecordID: input.currentRecord.id
        )
        let reports = try modelContext.fetch(FetchDescriptor<Report>()).filter {
            $0.id == input.identifiers.reportID
                || $0.sourceRecordID == record.id
        }
        let packets = try modelContext.fetch(FetchDescriptor<Packet>()).filter {
            $0.id == frozen.plan.packetAfter.id
                || $0.stableRootID == frozen.plan.packetAfter.stableRootID
        }
        guard recordPayload(record) == frozen.plan.recordAfter,
              reports.count == 1,
              immutableReportPayload(reports[0], matches: frozen.plan.reportInsert),
              validDeliveredState(reports[0]),
              packets.count == 1,
              packetPayload(packets[0]) == frozen.plan.packetAfter,
                try anchoredSnapshotData(frozen.plan.reportInsert.snapshotRelativePath)
                == frozen.encodedSnapshot.data else {
            throw FinalizationServiceError.preconditionFailed
        }
        return ReportCorrectionFinalizationOutcome(
            recordID: record.id,
            packetID: packets[0].id,
            stableRootID: packets[0].stableRootID,
            reportID: reports[0].id,
            priorReportID: input.currentReport.id,
            snapshotRelativePath: reports[0].snapshotRelativePath,
            snapshotSHA256: reports[0].snapshotSHA256,
            createdAuthority: false
        )
    }

    private func immutableReportPayload(
        _ value: Report,
        matches expected: ReportPayloadV1
    ) -> Bool {
        value.id == expected.id
            && value.schemaVersion == expected.schemaVersion
            && value.packetID == expected.packetID
            && value.sourceRecordID == expected.sourceRecordID
            && value.snapshotSchemaVersion == expected.snapshotSchemaVersion
            && value.snapshotRelativePath == expected.snapshotRelativePath
            && value.snapshotSHA256 == expected.snapshotSHA256
            && value.createdAt == expected.createdAt
            && value.replacesReportID == expected.replacesReportID
    }

    private func validDeliveredState(_ value: Report) -> Bool {
        let path = "pdfs/\(value.id.uuidString.lowercased()).pdf"
        switch ReportPDFState(rawValue: value.pdfState) {
        case .pending, .failed:
            return value.pdfRelativePath == nil && value.pdfSHA256 == nil
        case .ready:
            return value.pdfRelativePath == path
                && value.pdfSHA256.map(isLowercaseSHA256) == true
        case nil:
            return false
        }
    }

    private func validateCorrectionDatabasePreconditions(
        _ input: ReportCorrectionFinalizationInput,
        plan: ReportCorrectionRulePlan
    ) throws {
        let records = try modelContext.fetch(FetchDescriptor<WorkflowRecord>())
        let packets = try modelContext.fetch(FetchDescriptor<Packet>())
        let reports = try modelContext.fetch(FetchDescriptor<Report>())
        let evidence = try modelContext.fetch(FetchDescriptor<EvidenceFile>())
        let issues = try modelContext.fetch(FetchDescriptor<Issue>())
        guard records.filter({ $0.id == input.currentRecord.id }).count == 1,
              Set(records.map(\.id)).count == records.count,
              records.filter({ $0.id == plan.recordAfter.id }).isEmpty,
              records.filter({ $0.finalizationMutationID == input.identifiers.mutationID }).isEmpty,
              packets.filter({ $0.id == input.packet.id }).count == 1,
              packets.filter({ $0.stableRootID == input.packet.stableRootID }).count == 1,
              reports.filter({ $0.id == input.currentReport.id }).count == 1,
              reports.filter({ $0.id == plan.reportInsert.id }).isEmpty,
              reports.filter({ $0.sourceRecordID == plan.recordAfter.id }).isEmpty,
              reports.filter({ $0.replacesReportID == input.currentReport.id }).isEmpty,
              records.filter({ $0.revisesRecordID == input.currentRecord.id }).isEmpty,
              evidence.filter({ $0.recordID == plan.recordAfter.id }).isEmpty,
              issues.filter({
                $0.openedByRecordID == plan.recordAfter.id
                    || $0.resolvedByRecordID == plan.recordAfter.id
              }).isEmpty,
              packetPayload(input.packet) == plan.packetBefore,
              try validCompleteCorrectionChain(
                currentRecord: input.currentRecord,
                currentReport: input.currentReport,
                packet: input.packet,
                records: records,
                reports: reports
              ) else {
            throw FinalizationServiceError.preconditionFailed
        }
    }

    private func validCompleteCorrectionChain(
        currentRecord: WorkflowRecord,
        currentReport: Report,
        packet: Packet,
        records: [WorkflowRecord],
        reports: [Report]
    ) throws -> Bool {
        let packetReports = reports.filter { $0.packetID == packet.id }
        guard packet.currentRecordID == currentRecord.id,
              currentReport.sourceRecordID == currentRecord.id,
              Set(records.map(\.id)).count == records.count,
              Set(reports.map(\.id)).count == reports.count,
              Set(reports.map(\.sourceRecordID)).count == reports.count,
              packetReports.filter({ $0.sourceRecordID == currentRecord.id }).count == 1,
              reports.filter({ $0.replacesReportID == currentReport.id }).isEmpty,
              records.filter({ $0.revisesRecordID == currentRecord.id }).isEmpty,
              Set(packetReports.map(\.id)).count == packetReports.count,
              Set(packetReports.map(\.sourceRecordID)).count == packetReports.count else {
            return false
        }
        var reportIDs = Set<UUID>()
        var recordIDs = Set<UUID>()
        var report: Report? = currentReport
        var record: WorkflowRecord? = currentRecord
        while let reportValue = report, let recordValue = record {
            guard reportIDs.insert(reportValue.id).inserted,
                  recordIDs.insert(recordValue.id).inserted,
                  reportValue.sourceRecordID == recordValue.id,
                  recordValue.packetID == packet.id else { return false }
            switch WorkflowRevisionKind(rawValue: recordValue.revisionKind) {
            case .original:
                guard recordValue.revisesRecordID == nil,
                      recordValue.evidenceSourceRecordID == nil,
                      recordValue.recordRevisionRootID == recordValue.id,
                      reportValue.replacesReportID == nil else { return false }
                report = nil
                record = nil
            case .clericalCorrection:
                guard let priorReportID = reportValue.replacesReportID,
                      let priorRecordID = recordValue.revisesRecordID,
                      recordValue.evidenceSourceRecordID != nil else { return false }
                let priorReports = packetReports.filter { $0.id == priorReportID }
                let priorRecords = records.filter { $0.id == priorRecordID }
                guard priorReports.count == 1, priorRecords.count == 1,
                      records.filter({ $0.revisesRecordID == priorRecordID }).count == 1,
                      reports.filter({ $0.replacesReportID == priorReportID }).count == 1,
                      priorReports[0].sourceRecordID == priorRecords[0].id,
                      recordValue.recordRevisionRootID == priorRecords[0].recordRevisionRootID,
                      recordValue.evidenceSourceRecordID
                        == (priorRecords[0].evidenceSourceRecordID ?? priorRecords[0].id) else {
                    return false
                }
                report = priorReports[0]
                record = priorRecords[0]
            case nil:
                return false
            }
        }
        return reportIDs.count == packetReports.count
            && Set(records.filter { $0.packetID == packet.id }.map(\.id)) == recordIDs
    }

    private func applyCorrection(
        _ plan: ReportCorrectionRulePlan,
        packet: Packet
    ) throws {
        guard let revisionKind = WorkflowRevisionKind(rawValue: plan.recordAfter.revisionKind),
              let stage = WorkflowStage(rawValue: plan.recordAfter.stage),
              let state = WorkflowState(rawValue: plan.recordAfter.state),
              let reportState = ReportPDFState(rawValue: plan.reportInsert.pdfState),
              revisionKind == .clericalCorrection,
              plan.recordAfter.revisesRecordID == plan.packetBefore.currentRecordID,
              plan.recordAfter.evidenceSourceRecordID
                == plan.recordAfter.recordRevisionRootID else {
            throw FinalizationServiceError.preconditionFailed
        }
        let value = plan.recordAfter
        modelContext.insert(WorkflowRecord(
            id: value.id,
            assetID: value.assetID,
            packetID: value.packetID,
            issueID: value.issueID,
            parentRecordID: value.parentRecordID,
            recordRevisionRootID: value.recordRevisionRootID,
            revisesRecordID: value.revisesRecordID,
            evidenceSourceRecordID: value.evidenceSourceRecordID,
            revisionKind: revisionKind,
            stage: stage,
            state: state,
            draftStepKey: value.draftStepKey.flatMap(WorkflowDraftStep.init(rawValue:)),
            startedAt: value.startedAt,
            completedAt: value.completedAt,
            observedAtUTC: value.observedAtUTC,
            timeZoneID: value.timeZoneID,
            utcOffsetMinutes: value.utcOffsetMinutes,
            localDate: value.localDate,
            localTime: value.localTime,
            afterDarkAcknowledgementKey: value.afterDarkAcknowledgementKey,
            afterDarkAcknowledgementCopy: value.afterDarkAcknowledgementCopy,
            afterDarkAcknowledgementVersion: value.afterDarkAcknowledgementVersion,
            afterDarkAcknowledgementAccepted: value.afterDarkAcknowledgementAccepted,
            safePositionAcknowledgementKey: value.safePositionAcknowledgementKey,
            safePositionAcknowledgementCopy: value.safePositionAcknowledgementCopy,
            safePositionAcknowledgementVersion: value.safePositionAcknowledgementVersion,
            safePositionAcknowledgementAccepted: value.safePositionAcknowledgementAccepted,
            packID: value.packID,
            packSchemaVersion: value.packSchemaVersion,
            packContentVersion: value.packContentVersion,
            pdfTemplateID: value.pdfTemplateID,
            pdfTemplateVersion: value.pdfTemplateVersion,
            outcomeKey: value.outcomeKey,
            couldNotVerifyKey: value.couldNotVerifyKey,
            couldNotVerifyDisplaySnapshot: value.couldNotVerifyDisplaySnapshot,
            couldNotVerifyRegistryVersion: value.couldNotVerifyRegistryVersion,
            workPerformedLocalDate: value.workPerformedLocalDate,
            workDescription: value.workDescription,
            note: value.note,
            finalizationMutationID: value.finalizationMutationID
        ))
        packet.currentRecordID = plan.packetAfter.currentRecordID
        let report = plan.reportInsert
        modelContext.insert(Report(
            id: report.id,
            packetID: report.packetID,
            sourceRecordID: report.sourceRecordID,
            snapshotSchemaVersion: report.snapshotSchemaVersion,
            snapshotRelativePath: report.snapshotRelativePath,
            snapshotSHA256: report.snapshotSHA256,
            pdfState: reportState,
            pdfRelativePath: report.pdfRelativePath,
            pdfSHA256: report.pdfSHA256,
            createdAt: report.createdAt,
            replacesReportID: report.replacesReportID
        ))
    }

    private func recordPayload(_ value: WorkflowRecord) -> WorkflowRecordPayloadV1 {
        WorkflowRecordPayloadV1(
            id: value.id, schemaVersion: value.schemaVersion,
            assetID: value.assetID, packetID: value.packetID,
            issueID: value.issueID, parentRecordID: value.parentRecordID,
            recordRevisionRootID: value.recordRevisionRootID,
            revisesRecordID: value.revisesRecordID,
            evidenceSourceRecordID: value.evidenceSourceRecordID,
            revisionKind: value.revisionKind, stage: value.stage,
            state: value.state, draftStepKey: value.draftStepKey,
            startedAt: value.startedAt, completedAt: value.completedAt,
            observedAtUTC: value.observedAtUTC, timeZoneID: value.timeZoneID,
            utcOffsetMinutes: value.utcOffsetMinutes,
            localDate: value.localDate, localTime: value.localTime,
            afterDarkAcknowledgementKey: value.afterDarkAcknowledgementKey,
            afterDarkAcknowledgementCopy: value.afterDarkAcknowledgementCopy,
            afterDarkAcknowledgementVersion: value.afterDarkAcknowledgementVersion,
            afterDarkAcknowledgementAccepted: value.afterDarkAcknowledgementAccepted,
            safePositionAcknowledgementKey: value.safePositionAcknowledgementKey,
            safePositionAcknowledgementCopy: value.safePositionAcknowledgementCopy,
            safePositionAcknowledgementVersion: value.safePositionAcknowledgementVersion,
            safePositionAcknowledgementAccepted: value.safePositionAcknowledgementAccepted,
            packID: value.packID, packSchemaVersion: value.packSchemaVersion,
            packContentVersion: value.packContentVersion,
            pdfTemplateID: value.pdfTemplateID,
            pdfTemplateVersion: value.pdfTemplateVersion,
            outcomeKey: value.outcomeKey,
            couldNotVerifyKey: value.couldNotVerifyKey,
            couldNotVerifyDisplaySnapshot: value.couldNotVerifyDisplaySnapshot,
            couldNotVerifyRegistryVersion: value.couldNotVerifyRegistryVersion,
            workPerformedLocalDate: value.workPerformedLocalDate,
            workDescription: value.workDescription, note: value.note,
            finalizationMutationID: value.finalizationMutationID
        )
    }

    private struct FrozenFinalization {
        let encodedSnapshot: EncodedReportSnapshotV1
        let intent: FinalizationIntentV1
        let issue: Issue?
        let recheckPlan: RecheckOutcomeRulePlan?
        let packet: Packet
        let report: Report
        let snapshotRelativePath: String
    }

    private struct DraftMutationState {
        let packetID: UUID?
        let issueID: UUID?
        let state: String
        let draftStepKey: String?
        let completedAt: Date?
        let outcomeKey: String?
        let couldNotVerifyKey: String?
        let couldNotVerifyDisplaySnapshot: String?
        let couldNotVerifyRegistryVersion: String?
        let note: String?
        let finalizationMutationID: UUID?

        init(_ draft: WorkflowRecord) {
            packetID = draft.packetID
            issueID = draft.issueID
            state = draft.state
            draftStepKey = draft.draftStepKey
            completedAt = draft.completedAt
            outcomeKey = draft.outcomeKey
            couldNotVerifyKey = draft.couldNotVerifyKey
            couldNotVerifyDisplaySnapshot = draft.couldNotVerifyDisplaySnapshot
            couldNotVerifyRegistryVersion = draft.couldNotVerifyRegistryVersion
            note = draft.note
            finalizationMutationID = draft.finalizationMutationID
        }

        func restore(_ draft: WorkflowRecord) {
            draft.packetID = packetID
            draft.issueID = issueID
            draft.state = state
            draft.draftStepKey = draftStepKey
            draft.completedAt = completedAt
            draft.outcomeKey = outcomeKey
            draft.couldNotVerifyKey = couldNotVerifyKey
            draft.couldNotVerifyDisplaySnapshot = couldNotVerifyDisplaySnapshot
            draft.couldNotVerifyRegistryVersion = couldNotVerifyRegistryVersion
            draft.note = note
            draft.finalizationMutationID = finalizationMutationID
        }
    }

    private struct IssueMutationState {
        let status: String
        let resolvedByRecordID: UUID?
        let updatedAt: Date

        init(_ issue: Issue) {
            status = issue.status
            resolvedByRecordID = issue.resolvedByRecordID
            updatedAt = issue.updatedAt
        }

        func restore(_ issue: Issue) {
            issue.status = status
            issue.resolvedByRecordID = resolvedByRecordID
            issue.updatedAt = updatedAt
        }
    }

    private struct RecheckAuthority {
        let issue: Issue
        let parent: WorkflowRecord
        let chain: [WorkflowRecord]
        let historicalEvidence: [EvidenceFile]
        let plan: RecheckOutcomeRulePlan
    }

    private func recheckAuthority(_ input: FinalizationServiceInput) throws -> RecheckAuthority {
        guard let issueID = input.draft.issueID,
              input.identifiers.issueID == issueID,
              let parentID = input.draft.parentRecordID else {
            throw FinalizationServiceError.invalidDraft
        }
        let allSites = try modelContext.fetch(FetchDescriptor<Site>())
        let allAssets = try modelContext.fetch(FetchDescriptor<Asset>())
        let allIssues = try modelContext.fetch(FetchDescriptor<Issue>())
        let issues = allIssues.filter { $0.id == issueID }
        let allRecords = try modelContext.fetch(FetchDescriptor<WorkflowRecord>())
        let allEvidence = try modelContext.fetch(FetchDescriptor<EvidenceFile>())
        let allPackets = try modelContext.fetch(FetchDescriptor<Packet>())
        let allReports = try modelContext.fetch(FetchDescriptor<Report>())
        let parents = allRecords.filter { $0.id == parentID }
        let mutationIDs = allRecords.compactMap(\.finalizationMutationID)
        let evidencePaths = allEvidence.flatMap {
            [$0.relativePath, $0.thumbnailRelativePath]
        }
        guard !modelContext.hasChanges,
              uniqueValues(allSites.map(\.id)),
              uniqueValues(allAssets.map(\.id)),
              uniqueValues(allIssues.map(\.id)),
              uniqueValues(allRecords.map(\.id)),
              uniqueValues(allEvidence.map(\.id)),
              uniqueValues(allPackets.map(\.id)),
              uniqueValues(allPackets.map(\.stableRootID)),
              uniqueValues(allPackets.compactMap(\.currentRecordID)),
              uniqueValues(allReports.map(\.id)),
              uniqueValues(mutationIDs),
              Set(evidencePaths).count == evidencePaths.count,
              allAssets.filter({ $0.id == input.asset.id }).count == 1,
              allAssets.first(where: { $0.id == input.asset.id }) === input.asset,
              allSites.filter({ $0.id == input.site.id }).count == 1,
              allSites.first(where: { $0.id == input.site.id }) === input.site,
              input.asset.siteID == input.site.id,
              input.asset.packID == signPack.packID,
              input.asset.packSchemaVersion == signPack.schemaVersion,
              input.asset.packContentVersion == signPack.contentVersion,
              issues.count == 1,
              parents.count == 1,
              allRecords.filter({ $0.id == input.draft.id }).count == 1,
              allRecords.first(where: { $0.id == input.draft.id }) === input.draft,
              allRecords.filter({
                  $0.assetID == input.asset.id
                      && $0.state == WorkflowState.draft.rawValue
              }).count == 1 else {
            throw FinalizationServiceError.preconditionFailed
        }
        let issue = issues[0]
        let parent = parents[0]
        guard issue.schemaVersion == 1,
              issue.assetID == input.asset.id,
              signPack.issueLabels.filter({
                  $0.key == issue.labelKey
                      && $0.display == issue.labelDisplaySnapshot
              }).count == 1,
              issue.status == IssueStatus.recheckDue.rawValue,
              issue.resolvedByRecordID == nil,
              issue.updatedAt >= issue.createdAt else {
            throw FinalizationServiceError.preconditionFailed
        }
        let originals = allRecords.filter {
            $0.state == WorkflowState.completed.rawValue
                && $0.revisionKind == WorkflowRevisionKind.original.rawValue
        }
        guard let opening = originals.first(where: { $0.id == issue.openedByRecordID }),
              validRecheckOpening(opening, issue: issue) else {
            throw FinalizationServiceError.preconditionFailed
        }
        var chain = [opening]
        var visited: Set<UUID> = [opening.id]
        var current = opening
        while true {
            let children = originals.filter { $0.parentRecordID == current.id }
            guard children.count <= 1 else {
                throw FinalizationServiceError.preconditionFailed
            }
            guard let child = children.first else { break }
            guard visited.insert(child.id).inserted,
                  validRecheckChild(child, issue: issue, parent: current) else {
                throw FinalizationServiceError.preconditionFailed
            }
            chain.append(child)
            current = child
        }
        let issueOriginals = originals.filter { $0.issueID == issue.id }
        let issueRecords = allRecords.filter { $0.issueID == issue.id }
        let corrections = issueRecords.filter {
            $0.revisionKind == WorkflowRevisionKind.clericalCorrection.rawValue
                && $0.state == WorkflowState.completed.rawValue
        }
        let drafts = issueRecords.filter { $0.state == WorkflowState.draft.rawValue }
        guard current === parent,
              parent.stage == WorkflowStage.work.rawValue,
              parent.outcomeKey == "work_recorded",
              parent.completedAt == issue.updatedAt,
              Set(issueOriginals.map(\.id)) == Set(chain.map(\.id)),
              drafts.count == 1,
              drafts.first === input.draft,
              issueOriginals.count + corrections.count + drafts.count
                == issueRecords.count,
              allIssues.filter({
                $0.assetID == input.draft.assetID
                    && $0.status != IssueStatus.resolved.rawValue
              }).count == 1 else {
            throw FinalizationServiceError.preconditionFailed
        }
        try validateRecheckRevisionAuthority(
            roots: chain,
            records: allRecords,
            packets: allPackets
        )
        let plan = try RecheckOutcomeRule.makePlan(RecheckOutcomeRuleInput(
            draft: recordPayload(input.draft),
            parent: recordPayload(parent),
            issue: issuePayload(issue),
            outcomeKey: input.outcomeKey,
            note: input.note,
            completedAt: input.completedAt,
            mutationID: input.identifiers.mutationID,
            packetID: input.identifiers.packetID
        ))
        let chainIDs = Set(chain.map(\.id))
        let historicalEvidence = allEvidence.filter { chainIDs.contains($0.recordID) }
        for record in chain {
            try validateRecheckEvidenceCardinality(
                historicalEvidence.filter { $0.recordID == record.id },
                record: record
            )
        }
        let draftEvidence = allEvidence.filter { $0.recordID == input.draft.id }
        guard Set(draftEvidence.map(\.id)) == Set(input.evidence.map(\.id)),
              corrections.allSatisfy({ correction in
                  allEvidence.allSatisfy { $0.recordID != correction.id }
              }) else {
            throw FinalizationServiceError.invalidEvidence
        }
        try validateEvidenceFiles(historicalEvidence)
        return RecheckAuthority(
            issue: issue,
            parent: parent,
            chain: chain,
            historicalEvidence: historicalEvidence,
            plan: plan
        )
    }

    private func recheckPlan(_ input: FinalizationServiceInput) throws -> RecheckOutcomeRulePlan {
        try recheckAuthority(input).plan
    }

    private func validRecheckOpening(_ record: WorkflowRecord, issue: Issue) -> Bool {
        record.schemaVersion == 1
            && record.assetID == issue.assetID
            && record.issueID == issue.id
            && record.parentRecordID == nil
            && record.recordRevisionRootID == record.id
            && record.revisesRecordID == nil
            && record.evidenceSourceRecordID == nil
            && record.revisionKind == WorkflowRevisionKind.original.rawValue
            && record.stage == WorkflowStage.check.rawValue
            && record.state == WorkflowState.completed.rawValue
            && record.draftStepKey == nil
            && record.packetID != nil
            && record.completedAt.map({ $0 >= record.startedAt }) == true
            && validRecheckTimeAndAcknowledgements(record)
            && record.packID == signPack.packID
            && record.packSchemaVersion == signPack.schemaVersion
            && record.packContentVersion == signPack.contentVersion
            && record.pdfTemplateID == "field.evidence.pdf.worklight.v1"
            && record.pdfTemplateVersion == 1
            && record.outcomeKey == "visible_issue"
            && record.couldNotVerifyKey == nil
            && record.couldNotVerifyDisplaySnapshot == nil
            && record.couldNotVerifyRegistryVersion == nil
            && record.workPerformedLocalDate == nil
            && record.workDescription == nil
            && (record.note.map({
                validRecheckText($0, maximum: 1_000)
            }) ?? true)
            && record.finalizationMutationID != nil
            && issue.createdAt == record.completedAt
    }

    private func validRecheckChild(
        _ record: WorkflowRecord,
        issue: Issue,
        parent: WorkflowRecord
    ) -> Bool {
        guard record.schemaVersion == 1,
              record.assetID == issue.assetID,
              record.issueID == issue.id,
              record.parentRecordID == parent.id,
              record.recordRevisionRootID == record.id,
              record.revisesRecordID == nil,
              record.evidenceSourceRecordID == nil,
              record.revisionKind == WorkflowRevisionKind.original.rawValue,
              record.state == WorkflowState.completed.rawValue,
              record.draftStepKey == nil,
              let completedAt = record.completedAt,
              completedAt >= record.startedAt,
              parent.completedAt.map({ record.startedAt >= $0 }) == true,
              record.packID == signPack.packID,
              record.packSchemaVersion == signPack.schemaVersion,
              record.packContentVersion == signPack.contentVersion,
              record.pdfTemplateID == "field.evidence.pdf.worklight.v1",
              record.pdfTemplateVersion == 1,
              record.finalizationMutationID != nil else {
            return false
        }
        if record.stage == WorkflowStage.work.rawValue {
            return record.packetID == nil
                && record.outcomeKey == "work_recorded"
                && record.observedAtUTC == nil
                && record.timeZoneID == nil
                && record.utcOffsetMinutes == nil
                && record.localDate == nil
                && record.localTime == nil
                && noRecheckAcknowledgements(record)
                && record.couldNotVerifyKey == nil
                && record.couldNotVerifyDisplaySnapshot == nil
                && record.couldNotVerifyRegistryVersion == nil
                && record.workPerformedLocalDate.map(validRecheckLocalDate) == true
                && record.workDescription.map({ validRecheckText($0, maximum: 160) }) == true
                && (record.note.map({ validRecheckText($0, maximum: 1_000) }) ?? true)
        }
        if record.stage == WorkflowStage.recheck.rawValue {
            let couldNotVerify = record.outcomeKey == "could_not_verify"
            return record.packetID != nil
                && [
                    "resolved", "issue_still_visible",
                    "original_resolved_different_issue", "could_not_verify",
                ].contains(record.outcomeKey ?? "")
                && validRecheckTimeAndAcknowledgements(record)
                && record.workPerformedLocalDate == nil
                && record.workDescription == nil
                && (record.note.map({ validRecheckText($0, maximum: 1_000) }) ?? true)
                && (couldNotVerify
                    ? validRecheckCouldNotVerify(record)
                    : record.couldNotVerifyKey == nil
                        && record.couldNotVerifyDisplaySnapshot == nil
                        && record.couldNotVerifyRegistryVersion == nil)
        }
        return false
    }

    private func validateRecheckRevisionAuthority(
        roots: [WorkflowRecord],
        records: [WorkflowRecord],
        packets: [Packet]
    ) throws {
        for root in roots {
            let revisionGroup = records.filter { $0.recordRevisionRootID == root.id }
            var visited: Set<UUID> = [root.id]
            var current = root
            while true {
                let children = records.filter { $0.revisesRecordID == current.id }
                guard children.count <= 1 else {
                    throw FinalizationServiceError.preconditionFailed
                }
                guard let child = children.first else { break }
                guard visited.insert(child.id).inserted,
                      validRecheckCorrection(child, prior: current, root: root) else {
                    throw FinalizationServiceError.preconditionFailed
                }
                current = child
            }
            guard visited.count == revisionGroup.count else {
                throw FinalizationServiceError.preconditionFailed
            }
            if let packetID = root.packetID {
                let matches = packets.filter { $0.id == packetID }
                guard matches.count == 1,
                      let packet = matches.first,
                      packet.schemaVersion == 1,
                      packet.contentDeletedAt == nil,
                      packet.evaluationCounted,
                      packet.createdAt == root.completedAt,
                      packet.currentRecordID == current.id else {
                    throw FinalizationServiceError.preconditionFailed
                }
            }
        }
    }

    private func validRecheckCorrection(
        _ correction: WorkflowRecord,
        prior: WorkflowRecord,
        root: WorkflowRecord
    ) -> Bool {
        correction.schemaVersion == 1
            && correction.id != root.id
            && correction.assetID == prior.assetID
            && correction.packetID == prior.packetID
            && correction.issueID == prior.issueID
            && correction.parentRecordID == prior.parentRecordID
            && correction.recordRevisionRootID == root.id
            && correction.revisesRecordID == prior.id
            && correction.evidenceSourceRecordID == root.id
            && correction.revisionKind == WorkflowRevisionKind.clericalCorrection.rawValue
            && correction.stage == prior.stage
            && correction.stage != WorkflowStage.work.rawValue
            && correction.state == WorkflowState.completed.rawValue
            && correction.draftStepKey == nil
            && correction.startedAt == prior.startedAt
            && correction.completedAt == prior.completedAt
            && correction.observedAtUTC == prior.observedAtUTC
            && correction.timeZoneID == prior.timeZoneID
            && correction.utcOffsetMinutes == prior.utcOffsetMinutes
            && correction.localDate == prior.localDate
            && correction.localTime == prior.localTime
            && correction.afterDarkAcknowledgementKey == prior.afterDarkAcknowledgementKey
            && correction.afterDarkAcknowledgementCopy == prior.afterDarkAcknowledgementCopy
            && correction.afterDarkAcknowledgementVersion == prior.afterDarkAcknowledgementVersion
            && correction.afterDarkAcknowledgementAccepted == prior.afterDarkAcknowledgementAccepted
            && correction.safePositionAcknowledgementKey == prior.safePositionAcknowledgementKey
            && correction.safePositionAcknowledgementCopy == prior.safePositionAcknowledgementCopy
            && correction.safePositionAcknowledgementVersion == prior.safePositionAcknowledgementVersion
            && correction.safePositionAcknowledgementAccepted == prior.safePositionAcknowledgementAccepted
            && correction.packID == prior.packID
            && correction.packSchemaVersion == prior.packSchemaVersion
            && correction.packContentVersion == prior.packContentVersion
            && correction.pdfTemplateID == prior.pdfTemplateID
            && correction.pdfTemplateVersion == prior.pdfTemplateVersion
            && correction.outcomeKey == prior.outcomeKey
            && correction.couldNotVerifyKey == prior.couldNotVerifyKey
            && correction.couldNotVerifyDisplaySnapshot == prior.couldNotVerifyDisplaySnapshot
            && correction.couldNotVerifyRegistryVersion == prior.couldNotVerifyRegistryVersion
            && correction.workPerformedLocalDate == prior.workPerformedLocalDate
            && correction.workDescription == prior.workDescription
            && correction.note != prior.note
            && (correction.note.map({ validRecheckText($0, maximum: 1_000) }) ?? true)
            && correction.finalizationMutationID != nil
    }

    private func validateRecheckEvidenceCardinality(
        _ rows: [EvidenceFile],
        record: WorkflowRecord
    ) throws {
        let keys = rows.map(\.purposeKey)
        if record.stage == WorkflowStage.work.rawValue {
            guard rows.count <= 1,
                  keys.allSatisfy({ $0 == "work_context" }) else {
                throw FinalizationServiceError.invalidEvidence
            }
            return
        }
        guard record.stage == WorkflowStage.check.rawValue
                || record.stage == WorkflowStage.recheck.rawValue else {
            throw FinalizationServiceError.invalidEvidence
        }
        let allowed = Set(["wide_context", "close_detail"])
        if record.outcomeKey == "could_not_verify" {
            guard rows.count <= 2,
                  Set(keys).count == keys.count,
                  keys.allSatisfy(allowed.contains) else {
                throw FinalizationServiceError.invalidEvidence
            }
        } else {
            guard rows.count == 2, Set(keys) == allowed else {
                throw FinalizationServiceError.invalidEvidence
            }
        }
    }

    private func validRecheckTimeAndAcknowledgements(_ record: WorkflowRecord) -> Bool {
        record.observedAtUTC == record.startedAt
            && record.timeZoneID.map({ !$0.isEmpty }) == true
            && record.utcOffsetMinutes.map({ ((-14 * 60)...(14 * 60)).contains($0) }) == true
            && record.localDate.map(validRecheckLocalDate) == true
            && record.localTime.map({
                $0.range(
                    of: #"^(?:[01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]$"#,
                    options: .regularExpression
                ) != nil
            }) == true
            && record.afterDarkAcknowledgementKey == "after_dark"
            && record.afterDarkAcknowledgementCopy.map({ !$0.isEmpty }) == true
            && record.afterDarkAcknowledgementVersion.map({ !$0.isEmpty }) == true
            && record.afterDarkAcknowledgementAccepted == true
            && record.safePositionAcknowledgementKey == "safe_authorized_position"
            && record.safePositionAcknowledgementCopy.map({ !$0.isEmpty }) == true
            && record.safePositionAcknowledgementVersion.map({ !$0.isEmpty }) == true
            && record.safePositionAcknowledgementAccepted == true
    }

    private func noRecheckAcknowledgements(_ record: WorkflowRecord) -> Bool {
        record.afterDarkAcknowledgementKey == nil
            && record.afterDarkAcknowledgementCopy == nil
            && record.afterDarkAcknowledgementVersion == nil
            && record.afterDarkAcknowledgementAccepted == nil
            && record.safePositionAcknowledgementKey == nil
            && record.safePositionAcknowledgementCopy == nil
            && record.safePositionAcknowledgementVersion == nil
            && record.safePositionAcknowledgementAccepted == nil
    }

    private func validRecheckCouldNotVerify(_ record: WorkflowRecord) -> Bool {
        guard record.couldNotVerifyRegistryVersion == "cnv.reason.en-US.v1",
              let key = record.couldNotVerifyKey,
              let display = record.couldNotVerifyDisplaySnapshot else {
            return false
        }
        return signPack.couldNotVerifyReasons.entries.filter {
            $0.key == key && $0.display == display
        }.count == 1
    }

    private func validRecheckText(_ value: String, maximum: Int) -> Bool {
        !value.isEmpty
            && value.count <= maximum
            && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func validRecheckLocalDate(_ value: String) -> Bool {
        guard value.range(
            of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"#,
            options: .regularExpression
        ) != nil else {
            return false
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: value) else { return false }
        return formatter.string(from: date) == value
    }

    private func uniqueValues<T: Hashable>(_ values: [T]) -> Bool {
        Set(values).count == values.count
    }

    private func validateFrozenRecheckInput(_ input: FinalizationServiceInput) throws {
        guard input.draft.revisionKind == WorkflowRevisionKind.original.rawValue,
              input.draft.stage == WorkflowStage.recheck.rawValue,
              input.draft.state == WorkflowState.draft.rawValue,
              input.draft.draftStepKey == WorkflowDraftStep.outcome.rawValue,
              input.draft.packetID == nil,
              input.draft.issueID != nil,
              input.draft.parentRecordID != nil,
              input.draft.recordRevisionRootID == input.draft.id,
              input.draft.revisesRecordID == nil,
              input.draft.evidenceSourceRecordID == nil,
              input.draft.completedAt == nil,
              input.draft.outcomeKey == nil,
              input.draft.finalizationMutationID == nil,
              input.draft.packID == signPack.packID,
              input.draft.packSchemaVersion == signPack.schemaVersion,
              input.draft.packContentVersion == signPack.contentVersion,
              input.asset.id == input.draft.assetID,
              input.asset.siteID == input.site.id,
              input.completedAt >= input.draft.startedAt,
              input.snapshotCreatedAt >= input.completedAt,
              input.issueLabel == nil,
              input.couldNotVerify == nil,
              input.outcomeKey == "resolved" || input.outcomeKey == "issue_still_visible",
              uniqueDisplay(signPack.outcomeDisplays, key: input.outcomeKey) == input.outcomeDisplay else {
            throw FinalizationServiceError.invalidDraft
        }
        let keys = input.evidence.sorted(by: evidenceOrder).map(\.purposeKey)
        guard keys == ["wide_context", "close_detail"],
              input.evidence.allSatisfy({
                $0.recordID == input.draft.id
                    && $0.mimeType == MediaContractV1.durableMIMEType
                    && $0.createdAt >= input.draft.startedAt
                    && $0.createdAt <= input.completedAt
              }),
              purposeDisplay("wide_context") != nil,
              purposeDisplay("close_detail") != nil else {
            throw FinalizationServiceError.invalidEvidence
        }
        _ = try recheckAuthority(input)
    }

    private func freezeRecheck(_ input: FinalizationServiceInput) throws -> FrozenFinalization {
        let authority = try recheckAuthority(input)
        let packet = Packet(
            id: input.identifiers.packetID,
            stableRootID: input.identifiers.stableRootID,
            currentRecordID: input.draft.id,
            evaluationCounted: true,
            contentDeletedAt: nil,
            createdAt: input.completedAt
        )
        let snapshotRelativePath = "snapshots/\(input.identifiers.reportID.uuidString.lowercased()).json"
        let encodedSnapshot = try ReportSnapshotEncoderV1().encode(
            makeRecheckSnapshot(input, authority: authority)
        )
        let report = Report(
            id: input.identifiers.reportID,
            packetID: packet.id,
            sourceRecordID: input.draft.id,
            snapshotSchemaVersion: 1,
            snapshotRelativePath: snapshotRelativePath,
            snapshotSHA256: encodedSnapshot.sha256,
            pdfState: .pending,
            pdfRelativePath: nil,
            pdfSHA256: nil,
            createdAt: input.snapshotCreatedAt,
            replacesReportID: nil
        )
        let payload = FinalizationPayloadV1(
            issueInsert: nil,
            issueTransition: IssueTransitionV1(
                after: authority.plan.issueAfter,
                before: authority.plan.issueBefore
            ),
            packetAfter: packetPayload(packet),
            packetBefore: nil,
            reportInsert: reportPayload(report),
            workflowRecordAfter: authority.plan.recordAfter
        )
        let encodedPayload = try FinalizationContractEncoderV1().encodePayload(payload)
        let intent = FinalizationIntentV1(
            completedAt: input.completedAt,
            finalizationMutationID: input.identifiers.mutationID,
            finalizationPayload: payload,
            finalizationPayloadSHA256: encodedPayload.sha256,
            generationID: generationID,
            packetID: packet.id,
            phase: .prepared,
            recordID: input.draft.id,
            reportID: report.id,
            schemaVersion: 1,
            snapshotCreatedAt: input.snapshotCreatedAt,
            snapshotFinalRelativePath: snapshotRelativePath,
            snapshotSHA256: encodedSnapshot.sha256,
            snapshotStagingRelativePath: ".staging/\(snapshotRelativePath)",
            stableRootID: packet.stableRootID
        )
        return FrozenFinalization(
            encodedSnapshot: encodedSnapshot,
            intent: intent,
            issue: authority.issue,
            recheckPlan: authority.plan,
            packet: packet,
            report: report,
            snapshotRelativePath: snapshotRelativePath
        )
    }

    private func freeze(_ input: FinalizationServiceInput) throws -> FrozenFinalization {
        if input.draft.stage == WorkflowStage.recheck.rawValue {
            return try freezeRecheck(input)
        }
        let issue: Issue?
        if let label = input.issueLabel,
           let issueID = input.identifiers.issueID {
            issue = Issue(
                id: issueID,
                assetID: input.asset.id,
                openedByRecordID: input.draft.id,
                labelKey: label.key,
                labelDisplaySnapshot: label.display,
                status: .open,
                resolvedByRecordID: nil,
                createdAt: input.completedAt,
                updatedAt: input.completedAt
            )
        } else {
            issue = nil
        }
        let packet = Packet(
            id: input.identifiers.packetID,
            stableRootID: input.identifiers.stableRootID,
            currentRecordID: input.draft.id,
            evaluationCounted: true,
            contentDeletedAt: nil,
            createdAt: input.completedAt
        )
        let snapshotRelativePath = "snapshots/\(input.identifiers.reportID.uuidString.lowercased()).json"
        let snapshot = try makeSnapshot(
            input,
            issue: issue
        )
        let encodedSnapshot: EncodedReportSnapshotV1
        do {
            encodedSnapshot = try ReportSnapshotEncoderV1().encode(snapshot)
        } catch {
            throw FinalizationServiceError.invalidDraft
        }
        let report = Report(
            id: input.identifiers.reportID,
            packetID: packet.id,
            sourceRecordID: input.draft.id,
            snapshotSchemaVersion: 1,
            snapshotRelativePath: snapshotRelativePath,
            snapshotSHA256: encodedSnapshot.sha256,
            pdfState: .pending,
            pdfRelativePath: nil,
            pdfSHA256: nil,
            createdAt: input.snapshotCreatedAt,
            replacesReportID: nil
        )
        let payload = try makePayload(input, issue: issue, packet: packet, report: report)
        let encodedPayload: EncodedFinalizationContractV1
        do {
            encodedPayload = try FinalizationContractEncoderV1().encodePayload(payload)
        } catch {
            throw FinalizationServiceError.invalidDraft
        }
        let intent = FinalizationIntentV1(
            completedAt: input.completedAt,
            finalizationMutationID: input.identifiers.mutationID,
            finalizationPayload: payload,
            finalizationPayloadSHA256: encodedPayload.sha256,
            generationID: generationID,
            packetID: packet.id,
            phase: .prepared,
            recordID: input.draft.id,
            reportID: report.id,
            schemaVersion: 1,
            snapshotCreatedAt: input.snapshotCreatedAt,
            snapshotFinalRelativePath: snapshotRelativePath,
            snapshotSHA256: encodedSnapshot.sha256,
            snapshotStagingRelativePath: ".staging/\(snapshotRelativePath)",
            stableRootID: packet.stableRootID
        )
        return FrozenFinalization(
            encodedSnapshot: encodedSnapshot,
            intent: intent,
            issue: issue,
            recheckPlan: nil,
            packet: packet,
            report: report,
            snapshotRelativePath: snapshotRelativePath
        )
    }

    private func validateFrozenInput(_ input: FinalizationServiceInput) throws {
        if input.draft.stage == WorkflowStage.recheck.rawValue {
            try validateFrozenRecheckInput(input)
            return
        }
        guard input.draft.revisionKind == WorkflowRevisionKind.original.rawValue,
              input.draft.stage == WorkflowStage.check.rawValue,
              input.draft.state == WorkflowState.draft.rawValue,
              (input.outcomeKey == "could_not_verify"
                ? [WorkflowDraftStep.wide.rawValue, WorkflowDraftStep.close.rawValue, WorkflowDraftStep.outcome.rawValue].contains(input.draft.draftStepKey ?? "")
                : input.draft.draftStepKey == WorkflowDraftStep.outcome.rawValue),
              input.draft.packetID == nil,
              input.draft.issueID == nil,
              input.draft.parentRecordID == nil,
              input.draft.recordRevisionRootID == input.draft.id,
              input.draft.revisesRecordID == nil,
              input.draft.evidenceSourceRecordID == nil,
              input.draft.completedAt == nil,
              input.draft.outcomeKey == nil,
              input.draft.finalizationMutationID == nil,
              input.draft.packID == signPack.packID,
              input.draft.packSchemaVersion == signPack.schemaVersion,
              input.draft.packContentVersion == signPack.contentVersion,
              input.asset.id == input.draft.assetID,
              input.asset.siteID == input.site.id,
              input.completedAt >= input.draft.startedAt,
              input.snapshotCreatedAt >= input.completedAt else {
            throw FinalizationServiceError.invalidDraft
        }
        guard input.outcomeKey == "no_visible_issue"
                || input.outcomeKey == "visible_issue"
                || input.outcomeKey == "could_not_verify",
              (input.outcomeKey == "visible_issue") == (input.issueLabel != nil),
              (input.issueLabel != nil) == (input.identifiers.issueID != nil),
              uniqueDisplay(signPack.outcomeDisplays, key: input.outcomeKey) == input.outcomeDisplay,
              validCouldNotVerifySelection(input) else {
            throw FinalizationServiceError.invalidSelection
        }
        let sorted = input.evidence.sorted(by: evidenceOrder)
        let keys = sorted.map(\.purposeKey)
        guard (input.outcomeKey == "could_not_verify"
                ? (sorted.count <= 2 && Set(keys).count == keys.count && keys.allSatisfy { $0 == "wide_context" || $0 == "close_detail" })
                : keys == ["wide_context", "close_detail"]),
              sorted.allSatisfy({
                  $0.recordID == input.draft.id
                    && $0.mimeType == MediaContractV1.durableMIMEType
                    && $0.byteCount > 0
                    && $0.thumbnailByteCount > 0
                    && isLowercaseSHA256($0.sha256)
                    && isLowercaseSHA256($0.thumbnailSHA256)
                    && isSafeRelativePath($0.relativePath)
                    && isSafeRelativePath($0.thumbnailRelativePath)
              }) else {
            throw FinalizationServiceError.invalidEvidence
        }
        guard purposeDisplay("wide_context") != nil,
              purposeDisplay("close_detail") != nil else {
            throw FinalizationServiceError.invalidEvidence
        }
    }

    private func validateDatabasePreconditions(_ input: FinalizationServiceInput) throws {
        let packets = try modelContext.fetch(FetchDescriptor<Packet>())
        let reports = try modelContext.fetch(FetchDescriptor<Report>())
        let issues = try modelContext.fetch(FetchDescriptor<Issue>())
        let records = try modelContext.fetch(FetchDescriptor<WorkflowRecord>())
        guard !packets.contains(where: {
            $0.id == input.identifiers.packetID
                || $0.stableRootID == input.identifiers.stableRootID
        }),
              !reports.contains(where: { $0.id == input.identifiers.reportID }),
              (input.draft.stage == WorkflowStage.recheck.rawValue
                ? input.identifiers.issueID.map({ id in
                    issues.filter({ $0.id == id }).count == 1
                  }) ?? false
                : input.identifiers.issueID.map({ id in
                    !issues.contains(where: { $0.id == id })
                  }) ?? true),
              records.filter({
                  $0.finalizationMutationID == input.identifiers.mutationID
              }).isEmpty else {
            throw FinalizationServiceError.preconditionFailed
        }
    }

    private func validateEvidenceFiles(_ evidence: [EvidenceFile]) throws {
        let normalizer = MediaNormalizerV1()
        let records = try modelContext.fetch(FetchDescriptor<WorkflowRecord>())
        for row in evidence {
            let canonicalID = row.id.uuidString.lowercased()
            let matches = records.filter { $0.id == row.recordID }
            guard row.schemaVersion == 1,
                  matches.count == 1,
                  let record = matches.first,
                  row.relativePath == "evidence/\(canonicalID)/original.jpg",
                  row.thumbnailRelativePath
                    == "evidence/\(canonicalID)/thumbnail.jpg",
                  row.mimeType == MediaContractV1.durableMIMEType,
                  row.byteCount > 0,
                  row.byteCount <= MediaContractV1.originalByteCountMaximum,
                  row.thumbnailByteCount > 0,
                  row.thumbnailByteCount <= MediaContractV1.thumbnailByteCountMaximum,
                  isLowercaseSHA256(row.sha256),
                  isLowercaseSHA256(row.thumbnailSHA256),
                  row.createdAt >= record.startedAt,
                  record.completedAt.map({ row.createdAt <= $0 }) ?? true else {
                throw FinalizationServiceError.invalidEvidence
            }
            let originalURL = generationRootURL.appendingPathComponent(row.relativePath)
            let thumbnailURL = generationRootURL.appendingPathComponent(
                row.thumbnailRelativePath
            )
            let original: Data
            let thumbnail: Data
            do {
                original = try ReportPDFAnchoredFile.readRegularFile(
                    at: originalURL,
                    within: generationRootURL,
                    rootIdentity: rootIdentity
                )
                thumbnail = try ReportPDFAnchoredFile.readRegularFile(
                    at: thumbnailURL,
                    within: generationRootURL,
                    rootIdentity: rootIdentity
                )
            } catch {
                throw FinalizationServiceError.invalidEvidence
            }
            guard original.count == row.byteCount,
                  thumbnail.count == row.thumbnailByteCount,
                  sha256(original) == row.sha256,
                  sha256(thumbnail) == row.thumbnailSHA256 else {
                throw FinalizationServiceError.invalidEvidence
            }
            do {
                _ = try normalizer.validateCanonicalJPEG(original, kind: .original)
                _ = try normalizer.validateCanonicalJPEG(thumbnail, kind: .thumbnail)
            } catch {
                throw FinalizationServiceError.invalidEvidence
            }
        }
    }

    private func applyDatabaseMutation(
        _ input: FinalizationServiceInput,
        frozen: FrozenFinalization
    ) {
        if let plan = frozen.recheckPlan, let issue = frozen.issue {
            apply(plan.recordAfter, to: input.draft)
            apply(plan.issueAfter, to: issue)
        } else {
            input.draft.packetID = frozen.packet.id
            input.draft.issueID = frozen.issue?.id
            input.draft.state = WorkflowState.completed.rawValue
            input.draft.draftStepKey = nil
            input.draft.completedAt = input.completedAt
            input.draft.outcomeKey = input.outcomeKey
            input.draft.couldNotVerifyKey = input.couldNotVerify?.key
            input.draft.couldNotVerifyDisplaySnapshot = input.couldNotVerify?.display
            input.draft.couldNotVerifyRegistryVersion = input.couldNotVerify.map { _ in signPack.couldNotVerifyReasons.version }
            input.draft.note = input.note
            input.draft.finalizationMutationID = input.identifiers.mutationID
            if let issue = frozen.issue { modelContext.insert(issue) }
        }
        modelContext.insert(frozen.packet)
        modelContext.insert(frozen.report)
    }

    private func makeSnapshot(
        _ input: FinalizationServiceInput,
        issue: Issue?
    ) throws -> ReportSnapshotV1 {
        if input.draft.stage == WorkflowStage.recheck.rawValue {
            return try makeRecheckSnapshot(input)
        }
        guard let observedAtUTC = input.draft.observedAtUTC,
              let timeZoneID = input.draft.timeZoneID,
              let utcOffsetMinutes = input.draft.utcOffsetMinutes,
              let localDate = input.draft.localDate,
              let localTime = input.draft.localTime,
              let afterKey = input.draft.afterDarkAcknowledgementKey,
              let afterCopy = input.draft.afterDarkAcknowledgementCopy,
              let afterVersion = input.draft.afterDarkAcknowledgementVersion,
              input.draft.afterDarkAcknowledgementAccepted == true,
              let safeKey = input.draft.safePositionAcknowledgementKey,
              let safeCopy = input.draft.safePositionAcknowledgementCopy,
              let safeVersion = input.draft.safePositionAcknowledgementVersion,
              input.draft.safePositionAcknowledgementAccepted == true,
              let stageDisplay = uniqueDisplay(signPack.stageDisplays, key: "check") else {
            throw FinalizationServiceError.invalidDraft
        }
        let evidence = try input.evidence.sorted(by: evidenceOrder).map { row in
            guard let display = purposeDisplay(row.purposeKey) else {
                throw FinalizationServiceError.invalidEvidence
            }
            return EvidenceSnapshotV1(
                byteCount: row.byteCount,
                createdAt: row.createdAt,
                evidenceID: row.id,
                mimeType: row.mimeType,
                purposeDisplay: display,
                purposeKey: row.purposeKey,
                recordID: row.recordID,
                relativePath: row.relativePath,
                sha256: row.sha256,
                thumbnailByteCount: row.thumbnailByteCount,
                thumbnailRelativePath: row.thumbnailRelativePath,
                thumbnailSHA256: row.thumbnailSHA256
            )
        }
        let issues = issue.map {
            [IssueSnapshotV1(
                createdAt: $0.createdAt,
                display: $0.labelDisplaySnapshot,
                issueID: $0.id,
                key: $0.labelKey,
                openedByRecordID: $0.openedByRecordID,
                resolvedByRecordID: nil,
                status: IssueStatus.open.rawValue,
                updatedAt: $0.updatedAt
            )]
        } ?? []
        return ReportSnapshotV1(
            acknowledgements: [
                AcknowledgementSnapshotV1(accepted: true, copy: afterCopy, key: afterKey, version: afterVersion),
                AcknowledgementSnapshotV1(accepted: true, copy: safeCopy, key: safeKey, version: safeVersion),
            ],
            asset: AssetSnapshotV1(label: input.asset.label),
            couldNotVerify: input.couldNotVerify.map {
                CouldNotVerifySnapshotV1(display: $0.display, key: $0.key, registryVersion: signPack.couldNotVerifyReasons.version)
            },
            disclaimer: signPack.disclaimer,
            display: DisplaySnapshotV1(
                assetSingular: signPack.nouns.asset.singular,
                checkSingular: signPack.nouns.check.singular,
                issueSingular: signPack.nouns.issue.singular,
                outcome: input.outcomeDisplay,
                stage: stageDisplay
            ),
            evidence: evidence,
            evidenceSourceRecordID: input.draft.id,
            history: [],
            issues: issues,
            note: input.note,
            outcome: input.outcomeKey,
            pack: PackSnapshotV1(contentVersion: signPack.contentVersion, id: signPack.packID, schemaVersion: signPack.schemaVersion),
            packetID: input.identifiers.packetID,
            pdfTemplate: PDFTemplateReferenceV1(id: input.draft.pdfTemplateID, version: input.draft.pdfTemplateVersion),
            reportID: input.identifiers.reportID,
            site: SiteSnapshotV1(address: input.site.address, label: input.site.label),
            snapshotCreatedAt: input.snapshotCreatedAt,
            snapshotSchemaVersion: 1,
            sourceApp: input.sourceApp,
            sourceRecordID: input.draft.id,
            stableRootID: input.identifiers.stableRootID,
            stage: WorkflowStage.check.rawValue,
            timeContext: TimeContextSnapshotV1(localDate: localDate, localTime: localTime, observedAtUTC: observedAtUTC, timeZoneID: timeZoneID, utcOffsetMinutes: utcOffsetMinutes)
        )
    }

    private func makeRecheckSnapshot(
        _ input: FinalizationServiceInput,
        authority suppliedAuthority: RecheckAuthority? = nil
    ) throws -> ReportSnapshotV1 {
        let authority: RecheckAuthority
        if let suppliedAuthority {
            authority = suppliedAuthority
        } else {
            authority = try recheckAuthority(input)
        }
        guard let observedAtUTC = input.draft.observedAtUTC,
              let timeZoneID = input.draft.timeZoneID,
              let utcOffsetMinutes = input.draft.utcOffsetMinutes,
              let localDate = input.draft.localDate,
              let localTime = input.draft.localTime,
              let afterKey = input.draft.afterDarkAcknowledgementKey,
              let afterCopy = input.draft.afterDarkAcknowledgementCopy,
              let afterVersion = input.draft.afterDarkAcknowledgementVersion,
              input.draft.afterDarkAcknowledgementAccepted == true,
              let safeKey = input.draft.safePositionAcknowledgementKey,
              let safeCopy = input.draft.safePositionAcknowledgementCopy,
              let safeVersion = input.draft.safePositionAcknowledgementVersion,
              input.draft.safePositionAcknowledgementAccepted == true,
              let stageDisplay = uniqueDisplay(signPack.stageDisplays, key: "recheck") else {
            throw FinalizationServiceError.invalidDraft
        }
        let allEvidence = input.evidence + authority.historicalEvidence
        var evidenceRowsByID: [UUID: EvidenceFile] = [:]
        for row in allEvidence {
            guard evidenceRowsByID.updateValue(row, forKey: row.id) == nil else {
                throw FinalizationServiceError.invalidEvidence
            }
        }
        let currentEvidence = input.evidence.sorted(by: evidenceOrder)
        let historyRecords = authority.chain.sorted {
            let left = $0.completedAt ?? .distantPast
            let right = $1.completedAt ?? .distantPast
            return left < right
                || (left == right
                    && $0.id.uuidString.lowercased()
                        < $1.id.uuidString.lowercased())
        }
        var orderedEvidence = currentEvidence
        var seenEvidenceIDs = Set(currentEvidence.map(\.id))
        for record in historyRecords {
            let rows = authority.historicalEvidence
                .filter { $0.recordID == record.id }
                .sorted(by: evidenceOrder)
            for row in rows where seenEvidenceIDs.insert(row.id).inserted {
                orderedEvidence.append(row)
            }
        }
        let evidenceSnapshots = try orderedEvidence.map(evidenceSnapshot)
        let history = try historyRecords.map { record in
            guard let completedAt = record.completedAt,
                  completedAt < input.completedAt,
                  let outcomeKey = record.outcomeKey,
                  let historyStageDisplay = historyStageDisplay(record.stage),
                  let historyOutcomeDisplay = historyOutcomeDisplay(outcomeKey) else {
                throw FinalizationServiceError.invalidDraft
            }
            let evidenceIDs = authority.historicalEvidence
                .filter { $0.recordID == record.id }
                .sorted(by: evidenceOrder)
                .map(\.id)
            let issueIDs = Set(
                record.issueID.map { [$0] } ?? []
                    + ([authority.issue].compactMap {
                        $0.openedByRecordID == record.id ? $0.id : nil
                    })
            ).sorted {
                $0.uuidString.lowercased() < $1.uuidString.lowercased()
            }
            return HistoryEntrySnapshotV1(
                completedAt: completedAt,
                couldNotVerify: record.outcomeKey == "could_not_verify"
                    ? record.couldNotVerifyKey.flatMap { key in
                        guard let display = record.couldNotVerifyDisplaySnapshot,
                              let version = record.couldNotVerifyRegistryVersion else {
                            return nil
                        }
                        return CouldNotVerifySnapshotV1(
                            display: display,
                            key: key,
                            registryVersion: version
                        )
                    }
                    : nil,
                evidenceIDs: evidenceIDs,
                issueIDs: issueIDs,
                note: record.note,
                outcome: outcomeKey,
                outcomeDisplay: historyOutcomeDisplay,
                recordID: record.id,
                stage: record.stage,
                stageDisplay: historyStageDisplay,
                workDescription: record.workDescription,
                workPerformedLocalDate: record.workPerformedLocalDate
            )
        }
        let issue = authority.plan.issueAfter
        return ReportSnapshotV1(
            acknowledgements: [
                AcknowledgementSnapshotV1(
                    accepted: true,
                    copy: afterCopy,
                    key: afterKey,
                    version: afterVersion
                ),
                AcknowledgementSnapshotV1(
                    accepted: true,
                    copy: safeCopy,
                    key: safeKey,
                    version: safeVersion
                ),
            ],
            asset: AssetSnapshotV1(label: input.asset.label),
            couldNotVerify: nil,
            disclaimer: signPack.disclaimer,
            display: DisplaySnapshotV1(
                assetSingular: signPack.nouns.asset.singular,
                checkSingular: signPack.nouns.check.singular,
                issueSingular: signPack.nouns.issue.singular,
                outcome: input.outcomeDisplay,
                stage: stageDisplay
            ),
            evidence: evidenceSnapshots,
            evidenceSourceRecordID: input.draft.id,
            history: history,
            issues: [IssueSnapshotV1(
                createdAt: issue.createdAt,
                display: issue.labelDisplaySnapshot,
                issueID: issue.id,
                key: issue.labelKey,
                openedByRecordID: issue.openedByRecordID,
                resolvedByRecordID: issue.resolvedByRecordID,
                status: issue.status,
                updatedAt: issue.updatedAt
            )],
            note: input.note,
            outcome: input.outcomeKey,
            pack: PackSnapshotV1(
                contentVersion: signPack.contentVersion,
                id: signPack.packID,
                schemaVersion: signPack.schemaVersion
            ),
            packetID: input.identifiers.packetID,
            pdfTemplate: PDFTemplateReferenceV1(
                id: input.draft.pdfTemplateID,
                version: input.draft.pdfTemplateVersion
            ),
            reportID: input.identifiers.reportID,
            site: SiteSnapshotV1(address: input.site.address, label: input.site.label),
            snapshotCreatedAt: input.snapshotCreatedAt,
            snapshotSchemaVersion: 1,
            sourceApp: input.sourceApp,
            sourceRecordID: input.draft.id,
            stableRootID: input.identifiers.stableRootID,
            stage: WorkflowStage.recheck.rawValue,
            timeContext: TimeContextSnapshotV1(
                localDate: localDate,
                localTime: localTime,
                observedAtUTC: observedAtUTC,
                timeZoneID: timeZoneID,
                utcOffsetMinutes: utcOffsetMinutes
            )
        )
    }

    private func evidenceSnapshot(_ row: EvidenceFile) throws -> EvidenceSnapshotV1 {
        guard let display = purposeDisplay(row.purposeKey) else {
            throw FinalizationServiceError.invalidEvidence
        }
        return EvidenceSnapshotV1(
            byteCount: row.byteCount,
            createdAt: row.createdAt,
            evidenceID: row.id,
            mimeType: row.mimeType,
            purposeDisplay: display,
            purposeKey: row.purposeKey,
            recordID: row.recordID,
            relativePath: row.relativePath,
            sha256: row.sha256,
            thumbnailByteCount: row.thumbnailByteCount,
            thumbnailRelativePath: row.thumbnailRelativePath,
            thumbnailSHA256: row.thumbnailSHA256
        )
    }

    private func makePayload(
        _ input: FinalizationServiceInput,
        issue: Issue?,
        packet: Packet,
        report: Report
    ) throws -> FinalizationPayloadV1 {
        if input.draft.stage == WorkflowStage.recheck.rawValue,
           let plan = try? recheckPlan(input) {
            return FinalizationPayloadV1(
                issueInsert: nil,
                issueTransition: IssueTransitionV1(
                    after: plan.issueAfter,
                    before: plan.issueBefore
                ),
                packetAfter: packetPayload(packet),
                packetBefore: nil,
                reportInsert: reportPayload(report),
                workflowRecordAfter: plan.recordAfter
            )
        } else if input.draft.stage == WorkflowStage.recheck.rawValue {
            throw FinalizationServiceError.preconditionFailed
        }
        return FinalizationPayloadV1(
            issueInsert: issue.map(issuePayload),
            issueTransition: nil,
            packetAfter: packetPayload(packet),
            packetBefore: nil,
            reportInsert: reportPayload(report),
            workflowRecordAfter: completedRecordPayload(input, packet: packet, issue: issue)
        )
    }

    private func completedRecordPayload(_ input: FinalizationServiceInput, packet: Packet, issue: Issue?) -> WorkflowRecordPayloadV1 {
        let d = input.draft
        return WorkflowRecordPayloadV1(id: d.id, schemaVersion: d.schemaVersion, assetID: d.assetID, packetID: packet.id, issueID: issue?.id, parentRecordID: d.parentRecordID, recordRevisionRootID: d.recordRevisionRootID, revisesRecordID: d.revisesRecordID, evidenceSourceRecordID: d.evidenceSourceRecordID, revisionKind: d.revisionKind, stage: d.stage, state: WorkflowState.completed.rawValue, draftStepKey: nil, startedAt: d.startedAt, completedAt: input.completedAt, observedAtUTC: d.observedAtUTC, timeZoneID: d.timeZoneID, utcOffsetMinutes: d.utcOffsetMinutes, localDate: d.localDate, localTime: d.localTime, afterDarkAcknowledgementKey: d.afterDarkAcknowledgementKey, afterDarkAcknowledgementCopy: d.afterDarkAcknowledgementCopy, afterDarkAcknowledgementVersion: d.afterDarkAcknowledgementVersion, afterDarkAcknowledgementAccepted: d.afterDarkAcknowledgementAccepted, safePositionAcknowledgementKey: d.safePositionAcknowledgementKey, safePositionAcknowledgementCopy: d.safePositionAcknowledgementCopy, safePositionAcknowledgementVersion: d.safePositionAcknowledgementVersion, safePositionAcknowledgementAccepted: d.safePositionAcknowledgementAccepted, packID: d.packID, packSchemaVersion: d.packSchemaVersion, packContentVersion: d.packContentVersion, pdfTemplateID: d.pdfTemplateID, pdfTemplateVersion: d.pdfTemplateVersion, outcomeKey: input.outcomeKey, couldNotVerifyKey: input.couldNotVerify?.key, couldNotVerifyDisplaySnapshot: input.couldNotVerify?.display, couldNotVerifyRegistryVersion: input.couldNotVerify.map { _ in signPack.couldNotVerifyReasons.version }, workPerformedLocalDate: nil, workDescription: nil, note: input.note, finalizationMutationID: input.identifiers.mutationID)
    }

    private func apply(_ value: WorkflowRecordPayloadV1, to record: WorkflowRecord) {
        record.packetID = value.packetID
        record.issueID = value.issueID
        record.state = value.state
        record.draftStepKey = value.draftStepKey
        record.completedAt = value.completedAt
        record.outcomeKey = value.outcomeKey
        record.couldNotVerifyKey = value.couldNotVerifyKey
        record.couldNotVerifyDisplaySnapshot = value.couldNotVerifyDisplaySnapshot
        record.couldNotVerifyRegistryVersion = value.couldNotVerifyRegistryVersion
        record.note = value.note
        record.finalizationMutationID = value.finalizationMutationID
    }

    private func apply(_ value: IssuePayloadV1, to issue: Issue) {
        issue.status = value.status
        issue.resolvedByRecordID = value.resolvedByRecordID
        issue.updatedAt = value.updatedAt
    }

    private func validCouldNotVerifySelection(_ input: FinalizationServiceInput) -> Bool {
        let expected = SignPack.illuminatedSignV1.couldNotVerifyReasons
        if input.outcomeKey == "could_not_verify" {
            guard signPack.couldNotVerifyReasons == expected,
                  input.issueLabel == nil,
                  input.identifiers.issueID == nil,
                  input.outcomeDisplay == "Could not verify",
                  let selected = input.couldNotVerify,
                  expected.entries.filter({ $0.key == selected.key && $0.display == selected.display }).count == 1 else { return false }
            return input.note.map {
                $0 == $0.trimmingCharacters(in: .whitespacesAndNewlines) && (1...1000).contains($0.count)
            } ?? true
        }
        return input.couldNotVerify == nil && input.note == nil
    }

    private func issuePayload(_ issue: Issue) -> IssuePayloadV1 {
        IssuePayloadV1(id: issue.id, schemaVersion: issue.schemaVersion, assetID: issue.assetID, openedByRecordID: issue.openedByRecordID, labelKey: issue.labelKey, labelDisplaySnapshot: issue.labelDisplaySnapshot, status: issue.status, resolvedByRecordID: issue.resolvedByRecordID, createdAt: issue.createdAt, updatedAt: issue.updatedAt)
    }

    private func packetPayload(_ packet: Packet) -> PacketPayloadV1 {
        PacketPayloadV1(id: packet.id, schemaVersion: packet.schemaVersion, stableRootID: packet.stableRootID, currentRecordID: packet.currentRecordID, evaluationCounted: packet.evaluationCounted, contentDeletedAt: packet.contentDeletedAt, createdAt: packet.createdAt)
    }

    private func reportPayload(_ report: Report) -> ReportPayloadV1 {
        ReportPayloadV1(id: report.id, schemaVersion: report.schemaVersion, packetID: report.packetID, sourceRecordID: report.sourceRecordID, snapshotSchemaVersion: report.snapshotSchemaVersion, snapshotRelativePath: report.snapshotRelativePath, snapshotSHA256: report.snapshotSHA256, pdfState: report.pdfState, pdfRelativePath: report.pdfRelativePath, pdfSHA256: report.pdfSHA256, createdAt: report.createdAt, replacesReportID: report.replacesReportID)
    }

    private func evidenceOrder(_ lhs: EvidenceFile, _ rhs: EvidenceFile) -> Bool {
        let order = ["wide_context": 0, "close_detail": 1, "work_context": 2]
        let left = order[lhs.purposeKey] ?? 99
        let right = order[rhs.purposeKey] ?? 99
        return left == right
            ? lhs.id.uuidString.lowercased() < rhs.id.uuidString.lowercased()
            : left < right
    }

    private func purposeDisplay(_ key: String) -> String? {
        let matches = signPack.evidencePurposes.filter { $0.key == key }
        return matches.count == 1 ? matches[0].display : nil
    }

    private func historyStageDisplay(_ value: String) -> String? {
        if value == WorkflowStage.work.rawValue { return "Work" }
        return uniqueDisplay(signPack.stageDisplays, key: value)
    }

    private func historyOutcomeDisplay(_ value: String) -> String? {
        if value == "work_recorded" { return "Work recorded" }
        return uniqueDisplay(signPack.outcomeDisplays, key: value)
    }

    private func uniqueDisplay(_ entries: [SignPack.RegistryEntry], key: String) -> String? {
        let matches = entries.filter { $0.key == key }
        return matches.count == 1 ? matches[0].display : nil
    }

    private func isLowercaseSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (0x30...0x39).contains($0) || (0x61...0x66).contains($0)
        }
    }

    private func isSafeRelativePath(_ value: String) -> Bool {
        !value.isEmpty
            && !value.hasPrefix("/")
            && !value.contains("\\")
            && !value.split(separator: "/").contains("..")
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

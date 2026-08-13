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
            let currentPayload = makePayload(
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

    private func freeze(_ input: FinalizationServiceInput) throws -> FrozenFinalization {
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
        let payload = makePayload(input, issue: issue, packet: packet, report: report)
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
            packet: packet,
            report: report,
            snapshotRelativePath: snapshotRelativePath
        )
    }

    private func validateFrozenInput(_ input: FinalizationServiceInput) throws {
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
              input.identifiers.issueID.map({ id in
                  !issues.contains(where: { $0.id == id })
              }) ?? true,
              records.filter({
                  $0.finalizationMutationID == input.identifiers.mutationID
              }).isEmpty else {
            throw FinalizationServiceError.preconditionFailed
        }
    }

    private func validateEvidenceFiles(_ evidence: [EvidenceFile]) throws {
        let normalizer = MediaNormalizerV1()
        for row in evidence {
            let originalURL = try evidenceURL(
                for: row,
                relativePath: row.relativePath,
                fileName: "original.jpg"
            )
            let thumbnailURL = try evidenceURL(
                for: row,
                relativePath: row.thumbnailRelativePath,
                fileName: "thumbnail.jpg"
            )
            let original: Data
            let thumbnail: Data
            do {
                original = try Data(contentsOf: originalURL, options: .mappedIfSafe)
                thumbnail = try Data(contentsOf: thumbnailURL, options: .mappedIfSafe)
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

    private func evidenceURL(
        for row: EvidenceFile,
        relativePath: String,
        fileName: String
    ) throws -> URL {
        let canonicalID = row.id.uuidString.lowercased()
        let expectedRelativePath = "evidence/\(canonicalID)/\(fileName)"
        guard relativePath == expectedRelativePath else {
            throw FinalizationServiceError.invalidEvidence
        }
        let evidenceRootURL = generationRootURL.appendingPathComponent(
            "evidence",
            isDirectory: true
        )
        let evidenceDirectoryURL = evidenceRootURL.appendingPathComponent(
            canonicalID,
            isDirectory: true
        )
        let url = evidenceDirectoryURL.appendingPathComponent(fileName)
        guard try fileType(at: generationRootURL) == .typeDirectory,
              try fileType(at: evidenceRootURL) == .typeDirectory,
              try fileType(at: evidenceDirectoryURL) == .typeDirectory,
              try fileType(at: url) == .typeRegular else {
            throw FinalizationServiceError.invalidEvidence
        }
        return url
    }

    private func fileType(at url: URL) throws -> FileAttributeType {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard let type = attributes[.type] as? FileAttributeType else {
                throw FinalizationServiceError.invalidEvidence
            }
            return type
        } catch let error as FinalizationServiceError {
            throw error
        } catch {
            throw FinalizationServiceError.invalidEvidence
        }
    }

    private func applyDatabaseMutation(
        _ input: FinalizationServiceInput,
        frozen: FrozenFinalization
    ) {
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
        modelContext.insert(frozen.packet)
        modelContext.insert(frozen.report)
    }

    private func makeSnapshot(
        _ input: FinalizationServiceInput,
        issue: Issue?
    ) throws -> ReportSnapshotV1 {
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

    private func makePayload(
        _ input: FinalizationServiceInput,
        issue: Issue?,
        packet: Packet,
        report: Report
    ) -> FinalizationPayloadV1 {
        FinalizationPayloadV1(
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

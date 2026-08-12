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
}

struct FinalizationServiceInput {
    let draft: WorkflowRecord
    let asset: Asset
    let site: Site
    let evidence: [EvidenceFile]
    let outcomeKey: String
    let outcomeDisplay: String
    let issueLabel: SignPack.RegistryEntry?
    let completedAt: Date
    let snapshotCreatedAt: Date
    let sourceApp: SourceAppSnapshotV1
    let identifiers: FinalizationIdentifiers
}

struct FinalizationServiceOutcome: Equatable, Sendable {
    let result: FinalizationResult
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

@MainActor
final class FinalizationService {
    private let modelContext: ModelContext
    private let signPack: SignPack
    private let generationRootURL: URL
    private let generationID: UUID
    private let intentStore: FinalizationIntentStore
    private let failureInjection: FinalizationServiceFailureInjection?

    init(
        modelContext: ModelContext,
        signPack: SignPack,
        generationRootURL: URL,
        intentStoreFailureInjection: FinalizationIntentStoreFailureInjection? = nil,
        failureInjection: FinalizationServiceFailureInjection? = nil
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
        self.intentStore = FinalizationIntentStore(
            generationRootURL: root,
            failureInjection: intentStoreFailureInjection
        )
        self.failureInjection = failureInjection
    }

    func finalize(_ input: FinalizationServiceInput) async throws -> FinalizationServiceOutcome {
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
        do {
            prepared = try await intentStore.prepare(
                intent: frozen.intent,
                snapshot: frozen.encodedSnapshot
            )
            promoted = try await intentStore.promoteSnapshot(prepared)
            snapshotPromoted = try await intentStore.advance(
                promoted,
                to: .snapshotPromoted
            )
        } catch {
            throw FinalizationServiceError.journalFailed
        }

        do {
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
            applyDatabaseMutation(input, frozen: frozen)
            if failureInjection?.consume(.modelSave) == true {
                throw FinalizationServiceError.saveFailed
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            do {
                try await intentStore.rollbackUncommitted(snapshotPromoted)
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
            committed = try await intentStore.advance(
                snapshotPromoted,
                to: .databaseCommitted
            )
            try await intentStore.cleanupCommitted(committed)
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
              record.packID == signPack.packID,
              record.packSchemaVersion == signPack.schemaVersion,
              record.packContentVersion == signPack.contentVersion,
              record.pdfTemplateID == "field.evidence.pdf.worklight.v1",
              record.pdfTemplateVersion == 1,
              record.packetID == packet.id,
              record.issueID == issue?.id,
              sortedEvidence.count == 2,
              sortedEvidence[0].purposeKey == "wide_context",
              sortedEvidence[1].purposeKey == "close_detail",
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
              try readFinalSnapshot(report.snapshotRelativePath) == expectedSnapshot.data else {
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
        guard relativePath.hasPrefix("snapshots/"),
              relativePath.split(separator: "/").count == 2 else {
            throw FinalizationServiceError.preconditionFailed
        }
        let snapshotsURL = generationRootURL.appendingPathComponent(
            "snapshots",
            isDirectory: true
        )
        let snapshotURL = generationRootURL.appendingPathComponent(relativePath)
        guard try fileType(at: generationRootURL) == .typeDirectory,
              try fileType(at: snapshotsURL) == .typeDirectory,
              try fileType(at: snapshotURL) == .typeRegular else {
            throw FinalizationServiceError.preconditionFailed
        }
        do {
            return try Data(contentsOf: snapshotURL, options: .mappedIfSafe)
        } catch {
            throw FinalizationServiceError.preconditionFailed
        }
    }

    private struct FrozenFinalization {
        let encodedSnapshot: EncodedReportSnapshotV1
        let intent: FinalizationIntentV1
        let issue: Issue?
        let packet: Packet
        let report: Report
        let snapshotRelativePath: String
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
              input.draft.draftStepKey == WorkflowDraftStep.outcome.rawValue,
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
                || input.outcomeKey == "visible_issue",
              (input.outcomeKey == "visible_issue") == (input.issueLabel != nil),
              (input.issueLabel != nil) == (input.identifiers.issueID != nil) else {
            throw FinalizationServiceError.invalidSelection
        }
        let sorted = input.evidence.sorted(by: evidenceOrder)
        guard sorted.count == 2,
              sorted[0].purposeKey == "wide_context",
              sorted[1].purposeKey == "close_detail",
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
        let evidence = input.evidence.sorted(by: evidenceOrder).map { row in
            EvidenceSnapshotV1(
                byteCount: row.byteCount,
                createdAt: row.createdAt,
                evidenceID: row.id,
                mimeType: row.mimeType,
                purposeDisplay: purposeDisplay(row.purposeKey)!,
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
            couldNotVerify: nil,
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
            note: nil,
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
        return WorkflowRecordPayloadV1(id: d.id, schemaVersion: d.schemaVersion, assetID: d.assetID, packetID: packet.id, issueID: issue?.id, parentRecordID: d.parentRecordID, recordRevisionRootID: d.recordRevisionRootID, revisesRecordID: d.revisesRecordID, evidenceSourceRecordID: d.evidenceSourceRecordID, revisionKind: d.revisionKind, stage: d.stage, state: WorkflowState.completed.rawValue, draftStepKey: nil, startedAt: d.startedAt, completedAt: input.completedAt, observedAtUTC: d.observedAtUTC, timeZoneID: d.timeZoneID, utcOffsetMinutes: d.utcOffsetMinutes, localDate: d.localDate, localTime: d.localTime, afterDarkAcknowledgementKey: d.afterDarkAcknowledgementKey, afterDarkAcknowledgementCopy: d.afterDarkAcknowledgementCopy, afterDarkAcknowledgementVersion: d.afterDarkAcknowledgementVersion, afterDarkAcknowledgementAccepted: d.afterDarkAcknowledgementAccepted, safePositionAcknowledgementKey: d.safePositionAcknowledgementKey, safePositionAcknowledgementCopy: d.safePositionAcknowledgementCopy, safePositionAcknowledgementVersion: d.safePositionAcknowledgementVersion, safePositionAcknowledgementAccepted: d.safePositionAcknowledgementAccepted, packID: d.packID, packSchemaVersion: d.packSchemaVersion, packContentVersion: d.packContentVersion, pdfTemplateID: d.pdfTemplateID, pdfTemplateVersion: d.pdfTemplateVersion, outcomeKey: input.outcomeKey, couldNotVerifyKey: nil, couldNotVerifyDisplaySnapshot: nil, couldNotVerifyRegistryVersion: nil, workPerformedLocalDate: nil, workDescription: nil, note: nil, finalizationMutationID: input.identifiers.mutationID)
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

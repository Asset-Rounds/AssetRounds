import Foundation
import SwiftData

struct FinalizationRecoverySummary: Equatable, Sendable {
    let recoveredDraftRecordIDs: [UUID]
    let completedRecordIDs: [UUID]
}

enum FinalizationRecoveryServiceError: Error, Equatable {
    case inconsistent
}

@MainActor
final class FinalizationRecoveryService {
    private let modelContext: ModelContext
    private let store: FinalizationIntentStore

    init(modelContext: ModelContext, generationRootURL: URL) {
        self.modelContext = modelContext
        self.store = FinalizationIntentStore(generationRootURL: generationRootURL)
    }

    func reconcile() async throws -> FinalizationRecoverySummary {
        let recoveries: [RecoverableFinalization]
        do {
            recoveries = try await store.discoverRecoverableFinalizations()
        } catch {
            throw FinalizationRecoveryServiceError.inconsistent
        }
        try validateRecoverySet(recoveries)
        var draftIDs: [UUID] = []
        var completedIDs: [UUID] = []
        for recovery in recoveries {
            do {
                let result = try await reconcile(recovery)
                switch result {
                case .draft(let id): draftIDs.append(id)
                case .completed(let id): completedIDs.append(id)
                }
            } catch {
                throw FinalizationRecoveryServiceError.inconsistent
            }
        }
        return FinalizationRecoverySummary(
            recoveredDraftRecordIDs: draftIDs,
            completedRecordIDs: completedIDs
        )
    }

    private enum Result {
        case draft(UUID)
        case completed(UUID)
    }

    private enum DatabaseState: Equatable {
        case absent
        case matching
        case preconditionFailed
        case inconsistent
    }

    private func validateRecoverySet(_ recoveries: [RecoverableFinalization]) throws {
        var mutationIDs: Set<UUID> = []
        var recordIDs: Set<UUID> = []
        var packetIDs: Set<UUID> = []
        var reportIDs: Set<UUID> = []
        var stableRootIDs: Set<UUID> = []
        var issueIDs: Set<UUID> = []
        for recovery in recoveries {
            let intent = recovery.intent
            try validateContract(intent)
            try validateLiveAuthority(intent.finalizationPayload)
            if let snapshot = recovery.snapshot {
                try validateSnapshotAuthority(snapshot, payload: intent.finalizationPayload)
            } else if recovery.hasStagingSnapshot || recovery.hasFinalSnapshot {
                throw FinalizationRecoveryServiceError.inconsistent
            }
            guard mutationIDs.insert(intent.finalizationMutationID).inserted,
                  recordIDs.insert(intent.recordID).inserted,
                  packetIDs.insert(intent.packetID).inserted,
                  reportIDs.insert(intent.reportID).inserted,
                  stableRootIDs.insert(intent.stableRootID).inserted else {
                throw FinalizationRecoveryServiceError.inconsistent
            }
            if let issueID = intent.finalizationPayload.issueInsert?.id,
               !issueIDs.insert(issueID).inserted {
                throw FinalizationRecoveryServiceError.inconsistent
            }
            let state = databaseState(for: intent)
            guard state != .inconsistent else {
                throw FinalizationRecoveryServiceError.inconsistent
            }
            switch intent.phase {
            case .prepared where !recovery.hasStagingSnapshot && !recovery.hasFinalSnapshot:
                guard state == .absent || state == .preconditionFailed else {
                    throw FinalizationRecoveryServiceError.inconsistent
                }
            case .databaseCommitted:
                guard recovery.hasFinalSnapshot, state == .matching else {
                    throw FinalizationRecoveryServiceError.inconsistent
                }
            case .snapshotPromoted:
                guard recovery.hasFinalSnapshot else {
                    throw FinalizationRecoveryServiceError.inconsistent
                }
            case .prepared:
                break
            }
        }
    }

    private func reconcile(_ initial: RecoverableFinalization) async throws -> Result {
        try validateContract(initial.intent)
        if let snapshot = initial.snapshot {
            try validateSnapshotAuthority(snapshot, payload: initial.intent.finalizationPayload)
        } else if initial.hasStagingSnapshot || initial.hasFinalSnapshot {
            throw FinalizationRecoveryServiceError.inconsistent
        }
        var recovery = initial
        switch recovery.intent.phase {
        case .prepared:
            switch (recovery.hasStagingSnapshot, recovery.hasFinalSnapshot) {
            case (true, false):
                recovery = try await store.promoteForRecovery(recovery)
            case (false, true):
                break
            case (true, true):
                recovery = try await store.removeIdenticalStagingForRecovery(recovery)
            case (false, false):
                let state = databaseState(for: recovery.intent)
                guard state == .absent || state == .preconditionFailed else {
                    throw FinalizationRecoveryServiceError.inconsistent
                }
                try await store.abandonPreparedWithoutSnapshots(recovery)
                return .draft(recovery.intent.recordID)
            }
            recovery = try await store.advanceForRecovery(recovery, to: .snapshotPromoted)
            return try await reconcileSnapshotPromoted(recovery)

        case .snapshotPromoted:
            return try await reconcileSnapshotPromoted(recovery)

        case .databaseCommitted:
            guard recovery.hasFinalSnapshot else {
                throw FinalizationRecoveryServiceError.inconsistent
            }
            if recovery.hasStagingSnapshot {
                recovery = try await store.removeIdenticalStagingForRecovery(recovery)
            }
            guard databaseState(for: recovery.intent) == .matching else {
                throw FinalizationRecoveryServiceError.inconsistent
            }
            try await store.cleanupCommittedForRecovery(recovery)
            return .completed(recovery.intent.recordID)
        }
    }

    private func reconcileSnapshotPromoted(
        _ initial: RecoverableFinalization
    ) async throws -> Result {
        guard initial.hasFinalSnapshot else {
            throw FinalizationRecoveryServiceError.inconsistent
        }
        var recovery = initial
        if recovery.hasStagingSnapshot {
            recovery = try await store.removeIdenticalStagingForRecovery(recovery)
        }
        switch databaseState(for: recovery.intent) {
        case .matching:
            let committed = try await store.advanceForRecovery(recovery, to: .databaseCommitted)
            try await store.cleanupCommittedForRecovery(committed)
            return .completed(recovery.intent.recordID)
        case .absent:
            try apply(recovery.intent.finalizationPayload)
            do {
                try modelContext.save()
            } catch {
                modelContext.rollback()
                throw FinalizationRecoveryServiceError.inconsistent
            }
            guard databaseState(for: recovery.intent) == .matching else {
                throw FinalizationRecoveryServiceError.inconsistent
            }
            let committed = try await store.advanceForRecovery(recovery, to: .databaseCommitted)
            try await store.cleanupCommittedForRecovery(committed)
            return .completed(recovery.intent.recordID)
        case .preconditionFailed:
            try await store.rollbackForRecovery(recovery)
            return .draft(recovery.intent.recordID)
        case .inconsistent:
            throw FinalizationRecoveryServiceError.inconsistent
        }
    }

    private func validateContract(_ intent: FinalizationIntentV1) throws {
        let payload = intent.finalizationPayload
        guard intent.schemaVersion == 1,
              payload.workflowRecordAfter.schemaVersion == 1,
              payload.packetAfter.schemaVersion == 1,
              intent.recordID == payload.workflowRecordAfter.id,
              intent.packetID == payload.packetAfter.id,
              intent.stableRootID == payload.packetAfter.stableRootID,
              payload.workflowRecordAfter.packetID == intent.packetID,
              payload.workflowRecordAfter.finalizationMutationID == intent.finalizationMutationID,
              let report = payload.reportInsert,
              report.schemaVersion == 1,
              report.id == intent.reportID,
              report.packetID == intent.packetID,
              report.sourceRecordID == intent.recordID,
              report.snapshotSchemaVersion == 1,
              report.createdAt == intent.snapshotCreatedAt,
              report.snapshotRelativePath == intent.snapshotFinalRelativePath,
              report.snapshotSHA256 == intent.snapshotSHA256,
              payload.packetBefore == nil,
              payload.issueTransition == nil,
              payload.packetAfter.evaluationCounted,
              payload.packetAfter.contentDeletedAt == nil,
              payload.packetAfter.currentRecordID == intent.recordID,
              payload.workflowRecordAfter.state == WorkflowState.completed.rawValue,
              payload.workflowRecordAfter.revisionKind == WorkflowRevisionKind.original.rawValue,
              payload.workflowRecordAfter.stage == WorkflowStage.check.rawValue,
              payload.workflowRecordAfter.parentRecordID == nil,
              payload.workflowRecordAfter.recordRevisionRootID
                == payload.workflowRecordAfter.id,
              payload.workflowRecordAfter.revisesRecordID == nil,
              payload.workflowRecordAfter.evidenceSourceRecordID == nil,
              payload.workflowRecordAfter.draftStepKey == nil,
              payload.workflowRecordAfter.completedAt == intent.completedAt,
              intent.completedAt >= payload.workflowRecordAfter.startedAt,
              intent.snapshotCreatedAt >= intent.completedAt,
              payload.workflowRecordAfter.observedAtUTC != nil,
              payload.workflowRecordAfter.timeZoneID != nil,
              payload.workflowRecordAfter.utcOffsetMinutes != nil,
              payload.workflowRecordAfter.localDate != nil,
              payload.workflowRecordAfter.localTime != nil,
              payload.workflowRecordAfter.afterDarkAcknowledgementKey == "after_dark",
              payload.workflowRecordAfter.afterDarkAcknowledgementCopy != nil,
              payload.workflowRecordAfter.afterDarkAcknowledgementVersion != nil,
              payload.workflowRecordAfter.afterDarkAcknowledgementAccepted == true,
              payload.workflowRecordAfter.safePositionAcknowledgementKey
                == "safe_authorized_position",
              payload.workflowRecordAfter.safePositionAcknowledgementCopy != nil,
              payload.workflowRecordAfter.safePositionAcknowledgementVersion != nil,
              payload.workflowRecordAfter.safePositionAcknowledgementAccepted == true,
              payload.workflowRecordAfter.pdfTemplateID
                == "field.evidence.pdf.worklight.v1",
              payload.workflowRecordAfter.pdfTemplateVersion == 1,
              payload.workflowRecordAfter.couldNotVerifyKey == nil,
              payload.workflowRecordAfter.couldNotVerifyDisplaySnapshot == nil,
              payload.workflowRecordAfter.couldNotVerifyRegistryVersion == nil,
              payload.workflowRecordAfter.workPerformedLocalDate == nil,
              payload.workflowRecordAfter.workDescription == nil,
              payload.workflowRecordAfter.note == nil,
              payload.packetAfter.createdAt == intent.completedAt,
              validOriginalOutcome(payload),
              report.pdfState == ReportPDFState.pending.rawValue,
              report.pdfRelativePath == nil,
              report.pdfSHA256 == nil,
              report.replacesReportID == nil,
              (payload.issueInsert?.schemaVersion ?? 1) == 1,
              (payload.issueInsert?.status ?? IssueStatus.open.rawValue) == IssueStatus.open.rawValue,
              payload.issueInsert?.resolvedByRecordID == nil,
              (payload.issueInsert.map {
                  $0.assetID == payload.workflowRecordAfter.assetID
                      && $0.createdAt == intent.completedAt
                      && $0.updatedAt == intent.completedAt
              } ?? true),
              IssueStatus(rawValue: payload.issueInsert?.status ?? IssueStatus.open.rawValue) != nil,
              ReportPDFState(rawValue: report.pdfState) != nil,
              (payload.issueInsert.map {
                  $0.openedByRecordID == payload.workflowRecordAfter.id
              } ?? true),
              payload.issueInsert?.id == payload.workflowRecordAfter.issueID else {
            throw FinalizationRecoveryServiceError.inconsistent
        }
    }

    private func validOriginalOutcome(_ payload: FinalizationPayloadV1) -> Bool {
        switch payload.workflowRecordAfter.outcomeKey {
        case "no_visible_issue":
            return payload.issueInsert == nil && payload.workflowRecordAfter.issueID == nil
        case "visible_issue":
            return payload.issueInsert != nil
                && payload.workflowRecordAfter.issueID == payload.issueInsert?.id
                && !(payload.issueInsert?.labelKey.isEmpty ?? true)
                && !(payload.issueInsert?.labelDisplaySnapshot.isEmpty ?? true)
        default:
            return false
        }
    }

    private func validateSnapshotAuthority(
        _ snapshot: ReportSnapshotV1,
        payload: FinalizationPayloadV1
    ) throws {
        let assetID = payload.workflowRecordAfter.assetID
        let assets = try modelContext.fetch(FetchDescriptor<Asset>()).filter {
            $0.id == assetID
        }
        guard assets.count == 1, let asset = assets.first else {
            throw FinalizationRecoveryServiceError.inconsistent
        }
        let sites = try modelContext.fetch(FetchDescriptor<Site>()).filter {
            $0.id == asset.siteID
        }
        guard sites.count == 1, let site = sites.first,
              asset.schemaVersion == 1,
              site.schemaVersion == 1,
              asset.packID == payload.workflowRecordAfter.packID,
              asset.packSchemaVersion == payload.workflowRecordAfter.packSchemaVersion,
              asset.packContentVersion == payload.workflowRecordAfter.packContentVersion,
              snapshot.asset.label == asset.label,
              snapshot.site.label == site.label,
              snapshot.site.address == site.address else {
            throw FinalizationRecoveryServiceError.inconsistent
        }
        let sourceRecordID = payload.workflowRecordAfter.evidenceSourceRecordID
            ?? payload.workflowRecordAfter.id
        let rows = try modelContext.fetch(FetchDescriptor<EvidenceFile>()).filter {
            $0.recordID == sourceRecordID
        }
        guard rows.count == 2,
              snapshot.evidence.count == 2,
              snapshot.evidence[0].purposeKey == "wide_context",
              snapshot.evidence[1].purposeKey == "close_detail" else {
            throw FinalizationRecoveryServiceError.inconsistent
        }
        let groupedRows = Dictionary(grouping: rows, by: \.id)
        guard groupedRows.count == rows.count,
              snapshot.evidence.allSatisfy({ evidence in
                  guard let matches = groupedRows[evidence.evidenceID],
                        matches.count == 1,
                        let row = matches.first else { return false }
                  let id = row.id.uuidString.lowercased()
                  return row.schemaVersion == 1
                      && evidence.recordID == sourceRecordID
                      && row.recordID == evidence.recordID
                      && row.purposeKey == evidence.purposeKey
                      && row.relativePath == "evidence/\(id)/original.jpg"
                      && row.relativePath == evidence.relativePath
                      && row.mimeType == MediaContractV1.durableMIMEType
                      && evidence.mimeType == MediaContractV1.durableMIMEType
                      && row.byteCount > 0
                      && row.byteCount <= MediaContractV1.originalByteCountMaximum
                      && row.byteCount == evidence.byteCount
                      && isLowercaseSHA256(row.sha256)
                      && row.sha256 == evidence.sha256
                      && row.createdAt == evidence.createdAt
                      && row.thumbnailRelativePath == "evidence/\(id)/thumbnail.jpg"
                      && row.thumbnailRelativePath == evidence.thumbnailRelativePath
                      && row.thumbnailByteCount > 0
                      && row.thumbnailByteCount <= MediaContractV1.thumbnailByteCountMaximum
                      && row.thumbnailByteCount == evidence.thumbnailByteCount
                      && isLowercaseSHA256(row.thumbnailSHA256)
                      && row.thumbnailSHA256 == evidence.thumbnailSHA256
              }) else {
            throw FinalizationRecoveryServiceError.inconsistent
        }
        if let issue = payload.issueInsert {
            guard snapshot.issues.count == 1,
                  let value = snapshot.issues.first,
                  value.issueID == issue.id,
                  value.openedByRecordID == issue.openedByRecordID,
                  value.key == issue.labelKey,
                  value.display == issue.labelDisplaySnapshot,
                  value.status == issue.status,
                  value.resolvedByRecordID == issue.resolvedByRecordID,
                  value.createdAt == issue.createdAt,
                  value.updatedAt == issue.updatedAt else {
                throw FinalizationRecoveryServiceError.inconsistent
            }
        } else if !snapshot.issues.isEmpty {
            throw FinalizationRecoveryServiceError.inconsistent
        }
        guard snapshot.history.isEmpty,
              snapshot.couldNotVerify == nil,
              snapshot.note == payload.workflowRecordAfter.note,
              snapshot.timeContext.observedAtUTC == payload.workflowRecordAfter.observedAtUTC,
              snapshot.timeContext.timeZoneID == payload.workflowRecordAfter.timeZoneID,
              snapshot.timeContext.utcOffsetMinutes == payload.workflowRecordAfter.utcOffsetMinutes,
              snapshot.timeContext.localDate == payload.workflowRecordAfter.localDate,
              snapshot.timeContext.localTime == payload.workflowRecordAfter.localTime,
              snapshot.acknowledgements.count == 2,
              snapshot.acknowledgements[0].key
                == payload.workflowRecordAfter.afterDarkAcknowledgementKey,
              snapshot.acknowledgements[0].copy
                == payload.workflowRecordAfter.afterDarkAcknowledgementCopy,
              snapshot.acknowledgements[0].version
                == payload.workflowRecordAfter.afterDarkAcknowledgementVersion,
              snapshot.acknowledgements[0].accepted
                == payload.workflowRecordAfter.afterDarkAcknowledgementAccepted,
              snapshot.acknowledgements[1].key
                == payload.workflowRecordAfter.safePositionAcknowledgementKey,
              snapshot.acknowledgements[1].copy
                == payload.workflowRecordAfter.safePositionAcknowledgementCopy,
              snapshot.acknowledgements[1].version
                == payload.workflowRecordAfter.safePositionAcknowledgementVersion,
              snapshot.acknowledgements[1].accepted
                == payload.workflowRecordAfter.safePositionAcknowledgementAccepted else {
            throw FinalizationRecoveryServiceError.inconsistent
        }
    }

    private func validateLiveAuthority(_ payload: FinalizationPayloadV1) throws {
        let assetID = payload.workflowRecordAfter.assetID
        let assets = try modelContext.fetch(FetchDescriptor<Asset>()).filter {
            $0.id == assetID
        }
        guard assets.count == 1, let asset = assets.first else {
            throw FinalizationRecoveryServiceError.inconsistent
        }
        let sites = try modelContext.fetch(FetchDescriptor<Site>()).filter {
            $0.id == asset.siteID
        }
        let sourceRecordID = payload.workflowRecordAfter.evidenceSourceRecordID
            ?? payload.workflowRecordAfter.id
        let evidence = try modelContext.fetch(FetchDescriptor<EvidenceFile>()).filter {
            $0.recordID == sourceRecordID
        }
        guard sites.count == 1,
              asset.schemaVersion == 1,
              sites.first?.schemaVersion == 1,
              asset.packID == payload.workflowRecordAfter.packID,
              asset.packSchemaVersion == payload.workflowRecordAfter.packSchemaVersion,
              asset.packContentVersion == payload.workflowRecordAfter.packContentVersion,
              evidence.count == 2,
              evidence.filter({ $0.purposeKey == "wide_context" }).count == 1,
              evidence.filter({ $0.purposeKey == "close_detail" }).count == 1,
              evidence.allSatisfy(validEvidenceAuthority) else {
            throw FinalizationRecoveryServiceError.inconsistent
        }
    }

    private func validEvidenceAuthority(_ row: EvidenceFile) -> Bool {
        let id = row.id.uuidString.lowercased()
        return row.schemaVersion == 1
            && row.relativePath == "evidence/\(id)/original.jpg"
            && row.thumbnailRelativePath == "evidence/\(id)/thumbnail.jpg"
            && row.mimeType == MediaContractV1.durableMIMEType
            && row.byteCount > 0
            && row.byteCount <= MediaContractV1.originalByteCountMaximum
            && isLowercaseSHA256(row.sha256)
            && row.thumbnailByteCount > 0
            && row.thumbnailByteCount <= MediaContractV1.thumbnailByteCountMaximum
            && isLowercaseSHA256(row.thumbnailSHA256)
    }

    private func isLowercaseSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (0x30...0x39).contains($0) || (0x61...0x66).contains($0)
        }
    }

    private func databaseState(for intent: FinalizationIntentV1) -> DatabaseState {
        do {
            let mutationID = intent.finalizationMutationID
            let mutationRecords = try modelContext.fetch(FetchDescriptor<WorkflowRecord>(
                predicate: #Predicate { $0.finalizationMutationID == mutationID }
            ))
            guard mutationRecords.count <= 1 else { return .inconsistent }

            let payload = intent.finalizationPayload
            guard let reportPayload = payload.reportInsert else {
                return .inconsistent
            }
            let records = try fetch(WorkflowRecord.self, id: intent.recordID)
            let packets = try modelContext.fetch(FetchDescriptor<Packet>()).filter {
                $0.id == intent.packetID
                    || $0.stableRootID == intent.stableRootID
                    || $0.currentRecordID == intent.recordID
            }
            let reports = try modelContext.fetch(FetchDescriptor<Report>()).filter {
                $0.id == intent.reportID
                    || $0.packetID == intent.packetID
                    || $0.sourceRecordID == intent.recordID
            }
            let issues = try payload.issueInsert.map { try fetch(Issue.self, id: $0.id) } ?? []
            let issueCollisions = try modelContext.fetch(FetchDescriptor<Issue>()).filter {
                $0.openedByRecordID == intent.recordID
            }
            guard records.count <= 1, packets.count <= 1, reports.count <= 1,
                  issues.count <= 1, issueCollisions.count <= 1 else {
                return .inconsistent
            }

            if let mutationRecord = mutationRecords.first {
                guard records.count == 1, records.first === mutationRecord,
                      packets.count == 1, reports.count == 1,
                      issueCollisions.count == issues.count,
                      issueCollisions.first === issues.first,
                      record(records[0], matches: payload.workflowRecordAfter),
                      packet(packets[0], matches: payload.packetAfter),
                      report(reports[0], matches: reportPayload),
                      issueRowsMatch(issues, payload: payload.issueInsert) else {
                    return .inconsistent
                }
                return .matching
            }

            guard packets.isEmpty, reports.isEmpty, issues.isEmpty,
                  issueCollisions.isEmpty else {
                return .inconsistent
            }
            guard records.count == 1 else { return .inconsistent }
            let candidate = records[0]
            guard candidate.state == WorkflowState.draft.rawValue,
                  candidate.packetID == nil,
                  candidate.issueID == nil,
                  candidate.completedAt == nil,
                  candidate.finalizationMutationID == nil else {
                return .inconsistent
            }
            return draft(candidate, matchesBefore: payload.workflowRecordAfter)
                ? .absent
                : .preconditionFailed
        } catch {
            return .inconsistent
        }
    }

    private func apply(_ payload: FinalizationPayloadV1) throws {
        let records = try fetch(WorkflowRecord.self, id: payload.workflowRecordAfter.id)
        guard records.count == 1,
              draft(records[0], matchesBefore: payload.workflowRecordAfter),
              payload.issueTransition == nil,
              payload.packetBefore == nil,
              let reportPayload = payload.reportInsert,
              let reportState = ReportPDFState(rawValue: reportPayload.pdfState) else {
            throw FinalizationRecoveryServiceError.inconsistent
        }
        apply(payload.workflowRecordAfter, to: records[0])
        if let value = payload.issueInsert {
            guard let issueStatus = IssueStatus(rawValue: value.status) else {
                throw FinalizationRecoveryServiceError.inconsistent
            }
            modelContext.insert(Issue(
                id: value.id, assetID: value.assetID,
                openedByRecordID: value.openedByRecordID,
                labelKey: value.labelKey,
                labelDisplaySnapshot: value.labelDisplaySnapshot,
                status: issueStatus,
                resolvedByRecordID: value.resolvedByRecordID,
                createdAt: value.createdAt, updatedAt: value.updatedAt
            ))
        }
        let packet = payload.packetAfter
        modelContext.insert(Packet(
            id: packet.id, stableRootID: packet.stableRootID,
            currentRecordID: packet.currentRecordID,
            evaluationCounted: packet.evaluationCounted,
            contentDeletedAt: packet.contentDeletedAt, createdAt: packet.createdAt
        ))
        modelContext.insert(Report(
            id: reportPayload.id, packetID: reportPayload.packetID,
            sourceRecordID: reportPayload.sourceRecordID,
            snapshotSchemaVersion: reportPayload.snapshotSchemaVersion,
            snapshotRelativePath: reportPayload.snapshotRelativePath,
            snapshotSHA256: reportPayload.snapshotSHA256,
            pdfState: reportState,
            pdfRelativePath: reportPayload.pdfRelativePath,
            pdfSHA256: reportPayload.pdfSHA256,
            createdAt: reportPayload.createdAt,
            replacesReportID: reportPayload.replacesReportID
        ))
    }

    private func fetch<T: PersistentModel>(_ type: T.Type, id: UUID) throws -> [T] {
        try modelContext.fetch(FetchDescriptor<T>()).filter {
            if let value = $0 as? WorkflowRecord { return value.id == id }
            if let value = $0 as? Packet { return value.id == id }
            if let value = $0 as? Report { return value.id == id }
            if let value = $0 as? Issue { return value.id == id }
            return false
        }
    }

    private func draft(_ row: WorkflowRecord, matchesBefore after: WorkflowRecordPayloadV1) -> Bool {
        record(row, matches: after, overrides: (
            packetID: nil, issueID: nil, state: WorkflowState.draft.rawValue,
            draftStepKey: WorkflowDraftStep.outcome.rawValue, completedAt: nil,
            outcomeKey: nil, finalizationMutationID: nil
        ))
    }

    private func record(_ row: WorkflowRecord, matches value: WorkflowRecordPayloadV1) -> Bool {
        record(row, matches: value, overrides: nil)
    }

    private typealias RecordOverrides = (
        packetID: UUID?, issueID: UUID?, state: String, draftStepKey: String?,
        completedAt: Date?, outcomeKey: String?, finalizationMutationID: UUID?
    )

    private func record(
        _ r: WorkflowRecord,
        matches v: WorkflowRecordPayloadV1,
        overrides: RecordOverrides?
    ) -> Bool {
        let packetID: UUID?
        let issueID: UUID?
        let state: String
        let completedAt: Date?
        let draftStepKey: String?
        let outcomeKey: String?
        let mutationID: UUID?
        if let overrides {
            packetID = overrides.packetID
            issueID = overrides.issueID
            state = overrides.state
            completedAt = overrides.completedAt
            draftStepKey = overrides.draftStepKey
            outcomeKey = overrides.outcomeKey
            mutationID = overrides.finalizationMutationID
        } else {
            packetID = v.packetID
            issueID = v.issueID
            state = v.state
            completedAt = v.completedAt
            draftStepKey = v.draftStepKey
            outcomeKey = v.outcomeKey
            mutationID = v.finalizationMutationID
        }
        return r.id == v.id && r.schemaVersion == v.schemaVersion && r.assetID == v.assetID
            && r.packetID == packetID
            && r.issueID == issueID
            && r.parentRecordID == v.parentRecordID && r.recordRevisionRootID == v.recordRevisionRootID
            && r.revisesRecordID == v.revisesRecordID && r.evidenceSourceRecordID == v.evidenceSourceRecordID
            && r.revisionKind == v.revisionKind && r.stage == v.stage
            && r.state == state
            && r.draftStepKey == draftStepKey
            && r.startedAt == v.startedAt && r.completedAt == completedAt
            && r.observedAtUTC == v.observedAtUTC && r.timeZoneID == v.timeZoneID
            && r.utcOffsetMinutes == v.utcOffsetMinutes && r.localDate == v.localDate && r.localTime == v.localTime
            && r.afterDarkAcknowledgementKey == v.afterDarkAcknowledgementKey
            && r.afterDarkAcknowledgementCopy == v.afterDarkAcknowledgementCopy
            && r.afterDarkAcknowledgementVersion == v.afterDarkAcknowledgementVersion
            && r.afterDarkAcknowledgementAccepted == v.afterDarkAcknowledgementAccepted
            && r.safePositionAcknowledgementKey == v.safePositionAcknowledgementKey
            && r.safePositionAcknowledgementCopy == v.safePositionAcknowledgementCopy
            && r.safePositionAcknowledgementVersion == v.safePositionAcknowledgementVersion
            && r.safePositionAcknowledgementAccepted == v.safePositionAcknowledgementAccepted
            && r.packID == v.packID && r.packSchemaVersion == v.packSchemaVersion
            && r.packContentVersion == v.packContentVersion && r.pdfTemplateID == v.pdfTemplateID
            && r.pdfTemplateVersion == v.pdfTemplateVersion
            && r.outcomeKey == outcomeKey
            && r.couldNotVerifyKey == v.couldNotVerifyKey
            && r.couldNotVerifyDisplaySnapshot == v.couldNotVerifyDisplaySnapshot
            && r.couldNotVerifyRegistryVersion == v.couldNotVerifyRegistryVersion
            && r.workPerformedLocalDate == v.workPerformedLocalDate
            && r.workDescription == v.workDescription && r.note == v.note
            && r.finalizationMutationID == mutationID
    }

    private func packet(_ r: Packet, matches v: PacketPayloadV1) -> Bool {
        r.id == v.id && r.schemaVersion == v.schemaVersion && r.stableRootID == v.stableRootID
            && r.currentRecordID == v.currentRecordID && r.evaluationCounted == v.evaluationCounted
            && r.contentDeletedAt == v.contentDeletedAt && r.createdAt == v.createdAt
    }

    private func report(_ r: Report, matches v: ReportPayloadV1) -> Bool {
        r.id == v.id && r.schemaVersion == v.schemaVersion && r.packetID == v.packetID
            && r.sourceRecordID == v.sourceRecordID && r.snapshotSchemaVersion == v.snapshotSchemaVersion
            && r.snapshotRelativePath == v.snapshotRelativePath && r.snapshotSHA256 == v.snapshotSHA256
            && r.pdfState == v.pdfState && r.pdfRelativePath == v.pdfRelativePath
            && r.pdfSHA256 == v.pdfSHA256 && r.createdAt == v.createdAt
            && r.replacesReportID == v.replacesReportID
    }

    private func issueRowsMatch(_ rows: [Issue], payload: IssuePayloadV1?) -> Bool {
        guard let payload else { return rows.isEmpty }
        guard rows.count == 1 else { return false }
        let r = rows[0]
        return r.id == payload.id && r.schemaVersion == payload.schemaVersion
            && r.assetID == payload.assetID && r.openedByRecordID == payload.openedByRecordID
            && r.labelKey == payload.labelKey && r.labelDisplaySnapshot == payload.labelDisplaySnapshot
            && r.status == payload.status && r.resolvedByRecordID == payload.resolvedByRecordID
            && r.createdAt == payload.createdAt && r.updatedAt == payload.updatedAt
    }

    private func apply(_ v: WorkflowRecordPayloadV1, to r: WorkflowRecord) {
        r.packetID = v.packetID; r.issueID = v.issueID; r.parentRecordID = v.parentRecordID
        r.revisesRecordID = v.revisesRecordID; r.evidenceSourceRecordID = v.evidenceSourceRecordID
        r.revisionKind = v.revisionKind; r.stage = v.stage; r.state = v.state
        r.draftStepKey = v.draftStepKey; r.startedAt = v.startedAt; r.completedAt = v.completedAt
        r.observedAtUTC = v.observedAtUTC; r.timeZoneID = v.timeZoneID; r.utcOffsetMinutes = v.utcOffsetMinutes
        r.localDate = v.localDate; r.localTime = v.localTime
        r.afterDarkAcknowledgementKey = v.afterDarkAcknowledgementKey
        r.afterDarkAcknowledgementCopy = v.afterDarkAcknowledgementCopy
        r.afterDarkAcknowledgementVersion = v.afterDarkAcknowledgementVersion
        r.afterDarkAcknowledgementAccepted = v.afterDarkAcknowledgementAccepted
        r.safePositionAcknowledgementKey = v.safePositionAcknowledgementKey
        r.safePositionAcknowledgementCopy = v.safePositionAcknowledgementCopy
        r.safePositionAcknowledgementVersion = v.safePositionAcknowledgementVersion
        r.safePositionAcknowledgementAccepted = v.safePositionAcknowledgementAccepted
        r.packID = v.packID; r.packSchemaVersion = v.packSchemaVersion; r.packContentVersion = v.packContentVersion
        r.pdfTemplateID = v.pdfTemplateID; r.pdfTemplateVersion = v.pdfTemplateVersion
        r.outcomeKey = v.outcomeKey; r.couldNotVerifyKey = v.couldNotVerifyKey
        r.couldNotVerifyDisplaySnapshot = v.couldNotVerifyDisplaySnapshot
        r.couldNotVerifyRegistryVersion = v.couldNotVerifyRegistryVersion
        r.workPerformedLocalDate = v.workPerformedLocalDate; r.workDescription = v.workDescription
        r.note = v.note; r.finalizationMutationID = v.finalizationMutationID
    }
}

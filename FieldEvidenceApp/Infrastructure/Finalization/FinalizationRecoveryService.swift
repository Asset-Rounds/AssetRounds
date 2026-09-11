import CryptoKit
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
    private let generationRootURL: URL
    private let rootIdentity: ReportPDFAnchoredFile.RootIdentity?

    init(modelContext: ModelContext, generationRootURL: URL) {
        self.modelContext = modelContext
        self.generationRootURL = generationRootURL.standardizedFileURL
        let capturedRootIdentity = try? ReportPDFAnchoredFile.rootIdentity(
            at: generationRootURL.standardizedFileURL
        )
        self.rootIdentity = capturedRootIdentity
        self.store = FinalizationIntentStore(
            generationRootURL: generationRootURL,
            expectedGenerationRootIdentity: capturedRootIdentity
        )
    }

    func reconcile() async throws -> FinalizationRecoverySummary {
        try requireCleanContext()
        let recoveries: [RecoverableFinalization]
        do {
            try requireCleanContext()
            recoveries = try await store.discoverRecoverableFinalizations()
        } catch {
            throw FinalizationRecoveryServiceError.inconsistent
        }
        try requireCleanContext()
        try validateRecoverySet(recoveries)
        var draftIDs: [UUID] = []
        var completedIDs: [UUID] = []
        for recovery in recoveries {
            do {
                let result = try await reconcile(recovery)
                switch result {
                case .draft(let id): draftIDs.append(id)
                case .completed(let id): completedIDs.append(id)
                case .abandoned: break
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
        case abandoned
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
            for issueID in [
                intent.finalizationPayload.issueTransition?.before.id,
                intent.finalizationPayload.issueInsert?.id,
            ].compactMap({ $0 }) {
                guard issueIDs.insert(issueID).inserted else {
                    throw FinalizationRecoveryServiceError.inconsistent
                }
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
        try requireCleanContext()
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
                try requireCleanContext()
                recovery = try await store.promoteForRecovery(recovery)
                try requireCleanContext()
            case (false, true):
                break
            case (true, true):
                try requireCleanContext()
                recovery = try await store.removeIdenticalStagingForRecovery(recovery)
                try requireCleanContext()
            case (false, false):
                let state = databaseState(for: recovery.intent)
                guard state == .absent || state == .preconditionFailed else {
                    throw FinalizationRecoveryServiceError.inconsistent
                }
                try requireCleanContext()
                try await store.abandonPreparedWithoutSnapshots(recovery)
                try requireCleanContext()
                return recovery.intent.finalizationPayload.packetBefore == nil
                    ? .draft(recovery.intent.recordID)
                    : .abandoned
            }
            try requireCleanContext()
            recovery = try await store.advanceForRecovery(recovery, to: .snapshotPromoted)
            try requireCleanContext()
            return try await reconcileSnapshotPromoted(recovery)

        case .snapshotPromoted:
            return try await reconcileSnapshotPromoted(recovery)

        case .databaseCommitted:
            guard recovery.hasFinalSnapshot else {
                throw FinalizationRecoveryServiceError.inconsistent
            }
            if recovery.hasStagingSnapshot {
                try requireCleanContext()
                recovery = try await store.removeIdenticalStagingForRecovery(recovery)
                try requireCleanContext()
            }
            guard databaseState(for: recovery.intent) == .matching else {
                throw FinalizationRecoveryServiceError.inconsistent
            }
            try requireCleanContext()
            try await store.cleanupCommittedForRecovery(recovery)
            try requireCleanContext()
            return .completed(recovery.intent.recordID)
        }
    }

    private func reconcileSnapshotPromoted(
        _ initial: RecoverableFinalization
    ) async throws -> Result {
        try requireCleanContext()
        guard initial.hasFinalSnapshot else {
            throw FinalizationRecoveryServiceError.inconsistent
        }
        var recovery = initial
        if recovery.hasStagingSnapshot {
            try requireCleanContext()
            recovery = try await store.removeIdenticalStagingForRecovery(recovery)
            try requireCleanContext()
        }
        switch databaseState(for: recovery.intent) {
        case .matching:
            try requireCleanContext()
            let committed = try await store.advanceForRecovery(recovery, to: .databaseCommitted)
            try requireCleanContext()
            try await store.cleanupCommittedForRecovery(committed)
            try requireCleanContext()
            return .completed(recovery.intent.recordID)
        case .absent:
            try requireCleanContext()
            let payload = recovery.intent.finalizationPayload
            let priorState: OriginalRecoveryMutationState?
            if payload.packetBefore == nil {
                priorState = try originalRecoveryMutationState(payload)
            } else {
                priorState = nil
            }
            let correctionPacketState = try correctionRecoveryPacketState(payload)
            try apply(recovery.intent.finalizationPayload)
            do {
                guard let reportValue = payload.reportInsert else {
                    throw FinalizationRecoveryServiceError.inconsistent
                }
                let reports = try fetch(Report.self, id: reportValue.id)
                guard reports.count == 1 else {
                    throw FinalizationRecoveryServiceError.inconsistent
                }
                _ = try SnapshotValidatorV1(
                    modelContext: modelContext,
                    generationRootURL: generationRootURL
                ).validate(report: reports[0])
                try modelContext.save()
            } catch {
                priorState?.restore()
                correctionPacketState?.restore()
                modelContext.rollback()
                throw FinalizationRecoveryServiceError.inconsistent
            }
            guard databaseState(for: recovery.intent) == .matching else {
                throw FinalizationRecoveryServiceError.inconsistent
            }
            try requireCleanContext()
            let committed = try await store.advanceForRecovery(recovery, to: .databaseCommitted)
            try requireCleanContext()
            try await store.cleanupCommittedForRecovery(committed)
            try requireCleanContext()
            return .completed(recovery.intent.recordID)
        case .preconditionFailed:
            try requireCleanContext()
            try await store.rollbackForRecovery(recovery)
            try requireCleanContext()
            return recovery.intent.finalizationPayload.packetBefore == nil
                ? .draft(recovery.intent.recordID)
                : .abandoned
        case .inconsistent:
            throw FinalizationRecoveryServiceError.inconsistent
        }
    }

    private func requireCleanContext() throws {
        guard !modelContext.hasChanges,
              let rootIdentity,
              (try? ReportPDFAnchoredFile.rootIdentity(at: generationRootURL))
                == rootIdentity else {
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
              payload.packetAfter.evaluationCounted,
              payload.packetAfter.contentDeletedAt == nil,
              payload.packetAfter.currentRecordID == intent.recordID,
              payload.workflowRecordAfter.state == WorkflowState.completed.rawValue,
              payload.workflowRecordAfter.draftStepKey == nil,
              payload.workflowRecordAfter.completedAt == intent.completedAt,
              intent.completedAt >= payload.workflowRecordAfter.startedAt,
              (payload.packetBefore == nil
                ? intent.snapshotCreatedAt >= intent.completedAt
                : intent.snapshotCreatedAt >= report.createdAt),
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
              payload.workflowRecordAfter.workPerformedLocalDate == nil,
              payload.workflowRecordAfter.workDescription == nil,
              validPayloadKind(payload),
              report.pdfState == ReportPDFState.pending.rawValue,
              report.pdfRelativePath == nil,
              report.pdfSHA256 == nil,
              (payload.packetBefore == nil
                ? report.replacesReportID == nil
                : report.replacesReportID != nil),
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
              (payload.packetBefore == nil
                ? ((payload.workflowRecordAfter.stage == WorkflowStage.recheck.rawValue
                    && payload.issueTransition?.before.id
                        == payload.workflowRecordAfter.issueID
                    && (payload.workflowRecordAfter.outcomeKey
                            == "original_resolved_different_issue"
                        ? payload.issueInsert != nil
                        : payload.issueInsert == nil))
                  || (payload.workflowRecordAfter.stage == WorkflowStage.check.rawValue
                    && payload.issueTransition == nil
                    && payload.issueInsert?.id
                        == payload.workflowRecordAfter.issueID))
                : payload.issueInsert == nil && payload.issueTransition == nil) else {
            throw FinalizationRecoveryServiceError.inconsistent
        }
    }

    private func validOriginalOutcome(_ payload: FinalizationPayloadV1) -> Bool {
        switch payload.workflowRecordAfter.outcomeKey {
        case "no_visible_issue":
            return payload.issueInsert == nil && payload.workflowRecordAfter.issueID == nil
                && noCouldNotVerifyFields(payload.workflowRecordAfter)
        case "visible_issue":
            return payload.issueInsert != nil
                && payload.workflowRecordAfter.issueID == payload.issueInsert?.id
                && !(payload.issueInsert?.labelKey.isEmpty ?? true)
                && !(payload.issueInsert?.labelDisplaySnapshot.isEmpty ?? true)
                && noCouldNotVerifyFields(payload.workflowRecordAfter)
        case "could_not_verify":
            let record = payload.workflowRecordAfter
            guard payload.issueInsert == nil, record.issueID == nil,
                  record.couldNotVerifyRegistryVersion == "cnv.reason.en-US.v1",
                  let key = record.couldNotVerifyKey,
                  let display = record.couldNotVerifyDisplaySnapshot,
                  couldNotVerifyEntries.contains(where: { $0.key == key && $0.display == display }) else {
                return false
            }
            return record.note.map {
                $0 == $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    && (1...1000).contains($0.count)
            } ?? true
        default:
            return false
        }
    }

    private func validPayloadKind(_ payload: FinalizationPayloadV1) -> Bool {
        let record = payload.workflowRecordAfter
        if let before = payload.packetBefore {
            guard payload.issueInsert == nil,
                  payload.issueTransition == nil,
                  record.revisionKind == WorkflowRevisionKind.clericalCorrection.rawValue,
                  record.stage == WorkflowStage.check.rawValue
                    || record.stage == WorkflowStage.recheck.rawValue,
                  record.revisesRecordID == before.currentRecordID,
                  record.recordRevisionRootID != record.id,
                  record.evidenceSourceRecordID == record.recordRevisionRootID,
                  before.id == payload.packetAfter.id,
                  before.schemaVersion == payload.packetAfter.schemaVersion,
                  before.stableRootID == payload.packetAfter.stableRootID,
                  before.evaluationCounted == payload.packetAfter.evaluationCounted,
                  before.contentDeletedAt == payload.packetAfter.contentDeletedAt,
                  before.createdAt == payload.packetAfter.createdAt,
                  payload.packetAfter.currentRecordID == record.id,
                   let completedAt = record.completedAt,
                   record.startedAt <= completedAt,
                  record.note.map({
                      $0 == $0.trimmingCharacters(in: .whitespacesAndNewlines)
                        && (1...1000).contains($0.count)
                  }) ?? true else { return false }
            return true
        }
        guard payload.packetAfter.createdAt == record.completedAt,
              record.revisionKind == WorkflowRevisionKind.original.rawValue,
              record.recordRevisionRootID == record.id,
              record.revisesRecordID == nil,
              record.evidenceSourceRecordID == nil else {
            return false
        }
        if record.stage == WorkflowStage.check.rawValue {
            return record.parentRecordID == nil
                && payload.issueTransition == nil
                && validOriginalOutcome(payload)
        }
        if record.stage == WorkflowStage.recheck.rawValue {
            return validOriginalRecheck(payload)
        }
        return false
    }

    private func validOriginalRecheck(_ payload: FinalizationPayloadV1) -> Bool {
        let record = payload.workflowRecordAfter
        let isCouldNotVerify = record.outcomeKey == "could_not_verify"
        guard let transition = payload.issueTransition,
              let issueID = record.issueID,
              record.parentRecordID != nil,
              record.outcomeKey == "resolved"
                || record.outcomeKey == "issue_still_visible"
                || record.outcomeKey == "original_resolved_different_issue"
                || isCouldNotVerify,
              record.note.map({
                  $0 == $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    && (1...1_000).contains($0.count)
              }) ?? true,
              record.workPerformedLocalDate == nil,
              record.workDescription == nil,
              transition.before.id == issueID,
              transition.after.id == issueID,
              transition.before.schemaVersion == 1,
              transition.after.schemaVersion == 1,
              transition.before.assetID == record.assetID,
              transition.after.assetID == record.assetID,
              transition.before.openedByRecordID == transition.after.openedByRecordID,
              transition.before.labelKey == transition.after.labelKey,
              transition.before.labelDisplaySnapshot
                == transition.after.labelDisplaySnapshot,
              transition.before.createdAt == transition.after.createdAt,
              transition.before.status == IssueStatus.recheckDue.rawValue,
              transition.before.resolvedByRecordID == nil else {
            return false
        }
        if isCouldNotVerify {
            guard payload.issueInsert == nil,
                  transition.after == transition.before,
                  record.couldNotVerifyRegistryVersion
                    == "cnv.reason.en-US.v1",
                  let key = record.couldNotVerifyKey,
                  let display = record.couldNotVerifyDisplaySnapshot,
                  couldNotVerifyEntries.contains(where: {
                      $0.key == key && $0.display == display
                  }) else {
                return false
            }
            return true
        }
        guard record.couldNotVerifyKey == nil,
              record.couldNotVerifyDisplaySnapshot == nil,
              record.couldNotVerifyRegistryVersion == nil,
              transition.after.updatedAt == record.completedAt else {
            return false
        }
        if record.outcomeKey == "resolved" {
            return payload.issueInsert == nil
                && transition.after.status == IssueStatus.resolved.rawValue
                && transition.after.resolvedByRecordID == record.id
        }
        if record.outcomeKey == "original_resolved_different_issue" {
            guard let inserted = payload.issueInsert,
                  inserted.schemaVersion == 1,
                  inserted.id != issueID,
                  inserted.assetID == record.assetID,
                  inserted.openedByRecordID == record.id,
                  SignPack.illuminatedSignV1.issueLabels.filter({
                      $0.key == inserted.labelKey
                        && $0.display == inserted.labelDisplaySnapshot
                  }).count == 1,
                  inserted.status == IssueStatus.open.rawValue,
                  inserted.resolvedByRecordID == nil,
                  inserted.createdAt == record.completedAt,
                  inserted.updatedAt == record.completedAt else {
                return false
            }
            return transition.after.status == IssueStatus.resolved.rawValue
                && transition.after.resolvedByRecordID == record.id
        }
        return payload.issueInsert == nil
            && transition.after.status == IssueStatus.open.rawValue
            && transition.after.resolvedByRecordID == nil
    }

    private var couldNotVerifyEntries: [SignPack.RegistryEntry] {
        SignPack.illuminatedSignV1.couldNotVerifyReasons.entries
    }

    private func noCouldNotVerifyFields(_ record: WorkflowRecordPayloadV1) -> Bool {
        record.couldNotVerifyKey == nil
            && record.couldNotVerifyDisplaySnapshot == nil
            && record.couldNotVerifyRegistryVersion == nil
            && record.note == nil
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

    private func reportPayload(_ value: Report) -> ReportPayloadV1 {
        ReportPayloadV1(
            id: value.id, schemaVersion: value.schemaVersion,
            packetID: value.packetID, sourceRecordID: value.sourceRecordID,
            snapshotSchemaVersion: value.snapshotSchemaVersion,
            snapshotRelativePath: value.snapshotRelativePath,
            snapshotSHA256: value.snapshotSHA256,
            pdfState: value.pdfState, pdfRelativePath: value.pdfRelativePath,
            pdfSHA256: value.pdfSHA256, createdAt: value.createdAt,
            replacesReportID: value.replacesReportID
        )
    }

    private func validateSnapshotAuthority(
        _ snapshot: ReportSnapshotV1,
        payload: FinalizationPayloadV1
    ) throws {
        if payload.packetBefore != nil {
            try validateCorrectionSnapshotAuthority(snapshot, payload: payload)
            return
        }
        if payload.workflowRecordAfter.stage == WorkflowStage.recheck.rawValue {
            try validateRecheckSnapshotAuthority(snapshot, payload: payload)
            return
        }
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
        let cnv = payload.workflowRecordAfter.outcomeKey == "could_not_verify"
        let rowKeys = rows.sorted { evidenceOrder($0.purposeKey) < evidenceOrder($1.purposeKey) }.map(\.purposeKey)
        guard rows.count == snapshot.evidence.count,
              (cnv
                ? rows.count <= 2 && Set(rowKeys).count == rowKeys.count
                    && rowKeys.allSatisfy { $0 == "wide_context" || $0 == "close_detail" }
                : rowKeys == ["wide_context", "close_detail"]),
              snapshot.evidence.map(\.purposeKey) == rowKeys else {
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
                      && evidence.purposeDisplay == purposeDisplay(evidence.purposeKey)
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
        let record = payload.workflowRecordAfter
        guard let outcomeKey = record.outcomeKey else {
            throw FinalizationRecoveryServiceError.inconsistent
        }
        let expectedCNV = record.couldNotVerifyKey.map { key in
            CouldNotVerifySnapshotV1(
                display: record.couldNotVerifyDisplaySnapshot ?? "",
                key: key,
                registryVersion: record.couldNotVerifyRegistryVersion ?? ""
            )
        }
        guard snapshot.history.isEmpty,
              snapshot.outcome == outcomeKey,
              snapshot.display.outcome == outcomeDisplay(outcomeKey),
              snapshot.couldNotVerify == expectedCNV,
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

    private func validateRecheckSnapshotAuthority(
        _ snapshot: ReportSnapshotV1,
        payload: FinalizationPayloadV1
    ) throws {
        let after = payload.workflowRecordAfter
        let isCouldNotVerify = after.outcomeKey == "could_not_verify"
        let expectedCouldNotVerify: CouldNotVerifySnapshotV1?
        if isCouldNotVerify {
            guard let key = after.couldNotVerifyKey,
                  let display = after.couldNotVerifyDisplaySnapshot,
                  let version = after.couldNotVerifyRegistryVersion else {
                throw FinalizationRecoveryServiceError.inconsistent
            }
            expectedCouldNotVerify = CouldNotVerifySnapshotV1(
                display: display,
                key: key,
                registryVersion: version
            )
        } else {
            expectedCouldNotVerify = nil
        }
        guard payload.packetBefore == nil,
              let transition = payload.issueTransition,
              let report = payload.reportInsert,
              let issueID = after.issueID,
              let parentID = after.parentRecordID,
              transition.before.id == issueID,
              transition.after.id == issueID,
              snapshot.stage == WorkflowStage.recheck.rawValue,
              snapshot.outcome == after.outcomeKey,
              snapshot.note == after.note,
              snapshot.reportID == report.id,
              snapshot.packetID == payload.packetAfter.id,
              snapshot.sourceRecordID == after.id,
              snapshot.evidenceSourceRecordID == after.id,
              snapshot.stableRootID == payload.packetAfter.stableRootID,
              snapshot.pdfTemplate.id == after.pdfTemplateID,
              snapshot.pdfTemplate.version == after.pdfTemplateVersion,
              canonicalDateEqual(snapshot.snapshotCreatedAt, report.createdAt),
              snapshot.pack.id == after.packID,
              snapshot.pack.schemaVersion == after.packSchemaVersion,
              snapshot.pack.contentVersion == after.packContentVersion,
              snapshot.display.stage == stageDisplay(WorkflowStage.recheck.rawValue),
              snapshot.display.outcome == outcomeDisplay(after.outcomeKey ?? ""),
              snapshot.display.assetSingular == SignPack.illuminatedSignV1.nouns.asset.singular,
              snapshot.display.checkSingular == SignPack.illuminatedSignV1.nouns.check.singular,
              snapshot.display.issueSingular == SignPack.illuminatedSignV1.nouns.issue.singular,
              snapshot.disclaimer == SignPack.illuminatedSignV1.disclaimer,
              snapshot.couldNotVerify == expectedCouldNotVerify,
              !isCouldNotVerify || expectedCouldNotVerify != nil else {
            throw FinalizationRecoveryServiceError.inconsistent
        }
        let assets = try modelContext.fetch(FetchDescriptor<Asset>()).filter {
            $0.id == after.assetID
        }
        guard assets.count == 1, let asset = assets.first else {
            throw FinalizationRecoveryServiceError.inconsistent
        }
        let sites = try modelContext.fetch(FetchDescriptor<Site>()).filter {
            $0.id == asset.siteID
        }
        let issues = try modelContext.fetch(FetchDescriptor<Issue>()).filter {
            $0.id == issueID
        }
        let insertedIssueID = payload.issueInsert?.id
        let insertedIssues = try modelContext.fetch(FetchDescriptor<Issue>()).filter { issue in
            (insertedIssueID.map { $0 == issue.id } ?? false)
                || issue.openedByRecordID == after.id
        }
        let allRecords = try modelContext.fetch(FetchDescriptor<WorkflowRecord>())
        let drafts = allRecords.filter { $0.id == after.id }
        let parents = allRecords.filter { $0.id == parentID }
        let hasAbsentDatabaseState = drafts.count == 1
            && draft(drafts[0], matchesBefore: after)
            && issues.count == 1
            && issueRowsMatch(issues, payload: transition.before)
            && insertedIssues.isEmpty
        let hasMatchingDatabaseState = drafts.count == 1
            && record(drafts[0], matches: after)
            && issues.count == 1
            && issueRowsMatch(issues, payload: transition.after)
            && issueRowsMatch(insertedIssues, payload: payload.issueInsert)
        guard sites.count == 1,
              issues.count == 1,
              insertedIssues.count <= 1,
              drafts.count == 1,
              parents.count == 1,
              asset.schemaVersion == 1,
              asset.packID == after.packID,
              asset.packSchemaVersion == after.packSchemaVersion,
              asset.packContentVersion == after.packContentVersion,
              snapshot.asset.label == asset.label,
              snapshot.site.label == sites[0].label,
              snapshot.site.address == sites[0].address,
              hasAbsentDatabaseState || hasMatchingDatabaseState else {
            throw FinalizationRecoveryServiceError.inconsistent
        }
        let issue = issues[0]
        let originals = allRecords.filter {
            $0.state == WorkflowState.completed.rawValue
                && $0.revisionKind == WorkflowRevisionKind.original.rawValue
                && $0.id != after.id
        }
        guard let opening = originals.first(where: {
            $0.id == issue.openedByRecordID
        }), validRecoveryOpening(opening, issue: issue) else {
            throw FinalizationRecoveryServiceError.inconsistent
        }
        var chain = [opening]
        var visited: Set<UUID> = [opening.id]
        var current = opening
        while true {
            let children = originals.filter { $0.parentRecordID == current.id }
            guard children.count <= 1 else {
                throw FinalizationRecoveryServiceError.inconsistent
            }
            guard let child = children.first else { break }
            guard visited.insert(child.id).inserted,
                  validRecoveryChild(child, issue: issue, parent: current) else {
                throw FinalizationRecoveryServiceError.inconsistent
            }
            chain.append(child)
            current = child
        }
        let issueOriginals = originals.filter { $0.issueID == issue.id }
        guard let issueState = reducedRecoveryIssueState(chain),
              current === parents[0],
              issueState.status == transition.before.status,
              issueState.resolvedByRecordID == transition.before.resolvedByRecordID,
              canonicalDateEqual(issueState.updatedAt, transition.before.updatedAt),
              Set(issueOriginals.map(\.id)) == Set(chain.map(\.id)) else {
            throw FinalizationRecoveryServiceError.inconsistent
        }
        let completedAt = try requiredDate(after.completedAt)
        let expectedAfterStatus = isCouldNotVerify
            ? IssueStatus.recheckDue.rawValue
            : (after.outcomeKey == "resolved"
                || after.outcomeKey == "original_resolved_different_issue"
                ? IssueStatus.resolved.rawValue
                : IssueStatus.open.rawValue)
        var expectedIssuePayloads = [transition.after]
        if let insertedIssue = payload.issueInsert {
            expectedIssuePayloads.append(insertedIssue)
        }
        expectedIssuePayloads.sort {
            $0.createdAt < $1.createdAt
                || ($0.createdAt == $1.createdAt
                    && $0.id.uuidString.lowercased()
                        < $1.id.uuidString.lowercased())
        }
        guard transition.before.status == IssueStatus.recheckDue.rawValue,
              transition.before.resolvedByRecordID == nil,
              transition.after.status == expectedAfterStatus,
              transition.after.resolvedByRecordID
                == (expectedAfterStatus == IssueStatus.resolved.rawValue
                    ? after.id : nil),
              (isCouldNotVerify
                ? transition.after == transition.before
                : canonicalDateEqual(transition.after.updatedAt, completedAt)),
              snapshot.issues.count == expectedIssuePayloads.count,
              zip(snapshot.issues, expectedIssuePayloads).allSatisfy({ value, expected in
                  issueSnapshot(value, matches: expected)
              }),
              canonicalOptionalDateEqual(
                snapshot.timeContext.observedAtUTC,
                after.observedAtUTC
              ),
              snapshot.timeContext.timeZoneID == after.timeZoneID,
              snapshot.timeContext.utcOffsetMinutes == after.utcOffsetMinutes,
              snapshot.timeContext.localDate == after.localDate,
              snapshot.timeContext.localTime == after.localTime,
              snapshot.acknowledgements.count == 2,
              snapshot.acknowledgements[0].key == after.afterDarkAcknowledgementKey,
              snapshot.acknowledgements[0].copy == after.afterDarkAcknowledgementCopy,
              snapshot.acknowledgements[0].version == after.afterDarkAcknowledgementVersion,
              snapshot.acknowledgements[0].accepted
                == after.afterDarkAcknowledgementAccepted,
              snapshot.acknowledgements[1].key == after.safePositionAcknowledgementKey,
              snapshot.acknowledgements[1].copy == after.safePositionAcknowledgementCopy,
              snapshot.acknowledgements[1].version == after.safePositionAcknowledgementVersion,
              snapshot.acknowledgements[1].accepted
                == after.safePositionAcknowledgementAccepted else {
            throw FinalizationRecoveryServiceError.inconsistent
        }

        let allEvidence = try modelContext.fetch(FetchDescriptor<EvidenceFile>())
        let currentRows = allEvidence.filter { $0.recordID == after.id }
            .sorted { evidenceOrder($0.purposeKey) < evidenceOrder($1.purposeKey) }
        guard validEvidenceCardinality(
            currentRows,
            cnv: isCouldNotVerify
        ) else {
            throw FinalizationRecoveryServiceError.inconsistent
        }
        var orderedRows = currentRows
        var seen = Set(currentRows.map(\.id))
        let historyRecords = chain.sorted {
            let left = $0.completedAt ?? .distantPast
            let right = $1.completedAt ?? .distantPast
            return left < right
                || (left == right
                    && $0.id.uuidString.lowercased()
                        < $1.id.uuidString.lowercased())
        }
        guard snapshot.history.count == historyRecords.count else {
            throw FinalizationRecoveryServiceError.inconsistent
        }
        for (history, record) in zip(snapshot.history, historyRecords) {
            let rows = allEvidence.filter { $0.recordID == record.id }
                .sorted { evidenceOrder($0.purposeKey) < evidenceOrder($1.purposeKey) }
            guard validRecoveryHistoricalEvidence(rows, record: record),
                  history.recordID == record.id,
                  canonicalOptionalDateEqual(record.completedAt, history.completedAt),
                  history.stage == record.stage,
                  history.stageDisplay == stageDisplay(record.stage),
                  history.outcome == record.outcomeKey,
                  history.outcomeDisplay == outcomeDisplay(record.outcomeKey ?? ""),
                  history.note == record.note,
                  history.workDescription == record.workDescription,
                  history.workPerformedLocalDate == record.workPerformedLocalDate,
                  history.evidenceIDs == rows.map(\.id),
                  history.issueIDs == [issue.id],
                  history.couldNotVerify == recoveryCouldNotVerify(record) else {
                throw FinalizationRecoveryServiceError.inconsistent
            }
            for row in rows where seen.insert(row.id).inserted {
                orderedRows.append(row)
            }
        }
        guard historyRecords.allSatisfy({ record in
            record.completedAt.map({ $0 < completedAt }) == true
        }),
              snapshot.evidence.map(\.evidenceID) == orderedRows.map(\.id),
              snapshot.evidence.count == orderedRows.count else {
            throw FinalizationRecoveryServiceError.inconsistent
        }
        for (value, row) in zip(snapshot.evidence, orderedRows) {
            guard evidenceSnapshot(value, matches: row) else {
                throw FinalizationRecoveryServiceError.inconsistent
            }
            try validateRecoveryEvidenceBytes(row)
        }
        if hasMatchingDatabaseState {
            let reports = try modelContext.fetch(FetchDescriptor<Report>()).filter {
                $0.id == report.id
            }
            guard reports.count == 1 else {
                throw FinalizationRecoveryServiceError.inconsistent
            }
            do {
                _ = try SnapshotValidatorV1(
                    modelContext: modelContext,
                    generationRootURL: generationRootURL
                ).validate(report: reports[0])
            } catch {
                throw FinalizationRecoveryServiceError.inconsistent
            }
        }
    }

    private func requiredDate(_ value: Date?) throws -> Date {
        guard let value else { throw FinalizationRecoveryServiceError.inconsistent }
        return value
    }

    private func issueSnapshot(
        _ value: IssueSnapshotV1,
        matches issue: IssuePayloadV1
    ) -> Bool {
        value.issueID == issue.id
            && value.openedByRecordID == issue.openedByRecordID
            && value.key == issue.labelKey
            && value.display == issue.labelDisplaySnapshot
            && value.status == issue.status
            && value.resolvedByRecordID == issue.resolvedByRecordID
            && canonicalDateEqual(value.createdAt, issue.createdAt)
            && canonicalDateEqual(value.updatedAt, issue.updatedAt)
    }

    private func evidenceSnapshot(
        _ value: EvidenceSnapshotV1,
        matches row: EvidenceFile
    ) -> Bool {
        value.evidenceID == row.id
            && value.recordID == row.recordID
            && value.purposeKey == row.purposeKey
            && value.purposeDisplay == purposeDisplay(row.purposeKey)
            && value.relativePath == row.relativePath
            && value.mimeType == row.mimeType
            && value.byteCount == row.byteCount
            && value.sha256 == row.sha256
            && canonicalDateEqual(value.createdAt, row.createdAt)
            && value.thumbnailRelativePath == row.thumbnailRelativePath
            && value.thumbnailByteCount == row.thumbnailByteCount
            && value.thumbnailSHA256 == row.thumbnailSHA256
    }

    private func validateRecoveryEvidenceBytes(_ row: EvidenceFile) throws {
        guard validEvidenceAuthority(row), let rootIdentity else {
            throw FinalizationRecoveryServiceError.inconsistent
        }
        let original: Data
        let thumbnail: Data
        do {
            original = try ReportPDFAnchoredFile.readRegularFile(
                at: generationRootURL.appendingPathComponent(row.relativePath),
                within: generationRootURL,
                rootIdentity: rootIdentity
            )
            thumbnail = try ReportPDFAnchoredFile.readRegularFile(
                at: generationRootURL.appendingPathComponent(row.thumbnailRelativePath),
                within: generationRootURL,
                rootIdentity: rootIdentity
            )
        } catch {
            throw FinalizationRecoveryServiceError.inconsistent
        }
        guard original.count == row.byteCount,
              thumbnail.count == row.thumbnailByteCount,
              sha256(original) == row.sha256,
              sha256(thumbnail) == row.thumbnailSHA256 else {
            throw FinalizationRecoveryServiceError.inconsistent
        }
        do {
            _ = try MediaNormalizerV1().validateCanonicalJPEG(original, kind: .original)
            _ = try MediaNormalizerV1().validateCanonicalJPEG(thumbnail, kind: .thumbnail)
        } catch {
            throw FinalizationRecoveryServiceError.inconsistent
        }
    }

    private func validRecoveryHistoricalEvidence(
        _ rows: [EvidenceFile],
        record: WorkflowRecord
    ) -> Bool {
        let keys = rows.map(\.purposeKey)
        if record.stage == WorkflowStage.work.rawValue {
            return rows.count <= 1 && keys.allSatisfy { $0 == "work_context" }
        }
        if record.outcomeKey == "could_not_verify" {
            return rows.count <= 2 && Set(keys).count == keys.count
                && keys.allSatisfy { $0 == "wide_context" || $0 == "close_detail" }
        }
        return rows.count == 2
            && keys.filter { $0 == "wide_context" }.count == 1
            && keys.filter { $0 == "close_detail" }.count == 1
    }

    private struct RecoveryRecheckIssueState {
        let status: String
        let resolvedByRecordID: UUID?
        let updatedAt: Date
    }

    private func reducedRecoveryIssueState(
        _ chain: [WorkflowRecord]
    ) -> RecoveryRecheckIssueState? {
        guard let opening = chain.first,
              opening.stage == WorkflowStage.check.rawValue,
              opening.outcomeKey == "visible_issue",
              let openingCompletedAt = opening.completedAt else {
            return nil
        }
        var status = IssueStatus.open.rawValue
        var resolvedByRecordID: UUID?
        var updatedAt = openingCompletedAt
        for record in chain.dropFirst() {
            guard let completedAt = record.completedAt else { return nil }
            switch WorkflowStage(rawValue: record.stage) {
            case .work:
                guard status == IssueStatus.open.rawValue else { return nil }
                status = IssueStatus.recheckDue.rawValue
                resolvedByRecordID = nil
                updatedAt = completedAt
            case .recheck:
                guard status == IssueStatus.recheckDue.rawValue else { return nil }
                switch record.outcomeKey {
                case "resolved", "original_resolved_different_issue":
                    status = IssueStatus.resolved.rawValue
                    resolvedByRecordID = record.id
                    updatedAt = completedAt
                case "issue_still_visible":
                    status = IssueStatus.open.rawValue
                    resolvedByRecordID = nil
                    updatedAt = completedAt
                case "could_not_verify":
                    break
                default:
                    return nil
                }
            case .check, nil:
                return nil
            }
        }
        return RecoveryRecheckIssueState(
            status: status,
            resolvedByRecordID: resolvedByRecordID,
            updatedAt: updatedAt
        )
    }

    private func validRecoveryOpening(_ record: WorkflowRecord, issue: Issue) -> Bool {
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
            && validRecoveryTimeAndAcknowledgements(record)
            && record.packID == SignPack.illuminatedSignV1.packID
            && record.packSchemaVersion == SignPack.illuminatedSignV1.schemaVersion
            && record.packContentVersion == SignPack.illuminatedSignV1.contentVersion
            && record.pdfTemplateID == "field.evidence.pdf.worklight.v1"
            && record.pdfTemplateVersion == 1
            && record.outcomeKey == "visible_issue"
            && record.couldNotVerifyKey == nil
            && record.couldNotVerifyDisplaySnapshot == nil
            && record.couldNotVerifyRegistryVersion == nil
            && record.workPerformedLocalDate == nil
            && record.workDescription == nil
            && (record.note.map({
                validRecoveryText($0, maximum: 1_000)
            }) ?? true)
            && record.finalizationMutationID != nil
            && canonicalOptionalDateEqual(record.completedAt, issue.createdAt)
    }

    private func validRecoveryChild(
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
              record.packID == SignPack.illuminatedSignV1.packID,
              record.packSchemaVersion == SignPack.illuminatedSignV1.schemaVersion,
              record.packContentVersion == SignPack.illuminatedSignV1.contentVersion,
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
                && noRecoveryAcknowledgements(record)
                && record.couldNotVerifyKey == nil
                && record.couldNotVerifyDisplaySnapshot == nil
                && record.couldNotVerifyRegistryVersion == nil
                && record.workPerformedLocalDate.map(validRecoveryLocalDate) == true
                && record.workDescription.map({ validRecoveryText($0, maximum: 160) }) == true
                && (record.note.map({ validRecoveryText($0, maximum: 1_000) }) ?? true)
        }
        if record.stage == WorkflowStage.recheck.rawValue {
            let couldNotVerify = record.outcomeKey == "could_not_verify"
            return record.packetID != nil
                && [
                    "resolved", "issue_still_visible",
                    "original_resolved_different_issue", "could_not_verify",
                ].contains(record.outcomeKey ?? "")
                && validRecoveryTimeAndAcknowledgements(record)
                && record.workPerformedLocalDate == nil
                && record.workDescription == nil
                && (record.note.map({ validRecoveryText($0, maximum: 1_000) }) ?? true)
                && (couldNotVerify
                    ? recoveryCouldNotVerify(record) != nil
                    : record.couldNotVerifyKey == nil
                        && record.couldNotVerifyDisplaySnapshot == nil
                        && record.couldNotVerifyRegistryVersion == nil)
        }
        return false
    }

    private func validRecoveryTimeAndAcknowledgements(_ record: WorkflowRecord) -> Bool {
        record.observedAtUTC == record.startedAt
            && record.timeZoneID.map({ !$0.isEmpty }) == true
            && record.utcOffsetMinutes.map({ ((-14 * 60)...(14 * 60)).contains($0) }) == true
            && record.localDate.map(validRecoveryLocalDate) == true
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

    private func noRecoveryAcknowledgements(_ record: WorkflowRecord) -> Bool {
        record.afterDarkAcknowledgementKey == nil
            && record.afterDarkAcknowledgementCopy == nil
            && record.afterDarkAcknowledgementVersion == nil
            && record.afterDarkAcknowledgementAccepted == nil
            && record.safePositionAcknowledgementKey == nil
            && record.safePositionAcknowledgementCopy == nil
            && record.safePositionAcknowledgementVersion == nil
            && record.safePositionAcknowledgementAccepted == nil
    }

    private func validRecoveryText(_ value: String, maximum: Int) -> Bool {
        !value.isEmpty
            && value.count <= maximum
            && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func validRecoveryLocalDate(_ value: String) -> Bool {
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

    private func recoveryCouldNotVerify(
        _ record: WorkflowRecord
    ) -> CouldNotVerifySnapshotV1? {
        guard record.outcomeKey == "could_not_verify",
              let key = record.couldNotVerifyKey,
              let display = record.couldNotVerifyDisplaySnapshot,
              let version = record.couldNotVerifyRegistryVersion else {
            return nil
        }
        return CouldNotVerifySnapshotV1(
            display: display,
            key: key,
            registryVersion: version
        )
    }

    private func validateCorrectionSnapshotAuthority(
        _ snapshot: ReportSnapshotV1,
        payload: FinalizationPayloadV1
    ) throws {
        guard let packetBefore = payload.packetBefore,
              let report = payload.reportInsert,
              let priorReportID = report.replacesReportID else {
            throw FinalizationRecoveryServiceError.inconsistent
        }
        let priorReports = try modelContext.fetch(FetchDescriptor<Report>()).filter {
            $0.id == priorReportID
        }
        let priorRecords = try modelContext.fetch(FetchDescriptor<WorkflowRecord>()).filter {
            $0.id == packetBefore.currentRecordID
        }
        let correctionEvidence = try modelContext.fetch(FetchDescriptor<EvidenceFile>()).filter {
            $0.recordID == payload.workflowRecordAfter.id
        }
        let issueMutations = try modelContext.fetch(FetchDescriptor<Issue>()).filter {
            $0.openedByRecordID == payload.workflowRecordAfter.id
                || $0.resolvedByRecordID == payload.workflowRecordAfter.id
        }
        guard priorReports.count == 1, priorRecords.count == 1,
              priorReports[0].sourceRecordID == priorRecords[0].id,
              priorReports[0].packetID == packetBefore.id,
              priorReports[0].pdfState == ReportPDFState.ready.rawValue,
              correctionEvidence.isEmpty, issueMutations.isEmpty else {
            throw FinalizationRecoveryServiceError.inconsistent
        }
        guard let rootIdentity else {
            throw FinalizationRecoveryServiceError.inconsistent
        }
        let priorBytes: Data
        do {
            priorBytes = try ReportPDFAnchoredFile.readRegularFile(
                at: generationRootURL.appendingPathComponent(
                    priorReports[0].snapshotRelativePath
                ),
                within: generationRootURL,
                rootIdentity: rootIdentity
            )
        } catch {
            throw FinalizationRecoveryServiceError.inconsistent
        }
        guard CanonicalJSONV1.sha256(priorBytes) == priorReports[0].snapshotSHA256 else {
            throw FinalizationRecoveryServiceError.inconsistent
        }
        let priorSnapshot: ReportSnapshotV1
        do {
            priorSnapshot = try ReportSnapshotEncoderV1().decode(priorBytes)
            guard try ReportSnapshotEncoderV1().encode(priorSnapshot).data == priorBytes else {
                throw FinalizationRecoveryServiceError.inconsistent
            }
        } catch {
            throw FinalizationRecoveryServiceError.inconsistent
        }
        let fullyValidatedPrior: ValidatedReadyReportValue
        do {
            fullyValidatedPrior = try ReportDeliveryCoordinator(
                modelContext: modelContext,
                generationRootURL: generationRootURL,
                expectedRootIdentity: rootIdentity
            ).validatedReadyReport(id: priorReportID)
        } catch {
            throw FinalizationRecoveryServiceError.inconsistent
        }
        guard fullyValidatedPrior.snapshot == priorSnapshot else {
            throw FinalizationRecoveryServiceError.inconsistent
        }
        do {
            try ReportCorrectionRule().validateEdge(
                prior: ReportCorrectionRuleSource(
                    currentRecord: recordPayload(priorRecords[0]),
                    packet: packetBefore,
                    currentReport: reportPayload(priorReports[0]),
                    currentSnapshot: priorSnapshot
                ),
                correctionRecord: payload.workflowRecordAfter,
                correctionReport: report,
                correctionSnapshot: snapshot,
                canonicalizeSerializedRecordDates: true
            )
        } catch {
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
              validEvidenceCardinality(evidence, cnv: payload.workflowRecordAfter.outcomeKey == "could_not_verify"),
              evidence.allSatisfy(validEvidenceAuthority) else {
            throw FinalizationRecoveryServiceError.inconsistent
        }
    }

    private func validEvidenceCardinality(_ evidence: [EvidenceFile], cnv: Bool) -> Bool {
        let keys = evidence.map(\.purposeKey)
        if cnv {
            return evidence.count <= 2 && Set(keys).count == keys.count
                && keys.allSatisfy { $0 == "wide_context" || $0 == "close_detail" }
        }
        return evidence.count == 2
            && keys.filter { $0 == "wide_context" }.count == 1
            && keys.filter { $0 == "close_detail" }.count == 1
    }

    private func evidenceOrder(_ key: String) -> Int {
        key == "wide_context" ? 0 : key == "close_detail" ? 1 : 2
    }

    private func outcomeDisplay(_ key: String) -> String? {
        if key == "work_recorded" { return "Work recorded" }
        return SignPack.illuminatedSignV1.outcomeDisplays
            .first(where: { $0.key == key })?.display
    }

    private func stageDisplay(_ key: String) -> String? {
        if key == WorkflowStage.work.rawValue { return "Work" }
        return SignPack.illuminatedSignV1.stageDisplays
            .first(where: { $0.key == key })?.display
    }

    private func purposeDisplay(_ key: String) -> String? {
        SignPack.illuminatedSignV1.evidencePurposes
            .first(where: { $0.key == key })?.display
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

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
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
            if payload.packetBefore != nil {
                return try correctionDatabaseState(
                    intent: intent,
                    records: records,
                    mutationRecords: mutationRecords,
                    reportPayload: reportPayload
                )
            }
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
            let allIssues = try modelContext.fetch(FetchDescriptor<Issue>())
            let originalIssues = payload.issueTransition.map { transition in
                allIssues.filter { $0.id == transition.before.id }
            } ?? []
            let insertedIssueID = payload.issueInsert?.id
            let insertedIssues = allIssues.filter { issue in
                (insertedIssueID.map { $0 == issue.id } ?? false)
                    || issue.openedByRecordID == intent.recordID
            }
            guard records.count <= 1, packets.count <= 1, reports.count <= 1,
                  originalIssues.count <= 1, insertedIssues.count <= 1 else {
                return .inconsistent
            }

            if let mutationRecord = mutationRecords.first {
                guard records.count == 1, records.first === mutationRecord,
                      packets.count == 1, reports.count == 1,
                      record(records[0], matches: payload.workflowRecordAfter),
                      packet(packets[0], matches: payload.packetAfter),
                      report(reports[0], matches: reportPayload),
                      issueRowsMatch(originalIssues, payload: payload.issueTransition?.after),
                      issueRowsMatch(insertedIssues, payload: payload.issueInsert) else {
                    return .inconsistent
                }
                return .matching
            }

            guard packets.isEmpty, reports.isEmpty,
                  issueRowsMatch(originalIssues, payload: payload.issueTransition?.before),
                  insertedIssues.isEmpty else {
                return .inconsistent
            }
            guard records.count == 1 else { return .inconsistent }
            let candidate = records[0]
            guard candidate.state == WorkflowState.draft.rawValue,
                  candidate.packetID == nil,
                  candidate.issueID == (payload.workflowRecordAfter.stage
                    == WorkflowStage.recheck.rawValue
                    ? payload.workflowRecordAfter.issueID
                    : nil),
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

    private func correctionDatabaseState(
        intent: FinalizationIntentV1,
        records: [WorkflowRecord],
        mutationRecords: [WorkflowRecord],
        reportPayload: ReportPayloadV1
    ) throws -> DatabaseState {
        let payload = intent.finalizationPayload
        guard let packetBefore = payload.packetBefore else { return .inconsistent }
        let packets = try modelContext.fetch(FetchDescriptor<Packet>()).filter {
            $0.id == intent.packetID || $0.stableRootID == intent.stableRootID
        }
        let reports = try modelContext.fetch(FetchDescriptor<Report>())
        let allRecords = try modelContext.fetch(FetchDescriptor<WorkflowRecord>())
        let insertedReports = reports.filter {
            $0.id == intent.reportID || $0.sourceRecordID == intent.recordID
        }
        let evidence = try modelContext.fetch(FetchDescriptor<EvidenceFile>()).filter {
            $0.recordID == intent.recordID
        }
        let issues = try modelContext.fetch(FetchDescriptor<Issue>()).filter {
            $0.openedByRecordID == intent.recordID || $0.resolvedByRecordID == intent.recordID
        }
        guard packets.count == 1, evidence.isEmpty, issues.isEmpty else {
            return .inconsistent
        }
        if let mutationRecord = mutationRecords.first {
            guard records.count == 1, records.first === mutationRecord,
                  insertedReports.count == 1,
                  allRecords.filter({
                      $0.revisesRecordID == packetBefore.currentRecordID
                  }).count == 1,
                  reports.filter({
                      $0.replacesReportID == reportPayload.replacesReportID
                  }).count == 1,
                  allRecords.filter({
                      $0.revisesRecordID == payload.workflowRecordAfter.id
                  }).isEmpty,
                  reports.filter({
                      $0.replacesReportID == reportPayload.id
                  }).isEmpty,
                  record(mutationRecord, matches: payload.workflowRecordAfter),
                  packet(packets[0], matches: payload.packetAfter),
                  report(insertedReports[0], matches: reportPayload) else {
                return .inconsistent
            }
            return .matching
        }
        guard records.isEmpty, insertedReports.isEmpty,
              packet(packets[0], matches: packetBefore),
              reports.filter({ $0.id == reportPayload.replacesReportID }).count == 1,
              reports.filter({ $0.replacesReportID == reportPayload.replacesReportID }).isEmpty,
              allRecords.filter({ $0.id == packetBefore.currentRecordID }).count == 1,
              allRecords.filter({
                  $0.revisesRecordID == packetBefore.currentRecordID
              }).isEmpty else {
            return .preconditionFailed
        }
        return .absent
    }

    private func apply(_ payload: FinalizationPayloadV1) throws {
        if payload.packetBefore != nil {
            try applyCorrection(payload)
            return
        }
        let records = try fetch(WorkflowRecord.self, id: payload.workflowRecordAfter.id)
        guard records.count == 1,
              draft(records[0], matchesBefore: payload.workflowRecordAfter),
              payload.packetBefore == nil,
              let reportPayload = payload.reportInsert,
              let reportState = ReportPDFState(rawValue: reportPayload.pdfState) else {
            throw FinalizationRecoveryServiceError.inconsistent
        }
        apply(payload.workflowRecordAfter, to: records[0])
        if let transition = payload.issueTransition {
            let issues = try fetch(Issue.self, id: transition.before.id)
            guard issues.count == 1,
                  issueRowsMatch(issues, payload: transition.before) else {
                throw FinalizationRecoveryServiceError.inconsistent
            }
            issues[0].status = transition.after.status
            issues[0].resolvedByRecordID = transition.after.resolvedByRecordID
            issues[0].updatedAt = transition.after.updatedAt
        }
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

    private func applyCorrection(_ payload: FinalizationPayloadV1) throws {
        guard let packetBefore = payload.packetBefore,
              let report = payload.reportInsert,
              let revisionKind = WorkflowRevisionKind(
                rawValue: payload.workflowRecordAfter.revisionKind
              ),
              let stage = WorkflowStage(rawValue: payload.workflowRecordAfter.stage),
              let state = WorkflowState(rawValue: payload.workflowRecordAfter.state),
              let reportState = ReportPDFState(rawValue: report.pdfState) else {
            throw FinalizationRecoveryServiceError.inconsistent
        }
        let packets = try modelContext.fetch(FetchDescriptor<Packet>()).filter {
            $0.id == packetBefore.id
        }
        let priorRecords = try modelContext.fetch(FetchDescriptor<WorkflowRecord>()).filter {
            $0.id == packetBefore.currentRecordID
        }
        guard packets.count == 1,
              priorRecords.count == 1,
              packet(packets[0], matches: packetBefore) else {
            throw FinalizationRecoveryServiceError.inconsistent
        }
        let priorRecord = priorRecords[0]
        let value = payload.workflowRecordAfter
        modelContext.insert(WorkflowRecord(
            id: value.id, assetID: value.assetID, packetID: value.packetID,
            issueID: value.issueID, parentRecordID: value.parentRecordID,
            recordRevisionRootID: value.recordRevisionRootID,
            revisesRecordID: value.revisesRecordID,
            evidenceSourceRecordID: value.evidenceSourceRecordID,
            revisionKind: revisionKind, stage: stage, state: state,
            draftStepKey: value.draftStepKey.flatMap(WorkflowDraftStep.init(rawValue:)),
            startedAt: priorRecord.startedAt, completedAt: priorRecord.completedAt,
            observedAtUTC: priorRecord.observedAtUTC, timeZoneID: value.timeZoneID,
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
            workDescription: value.workDescription,
            note: value.note, finalizationMutationID: value.finalizationMutationID
        ))
        packets[0].currentRecordID = payload.packetAfter.currentRecordID
        modelContext.insert(Report(
            id: report.id, packetID: report.packetID,
            sourceRecordID: report.sourceRecordID,
            snapshotSchemaVersion: report.snapshotSchemaVersion,
            snapshotRelativePath: report.snapshotRelativePath,
            snapshotSHA256: report.snapshotSHA256,
            pdfState: reportState, pdfRelativePath: report.pdfRelativePath,
            pdfSHA256: report.pdfSHA256, createdAt: report.createdAt,
            replacesReportID: report.replacesReportID
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
        let steps = after.outcomeKey == "could_not_verify"
            ? [WorkflowDraftStep.wide, .close, .outcome]
            : [.outcome]
        return steps.contains { step in
            record(row, matches: after, overrides: (
                packetID: nil,
                issueID: after.stage == WorkflowStage.recheck.rawValue
                    ? after.issueID
                    : nil,
                state: WorkflowState.draft.rawValue,
                draftStepKey: step.rawValue, completedAt: nil,
                outcomeKey: nil, couldNotVerifyKey: nil,
                couldNotVerifyDisplaySnapshot: nil,
                couldNotVerifyRegistryVersion: nil, note: nil,
                finalizationMutationID: nil
            ))
        }
    }

    private func record(_ row: WorkflowRecord, matches value: WorkflowRecordPayloadV1) -> Bool {
        record(row, matches: value, overrides: nil)
    }

    private typealias RecordOverrides = (
        packetID: UUID?, issueID: UUID?, state: String, draftStepKey: String?,
        completedAt: Date?, outcomeKey: String?, couldNotVerifyKey: String?,
        couldNotVerifyDisplaySnapshot: String?, couldNotVerifyRegistryVersion: String?,
        note: String?, finalizationMutationID: UUID?
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
        let couldNotVerifyKey: String?
        let couldNotVerifyDisplaySnapshot: String?
        let couldNotVerifyRegistryVersion: String?
        let note: String?
        let mutationID: UUID?
        if let overrides {
            packetID = overrides.packetID
            issueID = overrides.issueID
            state = overrides.state
            completedAt = overrides.completedAt
            draftStepKey = overrides.draftStepKey
            outcomeKey = overrides.outcomeKey
            couldNotVerifyKey = overrides.couldNotVerifyKey
            couldNotVerifyDisplaySnapshot = overrides.couldNotVerifyDisplaySnapshot
            couldNotVerifyRegistryVersion = overrides.couldNotVerifyRegistryVersion
            note = overrides.note
            mutationID = overrides.finalizationMutationID
        } else {
            packetID = v.packetID
            issueID = v.issueID
            state = v.state
            completedAt = v.completedAt
            draftStepKey = v.draftStepKey
            outcomeKey = v.outcomeKey
            couldNotVerifyKey = v.couldNotVerifyKey
            couldNotVerifyDisplaySnapshot = v.couldNotVerifyDisplaySnapshot
            couldNotVerifyRegistryVersion = v.couldNotVerifyRegistryVersion
            note = v.note
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
            && canonicalDateEqual(r.startedAt, v.startedAt)
            && canonicalOptionalDateEqual(r.completedAt, completedAt)
            && canonicalOptionalDateEqual(r.observedAtUTC, v.observedAtUTC)
            && r.timeZoneID == v.timeZoneID
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
            && r.couldNotVerifyKey == couldNotVerifyKey
            && r.couldNotVerifyDisplaySnapshot == couldNotVerifyDisplaySnapshot
            && r.couldNotVerifyRegistryVersion == couldNotVerifyRegistryVersion
            && r.workPerformedLocalDate == v.workPerformedLocalDate
            && r.workDescription == v.workDescription && r.note == note
            && r.finalizationMutationID == mutationID
    }

    private func packet(_ r: Packet, matches v: PacketPayloadV1) -> Bool {
        r.id == v.id && r.schemaVersion == v.schemaVersion && r.stableRootID == v.stableRootID
            && r.currentRecordID == v.currentRecordID && r.evaluationCounted == v.evaluationCounted
            && canonicalOptionalDateEqual(r.contentDeletedAt, v.contentDeletedAt)
            && canonicalDateEqual(r.createdAt, v.createdAt)
    }

    private func report(_ r: Report, matches v: ReportPayloadV1) -> Bool {
        r.id == v.id && r.schemaVersion == v.schemaVersion && r.packetID == v.packetID
            && r.sourceRecordID == v.sourceRecordID && r.snapshotSchemaVersion == v.snapshotSchemaVersion
            && r.snapshotRelativePath == v.snapshotRelativePath && r.snapshotSHA256 == v.snapshotSHA256
            && r.pdfState == v.pdfState && r.pdfRelativePath == v.pdfRelativePath
            && r.pdfSHA256 == v.pdfSHA256
            && canonicalDateEqual(r.createdAt, v.createdAt)
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
            && canonicalDateEqual(r.createdAt, payload.createdAt)
            && canonicalDateEqual(r.updatedAt, payload.updatedAt)
    }

    private func canonicalDateEqual(_ lhs: Date, _ rhs: Date) -> Bool {
        canonicalTimestamp(lhs) == canonicalTimestamp(rhs)
    }

    private func canonicalOptionalDateEqual(_ lhs: Date?, _ rhs: Date?) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none): return true
        case let (.some(left), .some(right)):
            return canonicalDateEqual(left, right)
        default: return false
        }
    }

    private func canonicalTimestamp(_ value: Date) -> String {
        Self.timestampFormatter.string(from: value)
    }

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private func apply(_ v: WorkflowRecordPayloadV1, to r: WorkflowRecord) {
        r.packetID = v.packetID
        r.issueID = v.issueID
        r.state = v.state
        r.draftStepKey = v.draftStepKey
        r.completedAt = v.completedAt
        r.outcomeKey = v.outcomeKey
        r.couldNotVerifyKey = v.couldNotVerifyKey
        r.couldNotVerifyDisplaySnapshot = v.couldNotVerifyDisplaySnapshot
        r.couldNotVerifyRegistryVersion = v.couldNotVerifyRegistryVersion
        r.note = v.note
        r.finalizationMutationID = v.finalizationMutationID
    }

    private struct OriginalRecoveryMutationState {
        let record: WorkflowRecord
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
        let issue: Issue?
        let issueStatus: String?
        let issueResolvedByRecordID: UUID?
        let issueUpdatedAt: Date?

        func restore() {
            record.packetID = packetID
            record.issueID = issueID
            record.state = state
            record.draftStepKey = draftStepKey
            record.completedAt = completedAt
            record.outcomeKey = outcomeKey
            record.couldNotVerifyKey = couldNotVerifyKey
            record.couldNotVerifyDisplaySnapshot = couldNotVerifyDisplaySnapshot
            record.couldNotVerifyRegistryVersion = couldNotVerifyRegistryVersion
            record.note = note
            record.finalizationMutationID = finalizationMutationID
            if let issue {
                issue.status = issueStatus ?? issue.status
                issue.resolvedByRecordID = issueResolvedByRecordID
                issue.updatedAt = issueUpdatedAt ?? issue.updatedAt
            }
        }
    }

    private func originalRecoveryMutationState(
        _ payload: FinalizationPayloadV1
    ) throws -> OriginalRecoveryMutationState {
        guard payload.packetBefore == nil else {
            throw FinalizationRecoveryServiceError.inconsistent
        }
        let records = try fetch(
            WorkflowRecord.self,
            id: payload.workflowRecordAfter.id
        )
        guard records.count == 1 else {
            throw FinalizationRecoveryServiceError.inconsistent
        }
        let issue: Issue?
        if let transition = payload.issueTransition {
            let rows = try fetch(Issue.self, id: transition.before.id)
            guard rows.count == 1,
                  issueRowsMatch(rows, payload: transition.before) else {
                throw FinalizationRecoveryServiceError.inconsistent
            }
            issue = rows[0]
        } else {
            issue = nil
        }
        let record = records[0]
        return OriginalRecoveryMutationState(
            record: record,
            packetID: record.packetID,
            issueID: record.issueID,
            state: record.state,
            draftStepKey: record.draftStepKey,
            completedAt: record.completedAt,
            outcomeKey: record.outcomeKey,
            couldNotVerifyKey: record.couldNotVerifyKey,
            couldNotVerifyDisplaySnapshot: record.couldNotVerifyDisplaySnapshot,
            couldNotVerifyRegistryVersion: record.couldNotVerifyRegistryVersion,
            note: record.note,
            finalizationMutationID: record.finalizationMutationID,
            issue: issue,
            issueStatus: issue?.status,
            issueResolvedByRecordID: issue?.resolvedByRecordID,
            issueUpdatedAt: issue?.updatedAt
        )
    }

    private struct CorrectionRecoveryPacketState {
        let packet: Packet
        let currentRecordID: UUID?

        func restore() {
            packet.currentRecordID = currentRecordID
        }
    }

    private func correctionRecoveryPacketState(
        _ payload: FinalizationPayloadV1
    ) throws -> CorrectionRecoveryPacketState? {
        guard let before = payload.packetBefore else { return nil }
        let packets = try fetch(Packet.self, id: before.id)
        guard packets.count == 1,
              packet(packets[0], matches: before) else {
            throw FinalizationRecoveryServiceError.inconsistent
        }
        return CorrectionRecoveryPacketState(
            packet: packets[0],
            currentRecordID: packets[0].currentRecordID
        )
    }
}

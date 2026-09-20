import Foundation

/// A restore-local proposal derived from a physically validated full package.
/// It grants no writer permission and never survives as a second source of truth.
struct RepetitiveCaptureRestoreReviewPlanV1: Sendable {
    let restoreID: UUID
    let identity: RestoreIdentityV1
    let checkpoints: [FieldDraftCheckpointV1]
    private let sourcePackage: ValidatedRepetitiveCaptureSourcePackageV2
    private let suppressedDraftIDs: Set<UUID>
    private let sourceRowsByKey: [String: V16BackupFieldDraftRecordV1]

    private init(restoreID: UUID, identity: RestoreIdentityV1,
                 checkpoints: [FieldDraftCheckpointV1],
                 sourcePackage: ValidatedRepetitiveCaptureSourcePackageV2,
                 suppressedDraftIDs: Set<UUID>,
                 sourceRowsByKey: [String: V16BackupFieldDraftRecordV1]) {
        self.restoreID = restoreID
        self.identity = identity
        self.checkpoints = checkpoints
        self.sourcePackage = sourcePackage
        self.suppressedDraftIDs = suppressedDraftIDs
        self.sourceRowsByKey = sourceRowsByKey
    }

    static func containsReviewSource(_ records: V4BackupRecordsV1) throws -> Bool {
        let original = try RepetitiveCaptureProgressDraftCodecV2.release()
        let review = try RepetitiveCaptureDestinationReviewCodecV1.release()
        for row in records.fieldDrafts where row.kind == .checkpoint {
            let checkpoint = try FieldDraftCanonicalCodecV1.decode(
                FieldDraftCheckpointV1.self, from: row.canonicalData)
            if checkpoint.codec == original || checkpoint.codec == review { return true }
        }
        return false
    }

    static func prepare(sourcePackage: ValidatedRepetitiveCaptureSourcePackageV2,
                        identity: RestoreIdentityV1, restoreID: UUID,
                        reviewedAt: Date) throws -> Self? {
        // Exact replacement and configuration clone use their existing owners.
        guard identity.mode == .replaceExisting || identity.mode == .fork,
              identity.source.workspaceID != identity.targetPointer.workspaceID else { return nil }
        guard identity.source.workspaceID == sourcePackage.source.workspaceID,
              identity.source.replicaID == sourcePackage.source.replicaID,
              identity.recordIdentityDisposition == .preserve else { throw invalid() }

        let reviewed = try RepetitiveCaptureSourceGraphReviewV2.review(sourcePackage: sourcePackage)
        var checkpoints: [FieldDraftCheckpointV1] = []
        var suppressed = Set<UUID>()
        for graph in reviewed.graphs {
            let prepared = try RepetitiveCaptureDestinationReviewV1.prepareFirst(
                from: reviewed, sourceDraftID: graph.chain.sourceCheckpoint.draftID,
                identity: identity, reviewedAt: reviewedAt)
            guard suppressed.isDisjoint(with: prepared.sourceCheckpointIDs) else { throw invalid() }
            suppressed.formUnion(prepared.sourceCheckpointIDs)
            checkpoints.append(prepared.checkpoint)
        }

        let reviewRelease = try RepetitiveCaptureDestinationReviewCodecV1.release()
        guard let history = sourcePackage.records.mutationHistory else { throw invalid() }
        let facts = try MutationJournalStoreV1.validatedImportedSnapshotFacts(history)
        for row in sourcePackage.records.fieldDrafts where row.kind == .checkpoint {
            let checkpoint = try FieldDraftCanonicalCodecV1.decode(
                FieldDraftCheckpointV1.self, from: row.canonicalData)
            guard checkpoint.codec == reviewRelease else { continue }
            guard checkpoint.workspaceID.rawValue == sourcePackage.source.workspaceID,
                  row.id == checkpoint.draftID, row.workspaceID == checkpoint.workspaceID.rawValue,
                  row.revision == checkpoint.draftRevision else { throw invalid() }
            let lineage = try RepetitiveCaptureReviewLineageReaderV1.read(
                workspaceID: checkpoint.workspaceID, mutationID: checkpoint.mutationID,
                in: history, validatedBy: facts)
            guard lineage.selectedReview.checkpoint == checkpoint else { throw invalid() }
            let prepared = try RepetitiveCaptureDestinationReviewV1.prepareInherited(
                from: lineage, identity: identity, reviewedAt: reviewedAt)
            guard suppressed.insert(prepared.sourceReviewDraftID).inserted else { throw invalid() }
            checkpoints.append(prepared.checkpoint)
        }
        guard !checkpoints.isEmpty else { return nil }
        var rowsByKey: [String: V16BackupFieldDraftRecordV1] = [:]
        for row in sourcePackage.records.fieldDrafts {
            guard rowsByKey.updateValue(row, forKey: key(row)) == nil else { throw invalid() }
        }
        let result = Self(restoreID: restoreID, identity: identity,
            checkpoints: checkpoints.sorted { $0.draftID.uuidString < $1.draftID.uuidString },
            sourcePackage: sourcePackage, suppressedDraftIDs: suppressed, sourceRowsByKey: rowsByKey)
        try result.validate()
        return result
    }

    func validate() throws {
        try FieldDraftValidationV1.id(restoreID)
        guard identity.mode == .replaceExisting || identity.mode == .fork,
              identity.source.workspaceID == sourcePackage.source.workspaceID,
              identity.source.workspaceID != identity.targetPointer.workspaceID,
              identity.targetPointer.generationID != identity.oldPointer.generationID,
              identity.recordIdentityDisposition == .preserve,
              !checkpoints.isEmpty,
              Set(checkpoints.map(\.draftID)).count == checkpoints.count,
              Set(checkpoints.map(\.mutationID)).count == checkpoints.count else { throw Self.invalid() }
        for checkpoint in checkpoints {
            try RepetitiveCaptureDestinationReviewCodecV1.validateInitialCheckpoint(
                checkpoint, creationGenerationID: identity.targetPointer.generationID)
            guard checkpoint.workspaceID.rawValue == identity.targetPointer.workspaceID,
                  !suppressedDraftIDs.contains(checkpoint.draftID) else { throw Self.invalid() }
        }
    }

    /// Suppression is qualified by original workspace, decoded owner and exact
    /// source bytes. An unrelated draft with a coincident UUID is never consumed.
    func retainingUnownedRows(_ rows: [V16BackupFieldDraftRecordV1]) throws
        -> [V16BackupFieldDraftRecordV1] {
        var retained: [V16BackupFieldDraftRecordV1] = []
        var consumed = Set<String>()
        for row in rows {
            guard row.workspaceID == sourcePackage.source.workspaceID,
                  suppressedDraftIDs.contains(try Self.owner(row)) else {
                retained.append(row)
                continue
            }
            let key = Self.key(row)
            guard sourceRowsByKey[key] == row, consumed.insert(key).inserted else { throw Self.invalid() }
        }
        let required = try Set(sourceRowsByKey.values.filter {
            suppressedDraftIDs.contains(try Self.owner($0))
        }.map(Self.key))
        guard consumed == required else { throw Self.invalid() }
        return retained
    }

    /// Keep all source journal bytes; only the actual staging writer may add
    /// the fresh destination review creations. No predicted receipt is accepted.
    @MainActor
    func requireWrittenHistory(_ written: MutationHistorySnapshotV1,
                               preserving before: MutationHistorySnapshotV1,
                               diagnosticPhase: (@MainActor (String) -> Void)? = nil) throws {
        diagnosticPhase?("history.originals-before.begin")
        let beforeByKey = try Self.originals(before)
        diagnosticPhase?("history.originals-before.end")
        diagnosticPhase?("history.originals-after.begin")
        let afterByKey = try Self.originals(written)
        diagnosticPhase?("history.originals-after.end")
        diagnosticPhase?("history.preservation.begin")
        guard beforeByKey.allSatisfy({ afterByKey[$0.key] == $0.value }),
              written.quarantines == before.quarantines,
              afterByKey.count == beforeByKey.count + checkpoints.count else { throw Self.invalid() }
        diagnosticPhase?("history.preservation.end")
        for checkpoint in checkpoints {
            let key = MutationWorkspaceKeyV1.value(workspaceID: checkpoint.workspaceID,
                                                   mutationID: checkpoint.mutationID)
            diagnosticPhase?("history.checkpoint-original.begin")
            guard beforeByKey[key] == nil, let original = afterByKey[key] else { throw Self.invalid() }
            diagnosticPhase?("history.checkpoint-original.end")
            diagnosticPhase?("history.envelope.begin")
            let envelope = try MutationEnvelopeV1.decodeCanonical(from: original.envelopeData)
            diagnosticPhase?("history.envelope.end")
            diagnosticPhase?("history.receipt.begin")
            let receipt = try MutationReceiptV1.decodeCanonical(from: original.receiptData)
            diagnosticPhase?("history.receipt.end")
            diagnosticPhase?("history.typed-evidence.begin")
            let evidence = try FieldDraftCommittedEvidenceV1(envelope: envelope, receipt: receipt)
            diagnosticPhase?("history.typed-evidence.end")
            diagnosticPhase?("history.target.begin")
            guard envelope.generationID == identity.targetPointer.generationID,
                  envelope.replicaID.rawValue == identity.targetPointer.replicaID,
                  case .createCheckpoint(let actual) = evidence.mutation.postImage,
                  actual == checkpoint else { throw Self.invalid() }
            diagnosticPhase?("history.target.end")
            diagnosticPhase?("history.lineage.begin")
            let lineage = try RepetitiveCaptureReviewLineageReaderV1.read(
                workspaceID: checkpoint.workspaceID, mutationID: checkpoint.mutationID, in: written)
            diagnosticPhase?("history.lineage.end")
            diagnosticPhase?("history.selected-checkpoint.begin")
            guard lineage.selectedReview.initialCheckpoint == checkpoint else { throw Self.invalid() }
            diagnosticPhase?("history.selected-checkpoint.end")
        }
    }

    private static func originals(_ history: MutationHistorySnapshotV1) throws
        -> [String: MutationHistoryReceiptRecordV1] {
        var result: [String: MutationHistoryReceiptRecordV1] = [:]
        for original in history.receipts {
            let envelope = try MutationEnvelopeV1.decodeCanonical(from: original.envelopeData)
            let key = MutationWorkspaceKeyV1.value(workspaceID: envelope.workspaceID,
                                                   mutationID: envelope.mutationID)
            guard result.updateValue(original, forKey: key) == nil else { throw invalid() }
        }
        return result
    }

    private static func key(_ row: V16BackupFieldDraftRecordV1) -> String {
        "\(row.workspaceID.uuidString)|\(row.kind.rawValue)|\(row.id.uuidString)"
    }

    private static func owner(_ row: V16BackupFieldDraftRecordV1) throws -> UUID {
        switch row.kind {
        case .checkpoint:
            return try FieldDraftCanonicalCodecV1.decode(FieldDraftCheckpointV1.self, from: row.canonicalData).draftID
        case .stagingItem:
            return try FieldDraftCanonicalCodecV1.decode(AttachmentStagingItemV1.self, from: row.canonicalData).draftID
        case .commitSaga:
            return try FieldDraftCanonicalCodecV1.decode(DraftCommitSagaV1.self, from: row.canonicalData).draftID
        case .contentReservation:
            return try FieldDraftCanonicalCodecV1.decode(DraftContentReservationV1.self, from: row.canonicalData).draftID
        case .commitReceipt:
            return try FieldDraftCanonicalCodecV1.decode(DraftCommitReceiptV1.self, from: row.canonicalData).draftID
        case .discardReceipt:
            return try FieldDraftCanonicalCodecV1.decode(DraftDiscardReceiptV1.self, from: row.canonicalData).draftID
        }
    }

    private static func invalid() -> BackupRestoreServiceError { .invalidRestoreAuthority }
}

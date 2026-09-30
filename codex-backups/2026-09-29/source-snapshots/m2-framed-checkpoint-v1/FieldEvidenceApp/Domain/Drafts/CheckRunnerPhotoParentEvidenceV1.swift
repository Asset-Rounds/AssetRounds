import Foundation

/// Original parent/child relationship only. The live journal authenticates
/// these originals and current parent row. Source, mutable workflow, media,
/// destination correspondence and the eventual adoption CAS remain separate.
struct CheckRunnerPhotoParentEvidenceV1: Equatable, Sendable {
    struct CheckpointHistoryEntry: Equatable, Sendable {
        let evidence: FieldDraftCommittedEvidenceV1
        let checkpoint: FieldDraftCheckpointV1
        let payload: CheckRunnerItemDraftPayloadV1
    }

    struct ValidatedCheckpointHistory: Equatable, Sendable {
        let parent: CheckRunnerItemDraftPayloadV1
        let entries: [CheckpointHistoryEntry]
        let selectedChildDraftIDs: Set<UUID>
    }

    let checkpoint: FieldDraftCheckpointV1
    let pending: FieldDraftCommittedEvidenceV1
    let slot: CheckRunnerPhotoSlotV1
    let child: CheckRunnerPhotoCommitEvidenceV1

    init(history: [FieldDraftCommittedEvidenceV1], checkpoint: FieldDraftCheckpointV1,
         child: CheckRunnerPhotoCommitEvidenceV1, workflow: CheckRunnerBeginCommittedEvidenceV1,
         timeZone: CheckRunnerBeginCommittedEvidenceV1?,
         finalization: CheckRunnerItemFinalizationEvidenceV1? = nil) throws {
        let failure = WorkspaceMutationFailureV1.receiptHistoryCorrupt
        let validated: ValidatedCheckpointHistory
        if let finalization {
            guard finalization.checkpoint == checkpoint, finalization.history == history,
                  finalization.workflow == workflow, finalization.timeZone == timeZone else { throw failure }
            validated = finalization.editing
        } else {
            validated = try Self.validateCheckpointHistory(history: history, checkpoint: checkpoint,
                workflow: workflow, timeZone: timeZone)
        }
        let parent = validated.parent
        guard case let .createCheckpoint(createdChild) = child.creating.mutation.postImage,
              case let .applyCommitTerminal(terminal, _) = child.terminal.mutation.postImage else { throw failure }
        let photo = try CheckRunnerPhotoDraftCodecV1.validateCheckpoint(terminal.committedCheckpoint)
        try photo.validate(parent: parent, parentDraftID: checkpoint.draftID)
        let slot = CheckRunnerPhotoSlotV1.committed(childDraftID: photo.childDraftID,
            captureStep: photo.captureStep, purposeKey: photo.purposeKey,
            committedChildDraftRevision: terminal.committedCheckpoint.draftRevision,
            committedChildCheckpointSHA256: terminal.committedCheckpoint.checkpointSHA256,
            childCommitReceiptID: terminal.receipt.receiptID,
            childCommitReceiptSHA256: terminal.receipt.receiptSHA256,
            evidenceID: child.target.command.evidenceID,
            targetMutationID: child.target.receipt.mutationID,
            targetReceiptSHA256: child.target.receipt.resultSHA256)
        let expectedPending = CheckRunnerPhotoSlotV1.pending(childDraftID: photo.childDraftID,
            captureStep: photo.captureStep, purposeKey: photo.purposeKey)
        try slot.validateReplacement(of: expectedPending)

        var pending: FieldDraftCommittedEvidenceV1?
        var adopted = false
        for entry in validated.entries {
            let value = entry.checkpoint, payload = entry.payload
            let selected = photo.captureStep == .wide ? payload.field.wideContext : payload.field.closeDetail
            if pending == nil, selected?.childDraftID == photo.childDraftID {
                guard case .bound = payload.field.begin, selected == expectedPending else { throw failure }
                try photo.validate(parent: payload, parentDraftID: value.draftID)
                try photo.validateRawStageIntent(parentSlotCheckpointUpdatedAt: value.updatedAt)
                guard value.updatedAt <= createdChild.updatedAt else { throw failure }
                try CheckRunnerPhotoCommitEvidenceV1.requireOrder(entry.evidence.receipt, child.creating.receipt)
                pending = entry.evidence
            }
            if pending != nil {
                guard selected == slot || (!adopted && selected == expectedPending) else { throw failure }
                if selected == slot {
                    try CheckRunnerPhotoCommitEvidenceV1.requireOrder(child.terminal.receipt, entry.evidence.receipt)
                    guard value.updatedAt >= terminal.committedCheckpoint.updatedAt else { throw failure }
                    adopted = true
                }
            }
        }
        guard let pending else { throw failure }
        self.checkpoint = checkpoint; self.pending = pending; self.slot = slot; self.child = child
    }

    static func validateCheckpointHistory(
        history: [FieldDraftCommittedEvidenceV1], checkpoint: FieldDraftCheckpointV1,
        workflow: CheckRunnerBeginCommittedEvidenceV1, timeZone: CheckRunnerBeginCommittedEvidenceV1?
    ) throws -> ValidatedCheckpointHistory {
        let failure = WorkspaceMutationFailureV1.receiptHistoryCorrupt
        let parent = try CheckRunnerItemDraftCodecV1.validateCheckpoint(checkpoint)
        guard checkpoint.state == .active, parent.phase == .editing,
              case let .bound(attempt, workflowReference, zoneReference) = parent.field.begin,
              !history.isEmpty, Set(history.map { $0.mutation.mutationID }).count == history.count else {
            throw failure
        }
        try workflowReference.validate(evidence: workflow)
        guard attempt.sourceWorkspaceID == checkpoint.workspaceID,
              workflow.envelope.expectedRevision.entityRevisions == attempt.recordExpectedEntityRevisions,
              (timeZone == nil) == (zoneReference == nil) else { throw failure }
        if let zoneReference, let timeZone, let zone = attempt.timeZone {
            try zoneReference.validate(evidence: timeZone)
            let site = try WorkspaceEntityIdentityV1(kind: .site, id: zone.command.siteID)
            guard timeZone.envelope.expectedRevision.entityRevisions == [
                .init(identity: site, revision: zone.expectedSiteRevision)
            ] else { throw failure }
        }

        var originals: [(FieldDraftCommittedEvidenceV1, FieldDraftCheckpointV1)] = []
        for original in history {
            guard try FieldDraftCommittedEvidenceV1(envelope: original.envelope, receipt: original.receipt) == original,
                  original.mutation.workspaceID == checkpoint.workspaceID,
                  original.envelope.sourceKind == original.receipt.sourceKind,
                  original.envelope.causationMutationID == original.receipt.causationMutationID,
                  original.envelope.correlationID == original.receipt.correlationID,
                  original.envelope.contentDependencyIDs == original.receipt.contentDependencyIDs,
                  original.envelope.reversalPlanDigest == nil,
                  original.envelope.semanticReversalReplayIdentitySHA256 == nil,
                  original.envelope.semanticReversalExecution == nil,
                  original.receipt.reversesMutationID == nil else { throw failure }
            let value: FieldDraftCheckpointV1
            switch original.mutation.postImage {
            case let .createCheckpoint(created):
                guard created.draftRevision == 1 else { throw failure }; value = created
            case let .reviseCheckpoint(revised):
                guard revised.draftRevision > 1 else { throw failure }; value = revised
            default: throw failure
            }
            guard value.draftID == checkpoint.draftID, value.workspaceID == checkpoint.workspaceID,
                  value.mutationID == original.mutation.mutationID,
                  original.mutation.expectedRevision == value.draftRevision - 1,
                  original.mutation.expectedBaseCanonicalRevision == value.baseCanonicalRevision else { throw failure }
            originals.append((original, value))
        }
        originals.sort { $0.1.draftRevision < $1.1.draftRevision }
        guard originals.last?.1 == checkpoint else { throw failure }

        var entries: [CheckpointHistoryEntry] = []
        var selectedChildDraftIDs: Set<UUID> = []
        var previousBeginRank = 0
        for (index, original) in originals.enumerated() {
            let evidence = original.0, value = original.1
            let payload = try CheckRunnerItemDraftCodecV1.validateCheckpoint(value)
            guard value.draftRevision == UInt64(index) + 1,
                  value.state == .active, payload.phase == .editing,
                  value.lastDurableMutationID == nil, value.lastReceiptSHA256 == nil,
                  payload.source == parent.source else { throw failure }
            if index > 0 {
                let prior = originals[index - 1]
                try value.validateSuccessor(of: prior.1, expectedDraftRevision: prior.1.draftRevision,
                                            expectedBaseRevision: prior.1.baseCanonicalRevision)
                try CheckRunnerPhotoCommitEvidenceV1.requireOrder(prior.0.receipt, evidence.receipt)
            }
            let rank: Int
            switch payload.field.begin {
            case .notBegun: rank = 0
            case let .prepared(saved):
                guard saved == attempt else { throw failure }; rank = 1
            case .bound:
                guard payload.field.begin == parent.field.begin else { throw failure }; rank = 2
            }
            guard (index != 0 || rank == 0), rank >= previousBeginRank, rank <= previousBeginRank + 1 else {
                throw failure
            }
            if rank == 1 && previousBeginRank == 0 {
                try CheckRunnerPhotoCommitEvidenceV1.requireOrder(evidence.receipt,
                    timeZone?.receipt ?? workflow.receipt)
            }
            if rank == 2 && previousBeginRank < 2 {
                try CheckRunnerPhotoCommitEvidenceV1.requireOrder(workflow.receipt, evidence.receipt)
            }
            previousBeginRank = rank
            if let childID = payload.field.wideContext?.childDraftID { selectedChildDraftIDs.insert(childID) }
            if let childID = payload.field.closeDetail?.childDraftID { selectedChildDraftIDs.insert(childID) }
            entries.append(.init(evidence: evidence, checkpoint: value, payload: payload))
        }
        return .init(parent: parent, entries: entries, selectedChildDraftIDs: selectedChildDraftIDs)
    }
}

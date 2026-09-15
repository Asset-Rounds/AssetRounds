import Foundation

/// Retained child journal evidence, including the actual original COMMITTING
/// checkpoint. This value grants no media access, parent-slot replacement,
/// destination mapping or new effect. Those owners must perform their joins.
struct CheckRunnerPhotoCommitEvidenceV1: Equatable, Sendable {
    let creating: FieldDraftCommittedEvidenceV1
    let committing: FieldDraftCommittedEvidenceV1
    let terminal: FieldDraftCommittedEvidenceV1
    let reconstruction: CheckRunnerPhotoCommitReconstructionV1
    let target: CheckRunnerPhotoCommittedEvidenceV1
    let reservation: DraftContentReservationV1
    let stage: AttachmentStagingItemV1

    init(history: [FieldDraftCommittedEvidenceV1],
         checkpoint: FieldDraftCheckpointV1, sagas: [DraftCommitSagaV1],
         reservations: [DraftContentReservationV1], stages: [AttachmentStagingItemV1],
         receipts: [DraftCommitReceiptV1], target: CheckRunnerPhotoCommittedEvidenceV1) throws {
        let failure = WorkspaceMutationFailureV1.receiptHistoryCorrupt
        guard checkpoint.state == .committed, !history.isEmpty,
              Set(history.map { $0.mutation.mutationID }).count == history.count else { throw failure }
        for value in history {
            guard try FieldDraftCommittedEvidenceV1(envelope: value.envelope, receipt: value.receipt) == value,
                  value.mutation.workspaceID == checkpoint.workspaceID,
                  value.envelope.sourceKind == value.receipt.sourceKind,
                  value.envelope.causationMutationID == value.receipt.causationMutationID,
                  value.envelope.correlationID == value.receipt.correlationID,
                  value.envelope.contentDependencyIDs == value.receipt.contentDependencyIDs,
                  value.envelope.reversalPlanDigest == nil,
                  value.envelope.semanticReversalReplayIdentitySHA256 == nil,
                  value.envelope.semanticReversalExecution == nil,
                  value.receipt.reversesMutationID == nil else { throw failure }
        }
        let terminals = history.filter {
            if case .applyCommitTerminal = $0.mutation.postImage { return true }; return false
        }
        guard terminals.count == 1, let terminal = terminals.first,
              case let .applyCommitTerminal(bundle, expectedSagaRevision) = terminal.mutation.postImage,
              bundle.committedCheckpoint == checkpoint, receipts == [bundle.receipt],
              expectedSagaRevision == 4 else { throw failure }
        let checkpoints = history.compactMap { value -> (FieldDraftCommittedEvidenceV1, FieldDraftCheckpointV1)? in
            switch value.mutation.postImage {
            case let .createCheckpoint(cp), let .reviseCheckpoint(cp): return (value, cp)
            case let .publishReadyStage(publication): return (value, publication.successorCheckpoint)
            default: return nil
            }
        }.sorted { $0.1.draftRevision < $1.1.draftRevision }
        guard checkpoints.count >= 4, let first = checkpoints.first, let last = checkpoints.last,
              case .createCheckpoint = first.0.mutation.postImage,
              first.1.draftRevision == 1,
              case .reviseCheckpoint = last.0.mutation.postImage,
              last.1.state == .committing else { throw failure }
        let committing = last.0, original = last.1
        let reconstruction = try CheckRunnerPhotoDraftCodecV1.reconstructPhotoCommit(from: original)
        let commit = reconstruction.draftCommit
        let payload = try CheckRunnerPhotoDraftCodecV1.validateCheckpoint(original)
        guard case let .preparedCommit(pair, attempt) = payload.phase,
              case let .pairReady(priorPair) = try CheckRunnerPhotoDraftCodecV1.validateCheckpoint(
                checkpoints[checkpoints.count - 2].1).phase, priorPair == pair else { throw failure }
        try payload.validateCommitPreparation(pairReadyCheckpointUpdatedAt: checkpoints[checkpoints.count - 2].1.updatedAt)
        var previousRank = 0
        for (index, entry) in checkpoints.enumerated() {
            let value = try CheckRunnerPhotoDraftCodecV1.validateCheckpoint(entry.1)
            // Replace only the phase to compare every immutable child/source field.
            let sameIdentity = try CheckRunnerPhotoDraftPayloadV1(workspaceID: value.workspaceID,
                childDraftID: value.childDraftID, parentDraftID: value.parentDraftID,
                recordID: value.recordID, assetID: value.assetID, sourceBinding: value.sourceBinding,
                workflowStage: value.workflowStage, captureStep: value.captureStep,
                purposeKey: value.purposeKey, origin: value.origin, phase: payload.phase)
            guard sameIdentity == payload, entry.1.state == (index == checkpoints.count - 1 ? .committing : .active),
                  entry.1.lastDurableMutationID == nil, entry.1.lastReceiptSHA256 == nil else { throw failure }
            let rank: Int
            switch value.phase {
            case let .awaitingRawStage(intent): guard intent == pair.raw.intent else { throw failure }; rank = 0
            case let .rawReady(raw): guard raw == pair.raw else { throw failure }; rank = 1
            case let .pairReady(value): guard value == pair else { throw failure }; rank = 2
            case .preparedCommit:
                guard value == payload, index == checkpoints.count - 1 else { throw failure }; rank = 3
            }
            guard (index != 0 || rank == 0), rank >= previousRank, rank <= previousRank + 1 else { throw failure }
            if index > 0 {
                let prior = checkpoints[index - 1]
                try entry.1.validateSuccessor(of: prior.1, expectedDraftRevision: prior.1.draftRevision,
                                             expectedBaseRevision: prior.1.baseCanonicalRevision)
                try Self.requireOrder(prior.0.receipt, entry.0.receipt)
                if case let .publishReadyStage(publication) = entry.0.mutation.postImage {
                    guard publication.expectedCheckpoint == prior.1, publication.readyItem == pair.raw.readyItem,
                          previousRank == 0, rank == 1 else { throw failure }
                } else if rank == 1 && previousRank == 0 { throw failure }
            }
            previousRank = rank
        }
        let publications = history.filter {
            if case .publishReadyStage = $0.mutation.postImage { return true }; return false
        }
        guard publications.count == 1, publications[0].mutation.mutationID == pair.raw.stagePublicationMutationID,
              bundle.retiredSaga == commit.retired,
              sagas.count == 5, Set(sagas) == Set(commit.sagas),
              reservations.count == 1, let reservation = reservations.first,
              stages.count == 1, let stage = stages.first else { throw failure }

        var required = Set(checkpoints.map { $0.0.mutation.mutationID })
        required.insert(terminal.mutation.mutationID)
        var sagaEvidence: [FieldDraftCommittedEvidenceV1] = []
        for (index, saga) in commit.sagas.dropLast().enumerated() {
            let mutation = try FieldDraftMutationV1(workspaceID: checkpoint.workspaceID,
                expectedRevision: UInt64(index), expectedBaseCanonicalRevision: original.baseCanonicalRevision,
                mutationID: saga.mutationID,
                postImage: index == 0 ? .appendCommitSaga(saga) : .advanceCommitSaga(saga))
            let value = try Self.exact(mutation, in: history)
            required.insert(saga.mutationID); sagaEvidence.append(value)
        }
        try Self.requireOrder(committing.receipt, sagaEvidence[0].receipt)
        for index in 1..<sagaEvidence.count { try Self.requireOrder(sagaEvidence[index - 1].receipt, sagaEvidence[index].receipt) }
        try Self.requireOrder(sagaEvidence[3].receipt, terminal.receipt)

        let targetOutputs = try target.receipt.postImages.map { try $0.identity.stableKey }.sorted()
        guard try CheckRunnerPhotoCommittedEvidenceV1(envelope: target.envelope, receipt: target.receipt) == target,
              target.command == reconstruction.targetCommand, target.envelope.workspaceID == checkpoint.workspaceID,
              target.receipt.mutationID == commit.plan.mutationID,
              target.receipt.expectedRevision.entityRevisions.first(where: { $0.identity.kind == .workflowRecord })?.revision
                == commit.plan.expectedTargetRevision,
              targetOutputs == commit.plan.outputKeys else { throw failure }
        try Self.requireOrder(sagaEvidence[1].receipt, target.receipt)
        try Self.requireOrder(target.receipt, sagaEvidence[2].receipt)

        let raw = pair.raw, ready = raw.readyItem
        try reservation.validate()
        guard reservation.workspaceID == checkpoint.workspaceID, reservation.draftID == checkpoint.draftID,
              reservation.stageID == ready.stageID, reservation.commitPlanSHA256 == commit.plan.planSHA256,
              reservation.mutationID == attempt.reservationMutationID,
              reservation.reservationID == DraftAttachmentStagingAdapterV1.deterministicUUID(
                "reservation\u{1f}\(commit.plan.planSHA256)\u{1f}\(ready.stageID.uuidString.lowercased())"),
              reservation.createdAt == attempt.promotionAt, reservation.reviewAfter == attempt.reservationReviewAfter,
              reservation.revision == 1, reservation.reconciliationState == .reserved,
              reservation.contentDigest == raw.inspection.sourceSHA256,
              reservation.locator.workspaceID == checkpoint.workspaceID.rawValue.uuidString.lowercased(),
              reservation.locator.contentID == raw.inspection.rawContentID,
              reservation.locator.contentDigest == raw.inspection.sourceSHA256,
              reservation.locator.expectedByteLength == raw.inspection.sourceByteCount,
              reservation.locator.locatorRevision == 0 else { throw failure }
        let reserved = try Self.exact(.init(workspaceID: checkpoint.workspaceID, expectedRevision: 0,
            expectedBaseCanonicalRevision: 0, mutationID: reservation.mutationID,
            postImage: .appendContentReservation(reservation)), in: history)
        required.insert(reservation.mutationID)
        try Self.requireOrder(sagaEvidence[0].receipt, reserved.receipt)
        try Self.requireOrder(reserved.receipt, sagaEvidence[1].receipt)

        // The generic promotion manifest may advance before its operational row.
        // Both admitted row forms must retain the exact original raw witness.
        if stage != ready {
            let reference = try ContentReferenceV1(workspaceID: reservation.locator.workspaceID,
                contentID: raw.inspection.rawContentID, byteLength: raw.inspection.sourceByteCount,
                mediaType: raw.inspection.sourceMediaType, digests: .init([raw.inspection.sourceSHA256]),
                byteRole: .immutableOriginal, createdAt: CheckRunnerPhotoRawReadyV1.formatOriginalRecordedAt(attempt.promotionAt))
            let expected = try AttachmentStagingItemV1(stageID: ready.stageID, draftID: ready.draftID,
                workspaceID: ready.workspaceID, attachmentKind: ready.attachmentKind, scratchLeaseID: ready.scratchLeaseID,
                expectedByteCount: ready.expectedByteCount, actualByteCount: ready.actualByteCount,
                contentDigest: ready.contentDigest, contentReference: reference, processingJobID: ready.processingJobID,
                retryClass: ready.retryClass, state: .committed, protectionState: ready.protectionState,
                revision: ready.revision + 1, mutationID: .init(rawValue: DraftAttachmentStagingAdapterV1.deterministicUUID(
                    "stage-mutation\u{1f}\(ready.stageID.uuidString.lowercased())\u{1f}\(ready.revision + 1)\u{1f}COMMITTED\u{1f}\(raw.inspection.sourceSHA256.hexadecimalValue)")))
            guard stage == expected else { throw failure }
            let advanced = try Self.exact(.init(workspaceID: checkpoint.workspaceID, expectedRevision: ready.revision,
                expectedBaseCanonicalRevision: 0, mutationID: stage.mutationID, postImage: .reviseStagingItem(stage)), in: history)
            required.insert(stage.mutationID)
            try Self.requireOrder(publications[0].receipt, advanced.receipt)
            try Self.requireOrder(sagaEvidence[0].receipt, advanced.receipt)
        }
        let receipt = try DraftCommitReceiptV1(receiptID: commit.commitReceiptID, workspaceID: checkpoint.workspaceID,
            draftID: checkpoint.draftID, sagaID: commit.retired.sagaID, commitPlanSHA256: commit.plan.planSHA256,
            sagaEventSHA256Chain: commit.sagas.map(\.sagaSHA256), targetMutationID: commit.plan.mutationID,
            targetReceiptSHA256: target.receipt.resultSHA256,
            consumedStageToContentID: [ready.stageID.uuidString: reservation.locator.contentID],
            committedAt: target.receipt.committedAt, mutationID: commit.rowMutationIDs.terminalBundleMutationID)
        let expectedCheckpoint = try FieldDraftCheckpointV1(draftID: original.draftID, workspaceID: original.workspaceID,
            scope: original.scope, purpose: original.purpose, codec: original.codec,
            baseCanonicalRevision: original.baseCanonicalRevision, draftRevision: original.draftRevision + 1,
            payloadData: original.payloadData, stageIDs: original.stageIDs, resumeAnchor: original.resumeAnchor,
            state: .committed, lastDurableMutationID: commit.rowMutationIDs.terminalBundleMutationID,
            lastReceiptSHA256: receipt.receiptSHA256, updatedAt: commit.terminalCheckpointUpdatedAt,
            mutationID: commit.rowMutationIDs.terminalBundleMutationID)
        guard bundle.receipt == receipt, checkpoint == expectedCheckpoint,
              terminal.mutation.expectedRevision == original.draftRevision,
              terminal.mutation.expectedBaseCanonicalRevision == original.baseCanonicalRevision,
              required == Set(history.map { $0.mutation.mutationID }) else { throw failure }
        try checkpoint.validateSuccessor(of: original, expectedDraftRevision: original.draftRevision,
                                         expectedBaseRevision: original.baseCanonicalRevision)
        self.creating = checkpoints[0].0
        self.committing = committing; self.terminal = terminal; self.reconstruction = reconstruction
        self.target = target; self.reservation = reservation; self.stage = stage
    }

    private static func exact(_ mutation: FieldDraftMutationV1,
                              in history: [FieldDraftCommittedEvidenceV1]) throws -> FieldDraftCommittedEvidenceV1 {
        let values = history.filter { $0.mutation.mutationID == mutation.mutationID }
        guard values.count == 1, let value = values.first, value.mutation == mutation else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        return value
    }

    /// Workspace revision order is meaningful within one original generation.
    /// Across restored generations, exact command/revision joins govern instead.
    static func requireOrder(_ earlier: MutationReceiptV1, _ later: MutationReceiptV1) throws {
        guard earlier.identity.workspaceID == later.identity.workspaceID else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        if earlier.resultingRevision.generationID == later.resultingRevision.generationID {
            guard earlier.resultingRevision.workspaceRevision < later.resultingRevision.workspaceRevision else {
                throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
            }
        }
    }
}

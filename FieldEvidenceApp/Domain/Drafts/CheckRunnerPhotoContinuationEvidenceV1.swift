import Foundation

/// The original raw publication followed by an authenticated, possibly
/// interrupted child commit. This is an observation, never effect authority.
/// Unlike the initial publication reader, it permits the recorded target to
/// have advanced the workflow and the physical stage to have been promoted.
struct CheckRunnerPhotoContinuationEvidenceV1: Equatable, Sendable {
    let parentCheckpoint: FieldDraftCheckpointV1
    let checkpoint: FieldDraftCheckpointV1
    let payload: CheckRunnerPhotoDraftPayloadV1
    let workflow: CheckRunnerBeginCommittedEvidenceV1
    let timeZone: CheckRunnerBeginCommittedEvidenceV1?
    let pending: FieldDraftCommittedEvidenceV1
    let creating: FieldDraftCommittedEvidenceV1
    let rawPublication: FieldDraftCommittedEvidenceV1
    let raw: CheckRunnerPhotoRawReadyV1
    let pairPublication: FieldDraftCommittedEvidenceV1?
    let committing: FieldDraftCommittedEvidenceV1?
    let target: CheckRunnerPhotoCommittedEvidenceV1?
    let terminal: CheckRunnerPhotoCommitEvidenceV1?
    let currentStage: AttachmentStagingItemV1
    let sagas: [DraftCommitSagaV1]
    let currentWorkflowPostImage: MutationPostImageV1

    init(parentHistory: [FieldDraftCommittedEvidenceV1], parentCheckpoint: FieldDraftCheckpointV1,
         workflow: CheckRunnerBeginCommittedEvidenceV1, timeZone: CheckRunnerBeginCommittedEvidenceV1?,
         history: [FieldDraftCommittedEvidenceV1], checkpoint: FieldDraftCheckpointV1,
         stages: [AttachmentStagingItemV1], sagas: [DraftCommitSagaV1],
         reservations: [DraftContentReservationV1], receipts: [DraftCommitReceiptV1],
         precedingWide: CheckRunnerPhotoParentEvidenceV1?, target: CheckRunnerPhotoCommittedEvidenceV1?,
         currentWorkflowPostImage: MutationPostImageV1, currentEvidencePostImage: MutationPostImageV1?) throws {
        let failure = WorkspaceMutationFailureV1.receiptHistoryCorrupt
        let parent = try CheckRunnerPhotoParentEvidenceV1.validateCheckpointHistory(
            history: parentHistory, checkpoint: parentCheckpoint, workflow: workflow, timeZone: timeZone)
        let payload = try CheckRunnerPhotoDraftCodecV1.validateCheckpoint(checkpoint)
        try payload.validate(parent: parent.parent, parentDraftID: parentCheckpoint.draftID)
        guard !history.isEmpty, Set(history.map { $0.mutation.mutationID }).count == history.count,
              stages.count == 1, let stage = stages.first else { throw failure }
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
        let checkpoints = history.compactMap { value -> (FieldDraftCommittedEvidenceV1, FieldDraftCheckpointV1)? in
            switch value.mutation.postImage {
            case let .createCheckpoint(cp), let .reviseCheckpoint(cp): return (value, cp)
            case let .publishReadyStage(bundle): return (value, bundle.successorCheckpoint)
            default: return nil
            }
        }.sorted { $0.1.draftRevision < $1.1.draftRevision }
        guard checkpoints.count >= 2, let first = checkpoints.first, let last = checkpoints.last,
              case .createCheckpoint = first.0.mutation.postImage,
              first.1.draftRevision == 1, first.0.mutation.expectedRevision == 0,
              case let .awaitingRawStage(intent) = try CheckRunnerPhotoDraftCodecV1.validateCheckpoint(first.1).phase,
              case let .publishReadyStage(publication) = checkpoints[1].0.mutation.postImage,
              case let .rawReady(raw) = try CheckRunnerPhotoDraftCodecV1.validateCheckpoint(checkpoints[1].1).phase,
              intent == raw.intent, publication.expectedCheckpoint == first.1,
              publication.readyItem == raw.readyItem,
              publication.mutationID == raw.stagePublicationMutationID,
              publication.successorCheckpoint.updatedAt == intent.stageCreatedAt else { throw failure }
        let initial = try CheckRunnerPhotoDraftCodecV1.validateCheckpoint(first.1)
        let expectedPublication = try FieldDraftStagePublicationBundleV1(expectedCheckpoint: first.1,
            readyItem: raw.readyItem, successorCheckpoint: checkpoints[1].1)
        guard publication == expectedPublication,
              checkpoints[1].0.mutation == (try FieldDraftMutationV1(workspaceID: checkpoint.workspaceID,
                expectedRevision: first.1.draftRevision, expectedBaseCanonicalRevision: first.1.baseCanonicalRevision,
                mutationID: raw.stagePublicationMutationID, postImage: .publishReadyStage(expectedPublication))) else { throw failure }

        let expectedPending = CheckRunnerPhotoSlotV1.pending(childDraftID: payload.childDraftID,
            captureStep: payload.captureStep, purposeKey: payload.purposeKey)
        var pending: FieldDraftCommittedEvidenceV1?
        for entry in parent.entries {
            let selected = payload.captureStep == .wide ? entry.payload.field.wideContext : entry.payload.field.closeDetail
            if pending == nil, selected?.childDraftID == payload.childDraftID {
                guard selected == expectedPending, case .bound = entry.payload.field.begin else { throw failure }
                try initial.validate(parent: entry.payload, parentDraftID: entry.checkpoint.draftID)
                try initial.validateRawStageIntent(parentSlotCheckpointUpdatedAt: entry.checkpoint.updatedAt)
                guard entry.checkpoint.updatedAt <= first.1.updatedAt else { throw failure }
                try CheckRunnerPhotoCommitEvidenceV1.requireOrder(entry.evidence.receipt, first.0.receipt)
                pending = entry.evidence
            }
            if pending != nil, checkpoint.state != .committed, selected != expectedPending { throw failure }
        }
        guard let pending else { throw failure }

        var previousRank = -1
        var pair: CheckRunnerPhotoPairReadyV1?
        var pairPublication: FieldDraftCommittedEvidenceV1?
        var committing: FieldDraftCommittedEvidenceV1?
        for (index, entry) in checkpoints.enumerated() {
            let value = try CheckRunnerPhotoDraftCodecV1.validateCheckpoint(entry.1)
            let sameIdentity = try CheckRunnerPhotoDraftPayloadV1(workspaceID: value.workspaceID,
                childDraftID: value.childDraftID, parentDraftID: value.parentDraftID,
                recordID: value.recordID, assetID: value.assetID, sourceBinding: value.sourceBinding,
                workflowStage: value.workflowStage, captureStep: value.captureStep,
                purposeKey: value.purposeKey, origin: value.origin, phase: initial.phase)
            guard sameIdentity == initial, entry.1.draftRevision == UInt64(index + 1),
                  entry.1.lastDurableMutationID == nil, entry.1.lastReceiptSHA256 == nil,
                  entry.0.mutation.mutationID == entry.1.mutationID,
                  entry.0.mutation.expectedRevision == entry.1.draftRevision - 1,
                  entry.0.mutation.expectedBaseCanonicalRevision == entry.1.baseCanonicalRevision else { throw failure }
            let rank: Int
            switch value.phase {
            case .awaitingRawStage: guard index == 0 else { throw failure }; rank = 0
            case let .rawReady(value): guard value == raw, index == 1 else { throw failure }; rank = 1
            case let .pairReady(value):
                guard value.raw == raw, pair.map({ $0 == value }) ?? true else { throw failure }
                pair = value; pairPublication = entry.0; rank = 2
            case let .preparedCommit(value, _):
                guard value == pair, index == checkpoints.count - 1, committing == nil else { throw failure }
                try value.validate(childDraftID: payload.childDraftID, parentDraftID: payload.parentDraftID)
                try value.raw.validate()
                try value.normalizedPair.validate()
                try CheckRunnerPhotoDraftCodecV1.validateCheckpoint(entry.1)
                    .validateCommitPreparation(pairReadyCheckpointUpdatedAt: checkpoints[index - 1].1.updatedAt)
                committing = entry.0; rank = 3
            }
            guard rank >= previousRank, rank <= previousRank + 1,
                  entry.1.state == (rank == 3 ? .committing : .active) else { throw failure }
            if index > 0 {
                try entry.1.validateSuccessor(of: checkpoints[index - 1].1,
                    expectedDraftRevision: checkpoints[index - 1].1.draftRevision,
                    expectedBaseRevision: checkpoints[index - 1].1.baseCanonicalRevision)
                try CheckRunnerPhotoCommitEvidenceV1.requireOrder(checkpoints[index - 1].0.receipt, entry.0.receipt)
                if index != 1, case .reviseCheckpoint = entry.0.mutation.postImage {} else if index != 1 { throw failure }
            }
            previousRank = rank
        }
        let workflowIdentity = try WorkspaceEntityIdentityV1(kind: .workflowRecord, id: payload.recordID)
        let priorReceipt: MutationReceiptV1
        switch payload.captureStep {
        case .wide:
            guard precedingWide == nil, parent.parent.field.closeDetail == nil else { throw failure }
            priorReceipt = workflow.receipt
        case .close:
            guard let precedingWide, precedingWide.checkpoint == parentCheckpoint,
                  precedingWide.slot == parent.parent.field.wideContext,
                  precedingWide.slot.captureStep == .wide,
                  precedingWide.child.target.command.draftID == payload.recordID,
                  precedingWide.child.target.command.nextDraftStepKey == WorkflowDraftStep.close.rawValue else { throw failure }
            priorReceipt = precedingWide.child.target.receipt
            try CheckRunnerPhotoCommitEvidenceV1.requireOrder(precedingWide.child.terminal.receipt, pending.receipt)
        default: throw failure
        }
        let priorImages = try priorReceipt.postImages.filter { try $0.identity == workflowIdentity }
        guard priorImages.count == 1, let priorImage = priorImages.first else { throw failure }
        let terminal: CheckRunnerPhotoCommitEvidenceV1?
        if checkpoint.state == .committed {
            guard let target else { throw failure }
            let value = try CheckRunnerPhotoCommitEvidenceV1(history: history, checkpoint: checkpoint,
                sagas: sagas, reservations: reservations, stages: stages, receipts: receipts, target: target)
            _ = try CheckRunnerPhotoParentEvidenceV1(history: parentHistory, checkpoint: parentCheckpoint,
                child: value, workflow: workflow, timeZone: timeZone)
            terminal = value
        } else {
            guard checkpoint == last.1, receipts.isEmpty else { throw failure }
            terminal = nil
        }
        if let committing {
            guard case let .reviseCheckpoint(original) = committing.mutation.postImage else { throw failure }
            let reconstruction = try CheckRunnerPhotoDraftCodecV1.reconstructPhotoCommit(from: original)
            let commit = reconstruction.draftCommit
            guard case let .preparedCommit(_, attempt) = payload.phase,
                  attempt.expectedWorkflowRecordRevision == priorImage.revision else { throw failure }
            if terminal == nil {
                try Self.validatePartialCommit(history: history, checkpoints: checkpoints.map { $0.0 },
                    committing: committing, reconstruction: reconstruction, raw: raw, attempt: attempt,
                    sagas: sagas, reservations: reservations, stage: stage, target: target)
            }
            if let target {
                guard target.command == reconstruction.targetCommand,
                      target.receipt.mutationID == commit.plan.mutationID,
                      target.envelope.expectedRevision.entityRevisions.filter({ $0.identity == workflowIdentity })
                        == [.init(identity: workflowIdentity, revision: priorImage.revision)] else { throw failure }
                try CheckRunnerPhotoCommitEvidenceV1.requireOrder(priorReceipt, target.receipt)
                let images = try target.receipt.postImages.filter { try $0.identity == workflowIdentity }
                let evidenceIdentity = try WorkspaceEntityIdentityV1(kind: .evidenceFile, id: payload.phase.intent.evidenceID)
                let evidenceImages = try target.receipt.postImages.filter { try $0.identity == evidenceIdentity }
                guard images == [currentWorkflowPostImage], let currentEvidencePostImage,
                      evidenceImages == [currentEvidencePostImage] else { throw failure }
            } else {
                guard currentWorkflowPostImage == priorImage, currentEvidencePostImage == nil else { throw failure }
            }
        } else {
            guard history.count == checkpoints.count, sagas.isEmpty, reservations.isEmpty,
                  target == nil, stage == raw.readyItem, currentEvidencePostImage == nil,
                  currentWorkflowPostImage == priorImage else { throw failure }
        }
        self.parentCheckpoint = parentCheckpoint; self.checkpoint = checkpoint; self.payload = payload
        self.workflow = workflow; self.timeZone = timeZone; self.pending = pending
        creating = first.0; rawPublication = checkpoints[1].0; self.raw = raw
        self.pairPublication = pairPublication; self.committing = committing; self.target = target
        self.terminal = terminal; currentStage = stage; self.currentWorkflowPostImage = currentWorkflowPostImage
        self.sagas = sagas.sorted { $0.revision < $1.revision }
    }

    /// Only exact retained prefixes of the incumbent five-saga commit may be
    /// recovered. Unknown effects and rows cannot become retry authority.
    private static func validatePartialCommit(history: [FieldDraftCommittedEvidenceV1],
        checkpoints: [FieldDraftCommittedEvidenceV1], committing: FieldDraftCommittedEvidenceV1,
        reconstruction: CheckRunnerPhotoCommitReconstructionV1, raw: CheckRunnerPhotoRawReadyV1,
        attempt: CheckRunnerPhotoCommitAttemptV1, sagas: [DraftCommitSagaV1],
        reservations: [DraftContentReservationV1], stage: AttachmentStagingItemV1,
        target: CheckRunnerPhotoCommittedEvidenceV1?) throws {
        let failure = WorkspaceMutationFailureV1.receiptHistoryCorrupt
        let commit = reconstruction.draftCommit
        let plan = commit.plan
        let ordered = sagas.sorted { $0.revision < $1.revision }
        guard ordered.count <= 4, ordered == Array(commit.sagas.prefix(ordered.count)),
              reservations.count <= 1 else { throw failure }
        var required = Set(checkpoints.map { $0.mutation.mutationID })
        func exact(_ mutation: FieldDraftMutationV1) throws -> FieldDraftCommittedEvidenceV1 {
            let matches = history.filter { $0.mutation.mutationID == mutation.mutationID }
            guard matches.count == 1, let match = matches.first, match.mutation == mutation,
                  required.insert(mutation.mutationID).inserted else { throw failure }
            return match
        }
        var sagaEvidence: [FieldDraftCommittedEvidenceV1] = []
        for (index, saga) in ordered.enumerated() {
            let value = try exact(.init(workspaceID: plan.workspaceID, expectedRevision: UInt64(index),
                expectedBaseCanonicalRevision: plan.baseCanonicalRevision, mutationID: saga.mutationID,
                postImage: index == 0 ? .appendCommitSaga(saga) : .advanceCommitSaga(saga)))
            try CheckRunnerPhotoCommitEvidenceV1.requireOrder(sagaEvidence.last?.receipt ?? committing.receipt, value.receipt)
            sagaEvidence.append(value)
        }
        if let reservation = reservations.first {
            guard !sagaEvidence.isEmpty, reservation == (try Self.reservation(raw: raw, plan: plan, attempt: attempt)) else { throw failure }
            let value = try exact(.init(workspaceID: plan.workspaceID, expectedRevision: 0,
                expectedBaseCanonicalRevision: 0, mutationID: reservation.mutationID,
                postImage: .appendContentReservation(reservation)))
            try CheckRunnerPhotoCommitEvidenceV1.requireOrder(sagaEvidence[0].receipt, value.receipt)
            if sagaEvidence.count > 1 { try CheckRunnerPhotoCommitEvidenceV1.requireOrder(value.receipt, sagaEvidence[1].receipt) }
        } else if sagaEvidence.count > 1 { throw failure }
        if stage != raw.readyItem {
            guard !sagaEvidence.isEmpty, stage == (try Self.committedStage(raw: raw, attempt: attempt)) else { throw failure }
            let value = try exact(.init(workspaceID: plan.workspaceID, expectedRevision: raw.readyItem.revision,
                expectedBaseCanonicalRevision: 0, mutationID: stage.mutationID, postImage: .reviseStagingItem(stage)))
            try CheckRunnerPhotoCommitEvidenceV1.requireOrder(sagaEvidence[0].receipt, value.receipt)
        }
        if let target {
            guard sagaEvidence.count >= 2 else { throw failure }
            try CheckRunnerPhotoCommitEvidenceV1.requireOrder(sagaEvidence[1].receipt, target.receipt)
            if sagaEvidence.count > 2 { try CheckRunnerPhotoCommitEvidenceV1.requireOrder(target.receipt, sagaEvidence[2].receipt) }
        } else if sagaEvidence.count > 2 { throw failure }
        guard required == Set(history.map { $0.mutation.mutationID }) else { throw failure }
    }

    static func reservation(raw: CheckRunnerPhotoRawReadyV1, plan: DraftCommitPlanV1,
                            attempt: CheckRunnerPhotoCommitAttemptV1) throws -> DraftContentReservationV1 {
        let request = try DraftImmutableContentWriteRequestV1(workspaceID: plan.workspaceID,
            contentID: raw.inspection.rawContentID, digest: raw.inspection.sourceSHA256,
            byteLength: raw.inspection.sourceByteCount, mediaType: raw.inspection.sourceMediaType,
            mutationID: attempt.reservationMutationID,
            createdAt: CheckRunnerPhotoRawReadyV1.formatOriginalRecordedAt(attempt.promotionAt))
        return try .init(reservationID: DraftAttachmentStagingAdapterV1.deterministicUUID(
            "reservation\u{1f}\(plan.planSHA256)\u{1f}\(raw.readyItem.stageID.uuidString.lowercased())"),
            workspaceID: plan.workspaceID, draftID: plan.draftID, stageID: raw.readyItem.stageID,
            commitPlanSHA256: plan.planSHA256, mutationID: attempt.reservationMutationID,
            contentDigest: raw.inspection.sourceSHA256,
            locator: .init(locatorID: request.locatorID, workspaceID: plan.workspaceID.rawValue.uuidString.lowercased(),
                contentID: raw.inspection.rawContentID, locatorRevision: 0, contentDigest: raw.inspection.sourceSHA256,
                expectedByteLength: raw.inspection.sourceByteCount), createdAt: attempt.promotionAt,
            reviewAfter: attempt.reservationReviewAfter, reconciliationState: .reserved,
            revision: 1)
    }

    static func committedStage(raw: CheckRunnerPhotoRawReadyV1,
                               attempt: CheckRunnerPhotoCommitAttemptV1) throws -> AttachmentStagingItemV1 {
        let ready = raw.readyItem
        let reference = try ContentReferenceV1(workspaceID: ready.workspaceID.rawValue.uuidString.lowercased(),
            contentID: raw.inspection.rawContentID, byteLength: raw.inspection.sourceByteCount,
            mediaType: raw.inspection.sourceMediaType, digests: .init([raw.inspection.sourceSHA256]),
            byteRole: .immutableOriginal, createdAt: CheckRunnerPhotoRawReadyV1.formatOriginalRecordedAt(attempt.promotionAt))
        return try .init(stageID: ready.stageID, draftID: ready.draftID, workspaceID: ready.workspaceID,
            attachmentKind: ready.attachmentKind, scratchLeaseID: ready.scratchLeaseID,
            expectedByteCount: ready.expectedByteCount, actualByteCount: ready.actualByteCount,
            contentDigest: ready.contentDigest, contentReference: reference, processingJobID: ready.processingJobID,
            retryClass: ready.retryClass, state: .committed, protectionState: ready.protectionState,
            revision: ready.revision + 1, mutationID: .init(rawValue: DraftAttachmentStagingAdapterV1.deterministicUUID(
                "stage-mutation\u{1f}\(ready.stageID.uuidString.lowercased())\u{1f}\(ready.revision + 1)\u{1f}COMMITTED\u{1f}\(raw.inspection.sourceSHA256.hexadecimalValue)")))
    }
}

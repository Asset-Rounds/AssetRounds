import Foundation

/// Authenticated frontier before the child exists. Proposed capture values do
/// not replace the parent, Begin receipts or current workflow originals.
struct CheckRunnerPhotoPreparationEvidenceV1: Equatable, Sendable {
    let parentCheckpoint: FieldDraftCheckpointV1
    let workflow: CheckRunnerBeginCommittedEvidenceV1
    let timeZone: CheckRunnerBeginCommittedEvidenceV1?
    let currentWorkflowPostImage: MutationPostImageV1
    let precedingWide: CheckRunnerPhotoCurrentTargetEvidenceV1?

    init(parentHistory: [FieldDraftCommittedEvidenceV1], parentCheckpoint: FieldDraftCheckpointV1,
         workflow: CheckRunnerBeginCommittedEvidenceV1, timeZone: CheckRunnerBeginCommittedEvidenceV1?,
         currentWorkflowPostImage: MutationPostImageV1,
         precedingWide: CheckRunnerPhotoCurrentTargetEvidenceV1?, captureStep: WorkflowDraftStep) throws {
        let failure = WorkspaceMutationFailureV1.receiptHistoryCorrupt
        let parent = try CheckRunnerPhotoParentEvidenceV1.validateCheckpointHistory(
            history: parentHistory, checkpoint: parentCheckpoint, workflow: workflow, timeZone: timeZone).parent
        guard let attempt = parent.field.begin.attempt else { throw failure }
        let identity = try WorkspaceEntityIdentityV1(kind: .workflowRecord, id: attempt.recordCommand.recordID)
        guard try currentWorkflowPostImage.identity == identity else { throw failure }
        switch captureStep {
        case .wide:
            let images = try workflow.receipt.postImages.filter { try $0.identity == identity }
            guard precedingWide == nil, parent.field.closeDetail == nil,
                  images.count == 1, images[0] == currentWorkflowPostImage,
                  currentWorkflowPostImage.revision == 1 else { throw failure }
        case .close:
            guard let precedingWide, let slot = parent.field.wideContext,
                  precedingWide.parent.checkpoint == parentCheckpoint,
                  precedingWide.parent.slot == slot, slot.captureStep == .wide,
                  precedingWide.workflow.id == attempt.recordCommand.recordID,
                  precedingWide.workflow.draftStepKey == WorkflowDraftStep.close.rawValue,
                  precedingWide.workflowPostImage == currentWorkflowPostImage,
                  precedingWide.laterPhotos.isEmpty, precedingWide.finalization == nil else { throw failure }
        default: throw failure
        }
        self.parentCheckpoint = parentCheckpoint; self.workflow = workflow; self.timeZone = timeZone
        self.currentWorkflowPostImage = currentWorkflowPostImage; self.precedingWide = precedingWide
    }
}

/// Original pending-slot and initial raw-publication history. These values are
/// observations only; the application must repeat the live source, access,
/// writer and physical-owner checks before performing a publication.
struct CheckRunnerPhotoRawStageEvidenceV1: Equatable, Sendable {
    let parentCheckpoint: FieldDraftCheckpointV1
    let pendingParent: FieldDraftCommittedEvidenceV1
    let creating: FieldDraftCommittedEvidenceV1
    let expectedCheckpoint: FieldDraftCheckpointV1
    let currentCheckpoint: FieldDraftCheckpointV1
    let initialPayload: CheckRunnerPhotoDraftPayloadV1
    let workflow: CheckRunnerBeginCommittedEvidenceV1
    let timeZone: CheckRunnerBeginCommittedEvidenceV1?
    let currentWorkflowPostImage: MutationPostImageV1
    let precedingWide: CheckRunnerPhotoCurrentTargetEvidenceV1?
    let publication: FieldDraftCommittedEvidenceV1?
    let rawReady: CheckRunnerPhotoRawReadyV1?

    init(parentHistory: [FieldDraftCommittedEvidenceV1], parentCheckpoint: FieldDraftCheckpointV1,
         workflow: CheckRunnerBeginCommittedEvidenceV1, timeZone: CheckRunnerBeginCommittedEvidenceV1?,
         childHistory: [FieldDraftCommittedEvidenceV1], childCheckpoint: FieldDraftCheckpointV1,
         currentStage: AttachmentStagingItemV1?, currentWorkflowPostImage: MutationPostImageV1,
         precedingWide: CheckRunnerPhotoCurrentTargetEvidenceV1?) throws {
        let failure = WorkspaceMutationFailureV1.receiptHistoryCorrupt
        let parent = try CheckRunnerPhotoParentEvidenceV1.validateCheckpointHistory(
            history: parentHistory, checkpoint: parentCheckpoint, workflow: workflow, timeZone: timeZone)
        guard (1...2).contains(childHistory.count),
              Set(childHistory.map { $0.mutation.mutationID }).count == childHistory.count else { throw failure }
        let ordered = childHistory.sorted { $0.mutation.expectedRevision < $1.mutation.expectedRevision }
        let creating = ordered[0]
        guard case let .createCheckpoint(initial) = creating.mutation.postImage,
              initial.state == .active, initial.draftRevision == 1,
              creating.mutation.expectedRevision == 0,
              creating.mutation.expectedBaseCanonicalRevision == initial.baseCanonicalRevision,
              creating.mutation.workspaceID == initial.workspaceID,
              initial.mutationID == creating.mutation.mutationID else { throw failure }
        let photo = try CheckRunnerPhotoDraftCodecV1.validateCheckpoint(initial)
        guard case .awaitingRawStage = photo.phase else { throw failure }
        try photo.validate(parent: parent.parent, parentDraftID: parentCheckpoint.draftID)
        let slot = CheckRunnerPhotoSlotV1.pending(childDraftID: photo.childDraftID,
            captureStep: photo.captureStep, purposeKey: photo.purposeKey)
        let currentSlot = photo.captureStep == .wide
            ? parent.parent.field.wideContext : parent.parent.field.closeDetail
        guard currentSlot == slot else { throw failure }
        var pending: FieldDraftCommittedEvidenceV1?
        for entry in parent.entries {
            let selected = photo.captureStep == .wide
                ? entry.payload.field.wideContext : entry.payload.field.closeDetail
            if pending == nil, selected?.childDraftID == photo.childDraftID {
                guard selected == slot, case .bound = entry.payload.field.begin else { throw failure }
                try photo.validate(parent: entry.payload, parentDraftID: entry.checkpoint.draftID)
                try photo.validateRawStageIntent(parentSlotCheckpointUpdatedAt: entry.checkpoint.updatedAt)
                guard entry.checkpoint.updatedAt <= initial.updatedAt else { throw failure }
                try CheckRunnerPhotoCommitEvidenceV1.requireOrder(entry.evidence.receipt, creating.receipt)
                pending = entry.evidence
            }
            if pending != nil, selected != slot { throw failure }
        }
        guard let pending, let begin = parent.parent.field.begin.attempt else { throw failure }
        let workflowIdentity = try WorkspaceEntityIdentityV1(kind: .workflowRecord, id: photo.recordID)
        guard try currentWorkflowPostImage.identity == workflowIdentity else { throw failure }
        switch photo.captureStep {
        case .wide:
            let images = try workflow.receipt.postImages.filter { try $0.identity == workflowIdentity }
            guard precedingWide == nil, parent.parent.field.closeDetail == nil,
                  images.count == 1, images[0] == currentWorkflowPostImage,
                  currentWorkflowPostImage.revision == 1 else { throw failure }
        case .close:
            guard let precedingWide, let wideSlot = parent.parent.field.wideContext,
                  precedingWide.parent.checkpoint == parentCheckpoint,
                  precedingWide.parent.slot == wideSlot,
                  precedingWide.parent.slot.captureStep == .wide,
                  precedingWide.workflow.id == photo.recordID,
                  precedingWide.workflow.draftStepKey == WorkflowDraftStep.close.rawValue,
                  precedingWide.workflowPostImage == currentWorkflowPostImage,
                  precedingWide.laterPhotos.isEmpty, precedingWide.finalization == nil else { throw failure }
        default:
            throw failure
        }
        guard begin.recordCommand.recordID == photo.recordID else { throw failure }

        let publication: FieldDraftCommittedEvidenceV1?
        let rawReady: CheckRunnerPhotoRawReadyV1?
        if ordered.count == 1 {
            guard childCheckpoint == initial, currentStage == nil else { throw failure }
            publication = nil
            rawReady = nil
        } else {
            let evidence = ordered[1]
            guard case let .publishReadyStage(bundle) = evidence.mutation.postImage,
                  case let .rawReady(raw) = try CheckRunnerPhotoDraftCodecV1.validateCheckpoint(
                    bundle.successorCheckpoint).phase else { throw failure }
            let expected = try Self.publicationBundle(expectedCheckpoint: initial, payload: photo, raw: raw)
            let mutation = try FieldDraftMutationV1(workspaceID: expected.workspaceID,
                expectedRevision: initial.draftRevision,
                expectedBaseCanonicalRevision: initial.baseCanonicalRevision,
                mutationID: expected.mutationID, postImage: .publishReadyStage(expected))
            guard bundle == expected, evidence.mutation == mutation,
                  childCheckpoint == expected.successorCheckpoint, currentStage == raw.readyItem else { throw failure }
            try CheckRunnerPhotoCommitEvidenceV1.requireOrder(creating.receipt, evidence.receipt)
            publication = evidence
            rawReady = raw
        }
        self.parentCheckpoint = parentCheckpoint; pendingParent = pending
        self.creating = creating; expectedCheckpoint = initial; currentCheckpoint = childCheckpoint
        initialPayload = photo; self.workflow = workflow; self.timeZone = timeZone
        self.currentWorkflowPostImage = currentWorkflowPostImage; self.precedingWide = precedingWide
        self.publication = publication
        self.rawReady = rawReady
    }

    func publicationBundle(raw: CheckRunnerPhotoRawReadyV1) throws -> FieldDraftStagePublicationBundleV1 {
        try Self.publicationBundle(expectedCheckpoint: expectedCheckpoint, payload: initialPayload, raw: raw)
    }

    private static func publicationBundle(expectedCheckpoint: FieldDraftCheckpointV1,
        payload: CheckRunnerPhotoDraftPayloadV1, raw: CheckRunnerPhotoRawReadyV1) throws
        -> FieldDraftStagePublicationBundleV1 {
        try raw.validate()
        guard raw.intent == payload.phase.intent,
              raw.readyItem.workspaceID == payload.workspaceID,
              raw.readyItem.draftID == payload.childDraftID,
              raw.originalProvenance.origin == payload.origin else { throw FieldDraftFailureV1.digestMismatch }
        let successor = try CheckRunnerPhotoDraftPayloadV1(workspaceID: payload.workspaceID,
            childDraftID: payload.childDraftID, parentDraftID: payload.parentDraftID,
            recordID: payload.recordID, assetID: payload.assetID, sourceBinding: payload.sourceBinding,
            workflowStage: payload.workflowStage, captureStep: payload.captureStep,
            purposeKey: payload.purposeKey, origin: payload.origin, phase: .rawReady(raw))
        let checkpoint = try FieldDraftCheckpointV1(draftID: expectedCheckpoint.draftID,
            workspaceID: expectedCheckpoint.workspaceID, scope: expectedCheckpoint.scope,
            purpose: expectedCheckpoint.purpose, codec: expectedCheckpoint.codec,
            baseCanonicalRevision: expectedCheckpoint.baseCanonicalRevision,
            draftRevision: expectedCheckpoint.draftRevision + 1,
            payloadData: CheckRunnerPhotoDraftCodecV1.encode(successor), stageIDs: successor.phase.declaredStageIDs,
            resumeAnchor: CheckRunnerPhotoDraftCodecV1.resumeAnchor(payload: successor), state: .active,
            updatedAt: raw.intent.stageCreatedAt, mutationID: raw.stagePublicationMutationID)
        return try .init(expectedCheckpoint: expectedCheckpoint, readyItem: raw.readyItem,
                         successorCheckpoint: checkpoint)
    }
}

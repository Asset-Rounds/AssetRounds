import Foundation

protocol PlanOfflineWorkSourceResolvingV1: Sendable {
    func source(for request: PlanOfflineWorkRequestV1) async throws -> PlanOfflineWorkSourceV1
}

/// C19 application assembler. It owns no persistence and delegates every
/// canonical effect to the incumbent plan or universal-draft coordinator.
@MainActor
final class PlanOfflineWorkCoordinatorV1 {
    private let sourceResolver: any PlanOfflineWorkSourceResolvingV1
    private let planCoordinator: PlanRebaseCoordinatorV1
    private let draftCoordinator: FieldDraftCoordinatorV1

    init(sourceResolver: any PlanOfflineWorkSourceResolvingV1,
         planCoordinator: PlanRebaseCoordinatorV1,
         draftCoordinator: FieldDraftCoordinatorV1) {
        self.sourceResolver = sourceResolver
        self.planCoordinator = planCoordinator
        self.draftCoordinator = draftCoordinator
    }

    func readiness(for request: PlanOfflineWorkRequestV1) async throws -> OfflineWorkPacketReadinessV1 {
        let source = try await sourceResolver.source(for: request)
        return try OfflineWorkPacketReadinessV1(source: source)
    }

    func workSurface(for request: PlanOfflineWorkRequestV1,
                     selectedPageID: UUID,
                     selectedPlacementID: UUID?,
                     viewport: PlanViewportPresentationV1,
                     resumeDraft: FieldDraftReferenceProjectionV1?,
                     materializedPoseSnapshots: [PlanMaterializedPoseSnapshotV1],
                     evaluatedAt: Date) async throws -> PlanWorkSurfaceStateV1 {
        let source = try await sourceResolver.source(for: request)
        return try PlanWorkSurfaceStateV1(
            source: source, selectedPageID: selectedPageID,
            selectedPlacementID: selectedPlacementID, viewport: viewport,
            resumeDraft: resumeDraft, poseSnapshots: materializedPoseSnapshots,
            evaluatedAt: evaluatedAt
        )
    }

    func checkpoint(_ value: FieldDraftCheckpointV1,
                    expectedDraftRevision: UInt64,
                    expectedBaseRevision: UInt64) throws -> MutationReceiptV1 {
        try draftCoordinator.checkpoint(
            value, expectedDraftRevision: expectedDraftRevision,
            expectedBaseRevision: expectedBaseRevision
        )
    }

    func appendPlacement(_ value: PlanPlacementV1,
                         predecessor: PlanPlacementV1?,
                         planRevision: PlanRevisionV1,
                         prerequisites: PlanPrerequisiteClosureV1) throws -> MutationReceiptV1 {
        try planCoordinator.appendPlacement(
            value, predecessor: predecessor, planRevision: planRevision,
            prerequisites: prerequisites
        )
    }

    func previewRebase(previewID: UUID, workspaceID: WorkspaceID,
                       oldRevision: PlanRevisionV1, newRevision: PlanRevisionV1,
                       transform: PlanAffineTransformV1, placements: [PlanPlacementV1],
                       oldPrerequisites: PlanPrerequisiteClosureV1,
                       newPrerequisites: PlanPrerequisiteClosureV1,
                       expectedRevision: UInt64, generatedAt: Date) throws -> RebaseReviewStateV1 {
        let preview = try planCoordinator.preview(
            previewID: previewID, workspaceID: workspaceID,
            oldRevision: oldRevision, newRevision: newRevision,
            transform: transform, placements: placements,
            oldPrerequisites: oldPrerequisites, newPrerequisites: newPrerequisites,
            expectedRevision: expectedRevision, generatedAt: generatedAt
        )
        return try .pending(preview: preview, evaluatedAt: generatedAt)
    }

    func approveRebase(preview: RebasePreviewV1,
                       newRevision: PlanRevisionV1,
                       predecessorRevision: PlanRevisionV1,
                       placements: [PlanPlacementV1],
                       predecessorPlacements: [PlanPlacementV1],
                       receiptID: UUID,
                       prerequisites: PlanPrerequisiteClosureV1,
                       predecessorReceipt: RebaseReceiptV1?,
                       mutationID: MutationIDV1,
                       reviewedBy: ActorSnapshotV1,
                       recordedAt: Date,
                       poseEffects: PlacementPoseMutationV1?) throws -> PlanRebaseApprovalOutcomeV1 {
        try planCoordinator.approve(
            preview: preview, newRevision: newRevision,
            predecessorRevision: predecessorRevision, placements: placements,
            predecessorPlacements: predecessorPlacements, receiptID: receiptID,
            prerequisites: prerequisites, predecessorReceipt: predecessorReceipt,
            mutationID: mutationID, reviewedBy: reviewedBy, recordedAt: recordedAt,
            poseEffects: poseEffects
        )
    }

    func rejectRebase(preview: RebasePreviewV1, receiptID: UUID,
                      predecessorReceipt: RebaseReceiptV1?, mutationID: MutationIDV1,
                      reviewedBy: ActorSnapshotV1,
                      recordedAt: Date) throws -> PlanRebaseRejectionOutcomeV1 {
        try planCoordinator.reject(
            preview: preview, receiptID: receiptID,
            predecessorReceipt: predecessorReceipt, mutationID: mutationID,
            reviewedBy: reviewedBy, recordedAt: recordedAt
        )
    }

    func reviewState(preview: RebasePreviewV1, receipt: RebaseReceiptV1?,
                     evaluatedAt: Date) throws -> RebaseReviewStateV1 {
        try .init(preview: preview, receipt: receipt, evaluatedAt: evaluatedAt)
    }
}

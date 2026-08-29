import Foundation

protocol PlanRebaseReceiptRecoveringV1: Sendable {
    func acceptedPlanMutationReceipt(mutationID: MutationIDV1) throws -> MutationReceiptV1?
}

@MainActor
final class PlanLifecycleAdapterV1 {
    enum RecoveryDisposition: Equatable, Sendable {
        case retryRequired
        case accepted(MutationReceiptV1)
    }

    private let coordinator: PlanRebaseCoordinatorV1
    private let recovery: any PlanRebaseReceiptRecoveringV1

    init(coordinator: PlanRebaseCoordinatorV1,
         recovery: any PlanRebaseReceiptRecoveringV1) {
        self.coordinator = coordinator
        self.recovery = recovery
    }

    func preview(previewID: UUID, workspaceID: WorkspaceID,
                 oldRevision: PlanRevisionV1, newRevision: PlanRevisionV1,
                 transform: PlanAffineTransformV1, placements: [PlanPlacementV1],
                 oldPrerequisites: PlanPrerequisiteClosureV1,
                 newPrerequisites: PlanPrerequisiteClosureV1,
                 expectedRevision: UInt64, generatedAt: Date) throws -> RebasePreviewV1 {
        try coordinator.preview(previewID: previewID, workspaceID: workspaceID,
                                oldRevision: oldRevision, newRevision: newRevision,
                                transform: transform, placements: placements,
                                oldPrerequisites: oldPrerequisites,
                                newPrerequisites: newPrerequisites,
                                expectedRevision: expectedRevision, generatedAt: generatedAt)
    }

    func recover(mutationID: MutationIDV1) throws -> RecoveryDisposition {
        if let receipt = try recovery.acceptedPlanMutationReceipt(mutationID: mutationID) {
            return .accepted(receipt)
        }
        return .retryRequired
    }

    func approve(preview: RebasePreviewV1, newRevision: PlanRevisionV1,
                 predecessorRevision: PlanRevisionV1, placements: [PlanPlacementV1],
                 predecessorPlacements: [PlanPlacementV1], receiptID: UUID,
                 prerequisites: PlanPrerequisiteClosureV1,
                 predecessorReceipt: RebaseReceiptV1?, mutationID: MutationIDV1,
                 reviewedBy: ActorSnapshotV1, recordedAt: Date) throws
        -> PlanRebaseApprovalOutcomeV1 {
        try coordinator.approve(preview: preview, newRevision: newRevision,
                                predecessorRevision: predecessorRevision,
                                placements: placements,
                                predecessorPlacements: predecessorPlacements,
                                receiptID: receiptID, prerequisites: prerequisites,
                                predecessorReceipt: predecessorReceipt,
                                mutationID: mutationID, reviewedBy: reviewedBy,
                                recordedAt: recordedAt)
    }

    func reject(preview: RebasePreviewV1, receiptID: UUID,
                predecessorReceipt: RebaseReceiptV1?, mutationID: MutationIDV1,
                reviewedBy: ActorSnapshotV1, recordedAt: Date) throws
        -> PlanRebaseRejectionOutcomeV1 {
        try coordinator.reject(preview: preview, receiptID: receiptID,
                               predecessorReceipt: predecessorReceipt,
                               mutationID: mutationID, reviewedBy: reviewedBy,
                               recordedAt: recordedAt)
    }
}

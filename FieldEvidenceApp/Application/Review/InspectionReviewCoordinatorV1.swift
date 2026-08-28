import Foundation

@MainActor final class InspectionReviewCoordinatorV1 {
    private let writer: WorkspaceWriterV1
    private let lifecycle: InspectionReviewLifecycleAdapterV1
    init(writer: WorkspaceWriterV1, lifecycle: InspectionReviewLifecycleAdapterV1) { self.writer = writer; self.lifecycle = lifecycle }

    func apply(_ mutation: InspectionReviewMutationV1) throws -> InspectionReviewMutationReceiptV1 {
        try mutation.validate()
        _ = try writer.execute(.applyInspectionReview(mutation), mutationID: mutation.mutationID)
        guard let receipt = try writer.durableReceipt(mutationID: mutation.mutationID) else { throw WorkspaceMutationFailureV1.invalidReceipt }
        return try InspectionReviewMutationReceiptV1(mutation: mutation, mutationReceipt: receipt)
    }

    func reviewProjection(workspaceID: WorkspaceID, reviewID: UUID) throws -> InspectionReviewProjectionV1 { try lifecycle.reviewProjection(workspaceID: workspaceID, reviewID: reviewID) }
    func correctiveActionProjection(workspaceID: WorkspaceID, actionID: UUID, now: Date) throws -> CorrectiveActionProjectionV1 { try lifecycle.correctiveActionProjection(workspaceID: workspaceID, actionID: actionID, now: now) }
}

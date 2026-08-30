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
    func portableReviewBasis(mapping:ReviewRequestC14SubjectItemMappingV1,reviewID:UUID)throws->InspectionReviewProjectionV1{try lifecycle.portableReviewBasis(mapping:mapping,reviewID:reviewID)}
}

// MARK: - C49 work-resource review projection coordinator

extension InspectionReviewCoordinatorV1 {
    nonisolated static func workResourceReport(
        subject: WorkResourceSubjectV1,
        snapshots: [WorkResourceSnapshotV1],
        includeDirectCostPreview: Bool = false
    ) throws -> C49WorkResourceReportProjectionV1 {
        try C49WorkResourceInspectionReviewBoundaryV1.report(
            subject: subject,
            snapshots: snapshots,
            includeDirectCostPreview: includeDirectCostPreview
        )
    }
}

enum C49WorkResourceInspectionReviewCoordinatorBoundaryV1 {
    static let reportProjectionIsReadOnly = true
    static let writerRemainsCanonicalMutationRoute = true
    static let reviewDoesNotInferInventoryOrApproval = true
}

// MARK: - C50 incumbent file-exchange coordinator boundary

/// C50 exchange work is preview-only at this boundary. Any accepted review
/// mutation is still routed through the existing C14 writer; the coordinator
/// receives no source/session bytes and does not select a provider implicitly.
enum C50InspectionReviewIncumbentCoordinatorBoundaryV1 {
    static let adapterContract: Any.Type = IncumbentFileAdapterV1.self
    static let selectionReceiptContract: Any.Type = IncumbentSelectionReceiptV1.self
    static let exchangeReceiptContract: Any.Type = IncumbentFileExchangeReceiptV1.self
    static let quarantineReceiptContract: Any.Type = IncumbentFileQuarantineReceiptV1.self
    static let previewIsZeroWrite = true
    static let allowlistIsRequiredBeforeReview = true
    static let quarantineIsRequiredBeforeReview = true
    static let sourceBytesConsumed = false
    static let sessionBytesConsumed = false
    static let providerStateConsumed = false
    static let reviewCoordinatorIsNotAnImportWriter = true
    static let existingReviewWriterRemainsSoleMutationRoute = true
    static let disabledProfileHasNoIntegrationClaim = true

    static func validateProjection(_ projection: InspectionReviewProjectionV1) throws {
        try InspectionReviewValidationV1.workspace(projection.workspaceID)
        try InspectionReviewValidationV1.id(projection.reviewID)
        try InspectionReviewValidationV1.revision(projection.revision)
        try InspectionReviewValidationV1.id(projection.headTransitionID)
        try projection.openChangeRequests.forEach { try $0.validate() }
    }
}

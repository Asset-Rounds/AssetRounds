import Foundation

@MainActor
final class FunctionalRelationshipCoordinatorV1 {
    private let writer: WorkspaceWriterV1
    private let lifecycle: FunctionalRelationshipLifecycleAdapterV1

    init(writer: WorkspaceWriterV1, lifecycle: FunctionalRelationshipLifecycleAdapterV1) {
        self.writer = writer; self.lifecycle = lifecycle
    }

    func apply(_ mutation: FunctionalRelationshipMutationV1) throws -> FunctionalRelationshipMutationReceiptV1 {
        try mutation.validate()
        _ = try writer.execute(.applyFunctionalRelationship(mutation), mutationID: mutation.mutationID)
        guard let receipt = try writer.durableReceipt(mutationID: mutation.mutationID) else {
            throw WorkspaceMutationFailureV1.invalidReceipt
        }
        return try FunctionalRelationshipMutationReceiptV1(mutation: mutation, mutationReceipt: receipt)
    }

    func projection(
        workspaceID: WorkspaceID,
        boundary: FunctionalRelationshipReadinessBoundaryV1? = nil
    ) throws -> CurrentFunctionalRelationshipProjectionV1 {
        try lifecycle.projection(workspaceID: workspaceID, boundary: boundary)
    }

    func preview(
        change: FunctionalRelationshipEndpointChangeV1,
        relationshipID: UUID,
        workspaceID: WorkspaceID,
        currentSiteID: UUID,
        proposedSiteID: UUID? = nil
    ) throws -> FunctionalRelationshipDispositionPreviewV1 {
        try lifecycle.preview(change: change, relationshipID: relationshipID, workspaceID: workspaceID,
                              currentSiteID: currentSiteID, proposedSiteID: proposedSiteID)
    }
}

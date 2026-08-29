import Foundation

/// Existing-workspace-writer bridge. It owns no second store, evaluator,
/// measurement converter, topology projection, or receipt authority.
@MainActor
protocol LightingCanonicalWorkspaceWritingV1: AnyObject {
    func commitLighting(_ operation: LightingWriteOperationV1) throws -> MutationReceiptV1
}

@MainActor
final class LightingLifecycleAdapterV1: LightingMutationAuthorityV1 {
    private let writer: any LightingCanonicalWorkspaceWritingV1
    init(writer: any LightingCanonicalWorkspaceWritingV1) { self.writer = writer }
    func commit(_ operation: LightingWriteOperationV1) async throws -> MutationReceiptV1 {
        try operation.validate()
        let receipt = try writer.commitLighting(operation)
        try receipt.validate()
        guard receipt.identity.workspaceID == operation.workspaceID,
              receipt.mutationID == operation.mutationID else {
            throw LightingContractFailureV1.staleReference
        }
        return receipt
    }
}

import Foundation

/// C13 exposes deterministic review material only.  A caller must explicitly
/// choose an action and then submit a fully bound canonical command; preview
/// never allocates a mutation ID or writes a durable row.
@MainActor
final class EntityIdentityResolutionCoordinatorV1 {
    private let writer: WorkspaceWriterV1

    init(writer: WorkspaceWriterV1) {
        self.writer = writer
    }

    func preview(
        _ plan: EntityIdentityResolutionPlanV1
    ) throws -> EntityIdentityResolutionPlanV1 {
        try plan.validate()
        guard plan.workspaceID == (try writer.currentRevision()).workspaceID else {
            throw EntityIdentityResolutionFailureV1.wrongWorkspace
        }
        return plan
    }

    /// The only canonical action path.  There is deliberately no overload
    /// accepting a preview, candidate list, or inferred decision.
    func commit(
        _ command: EntityIdentityResolutionMutationCommandV1
    ) throws -> EntityIdentityResolutionMutationReceiptV1 {
        try writer.commitEntityIdentityResolution(command)
    }
}

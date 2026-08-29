import Foundation

/// Sole-writer bridge. It owns no store, network client, solar provider, or
/// current-state cache; retry and receipt publication remain writer concerns.
@MainActor
protocol EvidenceContextCanonicalWorkspaceWritingV1: AnyObject {
    func commitEvidenceContext(_ operation: EvidenceContextWriteOperationV1) throws -> MutationReceiptV1
}

@MainActor
final class EvidenceContextLifecycleAdapterV1: EvidenceContextMutationAuthorityV1 {
    private let writer: any EvidenceContextCanonicalWorkspaceWritingV1

    init(writer: any EvidenceContextCanonicalWorkspaceWritingV1) {
        self.writer = writer
    }

    func commit(_ operation: EvidenceContextWriteOperationV1) async throws -> MutationReceiptV1 {
        try operation.validate()
        let receipt = try writer.commitEvidenceContext(operation)
        try receipt.validate()
        guard receipt.identity.workspaceID == operation.workspaceID,
              receipt.mutationID == operation.mutationID else {
            throw EvidenceContextFailureV1.referenceMismatch
        }
        return receipt
    }
}

enum C31LightingConsumerBoundary_Infrastructure_EvidenceContext_EvidenceContextLifecycleAdapterV1 {
    static let registrationID = "C31_LIGHTING_CONSUMER/evidence-context-lifecycle-adapter"
    static let compatibility = C31LightingCompatibilityPolicyV1()
    static func validate(projection: C31LightingReportProjectionV1) throws {
        try compatibility.validate()
        try C31LightingProjectionPolicyV1.validate(projection)
    }
}

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

/// C32 keeps assistance candidates outside every durable and derived surface;
/// only explicit acceptance may reach the existing canonical writer/receipt path.
enum C32AssistanceCompatibility_Lighting_LightingLifecycleAdapterV1 {
    enum ProposalDispositionV1: Sendable {
        case nonpersistentUnverifiedExcludedFromStorageSearchReportBackup
    }

    enum AcceptanceDispositionV1: Sendable {
        case durableThroughExistingCanonicalWriter
    }

    static func disposition(
        for proposal: AssistanceProposalV1
    ) throws -> ProposalDispositionV1 {
        try proposal.validate()
        guard !AssistancePersistenceEnrollmentV1.proposalIsPersistent,
              !AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent else {
            throw AssistanceContractFailureV1.nonCanonicalData
        }
        switch proposal.verificationState {
        case .unverified:
            return .nonpersistentUnverifiedExcludedFromStorageSearchReportBackup
        }
    }

    static func disposition(
        for receipt: AssistanceAcceptanceReceiptV1
    ) throws -> AcceptanceDispositionV1 {
        try receipt.validate()
        guard AssistancePersistenceEnrollmentV1.durableModelCount == 1 else {
            throw AssistanceContractFailureV1.invalidReceipt
        }
        return .durableThroughExistingCanonicalWriter
    }

    static let capabilityScratchIsDiscardedOnTerminalReview = true
    static let manualFallbackRemainsAvailable = true
    static let interruptionNeverPromotesAProposal = true
    static let createsParallelStoreOrWriter = false
}

enum C33TemporalEvidenceConformance_FieldEvidenceApp_Infrastructure_Lighting_LightingLifecycleAdapterV1_swift {
    static let durableFamilyCount = TemporalEvidencePersistenceEnrollmentV1.durableModelCount
    static func validate(clip: TemporalEvidenceClipV1,
                         anchor: TimecodedEvidenceAnchorV1) throws {
        try clip.validateIntrinsic()
        try anchor.validate(clip: clip)
        guard durableFamilyCount == 2 else {
            throw TemporalEvidenceContractFailureV1.invalidValue
        }
    }
}

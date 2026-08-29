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

/// C32 keeps assistance candidates outside every durable and derived surface;
/// only explicit acceptance may reach the existing canonical writer/receipt path.
enum C32AssistanceCompatibility_EvidenceContext_EvidenceContextLifecycleAdapterV1 {
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

enum C33TemporalEvidenceConformance_FieldEvidenceApp_Infrastructure_EvidenceContext_EvidenceContextLifecycleAdapterV1_swift {
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

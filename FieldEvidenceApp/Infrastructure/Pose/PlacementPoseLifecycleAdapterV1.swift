import Foundation

/// C37 infrastructure bridge. Its closures must delegate to the existing
/// WorkspaceWriter; this adapter owns no persistence, sensor, network, or
/// receipt authority.
@MainActor
final class PlacementPoseLifecycleAdapterV1: PlacementPoseMutationAuthorityV1 {
    private let writer: WorkspaceWriterV1

    init(writer: WorkspaceWriterV1) { self.writer = writer }

    func appendPoseEvent(_ event: AssetPoseEventV1,
                         predecessor: AssetPoseEventV1?,
                         admissionClosure: PlacementPoseAdmissionClosureV1) async throws -> MutationReceiptV1 {
        try event.validateIntrinsic()
        try admissionClosure.validate(events: [event], observations: [])
        let mutation = try PlacementPoseMutationV1(workspaceID: event.workspaceID,
            mutationID: event.mutationID, events: [event], eventPredecessors: [predecessor],
            admissionClosure: admissionClosure)
        let receipt = try writer.commitPlacementPose(mutation); try receipt.validate()
        guard receipt.mutationID == event.mutationID,
              receipt.identity.workspaceID == event.workspaceID else {
            throw PlacementPoseFailureV1.referenceMismatch
        }
        return receipt
    }

    func appendSpatialAnchor(_ observation: SpatialAnchorObservationV1,
                             predecessor: SpatialAnchorObservationV1?,
                             admissionClosure: PlacementPoseAdmissionClosureV1) async throws -> MutationReceiptV1 {
        try observation.validateIntrinsic()
        try admissionClosure.validate(events: [], observations: [observation])
        let mutation = try PlacementPoseMutationV1(workspaceID: observation.workspaceID,
            mutationID: observation.mutationID, events: [], eventPredecessors: [],
            observations: [observation], observationPredecessors: [predecessor],
            admissionClosure: admissionClosure)
        let receipt = try writer.commitPlacementPose(mutation); try receipt.validate()
        guard receipt.mutationID == observation.mutationID,
              receipt.identity.workspaceID == observation.workspaceID else {
            throw PlacementPoseFailureV1.referenceMismatch
        }
        return receipt
    }
}
// C30: this seam consumes only the frozen, metadata-only operating-context projection.
enum C30ConsumerBoundaryV1_Infrastructure_Pose_PlacementPoseLifecycleAdapterV1 {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Infrastructure/Pose/PlacementPoseLifecycleAdapterV1.swift", role: .pose)
}

enum C31LightingConsumerBoundary_Infrastructure_Pose_PlacementPoseLifecycleAdapterV1 {
    static let registrationID = "C31_LIGHTING_CONSUMER/placement-pose-lifecycle-adapter"
    static let compatibility = C31LightingCompatibilityPolicyV1()
    static func validate(projection: C31LightingReportProjectionV1) throws {
        try compatibility.validate()
        try C31LightingProjectionPolicyV1.validate(projection)
    }
}

/// C32 keeps assistance candidates outside every durable and derived surface;
/// only explicit acceptance may reach the existing canonical writer/receipt path.
enum C32AssistanceCompatibility_Pose_PlacementPoseLifecycleAdapterV1 {
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

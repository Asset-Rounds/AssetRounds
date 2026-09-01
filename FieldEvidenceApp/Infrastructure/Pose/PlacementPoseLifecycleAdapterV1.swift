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

    /// C21's lifecycle may retain a pre-existing qualified pose anchor, but
    /// cannot turn scan input into a pose event or spatial-anchor mutation.
    func validateScanToWorkPoseAnchor(
        for binding: ScanToWorkAssetBindingV1
    ) throws -> AssetPoseEventReferenceV1? {
        try C21ScanToWorkPoseBoundaryV1.qualifiedAnchor(for: binding)
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

enum C33TemporalEvidenceConformance_FieldEvidenceApp_Infrastructure_Pose_PlacementPoseLifecycleAdapterV1_swift {
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

// MARK: - C45 canonical asset-label integration
enum C45AssetLabelBoundary_Row169 {
    static let reusesCanonicalAssetLocatorAndWriter = true
    static func validateAcceptedSnapshot(_ snapshot: AcceptedLabelGenerationSnapshotV1) throws {
        try snapshot.validate()
    }
}
enum C46OperationalContactConformance_FieldEvidenceApp_Infrastructure_Pose_PlacementPoseLifecycleAdapterV1_swift {
    static let operationalContactsRemainPurposeSeparated = true
    static let systemHandoffsRemainExplicitEphemeralAndNoncanonical = true
    static let subscriberConsentCampaignAndMeasurementProjectionForbidden = true
    static let contactExportExcludedByDefault = true
    static let noContactProjectionOrNetworkDelivery = true
}

// MARK: - C52 lifecycle and privacy boundary
enum C52ServiceRequestBoundary_FieldEvidenceApp_Infrastructure_Pose_PlacementPoseLifecycleAdapterV1_swift {
    static let acceptedCanonicalRecordPersistence: ServiceRequestPersistenceClassV1 = .canonicalPersistent
    static let acceptedEventPersistence: ServiceRequestPersistenceClassV1 = .canonicalPersistent
    static let duplicateProjectionPersistence: ServiceRequestPersistenceClassV1 = .nonpersistentDerived
    static let rawCapabilityPersistence: ServiceRequestPersistenceClassV1 = .prohibitedPersistent
    static let acceptedLifecycleEnrollment: ServiceRequestPersistenceEnrollmentV1.Type = ServiceRequestPersistenceEnrollmentV1.self
    static let cloneOrForkInvalidatesActiveCapabilities: Bool =
        ServiceRequestLifecycleRegistrationBoundaryV1.cloneOrForkInvalidatesOutstandingCapabilities
    static let duplicateProjectionIsRebuildable: Bool =
        ServiceRequestLifecycleRegistrationBoundaryV1.derivedProjectionIsRebuildable &&
        !ServiceRequestNoncanonicalBoundaryV1.duplicateProjectionIsPersistent
    static let rawCapabilityIsExcludedFromReportsAndDiagnostics: Bool =
        !ServiceRequestLifecycleRegistrationBoundaryV1.rawCapabilityAppearsInReportsOrDiagnostics
    static let sharedPortableFilesAreRecallable: Bool =
        ServiceRequestLifecycleRegistrationBoundaryV1.escapedPortableFilesCanBeRecalled
    static let unverifiedAssertionsAreVerified: Bool = false
    static let automaticWorkNetworkSLAOrAIClaimsPermitted: Bool = false
}

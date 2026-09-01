import Foundation

protocol PlanRebaseReceiptRecoveringV1: Sendable {
    func acceptedPlanMutationReceipt(mutationID: MutationIDV1) throws -> MutationReceiptV1?
}

@MainActor
final class PlanLifecycleAdapterV1 {
    enum RecoveryDisposition: Equatable, Sendable {
        case retryRequired
        case accepted(MutationReceiptV1)
    }

    private let coordinator: PlanRebaseCoordinatorV1
    private let recovery: any PlanRebaseReceiptRecoveringV1

    init(coordinator: PlanRebaseCoordinatorV1,
         recovery: any PlanRebaseReceiptRecoveringV1) {
        self.coordinator = coordinator
        self.recovery = recovery
    }

    func preview(previewID: UUID, workspaceID: WorkspaceID,
                 oldRevision: PlanRevisionV1, newRevision: PlanRevisionV1,
                 transform: PlanAffineTransformV1, placements: [PlanPlacementV1],
                 oldPrerequisites: PlanPrerequisiteClosureV1,
                 newPrerequisites: PlanPrerequisiteClosureV1,
                 expectedRevision: UInt64, generatedAt: Date) throws -> RebasePreviewV1 {
        try coordinator.preview(previewID: previewID, workspaceID: workspaceID,
                                oldRevision: oldRevision, newRevision: newRevision,
                                transform: transform, placements: placements,
                                oldPrerequisites: oldPrerequisites,
                                newPrerequisites: newPrerequisites,
                                expectedRevision: expectedRevision, generatedAt: generatedAt)
    }

    func recover(mutationID: MutationIDV1) throws -> RecoveryDisposition {
        if let receipt = try recovery.acceptedPlanMutationReceipt(mutationID: mutationID) {
            return .accepted(receipt)
        }
        return .retryRequired
    }

    /// The rebase review is derived from an immutable preview and, when
    /// present, its immutable receipt. It never activates a preview or writes
    /// a plan revision.
    func reviewState(
        preview: RebasePreviewV1,
        receipt: RebaseReceiptV1?,
        evaluatedAt: Date
    ) throws -> RebaseReviewStateV1 {
        try RebaseReviewStateV1(
            preview: preview,
            receipt: receipt,
            evaluatedAt: evaluatedAt
        )
    }

    /// Builds a device-local display state from the caller's already resolved
    /// exact source. Historic, withdrawn, or expired sources remain
    /// displayable, but they cannot carry a resume draft into a claim or
    /// mutation path.
    func workSurface(
        source: PlanOfflineWorkSourceV1,
        selectedPageID: UUID,
        selectedPlacementID: UUID?,
        viewport: PlanViewportPresentationV1,
        resumeDraft: FieldDraftReferenceProjectionV1?,
        poseSnapshots: [PlanMaterializedPoseSnapshotV1],
        evaluatedAt: Date
    ) throws -> PlanWorkSurfaceStateV1 {
        try source.validate()
        if resumeDraft != nil {
            guard source.revisionDisposition == .current,
                  source.fieldReference.availability == .readyOffline,
                  source.openability.state == .openable,
                  source.access.protectedDataAvailable else {
                throw PlanOfflineWorkFailureV1.staleSource
            }
        }
        return try PlanWorkSurfaceStateV1(
            source: source,
            selectedPageID: selectedPageID,
            selectedPlacementID: selectedPlacementID,
            viewport: viewport,
            resumeDraft: resumeDraft,
            poseSnapshots: poseSnapshots,
            evaluatedAt: evaluatedAt
        )
    }

    func approve(preview: RebasePreviewV1, newRevision: PlanRevisionV1,
                 predecessorRevision: PlanRevisionV1, placements: [PlanPlacementV1],
                 predecessorPlacements: [PlanPlacementV1], receiptID: UUID,
                 prerequisites: PlanPrerequisiteClosureV1,
                 predecessorReceipt: RebaseReceiptV1?, mutationID: MutationIDV1,
                 reviewedBy: ActorSnapshotV1, recordedAt: Date,
                 poseEffects: PlacementPoseMutationV1? = nil) throws
        -> PlanRebaseApprovalOutcomeV1 {
        try coordinator.approve(preview: preview, newRevision: newRevision,
                                predecessorRevision: predecessorRevision,
                                placements: placements,
                                predecessorPlacements: predecessorPlacements,
                                receiptID: receiptID, prerequisites: prerequisites,
                                predecessorReceipt: predecessorReceipt,
                                mutationID: mutationID, reviewedBy: reviewedBy,
                                recordedAt: recordedAt, poseEffects: poseEffects)
    }

    func reject(preview: RebasePreviewV1, receiptID: UUID,
                predecessorReceipt: RebaseReceiptV1?, mutationID: MutationIDV1,
                reviewedBy: ActorSnapshotV1, recordedAt: Date) throws
        -> PlanRebaseRejectionOutcomeV1 {
        try coordinator.reject(preview: preview, receiptID: receiptID,
                               predecessorReceipt: predecessorReceipt,
                               mutationID: mutationID, reviewedBy: reviewedBy,
                               recordedAt: recordedAt)
    }
}

enum C37PoseIntegration_FieldEvidenceApp_Infrastructure_Plans_PlanLifecycleAdapterV1_swift {
    /// Typed C37 boundary: inherited owners may retain an immutable pose
    /// reference, but cannot infer pose, compliance, or current-state truth.
    static func validate(reference: AssetPoseEventReferenceV1,
                         in workspaceID: WorkspaceID) throws {
        try reference.validate()
        guard reference.workspaceID == workspaceID else {
            throw PlacementPoseFailureV1.wrongWorkspace
        }
    }
}
// C30: this seam consumes only the frozen, metadata-only operating-context projection.
enum C30ConsumerBoundaryV1_Infrastructure_Plans_PlanLifecycleAdapterV1 {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Infrastructure/Plans/PlanLifecycleAdapterV1.swift", role: .plan)
}

enum C31LightingConsumerBoundary_Infrastructure_Plans_PlanLifecycleAdapterV1 {
    static let registrationID = "C31_LIGHTING_CONSUMER/plan-lifecycle-adapter"
    static let compatibility = C31LightingCompatibilityPolicyV1()
    static func validate(projection: C31LightingReportProjectionV1) throws {
        try compatibility.validate()
        try C31LightingProjectionPolicyV1.validate(projection)
    }
}

/// C32 keeps assistance candidates outside every durable and derived surface;
/// only explicit acceptance may reach the existing canonical writer/receipt path.
enum C32AssistanceCompatibility_Plans_PlanLifecycleAdapterV1 {
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

enum C33TemporalEvidenceConformance_FieldEvidenceApp_Infrastructure_Plans_PlanLifecycleAdapterV1_swift {
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
enum C45AssetLabelBoundary_Row159 {
    static let reusesCanonicalAssetLocatorAndWriter = true
    static func validateAcceptedSnapshot(_ snapshot: AcceptedLabelGenerationSnapshotV1) throws {
        try snapshot.validate()
    }
}
enum C46OperationalContactConformance_FieldEvidenceApp_Infrastructure_Plans_PlanLifecycleAdapterV1_swift {
    static let operationalContactsRemainPurposeSeparated = true
    static let systemHandoffsRemainExplicitEphemeralAndNoncanonical = true
    static let subscriberConsentCampaignAndMeasurementProjectionForbidden = true
    static let contactExportExcludedByDefault = true
    static let noContactProjectionOrNetworkDelivery = true
}

// MARK: - C52 lifecycle and privacy boundary
enum C52ServiceRequestBoundary_FieldEvidenceApp_Infrastructure_Plans_PlanLifecycleAdapterV1_swift {
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

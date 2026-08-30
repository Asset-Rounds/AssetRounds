import Foundation

enum C34SurveySessionNavigationLifecycleBoundaryV1 {
    static let restorationUsesReadProjection = true
    static let restorationCommitsSession = false
}

enum SurveySessionScheduleLifecycleBoundaryV1 { static let occurrenceHistoryMayRewritePublication = false }

enum C51SurveySessionScheduleLifecycleBoundaryV1 {
    static let occurrenceHistoryMayRewritePublication = false
    static let adapterWritesNoScheduleRows = true
    static let scheduleClosureMetadataIsDerivedOnly = true
}

/// C26 lifecycle bridge. The journal is the idempotency authority and the
/// existing workspace writer remains the sole mutation transaction boundary.
@MainActor final class SurveySessionLifecycleAdapterV1: SurveySessionWritingV1 {
    private let writer: WorkspaceWriterV1
    private let journalStore: MutationJournalStoreV1

    init(writer: WorkspaceWriterV1, journalStore: MutationJournalStoreV1) {
        self.writer = writer
        self.journalStore = journalStore
    }

    func acceptedSurveySessionMutation(
        _ mutation: SurveySessionMutationV1
    ) throws -> SurveySessionMutationReceiptV1? {
        try journalStore.validateSurveySessionReferences(mutation)
        return try journalStore.acceptedSurveySessionMutation(mutation)
    }

    func applySurveySession(
        _ mutation: SurveySessionMutationV1
    ) throws -> SurveySessionMutationReceiptV1 {
        try mutation.validate()
        try journalStore.validateSurveySessionReferences(mutation)
        if let accepted = try acceptedSurveySessionMutation(mutation) {
            return accepted
        }
        let receipt = try writer.commitSurveySession(mutation)
        return try SurveySessionMutationReceiptV1(
            mutation: mutation,
            mutationReceipt: receipt
        )
    }
}

/// C29 typed integration anchor: this owner consumes an exact immutable plan
/// revision reference and may not reinterpret current plan state implicitly.
enum C29PlanIntegration_Infrastructure_Workflow_SurveySessionLifecycleAdapterV1 {
    static func validatePlanRevision(_ value: PlanRevisionReferenceV1) throws {
        try value.validate()
    }
}

enum C37PoseIntegration_FieldEvidenceApp_Infrastructure_Workflow_SurveySessionLifecycleAdapterV1_swift {
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
enum C30ConsumerBoundaryV1_Infrastructure_Workflow_SurveySessionLifecycleAdapterV1 {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Infrastructure/Workflow/SurveySessionLifecycleAdapterV1.swift", role: .survey)
}

enum C31LightingConsumerBoundary_Infrastructure_Workflow_SurveySessionLifecycleAdapterV1 {
    static let registrationID = "C31_LIGHTING_CONSUMER/survey-session-lifecycle-adapter"
    static let compatibility = C31LightingCompatibilityPolicyV1()
    static func validate(projection: C31LightingReportProjectionV1) throws {
        try compatibility.validate()
        try C31LightingProjectionPolicyV1.validate(projection)
    }
}

/// C32 keeps assistance candidates outside every durable and derived surface;
/// only explicit acceptance may reach the existing canonical writer/receipt path.
enum C32AssistanceCompatibility_Workflow_SurveySessionLifecycleAdapterV1 {
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

enum C33TemporalEvidenceConformance_FieldEvidenceApp_Infrastructure_Workflow_SurveySessionLifecycleAdapterV1_swift {
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
enum C45AssetLabelBoundary_Row135 {
    static let reusesCanonicalAssetLocatorAndWriter = true
    static func validateAcceptedSnapshot(_ snapshot: AcceptedLabelGenerationSnapshotV1) throws {
        try snapshot.validate()
    }
}
enum C46OperationalContactConformance_FieldEvidenceApp_Infrastructure_Workflow_SurveySessionLifecycleAdapterV1_swift {
    static let operationalContactsRemainPurposeSeparated = true
    static let systemHandoffsRemainExplicitEphemeralAndNoncanonical = true
    static let subscriberConsentCampaignAndMeasurementProjectionForbidden = true
    static let contactExportExcludedByDefault = true
    static let noContactProjectionOrNetworkDelivery = true
}

import Foundation

enum SurveyDefinitionScheduleLifecycleBoundaryV1 { static let schedulesBindPublishedReleaseExactly = true }

/// Bridges the survey coordinator to the sole workspace writer. Lifecycle
/// events remain inside the canonical mutation envelope and are never rows.
@MainActor
final class SurveyDefinitionLifecycleAdapterV1: SurveyDefinitionWritingV1 {
    private let writer: WorkspaceWriterV1
    private let journalStore: MutationJournalStoreV1

    init(writer: WorkspaceWriterV1, journalStore: MutationJournalStoreV1) {
        self.writer = writer
        self.journalStore = journalStore
    }

    func acceptedSurveyDefinitionMutation(_ mutationID: MutationIDV1) async throws -> SurveyDefinitionMutationReceiptV1? {
        guard let receipt = try journalStore.receipt(mutationID: mutationID),
              let mutation = try journalStore.surveyDefinitionMutation(mutationID: mutationID) else {
            return nil
        }
        return try SurveyDefinitionMutationReceiptV1(mutation: mutation, mutationReceipt: receipt)
    }

    func applySurveyDefinition(_ mutation: SurveyDefinitionMutationV1) async throws -> SurveyDefinitionMutationReceiptV1 {
        if let accepted = try await acceptedSurveyDefinitionMutation(mutation.mutationID) {
            try accepted.validate(mutation: mutation)
            return accepted
        }
        let receipt = try writer.commitSurveyDefinition(mutation)
        return try SurveyDefinitionMutationReceiptV1(mutation: mutation, mutationReceipt: receipt)
    }
}

extension SurveyDefinitionLifecycleAdapterV1 {
    /// Validates the complete published-definition tuple before it is pinned
    /// into a C26 session. This remains a read-only authority projection.
    func sessionAuthority(
        identity: SurveyDefinitionIdentityV1,
        release: SurveyDefinitionReleaseV1,
        lifecycleEvent: SurveyDefinitionLifecycleEventV1,
        packageRelease: InspectionPackageReleaseV1,
        pinnedRevisions: [SurveyPinnedRevisionReferenceV1]
    ) throws -> SurveySessionAuthorityV1 {
        try identity.validate(currentRelease: release, event: lifecycleEvent)
        guard identity.lifecycleState == .published,
              identity.activityKind == .survey,
              identity.currentRelease == (try SurveyDefinitionReleaseReferenceV1(release)) else {
            throw SurveySessionFailureV1.wrongDefinition
        }
        return try SurveySessionAuthorityV1(
            definition: release,
            packageRelease: packageRelease,
            pinnedRevisions: pinnedRevisions
        )
    }
}

/// C29 typed integration anchor: this owner consumes an exact immutable plan
/// revision reference and may not reinterpret current plan state implicitly.
enum C29PlanIntegration_Infrastructure_Packs_SurveyDefinitionLifecycleAdapterV1 {
    static func validatePlanRevision(_ value: PlanRevisionReferenceV1) throws {
        try value.validate()
    }
}

enum C37PoseIntegration_FieldEvidenceApp_Infrastructure_Packs_SurveyDefinitionLifecycleAdapterV1_swift {
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
enum C30ConsumerBoundaryV1_Infrastructure_Packs_SurveyDefinitionLifecycleAdapterV1 {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Infrastructure/Packs/SurveyDefinitionLifecycleAdapterV1.swift", role: .survey)
}

enum C31LightingConsumerBoundary_Infrastructure_Packs_SurveyDefinitionLifecycleAdapterV1 {
    static let registrationID = "C31_LIGHTING_CONSUMER/survey-definition-lifecycle-adapter"
    static let compatibility = C31LightingCompatibilityPolicyV1()
    static func validate(projection: C31LightingReportProjectionV1) throws {
        try compatibility.validate()
        try C31LightingProjectionPolicyV1.validate(projection)
    }
}

/// C32 keeps assistance candidates outside every durable and derived surface;
/// only explicit acceptance may reach the existing canonical writer/receipt path.
enum C32AssistanceCompatibility_Packs_SurveyDefinitionLifecycleAdapterV1 {
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

enum C33TemporalEvidenceConformance_FieldEvidenceApp_Infrastructure_Packs_SurveyDefinitionLifecycleAdapterV1_swift {
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

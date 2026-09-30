import Foundation

enum C34SurveyDefinitionNavigationLifecycleBoundaryV1 {
    static let restorationUsesReadProjection = true
    static let restorationCommitsDefinition = false
}

enum SurveyDefinitionScheduleLifecycleBoundaryV1 { static let schedulesBindPublishedReleaseExactly = true }

enum C51SurveyDefinitionScheduleLifecycleBoundaryV1 {
    static let adapterWritesNoOccurrenceHistory = true
    static let scheduleClosureMetadataIsDerivedOnly = true
    static let canonicalDefinitionWriterRemainsUnchanged = true
}

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

    /// Opens only the caller-specified lifecycle revision.  The journal is
    /// consulted by the exact mutation ID, so a current identity is never
    /// substituted for historic draft, withdrawn, or retired content.
    func exactLibraryRow(
        workspaceID: WorkspaceID,
        identity: SurveyDefinitionIdentityV1,
        release: SurveyDefinitionReleaseV1,
        event: SurveyDefinitionLifecycleEventV1,
        overlay: SurveyDefinitionDeviceLocalOverlayV1?
    ) async throws -> SurveyDefinitionLibraryRowV1 {
        try identity.validate(currentRelease: release, event: event)
        try overlay?.validate()
        guard identity.workspaceID == workspaceID,
              release.workspaceID == workspaceID,
              event.workspaceID == workspaceID,
              overlay.map({ $0.definitionID == identity.definitionID }) ?? true,
              let recorded = try journalStore.surveyDefinitionMutation(
                mutationID: identity.mutationID
              ),
              recorded.identity == identity,
              recorded.release == release,
              recorded.event == event,
              let receipt = try await acceptedSurveyDefinitionMutation(identity.mutationID) else {
            throw GuidedSurveyFlowFailureV1.missingExactSource
        }
        try receipt.validate(mutation: recorded)
        return try SurveyDefinitionLibraryRowV1(
            identity: identity, release: release, event: event, overlay: overlay
        )
    }

    /// Revalidates the C20 exact source after the core flow resolver has
    /// assembled it.  This keeps the flow's historic reader and the sole
    /// canonical journal in agreement without introducing a second query
    /// store or a latest-release fallback.
    func validateExactSource(_ source: GuidedSurveyFlowSourceV1) async throws {
        try source.validate()
        _ = try await exactLibraryRow(
            workspaceID: source.request.workspaceID, identity: source.identity,
            release: source.definition, event: source.lifecycleEvent,
            overlay: nil
        )
        guard let sessionMutation = try journalStore.surveySessionMutation(
            mutationID: source.session.mutationID
        ), try journalStore.receipt(mutationID: source.session.mutationID) != nil,
              sessionMutation.workspaceID == source.request.workspaceID else {
            throw GuidedSurveyFlowFailureV1.missingExactSource
        }
        switch sessionMutation.payload {
        case let .applySession(value, definition, publication):
            guard value == source.session, definition == source.definition,
                  publication == nil else { throw GuidedSurveyFlowFailureV1.staleSource }
        case let .publish(value, publication, definition, _):
            guard value == source.session, definition == source.definition,
                  source.publication == publication else {
                throw GuidedSurveyFlowFailureV1.staleSource
            }
        default:
            throw GuidedSurveyFlowFailureV1.staleSource
        }
        for capture in source.captures {
            guard let mutation = try journalStore.surveySessionMutation(
                mutationID: capture.mutationID
            ), try journalStore.receipt(mutationID: capture.mutationID) != nil,
                  mutation.workspaceID == source.request.workspaceID else {
                throw GuidedSurveyFlowFailureV1.missingExactSource
            }
            guard case let .captureFact(value, session, definition, _) = mutation.payload,
                  value == capture, session.sessionID == source.session.sessionID,
                  definition == source.definition else {
                throw GuidedSurveyFlowFailureV1.staleSource
            }
        }
        if let publication = source.publication {
            guard let mutation = try journalStore.surveySessionMutation(
                mutationID: publication.mutationID
            ), try journalStore.receipt(mutationID: publication.mutationID) != nil,
                  case let .publish(_, value, definition, _) = mutation.payload,
                  value == publication, definition == source.definition else {
                throw GuidedSurveyFlowFailureV1.staleSource
            }
        }
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

// MARK: - C45 canonical asset-label integration
enum C45AssetLabelBoundary_Row132 {
    static let reusesCanonicalAssetLocatorAndWriter = true
    static func validateAcceptedSnapshot(_ snapshot: AcceptedLabelGenerationSnapshotV1) throws {
        try snapshot.validate()
    }
}
enum C46OperationalContactConformance_FieldEvidenceApp_Infrastructure_Packs_SurveyDefinitionLifecycleAdapterV1_swift {
    static let c47IntegrationRole = "SURVEY_PACKAGE_LIFECYCLE_REUSE"
    static let c47SharedReceipt = SharedActivityEnvelopeReceiptV1.self
    static let c47InstallationReceipt = InstallationActivityContractReceiptV1.self
    static let c47PunchReceipt = PunchActivityContractReceiptV1.self
    static let c47NoPlanFallback = NoPlanFallbackV1.self
    static let c47UsesExistingWriterRendererStoreAndPackageInfrastructure = true
    static let c47CreatesSecondRouteOrInspectionAlias = false
    static let operationalContactsRemainPurposeSeparated = true
    static let systemHandoffsRemainExplicitEphemeralAndNoncanonical = true
    static let subscriberConsentCampaignAndMeasurementProjectionForbidden = true
    static let contactExportExcludedByDefault = true
    static let noContactProjectionOrNetworkDelivery = true
}

enum C47ActivityContractConformance_FieldEvidenceApp_Infrastructure_Packs_SurveyDefinitionLifecycleAdapterV1_swift {
    static let sharedReceipt = SharedActivityEnvelopeReceiptV1.self
    static let installationReceipt = InstallationActivityContractReceiptV1.self
    static let punchReceipt = PunchActivityContractReceiptV1.self
    static let noPlanFallback = NoPlanFallbackV1.self
    static let usesExistingInfrastructureOnly = true
    static let createsSecondWriterRendererStoreRouteOrInspectionAlias = false
}

// MARK: - C52 lifecycle and privacy boundary
enum C52ServiceRequestBoundary_FieldEvidenceApp_Infrastructure_Packs_SurveyDefinitionLifecycleAdapterV1_swift {
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

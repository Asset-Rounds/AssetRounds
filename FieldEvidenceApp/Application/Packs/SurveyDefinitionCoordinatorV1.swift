import Foundation

enum SurveyDefinitionScheduleCoordinatorBoundaryV1 { static let publicationCreatesSchedule = false }

enum C51SurveyDefinitionScheduleCoordinatorBoundaryV1 {
    static let publicationCreatesSchedule = false
    static let coordinatorOwnsNoOccurrenceWriter = true
    static let scheduleClosureMetadataIsDerivedOnly = true

    static func validate(_ metadata: C51ScheduleClosureMetadataV1) throws {
        try metadata.validate()
    }
}

struct SurveyDefinitionPreparedMutationV1: Equatable, Sendable {
    let identity: SurveyDefinitionIdentityV1
    let release: SurveyDefinitionReleaseV1
    let event: SurveyDefinitionLifecycleEventV1
    let mutation: SurveyDefinitionMutationV1

    init(identity: SurveyDefinitionIdentityV1, release: SurveyDefinitionReleaseV1, event: SurveyDefinitionLifecycleEventV1) throws {
        try identity.validate(currentRelease: release, event: event)
        self.identity = identity
        self.release = release
        self.event = event
        mutation = try SurveyDefinitionMutationV1(identity: identity, release: release, event: event)
    }
}

protocol SurveyDefinitionWritingV1: Sendable {
    func acceptedSurveyDefinitionMutation(_ mutationID: MutationIDV1) async throws -> SurveyDefinitionMutationReceiptV1?
    func applySurveyDefinition(_ mutation: SurveyDefinitionMutationV1) async throws -> SurveyDefinitionMutationReceiptV1
}

struct SurveyTemplateQuarantineCandidateV1: Equatable, Sendable {
    let assessment: SurveyTemplateQuarantineAssessmentV1
    let manifest: SurveyTemplateArchiveManifestV1
    let importedRelease: SurveyDefinitionReleaseV1

    init(
        extraction: StreamingArchiveExtractionV1,
        manifest: SurveyTemplateArchiveManifestV1,
        assessment: SurveyTemplateQuarantineAssessmentV1,
        importedRelease: SurveyDefinitionReleaseV1
    ) throws {
        try SurveyTemplateArchiveAdmissionV1.validate(extraction.index)
        try manifest.validate(); try assessment.validate(); try importedRelease.validate()
        let indexedEntries = extraction.index.entries.map {
            SurveyTemplateArchiveEntryV1(
                path: $0.path, mediaType: $0.mimeType,
                byteCount: $0.uncompressedByteCount, sha256: $0.contentSHA256,
                compressedByteCount: $0.storedByteCount, storedSHA256: $0.storedSHA256
            )
        }.sorted { $0.path < $1.path }
        let releaseReference = try SurveyDefinitionReleaseReferenceV1(importedRelease)
        guard extraction.index.archiveSchemaVersion == StreamingArchiveIndexV1.currentSchemaVersion,
              extraction.index.storedPayloadByteCount == extraction.index.entries.reduce(Int64(0), { $0 + $1.storedByteCount }),
              extraction.index.uncompressedPayloadByteCount == extraction.index.entries.reduce(Int64(0), { $0 + $1.uncompressedByteCount }),
              extraction.archiveSHA256 == manifest.archiveSHA256,
              assessment.archiveSHA256 == manifest.archiveSHA256,
              manifest.archiveByteCount == extraction.index.uncompressedPayloadByteCount,
              manifest.entries == indexedEntries,
              manifest.definitionRelease == releaseReference,
              assessment.disposition == .draftCandidate,
              assessment.manifestSHA256 == manifest.manifestSHA256,
              assessment.candidateReleaseSHA256 == importedRelease.releaseSHA256 else {
            throw SurveyDefinitionFailureV1.hostileArchive
        }
        self.assessment = assessment
        self.manifest = manifest
        self.importedRelease = importedRelease
    }
}

actor SurveyDefinitionCoordinatorV1 {
    private let writer: any SurveyDefinitionWritingV1

    init(writer: any SurveyDefinitionWritingV1) { self.writer = writer }

    func createDraft(
        identity: SurveyDefinitionIdentityV1,
        release: SurveyDefinitionReleaseV1,
        event: SurveyDefinitionLifecycleEventV1
    ) async throws -> SurveyDefinitionMutationReceiptV1 {
        guard identity.lifecycleState == .draft,
              identity.revision == 1,
              release.revision == 1,
              event.action == .createDraft else {
            throw SurveyDefinitionFailureV1.invalidTransition
        }
        return try await apply(.init(identity: identity, release: release, event: event))
    }

    func applySuccessor(
        previousIdentity: SurveyDefinitionIdentityV1,
        previousRelease: SurveyDefinitionReleaseV1,
        previousEvent: SurveyDefinitionLifecycleEventV1,
        identity: SurveyDefinitionIdentityV1,
        release: SurveyDefinitionReleaseV1,
        event: SurveyDefinitionLifecycleEventV1
    ) async throws -> SurveyDefinitionMutationReceiptV1 {
        guard event.action != .adoptUpgradeAsDraft else {
            throw SurveyDefinitionFailureV1.stalePreview
        }
        try previousIdentity.validate(currentRelease: previousRelease, event: previousEvent)
        if event.action == .publish || event.action == .retire {
            guard release == previousRelease else { throw SurveyDefinitionFailureV1.invalidTransition }
        } else {
            try release.validateSuccessor(of: previousRelease)
        }
        try event.validateSuccessor(of: previousEvent, release: release)
        try identity.validateSuccessor(of: previousIdentity, event: event, release: release)
        return try await apply(.init(identity: identity, release: release, event: event))
    }

    func adoptUpgradeAsDraft(
        _ preview: SurveyDefinitionAdoptionPreviewV1,
        currentSource: SurveyDefinitionReleaseV1,
        currentTarget: SurveyDefinitionReleaseV1,
        previousIdentity: SurveyDefinitionIdentityV1,
        previousEvent: SurveyDefinitionLifecycleEventV1,
        currentDraftIDs: [UUID],
        currentActiveWorkCount: Int,
        identity: SurveyDefinitionIdentityV1,
        event: SurveyDefinitionLifecycleEventV1
    ) async throws -> SurveyDefinitionMutationReceiptV1 {
        try previousIdentity.validate(currentRelease: currentSource, event: previousEvent)
        try currentTarget.validateSuccessor(of: currentSource)
        try preview.validate(
            source: currentSource, target: currentTarget,
            currentDraftIDs: currentDraftIDs,
            currentActiveWorkCount: currentActiveWorkCount
        )
        guard event.action == .adoptUpgradeAsDraft,
              event.priorState == .draft, event.resultingState == .draft,
              event.semanticDiffSHA256 == preview.semanticDiff.diffSHA256,
              previousIdentity.lifecycleState == .draft,
              identity.lifecycleState == .draft else {
            throw SurveyDefinitionFailureV1.stalePreview
        }
        try event.validateSuccessor(of: previousEvent, release: currentTarget)
        try identity.validateSuccessor(
            of: previousIdentity, event: event, release: currentTarget
        )
        return try await apply(.init(identity: identity, release: currentTarget, event: event))
    }

    func importAsNewDraft(
        candidate: SurveyTemplateQuarantineCandidateV1,
        newDefinitionID: UUID,
        newReleaseID: UUID,
        newEventID: UUID,
        workspaceID: WorkspaceID,
        actor: ActorSnapshotV1,
        mutationID: MutationIDV1,
        recordedAt: Date
    ) async throws -> SurveyDefinitionMutationReceiptV1 {
        let source = candidate.importedRelease
        guard newDefinitionID != source.definitionID,
              newReleaseID != source.releaseID,
              actor.workspaceID == workspaceID else {
            throw SurveyDefinitionFailureV1.invalidTransition
        }
        let release = try SurveyDefinitionReleaseV1(
            releaseID: newReleaseID, workspaceID: workspaceID, definitionID: newDefinitionID,
            activityKind: source.activityKind, ownerPackageID: source.ownerPackageID,
            sections: source.sections, completionRules: source.completionRules,
            claimsProfile: source.claimsProfile, reportProjection: source.reportProjection,
            localizationReleaseSHA256: source.localizationReleaseSHA256,
            revision: 1, mutationID: mutationID, authoredBy: actor, authoredAt: recordedAt
        )
        let reference = try SurveyDefinitionReleaseReferenceV1(release)
        let event = try SurveyDefinitionLifecycleEventV1(
            eventID: newEventID, workspaceID: workspaceID, definitionID: newDefinitionID,
            action: .importAsDraft, priorState: nil, resultingState: .draft, release: reference,
            sourceDefinitionID: source.definitionID, sourceReleaseID: source.releaseID,
            sourceReleaseSHA256: source.releaseSHA256,
            sourceArchiveSHA256: candidate.assessment.archiveSHA256,
            actor: actor, recordedAt: recordedAt, revision: 1, mutationID: mutationID
        )
        let identity = try SurveyDefinitionIdentityV1(
            definitionID: newDefinitionID, workspaceID: workspaceID, activityKind: source.activityKind,
            lifecycleState: .draft, currentRelease: reference,
            latestLifecycleEventID: event.eventID, latestLifecycleEventSHA256: event.eventSHA256,
            createdBy: actor, createdAt: recordedAt, revision: 1, mutationID: mutationID
        )
        return try await apply(.init(identity: identity, release: release, event: event))
    }

    func previewAdoption(
        source: SurveyDefinitionReleaseV1,
        target: SurveyDefinitionReleaseV1,
        affectedDraftIDs: [UUID],
        pinnedActiveWorkCount: Int,
        generatedAt: Date
    ) throws -> SurveyDefinitionAdoptionPreviewV1 {
        guard source.workspaceID == target.workspaceID,
              source.definitionID == target.definitionID,
              source.activityKind == target.activityKind else {
            throw SurveyDefinitionFailureV1.invalidTransition
        }
        try target.validateSuccessor(of: source)
        let preview = try SurveyDefinitionAdoptionPreviewV1(
            workspaceID: source.workspaceID,
            diff: .init(source: source, target: target),
            affectedDraftIDs: affectedDraftIDs,
            pinnedActiveWorkCount: pinnedActiveWorkCount,
            generatedAt: generatedAt
        )
        try preview.validate(source: source, target: target, currentDraftIDs: affectedDraftIDs, currentActiveWorkCount: pinnedActiveWorkCount)
        return preview
    }

    func validateAdoption(
        _ preview: SurveyDefinitionAdoptionPreviewV1,
        currentSource: SurveyDefinitionReleaseV1,
        currentTarget: SurveyDefinitionReleaseV1,
        currentDraftIDs: [UUID],
        currentActiveWorkCount: Int
    ) throws {
        guard currentSource.workspaceID == currentTarget.workspaceID,
              currentSource.definitionID == currentTarget.definitionID,
              currentSource.activityKind == currentTarget.activityKind else {
            throw SurveyDefinitionFailureV1.stalePreview
        }
        do { try currentTarget.validateSuccessor(of: currentSource) }
        catch { throw SurveyDefinitionFailureV1.stalePreview }
        try preview.validate(
            source: currentSource, target: currentTarget,
            currentDraftIDs: currentDraftIDs,
            currentActiveWorkCount: currentActiveWorkCount
        )
    }

    private func apply(_ prepared: SurveyDefinitionPreparedMutationV1) async throws -> SurveyDefinitionMutationReceiptV1 {
        if let accepted = try await writer.acceptedSurveyDefinitionMutation(prepared.mutation.mutationID) {
            try accepted.validate(mutation: prepared.mutation)
            return accepted
        }
        let receipt = try await writer.applySurveyDefinition(prepared.mutation)
        try receipt.validate(mutation: prepared.mutation)
        return receipt
    }
}

// MARK: - C26 guided-survey session authority

extension SurveyDefinitionCoordinatorV1 {
    /// Builds the immutable authority captured when a survey session starts.
    /// Existing sessions retain this value; publishing a later definition or
    /// package release never silently upgrades in-flight work.
    func sessionAuthority(
        identity: SurveyDefinitionIdentityV1,
        release: SurveyDefinitionReleaseV1,
        lifecycleEvent: SurveyDefinitionLifecycleEventV1,
        packageRelease: InspectionPackageReleaseV1,
        pinnedRevisions: [SurveyPinnedRevisionReferenceV1]
    ) throws -> SurveySessionAuthorityV1 {
        try identity.validate(currentRelease: release, event: lifecycleEvent)
        guard identity.lifecycleState == .published,
              release.activityKind == .survey,
              identity.currentRelease == (try SurveyDefinitionReleaseReferenceV1(release)) else {
            throw SurveySessionFailureV1.wrongDefinition
        }
        return try SurveySessionAuthorityV1(
            definition: release,
            packageRelease: packageRelease,
            pinnedRevisions: pinnedRevisions
        )
    }

    /// Read-back validation is exact-release only. Callers must create an
    /// explicit successor session to adopt a newer definition release.
    func validatePinnedSession(
        _ session: SurveySessionV1,
        definition: SurveyDefinitionReleaseV1,
        packageRelease: InspectionPackageReleaseV1
    ) throws {
        try session.validate(definition: definition)
        try session.authority.validate(
            definition: definition,
            packageRelease: packageRelease
        )
        guard session.authority.definitionRelease
                == (try SurveyDefinitionReleaseReferenceV1(definition)) else {
            throw SurveySessionFailureV1.wrongDefinition
        }
    }
}

/// C29 typed integration anchor: this owner consumes an exact immutable plan
/// revision reference and may not reinterpret current plan state implicitly.
enum C29PlanIntegration_Application_Packs_SurveyDefinitionCoordinatorV1 {
    static func validatePlanRevision(_ value: PlanRevisionReferenceV1) throws {
        try value.validate()
    }
}

enum C37PoseIntegration_FieldEvidenceApp_Application_Packs_SurveyDefinitionCoordinatorV1_swift {
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
enum C30ConsumerBoundaryV1_Application_Packs_SurveyDefinitionCoordinatorV1 {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Application/Packs/SurveyDefinitionCoordinatorV1.swift", role: .survey)
}

enum C31LightingConsumerBoundary_Application_Packs_SurveyDefinitionCoordinatorV1 {
    static let registrationID = "C31_LIGHTING_CONSUMER/survey-definition-coordinator"
    static let compatibility = C31LightingCompatibilityPolicyV1()
    static func validate(projection: C31LightingReportProjectionV1) throws {
        try compatibility.validate()
        try C31LightingProjectionPolicyV1.validate(projection)
    }
}
// MARK: - C32 assistance survey definition boundary

enum C32AssistanceLifecycleBoundary_FieldEvidenceApp_Application_Packs_SurveyDefinitionCoordinatorV1_swift {
    static let proposalIsPersistent = AssistancePersistenceEnrollmentV1.proposalIsPersistent
    static let rejectedProposalCorpusIsPersistent = AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent
    static let durableFamilyCount = AssistancePersistenceEnrollmentV1.durableModelCount
    static let acceptedMutationKind: WorkspaceCommandKindV1 = .applyAssistanceAcceptance
    static let manualFallback: ManualFallbackActionV1 = .typeManually
    static let definitionRevisionInvalidatesProposal = true

    static func validateProposal(_ proposal: AssistanceProposalV1, in context: AssistanceProposalEvaluationContextV1) throws {
        try proposal.validate()
        try context.validate()
        guard proposal.verificationState.rawValue == AssistanceProposalVerificationStateV1.unverified.rawValue,
              context.policy.manualFallback == .typeManually else {
            throw AssistanceContractFailureV1.incompatibleCapability
        }
        if let reason = try proposal.expiryReason(in: context) {
            throw AssistanceContractFailureV1.expired(reason)
        }
    }

    static func validateAcceptanceReceipt(_ receipt: AssistanceAcceptanceReceiptV1) throws {
        try receipt.validate()
    }
}

enum C33TemporalEvidenceBoundary_Application_Packs_SurveyDefinitionCoordinatorV1_V1 {
    static let clipType: TemporalEvidenceClipV1.Type = TemporalEvidenceClipV1.self
    static let anchorType: TimecodedEvidenceAnchorV1.Type = TimecodedEvidenceAnchorV1.self
    static let persistentSchemaVersion: Int =
        TemporalEvidencePersistenceEnrollmentV1.persistentSchemaVersion
}

// MARK: - C45 canonical asset-label integration
enum C45AssetLabelBoundary_Row131 {
    static let reusesCanonicalAssetLocatorAndWriter = true
    static func validateAcceptedSnapshot(_ snapshot: AcceptedLabelGenerationSnapshotV1) throws {
        try snapshot.validate()
    }
}
enum C46OperationalContactConformance_FieldEvidenceApp_Application_Packs_SurveyDefinitionCoordinatorV1_swift {
    static let c47IntegrationRole = "SURVEY_DEFINITION_OWNERSHIP_PRESERVED"
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
    static let noSecondWriterOrAutomaticHandoff = true
}

enum C47ActivityContractConformance_FieldEvidenceApp_Application_Packs_SurveyDefinitionCoordinatorV1_swift {
    static let sharedReceipt = SharedActivityEnvelopeReceiptV1.self
    static let installationReceipt = InstallationActivityContractReceiptV1.self
    static let punchReceipt = PunchActivityContractReceiptV1.self
    static let noPlanFallback = NoPlanFallbackV1.self
    static let usesExistingInfrastructureOnly = true
    static let createsSecondWriterRendererStoreRouteOrInspectionAlias = false
}

enum C34RouteAdoptionBoundary_SurveyDefinitionCoordinatorV1 {
    static let packageSurfaceRegistration = C34PackageSurfaceRegistrationV1.self
    static let packageContributionKinds: [PackageSurfaceContributionKindV1] = [.destination, .navigationAction]
    static let packageRoutesUseExistingRoots = true
    static let packageRoutesStartAutomaticWork = false
}

// MARK: - C52 lifecycle and privacy boundary
enum C52ServiceRequestBoundary_FieldEvidenceApp_Application_Packs_SurveyDefinitionCoordinatorV1_swift {
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

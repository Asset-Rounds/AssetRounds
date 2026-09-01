import Foundation

enum C34ReportSnapshotNavigationBoundaryV1 {
    static let sceneStoresSnapshotBytes = false
    static let restorationRewritesSnapshot = false
}

extension ReportSnapshotV1 {
    func c34ValidateNavigationReference(
        _ target: NavigationTargetV1,
        workspaceID: WorkspaceID,
        expectedRevision: UInt64?
    ) throws {
        try C34NavigationReferenceAnchorV1.validate(
            target, workspaceID: workspaceID, stableEntityID: reportID,
            expectedRevision: expectedRevision
        )
    }
}

enum C51ReportSnapshotScheduleBoundaryV1 {
    static let scheduleClosureReferenceType = C51ScheduleClosureReferenceV1.self
    static let scheduleClosureMetadataType = C51ScheduleClosureMetadataV1.self
    static let scheduleClosureIsDerivedMetadataOnly = true
    static let reportCanonicalBytesRemainScheduleIndependent = true

    static func validate(_ metadata: C51ScheduleClosureMetadataV1) throws {
        try metadata.validate()
    }
}

extension ReportSnapshotV1 {
    /// Report construction may copy a capture-time interpretation but must
    /// never resolve it again against a later locator head.
    func assetLocatorProjection(
        resolution: LocatorResolutionV1,
        locator: AssetLocatorV1? = nil,
        interpretation: FrozenAssetLocatorInterpretationV1
    ) throws -> AssetLocatorReportProjectionV1 {
        try AssetLocatorReportProjectionV1(
            resolution: resolution,
            locator: locator,
            frozenInterpretation: interpretation
        )
    }
}

enum C50IncumbentReportSnapshotBoundaryV1 {
    static let historicExportUsesExactSnapshot = true
    static let adapterReplacementDoesNotRewriteSnapshot = true
    static let outputAvailabilityIsNotReportTruth = true
}

enum C30EvidenceContextReportSnapshotBoundaryV1 {
    static let snapshotCarriesRecordedContextOnly = true
    static let historicSnapshotImmutable = true
    static let solarProjectionMayImplyCompliance = false

    static func validate(context: EvidenceContextV1,
                         pairedLink: PairedObservationLinkV1? = nil,
                         workspaceID: WorkspaceID) throws {
        try C30EvidenceContextWorkflowBoundaryV1.validate(context: context,
                                                           pairedLink: pairedLink)
        guard context.workspaceID == workspaceID,
              snapshotCarriesRecordedContextOnly, historicSnapshotImmutable,
              !solarProjectionMayImplyCompliance else {
            throw EvidenceContextFailureV1.wrongWorkspace
        }
    }
}

struct ReportSnapshotV1: Codable, Equatable, Sendable {
    let acknowledgements: [AcknowledgementSnapshotV1]
    let asset: AssetSnapshotV1
    let couldNotVerify: CouldNotVerifySnapshotV1?
    let disclaimer: String
    let display: DisplaySnapshotV1
    let evidence: [EvidenceSnapshotV1]
    let evidenceSourceRecordID: UUID
    let history: [HistoryEntrySnapshotV1]
    let issues: [IssueSnapshotV1]
    let note: String?
    var observationBasis: ObservationBasisV1? = nil
    let outcome: String
    let pack: PackSnapshotV1
    let packetID: UUID
    let pdfTemplate: PDFTemplateReferenceV1
    let reportID: UUID
    let site: SiteSnapshotV1
    let snapshotCreatedAt: Date
    let snapshotSchemaVersion: Int
    let sourceApp: SourceAppSnapshotV1
    let sourceRecordID: UUID
    let stableRootID: UUID
    let stage: String
    var temporalContext: TemporalContextV1? = nil
    let timeContext: TimeContextSnapshotV1
    /// Optional, frozen requirement-assurance projection.  A missing value is
    /// the legacy snapshot shape; activation and production population remain
    /// owned by a later release surface.
    var requirementAssurance: RequirementAssuranceSnapshotV1? = nil
    /// Optional C38 accountability projection.  It freezes only recorded
    /// party/role/actor/qualification/signoff values and never asserts
    /// identity, authorization, legal effect, or external verification.
    var accountability: CompletedAccountabilitySnapshotV1? = nil
    /// Optional C39 asset-semantic projection.  It is a frozen view of
    /// canonical semantic/product/lifecycle/work-subject records only.
    var assetSemantics: CompletedAssetSemanticsSnapshotV1? = nil
    /// Optional C40 frozen authority, applicability, assessment, classification,
    /// severity, measurement-protocol, and derived-fact projection.
    var authorityCriterion: CompletedAuthorityCriterionSnapshotV1? = nil
    /// Optional C41 frozen functional-relationship descriptor/history snapshot.
    /// It is a typed report fact only; later events never mutate this value.
    var functionalRelationships: CompletedFunctionalRelationshipSnapshotV1? = nil
    /// Optional C13 preview-first evidence assurance binding. It is a
    /// read-only projection and never grants publication, delivery, approval,
    /// or release authority.
    var assurance: ReportEvidenceAssuranceProjectionV1? = nil
    /// Optional C14 frozen review, change-request, and corrective-action
    /// history. The value is an immutable projection over the exact completed
    /// snapshot boundary; amendments create a replacement snapshot and never
    /// rewrite this history in place.
    var inspectionReviewHistory: CompletedInspectionReviewHistorySnapshotV1? = nil
    /// Optional C15 packet-coordination projection. The completed packet
    /// snapshot remains the source of truth; this value contains only bounded
    /// item state/counts and exact provenance digests.
    var workPacket: ReportWorkPacketProjectionV1? = nil
    /// Optional C19 frozen measurement-integrity projection. It preserves
    /// fixed-point values, typed unit meaning, capture-time calibration facts,
    /// and bounded quality status without carrying operator or opaque serial
    /// detail into a report.
    var measurementIntegrity: MeasurementIntegrityReportProjectionV1? = nil
    /// Optional C20 audience-safe privacy-transform projection. It contains
    /// only the approved, current derivative binding; original access remains
    /// a separately authorized content operation.
    var privacyTransform: PrivacyTransformReportProjectionV1? = nil

    /// Optional C21 local client-capability and package-lifecycle projection.
    /// It contains only closed admission/operation/state values and digest
    /// bindings. Historic finalized snapshots remain readable after withdrawal
    /// and are never rewritten in place.
    var clientCapability: ClientCapabilityReportProjectionV1? = nil

    /// Optional C23 metadata-only field-reference projections. Reference
    /// bytes, locators, content IDs, and subject identity are never serialized
    /// into a report snapshot.
    var fieldReferences: [FieldReferenceReportProjectionV1]? = nil

    /// Optional C26 frozen guided-survey publication. Later promotion or
    /// correction produces another publication/report; it never rewrites this
    /// subject-at-publication or introduces pass/fail meaning.
    var surveyPublication: SurveyPublicationReportProjectionV1? = nil

    /// Optional C28 schedule projection. The canonical release and occurrence
    /// history remain authoritative; this field freezes the recorded time
    /// basis and bounded due/reminder metadata for a historic report.
    var scheduleProjection: ScheduleReportProjectionV1? = nil

    /// Optional C29 plan/rebase projection. It carries normalized placement
    /// metadata and frozen preview/receipt summaries without source bytes,
    /// private locators, actor identity, or an accuracy claim.
    var planProjection: PlanReportProjectionV1? = nil

    /// Optional C37 frozen placement-pose projection. It preserves the
    /// current tip and immutable observation history as reference-framed
    /// metadata; it never infers facing, alignment, accuracy, or compliance.
    var placementPose: C37PlacementPoseFrozenSnapshotV1? = nil

    /// Optional C17 frozen daylight-inventory projection. It contains only
    /// cautious recorded-state metadata and exact immutable source bindings;
    /// safety intake detail, route, actors, notes, and media remain excluded.
    var lightingDayInventory: C17LightingDayInventoryFrozenSnapshotV1? = nil

    /// Optional C18 immutable, metadata-only night-workflow projection.
    var lightingNightWorkflow: C18LightingNightFrozenSnapshotV1? = nil

    /// Optional C33 typed links into canonical temporal evidence. The snapshot
    /// carries bounded metadata and manual accessible text, never original
    /// bytes or private content locators.
    var temporalEvidenceLinks: [TemporalEvidenceReportLinkV1]? = nil

    /// C16 freezes the workspace classification at report creation. A missing
    /// projection deliberately means REAL, not unknown.
    var practiceWorkspace: PracticeWorkspaceReportProjectionV1? = nil

    var planHistoryProjection: PlanReportProjectionV1? {
        planProjection
    }

    var scheduleHistoryProjection: ScheduleReportProjectionV1? {
        scheduleProjection
    }

    var audienceSafeDerivativeProjection: PrivacyTransformReportProjectionV1? {
        privacyTransform
    }

    var privacyDerivativeProjection: PrivacyTransformReportProjectionV1? {
        privacyTransform
    }

    var privacyTransformProjection: PrivacyTransformReportProjectionV1? {
        privacyTransform
    }

    var clientCapabilityAdmission: ClientCapabilityReportProjectionV1? {
        clientCapability
    }

    var packageLifecycleProjection: ClientCapabilityReportProjectionV1? {
        clientCapability
    }

    var reviewHistory: [InspectionReviewTransitionV1] {
        inspectionReviewHistory?.reviewHistory ?? []
    }

    var changeHistory: [ChangeRequestV1] {
        inspectionReviewHistory?.changeHistory ?? []
    }

    var actionHistory: [CorrectiveActionEventV1] {
        inspectionReviewHistory?.actionHistory ?? []
    }
}

struct FrozenSurveyDefinitionSnapshotV1: Codable, Equatable, Sendable {
    let activityKind: ActivityKindV1
    let releaseID: UUID
    let definitionID: UUID
    let revision: UInt64
    let releaseSHA256: String
    init(_ value: SurveyDefinitionReleaseV1) throws { try value.validate(); activityKind=value.activityKind;releaseID=value.releaseID;definitionID=value.definitionID;revision=value.revision;releaseSHA256=value.releaseSHA256 }
}

enum ReportSnapshotAccessibleDocumentBoundaryV1{
    static let semanticTreeFieldStoredInSnapshot=false
    static let rebuildUsesFrozenSnapshotOnly=true
}

// MARK: - C23 metadata-only reference projection

extension ReportSnapshotV1 {
    /// Builds the existing audience-safe report projection only after proving
    /// that the binding names this report's packet generation. Reference bytes,
    /// locators, content IDs, and subject identity stay outside the report.
    func c23FieldReferenceProjection(
        binding: FieldReferenceBindingV1,
        release: FieldReferenceReleaseV1,
        readiness: FieldReferenceOfflineReadinessV1,
        subjectRevision: UInt64
    ) throws -> FieldReferenceReportProjectionV1 {
        guard binding.subjectKind == .workPacket,
              binding.subjectID == packetID,
              binding.subjectRevision == subjectRevision,
              binding.subjectState == .finalized else {
            throw WorkSessionFieldReferenceFailureV1.wrongSubject
        }
        let reference = try WorkSessionFieldReferenceProjectionV1(
            binding: binding, release: release, readiness: readiness
        )
        try reference.validate(
            expectedWorkspaceID: release.workspaceID,
            expectedSubjectKind: .workPacket,
            expectedSubjectID: packetID,
            expectedSubjectRevision: subjectRevision,
            expectedSubjectState: .finalized
        )
        return try FieldReferenceReportProjectionV1(
            release: release, binding: binding, readiness: readiness
        )
    }

    /// Re-validates a previously constructed C23 report projection against
    /// the immutable packet subject before it is encoded or exported.
    func c23ValidateFieldReferenceProjection(
        _ projection: FieldReferenceReportProjectionV1,
        binding: FieldReferenceBindingV1,
        release: FieldReferenceReleaseV1,
        readiness: FieldReferenceOfflineReadinessV1,
        subjectRevision: UInt64
    ) throws -> FieldReferenceReportProjectionV1 {
        let expected = try c23FieldReferenceProjection(
            binding: binding,
            release: release,
            readiness: readiness,
            subjectRevision: subjectRevision
        )
        guard projection == expected else {
            throw WorkSessionFieldReferenceFailureV1.staleBinding
        }
        return projection
    }

    /// Returns an additive snapshot carrying one validated, finalized
    /// field-reference projection. Existing snapshot fields and historical
    /// bytes remain unchanged; a different release requires an explicit new
    /// snapshot rather than an in-place rebind.
    func withC23FieldReferenceProjection(
        binding: FieldReferenceBindingV1,
        release: FieldReferenceReleaseV1,
        readiness: FieldReferenceOfflineReadinessV1,
        subjectRevision: UInt64
    ) throws -> ReportSnapshotV1 {
        let projection = try c23FieldReferenceProjection(
            binding: binding,
            release: release,
            readiness: readiness,
            subjectRevision: subjectRevision
        )
        var copy = self
        copy.fieldReferences = [projection]
        return copy
    }
}

struct C18LightingNightFrozenSnapshotV1:Codable,Equatable,Sendable{
    static let projectionVersion=C18LightingReportProjectionSupportV1.projectionVersion
    let sourceRecordID:UUID;let sourceWorkflowSHA256:String;let capturedAt:Date
    let patrol:LightingPatrolReferenceV1?;let projection:LightingReportProjectionV1;let projectionSHA256:String;let snapshotSHA256:String
    init(workflow:LightingNightWorkflowV1,capturedAt:Date)throws{
        try workflow.validateIntrinsic();try LightingLimitsV1.instant(capturedAt)
        sourceRecordID=workflow.recordID;sourceWorkflowSHA256=workflow.workflowSHA256;self.capturedAt=capturedAt;patrol=workflow.patrol
        projection=try C18LightingReportProjectionSupportV1.projection(workflow)
        projectionSHA256=try C18LightingReportProjectionSupportV1.digest(projection)
        snapshotSHA256=try LightingCanonicalCodecV1.sha256(Basis(sourceRecordID:workflow.recordID,sourceWorkflowSHA256:workflow.workflowSHA256,capturedAt:capturedAt,patrol:patrol,projection:projection,projectionSHA256:projectionSHA256))
        try validate()
    }
    func validate()throws{try LightingLimitsV1.id(sourceRecordID);try [sourceWorkflowSHA256,projectionSHA256,snapshotSHA256].forEach(LightingLimitsV1.digest);try LightingLimitsV1.instant(capturedAt);try patrol?.validate(workspaceID:projection.workspaceID);try C18LightingReportProjectionSupportV1.validate(projection);guard projection.workflowSHA256==sourceWorkflowSHA256,projection.patrol==patrol,projectionSHA256==(try C18LightingReportProjectionSupportV1.digest(projection)),snapshotSHA256==(try LightingCanonicalCodecV1.sha256(basis)) else{throw SnapshotProjectionFailureV1.digestMismatch}}
    private var basis:Basis{.init(sourceRecordID:sourceRecordID,sourceWorkflowSHA256:sourceWorkflowSHA256,capturedAt:capturedAt,patrol:patrol,projection:projection,projectionSHA256:projectionSHA256)}
    private struct Basis:Codable{let sourceRecordID:UUID;let sourceWorkflowSHA256:String;let capturedAt:Date;let patrol:LightingPatrolReferenceV1?;let projection:LightingReportProjectionV1;let projectionSHA256:String}
}

extension ReportSnapshotV1{func withC18LightingNightWorkflow(_ value:C18LightingNightFrozenSnapshotV1)throws->ReportSnapshotV1{try value.validate();var copy=self;copy.lightingNightWorkflow=value;return copy}}

struct AcknowledgementSnapshotV1: Codable, Equatable, Sendable {
    let accepted: Bool
    let copy: String
    let key: String
    let version: String
}

struct AssetSnapshotV1: Codable, Equatable, Sendable {
    let label: String
}

struct CouldNotVerifySnapshotV1: Codable, Equatable, Sendable {
    let display: String
    let key: String
    let registryVersion: String
}

struct DisplaySnapshotV1: Codable, Equatable, Sendable {
    let assetSingular: String
    let checkSingular: String
    let issueSingular: String
    let outcome: String
    let stage: String
}

struct EvidenceSnapshotV1: Codable, Equatable, Sendable {
    let byteCount: Int
    let createdAt: Date
    let evidenceID: UUID
    let mimeType: String
    let purposeDisplay: String
    let purposeKey: String
    let recordID: UUID
    let relativePath: String
    let sha256: String
    let thumbnailByteCount: Int
    let thumbnailRelativePath: String
    let thumbnailSHA256: String
}

struct HistoryEntrySnapshotV1: Codable, Equatable, Sendable {
    let completedAt: Date
    let couldNotVerify: CouldNotVerifySnapshotV1?
    let evidenceIDs: [UUID]
    let issueIDs: [UUID]
    let note: String?
    var observationBasis: ObservationBasisV1? = nil
    let outcome: String
    let outcomeDisplay: String
    let recordID: UUID
    let stage: String
    let stageDisplay: String
    var temporalContext: TemporalContextV1? = nil
    let workDescription: String?
    let workPerformedLocalDate: String?
}

struct IssueSnapshotV1: Codable, Equatable, Sendable {
    let createdAt: Date
    let display: String
    let issueID: UUID
    let key: String
    let openedByRecordID: UUID
    let resolvedByRecordID: UUID?
    let status: String
    let updatedAt: Date
}

struct PackSnapshotV1: Codable, Equatable, Sendable {
    let contentVersion: Int
    let id: String
    let schemaVersion: Int
}

struct PDFTemplateReferenceV1: Codable, Equatable, Sendable {
    let id: String
    let version: Int
}

struct SiteSnapshotV1: Codable, Equatable, Sendable {
    let address: String?
    let label: String
}

struct SourceAppSnapshotV1: Codable, Equatable, Sendable {
    let build: String
    let version: String
}

struct TimeContextSnapshotV1: Codable, Equatable, Sendable {
    let localDate: String
    let localTime: String
    let observedAtUTC: Date
    let timeZoneID: String
    let utcOffsetMinutes: Int
}

/// C29 typed integration anchor: this owner consumes an exact immutable plan
/// revision reference and may not reinterpret current plan state implicitly.
enum C29PlanIntegration_Domain_Workflow_ReportSnapshotV1 {
    static func validatePlanRevision(_ value: PlanRevisionReferenceV1) throws {
        try value.validate()
    }
}

enum C37PoseIntegration_FieldEvidenceApp_Domain_Workflow_ReportSnapshotV1_swift {
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

extension ReportSnapshotV1 {
    /// Adds a validated C37 pose snapshot without resolving a later current
    /// tip. A replacement report is required when the pose history changes.
    func withC37PlacementPose(
        _ pose: C37PlacementPoseFrozenSnapshotV1
    ) throws -> ReportSnapshotV1 {
        try pose.validate()
        var copy = self
        copy.placementPose = pose
        return copy
    }

    func c37ValidatePlacementPose() throws -> C37PlacementPoseFrozenSnapshotV1? {
        try placementPose?.validate()
        return placementPose
    }
}

struct C31LightingFrozenSnapshotBindingV1: Codable, Equatable, Sendable {
    let projection: C31LightingCompletedSnapshotReferenceV1
    let historicDisplayIsFrozen: Bool
    let sourceEvidenceRemainsSeparate: Bool

    init(projection: C31LightingReportProjectionV1) throws {
        self.projection = try C31LightingCompletedSnapshotReferenceV1(projection: projection)
        historicDisplayIsFrozen = true
        sourceEvidenceRemainsSeparate = true
        try validate()
    }

    func validate() throws {
        try projection.validate()
        guard historicDisplayIsFrozen, sourceEvidenceRemainsSeparate else {
            throw SnapshotProjectionFailureV1.historyRewrite
        }
    }
}
// MARK: - C32 assistance report snapshot boundary

enum C32AssistanceLifecycleBoundary_FieldEvidenceApp_Domain_Workflow_ReportSnapshotV1_swift {
    static let proposalIsPersistent = AssistancePersistenceEnrollmentV1.proposalIsPersistent
    static let rejectedProposalCorpusIsPersistent = AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent
    static let durableFamilyCount = AssistancePersistenceEnrollmentV1.durableModelCount
    static let acceptedMutationKind: WorkspaceCommandKindV1 = .applyAssistanceAcceptance
    static let manualFallback: ManualFallbackActionV1 = .typeManually
    static let proposalCannotRewriteFinalSnapshot = true

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

/// C45 reports may link an accepted manifest but never embed mutable scratch bytes.
enum C45AssetLabelBoundary_ReportSnapshotV1 {
    static func validate(_ snapshot: AcceptedLabelGenerationSnapshotV1) throws { try snapshot.validate() }
    static let embedsScratchArtifacts = false
}

enum C46OperationalContactConformance_FieldEvidenceApp_Domain_Workflow_ReportSnapshotV1_swift {
    static let operationalContactsRemainPurposeSeparated = true
    static let systemHandoffsRemainExplicitEphemeralAndNoncanonical = true
    static let subscriberConsentCampaignAndMeasurementProjectionForbidden = true
    static let contactExportExcludedByDefault = true
    static let siteRoleOwnershipForbidden = true
}

enum C47ActivityContractCompatibility_FieldEvidenceApp_Domain_Workflow_ReportSnapshotV1_swift {
    static let sharedEnvelopeDoesNotCollapseFamilyTruth = true
    static let installationAndPunchReceiptsRemainIndependent = true
    static let noPlanFallbackIsExplicit = true
    static let surveyDefinitionOwnershipIsPreserved = true
    static let legacyInspectionTruthIsNotRewritten = true
    static let threeReceiptIsolationIsRequired = true
}

enum C48PortableReviewReportSnapshotBoundaryV1 {
    static let reportSnapshotCarriesDerivedHistoryOnly = true
    static let capabilityProofIsExcluded = true
    static let rawResponseBytesAreExcluded = true
    static let responseBodyIsExcluded = true
    static let externalReviewCannotRewriteHistoricSnapshot = true

    static func validateDerivedHistory(
        _ projection: C48PortableReviewDerivedHistoryProjectionV1
    ) throws {
        try projection.validate()
    }
}

// MARK: - C49 report snapshot boundary

enum C49WorkResourceReportSnapshotBoundaryV1 {
    static let snapshotIsImmutableAfterAppend = true
    static let correctionCreatesNewSnapshot = true
    static let liveInventorySnapshotRows = false

    static func validate(_ envelope: C49WorkResourceProjectionEnvelopeV1) throws {
        try envelope.validate()
        guard envelope.projection.projectionSHA256.count == 64 else {
            throw C49WorkResourceProjectionFailureV1.nonCanonical
        }
    }
}
enum C52ServiceRequestBoundary_ReportSnapshotV1 {
    static let sourceKind: ServiceRequestSourceKindV1 = .portableSubmission
    static let requesterAssertionType: ServiceRequestRequesterAssertionV1.Type = ServiceRequestRequesterAssertionV1.self
    static let contactAssertionType: ServiceRequestContactAssertionV1.Type = ServiceRequestContactAssertionV1.self
    static let requesterIdentityIsUnverified: Bool = !PortableServiceRequestFormatBoundaryV1.requesterIdentityIsVerified
    static let contactAssertionWording: String = "SELF_ASSERTED_UNVERIFIED"
    static let urgencyIsUnverified: Bool = !PortableServiceRequestFormatBoundaryV1.urgencyIsVerified
    static let cleartextIsReadableAndForwardable: Bool = PortableServiceRequestFormatBoundaryV1.submissionIsCleartext && PortableServiceRequestFormatBoundaryV1.invitationIsReadableAndForwardable
    static let providerContactPurposeSeparationRequired: Bool = true
    static let canonicalSourceBytesAreAuthoritative: Bool = true
    static let duplicateCandidatesAreDerived: Bool = !ServiceRequestNoncanonicalBoundaryV1.duplicateProjectionIsPersistent
    static let rawCapabilityMayBecomeWorkspaceTruth: Bool = ServiceRequestNoncanonicalBoundaryV1.rawCapabilityIsWorkspaceTruth
    static let automaticWorkOrDuplicateActionPermitted: Bool = ServiceRequestNoncanonicalBoundaryV1.automaticWorkCreationPermitted || ServiceRequestNoncanonicalBoundaryV1.automaticDuplicateMergePermitted
    static let excludedSurfaces: [String] = ["REPORT", "SEARCH", "DIAGNOSTIC", "LIFECYCLE", "COMPATIBILITY", "BACKUP", "DELETE"]
}

// MARK: - C53 reliability snapshot boundary

/// Reliability is an additive report projection. It does not add an optional
/// field to the frozen legacy snapshot shape or make the snapshot mutable.
enum C53ServiceReliabilityReportSnapshotBoundaryV1 {
    static let snapshotType: ReportSnapshotV1.Type = ReportSnapshotV1.self
    static let projectionType: C53ServiceReliabilityReportProjectionV1.Type =
        C53ServiceReliabilityReportProjectionV1.self
    static let projectionIsOptionalAndAdditive = true
    static let historicSnapshotBytesAreRewritten = false
    static let unavailableMetricsRemainUnavailable = true

    static func validate(
        _ projection: C53ServiceReliabilityReportProjectionV1
    ) throws {
        try projection.validate()
    }
}

struct PracticeWorkspaceReportProjectionV1: Codable, Equatable, Sendable {
    static let mandatoryWatermark = "PRACTICE — NOT FOR FIELD USE"
    let workspaceID: WorkspaceID
    let kind: WorkspaceExperienceWorkspaceKindV1
    let provenanceID: UUID?
    let provenanceSHA256: String?
    let watermark: String?

    init(workspaceID: WorkspaceID, provenance: PracticeWorkspaceProvenanceV1?) throws {
        self.workspaceID = workspaceID
        kind = try WorkspaceExperienceClassificationV1.kind(provenance: provenance)
        provenanceID = provenance?.provenanceID
        provenanceSHA256 = provenance?.provenanceSHA256
        watermark = provenance == nil ? nil : Self.mandatoryWatermark
        try validate()
    }

    func validate() throws {
        guard (kind == .real && provenanceID == nil && provenanceSHA256 == nil && watermark == nil)
                || (kind == .practice && provenanceID != nil && provenanceSHA256 != nil && watermark == Self.mandatoryWatermark) else {
            throw WorkspaceExperienceFailureV1.invalidValue
        }
    }
}

// MARK: - C17 exterior-lighting day inventory report snapshot

struct C17LightingDayConditionReportProjectionV1: Codable, Equatable, Comparable, Sendable {
    let luminaireID: UUID
    let assetID: UUID
    let zoneID: UUID
    let controlGroupID: UUID
    let facts: [LightingDayConditionFactV1]
    let poseDisposition: LightingDayPoseDispositionV1
    let poseEvent: AssetPoseEventReferenceV1?
    let pose: C37PlacementPoseFrozenSnapshotV1?
    let snapshotSHA256: String

    init(
        snapshot: LightingDayConditionSnapshotV1,
        pose: C37PlacementPoseFrozenSnapshotV1?
    ) throws {
        try snapshot.validate(); try pose?.validate()
        if snapshot.poseDisposition == .notDeclared {
            guard snapshot.poseEvent == nil, pose == nil else {
                throw LightingDayInventoryFailureV1.staleReference
            }
        } else {
            guard let event = snapshot.poseEvent, let pose,
                  pose.projection.workspaceID == snapshot.observation.workspaceID,
                  pose.projection.assetID == snapshot.assetID,
                  pose.projection.history.contains(where: {
                      $0.eventID == event.eventID
                        && $0.axisID == event.axisID.rawValue
                        && $0.revision == event.revision
                        && $0.eventSHA256 == event.eventSHA256
                  }) else {
                throw LightingDayInventoryFailureV1.staleReference
            }
        }
        luminaireID = snapshot.luminaireID
        assetID = snapshot.assetID
        zoneID = snapshot.zoneID
        controlGroupID = snapshot.controlGroupID
        facts = snapshot.facts
        poseDisposition = snapshot.poseDisposition
        poseEvent = snapshot.poseEvent
        self.pose = pose
        snapshotSHA256 = snapshot.snapshotSHA256
        try validate()
    }

    func validate() throws {
        try [luminaireID, assetID, zoneID, controlGroupID]
            .forEach(LightingDayInventoryLimitsV1.id)
        try facts.forEach { try $0.validate() }
        try poseEvent?.validate()
        try pose?.validate()
        try LightingDayInventoryLimitsV1.digest(snapshotSHA256)
        let notDeclared = poseDisposition == .notDeclared
        let hasPoseBinding = poseEvent != nil && pose != nil
        guard !facts.isEmpty,
              facts == facts.sorted(),
              Set(facts.map(\.aspect)).count == facts.count,
              notDeclared == !hasPoseBinding,
              poseEvent.map({ $0.assetID == assetID && $0.axisID == .lightBeamCenterline }) ?? notDeclared,
              pose.map({ value in
                  guard let poseEvent else { return false }
                  return value.projection.assetID == assetID
                    && value.projection.history.contains(where: {
                        $0.eventID == poseEvent.eventID
                          && $0.axisID == poseEvent.axisID.rawValue
                          && $0.revision == poseEvent.revision
                          && $0.eventSHA256 == poseEvent.eventSHA256
                    })
              }) ?? notDeclared else {
            throw LightingDayInventoryFailureV1.invalidValue
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.zoneID.uuidString, lhs.controlGroupID.uuidString, lhs.luminaireID.uuidString)
            < (rhs.zoneID.uuidString, rhs.controlGroupID.uuidString, rhs.luminaireID.uuidString)
    }
}

struct C17LightingDayInventoryReportProjectionV1: Codable, Equatable, Sendable {
    static let projectionVersion = "C17_LIGHTING_DAY_REPORT_V1"
    static let claimBoundary = "OBSERVATION_ONLY_NOT_PHOTOMETRY_DIAGNOSIS_ADEQUACY_COMMISSIONING_OR_NIGHT_PASS"
    let projectionVersion: String
    let workspaceID: WorkspaceID
    let workflowID: UUID
    let workflowRevision: UInt64
    let workflowSHA256: String
    let systemID: UUID
    let systemRevision: UInt64
    let systemSHA256: String
    let packageRelease: LightingPackageReleaseReferenceV1
    let state: LightingDayInventoryWorkflowStateV1
    let conditions: [C17LightingDayConditionReportProjectionV1]
    let unknownOrNotObservedCount: Int
    let daylightEnergizedObservationCount: Int
    let nightFollowupPlanID: UUID?
    let nightFollowupPlanSHA256: String?
    let offlineReadinessSourceSHA256: String?
    let offlineReadinessManifestSHA256: String?
    let claimBoundary: String
    let projectionSHA256: String

    init(
        workflow: LightingDayInventoryWorkflowV1,
        poseSnapshots: [C37PlacementPoseFrozenSnapshotV1]
    ) throws {
        let source = try LightingDayInventoryProjectionV1(workflow)
        guard source.reportEligible else { throw LightingDayInventoryFailureV1.safetyStop }
        try poseSnapshots.forEach { try $0.validate() }
        let poseByAsset = Dictionary(grouping: poseSnapshots, by: { $0.projection.assetID })
        let declaredPoseAssets = Set(workflow.conditionSnapshots.compactMap {
            $0.poseEvent?.assetID
        })
        guard poseByAsset.values.allSatisfy({ $0.count == 1 }),
              Set(poseByAsset.keys) == declaredPoseAssets else {
            throw LightingDayInventoryFailureV1.staleReference
        }
        let projected = try workflow.conditionSnapshots.map { snapshot in
            return try C17LightingDayConditionReportProjectionV1(
                snapshot: snapshot, pose: poseByAsset[snapshot.assetID]?.first
            )
        }.sorted()
        projectionVersion = Self.projectionVersion
        workspaceID = workflow.workspaceID
        workflowID = workflow.workflowID
        workflowRevision = workflow.revision
        workflowSHA256 = workflow.workflowSHA256
        systemID = workflow.systemID
        systemRevision = workflow.systemRevision
        systemSHA256 = workflow.systemSHA256
        packageRelease = workflow.packageRelease
        state = workflow.state
        conditions = projected
        unknownOrNotObservedCount = source.unknownOrNotObservedCount
        daylightEnergizedObservationCount = projected.flatMap(\.facts).filter {
            $0.aspect == .daylightEnergized && $0.state == .observedPresent
        }.count
        nightFollowupPlanID = workflow.nightFollowupPlan?.planID
        nightFollowupPlanSHA256 = workflow.nightFollowupPlan?.planSHA256
        offlineReadinessSourceSHA256 = workflow.nightFollowupPlan?.offlineReadinessSourceSHA256
        offlineReadinessManifestSHA256 = workflow.nightFollowupPlan?.offlineReadinessManifestSHA256
        claimBoundary = Self.claimBoundary
        projectionSHA256 = try LightingDayInventoryCanonicalCodecV1.sha256(basisWithoutDigest)
        try validate()
    }

    func validate() throws {
        try [workflowID, systemID].forEach(LightingDayInventoryLimitsV1.id)
        try [workflowRevision, systemRevision].forEach(LightingDayInventoryLimitsV1.revision)
        try [workflowSHA256, systemSHA256, projectionSHA256]
            .forEach(LightingDayInventoryLimitsV1.digest)
        try packageRelease.validate(); try conditions.forEach { try $0.validate() }
        try nightFollowupPlanID.map(LightingDayInventoryLimitsV1.id)
        try nightFollowupPlanSHA256.map(LightingDayInventoryLimitsV1.digest)
        try offlineReadinessSourceSHA256.map(LightingDayInventoryLimitsV1.digest)
        try offlineReadinessManifestSHA256.map(LightingDayInventoryLimitsV1.digest)
        let hasAnyNightBinding = nightFollowupPlanID != nil
            || nightFollowupPlanSHA256 != nil
            || offlineReadinessSourceSHA256 != nil
            || offlineReadinessManifestSHA256 != nil
        let hasCompleteNightBinding = nightFollowupPlanID != nil
            && nightFollowupPlanSHA256 != nil
            && offlineReadinessSourceSHA256 != nil
            && offlineReadinessManifestSHA256 != nil
        guard projectionVersion == Self.projectionVersion,
              state != .safetyStopped,
              !conditions.isEmpty,
              conditions == conditions.sorted(),
              Set(conditions.map(\.luminaireID)).count == conditions.count,
              unknownOrNotObservedCount == conditions.flatMap(\.facts).filter({
                  $0.state == .unknown || $0.state == .notObserved
              }).count,
              daylightEnergizedObservationCount == conditions.flatMap(\.facts).filter({
                  $0.aspect == .daylightEnergized && $0.state == .observedPresent
              }).count,
              hasAnyNightBinding == hasCompleteNightBinding,
              (state == .nightFollowupPrepared) == hasCompleteNightBinding,
              claimBoundary == Self.claimBoundary,
              projectionSHA256 == (try LightingDayInventoryCanonicalCodecV1.sha256(basisWithoutDigest)) else {
            throw LightingDayInventoryFailureV1.invalidValue
        }
    }

    private var basisWithoutDigest: Basis {
        .init(projectionVersion: projectionVersion, workspaceID: workspaceID,
              workflowID: workflowID, workflowRevision: workflowRevision,
              workflowSHA256: workflowSHA256, systemID: systemID,
              systemRevision: systemRevision, systemSHA256: systemSHA256,
              packageRelease: packageRelease, state: state, conditions: conditions,
              unknownOrNotObservedCount: unknownOrNotObservedCount,
              daylightEnergizedObservationCount: daylightEnergizedObservationCount,
              nightFollowupPlanID: nightFollowupPlanID,
              nightFollowupPlanSHA256: nightFollowupPlanSHA256,
              offlineReadinessSourceSHA256: offlineReadinessSourceSHA256,
              offlineReadinessManifestSHA256: offlineReadinessManifestSHA256,
              claimBoundary: claimBoundary)
    }
    private struct Basis: Codable {
        let projectionVersion: String; let workspaceID: WorkspaceID
        let workflowID: UUID; let workflowRevision: UInt64; let workflowSHA256: String
        let systemID: UUID; let systemRevision: UInt64; let systemSHA256: String
        let packageRelease: LightingPackageReleaseReferenceV1
        let state: LightingDayInventoryWorkflowStateV1
        let conditions: [C17LightingDayConditionReportProjectionV1]
        let unknownOrNotObservedCount: Int; let daylightEnergizedObservationCount: Int
        let nightFollowupPlanID: UUID?; let nightFollowupPlanSHA256: String?
        let offlineReadinessSourceSHA256: String?; let offlineReadinessManifestSHA256: String?
        let claimBoundary: String
    }
}

struct C17LightingDayInventoryFrozenSnapshotV1: Codable, Equatable, Sendable {
    let sourceRecordID: UUID
    let sourceWorkflowSHA256: String
    let capturedAt: Date
    let projection: C17LightingDayInventoryReportProjectionV1
    let snapshotSHA256: String

    init(
        workflow: LightingDayInventoryWorkflowV1,
        poseSnapshots: [C37PlacementPoseFrozenSnapshotV1],
        capturedAt: Date
    ) throws {
        try LightingDayInventoryLimitsV1.instant(capturedAt)
        sourceRecordID = workflow.recordID
        sourceWorkflowSHA256 = workflow.workflowSHA256
        self.capturedAt = capturedAt
        projection = try .init(workflow: workflow, poseSnapshots: poseSnapshots)
        snapshotSHA256 = try LightingDayInventoryCanonicalCodecV1.sha256(Basis(
            sourceRecordID: workflow.recordID,
            sourceWorkflowSHA256: workflow.workflowSHA256,
            capturedAt: capturedAt, projection: projection
        ))
        try validate()
    }

    func validate() throws {
        try LightingDayInventoryLimitsV1.id(sourceRecordID)
        try [sourceWorkflowSHA256, snapshotSHA256]
            .forEach(LightingDayInventoryLimitsV1.digest)
        try LightingDayInventoryLimitsV1.instant(capturedAt)
        try projection.validate()
        guard projection.workflowSHA256 == sourceWorkflowSHA256,
              snapshotSHA256 == (try LightingDayInventoryCanonicalCodecV1.sha256(basis)) else {
            throw LightingDayInventoryFailureV1.invalidDigest
        }
    }

    private var basis: Basis {
        .init(sourceRecordID: sourceRecordID, sourceWorkflowSHA256: sourceWorkflowSHA256,
              capturedAt: capturedAt, projection: projection)
    }
    private struct Basis: Codable {
        let sourceRecordID: UUID; let sourceWorkflowSHA256: String
        let capturedAt: Date; let projection: C17LightingDayInventoryReportProjectionV1
    }
}

extension ReportSnapshotV1 {
    func withC17LightingDayInventory(
        _ value: C17LightingDayInventoryFrozenSnapshotV1
    ) throws -> ReportSnapshotV1 {
        try value.validate()
        var copy = self
        copy.lightingDayInventory = value
        return copy
    }
}

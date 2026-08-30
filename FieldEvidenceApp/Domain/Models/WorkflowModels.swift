import Foundation
enum EvidenceContextWorkflowBoundaryV1{static let workflowRowsDoNotOwnEvidenceContext=true;static let pairedObservationStateIsDerivedFromImmutableLinks=true}
enum PlacementPoseWorkflowPersistenceBoundaryV1{static let workflowRowsOwnNoPoseHistory=true;static let completedPoseSnapshotsAreDerived=true}
import SwiftData

enum C34WorkflowModelNavigationBoundaryV1 {
    static let workflowRowStoresRouteState = false
    static let routeSnapshotCopiesWorkflowPayload = false
    static let restorationMutatesWorkflowRow = false
}

enum PlanWorkflowPersistenceBoundaryV1 { static let rebasePreviewIsDerived = true; static let framesAreEmbeddedInRevision = true }

enum WorkflowRecordAssetLocatorBoundaryV1 {
    static let locatorCurrentProjectionStoredOnWorkflowRow = false

    static func validateCapture(
        _ interpretation: FrozenAssetLocatorInterpretationV1,
        assetID: UUID
    ) throws {
        try interpretation.validate()
        guard interpretation.assetIDAtCapture == assetID else {
            throw AssetLocatorFailureV1.invalidValue
        }
    }
}

enum C47ActivityContractWorkflowModelBoundaryV2 {
    static let canonicalFamilies = ActivityContractPersistenceEnrollmentV2.persistentFamilies
    static let noPlanFallbackAndConformanceReceiptsAreNonpersistent = true
}

@Model
final class DeletionLedgerRow {
    var schemaVersion: Int
    @Attribute(.unique) var typedID: String
    var deletedAt: Date

    init(typedID: String, deletedAt: Date, schemaVersion: Int = 2) {
        self.schemaVersion = schemaVersion
        self.typedID = typedID
        self.deletedAt = deletedAt
    }
}

enum SurveySessionPersistenceBoundaryV1 {
    static let durableFamilies=C26SurveyPackageBindingLifecycleV1.persistentFamilies
    static let publicationStorage="IMMUTABLE"
    static let conflictPolicy="EXPLICIT_RESOLUTION_NO_LAST_WRITE_WINS"
    static let previewPersistence="NONPERSISTENT"
    static func validate()throws{try C26SurveyPackageBindingLifecycleV1.validate();guard durableFamilies.count==5,publicationStorage=="IMMUTABLE",previewPersistence=="NONPERSISTENT"else{throw SurveySessionFailureV1.invalidValue}}
}

enum SurveyDefinitionPersistenceBoundaryV1 {
    static let durableFamilies = ["SurveyDefinitionIdentityV1", "SurveyDefinitionReleaseV1"]
    static let lifecycleEventStorage = "MUTATION_JOURNAL"
    static let currentProjectionStorage = "NONPERSISTENT"
}

@Model
final class WorkflowRecord {
    @Attribute(.unique) var id: UUID
    var schemaVersion: Int
    var assetID: UUID
    var packetID: UUID?
    var issueID: UUID?
    var parentRecordID: UUID?
    private(set) var recordRevisionRootID: UUID
    var revisesRecordID: UUID?
    var evidenceSourceRecordID: UUID?
    var revisionKind: String
    var stage: String
    var state: String
    var draftStepKey: String?
    var startedAt: Date
    var completedAt: Date?
    var observedAtUTC: Date?
    var timeZoneID: String?
    var utcOffsetMinutes: Int?
    var localDate: String?
    var localTime: String?
    var afterDarkAcknowledgementKey: String?
    var afterDarkAcknowledgementCopy: String?
    var afterDarkAcknowledgementVersion: String?
    var afterDarkAcknowledgementAccepted: Bool?
    var safePositionAcknowledgementKey: String?
    var safePositionAcknowledgementCopy: String?
    var safePositionAcknowledgementVersion: String?
    var safePositionAcknowledgementAccepted: Bool?
    var packID: String
    var packSchemaVersion: Int
    var packContentVersion: Int
    var pdfTemplateID: String
    var pdfTemplateVersion: Int
    var outcomeKey: String?
    var couldNotVerifyKey: String?
    var couldNotVerifyDisplaySnapshot: String?
    var couldNotVerifyRegistryVersion: String?
    var workPerformedLocalDate: String?
    var workDescription: String?
    var note: String?
    @Attribute(.unique) var finalizationMutationID: UUID?

    init(
        id: UUID,
        assetID: UUID,
        packetID: UUID?,
        issueID: UUID?,
        parentRecordID: UUID?,
        recordRevisionRootID: UUID,
        revisesRecordID: UUID?,
        evidenceSourceRecordID: UUID?,
        revisionKind: WorkflowRevisionKind,
        stage: WorkflowStage,
        state: WorkflowState,
        draftStepKey: WorkflowDraftStep?,
        startedAt: Date,
        completedAt: Date?,
        observedAtUTC: Date?,
        timeZoneID: String?,
        utcOffsetMinutes: Int?,
        localDate: String?,
        localTime: String?,
        afterDarkAcknowledgementKey: String?,
        afterDarkAcknowledgementCopy: String?,
        afterDarkAcknowledgementVersion: String?,
        afterDarkAcknowledgementAccepted: Bool?,
        safePositionAcknowledgementKey: String?,
        safePositionAcknowledgementCopy: String?,
        safePositionAcknowledgementVersion: String?,
        safePositionAcknowledgementAccepted: Bool?,
        packID: String,
        packSchemaVersion: Int,
        packContentVersion: Int,
        pdfTemplateID: String,
        pdfTemplateVersion: Int,
        outcomeKey: String?,
        couldNotVerifyKey: String?,
        couldNotVerifyDisplaySnapshot: String?,
        couldNotVerifyRegistryVersion: String?,
        workPerformedLocalDate: String?,
        workDescription: String?,
        note: String?,
        finalizationMutationID: UUID?
    ) {
        self.id = id
        self.schemaVersion = 1
        self.assetID = assetID
        self.packetID = packetID
        self.issueID = issueID
        self.parentRecordID = parentRecordID
        self.recordRevisionRootID = recordRevisionRootID
        self.revisesRecordID = revisesRecordID
        self.evidenceSourceRecordID = evidenceSourceRecordID
        self.revisionKind = revisionKind.rawValue
        self.stage = stage.rawValue
        self.state = state.rawValue
        self.draftStepKey = draftStepKey?.rawValue
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.observedAtUTC = observedAtUTC
        self.timeZoneID = timeZoneID
        self.utcOffsetMinutes = utcOffsetMinutes
        self.localDate = localDate
        self.localTime = localTime
        self.afterDarkAcknowledgementKey = afterDarkAcknowledgementKey
        self.afterDarkAcknowledgementCopy = afterDarkAcknowledgementCopy
        self.afterDarkAcknowledgementVersion = afterDarkAcknowledgementVersion
        self.afterDarkAcknowledgementAccepted = afterDarkAcknowledgementAccepted
        self.safePositionAcknowledgementKey = safePositionAcknowledgementKey
        self.safePositionAcknowledgementCopy = safePositionAcknowledgementCopy
        self.safePositionAcknowledgementVersion = safePositionAcknowledgementVersion
        self.safePositionAcknowledgementAccepted = safePositionAcknowledgementAccepted
        self.packID = packID
        self.packSchemaVersion = packSchemaVersion
        self.packContentVersion = packContentVersion
        self.pdfTemplateID = pdfTemplateID
        self.pdfTemplateVersion = pdfTemplateVersion
        self.outcomeKey = outcomeKey
        self.couldNotVerifyKey = couldNotVerifyKey
        self.couldNotVerifyDisplaySnapshot = couldNotVerifyDisplaySnapshot
        self.couldNotVerifyRegistryVersion = couldNotVerifyRegistryVersion
        self.workPerformedLocalDate = workPerformedLocalDate
        self.workDescription = workDescription
        self.note = note
        self.finalizationMutationID = finalizationMutationID
    }
}

@Model
final class EvidenceFile {
    @Attribute(.unique) var id: UUID
    var schemaVersion: Int
    var recordID: UUID
    var purposeKey: String
    var relativePath: String
    var mimeType: String
    var byteCount: Int
    var sha256: String
    var createdAt: Date
    var thumbnailRelativePath: String
    var thumbnailByteCount: Int
    var thumbnailSHA256: String

    init(
        id: UUID,
        recordID: UUID,
        purposeKey: String,
        relativePath: String,
        mimeType: String,
        byteCount: Int,
        sha256: String,
        createdAt: Date,
        thumbnailRelativePath: String,
        thumbnailByteCount: Int,
        thumbnailSHA256: String
    ) {
        self.id = id
        self.schemaVersion = 1
        self.recordID = recordID
        self.purposeKey = purposeKey
        self.relativePath = relativePath
        self.mimeType = mimeType
        self.byteCount = byteCount
        self.sha256 = sha256
        self.createdAt = createdAt
        self.thumbnailRelativePath = thumbnailRelativePath
        self.thumbnailByteCount = thumbnailByteCount
        self.thumbnailSHA256 = thumbnailSHA256
    }
}

// MARK: - C19 workflow binding

extension WorkflowRecord {
    /// The frozen V4 SwiftData row remains unchanged. C19 measurements bind
    /// through the existing package identity and do not add a parallel
    /// workflow store or outcome-derived compliance state.
    func c19ValidateMeasurementCapture(
        _ capture: MeasurementCaptureV1,
        against release: InspectionPackageReleaseV1
    ) throws {
        try release.c19ValidateMeasurementCapture(capture)
        guard packID == release.packageID,
              packContentVersion == release.packageContentVersion else {
            throw MeasurementIntegrityFailureV1.staleReference
        }
    }

    /// Validates a reviewed C20 derivative at the existing workflow boundary.
    /// The workflow row remains frozen: this is a read-only projection check
    /// and never changes outcome, completion, or original-content identity.
    func c20ValidateReviewedDerivative(
        manifest: PrivacyTransformManifestV1,
        review: PrivacyReviewReceiptV1?,
        policy: PrivacyTransformPolicyV1,
        requestedAudience: EvidenceAudienceV1,
        currentSourceRevision: UInt64,
        currentSourceSHA256: String,
        at now: Date
    ) throws -> ContentReferenceV1 {
        guard id != PartyAccountabilityValidationV1.zero,
              assetID != PartyAccountabilityValidationV1.zero else {
            throw PrivacyTransformFailureV1.invalidValue
        }
        return try C20PrivacyProjectionBridgeV1.requireAllowed(
            manifest: manifest,
            review: review,
            policy: policy,
            requestedAudience: requestedAudience,
            currentSourceRevision: currentSourceRevision,
            currentSourceSHA256: currentSourceSHA256,
            at: now
        )
    }

    /// Binds the frozen workflow row to the C21 capability/lifecycle
    /// decision.  Admission is evaluated against the exact profile, policy,
    /// disposition, and package release; the workflow row remains a stored
    /// history record and never becomes a second lifecycle authority.
    func c21ValidatePackageLifecycle(
        admittedBy capability: ClientCapabilityLifecycleClosureV1,
        operation: PackageLifecycleOperationV1? = nil,
        historic: Bool = false
    ) throws {
        guard let workflowState = WorkflowState(rawValue: state) else {
            throw ClientCapabilityFailureV1.invalidValue
        }
        guard packID == capability.release.packageID,
              packContentVersion == capability.release.packageContentVersion else {
            throw ClientCapabilityFailureV1.staleReference
        }

        let requestedOperation = operation ?? capability.decision.operation
        let isHistoric = historic || workflowState == .completed
        let historicOperations: Set<PackageLifecycleOperationV1> = [
            .view, .export, .restore, .replay
        ]

        // A finalized row can still be viewed, exported, restored, or
        // replayed as history, but cannot be used for a new mutation.
        guard !isHistoric || historicOperations.contains(requestedOperation) else {
            throw ClientCapabilityFailureV1.admissionDenied
        }
        if [.start, .resume, .upgradeDraft].contains(requestedOperation) {
            guard !isHistoric, workflowState == .draft else {
                throw ClientCapabilityFailureV1.admissionDenied
            }
        }

        try C21CapabilityAdmissionBoundaryV1.validate(
            capability,
            for: requestedOperation,
            historic: isHistoric
        )
    }
}

// MARK: - C23 field-reference binding

extension WorkflowRecord {
    /// Workflow records are historical consumers of a packet binding. The
    /// record never stores a second release identity; callers must provide the
    /// exact canonical release and readiness tuple for this read-only check.
    func c23ValidateFieldReferenceBinding(
        workspaceID: WorkspaceID,
        binding: FieldReferenceBindingV1,
        release: FieldReferenceReleaseV1,
        readiness: FieldReferenceOfflineReadinessV1,
        subjectRevision: UInt64,
        subjectState: FieldReferenceSubjectStateV1? = nil
    ) throws -> WorkSessionFieldReferenceProjectionV1 {
        guard let packetID,
              binding.subjectKind == .workPacket,
              binding.subjectID == packetID,
              binding.subjectRevision == subjectRevision,
              binding.workspaceID == workspaceID else {
            throw WorkSessionFieldReferenceFailureV1.wrongSubject
        }
        guard let workflowState = WorkflowState(rawValue: state) else {
            throw WorkSessionFieldReferenceFailureV1.invalidValue
        }
        let expectedState: FieldReferenceSubjectStateV1 =
            workflowState == .completed ? .finalized : .active
        guard binding.subjectState == (subjectState ?? expectedState),
              binding.subjectState == expectedState else {
            throw WorkSessionFieldReferenceFailureV1.finalizedWorkImmutable
        }
        let projection = try WorkSessionFieldReferenceProjectionV1(
            binding: binding, release: release, readiness: readiness
        )
        try projection.validate(
            expectedWorkspaceID: workspaceID,
            expectedSubjectKind: .workPacket,
            expectedSubjectID: packetID,
            expectedSubjectRevision: subjectRevision,
            expectedSubjectState: expectedState
        )
        return projection
    }
}

extension Packet {
    /// Packet-level consumers use the same immutable binding proof as the
    /// record path. The packet model remains unchanged and owns no reference
    /// bytes or locators.
    func c23ValidateFieldReferenceBinding(
        workspaceID: WorkspaceID,
        binding: FieldReferenceBindingV1,
        release: FieldReferenceReleaseV1,
        readiness: FieldReferenceOfflineReadinessV1,
        subjectRevision: UInt64,
        subjectState: FieldReferenceSubjectStateV1 = .active
    ) throws -> WorkSessionFieldReferenceProjectionV1 {
        guard binding.subjectKind == .workPacket,
              binding.subjectID == id,
              binding.subjectRevision == subjectRevision,
              binding.subjectState == subjectState,
              binding.workspaceID == workspaceID else {
            throw WorkSessionFieldReferenceFailureV1.wrongSubject
        }
        let projection = try WorkSessionFieldReferenceProjectionV1(
            binding: binding, release: release, readiness: readiness
        )
        try projection.validate(
            expectedWorkspaceID: workspaceID,
            expectedSubjectKind: .workPacket,
            expectedSubjectID: id,
            expectedSubjectRevision: subjectRevision,
            expectedSubjectState: subjectState
        )
        return projection
    }
}

@Model
final class Issue {
    @Attribute(.unique) var id: UUID
    var schemaVersion: Int
    var assetID: UUID
    var openedByRecordID: UUID
    private(set) var labelKey: String
    private(set) var labelDisplaySnapshot: String
    var status: String
    var resolvedByRecordID: UUID?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID,
        assetID: UUID,
        openedByRecordID: UUID,
        labelKey: String,
        labelDisplaySnapshot: String,
        status: IssueStatus,
        resolvedByRecordID: UUID?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.schemaVersion = 1
        self.assetID = assetID
        self.openedByRecordID = openedByRecordID
        self.labelKey = labelKey
        self.labelDisplaySnapshot = labelDisplaySnapshot
        self.status = status.rawValue
        self.resolvedByRecordID = resolvedByRecordID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class Packet {
    @Attribute(.unique) var id: UUID
    var schemaVersion: Int
    @Attribute(.unique) private(set) var stableRootID: UUID
    var currentRecordID: UUID?
    var evaluationCounted: Bool
    var contentDeletedAt: Date?
    var createdAt: Date

    init(
        id: UUID,
        stableRootID: UUID,
        currentRecordID: UUID?,
        evaluationCounted: Bool,
        contentDeletedAt: Date?,
        createdAt: Date
    ) {
        self.id = id
        self.schemaVersion = 1
        self.stableRootID = stableRootID
        self.currentRecordID = currentRecordID
        self.evaluationCounted = evaluationCounted
        self.contentDeletedAt = contentDeletedAt
        self.createdAt = createdAt
    }
}

@Model
final class Report {
    @Attribute(.unique) var id: UUID
    var schemaVersion: Int
    private(set) var packetID: UUID
    private(set) var sourceRecordID: UUID
    private(set) var snapshotSchemaVersion: Int
    private(set) var snapshotRelativePath: String
    private(set) var snapshotSHA256: String
    var pdfState: String
    var pdfRelativePath: String?
    var pdfSHA256: String?
    private(set) var createdAt: Date
    private(set) var replacesReportID: UUID?

    init(
        id: UUID,
        packetID: UUID,
        sourceRecordID: UUID,
        snapshotSchemaVersion: Int,
        snapshotRelativePath: String,
        snapshotSHA256: String,
        pdfState: ReportPDFState,
        pdfRelativePath: String?,
        pdfSHA256: String?,
        createdAt: Date,
        replacesReportID: UUID?
    ) {
        self.id = id
        self.schemaVersion = 1
        self.packetID = packetID
        self.sourceRecordID = sourceRecordID
        self.snapshotSchemaVersion = snapshotSchemaVersion
        self.snapshotRelativePath = snapshotRelativePath
        self.snapshotSHA256 = snapshotSHA256
        self.pdfState = pdfState.rawValue
        self.pdfRelativePath = pdfRelativePath
        self.pdfSHA256 = pdfSHA256
        self.createdAt = createdAt
        self.replacesReportID = replacesReportID
    }
}

/// Executable V27 partition assertion: canonical workflow rows remain inherited
/// while schedule state is represented only by immutable release/history rows.
enum WorkflowSchedulePersistenceEnrollmentV1 {
    static func validate() throws {
        let v26 = PersistentSchemaV26.models.map { ObjectIdentifier($0) }
        let v27 = PersistentSchemaV27.models.map { ObjectIdentifier($0) }
        let v38 = PersistentSchemaV38.models.map { ObjectIdentifier($0) }
        guard Array(v27.dropLast(2)) == v26,
              Array(v27.suffix(2)) == [ObjectIdentifier(ScheduleDefinitionReleaseRow.self), ObjectIdentifier(OccurrenceHistoryEventRow.self)],
              Array(v38.dropLast(2)) == PersistentSchemaV37.models.map({ ObjectIdentifier($0) }),
              Array(v38.suffix(2)) == [ObjectIdentifier(ExceptionCalendarReleaseRow.self), ObjectIdentifier(ScheduleOverrideEventRow.self)],
              v27.contains(ObjectIdentifier(WorkflowRecord.self)) else {
            throw WorkspaceMutationFailureV1.persistenceFailed
        }
    }
}

enum LightingWorkflowReferenceEnrollmentV1 { static let measurementAndClaimHistoryRemainAppendOnly = true; static let derivedLightingPreviewsAreNotPersistent = true }

enum C31LightingWorkflowModelBoundaryV1 {
    static let completedSnapshotsReferenceFrozenProjection = true
    static let workflowRowsDoNotDuplicateLightingBytes = true
    static let currentTipDoesNotRewriteHistoricDisplay = true
    static let noOperationalStateInferred = true
}
// MARK: - C32 assistance workflow models boundary

enum C32AssistanceLifecycleBoundary_FieldEvidenceApp_Domain_Models_WorkflowModels_swift {
    static let proposalIsPersistent = AssistancePersistenceEnrollmentV1.proposalIsPersistent
    static let rejectedProposalCorpusIsPersistent = AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent
    static let durableFamilyCount = AssistancePersistenceEnrollmentV1.durableModelCount
    static let acceptedMutationKind: WorkspaceCommandKindV1 = .applyAssistanceAcceptance
    static let manualFallback: ManualFallbackActionV1 = .typeManually
    static let proposalNotModeledAsWorkflowState = true

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

enum C33TemporalEvidenceBoundary_Domain_Models_WorkflowModels_V1 {
    static let clipType: TemporalEvidenceClipV1.Type = TemporalEvidenceClipV1.self
    static let anchorType: TimecodedEvidenceAnchorV1.Type = TimecodedEvidenceAnchorV1.self
    static let persistentSchemaVersion: Int =
        TemporalEvidencePersistenceEnrollmentV1.persistentSchemaVersion
}

/// C45 label lifecycle state is not inferred from report or workflow state.
enum C45AssetLabelBoundary_WorkflowModelsV1 {
    static func validate(_ snapshot: AcceptedLabelGenerationSnapshotV1) throws { try snapshot.validate() }
    static let infersLabelDelivery = false
}

enum C46OperationalContactConformance_FieldEvidenceApp_Domain_Models_WorkflowModels_swift {
    static let operationalContactsRemainPurposeSeparated = true
    static let systemHandoffsRemainExplicitEphemeralAndNoncanonical = true
    static let subscriberConsentCampaignAndMeasurementProjectionForbidden = true
    static let contactExportExcludedByDefault = true
    static let siteRoleOwnershipForbidden = true
}

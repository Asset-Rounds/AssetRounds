import Foundation

enum PackageReleaseBindingKindV1: String, CaseIterable, Codable, Sendable {
    case draft = "DRAFT"
    case active = "ACTIVE"
    case completed = "COMPLETED"
    case amendment = "AMENDMENT"
    case export = "EXPORT"
}

enum C26SurveyPackageBindingLifecycleV1 {
    static let persistentFamilies=["SurveySessionV1","FactCaptureV1","ProvisionalSubjectV1","SubjectPromotionReceiptV1","SurveyPublicationSnapshotV1"]
    static let activityKind=ActivityKindV1.survey
    static let immutablePublication=true
    static let lastWriteWins=false
    static func validate()throws{guard persistentFamilies.count==5,immutablePublication,!lastWriteWins else{throw SurveySessionFailureV1.invalidValue}}
}

enum SurveyPackageReleaseBindingV1 {
    static func validate(survey: SurveyDefinitionReleaseV1, package: InspectionPackageReleaseV1) throws {
        try package.validateSurveyDefinitionRelease(survey)
        guard package.state == .published else { throw InspectionKernelFailureV1.invalidValue }
    }
}

enum PackageReleaseAccessibleDocumentBindingV1{
    static let exactReleaseBindingRequired=true
    static let semanticTreePersistent=false
}

extension PackageReleaseBindingV1 {
    func validateFieldReferenceBinding(
        _ closure: FieldReferenceLifecycleClosureV1,
        checkedAt: Date
    ) throws -> FieldReferenceOfflineReadinessV1 {
        try validate()
        let readiness = try closure.validate(checkedAt: checkedAt)
        guard readiness.availability == .readyOffline else { throw FieldReferencePackFailureV1.missingContent }
        return readiness
    }
}

extension PackageReleaseBindingV1 {
    func validateClientAdmission(_ closure: ClientCapabilityLifecycleClosureV1,
                                 operation: PackageLifecycleOperationV1,
                                 forWrite: Bool) throws {
        try validate()
        try closure.validate()
        let decision = closure.decision
        let release = closure.release
        guard decision.packageReleaseID == packageReleaseID,
              decision.packageSHA256 == packageSHA256,
              decision.workflowSHA256 == workflowSHA256,
              release.packageReleaseID == packageReleaseID,
              release.packageID == packageID,
              release.packageContentVersion == packageContentVersion,
              release.packageSHA256 == packageSHA256,
              release.canonicalPackageBytes == canonicalPackageBytes,
              release.workflowSHA256 == workflowSHA256,
              release.canonicalWorkflowBytes == canonicalWorkflowBytes,
              decision.operation == operation,
              decision.admission == .readWrite || (!forWrite && decision.admission == .readOnly) else {
            throw InspectionKernelFailureV1.invalidTransition
        }
    }
}

struct PackageReleaseBindingV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let bindingID: String
    let kind: PackageReleaseBindingKindV1
    let packageReleaseID: String
    let packageID: String
    let packageContentVersion: Int
    let packageSHA256: String
    let canonicalPackageBytes: Data
    let workflowSHA256: String
    let canonicalWorkflowBytes: Data

    private init(
        schemaVersion: Int,
        bindingID: String,
        kind: PackageReleaseBindingKindV1,
        packageReleaseID: String,
        packageID: String,
        packageContentVersion: Int,
        packageSHA256: String,
        canonicalPackageBytes: Data,
        workflowSHA256: String,
        canonicalWorkflowBytes: Data
    ) {
        self.schemaVersion = schemaVersion
        self.bindingID = bindingID
        self.kind = kind
        self.packageReleaseID = packageReleaseID
        self.packageID = packageID
        self.packageContentVersion = packageContentVersion
        self.packageSHA256 = packageSHA256
        self.canonicalPackageBytes = canonicalPackageBytes
        self.workflowSHA256 = workflowSHA256
        self.canonicalWorkflowBytes = canonicalWorkflowBytes
    }

    init(
        bindingID: String,
        kind: PackageReleaseBindingKindV1,
        publication: InspectionPackagePublishedReleaseV1
    ) throws {
        try publication.validate()
        let release = publication.release
        try release.validate()
        guard WorkflowGrammarValidationV1.validID(bindingID),
              release.state == .published else {
            throw InspectionKernelFailureV1.invalidTransition
        }
        schemaVersion = Self.schemaVersion
        self.bindingID = bindingID
        self.kind = kind
        self.packageReleaseID = release.packageReleaseID
        self.packageID = release.packageID
        self.packageContentVersion = release.packageContentVersion
        self.packageSHA256 = release.packageSHA256
        self.canonicalPackageBytes = release.canonicalPackageBytes
        self.workflowSHA256 = release.workflowSHA256
        self.canonicalWorkflowBytes = release.canonicalWorkflowBytes
    }

    func validateResume(against publication: InspectionPackagePublishedReleaseV1) throws {
        try validate()
        try publication.validate()
        let release = publication.release
        try release.validate()
        guard schemaVersion == Self.schemaVersion,
              release.state == .published,
              packageReleaseID == release.packageReleaseID,
              packageID == release.packageID,
              packageContentVersion == release.packageContentVersion,
              packageSHA256 == release.packageSHA256,
              canonicalPackageBytes == release.canonicalPackageBytes,
              workflowSHA256 == release.workflowSHA256,
              canonicalWorkflowBytes == release.canonicalWorkflowBytes else {
            throw InspectionKernelFailureV1.hashMismatch
        }
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              WorkflowGrammarValidationV1.validID(bindingID),
              KernelCanonicalHashV1.validSHA256(packageReleaseID),
              WorkflowGrammarValidationV1.validID(packageID),
              packageContentVersion > 0,
              KernelCanonicalHashV1.sha256(canonicalPackageBytes) == packageSHA256,
              KernelCanonicalHashV1.sha256(canonicalWorkflowBytes) == workflowSHA256 else {
            throw InspectionKernelFailureV1.hashMismatch
        }
        let package = try InspectionPackageCanonicalCodecV2.decode(canonicalPackageBytes)
        let workflow = try WorkflowDefinitionCanonicalCodecV1.decode(canonicalWorkflowBytes)
        guard package.packageID == packageID, package.contentVersion == packageContentVersion else {
            throw InspectionKernelFailureV1.hashMismatch
        }
        let expected = try InspectionPackageReleaseV1.makeDraft(
            package: package,
            workflow: workflow
        )
        guard expected.packageReleaseID == packageReleaseID else {
            throw InspectionKernelFailureV1.hashMismatch
        }
    }
}

struct FrozenAssetSemanticPackageBindingV1: Codable, Equatable, Sendable {
    let packageBinding: PackageReleaseBindingV1
    let kindBindingEventID: UUID
    let kindBindingRevision: UInt64
    let catalogRelease: AssetSemanticCatalogReleaseReferenceV1
    let semanticID: String

    init(
        packageBinding: PackageReleaseBindingV1,
        kindBinding: AssetKindBindingEventV1
    ) throws {
        try packageBinding.validate()
        try kindBinding.validate()
        self.packageBinding = packageBinding
        self.kindBindingEventID = kindBinding.eventID
        self.kindBindingRevision = kindBinding.revision
        self.catalogRelease = kindBinding.catalogRelease
        self.semanticID = kindBinding.semanticID
    }

    func validate() throws {
        try packageBinding.validate()
        try catalogRelease.validate()
        guard kindBindingRevision > 0,
              AssetSemanticValidationV1.validIdentifier(semanticID, maximumBytes: 160) else {
            throw AssetSemanticContractFailureV1.incompatibleRelease
        }
    }
}

enum PackageReleaseBindingCanonicalCodecV1 {
    static func encode(_ value: PackageReleaseBindingV1) throws -> Data {
        try value.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    static func decode(_ data: Data) throws -> PackageReleaseBindingV1 {
        guard !data.isEmpty, data.count <= 2_097_152 else {
            throw InspectionKernelFailureV1.limitExceeded
        }
        let value = try JSONDecoder().decode(PackageReleaseBindingV1.self, from: data)
        guard try encode(value) == data else { throw InspectionKernelFailureV1.invalidValue }
        return value
    }
}

extension PackageReleaseBindingV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, bindingID, kind, packageReleaseID, packageID
        case packageContentVersion, packageSHA256, canonicalPackageBytes
        case workflowSHA256, canonicalWorkflowBytes
    }
    init(from decoder: any Decoder) throws {
        try KernelClosedCodingV1.require(decoder, keys: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            schemaVersion: try c.decode(Int.self, forKey: .schemaVersion),
            bindingID: try c.decode(String.self, forKey: .bindingID),
            kind: try c.decode(PackageReleaseBindingKindV1.self, forKey: .kind),
            packageReleaseID: try c.decode(String.self, forKey: .packageReleaseID),
            packageID: try c.decode(String.self, forKey: .packageID),
            packageContentVersion: try c.decode(Int.self, forKey: .packageContentVersion),
            packageSHA256: try c.decode(String.self, forKey: .packageSHA256),
            canonicalPackageBytes: try c.decode(Data.self, forKey: .canonicalPackageBytes),
            workflowSHA256: try c.decode(String.self, forKey: .workflowSHA256),
            canonicalWorkflowBytes: try c.decode(Data.self, forKey: .canonicalWorkflowBytes)
        )
        try validate()
    }
}

// MARK: - C19 measurement release binding

extension PackageReleaseBindingV1 {
    /// Preserves the existing active/completed binding while checking that a
    /// local measurement refers to the same immutable package release and
    /// workflow bytes.
    func c19ValidateMeasurementCapture(
        _ capture: MeasurementCaptureV1
    ) throws {
        try validate()
        try capture.validate()
        guard capture.packageReleaseID == packageReleaseID,
              capture.workflowSHA256 == workflowSHA256 else {
            throw MeasurementIntegrityFailureV1.staleReference
        }
    }

    func c19ValidateMeasurementSeries(
        _ series: MeasurementSeriesV1,
        captures: [MeasurementCaptureV1],
        protocolRelease: MeasurementProtocolReleaseV1
    ) throws {
        try validate()
        try protocolRelease.c19ValidateSeries(series, captures: captures)
        guard captures.allSatisfy({
            $0.packageReleaseID == packageReleaseID
                && $0.workflowSHA256 == workflowSHA256
        }) else {
            throw MeasurementIntegrityFailureV1.staleReference
        }
    }
}

// MARK: - C20 reviewed-derivative release binding

extension PackageReleaseBindingV1 {
    /// Validates the existing immutable package publication before a C20
    /// derivative is projected. The binding remains a release identity and
    /// never becomes a privacy/compliance decision or a second writer.
    func c20ValidateReviewedDerivative(
        package: InspectionPackageV2,
        release: InspectionPackageReleaseV1,
        manifest: PrivacyTransformManifestV1,
        review: PrivacyReviewReceiptV1?,
        policy: PrivacyTransformPolicyV1,
        requestedAudience: EvidenceAudienceV1,
        currentSourceRevision: UInt64,
        currentSourceSHA256: String,
        at now: Date
    ) throws -> ContentReferenceV1 {
        try validate()
        try package.validate()
        try release.validate()
        let packageBytes = try InspectionPackageCanonicalCodecV2.encode(package)
        guard packageReleaseID == release.packageReleaseID,
              release.state == .published,
              packageID == package.packageID,
              packageContentVersion == package.contentVersion,
              packageID == release.packageID,
              packageContentVersion == release.packageContentVersion,
              packageSHA256 == release.packageSHA256,
              canonicalPackageBytes == packageBytes,
              canonicalPackageBytes == release.canonicalPackageBytes,
              workflowSHA256 == release.workflowSHA256,
              canonicalWorkflowBytes == release.canonicalWorkflowBytes else {
            throw InspectionKernelFailureV1.hashMismatch
        }
        guard manifest.workspaceID == policy.workspaceID else {
            throw PrivacyTransformFailureV1.wrongWorkspace
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
}

enum InspectionKernelLifecycleV1 {
    static let mode = "DECLARATION_ONLY"
    static let schema = "KERNEL_CONTRACT_V1"
    static let persistent = false
    static let migrationRequired = false
    static let backupRestoreRequired = false
    static let deleteEraseRequired = false
    static let exportReportEffectRequired = false
    static let searchRebuildReplayRequired = false
    static let downgradePolicy = "DORMANT_REVERT_ALLOWED"
    static let interruption = "ZERO_OR_COMPLETE"
    static let idempotentReceipt = "EXACT_CANONICAL_BYTES_ADOPTION"
}

/// C29 typed integration anchor: this owner consumes an exact immutable plan
/// revision reference and may not reinterpret current plan state implicitly.
enum C29PlanIntegration_Domain_InspectionKernel_PackageReleaseBindingV1 {
    static func validatePlanRevision(_ value: PlanRevisionReferenceV1) throws {
        try value.validate()
    }
}

enum C37PoseIntegration_FieldEvidenceApp_Domain_InspectionKernel_PackageReleaseBindingV1_swift {
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
enum C30ConsumerBoundaryV1_Domain_InspectionKernel_PackageReleaseBindingV1 {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Domain/InspectionKernel/PackageReleaseBindingV1.swift", role: .lifecycle)
}

enum C31LightingPackageBindingBoundaryV1 {
    static let bindingRequiresWorkspaceAndReleaseMatch = true
    static let bindingDigestIsFrozenForHistoricDisplay = true
    static let wrongReleaseCannotSupplyLightingCriteria = true
}
// MARK: - C32 assistance package binding boundary

enum C32AssistanceLifecycleBoundary_FieldEvidenceApp_Domain_InspectionKernel_PackageReleaseBindingV1_swift {
    static let proposalIsPersistent = AssistancePersistenceEnrollmentV1.proposalIsPersistent
    static let rejectedProposalCorpusIsPersistent = AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent
    static let durableFamilyCount = AssistancePersistenceEnrollmentV1.durableModelCount
    static let acceptedMutationKind: WorkspaceCommandKindV1 = .applyAssistanceAcceptance
    static let manualFallback: ManualFallbackActionV1 = .typeManually
    static let proposalRequiresPackageDigestMatch = true

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

enum C33TemporalEvidenceBoundary_Domain_InspectionKernel_PackageReleaseBindingV1_V1 {
    static let clipType: TemporalEvidenceClipV1.Type = TemporalEvidenceClipV1.self
    static let anchorType: TimecodedEvidenceAnchorV1.Type = TimecodedEvidenceAnchorV1.self
    static let persistentSchemaVersion: Int =
        TemporalEvidencePersistenceEnrollmentV1.persistentSchemaVersion
}

// MARK: - C45 canonical asset-label integration
enum C45AssetLabelBoundary_Row142 {
    static let reusesCanonicalAssetLocatorAndWriter = true
    static func validateAcceptedSnapshot(_ snapshot: AcceptedLabelGenerationSnapshotV1) throws {
        try snapshot.validate()
    }
}

enum C46OperationalContactConformance_FieldEvidenceApp_Domain_InspectionKernel_PackageReleaseBindingV1_swift {
    static let operationalContactsRemainPurposeSeparated = true
    static let systemHandoffsRemainExplicitEphemeralAndNoncanonical = true
    static let subscriberConsentCampaignAndMeasurementProjectionForbidden = true
    static let contactExportExcludedByDefault = true
    static let siteRoleOwnershipForbidden = true
}

enum C47ActivityContractCompatibility_FieldEvidenceApp_Domain_InspectionKernel_PackageReleaseBindingV1_swift {
    static let sharedEnvelopeDoesNotCollapseFamilyTruth = true
    static let installationAndPunchReceiptsRemainIndependent = true
    static let noPlanFallbackIsExplicit = true
    static let surveyDefinitionOwnershipIsPreserved = true
    static let legacyInspectionTruthIsNotRewritten = true
    static let threeReceiptIsolationIsRequired = true
}

enum C48PortableReviewPackageBindingBoundaryV1 {
    static let bindingContainsSubjectSnapshotMetadataOnly = true
    static let capabilityProofIsNotBoundIntoPackageRelease = true
    static let responseBytesAreNotBoundIntoPackageRelease = true
    static let publicRequestIdentityDoesNotExposeWorkspaceIdentity = true
    static let responseHistoryCannotRebindTheSubject = true

    static func validateDerivedHistory(
        _ projection: C48PortableReviewDerivedHistoryProjectionV1
    ) throws {
        try projection.validate()
    }
}

// MARK: - C49 package binding projection

enum C49WorkResourcePackageReleaseBindingBoundaryV1 {
    static let packageBindingIsDerived = true
    static let bindingCannotRewriteAppendOnlyHistory = true
    static let bindingCannotExposeLiveStockRows = true

    static func bind(
        workspaceID: WorkspaceID,
        projection: C49WorkResourceReportProjectionV1,
        format: String = "OPEN_JSON"
    ) throws -> C49WorkResourceProjectionEnvelopeV1 {
        guard projection.workspaceID == workspaceID else {
            throw C49WorkResourceProjectionFailureV1.invalidWorkspace
        }
        return try C49WorkResourceProjectionSupportV1.envelope(projection, format: format)
    }
}

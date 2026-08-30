import Foundation

enum ScheduleContentContractRegistryBoundaryV1 { static let scheduleIsContentContract = false }

enum C51ScheduleContentContractRegistryBoundaryV1 {
    static let scheduleIsContentContract = false
    static let scheduleUsesNoParallelByteStore = true
    static let scheduleClosureMetadataIsDerivedOnly = true
}

enum AssetLocatorContentContractBoundaryV1 {
    static let locatorContractIsRegisteredAsContent = false
    static let locatorContractOwnsSeparateByteStore = false
}

enum ContentContractPublicationBoundaryV1: String, CaseIterable, Sendable {
    case beforeValidation = "BEFORE_VALIDATION"
    case afterValidationBeforePublication = "AFTER_VALIDATION_BEFORE_PUBLICATION"
    case afterPublicationBeforeReceipt = "AFTER_PUBLICATION_BEFORE_RECEIPT"
}

enum FieldReferenceContentContractRegistryV1 {
    static let releaseFamily = "FieldReferenceReleaseV1"
    static let bindingFamily = "FieldReferenceBindingV1"
    static let byteAuthority = "C05_IMMUTABLE_CONTENT_AUTHORITY"
    static let readinessPersistence = "DERIVED_ONLY"
}

struct ContentContractRegistryV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let persistentContractSchema = "KERNEL_MEDIA_V1"
    static let downgradeDisposition = "DORMANT_REVERT_ALLOWED"

    let schemaVersion: Int
    let persistentContractSchema: String
    let downgradeDisposition: String
    let declaredContracts: [String]

    init(declaredContracts: [String]) throws {
        let expected = [
            "ContentReferenceV1",
            "ContentLocatorV1",
            "ContentManifestV1",
            "EvidenceAssociationV1",
            "ContentDerivativeProvenanceV1",
            "LocalContentStoreV1",
        ]
        guard declaredContracts == expected else { throw ContentContractFailureV1.invalidValue }
        schemaVersion = Self.schemaVersion
        persistentContractSchema = Self.persistentContractSchema
        downgradeDisposition = Self.downgradeDisposition
        self.declaredContracts = declaredContracts
    }

    static func canonical() throws -> ContentContractRegistryV1 {
        try .init(declaredContracts: [
            "ContentReferenceV1",
            "ContentLocatorV1",
            "ContentManifestV1",
            "EvidenceAssociationV1",
            "ContentDerivativeProvenanceV1",
            "LocalContentStoreV1",
        ])
    }
}

/// The C50 adapter contributes no new durable content family to the closed
/// registry; it consumes existing projections and canonical references only.
enum C50IncumbentFileExchangeContractRegistryBoundaryV1 {
    static let newCanonicalContentFamilyCount = 0
    static let sourceAndQuarantineFamiliesRegistered = false
    static let profileSelectionFamilyRegistered = false
    static let acceptedContentUsesExistingRegistry = true
    static let registryIsClosedAndDeterministic = true

    static func validate() -> Bool {
        newCanonicalContentFamilyCount == 0
            && !sourceAndQuarantineFamiliesRegistered
            && !profileSelectionFamilyRegistered
            && acceptedContentUsesExistingRegistry
            && registryIsClosedAndDeterministic
    }
}

struct ContentContractRegistryReceiptV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let registrySHA256: String
    let publicationState: String
    let nativeCompileRan: Bool
    let hostedDispatchRan: Bool
    let acceptanceCredit: Bool
    let releaseCredit: Bool
    let requiresAcceptedS10_6Reconciliation: Bool

    fileprivate init(registrySHA256: String) throws {
        guard KernelCanonicalHashV1.validSHA256(registrySHA256) else {
            throw ContentContractFailureV1.invalidValue
        }
        schemaVersion = Self.schemaVersion
        self.registrySHA256 = registrySHA256
        publicationState = "COMPLETE"
        nativeCompileRan = false
        hostedDispatchRan = false
        acceptanceCredit = false
        releaseCredit = false
        requiresAcceptedS10_6Reconciliation = true
    }
}

enum ContentContractRegistryPublicationV1: Equatable, Sendable {
    case zero
    case complete(registry: ContentContractRegistryV1, receipt: ContentContractRegistryReceiptV1)
}

enum ContentContractRegistryCanonicalCodecV1 {
    static func encode(_ registry: ContentContractRegistryV1) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(registry)
        guard !data.isEmpty, data.count <= ContentContractLimitsV1.maximumCanonicalBytes else {
            throw ContentContractFailureV1.limitExceeded
        }
        return data
    }

    static func decode(_ data: Data) throws -> ContentContractRegistryV1 {
        guard !data.isEmpty, data.count <= ContentContractLimitsV1.maximumCanonicalBytes else {
            throw ContentContractFailureV1.limitExceeded
        }
        let registry = try JSONDecoder().decode(ContentContractRegistryV1.self, from: data)
        guard try encode(registry) == data else { throw ContentContractFailureV1.digestMismatch }
        return registry
    }
}

enum ContentContractRegistryPublisherV1 {
    static func publish(
        recoveringFrom boundary: ContentContractPublicationBoundaryV1?
    ) throws -> ContentContractRegistryPublicationV1 {
        switch boundary {
        case .beforeValidation, .afterValidationBeforePublication:
            return .zero
        case .afterPublicationBeforeReceipt, .none:
            let registry = try ContentContractRegistryV1.canonical()
            let canonicalBytes = try ContentContractRegistryCanonicalCodecV1.encode(registry)
            return .complete(
                registry: registry,
                receipt: try .init(registrySHA256: KernelCanonicalHashV1.sha256(canonicalBytes))
            )
        }
    }

    static func recover(
        canonicalData: Data?,
        receipt: ContentContractRegistryReceiptV1?
    ) throws -> ContentContractRegistryV1? {
        switch (canonicalData, receipt) {
        case (nil, nil):
            return nil
        case (.some(let data), .some(let receipt)):
            guard receipt.registrySHA256 == KernelCanonicalHashV1.sha256(data) else {
                throw ContentContractFailureV1.digestMismatch
            }
            return try ContentContractRegistryCanonicalCodecV1.decode(data)
        default:
            throw ContentIntegrityFailureV1.partialEffect
        }
    }
}

extension ContentContractRegistryV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, persistentContractSchema, downgradeDisposition, declaredContracts
    }

    init(from decoder: any Decoder) throws {
        try ContentClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion,
              try c.decode(String.self, forKey: .persistentContractSchema) == Self.persistentContractSchema,
              try c.decode(String.self, forKey: .downgradeDisposition) == Self.downgradeDisposition else {
            throw ContentContractFailureV1.incompatibleVersion
        }
        try self.init(declaredContracts: c.decode([String].self, forKey: .declaredContracts))
    }
}

enum C34RouteAdoptionBoundary_ContentContractRegistryV1 {
    static let packageSurfaceManifestType = PackageSurfaceManifestV1.self
    static let canonicalRegistryType = RouteRegistryV1.self
    static let routeStateIsCanonicalContent = false
}


// C20 is additive. Keeping this separate preserves the immutable C05 registry
// receipt while publishing the privacy-transform contract family explicitly.
extension ContentContractRegistryV1 {
    static let c20PrivacyTransformContracts: [String] = [
        "PrivacyTransformPolicyV1",
        "PrivacyCoordinateSpaceV1",
        "PrivacyImageOrientationV1",
        "PrivacyCoordinateScaleV1",
        "PrivacyIntegerRectV1",
        "PrivacyRegionV1",
        "PrivacyTransformManifestV1",
        "PrivacyReviewReceiptV1",
        "PrivacyTransformPublicationAuthorityV1",
        "ExistingContentStorePrivacyDerivativeWriterV1",
        "WorkspacePrivacyTransformPublicationAuthorityV1",
    ]

    static func c20BoundaryContracts() throws -> [String] {
        let registry = try canonical()
        return registry.declaredContracts + c20PrivacyTransformContracts
    }
}

extension ContentContractRegistryReceiptV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, registrySHA256, publicationState, nativeCompileRan, hostedDispatchRan
        case acceptanceCredit, releaseCredit, requiresAcceptedS10_6Reconciliation
    }

    init(from decoder: any Decoder) throws {
        try ContentClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion,
              try c.decode(String.self, forKey: .publicationState) == "COMPLETE",
              try c.decode(Bool.self, forKey: .nativeCompileRan) == false,
              try c.decode(Bool.self, forKey: .hostedDispatchRan) == false,
              try c.decode(Bool.self, forKey: .acceptanceCredit) == false,
              try c.decode(Bool.self, forKey: .releaseCredit) == false,
              try c.decode(Bool.self, forKey: .requiresAcceptedS10_6Reconciliation) else {
            throw ContentContractFailureV1.incompatibleVersion
        }
        try self.init(registrySHA256: c.decode(String.self, forKey: .registrySHA256))
    }
}

// MARK: - C36 contract registration

extension ContentContractRegistryV1 {
    /// C36 is additive to the C05 content contract.  These names describe
    /// device-local staging/reservation boundaries and do not claim a second
    /// canonical content store.
    static let c36StagingContracts: [String] = [
        "AttachmentStagingItemV1",
        "DraftAttachmentStagingAdapterV1",
        "DraftContentReservationV1",
        "DraftContentPromotionPortV1",
    ]

    static func c36BoundaryContracts() throws -> [String] {
        let registry = try canonical()
        return registry.declaredContracts + c36StagingContracts
    }

    static func validateC36Reservation(
        _ reservation: DraftContentReservationV1,
        reference: ContentReferenceV1
    ) throws {
        try ContentIntegrityV1.validateDraftReservation(
            reservation,
            reference: reference
        )
    }
}

// MARK: - C24 accessible-document consumer registration

extension ContentContractRegistryV1 {
    /// C24 registers only consumer-side boundaries.  The canonical semantic
    /// tree and assessment receipt remain owned by the reporting lane; no
    /// alternate content or semantic-tree writer is registered here.
    static let c24AccessibleDocumentContracts: [String] = [
        "AccessibleDocumentSemanticTreeV1",
        "AccessibleDocumentAssessmentReceiptV1",
        "AccessibleDocumentContentReferenceBoundaryV1",
        "AccessibleDocumentLocatorBoundaryV1",
        "AccessibleDocumentProvenanceBoundaryV1",
        "AccessibleDocumentPrivacyTransformBoundaryV1",
        "AccessibleDocumentIntegrityBoundaryV1",
    ]

    static func c24BoundaryContracts() throws -> [String] {
        try c20BoundaryContracts() + c24AccessibleDocumentContracts
    }

    static func validateC24AudienceSafeTree(
        _ tree: AccessibleDocumentSemanticTreeV1
    ) throws {
        try AccessibleDocumentIntegrityBoundaryV1.validateTree(tree)
    }
}

/// C29 typed integration anchor: this owner consumes an exact immutable plan
/// revision reference and may not reinterpret current plan state implicitly.
enum C29PlanIntegration_Infrastructure_Content_ContentContractRegistryV1 {
    static func validatePlanRevision(_ value: PlanRevisionReferenceV1) throws {
        try value.validate()
    }
}

enum C37PoseIntegration_FieldEvidenceApp_Infrastructure_Content_ContentContractRegistryV1_swift {
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
enum C30ConsumerBoundaryV1_Infrastructure_Content_ContentContractRegistryV1 {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Infrastructure/Content/ContentContractRegistryV1.swift", role: .content)
}

enum C31LightingContentContractRegistryV1 {
    static let contractIDs = [
        "lighting.system.v1", "lighting.observation.v1", "lighting.issue.v1",
        "lighting.measurement-plan.v1", "lighting.claim-state.v1",
    ]
    static let oneCanonicalByteStore = true
    static let oneCanonicalReceiptAuthority = true
    static let projectionIsDerived = true
}

/// C32 keeps assistance candidates outside every durable and derived surface;
/// only explicit acceptance may reach the existing canonical writer/receipt path.
enum C32AssistanceCompatibility_Content_ContentContractRegistryV1 {
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

// MARK: - C33 canonical content contract enrollment

enum TemporalEvidenceContentContractEnrollmentV1 {
    static let requiredContracts = [
        "ContentReferenceV1",
        "ContentLocatorV1",
        "ContentOriginalProvenanceV1",
        "ContentDerivativeProvenanceV1",
        "ContentProvenanceGraphV1",
        "DraftImmutableContentWriterV1"
    ]
    static let usesExistingCanonicalWriter = true
    static let addsSecondByteStore = false

    static func validate() throws {
        guard Set(requiredContracts).count == requiredContracts.count,
              usesExistingCanonicalWriter,
              !addsSecondByteStore,
              TemporalEvidencePersistenceEnrollmentV1.secondByteStoreAllowed == false,
              TemporalEvidencePersistenceEnrollmentV1.immutableOriginalsAreRewritten == false else {
            throw ContentContractFailureV1.invalidValue
        }
    }
}

/// C45 C45 enrolls three derived artifact kinds without a second content authority.
enum C45AssetLabelBoundary_ContentContractRegistryV1 {
    static func validate(_ plan: AssetLabelGenerationPlanV1) throws { try plan.validate() }
    static let artifactKindCount = LabelArtifactKindV1.allCases.count
}
enum C46OperationalContactConformance_FieldEvidenceApp_Infrastructure_Content_ContentContractRegistryV1_swift {
    static let operationalContactsRemainPurposeSeparated = true
    static let systemHandoffsRemainExplicitEphemeralAndNoncanonical = true
    static let subscriberConsentCampaignAndMeasurementProjectionForbidden = true
    static let contactExportExcludedByDefault = true
    static let noContactProjectionOrNetworkDelivery = true
}

// MARK: - C48 portable-review derived-content boundary

enum C48PortableReviewContentContractRegistryBoundaryV1 {
    static let derivedMetadataContract = C48PortableReviewDerivedHistoryProjectionV1.self
    static let requestAndResponseRemainExchangeOwned = true
    static let rawCapabilityBytesAreContentContractMembers = false
    static let capabilityProofBytesAreContentContractMembers = false
    static let rawRequestResponseBytesAreContentContractMembers = false
    static let workspaceAndReplicaIdentityAreContentContractMembers = false
    static let existingContentRegistryRemainsCanonical = true

    static func validate(_ projection: C48PortableReviewDerivedHistoryProjectionV1) throws {
        try projection.validate()
    }
}

// MARK: - C49 work-resource content contract enrollment

enum C49WorkResourceContentContractRegistryBoundaryV1 {
    static let requiredContracts = [
        "WorkResourceEntryV1",
        "ManualWorkResourceRecordRow",
        "DirectCostEntryV1",
        "LocalPartReferenceSnapshotV1",
        "ContentIntegrityReceiptV1",
    ]
    static let usesExistingCanonicalContentRegistry = true
    static let localPartReferenceIsEmbeddedSnapshot = true
    static let liveInventoryLookup = false
    static let directCostIsNotASecondLedger = true
    static let customerSafeCostRequiresExplicitSelection = true

    static func validate() throws {
        guard Set(requiredContracts).count == requiredContracts.count,
              usesExistingCanonicalContentRegistry,
              localPartReferenceIsEmbeddedSnapshot,
              !liveInventoryLookup,
              directCostIsNotASecondLedger,
              customerSafeCostRequiresExplicitSelection else {
            throw ContentContractFailureV1.invalidValue
        }
    }
}

extension ContentContractRegistryV1 {
    /// Returns an additive view for C49 without changing the frozen base
    /// registry used by existing content callers.
    static func c49Contracts() throws -> [String] {
        try C49WorkResourceContentContractRegistryBoundaryV1.validate()
        let contracts = try canonical().declaredContracts
            + C49WorkResourceContentContractRegistryBoundaryV1.requiredContracts
        guard Set(contracts).count == contracts.count else {
            throw ContentContractFailureV1.invalidValue
        }
        return contracts
    }
}

import Foundation

enum ScheduleContentReferenceBoundaryV1 { static let scheduleContainsContentBytes = false }

enum AssetLocatorContentReferenceBoundaryV1 {
    static let locatorPayloadIsContentReference = false
    static let rawExternalKeyMayBePersisted = false
}

enum ContentContractFailureV1: Error, Equatable, Sendable {
    case invalidValue
    case limitExceeded
    case unknownAlgorithm
    case duplicateIdentity
    case wrongWorkspace
    case staleReference
    case missingContent
    case orphanEvidence
    case immutableOriginal
    case digestMismatch
    case byteLengthMismatch
    case mediaTypeMismatch
    case invalidProvenance
    case cycleDetected
    case historyRewrite
    case incompatibleVersion
}

enum FieldReferenceContentBoundaryV1 {
    static func validateImmutableOriginals(_ references: [ContentReferenceV1], workspaceID: WorkspaceID) throws {
        let expected = workspaceID.rawValue.uuidString.lowercased()
        guard !references.isEmpty,
              Set(references.map(\.contentID)).count == references.count,
              references.allSatisfy({ $0.workspaceID == expected && $0.byteRole == .immutableOriginal }) else {
            throw ContentContractFailureV1.immutableOriginal
        }
    }
}

enum ContentContractLimitsV1 {
    static let maximumIDBytes = 128
    static let maximumMediaTypeBytes = 127
    static let maximumDigestCount = 2
    static let maximumManifestEntries = 256
    static let maximumAssociations = 512
    static let maximumProvenanceSources = 32
    static let maximumTextBytes = 1_024
    static let maximumCanonicalBytes = 1_048_576
}

enum ContentContractValidationV1 {
    static func validID(_ value: String) -> Bool {
        WorkflowGrammarValidationV1.validID(value)
    }

    static func validMediaType(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= ContentContractLimitsV1.maximumMediaTypeBytes,
              value == value.lowercased(),
              value.filter({ $0 == "/" }).count == 1,
              let slash = value.firstIndex(of: "/"), slash != value.startIndex,
              value.index(after: slash) != value.endIndex else { return false }
        return value.utf8.allSatisfy {
            (0x61...0x7A).contains($0) || (0x30...0x39).contains($0)
                || $0 == 0x2F || $0 == 0x2B || $0 == 0x2D || $0 == 0x2E
        }
    }

    static func validVersion(_ value: String) -> Bool {
        validID(value)
    }
}

enum ContentDigestAlgorithmV1: String, CaseIterable, Codable, Hashable, Sendable {
    case sha256 = "SHA256"
    case sha512 = "SHA512"

    var hexadecimalLength: Int {
        switch self {
        case .sha256: return 64
        case .sha512: return 128
        }
    }
}

struct ContentDigestV1: Codable, Equatable, Hashable, Sendable {
    let algorithm: ContentDigestAlgorithmV1
    let hexadecimalValue: String

    init(algorithm: ContentDigestAlgorithmV1, hexadecimalValue: String) throws {
        guard hexadecimalValue.count == algorithm.hexadecimalLength,
              hexadecimalValue.utf8.allSatisfy({
                (0x30...0x39).contains($0) || (0x61...0x66).contains($0)
              }) else { throw ContentContractFailureV1.invalidValue }
        self.algorithm = algorithm
        self.hexadecimalValue = hexadecimalValue
    }
}

struct ContentDigestSetV1: Codable, Equatable, Hashable, Sendable {
    let values: [ContentDigestV1]

    init(_ values: [ContentDigestV1]) throws {
        let sorted = values.sorted { $0.algorithm.rawValue < $1.algorithm.rawValue }
        guard !sorted.isEmpty,
              sorted.count <= ContentContractLimitsV1.maximumDigestCount,
              sorted == values,
              Set(sorted.map(\.algorithm)).count == sorted.count,
              sorted.contains(where: { $0.algorithm == .sha256 }) else {
            throw ContentContractFailureV1.invalidValue
        }
        self.values = sorted
    }

    func digest(for algorithm: ContentDigestAlgorithmV1) -> ContentDigestV1? {
        values.first { $0.algorithm == algorithm }
    }
}

enum ContentByteRoleV1: String, CaseIterable, Codable, Hashable, Sendable {
    case immutableOriginal = "IMMUTABLE_ORIGINAL"
    case derivative = "DERIVATIVE"
}

struct ContentReferenceV1: Codable, Equatable, Hashable, Identifiable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let workspaceID: String
    let contentID: String
    let byteLength: Int64
    let mediaType: String
    let digests: ContentDigestSetV1
    let byteRole: ContentByteRoleV1
    let createdAt: String

    var id: String { "\(workspaceID)|\(contentID)" }

    init(
        workspaceID: String,
        contentID: String,
        byteLength: Int64,
        mediaType: String,
        digests: ContentDigestSetV1,
        byteRole: ContentByteRoleV1,
        createdAt: String
    ) throws {
        guard ContentContractValidationV1.validID(workspaceID),
              ContentContractValidationV1.validID(contentID), byteLength >= 0,
              ContentContractValidationV1.validMediaType(mediaType),
              FindingContractValidationV1.validInstant(createdAt) else {
            throw ContentContractFailureV1.invalidValue
        }
        schemaVersion = Self.schemaVersion
        self.workspaceID = workspaceID
        self.contentID = contentID
        self.byteLength = byteLength
        self.mediaType = mediaType
        self.digests = digests
        self.byteRole = byteRole
        self.createdAt = createdAt
    }

    func validateImmutableIdentity(against other: ContentReferenceV1) throws {
        guard workspaceID == other.workspaceID else { throw ContentContractFailureV1.wrongWorkspace }
        guard contentID == other.contentID else { throw ContentContractFailureV1.missingContent }
        guard self == other else { throw ContentContractFailureV1.immutableOriginal }
    }
}

enum ContentClosedCodingV1 {
    static func requireExact(_ decoder: any Decoder, keys: [String]) throws {
        try KernelClosedCodingV1.require(decoder, keys: keys)
    }

    static func requireClosed(_ decoder: any Decoder, allowed: [String], required: [String]) throws {
        try KernelClosedCodingV1.require(decoder, keys: allowed, required: required)
    }
}

extension ContentDigestV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable { case algorithm, hexadecimalValue }
    init(from decoder: any Decoder) throws {
        try ContentClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawAlgorithm = try c.decode(String.self, forKey: .algorithm)
        guard let algorithm = ContentDigestAlgorithmV1(rawValue: rawAlgorithm) else {
            throw ContentContractFailureV1.unknownAlgorithm
        }
        try self.init(
            algorithm: algorithm,
            hexadecimalValue: c.decode(String.self, forKey: .hexadecimalValue)
        )
    }
}

extension ContentDigestSetV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable { case values }
    init(from decoder: any Decoder) throws {
        try ContentClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(c.decode([ContentDigestV1].self, forKey: .values))
    }
}

extension ContentReferenceV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, workspaceID, contentID, byteLength, mediaType, digests, byteRole, createdAt
    }
    init(from decoder: any Decoder) throws {
        try ContentClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw ContentContractFailureV1.incompatibleVersion
        }
        try self.init(
            workspaceID: c.decode(String.self, forKey: .workspaceID),
            contentID: c.decode(String.self, forKey: .contentID),
            byteLength: c.decode(Int64.self, forKey: .byteLength),
            mediaType: c.decode(String.self, forKey: .mediaType),
            digests: c.decode(ContentDigestSetV1.self, forKey: .digests),
            byteRole: c.decode(ContentByteRoleV1.self, forKey: .byteRole),
            createdAt: c.decode(String.self, forKey: .createdAt)
        )
    }
}

extension ContentReferenceV1 {
    /// Privacy processing never changes the original identity. A rendered
    /// result is required to be a distinct derivative with its own digest.
    func validatePrivacyDerivative(_ derivative: ContentReferenceV1) throws {
        guard byteRole == .immutableOriginal,
              derivative.byteRole == .derivative,
              workspaceID == derivative.workspaceID,
              contentID != derivative.contentID,
              digests.digest(for: .sha256) != derivative.digests.digest(for: .sha256) else {
            throw ContentContractFailureV1.immutableOriginal
        }
    }
}

extension ContentReferenceV1 {
    func validateAuthoritySourceBinding(_ release: AuthoritySourceReleaseV1) throws {
        try release.validate()
        guard release.licenseStorageDisposition == .lawfulContentReference,
              release.lawfulContentReference == self,
              AuthorityCriterionValidationV1.sameWorkspaceString(
                workspaceID,
                as: release.workspaceID
              ) else {
            throw ContentContractFailureV1.wrongWorkspace
        }
    }
}

// MARK: - C24 accessible-document audience boundary

/// Accessible-document semantic trees are derived report companions.  This
/// boundary validates the canonical tree while making the customer-safe
/// audience requirement explicit; it never turns a content reference into a
/// searchable node, locator, or alternate source of truth.
enum AccessibleDocumentContentReferenceBoundaryV1 {
    static let semanticTreeIsDerivedOnly = true
    static let requiresCustomerSafeAudience = true
    static let excludesOriginalBytes = true
    static let excludesPrivateEvidence = true
    static let excludesLocators = true
    static let excludesAssessorIdentity = true

    static func validateAudienceSafeTree(
        _ tree: AccessibleDocumentSemanticTreeV1
    ) throws {
        try tree.validate()
        guard tree.audience == .customerSafe,
              tree.nodes.allSatisfy({ $0.sensitivity == .customerSafe }) else {
            throw AccessibleDocumentFailureV1.privacyViolation
        }
    }

    static func validateAssessment(
        _ assessment: AccessibleDocumentAssessmentReceiptV1,
        for tree: AccessibleDocumentSemanticTreeV1
    ) throws {
        try validateAudienceSafeTree(tree)
        try assessment.validate(tree: tree)
    }
}

/// C29 typed integration anchor: this owner consumes an exact immutable plan
/// revision reference and may not reinterpret current plan state implicitly.
enum C29PlanIntegration_Domain_Content_ContentReferenceContractsV1 {
    static func validatePlanRevision(_ value: PlanRevisionReferenceV1) throws {
        try value.validate()
    }
}

enum C37PoseIntegration_FieldEvidenceApp_Domain_Content_ContentReferenceContractsV1_swift {
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
enum C30ConsumerBoundaryV1_Domain_Content_ContentReferenceContractsV1 {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Domain/Content/ContentReferenceContractsV1.swift", role: .content)
}

enum C31LightingContentReferenceBoundaryV1 {
    static let lightingProjectionUsesDigestOnly = true
    static let originalBytesRemainInExistingStore = true
    static let privateLocatorsAndActorIdentityExcluded = true

    static func accepts(_ reference: ContentReferenceV1) -> Bool {
        reference.byteLength >= 0
            && !reference.contentID.isEmpty
            && !reference.workspaceID.isEmpty
    }
}
// MARK: - C32 assistance content reference boundary

enum C32AssistanceLifecycleBoundary_FieldEvidenceApp_Domain_Content_ContentReferenceContractsV1_swift {
    static let proposalIsPersistent = AssistancePersistenceEnrollmentV1.proposalIsPersistent
    static let rejectedProposalCorpusIsPersistent = AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent
    static let durableFamilyCount = AssistancePersistenceEnrollmentV1.durableModelCount
    static let acceptedMutationKind: WorkspaceCommandKindV1 = .applyAssistanceAcceptance
    static let manualFallback: ManualFallbackActionV1 = .typeManually
    static let sourceContentRemainsLeasedUntilAcceptance = true

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

// MARK: - C33 bounded temporal evidence content boundary

/// C33 is metadata over the existing immutable content identity. A temporal
/// clip never manufactures an EvidenceFile identity and a replaceable
/// waveform/thumbnail never aliases or overwrites its source original.
enum TemporalEvidenceContentReferenceBoundaryV1 {
    static let usesExistingContentStore = true
    static let legacyEvidenceFileIsClipIdentity = false
    static let originalsRemainImmutable = true

    static func validate(
        clip: TemporalEvidenceClipV1,
        derivatives: [TemporalEvidenceDerivativeV1]
    ) throws {
        try clip.validateIntrinsic()
        guard clip.original.byteRole == .immutableOriginal,
              derivatives.allSatisfy({
                  $0.workspaceID == clip.workspaceID
                    && $0.clipID == clip.clipID
                    && $0.content.byteRole == .derivative
                    && $0.content.contentID != clip.original.contentID
              }),
              Set(derivatives.map(\.content.contentID)).count == derivatives.count else {
            throw ContentContractFailureV1.immutableOriginal
        }
        try derivatives.forEach { try $0.validate(clip: clip) }
    }
}

/// C45 generated label artifacts reuse canonical local content references.
enum C45AssetLabelBoundary_ContentReferenceContractsV1 {
    static func validate(_ plan: AssetLabelGenerationPlanV1) throws { try plan.validate() }
    static let createsSecondByteStore = false
}

enum C46OperationalContactConformance_FieldEvidenceApp_Domain_Content_ContentReferenceContractsV1_swift {
    static let operationalContactsRemainPurposeSeparated = true
    static let systemHandoffsRemainExplicitEphemeralAndNoncanonical = true
    static let subscriberConsentCampaignAndMeasurementProjectionForbidden = true
    static let contactExportExcludedByDefault = true
    static let siteRoleOwnershipForbidden = true
}

enum C48PortableReviewContentReferenceBoundaryV1 {
    static let rawCapabilityOrResponseBytesAreContentReferences = false
    static let derivedMetadataUsesPublicRequestIdentityOnly = true
    static let evidenceAssociationRemainsCanonical = true
}

// MARK: - C49 work-resource derived content boundary

enum C49WorkResourceContentReferenceBoundaryV1 {
    static let reportCarriesContentBytes = false
    static let reportCarriesLiveInventoryReferences = false
    static let localPartReferencesRemainFrozenSourceFacts = true

    static func validate(_ projection: C49WorkResourceReportProjectionV1) throws {
        try C49WorkResourceProjectionSupportV1.validate(projection)
        guard !C49WorkResourceProjectionSupportV1.rawStockRowsProjected,
              !C49WorkResourceProjectionSupportV1.liveInventoryClaims else {
            throw C49WorkResourceProjectionFailureV1.nonCanonical
        }
    }
}

import Foundation

enum ScheduleContentLocatorBoundaryV1 { static let reminderStateIsContent = false }

enum C51ScheduleContentLocatorBoundaryV1 {
    static let schedulePersistsNoLocators = true
    static let schedulePersistsNoContentBytes = true
    static let privateLocatorAuthorityRemainsUnchanged = true
}

enum AssetLocatorManifestBoundaryV1 {
    static let locatorLookupUsesContentLocatorManifest = false
    static let locatorResolutionMayFetchBytes = false
}

enum C50IncumbentContentLocatorBoundaryV1 {
    static let securityScopedURLsAreOperationScoped = true
    static let persistentBookmarksAreForbidden = true
    static let scratchPathsNeverBecomeCanonicalLocators = true
}

struct ContentLocatorV1: Codable, Equatable, Hashable, Identifiable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let locatorID: String
    let workspaceID: String
    let contentID: String
    let locatorRevision: Int
    let contentDigest: ContentDigestV1
    let expectedByteLength: Int64

    var id: String { "\(workspaceID)|\(locatorID)" }

    init(
        locatorID: String,
        workspaceID: String,
        contentID: String,
        locatorRevision: Int,
        contentDigest: ContentDigestV1,
        expectedByteLength: Int64
    ) throws {
        guard ContentContractValidationV1.validID(locatorID),
              ContentContractValidationV1.validID(workspaceID),
              ContentContractValidationV1.validID(contentID),
              locatorRevision >= 0, expectedByteLength >= 0 else {
            throw ContentContractFailureV1.invalidValue
        }
        schemaVersion = Self.schemaVersion
        self.locatorID = locatorID
        self.workspaceID = workspaceID
        self.contentID = contentID
        self.locatorRevision = locatorRevision
        self.contentDigest = contentDigest
        self.expectedByteLength = expectedByteLength
    }

    func validate(against reference: ContentReferenceV1) throws {
        guard workspaceID == reference.workspaceID else { throw ContentContractFailureV1.wrongWorkspace }
        guard contentID == reference.contentID else { throw ContentContractFailureV1.missingContent }
        guard expectedByteLength == reference.byteLength else { throw ContentContractFailureV1.byteLengthMismatch }
        guard reference.digests.digest(for: contentDigest.algorithm) == contentDigest else {
            throw ContentContractFailureV1.digestMismatch
        }
    }
}

extension ContentManifestV1 {
    func validateFieldReferenceOfflineClosure(references: [ContentReferenceV1], locators: [ContentLocatorV1]) throws {
        guard entries.allSatisfy(\.requiredForOpen) else { throw ContentContractFailureV1.missingContent }
        try validate(references: references, locators: locators)
    }
}

struct ContentManifestEntryV1: Codable, Equatable, Sendable {
    let contentID: String
    let expectedByteLength: Int64
    let mediaType: String
    let digest: ContentDigestV1
    let expectedLocatorRevision: Int
    let requiredForOpen: Bool

    init(
        contentID: String,
        expectedByteLength: Int64,
        mediaType: String,
        digest: ContentDigestV1,
        expectedLocatorRevision: Int,
        requiredForOpen: Bool
    ) throws {
        guard ContentContractValidationV1.validID(contentID), expectedByteLength >= 0,
              ContentContractValidationV1.validMediaType(mediaType), expectedLocatorRevision >= 0 else {
            throw ContentContractFailureV1.invalidValue
        }
        self.contentID = contentID
        self.expectedByteLength = expectedByteLength
        self.mediaType = mediaType
        self.digest = digest
        self.expectedLocatorRevision = expectedLocatorRevision
        self.requiredForOpen = requiredForOpen
    }
}

struct ContentManifestV1: Codable, Equatable, Identifiable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let manifestID: String
    let workspaceID: String
    let manifestRevision: Int
    let entries: [ContentManifestEntryV1]

    var id: String { "\(workspaceID)|\(manifestID)" }

    init(
        manifestID: String,
        workspaceID: String,
        manifestRevision: Int,
        entries: [ContentManifestEntryV1]
    ) throws {
        guard ContentContractValidationV1.validID(manifestID),
              ContentContractValidationV1.validID(workspaceID), manifestRevision >= 0,
              !entries.isEmpty, entries.count <= ContentContractLimitsV1.maximumManifestEntries,
              entries == entries.sorted(by: { $0.contentID < $1.contentID }),
              Set(entries.map(\.contentID)).count == entries.count else {
            throw ContentContractFailureV1.invalidValue
        }
        schemaVersion = Self.schemaVersion
        self.manifestID = manifestID
        self.workspaceID = workspaceID
        self.manifestRevision = manifestRevision
        self.entries = entries
    }

    func validate(
        references: [ContentReferenceV1],
        locators: [ContentLocatorV1]
    ) throws {
        guard references.count <= ContentContractLimitsV1.maximumManifestEntries,
              locators.count <= ContentContractLimitsV1.maximumManifestEntries else {
            throw ContentContractFailureV1.limitExceeded
        }
        guard Set(references.map(\.contentID)).count == references.count,
              Set(locators.map(\.contentID)).count == locators.count,
              Set(locators.map { "\($0.workspaceID)|\($0.locatorID)" }).count == locators.count else {
            throw ContentContractFailureV1.duplicateIdentity
        }
        let entryIDs = Set(entries.map(\.contentID))
        guard Set(references.map(\.contentID)) == entryIDs,
              Set(locators.map(\.contentID)) == entryIDs else {
            throw ContentContractFailureV1.missingContent
        }
        for entry in entries {
            let matches = references.filter { $0.contentID == entry.contentID }
            guard matches.count == 1 else { throw ContentContractFailureV1.missingContent }
            let reference = matches[0]
            guard reference.workspaceID == workspaceID else { throw ContentContractFailureV1.wrongWorkspace }
            guard reference.byteLength == entry.expectedByteLength else { throw ContentContractFailureV1.byteLengthMismatch }
            guard reference.mediaType == entry.mediaType else { throw ContentContractFailureV1.mediaTypeMismatch }
            guard reference.digests.digest(for: entry.digest.algorithm) == entry.digest else {
                throw ContentContractFailureV1.digestMismatch
            }
            let locatorMatches = locators.filter { $0.contentID == entry.contentID }
            guard locatorMatches.count == 1 else { throw ContentContractFailureV1.missingContent }
            let locator = locatorMatches[0]
            guard locator.locatorRevision == entry.expectedLocatorRevision else {
                throw ContentContractFailureV1.staleReference
            }
            try locator.validate(against: reference)
        }
    }

    func validateOpenability(
        references: [ContentReferenceV1],
        locators: [ContentLocatorV1]
    ) throws {
        guard references.count <= ContentContractLimitsV1.maximumManifestEntries,
              locators.count <= ContentContractLimitsV1.maximumManifestEntries else {
            throw ContentContractFailureV1.limitExceeded
        }
        guard Set(references.map(\.contentID)).count == references.count,
              Set(locators.map(\.contentID)).count == locators.count,
              Set(locators.map { "\($0.workspaceID)|\($0.locatorID)" }).count == locators.count else {
            throw ContentContractFailureV1.duplicateIdentity
        }
        for entry in entries where entry.requiredForOpen {
            guard let reference = references.first(where: { $0.contentID == entry.contentID }),
                  let locator = locators.first(where: { $0.contentID == entry.contentID }) else {
                throw ContentContractFailureV1.missingContent
            }
            guard reference.workspaceID == workspaceID else { throw ContentContractFailureV1.wrongWorkspace }
            guard reference.byteLength == entry.expectedByteLength else { throw ContentContractFailureV1.byteLengthMismatch }
            guard reference.mediaType == entry.mediaType else { throw ContentContractFailureV1.mediaTypeMismatch }
            guard reference.digests.digest(for: entry.digest.algorithm) == entry.digest else {
                throw ContentContractFailureV1.digestMismatch
            }
            guard locator.locatorRevision == entry.expectedLocatorRevision else {
                throw ContentContractFailureV1.staleReference
            }
            try locator.validate(against: reference)
        }
    }
}

enum ContentManifestCanonicalCodecV1 {
    static func encode(_ value: ContentManifestV1) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        guard data.count <= ContentContractLimitsV1.maximumCanonicalBytes else {
            throw ContentContractFailureV1.limitExceeded
        }
        return data
    }

    static func decode(_ data: Data) throws -> ContentManifestV1 {
        guard !data.isEmpty, data.count <= ContentContractLimitsV1.maximumCanonicalBytes else {
            throw ContentContractFailureV1.limitExceeded
        }
        let value = try JSONDecoder().decode(ContentManifestV1.self, from: data)
        guard try encode(value) == data else { throw ContentContractFailureV1.digestMismatch }
        return value
    }
}

extension ContentLocatorV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, locatorID, workspaceID, contentID, locatorRevision
        case contentDigest, expectedByteLength
    }
    init(from decoder: any Decoder) throws {
        try ContentClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else { throw ContentContractFailureV1.incompatibleVersion }
        try self.init(
            locatorID: c.decode(String.self, forKey: .locatorID), workspaceID: c.decode(String.self, forKey: .workspaceID),
            contentID: c.decode(String.self, forKey: .contentID), locatorRevision: c.decode(Int.self, forKey: .locatorRevision),
            contentDigest: c.decode(ContentDigestV1.self, forKey: .contentDigest), expectedByteLength: c.decode(Int64.self, forKey: .expectedByteLength)
        )
    }
}

extension ContentLocatorV1 {
    func validateAuthoritySourceBinding(_ release: AuthoritySourceReleaseV1) throws {
        try release.validate()
        guard release.contentLocator == self,
              AuthorityCriterionValidationV1.sameWorkspaceString(
                workspaceID,
                as: release.workspaceID
              ) else {
            throw ContentContractFailureV1.wrongWorkspace
        }
        if let reference = release.lawfulContentReference {
            try validate(against: reference)
        }
    }
}

extension ContentManifestEntryV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable { case contentID, expectedByteLength, mediaType, digest, expectedLocatorRevision, requiredForOpen }
    init(from decoder: any Decoder) throws {
        try ContentClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue)); let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(contentID: c.decode(String.self, forKey: .contentID), expectedByteLength: c.decode(Int64.self, forKey: .expectedByteLength), mediaType: c.decode(String.self, forKey: .mediaType), digest: c.decode(ContentDigestV1.self, forKey: .digest), expectedLocatorRevision: c.decode(Int.self, forKey: .expectedLocatorRevision), requiredForOpen: c.decode(Bool.self, forKey: .requiredForOpen))
    }
}

extension ContentManifestV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, manifestID, workspaceID, manifestRevision, entries }
    init(from decoder: any Decoder) throws {
        try ContentClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue)); let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else { throw ContentContractFailureV1.incompatibleVersion }
        try self.init(manifestID: c.decode(String.self, forKey: .manifestID), workspaceID: c.decode(String.self, forKey: .workspaceID), manifestRevision: c.decode(Int.self, forKey: .manifestRevision), entries: c.decode([ContentManifestEntryV1].self, forKey: .entries))
    }
}

extension ContentManifestV1 {
    func validatePrivacyTransformClosure(
        _ closure: PrivacyTransformLifecycleClosureV1,
        references: [ContentReferenceV1],
        locators: [ContentLocatorV1]
    ) throws {
        try closure.validate()
        try validate(references: references, locators: locators)
        let ids = Set(entries.map(\.contentID))
        guard ids.contains(closure.manifest.original.contentID),
              ids.contains(closure.manifest.derivative.contentID) else {
            throw ContentContractFailureV1.missingContent
        }
    }
}

// MARK: - C24 accessible-document locator boundary

/// A semantic-tree projection can describe recorded structure without making
/// a private content locator reachable from an audience output.  The locator
/// store remains the only byte resolver; this policy has no locator fields and
/// therefore cannot leak one by construction.
enum AccessibleDocumentLocatorBoundaryV1 {
    static let audienceOutputMayResolveLocators = false
    static let originalBytesMayResolveFromTree = false
    static let hiddenEvidenceIsOmitted = true
    static let privateLocatorsAreOmitted = true

    static func validateAudienceSafeTree(
        _ tree: AccessibleDocumentSemanticTreeV1
    ) throws {
        try AccessibleDocumentContentReferenceBoundaryV1.validateAudienceSafeTree(tree)
        guard tree.nodes.allSatisfy({
            $0.evidenceLinks.allSatisfy { !$0.evidenceID.isEmpty }
        }) else {
            throw AccessibleDocumentFailureV1.privacyViolation
        }
    }
}

/// C29 typed integration anchor: this owner consumes an exact immutable plan
/// revision reference and may not reinterpret current plan state implicitly.
enum C29PlanIntegration_Domain_Content_ContentLocatorManifestContractsV1 {
    static func validatePlanRevision(_ value: PlanRevisionReferenceV1) throws {
        try value.validate()
    }
}

enum C37PoseIntegration_FieldEvidenceApp_Domain_Content_ContentLocatorManifestContractsV1_swift {
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
enum C30ConsumerBoundaryV1_Domain_Content_ContentLocatorManifestContractsV1 {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Domain/Content/ContentLocatorManifestContractsV1.swift", role: .content)
}

struct C31LightingContentLocatorProjectionV1: Codable, Equatable, Sendable {
    let workspaceID: String
    let contentID: String
    let locatorRevision: Int
    let expectedByteLength: Int64

    init(_ locator: ContentLocatorV1) {
        workspaceID = locator.workspaceID
        contentID = locator.contentID
        locatorRevision = locator.locatorRevision
        expectedByteLength = locator.expectedByteLength
    }

    func validate() throws {
        guard !workspaceID.isEmpty, !contentID.isEmpty,
              locatorRevision >= 0, expectedByteLength >= 0 else {
            throw ContentContractFailureV1.invalidValue
        }
    }
}
// MARK: - C32 assistance content locator boundary

enum C32AssistanceLifecycleBoundary_FieldEvidenceApp_Domain_Content_ContentLocatorManifestContractsV1_swift {
    static let proposalIsPersistent = AssistancePersistenceEnrollmentV1.proposalIsPersistent
    static let rejectedProposalCorpusIsPersistent = AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent
    static let durableFamilyCount = AssistancePersistenceEnrollmentV1.durableModelCount
    static let acceptedMutationKind: WorkspaceCommandKindV1 = .applyAssistanceAcceptance
    static let manualFallback: ManualFallbackActionV1 = .typeManually
    static let proposalSourceLocatorIsNotCanonicalContent = true

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

// MARK: - C33 temporal evidence locator closure

enum TemporalEvidenceLocatorBoundaryV1 {
    static let locatorsRemainPrivateStorageCoordinates = true
    static let reportsContainLocators = false

    static func validate(
        clip: TemporalEvidenceClipV1,
        derivatives: [TemporalEvidenceDerivativeV1]
    ) throws {
        try clip.locator.validate(against: clip.original)
        try derivatives.forEach {
            try $0.validate(clip: clip)
            try $0.locator.validate(against: $0.content)
        }
        let allIDs = [clip.original.contentID] + derivatives.map(\.content.contentID)
        guard Set(allIDs).count == allIDs.count else {
            throw ContentContractFailureV1.duplicateIdentity
        }
    }
}

/// C45 published label files use neutral filenames and digest-bound locators.
enum C45AssetLabelBoundary_ContentLocatorManifestContractsV1 {
    static func validate(_ plan: AssetLabelGenerationPlanV1) throws { try plan.validate() }
    static let usesNeutralFilenames = true
}

enum C46OperationalContactConformance_FieldEvidenceApp_Domain_Content_ContentLocatorManifestContractsV1_swift {
    static let operationalContactsRemainPurposeSeparated = true
    static let systemHandoffsRemainExplicitEphemeralAndNoncanonical = true
    static let subscriberConsentCampaignAndMeasurementProjectionForbidden = true
    static let contactExportExcludedByDefault = true
    static let siteRoleOwnershipForbidden = true
}

enum C48PortableReviewContentLocatorBoundaryV1 {
    static let capabilityProofLocatorIsAllowed = false
    static let responseByteLocatorIsAllowed = false
    static let derivedProjectionMayExposeFilesystemIdentity = false
    static let customerSafeReportUsesExistingContentLocatorsOnly = true
}

// MARK: - C49 work-resource locator boundary

enum C49WorkResourceContentLocatorBoundaryV1 {
    static let reportCarriesFilesystemCoordinates = false
    static let reportCarriesLiveStockCoordinates = false
    static let locatorProjectionIsMetadataOnly = true

    static func validate(_ envelope: C49WorkResourceProjectionEnvelopeV1) throws {
        try envelope.validate()
        guard envelope.projection.sourceRecordIDs == envelope.projection.sourceRecordIDs.sorted(by: {
            $0.uuidString < $1.uuidString
        }) else {
            throw C49WorkResourceProjectionFailureV1.nonCanonical
        }
    }
}

enum C34ContentLocatorRouteSemanticIDAdapterV1 {
    static let routeStoresLocatorBytes = false

    static func semanticID(from locator: ContentLocatorV1) throws -> String {
        try RouteContractValidationV1.semanticID(locator.locatorID)
        return locator.locatorID
    }
}

enum C34RouteAdoptionBoundary_ContentLocatorManifestContractsV1 {
    static let semanticIDAdapter = C34ContentLocatorRouteSemanticIDAdapterV1.self
    static let canonicalTargetType = NavigationTargetV1.self
    static let routeStoresLocatorBytes = false
}
enum C52ServiceRequestBoundary_ContentLocatorManifestContractsV1 {
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

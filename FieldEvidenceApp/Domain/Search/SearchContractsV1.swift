import Foundation

/// Typed composition seam for the single protected, disposable system index.
/// The incumbent search/deletion/report owners may depend on this port without
/// gaining access to CoreSpotlight or to private query/route parameters.
protocol PrivateSystemDiscoveryIndexLifecyclePortV1: Sendable {
    func rebuild(
        operationID: PrivateSystemDiscoveryOperationIDV1,
        workspaceID: WorkspaceID,
        workspaceRevision: UInt64,
        deletionFrontier: UInt64,
        descriptors: [PrivateSystemDiscoveryProjectionDescriptorV1],
        manifest: PrivateSystemDiscoveryManifestV1,
        optIn: PrivateSystemDiscoveryOptInV1,
        availability: [AppIntentAvailabilityV1],
        now: Date
    ) async throws
    func remove(operationID: PrivateSystemDiscoveryOperationIDV1, workspaceID: WorkspaceID, now: Date) async throws
    func eraseAll(operationID: PrivateSystemDiscoveryOperationIDV1, now: Date) async throws
    func dropAndRebuild() async throws
    func state() async throws -> PrivateSystemDiscoveryStateMapV1
    func journalEntries() async throws -> [PrivateSystemDiscoveryJournalEntryV1]
}

protocol PrivateSystemDiscoveryClientStateStoreV1: Sendable {
    func load() throws -> PrivateSystemDiscoveryClientStateV1?
    func save(_ state: PrivateSystemDiscoveryClientStateV1) throws
    func clear() throws
}

struct PrivateSystemDiscoveryIndexItemV1: Equatable, Sendable {
    let uniqueIdentifier: String
    let domainIdentifier: String
    let titleKey: String
    let actionToken: String
}

protocol PrivateSystemDiscoveryProtectedIndexClientV1: Sendable {
    func replaceItems(
        deleting identifiers: [String],
        with items: [PrivateSystemDiscoveryIndexItemV1]
    ) async throws
    func deleteItems(withIdentifiers identifiers: [String]) async throws
    func deleteAllItems() async throws
}

protocol PrivateSystemDiscoveryRebuildRequestProvidingV1: Sendable {
    func privateSystemDiscoveryRebuildRequest(
        source: SearchSourceRevisionV1,
        operationID: PrivateSystemDiscoveryOperationIDV1
    ) async throws -> PrivateSystemDiscoveryIndexRebuildPayloadV1?
}

enum SearchContractFailureV1: Error, Equatable, Sendable {
    case unsupportedSchemaVersion
    case invalidIdentifier
    case invalidText
    case invalidField
    case duplicateField
    case forbiddenField
    case scopeMismatch
    case invalidQuery
    case invalidFilter
    case invalidRanking
    case invalidSuggestion
    case invalidContext
    case invalidSession
    case invalidRevision
    case indexAheadOfSource
    case staleIndex
    case duplicateProjection
    case invalidSmartView
    case builtInViewMutation
    case limitExceeded
}

enum SearchContractLimitsV1 {
    static let maximumIdentifierBytes = 160
    static let maximumQueryBytes = 512
    static let maximumNormalizedTokenBytes = 128
    static let maximumQueryTokens = 32
    static let exactSearchableFieldCount = 10
    static let maximumFieldRegistrations = 13
    /// Additive C38 party projection fields.  The original 13-field registry
    /// remains valid for callers that have not opted into accountability.
    static let maximumAccountabilityFieldRegistrations = 17
    /// Additive C39 semantic fields are opt-in and never replace the frozen
    /// V1/V2 registries.
    static let maximumAssetSemanticsFieldRegistrations = 18
    static let maximumAccountabilityAssetSemanticsFieldRegistrations = 22
    static let maximumAuthorityCriterionFieldRegistrations = 18
    static let maximumAccountabilityAuthorityCriterionFieldRegistrations = 22
    static let maximumAssetSemanticsAuthorityCriterionFieldRegistrations = 23
    static let maximumAllProjectionFieldRegistrations = 27
    /// C41 relationship fields are opt-in. The legacy maximum above remains
    /// unchanged for byte-compatible V1--V3 registries.
    static let maximumFunctionalRelationshipFieldRegistrations = 17
    static let maximumAccountabilityFunctionalRelationshipFieldRegistrations = 21
    static let maximumAssetSemanticsFunctionalRelationshipFieldRegistrations = 22
    static let maximumAccountabilityAssetSemanticsFunctionalRelationshipFieldRegistrations = 26
    static let maximumAuthorityCriterionFunctionalRelationshipFieldRegistrations = 22
    static let maximumAccountabilityAuthorityCriterionFunctionalRelationshipFieldRegistrations = 26
    static let maximumAssetSemanticsAuthorityCriterionFunctionalRelationshipFieldRegistrations = 27
    static let maximumAllProjectionFunctionalRelationshipFieldRegistrations = 31
    /// C13 assurance fields are opt-in and add only audience-safe disposition
    /// metadata to the disposable report index.
    static let maximumAssuranceFieldRegistrations = 17
    static let maximumAccountabilityAssuranceFieldRegistrations = 21
    static let maximumAssetSemanticsAssuranceFieldRegistrations = 22
    static let maximumAccountabilityAssetSemanticsAssuranceFieldRegistrations = 26
    static let maximumAuthorityCriterionAssuranceFieldRegistrations = 22
    static let maximumAccountabilityAuthorityCriterionAssuranceFieldRegistrations = 26
    static let maximumAssetSemanticsAuthorityCriterionAssuranceFieldRegistrations = 27
    static let maximumAllProjectionAssuranceFieldRegistrations = 31
    static let maximumAssuranceFunctionalRelationshipFieldRegistrations = 21
    static let maximumAccountabilityAssuranceFunctionalRelationshipFieldRegistrations = 25
    static let maximumAssetSemanticsAssuranceFunctionalRelationshipFieldRegistrations = 26
    static let maximumAccountabilityAssetSemanticsAssuranceFunctionalRelationshipFieldRegistrations = 30
    static let maximumAuthorityCriterionAssuranceFunctionalRelationshipFieldRegistrations = 26
    static let maximumAccountabilityAuthorityCriterionAssuranceFunctionalRelationshipFieldRegistrations = 30
    static let maximumAssetSemanticsAuthorityCriterionAssuranceFunctionalRelationshipFieldRegistrations = 31
    static let maximumAllProjectionAssuranceFunctionalRelationshipFieldRegistrations = 35
    /// C14 inspection-review metadata is opt-in and adds only typed state and
    /// projection-version fields. Review reasons, actor snapshots, and
    /// evidence content are never searchable values.
    static let maximumInspectionReviewFieldRegistrations = 40
    /// C15 packet coordination is opt-in and contributes only packet/item
    /// identifiers plus current-head typed state. Claims, leases, actors,
    /// result links, and collision digests are never searchable values.
    static let maximumWorkPacketFieldRegistrations = 45
    static let maximumFilters = 16
    static let maximumSuggestions = 5
    static let maximumSnippetBytes = 320
    static let maximumBreadcrumbComponents = 16
    static let maximumProjectionTokens = 128
    static let maximumCanonicalRecords = 10_000
    static let maximumC13SearchableFieldCount = maximumAllProjectionAssuranceFunctionalRelationshipFieldRegistrations
    /// The C14 registry is the largest admitted projection. Older registries
    /// remain valid by their exact identity-set checks below, but rebuild and
    /// staging capacity must also cover an opted-in C14 index.
    static let maximumSearchableFieldCount = maximumWorkPacketFieldRegistrations
    static let maximumC41SearchableFieldCount = maximumAllProjectionFunctionalRelationshipFieldRegistrations
    static let maximumC14SearchableFieldCount = maximumInspectionReviewFieldRegistrations
    static let maximumC15SearchableFieldCount = maximumWorkPacketFieldRegistrations
    static let maximumProjectionRecords = maximumCanonicalRecords * maximumSearchableFieldCount
    static let maximumAccountabilityProjectionFieldsPerRecord = 4
    static let maximumAccountabilityProjectionRecords = maximumCanonicalRecords
        * maximumAccountabilityProjectionFieldsPerRecord
    static let maximumSavedViewNameBytes = 120
}

enum SearchContractValidationV1 {
    static let zeroUUID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    private static let bidiFormattingScalars: Set<UInt32> = [
        0x061C, 0x200E, 0x200F,
        0x202A, 0x202B, 0x202C, 0x202D, 0x202E,
        0x2066, 0x2067, 0x2068, 0x2069,
    ]

    static func validID(_ value: String, maximumBytes: Int = SearchContractLimitsV1.maximumIdentifierBytes) -> Bool {
        !value.isEmpty && value.utf8.count <= maximumBytes
            && value.unicodeScalars.allSatisfy { scalar in
                !CharacterSet.controlCharacters.contains(scalar)
                    && !CharacterSet.whitespacesAndNewlines.contains(scalar)
            }
    }

    static func validDisplayText(_ value: String, maximumBytes: Int, allowEmpty: Bool = false) -> Bool {
        (value.isEmpty ? allowEmpty : !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            && value.utf8.count <= maximumBytes
            && !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }

    static func validDate(_ value: Date) -> Bool { value.timeIntervalSinceReferenceDate.isFinite }

    static func normalizeSearchText(_ value: String) -> String {
        let safeScalars = value.unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0)
                && !bidiFormattingScalars.contains($0.value)
        }
        let safe = String(String.UnicodeScalarView(safeScalars))
        return safe
            .decomposedStringWithCompatibilityMapping
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .precomposedStringWithCanonicalMapping
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
    }

    static func isCanonicalSearchToken(_ value: String) -> Bool {
        validDisplayText(value, maximumBytes: SearchContractLimitsV1.maximumNormalizedTokenBytes)
            && value.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) }
            && value == normalizeSearchText(value)
    }

    static func normalizedTokensAreCanonical(_ values: [String]) -> Bool {
        values.count <= SearchContractLimitsV1.maximumQueryTokens
            && Set(values).count == values.count
            && values.allSatisfy(isCanonicalSearchToken)
    }
}

enum SearchScopeV1: String, CaseIterable, Codable, Hashable, Sendable {
    case all = "ALL"
    case assets = "ASSETS"
    case locations = "LOCATIONS"
    case work = "WORK"
    case reports = "REPORTS"
    case parties = "PARTIES"

    func contains(_ kind: SearchSourceKindV1) -> Bool {
        switch self {
        case .all: return true
        case .assets: return kind == .asset
        case .locations: return kind == .location
        case .work: return kind == .work
        case .reports: return kind == .report
        case .parties: return kind == .party
        }
    }
}

enum SearchSourceKindV1: String, CaseIterable, Codable, Hashable, Sendable {
    case asset = "ASSET"
    case location = "LOCATION"
    case work = "WORK"
    case report = "REPORT"
    case party = "PARTY"
}

enum EntityIdentityResolutionSearchBoundaryV1 {
    static let aliasAndSurvivorIdentifiersAreIndexed = true
    static let indexIsDerivedAndDisposable = true
    static let historicEvidenceOrRelationshipRowsAreRewritten = false
    static let relationshipRowsAreConsolidationAuthority = false
    static let automaticConsolidationFromSearchPermitted = false
}

enum SearchFieldPrivacyClassV1: String, CaseIterable, Codable, Hashable, Sendable {
    case userVisibleIdentifier = "USER_VISIBLE_IDENTIFIER"
    case approvedCustomerText = "APPROVED_CUSTOMER_TEXT"
    case approvedOperationalState = "APPROVED_OPERATIONAL_STATE"
}

enum SearchTokenizationV1: String, CaseIterable, Codable, Hashable, Sendable {
    case exactIdentity = "EXACT_IDENTITY"
    case unicodeWords = "UNICODE_WORDS"
    case keyword = "KEYWORD"
}

enum SearchNormalizationV1: String, CaseIterable, Codable, Hashable, Sendable {
    case stableIdentity = "STABLE_IDENTITY"
    case unicodeCaseAndDiacriticFoldedNFC = "UNICODE_CASE_DIACRITIC_FOLDED_NFC"
}

enum SearchSnippetPermissionV1: String, CaseIterable, Codable, Hashable, Sendable {
    case prohibited = "PROHIBITED"
    case boundedUserVisibleExcerpt = "BOUNDED_USER_VISIBLE_EXCERPT"
    case exactDisplayValue = "EXACT_DISPLAY_VALUE"
}

enum SearchFieldRetentionV1: String, CaseIterable, Codable, Hashable, Sendable {
    case whileCanonicalSourceExists = "WHILE_CANONICAL_SOURCE_EXISTS"
    case untilSourceFieldIsAmended = "UNTIL_SOURCE_FIELD_IS_AMENDED"
}

enum SearchPurgeOwnerV1: String, CaseIterable, Codable, Hashable, Sendable {
    case canonicalWriterReconciler = "CANONICAL_WRITER_RECONCILER"
    case indexRebuildCoordinator = "INDEX_REBUILD_COORDINATOR"
}

enum FrozenSearchableFieldV1: String, CaseIterable, Codable, Hashable, Sendable {
    case assetIdentifier = "asset_identifier"
    case assetLabel = "asset_label"
    case locationIdentifier = "location_identifier"
    case locationLabel = "location_label"
    case locationBreadcrumb = "location_breadcrumb"
    case workIdentifier = "work_identifier"
    case workSummary = "work_summary"
    case reportIdentifier = "report_identifier"
    case reportSummary = "report_summary"
    case partyIdentifier = "party_identifier"
    case partyLabel = "party_label"
    case partyRole = "party_role"
    case status = "status"
    case assetSemanticKind = "asset_semantic_kind"
    case assetSemanticCapability = "asset_semantic_capability"
    case assetLifecycleEvent = "asset_lifecycle_event"
    case assetProductIdentityState = "asset_product_identity_state"
    case workSubjectScope = "work_subject_scope"
    case authoritySource = "authority_source"
    case applicabilityDisposition = "applicability_disposition"
    case criterionResult = "criterion_result"
    case severityLevel = "severity_level"
    case measurementProtocol = "measurement_protocol"
    case functionalRelationshipDescriptor = "functional_relationship_descriptor"
    case functionalRelationshipDirection = "functional_relationship_direction"
    case functionalRelationshipState = "functional_relationship_state"
    case functionalRelationshipEndpoint = "functional_relationship_endpoint"
    case assuranceAudience = "assurance_audience"
    case assuranceDisposition = "assurance_disposition"
    case assuranceLimitation = "assurance_limitation"
    case assuranceProjectionVersion = "assurance_projection_version"
    case inspectionReviewState = "inspection_review_state"
    case inspectionReviewDisposition = "inspection_review_disposition"
    case changeRequestState = "change_request_state"
    case correctiveActionState = "corrective_action_state"
    case inspectionReviewProjectionVersion = "inspection_review_projection_version"
    case workPacketIdentifier = "work_packet_identifier"
    case workPacketManifestState = "work_packet_manifest_state"
    case workPacketItemState = "work_packet_item_state"
    case workPacketConflictState = "work_packet_conflict_state"
    case workPacketProjectionVersion = "work_packet_projection_version"

    var allowedSourceKinds: Set<SearchSourceKindV1> {
        switch self {
        case .assetIdentifier, .assetLabel: return [.asset]
        case .locationIdentifier, .locationLabel, .locationBreadcrumb: return [.location]
        case .workIdentifier, .workSummary: return [.work]
        case .reportIdentifier, .reportSummary: return [.report]
        case .partyIdentifier, .partyLabel, .partyRole: return [.party]
        case .status: return Set(SearchSourceKindV1.allCases)
        case .assetSemanticKind, .assetSemanticCapability, .assetLifecycleEvent,
             .assetProductIdentityState, .workSubjectScope: return [.asset]
        case .authoritySource, .applicabilityDisposition, .criterionResult,
             .severityLevel, .measurementProtocol: return [.work]
        case .functionalRelationshipDescriptor, .functionalRelationshipDirection,
             .functionalRelationshipState, .functionalRelationshipEndpoint: return [.asset]
        case .assuranceAudience, .assuranceDisposition, .assuranceLimitation,
             .assuranceProjectionVersion: return [.report]
        case .inspectionReviewState, .inspectionReviewDisposition,
             .changeRequestState, .correctiveActionState,
             .inspectionReviewProjectionVersion: return [.report]
        case .workPacketIdentifier, .workPacketManifestState,
             .workPacketItemState, .workPacketConflictState,
             .workPacketProjectionVersion: return [.work]
        }
    }

    var isIdentifier: Bool {
        switch self {
        case .assetIdentifier, .locationIdentifier, .workIdentifier, .reportIdentifier,
             .partyIdentifier, .workPacketIdentifier: return true
        default: return false
        }
    }
}

struct SearchableFieldDescriptorV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let fieldID: String
    let sourceKind: SearchSourceKindV1
    let privacyClass: SearchFieldPrivacyClassV1
    let tokenization: SearchTokenizationV1
    let normalization: SearchNormalizationV1
    let snippetPermission: SearchSnippetPermissionV1
    let retention: SearchFieldRetentionV1
    let purgeOwner: SearchPurgeOwnerV1

    init(
        fieldID: String,
        sourceKind: SearchSourceKindV1,
        privacyClass: SearchFieldPrivacyClassV1,
        tokenization: SearchTokenizationV1,
        normalization: SearchNormalizationV1,
        snippetPermission: SearchSnippetPermissionV1,
        retention: SearchFieldRetentionV1,
        purgeOwner: SearchPurgeOwnerV1
    ) throws {
        schemaVersion = Self.schemaVersion
        self.fieldID = fieldID
        self.sourceKind = sourceKind
        self.privacyClass = privacyClass
        self.tokenization = tokenization
        self.normalization = normalization
        self.snippetPermission = snippetPermission
        self.retention = retention
        self.purgeOwner = purgeOwner
        try validate()
    }

    func validate() throws {
        guard let frozenField = FrozenSearchableFieldV1(rawValue: fieldID),
              frozenField.allowedSourceKinds.contains(sourceKind),
              !Self.explicitlyExcludedFieldIDs.contains(fieldID),
              !fieldID.contains("uncommitted") else {
            throw SearchContractFailureV1.forbiddenField
        }
        guard schemaVersion == Self.schemaVersion,
              SearchContractValidationV1.validID(fieldID),
              !Self.forbiddenFieldFragments.contains(where: { fieldID.lowercased().contains($0) }) else {
            throw SearchContractFailureV1.forbiddenField
        }
        if frozenField.isIdentifier {
            guard privacyClass == .userVisibleIdentifier,
                  tokenization == .exactIdentity,
                  normalization == .stableIdentity,
                  snippetPermission == .exactDisplayValue else {
                throw SearchContractFailureV1.invalidField
            }
        } else if frozenField == .status {
            guard privacyClass == .approvedOperationalState,
                  tokenization == .keyword,
                  normalization == .unicodeCaseAndDiacriticFoldedNFC,
                  snippetPermission == .exactDisplayValue else {
                throw SearchContractFailureV1.invalidField
            }
        } else {
            guard privacyClass == .approvedCustomerText,
                  tokenization == .unicodeWords,
                  normalization == .unicodeCaseAndDiacriticFoldedNFC,
                  snippetPermission == .boundedUserVisibleExcerpt else {
                throw SearchContractFailureV1.invalidField
            }
        }
        guard retention == .untilSourceFieldIsAmended,
              purgeOwner == .indexRebuildCoordinator else {
            throw SearchContractFailureV1.invalidField
        }
        if privacyClass == .approvedCustomerText && tokenization != .unicodeWords {
            throw SearchContractFailureV1.invalidField
        }
        if tokenization == .exactIdentity {
            guard privacyClass == .userVisibleIdentifier,
                  normalization == .stableIdentity else { throw SearchContractFailureV1.invalidField }
        }
        if snippetPermission == .exactDisplayValue && privacyClass == .approvedCustomerText {
            throw SearchContractFailureV1.invalidField
        }
    }

    private static let forbiddenFieldFragments = [
        "media", "binary", "original", "ocr", "hidden", "metadata", "support", "feedback", "draft",
        "uncommitted"
    ]
    private static let explicitlyExcludedFieldIDs: Set<String> = [
        "media_bytes", "raw_ocr", "hidden_metadata", "support_draft", "feedback_draft",
        "uncommitted_c36",
    ]
}

struct SearchableFieldRegistryV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let fields: [SearchableFieldDescriptorV1]

    init(fields: [SearchableFieldDescriptorV1]) throws {
        schemaVersion = Self.schemaVersion
        self.fields = fields.sorted {
            if $0.fieldID != $1.fieldID { return $0.fieldID < $1.fieldID }
            return $0.sourceKind.rawValue < $1.sourceKind.rawValue
        }
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              fields.count <= SearchContractLimitsV1.maximumWorkPacketFieldRegistrations else {
            throw SearchContractFailureV1.limitExceeded
        }
        guard fields.count == SearchContractLimitsV1.maximumFieldRegistrations
                || fields.count == SearchContractLimitsV1.maximumAccountabilityFieldRegistrations
                || fields.count == SearchContractLimitsV1.maximumAssetSemanticsFieldRegistrations
                || fields.count == SearchContractLimitsV1.maximumAccountabilityAssetSemanticsFieldRegistrations
                || fields.count == SearchContractLimitsV1.maximumAuthorityCriterionFieldRegistrations
                || fields.count == SearchContractLimitsV1.maximumAccountabilityAuthorityCriterionFieldRegistrations
                || fields.count == SearchContractLimitsV1.maximumAssetSemanticsAuthorityCriterionFieldRegistrations
                || fields.count == SearchContractLimitsV1.maximumAllProjectionFieldRegistrations
                || fields.count == SearchContractLimitsV1.maximumFunctionalRelationshipFieldRegistrations
                || fields.count == SearchContractLimitsV1.maximumAccountabilityFunctionalRelationshipFieldRegistrations
                || fields.count == SearchContractLimitsV1.maximumAssetSemanticsFunctionalRelationshipFieldRegistrations
                || fields.count == SearchContractLimitsV1.maximumAccountabilityAssetSemanticsFunctionalRelationshipFieldRegistrations
                || fields.count == SearchContractLimitsV1.maximumAuthorityCriterionFunctionalRelationshipFieldRegistrations
                || fields.count == SearchContractLimitsV1.maximumAccountabilityAuthorityCriterionFunctionalRelationshipFieldRegistrations
                || fields.count == SearchContractLimitsV1.maximumAssetSemanticsAuthorityCriterionFunctionalRelationshipFieldRegistrations
                || fields.count == SearchContractLimitsV1.maximumAllProjectionFunctionalRelationshipFieldRegistrations
                || fields.count == SearchContractLimitsV1.maximumAssuranceFieldRegistrations
                || fields.count == SearchContractLimitsV1.maximumAccountabilityAssuranceFieldRegistrations
                || fields.count == SearchContractLimitsV1.maximumAssetSemanticsAssuranceFieldRegistrations
                || fields.count == SearchContractLimitsV1.maximumAccountabilityAssetSemanticsAssuranceFieldRegistrations
                || fields.count == SearchContractLimitsV1.maximumAuthorityCriterionAssuranceFieldRegistrations
                || fields.count == SearchContractLimitsV1.maximumAccountabilityAuthorityCriterionAssuranceFieldRegistrations
                || fields.count == SearchContractLimitsV1.maximumAssetSemanticsAuthorityCriterionAssuranceFieldRegistrations
                || fields.count == SearchContractLimitsV1.maximumAllProjectionAssuranceFieldRegistrations
                || fields.count == SearchContractLimitsV1.maximumAssuranceFunctionalRelationshipFieldRegistrations
                || fields.count == SearchContractLimitsV1.maximumAccountabilityAssuranceFunctionalRelationshipFieldRegistrations
                || fields.count == SearchContractLimitsV1.maximumAssetSemanticsAssuranceFunctionalRelationshipFieldRegistrations
                || fields.count == SearchContractLimitsV1.maximumAccountabilityAssetSemanticsAssuranceFunctionalRelationshipFieldRegistrations
                || fields.count == SearchContractLimitsV1.maximumAuthorityCriterionAssuranceFunctionalRelationshipFieldRegistrations
                || fields.count == SearchContractLimitsV1.maximumAccountabilityAuthorityCriterionAssuranceFunctionalRelationshipFieldRegistrations
                || fields.count == SearchContractLimitsV1.maximumAssetSemanticsAuthorityCriterionAssuranceFunctionalRelationshipFieldRegistrations
                || fields.count == SearchContractLimitsV1.maximumAllProjectionAssuranceFunctionalRelationshipFieldRegistrations
                || fields.count == SearchContractLimitsV1.maximumInspectionReviewFieldRegistrations
                || fields.count == SearchContractLimitsV1.maximumWorkPacketFieldRegistrations else {
            throw SearchContractFailureV1.invalidField
        }
        let identities = fields.map { $0.fieldID + ":" + $0.sourceKind.rawValue }
        guard Set(identities).count == fields.count else {
            throw SearchContractFailureV1.duplicateField
        }
        guard Set(identities) == Self.frozenRegistrationIdentities
                || Set(identities) == Self.accountabilityRegistrationIdentities
                || Set(identities) == Self.assetSemanticsRegistrationIdentities
                || Set(identities) == Self.accountabilityAssetSemanticsRegistrationIdentities
                || Set(identities) == Self.authorityCriterionRegistrationIdentities
                || Set(identities) == Self.accountabilityAuthorityCriterionRegistrationIdentities
                || Set(identities) == Self.assetSemanticsAuthorityCriterionRegistrationIdentities
                || Set(identities) == Self.allProjectionRegistrationIdentities
                || Set(identities) == Self.functionalRelationshipRegistrationIdentities
                || Set(identities) == Self.accountabilityFunctionalRelationshipRegistrationIdentities
                || Set(identities) == Self.assetSemanticsFunctionalRelationshipRegistrationIdentities
                || Set(identities) == Self.accountabilityAssetSemanticsFunctionalRelationshipRegistrationIdentities
                || Set(identities) == Self.authorityCriterionFunctionalRelationshipRegistrationIdentities
                || Set(identities) == Self.accountabilityAuthorityCriterionFunctionalRelationshipRegistrationIdentities
                || Set(identities) == Self.assetSemanticsAuthorityCriterionFunctionalRelationshipRegistrationIdentities
                || Set(identities) == Self.allProjectionFunctionalRelationshipRegistrationIdentities
                || Set(identities) == Self.assuranceRegistrationIdentities
                || Set(identities) == Self.accountabilityAssuranceRegistrationIdentities
                || Set(identities) == Self.assetSemanticsAssuranceRegistrationIdentities
                || Set(identities) == Self.accountabilityAssetSemanticsAssuranceRegistrationIdentities
                || Set(identities) == Self.authorityCriterionAssuranceRegistrationIdentities
                || Set(identities) == Self.accountabilityAuthorityCriterionAssuranceRegistrationIdentities
                || Set(identities) == Self.assetSemanticsAuthorityCriterionAssuranceRegistrationIdentities
                || Set(identities) == Self.allProjectionAssuranceRegistrationIdentities
                || Set(identities) == Self.assuranceFunctionalRelationshipRegistrationIdentities
                || Set(identities) == Self.accountabilityAssuranceFunctionalRelationshipRegistrationIdentities
                || Set(identities) == Self.assetSemanticsAssuranceFunctionalRelationshipRegistrationIdentities
                || Set(identities) == Self.accountabilityAssetSemanticsAssuranceFunctionalRelationshipRegistrationIdentities
                || Set(identities) == Self.authorityCriterionAssuranceFunctionalRelationshipRegistrationIdentities
                || Set(identities) == Self.accountabilityAuthorityCriterionAssuranceFunctionalRelationshipRegistrationIdentities
                || Set(identities) == Self.assetSemanticsAuthorityCriterionAssuranceFunctionalRelationshipRegistrationIdentities
                || Set(identities) == Self.allProjectionAssuranceFunctionalRelationshipRegistrationIdentities
                || Set(identities) == Self.inspectionReviewRegistrationIdentities
                || Set(identities) == Self.workPacketRegistrationIdentities else {
            throw SearchContractFailureV1.invalidField
        }
        try fields.forEach { try $0.validate() }
    }

    private static let frozenRegistrationIdentities: Set<String> = [
        "asset_identifier:ASSET",
        "asset_label:ASSET",
        "location_identifier:LOCATION",
        "location_label:LOCATION",
        "location_breadcrumb:LOCATION",
        "work_identifier:WORK",
        "work_summary:WORK",
        "report_identifier:REPORT",
        "report_summary:REPORT",
        "status:ASSET",
        "status:LOCATION",
        "status:WORK",
        "status:REPORT",
    ]

    static let accountabilityRegistrationIdentities: Set<String> = frozenRegistrationIdentities.union([
        "party_identifier:PARTY",
        "party_label:PARTY",
        "party_role:PARTY",
        "status:PARTY",
    ])

    static let assetSemanticsRegistrationIdentities: Set<String> = frozenRegistrationIdentities.union([
        "asset_semantic_kind:ASSET",
        "asset_semantic_capability:ASSET",
        "asset_lifecycle_event:ASSET",
        "asset_product_identity_state:ASSET",
        "work_subject_scope:ASSET",
    ])

    static let accountabilityAssetSemanticsRegistrationIdentities: Set<String> =
        accountabilityRegistrationIdentities.union([
            "asset_semantic_kind:ASSET",
            "asset_semantic_capability:ASSET",
            "asset_lifecycle_event:ASSET",
            "asset_product_identity_state:ASSET",
            "work_subject_scope:ASSET",
        ])

    static let authorityCriterionRegistrationIdentities: Set<String> =
        frozenRegistrationIdentities.union(authorityCriterionFields)
    static let accountabilityAuthorityCriterionRegistrationIdentities: Set<String> =
        accountabilityRegistrationIdentities.union(authorityCriterionFields)
    static let assetSemanticsAuthorityCriterionRegistrationIdentities: Set<String> =
        assetSemanticsRegistrationIdentities.union(authorityCriterionFields)
    static let allProjectionRegistrationIdentities: Set<String> =
        accountabilityAssetSemanticsRegistrationIdentities.union(authorityCriterionFields)

    static let functionalRelationshipRegistrationIdentities: Set<String> =
        frozenRegistrationIdentities.union(functionalRelationshipFields)
    static let accountabilityFunctionalRelationshipRegistrationIdentities: Set<String> =
        accountabilityRegistrationIdentities.union(functionalRelationshipFields)
    static let assetSemanticsFunctionalRelationshipRegistrationIdentities: Set<String> =
        assetSemanticsRegistrationIdentities.union(functionalRelationshipFields)
    static let accountabilityAssetSemanticsFunctionalRelationshipRegistrationIdentities: Set<String> =
        accountabilityAssetSemanticsRegistrationIdentities.union(functionalRelationshipFields)
    static let authorityCriterionFunctionalRelationshipRegistrationIdentities: Set<String> =
        authorityCriterionRegistrationIdentities.union(functionalRelationshipFields)
    static let accountabilityAuthorityCriterionFunctionalRelationshipRegistrationIdentities: Set<String> =
        accountabilityAuthorityCriterionRegistrationIdentities.union(functionalRelationshipFields)
    static let assetSemanticsAuthorityCriterionFunctionalRelationshipRegistrationIdentities: Set<String> =
        assetSemanticsAuthorityCriterionRegistrationIdentities.union(functionalRelationshipFields)
    static let allProjectionFunctionalRelationshipRegistrationIdentities: Set<String> =
        allProjectionRegistrationIdentities.union(functionalRelationshipFields)

    static let assuranceRegistrationIdentities: Set<String> =
        frozenRegistrationIdentities.union(assuranceFields)
    static let accountabilityAssuranceRegistrationIdentities: Set<String> =
        accountabilityRegistrationIdentities.union(assuranceFields)
    static let assetSemanticsAssuranceRegistrationIdentities: Set<String> =
        assetSemanticsRegistrationIdentities.union(assuranceFields)
    static let accountabilityAssetSemanticsAssuranceRegistrationIdentities: Set<String> =
        accountabilityAssetSemanticsRegistrationIdentities.union(assuranceFields)
    static let authorityCriterionAssuranceRegistrationIdentities: Set<String> =
        authorityCriterionRegistrationIdentities.union(assuranceFields)
    static let accountabilityAuthorityCriterionAssuranceRegistrationIdentities: Set<String> =
        accountabilityAuthorityCriterionRegistrationIdentities.union(assuranceFields)
    static let assetSemanticsAuthorityCriterionAssuranceRegistrationIdentities: Set<String> =
        assetSemanticsAuthorityCriterionRegistrationIdentities.union(assuranceFields)
    static let allProjectionAssuranceRegistrationIdentities: Set<String> =
        allProjectionRegistrationIdentities.union(assuranceFields)

    static let assuranceFunctionalRelationshipRegistrationIdentities: Set<String> =
        assuranceRegistrationIdentities.union(functionalRelationshipFields)
    static let accountabilityAssuranceFunctionalRelationshipRegistrationIdentities: Set<String> =
        accountabilityAssuranceRegistrationIdentities.union(functionalRelationshipFields)
    static let assetSemanticsAssuranceFunctionalRelationshipRegistrationIdentities: Set<String> =
        assetSemanticsAssuranceRegistrationIdentities.union(functionalRelationshipFields)
    static let accountabilityAssetSemanticsAssuranceFunctionalRelationshipRegistrationIdentities: Set<String> =
        accountabilityAssetSemanticsAssuranceRegistrationIdentities.union(functionalRelationshipFields)
    static let authorityCriterionAssuranceFunctionalRelationshipRegistrationIdentities: Set<String> =
        authorityCriterionAssuranceRegistrationIdentities.union(functionalRelationshipFields)
    static let accountabilityAuthorityCriterionAssuranceFunctionalRelationshipRegistrationIdentities: Set<String> =
        accountabilityAuthorityCriterionAssuranceRegistrationIdentities.union(functionalRelationshipFields)
    static let assetSemanticsAuthorityCriterionAssuranceFunctionalRelationshipRegistrationIdentities: Set<String> =
        assetSemanticsAuthorityCriterionAssuranceRegistrationIdentities.union(functionalRelationshipFields)
    static let allProjectionAssuranceFunctionalRelationshipRegistrationIdentities: Set<String> =
        allProjectionAssuranceRegistrationIdentities.union(functionalRelationshipFields)

    static let inspectionReviewRegistrationIdentities: Set<String> =
        allProjectionAssuranceFunctionalRelationshipRegistrationIdentities.union(inspectionReviewFields)

    static let workPacketRegistrationIdentities: Set<String> =
        inspectionReviewRegistrationIdentities.union(workPacketFields)

    private static let authorityCriterionFields: Set<String> = [
        "authority_source:WORK", "applicability_disposition:WORK",
        "criterion_result:WORK", "severity_level:WORK", "measurement_protocol:WORK",
    ]

    private static let functionalRelationshipFields: Set<String> = [
        "functional_relationship_descriptor:ASSET",
        "functional_relationship_direction:ASSET",
        "functional_relationship_state:ASSET",
        "functional_relationship_endpoint:ASSET",
    ]

    private static let assuranceFields: Set<String> = [
        "assurance_audience:REPORT",
        "assurance_disposition:REPORT",
        "assurance_limitation:REPORT",
        "assurance_projection_version:REPORT",
    ]

    private static let inspectionReviewFields: Set<String> = [
        "inspection_review_state:REPORT",
        "inspection_review_disposition:REPORT",
        "change_request_state:REPORT",
        "corrective_action_state:REPORT",
        "inspection_review_projection_version:REPORT",
    ]

    private static let workPacketFields: Set<String> = [
        "work_packet_identifier:WORK",
        "work_packet_manifest_state:WORK",
        "work_packet_item_state:WORK",
        "work_packet_conflict_state:WORK",
        "work_packet_projection_version:WORK",
    ]

    func descriptor(fieldID: String, sourceKind: SearchSourceKindV1) throws -> SearchableFieldDescriptorV1 {
        guard let value = fields.first(where: { $0.fieldID == fieldID && $0.sourceKind == sourceKind }) else {
            throw SearchContractFailureV1.forbiddenField
        }
        return value
    }
}

enum SearchFilterKindV1: String, CaseIterable, Codable, Hashable, Sendable {
    case incomplete = "INCOMPLETE"
    case recheckDue = "RECHECK_DUE"
    case reportFailed = "REPORT_FAILED"
    case backupStale = "BACKUP_STALE"
}

struct SearchFilterV1: Codable, Equatable, Hashable, Comparable, Sendable {
    let kind: SearchFilterKindV1
    let canonicalValue: String

    init(kind: SearchFilterKindV1, canonicalValue: String = "true") throws {
        self.kind = kind
        self.canonicalValue = canonicalValue
        guard canonicalValue == "true" else { throw SearchContractFailureV1.invalidFilter }
    }

    func validate() throws {
        guard canonicalValue == "true" else { throw SearchContractFailureV1.invalidFilter }
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.kind.rawValue < rhs.kind.rawValue }
}

enum SearchSortV1: String, CaseIterable, Codable, Hashable, Sendable {
    case deterministicRelevance = "DETERMINISTIC_RELEVANCE"
    case mostRecent = "MOST_RECENT"
    case oldestFirst = "OLDEST_FIRST"
    case statusThenStableID = "STATUS_THEN_STABLE_ID"
    case dueDateThenStableID = "DUE_DATE_THEN_STABLE_ID"
}

struct SearchQueryPlanV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let query: String
    let normalizedTokens: [String]
    let scope: SearchScopeV1
    let filters: [SearchFilterV1]
    let sort: SearchSortV1
    let maximumResults: Int
    let sourceRevision: UInt64
    let permitsTypoSuggestions: Bool

    init(
        query: String,
        normalizedTokens: [String],
        scope: SearchScopeV1 = .all,
        filters: [SearchFilterV1] = [],
        sort: SearchSortV1 = .deterministicRelevance,
        maximumResults: Int = 100,
        sourceRevision: UInt64,
        permitsTypoSuggestions: Bool = true
    ) throws {
        schemaVersion = Self.schemaVersion
        self.query = query
        self.normalizedTokens = normalizedTokens
        self.scope = scope
        self.filters = filters.sorted()
        self.sort = sort
        self.maximumResults = maximumResults
        self.sourceRevision = sourceRevision
        self.permitsTypoSuggestions = permitsTypoSuggestions
        try validate()
    }

    func validate() throws {
        let hasExecutableCriterion = !query.isEmpty || !filters.isEmpty || sort == .mostRecent
        guard schemaVersion == Self.schemaVersion, hasExecutableCriterion,
              SearchContractValidationV1.validDisplayText(
                query,
                maximumBytes: SearchContractLimitsV1.maximumQueryBytes,
                allowEmpty: true
              ),
              query.isEmpty == normalizedTokens.isEmpty,
              SearchContractValidationV1.normalizedTokensAreCanonical(normalizedTokens),
              filters.count <= SearchContractLimitsV1.maximumFilters,
              Set(filters).count == filters.count,
              (1...500).contains(maximumResults) else {
            throw SearchContractFailureV1.invalidQuery
        }
        try filters.forEach { try $0.validate() }
    }
}

enum SearchMatchTierV1: Int, CaseIterable, Codable, Comparable, Hashable, Sendable {
    case exactStableOrDisplayIdentity = 0
    case normalizedExactToken = 1
    case prefix = 2
    case tokenPrefix = 3
    case substring = 4

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct SearchRankingKeyV1: Codable, Equatable, Comparable, Sendable {
    let tier: SearchMatchTierV1
    let stableID: String
    let timestamp: Date

    init(tier: SearchMatchTierV1, stableID: String, timestamp: Date) throws {
        guard SearchContractValidationV1.validID(stableID), SearchContractValidationV1.validDate(timestamp) else {
            throw SearchContractFailureV1.invalidRanking
        }
        self.tier = tier
        self.stableID = stableID
        self.timestamp = timestamp
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.tier != rhs.tier { return lhs.tier < rhs.tier }
        if lhs.stableID != rhs.stableID { return lhs.stableID < rhs.stableID }
        return lhs.timestamp < rhs.timestamp
    }
}

enum SearchSuggestionReasonV1: String, CaseIterable, Codable, Hashable, Sendable {
    case editDistanceOne = "EDIT_DISTANCE_ONE"
    case editDistanceTwo = "EDIT_DISTANCE_TWO"
}

struct SearchSuggestionV1: Codable, Equatable, Comparable, Sendable {
    let suggestedToken: String
    let editDistance: Int
    let reason: SearchSuggestionReasonV1
    let sourceStableID: String

    init(suggestedToken: String, editDistance: Int, sourceStableID: String) throws {
        self.suggestedToken = suggestedToken
        self.editDistance = editDistance
        self.reason = editDistance == 1 ? .editDistanceOne : .editDistanceTwo
        self.sourceStableID = sourceStableID
        try validate()
    }

    func validate() throws {
        guard SearchContractValidationV1.validDisplayText(
            suggestedToken,
            maximumBytes: SearchContractLimitsV1.maximumNormalizedTokenBytes
        ), SearchContractValidationV1.isCanonicalSearchToken(suggestedToken),
           SearchContractValidationV1.validID(sourceStableID),
           editDistance == 1 || editDistance == 2,
           reason == (editDistance == 1 ? .editDistanceOne : .editDistanceTwo) else {
            throw SearchContractFailureV1.invalidSuggestion
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.editDistance != rhs.editDistance { return lhs.editDistance < rhs.editDistance }
        if lhs.suggestedToken != rhs.suggestedToken { return lhs.suggestedToken < rhs.suggestedToken }
        return lhs.sourceStableID < rhs.sourceStableID
    }

    static func validatedSet(_ values: [Self]) throws -> [Self] {
        let sorted = values.sorted()
        guard sorted.count <= SearchContractLimitsV1.maximumSuggestions,
              Set(sorted.map(\.suggestedToken)).count == sorted.count else {
            throw SearchContractFailureV1.invalidSuggestion
        }
        try sorted.forEach { try $0.validate() }
        return sorted
    }
}

struct SearchResultContextV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let workspaceID: UUID
    let sourceKind: SearchSourceKindV1
    let stableID: String
    let displayIdentity: String
    let locationBreadcrumb: [String]
    let status: String
    let openWorkStableIDs: [String]
    let snippet: String?
    let dueAt: Date?
    let rankingKey: SearchRankingKeyV1
    let sourceRevision: UInt64
    let indexRevision: UInt64

    init(
        workspaceID: UUID,
        sourceKind: SearchSourceKindV1,
        stableID: String,
        displayIdentity: String,
        locationBreadcrumb: [String],
        status: String,
        openWorkStableIDs: [String] = [],
        snippet: String? = nil,
        dueAt: Date? = nil,
        rankingKey: SearchRankingKeyV1,
        sourceRevision: UInt64,
        indexRevision: UInt64
    ) throws {
        schemaVersion = Self.schemaVersion
        self.workspaceID = workspaceID
        self.sourceKind = sourceKind
        self.stableID = stableID
        self.displayIdentity = displayIdentity
        self.locationBreadcrumb = locationBreadcrumb
        self.status = status
        self.openWorkStableIDs = openWorkStableIDs.sorted()
        self.snippet = snippet
        self.dueAt = dueAt
        self.rankingKey = rankingKey
        self.sourceRevision = sourceRevision
        self.indexRevision = indexRevision
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion, workspaceID != SearchContractValidationV1.zeroUUID,
              SearchContractValidationV1.validID(stableID), rankingKey.stableID == stableID,
              SearchContractValidationV1.validDisplayText(displayIdentity, maximumBytes: 240),
              SearchContractValidationV1.validDisplayText(status, maximumBytes: 120),
              locationBreadcrumb.count <= SearchContractLimitsV1.maximumBreadcrumbComponents,
              locationBreadcrumb.allSatisfy({ SearchContractValidationV1.validDisplayText($0, maximumBytes: 160) }),
              Set(openWorkStableIDs).count == openWorkStableIDs.count,
              openWorkStableIDs.allSatisfy({ SearchContractValidationV1.validID($0) }),
              snippet.map({ SearchContractValidationV1.validDisplayText($0, maximumBytes: SearchContractLimitsV1.maximumSnippetBytes) }) ?? true,
              dueAt.map(SearchContractValidationV1.validDate) ?? true,
              indexRevision <= sourceRevision else {
            throw indexRevision > sourceRevision ? .indexAheadOfSource : .invalidContext
        }
    }
}

struct SearchScrollAnchorV1: Codable, Equatable, Sendable {
    let stableID: String
    let offset: Double
    init(stableID: String, offset: Double) throws {
        guard SearchContractValidationV1.validID(stableID), offset.isFinite else {
            throw SearchContractFailureV1.invalidSession
        }
        self.stableID = stableID
        self.offset = offset
    }
}

struct SearchSessionStateV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let query: String
    let scope: SearchScopeV1
    let filters: [SearchFilterV1]
    let selectedStableID: String?
    let scrollAnchor: SearchScrollAnchorV1?

    init(
        query: String,
        scope: SearchScopeV1,
        filters: [SearchFilterV1] = [],
        selectedStableID: String? = nil,
        scrollAnchor: SearchScrollAnchorV1? = nil
    ) throws {
        schemaVersion = Self.schemaVersion
        self.query = query
        self.scope = scope
        self.filters = filters.sorted()
        self.selectedStableID = selectedStableID
        self.scrollAnchor = scrollAnchor
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion, query.utf8.count <= SearchContractLimitsV1.maximumQueryBytes,
              !query.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              filters.count <= SearchContractLimitsV1.maximumFilters, Set(filters).count == filters.count,
              selectedStableID.map({ SearchContractValidationV1.validID($0) }) ?? true else {
            throw SearchContractFailureV1.invalidSession
        }
        try filters.forEach { try $0.validate() }
    }

    /// Detail/back navigation remains live and therefore retains the query.
    func liveNavigationState() -> Self { self }

    /// Scene/cold persistence never retains user-entered search text.
    func coldRestorationState(validStableIDs: Set<String>) throws -> Self {
        let selected = selectedStableID.flatMap { validStableIDs.contains($0) ? $0 : nil }
        let anchor = scrollAnchor.flatMap { validStableIDs.contains($0.stableID) ? $0 : nil }
        return try Self(query: "", scope: scope, filters: filters, selectedStableID: selected, scrollAnchor: anchor)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, scope, filters, selectedStableID, scrollAnchor
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw SearchContractFailureV1.unsupportedSchemaVersion
        }
        try self.init(
            query: "",
            scope: container.decode(SearchScopeV1.self, forKey: .scope),
            filters: container.decode([SearchFilterV1].self, forKey: .filters),
            selectedStableID: container.decodeIfPresent(String.self, forKey: .selectedStableID),
            scrollAnchor: container.decodeIfPresent(SearchScrollAnchorV1.self, forKey: .scrollAnchor)
        )
    }

    func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.schemaVersion, forKey: .schemaVersion)
        try container.encode(scope, forKey: .scope)
        try container.encode(filters, forKey: .filters)
        try container.encodeIfPresent(selectedStableID, forKey: .selectedStableID)
        try container.encodeIfPresent(scrollAnchor, forKey: .scrollAnchor)
    }
}

struct SearchSourceRevisionV1: Codable, Equatable, Hashable, Sendable {
    let workspaceID: UUID
    let generationID: UUID
    let commitRevision: UInt64
    init(workspaceID: UUID, generationID: UUID, commitRevision: UInt64) throws {
        guard workspaceID != SearchContractValidationV1.zeroUUID,
              generationID != SearchContractValidationV1.zeroUUID else {
            throw SearchContractFailureV1.invalidRevision
        }
        self.workspaceID = workspaceID
        self.generationID = generationID
        self.commitRevision = commitRevision
    }
}

struct SearchIndexRevisionV1: Codable, Equatable, Hashable, Sendable {
    let workspaceID: UUID
    let generationID: UUID
    let projectionFormatVersion: Int
    let indexedCommitRevision: UInt64
    init(workspaceID: UUID, generationID: UUID, projectionFormatVersion: Int = 1, indexedCommitRevision: UInt64) throws {
        guard workspaceID != SearchContractValidationV1.zeroUUID,
              generationID != SearchContractValidationV1.zeroUUID,
              projectionFormatVersion > 0 else { throw SearchContractFailureV1.invalidRevision }
        self.workspaceID = workspaceID
        self.generationID = generationID
        self.projectionFormatVersion = projectionFormatVersion
        self.indexedCommitRevision = indexedCommitRevision
    }
}

enum SearchIndexReconciliationV1: String, Codable, Equatable, Sendable {
    case current = "CURRENT"
    case staleDropAndRebuild = "STALE_DROP_AND_REBUILD"
    case aheadDropAndRebuild = "AHEAD_DROP_AND_REBUILD"
    case incompatibleFormatDropAndRebuild = "INCOMPATIBLE_FORMAT_DROP_AND_REBUILD"
    case wrongGenerationDropAndRebuild = "WRONG_GENERATION_DROP_AND_REBUILD"
    case absentBuild = "ABSENT_BUILD"

    static func disposition(source: SearchSourceRevisionV1, index: SearchIndexRevisionV1?) -> Self {
        guard let index else { return .absentBuild }
        guard index.workspaceID == source.workspaceID, index.generationID == source.generationID else {
            return .wrongGenerationDropAndRebuild
        }
        guard index.projectionFormatVersion == SearchPersistenceReleaseV1.derivedProjectionFormatVersion else {
            return .incompatibleFormatDropAndRebuild
        }
        if index.indexedCommitRevision < source.commitRevision { return .staleDropAndRebuild }
        if index.indexedCommitRevision > source.commitRevision { return .aheadDropAndRebuild }
        return .current
    }
}

struct SearchIndexProjectionRecordV1: Codable, Equatable, Comparable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let workspaceID: UUID
    let sourceKind: SearchSourceKindV1
    let sourceStableID: String
    let sourceRevision: UInt64
    let fieldID: String
    let normalizedTokens: [String]
    let displayIdentity: String
    let locationBreadcrumb: [String]
    let status: String
    let openWorkStableIDs: [String]
    let permittedSnippet: String?
    let dueAt: Date?
    let sourceTimestamp: Date

    init(
        workspaceID: UUID, sourceKind: SearchSourceKindV1, sourceStableID: String,
        sourceRevision: UInt64, fieldID: String, normalizedTokens: [String],
        displayIdentity: String, locationBreadcrumb: [String], status: String,
        openWorkStableIDs: [String] = [], permittedSnippet: String? = nil,
        dueAt: Date? = nil, sourceTimestamp: Date
    ) throws {
        schemaVersion = Self.schemaVersion; self.workspaceID = workspaceID; self.sourceKind = sourceKind
        self.sourceStableID = sourceStableID; self.sourceRevision = sourceRevision; self.fieldID = fieldID
        self.normalizedTokens = normalizedTokens; self.displayIdentity = displayIdentity
        self.locationBreadcrumb = locationBreadcrumb; self.status = status
        self.openWorkStableIDs = openWorkStableIDs.sorted(); self.permittedSnippet = permittedSnippet
        self.dueAt = dueAt
        self.sourceTimestamp = sourceTimestamp
        try validate()
    }

    var projectionIdentity: String { "\(sourceKind.rawValue):\(sourceStableID):\(fieldID)" }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion, workspaceID != SearchContractValidationV1.zeroUUID,
              SearchContractValidationV1.validID(sourceStableID), SearchContractValidationV1.validID(fieldID),
              normalizedTokens.count <= SearchContractLimitsV1.maximumProjectionTokens,
              !normalizedTokens.isEmpty,
              Set(normalizedTokens).count == normalizedTokens.count,
              normalizedTokens.allSatisfy(SearchContractValidationV1.isCanonicalSearchToken),
              SearchContractValidationV1.validDisplayText(displayIdentity, maximumBytes: 240),
              locationBreadcrumb.count <= SearchContractLimitsV1.maximumBreadcrumbComponents,
              locationBreadcrumb.allSatisfy({ SearchContractValidationV1.validDisplayText($0, maximumBytes: 160) }),
              SearchContractValidationV1.validDisplayText(status, maximumBytes: 120),
              Set(openWorkStableIDs).count == openWorkStableIDs.count,
              openWorkStableIDs.allSatisfy({ SearchContractValidationV1.validID($0) }),
              permittedSnippet.map({ SearchContractValidationV1.validDisplayText($0, maximumBytes: SearchContractLimitsV1.maximumSnippetBytes) }) ?? true,
              dueAt.map(SearchContractValidationV1.validDate) ?? true,
              SearchContractValidationV1.validDate(sourceTimestamp) else { throw SearchContractFailureV1.invalidField }
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.projectionIdentity < rhs.projectionIdentity }

    static func validateProjection(_ records: [Self], against registry: SearchableFieldRegistryV1) throws -> [Self] {
        guard records.count <= SearchContractLimitsV1.maximumProjectionRecords else { throw SearchContractFailureV1.limitExceeded }
        let sorted = records.sorted()
        guard Set(sorted.map(\.projectionIdentity)).count == sorted.count else { throw SearchContractFailureV1.duplicateProjection }
        for record in sorted {
            try record.validate()
            let field = try registry.descriptor(fieldID: record.fieldID, sourceKind: record.sourceKind)
            if record.permittedSnippet != nil && field.snippetPermission == .prohibited {
                throw SearchContractFailureV1.forbiddenField
            }
        }
        return sorted
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, workspaceID, sourceKind, sourceStableID, sourceRevision, fieldID
        case normalizedTokens, displayIdentity, locationBreadcrumb, status, openWorkStableIDs
        case permittedSnippet, dueAt, sourceTimestamp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw SearchContractFailureV1.unsupportedSchemaVersion
        }
        try self.init(
            workspaceID: container.decode(UUID.self, forKey: .workspaceID),
            sourceKind: container.decode(SearchSourceKindV1.self, forKey: .sourceKind),
            sourceStableID: container.decode(String.self, forKey: .sourceStableID),
            sourceRevision: container.decode(UInt64.self, forKey: .sourceRevision),
            fieldID: container.decode(String.self, forKey: .fieldID),
            normalizedTokens: container.decode([String].self, forKey: .normalizedTokens),
            displayIdentity: container.decode(String.self, forKey: .displayIdentity),
            locationBreadcrumb: container.decode([String].self, forKey: .locationBreadcrumb),
            status: container.decode(String.self, forKey: .status),
            openWorkStableIDs: container.decode([String].self, forKey: .openWorkStableIDs),
            permittedSnippet: container.decodeIfPresent(String.self, forKey: .permittedSnippet),
            dueAt: container.decodeIfPresent(Date.self, forKey: .dueAt),
            sourceTimestamp: container.decode(Date.self, forKey: .sourceTimestamp)
        )
    }
}

enum SearchIndexBuildStateV1: String, CaseIterable, Codable, Hashable, Sendable {
    case building = "BUILDING"
    case complete = "COMPLETE"
}

struct SearchIndexRebuildCheckpointV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let operationID: UUID
    let source: SearchSourceRevisionV1
    let projectionFormatVersion: Int
    let nextCanonicalOffset: Int
    let projectedRecordCount: Int
    let state: SearchIndexBuildStateV1

    init(
        operationID: UUID,
        source: SearchSourceRevisionV1,
        projectionFormatVersion: Int = SearchPersistenceReleaseV1.derivedProjectionFormatVersion,
        nextCanonicalOffset: Int,
        projectedRecordCount: Int,
        state: SearchIndexBuildStateV1
    ) throws {
        schemaVersion = Self.schemaVersion
        self.operationID = operationID
        self.source = source
        self.projectionFormatVersion = projectionFormatVersion
        self.nextCanonicalOffset = nextCanonicalOffset
        self.projectedRecordCount = projectedRecordCount
        self.state = state
        try validate()
    }

    func validate() throws {
        guard operationID != SearchContractValidationV1.zeroUUID,
              source.workspaceID != SearchContractValidationV1.zeroUUID,
              source.generationID != SearchContractValidationV1.zeroUUID,
              projectionFormatVersion == SearchPersistenceReleaseV1.derivedProjectionFormatVersion,
              nextCanonicalOffset >= 0,
              projectedRecordCount >= 0,
              projectedRecordCount <= SearchContractLimitsV1.maximumProjectionRecords else {
            throw SearchContractFailureV1.invalidRevision
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, operationID, source, projectionFormatVersion
        case nextCanonicalOffset, projectedRecordCount, state
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw SearchContractFailureV1.unsupportedSchemaVersion
        }
        try self.init(
            operationID: container.decode(UUID.self, forKey: .operationID),
            source: container.decode(SearchSourceRevisionV1.self, forKey: .source),
            projectionFormatVersion: container.decode(Int.self, forKey: .projectionFormatVersion),
            nextCanonicalOffset: container.decode(Int.self, forKey: .nextCanonicalOffset),
            projectedRecordCount: container.decode(Int.self, forKey: .projectedRecordCount),
            state: container.decode(SearchIndexBuildStateV1.self, forKey: .state)
        )
    }
}

/// A disposable, source-revision-bound snapshot. It contains no canonical
/// writer state and is never admitted to the SwiftData schema or backups.
struct SearchIndexProjectionV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let source: SearchSourceRevisionV1
    let index: SearchIndexRevisionV1
    let records: [SearchIndexProjectionRecordV1]

    init(
        source: SearchSourceRevisionV1,
        index: SearchIndexRevisionV1,
        records: [SearchIndexProjectionRecordV1],
        registry: SearchableFieldRegistryV1
    ) throws {
        schemaVersion = Self.schemaVersion
        self.source = source
        self.index = index
        self.records = try SearchIndexProjectionRecordV1.validateProjection(records, against: registry)
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              source.workspaceID != SearchContractValidationV1.zeroUUID,
              source.generationID != SearchContractValidationV1.zeroUUID,
              source.workspaceID == index.workspaceID,
              source.generationID == index.generationID,
              index.projectionFormatVersion == SearchPersistenceReleaseV1.derivedProjectionFormatVersion,
              index.indexedCommitRevision == source.commitRevision,
              records.count <= SearchContractLimitsV1.maximumProjectionRecords,
              records == records.sorted(),
              Set(records.map(\.projectionIdentity)).count == records.count,
              records.allSatisfy({
                  $0.workspaceID == source.workspaceID && $0.sourceRevision <= source.commitRevision
              }) else {
            throw index.indexedCommitRevision > source.commitRevision
                ? .indexAheadOfSource : .staleIndex
        }
        try records.forEach { try $0.validate() }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, source, index, records
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        source = try container.decode(SearchSourceRevisionV1.self, forKey: .source)
        index = try container.decode(SearchIndexRevisionV1.self, forKey: .index)
        records = try container.decode([SearchIndexProjectionRecordV1].self, forKey: .records)
        try validate()
    }
}

enum BuiltInSmartViewV1: String, CaseIterable, Codable, Hashable, Sendable {
    case recent = "RECENT"
    case incomplete = "INCOMPLETE"
    case recheckDue = "RECHECK_DUE"
    case reportFailed = "REPORT_FAILED"
    case backupStale = "BACKUP_STALE"

    var stableID: String { "builtin.search.\(rawValue.lowercased())" }
}

struct BuiltInSmartViewDefinitionV1: Codable, Equatable, Sendable {
    let kind: BuiltInSmartViewV1
    let stableID: String
    let nameLocalizationKey: String
    let scope: SearchScopeV1
    let filters: [SearchFilterV1]
    let sort: SearchSortV1

    init(kind: BuiltInSmartViewV1) throws {
        self.kind = kind
        stableID = kind.stableID
        nameLocalizationKey = "search.smartView.\(kind.rawValue.lowercased()).name"
        switch kind {
        case .recent:
            scope = .all; filters = []; sort = .mostRecent
        case .incomplete:
            scope = .work; filters = [try SearchFilterV1(kind: .incomplete)]; sort = .statusThenStableID
        case .recheckDue:
            scope = .work; filters = [try SearchFilterV1(kind: .recheckDue)]; sort = .dueDateThenStableID
        case .reportFailed:
            scope = .reports; filters = [try SearchFilterV1(kind: .reportFailed)]; sort = .mostRecent
        case .backupStale:
            scope = .all; filters = [try SearchFilterV1(kind: .backupStale)]; sort = .mostRecent
        }
    }

    static func catalog() throws -> [Self] { try BuiltInSmartViewV1.allCases.map { try Self(kind: $0) } }
}

enum SmartViewOriginV1: String, CaseIterable, Codable, Hashable, Sendable {
    case builtIn = "BUILT_IN"
    case userSaved = "USER_SAVED"
}

struct SavedSmartViewDescriptorV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let id: UUID
    let workspaceID: UUID
    let stableID: String
    let origin: SmartViewOriginV1
    let builtInKind: BuiltInSmartViewV1?
    let name: String
    let query: String
    let scope: SearchScopeV1
    let filters: [SearchFilterV1]
    let sort: SearchSortV1
    let revision: UInt64
    let mutationID: UUID
    let createdAt: Date
    let updatedAt: Date

    init(
        id: UUID, workspaceID: UUID, stableID: String, origin: SmartViewOriginV1,
        builtInKind: BuiltInSmartViewV1? = nil, name: String, query: String,
        scope: SearchScopeV1, filters: [SearchFilterV1] = [], sort: SearchSortV1,
        revision: UInt64, mutationID: UUID, createdAt: Date, updatedAt: Date
    ) throws {
        schemaVersion = Self.schemaVersion; self.id = id; self.workspaceID = workspaceID; self.stableID = stableID
        self.origin = origin; self.builtInKind = builtInKind; self.name = name; self.query = query
        self.scope = scope; self.filters = filters.sorted(); self.sort = sort; self.revision = revision
        self.mutationID = mutationID; self.createdAt = createdAt; self.updatedAt = updatedAt
        try validate()
    }

    func validate() throws {
        let hasUserExecutableCriterion = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !filters.isEmpty
            || sort == .mostRecent
        guard schemaVersion == Self.schemaVersion, id != SearchContractValidationV1.zeroUUID,
              workspaceID != SearchContractValidationV1.zeroUUID, mutationID != SearchContractValidationV1.zeroUUID,
              SearchContractValidationV1.validID(stableID),
              SearchContractValidationV1.validDisplayText(name, maximumBytes: SearchContractLimitsV1.maximumSavedViewNameBytes),
              query.utf8.count <= SearchContractLimitsV1.maximumQueryBytes,
              !query.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              filters.count <= SearchContractLimitsV1.maximumFilters, Set(filters).count == filters.count,
              revision > 0, SearchContractValidationV1.validDate(createdAt),
              SearchContractValidationV1.validDate(updatedAt), updatedAt >= createdAt else {
            throw SearchContractFailureV1.invalidSmartView
        }
        try filters.forEach { try $0.validate() }
        switch origin {
        case .builtIn:
            guard let builtInKind else { throw SearchContractFailureV1.invalidSmartView }
            let definition = try BuiltInSmartViewDefinitionV1(kind: builtInKind)
            guard stableID == definition.stableID,
                  query.isEmpty,
                  scope == definition.scope,
                  filters == definition.filters,
                  sort == definition.sort else {
                throw SearchContractFailureV1.invalidSmartView
            }
        case .userSaved:
            guard builtInKind == nil,
                  !stableID.hasPrefix("builtin.search."),
                  hasUserExecutableCriterion else {
                throw SearchContractFailureV1.invalidSmartView
            }
        }
    }

    func replacingUserDefinition(
        name: String, query: String, scope: SearchScopeV1, filters: [SearchFilterV1],
        sort: SearchSortV1, mutationID: UUID, updatedAt: Date
    ) throws -> Self {
        guard origin == .userSaved else { throw SearchContractFailureV1.builtInViewMutation }
        guard revision < UInt64.max else { throw SearchContractFailureV1.invalidRevision }
        let (nextRevision, overflowed) = revision.addingReportingOverflow(1)
        guard !overflowed else { throw SearchContractFailureV1.invalidRevision }
        return try Self(id: id, workspaceID: workspaceID, stableID: stableID, origin: origin,
                        name: name, query: query, scope: scope, filters: filters, sort: sort,
                        revision: nextRevision, mutationID: mutationID, createdAt: createdAt, updatedAt: updatedAt)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, id, workspaceID, stableID, origin, builtInKind, name, query
        case scope, filters, sort, revision, mutationID, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw SearchContractFailureV1.unsupportedSchemaVersion
        }
        try self.init(
            id: container.decode(UUID.self, forKey: .id),
            workspaceID: container.decode(UUID.self, forKey: .workspaceID),
            stableID: container.decode(String.self, forKey: .stableID),
            origin: container.decode(SmartViewOriginV1.self, forKey: .origin),
            builtInKind: container.decodeIfPresent(BuiltInSmartViewV1.self, forKey: .builtInKind),
            name: container.decode(String.self, forKey: .name),
            query: container.decode(String.self, forKey: .query),
            scope: container.decode(SearchScopeV1.self, forKey: .scope),
            filters: container.decode([SearchFilterV1].self, forKey: .filters),
            sort: container.decode(SearchSortV1.self, forKey: .sort),
            revision: container.decode(UInt64.self, forKey: .revision),
            mutationID: container.decode(UUID.self, forKey: .mutationID),
            createdAt: container.decode(Date.self, forKey: .createdAt),
            updatedAt: container.decode(Date.self, forKey: .updatedAt)
        )
    }
}

// C18 exposes package evolution to downstream consumers only as a bounded
// metadata projection.  Package bytes, draft payloads, actor snapshots, exact
// candidate heads, and receipt digests stay in the canonical lifecycle and are
// deliberately absent from this type.
enum PackageEvolutionConsumerFailureV1: Error, Equatable, Sendable {
    case invalidMetadata
    case incompleteSandbox
    case mismatchedRelease
    case forbiddenSensitiveMetadata
}

enum PackageEvolutionConsumerStatusV1: String, Codable, CaseIterable, Sendable {
    case preview = "PREVIEW"
    case promoted = "PROMOTED"
    case rolledBack = "ROLLED_BACK"
    case forwardFixRequired = "FORWARD_FIX_REQUIRED"
    case void = "VOID"
}

struct PackageEvolutionConsumerMetadataV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let packageID: String
    let packageReleaseID: String
    let semanticClassification: PackageSemanticDiffClassificationV1
    let promotionStatus: PackageEvolutionConsumerStatusV1
    let sandboxDisposition: PackageSandboxDispositionV1
    let localizationReleaseSHA256: String?

    init(
        packageID: String,
        packageReleaseID: String,
        semanticClassification: PackageSemanticDiffClassificationV1,
        promotionStatus: PackageEvolutionConsumerStatusV1,
        sandboxDisposition: PackageSandboxDispositionV1,
        localizationReleaseSHA256: String? = nil
    ) throws {
        schemaVersion = Self.schemaVersion
        self.packageID = packageID
        self.packageReleaseID = packageReleaseID
        self.semanticClassification = semanticClassification
        self.promotionStatus = promotionStatus
        self.sandboxDisposition = sandboxDisposition
        self.localizationReleaseSHA256 = localizationReleaseSHA256
        try validate()
    }

    init(bundle: PackagePromotionAtomicBundleV1) throws {
        try bundle.validate()
        try self.init(
            packageID: bundle.promotedRelease.packageRelease.packageID,
            packageReleaseID: bundle.promotedRelease.packageRelease.packageReleaseID,
            semanticClassification: bundle.semanticDiff.classification,
            promotionStatus: .promoted,
            sandboxDisposition: bundle.sandboxRun.disposition,
            localizationReleaseSHA256: bundle.semanticDiff.target
                .semanticReleaseBindings.localizationReleaseSHA256
        )
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              InspectionPackageValidationV2.validIdentifier(packageID, maximumBytes: 200),
              KernelCanonicalHashV1.validSHA256(packageReleaseID),
              localizationReleaseSHA256.map(KernelCanonicalHashV1.validSHA256) ?? true else {
            throw PackageEvolutionConsumerFailureV1.invalidMetadata
        }
    }
}

enum PackageEvolutionSearchFieldV1: String, CaseIterable, Codable, Hashable, Sendable {
    case packageID = "package_id"
    case packageReleaseID = "package_release_id"
    case semanticClassification = "package_semantic_classification"
    case promotionStatus = "package_promotion_status"
}

struct PackageEvolutionSearchRecordV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let packageID: String
    let packageReleaseID: String
    let semanticClassification: PackageSemanticDiffClassificationV1
    let promotionStatus: PackageEvolutionConsumerStatusV1

    init(metadata: PackageEvolutionConsumerMetadataV1) throws {
        try metadata.validate()
        schemaVersion = Self.schemaVersion
        packageID = metadata.packageID
        packageReleaseID = metadata.packageReleaseID
        semanticClassification = metadata.semanticClassification
        promotionStatus = metadata.promotionStatus
        try validate()
    }

    var boundedFieldValues: [PackageEvolutionSearchFieldV1: String] {
        [
            .packageID: packageID,
            .packageReleaseID: packageReleaseID,
            .semanticClassification: semanticClassification.rawValue,
            .promotionStatus: promotionStatus.rawValue,
        ]
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              InspectionPackageValidationV2.validIdentifier(packageID, maximumBytes: 200),
              KernelCanonicalHashV1.validSHA256(packageReleaseID),
              boundedFieldValues.count == PackageEvolutionSearchFieldV1.allCases.count else {
            throw PackageEvolutionConsumerFailureV1.invalidMetadata
        }
    }
}

enum PackageEvolutionSearchProjectionPolicyV1 {
    static let sourceKind = "PACKAGE_EVOLUTION"
    static let semanticLabel = "PACKAGE_EVOLUTION_SEARCH_METADATA_V1"
    static let fieldIDs = PackageEvolutionSearchFieldV1.allCases.map(\.rawValue)
    static let derivedOnly = true
    static let dropAndRebuildAfterRestore = true
    static let dropAndRebuildOnReplay = true
    static let excludesCanonicalPackageBytes = true
    static let excludesDraftPayload = true
    static let excludesActorIdentity = true
    static let excludesExactCandidateHead = true

    static func accepts(_ field: PackageEvolutionSearchFieldV1) -> Bool {
        fieldIDs.contains(field.rawValue)
    }
}

/// C19 search is deliberately metadata-only. It exposes stable identifiers,
/// release identity, typed classification/state, and no exact measurement
/// values, opaque serials, operator data, response payloads, or evidence.
enum MeasurementIntegritySearchFieldV1: String, CaseIterable, Codable, Hashable, Sendable {
    case captureIdentifier = "measurement_capture_identifier"
    case packageReleaseIdentifier = "measurement_package_release_identifier"
    case enteredUnitIdentifier = "measurement_entered_unit_identifier"
    case canonicalUnitIdentifier = "measurement_canonical_unit_identifier"
    case dimension = "measurement_dimension"
    case sourceMode = "measurement_source_mode"
    case instrumentIdentifier = "measurement_instrument_identifier"
    case calibrationStatus = "measurement_calibration_status"
    case calibrationBasis = "measurement_calibration_basis"
    case seriesIdentifier = "measurement_series_identifier"
    case seriesState = "measurement_series_state"
    case qualityResult = "measurement_quality_result"
    case qualityReason = "measurement_quality_reason"
}

struct MeasurementIntegritySearchRecordV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let workspaceID: UUID
    let captureID: UUID
    let sourceRevision: UInt64
    let boundedFieldValues: [MeasurementIntegritySearchFieldV1: String]

    init(
        projection: MeasurementIntegrityReportProjectionV1,
        sourceRevision: UInt64 = 0
    ) throws {
        try projection.validate()
        schemaVersion = Self.schemaVersion
        workspaceID = projection.workspaceID.rawValue
        captureID = projection.captureID
        self.sourceRevision = sourceRevision
        var values: [MeasurementIntegritySearchFieldV1: String] = [
            .captureIdentifier: projection.captureID.uuidString.lowercased(),
            .packageReleaseIdentifier: projection.packageReleaseID,
            .enteredUnitIdentifier: projection.enteredUnitID,
            .canonicalUnitIdentifier: projection.canonicalUnitID,
            .dimension: projection.dimension.rawValue,
            .sourceMode: projection.sourceMode.rawValue,
        ]
        if let instrumentID = projection.instrumentID {
            values[.instrumentIdentifier] = instrumentID.uuidString.lowercased()
        }
        if let status = projection.calibrationStatus {
            values[.calibrationStatus] = status.rawValue
        }
        if let basis = projection.calibrationBasis {
            values[.calibrationBasis] = basis.rawValue
        }
        if let seriesID = projection.seriesID {
            values[.seriesIdentifier] = seriesID.uuidString.lowercased()
        }
        if let state = projection.seriesState {
            values[.seriesState] = state.rawValue
        }
        if let result = projection.qualityResult {
            values[.qualityResult] = result.rawValue
        }
        if !projection.qualityReasonCodes.isEmpty {
            values[.qualityReason] = projection.qualityReasonCodes.map(\.rawValue).joined(separator: ",")
        }
        boundedFieldValues = values
        try validate()
    }

    var displayIdentity: String {
        "measurement:\(captureID.uuidString.lowercased())"
    }

    func normalizedTokens(for field: MeasurementIntegritySearchFieldV1) -> [String] {
        guard let value = boundedFieldValues[field] else { return [] }
        return SearchContractValidationV1.normalizeSearchText(value)
            .unicodeScalars
            .split { !CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              workspaceID.rawValue != SearchContractValidationV1.zeroUUID,
              captureID != SearchContractValidationV1.zeroUUID,
              boundedFieldValues.keys.allSatisfy(MeasurementIntegritySearchProjectionPolicyV1.accepts),
              boundedFieldValues.keys.contains(.captureIdentifier),
              boundedFieldValues.keys.contains(.packageReleaseIdentifier),
              boundedFieldValues.keys.contains(.canonicalUnitIdentifier),
              boundedFieldValues.values.allSatisfy({
                  SearchContractValidationV1.validID($0)
              }),
              !MeasurementIntegrityLocalizationPolicyV1.containsProhibitedClaim(
                  in: Array(boundedFieldValues.values)
              ),
              !MeasurementIntegrityLocalizationPolicyV1.containsCustomerOrWorkDataLeakage(
                  in: Array(boundedFieldValues.values)
              ) else {
            throw SearchContractFailureV1.forbiddenField
        }
        guard boundedFieldValues.allSatisfy({ _, value in
            let tokens = SearchContractValidationV1.normalizeSearchText(value)
                .unicodeScalars
                .split { !CharacterSet.alphanumerics.contains($0) }
                .map(String.init)
            return !tokens.isEmpty && tokens.allSatisfy(SearchContractValidationV1.isCanonicalSearchToken)
        }) else {
            throw SearchContractFailureV1.invalidField
        }
    }
}

enum MeasurementIntegritySearchProjectionPolicyV1 {
    static let sourceKind = "MEASUREMENT_INTEGRITY"
    static let semanticLabel = "MEASUREMENT_INTEGRITY_SEARCH_METADATA_V1"
    static let fieldIDs = MeasurementIntegritySearchFieldV1.allCases.map(\.rawValue)
    static let derivedOnly = true
    static let metadataOnly = true
    static let dropAndRebuildAfterRestore = true
    static let dropAndRebuildOnReplay = true
    static let excludesExactCanonicalValues = true
    static let excludesOpaqueSerials = true
    static let excludesOperatorIdentity = true
    static let excludesResponsePayload = true
    static let excludesEvidenceLocators = true
    static let excludesLocalizedUnitIdentity = true

    static func accepts(_ field: MeasurementIntegritySearchFieldV1) -> Bool {
        fieldIDs.contains(field.rawValue)
    }
}

// MARK: - C20 approved-derivative search projection

/// Search metadata for C20 is deliberately narrower than the report
/// projection: it can identify an approved derivative and its policy/review
/// binding, but never indexes bytes, original references, reviewer identity,
/// or review rationale.
enum PrivacyTransformSearchFieldV1: String, CaseIterable, Codable, Hashable, Sendable {
    case manifestIdentifier = "privacy_transform_manifest_identifier"
    case derivativeContentIdentifier = "privacy_transform_derivative_content_identifier"
    case derivativeDigest = "privacy_transform_derivative_digest"
    case policyIdentifier = "privacy_transform_policy_identifier"
    case policyRevision = "privacy_transform_policy_revision"
    case reviewReceiptIdentifier = "privacy_transform_review_receipt_identifier"
    case reviewState = "privacy_transform_review_state"
    case audience = "privacy_transform_audience"
    case regionCount = "privacy_transform_region_count"
    case redactionDeclaration = "privacy_transform_redaction_declaration"
    case thumbnailEligibility = "privacy_transform_thumbnail_eligibility"
}

struct PrivacyTransformSearchRecordV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let workspaceID: UUID
    let manifestID: UUID
    let derivativeContentID: String
    let derivativeSHA256: String
    let policyID: UUID
    let policyRevision: UInt64
    let reviewReceiptID: UUID
    let sourceRevision: UInt64
    let boundedFieldValues: [PrivacyTransformSearchFieldV1: String]
    let thumbnailEligible: Bool

    init(
        projection: PrivacyTransformReportProjectionV1
    ) throws {
        try projection.validate()
        schemaVersion = Self.schemaVersion
        workspaceID = projection.workspaceID.rawValue
        manifestID = projection.manifestID
        derivativeContentID = projection.derivativeContentID
        derivativeSHA256 = projection.derivativeSHA256
        policyID = projection.policyID
        policyRevision = projection.policyRevision
        reviewReceiptID = projection.reviewReceiptID
        sourceRevision = projection.sourceRevision
        thumbnailEligible = projection.isAudienceSafe
        boundedFieldValues = [
            .manifestIdentifier: projection.manifestID.uuidString.lowercased(),
            .derivativeContentIdentifier: projection.derivativeContentID,
            .derivativeDigest: projection.derivativeSHA256,
            .policyIdentifier: projection.policyID.uuidString.lowercased(),
            .policyRevision: String(projection.policyRevision),
            .reviewReceiptIdentifier: projection.reviewReceiptID.uuidString.lowercased(),
            .reviewState: projection.reviewDecision.rawValue,
            .audience: projection.audience.rawValue,
            .regionCount: String(projection.regionCount),
            .redactionDeclaration: projection.redactionDeclared ? "RECORDED" : "NOT_RECORDED",
            .thumbnailEligibility: projection.isAudienceSafe ? "ELIGIBLE" : "DENIED",
        ]
        try validate()
    }

    var displayIdentity: String {
        "privacy-transform:\(manifestID.uuidString.lowercased())"
    }

    func normalizedTokens(
        for field: PrivacyTransformSearchFieldV1
    ) -> [String] {
        guard let value = boundedFieldValues[field] else { return [] }
        return SearchContractValidationV1.normalizeSearchText(value)
            .unicodeScalars
            .split { !CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
    }

    func validate() throws {
        let required = Set(PrivacyTransformSearchFieldV1.allCases)
        guard schemaVersion == Self.schemaVersion,
              workspaceID != SearchContractValidationV1.zeroUUID,
              manifestID != SearchContractValidationV1.zeroUUID,
              SearchContractValidationV1.validID(derivativeContentID),
              KernelCanonicalHashV1.validSHA256(derivativeSHA256),
              policyID != SearchContractValidationV1.zeroUUID,
              policyRevision > 0,
              reviewReceiptID != SearchContractValidationV1.zeroUUID,
              sourceRevision > 0,
              thumbnailEligible,
              Set(boundedFieldValues.keys) == required,
              boundedFieldValues.values.allSatisfy({
                  SearchContractValidationV1.validID($0)
              }),
              !PrivacyTransformLocalizationPolicyV1.containsProhibitedClaim(
                  in: Array(boundedFieldValues.values)
              ),
              !PrivacyTransformLocalizationPolicyV1.containsCustomerOrWorkDataLeakage(
                  in: Array(boundedFieldValues.values)
              ) else {
            throw SearchContractFailureV1.forbiddenField
        }
    }
}

enum PrivacyTransformSearchProjectionPolicyV1 {
    static let sourceKind = "PRIVACY_TRANSFORM"
    static let semanticLabel = "PRIVACY_TRANSFORM_APPROVED_DERIVATIVE_METADATA_V1"
    static let fieldIDs = PrivacyTransformSearchFieldV1.allCases.map(\.rawValue)
    static let derivedOnly = true
    static let metadataOnly = true
    static let approvedNonStaleOnly = true
    static let requiresMatchingSourceAndDerivativeDigest = true
    static let requiresExplicitRedactionDeclaration = true
    static let dropAndRebuildAfterRestore = true
    static let dropAndRebuildOnReplay = true
    static let excludesOriginalReferences = true
    static let excludesOriginalBytes = true
    static let excludesDerivativeBytes = true
    static let excludesReviewerIdentity = true
    static let excludesReviewRationale = true

    static func accepts(_ field: PrivacyTransformSearchFieldV1) -> Bool {
        fieldIDs.contains(field.rawValue)
    }
}

// MARK: - C21 client capability and package lifecycle search projection

/// Search values are bounded local metadata. Closed enum values are indexed
/// for diagnostics and filtering, while package payloads and client identity
/// remain outside the disposable index.
enum ClientCapabilitySearchFieldV1: String, CaseIterable, Codable, Hashable, Sendable {
    case decisionIdentifier = "client_capability_decision_identifier"
    case profileIdentifier = "client_capability_profile_identifier"
    case policyIdentifier = "client_capability_policy_identifier"
    case dispositionIdentifier = "client_capability_disposition_identifier"
    case packageReleaseIdentifier = "client_capability_package_release_identifier"
    case packageDigest = "client_capability_package_digest"
    case workflowDigest = "client_capability_workflow_digest"
    case admission = "client_capability_admission"
    case lifecycleState = "client_capability_lifecycle_state"
    case operation = "client_capability_operation"
    case reasonCodes = "client_capability_reason_codes"
    case readAllowed = "client_capability_read_allowed"
    case writeAllowed = "client_capability_write_allowed"
    case historicExportAllowed = "client_capability_historic_export_allowed"
}

struct ClientCapabilitySearchRecordV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let workspaceID: UUID
    let decisionID: UUID
    let profileID: UUID
    let policyID: UUID
    let dispositionID: UUID
    let packageReleaseID: String
    let packageSHA256: String
    let workflowSHA256: String
    let admission: ClientAdmissionV1
    let lifecycleState: PackageLifecycleStateV1
    let operation: PackageLifecycleOperationV1
    let reasonCodes: [ClientCapabilityReasonV1]
    let readAllowed: Bool
    let writeAllowed: Bool
    let historicExportAllowed: Bool
    let boundedFieldValues: [ClientCapabilitySearchFieldV1: String]

    init(projection: ClientCapabilityReportProjectionV1) throws {
        try projection.validate()
        schemaVersion = Self.schemaVersion
        workspaceID = projection.workspaceID.rawValue
        decisionID = projection.decisionID
        profileID = projection.profileID
        policyID = projection.policyID
        dispositionID = projection.dispositionID
        packageReleaseID = projection.packageReleaseID
        packageSHA256 = projection.packageSHA256
        workflowSHA256 = projection.workflowSHA256
        admission = projection.admission
        lifecycleState = projection.lifecycleState
        operation = projection.operation
        reasonCodes = projection.reasons
        readAllowed = projection.readAllowed
        writeAllowed = projection.writeAllowed
        historicExportAllowed = projection.historicExportAllowed
        boundedFieldValues = [
            .decisionIdentifier: projection.decisionID.uuidString.lowercased(),
            .profileIdentifier: projection.profileID.uuidString.lowercased(),
            .policyIdentifier: projection.policyID.uuidString.lowercased(),
            .dispositionIdentifier: projection.dispositionID.uuidString.lowercased(),
            .packageReleaseIdentifier: projection.packageReleaseID,
            .packageDigest: projection.packageSHA256,
            .workflowDigest: projection.workflowSHA256,
            .admission: projection.admission.rawValue,
            .lifecycleState: projection.lifecycleState.rawValue,
            .operation: projection.operation.rawValue,
            .reasonCodes: projection.reasons.map(\.rawValue).joined(separator: ","),
            .readAllowed: projection.readAllowed ? "ALLOWED" : "DENIED",
            .writeAllowed: projection.writeAllowed ? "ALLOWED" : "DENIED",
            .historicExportAllowed: projection.historicExportAllowed ? "ALLOWED" : "DENIED",
        ]
        try validate()
    }

    var displayIdentity: String {
        "client-capability:\(decisionID.uuidString.lowercased())"
    }

    func normalizedTokens(for field: ClientCapabilitySearchFieldV1) -> [String] {
        guard let value = boundedFieldValues[field] else { return [] }
        return SearchContractValidationV1.normalizeSearchText(value)
            .unicodeScalars
            .split { !CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
    }

    func validate() throws {
        let required = Set(ClientCapabilitySearchFieldV1.allCases)
        guard schemaVersion == Self.schemaVersion,
              workspaceID != SearchContractValidationV1.zeroUUID,
              decisionID != SearchContractValidationV1.zeroUUID,
              profileID != SearchContractValidationV1.zeroUUID,
              policyID != SearchContractValidationV1.zeroUUID,
              dispositionID != SearchContractValidationV1.zeroUUID,
              SearchContractValidationV1.validID(packageReleaseID),
              KernelCanonicalHashV1.validSHA256(packageSHA256),
              KernelCanonicalHashV1.validSHA256(workflowSHA256),
              !reasonCodes.isEmpty,
              reasonCodes == reasonCodes.sorted(by: { $0.rawValue < $1.rawValue }),
              Set(reasonCodes).count == reasonCodes.count,
              Set(boundedFieldValues.keys) == required,
              boundedFieldValues.values.allSatisfy({
                  SearchContractValidationV1.validID($0)
              }),
              !ClientCapabilityLocalizationPolicyV1.containsProhibitedClaim(
                  in: Array(boundedFieldValues.values)
              ),
              !ClientCapabilityLocalizationPolicyV1.containsCustomerOrWorkDataLeakage(
                  in: Array(boundedFieldValues.values)
              ) else {
            throw SearchContractFailureV1.forbiddenField
        }
        guard boundedFieldValues.allSatisfy({ _, value in
            let tokens = SearchContractValidationV1.normalizeSearchText(value)
                .unicodeScalars
                .split { !CharacterSet.alphanumerics.contains($0) }
                .map(String.init)
            return !tokens.isEmpty
                && tokens.allSatisfy(SearchContractValidationV1.isCanonicalSearchToken)
        }) else {
            throw SearchContractFailureV1.invalidField
        }
    }
}

enum ClientCapabilitySearchProjectionPolicyV1 {
    static let sourceKind = "CLIENT_CAPABILITY_PACKAGE_LIFECYCLE"
    static let semanticLabel = "CLIENT_CAPABILITY_PACKAGE_LIFECYCLE_METADATA_V1"
    static let fieldIDs = ClientCapabilitySearchFieldV1.allCases.map(\.rawValue)
    static let derivedOnly = true
    static let metadataOnly = true
    static let closedValuesOnly = true
    static let dropAndRebuildAfterRestore = true
    static let dropAndRebuildOnReplay = true
    static let excludesDeviceIdentity = true
    static let excludesUserIdentity = true
    static let excludesEndpointProviderAccount = true
    static let excludesRemoteDeliveryAcknowledgement = true
    static let excludesPackagePayload = true

    static func accepts(_ field: ClientCapabilitySearchFieldV1) -> Bool {
        fieldIDs.contains(field.rawValue)
    }
}

// MARK: - C24 accessible-document semantic search projection

/// Search receives a bounded, disposable summary of the customer-safe
/// semantic tree.  It never receives node text, node IDs, evidence IDs,
/// locators, original bytes, or assessor identity.
enum AccessibleDocumentSearchFieldV1: String, CaseIterable, Codable, Hashable, Sendable {
    case roleSummary = "ROLE_SUMMARY"
    case alternateTextProvenance = "ALTERNATE_TEXT_PROVENANCE"
    case decorativeState = "DECORATIVE_STATE"
    case assessmentState = "ASSESSMENT_STATE"
    case audience = "AUDIENCE"
    case projectionVersion = "PROJECTION_VERSION"
}

struct AccessibleDocumentSearchRecordV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let maximumValues = 10_000
    static let assessmentNotRecorded = "NOT_RECORDED"

    let schemaVersion: Int
    let treeSHA256: String
    let audience: ReportAudienceV1
    let projectionVersion: String
    let nodeCount: Int
    let figureCount: Int
    let decorativeFigureCount: Int
    let describedFigureCount: Int
    let missingAlternateTextFigureCount: Int
    let evidenceLinkCount: Int
    let roleValues: [AccessibleDocumentRoleV1]
    let alternateTextProvenances: [AccessibleAlternateTextProvenanceV1]
    let assessmentState: AccessibleDocumentAssessmentStateV1?
    let boundedFieldValues: [AccessibleDocumentSearchFieldV1: String]

    init(
        tree: AccessibleDocumentSemanticTreeV1,
        assessment: AccessibleDocumentAssessmentReceiptV1? = nil
    ) throws {
        try AccessibleDocumentPrivacyTransformBoundaryV1
            .validateAudienceSafeProjection(tree, assessment: assessment)
        guard tree.audience == .customerSafe,
              tree.nodes.allSatisfy({ $0.evidenceLinks.count <= Self.maximumValues }) else {
            throw SearchContractFailureV1.forbiddenField
        }
        let figures = tree.nodes.filter { $0.role == .figure }
        let described = figures.filter { !$0.decorative && $0.alternateText != nil }
        let missing = figures.filter {
            !$0.decorative && $0.alternateTextProvenance == .notProvided
        }
        let roles = Array(Set(tree.nodes.map(\.role))).sorted {
            $0.rawValue < $1.rawValue
        }
        let provenance = Array(Set(tree.nodes.compactMap(\.alternateTextProvenance))).sorted {
            $0.rawValue < $1.rawValue
        }
        let linkCount = tree.nodes.reduce(0) { $0 + $1.evidenceLinks.count }
        schemaVersion = Self.schemaVersion
        treeSHA256 = tree.treeSHA256
        audience = tree.audience
        projectionVersion = tree.projectionVersion
        nodeCount = tree.nodes.count
        figureCount = figures.count
        decorativeFigureCount = figures.filter { $0.decorative }.count
        describedFigureCount = described.count
        missingAlternateTextFigureCount = missing.count
        evidenceLinkCount = linkCount
        roleValues = roles
        alternateTextProvenances = provenance
        assessmentState = assessment?.state
        boundedFieldValues = [
            .roleSummary: roles.map(\.rawValue).joined(separator: ","),
            .alternateTextProvenance: provenance.isEmpty
                ? Self.assessmentNotRecorded
                : provenance.map(\.rawValue).joined(separator: ","),
            .decorativeState: decorativeFigureCount > 0
                ? "DECORATIVE_FIGURES_PRESENT" : "NO_DECORATIVE_FIGURES",
            .assessmentState: assessment?.state.rawValue ?? Self.assessmentNotRecorded,
            .audience: audience.rawValue,
            .projectionVersion: projectionVersion,
        ]
        try validate()
    }

    func normalizedTokens(
        for field: AccessibleDocumentSearchFieldV1
    ) -> [String] {
        guard let value = boundedFieldValues[field] else { return [] }
        return SearchContractValidationV1.normalizeSearchText(value)
            .unicodeScalars
            .split { !CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
    }

    func validate() throws {
        let fields = [
            nodeCount, figureCount, decorativeFigureCount,
            describedFigureCount, missingAlternateTextFigureCount,
            evidenceLinkCount,
        ]
        let required = Set(AccessibleDocumentSearchFieldV1.allCases)
        guard schemaVersion == Self.schemaVersion,
              KernelCanonicalHashV1.validSHA256(treeSHA256),
              audience == .customerSafe,
              SearchContractValidationV1.validID(projectionVersion),
              fields.allSatisfy({ $0 >= 0 && $0 <= Self.maximumValues }),
              figureCount <= nodeCount,
              decorativeFigureCount + describedFigureCount
                  + missingAlternateTextFigureCount == figureCount,
              roleValues == roleValues.sorted(by: { $0.rawValue < $1.rawValue }),
              Set(roleValues).count == roleValues.count,
              alternateTextProvenances == alternateTextProvenances.sorted(
                  by: { $0.rawValue < $1.rawValue }
              ),
              Set(alternateTextProvenances).count == alternateTextProvenances.count,
              Set(boundedFieldValues.keys) == required,
              boundedFieldValues.values.allSatisfy(SearchContractValidationV1.validID),
              !AccessibleDocumentLocalizationPolicyV1.containsProhibitedClaim(
                  in: Array(boundedFieldValues.values)
              ),
              !AccessibleDocumentLocalizationPolicyV1.containsCustomerOrWorkDataLeakage(
                  in: Array(boundedFieldValues.values)
              ) else {
            throw SearchContractFailureV1.forbiddenField
        }
        guard boundedFieldValues.values.allSatisfy({ value in
            let tokens = SearchContractValidationV1.normalizeSearchText(value)
                .unicodeScalars
                .split { !CharacterSet.alphanumerics.contains($0) }
                .map(String.init)
            return !tokens.isEmpty
                && tokens.allSatisfy(SearchContractValidationV1.isCanonicalSearchToken)
        }) else {
            throw SearchContractFailureV1.invalidField
        }
    }
}

enum AccessibleDocumentSearchProjectionPolicyV1 {
    static let sourceKind = "ACCESSIBLE_DOCUMENT_SEMANTIC_SUMMARY"
    static let semanticLabel = "ACCESSIBLE_DOCUMENT_SEMANTIC_SUMMARY_V1"
    static let fieldIDs = AccessibleDocumentSearchFieldV1.allCases.map(\.rawValue)
    static let metadataOnly = true
    static let derivedOnly = true
    static let customerSafeOnly = true
    static let excludesSemanticTree = true
    static let excludesNodeText = true
    static let excludesOriginalEvidence = true
    static let excludesEvidenceLinks = true
    static let excludesAssessorIdentity = true
    static let excludesPrivateLocators = true
    static let excludesUnsupportedClaims = true
    static let dropAndRebuildAfterRestore = true
    static let dropAndRebuildOnReplay = true

    static func accepts(_ field: AccessibleDocumentSearchFieldV1) -> Bool {
        fieldIDs.contains(field.rawValue)
    }
}

// MARK: - C23 version-bound field-reference search

/// Closed, metadata-only fields for the C23 disposable search projection.
/// Subject IDs, content IDs, locators, bytes, license notices, and source
/// payloads are deliberately not searchable.
enum FieldReferenceSearchFieldV1: String, CaseIterable, Codable, Hashable, Sendable {
    case referencePackID = "REFERENCE_PACK_ID"
    case releaseID = "RELEASE_ID"
    case bindingID = "BINDING_ID"
    case kind = "KIND"
    case semanticVersion = "SEMANTIC_VERSION"
    case provenanceKind = "PROVENANCE_KIND"
    case licenseScope = "LICENSE_SCOPE"
    case releaseDisposition = "RELEASE_DISPOSITION"
    case subjectKind = "SUBJECT_KIND"
    case subjectState = "SUBJECT_STATE"
    case availability = "AVAILABILITY"
    case requiredContentCount = "REQUIRED_CONTENT_COUNT"
    case missingContentCount = "MISSING_CONTENT_COUNT"
    case releaseDigest = "RELEASE_SHA256"
    case manifestDigest = "MANIFEST_SHA256"
    case readinessDigest = "READINESS_SHA256"
    case projectionDigest = "PROJECTION_SHA256"
}

struct FieldReferenceSearchRecordV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let releaseID: UUID
    let bindingID: UUID
    let referencePackID: String
    let semanticVersion: String
    let kind: FieldReferenceKindV1
    let provenanceKind: FieldReferenceProvenanceKindV1
    let licenseScope: FieldReferenceLicenseScopeV1
    let releaseDisposition: FieldReferenceReleaseDispositionV1
    let subjectKind: FieldReferenceSubjectKindV1
    let subjectState: FieldReferenceSubjectStateV1
    let availability: FieldReferenceAvailabilityV1
    let requiredContentCount: Int
    let missingContentCount: Int
    let releaseSHA256: String
    let manifestSHA256: String
    let readinessSHA256: String
    let projectionSHA256: String
    let boundedFieldValues: [FieldReferenceSearchFieldV1: String]

    init(projection: FieldReferenceReportProjectionV1) throws {
        try projection.validate()
        schemaVersion = Self.schemaVersion
        releaseID = projection.releaseID
        bindingID = projection.bindingID
        referencePackID = projection.referencePackID
        semanticVersion = projection.semanticVersion
        kind = projection.kind
        provenanceKind = projection.provenanceKind
        licenseScope = projection.licenseScope
        releaseDisposition = projection.releaseDisposition
        subjectKind = projection.subjectKind
        subjectState = projection.subjectState
        availability = projection.availability
        requiredContentCount = projection.requiredContentCount
        missingContentCount = projection.missingContentCount
        releaseSHA256 = projection.releaseSHA256
        manifestSHA256 = projection.manifestSHA256
        readinessSHA256 = projection.readinessSHA256
        projectionSHA256 = projection.projectionSHA256
        boundedFieldValues = [
            .referencePackID: projection.referencePackID,
            .releaseID: projection.releaseID.uuidString.lowercased(),
            .bindingID: projection.bindingID.uuidString.lowercased(),
            .kind: projection.kind.rawValue,
            .semanticVersion: projection.semanticVersion,
            .provenanceKind: projection.provenanceKind.rawValue,
            .licenseScope: projection.licenseScope.rawValue,
            .releaseDisposition: projection.releaseDisposition.rawValue,
            .subjectKind: projection.subjectKind.rawValue,
            .subjectState: projection.subjectState.rawValue,
            .availability: projection.availability.rawValue,
            .requiredContentCount: String(projection.requiredContentCount),
            .missingContentCount: String(projection.missingContentCount),
            .releaseDigest: projection.releaseSHA256,
            .manifestDigest: projection.manifestSHA256,
            .readinessDigest: projection.readinessSHA256,
            .projectionDigest: projection.projectionSHA256,
        ]
        try validate()
    }

    func normalizedTokens(for field: FieldReferenceSearchFieldV1) -> [String] {
        guard let value = boundedFieldValues[field] else { return [] }
        return SearchContractValidationV1.normalizeSearchText(value)
            .unicodeScalars
            .split { !CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
    }

    func validate() throws {
        let required = Set(FieldReferenceSearchFieldV1.allCases)
        let digestFields: Set<FieldReferenceSearchFieldV1> = [
            .releaseDigest, .manifestDigest, .readinessDigest, .projectionDigest,
        ]
        guard schemaVersion == Self.schemaVersion,
              releaseID != SearchContractValidationV1.zeroUUID,
              bindingID != SearchContractValidationV1.zeroUUID,
              SearchContractValidationV1.validID(referencePackID),
              SearchContractValidationV1.validID(semanticVersion),
              requiredContentCount >= 0,
              missingContentCount >= 0,
              missingContentCount <= requiredContentCount,
              KernelCanonicalHashV1.validSHA256(releaseSHA256),
              KernelCanonicalHashV1.validSHA256(manifestSHA256),
              KernelCanonicalHashV1.validSHA256(readinessSHA256),
              KernelCanonicalHashV1.validSHA256(projectionSHA256),
              Set(boundedFieldValues.keys) == required,
              boundedFieldValues.allSatisfy({ field, value in
                  digestFields.contains(field)
                      ? KernelCanonicalHashV1.validSHA256(value)
                      : SearchContractValidationV1.validID(value)
              }),
              !boundedFieldValues.keys.contains(where: {
                  $0.rawValue.contains("CONTENT_ID")
              }) else {
            throw SearchContractFailureV1.forbiddenField
        }
        guard boundedFieldValues.values.allSatisfy({ value in
            let tokens = SearchContractValidationV1.normalizeSearchText(value)
                .unicodeScalars
                .split { !CharacterSet.alphanumerics.contains($0) }
                .map(String.init)
            return !tokens.isEmpty
                && tokens.allSatisfy(SearchContractValidationV1.isCanonicalSearchToken)
        }) else {
            throw SearchContractFailureV1.invalidField
        }
    }
}

enum FieldReferenceSearchProjectionPolicyV1 {
    static let sourceKind = "FIELD_REFERENCE_RELEASE_BINDING"
    static let semanticLabel = "FIELD_REFERENCE_RELEASE_BINDING_METADATA_V1"
    static let fieldIDs = FieldReferenceSearchFieldV1.allCases.map(\.rawValue)
    static let metadataOnly = true
    static let derivedOnly = true
    static let dropAndRebuildAfterRestore = true
    static let dropAndRebuildOnReplay = true
    static let excludesReferenceBytes = true
    static let excludesContentIDs = true
    static let excludesPrivateLocators = true
    static let excludesLicenseSecrets = true
    static let excludesSubjectIdentity = true

    static func accepts(_ field: FieldReferenceSearchFieldV1) -> Bool {
        fieldIDs.contains(field.rawValue)
    }
}

// MARK: - C25 bounded survey-definition search projection

enum SurveyDefinitionSearchFieldV1: String, CaseIterable, Codable, Hashable, Sendable {
    case definitionID = "DEFINITION_ID"
    case releaseID = "RELEASE_ID"
    case activityKind = "ACTIVITY_KIND"
    case lifecycleState = "LIFECYCLE_STATE"
    case releaseRevision = "RELEASE_REVISION"
    case releaseSHA256 = "RELEASE_SHA256"
    case reportProjectionID = "REPORT_PROJECTION_ID"
}

struct SurveyDefinitionSearchRecordV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let maximumSearchTokens = 32

    let schemaVersion: Int
    let definitionID: String
    let releaseID: String
    let activityKind: ActivityKindV1
    let lifecycleState: SurveyDefinitionLifecycleStateV1
    let releaseRevision: UInt64
    let releaseSHA256: String
    let reportProjectionID: String
    let normalizedTokens: [String]

    init(
        release: SurveyDefinitionReleaseV1,
        lifecycleState: SurveyDefinitionLifecycleStateV1
    ) throws {
        try release.validate()
        schemaVersion = Self.schemaVersion
        definitionID = release.definitionID.uuidString.lowercased()
        releaseID = release.releaseID.uuidString.lowercased()
        activityKind = release.activityKind
        self.lifecycleState = lifecycleState
        releaseRevision = release.revision
        releaseSHA256 = release.releaseSHA256
        reportProjectionID = release.reportProjection.projectionID
        normalizedTokens = Self.tokens(
            definitionID: definitionID,
            releaseID: releaseID,
            activityKind: activityKind,
            lifecycleState: lifecycleState,
            reportProjectionID: reportProjectionID
        )
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              SearchContractValidationV1.validID(definitionID),
              SearchContractValidationV1.validID(releaseID),
              SearchContractValidationV1.validID(reportProjectionID),
              KernelCanonicalHashV1.validSHA256(releaseSHA256),
              releaseRevision > 0,
              normalizedTokens.count <= Self.maximumSearchTokens,
              normalizedTokens == normalizedTokens.sorted(),
              SearchContractValidationV1.normalizedTokensAreCanonical(normalizedTokens) else {
            throw SurveyDefinitionConsumerFailureV1.invalidValue
        }
    }

    private static func tokens(
        definitionID: String,
        releaseID: String,
        activityKind: ActivityKindV1,
        lifecycleState: SurveyDefinitionLifecycleStateV1,
        reportProjectionID: String
    ) -> [String] {
        let values = [
            definitionID, releaseID, activityKind.rawValue,
            lifecycleState.rawValue, reportProjectionID,
        ]
        let tokens = values.flatMap { value in
            SearchContractValidationV1.normalizeSearchText(value)
                .split { !CharacterSet.alphanumerics.contains($0) }
                .map(String.init)
        }
        return Array(Set(tokens)).sorted()
    }
}

enum SurveyDefinitionSearchProjectionPolicyV1 {
    static let sourceKind = "SURVEY_DEFINITION_RELEASE"
    static let semanticLabel = "SURVEY_DEFINITION_RELEASE_METADATA_V1"
    static let fieldIDs = SurveyDefinitionSearchFieldV1.allCases.map(\.rawValue).sorted()
    static let metadataOnly = true
    static let derivedOnly = true
    static let boundedToDefinitionReleaseAndLifecycle = true
    static let excludesAnswers = true
    static let excludesPromptText = true
    static let excludesActorIdentity = true
    static let excludesPrivateLocators = true
    static let excludesEvidenceBytes = true
    static let excludesPackagePayload = true
    static let dropAndRebuildAfterRestore = true
    static let dropAndRebuildOnReplay = true
    static let dropAndRebuildAfterDelete = true

    static func accepts(_ field: SurveyDefinitionSearchFieldV1) -> Bool {
        fieldIDs.contains(field.rawValue)
    }

    static func validate(_ record: SurveyDefinitionSearchRecordV1) throws {
        try record.validate()
        guard metadataOnly, derivedOnly,
              boundedToDefinitionReleaseAndLifecycle,
              excludesAnswers, excludesPromptText, excludesActorIdentity,
              excludesPrivateLocators, excludesEvidenceBytes, excludesPackagePayload else {
            throw SurveyDefinitionConsumerFailureV1.privacyViolation
        }
    }
}

// MARK: - C26 guided-survey session search projection

/// C26 search rows are disposable metadata derived from validated session
/// snapshots.  They deliberately omit fact values, prompts, provisional
/// labels, actor snapshots, evidence references, and publication payloads.
enum SurveySessionSearchFieldV1: String, CaseIterable, Codable, Hashable, Sendable {
    case sessionID = "survey_session_id"
    case definitionID = "survey_definition_id"
    case definitionReleaseID = "survey_definition_release_id"
    case lifecycleState = "survey_lifecycle_state"
    case sessionRevision = "survey_session_revision"
    case factState = "survey_fact_state"
    case subjectState = "survey_subject_state"
    case publicationState = "survey_publication_state"
    case publicationRevision = "survey_publication_revision"
}

struct SurveySessionSearchRecordV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let maximumSearchTokens = SearchContractLimitsV1.maximumQueryTokens

    let schemaVersion: Int
    let workspaceID: UUID
    let sessionID: UUID
    let definitionID: UUID
    let definitionReleaseID: UUID
    let lifecycleState: SurveySessionStateV1
    let sessionRevision: UInt64
    let factState: SurveySessionFactLocalizationStateV1
    let factCount: Int
    let subjectState: SurveySessionSubjectLocalizationStateV1
    let publicationState: SurveySessionPublicationLocalizationStateV1
    let publicationRevision: UInt64?
    let normalizedTokens: [String]

    init(
        session: SurveySessionV1,
        publication: SurveyPublicationSnapshotV1? = nil,
        provisionalSubject: ProvisionalSubjectV1? = nil,
        factState: SurveySessionFactLocalizationStateV1? = nil,
        publicationState: SurveySessionPublicationLocalizationStateV1? = nil
    ) throws {
        try session.validateIntrinsic()
        if let publication {
            guard publication.workspaceID == session.workspaceID,
                  publication.sessionID == session.sessionID,
                  publication.snapshotID != SearchContractValidationV1.zeroUUID,
                  publication.revision > 0 else {
                throw SearchContractFailureV1.invalidSession
            }
            try publication.reference.validate()
        }
        if let publicationState {
            guard (publication == nil) == (publicationState != .immutable) else {
                throw SearchContractFailureV1.invalidSession
            }
        }
        if let provisionalSubject {
            try provisionalSubject.validate()
            guard provisionalSubject.workspaceID == session.workspaceID else {
                throw SearchContractFailureV1.scopeMismatch
            }
            guard case let .provisional(reference) = session.subject,
                  reference.provisionalSubjectID == provisionalSubject.provisionalSubjectID,
                  reference.revision == provisionalSubject.revision,
                  reference.subjectSHA256 == provisionalSubject.subjectSHA256 else {
                throw SearchContractFailureV1.invalidSession
            }
        }
        let projectedFactCount = publication?.facts.count ?? 0
        if let factState {
            guard (projectedFactCount == 0) == (factState != .recorded) else {
                throw SearchContractFailureV1.invalidField
            }
        }

        schemaVersion = Self.schemaVersion
        workspaceID = session.workspaceID.rawValue
        sessionID = session.sessionID
        definitionID = session.authority.definitionRelease.definitionID
        definitionReleaseID = session.authority.definitionRelease.releaseID
        lifecycleState = session.state
        sessionRevision = session.revision
        subjectState = Self.subjectState(
            for: session.subject,
            provisionalSubject: provisionalSubject
        )
        factCount = projectedFactCount
        let resolvedFactState = factState ?? (factCount == 0 ? .notRecorded : .recorded)
        self.factState = resolvedFactState
        self.publicationRevision = publication?.revision ?? session.latestPublication?.revision
        let resolvedPublicationState = publicationState ?? Self.publicationState(
            publication: publication,
            latestPublication: session.latestPublication
        )
        self.publicationState = resolvedPublicationState
        normalizedTokens = Self.tokens(
            sessionID: sessionID,
            definitionID: definitionID,
            definitionReleaseID: definitionReleaseID,
            lifecycleState: lifecycleState,
            sessionRevision: sessionRevision,
            factState: resolvedFactState,
            subjectState: subjectState,
            publicationState: resolvedPublicationState,
            publicationRevision: self.publicationRevision
        )
        try validate()
    }

    var projectionIdentity: String {
        let publication = publicationRevision.map(String.init) ?? "none"
        return "survey-session:\(sessionID.uuidString.lowercased()):publication:\(publication)"
    }

    var boundedFieldValues: [SurveySessionSearchFieldV1: String] {
        [
            .sessionID: sessionID.uuidString.lowercased(),
            .definitionID: definitionID.uuidString.lowercased(),
            .definitionReleaseID: definitionReleaseID.uuidString.lowercased(),
            .lifecycleState: lifecycleState.rawValue,
            .sessionRevision: String(sessionRevision),
            .factState: factState.rawValue,
            .subjectState: subjectState.rawValue,
            .publicationState: publicationState.rawValue,
            .publicationRevision: publicationRevision.map(String.init) ?? "0",
        ]
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              workspaceID != SearchContractValidationV1.zeroUUID,
              sessionID != SearchContractValidationV1.zeroUUID,
              definitionID != SearchContractValidationV1.zeroUUID,
              definitionReleaseID != SearchContractValidationV1.zeroUUID,
              sessionRevision > 0,
              factCount >= 0,
              factCount <= SurveyDefinitionLimitsV1.maximumFacts,
              normalizedTokens.count <= Self.maximumSearchTokens,
              normalizedTokens == normalizedTokens.sorted(),
              SearchContractValidationV1.normalizedTokensAreCanonical(normalizedTokens),
              boundedFieldValues.count == SurveySessionSearchFieldV1.allCases.count else {
            throw SearchContractFailureV1.invalidSession
        }
        switch publicationState {
        case .notPublished, .interrupted:
            guard publicationRevision == nil else { throw SearchContractFailureV1.invalidSession }
        case .recorded, .immutable:
            guard let publicationRevision, publicationRevision > 0 else {
                throw SearchContractFailureV1.invalidSession
            }
        }
        if factState == .recorded {
            guard factCount > 0 else { throw SearchContractFailureV1.invalidField }
        }
        guard boundedFieldValues.values.allSatisfy({ value in
            let tokens = SearchContractValidationV1.normalizeSearchText(value)
                .unicodeScalars
                .split { !CharacterSet.alphanumerics.contains($0) }
                .map(String.init)
            return !tokens.isEmpty
                && tokens.allSatisfy(SearchContractValidationV1.isCanonicalSearchToken)
        }) else {
            throw SearchContractFailureV1.invalidField
        }
    }

    private static func subjectState(
        for subject: SurveySessionSubjectV1,
        provisionalSubject: ProvisionalSubjectV1?
    ) -> SurveySessionSubjectLocalizationStateV1 {
        switch subject {
        case .canonical:
            return .canonical
        case .provisional:
            guard let provisionalSubject else { return .provisional }
            switch provisionalSubject.state {
            case .active: return .provisional
            case .promoted: return .promoted
            case .reconciledAlias: return .reconciledAlias
            case .promotionReversed: return .promotionReversed
            case .archived: return .archived
            }
        }
    }

    private static func publicationState(
        publication: SurveyPublicationSnapshotV1?,
        latestPublication: SurveyPublicationReferenceV1?
    ) -> SurveySessionPublicationLocalizationStateV1 {
        if publication != nil { return .immutable }
        return latestPublication == nil ? .notPublished : .recorded
    }

    private static func tokens(
        sessionID: UUID,
        definitionID: UUID,
        definitionReleaseID: UUID,
        lifecycleState: SurveySessionStateV1,
        sessionRevision: UInt64,
        factState: SurveySessionFactLocalizationStateV1,
        subjectState: SurveySessionSubjectLocalizationStateV1,
        publicationState: SurveySessionPublicationLocalizationStateV1,
        publicationRevision: UInt64?
    ) -> [String] {
        let values = [
            sessionID.uuidString,
            definitionID.uuidString,
            definitionReleaseID.uuidString,
            lifecycleState.rawValue,
            String(sessionRevision),
            factState.rawValue,
            subjectState.rawValue,
            publicationState.rawValue,
            String(publicationRevision ?? 0),
        ]
        let tokens = values.flatMap { value in
            SearchContractValidationV1.normalizeSearchText(value)
                .split { !CharacterSet.alphanumerics.contains($0) }
                .map(String.init)
        }
        return Array(Set(tokens)).sorted()
    }
}

enum SurveySessionSearchProjectionPolicyV1 {
    static let sourceKind = "SURVEY_SESSION"
    static let semanticLabel = "SURVEY_SESSION_METADATA_V1"
    static let fieldIDs = SurveySessionSearchFieldV1.allCases.map(\.rawValue).sorted()
    static let metadataOnly = true
    static let derivedOnly = true
    static let dropAndRebuildAfterRestore = true
    static let dropAndRebuildOnReplay = true
    static let dropAndRebuildAfterDelete = true
    static let excludesFactValues = true
    static let excludesPromptText = true
    static let excludesProvisionalSubjectLabels = true
    static let excludesActorIdentity = true
    static let excludesEvidenceReferences = true
    static let excludesEvidenceBytes = true
    static let excludesPrivateLocators = true
    static let excludesCustomerAndWorkData = true
    static let excludesUnsupportedClaims = true

    static func accepts(_ field: SurveySessionSearchFieldV1) -> Bool {
        fieldIDs.contains(field.rawValue)
    }

    static func validate(_ record: SurveySessionSearchRecordV1) throws {
        try record.validate()
        guard metadataOnly, derivedOnly, dropAndRebuildAfterRestore,
              dropAndRebuildOnReplay, dropAndRebuildAfterDelete,
              excludesFactValues, excludesPromptText,
              excludesProvisionalSubjectLabels, excludesActorIdentity,
              excludesEvidenceReferences, excludesEvidenceBytes,
              excludesPrivateLocators, excludesCustomerAndWorkData,
              excludesUnsupportedClaims else {
            throw SearchContractFailureV1.forbiddenField
        }
    }
}

// MARK: - C27 bounded asset-locator search projection

/// Search stores only bounded identity/state fields from a locator report.
/// Opaque input, external-key values, signed payloads, and private key
/// material are never tokenized or persisted in this disposable index.
enum AssetLocatorSearchFieldV1: String, CaseIterable, Codable, Hashable, Sendable {
    case workspaceID = "asset_locator_workspace_id"
    case locatorID = "asset_locator_id"
    case assetID = "asset_locator_asset_id"
    case locatorRevision = "asset_locator_revision"
    case locatorState = "asset_locator_state"
    case replacementLocatorID = "asset_locator_replacement_locator_id"
    case resolutionOutcome = "asset_locator_resolution_outcome"
    case candidateCount = "asset_locator_candidate_count"
}

struct AssetLocatorSearchRecordV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let maximumSearchTokens = SearchContractLimitsV1.maximumQueryTokens

    let schemaVersion: Int
    let workspaceID: UUID
    let locatorID: UUID?
    let assetID: UUID?
    let locatorRevision: UInt64?
    let locatorState: AssetLocatorStateV1?
    let replacementLocatorID: UUID?
    let resolutionOutcome: LocatorResolutionOutcomeV1
    let candidateCount: Int
    let resolutionSHA256: String
    let normalizedTokens: [String]

    init(projection: AssetLocatorReportProjectionV1) throws {
        try projection.validate(format: .openJSON)
        schemaVersion = Self.schemaVersion
        workspaceID = projection.resolution.workspaceID.rawValue
        locatorID = projection.metadata?.locatorID
        assetID = projection.metadata?.assetID
        locatorRevision = projection.metadata?.revision
        locatorState = projection.metadata?.state
        replacementLocatorID = projection.resolution.replacementLocatorID
        resolutionOutcome = projection.resolution.outcome
        candidateCount = projection.resolution.candidateCount
        resolutionSHA256 = projection.resolution.resolutionSHA256
        normalizedTokens = Self.tokens(
            workspaceID: workspaceID,
            locatorID: locatorID,
            assetID: assetID,
            locatorRevision: locatorRevision,
            locatorState: locatorState,
            replacementLocatorID: replacementLocatorID,
            resolutionOutcome: resolutionOutcome,
            candidateCount: candidateCount
        )
        try validate()
    }

    init(
        locator: AssetLocatorV1,
        resolution: LocatorResolutionV1? = nil
    ) throws {
        let projection = try AssetLocatorReportProjectionV1(
            locator: locator,
            resolution: resolution
        )
        try self.init(projection: projection)
    }

    var projectionIdentity: String {
        "asset-locator:\(workspaceID.uuidString.lowercased()):\(resolutionSHA256)"
    }

    var boundedFieldValues: [AssetLocatorSearchFieldV1: String] {
        [
            .workspaceID: workspaceID.uuidString.lowercased(),
            .locatorID: locatorID?.uuidString.lowercased() ?? "none",
            .assetID: assetID?.uuidString.lowercased() ?? "none",
            .locatorRevision: locatorRevision.map(String.init) ?? "none",
            .locatorState: locatorState?.rawValue ?? "NONE",
            .replacementLocatorID: replacementLocatorID?.uuidString.lowercased() ?? "none",
            .resolutionOutcome: resolutionOutcome.rawValue,
            .candidateCount: String(candidateCount),
        ]
    }

    func validate() throws {
        let zero = SearchContractValidationV1.zeroUUID
        guard schemaVersion == Self.schemaVersion,
              workspaceID != zero,
              KernelCanonicalHashV1.validSHA256(resolutionSHA256),
              (0...AssetLocatorLimitsV1.maximumCandidates).contains(candidateCount),
              normalizedTokens.count <= Self.maximumSearchTokens,
              normalizedTokens == normalizedTokens.sorted(),
              SearchContractValidationV1.normalizedTokensAreCanonical(normalizedTokens),
              boundedFieldValues.count == AssetLocatorSearchFieldV1.allCases.count,
              boundedFieldValues.values.allSatisfy({ value in
                  let parts = SearchContractValidationV1.normalizeSearchText(value)
                      .split { !CharacterSet.alphanumerics.contains($0) }
                      .map(String.init)
                  return !parts.isEmpty
                      && parts.allSatisfy(SearchContractValidationV1.isCanonicalSearchToken)
              }) else {
            throw SearchContractFailureV1.invalidField
        }
        let selected = locatorID != nil && assetID != nil
        switch resolutionOutcome {
        case .matched, .retired, .revoked:
            guard selected, replacementLocatorID == nil,
                  locatorRevision != nil, locatorState != nil else {
                throw SearchContractFailureV1.invalidField
            }
        case .replaced:
            guard selected, replacementLocatorID != nil,
                  locatorRevision != nil,
                  locatorState.map({ $0 == .replaced }) == true else {
                throw SearchContractFailureV1.invalidField
            }
        case .ambiguous:
            guard !selected, replacementLocatorID == nil, candidateCount > 1 else {
                throw SearchContractFailureV1.invalidField
            }
        case .noMatch, .foreignWorkspace, .damagedOrIncomplete:
            guard !selected, replacementLocatorID == nil,
                  locatorRevision == nil, locatorState == nil else {
                throw SearchContractFailureV1.invalidField
            }
        }
    }

    private static func tokens(
        workspaceID: UUID,
        locatorID: UUID?,
        assetID: UUID?,
        locatorRevision: UInt64?,
        locatorState: AssetLocatorStateV1?,
        replacementLocatorID: UUID?,
        resolutionOutcome: LocatorResolutionOutcomeV1,
        candidateCount: Int
    ) -> [String] {
        let values = [
            workspaceID.uuidString,
            locatorID?.uuidString ?? "none",
            assetID?.uuidString ?? "none",
            locatorRevision.map(String.init) ?? "none",
            locatorState?.rawValue ?? "NONE",
            replacementLocatorID?.uuidString ?? "none",
            resolutionOutcome.rawValue,
            String(candidateCount),
        ]
        let tokens = values.flatMap { value in
            SearchContractValidationV1.normalizeSearchText(value)
                .split { !CharacterSet.alphanumerics.contains($0) }
                .map(String.init)
        }
        return Array(Set(tokens)).sorted()
    }
}

enum AssetLocatorSearchProjectionPolicyV1 {
    static let sourceKind = "ASSET_LOCATOR"
    static let semanticLabel = "ASSET_LOCATOR_METADATA_V1"
    static let fieldIDs = AssetLocatorSearchFieldV1.allCases.map(\.rawValue).sorted()
    static let metadataOnly = true
    static let derivedOnly = true
    static let boundedToLocatorAssetAndState = true
    static let dropAndRebuildAfterRestore = true
    static let dropAndRebuildOnReplay = true
    static let dropAndRebuildAfterDelete = true
    static let excludesOpaqueInput = true
    static let excludesPrivateKeyMaterial = true
    static let excludesSecrets = true
    static let excludesVendorIdentifiers = true
    static let excludesPrivateLocators = true
    static let excludesActorIdentity = true
    static let excludesUnsupportedClaims = true

    static func accepts(_ field: AssetLocatorSearchFieldV1) -> Bool {
        fieldIDs.contains(field.rawValue)
    }

    static func validate(_ record: AssetLocatorSearchRecordV1) throws {
        try record.validate()
        guard metadataOnly, derivedOnly, boundedToLocatorAssetAndState,
              dropAndRebuildAfterRestore, dropAndRebuildOnReplay,
              dropAndRebuildAfterDelete, excludesOpaqueInput,
              excludesPrivateKeyMaterial, excludesSecrets,
              excludesVendorIdentifiers, excludesPrivateLocators,
              excludesActorIdentity, excludesUnsupportedClaims else {
            throw SearchContractFailureV1.forbiddenField
        }
    }
}

// MARK: - C28 bounded schedule occurrence search projection

/// Search stores only schedule identity, frozen time-basis metadata, and the
/// closed occurrence state. Due/reminder rows are disposable derivatives; no
/// notification payload, work-instance identity, actor, note, or draft is
/// searchable.
enum ScheduleOccurrenceSearchFieldV1: String, CaseIterable, Codable, Hashable, Sendable {
    case workspaceID = "schedule_workspace_id"
    case scheduleDefinitionID = "schedule_definition_id"
    case releaseID = "schedule_release_id"
    case occurrenceID = "schedule_occurrence_id"
    case occurrenceState = "schedule_occurrence_state"
    case nominalLocalDate = "schedule_nominal_local_date"
    case nominalLocalTime = "schedule_nominal_local_time"
    case effectiveDueAtUTC = "schedule_effective_due_at_utc"
    case timeZoneIdentifier = "schedule_time_zone_identifier"
    case calendarBasisID = "schedule_calendar_basis_id"
    case releaseSHA256 = "schedule_release_sha256"
}

struct ScheduleOccurrenceSearchRecordV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let maximumSearchTokens = SearchContractLimitsV1.maximumQueryTokens

    let schemaVersion: Int
    let workspaceID: UUID
    let scheduleDefinitionID: UUID
    let releaseID: UUID
    let occurrenceID: OccurrenceIDV1
    let occurrenceState: OccurrenceStateV1
    let nominalLocalDate: String
    let nominalLocalTime: String
    let effectiveDueAtUTC: Date?
    let timeZoneIdentifier: String
    let calendarBasisID: String
    let releaseSHA256: String
    let normalizedTokens: [String]

    init(
        projection: ScheduleReportProjectionV1,
        occurrence: ScheduleOccurrenceReportProjectionV1
    ) throws {
        try ScheduleReportProjectionPolicyV1.validate(projection)
        try occurrence.validate()
        guard projection.occurrences.contains(occurrence),
              occurrence.scheduleRelease == projection.scheduleRelease else {
            throw SearchContractFailureV1.scopeMismatch
        }
        schemaVersion = Self.schemaVersion
        workspaceID = projection.workspaceID
        scheduleDefinitionID = projection.scheduleDefinitionID
        releaseID = projection.scheduleRelease.releaseID
        occurrenceID = occurrence.occurrenceID
        occurrenceState = occurrence.state
        nominalLocalDate = occurrence.nominalBasis.nominalLocalDate
        nominalLocalTime = occurrence.nominalBasis.nominalLocalTime
        effectiveDueAtUTC = occurrence.effectiveBasis.resolvedAtUTC
        timeZoneIdentifier = projection.timeBasis.ianaTimeZoneIdentifier
        calendarBasisID = projection.timeBasis.calendarBasisID
        releaseSHA256 = projection.scheduleRelease.releaseSHA256
        normalizedTokens = Self.tokens(
            workspaceID: workspaceID,
            scheduleDefinitionID: scheduleDefinitionID,
            releaseID: releaseID,
            occurrenceID: occurrenceID,
            occurrenceState: occurrenceState,
            nominalLocalDate: nominalLocalDate,
            nominalLocalTime: nominalLocalTime,
            timeZoneIdentifier: timeZoneIdentifier,
            calendarBasisID: calendarBasisID
        )
        try validate()
    }

    var projectionIdentity: String {
        "schedule-occurrence:\(workspaceID.uuidString.lowercased()):\(occurrenceID.rawValue)"
    }

    var boundedFieldValues: [ScheduleOccurrenceSearchFieldV1: String] {
        [
            .workspaceID: workspaceID.uuidString.lowercased(),
            .scheduleDefinitionID: scheduleDefinitionID.uuidString.lowercased(),
            .releaseID: releaseID.uuidString.lowercased(),
            .occurrenceID: occurrenceID.rawValue,
            .occurrenceState: occurrenceState.rawValue,
            .nominalLocalDate: nominalLocalDate,
            .nominalLocalTime: nominalLocalTime,
            .effectiveDueAtUTC: effectiveDueAtUTC.map {
                // Keep hostile-but-finite Date values lossless and avoid a
                // trapping floating-point-to-Int conversion in search.
                String($0.timeIntervalSince1970)
            } ?? "none",
            .timeZoneIdentifier: timeZoneIdentifier,
            .calendarBasisID: calendarBasisID,
            .releaseSHA256: releaseSHA256,
        ]
    }

    func validate() throws {
        let zero = SearchContractValidationV1.zeroUUID
        guard schemaVersion == Self.schemaVersion,
              workspaceID != zero,
              scheduleDefinitionID != zero,
              releaseID != zero,
              occurrenceState == OccurrenceStateV1(rawValue: occurrenceState.rawValue),
              SearchContractValidationV1.validID(occurrenceID.rawValue),
              SearchContractValidationV1.validDisplayText(
                  nominalLocalDate,
                  maximumBytes: SearchContractLimitsV1.maximumIdentifierBytes
              ),
              SearchContractValidationV1.validDisplayText(
                  nominalLocalTime,
                  maximumBytes: SearchContractLimitsV1.maximumIdentifierBytes
              ),
              SearchContractValidationV1.validDisplayText(
                  timeZoneIdentifier,
                  maximumBytes: SearchContractLimitsV1.maximumIdentifierBytes
              ),
              SearchContractValidationV1.validDisplayText(
                  calendarBasisID,
                  maximumBytes: SearchContractLimitsV1.maximumIdentifierBytes
              ),
              effectiveDueAtUTC.map(SearchContractValidationV1.validDate) ?? true,
              KernelCanonicalHashV1.validSHA256(releaseSHA256),
              normalizedTokens.count <= Self.maximumSearchTokens,
              normalizedTokens == normalizedTokens.sorted(),
              SearchContractValidationV1.normalizedTokensAreCanonical(normalizedTokens),
              boundedFieldValues.count == ScheduleOccurrenceSearchFieldV1.allCases.count,
              boundedFieldValues.values.allSatisfy({ value in
                  let parts = SearchContractValidationV1.normalizeSearchText(value)
                      .split { !CharacterSet.alphanumerics.contains($0) }
                      .map(String.init)
                  return !parts.isEmpty
                      && parts.allSatisfy(SearchContractValidationV1.isCanonicalSearchToken)
              }) else {
            throw SearchContractFailureV1.invalidField
        }
    }

    private static func tokens(
        workspaceID: UUID,
        scheduleDefinitionID: UUID,
        releaseID: UUID,
        occurrenceID: OccurrenceIDV1,
        occurrenceState: OccurrenceStateV1,
        nominalLocalDate: String,
        nominalLocalTime: String,
        timeZoneIdentifier: String,
        calendarBasisID: String
    ) -> [String] {
        let values = [
            workspaceID.uuidString,
            scheduleDefinitionID.uuidString,
            releaseID.uuidString,
            occurrenceID.rawValue,
            occurrenceState.rawValue,
            nominalLocalDate,
            nominalLocalTime,
            timeZoneIdentifier,
            calendarBasisID,
        ]
        let tokens = values.flatMap { value in
            SearchContractValidationV1.normalizeSearchText(value)
                .split { !CharacterSet.alphanumerics.contains($0) }
                .map(String.init)
        }
        return Array(Set(tokens)).sorted()
    }
}

enum ScheduleOccurrenceSearchProjectionPolicyV1 {
    static let sourceKind = "SCHEDULE_OCCURRENCE"
    static let semanticLabel = "SCHEDULE_OCCURRENCE_METADATA_V1"
    static let fieldIDs = ScheduleOccurrenceSearchFieldV1.allCases.map(\.rawValue).sorted()
    static let metadataOnly = true
    static let derivedOnly = true
    static let dropAndRebuildAfterRestore = true
    static let dropAndRebuildOnReplay = true
    static let dropAndRebuildAfterDelete = true
    static let notificationDeliveryIsTruth = false
    static let excludesNotificationPayload = true
    static let excludesWorkInstanceIdentity = true
    static let excludesActorIdentity = true
    static let excludesDraftValues = true
    static let excludesUnsupportedClaims = true

    static func accepts(_ field: ScheduleOccurrenceSearchFieldV1) -> Bool {
        fieldIDs.contains(field.rawValue)
    }

    static func validate(_ record: ScheduleOccurrenceSearchRecordV1) throws {
        try record.validate()
        guard metadataOnly, derivedOnly,
              dropAndRebuildAfterRestore, dropAndRebuildOnReplay,
              dropAndRebuildAfterDelete, !notificationDeliveryIsTruth,
              excludesNotificationPayload, excludesWorkInstanceIdentity,
              excludesActorIdentity, excludesDraftValues,
              excludesUnsupportedClaims else {
            throw SearchContractFailureV1.forbiddenField
        }
    }
}

// MARK: - C51 advanced schedule derived search projection

enum AdvancedScheduleOccurrenceSearchFieldV1: String, CaseIterable, Codable, Hashable, Sendable {
    case occurrenceID = "advanced_schedule_occurrence_id"
    case occurrenceState = "advanced_schedule_occurrence_state"
    case nominalDate = "advanced_schedule_nominal_date"
    case effectiveDate = "advanced_schedule_effective_date"
    case adjustmentReason = "advanced_schedule_adjustment_reason"
    case precedenceLevel = "advanced_schedule_precedence_level"
    case overrideScope = "advanced_schedule_override_scope"
    case overrideKind = "advanced_schedule_override_kind"
    case localTimeDisposition = "advanced_schedule_local_time_disposition"
    case historyImmutable = "advanced_schedule_history_immutable"
    case requiresManualResolution = "advanced_schedule_requires_manual_resolution"
    case calendarReleaseSHA256 = "advanced_schedule_calendar_release_sha256"
    case basisSHA256 = "advanced_schedule_basis_sha256"
}

struct AdvancedScheduleOccurrenceSearchRecordV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let occurrenceID: OccurrenceIDV1
    let occurrenceState: OccurrenceStateV1
    let nominalDate: String
    let effectiveDate: String?
    let adjustmentReason: ScheduleBasisAdjustmentReasonV1
    let precedenceLevel: ScheduleOverridePrecedenceLevelV1
    let overrideScope: ScheduleOverrideScopeV1?
    let overrideKind: ScheduleOccurrenceOverrideKindV1?
    let localTimeDisposition: LocalTimeDispositionV1
    let historyImmutable: Bool
    let requiresManualResolution: Bool
    let calendarReleaseSHA256: String
    let basisSHA256: String
    let normalizedTokens: [String]

    init(projection: AdvancedScheduleReportProjectionV1,
         occurrence: AdvancedScheduleOccurrenceReportProjectionV1) throws {
        try projection.validate(); try occurrence.validate()
        guard projection.occurrences.contains(occurrence),
              occurrence.basis.calendarRelease == projection.calendarRelease else {
            throw SearchContractFailureV1.scopeMismatch
        }
        schemaVersion = Self.schemaVersion; occurrenceID = occurrence.occurrenceID
        occurrenceState = occurrence.state; nominalDate = occurrence.basis.nominalDate.canonicalString
        effectiveDate = occurrence.basis.effectiveDate?.canonicalString
        adjustmentReason = occurrence.basis.adjustmentReason
        precedenceLevel = occurrence.precedenceLevel; overrideScope = occurrence.overrideScope
        overrideKind = occurrence.overrideKind; localTimeDisposition = occurrence.basis.localTimeDisposition
        historyImmutable = occurrence.historyImmutable
        requiresManualResolution = occurrence.requiresManualResolution
        calendarReleaseSHA256 = occurrence.basis.calendarRelease.releaseSHA256
        basisSHA256 = occurrence.basis.basisSHA256
        normalizedTokens = Self.tokens(occurrenceID.rawValue, occurrenceState.rawValue,
            nominalDate, effectiveDate ?? "none", adjustmentReason.rawValue,
            String(precedenceLevel.rawValue), overrideScope?.rawValue ?? "none",
            overrideKind?.rawValue ?? "none", localTimeDisposition.rawValue,
            historyImmutable ? "immutable" : "mutable",
            requiresManualResolution ? "manual" : "resolved")
        try validate()
    }

    var projectionIdentity: String { "advanced-schedule-occurrence:\(occurrenceID.rawValue):\(basisSHA256)" }
    var boundedFieldValues: [AdvancedScheduleOccurrenceSearchFieldV1: String] { [
        .occurrenceID: occurrenceID.rawValue, .occurrenceState: occurrenceState.rawValue,
        .nominalDate: nominalDate, .effectiveDate: effectiveDate ?? "none",
        .adjustmentReason: adjustmentReason.rawValue,
        .precedenceLevel: String(precedenceLevel.rawValue),
        .overrideScope: overrideScope?.rawValue ?? "none",
        .overrideKind: overrideKind?.rawValue ?? "none",
        .localTimeDisposition: localTimeDisposition.rawValue,
        .historyImmutable: historyImmutable ? "true" : "false",
        .requiresManualResolution: requiresManualResolution ? "true" : "false",
        .calendarReleaseSHA256: calendarReleaseSHA256, .basisSHA256: basisSHA256,
    ] }

    func validate() throws {
        try occurrenceID.validate(); try ScheduleLimitsV1.digest(calendarReleaseSHA256)
        try ScheduleLimitsV1.digest(basisSHA256)
        guard schemaVersion == Self.schemaVersion,
              (try? ScheduleLocalDateV1(nominalDate)) != nil,
              effectiveDate.map({ (try? ScheduleLocalDateV1($0)) != nil }) ?? true,
              requiresManualResolution == (adjustmentReason == .manualResolution),
              boundedFieldValues.count == AdvancedScheduleOccurrenceSearchFieldV1.allCases.count,
              normalizedTokens == normalizedTokens.sorted(),
              normalizedTokens.count <= SearchContractLimitsV1.maximumQueryTokens,
              SearchContractValidationV1.normalizedTokensAreCanonical(normalizedTokens) else {
            throw SearchContractFailureV1.invalidField
        }
    }

    private static func tokens(_ values: String...) -> [String] {
        Array(Set(values.flatMap { SearchContractValidationV1.normalizeSearchText($0)
            .split { !CharacterSet.alphanumerics.contains($0) }.map(String.init) })).sorted()
    }
}

enum AdvancedScheduleOccurrenceSearchProjectionPolicyV1 {
    static let semanticLabel = "ADVANCED_SCHEDULE_OCCURRENCE_METADATA_V1"
    static let fieldIDs = AdvancedScheduleOccurrenceSearchFieldV1.allCases.map(\.rawValue).sorted()
    static let derivedOnly = true
    static let dropAndRebuildFromFrozenTruth = true
    static let excludesFreeText = true
    static let excludesActorIdentity = true
    static let excludesWorkIdentity = true
    static let excludesNotificationPayload = true
    static let excludesCalendarBytes = true
    static func validate(_ value: AdvancedScheduleOccurrenceSearchRecordV1) throws {
        guard derivedOnly, dropAndRebuildFromFrozenTruth, excludesFreeText,
              excludesActorIdentity, excludesWorkIdentity, excludesNotificationPayload,
              excludesCalendarBytes else { throw SearchContractFailureV1.forbiddenField }
        try value.validate()
    }
}

// MARK: - C29 versioned plan placement search projection

/// Search receives only bounded plan identity, normalized placement values,
/// and closed recorded states. Subject identifiers, source bytes, private
/// locator bindings, component inputs, and rebase payloads stay out of the
/// disposable local index.
enum PlanPlacementSearchFieldV1: String, CaseIterable, Codable, Hashable, Sendable {
    case workspaceID = "plan_workspace_id"
    case planDocumentID = "plan_document_id"
    case planRevisionID = "plan_revision_id"
    case placementID = "plan_placement_id"
    case subjectKind = "plan_subject_kind"
    case documentState = "plan_document_state"
    case revisionState = "plan_revision_state"
    case disposition = "plan_placement_disposition"
    case spatialFrameID = "plan_spatial_frame_id"
    case xMillionths = "plan_x_millionths"
    case yMillionths = "plan_y_millionths"
    case placementRevision = "plan_placement_revision"
    case projectionSHA256 = "plan_projection_sha256"
}

struct PlanPlacementSearchRecordV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let maximumSearchTokens = SearchContractLimitsV1.maximumQueryTokens

    let schemaVersion: Int
    let workspaceID: UUID
    let planDocumentID: UUID
    let planRevisionID: UUID
    let placementID: UUID
    let subjectKind: PlanPlacementSubjectKindV1
    let documentState: PlanDocumentStateV1
    let revisionState: PlanRevisionStateV1
    let disposition: PlanPlacementDispositionV1
    let spatialFrameID: UUID
    let xMillionths: Int64
    let yMillionths: Int64
    let placementRevision: UInt64
    let projectionSHA256: String
    let normalizedTokens: [String]

    init(
        projection: PlanReportProjectionV1,
        placement: PlanPlacementReportProjectionV1
    ) throws {
        try PlanReportProjectionPolicyV1.validate(projection)
        try placement.validate()
        guard projection.placements.contains(placement),
              placement.planRevisionID == projection.revisionReference.planRevisionID else {
            throw SearchContractFailureV1.scopeMismatch
        }
        schemaVersion = Self.schemaVersion
        workspaceID = projection.workspaceID
        planDocumentID = projection.documentReference.planDocumentID
        planRevisionID = projection.revisionReference.planRevisionID
        placementID = placement.placementID
        subjectKind = placement.subjectKind
        documentState = projection.documentState
        revisionState = projection.revisionState
        disposition = placement.disposition
        spatialFrameID = placement.spatialFrameID
        xMillionths = placement.xMillionths
        yMillionths = placement.yMillionths
        placementRevision = placement.revision
        projectionSHA256 = projection.projectionSHA256
        normalizedTokens = Self.tokens(
            workspaceID: workspaceID,
            planDocumentID: planDocumentID,
            planRevisionID: planRevisionID,
            placementID: placementID,
            spatialFrameID: spatialFrameID,
            subjectKind: subjectKind,
            documentState: documentState,
            revisionState: revisionState,
            disposition: disposition,
            xMillionths: xMillionths,
            yMillionths: yMillionths
        )
        try validate()
    }

    var projectionIdentity: String {
        "plan-placement:\(workspaceID.uuidString.lowercased()):\(placementID.uuidString.lowercased())"
    }

    var boundedFieldValues: [PlanPlacementSearchFieldV1: String] {
        [
            .workspaceID: workspaceID.uuidString.lowercased(),
            .planDocumentID: planDocumentID.uuidString.lowercased(),
            .planRevisionID: planRevisionID.uuidString.lowercased(),
            .placementID: placementID.uuidString.lowercased(),
            .subjectKind: subjectKind.rawValue,
            .documentState: documentState.rawValue,
            .revisionState: revisionState.rawValue,
            .disposition: disposition.rawValue,
            .spatialFrameID: spatialFrameID.uuidString.lowercased(),
            .xMillionths: String(xMillionths),
            .yMillionths: String(yMillionths),
            .placementRevision: String(placementRevision),
            .projectionSHA256: projectionSHA256,
        ]
    }

    func validate() throws {
        let zero = SearchContractValidationV1.zeroUUID
        guard schemaVersion == Self.schemaVersion,
              workspaceID != zero,
              planDocumentID != zero,
              planRevisionID != zero,
              placementID != zero,
              spatialFrameID != zero,
              subjectKind == PlanPlacementSubjectKindV1(rawValue: subjectKind.rawValue),
              documentState == PlanDocumentStateV1(rawValue: documentState.rawValue),
              revisionState == PlanRevisionStateV1(rawValue: revisionState.rawValue),
              disposition == PlanPlacementDispositionV1(rawValue: disposition.rawValue),
              (0...PlanLimitsV1.normalizedScale).contains(xMillionths),
              (0...PlanLimitsV1.normalizedScale).contains(yMillionths),
              placementRevision > 0,
              KernelCanonicalHashV1.validSHA256(projectionSHA256),
              normalizedTokens.count <= Self.maximumSearchTokens,
              normalizedTokens == normalizedTokens.sorted(),
              SearchContractValidationV1.normalizedTokensAreCanonical(normalizedTokens),
              boundedFieldValues.count == PlanPlacementSearchFieldV1.allCases.count,
              boundedFieldValues.values.allSatisfy({ value in
                  let parts = SearchContractValidationV1.normalizeSearchText(value)
                      .split { !CharacterSet.alphanumerics.contains($0) }
                      .map(String.init)
                  return !parts.isEmpty
                      && parts.allSatisfy(SearchContractValidationV1.isCanonicalSearchToken)
              }) else {
            throw SearchContractFailureV1.invalidField
        }
    }

    private static func tokens(
        workspaceID: UUID,
        planDocumentID: UUID,
        planRevisionID: UUID,
        placementID: UUID,
        spatialFrameID: UUID,
        subjectKind: PlanPlacementSubjectKindV1,
        documentState: PlanDocumentStateV1,
        revisionState: PlanRevisionStateV1,
        disposition: PlanPlacementDispositionV1,
        xMillionths: Int64,
        yMillionths: Int64
    ) -> [String] {
        let values = [
            workspaceID.uuidString,
            planDocumentID.uuidString,
            planRevisionID.uuidString,
            placementID.uuidString,
            spatialFrameID.uuidString,
            subjectKind.rawValue,
            documentState.rawValue,
            revisionState.rawValue,
            disposition.rawValue,
            String(xMillionths),
            String(yMillionths),
        ]
        let tokens = values.flatMap { value in
            SearchContractValidationV1.normalizeSearchText(value)
                .split { !CharacterSet.alphanumerics.contains($0) }
                .map(String.init)
        }
        return Array(Set(tokens)).sorted()
    }
}

enum PlanPlacementSearchProjectionPolicyV1 {
    static let sourceKind = "PLAN_PLACEMENT"
    static let semanticLabel = "PLAN_PLACEMENT_METADATA_V1"
    static let fieldIDs = PlanPlacementSearchFieldV1.allCases.map(\.rawValue).sorted()
    static let metadataOnly = true
    static let derivedOnly = true
    static let normalizedCoordinatesOnly = true
    static let dropAndRebuildAfterRestore = true
    static let dropAndRebuildOnReplay = true
    static let dropAndRebuildAfterDelete = true
    static let excludesSubjectIdentity = true
    static let excludesSourceBytes = true
    static let excludesPrivateLocators = true
    static let excludesActorIdentity = true
    static let excludesComponentInputs = true
    static let excludesUnsupportedClaims = true

    static func accepts(_ field: PlanPlacementSearchFieldV1) -> Bool {
        fieldIDs.contains(field.rawValue)
    }

    static func validate(_ record: PlanPlacementSearchRecordV1) throws {
        try record.validate()
        guard metadataOnly, derivedOnly, normalizedCoordinatesOnly,
              dropAndRebuildAfterRestore, dropAndRebuildOnReplay,
              dropAndRebuildAfterDelete, excludesSubjectIdentity,
              excludesSourceBytes, excludesPrivateLocators,
              excludesActorIdentity, excludesComponentInputs,
              excludesUnsupportedClaims else {
            throw SearchContractFailureV1.forbiddenField
        }
    }
}

// MARK: - C19 current plan-document search projection

/// One disposable row per current plan-document tip. Unlike the placement
/// projection, this row exists even when the current plan revision has no
/// placements. Currentness is established only by the canonical-history
/// rebuild route; a historic-open selection cannot construct this value.
enum PlanDocumentSearchFieldV1: String, CaseIterable, Codable, Hashable, Sendable {
    case workspaceID = "plan_document_workspace_id"
    case planDocumentID = "plan_document_current_id"
    case stablePlanKey = "plan_document_stable_key"
    case displayName = "plan_document_display_name"
    case documentState = "plan_document_current_state"
    case documentRevision = "plan_document_current_revision"
    case documentSHA256 = "plan_document_current_sha256"
    case planRevisionID = "plan_content_current_revision_id"
    case revisionState = "plan_content_current_state"
    case planRevision = "plan_content_current_revision"
    case revisionSHA256 = "plan_content_current_sha256"
    case contentID = "plan_content_id"
    case mediaType = "plan_content_media_type"
    case contentSHA256 = "plan_content_sha256"
    case fieldReferenceReleaseID = "plan_content_release_id"
    case fieldReferenceReleaseRevision = "plan_content_release_revision"
    case fieldReferenceReleaseSHA256 = "plan_content_release_sha256"
    case currentPlacementCount = "plan_current_placement_count"
}

struct PlanOfflineReadinessSearchMetadataV1: Codable, Equatable, Hashable, Comparable, Sendable {
    let workspaceID: WorkspaceID
    let manifestID: UUID
    let packetID: UUID
    let packetVersion: UInt64
    let manifestSHA256: String
    let itemID: String
    let itemKind: WorkPacketItemKindV1
    let itemExpectedRevision: UInt64
    let itemSHA256: String
    let planRevision: PlanRevisionReferenceV1
    let revisionDisposition: PlanRevisionSelectionDispositionV1
    let sourceSnapshotSHA256: String
    let findingCodes: [PlanOfflineReadinessFindingCodeV1]

    init(_ value: OfflineWorkPacketReadinessV1) throws {
        try value.validateIntrinsic()
        guard value.applicability != .notApplicable,
              let exactPlanRevision = value.planRevision,
              value.contentBinding != nil,
              value.fieldReference != nil,
              value.openability != nil,
              let exactRevisionDisposition = value.revisionDisposition else {
            throw SearchContractFailureV1.scopeMismatch
        }
        workspaceID = value.workspaceID
        manifestID = value.packet.manifestID
        packetID = value.packet.packetID
        packetVersion = value.packet.packetVersion
        manifestSHA256 = value.packet.manifestSHA256
        itemID = value.item.itemID
        itemKind = value.item.itemKind
        itemExpectedRevision = value.item.expectedRevision
        itemSHA256 = value.item.itemSHA256
        planRevision = exactPlanRevision
        revisionDisposition = exactRevisionDisposition
        sourceSnapshotSHA256 = value.sourceSnapshotSHA256
        findingCodes = Array(Set(value.findings.map(\.code))).sorted {
            $0.rawValue < $1.rawValue
        }
        try validate()
    }

    func validate() throws {
        try planRevision.validate()
        try PlanOfflineWorkLimitsV1.id(manifestID)
        try PlanOfflineWorkLimitsV1.id(packetID)
        try PlanOfflineWorkLimitsV1.text(itemID)
        try PlanOfflineWorkLimitsV1.digest(manifestSHA256)
        try PlanOfflineWorkLimitsV1.digest(itemSHA256)
        try PlanOfflineWorkLimitsV1.digest(sourceSnapshotSHA256)
        guard workspaceID.rawValue != SearchContractValidationV1.zeroUUID,
              packetVersion > 0, itemExpectedRevision > 0,
              findingCodes == findingCodes.sorted(by: { $0.rawValue < $1.rawValue }),
              Set(findingCodes).count == findingCodes.count else {
            throw SearchContractFailureV1.invalidField
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.packetID.uuidString, lhs.packetVersion, lhs.itemID, lhs.sourceSnapshotSHA256) <
            (rhs.packetID.uuidString, rhs.packetVersion, rhs.itemID, rhs.sourceSnapshotSHA256)
    }
}

struct PlanWorkSurfacePageSearchMetadataV1: Codable, Equatable, Hashable, Comparable, Sendable {
    let pageID: UUID
    let presentedPageOrdinal: Int
    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.presentedPageOrdinal, lhs.pageID.uuidString) <
            (rhs.presentedPageOrdinal, rhs.pageID.uuidString)
    }
}

struct PlanWorkSurfacePlacementSearchMetadataV1: Codable, Equatable, Hashable, Comparable, Sendable {
    let placementID: UUID
    let revision: UInt64
    let placementSHA256: String
    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.placementID.uuidString, lhs.revision, lhs.placementSHA256) <
            (rhs.placementID.uuidString, rhs.revision, rhs.placementSHA256)
    }
}

struct PlanWorkSurfaceSearchMetadataV1: Codable, Equatable, Hashable, Comparable, Sendable {
    let workspaceID: WorkspaceID
    let manifestID: UUID
    let packetID: UUID
    let packetVersion: UInt64
    let manifestSHA256: String
    let itemID: String
    let itemKind: WorkPacketItemKindV1
    let itemExpectedRevision: UInt64
    let itemSHA256: String
    let planRevision: PlanRevisionReferenceV1
    let pages: [PlanWorkSurfacePageSearchMetadataV1]
    let placements: [PlanWorkSurfacePlacementSearchMetadataV1]
    let poseEvents: [AssetPoseEventReferenceV1]
    let stateSHA256: String

    init(_ value: PlanWorkSurfaceStateV1) throws {
        try value.validateIntrinsic()
        workspaceID = value.workspaceID
        manifestID = value.packet.manifestID
        packetID = value.packet.packetID
        packetVersion = value.packet.packetVersion
        manifestSHA256 = value.packet.manifestSHA256
        itemID = value.item.itemID
        itemKind = value.item.itemKind
        itemExpectedRevision = value.item.expectedRevision
        itemSHA256 = value.item.itemSHA256
        planRevision = value.planRevision
        pages = value.pages.map {
            .init(pageID: $0.page.pageID,
                  presentedPageOrdinal: $0.page.presentedPageOrdinal)
        }.sorted()
        placements = value.placements.map {
            .init(placementID: $0.placement.placementID,
                  revision: $0.placement.revision,
                  placementSHA256: $0.placement.placementSHA256)
        }.sorted()
        poseEvents = value.poseSnapshots.map(\.event).sorted {
            ($0.eventID.uuidString, $0.axisID.rawValue, $0.revision, $0.eventSHA256) <
                ($1.eventID.uuidString, $1.axisID.rawValue, $1.revision, $1.eventSHA256)
        }
        stateSHA256 = value.stateSHA256
        try validate()
    }

    func validate() throws {
        try planRevision.validate()
        try PlanOfflineWorkLimitsV1.id(manifestID)
        try PlanOfflineWorkLimitsV1.id(packetID)
        try PlanOfflineWorkLimitsV1.text(itemID)
        try PlanOfflineWorkLimitsV1.digest(manifestSHA256)
        try PlanOfflineWorkLimitsV1.digest(itemSHA256)
        try PlanOfflineWorkLimitsV1.digest(stateSHA256)
        try pages.forEach { try PlanOfflineWorkLimitsV1.id($0.pageID) }
        try poseEvents.forEach { try $0.validate() }
        try placements.forEach {
            try PlanOfflineWorkLimitsV1.id($0.placementID)
            try PlanOfflineWorkLimitsV1.digest($0.placementSHA256)
        }
        guard workspaceID.rawValue != SearchContractValidationV1.zeroUUID,
              packetVersion > 0, itemExpectedRevision > 0,
              pages.allSatisfy({ $0.presentedPageOrdinal >= 0 }),
              pages == pages.sorted(), Set(pages.map(\.pageID)).count == pages.count,
              placements == placements.sorted(),
              placements.allSatisfy({ $0.revision > 0 }),
              Set(placements.map(\.placementID)).count == placements.count,
              poseEvents == poseEvents.sorted(by: {
                  ($0.eventID.uuidString, $0.axisID.rawValue, $0.revision, $0.eventSHA256) <
                      ($1.eventID.uuidString, $1.axisID.rawValue, $1.revision, $1.eventSHA256)
              }), Set(poseEvents).count == poseEvents.count else {
            throw SearchContractFailureV1.invalidField
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.packetID.uuidString, lhs.packetVersion, lhs.itemID, lhs.stateSHA256) <
            (rhs.packetID.uuidString, rhs.packetVersion, rhs.itemID, rhs.stateSHA256)
    }
}

struct PlanDocumentSearchRecordV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let workspaceID: WorkspaceID
    let planDocumentID: UUID
    let stablePlanKey: String
    let displayName: String
    let documentState: PlanDocumentStateV1
    let documentRevision: UInt64
    let documentSHA256: String
    let planRevisionID: UUID
    let revisionState: PlanRevisionStateV1
    let planRevision: UInt64
    let revisionSHA256: String
    let contentID: String
    let mediaType: String
    let contentSHA256: String
    let fieldReferenceReleaseID: UUID
    let fieldReferenceReleaseRevision: UInt64
    let fieldReferenceReleaseSHA256: String
    let currentPlacementCount: Int
    let offlineReadiness: [PlanOfflineReadinessSearchMetadataV1]
    let workSurfaces: [PlanWorkSurfaceSearchMetadataV1]
    let normalizedTokens: [String]

    init(
        currentDocument: PlanDocumentV1,
        currentRevision: PlanRevisionV1,
        currentPlacementCount: Int,
        offlineReadiness: [PlanOfflineReadinessSearchMetadataV1] = [],
        workSurfaces: [PlanWorkSurfaceSearchMetadataV1] = []
    ) throws {
        try currentDocument.validateIntrinsic()
        try currentRevision.validateIntrinsic()
        guard currentDocument.workspaceID == currentRevision.workspaceID,
              currentDocument.planDocumentID == currentRevision.planDocument.planDocumentID,
              currentPlacementCount >= 0,
              currentPlacementCount <= PlanLimitsV1.maximumPlacements else {
            throw SearchContractFailureV1.scopeMismatch
        }
        schemaVersion = Self.schemaVersion
        workspaceID = currentDocument.workspaceID
        planDocumentID = currentDocument.planDocumentID
        stablePlanKey = currentDocument.stablePlanKey
        displayName = currentDocument.displayName
        documentState = currentDocument.state
        documentRevision = currentDocument.revision
        documentSHA256 = currentDocument.documentSHA256
        planRevisionID = currentRevision.planRevisionID
        revisionState = currentRevision.state
        planRevision = currentRevision.revision
        revisionSHA256 = currentRevision.revisionSHA256
        contentID = currentRevision.contentBinding.contentID
        mediaType = currentRevision.contentBinding.mediaType
        contentSHA256 = currentRevision.contentBinding.contentSHA256
        fieldReferenceReleaseID = currentRevision.contentBinding.fieldReferenceReleaseID
        fieldReferenceReleaseRevision = currentRevision.contentBinding.fieldReferenceReleaseRevision
        fieldReferenceReleaseSHA256 = currentRevision.contentBinding.fieldReferenceReleaseSHA256
        self.currentPlacementCount = currentPlacementCount
        self.offlineReadiness = offlineReadiness.sorted()
        self.workSurfaces = workSurfaces.sorted()
        normalizedTokens = Self.tokens(
            workspaceID: workspaceID,
            planDocumentID: planDocumentID,
            stablePlanKey: stablePlanKey,
            displayName: displayName,
            documentState: documentState,
            planRevisionID: planRevisionID,
            revisionState: revisionState,
            contentID: contentID,
            mediaType: mediaType,
            offlineReadiness: self.offlineReadiness,
            workSurfaces: self.workSurfaces
        )
        try validate()
    }

    var projectionIdentity: String {
        "plan-document:\(workspaceID.rawValue.uuidString.lowercased()):\(planDocumentID.uuidString.lowercased())"
    }

    var boundedFieldValues: [PlanDocumentSearchFieldV1: String] {
        [
            .workspaceID: workspaceID.rawValue.uuidString.lowercased(),
            .planDocumentID: planDocumentID.uuidString.lowercased(),
            .stablePlanKey: stablePlanKey,
            .displayName: displayName,
            .documentState: documentState.rawValue,
            .documentRevision: String(documentRevision),
            .documentSHA256: documentSHA256,
            .planRevisionID: planRevisionID.uuidString.lowercased(),
            .revisionState: revisionState.rawValue,
            .planRevision: String(planRevision),
            .revisionSHA256: revisionSHA256,
            .contentID: contentID,
            .mediaType: mediaType,
            .contentSHA256: contentSHA256,
            .fieldReferenceReleaseID: fieldReferenceReleaseID.uuidString.lowercased(),
            .fieldReferenceReleaseRevision: String(fieldReferenceReleaseRevision),
            .fieldReferenceReleaseSHA256: fieldReferenceReleaseSHA256,
            .currentPlacementCount: String(currentPlacementCount),
        ]
    }

    func validate() throws {
        try PlanLimitsV1.token(stablePlanKey)
        try PlanLimitsV1.token(displayName)
        try PlanLimitsV1.token(contentID)
        try PlanLimitsV1.token(mediaType)
        guard schemaVersion == Self.schemaVersion,
              workspaceID.rawValue != SearchContractValidationV1.zeroUUID,
              planDocumentID != SearchContractValidationV1.zeroUUID,
              planRevisionID != SearchContractValidationV1.zeroUUID,
              fieldReferenceReleaseID != SearchContractValidationV1.zeroUUID,
              documentRevision > 0, planRevision > 0,
              fieldReferenceReleaseRevision > 0,
              currentPlacementCount >= 0,
              currentPlacementCount <= PlanLimitsV1.maximumPlacements,
              offlineReadiness == offlineReadiness.sorted(),
              Set(offlineReadiness).count == offlineReadiness.count,
              workSurfaces == workSurfaces.sorted(),
              Set(workSurfaces).count == workSurfaces.count,
              offlineReadiness.allSatisfy({
                  $0.workspaceID == workspaceID && $0.planRevision.planRevisionID == planRevisionID
                      && $0.planRevision.revision == planRevision
                      && $0.planRevision.revisionSHA256 == revisionSHA256
                      && $0.revisionDisposition == .current
              }),
              workSurfaces.allSatisfy({
                  $0.workspaceID == workspaceID && $0.planRevision.planRevisionID == planRevisionID
                      && $0.planRevision.revision == planRevision
                      && $0.planRevision.revisionSHA256 == revisionSHA256
              }),
              KernelCanonicalHashV1.validSHA256(documentSHA256),
              KernelCanonicalHashV1.validSHA256(revisionSHA256),
              KernelCanonicalHashV1.validSHA256(contentSHA256),
              KernelCanonicalHashV1.validSHA256(fieldReferenceReleaseSHA256),
              normalizedTokens.count <= SearchContractLimitsV1.maximumQueryTokens,
              normalizedTokens == normalizedTokens.sorted(),
              SearchContractValidationV1.normalizedTokensAreCanonical(normalizedTokens),
              boundedFieldValues.count == PlanDocumentSearchFieldV1.allCases.count else {
            throw SearchContractFailureV1.invalidField
        }
        try offlineReadiness.forEach { try $0.validate() }
        try workSurfaces.forEach { try $0.validate() }
    }

    private static func tokens(
        workspaceID: WorkspaceID,
        planDocumentID: UUID,
        stablePlanKey: String,
        displayName: String,
        documentState: PlanDocumentStateV1,
        planRevisionID: UUID,
        revisionState: PlanRevisionStateV1,
        contentID: String,
        mediaType: String,
        offlineReadiness: [PlanOfflineReadinessSearchMetadataV1],
        workSurfaces: [PlanWorkSurfaceSearchMetadataV1]
    ) -> [String] {
        let values = [displayName, stablePlanKey, contentID, mediaType,
                      documentState.rawValue, revisionState.rawValue,
                      planDocumentID.uuidString, planRevisionID.uuidString,
                      workspaceID.rawValue.uuidString]
            + offlineReadiness.flatMap {
                [$0.itemID, $0.itemKind.rawValue, $0.packetID.uuidString]
                    + $0.findingCodes.map(\.rawValue)
            }
            + workSurfaces.flatMap {
                [$0.itemID, $0.itemKind.rawValue, $0.packetID.uuidString]
            }
        var seen: Set<String> = []
        var bounded: [String] = []
        for token in values.flatMap({ value in
            SearchContractValidationV1.normalizeSearchText(value)
                .split { !CharacterSet.alphanumerics.contains($0) }
                .map(String.init)
        }) where seen.insert(token).inserted {
            guard bounded.count < SearchContractLimitsV1.maximumQueryTokens else { break }
            bounded.append(token)
        }
        return bounded.sorted()
    }
}

enum PlanDocumentSearchProjectionPolicyV1 {
    static let sourceKind = "PLAN_DOCUMENT_CURRENT_TIP"
    static let semanticLabel = "PLAN_DOCUMENT_CURRENT_METADATA_V1"
    static let fieldIDs = PlanDocumentSearchFieldV1.allCases.map(\.rawValue).sorted()
    static let derivedOnly = true
    static let currentTipsOnly = true
    static let includesZeroPlacementDocuments = true
    static let historicOpenSelectionIsNeverCurrent = true
    static let absentPlanAndNotApplicableItemsAreExcluded = true
    static let offlineReadinessBooleanIsNeverIndexed = true
    static let dropAndRebuildAfterRestoreReplayDelete = true
    static let excludesSourceBytesActorsPrivateLocatorsAndUnsupportedClaims = true

    static func validate(_ record: PlanDocumentSearchRecordV1) throws {
        try record.validate()
        guard derivedOnly, currentTipsOnly, includesZeroPlacementDocuments,
              historicOpenSelectionIsNeverCurrent,
              absentPlanAndNotApplicableItemsAreExcluded,
              offlineReadinessBooleanIsNeverIndexed,
              dropAndRebuildAfterRestoreReplayDelete,
              excludesSourceBytesActorsPrivateLocatorsAndUnsupportedClaims else {
            throw SearchContractFailureV1.forbiddenField
        }
    }
}

// MARK: - C37 current placement-pose search projection

/// Search is limited to the current qualified tip per axis. Full immutable
/// pose history remains a report/timeline concern, while index rows carry only
/// stable IDs, reference frame, disposition, reason, and revision metadata.
enum C37PoseSearchFieldV1: String, CaseIterable, Codable, Hashable, Sendable {
    case workspaceID = "pose_workspace_id"
    case assetID = "pose_asset_id"
    case eventID = "pose_event_id"
    case axisID = "pose_axis_id"
    case referenceFrame = "pose_reference_frame"
    case disposition = "pose_disposition"
    case observationState = "pose_observation_state"
    case notObservedReason = "pose_not_observed_reason"
    case revision = "pose_revision"
    case projectionSHA256 = "pose_projection_sha256"
}

struct C37PoseSearchRecordV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let workspaceID: UUID
    let assetID: UUID
    let eventID: UUID
    let axisID: String
    let referenceFrame: C37PoseReferenceFrameProjectionV1
    let disposition: PoseObservationDispositionV1
    let observationState: C37PoseObservationStateV1
    let notObservedReason: PoseNotObservedReasonV1?
    let revision: UInt64
    let projectionSHA256: String
    let normalizedTokens: [String]

    init(
        projection: C37PlacementPoseReportProjectionV1,
        row: C37PoseHistoryProjectionV1
    ) throws {
        try C37PoseReportProjectionPolicyV1.validate(projection)
        try row.validate()
        guard projection.history.contains(row),
              projection.currentTipReferences.contains(where: {
                  $0.eventID == row.eventID
                      && $0.axisID.rawValue == row.axisID
                      && $0.revision == row.revision
                      && $0.eventSHA256 == row.eventSHA256
              }) else {
            throw SearchContractFailureV1.scopeMismatch
        }
        schemaVersion = Self.schemaVersion
        workspaceID = projection.workspaceID.rawValue
        assetID = projection.assetID
        eventID = row.eventID
        axisID = row.axisID
        referenceFrame = row.referenceFrame
        disposition = row.disposition
        observationState = row.observationState
        notObservedReason = row.notObservedReason
        revision = row.revision
        projectionSHA256 = projection.projectionSHA256
        normalizedTokens = Self.tokens(
            workspaceID: workspaceID,
            assetID: assetID,
            eventID: eventID,
            axisID: axisID,
            referenceFrame: referenceFrame,
            disposition: disposition,
            observationState: observationState,
            notObservedReason: notObservedReason,
            revision: revision,
            projectionSHA256: projectionSHA256
        )
        try validate()
    }

    var projectionIdentity: String {
        "pose-current:\(workspaceID.uuidString.lowercased()):\(assetID.uuidString.lowercased()):\(axisID)"
    }

    var boundedFieldValues: [C37PoseSearchFieldV1: String] {
        [
            .workspaceID: workspaceID.uuidString.lowercased(),
            .assetID: assetID.uuidString.lowercased(),
            .eventID: eventID.uuidString.lowercased(),
            .axisID: axisID,
            .referenceFrame: referenceFrame.rawValue,
            .disposition: disposition.rawValue,
            .observationState: observationState.rawValue,
            .notObservedReason: notObservedReason?.rawValue ?? "NONE",
            .revision: String(revision),
            .projectionSHA256: projectionSHA256,
        ]
    }

    func validate() throws {
        let zero = SearchContractValidationV1.zeroUUID
        guard schemaVersion == Self.schemaVersion,
              workspaceID != zero, assetID != zero, eventID != zero,
              SearchContractValidationV1.validID(axisID),
              disposition == PoseObservationDispositionV1(rawValue: disposition.rawValue),
              observationState == C37PoseObservationStateV1(rawValue: observationState.rawValue),
              revision > 0,
              KernelCanonicalHashV1.validSHA256(projectionSHA256),
              (disposition == .notObserved) == (notObservedReason != nil),
              boundedFieldValues.count == C37PoseSearchFieldV1.allCases.count,
              normalizedTokens.count <= SearchContractLimitsV1.maximumQueryTokens,
              normalizedTokens == normalizedTokens.sorted(),
              SearchContractValidationV1.normalizedTokensAreCanonical(normalizedTokens),
              boundedFieldValues.values.allSatisfy({ value in
                  let parts = SearchContractValidationV1.normalizeSearchText(value)
                      .split { !CharacterSet.alphanumerics.contains($0) }
                      .map(String.init)
                  return !parts.isEmpty
                      && parts.allSatisfy(SearchContractValidationV1.isCanonicalSearchToken)
              }) else {
            throw SearchContractFailureV1.invalidField
        }
        guard C37PoseSearchProjectionPolicyV1.metadataOnly,
              C37PoseSearchProjectionPolicyV1.currentTipsOnly,
              C37PoseSearchProjectionPolicyV1.historyRemainsReportOnly,
              C37PoseSearchProjectionPolicyV1.derivedOnly else {
            throw SearchContractFailureV1.forbiddenField
        }
    }

    private static func tokens(
        workspaceID: UUID, assetID: UUID, eventID: UUID, axisID: String,
        referenceFrame: C37PoseReferenceFrameProjectionV1,
        disposition: PoseObservationDispositionV1,
        observationState: C37PoseObservationStateV1,
        notObservedReason: PoseNotObservedReasonV1?, revision: UInt64,
        projectionSHA256: String
    ) -> [String] {
        let values = [
            workspaceID.uuidString, assetID.uuidString, eventID.uuidString,
            axisID, referenceFrame.rawValue, disposition.rawValue,
            observationState.rawValue, notObservedReason?.rawValue ?? "NONE",
            String(revision), projectionSHA256,
        ]
        return Array(Set(values.flatMap { value in
            SearchContractValidationV1.normalizeSearchText(value)
                .split { !CharacterSet.alphanumerics.contains($0) }
                .map(String.init)
        })).sorted()
    }
}

enum C37PoseSearchProjectionPolicyV1 {
    static let sourceKind = "POSE_CURRENT"
    static let semanticLabel = "C37_POSE_CURRENT_METADATA_V1"
    static let fieldIDs = C37PoseSearchFieldV1.allCases.map(\.rawValue).sorted()
    static let metadataOnly = true
    static let currentTipsOnly = true
    static let historyRemainsReportOnly = true
    static let derivedOnly = true
    static let dropAndRebuildAfterRestore = true
    static let dropAndRebuildOnReplay = true
    static let dropAndRebuildAfterDelete = true
    static let excludesAngles = true
    static let excludesActorIdentity = true
    static let excludesSensorStream = true
    static let excludesPrivateLocators = true
    static let excludesSourceBytes = true
    static let excludesUnsupportedClaims = true

    static func validate(_ record: C37PoseSearchRecordV1) throws {
        try record.validateWithoutProjectionResolution()
        guard metadataOnly, currentTipsOnly, historyRemainsReportOnly, derivedOnly,
              dropAndRebuildAfterRestore, dropAndRebuildOnReplay,
              dropAndRebuildAfterDelete, excludesAngles, excludesActorIdentity,
              excludesSensorStream, excludesPrivateLocators, excludesSourceBytes,
              excludesUnsupportedClaims else {
            throw SearchContractFailureV1.forbiddenField
        }
    }
}

private extension C37PoseSearchRecordV1 {
    func validateWithoutProjectionResolution() throws {
        let zero = SearchContractValidationV1.zeroUUID
        guard schemaVersion == Self.schemaVersion,
              workspaceID != zero, assetID != zero, eventID != zero,
              SearchContractValidationV1.validID(axisID), revision > 0,
              KernelCanonicalHashV1.validSHA256(projectionSHA256),
              (disposition == .notObserved) == (notObservedReason != nil),
              boundedFieldValues.count == C37PoseSearchFieldV1.allCases.count,
              normalizedTokens.count <= SearchContractLimitsV1.maximumQueryTokens,
              normalizedTokens == normalizedTokens.sorted(),
              SearchContractValidationV1.normalizedTokensAreCanonical(normalizedTokens) else {
            throw SearchContractFailureV1.invalidField
        }
    }
}

// MARK: - C30 operating-context search projection

/// Disposable search metadata for a frozen C30 projection.  It contains only
/// bounded identity/state tokens; context notes, coordinates, timestamps,
/// images, actor references, and source bytes remain outside the index.
struct C30OperatingContextSearchRecordV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let workspaceID: WorkspaceID
    let assetID: UUID
    let evidenceID: String
    let contextID: UUID
    let contextRevision: UInt64
    let observedCondition: EvidenceLightingConditionV1
    let expectedControlState: ExpectedControlStateV1?
    let pairedDisposition: C30PairedComparisonDispositionV1
    let pairedMismatchReasons: [PairedObservationMismatchReasonV1]
    let normalizedTokens: [String]
    let projectionSHA256: String

    init(_ projection: C30EvidenceContextReportReferenceV1) throws {
        try projection.validate()
        schemaVersion = Self.schemaVersion
        workspaceID = projection.workspaceID
        assetID = projection.assetID
        evidenceID = projection.evidenceID
        contextID = projection.contextID
        contextRevision = projection.contextRevision
        observedCondition = projection.observedCondition
        expectedControlState = projection.expectedControlState
        pairedDisposition = projection.pairedObservation?.disposition ?? .notLinked
        pairedMismatchReasons = projection.pairedObservation?.mismatchReasons ?? []
        normalizedTokens = Self.tokens(for: projection)
        projectionSHA256 = projection.contextSHA256
        try validate()
    }

    private static func tokens(
        for projection: C30EvidenceContextReportReferenceV1
    ) -> [String] {
        var values = [
            projection.evidenceID,
            projection.contextID.uuidString,
            projection.assetID.uuidString,
            projection.observedCondition.rawValue,
            projection.pairedObservation?.purpose.rawValue ?? "NOT_LINKED",
        ]
        if let expected = projection.expectedControlState {
            values.append(expected.rawValue)
        }
        values.append(contentsOf: projection.pairedObservation?.mismatchReasons.map(\.rawValue) ?? [])
        return Array(Set(values.flatMap { token in
            SearchContractValidationV1.normalizeSearchText(token)
                .split { !CharacterSet.alphanumerics.contains($0) }
                .map(String.init)
                .filter(SearchContractValidationV1.isCanonicalSearchToken)
        })).sorted()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              workspaceID != SearchContractValidationV1.zeroUUID,
              assetID != SearchContractValidationV1.zeroUUID,
              contextID != SearchContractValidationV1.zeroUUID,
              SearchContractValidationV1.validID(evidenceID),
              contextRevision > 0,
              SearchContractValidationV1.normalizedTokensAreCanonical(normalizedTokens),
              KernelCanonicalHashV1.validSHA256(projectionSHA256),
              pairedMismatchReasons == pairedMismatchReasons.sorted(),
              Set(pairedMismatchReasons).count == pairedMismatchReasons.count else {
            throw SearchContractFailureV1.invalidField
        }
    }
}

enum C30OperatingContextSearchPolicyV1 {
    static let metadataOnly = true
    static let currentFrozenProjectionOnly = true
    static let timestampsAndNotesExcluded = true
    static let imageAndSourceBytesExcluded = true
    static let actorAndLocationExcluded = true
    static let expectedControlIsNotActual = true
    static let dropAndRebuildAfterRestoreReplayDelete = true
    static let searchableFields = [
        "evidence_id", "asset_id", "context_id", "condition",
        "expected_control_state", "paired_disposition", "paired_mismatch_reason",
        "context_revision", "projection_sha256",
    ]

    static func validate(_ record: C30OperatingContextSearchRecordV1) throws {
        guard metadataOnly, currentFrozenProjectionOnly,
              timestampsAndNotesExcluded, imageAndSourceBytesExcluded,
              actorAndLocationExcluded, expectedControlIsNotActual,
              dropAndRebuildAfterRestoreReplayDelete else {
            throw SearchContractFailureV1.forbiddenField
        }
        try record.validate()
    }
}
// C30: this seam consumes only the frozen, metadata-only operating-context projection.
enum C30ConsumerBoundaryV1_Domain_Search_SearchContractsV1 {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Domain/Search/SearchContractsV1.swift", role: .search)
}

// MARK: - C31 lighting search projection

/// Search receives only a derived summary of the frozen lighting projection.
/// Source bytes, notes, actor identity, private locators, and safety claims do
/// not enter the local index.
struct C31LightingSearchRecordV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let workspaceID: WorkspaceID
    let systemID: UUID
    let systemRevision: UInt64
    let systemSHA256: String
    let zoneCount: Int
    let controlGroupCount: Int
    let luminaireCount: Int
    let observationCount: Int
    let issueCount: Int
    let measurementPlanCount: Int
    let claimCount: Int
    let claimBoundary: C31LightingClaimBoundaryV1
    let claimTiers: [LightingClaimTierV1]
    let issueKinds: [LightingIssueKindV1]

    init(projection: C31LightingReportProjectionV1) throws {
        try C31LightingProjectionPolicyV1.validate(projection)
        schemaVersion = Self.schemaVersion
        workspaceID = projection.workspaceID
        systemID = projection.systemID
        systemRevision = projection.systemRevision
        systemSHA256 = projection.systemSHA256
        zoneCount = projection.zoneCount
        controlGroupCount = projection.controlGroupCount
        luminaireCount = projection.luminaireCount
        observationCount = projection.observationCount
        issueCount = projection.issueCount
        measurementPlanCount = projection.measurementPlanCount
        claimCount = projection.claimCount
        claimBoundary = projection.claimBoundary
        claimTiers = projection.claimTiers
        issueKinds = projection.issueKinds
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              systemID != SearchContractValidationV1.zeroUUID,
              systemRevision > 0,
              KernelCanonicalHashV1.validSHA256(systemSHA256),
              [zoneCount, controlGroupCount, luminaireCount, observationCount,
               issueCount, measurementPlanCount, claimCount].allSatisfy({ $0 >= 0 }),
              claimTiers == claimTiers.sorted(by: { $0.rawValue < $1.rawValue }),
              issueKinds == issueKinds.sorted(),
              Set(issueKinds).count == issueKinds.count else {
            throw SearchContractFailureV1.invalidField
        }
    }
}

enum C31LightingSearchProjectionPolicyV1 {
    static let metadataOnly = true
    static let localOnly = true
    static let derivedFromFrozenProjection = true
    static let dropAndRebuildAfterRestoreReplayDelete = true
    static let excludesSourceBytesNotesActorsAndPrivateLocators = true
    static let excludesOperationalSafetySecurityComplianceClaims = true
    static let searchableFields = [
        "system_id", "system_revision", "system_sha256", "zone_count",
        "control_group_count", "luminaire_count", "observation_count",
        "issue_count", "measurement_plan_count", "claim_count",
        "claim_boundary", "claim_tier", "issue_kind",
    ]

    static func validate(_ record: C31LightingSearchRecordV1) throws {
        guard metadataOnly, localOnly, derivedFromFrozenProjection,
              dropAndRebuildAfterRestoreReplayDelete,
              excludesSourceBytesNotesActorsAndPrivateLocators,
              excludesOperationalSafetySecurityComplianceClaims else {
            throw SearchContractFailureV1.forbiddenField
        }
        try record.validate()
    }
}

// MARK: - C32 assistance search isolation

enum AssistanceSearchIsolationPolicyV1 {
    static let proposalIsSearchable = false
    static let acceptanceReceiptIsSearchable = false
    static let acceptedCanonicalTargetUsesExistingProjection = true

    static func mayIndex(_ proposal: AssistanceProposalV1) throws -> Bool {
        try proposal.validate()
        return false
    }

    static func mayIndex(_ receipt: AssistanceAcceptanceReceiptV1) throws -> Bool {
        try receipt.validate()
        return false
    }
}


// MARK: - C33 temporal evidence search metadata

struct TemporalEvidenceSearchRecordV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let workspaceID: WorkspaceID
    let clipID: UUID
    let clipRevision: UInt64
    let clipSHA256: String
    let mediaKind: TemporalEvidenceMediaKindV1
    let durationMilliseconds: UInt64
    let accessibleDescription: String
    let anchorLabels: [String]
    let includesTranscript: Bool

    init(clip: TemporalEvidenceClipV1, anchors: [TimecodedEvidenceAnchorV1]) throws {
        try clip.validateIntrinsic(); try anchors.forEach { try $0.validate(clip: clip) }
        schemaVersion = Self.schemaVersion; workspaceID = clip.workspaceID
        clipID = clip.clipID; clipRevision = clip.revision; clipSHA256 = clip.clipSHA256
        mediaKind = clip.facts.kind; durationMilliseconds = clip.facts.durationMilliseconds
        accessibleDescription = clip.accessibleDescription
        anchorLabels = anchors.map(\.label).sorted()
        includesTranscript = clip.manualTranscript?.isEmpty == false
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion, clipID != .zero, clipRevision > 0,
              MutationEnvelopeV1.isSHA256(clipSHA256), durationMilliseconds > 0,
              accessibleDescription.utf8.count <= 4_096,
              anchorLabels == anchorLabels.sorted(),
              anchorLabels.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 256 }) else {
            throw TemporalEvidenceContractFailureV1.invalidValue
        }
    }
}

enum TemporalEvidenceSearchProjectionPolicyV1 {
    static let metadataOnly = true
    static let excludesOriginalBytes = true
    static let excludesPrivateLocators = true
    static let excludesTranscriptBody = true

    static func validate(_ record: TemporalEvidenceSearchRecordV1) throws {
        try record.validate()
        guard metadataOnly, excludesOriginalBytes, excludesPrivateLocators,
              excludesTranscriptBody else { throw SearchContractFailureV1.forbiddenField }
    }
}

struct AcceptedLabelSearchMetadataV1: Equatable, Sendable {
    let workspaceID: UUID
    let snapshotID: UUID
    let planID: UUID
    let assetIDs: [UUID]
    let snapshotSHA256: String
    let disposition: AcceptedLabelSnapshotDispositionV1

    init(_ snapshot: AcceptedLabelGenerationSnapshotV1) throws {
        try snapshot.validate()
        workspaceID = snapshot.workspaceID.rawValue
        snapshotID = snapshot.snapshotID
        planID = snapshot.plan.planID
        assetIDs = snapshot.plan.items.map(\.assetID).sorted { $0.uuidString < $1.uuidString }
        snapshotSHA256 = snapshot.snapshotSHA256
        disposition = snapshot.disposition
    }
}

enum C45AcceptedLabelSearchBoundaryV1 { static let acceptedSnapshotMetadataIsSearchSource=true;static let labelTextAndShortCodesAreExcluded=true }

enum C46OperationalContactBoundary_33{static let permittedProjection="PARTY_METADATA_ONLY";static let rawPhoneOrEmailIndexed=false}

enum C47ActivityContractConformance_FieldEvidenceApp_Domain_Search_SearchContractsV1_swift {
    static let integrationRole = "SEARCH_READ_EXPORT_UNKNOWN_KIND_WITHOUT_MUTATION"
    static let sharedReceipt = SharedActivityEnvelopeReceiptV1.self
    static let installationReceipt = InstallationActivityContractReceiptV1.self
    static let punchReceipt = PunchActivityContractReceiptV1.self
    static let explicitNoPlanFallback = NoPlanFallbackV1.self
    static let usesSoleWorkspaceWriter = true
    static let createsSecondRendererStoreOrRoute = false
    static let inspectionStorageAliasingAllowed = false
    static let planOrScanRequired = false
    static let approvalComplianceCertificationClaimAllowed = false
    static func validateReadable(_ envelope: ActivitySessionEnvelopeV2) throws {
        try envelope.validateForRead()
    }
}

/// Derived C47 metadata only. Unknown activity kinds remain visible for read/export,
/// while mutation continues to fail in ActivityKindV2.requireKnownForMutation().
struct ActivityContractSearchProjectionV2: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID
    let activityID: UUID
    let kind: ActivityKindV2
    let state: ActivityStateV2
    let title: String
    let revision: UInt64
    let envelopeSHA256: String
    let completedSnapshotReference: CompletedActivitySnapshotV2CompatibilityReferenceV1?
    let sourceCloseoutSHA256: String?
    let targetCloseoutSHA256: String?
    let installationCloseout: InstallationCloseoutV1?
    let punchReviewCloseout: PunchReviewCloseoutV1?
    let closeoutKind: String?
    let closeoutDisposition: String?
    let closeoutSHA256: String?
    let recordedFindingCount: Int
    let reviewedScopeItemCount: Int

    init(envelope: ActivitySessionEnvelopeV2) throws {
        try envelope.validateForRead()
        workspaceID = envelope.workspaceID
        activityID = envelope.activityID
        kind = envelope.kind
        state = envelope.state
        title = envelope.title
        revision = envelope.revision
        envelopeSHA256 = envelope.envelopeSHA256
        completedSnapshotReference = envelope.completedSnapshotReference
        sourceCloseoutSHA256 = envelope.completedSnapshotReference?.sourceCloseoutSHA256
        targetCloseoutSHA256 = envelope.completedSnapshotReference?.targetCloseoutSHA256
        installationCloseout = envelope.installationCloseout
        punchReviewCloseout = envelope.punchReviewCloseout
        if let closeout = envelope.installationCloseout {
            closeoutKind = "INSTALLATION"
            closeoutDisposition = closeout.completion.rawValue
            closeoutSHA256 = closeout.closeoutSHA256
            recordedFindingCount = closeout.openFindings.count
            reviewedScopeItemCount = 0
        } else if let closeout = envelope.punchReviewCloseout {
            closeoutKind = "PUNCH_REVIEW"
            closeoutDisposition = closeout.completion.rawValue
            closeoutSHA256 = closeout.closeoutSHA256
            recordedFindingCount = closeout.scope.reduce(0) { $0 + $1.findingLinks.count }
            reviewedScopeItemCount = closeout.scope.count
        } else {
            closeoutKind = nil
            closeoutDisposition = nil
            closeoutSHA256 = nil
            recordedFindingCount = 0
            reviewedScopeItemCount = 0
        }
    }

    static let includesEvidenceAnswersActorIdentityOrPrivateLocators = false
    static let indexesFindingStatusDueDateOrSeverity = false
    static let cloneForkSourceAndTargetSnapshotIdentityRemainDistinct = true
}

// MARK: - C48 portable-review derived search boundary

enum C48PortableReviewSearchBoundaryV1 {
    static let derivedMetadataType = C48PortableReviewDerivedHistoryProjectionV1.self
    static let indexedFieldIDs = C48PortableReviewDerivedHistoryProjectionV1.allowedFieldIDs
    static let currentStateAndHistoryMayBeRead = true
    static let capabilityBytesIndexed = false
    static let capabilityProofBytesIndexed = false
    static let responseBodyIndexed = false
    static let rawRequestResponseBytesIndexed = false
    static let workspaceAndReplicaIdentityIndexed = false
    static let authorIdentityIndexed = false
    static let deliveryOrApprovalClaimIndexed = false
    static let responseHistoryIsNotMutationAuthority = true

    static func validate(_ projection: C48PortableReviewDerivedHistoryProjectionV1) throws {
        try projection.validate()
    }

    static func derivedHistory(
        state: ReviewRequestStateProjectionV1,
        response: ExternalReviewResponseRecordV1? = nil,
        conflictCount: Int = 0
    ) throws -> C48PortableReviewDerivedHistoryProjectionV1 {
        try .init(state: state, response: response, conflictCount: conflictCount)
    }
}

// MARK: - C49 work-resource search projection

struct C49WorkResourceSearchProjectionV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID
    let recordIDs: [UUID]
    let terms: [String]
    let projectionSHA256: String

    init(projection: C49WorkResourceReportProjectionV1) throws {
        try C49WorkResourceProjectionSupportV1.validate(projection)
        workspaceID = projection.workspaceID
        recordIDs = projection.sourceRecordIDs
        terms = Array(Set(projection.materials.flatMap { [$0.description, $0.unit].compactMap { $0 } })).sorted()
        projectionSHA256 = projection.projectionSHA256
    }

    func validate() throws {
        guard recordIDs == recordIDs.sorted(by: { $0.uuidString < $1.uuidString }),
              Set(recordIDs).count == recordIDs.count,
              terms == terms.sorted(), Set(terms).count == terms.count,
              projectionSHA256.count == 64 else {
            throw C49WorkResourceProjectionFailureV1.nonCanonical
        }
    }
}

enum C49WorkResourceSearchBoundaryV1 {
    static let indexUsesDerivedMetadataOnly = true
    static let sourceBytesIndexed = false
    static let liveInventoryRowsIndexed = false

    static func projection(
        _ report: C49WorkResourceReportProjectionV1
    ) throws -> C49WorkResourceSearchProjectionV1 {
        let value = try C49WorkResourceSearchProjectionV1(projection: report)
        try value.validate()
        return value
    }
}


// MARK: - C50 incumbent file-exchange search exclusion

enum C50IncumbentFileExchangeSearchBoundaryV1 {
    static let closedAdapterFieldSet = Set(IncumbentCanonicalFieldV1.allCases)
    static let projectionType = IncumbentAdapterProjectionV1.self
    static let adapterSessionIndexedFieldIDs: [String] = []
    static let sourceOrQuarantineBytesIndexed = false
    static let externalKeysPathsOrAvailabilityIndexed = false
    static let selectedProfileEvidenceIndexed = false
    static let canonicalTargetRowsRemainOwnedByExistingSearchProjections = true

    static func validate() -> Bool {
        !closedAdapterFieldSet.isEmpty
            && adapterSessionIndexedFieldIDs.isEmpty
            && !sourceOrQuarantineBytesIndexed
            && !externalKeysPathsOrAvailabilityIndexed
            && !selectedProfileEvidenceIndexed
            && canonicalTargetRowsRemainOwnedByExistingSearchProjections
    }
}

enum C34SearchRouteSemanticIDAdapterV1 {
    static let routeAnchorType = RouteSearchAnchorV1.self
    static let routeStoresQueryText = false

    static func anchor(from session: SearchSessionStateV1) throws -> RouteSearchAnchorV1 {
        try RouteSearchAnchorV1(sanitizing: session)
    }
}

enum C34RouteAdoptionBoundary_SearchContractsV1 {
    static let searchAnchorType = RouteSearchAnchorV1.self
    static let canonicalTargetType = NavigationTargetV1.self
    static let routeStoresQueryText = false
}

enum C52ServiceRequestBoundary_SearchContractsV1 {
    static let sourceKind: ServiceRequestSourceKindV1 = .portableSubmission
    static let requestBodyType: ServiceRequestSubmissionBodyV1.Type = ServiceRequestSubmissionBodyV1.self
    static let permittedCurrentNonSensitiveFields: [String] = [
        "REQUEST_TEXT", "CATEGORY", "STATED_DATE", "URGENCY_ASSERTION",
        "REQUESTER_ASSERTION_STATUS", "CONTACT_ASSERTION_STATUS"
    ]
    static let requesterAssertionIsVerifiedIdentity: Bool = false
    static let contactAssertionIsVerifiedIdentity: Bool = false
    static let rawCapabilityBytesIndexed: Bool = false
    static let immutableSourceBytesIndexed: Bool = false
    static let dispositionProvenanceIndexed: Bool = false
    static let workLinkProvenanceIndexed: Bool = false
    static let hiddenDuplicateScoresIndexed: Bool = false
    static let duplicateProjectionIsSearchable: Bool = false
}

// MARK: - C53 service-reliability derived search projection

struct C53ServiceReliabilitySearchProjectionV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let workspaceID: WorkspaceID
    let subjectID: UUID
    let reliabilityIdentityEpochID: UUID
    let sourceProjectionSHA256: String
    let availabilityQualification: String
    let mtbfQualification: String
    let mttrQualification: String
    let includedSourceEventCount: Int
    let excludedSourceCount: Int
    let exactAvailabilityIndexed: Bool
    let exactMTBFIndexed: Bool
    let exactMTTRIndexed: Bool
    let normalizedTokens: [String]

    init(projection: C53ServiceReliabilityReportProjectionV1) throws {
        try projection.validate()
        schemaVersion = Self.schemaVersion
        workspaceID = projection.workspaceID
        subjectID = projection.subjectID
        reliabilityIdentityEpochID = projection.reliabilityIdentityEpochID
        sourceProjectionSHA256 = projection.sourceProjectionSHA256
        availabilityQualification = Self.qualificationText(projection.availabilityQualification)
        mtbfQualification = Self.qualificationText(projection.mtbfQualification)
        mttrQualification = Self.qualificationText(projection.mttrQualification)
        includedSourceEventCount = projection.includedSourceEventIDs.count
        excludedSourceCount = projection.excludedSources.count
        // Search exposes qualification state only; exact metric values never
        // become query tokens or derived search truth.
        exactAvailabilityIndexed = false
        exactMTBFIndexed = false
        exactMTTRIndexed = false
        normalizedTokens = Self.tokens(
            availabilityQualification,
            mtbfQualification,
            mttrQualification,
            includedSourceEventCount > 0 ? "sources-present" : "sources-none",
            excludedSourceCount > 0 ? "sources-excluded" : "sources-complete"
        )
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              SearchContractValidationV1.validID(subjectID.uuidString),
              SearchContractValidationV1.validID(reliabilityIdentityEpochID.uuidString),
              MutationEnvelopeV1.isSHA256(sourceProjectionSHA256),
              includedSourceEventCount >= 0,
              excludedSourceCount >= 0,
              !exactAvailabilityIndexed,
              !exactMTBFIndexed,
              !exactMTTRIndexed,
              normalizedTokens == normalizedTokens.sorted(),
              SearchContractValidationV1.normalizedTokensAreCanonical(normalizedTokens) else {
            throw SearchContractFailureV1.invalidField
        }
    }

    private static func qualificationText(
        _ value: ServiceReliabilityQualificationV1
    ) -> String {
        switch value {
        case .qualified:
            return "qualified"
        case .unavailable(let reason):
            return "unavailable-" + reason.rawValue.lowercased()
        }
    }

    private static func tokens(_ values: String...) -> [String] {
        Array(Set(values.flatMap {
            SearchContractValidationV1.normalizeSearchText($0)
                .split { !CharacterSet.alphanumerics.contains($0) }
                .map(String.init)
        })).sorted()
    }
}

enum C53ServiceReliabilitySearchProjectionBoundaryV1 {
    static let sourceIsCanonicalMetricInput = true
    static let indexIsDerivedAndDisposable = true
    static let exactMetricValuesAreNotSearchable = true
    static let rawEventBytesAreNotSearchable = true
    static let actorAndEvidenceLocatorValuesAreNotSearchable = true

    static func projection(
        _ report: C53ServiceReliabilityReportProjectionV1
    ) throws -> C53ServiceReliabilitySearchProjectionV1 {
        let value = try C53ServiceReliabilitySearchProjectionV1(projection: report)
        try value.validate()
        return value
    }
}

// MARK: - C57 My Day disposable search projection

struct C57MyDaySearchRecordV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let workspaceID: WorkspaceID
    let planKeySHA256: String
    let planRevision: UInt64
    let membershipID: UUID
    let sourceKind: String
    let sourceStableKeySHA256: String
    let sourceClosureSHA256: String
    let sourceFrontierSHA256: String
    let reportProjectionSHA256: String
    let sourceState: MyDaySourceStateV1
    let readiness: MyDayReadinessV1
    let hasDueAt: Bool
    let hasEstimate: Bool
    let normalizedTokens: [String]

    var projectionIdentity: String {
        "\(workspaceID.rawValue.uuidString.lowercased())|\(planKeySHA256)|\(membershipID.uuidString.lowercased())"
    }

    init(report: C57MyDayReportProjectionV1,
         item: C57MyDayReportItemProjectionV1) throws {
        try report.validate(); try item.validate()
        guard report.items.contains(item) else { throw SearchContractFailureV1.scopeMismatch }
        schemaVersion = Self.schemaVersion
        workspaceID = report.workspaceID
        planKeySHA256 = report.plan.key.keySHA256
        planRevision = report.plan.revision
        membershipID = item.membershipID
        sourceKind = item.referenceStableKey.split(separator: "|", maxSplits: 1)
            .first.map(String.init) ?? ""
        sourceStableKeySHA256 = KernelCanonicalHashV1.sha256(Data(item.referenceStableKey.utf8))
        sourceClosureSHA256 = report.sourceClosureSHA256
        sourceFrontierSHA256 = item.sourceFrontierSHA256
        reportProjectionSHA256 = report.projectionSHA256
        sourceState = item.sourceState
        readiness = item.readiness
        hasDueAt = item.dueAt != nil
        hasEstimate = item.estimateWholeMinutes != nil
        normalizedTokens = Self.tokens(
            "my day", sourceKind, sourceState.rawValue, readiness.rawValue,
            hasDueAt ? "due date" : "no due date",
            hasEstimate ? "estimated" : "no estimate"
        )
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              SearchContractValidationV1.validID(projectionIdentity),
              Self.allowedSourceKinds.contains(sourceKind),
              planRevision > 0,
              membershipID != SearchContractValidationV1.zeroUUID,
              MutationEnvelopeV1.isSHA256(planKeySHA256),
              MutationEnvelopeV1.isSHA256(sourceStableKeySHA256),
              MutationEnvelopeV1.isSHA256(sourceClosureSHA256),
              MutationEnvelopeV1.isSHA256(sourceFrontierSHA256),
              MutationEnvelopeV1.isSHA256(reportProjectionSHA256),
              normalizedTokens == normalizedTokens.sorted(),
              normalizedTokens == Self.tokens(
                  "my day",
                  sourceKind,
                  sourceState.rawValue, readiness.rawValue,
                  hasDueAt ? "due date" : "no due date",
                  hasEstimate ? "estimated" : "no estimate"
              ),
              SearchContractValidationV1.normalizedTokensAreCanonical(normalizedTokens) else {
            throw SearchContractFailureV1.invalidField
        }
    }

    private static func tokens(_ values: String...) -> [String] {
        Array(Set(values.flatMap {
            SearchContractValidationV1.normalizeSearchText($0)
                .split { !CharacterSet.alphanumerics.contains($0) }
                .map(String.init)
        })).sorted()
    }

    private static let allowedSourceKinds: Set<String> = [
        "WORK_PACKET", "ROUND_SESSION", "SCHEDULE_OCCURRENCE", "RESUMABLE_DRAFT",
    ]
}

enum C57MyDaySearchProjectionBoundaryV1 {
    static let rowsAreDerivedAndDisposable = true
    static let sourceStateReadinessAndDueAreNeverCanonicalSearchTruth = true
    static let sourceFrontierClosureIsRequired = true
    static let searchRowsAreNeverWriterInputs = true

    static func records(from report: C57MyDayReportProjectionV1) throws
        -> [C57MyDaySearchRecordV1] {
        try report.validate()
        let values = try report.items.map { try C57MyDaySearchRecordV1(report: report, item: $0) }
        let sorted = values.sorted { $0.projectionIdentity < $1.projectionIdentity }
        guard Set(sorted.map(\.projectionIdentity)).count == sorted.count else {
            throw SearchContractFailureV1.duplicateProjection
        }
        return sorted
    }
}

// MARK: - C05 round-session disposable search projection

/// Search receives a small, rebuildable metadata projection. The canonical
/// session, item selections, reasons, content references, and actor snapshots
/// are never search rows or search tokens.
struct C05RoundSessionSearchProjectionV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let workspaceID: WorkspaceID
    let session: RoundSessionReferenceV1
    let state: RoundSessionStateV1
    let counts: RoundSessionCountsV1
    let sourceFrontierSHA256: String
    let progressProjectionSHA256: String
    let closeoutSHA256: String?
    let normalizedTokens: [String]
    let projectionSHA256: String

    init(
        progress: C05RoundSessionProgressReportProjectionV1,
        closeout: C05RoundSessionCloseoutReportProjectionV1?
    ) throws {
        try progress.validate()
        if let closeout {
            try closeout.validate()
            guard closeout.progress == progress else {
                throw SearchContractFailureV1.staleIndex
            }
        }
        guard (progress.state == .completed) == (closeout != nil) else {
            throw SearchContractFailureV1.staleIndex
        }
        schemaVersion = Self.schemaVersion
        workspaceID = progress.session.workspaceID
        session = progress.session
        state = progress.state
        counts = progress.counts
        sourceFrontierSHA256 = progress.sourceFrontierSHA256
        progressProjectionSHA256 = progress.projectionSHA256
        closeoutSHA256 = closeout?.closeoutSHA256
        normalizedTokens = Self.tokens(
            "round session",
            state.rawValue,
            "expected items",
            counts.completed > 0 ? "completed items" : "no completed items",
            closeout == nil ? "closeout unavailable" : "closeout recorded"
        )
        projectionSHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(
            schemaVersion: schemaVersion,
            workspaceID: workspaceID,
            session: session,
            state: state,
            counts: counts,
            sourceFrontierSHA256: sourceFrontierSHA256,
            progressProjectionSHA256: progressProjectionSHA256,
            closeoutSHA256: closeoutSHA256,
            normalizedTokens: normalizedTokens
        ))
        try validate()
    }

    func validate() throws {
        try session.validate()
        guard schemaVersion == Self.schemaVersion,
              workspaceID == session.workspaceID,
              sourceFrontierSHA256 == session.sessionSHA256,
              MutationEnvelopeV1.isSHA256(sourceFrontierSHA256),
              MutationEnvelopeV1.isSHA256(progressProjectionSHA256),
              closeoutSHA256.map(MutationEnvelopeV1.isSHA256) ?? true,
              (state == .completed) == (closeoutSHA256 != nil),
              C05RoundSessionCountValidationV1.validProgress(counts),
              normalizedTokens == Self.tokens(
                  "round session",
                  state.rawValue,
                  "expected items",
                  counts.completed > 0 ? "completed items" : "no completed items",
                  closeoutSHA256 == nil ? "closeout unavailable" : "closeout recorded"
              ),
              SearchContractValidationV1.normalizedTokensAreCanonical(normalizedTokens),
              projectionSHA256 == (try WorkspaceMutationCanonicalV1.sha256(basis)) else {
            throw SearchContractFailureV1.invalidField
        }
    }

    private static func tokens(_ values: String...) -> [String] {
        Array(Set(values.flatMap {
            SearchContractValidationV1.normalizeSearchText($0)
                .split { !CharacterSet.alphanumerics.contains($0) }
                .map(String.init)
        })).sorted()
    }

    private var basis: Basis {
        Basis(
            schemaVersion: schemaVersion,
            workspaceID: workspaceID,
            session: session,
            state: state,
            counts: counts,
            sourceFrontierSHA256: sourceFrontierSHA256,
            progressProjectionSHA256: progressProjectionSHA256,
            closeoutSHA256: closeoutSHA256,
            normalizedTokens: normalizedTokens
        )
    }

    private struct Basis: Codable {
        let schemaVersion: Int
        let workspaceID: WorkspaceID
        let session: RoundSessionReferenceV1
        let state: RoundSessionStateV1
        let counts: RoundSessionCountsV1
        let sourceFrontierSHA256: String
        let progressProjectionSHA256: String
        let closeoutSHA256: String?
        let normalizedTokens: [String]
    }
}

enum C05RoundSessionSearchProjectionBoundaryV1 {
    static let indexIsDerivedAndDisposable = true
    static let indexRowsAreNeverCanonicalWriterInputs = true
    static let rawContentOrLocatorValuesAreSearchable = false
    static let actorOrReasonValuesAreSearchable = false
    static let routeDueReminderOrTeamStateIsSearchable = false

    static func projection(
        progress: C05RoundSessionProgressReportProjectionV1,
        closeout: C05RoundSessionCloseoutReportProjectionV1?
    ) throws -> C05RoundSessionSearchProjectionV1 {
        let projection = try C05RoundSessionSearchProjectionV1(
            progress: progress,
            closeout: closeout
        )
        try projection.validate()
        return projection
    }
}

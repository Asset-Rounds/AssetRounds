import Foundation

enum LocalizationContractFailureV1: Error, Equatable, Sendable {
    case invalidValue
    case incompatibleVersion
    case duplicateKey
    case missingKey
    case missingComment
    case incompatibleKeyReuse
    case removedPublishedKey
    case invalidShippingLocale
    case pseudoLocaleDeclaredForShipping
    case duplicateSemanticID
    case invalidAccessibilityBinding
    case invalidOpaqueSuffix
    case legacyAllowlistGrowth
    case digestMismatch
    case packageReleaseMismatch
    case frozenDisplayChanged
    case partialPublication
}

struct LocalizationKeyV1: Codable, Equatable, Hashable, Comparable, Sendable {
    let rawValue: String

    init(_ rawValue: String) throws {
        guard Self.isValid(rawValue) else { throw LocalizationContractFailureV1.invalidValue }
        self.rawValue = rawValue
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    private static func isValid(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 200,
              value == value.lowercased(), value.first != ".", value.last != ".",
              !value.contains("..") else { return false }
        return value.utf8.allSatisfy {
            (0x61...0x7A).contains($0) || (0x30...0x39).contains($0)
                || $0 == 0x2E || $0 == 0x5F || $0 == 0x2D
        }
    }

    init(from decoder: any Decoder) throws {
        try self.init(decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum LocalizationMessageShapeV1: String, Codable, CaseIterable, Sendable {
    case plain = "PLAIN"
    case integerPlural = "INTEGER_PLURAL"
    case number = "NUMBER"
    case date = "DATE"
    case measurement = "MEASUREMENT"
}

enum LocalizationKeyStateV1: String, Codable, CaseIterable, Sendable {
    case active = "ACTIVE"
    case deprecated = "DEPRECATED"
}

enum TestOnlyPseudoLocaleV1: String, Codable, CaseIterable, Sendable {
    case accented = "en-XA"
    case doubleLength = "en-XB"
    case rightToLeft = "ar-XB"
    case long = "en-XL"
    case tall = "en-XT"

    static let shippingEnabled = false
}

struct LocalizationArgumentV1: Codable, Equatable, Sendable {
    let name: String
    let shape: LocalizationMessageShapeV1
}

struct LocalizationKeyDefinitionV1: Codable, Equatable, Sendable {
    let key: LocalizationKeyV1
    let meaningID: String
    let translatorComment: String
    let englishDefaultValue: String
    let arguments: [LocalizationArgumentV1]
    let requiredEnglishPluralCategories: [String]
    let state: LocalizationKeyStateV1
    let deprecatedFallbackKey: LocalizationKeyV1?

    func validate() throws {
        guard !meaningID.isEmpty, meaningID.utf8.count <= 200,
              !translatorComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              translatorComment == translatorComment.trimmingCharacters(in: .whitespacesAndNewlines),
              !englishDefaultValue.isEmpty, englishDefaultValue.utf8.count <= 2_000,
              arguments.map(\.name) == arguments.map(\.name).sorted(),
              Set(arguments.map(\.name)).count == arguments.count,
              arguments.allSatisfy({ !$0.name.isEmpty }),
              (requiredEnglishPluralCategories.isEmpty
               || requiredEnglishPluralCategories == ["one", "other"]),
              (requiredEnglishPluralCategories.isEmpty
               || arguments.contains(where: { $0.shape == .integerPlural })),
              deprecatedFallbackKey != key else {
            throw LocalizationContractFailureV1.invalidValue
        }
    }

    func validateSuccessor(of previous: Self) throws {
        try validate()
        try previous.validate()
        guard key == previous.key,
              meaningID == previous.meaningID,
              arguments == previous.arguments,
              requiredEnglishPluralCategories == previous.requiredEnglishPluralCategories,
              !(previous.state == .deprecated && state == .active),
              previous.deprecatedFallbackKey == nil
                || deprecatedFallbackKey == previous.deprecatedFallbackKey else {
            throw LocalizationContractFailureV1.incompatibleKeyReuse
        }
    }
}

struct LocalizationKeyRegistryV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let definitions: [LocalizationKeyDefinitionV1]

    init(definitions: [LocalizationKeyDefinitionV1]) throws {
        try definitions.forEach { try $0.validate() }
        let ordered = definitions.sorted { $0.key < $1.key }
        guard !ordered.isEmpty, ordered.count <= 4_096,
              Set(ordered.map(\.key)).count == ordered.count else {
            throw LocalizationContractFailureV1.duplicateKey
        }
        schemaVersion = Self.schemaVersion
        self.definitions = ordered
    }

    func definition(for key: LocalizationKeyV1) throws -> LocalizationKeyDefinitionV1 {
        guard let value = definitions.first(where: { $0.key == key }) else {
            throw LocalizationContractFailureV1.missingKey
        }
        return value
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              self == (try Self(definitions: definitions)) else {
            throw LocalizationContractFailureV1.incompatibleVersion
        }
    }

    func validateSuccessor(of previous: Self) throws {
        try validate()
        try previous.validate()
        for old in previous.definitions {
            guard let current = definitions.first(where: { $0.key == old.key }) else {
                throw LocalizationContractFailureV1.removedPublishedKey
            }
            try current.validateSuccessor(of: old)
        }
    }
}

struct LocalizationLocaleManifestV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let sourceLanguage: String
    let shippingRuntimeLanguages: [String]
    let completeCatalogLanguages: [String]
    let appStorePrimaryMetadataLocale: String
    let testOnlyPseudoLocaleIdentifiers: [String]

    static func shippingV1() -> Self {
        Self(
            schemaVersion: schemaVersion,
            sourceLanguage: "en",
            shippingRuntimeLanguages: ["en"],
            completeCatalogLanguages: ["en"],
            appStorePrimaryMetadataLocale: "en-US",
            testOnlyPseudoLocaleIdentifiers: TestOnlyPseudoLocaleV1.allCases
                .map(\.rawValue).sorted()
        )
    }

    func validate() throws {
        guard Set(shippingRuntimeLanguages).isDisjoint(with: testOnlyPseudoLocaleIdentifiers) else {
            throw LocalizationContractFailureV1.pseudoLocaleDeclaredForShipping
        }
        guard schemaVersion == Self.schemaVersion, sourceLanguage == "en",
              shippingRuntimeLanguages == ["en"], completeCatalogLanguages == ["en"],
              appStorePrimaryMetadataLocale == "en-US" else {
            throw LocalizationContractFailureV1.invalidShippingLocale
        }
    }
}

struct LocalizationCatalogReleaseV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let releaseSHA256: String
    let sourceCatalogSHA256: String
    let keyRegistrySHA256: String
    let localeManifestSHA256: String

    static func make(sourceCatalog: Data, registry: Data, localeManifest: Data) throws -> Self {
        guard !sourceCatalog.isEmpty, !registry.isEmpty, !localeManifest.isEmpty else {
            throw LocalizationContractFailureV1.invalidValue
        }
        let source = KernelCanonicalHashV1.sha256(sourceCatalog)
        let keys = KernelCanonicalHashV1.sha256(registry)
        let locales = KernelCanonicalHashV1.sha256(localeManifest)
        let release = KernelCanonicalHashV1.sha256(
            Data("1|\(source)|\(keys)|\(locales)".utf8)
        )
        return Self(
            schemaVersion: schemaVersion, releaseSHA256: release,
            sourceCatalogSHA256: source, keyRegistrySHA256: keys,
            localeManifestSHA256: locales
        )
    }

    func validateIdentity() throws {
        guard schemaVersion == Self.schemaVersion,
              KernelCanonicalHashV1.validSHA256(releaseSHA256),
              KernelCanonicalHashV1.validSHA256(sourceCatalogSHA256),
              KernelCanonicalHashV1.validSHA256(keyRegistrySHA256),
              KernelCanonicalHashV1.validSHA256(localeManifestSHA256),
              releaseSHA256 == KernelCanonicalHashV1.sha256(
                Data("1|\(sourceCatalogSHA256)|\(keyRegistrySHA256)|\(localeManifestSHA256)".utf8)
              ) else {
            throw LocalizationContractFailureV1.digestMismatch
        }
    }

    func validate(sourceCatalog: Data, registry: Data, localeManifest: Data) throws {
        try validateIdentity()
        guard self == (try Self.make(
            sourceCatalog: sourceCatalog, registry: registry, localeManifest: localeManifest
        )) else { throw LocalizationContractFailureV1.digestMismatch }
    }
}

struct PackageLocalizationSlotBindingV1: Codable, Equatable, Sendable {
    let slotID: String
    let localizationKey: LocalizationKeyV1
}

struct PackageLocalizationReleaseBindingV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let packageReleaseID: String
    let packageSHA256: String
    let workflowSHA256: String
    let localizationReleaseSHA256: String
    let sourceCatalogSHA256: String
    let keyRegistrySHA256: String
    let localeManifestSHA256: String
    let orderedSlotBindings: [PackageLocalizationSlotBindingV1]

    init(
        publication: InspectionPackagePublishedReleaseV1,
        localizationRelease: LocalizationCatalogReleaseV1,
        slotBindings: [PackageLocalizationSlotBindingV1],
        registry: LocalizationKeyRegistryV1
    ) throws {
        try publication.validate()
        try localizationRelease.validateIdentity()
        let ordered = slotBindings.sorted { $0.slotID < $1.slotID }
        let package = try InspectionPackageCanonicalCodecV2.decode(
            publication.release.canonicalPackageBytes
        )
        let expectedSlots = try package.advisoryGuidance.map {
            PackageLocalizationSlotBindingV1(
                slotID: "advisoryGuidance.\($0.guidanceID)",
                localizationKey: try LocalizationKeyV1($0.localizationKey)
            )
        }.sorted { $0.slotID < $1.slotID }
        guard localizationRelease.schemaVersion == LocalizationCatalogReleaseV1.schemaVersion,
              KernelCanonicalHashV1.validSHA256(localizationRelease.releaseSHA256),
              KernelCanonicalHashV1.validSHA256(localizationRelease.sourceCatalogSHA256),
              KernelCanonicalHashV1.validSHA256(localizationRelease.keyRegistrySHA256),
              KernelCanonicalHashV1.validSHA256(localizationRelease.localeManifestSHA256),
              Set(ordered.map(\.slotID)).count == ordered.count,
              ordered.allSatisfy({ !$0.slotID.isEmpty }),
              ordered == expectedSlots,
              try ordered.allSatisfy({ try registry.definition(for: $0.localizationKey).state == .active }) else {
            throw LocalizationContractFailureV1.invalidValue
        }
        schemaVersion = Self.schemaVersion
        packageReleaseID = publication.release.packageReleaseID
        packageSHA256 = publication.release.packageSHA256
        workflowSHA256 = publication.release.workflowSHA256
        localizationReleaseSHA256 = localizationRelease.releaseSHA256
        sourceCatalogSHA256 = localizationRelease.sourceCatalogSHA256
        keyRegistrySHA256 = localizationRelease.keyRegistrySHA256
        localeManifestSHA256 = localizationRelease.localeManifestSHA256
        orderedSlotBindings = ordered
    }

    func validate(
        publication: InspectionPackagePublishedReleaseV1,
        localizationRelease: LocalizationCatalogReleaseV1,
        registry: LocalizationKeyRegistryV1
    ) throws {
        let expected = try Self(
            publication: publication, localizationRelease: localizationRelease,
            slotBindings: orderedSlotBindings, registry: registry
        )
        guard self == expected else { throw LocalizationContractFailureV1.packageReleaseMismatch }
    }
}

struct FrozenDisplaySnapshotV1: Equatable, Sendable {
    let canonicalBytes: Data
    let sha256: String

    init(canonicalBytes: Data, sha256: String) throws {
        guard !canonicalBytes.isEmpty, KernelCanonicalHashV1.validSHA256(sha256),
              KernelCanonicalHashV1.sha256(canonicalBytes) == sha256 else {
            throw LocalizationContractFailureV1.digestMismatch
        }
        self.canonicalBytes = canonicalBytes
        self.sha256 = sha256
    }

    func validateUnchanged(canonicalBytes: Data, sha256: String) throws {
        guard self.canonicalBytes == canonicalBytes, self.sha256 == sha256 else {
            throw LocalizationContractFailureV1.frozenDisplayChanged
        }
    }

}

enum LocalizationContractCanonicalCodecV1 {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
}

enum LocalizationLifecycleV1 {
    static let mode = "DECLARATION_ONLY"
    static let persistent = false
    static let writerCommand = "NOT_APPLICABLE"
    static let canonicalQuery = "BUNDLED_IN_MEMORY_DECLARATION"
    static let migration = "NOT_APPLICABLE"
    static let backupRestore = "NOT_APPLICABLE"
    static let replaceRestore = "NOT_APPLICABLE"
    static let clone = "NOT_APPLICABLE"
    static let fork = "NOT_APPLICABLE"
    static let importDisposition = "BUNDLED_ONLY"
    static let exportDisposition = "EVIDENCE_ONLY"
    static let journal = "NOT_APPLICABLE"
    static let replay = "DETERMINISTIC_REBUILD_FROM_BUNDLE"
    static let search = "NOT_APPLICABLE"
    static let rebuild = "DETERMINISTIC_REBUILD_FROM_BUNDLE"
    static let delete = "NOT_APPLICABLE"
    static let erase = "NOT_APPLICABLE"
    static let retention = "PROCESS_LIFETIME_ONLY"
    static let compatibility = "IMMUTABLE_RELEASE_DIGEST_BINDING"
    static let downgrade = "DORMANT_REVERT_ALLOWED"
    static let forwardFix = "REPLACE_BUNDLED_DECLARATION"
    static let interruption = "ZERO_OR_COMPLETE"
    static let idempotentReceipt = "EXACT_CANONICAL_BYTES_ADOPTION"
}

/// The C38 report/search slice consumes only these additive localization
/// concepts.  Keeping the identifiers in the domain contract makes the
/// locale truth explicit without changing the published V1 key registry's
/// legacy default surface.
enum LocalizationAccountabilityPolicyV1 {
    static let semanticNamespace = "accountability"
    static let keyNamespace = "accountability"
    static let sourceLocale = "en"
    static let shippingLocale = "en"
    static let metadataLocale = "en-US"
    static let testOnlyLocales = TestOnlyPseudoLocaleV1.allCases.map(\.rawValue).sorted()
    static let excludesContactPoints = true
    static let excludesIdentityAndLegalClaims = true

    static let reportKeys = [
        "accountability.heading",
        "accountability.party",
        "accountability.role",
        "accountability.actor",
        "accountability.qualification",
        "accountability.signoff",
    ]
}

/// C39's semantic labels are a closed, typed English source surface.  The
/// semantic catalog owns the facts; these keys only describe how those facts
/// are presented to a local reader.  In particular, none of the state labels
/// is allowed to imply operational disposition, verification, or identity.
enum AssetSemanticLocalizationKeyV1: String, CaseIterable, Codable, Sendable {
    case illuminatedSignName = "asset.semantic.sign.illuminated.name"
    case illuminatedSignDescription = "asset.semantic.sign.illuminated.description"
    case heading = "asset.semantic.heading"
    case kind = "asset.semantic.kind"
    case productIdentity = "asset.semantic.product_identity"
    case workSubjectScope = "asset.semantic.work_subject_scope"
    case lifecycle = "asset.semantic.lifecycle"
    case state = "asset.semantic.state"
    case unknownState = "asset.semantic.state.unknown"
    case duplicateState = "asset.semantic.state.duplicate"
    case retiredState = "asset.semantic.state.retired"
    case replacedState = "asset.semantic.state.replaced"
    case recordedState = "asset.semantic.state.recorded"

    var localizationKey: LocalizationKeyV1 {
        // Every enum case is a repository-owned, syntactically valid key.
        // Construction is kept non-throwing for callers that already hold the
        // closed type; registry construction remains the validation boundary.
        // swiftlint:disable:next force_try
        try! LocalizationKeyV1(rawValue)
    }
}

enum AssetSemanticLocalizationPolicyV1 {
    static let semanticNamespace = "asset.semantic"
    static let sourceLocale = "en"
    static let shippingLocale = "en"
    static let metadataLocale = "en-US"
    static let testOnlyLocales = TestOnlyPseudoLocaleV1.allCases.map(\.rawValue).sorted()
    static let keys = AssetSemanticLocalizationKeyV1.allCases.map(\.rawValue)
    static let semanticIDs = AssetSemanticAccessibilityIDV1.allCases.map(\.rawValue)
    static let excludesOperationalDisposition = true
    static let excludesIdentityClaims = true
    static let progressivelyDisclosedProductIdentity = true
}

/// C40's authority and criterion labels are a closed English source surface.
/// They describe the recorded basis and screening disposition only; they do
/// not turn a source, result, or severity label into a legal, safety,
/// compliance, or professional claim.
enum AuthorityCriterionLocalizationKeyV1: String, CaseIterable, Codable, Sendable {
    case heading = "authority.criterion.heading"
    case authoritySource = "authority.criterion.authority_source"
    case applicability = "authority.criterion.applicability"
    case applicabilityApplicable = "authority.criterion.applicability.applicable"
    case applicabilityNotApplicableWithReason = "authority.criterion.applicability.not_applicable_with_reason"
    case applicabilityUnknown = "authority.criterion.applicability.unknown"
    case applicabilityConflictReviewRequired = "authority.criterion.applicability.conflict_review_required"
    case applicabilityUnsupported = "authority.criterion.applicability.unsupported"
    case criterionResult = "authority.criterion.result"
    case resultMeetsScreeningCriterion = "authority.criterion.result.meets_screening_criterion"
    case resultDoesNotMeet = "authority.criterion.result.does_not_meet"
    case resultInconclusive = "authority.criterion.result.inconclusive"
    case resultNotEvaluated = "authority.criterion.result.not_evaluated"
    case severity = "authority.criterion.severity"
    case measurementProtocol = "authority.criterion.measurement_protocol"
    case technicalBasis = "authority.criterion.technical_basis"
    case nextStep = "authority.criterion.next_step"
    case assessedAgainst = "authority.criterion.assessed_against"

    // Additive spelling aliases keep call sites readable without adding a
    // second raw key or a second catalog entry.
    static var result: Self { .criterionResult }
    static var applicable: Self { .applicabilityApplicable }
    static var notApplicableWithReason: Self { .applicabilityNotApplicableWithReason }
    static var unknown: Self { .applicabilityUnknown }
    static var conflictReviewRequired: Self { .applicabilityConflictReviewRequired }
    static var unsupported: Self { .applicabilityUnsupported }
    static var meetsScreeningCriterion: Self { .resultMeetsScreeningCriterion }
    static var doesNotMeet: Self { .resultDoesNotMeet }
    static var inconclusive: Self { .resultInconclusive }
    static var notEvaluated: Self { .resultNotEvaluated }

    var localizationKey: LocalizationKeyV1 {
        // Construction is non-throwing for this closed, repository-owned set;
        // registry construction remains the validation boundary.
        // swiftlint:disable:next force_try
        try! LocalizationKeyV1(rawValue)
    }
}

enum AuthorityCriterionLocalizationPolicyV1 {
    static let semanticNamespace = "authority.criterion"
    static let sourceLocale = "en"
    static let shippingLocale = "en"
    static let metadataLocale = "en-US"
    static let testOnlyLocales = TestOnlyPseudoLocaleV1.allCases.map(\.rawValue).sorted()
    static let keys = AuthorityCriterionLocalizationKeyV1.allCases.map(\.rawValue)
    static let semanticIDs = AuthorityCriterionAccessibilityIDV1.allCases.map(\.rawValue)
    static let reportKeys = [
        AuthorityCriterionLocalizationKeyV1.authoritySource.rawValue,
        AuthorityCriterionLocalizationKeyV1.applicability.rawValue,
        AuthorityCriterionLocalizationKeyV1.criterionResult.rawValue,
        AuthorityCriterionLocalizationKeyV1.severity.rawValue,
        AuthorityCriterionLocalizationKeyV1.measurementProtocol.rawValue,
        AuthorityCriterionLocalizationKeyV1.technicalBasis.rawValue,
        AuthorityCriterionLocalizationKeyV1.assessedAgainst.rawValue,
        AuthorityCriterionLocalizationKeyV1.nextStep.rawValue,
    ]
    static let requiredReportWording = "assessed against"
    static let excludesLicensedSourceText = true
    static let excludesRawMeasurementSamples = true
    static let excludesPrivateLocators = true
    static let excludesQualificationDetail = true
    static let excludesUnsupportedClaims = true
    static let requiresNonColorStateText = true
    static let requiresTextAndIconForIndeterminateStates = true
    static let requiresActionableNextStep = true
    static let allowsColorOnlySeverity = false
    static let allowsIconOnlyState = false
    static let excludesLegalSafetyComplianceClaims = true
    static let textIconActionableNextStepRequired = true

    /// Claim words are tokenized, not substring-matched, so a harmless word
    /// such as "safely" cannot accidentally be treated as the prohibited
    /// app-origin claim "safe".
    static let prohibitedClaimTokens: Set<String> = [
        "ahj", "certified", "compliant", "safe", "legal", "professional",
    ]

    static func containsProhibitedClaim(in values: [String]) -> Bool {
        values.contains { value in
            let tokens = value.lowercased().split { !$0.isLetter && !$0.isNumber }
            return tokens.contains { prohibitedClaimTokens.contains(String($0)) }
        }
    }
}

extension AuthorityCriterionLocalizationKeyV1 {
    static func applicabilityKey(_ disposition: ApplicabilityDispositionV1) -> Self {
        switch disposition {
        case .applicable: return .applicabilityApplicable
        case .notApplicableWithReason: return .applicabilityNotApplicableWithReason
        case .unknown: return .applicabilityUnknown
        case .conflictReviewRequired: return .applicabilityConflictReviewRequired
        case .unsupported: return .applicabilityUnsupported
        }
    }

    static func resultKey(_ result: ScreeningCriterionResultV1) -> Self {
        switch result {
        case .meetsScreeningCriterion: return .resultMeetsScreeningCriterion
        case .doesNotMeet: return .resultDoesNotMeet
        case .inconclusive: return .resultInconclusive
        case .notEvaluated: return .resultNotEvaluated
        }
    }
}

/// C41's functional-relationship labels are a closed, English-only display
/// surface.  The relationship contract owns the recorded topology facts;
/// these keys only give local readers stable text for those facts.
enum FunctionalRelationshipLocalizationKeyV1: String, CaseIterable, Codable, Sendable {
    case heading = "functional.relationship.heading"
    case type = "functional.relationship.type"
    case directedSourceToTarget = "functional.relationship.direction.source_to_target"
    case symmetric = "functional.relationship.direction.symmetric"
    case activeState = "functional.relationship.state.active"
    case endedState = "functional.relationship.state.ended"
    case supersededState = "functional.relationship.state.superseded"
    case incompleteState = "functional.relationship.state.incomplete"
    case blockedState = "functional.relationship.state.blocked"
    case minimumNextRequirement = "functional.relationship.next_step.minimum_requirement"
    case descriptor = "functional.relationship.descriptor"
    case bounds = "functional.relationship.bounds"
    case site = "functional.relationship.site"
    case crossSiteState = "functional.relationship.site.cross_site"

    // Additive aliases keep the closed surface discoverable for callers that
    // name the displayed concept rather than the compact enum case.
    static var relationshipHeading: Self { .heading }
    static var relationshipType: Self { .type }
    static var directed: Self { .directedSourceToTarget }
    static var active: Self { .activeState }
    static var ended: Self { .endedState }
    static var superseded: Self { .supersededState }
    static var incomplete: Self { .incompleteState }
    static var blocked: Self { .blockedState }
    static var minimumNextStepRequirement: Self { .minimumNextRequirement }
    static var cardinalityBounds: Self { .bounds }
    static var sitePolicy: Self { .site }
    static var crossSite: Self { .crossSiteState }

    var localizationKey: LocalizationKeyV1 {
        // Construction is non-throwing for this closed repository-owned set;
        // registry construction remains the validation boundary.
        // swiftlint:disable:next force_try
        try! LocalizationKeyV1(rawValue)
    }
}

enum FunctionalRelationshipLocalizationPolicyV1 {
    static let semanticNamespace = "functional.relationship"
    static let sourceLocale = "en"
    static let shippingLocale = "en"
    static let metadataLocale = "en-US"
    static let testOnlyLocales = TestOnlyPseudoLocaleV1.allCases.map(\.rawValue).sorted()
    static let keys = FunctionalRelationshipLocalizationKeyV1.allCases.map(\.rawValue)
    static let semanticIDs = FunctionalRelationshipAccessibilityIDV1.allCases.map(\.rawValue)
    static let reportKeys = FunctionalRelationshipLocalizationKeyV1.allCases.map(\.rawValue)

    static let directionTextRequired = true
    static let stateTextRequired = true
    static let excludesOwnershipClaims = true
    static let excludesAuthorizationClaims = true
    static let excludesComplianceClaims = true
    static let excludesSafetyClaims = true
    static let excludesTelemetryClaims = true
    static let excludesRemoteClaims = true
    static let requiresNonColorStateText = true
    static let requiresTextAndIconForIndeterminateStates = true
    static let requiresActionableNextStep = true
    static let allowsColorOnlyState = false
    static let allowsIconOnlyState = false

    /// Claim words are tokenized so a harmless word such as "safely" does not
    /// accidentally become a prohibited relationship claim.
    static let prohibitedClaimTokens: Set<String> = [
        "owner", "owners", "owned", "ownership",
        "authorize", "authorized", "authorization",
        "compliance", "compliant",
        "safety", "safe",
        "telemetry", "telemetric",
        "remote", "remotely",
    ]

    static func containsProhibitedClaim(in values: [String]) -> Bool {
        values.contains { value in
            let tokens = value.lowercased().split { !$0.isLetter && !$0.isNumber }
            return tokens.contains { prohibitedClaimTokens.contains(String($0)) }
        }
    }
}

/// A named vocabulary alias keeps privacy tests and report consumers from
/// coupling to the authority-criterion claim vocabulary.
enum FunctionalRelationshipClaimVocabularyV1 {
    static let prohibitedTokens = FunctionalRelationshipLocalizationPolicyV1.prohibitedClaimTokens

    static func containsProhibitedClaim(in values: [String]) -> Bool {
        FunctionalRelationshipLocalizationPolicyV1.containsProhibitedClaim(in: values)
    }
}

extension FunctionalRelationshipLocalizationKeyV1 {
    static func directionLocalizationKey(_ direction: FunctionalRelationshipDirectionV1) -> Self {
        directionKey(direction)
    }

    static func directionKey(_ direction: FunctionalRelationshipDirectionV1) -> Self {
        switch direction {
        case .directed: return .directedSourceToTarget
        case .undirected: return .symmetric
        }
    }

    static func symmetryLocalizationKey(_ symmetry: FunctionalRelationshipSymmetryV1) -> Self {
        symmetryKey(symmetry)
    }

    static func symmetryKey(_ symmetry: FunctionalRelationshipSymmetryV1) -> Self {
        switch symmetry {
        case .asymmetric: return .directedSourceToTarget
        case .symmetric: return .symmetric
        }
    }

    static func stateKey(_ action: AssetFunctionalRelationshipEventActionV1) -> Self {
        eventStateKey(action)
    }

    static func eventStateKey(_ action: AssetFunctionalRelationshipEventActionV1) -> Self {
        switch action {
        case .added: return .activeState
        case .ended: return .endedState
        case .superseded: return .supersededState
        }
    }

    static func stateKey(_ state: FunctionalRelationshipReadinessStateV1) -> Self {
        readinessStateKey(state)
    }

    static func readinessStateKey(_ state: FunctionalRelationshipReadinessStateV1) -> Self {
        switch state {
        case .ready: return .activeState
        case .incomplete: return .incompleteState
        }
    }

    static func stateKey(_ disposition: FunctionalRelationshipDispositionV1) -> Self {
        dispositionStateKey(disposition)
    }

    static func dispositionStateKey(_ disposition: FunctionalRelationshipDispositionV1) -> Self {
        switch disposition {
        case .retain: return .activeState
        case .end: return .endedState
        case .supersede: return .supersededState
        case .reviewRequired, .denied: return .blockedState
        }
    }

    static func siteLocalizationKey(_ policy: FunctionalRelationshipSitePolicyV1) -> Self {
        sitePolicyKey(policy)
    }

    static func sitePolicyKey(_ policy: FunctionalRelationshipSitePolicyV1) -> Self {
        switch policy {
        case .sameSiteRequired: return .site
        case .crossSiteLocalAllowed: return .crossSiteState
        }
    }

    static func nextStepKey(
        _ boundary: FunctionalRelationshipReadinessBoundaryV1
    ) -> Self {
        minimumRequirementKey(boundary)
    }

    static func minimumRequirementKey(
        _ boundary: FunctionalRelationshipReadinessBoundaryV1
    ) -> Self {
        // Every named readiness boundary uses the same localized next-step
        // wording; the boundary's machine value remains a recorded fact.
        switch boundary {
        case .atomicCreationBundle, .readiness, .finalization:
            return .minimumNextRequirement
        }
    }
}

/// C13's evidence-assurance labels are a closed English-only presentation
/// surface.  The assurance contracts retain the durable audience, sensitivity,
/// inclusion, preview, manifest, and attestation values; these keys describe
/// only how those recorded values are presented to a local reader.
enum EvidenceVisibilityLocalizationKeyV1: String, CaseIterable, Codable, Sendable {
    case heading = "evidence.visibility.heading"
    case audience = "evidence.visibility.audience"
    case audienceInternalReview = "evidence.visibility.audience.internal_review"
    case audienceCustomerReport = "evidence.visibility.audience.customer_report"
    case audienceExternalCollaborator = "evidence.visibility.audience.external_collaborator"
    case sensitivity = "evidence.visibility.sensitivity"
    case sensitivityRoutine = "evidence.visibility.sensitivity.routine"
    case sensitivityRestricted = "evidence.visibility.sensitivity.restricted"
    case sensitivityHighlyRestricted = "evidence.visibility.sensitivity.highly_restricted"
    case included = "evidence.visibility.state.included"
    case excluded = "evidence.visibility.state.excluded"
    case omitted = "evidence.visibility.state.omitted"
    case limitation = "evidence.visibility.state.limitation"
    case unknown = "evidence.visibility.state.unknown"
    case preview = "evidence.visibility.preview"
    case previewReady = "evidence.visibility.preview.ready"
    case previewStale = "evidence.visibility.preview.stale"
    case manifest = "evidence.visibility.manifest"
    case attestation = "evidence.visibility.attestation"
    case attestationPurpose = "evidence.visibility.attestation.purpose"
    case attestationRecorded = "evidence.visibility.attestation.recorded"
    case attestationSuperseded = "evidence.visibility.attestation.superseded"
    case attestationVoid = "evidence.visibility.attestation.void"
    case nextStep = "evidence.visibility.next_step"

    // Additive aliases keep the closed key set discoverable by the contract
    // name used by callers without introducing another catalog entry.
    static var visibilityHeading: Self { .heading }
    static var audienceInternal: Self { .audienceInternalReview }
    static var audienceCustomer: Self { .audienceCustomerReport }
    static var audienceExternal: Self { .audienceExternalCollaborator }
    static var routineSensitivity: Self { .sensitivityRoutine }
    static var highlyRestrictedSensitivity: Self { .sensitivityHighlyRestricted }
    static var includedState: Self { .included }
    static var excludedState: Self { .excluded }
    static var omittedState: Self { .omitted }
    static var limitationState: Self { .limitation }
    static var unknownState: Self { .unknown }
    static var readyPreview: Self { .previewReady }
    static var stalePreview: Self { .previewStale }
    static var assuranceManifest: Self { .manifest }
    static var attestationStateRecorded: Self { .attestationRecorded }
    static var attestationStateSuperseded: Self { .attestationSuperseded }
    static var attestationStateVoid: Self { .attestationVoid }
    static var actionableNextStep: Self { .nextStep }

    var localizationKey: LocalizationKeyV1 {
        // The enum is repository-owned and closed; registry construction is
        // still the validation boundary for serialized declarations.
        // swiftlint:disable:next force_try
        try! LocalizationKeyV1(rawValue)
    }
}

/// Compatibility names for callers that use the assurance or manifest
/// vocabulary while retaining one canonical CaseIterable key surface.
typealias EvidenceAssuranceLocalizationKeyV1 = EvidenceVisibilityLocalizationKeyV1
typealias AssuranceManifestLocalizationKeyV1 = EvidenceVisibilityLocalizationKeyV1

enum EvidencePreviewLocalizationStateV1: String, CaseIterable, Codable, Sendable {
    case ready = "READY"
    case stale = "STALE"
}

typealias EvidenceAssurancePreviewStateV1 = EvidencePreviewLocalizationStateV1

enum EvidenceVisibilityLocalizationPolicyV1 {
    static let semanticNamespace = "evidence.visibility"
    static let sourceLocale = "en"
    static let shippingLocale = "en"
    static let metadataLocale = "en-US"
    static let testOnlyLocales = TestOnlyPseudoLocaleV1.allCases.map(\.rawValue).sorted()
    static let keys = EvidenceVisibilityLocalizationKeyV1.allCases.map(\.rawValue)
    static let reportKeys = EvidenceVisibilityLocalizationKeyV1.allCases.map(\.rawValue)

    static let denyByDefault = true
    static let requiresExplicitAudience = true
    static let requiresRecordedSensitivity = true
    static let requiresNonColorStateText = true
    static let requiresTextAndIconForIndeterminateStates = true
    static let requiresActionableNextStep = true
    static let allowsColorOnlyState = false
    static let allowsIconOnlyState = false
    static let excludesCustomerDataLeakage = true
    static let excludesPrivateLocators = true
    static let excludesUnsupportedClaims = true

    /// The vocabulary is normalized to words so punctuation and hyphenation
    /// cannot turn a prohibited claim into an accepted display string.
    static let prohibitedClaimPhrases: Set<String> = [
        "approval", "approved", "authorship", "author", "authored",
        "legal", "signature", "legal signature", "nonrepudiation",
        "non repudiation", "tamperproof", "tamper proof", "verified identity",
        "secure", "secured", "sent", "delivered", "compliance", "compliant",
        "professional", "customer data", "customer data leakage", "private data",
        "data leakage",
    ]

    static func containsProhibitedClaim(in values: [String]) -> Bool {
        values.contains { value in
            let normalized = value
                .folding(
                    options: [.caseInsensitive, .diacriticInsensitive],
                    locale: Locale(identifier: "en_US_POSIX")
                )
                .split { !$0.isLetter && !$0.isNumber }
                .joined(separator: " ")
            let bounded = " \(normalized) "
            return prohibitedClaimPhrases.contains { bounded.contains(" \($0) ") }
        }
    }

    static func containsCustomerDataLeakage(in values: [String]) -> Bool {
        values.contains { value in
            let normalized = value
                .folding(
                    options: [.caseInsensitive, .diacriticInsensitive],
                    locale: Locale(identifier: "en_US_POSIX")
                )
                .split { !$0.isLetter && !$0.isNumber }
                .joined(separator: " ")
            let bounded = " \(normalized) "
            return [
                " customer data ", " customer data leakage ", " private data ",
                " data leakage ", " personal data ",
            ].contains { bounded.contains($0) }
        }
    }
}

typealias EvidenceAssuranceLocalizationPolicyV1 = EvidenceVisibilityLocalizationPolicyV1

enum EvidenceVisibilityClaimVocabularyV1 {
    static let prohibitedTokens = EvidenceVisibilityLocalizationPolicyV1.prohibitedClaimPhrases

    static func containsProhibitedClaim(in values: [String]) -> Bool {
        EvidenceVisibilityLocalizationPolicyV1.containsProhibitedClaim(in: values)
    }

    static func containsCustomerDataLeakage(in values: [String]) -> Bool {
        EvidenceVisibilityLocalizationPolicyV1.containsCustomerDataLeakage(in: values)
    }
}

typealias EvidenceAssuranceClaimVocabularyV1 = EvidenceVisibilityClaimVocabularyV1

extension EvidenceVisibilityLocalizationKeyV1 {
    static func audienceKey(_ audience: EvidenceAudienceV1) -> Self {
        switch audience {
        case .internalReview: return .audienceInternalReview
        case .customerReport: return .audienceCustomerReport
        case .externalCollaborator: return .audienceExternalCollaborator
        }
    }

    static func sensitivityKey(_ sensitivity: EvidenceSensitivityV1) -> Self {
        switch sensitivity {
        case .routine: return .sensitivityRoutine
        case .restricted: return .sensitivityRestricted
        case .highlyRestricted: return .sensitivityHighlyRestricted
        }
    }

    static func dispositionKey(_ disposition: EvidenceInclusionDispositionV1) -> Self {
        switch disposition {
        case .included: return .included
        case .excluded: return .excluded
        }
    }

    static func inclusionKey(_ disposition: EvidenceInclusionDispositionV1) -> Self {
        dispositionKey(disposition)
    }

    static func limitationKey(_ limitation: EvidenceLimitationV1) -> Self {
        switch limitation {
        case .none: return .included
        case .audienceNotDeclared: return .unknown
        case .sensitivityRestricted: return .limitation
        case .evidenceUnavailable, .evidenceInvalid: return .omitted
        }
    }

    static func previewStateKey(_ state: EvidencePreviewLocalizationStateV1) -> Self {
        switch state {
        case .ready: return .previewReady
        case .stale: return .previewStale
        }
    }

    static func previewKey(_ state: EvidencePreviewLocalizationStateV1) -> Self {
        previewStateKey(state)
    }

    static func attestationPurposeKey(_ purpose: AttestationPurposeV1) -> Self {
        // The purpose remains a recorded machine value; one stable localized
        // label identifies the purpose field without exposing that value.
        _ = purpose
        return .attestationPurpose
    }

    static func attestationActionKey(_ action: AttestationActionV1) -> Self {
        switch action {
        case .recorded: return .attestationRecorded
        case .superseded: return .attestationSuperseded
        case .voided: return .attestationVoid
        }
    }

    static func attestationStateKey(_ action: AttestationActionV1) -> Self {
        attestationActionKey(action)
    }
}

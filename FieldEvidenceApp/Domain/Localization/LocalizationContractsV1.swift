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

enum C50IncumbentLocalizationBoundaryV1 {
    static let disabledStateKey = "incumbent.adapter.disabled.no_selected_profile"
    static let externalAvailabilityUnknownKey = "incumbent.adapter.external_availability_unknown"
    static let quarantineKey = "incumbent.adapter.quarantined"
    static let providerMechanicsRemainSecondary = true
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

/// C18 binds a package to localization by release digest and typed key IDs.
/// Localized labels are presentation data and are never part of package
/// identity, diff classification, or report replay.
struct PackageEvolutionLocalizationBindingV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let packageReleaseID: String
    let localizationReleaseSHA256: String?
    let sourceLocale: String
    let shippingLocales: [String]
    let keyIDs: [String]

    init(
        metadata: PackageEvolutionConsumerMetadataV1,
        keyIDs: [String] = []
    ) throws {
        try metadata.validate()
        let orderedKeys = keyIDs.sorted()
        guard Set(orderedKeys).count == orderedKeys.count,
              orderedKeys.allSatisfy({ (try? LocalizationKeyV1($0)) != nil }) else {
            throw LocalizationContractFailureV1.invalidValue
        }
        schemaVersion = Self.schemaVersion
        packageReleaseID = metadata.packageReleaseID
        localizationReleaseSHA256 = metadata.localizationReleaseSHA256
        sourceLocale = "en"
        shippingLocales = ["en"]
        self.keyIDs = orderedKeys
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              KernelCanonicalHashV1.validSHA256(packageReleaseID),
              localizationReleaseSHA256.map(KernelCanonicalHashV1.validSHA256) ?? true,
              sourceLocale == "en",
              shippingLocales == ["en"],
              Set(keyIDs).count == keyIDs.count,
              keyIDs == keyIDs.sorted(),
              keyIDs.allSatisfy({ (try? LocalizationKeyV1($0)) != nil }) else {
            throw LocalizationContractFailureV1.invalidShippingLocale
        }
    }

    /// Equality of package localization bindings intentionally ignores all
    /// translated/default label text and compares only stable key/release
    /// identity.
    func comparesKeysAndReleasesOnly(to other: Self) -> Bool {
        packageReleaseID == other.packageReleaseID
            && localizationReleaseSHA256 == other.localizationReleaseSHA256
            && keyIDs == other.keyIDs
    }
}

enum PackageEvolutionLocalizationPolicyV1 {
    static let sourceLocale = "en"
    static let shippingLocales = ["en"]
    static let testOnlyPseudoLocales = TestOnlyPseudoLocaleV1.allCases
        .map(\.rawValue).sorted()
    static let comparesKeysAndReleasesNotLabels = true
    static let pseudoLocalesMayShip = false
    static let canonicalPackageBytesAreNeverTranslated = true
    static let frozenReportDisplaysAreNeverReformatted = true

    static func binding(
        metadata: PackageEvolutionConsumerMetadataV1,
        keyIDs: [String] = []
    ) throws -> PackageEvolutionLocalizationBindingV1 {
        try PackageEvolutionLocalizationBindingV1(metadata: metadata, keyIDs: keyIDs)
    }
}

extension PackageEvolutionConsumerMetadataV1 {
    func packageLocalizationBinding(keyIDs: [String] = []) throws
        -> PackageEvolutionLocalizationBindingV1 {
        try PackageEvolutionLocalizationBindingV1(metadata: self, keyIDs: keyIDs)
    }
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

/// C14's review and corrective-action labels are a closed, English-only
/// presentation surface.  The review contracts retain the durable transition,
/// request, resolution, and action values; these keys only describe recorded
/// local facts and the next step a reader may take.
enum InspectionReviewLocalizationKeyV1: String, CaseIterable, Codable, Sendable {
    case heading = "inspection.review.heading"
    case state = "inspection.review.state"
    case draft = "inspection.review.state.draft"
    case fieldComplete = "inspection.review.state.field_complete"
    case readyForReview = "inspection.review.state.ready_for_review"
    case changesRequested = "inspection.review.state.changes_requested"
    case accepted = "inspection.review.state.accepted"
    case finalized = "inspection.review.state.finalized"
    case amended = "inspection.review.state.amended"
    case superseded = "inspection.review.state.superseded"
    case disposition = "inspection.review.disposition"
    case dispositionChangesRequested = "inspection.review.disposition.changes_requested"
    case dispositionAccepted = "inspection.review.disposition.accepted"
    case changeRequest = "inspection.review.change_request"
    case changeRequestState = "inspection.review.change_request.state"
    case changeRequestOpen = "inspection.review.change_request.state.open"
    case changeRequestResolved = "inspection.review.change_request.state.resolved"
    case changeRequestWithdrawn = "inspection.review.change_request.state.withdrawn"
    case changeRequestSuperseded = "inspection.review.change_request.state.superseded"
    case changeRequestResolution = "inspection.review.change_request.resolution"
    case changeRequestResolutionFulfilled = "inspection.review.change_request.resolution.fulfilled"
    case changeRequestResolutionWithdrawnWithReason = "inspection.review.change_request.resolution.withdrawn_with_reason"
    case changeRequestResolutionSuperseded = "inspection.review.change_request.resolution.superseded"
    case correctiveAction = "inspection.review.corrective_action"
    case correctiveActionState = "inspection.review.corrective_action.state"
    case correctiveActionOpen = "inspection.review.corrective_action.state.open"
    case correctiveActionInProgress = "inspection.review.corrective_action.state.in_progress"
    case correctiveActionAwaitingVerification = "inspection.review.corrective_action.state.awaiting_verification"
    case correctiveActionClosed = "inspection.review.corrective_action.state.closed"
    case correctiveActionReopened = "inspection.review.corrective_action.state.reopened"
    case correctiveActionSuperseded = "inspection.review.corrective_action.state.superseded"
    case nextStep = "inspection.review.next_step"
    case minimumNextRequirement = "inspection.review.next_step.minimum_requirement"

    static var reviewHeading: Self { .heading }
    static var reviewState: Self { .state }
    static var reviewDraft: Self { .draft }
    static var fieldCompleteState: Self { .fieldComplete }
    static var reviewFieldComplete: Self { .fieldComplete }
    static var readyState: Self { .readyForReview }
    static var reviewReadyForReview: Self { .readyForReview }
    static var changesRequestedState: Self { .changesRequested }
    static var reviewChangesRequested: Self { .changesRequested }
    static var acceptedState: Self { .accepted }
    static var reviewAccepted: Self { .accepted }
    static var finalizedState: Self { .finalized }
    static var reviewFinalized: Self { .finalized }
    static var amendedState: Self { .amended }
    static var reviewAmended: Self { .amended }
    static var supersededState: Self { .superseded }
    static var reviewSuperseded: Self { .superseded }
    static var changeRequestHeading: Self { .changeRequest }
    static var changeRequestOpenState: Self { .changeRequestOpen }
    static var changeRequestResolvedState: Self { .changeRequestResolved }
    static var changeRequestWithdrawnState: Self { .changeRequestWithdrawn }
    static var changeRequestSupersededState: Self { .changeRequestSuperseded }
    static var correctiveActionHeading: Self { .correctiveAction }
    static var correctiveActionOpenState: Self { .correctiveActionOpen }
    static var correctiveActionInProgressState: Self { .correctiveActionInProgress }
    static var correctiveActionAwaitingVerificationState: Self { .correctiveActionAwaitingVerification }
    static var correctiveActionClosedState: Self { .correctiveActionClosed }
    static var correctiveActionReopenedState: Self { .correctiveActionReopened }
    static var correctiveActionSupersededState: Self { .correctiveActionSuperseded }
    static var actionableNextStep: Self { .nextStep }

    var localizationKey: LocalizationKeyV1 {
        // Construction is non-throwing for this closed repository-owned set;
        // registry construction remains the validation boundary.
        // swiftlint:disable:next force_try
        try! LocalizationKeyV1(rawValue)
    }
}

typealias ReviewCorrectiveActionLocalizationKeyV1 = InspectionReviewLocalizationKeyV1
typealias ReviewAndCorrectiveActionLocalizationKeyV1 = InspectionReviewLocalizationKeyV1
typealias ReviewLocalizationKeyV1 = InspectionReviewLocalizationKeyV1
typealias CorrectiveActionLocalizationKeyV1 = InspectionReviewLocalizationKeyV1

enum InspectionReviewLocalizationPolicyV1 {
    static let semanticNamespace = "inspection.review"
    static let sourceLocale = "en"
    static let shippingLocale = "en"
    static let metadataLocale = "en-US"
    static let testOnlyLocales = TestOnlyPseudoLocaleV1.allCases.map(\.rawValue).sorted()
    static let keys = InspectionReviewLocalizationKeyV1.allCases.map(\.rawValue)
    static let reportKeys = InspectionReviewLocalizationKeyV1.allCases.map(\.rawValue)
    static let stateKeys = [
        InspectionReviewLocalizationKeyV1.draft.rawValue,
        InspectionReviewLocalizationKeyV1.fieldComplete.rawValue,
        InspectionReviewLocalizationKeyV1.readyForReview.rawValue,
        InspectionReviewLocalizationKeyV1.changesRequested.rawValue,
        InspectionReviewLocalizationKeyV1.accepted.rawValue,
        InspectionReviewLocalizationKeyV1.finalized.rawValue,
        InspectionReviewLocalizationKeyV1.amended.rawValue,
        InspectionReviewLocalizationKeyV1.superseded.rawValue,
        InspectionReviewLocalizationKeyV1.dispositionChangesRequested.rawValue,
        InspectionReviewLocalizationKeyV1.dispositionAccepted.rawValue,
        InspectionReviewLocalizationKeyV1.changeRequestOpen.rawValue,
        InspectionReviewLocalizationKeyV1.changeRequestResolved.rawValue,
        InspectionReviewLocalizationKeyV1.changeRequestWithdrawn.rawValue,
        InspectionReviewLocalizationKeyV1.changeRequestSuperseded.rawValue,
        InspectionReviewLocalizationKeyV1.changeRequestResolutionFulfilled.rawValue,
        InspectionReviewLocalizationKeyV1.changeRequestResolutionWithdrawnWithReason.rawValue,
        InspectionReviewLocalizationKeyV1.changeRequestResolutionSuperseded.rawValue,
        InspectionReviewLocalizationKeyV1.correctiveActionOpen.rawValue,
        InspectionReviewLocalizationKeyV1.correctiveActionInProgress.rawValue,
        InspectionReviewLocalizationKeyV1.correctiveActionAwaitingVerification.rawValue,
        InspectionReviewLocalizationKeyV1.correctiveActionClosed.rawValue,
        InspectionReviewLocalizationKeyV1.correctiveActionReopened.rawValue,
        InspectionReviewLocalizationKeyV1.correctiveActionSuperseded.rawValue,
    ]
    static let indeterminateStateKeys: Set<String> = [
        InspectionReviewLocalizationKeyV1.draft.rawValue,
        InspectionReviewLocalizationKeyV1.fieldComplete.rawValue,
        InspectionReviewLocalizationKeyV1.readyForReview.rawValue,
        InspectionReviewLocalizationKeyV1.changesRequested.rawValue,
        InspectionReviewLocalizationKeyV1.amended.rawValue,
        InspectionReviewLocalizationKeyV1.superseded.rawValue,
        InspectionReviewLocalizationKeyV1.dispositionChangesRequested.rawValue,
        InspectionReviewLocalizationKeyV1.changeRequestOpen.rawValue,
        InspectionReviewLocalizationKeyV1.changeRequestResolutionSuperseded.rawValue,
        InspectionReviewLocalizationKeyV1.correctiveActionOpen.rawValue,
        InspectionReviewLocalizationKeyV1.correctiveActionInProgress.rawValue,
        InspectionReviewLocalizationKeyV1.correctiveActionAwaitingVerification.rawValue,
        InspectionReviewLocalizationKeyV1.correctiveActionReopened.rawValue,
        InspectionReviewLocalizationKeyV1.correctiveActionSuperseded.rawValue,
    ]

    static let denyByDefault = true
    static let requiresNonColorStateText = true
    static let requiresTextAndIconForIndeterminateStates = true
    static let requiresActionableNextStep = true
    static let allowsColorOnlyState = false
    static let allowsIconOnlyState = false
    static let excludesCustomerDataLeakage = true
    static let excludesPrivateLocators = true
    static let excludesUnsupportedClaims = true

    /// Normalize punctuation and hyphenation before matching so a prohibited
    /// claim cannot be smuggled through as a differently punctuated label.
    static let prohibitedClaimPhrases: Set<String> = [
        "approval", "approve", "approved",
        "authorization", "authorize", "authorized",
        "verified identity", "identity verified",
        "legal", "legal signature",
        "compliance", "compliant",
        "tamperproof", "tamper proof", "tamper-proof",
        "nonrepudiation", "non repudiation", "non-repudiation",
        "secure", "secured", "sent", "delivered",
        "professional", "certification", "certified",
        "customer data", "customer data leakage", "customer information",
        "private data", "personal data", "data leakage", "customer record",
    ]

    private static func normalized(_ value: String) -> String {
        value
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .split { !$0.isLetter && !$0.isNumber }
            .joined(separator: " ")
    }

    static func containsProhibitedClaim(in values: [String]) -> Bool {
        values.contains { value in
            let bounded = " \(normalized(value)) "
            return prohibitedClaimPhrases.contains { phrase in
                let normalizedPhrase = normalized(phrase)
                return bounded.contains(" \(normalizedPhrase) ")
            }
        }
    }

    static func containsCustomerDataLeakage(in values: [String]) -> Bool {
        values.contains { value in
            let bounded = " \(normalized(value)) "
            return [
                "customer data", "customer information", "private data",
                "personal data", "data leakage", "customer record",
            ].contains { bounded.contains(" \($0) ") }
        }
    }
}

typealias ReviewCorrectiveActionLocalizationPolicyV1 = InspectionReviewLocalizationPolicyV1
typealias ReviewAndCorrectiveActionLocalizationPolicyV1 = InspectionReviewLocalizationPolicyV1
typealias ReviewLocalizationPolicyV1 = InspectionReviewLocalizationPolicyV1
typealias CorrectiveActionLocalizationPolicyV1 = InspectionReviewLocalizationPolicyV1

enum InspectionReviewClaimVocabularyV1 {
    static let prohibitedTokens = InspectionReviewLocalizationPolicyV1.prohibitedClaimPhrases

    static func containsProhibitedClaim(in values: [String]) -> Bool {
        InspectionReviewLocalizationPolicyV1.containsProhibitedClaim(in: values)
    }

    static func containsCustomerDataLeakage(in values: [String]) -> Bool {
        InspectionReviewLocalizationPolicyV1.containsCustomerDataLeakage(in: values)
    }
}

typealias ReviewCorrectiveActionClaimVocabularyV1 = InspectionReviewClaimVocabularyV1

extension InspectionReviewLocalizationKeyV1 {
    static func stateKey(_ state: InspectionReviewStateV1) -> Self {
        switch state {
        case .draft: return .draft
        case .fieldComplete: return .fieldComplete
        case .readyForReview: return .readyForReview
        case .changesRequested: return .changesRequested
        case .accepted: return .accepted
        case .finalized: return .finalized
        case .amended: return .amended
        case .superseded: return .superseded
        }
    }

    static func reviewStateKey(_ state: InspectionReviewStateV1) -> Self {
        stateKey(state)
    }

    static func reviewStateLocalizationKey(_ state: InspectionReviewStateV1) -> Self {
        stateKey(state)
    }

    static func dispositionKey(_ disposition: ReviewDispositionKindV1) -> Self {
        switch disposition {
        case .changesRequested: return .dispositionChangesRequested
        case .accepted: return .dispositionAccepted
        }
    }

    static func dispositionStateKey(_ disposition: ReviewDispositionKindV1) -> Self {
        dispositionKey(disposition)
    }

    static func changeRequestStateKey(_ state: ChangeRequestStateV1) -> Self {
        switch state {
        case .open: return .changeRequestOpen
        case .resolved: return .changeRequestResolved
        case .withdrawn: return .changeRequestWithdrawn
        case .superseded: return .changeRequestSuperseded
        }
    }

    static func changeRequestResolutionKey(
        _ resolution: ChangeRequestResolutionKindV1
    ) -> Self {
        switch resolution {
        case .fulfilled: return .changeRequestResolutionFulfilled
        case .withdrawnWithReason: return .changeRequestResolutionWithdrawnWithReason
        case .superseded: return .changeRequestResolutionSuperseded
        }
    }

    static func resolutionKey(_ resolution: ChangeRequestResolutionKindV1) -> Self {
        changeRequestResolutionKey(resolution)
    }

    static func correctiveActionStateKey(_ state: CorrectiveActionStateV1) -> Self {
        switch state {
        case .open: return .correctiveActionOpen
        case .inProgress: return .correctiveActionInProgress
        case .awaitingVerification: return .correctiveActionAwaitingVerification
        case .closed: return .correctiveActionClosed
        case .reopened: return .correctiveActionReopened
        case .superseded: return .correctiveActionSuperseded
        }
    }

    static func stateKey(_ state: CorrectiveActionStateV1) -> Self {
        correctiveActionStateKey(state)
    }

    static func nextStepKey() -> Self { .nextStep }
    static func minimumRequirementKey() -> Self { .minimumNextRequirement }
}

/// C15's packet-coordination presentation vocabulary is closed and English
/// only.  Packet, claim, lease, release, handoff, conflict, expiry, and
/// replay values remain recorded facts; these keys never localize wire values
/// into canonical bytes or expose packet contents.
enum WorkPacketLocalizationKeyV1: String, CaseIterable, Codable, Sendable {
    case heading = "work.packet.heading"
    case manifest = "work.packet.manifest"
    case item = "work.packet.item"
    case manifestState = "work.packet.manifest.state"
    case manifestDraft = "work.packet.manifest.state.draft"
    case manifestReady = "work.packet.manifest.state.ready"
    case manifestInvalid = "work.packet.manifest.state.invalid"
    case manifestReplayed = "work.packet.manifest.state.replayed"
    case manifestConflicted = "work.packet.manifest.state.conflicted"
    case manifestSuperseded = "work.packet.manifest.state.superseded"
    case claim = "work.packet.claim"
    case claimState = "work.packet.claim.state"
    case claimUnclaimed = "work.packet.claim.state.unclaimed"
    case claimClaimed = "work.packet.claim.state.claimed"
    case claimReleased = "work.packet.claim.state.released"
    case claimConflicted = "work.packet.claim.state.conflicted"
    case lease = "work.packet.lease"
    case leaseState = "work.packet.lease.state"
    case leaseActive = "work.packet.lease.state.active"
    case leaseExpiring = "work.packet.lease.state.expiring"
    case leaseExpired = "work.packet.lease.state.expired"
    case leaseReclaimed = "work.packet.lease.state.reclaimed"
    case release = "work.packet.release"
    case releaseState = "work.packet.release.state"
    case releaseRecorded = "work.packet.release.state.recorded"
    case releaseAvailable = "work.packet.release.state.available"
    case releaseSuperseded = "work.packet.release.state.superseded"
    case handoff = "work.packet.handoff"
    case handoffState = "work.packet.handoff.state"
    case handoffPending = "work.packet.handoff.state.pending"
    case handoffAccepted = "work.packet.handoff.state.accepted"
    case handoffRejected = "work.packet.handoff.state.rejected"
    case handoffCompleted = "work.packet.handoff.state.completed"
    case conflict = "work.packet.conflict"
    case conflictState = "work.packet.conflict.state"
    case conflictDetected = "work.packet.conflict.state.detected"
    case conflictQuarantined = "work.packet.conflict.state.quarantined"
    case conflictReviewRequired = "work.packet.conflict.state.review_required"
    case conflictResolved = "work.packet.conflict.state.resolved"
    case expiry = "work.packet.expiry"
    case expiryState = "work.packet.expiry.state"
    case expiryNotExpired = "work.packet.expiry.state.not_expired"
    case expiryExpiring = "work.packet.expiry.state.expiring"
    case expiryExpired = "work.packet.expiry.state.expired"
    case replay = "work.packet.replay"
    case replayState = "work.packet.replay.state"
    case replayPending = "work.packet.replay.state.pending"
    case replayApplied = "work.packet.replay.state.applied"
    case replayIdempotent = "work.packet.replay.state.idempotent"
    case replayQuarantined = "work.packet.replay.state.quarantined"
    case nextStep = "work.packet.next_step"
    case minimumNextRequirement = "work.packet.next_step.minimum_requirement"

    static var packetHeading: Self { .heading }
    static var packetManifest: Self { .manifest }
    static var packetItem: Self { .item }
    static var packetManifestState: Self { .manifestState }
    static var packetClaim: Self { .claim }
    static var packetLease: Self { .lease }
    static var packetRelease: Self { .release }
    static var packetHandoff: Self { .handoff }
    static var packetConflict: Self { .conflict }
    static var packetExpiry: Self { .expiry }
    static var packetReplay: Self { .replay }
    static var packetNextStep: Self { .nextStep }
    static var actionableNextStep: Self { .nextStep }
    static var minimumRequirement: Self { .minimumNextRequirement }

    var localizationKey: LocalizationKeyV1 {
        // This enum is repository-owned and closed; registry construction is
        // still the validation boundary for serialized declarations.
        // swiftlint:disable:next force_try
        try! LocalizationKeyV1(rawValue)
    }
}

typealias WorkPacketManifestLocalizationKeyV1 = WorkPacketLocalizationKeyV1
typealias PacketCoordinationLocalizationKeyV1 = WorkPacketLocalizationKeyV1

enum WorkPacketLocalizationPolicyV1 {
    static let semanticNamespace = "work.packet"
    static let sourceLocale = "en"
    static let shippingLocale = "en"
    static let metadataLocale = "en-US"
    static let testOnlyLocales = TestOnlyPseudoLocaleV1.allCases.map(\.rawValue).sorted()
    static let keys = WorkPacketLocalizationKeyV1.allCases.map(\.rawValue)
    static let reportKeys = WorkPacketLocalizationKeyV1.allCases.map(\.rawValue)
    static let stateKeys = [
        WorkPacketLocalizationKeyV1.manifestDraft.rawValue,
        WorkPacketLocalizationKeyV1.manifestReady.rawValue,
        WorkPacketLocalizationKeyV1.manifestInvalid.rawValue,
        WorkPacketLocalizationKeyV1.manifestReplayed.rawValue,
        WorkPacketLocalizationKeyV1.manifestConflicted.rawValue,
        WorkPacketLocalizationKeyV1.manifestSuperseded.rawValue,
        WorkPacketLocalizationKeyV1.claimUnclaimed.rawValue,
        WorkPacketLocalizationKeyV1.claimClaimed.rawValue,
        WorkPacketLocalizationKeyV1.claimReleased.rawValue,
        WorkPacketLocalizationKeyV1.claimConflicted.rawValue,
        WorkPacketLocalizationKeyV1.leaseActive.rawValue,
        WorkPacketLocalizationKeyV1.leaseExpiring.rawValue,
        WorkPacketLocalizationKeyV1.leaseExpired.rawValue,
        WorkPacketLocalizationKeyV1.leaseReclaimed.rawValue,
        WorkPacketLocalizationKeyV1.releaseRecorded.rawValue,
        WorkPacketLocalizationKeyV1.releaseAvailable.rawValue,
        WorkPacketLocalizationKeyV1.releaseSuperseded.rawValue,
        WorkPacketLocalizationKeyV1.handoffPending.rawValue,
        WorkPacketLocalizationKeyV1.handoffAccepted.rawValue,
        WorkPacketLocalizationKeyV1.handoffRejected.rawValue,
        WorkPacketLocalizationKeyV1.handoffCompleted.rawValue,
        WorkPacketLocalizationKeyV1.conflictDetected.rawValue,
        WorkPacketLocalizationKeyV1.conflictQuarantined.rawValue,
        WorkPacketLocalizationKeyV1.conflictReviewRequired.rawValue,
        WorkPacketLocalizationKeyV1.conflictResolved.rawValue,
        WorkPacketLocalizationKeyV1.expiryNotExpired.rawValue,
        WorkPacketLocalizationKeyV1.expiryExpiring.rawValue,
        WorkPacketLocalizationKeyV1.expiryExpired.rawValue,
        WorkPacketLocalizationKeyV1.replayPending.rawValue,
        WorkPacketLocalizationKeyV1.replayApplied.rawValue,
        WorkPacketLocalizationKeyV1.replayIdempotent.rawValue,
        WorkPacketLocalizationKeyV1.replayQuarantined.rawValue,
    ]
    static let indeterminateStateKeys: Set<String> = [
        WorkPacketLocalizationKeyV1.manifestDraft.rawValue,
        WorkPacketLocalizationKeyV1.manifestInvalid.rawValue,
        WorkPacketLocalizationKeyV1.manifestConflicted.rawValue,
        WorkPacketLocalizationKeyV1.claimUnclaimed.rawValue,
        WorkPacketLocalizationKeyV1.claimConflicted.rawValue,
        WorkPacketLocalizationKeyV1.leaseExpiring.rawValue,
        WorkPacketLocalizationKeyV1.leaseExpired.rawValue,
        WorkPacketLocalizationKeyV1.leaseReclaimed.rawValue,
        WorkPacketLocalizationKeyV1.releaseAvailable.rawValue,
        WorkPacketLocalizationKeyV1.releaseSuperseded.rawValue,
        WorkPacketLocalizationKeyV1.handoffPending.rawValue,
        WorkPacketLocalizationKeyV1.handoffRejected.rawValue,
        WorkPacketLocalizationKeyV1.conflictDetected.rawValue,
        WorkPacketLocalizationKeyV1.conflictQuarantined.rawValue,
        WorkPacketLocalizationKeyV1.conflictReviewRequired.rawValue,
        WorkPacketLocalizationKeyV1.expiryExpiring.rawValue,
        WorkPacketLocalizationKeyV1.expiryExpired.rawValue,
        WorkPacketLocalizationKeyV1.replayPending.rawValue,
        WorkPacketLocalizationKeyV1.replayQuarantined.rawValue,
    ]

    static let denyByDefault = true
    static let requiresNonColorStateText = true
    static let requiresTextAndIconForIndeterminateStates = true
    static let requiresActionableNextStep = true
    static let allowsColorOnlyState = false
    static let allowsIconOnlyState = false
    static let excludesSecrets = true
    static let excludesCustomerData = true
    static let excludesWorkData = true
    static let excludesCustomerDataLeakage = true
    static let excludesPrivateLocators = true
    static let excludesUnsupportedClaims = true

    static let prohibitedClaimPhrases: Set<String> = [
        "approval", "approve", "approved", "authorization", "authorize", "authorized",
        "verified", "verified identity", "identity verified", "legal", "legal signature",
        "compliance", "compliant", "tamperproof", "tamper proof", "tamper-proof",
        "nonrepudiation", "non repudiation", "non-repudiation", "secure", "secured",
        "sent", "delivered", "professional", "certification", "certified", "saved",
        "complete", "customer data", "customer information", "private data", "personal data",
        "work data", "work item data", "work product", "secret", "secrets", "credential",
        "credentials", "password", "token", "customer record", "data leakage", "account",
        "accounts", "authentication", "authorize", "rbac", "remote", "transport", "provider",
        "delivery", "cmms", "artificial intelligence", "signing", "upload", "submission",
        "dispatch", "telemetry", "finalization",
    ]

    private static func normalized(_ value: String) -> String {
        value
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .split { !$0.isLetter && !$0.isNumber }
            .joined(separator: " ")
    }

    static func containsProhibitedClaim(in values: [String]) -> Bool {
        values.contains { value in
            let bounded = " \(normalized(value)) "
            prohibitedClaimPhrases.contains { phrase in
                bounded.contains(" \(normalized(phrase)) ")
            }
        }
    }

    static func containsSensitiveDataLeakage(in values: [String]) -> Bool {
        values.contains { value in
            let bounded = " \(normalized(value)) "
            [
                "customer data", "customer information", "customer record", "private data",
                "personal data", "work data", "work item data", "work product", "secret",
                "credentials", "credential", "password", "token", "account", "accounts",
                "data leakage",
            ].contains { bounded.contains(" \($0) ") }
        }
    }

    static func containsCustomerDataLeakage(in values: [String]) -> Bool {
        containsSensitiveDataLeakage(in: values)
    }

    static func containsCustomerOrWorkDataLeakage(in values: [String]) -> Bool {
        containsSensitiveDataLeakage(in: values)
    }
}

typealias WorkPacketManifestLocalizationPolicyV1 = WorkPacketLocalizationPolicyV1
typealias PacketCoordinationLocalizationPolicyV1 = WorkPacketLocalizationPolicyV1

enum WorkPacketClaimVocabularyV1 {
    static let prohibitedTokens = WorkPacketLocalizationPolicyV1.prohibitedClaimPhrases

    static func containsProhibitedClaim(in values: [String]) -> Bool {
        WorkPacketLocalizationPolicyV1.containsProhibitedClaim(in: values)
    }

    static func containsSensitiveDataLeakage(in values: [String]) -> Bool {
        WorkPacketLocalizationPolicyV1.containsSensitiveDataLeakage(in: values)
    }

    static func containsCustomerDataLeakage(in values: [String]) -> Bool {
        WorkPacketLocalizationPolicyV1.containsSensitiveDataLeakage(in: values)
    }

    static func containsCustomerOrWorkDataLeakage(in values: [String]) -> Bool {
        WorkPacketLocalizationPolicyV1.containsSensitiveDataLeakage(in: values)
    }
}

typealias WorkPacketManifestClaimVocabularyV1 = WorkPacketClaimVocabularyV1

extension WorkPacketLocalizationKeyV1 {
    static func manifestStateKey(_ rawValue: String) -> Self? {
        switch rawValue {
        case "DRAFT": return .manifestDraft
        case "READY": return .manifestReady
        case "INVALID": return .manifestInvalid
        case "REPLAYED": return .manifestReplayed
        case "CONFLICTED": return .manifestConflicted
        case "SUPERSEDED": return .manifestSuperseded
        default: return nil
        }
    }

    static func claimStateKey(_ rawValue: String) -> Self? {
        switch rawValue {
        case "UNCLAIMED", "AVAILABLE": return .claimUnclaimed
        case "CLAIMED": return .claimClaimed
        case "RELEASED": return .claimReleased
        case "CONFLICTED": return .claimConflicted
        default: return nil
        }
    }

    static func leaseStateKey(_ rawValue: String) -> Self? {
        switch rawValue {
        case "ACTIVE": return .leaseActive
        case "EXPIRING": return .leaseExpiring
        case "EXPIRED": return .leaseExpired
        case "RECLAIMED": return .leaseReclaimed
        default: return nil
        }
    }

    static func releaseStateKey(_ rawValue: String) -> Self? {
        switch rawValue {
        case "RECORDED": return .releaseRecorded
        case "AVAILABLE": return .releaseAvailable
        case "SUPERSEDED": return .releaseSuperseded
        default: return nil
        }
    }

    static func handoffStateKey(_ rawValue: String) -> Self? {
        switch rawValue {
        case "PENDING": return .handoffPending
        case "ACCEPTED": return .handoffAccepted
        case "REJECTED": return .handoffRejected
        case "COMPLETED": return .handoffCompleted
        default: return nil
        }
    }

    static func conflictStateKey(_ rawValue: String) -> Self? {
        switch rawValue {
        case "DETECTED": return .conflictDetected
        case "QUARANTINED": return .conflictQuarantined
        case "REVIEW_REQUIRED": return .conflictReviewRequired
        case "RESOLVED": return .conflictResolved
        default: return nil
        }
    }

    static func expiryStateKey(_ rawValue: String) -> Self? {
        switch rawValue {
        case "NOT_EXPIRED": return .expiryNotExpired
        case "EXPIRING": return .expiryExpiring
        case "EXPIRED": return .expiryExpired
        default: return nil
        }
    }

    static func replayStateKey(_ rawValue: String) -> Self? {
        switch rawValue {
        case "PENDING": return .replayPending
        case "APPLIED": return .replayApplied
        case "IDEMPOTENT": return .replayIdempotent
        case "QUARANTINED": return .replayQuarantined
        default: return nil
        }
    }

    /// Core replay dispositions are recorded wire facts; these mappings only
    /// select truthful local display states and never rewrite the disposition.
    static func replayStateKey(_ disposition: WorkPacketReplayDispositionV1) -> Self {
        switch disposition {
        case .apply: return .replayApplied
        case .idempotentReplay: return .replayIdempotent
        case .quarantineDivergentBytes: return .replayQuarantined
        }
    }

    static func replayDispositionKey(_ disposition: WorkPacketReplayDispositionV1) -> Self {
        replayStateKey(disposition)
    }

    /// Conflict kinds stay in the recorded domain.  Divergent bytes are
    /// quarantined; other collision classes require a recorded review.
    static func conflictStateKey(_ kind: WorkPacketConflictKindV1) -> Self {
        switch kind {
        case .simultaneousClaim: return .conflictDetected
        case .staleResultRevision, .expiredLeaseResult: return .conflictReviewRequired
        case .divergentSameIdentity: return .conflictQuarantined
        }
    }

    static func conflictKindKey(_ kind: WorkPacketConflictKindV1) -> Self {
        conflictStateKey(kind)
    }

    static func releaseStateKey(_ reason: WorkReleaseReasonV1) -> Self {
        switch reason {
        case .leaseExpired: return .releaseAvailable
        case .completed, .deliberatelyReleased, .handoff, .reclaimed:
            return .releaseRecorded
        }
    }

    static func releaseReasonKey(_ reason: WorkReleaseReasonV1) -> Self {
        releaseStateKey(reason)
    }

    static func nextStepKey() -> Self { .nextStep }
    static func minimumRequirementKey() -> Self { .minimumNextRequirement }
}

/// C36 keeps durable draft and attachment lifecycle values in the recorded
/// domain.  These closed presentation states are English-only labels and do
/// not rewrite the checkpoint, staging item, or commit-saga bytes.
enum FieldDraftCheckpointLocalizationStateV1: String, CaseIterable, Codable, Hashable, Sendable {
    case active = "ACTIVE"
    case committing = "COMMITTING"
    case conflicted = "CONFLICTED"
    case recoveryRequired = "RECOVERY_REQUIRED"
    case committed = "COMMITTED"
    case discardPending = "DISCARD_PENDING"
    case discarded = "DISCARDED"
}

enum FieldDraftDurabilityLocalizationStateV1: String, CaseIterable, Codable, Hashable, Sendable {
    case unsavedChanges = "UNSAVED_CHANGES"
    case savingOnThisIPhone = "SAVING_ON_THIS_IPHONE"
    case savedOnThisIPhone = "SAVED_ON_THIS_IPHONE"
    case saveBlocked = "SAVE_BLOCKED"
    case committing = "COMMITTING"
    case conflicted = "CONFLICTED"
    case recoveryRequired = "RECOVERY_REQUIRED"
    case committed = "COMMITTED"
    case discarding = "DISCARDING"
    case discarded = "DISCARDED"
}

enum FieldDraftAttachmentLocalizationStateV1: String, CaseIterable, Codable, Hashable, Sendable {
    // V21's visible per-selected-attachment refinement.
    case selected = "SELECTED"
    case loading = "LOADING"
    case stagedLocal = "STAGED_LOCAL"
    case processing = "PROCESSING"
    case ready = "READY"
    case retryableFailure = "RETRYABLE_FAILURE"
    case blocked = "BLOCKED"
    case removed = "REMOVED"
    case promoted = "PROMOTED"
    // C36's durable staging item states.
    case capturing = "CAPTURING"
    case hashing = "HASHING"
    case readyLocal = "READY_LOCAL"
    case failedRetryable = "FAILED_RETRYABLE"
    case failedFinal = "FAILED_FINAL"
    case removePending = "REMOVE_PENDING"
    case committed = "COMMITTED"
    case orphanQuarantined = "ORPHAN_QUARANTINED"
}

enum FieldDraftCommitSagaLocalizationStateV1: String, CaseIterable, Codable, Hashable, Sendable {
    case prepared = "PREPARED"
    case contentPromotedUnbound = "CONTENT_PROMOTED_UNBOUND"
    case targetCommitted = "TARGET_COMMITTED"
    case draftRetirePending = "DRAFT_RETIRE_PENDING"
    case draftRetired = "DRAFT_RETIRED"
    case conflicted = "CONFLICTED"
    case recoveryRequired = "RECOVERY_REQUIRED"
}

enum FieldDraftRecoveryLocalizationStateV1: String, CaseIterable, Codable, Hashable, Sendable {
    case resumeAvailable = "RESUME_AVAILABLE"
    case conflict = "CONFLICT"
    case missingMedia = "MISSING_MEDIA"
    case lowStorage = "LOW_STORAGE"
    case protectedData = "PROTECTED_DATA"
    case unsupportedCodec = "UNSUPPORTED_CODEC"
    case partialStage = "PARTIAL_STAGE"
    case staleTarget = "STALE_TARGET"
    case recoveryRequired = "RECOVERY_REQUIRED"
}

enum FieldDraftLocalizationKeyV1: String, CaseIterable, Codable, Sendable {
    case screen = "field.draft.screen"
    case heading = "field.draft.heading"
    case durability = "field.draft.durability"
    case durabilityState = "field.draft.durability.state"
    case nextStep = "field.draft.next_step"
    case minimumNextRequirement = "field.draft.next_step.minimum_requirement"
    case checkpoint = "field.draft.checkpoint"
    case checkpointState = "field.draft.checkpoint.state"
    case attachment = "field.draft.attachment"
    case attachmentState = "field.draft.attachment.state"
    case commitSaga = "field.draft.commit.saga"
    case commitSagaState = "field.draft.commit.saga.state"
    case recovery = "field.draft.recovery"
    case recoveryState = "field.draft.recovery.state"
    case recoverySafeAction = "field.draft.recovery.safe_action"
    case recoveryFallback = "field.draft.recovery.fallback"

    case durabilityUnsavedChanges = "field.draft.durability.state.unsaved_changes"
    case durabilitySavingOnThisIPhone = "field.draft.durability.state.saving_on_this_iphone"
    case durabilitySavedOnThisIPhone = "field.draft.durability.state.saved_on_this_iphone"
    case durabilitySaveBlocked = "field.draft.durability.state.save_blocked"
    case durabilityCommitting = "field.draft.durability.state.committing"
    case durabilityConflicted = "field.draft.durability.state.conflicted"
    case durabilityRecoveryRequired = "field.draft.durability.state.recovery_required"
    case durabilityCommitted = "field.draft.durability.state.committed"
    case durabilityDiscarding = "field.draft.durability.state.discarding"
    case durabilityDiscarded = "field.draft.durability.state.discarded"

    case checkpointActive = "field.draft.checkpoint.state.active"
    case checkpointCommitting = "field.draft.checkpoint.state.committing"
    case checkpointConflicted = "field.draft.checkpoint.state.conflicted"
    case checkpointRecoveryRequired = "field.draft.checkpoint.state.recovery_required"
    case checkpointCommitted = "field.draft.checkpoint.state.committed"
    case checkpointDiscardPending = "field.draft.checkpoint.state.discard_pending"
    case checkpointDiscarded = "field.draft.checkpoint.state.discarded"

    case attachmentSelected = "field.draft.attachment.state.selected"
    case attachmentLoading = "field.draft.attachment.state.loading"
    case attachmentStagedLocal = "field.draft.attachment.state.staged_local"
    case attachmentProcessing = "field.draft.attachment.state.processing"
    case attachmentReady = "field.draft.attachment.state.ready"
    case attachmentRetryableFailure = "field.draft.attachment.state.retryable_failure"
    case attachmentBlocked = "field.draft.attachment.state.blocked"
    case attachmentRemoved = "field.draft.attachment.state.removed"
    case attachmentPromoted = "field.draft.attachment.state.promoted"
    case attachmentCapturing = "field.draft.attachment.state.capturing"
    case attachmentHashing = "field.draft.attachment.state.hashing"
    case attachmentReadyLocal = "field.draft.attachment.state.ready_local"
    case attachmentFailedRetryable = "field.draft.attachment.state.failed_retryable"
    case attachmentFailedFinal = "field.draft.attachment.state.failed_final"
    case attachmentRemovePending = "field.draft.attachment.state.remove_pending"
    case attachmentCommitted = "field.draft.attachment.state.committed"
    case attachmentOrphanQuarantined = "field.draft.attachment.state.orphan_quarantined"

    case sagaPrepared = "field.draft.commit.saga.state.prepared"
    case sagaContentPromotedUnbound = "field.draft.commit.saga.state.content_promoted_unbound"
    case sagaTargetCommitted = "field.draft.commit.saga.state.target_committed"
    case sagaDraftRetirePending = "field.draft.commit.saga.state.draft_retire_pending"
    case sagaDraftRetired = "field.draft.commit.saga.state.draft_retired"
    case sagaConflicted = "field.draft.commit.saga.state.conflicted"
    case sagaRecoveryRequired = "field.draft.commit.saga.state.recovery_required"

    case recoveryResumeAvailable = "field.draft.recovery.state.resume_available"
    case recoveryConflict = "field.draft.recovery.state.conflict"
    case recoveryMissingMedia = "field.draft.recovery.state.missing_media"
    case recoveryLowStorage = "field.draft.recovery.state.low_storage"
    case recoveryProtectedData = "field.draft.recovery.state.protected_data"
    case recoveryUnsupportedCodec = "field.draft.recovery.state.unsupported_codec"
    case recoveryPartialStage = "field.draft.recovery.state.partial_stage"
    case recoveryStaleTarget = "field.draft.recovery.state.stale_target"
    case recoveryRecoveryRequired = "field.draft.recovery.state.recovery_required"

    static var actionableNextStep: Self { .nextStep }
    static var minimumRequirement: Self { .minimumNextRequirement }
    static var savedLocally: Self { .durabilitySavedOnThisIPhone }
    static var readyLocally: Self { .attachmentReadyLocal }

    var localizationKey: LocalizationKeyV1 {
        // This is a closed repository-owned set; registry construction remains
        // the validation boundary for serialized declarations.
        // swiftlint:disable:next force_try
        try! LocalizationKeyV1(rawValue)
    }

    var englishDefaultValue: String {
        switch self {
        case .screen: return "Field draft"
        case .heading: return "Field draft"
        case .durability: return "Draft durability"
        case .durabilityState: return "Durability state"
        case .nextStep: return "Next step"
        case .minimumNextRequirement: return "Minimum requirement"
        case .checkpoint: return "Draft checkpoint"
        case .checkpointState: return "Checkpoint state"
        case .attachment: return "Attachment"
        case .attachmentState: return "Attachment state"
        case .commitSaga: return "Commit progress"
        case .commitSagaState: return "Commit state"
        case .recovery: return "Draft recovery"
        case .recoveryState: return "Recovery state"
        case .recoverySafeAction: return "Safe action"
        case .recoveryFallback: return "Fallback"
        case .durabilityUnsavedChanges: return "Unsaved changes"
        case .durabilitySavingOnThisIPhone: return "Saving on this iPhone"
        case .durabilitySavedOnThisIPhone: return "Saved on this iPhone"
        case .durabilitySaveBlocked: return "Save blocked"
        case .durabilityCommitting: return "Committing"
        case .durabilityConflicted: return "Conflict recorded"
        case .durabilityRecoveryRequired: return "Recovery required"
        case .durabilityCommitted: return "Committed"
        case .durabilityDiscarding: return "Discarding"
        case .durabilityDiscarded: return "Discarded"
        case .checkpointActive: return "Active"
        case .checkpointCommitting: return "Committing"
        case .checkpointConflicted: return "Conflict recorded"
        case .checkpointRecoveryRequired: return "Recovery required"
        case .checkpointCommitted: return "Committed"
        case .checkpointDiscardPending: return "Discard pending"
        case .checkpointDiscarded: return "Discarded"
        case .attachmentSelected: return "Selected"
        case .attachmentLoading: return "Loading"
        case .attachmentStagedLocal: return "Staged locally"
        case .attachmentProcessing: return "Processing"
        case .attachmentReady: return "Ready"
        case .attachmentRetryableFailure: return "Retryable failure"
        case .attachmentBlocked: return "Blocked"
        case .attachmentRemoved: return "Removed"
        case .attachmentPromoted: return "Promoted"
        case .attachmentCapturing: return "Capturing"
        case .attachmentHashing: return "Hashing"
        case .attachmentReadyLocal: return "Ready locally"
        case .attachmentFailedRetryable: return "Retry available"
        case .attachmentFailedFinal: return "Final failure"
        case .attachmentRemovePending: return "Remove pending"
        case .attachmentCommitted: return "Committed"
        case .attachmentOrphanQuarantined: return "Quarantined"
        case .sagaPrepared: return "Prepared"
        case .sagaContentPromotedUnbound: return "Content promoted locally"
        case .sagaTargetCommitted: return "Target committed"
        case .sagaDraftRetirePending: return "Draft retirement pending"
        case .sagaDraftRetired: return "Draft retired"
        case .sagaConflicted: return "Conflict recorded"
        case .sagaRecoveryRequired: return "Recovery required"
        case .recoveryResumeAvailable: return "Resume available"
        case .recoveryConflict: return "Conflict review"
        case .recoveryMissingMedia: return "Missing media"
        case .recoveryLowStorage: return "Low storage"
        case .recoveryProtectedData: return "Protected data unavailable"
        case .recoveryUnsupportedCodec: return "Unsupported format"
        case .recoveryPartialStage: return "Partial stage"
        case .recoveryStaleTarget: return "Stale target"
        case .recoveryRecoveryRequired: return "Recovery required"
        }
    }

    var translatorComment: String {
        switch self {
        case .screen: return "Accessible label for the local field draft surface."
        case .heading: return "Heading for a local field draft."
        case .durability: return "Localized label for truthful local draft durability."
        case .durabilityState: return "Localized label for a recorded draft durability state."
        case .nextStep: return "Actionable label for the next safe local draft step."
        case .minimumNextRequirement: return "Actionable label for the minimum local draft requirement."
        case .checkpoint: return "Localized label for a durable field draft checkpoint."
        case .checkpointState: return "Localized label for the recorded draft checkpoint state."
        case .attachment: return "Localized label for a locally staged draft attachment."
        case .attachmentState: return "Localized label for the recorded attachment staging state."
        case .commitSaga: return "Localized label for the receipt-backed draft commit saga."
        case .commitSagaState: return "Localized label for the recorded commit saga state."
        case .recovery: return "Localized label for local draft recovery."
        case .recoveryState: return "Localized label for a recorded draft recovery state."
        case .recoverySafeAction: return "Actionable label for one safe draft recovery action."
        case .recoveryFallback: return "Localized label for a bounded draft recovery fallback."
        default: return "Accessible text for a recorded local draft or attachment state."
        }
    }
}

enum FieldDraftLocalizationPolicyV1 {
    static let semanticNamespace = "field.draft"
    static let sourceLocale = "en"
    static let shippingLocale = "en"
    static let metadataLocale = "en-US"
    static let testOnlyLocales = TestOnlyPseudoLocaleV1.allCases.map(\.rawValue).sorted()
    static let keys = FieldDraftLocalizationKeyV1.allCases.map(\.rawValue)
    static let reportKeys: [String] = []
    static let semanticIDs = FieldDraftAccessibilityIDV1.allCases.map(\.rawValue)
    static let stateKeys = FieldDraftLocalizationKeyV1.allCases.filter { key in
        key.rawValue.contains(".state.")
    }.map(\.rawValue)
    static let indeterminateStateKeys: Set<String> = Set([
        FieldDraftLocalizationKeyV1.durabilityUnsavedChanges,
        .durabilitySavingOnThisIPhone,
        .durabilitySaveBlocked,
        .durabilityConflicted,
        .durabilityRecoveryRequired,
        .durabilityDiscarding,
        .checkpointConflicted,
        .checkpointRecoveryRequired,
        .checkpointDiscardPending,
        .attachmentSelected,
        .attachmentLoading,
        .attachmentStagedLocal,
        .attachmentProcessing,
        .attachmentRetryableFailure,
        .attachmentBlocked,
        .attachmentCapturing,
        .attachmentHashing,
        .attachmentFailedRetryable,
        .attachmentFailedFinal,
        .attachmentRemovePending,
        .attachmentOrphanQuarantined,
        .sagaPrepared,
        .sagaContentPromotedUnbound,
        .sagaDraftRetirePending,
        .sagaConflicted,
        .sagaRecoveryRequired,
        .recoveryResumeAvailable,
        .recoveryConflict,
        .recoveryMissingMedia,
        .recoveryLowStorage,
        .recoveryProtectedData,
        .recoveryUnsupportedCodec,
        .recoveryPartialStage,
        .recoveryStaleTarget,
        .recoveryRecoveryRequired,
    ].map(\.rawValue))
    static let denyByDefault = true
    static let requiresNonColorStateText = true
    static let requiresTextAndIconForIndeterminateStates = true
    static let requiresActionableNextStep = true
    static let allowsColorOnlyState = false
    static let allowsIconOnlyState = false
    static let allowsMotionOnlyState = false
    static let requiresTextValueForEveryState = true
    static let requiresReceiptReadBackForSavedOnThisIPhone = true
    static let readyLocallyIsStagingOnly = true
    static let excludesEvidenceTruth = true
    static let excludesReportTruth = true
    static let excludesExportTruth = true
    static let excludesSearchTruth = true
    static let excludesSupportAndMetricTruth = true
    static let excludesSecrets = true
    static let excludesCustomerData = true
    static let excludesWorkData = true
    static let excludesPrivateLocators = true
    static let excludesUnsupportedClaims = true

    static let permittedRecordedPhrases: Set<String> = [
        "saved on this iphone", "ready locally", "saving on this iphone",
    ]
    static let prohibitedClaimTokens: Set<String> = [
        "synced", "sync", "synchronized", "synchronised", "synchronize", "cloud",
        "approval", "approve", "approved",
        "authorization", "authorize", "authorized", "verified", "identity", "legal",
        "signature", "compliance", "compliant", "tamperproof", "tamper proof", "tamper",
        "nonrepudiation", "non repudiation",
        "secure", "secured", "sent", "delivered", "complete", "customer", "work",
        "secret", "credential", "password", "token", "locator", "filename", "exif",
        "telemetry", "remote", "upload", "submission", "delivery",
    ]
    static let prohibitedSensitivePhrases: Set<String> = [
        "customer data", "customer information", "customer record", "private data",
        "personal data", "work data", "work item data", "work product", "secret",
        "credential", "credentials", "password", "private locator", "file locator",
        "filename", "exif", "photo metadata",
    ]

    private static func normalized(_ value: String) -> String {
        value
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .split { !$0.isLetter && !$0.isNumber }
            .joined(separator: " ")
    }

    static func containsProhibitedClaim(in values: [String]) -> Bool {
        values.contains { value in
            let normalizedValue = normalized(value)
            if permittedRecordedPhrases.contains(normalizedValue) { return false }
            let bounded = " \(normalizedValue) "
            return prohibitedClaimTokens.contains { token in
                bounded.contains(" \(normalized(token)) ")
            }
        }
    }

    static func containsSensitiveDataLeakage(in values: [String]) -> Bool {
        values.contains { value in
            let normalizedValue = normalized(value)
            let bounded = " \(normalizedValue) "
            return prohibitedSensitivePhrases.contains { phrase in
                bounded.contains(" \(normalized(phrase)) ")
            }
        }
    }

    static func containsCustomerDataLeakage(in values: [String]) -> Bool {
        containsSensitiveDataLeakage(in: values)
    }

    static func containsCustomerOrWorkDataLeakage(in values: [String]) -> Bool {
        containsSensitiveDataLeakage(in: values)
    }
}

enum FieldDraftClaimVocabularyV1 {
    static let prohibitedTokens = FieldDraftLocalizationPolicyV1.prohibitedClaimTokens

    static func containsProhibitedClaim(in values: [String]) -> Bool {
        FieldDraftLocalizationPolicyV1.containsProhibitedClaim(in: values)
    }

    static func containsSensitiveDataLeakage(in values: [String]) -> Bool {
        FieldDraftLocalizationPolicyV1.containsSensitiveDataLeakage(in: values)
    }

    static func containsCustomerDataLeakage(in values: [String]) -> Bool {
        FieldDraftLocalizationPolicyV1.containsCustomerDataLeakage(in: values)
    }

    static func containsCustomerOrWorkDataLeakage(in values: [String]) -> Bool {
        FieldDraftLocalizationPolicyV1.containsCustomerOrWorkDataLeakage(in: values)
    }
}

extension FieldDraftLocalizationKeyV1 {
    static func durabilityStateKey(_ state: FieldDraftDurabilityLocalizationStateV1) -> Self {
        switch state {
        case .unsavedChanges: return .durabilityUnsavedChanges
        case .savingOnThisIPhone: return .durabilitySavingOnThisIPhone
        case .savedOnThisIPhone: return .durabilitySavedOnThisIPhone
        case .saveBlocked: return .durabilitySaveBlocked
        case .committing: return .durabilityCommitting
        case .conflicted: return .durabilityConflicted
        case .recoveryRequired: return .durabilityRecoveryRequired
        case .committed: return .durabilityCommitted
        case .discarding: return .durabilityDiscarding
        case .discarded: return .durabilityDiscarded
        }
    }

    static func checkpointStateKey(_ state: FieldDraftCheckpointLocalizationStateV1) -> Self {
        switch state {
        case .active: return .checkpointActive
        case .committing: return .checkpointCommitting
        case .conflicted: return .checkpointConflicted
        case .recoveryRequired: return .checkpointRecoveryRequired
        case .committed: return .checkpointCommitted
        case .discardPending: return .checkpointDiscardPending
        case .discarded: return .checkpointDiscarded
        }
    }

    static func attachmentStateKey(_ state: FieldDraftAttachmentLocalizationStateV1) -> Self {
        switch state {
        case .selected: return .attachmentSelected
        case .loading: return .attachmentLoading
        case .stagedLocal: return .attachmentStagedLocal
        case .processing: return .attachmentProcessing
        case .ready: return .attachmentReady
        case .retryableFailure: return .attachmentRetryableFailure
        case .blocked: return .attachmentBlocked
        case .removed: return .attachmentRemoved
        case .promoted: return .attachmentPromoted
        case .capturing: return .attachmentCapturing
        case .hashing: return .attachmentHashing
        case .readyLocal: return .attachmentReadyLocal
        case .failedRetryable: return .attachmentFailedRetryable
        case .failedFinal: return .attachmentFailedFinal
        case .removePending: return .attachmentRemovePending
        case .committed: return .attachmentCommitted
        case .orphanQuarantined: return .attachmentOrphanQuarantined
        }
    }

    static func commitSagaStateKey(_ state: FieldDraftCommitSagaLocalizationStateV1) -> Self {
        switch state {
        case .prepared: return .sagaPrepared
        case .contentPromotedUnbound: return .sagaContentPromotedUnbound
        case .targetCommitted: return .sagaTargetCommitted
        case .draftRetirePending: return .sagaDraftRetirePending
        case .draftRetired: return .sagaDraftRetired
        case .conflicted: return .sagaConflicted
        case .recoveryRequired: return .sagaRecoveryRequired
        }
    }

    static func recoveryStateKey(_ state: FieldDraftRecoveryLocalizationStateV1) -> Self {
        switch state {
        case .resumeAvailable: return .recoveryResumeAvailable
        case .conflict: return .recoveryConflict
        case .missingMedia: return .recoveryMissingMedia
        case .lowStorage: return .recoveryLowStorage
        case .protectedData: return .recoveryProtectedData
        case .unsupportedCodec: return .recoveryUnsupportedCodec
        case .partialStage: return .recoveryPartialStage
        case .staleTarget: return .recoveryStaleTarget
        case .recoveryRequired: return .recoveryRecoveryRequired
        }
    }

    static func nextStepKey() -> Self { .nextStep }
    static func minimumRequirementKey() -> Self { .minimumNextRequirement }
}

// Bind the presentation catalog to the canonical C36 domain enums when they
// are available.  The overloads are exhaustive so a newly added durable value
// cannot silently fall through to a generic or raw enum label.
extension FieldDraftLocalizationKeyV1 {
    static func checkpointStateKey(_ state: FieldDraftStateV1) -> Self {
        switch state {
        case .active: return .checkpointActive
        case .committing: return .checkpointCommitting
        case .conflicted: return .checkpointConflicted
        case .recoveryRequired: return .checkpointRecoveryRequired
        case .committed: return .checkpointCommitted
        case .discardPending: return .checkpointDiscardPending
        case .discarded: return .checkpointDiscarded
        }
    }

    static func durabilityStateKey(_ state: DraftDurabilityPresentationStateV1) -> Self {
        switch state {
        case .unsavedChanges: return .durabilityUnsavedChanges
        case .savingOnThisIPhone: return .durabilitySavingOnThisIPhone
        case .savedOnThisIPhone: return .durabilitySavedOnThisIPhone
        case .saveBlocked: return .durabilitySaveBlocked
        case .committing: return .durabilityCommitting
        case .conflicted: return .durabilityConflicted
        case .recoveryRequired: return .durabilityRecoveryRequired
        case .committed: return .durabilityCommitted
        case .discarding: return .durabilityDiscarding
        case .discarded: return .durabilityDiscarded
        }
    }

    static func attachmentStateKey(_ state: AttachmentStagingStateV1) -> Self {
        switch state {
        case .capturing: return .attachmentCapturing
        case .hashing: return .attachmentHashing
        case .processing: return .attachmentProcessing
        case .readyLocal: return .attachmentReadyLocal
        case .failedRetryable: return .attachmentFailedRetryable
        case .failedFinal: return .attachmentFailedFinal
        case .removePending: return .attachmentRemovePending
        case .committed: return .attachmentCommitted
        case .orphanQuarantined: return .attachmentOrphanQuarantined
        }
    }

    static func attachmentPresentationStateKey(
        _ state: DraftAttachmentPresentationStateV1
    ) -> Self {
        switch state {
        case .selected: return .attachmentSelected
        case .loading: return .attachmentLoading
        case .stagedLocal: return .attachmentStagedLocal
        case .processing: return .attachmentProcessing
        case .ready: return .attachmentReady
        case .retryableFailure: return .attachmentRetryableFailure
        case .blocked: return .attachmentBlocked
        case .removed: return .attachmentRemoved
        case .promoted: return .attachmentPromoted
        }
    }

    static func commitSagaStateKey(_ state: DraftCommitSagaStateV1) -> Self {
        switch state {
        case .prepared: return .sagaPrepared
        case .contentPromotedUnbound: return .sagaContentPromotedUnbound
        case .targetCommitted: return .sagaTargetCommitted
        case .draftRetirePending: return .sagaDraftRetirePending
        case .draftRetired: return .sagaDraftRetired
        case .conflicted: return .sagaConflicted
        case .recoveryRequired: return .sagaRecoveryRequired
        }
    }

    static func recoveryStateKey(_ state: DraftRecoveryStatusV1) -> Self {
        switch state {
        case .resumable: return .recoveryResumeAvailable
        case .conflict: return .recoveryConflict
        case .missingMedia: return .recoveryMissingMedia
        case .lowStorage: return .recoveryLowStorage
        case .protectedData: return .recoveryProtectedData
        case .unsupportedCodec: return .recoveryUnsupportedCodec
        case .partialStage: return .recoveryPartialStage
        case .staleTarget: return .recoveryStaleTarget
        case .recoveryRequired: return .recoveryRecoveryRequired
        }
    }
}

/// C19's presentation surface is deliberately separate from the durable
/// measurement contracts.  The recorded fixed-point value, unit identity,
/// calibration status, and quality result remain machine facts; these keys
/// provide stable English labels for a local report reader only.
enum MeasurementIntegrityLocalizationKeyV1: String, CaseIterable, Codable, Sendable {
    case heading = "measurement.integrity.heading"
    case instrument = "measurement.integrity.instrument"
    case instrumentKind = "measurement.integrity.instrument.kind"
    case instrumentKindMeasuring = "measurement.integrity.instrument.kind.measuring"
    case instrumentKindReference = "measurement.integrity.instrument.kind.reference"
    case instrumentKindOther = "measurement.integrity.instrument.kind.other"
    case instrumentLifecycle = "measurement.integrity.instrument.lifecycle"
    case instrumentLifecycleActive = "measurement.integrity.instrument.lifecycle.active"
    case instrumentLifecycleOutOfService = "measurement.integrity.instrument.lifecycle.out_of_service"
    case instrumentLifecycleRetired = "measurement.integrity.instrument.lifecycle.retired"
    case calibration = "measurement.integrity.calibration"
    case calibrationStatus = "measurement.integrity.calibration.status"
    case calibrationNotRequired = "measurement.integrity.calibration.status.not_required"
    case calibrationCurrent = "measurement.integrity.calibration.status.current"
    case calibrationExpired = "measurement.integrity.calibration.status.expired"
    case calibrationUnknown = "measurement.integrity.calibration.status.unknown"
    case calibrationOutOfService = "measurement.integrity.calibration.status.out_of_service"
    case calibrationBasis = "measurement.integrity.calibration.basis"
    case calibrationBasisDeclared = "measurement.integrity.calibration.basis.declared_not_required"
    case calibrationBasisEvidence = "measurement.integrity.calibration.basis.referenced_evidence"
    case calibrationBasisLocal = "measurement.integrity.calibration.basis.locally_recorded"
    case calibrationBasisUnknown = "measurement.integrity.calibration.basis.unknown"
    case capture = "measurement.integrity.capture"
    case captureValue = "measurement.integrity.capture.value"
    case captureUnit = "measurement.integrity.capture.unit"
    case captureSource = "measurement.integrity.capture.source"
    case captureSourceManual = "measurement.integrity.capture.source.manual_entry"
    case captureSourceLocalObservation = "measurement.integrity.capture.source.local_observation"
    case series = "measurement.integrity.series"
    case seriesState = "measurement.integrity.series.state"
    case seriesOpen = "measurement.integrity.series.state.open"
    case seriesFinalized = "measurement.integrity.series.state.finalized"
    case `protocol` = "measurement.integrity.protocol"
    case quality = "measurement.integrity.quality"
    case qualityResult = "measurement.integrity.quality.result"
    case qualityClear = "measurement.integrity.quality.result.clear"
    case qualityReviewRequired = "measurement.integrity.quality.result.review_required"
    case qualityOverridden = "measurement.integrity.quality.result.overridden"
    case qualityReason = "measurement.integrity.quality.reason"
    case qualityReasonDeclaredChecksClear = "measurement.integrity.quality.reason.declared_checks_clear"
    case qualityReasonCalibrationNotRequired = "measurement.integrity.quality.reason.calibration_not_required"
    case qualityReasonCalibrationExpired = "measurement.integrity.quality.reason.calibration_expired"
    case qualityReasonCalibrationUnknown = "measurement.integrity.quality.reason.calibration_unknown"
    case qualityReasonInstrumentOutOfService = "measurement.integrity.quality.reason.instrument_out_of_service"
    case qualityReasonMissingUncertainty = "measurement.integrity.quality.reason.missing_uncertainty"
    case qualityReasonUncertaintyCrossesBoundary = "measurement.integrity.quality.reason.uncertainty_crosses_boundary"
    case qualityReasonIncompleteSampleSet = "measurement.integrity.quality.reason.incomplete_sample_set"
    case qualityReasonDuplicateSample = "measurement.integrity.quality.reason.duplicate_sample"
    case qualityReasonRetainedOutlier = "measurement.integrity.quality.reason.retained_outlier"
    case qualityReasonObservationLimitation = "measurement.integrity.quality.reason.observation_limitation"
    case qualityReasonHumanOverride = "measurement.integrity.quality.reason.human_override"
    case nextStep = "measurement.integrity.next_step"

    static var measurementHeading: Self { .heading }
    static var instrumentReference: Self { .instrument }
    static var calibrationStatusLabel: Self { .calibrationStatus }
    static var exactValue: Self { .captureValue }
    static var exactUnit: Self { .captureUnit }
    static var qualityDisposition: Self { .qualityResult }
    static var actionableNextStep: Self { .nextStep }

    var localizationKey: LocalizationKeyV1 {
        // The enum is closed and checked again when the bundled registry is
        // built; force-try here cannot receive an unvalidated key.
        // swiftlint:disable:next force_try
        try! LocalizationKeyV1(rawValue)
    }

    var englishDefaultValue: String {
        switch self {
        case .heading: return "Measurement record"
        case .instrument: return "Instrument"
        case .instrumentKind: return "Instrument type"
        case .instrumentKindMeasuring: return "Measuring instrument"
        case .instrumentKindReference: return "Reference standard"
        case .instrumentKindOther: return "Other declared type"
        case .instrumentLifecycle: return "Instrument lifecycle"
        case .instrumentLifecycleActive: return "Active (recorded)"
        case .instrumentLifecycleOutOfService: return "Out of service (recorded)"
        case .instrumentLifecycleRetired: return "Retired (recorded)"
        case .calibration: return "Calibration record"
        case .calibrationStatus: return "Calibration status"
        case .calibrationNotRequired: return "Not required (recorded)"
        case .calibrationCurrent: return "Current at capture (recorded)"
        case .calibrationExpired: return "Expired at capture (recorded)"
        case .calibrationUnknown: return "Unknown at capture"
        case .calibrationOutOfService: return "Out of service at capture"
        case .calibrationBasis: return "Calibration basis"
        case .calibrationBasisDeclared: return "Declared not required"
        case .calibrationBasisEvidence: return "Referenced local evidence"
        case .calibrationBasisLocal: return "Locally recorded status"
        case .calibrationBasisUnknown: return "Unknown basis"
        case .capture: return "Measurement capture"
        case .captureValue: return "Recorded value"
        case .captureUnit: return "Recorded unit"
        case .captureSource: return "Capture source"
        case .captureSourceManual: return "Manual entry"
        case .captureSourceLocalObservation: return "Local instrument observation"
        case .series: return "Measurement series"
        case .seriesState: return "Series state"
        case .seriesOpen: return "Open (recorded)"
        case .seriesFinalized: return "Finalized (recorded)"
        case .`protocol`: return "Measurement protocol"
        case .quality: return "Quality review"
        case .qualityResult: return "Quality result"
        case .qualityClear: return "Clear (recorded)"
        case .qualityReviewRequired: return "Review required"
        case .qualityOverridden: return "Overridden by recorded review"
        case .qualityReason: return "Quality reason"
        case .qualityReasonDeclaredChecksClear: return "Declared checks clear"
        case .qualityReasonCalibrationNotRequired: return "Calibration not required"
        case .qualityReasonCalibrationExpired: return "Calibration expired"
        case .qualityReasonCalibrationUnknown: return "Calibration unknown"
        case .qualityReasonInstrumentOutOfService: return "Instrument out of service"
        case .qualityReasonMissingUncertainty: return "Uncertainty not recorded"
        case .qualityReasonUncertaintyCrossesBoundary: return "Uncertainty crosses a boundary"
        case .qualityReasonIncompleteSampleSet: return "Sample set incomplete"
        case .qualityReasonDuplicateSample: return "Duplicate sample"
        case .qualityReasonRetainedOutlier: return "Outlier retained in the record"
        case .qualityReasonObservationLimitation: return "Observation limitation recorded"
        case .qualityReasonHumanOverride: return "Recorded human override"
        case .nextStep: return "Next recorded step"
        }
    }

    var translatorComment: String {
        "English label for a recorded local measurement-integrity fact; do not infer compliance, safety, certification, or automatic pass/fail."
    }
}

extension MeasurementIntegrityLocalizationKeyV1 {
    static func instrumentKindKey(_ value: InstrumentKindV1) -> Self {
        switch value {
        case .illuminanceMeter, .multimeter, .thermometer:
            return .instrumentKindMeasuring
        case .otherTypedLocalInstrument:
            return .instrumentKindOther
        }
    }

    static func instrumentLifecycleKey(_ value: InstrumentLifecycleStateV1) -> Self {
        switch value {
        case .active: return .instrumentLifecycleActive
        case .outOfService: return .instrumentLifecycleOutOfService
        case .retired: return .instrumentLifecycleRetired
        }
    }

    static func calibrationStatusKey(_ value: CalibrationStatusV1) -> Self {
        switch value {
        case .notRequired: return .calibrationNotRequired
        case .current: return .calibrationCurrent
        case .expired: return .calibrationExpired
        case .unknown: return .calibrationUnknown
        case .outOfService: return .calibrationOutOfService
        }
    }

    static func calibrationBasisKey(_ value: CalibrationBasisV1) -> Self {
        switch value {
        case .declaredNotRequired: return .calibrationBasisDeclared
        case .referencedEvidence: return .calibrationBasisEvidence
        case .locallyRecordedStatus: return .calibrationBasisLocal
        case .unknown: return .calibrationBasisUnknown
        }
    }

    static func captureSourceKey(_ value: MeasurementCaptureSourceModeV1) -> Self {
        switch value {
        case .manualEntry: return .captureSourceManual
        case .localObservation: return .captureSourceLocalObservation
        }
    }

    static func seriesStateKey(_ value: MeasurementSeriesStateV1) -> Self {
        switch value {
        case .open: return .seriesOpen
        case .finalized: return .seriesFinalized
        }
    }

    static func qualityResultKey(_ value: MeasurementQualityResultV1) -> Self {
        switch value {
        case .clear: return .qualityClear
        case .reviewRequired: return .qualityReviewRequired
        case .overridden: return .qualityOverridden
        }
    }

    static func qualityReasonKey(_ value: MeasurementQualityReasonV1) -> Self {
        switch value {
        case .declaredChecksClear: return .qualityReasonDeclaredChecksClear
        case .calibrationNotRequired: return .qualityReasonCalibrationNotRequired
        case .calibrationExpired: return .qualityReasonCalibrationExpired
        case .calibrationUnknown: return .qualityReasonCalibrationUnknown
        case .instrumentOutOfService: return .qualityReasonInstrumentOutOfService
        case .missingUncertainty: return .qualityReasonMissingUncertainty
        case .uncertaintyCrossesBoundary: return .qualityReasonUncertaintyCrossesBoundary
        case .incompleteSampleSet: return .qualityReasonIncompleteSampleSet
        case .duplicateSample: return .qualityReasonDuplicateSample
        case .retainedOutlier: return .qualityReasonRetainedOutlier
        case .observationLimitation: return .qualityReasonObservationLimitation
        case .humanOverride: return .qualityReasonHumanOverride
        }
    }
}

enum MeasurementIntegrityLocalizationPolicyV1 {
    static let semanticNamespace = "measurement.integrity"
    static let sourceLocale = "en"
    static let shippingLocale = "en"
    static let metadataLocale = "en-US"
    static let testOnlyLocales = TestOnlyPseudoLocaleV1.allCases.map(\.rawValue).sorted()
    static let keys = MeasurementIntegrityLocalizationKeyV1.allCases.map(\.rawValue)
    static let stateKeys = MeasurementIntegrityLocalizationKeyV1.allCases.filter {
        $0.rawValue.contains(".status.") || $0.rawValue.contains(".state.")
            || $0.rawValue.contains(".result.") || $0.rawValue.contains(".reason.")
            || $0.rawValue.contains(".lifecycle.") || $0.rawValue.contains(".source.")
    }.map(\.rawValue)
    static let denyByDefault = true
    static let requiresExactFixedPointValue = true
    static let allowsLocalizedUnitIdentity = false
    static let requiresNonColorStateText = true
    static let requiresTextAndIconForIndeterminateStates = true
    static let requiresActionableNextStep = true
    static let allowsColorOnlyState = false
    static let allowsIconOnlyState = false
    static let allowsMotionOnlyState = false
    static let excludesOpaqueSerial = true
    static let excludesOperatorSnapshot = true
    static let excludesEvidenceLocators = true
    static let excludesUnsupportedClaims = true

    static let prohibitedClaimPhrases: Set<String> = [
        "pass", "passed", "automatic pass", "fail", "failed", "compliant", "compliance",
        "certified", "certification", "safe", "safety", "approved", "approval",
        "authorized", "authorization", "verified", "verification", "secure", "secured",
        "sent", "delivered", "operator", "serial", "customer data", "work data",
        "telemetry", "remote calibration", "hardware integration", "predictive maintenance",
        "diagnosis", "ai diagnosis", "cloud state",
    ]

    static func containsProhibitedClaim(in values: [String]) -> Bool {
        values.contains { value in
            let normalized = value
                .folding(options: [.caseInsensitive, .diacriticInsensitive],
                         locale: Locale(identifier: "en_US_POSIX"))
                .split { !$0.isLetter && !$0.isNumber }
                .joined(separator: " ")
            let bounded = " \(normalized) "
            return prohibitedClaimPhrases.contains { bounded.contains(" \($0) ") }
        }
    }

    static func containsCustomerOrWorkDataLeakage(in values: [String]) -> Bool {
        values.contains { value in
            let normalized = value
                .folding(options: [.caseInsensitive, .diacriticInsensitive],
                         locale: Locale(identifier: "en_US_POSIX"))
                .split { !$0.isLetter && !$0.isNumber }
                .joined(separator: " ")
            let bounded = " \(normalized) "
            return [" customer data ", " work data ", " customer information ", " private data "]
                .contains { bounded.contains($0) }
        }
    }
}

typealias MeasurementIntegrityClaimVocabularyV1 = MeasurementIntegrityLocalizationPolicyV1

/// C20's report-facing labels describe a recorded manual redaction review and
/// its bounded projection state.  They never describe the original bytes,
/// reviewer identity, or a legal/anonymization outcome.
enum PrivacyTransformLocalizationKeyV1: String, CaseIterable, Codable, Sendable {
    case heading = "privacy.transform.heading"
    case redactionDeclaration = "privacy.transform.redaction.declaration"
    case derivative = "privacy.transform.derivative"
    case derivativeOnly = "privacy.transform.derivative.only"
    case review = "privacy.transform.review"
    case reviewApproved = "privacy.transform.review.approved"
    case reviewRejected = "privacy.transform.review.rejected"
    case freshness = "privacy.transform.freshness"
    case freshnessCurrent = "privacy.transform.freshness.current"
    case projection = "privacy.transform.projection"
    case projectionAllowed = "privacy.transform.projection.allowed"
    case projectionDenied = "privacy.transform.projection.denied"
    case denialMissingReview = "privacy.transform.projection.denial.missing_review"
    case denialRejected = "privacy.transform.projection.denial.rejected"
    case denialStale = "privacy.transform.projection.denial.stale"
    case denialWrongAudience = "privacy.transform.projection.denial.wrong_audience"
    case denialWrongPolicy = "privacy.transform.projection.denial.wrong_policy"
    case denialSourceChanged = "privacy.transform.projection.denial.source_changed"
    case denialDigestMismatch = "privacy.transform.projection.denial.digest_mismatch"
    case denialMetadataNotSanitized = "privacy.transform.projection.denial.metadata_not_sanitized"
    case originalAccessSeparate = "privacy.transform.original.access.separate"
    case nextStep = "privacy.transform.next_step"

    var localizationKey: LocalizationKeyV1 {
        // The enum is closed and every raw value is checked by the bundled
        // registry before publication.
        // swiftlint:disable:next force_try
        try! LocalizationKeyV1(rawValue)
    }

    var englishDefaultValue: String {
        switch self {
        case .heading: return "Redaction review"
        case .redactionDeclaration: return "Manual redaction declaration"
        case .derivative: return "Reviewed derivative"
        case .derivativeOnly: return "Derivative only"
        case .review: return "Review state"
        case .reviewApproved: return "Approved review recorded"
        case .reviewRejected: return "Rejected review recorded"
        case .freshness: return "Derivative freshness"
        case .freshnessCurrent: return "Current for the recorded source"
        case .projection: return "Audience projection"
        case .projectionAllowed: return "Derivative available for this audience"
        case .projectionDenied: return "Derivative not available"
        case .denialMissingReview: return "Review is required"
        case .denialRejected: return "Review was rejected"
        case .denialStale: return "Derivative is stale"
        case .denialWrongAudience: return "Audience does not match"
        case .denialWrongPolicy: return "Policy does not match"
        case .denialSourceChanged: return "Source changed; review again"
        case .denialDigestMismatch: return "Digest does not match"
        case .denialMetadataNotSanitized: return "Metadata sanitation is incomplete"
        case .originalAccessSeparate: return "Original access is separate"
        case .nextStep: return "Next recorded step"
        }
    }

    var translatorComment: String {
        "English label for a recorded manual privacy-transform review state; do not claim legal compliance, guaranteed anonymization, or an automatic privacy decision."
    }
}

extension PrivacyTransformLocalizationKeyV1 {
    static func reviewKey(_ decision: PrivacyReviewDecisionV1) -> Self {
        switch decision {
        case .approved: return .reviewApproved
        case .rejected: return .reviewRejected
        }
    }

    static func freshnessKey(_ state: PrivacyTransformStaleStateV1) -> Self {
        switch state {
        case .current: return .freshnessCurrent
        case .sourceChanged: return .denialSourceChanged
        case .policyChanged: return .denialWrongPolicy
        case .expired: return .denialStale
        }
    }

    static func denialKey(_ denial: PrivacyProjectionDenialV1) -> Self {
        switch denial {
        case .missingReview: return .denialMissingReview
        case .rejected: return .denialRejected
        case .stale: return .denialStale
        case .wrongAudience: return .denialWrongAudience
        case .wrongPolicy: return .denialWrongPolicy
        case .sourceChanged: return .denialSourceChanged
        case .digestMismatch: return .denialDigestMismatch
        case .metadataNotSanitized: return .denialMetadataNotSanitized
        }
    }
}

enum PrivacyTransformLocalizationPolicyV1 {
    static let semanticNamespace = "privacy.transform"
    static let sourceLocale = "en"
    static let shippingLocale = "en"
    static let metadataLocale = "en-US"
    static let testOnlyLocales = TestOnlyPseudoLocaleV1.allCases.map(\.rawValue).sorted()
    static let keys = PrivacyTransformLocalizationKeyV1.allCases.map(\.rawValue)
    static let stateKeys = PrivacyTransformLocalizationKeyV1.allCases
        .filter { $0.rawValue.contains(".review.") || $0.rawValue.contains(".freshness.") || $0.rawValue.contains(".denial.") || $0 == .projectionAllowed || $0 == .projectionDenied }
        .map(\.rawValue)
    static let denyByDefault = true
    static let requiresExplicitRedactionDeclaration = true
    static let requiresApprovedNonStaleDerivative = true
    static let requiresNonColorStateText = true
    static let requiresTextAndIconForIndeterminateStates = true
    static let requiresActionableNextStep = true
    static let allowsColorOnlyState = false
    static let allowsIconOnlyState = false
    static let allowsMotionOnlyState = false
    static let excludesOriginalBytes = true
    static let excludesOriginalReferences = true
    static let excludesDerivativeBytes = true
    static let excludesReviewerIdentity = true
    static let excludesReviewRationale = true
    static let excludesUnsupportedClaims = true

    static let prohibitedClaimPhrases: Set<String> = [
        "guaranteed anonymization", "guaranteed anonymous", "anonymized", "anonymous",
        "legal compliance", "compliant", "certified", "tamperproof", "nonrepudiation",
        "verified identity", "secure", "sent", "delivered", "automatic privacy decision",
    ]

    private static func normalized(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        .split { !$0.isLetter && !$0.isNumber }
        .joined(separator: " ")
    }

    static func containsProhibitedClaim(in values: [String]) -> Bool {
        values.contains { value in
            let bounded = " \(normalized(value)) "
            prohibitedClaimPhrases.contains { bounded.contains(" \($0) ") }
        }
    }

    static func containsCustomerOrWorkDataLeakage(in values: [String]) -> Bool {
        values.contains { value in
            let bounded = " \(normalized(value)) "
            [" customer data ", " customer information ", " work data ", " private data ", " credentials ", " password ", " token "]
                .contains { bounded.contains($0) }
        }
    }
}

typealias PrivacyTransformClaimVocabularyV1 = PrivacyTransformLocalizationPolicyV1

// MARK: - C21 client admission and package lifecycle labels

/// English-only labels for the closed C21 admission and package lifecycle
/// values.  These describe recorded local capability facts only; they never
/// imply a device, user, account, endpoint, provider, or remote delivery.
enum ClientCapabilityLocalizationKeyV1: String, CaseIterable, Codable, Sendable {
    case heading = "client.capability.heading"
    case admission = "client.capability.admission"
    case admissionReadWrite = "client.capability.admission.read_write"
    case admissionReadOnly = "client.capability.admission.read_only"
    case admissionMigrationRequired = "client.capability.admission.migration_required"
    case admissionQuarantine = "client.capability.admission.quarantine"
    case admissionReject = "client.capability.admission.reject"
    case reason = "client.capability.reason"
    case reasonExactMatch = "client.capability.reason.exact_match"
    case reasonReadOnlyCompatibility = "client.capability.reason.read_only_compatibility"
    case reasonMigrationAvailable = "client.capability.reason.migration_available"
    case reasonUnsupportedRequiredRange = "client.capability.reason.unsupported_required_range"
    case reasonUnknownCapability = "client.capability.reason.unknown_capability"
    case reasonPackageWithdrawn = "client.capability.reason.package_withdrawn"
    case reasonPackageQuarantined = "client.capability.reason.package_quarantined"
    case reasonPackageSuperseded = "client.capability.reason.package_superseded"
    case reasonDigestMismatch = "client.capability.reason.digest_mismatch"
    case reasonStalePolicy = "client.capability.reason.stale_policy"
    case reasonOperationBlocked = "client.capability.reason.operation_blocked"
    case lifecycleHeading = "package.lifecycle.heading"
    case lifecycleState = "package.lifecycle.state"
    case stateActive = "package.lifecycle.state.active"
    case stateDeprecated = "package.lifecycle.state.deprecated"
    case stateWithdrawn = "package.lifecycle.state.withdrawn"
    case stateQuarantined = "package.lifecycle.state.quarantined"
    case stateSuperseded = "package.lifecycle.state.superseded"
    case lifecycleOperation = "package.lifecycle.operation"
    case operationStart = "package.lifecycle.operation.start"
    case operationResume = "package.lifecycle.operation.resume"
    case operationFinalize = "package.lifecycle.operation.finalize"
    case operationAmend = "package.lifecycle.operation.amend"
    case operationView = "package.lifecycle.operation.view"
    case operationExport = "package.lifecycle.operation.export"
    case operationRestore = "package.lifecycle.operation.restore"
    case operationReplay = "package.lifecycle.operation.replay"
    case operationUpgradeDraft = "package.lifecycle.operation.upgrade_draft"
    case historicExport = "package.lifecycle.historic.export"
    case withdrawal = "package.lifecycle.withdrawal"
    case blocked = "package.lifecycle.blocked"
    case nextStep = "client.capability.next_step"

    var localizationKey: LocalizationKeyV1 {
        // The closed enum is checked against the bundled catalog before use.
        // swiftlint:disable:next force_try
        try! LocalizationKeyV1(rawValue)
    }

    var englishDefaultValue: String {
        switch self {
        case .heading: return "Client capability admission"
        case .admission: return "Admission"
        case .admissionReadWrite: return "Read and write admitted"
        case .admissionReadOnly: return "Read-only admitted"
        case .admissionMigrationRequired: return "Migration required"
        case .admissionQuarantine: return "Quarantine required"
        case .admissionReject: return "Rejected"
        case .reason: return "Recorded reason"
        case .reasonExactMatch: return "Exact capability match"
        case .reasonReadOnlyCompatibility: return "Read-only compatibility"
        case .reasonMigrationAvailable: return "Migration is available"
        case .reasonUnsupportedRequiredRange: return "Required capability range is unsupported"
        case .reasonUnknownCapability: return "Capability is unknown"
        case .reasonPackageWithdrawn: return "Package release is withdrawn"
        case .reasonPackageQuarantined: return "Package release is quarantined"
        case .reasonPackageSuperseded: return "Package release is superseded"
        case .reasonDigestMismatch: return "Recorded digest does not match"
        case .reasonStalePolicy: return "Capability policy is stale"
        case .reasonOperationBlocked: return "Operation is blocked"
        case .lifecycleHeading: return "Package lifecycle"
        case .lifecycleState: return "Lifecycle state"
        case .stateActive: return "Active"
        case .stateDeprecated: return "Deprecated"
        case .stateWithdrawn: return "Withdrawn"
        case .stateQuarantined: return "Quarantined"
        case .stateSuperseded: return "Superseded"
        case .lifecycleOperation: return "Lifecycle operation"
        case .operationStart: return "Start"
        case .operationResume: return "Resume"
        case .operationFinalize: return "Finalize"
        case .operationAmend: return "Amend"
        case .operationView: return "View"
        case .operationExport: return "Export"
        case .operationRestore: return "Restore"
        case .operationReplay: return "Replay"
        case .operationUpgradeDraft: return "Upgrade draft"
        case .historicExport: return "Historic export remains available"
        case .withdrawal: return "Withdrawal blocks new work"
        case .blocked: return "Operation blocked by admission"
        case .nextStep: return "Next recorded step"
        }
    }

    var translatorComment: String {
        "English label for a recorded local client capability or package lifecycle state; do not imply device, user, account, endpoint, provider, remote delivery, acknowledgement, legal, compliance, or security claims."
    }
}

extension ClientCapabilityLocalizationKeyV1 {
    static func admissionKey(_ value: ClientAdmissionV1) -> Self {
        switch value {
        case .readWrite: return .admissionReadWrite
        case .readOnly: return .admissionReadOnly
        case .migrationRequired: return .admissionMigrationRequired
        case .quarantine: return .admissionQuarantine
        case .reject: return .admissionReject
        }
    }

    static func reasonKey(_ value: ClientCapabilityReasonV1) -> Self {
        switch value {
        case .exactMatch: return .reasonExactMatch
        case .readOnlyCompatibility: return .reasonReadOnlyCompatibility
        case .migrationAvailable: return .reasonMigrationAvailable
        case .unsupportedRequiredRange: return .reasonUnsupportedRequiredRange
        case .unknownCapability: return .reasonUnknownCapability
        case .packageWithdrawn: return .reasonPackageWithdrawn
        case .packageQuarantined: return .reasonPackageQuarantined
        case .packageSuperseded: return .reasonPackageSuperseded
        case .digestMismatch: return .reasonDigestMismatch
        case .stalePolicy: return .reasonStalePolicy
        case .operationBlocked: return .reasonOperationBlocked
        }
    }

    static func stateKey(_ value: PackageLifecycleStateV1) -> Self {
        switch value {
        case .active: return .stateActive
        case .deprecated: return .stateDeprecated
        case .withdrawn: return .stateWithdrawn
        case .quarantined: return .stateQuarantined
        case .superseded: return .stateSuperseded
        }
    }

    static func operationKey(_ value: PackageLifecycleOperationV1) -> Self {
        switch value {
        case .start: return .operationStart
        case .resume: return .operationResume
        case .finalize: return .operationFinalize
        case .amend: return .operationAmend
        case .view: return .operationView
        case .export: return .operationExport
        case .restore: return .operationRestore
        case .replay: return .operationReplay
        case .upgradeDraft: return .operationUpgradeDraft
        }
    }
}

enum ClientCapabilityLocalizationPolicyV1 {
    static let semanticNamespace = "client.capability"
    static let sourceLocale = "en"
    static let shippingLocale = "en"
    static let metadataLocale = "en-US"
    static let testOnlyLocales = TestOnlyPseudoLocaleV1.allCases.map(\.rawValue).sorted()
    static let keys = ClientCapabilityLocalizationKeyV1.allCases.map(\.rawValue)
    static let stateKeys = ClientCapabilityLocalizationKeyV1.allCases
        .filter {
            $0.rawValue.contains(".admission.")
                || $0.rawValue.contains(".reason.")
                || $0.rawValue.contains(".state.")
                || $0.rawValue.contains(".operation.")
                || $0 == .historicExport
                || $0 == .withdrawal
                || $0 == .blocked
        }
        .map(\.rawValue)
    static let denyByDefault = true
    static let requiresTruthfulClosedValues = true
    static let requiresHistoricExportAfterWithdrawal = true
    static let requiresNonColorStateText = true
    static let requiresTextAndIconForIndeterminateStates = true
    static let requiresActionableNextStep = true
    static let allowsColorOnlyState = false
    static let allowsIconOnlyState = false
    static let allowsMotionOnlyState = false
    static let excludesDeviceIdentity = true
    static let excludesUserIdentity = true
    static let excludesEndpointProviderAccount = true
    static let excludesRemoteDeliveryAcknowledgement = true
    static let excludesUnsupportedClaims = true

    static let prohibitedClaimPhrases: Set<String> = [
        "device identity", "user identity", "endpoint", "provider", "account",
        "remote delivery", "remote acknowledgment", "remote acknowledgement",
        "heartbeat", "upload", "sent", "delivered", "acknowledgment",
        "acknowledgement", "credential", "password", "legal compliance",
        "compliant", "certified", "tamperproof", "nonrepudiation", "secure",
        "verified identity", "guaranteed", "automatic decision",
    ]

    private static func normalized(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        .split { !$0.isLetter && !$0.isNumber }
        .joined(separator: " ")
    }

    static func containsProhibitedClaim(in values: [String]) -> Bool {
        values.contains { value in
            let bounded = " \(normalized(value)) "
            prohibitedClaimPhrases.contains { bounded.contains(" \($0) ") }
        }
    }

    static func containsCustomerOrWorkDataLeakage(in values: [String]) -> Bool {
        values.contains { value in
            let bounded = " \(normalized(value)) "
            [
                " customer data ", " customer information ", " work data ",
                " private data ", " credentials ", " token ", " tenant ",
            ].contains { bounded.contains($0) }
        }
    }
}

typealias ClientCapabilityClaimVocabularyV1 = ClientCapabilityLocalizationPolicyV1

// MARK: - C23 version-bound field-reference labels

/// English-only keys for the immutable field-reference release/binding
/// projection.  Raw release, binding, content, and locator identifiers are
/// never used as display labels and labels never participate in identity.
enum FieldReferenceLocalizationKeyV1: String, CaseIterable, Codable, Sendable {
    case heading = "field.reference.heading"
    case provenance = "field.reference.provenance"
    case pack = "field.reference.pack"
    case kind = "field.reference.kind"
    case kindSOP = "field.reference.kind.sop"
    case kindManual = "field.reference.kind.manual"
    case kindDrawing = "field.reference.kind.drawing"
    case kindSpecification = "field.reference.kind.specification"
    case semanticVersion = "field.reference.semantic-version"
    case release = "field.reference.release"
    case releaseActive = "field.reference.release.active"
    case releaseRevoked = "field.reference.release.revoked"
    case binding = "field.reference.binding"
    case subject = "field.reference.subject"
    case subjectWorkPacket = "field.reference.subject.work-packet"
    case subjectRoundSession = "field.reference.subject.round-session"
    case subjectActive = "field.reference.subject.active"
    case subjectFinalized = "field.reference.subject.finalized"
    case provenanceKind = "field.reference.provenance.kind"
    case provenanceLicensed = "field.reference.provenance.licensed"
    case provenanceSynthetic = "field.reference.provenance.synthetic"
    case licenseScope = "field.reference.provenance.license-scope"
    case licenseLocalUseOnly = "field.reference.provenance.license-scope.local-use-only"
    case licenseCitationAllowed = "field.reference.provenance.license-scope.citation-allowed"
    case licenseCitationAndExportAllowed = "field.reference.provenance.license-scope.citation-and-export-allowed"
    case licenseRestricted = "field.reference.provenance.license-scope.restricted"
    case availability = "field.reference.availability"
    case availabilityReadyOffline = "field.reference.availability.ready-offline"
    case availabilityMissingBytes = "field.reference.availability.missing-bytes"
    case availabilityExpired = "field.reference.availability.expired"
    case availabilityRevoked = "field.reference.availability.revoked"
    case availabilitySuperseded = "field.reference.availability.superseded"
    case availabilityStaleBinding = "field.reference.availability.stale-binding"
    case availabilityProtectedDataUnavailable = "field.reference.availability.protected-data-unavailable"
    case availabilityUnavailable = "field.reference.availability.unavailable"
    case requiredContent = "field.reference.required-content"
    case missingContent = "field.reference.missing-content"
    case nextStep = "field.reference.next-step"

    var localizationKey: LocalizationKeyV1 {
        // The bundled catalog validates this closed enum before publication.
        // swiftlint:disable:next force_try
        try! LocalizationKeyV1(rawValue)
    }

    var englishDefaultValue: String {
        switch self {
        case .heading: return "Field reference"
        case .provenance: return "Reference provenance"
        case .pack: return "Reference pack"
        case .kind: return "Reference kind"
        case .kindSOP: return "Standard operating procedure"
        case .kindManual: return "Manual"
        case .kindDrawing: return "Drawing"
        case .kindSpecification: return "Specification"
        case .semanticVersion: return "Reference version"
        case .release: return "Reference release"
        case .releaseActive: return "Release active"
        case .releaseRevoked: return "Release revoked"
        case .binding: return "Work binding"
        case .subject: return "Bound work"
        case .subjectWorkPacket: return "Work packet"
        case .subjectRoundSession: return "Round session"
        case .subjectActive: return "Active work"
        case .subjectFinalized: return "Finalized work"
        case .provenanceKind: return "Provenance type"
        case .provenanceLicensed: return "Licensed source"
        case .provenanceSynthetic: return "Synthetic source"
        case .licenseScope: return "License scope"
        case .licenseLocalUseOnly: return "Local use only"
        case .licenseCitationAllowed: return "Citation allowed"
        case .licenseCitationAndExportAllowed: return "Citation and export allowed"
        case .licenseRestricted: return "Restricted use"
        case .availability: return "Reference availability"
        case .availabilityReadyOffline: return "Ready offline"
        case .availabilityMissingBytes: return "Required bytes missing"
        case .availabilityExpired: return "Reference expired"
        case .availabilityRevoked: return "Reference revoked"
        case .availabilitySuperseded: return "Reference superseded"
        case .availabilityStaleBinding: return "Binding is stale"
        case .availabilityProtectedDataUnavailable: return "Protected data unavailable"
        case .availabilityUnavailable: return "Reference unavailable"
        case .requiredContent: return "Required reference bytes"
        case .missingContent: return "Missing required bytes"
        case .nextStep: return "Review the recorded reference state"
        }
    }

    var translatorComment: String {
        "English label for a recorded local field-reference release, binding, provenance, license scope, or offline availability state; never imply authority, compliance, observation, secure storage, remote delivery, customer data, or work identity."
    }
}

extension FieldReferenceLocalizationKeyV1 {
    static func kindKey(_ value: FieldReferenceKindV1) -> Self {
        switch value {
        case .sop: return .kindSOP
        case .manual: return .kindManual
        case .drawing: return .kindDrawing
        case .specification: return .kindSpecification
        }
    }

    static func availabilityKey(_ value: FieldReferenceAvailabilityV1) -> Self {
        switch value {
        case .readyOffline: return .availabilityReadyOffline
        case .missingBytes: return .availabilityMissingBytes
        case .expired: return .availabilityExpired
        case .revoked: return .availabilityRevoked
        case .superseded: return .availabilitySuperseded
        case .staleBinding: return .availabilityStaleBinding
        case .protectedDataUnavailable: return .availabilityProtectedDataUnavailable
        case .unavailable: return .availabilityUnavailable
        }
    }

    static func subjectKindKey(_ value: FieldReferenceSubjectKindV1) -> Self {
        switch value {
        case .workPacket: return .subjectWorkPacket
        case .roundSession: return .subjectRoundSession
        }
    }

    static func subjectStateKey(_ value: FieldReferenceSubjectStateV1) -> Self {
        switch value {
        case .active: return .subjectActive
        case .finalized: return .subjectFinalized
        }
    }

    static func provenanceKindKey(_ value: FieldReferenceProvenanceKindV1) -> Self {
        switch value {
        case .licensed: return .provenanceLicensed
        case .synthetic: return .provenanceSynthetic
        }
    }

    static func licenseScopeKey(_ value: FieldReferenceLicenseScopeV1) -> Self {
        switch value {
        case .localUseOnly: return .licenseLocalUseOnly
        case .citationAllowed: return .licenseCitationAllowed
        case .citationAndExportAllowed: return .licenseCitationAndExportAllowed
        case .restricted: return .licenseRestricted
        }
    }
}

enum FieldReferenceLocalizationPolicyV1 {
    static let semanticNamespace = "field.reference"
    static let sourceLocale = "en"
    static let shippingLocale = "en"
    static let metadataLocale = "en-US"
    static let testOnlyLocales = TestOnlyPseudoLocaleV1.allCases.map(\.rawValue).sorted()
    static let keys = FieldReferenceLocalizationKeyV1.allCases.map(\.rawValue)
    static let stateKeys = FieldReferenceLocalizationKeyV1.allCases.filter {
        $0.rawValue.contains(".availability.")
            || $0.rawValue.contains(".release.")
            || $0.rawValue.contains(".subject.")
            || $0.rawValue.contains(".provenance.")
            || $0 == .requiredContent
            || $0 == .missingContent
    }.map(\.rawValue)
    static let denyByDefault = true
    static let requiresTruthfulClosedValues = true
    static let requiresNonColorStateText = true
    static let requiresTextAndIconForIndeterminateStates = true
    static let requiresActionableNextStep = true
    static let allowsColorOnlyState = false
    static let allowsIconOnlyState = false
    static let allowsMotionOnlyState = false
    static let excludesReferenceBytes = true
    static let excludesPrivateLocators = true
    static let excludesLicenseSecrets = true
    static let excludesSubjectIdentity = true
    static let excludesObservationClaims = true
    static let excludesComplianceClaims = true

    static let prohibitedClaimPhrases: Set<String> = [
        "approved", "approval", "authorized", "authorization", "authority",
        "compliant", "compliance", "certified", "verified", "verified identity",
        "authenticated", "secure", "secure storage", "tamperproof", "tamper proof",
        "nonrepudiation", "non repudiation", "legal signature", "professional",
        "safety",
        "customer data", "work data", "private data", "password", "credential",
        "license secret", "remote delivery", "sent", "delivered",
        "observation complete", "requirement complete",
    ]

    private static func normalized(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        ).split { !$0.isLetter && !$0.isNumber }.joined(separator: " ")
    }

    static func containsProhibitedClaim(in values: [String]) -> Bool {
        values.contains { value in
            let bounded = " \(normalized(value)) "
            prohibitedClaimPhrases.contains { bounded.contains(" \($0) ") }
        }
    }

    static func containsCustomerOrWorkDataLeakage(in values: [String]) -> Bool {
        values.contains { value in
            let bounded = " \(normalized(value)) "
            [" customer data ", " work data ", " private data ", " password ", " credential ", " token ", " locator "]
                .contains { bounded.contains($0) }
        }
    }
}

typealias FieldReferenceClaimVocabularyV1 = FieldReferenceLocalizationPolicyV1

// MARK: - C24 accessible-document labels

/// English-only keys for the canonical accessible-document semantic tree and
/// its recorded assessment.  These labels describe recorded structure and
/// provenance; they never manufacture alternate text or imply certification.
enum AccessibleDocumentLocalizationKeyV1: String, CaseIterable, Codable, Sendable {
    case screen = "accessible.document.screen"
    case heading = "accessible.document.heading"
    case node = "accessible.document.node"
    case role = "accessible.document.role"
    case roleDocument = "accessible.document.role.document"
    case roleSection = "accessible.document.role.section"
    case roleHeading = "accessible.document.role.heading"
    case roleParagraph = "accessible.document.role.paragraph"
    case roleList = "accessible.document.role.list"
    case roleListItem = "accessible.document.role.list-item"
    case roleTable = "accessible.document.role.table"
    case roleTableRow = "accessible.document.role.table-row"
    case roleTableHeader = "accessible.document.role.table-header"
    case roleTableCell = "accessible.document.role.table-cell"
    case roleFigure = "accessible.document.role.figure"
    case roleEvidenceLink = "accessible.document.role.evidence-link"
    case roleNote = "accessible.document.role.note"
    case alternateText = "accessible.document.alternate-text"
    case alternateTextProvenance = "accessible.document.alternate-text.provenance"
    case alternateTextAuthoredForSource = "accessible.document.alternate-text.provenance.authored-for-source"
    case alternateTextSourceCaption = "accessible.document.alternate-text.provenance.source-caption"
    case alternateTextNotProvided = "accessible.document.alternate-text.provenance.not-provided"
    case decorativeFigure = "accessible.document.figure.decorative"
    case describedFigure = "accessible.document.figure.described"
    case assessment = "accessible.document.assessment"
    case assessmentInternalPass = "accessible.document.assessment.internal-pass"
    case assessmentInternalFail = "accessible.document.assessment.internal-fail"
    case assessmentIncomplete = "accessible.document.assessment.incomplete"
    case assessmentExternallyProved = "accessible.document.assessment.external-proof-recorded"
    case evidence = "accessible.document.evidence"
    case evidenceLimited = "accessible.document.evidence.limited"
    case claimBoundary = "accessible.document.claim-boundary"
    case nextStep = "accessible.document.next-step"

    var localizationKey: LocalizationKeyV1 {
        // swiftlint:disable:next force_try
        try! LocalizationKeyV1(rawValue)
    }

    var englishDefaultValue: String {
        switch self {
        case .screen: return "Accessible document"
        case .heading: return "Document structure"
        case .node: return "Document item"
        case .role: return "Document role"
        case .roleDocument: return "Document"
        case .roleSection: return "Section"
        case .roleHeading: return "Heading"
        case .roleParagraph: return "Paragraph"
        case .roleList: return "List"
        case .roleListItem: return "List item"
        case .roleTable: return "Table"
        case .roleTableRow: return "Table row"
        case .roleTableHeader: return "Table header"
        case .roleTableCell: return "Table cell"
        case .roleFigure: return "Figure"
        case .roleEvidenceLink: return "Evidence link"
        case .roleNote: return "Note"
        case .alternateText: return "Alternate text"
        case .alternateTextProvenance: return "Alternate text provenance"
        case .alternateTextAuthoredForSource: return "Description authored for source"
        case .alternateTextSourceCaption: return "Source caption"
        case .alternateTextNotProvided: return "No alternate text recorded"
        case .decorativeFigure: return "Decorative figure"
        case .describedFigure: return "Described figure"
        case .assessment: return "Document assessment"
        case .assessmentInternalPass: return "Internal pass recorded"
        case .assessmentInternalFail: return "Internal fail recorded"
        case .assessmentIncomplete: return "Assessment incomplete"
        case .assessmentExternallyProved: return "External proof recorded"
        case .evidence: return "Evidence"
        case .evidenceLimited: return "Evidence details limited"
        case .claimBoundary: return "Recorded document semantics only"
        case .nextStep: return "Review the recorded document state"
        }
    }

    var translatorComment: String {
        "English label for a recorded accessible-document role, alternate-text provenance, decorative state, or assessment state; do not imply certification, compliance, identity, legal status, or hidden evidence."
    }
}

extension AccessibleDocumentLocalizationKeyV1 {
    static func roleKey(_ value: AccessibleDocumentRoleV1) -> Self {
        switch value {
        case .document: return .roleDocument
        case .section: return .roleSection
        case .heading: return .roleHeading
        case .paragraph: return .roleParagraph
        case .list: return .roleList
        case .listItem: return .roleListItem
        case .table: return .roleTable
        case .tableRow: return .roleTableRow
        case .tableHeader: return .roleTableHeader
        case .tableCell: return .roleTableCell
        case .figure: return .roleFigure
        case .evidenceLink: return .roleEvidenceLink
        case .note: return .roleNote
        }
    }

    static func alternateTextProvenanceKey(
        _ value: AccessibleAlternateTextProvenanceV1
    ) -> Self {
        switch value {
        case .authoredForSource: return .alternateTextAuthoredForSource
        case .sourceCaption: return .alternateTextSourceCaption
        case .notProvided: return .alternateTextNotProvided
        }
    }

    static func assessmentStateKey(
        _ value: AccessibleDocumentAssessmentStateV1
    ) -> Self {
        switch value {
        case .internalPass: return .assessmentInternalPass
        case .internalFail: return .assessmentInternalFail
        case .incomplete: return .assessmentIncomplete
        case .externallyProved: return .assessmentExternallyProved
        }
    }
}

enum AccessibleDocumentLocalizationPolicyV1 {
    static let semanticNamespace = "accessible.document"
    static let sourceLocale = "en"
    static let shippingLocale = "en"
    static let metadataLocale = "en-US"
    static let testOnlyLocales = TestOnlyPseudoLocaleV1.allCases.map(\.rawValue).sorted()
    static let keys = AccessibleDocumentLocalizationKeyV1.allCases.map(\.rawValue)
    static let stateKeys = AccessibleDocumentLocalizationKeyV1.allCases.filter {
        $0.rawValue.contains(".role.")
            || $0.rawValue.contains(".provenance.")
            || $0.rawValue.contains(".figure.")
            || $0.rawValue.contains(".assessment.")
            || $0 == .evidenceLimited
    }.map(\.rawValue)
    static let denyByDefault = true
    static let requiresTruthfulClosedValues = true
    static let requiresNonColorStateText = true
    static let requiresTextAndIconForIndeterminateStates = true
    static let requiresActionableNextStep = true
    static let allowsColorOnlyState = false
    static let allowsIconOnlyState = false
    static let allowsMotionOnlyState = false
    static let excludesOriginalEvidence = true
    static let excludesPrivateEvidence = true
    static let excludesAssessorIdentity = true
    static let excludesPrivateLocators = true
    static let excludesUnsupportedClaims = true

    static let prohibitedClaimPhrases: Set<String> = [
        "pdf ua", "wcag", "section 508", "ada", "legal",
        "certified", "certification", "compliant", "compliance",
        "verified identity", "authenticated", "tamperproof", "tamper proof",
        "nonrepudiation", "non repudiation", "every reader", "identical rendering",
        "accessible to everyone", "guaranteed", "approved", "authorized",
    ]

    private static func normalized(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        ).split { !$0.isLetter && !$0.isNumber }.joined(separator: " ")
    }

    static func containsProhibitedClaim(in values: [String]) -> Bool {
        values.contains { value in
            let bounded = " \(normalized(value)) "
            prohibitedClaimPhrases.contains { bounded.contains(" \($0) ") }
        }
    }

    static func containsCustomerOrWorkDataLeakage(in values: [String]) -> Bool {
        values.contains { value in
            let bounded = " \(normalized(value)) "
            [
                " customer data ", " work data ", " private data ", " password ",
                " credential ", " token ", " locator ", " assessor ", " evidence id ",
            ].contains { bounded.contains($0) }
        }
    }
}

typealias AccessibleDocumentClaimVocabularyV1 = AccessibleDocumentLocalizationPolicyV1

// MARK: - C25 guided-survey localization contract

/// C25 keeps the activity vocabulary closed and machine values separate from
/// user-facing copy.  These keys describe recorded definition/release state;
/// they never turn a survey response into an inspection, compliance, safety,
/// training, or certification claim.
enum SurveyDefinitionLocalizationKeyV1: String, CaseIterable, Codable, Sendable {
    case activityKindInspection = "activity.kind.inspection"
    case activityKindSurvey = "activity.kind.survey"
    case activityKindPreventiveMaintenance = "activity.kind.preventive_maintenance"
    case activityKindRepair = "activity.kind.repair"
    case activityKindOperationalRecheck = "activity.kind.operational_recheck"
    case lifecycleDraft = "survey.definition.lifecycle.draft"
    case lifecyclePublished = "survey.definition.lifecycle.published"
    case lifecycleRetired = "survey.definition.lifecycle.retired"
    case fieldInstruction = "survey.field.kind.instruction"
    case fieldShortText = "survey.field.kind.short_text"
    case fieldLongText = "survey.field.kind.long_text"
    case fieldInteger = "survey.field.kind.integer"
    case fieldDecimal = "survey.field.kind.decimal"
    case fieldMeasurement = "survey.field.kind.measurement"
    case fieldBooleanObservation = "survey.field.kind.boolean_observation"
    case fieldSingleChoice = "survey.field.kind.single_choice"
    case fieldMultipleChoice = "survey.field.kind.multiple_choice"
    case fieldDate = "survey.field.kind.date"
    case fieldTime = "survey.field.kind.time"
    case fieldSubjectReference = "survey.field.kind.subject_reference"
    case fieldLocator = "survey.field.kind.locator"
    case fieldOneShotLocation = "survey.field.kind.one_shot_location"
    case fieldNormalizedPlanPlacement = "survey.field.kind.normalized_plan_placement"
    case fieldEvidenceRequest = "survey.field.kind.evidence_request"
    case fieldRepeatableGroup = "survey.field.kind.repeatable_group"
    case fieldAttributedAcknowledgement = "survey.field.kind.attributed_acknowledgement"
    case booleanYes = "survey.boolean.yes"
    case booleanNo = "survey.boolean.no"
    case booleanUnknown = "survey.boolean.unknown"
    case booleanNotObserved = "survey.boolean.not_observed"
    case reportHeading = "survey.definition.report.heading"
    case reportDefinition = "survey.definition.report.definition"
    case reportRelease = "survey.definition.report.release"
    case reportActivityKind = "survey.definition.report.activity_kind"
    case reportLifecycle = "survey.definition.report.lifecycle"
    case reportSections = "survey.definition.report.sections"
    case reportFacts = "survey.definition.report.facts"
    case reportNotObserved = "survey.definition.value.not_observed"
    case reportClaimBoundary = "survey.definition.report.claim_boundary"
    case nextStepReviewRecordedFacts = "survey.definition.next_step.review_recorded_facts"
    case searchDefinition = "survey.definition.search.definition"
    case searchRelease = "survey.definition.search.release"
    case searchActivityKind = "survey.definition.search.activity_kind"
    case searchLifecycle = "survey.definition.search.lifecycle"
    case searchReleaseRevision = "survey.definition.search.release_revision"
    case settingsFavorite = "settings.survey_definition.favorite"
    case settingsRecents = "settings.survey_definition.recents"

    var englishDefaultValue: String {
        switch self {
        case .activityKindInspection: return "Inspection"
        case .activityKindSurvey: return "Survey"
        case .activityKindPreventiveMaintenance: return "Preventive maintenance"
        case .activityKindRepair: return "Repair"
        case .activityKindOperationalRecheck: return "Operational recheck"
        case .lifecycleDraft: return "Draft"
        case .lifecyclePublished: return "Published"
        case .lifecycleRetired: return "Retired"
        case .fieldInstruction: return "Instruction"
        case .fieldShortText: return "Short text"
        case .fieldLongText: return "Long text"
        case .fieldInteger: return "Integer"
        case .fieldDecimal: return "Decimal"
        case .fieldMeasurement: return "Measurement"
        case .fieldBooleanObservation: return "Boolean observation"
        case .fieldSingleChoice: return "Single choice"
        case .fieldMultipleChoice: return "Multiple choice"
        case .fieldDate: return "Date"
        case .fieldTime: return "Time"
        case .fieldSubjectReference: return "Subject reference"
        case .fieldLocator: return "Locator"
        case .fieldOneShotLocation: return "One-shot location"
        case .fieldNormalizedPlanPlacement: return "Normalized plan placement"
        case .fieldEvidenceRequest: return "Evidence request"
        case .fieldRepeatableGroup: return "Repeatable group"
        case .fieldAttributedAcknowledgement: return "Attributed acknowledgment"
        case .booleanYes: return "Yes"
        case .booleanNo: return "No"
        case .booleanUnknown: return "Unknown"
        case .booleanNotObserved: return "Not observed"
        case .reportHeading: return "Survey definition"
        case .reportDefinition: return "Definition"
        case .reportRelease: return "Definition release"
        case .reportActivityKind: return "Activity kind"
        case .reportLifecycle: return "Recorded lifecycle"
        case .reportSections: return "Sections"
        case .reportFacts: return "Facts"
        case .reportNotObserved: return "Not observed"
        case .reportClaimBoundary: return "Recorded definition metadata only"
        case .nextStepReviewRecordedFacts: return "Review the recorded facts"
        case .searchDefinition: return "Survey definition"
        case .searchRelease: return "Definition release"
        case .searchActivityKind: return "Activity kind"
        case .searchLifecycle: return "Recorded lifecycle"
        case .searchReleaseRevision: return "Release revision"
        case .settingsFavorite: return "Favorite definitions"
        case .settingsRecents: return "Recent definitions"
        }
    }

    var translatorComment: String {
        "English-only C25 label for bounded survey-definition metadata; do not imply inspection results, compliance, certification, training, safety, authorization, identity, or legal status."
    }

    static func activityKindKey(_ value: ActivityKindV1) -> Self {
        switch value {
        case .inspection: return .activityKindInspection
        case .survey: return .activityKindSurvey
        case .preventiveMaintenance: return .activityKindPreventiveMaintenance
        case .repair: return .activityKindRepair
        case .operationalRecheck: return .activityKindOperationalRecheck
        }
    }

    static func lifecycleKey(_ value: SurveyDefinitionLifecycleStateV1) -> Self {
        switch value {
        case .draft: return .lifecycleDraft
        case .published: return .lifecyclePublished
        case .retired: return .lifecycleRetired
        }
    }

    static func fieldKindKey(_ value: SurveyFieldKindV1) -> Self {
        switch value {
        case .instruction: return .fieldInstruction
        case .shortText: return .fieldShortText
        case .longText: return .fieldLongText
        case .integer: return .fieldInteger
        case .decimal: return .fieldDecimal
        case .measurement: return .fieldMeasurement
        case .booleanObservation: return .fieldBooleanObservation
        case .singleChoice: return .fieldSingleChoice
        case .multipleChoice: return .fieldMultipleChoice
        case .date: return .fieldDate
        case .time: return .fieldTime
        case .subjectReference: return .fieldSubjectReference
        case .locator: return .fieldLocator
        case .oneShotLocation: return .fieldOneShotLocation
        case .normalizedPlanPlacement: return .fieldNormalizedPlanPlacement
        case .evidenceRequest: return .fieldEvidenceRequest
        case .repeatableGroup: return .fieldRepeatableGroup
        case .attributedAcknowledgement: return .fieldAttributedAcknowledgement
        }
    }

    static func booleanKey(_ value: SurveyBooleanObservationV1) -> Self {
        switch value {
        case .yes: return .booleanYes
        case .no: return .booleanNo
        case .unknown: return .booleanUnknown
        case .notObserved: return .booleanNotObserved
        }
    }
}

enum SurveyDefinitionLocalizationPolicyV1 {
    static let semanticNamespace = "survey.definition"
    static let sourceLocale = "en"
    static let shippingLocale = "en"
    static let metadataLocale = "en-US"
    static let testOnlyLocales = TestOnlyPseudoLocaleV1.allCases.map(\.rawValue).sorted()
    static let keys = SurveyDefinitionLocalizationKeyV1.allCases.map(\.rawValue).sorted()
    static let denyByDefault = true
    static let englishOnly = true
    static let requiresTextState = true
    static let requiresTextAndIconForIndeterminateState = true
    static let requiresActionableNextStep = true
    static let allowsColorOnlyState = false
    static let allowsIconOnlyState = false
    static let allowsMotionOnlyState = false
    static let excludesAnswers = true
    static let excludesPromptText = true
    static let excludesActorIdentity = true
    static let excludesPrivateLocators = true
    static let excludesEvidenceBytes = true
    static let excludesUnsupportedClaims = true

    static func key(_ value: SurveyDefinitionLocalizationKeyV1) throws -> LocalizationKeyV1 {
        try LocalizationKeyV1(value.rawValue)
    }

    static func validate() throws {
        let typed = try SurveyDefinitionLocalizationKeyV1.allCases.map { try key($0) }
        guard typed.map(\.rawValue).sorted() == keys,
              Set(keys).count == keys.count,
              denyByDefault, englishOnly, requiresTextState,
              !allowsColorOnlyState, !allowsIconOnlyState, !allowsMotionOnlyState else {
            throw LocalizationContractFailureV1.invalidValue
        }
    }
}
enum C52ServiceRequestBoundary_LocalizationContractsV1 {
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

// MARK: - C26 guided-survey session localization contract

/// C26 labels describe the recorded state of a survey session and its
/// explicitly published fact snapshot.  They are presentation vocabulary,
/// not a second source of truth for answers, subjects, actors, or publication
/// authority.
enum SurveySessionFactLocalizationStateV1: String, CaseIterable, Codable, Hashable, Sendable {
    case notRecorded = "NOT_RECORDED"
    case recorded = "RECORDED"
    case unknown = "UNKNOWN"
    case notObserved = "NOT_OBSERVED"
}

enum SurveySessionSubjectLocalizationStateV1: String, CaseIterable, Codable, Hashable, Sendable {
    case canonical = "CANONICAL"
    case provisional = "PROVISIONAL"
    case promoted = "PROMOTED"
    case reconciledAlias = "RECONCILED_ALIAS"
    case promotionReversed = "PROMOTION_REVERSED"
    case archived = "ARCHIVED"
    case unavailable = "UNAVAILABLE"
}

/// Publication interruption is a consumer state supplied by the caller when
/// no immutable snapshot was accepted; it is never inferred from a missing
/// snapshot or treated as a successful publication.
enum SurveySessionPublicationLocalizationStateV1: String, CaseIterable, Codable, Hashable, Sendable {
    case notPublished = "NOT_PUBLISHED"
    case recorded = "RECORDED"
    case interrupted = "INTERRUPTED"
    case immutable = "IMMUTABLE"
}

enum SurveySessionLocalizationKeyV1: String, CaseIterable, Codable, Sendable {
    case heading = "survey.session.heading"
    case lifecycle = "survey.session.lifecycle"
    case lifecycleDraft = "survey.session.lifecycle.draft"
    case lifecyclePaused = "survey.session.lifecycle.paused"
    case lifecycleReviewRequired = "survey.session.lifecycle.review_required"
    case lifecycleCompleted = "survey.session.lifecycle.completed"
    case lifecycleAmended = "survey.session.lifecycle.amended"
    case lifecycleSuperseded = "survey.session.lifecycle.superseded"
    case lifecycleArchived = "survey.session.lifecycle.archived"
    case lifecycleDeleted = "survey.session.lifecycle.deleted"
    case fact = "survey.session.fact"
    case factNotRecorded = "survey.session.fact.state.not_recorded"
    case factRecorded = "survey.session.fact.state.recorded"
    case factUnknown = "survey.session.fact.state.unknown"
    case factNotObserved = "survey.session.fact.state.not_observed"
    case subject = "survey.session.subject"
    case subjectCanonical = "survey.session.subject.state.canonical"
    case subjectProvisional = "survey.session.subject.state.provisional"
    case subjectPromoted = "survey.session.subject.state.promoted"
    case subjectReconciledAlias = "survey.session.subject.state.reconciled_alias"
    case subjectPromotionReversed = "survey.session.subject.state.promotion_reversed"
    case subjectArchived = "survey.session.subject.state.archived"
    case subjectUnavailable = "survey.session.subject.state.unavailable"
    case subjectPromotion = "survey.session.subject.promotion"
    case subjectPromotionToAsset = "survey.session.subject.promotion.to_asset"
    case subjectReconcileAsAlias = "survey.session.subject.promotion.reconcile_as_alias"
    case subjectReversePromotion = "survey.session.subject.promotion.reverse"
    case publication = "survey.session.publication"
    case publicationNotPublished = "survey.session.publication.state.not_published"
    case publicationRecorded = "survey.session.publication.state.recorded"
    case publicationInterrupted = "survey.session.publication.state.interrupted"
    case publicationImmutable = "survey.session.publication.state.immutable"
    case claimBoundary = "survey.session.claim_boundary"
    case nextStepReviewFacts = "survey.session.next_step.review_recorded_facts"
    case nextStepReviewPromotion = "survey.session.next_step.review_subject_promotion"

    var englishDefaultValue: String {
        switch self {
        case .heading: return "Survey session"
        case .lifecycle: return "Session lifecycle"
        case .lifecycleDraft: return "Draft"
        case .lifecyclePaused: return "Paused"
        case .lifecycleReviewRequired: return "Review required"
        case .lifecycleCompleted: return "Completed"
        case .lifecycleAmended: return "Amended"
        case .lifecycleSuperseded: return "Superseded"
        case .lifecycleArchived: return "Archived"
        case .lifecycleDeleted: return "Deleted"
        case .fact: return "Recorded fact"
        case .factNotRecorded: return "Not recorded"
        case .factRecorded: return "Recorded"
        case .factUnknown: return "Unknown"
        case .factNotObserved: return "Not observed"
        case .subject: return "Session subject"
        case .subjectCanonical: return "Canonical subject"
        case .subjectProvisional: return "Provisional subject"
        case .subjectPromoted: return "Promotion recorded"
        case .subjectReconciledAlias: return "Alias reconciliation recorded"
        case .subjectPromotionReversed: return "Promotion reversed"
        case .subjectArchived: return "Provisional subject archived"
        case .subjectUnavailable: return "Subject status unavailable"
        case .subjectPromotion: return "Subject promotion"
        case .subjectPromotionToAsset: return "Promotion to asset"
        case .subjectReconcileAsAlias: return "Reconcile as alias"
        case .subjectReversePromotion: return "Reverse recorded promotion"
        case .publication: return "Publication record"
        case .publicationNotPublished: return "Not published"
        case .publicationRecorded: return "Publication recorded"
        case .publicationInterrupted: return "Publication interrupted"
        case .publicationImmutable: return "Immutable publication record"
        case .claimBoundary: return "Recorded survey facts only"
        case .nextStepReviewFacts: return "Review the recorded facts"
        case .nextStepReviewPromotion: return "Review the recorded subject promotion"
        }
    }

    var translatorComment: String {
        "English-only C26 label for recorded survey-session metadata; do not imply inspection outcomes, compliance, authorization, identity, legal status, secure delivery, or automatic subject merging."
    }

    static func lifecycleKey(_ value: SurveySessionStateV1) -> Self {
        switch value {
        case .draft: return .lifecycleDraft
        case .paused: return .lifecyclePaused
        case .reviewRequired: return .lifecycleReviewRequired
        case .completed: return .lifecycleCompleted
        case .amended: return .lifecycleAmended
        case .superseded: return .lifecycleSuperseded
        case .archived: return .lifecycleArchived
        case .deleted: return .lifecycleDeleted
        }
    }

    static func factStateKey(_ value: SurveySessionFactLocalizationStateV1) -> Self {
        switch value {
        case .notRecorded: return .factNotRecorded
        case .recorded: return .factRecorded
        case .unknown: return .factUnknown
        case .notObserved: return .factNotObserved
        }
    }

    static func factStateKey(_ value: SurveyBooleanObservationV1) -> Self? {
        switch value {
        case .unknown: return .factUnknown
        case .notObserved: return .factNotObserved
        case .yes, .no: return nil
        }
    }

    static func subjectStateKey(_ value: SurveySessionSubjectLocalizationStateV1) -> Self {
        switch value {
        case .canonical: return .subjectCanonical
        case .provisional: return .subjectProvisional
        case .promoted: return .subjectPromoted
        case .reconciledAlias: return .subjectReconciledAlias
        case .promotionReversed: return .subjectPromotionReversed
        case .archived: return .subjectArchived
        case .unavailable: return .subjectUnavailable
        }
    }

    static func provisionalSubjectKey(_ value: ProvisionalSubjectStateV1) -> Self {
        switch value {
        case .active: return .subjectProvisional
        case .promoted: return .subjectPromoted
        case .reconciledAlias: return .subjectReconciledAlias
        case .promotionReversed: return .subjectPromotionReversed
        case .archived: return .subjectArchived
        }
    }

    static func promotionActionKey(_ value: SubjectPromotionActionV1) -> Self {
        switch value {
        case .promoteToAsset: return .subjectPromotionToAsset
        case .reconcileAsAlias: return .subjectReconcileAsAlias
        case .reverse: return .subjectReversePromotion
        }
    }

    static func publicationStateKey(
        _ value: SurveySessionPublicationLocalizationStateV1
    ) -> Self {
        switch value {
        case .notPublished: return .publicationNotPublished
        case .recorded: return .publicationRecorded
        case .interrupted: return .publicationInterrupted
        case .immutable: return .publicationImmutable
        }
    }
}

enum SurveySessionLocalizationPolicyV1 {
    static let semanticNamespace = "survey.session"
    static let sourceLocale = "en"
    static let shippingLocale = "en"
    static let metadataLocale = "en-US"
    static let testOnlyLocales = TestOnlyPseudoLocaleV1.allCases.map(\.rawValue).sorted()
    static let keys = SurveySessionLocalizationKeyV1.allCases.map(\.rawValue).sorted()
    static let denyByDefault = true
    static let englishOnly = true
    static let requiresTextState = true
    static let requiresTextAndIconForIndeterminateState = true
    static let requiresActionableNextStep = true
    static let allowsColorOnlyState = false
    static let allowsIconOnlyState = false
    static let allowsMotionOnlyState = false
    static let excludesAnswers = true
    static let excludesPromptText = true
    static let excludesActorIdentity = true
    static let excludesPrivateLocators = true
    static let excludesEvidenceBytes = true
    static let excludesCustomerData = true
    static let excludesUnsupportedClaims = true
    static let excludesInspectionOutcomes = true
    static let excludesAutomaticSubjectMerge = true

    static let prohibitedClaimPhrases = [
        "approval", "approve", "approved", "authorization", "authorize", "authorized",
        "authorship", "author", "authored", "compliance", "compliant", "certification",
        "certified", "professional", "legal", "legal signature", "nonrepudiation",
        "non-repudiation", "tamperproof", "tamper-proof", "verified identity", "verified",
        "secure", "secured", "sent", "delivered", "inspection pass", "inspection fail",
        "pass", "fail", "automatic merge", "auto merge", "customer data", "private data",
        "work data", "telemetry", "private locator", "evidence bytes"
    ]

    static func key(_ value: SurveySessionLocalizationKeyV1) throws -> LocalizationKeyV1 {
        try LocalizationKeyV1(value.rawValue)
    }

    static func containsProhibitedClaim(_ value: String) -> Bool {
        let normalized = value.lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        return prohibitedClaimPhrases.contains { normalized.contains($0) }
    }

    static func validate() throws {
        let typed = try SurveySessionLocalizationKeyV1.allCases.map { try key($0) }
        guard typed.map(\.rawValue).sorted() == keys,
              Set(keys).count == keys.count,
              denyByDefault, englishOnly, requiresTextState,
              requiresTextAndIconForIndeterminateState, requiresActionableNextStep,
              !allowsColorOnlyState, !allowsIconOnlyState, !allowsMotionOnlyState,
              excludesAnswers, excludesPromptText, excludesActorIdentity,
              excludesPrivateLocators, excludesEvidenceBytes, excludesCustomerData,
              excludesUnsupportedClaims, excludesInspectionOutcomes,
              excludesAutomaticSubjectMerge,
              SurveySessionLocalizationKeyV1.allCases.allSatisfy({
                  !containsProhibitedClaim($0.englishDefaultValue)
              }) else {
            throw LocalizationContractFailureV1.invalidValue
        }
    }
}

// MARK: - C27 asset-locator localization contract

/// C27 is deliberately a closed, English-only presentation vocabulary.  The
/// values describe recorded locator metadata and the result of an offline
/// lookup; they never turn an opaque input, key digest, or lifecycle fact into
/// a user/permission/identity claim.
enum AssetLocatorLocalizationKeyV1: String, CaseIterable, Codable, Sendable {
    case heading = "asset.locator.heading"
    case resolution = "asset.locator.resolution"
    case representation = "asset.locator.representation"
    case representationLocalSigned = "asset.locator.representation.local_signed"
    case representationExternalKey = "asset.locator.representation.external_key"
    case representationUnavailable = "asset.locator.representation.unavailable"
    case outcomeMatched = "asset.locator.outcome.matched"
    case outcomeNoMatch = "asset.locator.outcome.no_match"
    case outcomeForeignWorkspace = "asset.locator.outcome.foreign_workspace"
    case outcomeAmbiguous = "asset.locator.outcome.ambiguous"
    case outcomeDamagedOrIncomplete = "asset.locator.outcome.damaged_or_incomplete"
    case outcomeRetired = "asset.locator.outcome.retired"
    case outcomeRevoked = "asset.locator.outcome.revoked"
    case outcomeReplaced = "asset.locator.outcome.replaced"
    case lifecycle = "asset.locator.lifecycle"
    case stateActive = "asset.locator.state.active"
    case stateRetired = "asset.locator.state.retired"
    case stateRevoked = "asset.locator.state.revoked"
    case stateReplaced = "asset.locator.state.replaced"
    case stateUnavailable = "asset.locator.state.unavailable"
    case claimBoundary = "asset.locator.claim_boundary"
    case nextStep = "asset.locator.next_step"

    var localizationKey: LocalizationKeyV1 {
        // swiftlint:disable:next force_try
        try! LocalizationKeyV1(rawValue)
    }

    var englishDefaultValue: String {
        switch self {
        case .heading: return "Asset locator"
        case .resolution: return "Locator resolution"
        case .representation: return "Locator representation"
        case .representationLocalSigned: return "Local signed locator"
        case .representationExternalKey: return "External key reference"
        case .representationUnavailable: return "Representation unavailable"
        case .outcomeMatched: return "Locator matched"
        case .outcomeNoMatch: return "No locator match"
        case .outcomeForeignWorkspace: return "Locator belongs to another workspace"
        case .outcomeAmbiguous: return "Multiple locator candidates"
        case .outcomeDamagedOrIncomplete: return "Locator data incomplete"
        case .outcomeRetired: return "Locator is retired"
        case .outcomeRevoked: return "Locator is revoked"
        case .outcomeReplaced: return "Locator is replaced"
        case .lifecycle: return "Locator lifecycle"
        case .stateActive: return "Active locator"
        case .stateRetired: return "Retired locator"
        case .stateRevoked: return "Revoked locator"
        case .stateReplaced: return "Replaced locator"
        case .stateUnavailable: return "Locator state unavailable"
        case .claimBoundary: return "Recorded locator metadata only"
        case .nextStep: return "Review locator details"
        }
    }

    var translatorComment: String {
        "English-only C27 label for recorded locator metadata and offline resolution; do not expose opaque input, secrets, private key material, vendor identifiers, identity, access, or delivery claims."
    }

    static func key(_ value: Self) throws -> LocalizationKeyV1 {
        try LocalizationKeyV1(value.rawValue)
    }

    static func outcomeKey(_ value: LocatorResolutionOutcomeV1) -> Self {
        switch value {
        case .matched: return .outcomeMatched
        case .noMatch: return .outcomeNoMatch
        case .foreignWorkspace: return .outcomeForeignWorkspace
        case .ambiguous: return .outcomeAmbiguous
        case .damagedOrIncomplete: return .outcomeDamagedOrIncomplete
        case .retired: return .outcomeRetired
        case .revoked: return .outcomeRevoked
        case .replaced: return .outcomeReplaced
        }
    }

    static func stateKey(_ value: AssetLocatorStateV1?) -> Self {
        guard let value else { return .stateUnavailable }
        switch value {
        case .active: return .stateActive
        case .retired: return .stateRetired
        case .revoked: return .stateRevoked
        case .replaced: return .stateReplaced
        }
    }

    static func representationKey(_ value: AssetLocatorRepresentationV1?) -> Self {
        guard let value else { return .representationUnavailable }
        switch value {
        case .localSigned: return .representationLocalSigned
        case .externalKey: return .representationExternalKey
        }
    }
}

enum AssetLocatorLocalizationPolicyV1 {
    static let semanticNamespace = "asset.locator"
    static let sourceLocale = "en"
    static let shippingLocale = "en"
    static let metadataLocale = "en-US"
    static let testOnlyLocales = TestOnlyPseudoLocaleV1.allCases.map(\.rawValue).sorted()
    static let keys = AssetLocatorLocalizationKeyV1.allCases.map(\.rawValue).sorted()
    static let denyByDefault = true
    static let englishOnly = true
    static let requiresTextState = true
    static let requiresTextAndIconForIndeterminateState = true
    static let requiresActionableNextStep = true
    static let allowsColorOnlyState = false
    static let allowsIconOnlyState = false
    static let allowsMotionOnlyState = false
    static let excludesOpaqueInput = true
    static let excludesPrivateKeyMaterial = true
    static let excludesSecrets = true
    static let excludesVendorIdentifiers = true
    static let excludesActorIdentity = true
    static let excludesPermissionClaims = true
    static let excludesNetworkResolutionClaims = true
    static let excludesUnsupportedClaims = true

    static let prohibitedClaimPhrases = [
        "approval", "approve", "approved", "authorization", "authorize", "authorized",
        "permission", "identity verified", "verified identity", "verified", "authorship",
        "compliance", "compliant", "certified", "professional", "legal signature",
        "nonrepudiation", "non-repudiation", "tamperproof", "tamper-proof", "secure",
        "sent", "delivered", "remote", "network", "telemetry", "private key", "secret",
        "vendor", "customer data", "work data", "evidence bytes"
    ]

    static func containsProhibitedClaim(_ values: [String]) -> Bool {
        values.contains { value in
            let normalized = value.lowercased()
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
            return prohibitedClaimPhrases.contains { normalized.contains($0) }
        }
    }

    static func validate() throws {
        let typed = try AssetLocatorLocalizationKeyV1.allCases.map { try key($0) }
        guard typed.map(\.rawValue).sorted() == keys,
              Set(keys).count == keys.count,
              denyByDefault, englishOnly, requiresTextState,
              requiresTextAndIconForIndeterminateState, requiresActionableNextStep,
              !allowsColorOnlyState, !allowsIconOnlyState, !allowsMotionOnlyState,
              excludesOpaqueInput, excludesPrivateKeyMaterial, excludesSecrets,
              excludesVendorIdentifiers, excludesActorIdentity, excludesPermissionClaims,
              excludesNetworkResolutionClaims, excludesUnsupportedClaims,
              AssetLocatorLocalizationKeyV1.allCases.allSatisfy({
                  !$0.englishDefaultValue.isEmpty
                      && !containsProhibitedClaim([$0.englishDefaultValue])
              }) else {
            throw LocalizationContractFailureV1.invalidValue
        }
    }
}

// MARK: - C28 schedule and occurrence localization

/// Closed English-only labels for the C28 schedule projection. Canonical
/// schedule/occurrence wire values remain machine tokens; this enum is only a
/// presentation mapping and never participates in identity or recurrence.
enum ScheduleLocalizationKeyV1: String, CaseIterable, Codable, Sendable {
    case heading = "schedule.heading"
    case definition = "schedule.definition"
    case occurrence = "schedule.occurrence"
    case occurrenceState = "schedule.occurrence.state"
    case fixedCalendar = "schedule.recurrence.fixed_calendar"
    case completionRelative = "schedule.recurrence.completion_relative"
    case timeBasis = "schedule.time_basis"
    case history = "schedule.history"
    case historyImmutable = "schedule.history.immutable"
    case dueQueue = "schedule.due_queue"
    case reminder = "schedule.reminder"
    case reminderNotTruth = "schedule.reminder.not_truth"
    case claimBoundary = "schedule.claim_boundary"
    case nextStep = "schedule.next_step"
    case advancedRecurrence = "schedule.recurrence.advanced"
    case exceptionCalendar = "schedule.exception_calendar"
    case calendarRelease = "schedule.exception_calendar.release"
    case businessDayAdjustment = "schedule.business_day_adjustment"
    case completionGap = "schedule.completion_gap"
    case nominalBasis = "schedule.occurrence.nominal_basis"
    case effectiveBasis = "schedule.occurrence.effective_basis"
    case occurrenceLineage = "schedule.occurrence.lineage"
    case scheduleOverride = "schedule.override"
    case overridePrecedence = "schedule.override.precedence"
    case changePreview = "schedule.change.preview"
    case previewNotApplied = "schedule.change.preview.not_applied"
    case changeConflict = "schedule.change.conflict"
    case manualResolutionRequired = "schedule.change.conflict.manual_resolution_required"
    case recovery = "schedule.recovery"
    case recoveryRebuilt = "schedule.recovery.rebuilt"
    case stateUpcoming = "schedule.occurrence.state.upcoming"
    case stateReady = "schedule.occurrence.state.ready"
    case stateDue = "schedule.occurrence.state.due"
    case stateOverdue = "schedule.occurrence.state.overdue"
    case stateDeferred = "schedule.occurrence.state.deferred"
    case stateMissed = "schedule.occurrence.state.missed"
    case stateSkipped = "schedule.occurrence.state.skipped"
    case stateCancelled = "schedule.occurrence.state.cancelled"
    case stateStarted = "schedule.occurrence.state.started"
    case stateCompleted = "schedule.occurrence.state.completed"

    var localizationKey: LocalizationKeyV1 {
        // swiftlint:disable:next force_try
        try! LocalizationKeyV1(rawValue)
    }

    var englishDefaultValue: String {
        switch self {
        case .heading: return "Schedule"
        case .definition: return "Schedule definition"
        case .occurrence: return "Occurrence"
        case .occurrenceState: return "Occurrence state"
        case .fixedCalendar: return "Fixed-calendar schedule"
        case .completionRelative: return "Completion-relative schedule"
        case .timeBasis: return "Frozen time basis"
        case .history: return "Occurrence history"
        case .historyImmutable: return "History remains unchanged"
        case .dueQueue: return "Due queue"
        case .reminder: return "Reminder preview"
        case .reminderNotTruth: return "Reminder is a preview; it does not change occurrence state"
        case .claimBoundary: return "Recorded schedule metadata only"
        case .nextStep: return "Review recorded schedule facts"
        case .advancedRecurrence: return "Advanced recurrence"
        case .exceptionCalendar: return "Exception calendar"
        case .calendarRelease: return "Frozen calendar release"
        case .businessDayAdjustment: return "Business-day adjustment"
        case .completionGap: return "Completion gap"
        case .nominalBasis: return "Nominal occurrence"
        case .effectiveBasis: return "Effective occurrence"
        case .occurrenceLineage: return "Occurrence lineage"
        case .scheduleOverride: return "Schedule override"
        case .overridePrecedence: return "Override precedence"
        case .changePreview: return "Schedule change preview"
        case .previewNotApplied: return "Preview only; no schedule change is recorded"
        case .changeConflict: return "Recorded values conflict"
        case .manualResolutionRequired: return "Manual resolution required"
        case .recovery: return "Schedule recovery"
        case .recoveryRebuilt: return "Derived schedule view rebuilt from recorded facts"
        case .stateUpcoming: return "Upcoming"
        case .stateReady: return "Ready"
        case .stateDue: return "Due"
        case .stateOverdue: return "Overdue"
        case .stateDeferred: return "Deferred"
        case .stateMissed: return "Missed"
        case .stateSkipped: return "Skipped"
        case .stateCancelled: return "Cancelled"
        case .stateStarted: return "Started"
        case .stateCompleted: return "Completed"
        }
    }

    var translatorComment: String {
        switch self {
        case .advancedRecurrence, .exceptionCalendar, .calendarRelease,
             .businessDayAdjustment, .completionGap, .nominalBasis,
             .effectiveBasis, .occurrenceLineage, .scheduleOverride,
             .overridePrecedence, .changePreview, .previewNotApplied,
             .changeConflict, .manualResolutionRequired, .recovery,
             .recoveryRebuilt:
            return "English-only C51 label for frozen recurrence, calendar, override, preview, conflict, recovery, and occurrence-lineage facts; canonical semantics remain locale-independent."
        default:
            return "English-only C28 label for frozen schedule and occurrence facts; notification delivery is disposable and never changes canonical occurrence state."
        }
    }

    static func key(for state: OccurrenceStateV1) -> Self {
        switch state {
        case .upcoming: return .stateUpcoming
        case .ready: return .stateReady
        case .due: return .stateDue
        case .overdue: return .stateOverdue
        case .deferred: return .stateDeferred
        case .missed: return .stateMissed
        case .skipped: return .stateSkipped
        case .cancelled: return .stateCancelled
        case .started: return .stateStarted
        case .completed: return .stateCompleted
        }
    }

    static func recurrenceKey(for recurrence: ScheduleRecurrenceV1) -> Self {
        switch recurrence {
        case .fixedCalendar: return .fixedCalendar
        case .completionRelative: return .completionRelative
        case .advanced: return .advancedRecurrence
        }
    }
}

enum ScheduleLocalizationPolicyV1 {
    static let sourceLocale = "en"
    static let shippingRuntimeLocales = ["en"]
    static let metadataLocale = "en-US"
    static let pseudoLocalesAreTestOnly = true
    static let keys = ScheduleLocalizationKeyV1.allCases.map(\.rawValue).sorted()
    static let occurrenceStateKeys = OccurrenceStateV1.allCases.map {
        ScheduleLocalizationKeyV1.key(for: $0).rawValue
    }.sorted()
    static let englishOnly = true
    static let notificationDeliveryIsTruth = false
    static let historyDisplayIsFrozen = true
    static let canonicalSemanticsAreLocaleIndependent = true
    static let dateAndTimeFormattingUsesPresentationLocaleOnly = true
    static let identifiersAreNeverLocalized = true
    static let timeZoneIdentifiersAreNeverLocalized = true
    static let exceptionReasonsAreNeverLocalizationKeys = true
    static let calendarPayloadIsNeverLocalized = true
    static let denyByDefault = true
    static let prohibitedClaimPhrases = [
        "approval", "authorization", "permission", "verified identity", "authorship",
        "legal signature", "nonrepudiation", "tamperproof", "secure", "sent", "delivered",
        "remote", "network", "telemetry", "customer data", "work data", "evidence bytes",
    ]

    static func containsProhibitedClaim(_ values: [String]) -> Bool {
        values.contains { value in
            let normalized = value.lowercased()
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
            return prohibitedClaimPhrases.contains { normalized.contains($0) }
        }
    }

    static func validate() throws {
        let typed = ScheduleLocalizationKeyV1.allCases.map(\.localizationKey.rawValue).sorted()
        guard typed == keys,
              Set(keys).count == keys.count,
              occurrenceStateKeys.count == OccurrenceStateV1.allCases.count,
              Set(occurrenceStateKeys).count == occurrenceStateKeys.count,
              sourceLocale == "en",
              shippingRuntimeLocales == ["en"],
              metadataLocale == "en-US",
              pseudoLocalesAreTestOnly,
              englishOnly,
              !notificationDeliveryIsTruth,
              historyDisplayIsFrozen,
              canonicalSemanticsAreLocaleIndependent,
              dateAndTimeFormattingUsesPresentationLocaleOnly,
              identifiersAreNeverLocalized,
              timeZoneIdentifiersAreNeverLocalized,
              exceptionReasonsAreNeverLocalizationKeys,
              calendarPayloadIsNeverLocalized,
              denyByDefault,
              ScheduleLocalizationKeyV1.allCases.allSatisfy({
                  !$0.englishDefaultValue.isEmpty
                      && !containsProhibitedClaim([$0.englishDefaultValue])
              }) else {
            throw LocalizationContractFailureV1.invalidValue
        }
    }
}

// MARK: - C29 versioned plan and rebase localization

/// Closed English-only labels for plan documents, normalized placements, and
/// deterministic rebase previews. These labels describe recorded facts only;
/// they never turn a preview into applied or verified plan truth.
enum PlanLocalizationKeyV1: String, CaseIterable, Codable, Sendable {
    case planHeading = "plan.heading"
    case planDocument = "plan.document"
    case planRevision = "plan.revision"
    case planRevisionState = "plan.revision.state"
    case planPlacement = "plan.placement"
    case planPlacementDisposition = "plan.placement.disposition"
    case planCoordinate = "plan.coordinate"
    case planReference = "plan.reference"
    case planContentBinding = "plan.content.binding"
    case planSpatialFrame = "plan.spatial.frame"
    case planRebasePreview = "plan.rebase.preview"
    case planRebaseReceipt = "plan.rebase.receipt"
    case planRebaseDecision = "plan.rebase.decision"
    case planRebaseWarning = "plan.rebase.warning"
    case planRebaseComponent = "plan.rebase.component"
    case planResidual = "plan.rebase.residual"
    case planExpectedRevision = "plan.rebase.expected_revision"
    case planHistoryImmutable = "plan.history.immutable"
    case planPreviewNotApplied = "plan.rebase.preview.not_applied"
    case planClaimBoundary = "plan.claim_boundary"
    case planNextStep = "plan.next_step"

    case documentActive = "plan.document.state.active"
    case documentRetired = "plan.document.state.retired"
    case revisionDraft = "plan.revision.state.draft"
    case revisionReleased = "plan.revision.state.released"
    case revisionWithdrawn = "plan.revision.state.withdrawn"
    case placementAccepted = "plan.placement.disposition.accepted"
    case placementReviewRequired = "plan.placement.disposition.review_required"
    case placementOrphaned = "plan.placement.disposition.orphaned"
    case placementOutOfBounds = "plan.placement.disposition.out_of_bounds"
    case decisionApplyRecorded = "plan.rebase.decision.apply_recorded"
    case decisionRejectRecorded = "plan.rebase.decision.reject_recorded"
    case warningPageMissing = "plan.rebase.warning.page_missing"
    case warningPageReordered = "plan.rebase.warning.page_reordered"
    case warningOutOfBounds = "plan.rebase.warning.out_of_bounds"
    case warningOrphanedAnchor = "plan.rebase.warning.orphaned_anchor"
    case warningResidualExceeded = "plan.rebase.warning.residual_exceeded"
    case warningCalibrationUnavailable = "plan.rebase.warning.calibration_unavailable"
    case warningComponentReviewRequired = "plan.rebase.warning.component_review_required"
    case errorStalePreview = "plan.error.stale_preview"
    case errorWrongReference = "plan.error.wrong_reference"
    case errorComponentConflict = "plan.error.component_conflict"
    case errorReviewRequired = "plan.error.review_required"
    case errorInvalidDigest = "plan.error.invalid_digest"

    var localizationKey: LocalizationKeyV1 {
        // swiftlint:disable:next force_try
        try! LocalizationKeyV1(rawValue)
    }

    var englishDefaultValue: String {
        switch self {
        case .planHeading: return "Plan"
        case .planDocument: return "Plan document"
        case .planRevision: return "Plan revision"
        case .planRevisionState: return "Plan revision state"
        case .planPlacement: return "Plan placement"
        case .planPlacementDisposition: return "Placement status"
        case .planCoordinate: return "Normalized page coordinate"
        case .planReference: return "Plan reference"
        case .planContentBinding: return "Bound content metadata"
        case .planSpatialFrame: return "Spatial reference frame"
        case .planRebasePreview: return "Rebase preview"
        case .planRebaseReceipt: return "Rebase receipt"
        case .planRebaseDecision: return "Recorded rebase decision"
        case .planRebaseWarning: return "Rebase warning"
        case .planRebaseComponent: return "Rebase component"
        case .planResidual: return "Residual normalized units"
        case .planExpectedRevision: return "Expected revision"
        case .planHistoryImmutable: return "Historic plan output remains unchanged"
        case .planPreviewNotApplied: return "Preview only; it is not applied or saved"
        case .planClaimBoundary: return "Recorded plan metadata only"
        case .planNextStep: return "Review the recorded plan preview"
        case .documentActive: return "Active"
        case .documentRetired: return "Retired"
        case .revisionDraft: return "Draft"
        case .revisionReleased: return "Released"
        case .revisionWithdrawn: return "Withdrawn"
        case .placementAccepted: return "Accepted placement"
        case .placementReviewRequired: return "Review required"
        case .placementOrphaned: return "Orphaned placement"
        case .placementOutOfBounds: return "Outside normalized bounds"
        case .decisionApplyRecorded: return "Recorded decision: apply"
        case .decisionRejectRecorded: return "Recorded decision: reject"
        case .warningPageMissing: return "Page is missing"
        case .warningPageReordered: return "Page order changed"
        case .warningOutOfBounds: return "Placement is outside normalized bounds"
        case .warningOrphanedAnchor: return "Anchor is orphaned"
        case .warningResidualExceeded: return "Residual exceeds the recorded limit"
        case .warningCalibrationUnavailable: return "Calibration is unavailable"
        case .warningComponentReviewRequired: return "Component review is required"
        case .errorStalePreview: return "Preview is stale"
        case .errorWrongReference: return "Reference does not match"
        case .errorComponentConflict: return "Component outputs conflict"
        case .errorReviewRequired: return "Review is required"
        case .errorInvalidDigest: return "Digest is invalid"
        }
    }

    var translatorComment: String {
        "English-only C29 label for recorded plan, normalized placement, and rebase facts; previews remain unapplied until a separate canonical mutation is recorded."
    }

    static func documentStateKey(_ state: PlanDocumentStateV1) -> Self {
        switch state {
        case .active: return .documentActive
        case .retired: return .documentRetired
        }
    }

    static func revisionStateKey(_ state: PlanRevisionStateV1) -> Self {
        switch state {
        case .draft: return .revisionDraft
        case .released: return .revisionReleased
        case .withdrawn: return .revisionWithdrawn
        }
    }

    static func placementDispositionKey(_ disposition: PlanPlacementDispositionV1) -> Self {
        switch disposition {
        case .accepted: return .placementAccepted
        case .reviewRequired: return .placementReviewRequired
        case .orphaned: return .placementOrphaned
        case .outOfBounds: return .placementOutOfBounds
        }
    }

    static func decisionKey(_ decision: PlanRebaseDecisionV1) -> Self {
        switch decision {
        case .approved: return .decisionApplyRecorded
        case .rejected: return .decisionRejectRecorded
        }
    }

    static func warningKey(_ warning: PlanRebaseWarningCodeV1) -> Self {
        switch warning {
        case .pageMissing: return .warningPageMissing
        case .pageReordered: return .warningPageReordered
        case .outOfBounds: return .warningOutOfBounds
        case .orphanedAnchor: return .warningOrphanedAnchor
        case .residualExceeded: return .warningResidualExceeded
        case .calibrationUnavailable: return .warningCalibrationUnavailable
        case .componentReviewRequired: return .warningComponentReviewRequired
        }
    }
}

enum PlanLocalizationPolicyV1 {
    static let sourceLocale = "en"
    static let shippingRuntimeLocales = ["en"]
    static let metadataLocale = "en-US"
    static let pseudoLocalesAreTestOnly = true
    static let englishOnly = true
    static let previewIsNotApplied = true
    static let historicDisplayIsFrozen = true
    static let denyByDefault = true
    static let keys = PlanLocalizationKeyV1.allCases.map(\.rawValue).sorted()
    static let documentStateKeys = PlanDocumentStateV1.allCases.map {
        PlanLocalizationKeyV1.documentStateKey($0).rawValue
    }.sorted()
    static let revisionStateKeys = PlanRevisionStateV1.allCases.map {
        PlanLocalizationKeyV1.revisionStateKey($0).rawValue
    }.sorted()
    static let placementDispositionKeys = PlanPlacementDispositionV1.allCases.map {
        PlanLocalizationKeyV1.placementDispositionKey($0).rawValue
    }.sorted()
    static let warningKeys = PlanRebaseWarningCodeV1.allCases.map {
        PlanLocalizationKeyV1.warningKey($0).rawValue
    }.sorted()
    static let prohibitedClaimPhrases = [
        "approval", "approved", "authorization", "authorized", "verified",
        "accuracy", "delivery", "delivered", "security", "secure", "legal",
        "compliance", "identity", "operator", "customer data", "work data",
        "evidence bytes", "private locator", "remote",
    ]

    static func containsProhibitedClaim(_ values: [String]) -> Bool {
        values.contains { value in
            let normalized = value.lowercased()
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
            return prohibitedClaimPhrases.contains { normalized.contains($0) }
        }
    }

    static func validate() throws {
        let typed = PlanLocalizationKeyV1.allCases
            .map(\.localizationKey.rawValue).sorted()
        let values = PlanLocalizationKeyV1.allCases.map(\.englishDefaultValue)
        guard typed == keys,
              Set(keys).count == keys.count,
              documentStateKeys.count == PlanDocumentStateV1.allCases.count,
              revisionStateKeys.count == PlanRevisionStateV1.allCases.count,
              placementDispositionKeys.count == PlanPlacementDispositionV1.allCases.count,
              warningKeys.count == PlanRebaseWarningCodeV1.allCases.count,
              sourceLocale == "en", shippingRuntimeLocales == ["en"],
              metadataLocale == "en-US", pseudoLocalesAreTestOnly,
              englishOnly, previewIsNotApplied, historicDisplayIsFrozen,
              denyByDefault, values.allSatisfy({
                  !$0.isEmpty && !containsProhibitedClaim([$0])
              }) else {
            throw LocalizationContractFailureV1.invalidValue
        }
    }
}

// MARK: - C37 reference-framed pose localization

/// English-only, typed labels for the C37 report/search projection. The
/// machine frame/disposition/reason remains beside these labels so a locale
/// cannot collapse TRUE, MAGNETIC, or PLAN_RELATIVE into an ambiguous phrase.
enum C37PoseLocalizationKeyV1: String, CaseIterable, Codable, Sendable {
    case heading = "pose.heading"
    case axis = "pose.axis"
    case current = "pose.current"
    case history = "pose.history"
    case referenceFrame = "pose.reference_frame"
    case referenceTrue = "pose.reference.true"
    case referenceMagnetic = "pose.reference.magnetic"
    case referencePlanRelative = "pose.reference.plan_relative"
    case referenceUnknown = "pose.reference.unknown"
    case observation = "pose.observation"
    case observed = "pose.observation.observed"
    case notObserved = "pose.observation.not_observed"
    case manualFallback = "pose.observation.manual_fallback"
    case uncertainty = "pose.uncertainty"
    case uncertaintyKnown = "pose.uncertainty.known"
    case uncertaintyUnknown = "pose.uncertainty.unknown"
    case notObservedReason = "pose.not_observed.reason"
    case reasonNotYetObserved = "pose.not_observed.reason.not_yet_observed"
    case reasonPhysicalMove = "pose.not_observed.reason.physical_move_reobservation"
    case reasonPlanFrameLost = "pose.not_observed.reason.plan_frame_lost_reobservation"
    case reasonObscured = "pose.not_observed.reason.obscured_or_unsafe"
    case reasonSourceUnavailable = "pose.not_observed.reason.source_unavailable"
    case reasonUserDeclined = "pose.not_observed.reason.user_declined"
    case currentTip = "pose.current_tip"
    case historyFrozen = "pose.history.frozen"
    case rebasePreview = "pose.rebase.preview"
    case previewNotApplied = "pose.rebase.preview.not_applied"
    case reviewRequired = "pose.review_required"
    case azimuth = "pose.azimuth"
    case elevation = "pose.elevation"
    case horizontalUncertainty = "pose.horizontal_uncertainty"
    case verticalUncertainty = "pose.vertical_uncertainty"
    case recordedSource = "pose.recorded_source"
    case claimBoundary = "pose.claim_boundary"
    case nextStep = "pose.next_step"
    case missing = "pose.missing"

    var localizationKey: LocalizationKeyV1 {
        // swiftlint:disable:next force_try
        try! LocalizationKeyV1(rawValue)
    }

    var englishDefaultValue: String {
        switch self {
        case .heading: return "Placement pose"
        case .axis: return "Pose axis"
        case .current: return "Current recorded pose"
        case .history: return "Pose history"
        case .referenceFrame: return "Reference frame"
        case .referenceTrue: return "TRUE reference frame"
        case .referenceMagnetic: return "MAGNETIC reference frame"
        case .referencePlanRelative: return "PLAN_RELATIVE reference frame"
        case .referenceUnknown: return "Reference frame unknown"
        case .observation: return "Observation"
        case .observed: return "Observed"
        case .notObserved: return "Not observed"
        case .manualFallback: return "Manual fallback recorded"
        case .uncertainty: return "Uncertainty"
        case .uncertaintyKnown: return "Uncertainty recorded"
        case .uncertaintyUnknown: return "Uncertainty unknown"
        case .notObservedReason: return "Reason not observed"
        case .reasonNotYetObserved: return "Not yet observed"
        case .reasonPhysicalMove: return "Moved; re-observation required"
        case .reasonPlanFrameLost: return "Plan frame lost; re-observation required"
        case .reasonObscured: return "Obscured or unavailable for observation"
        case .reasonSourceUnavailable: return "Observation source unavailable"
        case .reasonUserDeclined: return "Observation not recorded by request"
        case .currentTip: return "Current history tip"
        case .historyFrozen: return "Historic pose display remains unchanged"
        case .rebasePreview: return "Pose rebase preview"
        case .previewNotApplied: return "Preview only; it is not applied or saved"
        case .reviewRequired: return "Review required"
        case .azimuth: return "Azimuth"
        case .elevation: return "Elevation"
        case .horizontalUncertainty: return "Horizontal uncertainty"
        case .verticalUncertainty: return "Vertical uncertainty"
        case .recordedSource: return "Recorded source"
        case .claimBoundary: return "Recorded pose metadata only"
        case .nextStep: return "Review the recorded pose and uncertainty"
        case .missing: return "Pose not recorded"
        }
    }

    var translatorComment: String {
        "English-only C37 label for recorded reference-framed pose facts; it must not imply alignment, accuracy, compliance, or a sensor stream."
    }

    static func referenceFrameKey(
        _ value: C37PoseReferenceFrameProjectionV1
    ) -> Self {
        switch value {
        case .trueBearing: return .referenceTrue
        case .magneticBearing: return .referenceMagnetic
        case .planRelative: return .referencePlanRelative
        case .unknown: return .referenceUnknown
        }
    }

    static func observationStateKey(
        _ value: C37PoseObservationStateV1
    ) -> Self {
        switch value {
        case .observed: return .observed
        case .notObserved: return .notObserved
        case .manualFallback: return .manualFallback
        case .uncertaintyUnknown: return .uncertaintyUnknown
        case .reviewRequired: return .reviewRequired
        }
    }

    static func notObservedReasonKey(
        _ value: PoseNotObservedReasonV1
    ) -> Self {
        switch value {
        case .notYetObserved: return .reasonNotYetObserved
        case .physicalMoveReobservationRequired: return .reasonPhysicalMove
        case .planFrameLostReobservationRequired: return .reasonPlanFrameLost
        case .obscuredOrUnsafe: return .reasonObscured
        case .sourceUnavailable: return .reasonSourceUnavailable
        case .userDeclined: return .reasonUserDeclined
        }
    }
}

enum C37PoseLocalizationPolicyV1 {
    static let sourceLocale = "en"
    static let shippingRuntimeLocales = ["en"]
    static let metadataLocale = "en-US"
    static let pseudoLocalesAreTestOnly = true
    static let englishOnly = true
    static let denyByDefault = true
    static let historyFrozen = true
    static let previewIsNotApplied = true
    static let keys = C37PoseLocalizationKeyV1.allCases.map(\.rawValue).sorted()
    static let prohibitedClaimPhrases = [
        "east", "west", "north", "south", "aligned", "aimed correctly",
        "compliance", "accurate", "verified", "approved", "authorized",
        "secure", "delivered", "operator", "customer data", "work data",
        "sensor stream", "location stream",
    ]

    static func containsProhibitedClaim(_ values: [String]) -> Bool {
        values.contains { value in
            let normalized = value.lowercased()
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
            return prohibitedClaimPhrases.contains { normalized.contains($0) }
        }
    }

    static func validate() throws {
        let definitions = C37PoseLocalizationKeyV1.allCases
        let values = definitions.map(\.englishDefaultValue)
        guard definitions.map(\.localizationKey.rawValue).sorted() == keys,
              Set(keys).count == keys.count,
              sourceLocale == "en", shippingRuntimeLocales == ["en"],
              metadataLocale == "en-US", pseudoLocalesAreTestOnly,
              englishOnly, denyByDefault, historyFrozen, previewIsNotApplied,
              values.allSatisfy({ !$0.isEmpty && !containsProhibitedClaim([$0]) }) else {
            throw LocalizationContractFailureV1.invalidValue
        }
    }
}
// MARK: - C30 operating-context localization

/// Closed English-only keys for the C30 context projection.  The observed
/// condition, optional solar calculation, expected control state, and paired
/// comparison disposition are deliberately labelled as separate facts.
enum C30OperatingContextLocalizationKeyV1: String, CaseIterable, Codable, Sendable {
    case heading = "evidence.context.heading"
    case condition = "evidence.context.condition"
    case daylight = "evidence.context.condition.daylight"
    case civilTwilight = "evidence.context.condition.civil_twilight"
    case night = "evidence.context.condition.night"
    case coveredDay = "evidence.context.condition.covered_day"
    case coveredNight = "evidence.context.condition.covered_night"
    case conditionUnknown = "evidence.context.condition.unknown"
    case userObserved = "evidence.context.source.user_observed"
    case solarDerived = "evidence.context.source.solar_derived"
    case temporalBasis = "evidence.context.temporal_basis"
    case expectedControl = "evidence.context.expected_control"
    case expectedOperating = "evidence.context.expected_control.operating"
    case expectedNotOperating = "evidence.context.expected_control.not_operating"
    case expectedNone = "evidence.context.expected_control.none"
    case pairedComparison = "evidence.context.paired_comparison"
    case pairedComparable = "evidence.context.paired_comparison.comparable"
    case pairedMismatch = "evidence.context.paired_comparison.mismatch"
    case pairedNotLinked = "evidence.context.paired_comparison.not_linked"
    case pairedMismatchReason = "evidence.context.paired_comparison.reason"
    case historyFrozen = "evidence.context.history.frozen"
    case claimBoundary = "evidence.context.claim_boundary"
    case nextStep = "evidence.context.next_step"
    case manualOffline = "evidence.context.manual_offline"
    case derivedCondition = "evidence.context.derived_condition"

    var localizationKey: LocalizationKeyV1 {
        // swiftlint:disable:next force_try
        try! LocalizationKeyV1(rawValue)
    }

    var englishDefaultValue: String {
        switch self {
        case .heading: return "Operating context"
        case .condition: return "Recorded condition"
        case .daylight: return "Daylight recorded"
        case .civilTwilight: return "Civil twilight recorded"
        case .night: return "Night recorded"
        case .coveredDay: return "Covered-day condition recorded"
        case .coveredNight: return "Covered-night condition recorded"
        case .conditionUnknown: return "Condition unknown"
        case .userObserved: return "User-observed condition"
        case .solarDerived: return "Solar calculation (separate)"
        case .temporalBasis: return "Recorded time basis"
        case .expectedControl: return "Expected control state"
        case .expectedOperating: return "Expected operating"
        case .expectedNotOperating: return "Expected not operating"
        case .expectedNone: return "No expectation recorded"
        case .pairedComparison: return "Paired comparison"
        case .pairedComparable: return "Comparable references recorded"
        case .pairedMismatch: return "Paired references differ"
        case .pairedNotLinked: return "No paired reference"
        case .pairedMismatchReason: return "Comparison difference"
        case .historyFrozen: return "Historic display is frozen"
        case .claimBoundary: return "Recorded context only; no operational conclusion"
        case .nextStep: return "Review the recorded context and comparison differences"
        case .manualOffline: return "Manual/offline path remains available"
        case .derivedCondition: return "Derived condition (separate fact)"
        }
    }

    var translatorComment: String {
        "English-only C30 label for separately recorded evidence context facts; do not infer lighting, control state, measurement, failure, or compliance."
    }

    static func conditionKey(
        _ value: EvidenceLightingConditionV1
    ) -> Self {
        switch value {
        case .daylight: return .daylight
        case .civilTwilight: return .civilTwilight
        case .night: return .night
        case .coveredDayCondition: return .coveredDay
        case .coveredNightCondition: return .coveredNight
        case .unknown: return .conditionUnknown
        }
    }

    static func expectedControlKey(
        _ value: ExpectedControlStateV1?
    ) -> Self {
        switch value {
        case .some(.expectedOperating): return .expectedOperating
        case .some(.expectedNotOperating): return .expectedNotOperating
        case .some(.noExpectation), .none: return .expectedNone
        }
    }

    static let keys = allCases.map(\.rawValue).sorted()
    static let sourceLocale = "en"
    static let shippingRuntimeLocales = ["en"]
    static let metadataLocale = "en-US"
    static let pseudoLocalesAreTestOnly = true
    static let denyByDefault = true
    static let historicDisplayFrozen = true
    static let manualOfflinePathPreserved = true
}

enum C30OperatingContextLocalizationPolicyV1 {
    static let prohibitedClaimPhrases = [
        "actual control", "control failure", "darkness inferred", "derived darkness",
        "measurement", "compliance", "accurate", "verified", "approved",
        "authorized", "secure", "delivered", "customer data", "work data",
        "sensor stream", "photo proves", "timestamp proves",
    ]

    static func containsProhibitedClaim(_ values: [String]) -> Bool {
        values.contains { value in
            let normalized = value.lowercased()
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
            return prohibitedClaimPhrases.contains { normalized.contains($0) }
        }
    }

    static func validate() throws {
        let values = C30OperatingContextLocalizationKeyV1.allCases
        guard values.map(\.rawValue).sorted() == C30OperatingContextLocalizationKeyV1.keys,
              Set(C30OperatingContextLocalizationKeyV1.keys).count == values.count,
              C30OperatingContextLocalizationKeyV1.sourceLocale == "en",
              C30OperatingContextLocalizationKeyV1.shippingRuntimeLocales == ["en"],
              C30OperatingContextLocalizationKeyV1.metadataLocale == "en-US",
              C30OperatingContextLocalizationKeyV1.pseudoLocalesAreTestOnly,
              C30OperatingContextLocalizationKeyV1.denyByDefault,
              C30OperatingContextLocalizationKeyV1.historicDisplayFrozen,
              C30OperatingContextLocalizationKeyV1.manualOfflinePathPreserved,
              !containsProhibitedClaim(values.map(\.englishDefaultValue)) else {
            throw LocalizationContractFailureV1.invalidValue
        }
    }
}
// C30: this seam consumes only the frozen, metadata-only operating-context projection.
enum C30ConsumerBoundaryV1_Domain_Localization_LocalizationContractsV1 {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Domain/Localization/LocalizationContractsV1.swift", role: .localization)
}

// MARK: - C31 exterior/parking-lighting localization

/// English-only labels for recorded lighting topology, observations,
/// measurements, criteria, and stop conditions.  Raw durable enum values are
/// never used as user-facing text.
enum C31LightingLocalizationKeyV1: String, CaseIterable, Codable, Sendable {
    case systemHeading = "lighting.system.heading"
    case topology = "lighting.system.topology"
    case zones = "lighting.system.zones"
    case controlGroups = "lighting.system.control_groups"
    case luminaires = "lighting.system.luminaires"
    case observationHeading = "lighting.observation.heading"
    case observationRecorded = "lighting.observation.recorded"
    case issueRecorded = "lighting.issue.recorded"
    case issueOpen = "lighting.issue.open"
    case issueResolved = "lighting.issue.resolved"
    case issueSuperseded = "lighting.issue.superseded"
    case measurementHeading = "lighting.measurement.heading"
    case illuminance = "lighting.measurement.illuminance"
    case calibration = "lighting.measurement.calibration"
    case claimObserved = "lighting.claim.observed"
    case claimMeasured = "lighting.claim.measured"
    case claimDerived = "lighting.claim.derived"
    case claimCriterion = "lighting.claim.criterion"
    case claimExternal = "lighting.claim.external_reference"
    case claimUnavailable = "lighting.claim.unavailable"
    case safetyStop = "lighting.safety.stop"
    case safetyNextStep = "lighting.safety.next_step"
    case claimBoundary = "lighting.claim.boundary"
    case historyFrozen = "lighting.history.frozen"
    case manualOffline = "lighting.manual_offline"

    var localizationKey: LocalizationKeyV1 {
        // swiftlint:disable:next force_try
        try! LocalizationKeyV1(rawValue)
    }

    var englishDefaultValue: String {
        switch self {
        case .systemHeading: return "Lighting record"
        case .topology: return "Recorded topology"
        case .zones: return "Zones"
        case .controlGroups: return "Control groups"
        case .luminaires: return "Luminaires"
        case .observationHeading: return "Lighting observation"
        case .observationRecorded: return "Observation recorded"
        case .issueRecorded: return "Recorded issue"
        case .issueOpen: return "Issue open"
        case .issueResolved: return "Issue resolved with recorded evidence"
        case .issueSuperseded: return "Issue superseded by a later record"
        case .measurementHeading: return "Measurement plan"
        case .illuminance: return "Recorded illuminance measurement"
        case .calibration: return "Calibration reference"
        case .claimObserved: return "Observed fact"
        case .claimMeasured: return "Measured fact with recorded inputs"
        case .claimDerived: return "Derived fact from recorded inputs"
        case .claimCriterion: return "Criterion reference recorded"
        case .claimExternal: return "External evidence reference recorded"
        case .claimUnavailable: return "Claim unavailable"
        case .safetyStop: return "Safety stop recorded"
        case .safetyNextStep: return "Review the recorded authority and control-plan references before continuing"
        case .claimBoundary: return "Recorded facts only; no operational conclusion"
        case .historyFrozen: return "Historic display is frozen"
        case .manualOffline: return "Manual/offline path remains available"
        }
    }

    var translatorComment: String {
        "English-only C31 label for recorded exterior-lighting facts and references; do not add safety, compliance, security, ADA, IES, or operational conclusions."
    }

    static func claimKey(_ value: LightingClaimTierV1) -> Self {
        switch value {
        case .observed: return .claimObserved
        case .measured: return .claimMeasured
        case .derived: return .claimDerived
        case .screened: return .claimCriterion
        case .externallyAttested: return .claimExternal
        }
    }

    static func issueKey(_ value: LightingIssueDispositionV1) -> Self {
        switch value {
        case .open: return .issueOpen
        case .resolved: return .issueResolved
        case .superseded: return .issueSuperseded
        }
    }

    static let keys = allCases.map(\.rawValue).sorted()
    static let sourceLocale = "en"
    static let shippingRuntimeLocales = ["en"]
    static let metadataLocale = "en-US"
    static let pseudoLocalesAreTestOnly = true
    static let denyByDefault = true
    static let historicDisplayFrozen = true
    static let manualOfflinePathPreserved = true
}

enum C31LightingLocalizationPolicyV1 {
    static let englishOnly = true
    static let textAndIconRequired = true
    static let nonColorStateRequired = true
    static let historicDisplayFrozen = true
    static let manualOfflinePathPreserved = true
    static let forbiddenClaimPhrases = [
        "compliance", "safety certified", "security certified", "ada compliant",
        "ies compliant", "verified safe", "actual control", "control failure",
        "darkness inferred", "photo proves", "timestamp proves", "survey-grade",
        "gis", "cad", "bim", "lidar", "remote delivery", "secure",
    ]

    static func containsProhibitedClaim(_ values: [String]) -> Bool {
        values.contains { value in
            let normalized = value.lowercased()
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
            return forbiddenClaimPhrases.contains { normalized.contains($0) }
        }
    }

    static func validate() throws {
        let values = C31LightingLocalizationKeyV1.allCases
        guard values.map(\.rawValue).sorted() == C31LightingLocalizationKeyV1.keys,
              Set(C31LightingLocalizationKeyV1.keys).count == values.count,
              values.allSatisfy({ !$0.englishDefaultValue.isEmpty }),
              englishOnly, textAndIconRequired, nonColorStateRequired,
              historicDisplayFrozen, manualOfflinePathPreserved,
              !containsProhibitedClaim(values.map(\.englishDefaultValue)) else {
            throw LocalizationContractFailureV1.invalidValue
        }
    }
}

// MARK: - C32 assistance review localization

enum C32AssistanceLocalizationKeyV1: String, CaseIterable, Codable, Sendable {
    case unverified = "assistance.proposal.unverified"
    case review = "assistance.proposal.review"
    case accept = "assistance.proposal.accept"
    case reject = "assistance.proposal.reject"
    case expired = "assistance.proposal.expired"
    case manualAvailable = "assistance.manual.available"
    case permissionDenied = "assistance.permission.denied"
    case interrupted = "assistance.interrupted"

    var localizationKey: LocalizationKeyV1 {
        // The closed raw values are validated by C32AssistanceLocalizationPolicyV1.
        // swiftlint:disable:next force_try
        try! LocalizationKeyV1(rawValue)
    }
}

enum C32AssistanceLocalizationPolicyV1 {
    static let englishOnly = true
    static let proposalAlwaysLabeledUnverified = true
    static let explicitReviewActionRequired = true
    static let manualPathAlwaysNamed = true
    static let permissionAndInterruptionStatesAreTruthful = true
    static let stateIsNotColorOnly = true

    static func validate() throws {
        let keys = C32AssistanceLocalizationKeyV1.allCases.map(\.localizationKey)
        guard keys.count == 8,
              Set(keys).count == keys.count,
              englishOnly,
              proposalAlwaysLabeledUnverified,
              explicitReviewActionRequired,
              manualPathAlwaysNamed,
              permissionAndInterruptionStatesAreTruthful,
              stateIsNotColorOnly else {
            throw LocalizationContractFailureV1.invalidValue
        }
    }
}


// MARK: - C33 temporal evidence localization

enum TemporalEvidenceLocalizationKeyV1: String, CaseIterable, Codable, Sendable {
    case reviewRequired = "temporal_evidence.review_required"
    case audio = "temporal_evidence.kind.audio"
    case video = "temporal_evidence.kind.video"
    case durationLimit = "temporal_evidence.limit.duration"
    case byteLimit = "temporal_evidence.limit.bytes"
    case storageLimit = "temporal_evidence.limit.storage"
    case permissionDenied = "temporal_evidence.permission.denied"
    case interrupted = "temporal_evidence.interrupted"
    case cancelled = "temporal_evidence.cancelled"
    case descriptionRequired = "temporal_evidence.description.required"
    case transcriptRequired = "temporal_evidence.transcript.required"
    case manualImport = "temporal_evidence.manual_import"

    var localizationKey: LocalizationKeyV1 {
        // swiftlint:disable:next force_try
        try! LocalizationKeyV1(rawValue)
    }
}

enum TemporalEvidenceLocalizationPolicyV1 {
    static let visibleLimitReasonRequired = true
    static let interruptionStatesMustSayNothingWasSaved = true
    static let permissionDenialNamesManualFallback = true
    static let transcriptIsHumanAuthored = true
    static let stateIsNotColorOnly = true

    static func validate() throws {
        let values = TemporalEvidenceLocalizationKeyV1.allCases
        guard values.map(\.rawValue).count == Set(values.map(\.rawValue)).count,
              values.allSatisfy({ !$0.localizationKey.rawValue.isEmpty }),
              visibleLimitReasonRequired, interruptionStatesMustSayNothingWasSaved,
              permissionDenialNamesManualFallback, transcriptIsHumanAuthored,
              stateIsNotColorOnly else { throw LocalizationContractFailureV1.invalidValue }
    }
}

enum AssetLabelLocalizationKeyV1: String, CaseIterable, Codable, Sendable {
    case preview = "asset_label.preview"
    case explicitStart = "asset_label.explicit_start"
    case manualShortCode = "asset_label.manual_short_code"
    case activeExactReprint = "asset_label.active_exact_reprint"
    case historicExportOnly = "asset_label.historic_export_only"
    case blockedMissingRelease = "asset_label.blocked_missing_release"
    case generated = "asset_label.generated"
    case handedOff = "asset_label.handed_off"
    case claimBoundary = "asset_label.claim_boundary"
}

enum AssetLabelLocalizationPolicyV1 {
    static let englishOnly = true
    static let statusIsNotColorOnly = true
    static let manualEntryRemainsNamed = true
    static let outputNeverSaysPrintedOrDelivered = true
    static func validate() throws {
        let keys = AssetLabelLocalizationKeyV1.allCases.map(\.rawValue)
        guard keys.count == Set(keys).count, statusIsNotColorOnly,
              manualEntryRemainsNamed, outputNeverSaysPrintedOrDelivered else {
            throw LocalizationContractFailureV1.invalidValue
        }
    }
}

// MARK: - C46 operational system handoff localization

enum OperationalContactLocalizationKeyV1: String, CaseIterable, Codable, Sendable {
    case directions = "operational_contact.action.directions"
    case call = "operational_contact.action.call"
    case text = "operational_contact.action.text"
    case email = "operational_contact.action.email"
    case opensSystemApp = "operational_contact.handoff.opens_system_app"
    case handedOff = "operational_contact.handoff.handed_off"
    case targetMissing = "operational_contact.handoff.target_missing"
    case targetStale = "operational_contact.handoff.target_stale"
    case targetInvalid = "operational_contact.handoff.target_invalid"
    case systemUnavailable = "operational_contact.handoff.system_unavailable"
    case systemRejected = "operational_contact.handoff.system_rejected"
    case cancelled = "operational_contact.handoff.cancelled"
    case claimBoundary = "operational_contact.handoff.claim_boundary"

    var localizationKey: LocalizationKeyV1 {
        // swiftlint:disable:next force_try
        try! LocalizationKeyV1(rawValue)
    }
}

enum OperationalContactLocalizationPolicyV1 {
    static let englishOnly = true
    static let explicitUserActionRequired = true
    static let handedOffMeansSystemAcceptedPresentationOnly = true
    static let sentDeliveredConnectedOrArrivedClaimAllowed = false
    static let destinationIsIncludedInLocalizedHistory = false
    static let historicIntentIsActionable = false

    static func key(
        for disposition: SystemHandoffDispositionV1
    ) -> OperationalContactLocalizationKeyV1 {
        switch disposition {
        case .handedOffToSystem: .handedOff
        case .targetMissing: .targetMissing
        case .targetStale: .targetStale
        case .targetInvalid: .targetInvalid
        case .systemUnavailable: .systemUnavailable
        case .systemRejected: .systemRejected
        case .cancelledBeforeHandoff: .cancelled
        }
    }

    static func validate() throws {
        let values = OperationalContactLocalizationKeyV1.allCases
        guard values.map(\.rawValue).count == Set(values.map(\.rawValue)).count,
              values.allSatisfy({ !$0.localizationKey.rawValue.isEmpty }),
              explicitUserActionRequired,
              handedOffMeansSystemAcceptedPresentationOnly,
              !sentDeliveredConnectedOrArrivedClaimAllowed,
              !destinationIsIncludedInLocalizedHistory,
              !historicIntentIsActionable else {
            throw LocalizationContractFailureV1.invalidValue
        }
    }
}

enum ActivityContractLocalizationKeyV2: String, Codable, CaseIterable, Hashable, Sendable {
    case installation = "activity.contract.installation"
    case punchReview = "activity.contract.punch_review"
    case noPlanFallback = "activity.contract.no_plan_fallback"
    case deferred = "activity.contract.deferred"
    case unableToComplete = "activity.contract.unable_to_complete"
    case fieldComplete = "activity.contract.field_complete"
    case readyForReview = "activity.contract.ready_for_review"
    case claimBoundary = "activity.contract.claim_boundary"

    var localizationKey: LocalizationKeyV1 { get throws { try .init(rawValue) } }
}

enum C47ActivityContractConformance_FieldEvidenceApp_Domain_Localization_LocalizationContractsV1_swift {
    static let integrationRole = "TRUTHFUL_FAMILY_WORDING"
    static let sharedReceipt = SharedActivityEnvelopeReceiptV1.self
    static let installationReceipt = InstallationActivityContractReceiptV1.self
    static let punchReceipt = PunchActivityContractReceiptV1.self
    static let noPlanFallback = NoPlanFallbackV1.self
    static let usesExistingWriterRendererStoreAndPackageInfrastructure = true
    static let createsSecondRouteOrInspectionAlias = false
    static func validateReadable(_ value: ActivitySessionEnvelopeV2) throws { try value.validateForRead() }
}

// MARK: - C48 portable-review derived-consumer localization

/// Customer-facing wording for the derived review history surface.  These
/// keys deliberately describe a recorded state or an unverified assertion;
/// they do not offer delivery, identity, security, or approval claims.
enum C48PortableReviewLocalizationKeyV1: String, CaseIterable, Codable, Hashable, Sendable {
    case capabilityWarning = "portable_review.capability.forwardable_warning"
    case responseAcknowledged = "portable_review.response.acknowledged"
    case responseApproved = "portable_review.response.approved"
    case responseChangesRequested = "portable_review.response.changes_requested"
    case historyOnly = "portable_review.response.history_only"
    case responseNotVerified = "portable_review.response.not_verified"
    case responseRecorded = "portable_review.response.recorded"

    var localizationKey: LocalizationKeyV1 {
        get throws { try LocalizationKeyV1(rawValue) }
    }
}

enum C48PortableReviewLocalizationPolicyV1 {
    static let sourceLocale = "en"
    static let englishOnly = true
    static let explicitRecordedWording = true
    static let selfAssertedIdentityIsUnverified = true
    static let capabilityIsNotSecurityWording = true
    static let noDeliveryOrApprovalClaim = true

    static let keys = C48PortableReviewLocalizationKeyV1.allCases

    static func validate() throws {
        let rawValues = keys.map(\.rawValue)
        guard rawValues == rawValues.sorted(),
              Set(rawValues).count == rawValues.count,
              keys.allSatisfy({ !$0.rawValue.isEmpty }),
              explicitRecordedWording,
              selfAssertedIdentityIsUnverified,
              capabilityIsNotSecurityWording,
              noDeliveryOrApprovalClaim else {
            throw LocalizationContractFailureV1.invalidValue
        }
    }
}

// MARK: - C49 work-resource localization

enum C49WorkResourceLocalizationKeyV1: String, CaseIterable, Codable, Hashable, Sendable {
    case customerSafe = "work_resource.customer_safe"
    case directCostInternal = "work_resource.direct_cost.internal"
    case directCostPreview = "work_resource.direct_cost_preview"
    case duration = "work_resource.duration"
    case durationManual = "work_resource.duration.manual"
    case internalOnly = "work_resource.internal_only"
    case material = "work_resource.material"
    case noLiveInventoryClaim = "work_resource.no_live_inventory_claim"
}

enum C49WorkResourceLocalizationPolicyV1 {
    static let sourceLocale = "en"
    static let keys = C49WorkResourceLocalizationKeyV1.allCases
    static let rawStockAndInventoryClaimsAreNotLocalized = true

    static func english(_ key: C49WorkResourceLocalizationKeyV1) -> String {
        switch key {
        case .duration: return "Duration"
        case .durationManual: return "Time spent — entered manually"
        case .material: return "Material"
        case .directCostInternal:
            return "Direct cost — entered amount; no tax, rates, markup, or invoice calculation."
        case .directCostPreview: return "Direct cost preview"
        case .internalOnly: return "Internal only"
        case .customerSafe: return "Customer safe"
        case .noLiveInventoryClaim: return "No live inventory claim"
        }
    }

    static func validate() throws {
        let values = keys.map(\.rawValue)
        guard values == values.sorted(), Set(values).count == values.count,
              keys.allSatisfy({ !english($0).isEmpty }),
              rawStockAndInventoryClaimsAreNotLocalized else {
            throw LocalizationContractFailureV1.invalidValue
        }
    }
}

// MARK: - C52 portable service-request localization

/// C52 wording describes recorded, self-asserted service-request state only.
/// It deliberately does not promise emergency handling, delivery, identity,
/// urgency verification, or an SLA.
enum C52ServiceRequestLocalizationKeyV1: String, CaseIterable, Codable, Hashable, Sendable {
    case contactUnverified = "service_request.contact.unverified"
    case duplicateSuggestion = "service_request.duplicate.suggestion"
    case intakeManual = "service_request.intake.manual"
    case intakePortable = "service_request.intake.portable"
    case stateAccepted = "service_request.state.accepted"
    case stateDeclined = "service_request.state.declined"
    case stateHistoryOnly = "service_request.state.history_only"
    case stateUntriaged = "service_request.state.untriaged"
    case statusNoDeliveryClaim = "service_request.status.no_delivery_claim"
    case urgencySelfAsserted = "service_request.urgency.self_asserted"

    var localizationKey: LocalizationKeyV1 {
        // swiftlint:disable:next force_try
        try! LocalizationKeyV1(rawValue)
    }
}

enum C52ServiceRequestLocalizationPolicyV1 {
    static let sourceLocale = "en"
    static let englishOnly = true
    static let duplicateCandidatesAreSuggestionOnly = true
    static let requesterIdentityIsUnverified = true
    static let urgencyIsSelfAsserted = true
    static let emergencyHandlingIsNotClaimed = true
    static let deliveryIsNotClaimed = true
    static let serviceLevelAgreementIsNotClaimed = true

    static func english(_ key: C52ServiceRequestLocalizationKeyV1) -> String {
        switch key {
        case .intakeManual: return "Service request recorded manually"
        case .intakePortable: return "Portable service request"
        case .stateUntriaged: return "Awaiting review"
        case .stateAccepted: return "Service request accepted"
        case .stateDeclined: return "Service request declined"
        case .stateHistoryOnly: return "History only"
        case .duplicateSuggestion: return "Possible duplicate — review required"
        case .contactUnverified: return "Contact information is unverified"
        case .urgencySelfAsserted: return "Urgency is self-asserted"
        case .statusNoDeliveryClaim: return "Recorded locally; delivery was not confirmed"
        }
    }

    static func validate() throws {
        let values = C52ServiceRequestLocalizationKeyV1.allCases
        let rawValues = values.map(\.rawValue)
        guard sourceLocale == "en",
              englishOnly,
              rawValues == rawValues.sorted(),
              Set(rawValues).count == rawValues.count,
              values.allSatisfy({ !$0.localizationKey.rawValue.isEmpty && !english($0).isEmpty }),
              duplicateCandidatesAreSuggestionOnly,
              requesterIdentityIsUnverified,
              urgencyIsSelfAsserted,
              emergencyHandlingIsNotClaimed,
              deliveryIsNotClaimed,
              serviceLevelAgreementIsNotClaimed else {
            throw LocalizationContractFailureV1.invalidValue
        }
    }
}

// MARK: - C34 route restoration localization

enum C34RouteLocalizationKeyV1: String, CaseIterable, Codable, Hashable, Sendable {
    case safeFallbackAction = "navigation.route.fallback.action"
    case safeFallbackHeading = "navigation.route.fallback.heading"
    case corruptSnapshot = "navigation.route.fallback.reason.corrupt_snapshot"
    case deletedOrTombstoned = "navigation.route.fallback.reason.deleted_or_tombstoned"
    case invalidTarget = "navigation.route.fallback.reason.invalid_target"
    case protectedDataUnavailable = "navigation.route.fallback.reason.protected_data_unavailable"
    case retiredOrMissingPackage = "navigation.route.fallback.reason.retired_or_missing_package"
    case revokedAvailability = "navigation.route.fallback.reason.revoked_availability"
    case staleRevision = "navigation.route.fallback.reason.stale_revision"
    case unsupportedSnapshotVersion = "navigation.route.fallback.reason.unsupported_snapshot_version"
    case wrongWorkspace = "navigation.route.fallback.reason.wrong_workspace"
}

extension RouteFallbackReasonV1 {
    var c34LocalizationKey: C34RouteLocalizationKeyV1 {
        switch self {
        case .wrongWorkspace: return .wrongWorkspace
        case .staleRevision: return .staleRevision
        case .deletedOrTombstoned: return .deletedOrTombstoned
        case .retiredOrMissingPackage: return .retiredOrMissingPackage
        case .revokedAvailability: return .revokedAvailability
        case .protectedDataUnavailable: return .protectedDataUnavailable
        case .corruptSnapshot: return .corruptSnapshot
        case .unsupportedSnapshotVersion: return .unsupportedSnapshotVersion
        case .invalidTarget: return .invalidTarget
        }
    }
}

enum C34RouteLocalizationContractV1 {
    static let keys = C34RouteLocalizationKeyV1.allCases.sorted { $0.rawValue < $1.rawValue }
    static let englishRuntimeAuthority = true
    static let localeChangesDoNotChangeRouteIdentity = true
    static let rtlChangesDoNotChangeRouteIdentity = true
    static let customerContentIsNotLocalizationInput = true

    static func english(_ key: C34RouteLocalizationKeyV1) -> String {
        switch key {
        case .safeFallbackAction: return "Go to safe destination"
        case .safeFallbackHeading: return "This destination is unavailable"
        case .corruptSnapshot: return "Saved navigation could not be read."
        case .deletedOrTombstoned: return "That item is no longer available."
        case .invalidTarget: return "That destination is not available."
        case .protectedDataUnavailable: return "Unlock this device to continue."
        case .retiredOrMissingPackage: return "That feature is no longer available."
        case .revokedAvailability: return "Access to that destination is no longer available."
        case .staleRevision: return "That item changed since it was last opened."
        case .unsupportedSnapshotVersion: return "Saved navigation came from an unsupported version."
        case .wrongWorkspace: return "That destination belongs to a different workspace."
        }
    }

    static func validate() throws {
        let values = keys.map(\.rawValue)
        let mappedReasons = Set([
            RouteFallbackReasonV1.wrongWorkspace,
            .staleRevision, .deletedOrTombstoned, .retiredOrMissingPackage,
            .revokedAvailability, .protectedDataUnavailable, .corruptSnapshot,
            .unsupportedSnapshotVersion, .invalidTarget,
        ].map(\.c34LocalizationKey))
        guard values == values.sorted(), Set(values).count == values.count,
              mappedReasons.count == 9,
              keys.allSatisfy({ !english($0).isEmpty }) else {
            throw LocalizationContractFailureV1.invalidValue
        }
    }
}

// MARK: - C53 asset-service reliability localization

/// C53 labels describe recorded operational-impact and qualification state.
/// They never turn an observation into a verified identity, uptime claim, or
/// release-to-service decision.
enum C53AssetServiceReliabilityLocalizationKeyV1: String, CaseIterable, Codable, Hashable, Sendable {
    case causeUnverified = "service_reliability.cause.unverified"
    case exposureQualified = "service_reliability.exposure.qualified"
    case incidentRecorded = "service_reliability.incident.recorded"
    case metricUnavailable = "service_reliability.metric.unavailable"
    case restorationRecorded = "service_reliability.restoration.recorded"
    case segmentImpact = "service_reliability.segment.impact"

    var localizationKey: LocalizationKeyV1 {
        // swiftlint:disable:next force_try
        try! LocalizationKeyV1(rawValue)
    }
}

enum C53AssetServiceReliabilityLocalizationPolicyV1 {
    static let sourceLocale = "en"
    static let englishOnly = true
    static let recordedStateOnly = true
    static let verifiedIdentityClaimed = false
    static let uptimeClaimed = false
    static let releaseToServiceClaimed = false
    static let unknownIntervalsQualifyForExactMetrics = false

    static func english(_ key: C53AssetServiceReliabilityLocalizationKeyV1) -> String {
        switch key {
        case .causeUnverified: return "Cause assessment is unverified"
        case .exposureQualified: return "Qualified service exposure"
        case .incidentRecorded: return "Operational impact recorded"
        case .metricUnavailable: return "Reliability metric unavailable"
        case .restorationRecorded: return "Restoration recorded"
        case .segmentImpact: return "Service impact segment"
        }
    }

    static func validate() throws {
        let values = C53AssetServiceReliabilityLocalizationKeyV1.allCases
        let rawValues = values.map(\.rawValue)
        guard sourceLocale == "en",
              englishOnly,
              recordedStateOnly,
              !verifiedIdentityClaimed,
              !uptimeClaimed,
              !releaseToServiceClaimed,
              !unknownIntervalsQualifyForExactMetrics,
              rawValues == rawValues.sorted(),
              Set(rawValues).count == rawValues.count,
              values.allSatisfy({ !$0.localizationKey.rawValue.isEmpty && !english($0).isEmpty }) else {
            throw LocalizationContractFailureV1.invalidValue
        }
    }
}

// MARK: - C09 operations dashboard localization

enum C09OperationsDashboardLocalizationKeyV1: String, CaseIterable, Codable, Hashable, Sendable {
    case assetName = "operations_dashboard.asset_name"
    case correctExposure = "operations_dashboard.correct_exposure"
    case correctExposureHint = "operations_dashboard.correct_exposure.hint"
    case definitionVersion = "operations_dashboard.definition_version"
    case exposureHeading = "operations_dashboard.exposure.heading"
    case exposureQualified = "operations_dashboard.exposure.qualified"
    case exposureUnavailable = "operations_dashboard.exposure.unavailable"
    case heading = "operations_dashboard.heading"
    case introduction = "operations_dashboard.introduction"
    case metricFullInterruptionAvailability = "operations_dashboard.metric.full_interruption_availability"
    case metricMTBF = "operations_dashboard.metric.mtbf"
    case metricUnavailable = "operations_dashboard.metric.unavailable"
    case metricsHeading = "operations_dashboard.metrics.heading"
    case provenanceCorrected = "operations_dashboard.provenance.corrected"
    case provenanceRecorded = "operations_dashboard.provenance.recorded"
    case provenanceSuperseded = "operations_dashboard.provenance.superseded"
    case reviewExposure = "operations_dashboard.review_exposure"
    case reviewExposureHint = "operations_dashboard.review_exposure.hint"
    case reviewMetricDetails = "operations_dashboard.review_metric_details"
    case reviewMetricDetailsHint = "operations_dashboard.review_metric_details.hint"
    case timelineCorrectiveWork = "operations_dashboard.timeline.corrective_work"
    case timelineEmpty = "operations_dashboard.timeline.empty"
    case timelineEvidenceAssociation = "operations_dashboard.timeline.evidence_association"
    case timelineExplicitAssetChange = "operations_dashboard.timeline.explicit_asset_change"
    case timelineFinding = "operations_dashboard.timeline.finding"
    case timelineHeading = "operations_dashboard.timeline.heading"
    case timelineImpactSegment = "operations_dashboard.timeline.impact_segment"
    case timelineIncident = "operations_dashboard.timeline.incident"
    case timelineInspection = "operations_dashboard.timeline.inspection"
    case timelinePlacementChange = "operations_dashboard.timeline.placement_change"
    case timelineQualifiedExposure = "operations_dashboard.timeline.qualified_exposure"
    case timelineRecheck = "operations_dashboard.timeline.recheck"
    case timelineReport = "operations_dashboard.timeline.report"
    case unavailableCancelled = "operations_dashboard.unavailable.cancelled"
    case unavailableData = "operations_dashboard.unavailable.data"
    case unavailableMissingCoverage = "operations_dashboard.unavailable.missing_coverage"
    case unavailableMissingQualifiedExposure = "operations_dashboard.unavailable.missing_qualified_exposure"
    case unavailableNoQualifyingFailureStart = "operations_dashboard.unavailable.no_qualifying_failure_start"
    case unavailableNoReason = "operations_dashboard.unavailable.no_reason"
    case unavailableProtectedData = "operations_dashboard.unavailable.protected_data"

    var localizationKey: LocalizationKeyV1 {
        // swiftlint:disable:next force_try
        try! LocalizationKeyV1(rawValue)
    }
}

enum C09OperationsDashboardLocalizationPolicyV1 {
    static let sourceLocale = "en"
    static let englishOnly = true
    static let displaySafeProjectionOnly = true
    static let rawInternalIdentityLocalized = false
    static let rawInternalReasonLocalized = false
    static let uptimeClaimed = false
    static let releaseToServiceClaimed = false

    static func english(_ key: C09OperationsDashboardLocalizationKeyV1) -> String {
        switch key {
        case .assetName: return "Asset name"
        case .correctExposure: return "Correct exposure and coverage"
        case .correctExposureHint: return "Records a correction through the exposure coordinator."
        case .definitionVersion: return "Definition version"
        case .exposureHeading: return "Exposure and coverage"
        case .exposureQualified: return "Recorded exposure and coverage qualify for this projection."
        case .exposureUnavailable: return "Recorded exposure and coverage do not qualify for this projection."
        case .heading: return "Operations dashboard"
        case .introduction: return "Values are shown only when their recorded exposure and source evidence qualify."
        case .metricUnavailable: return "Reliability metric unavailable"
        case .metricFullInterruptionAvailability: return "Recorded full-interruption availability"
        case .metricMTBF: return "Recorded mean time between failures"
        case .metricsHeading: return "Qualified reliability metrics"
        case .provenanceCorrected: return "Recorded correction"
        case .provenanceRecorded: return "Recorded source event"
        case .provenanceSuperseded: return "Superseded recorded event"
        case .reviewExposure: return "Review exposure and coverage"
        case .reviewExposureHint: return "Reviews recorded intervals, exclusions, and coverage without changing them."
        case .reviewMetricDetails: return "Review metric details"
        case .reviewMetricDetailsHint: return "Shows the metric definition, included evidence, and exclusions."
        case .timelineEmpty: return "No service history is available to show."
        case .timelineExplicitAssetChange: return "Asset change recorded"
        case .timelineCorrectiveWork: return "Corrective work recorded"
        case .timelineEvidenceAssociation: return "Evidence association recorded"
        case .timelineFinding: return "Finding recorded"
        case .timelineHeading: return "Asset service history"
        case .timelineImpactSegment: return "Service impact segment recorded"
        case .timelineIncident: return "Asset service incident recorded"
        case .timelineInspection: return "Inspection recorded"
        case .timelinePlacementChange: return "Placement change recorded"
        case .timelineQualifiedExposure: return "Qualified service exposure recorded"
        case .timelineRecheck: return "Recheck recorded"
        case .timelineReport: return "Report recorded"
        case .unavailableCancelled: return "The projection was cancelled before a qualified value was available."
        case .unavailableData: return "Recorded data is unavailable for this projection."
        case .unavailableMissingCoverage: return "Recorded coverage does not qualify for this metric."
        case .unavailableMissingQualifiedExposure: return "No qualifying recorded service exposure is available."
        case .unavailableNoQualifyingFailureStart: return "No qualifying recorded failure start is available."
        case .unavailableNoReason: return "A qualifying reason is not available. Review exposure and coverage."
        case .unavailableProtectedData: return "Unlock this device to review the recorded data."
        }
    }

    static func validate() throws {
        let keys = C09OperationsDashboardLocalizationKeyV1.allCases
        let rawValues = keys.map(\.rawValue)
        guard sourceLocale == "en", englishOnly, displaySafeProjectionOnly,
              !rawInternalIdentityLocalized, !rawInternalReasonLocalized,
              !uptimeClaimed, !releaseToServiceClaimed,
              rawValues == rawValues.sorted(), Set(rawValues).count == rawValues.count,
              keys.allSatisfy({ !$0.localizationKey.rawValue.isEmpty && !english($0).isEmpty }) else {
            throw LocalizationContractFailureV1.invalidValue
        }
    }
}

/// Shared C53 boundary constants let inherited surfaces enroll the four
/// contract refs without introducing a second writer, store, or claim.
enum C53SharedServiceReliabilitySemanticBoundaryV1 {
    static let cardID = "V23-P03-C53"
    static let schema = "V23P03C53AssetServiceReliabilityContractV1"
    static let incidentType: AssetServiceIncidentV1.Type = AssetServiceIncidentV1.self
    static let impactSegmentType: ServiceImpactSegmentV1.Type = ServiceImpactSegmentV1.self
    static let qualifiedExposureType: QualifiedServiceExposureV1.Type = QualifiedServiceExposureV1.self
    static let metricInputProjectionType: ReliabilityMetricInputProjectionV1.Type = ReliabilityMetricInputProjectionV1.self
    static let claimBoundaryType: ServiceReliabilityClaimBoundaryV1.Type = ServiceReliabilityClaimBoundaryV1.self
    static let journeyContractType: ServiceReliabilityFJ09ContractV1.Type = ServiceReliabilityFJ09ContractV1.self
    static let contractNames = [
        "AssetServiceIncidentV1",
        "ServiceImpactSegmentV1",
        "QualifiedServiceExposureV1",
        "ReliabilityMetricInputProjectionV1"
    ]
    static let impactKinds = ["FULL_INTERRUPTION", "DEGRADED", "INTERMITTENT", "UNKNOWN"]
    static let originKinds = ["PLANNED", "UNPLANNED", "UNKNOWN"]
    static let appendOnlyIncidentAndCorrectionHistory = true
    static let metricRequiresQualifiedPositiveExposure = true
    static let unknownIntervalsExcludedFromExactMetrics = true
    static let noVerifiedIdentityOrReleaseToServiceClaim = true
    static let noAutomaticWorkOrDuplicateAction = true
    static let rawCapabilitiesAndDiagnosticProjectionsExcluded = true
    static let zeroExposureDisposition = "UNAVAILABLE_ZERO_QUALIFIED_EXPOSURE"
}

// MARK: - C01 Support & Recovery Center localization

/// C01's display vocabulary is a closed, English-source projection of typed
/// local facts.  It contains no customer/work content, identifiers, paths,
/// secrets, legal copy, delivery claim, or capability bytes.
enum RecoveryCenterLocalizationKeyV1: String, CaseIterable, Codable, Hashable, Sendable {
    case actionCancel = "recovery.center.action.cancel"
    case actionChooseFile = "recovery.center.action.choose_file"
    case actionCloseOtherOperation = "recovery.center.action.close_other_operation"
    case actionContactSupport = "recovery.center.action.contact_support"
    case actionFreeStorage = "recovery.center.action.free_storage"
    case actionOpenSettings = "recovery.center.action.open_settings"
    case actionRestart = "recovery.center.action.restart"
    case actionResume = "recovery.center.action.resume"
    case actionRetry = "recovery.center.action.retry"
    case actionUnlockDevice = "recovery.center.action.unlock_device"
    case backupStandardAction = "recovery.center.backup.standard.action"
    case backupStandardDescription = "recovery.center.backup.standard.description"
    case backupStandardHeading = "recovery.center.backup.standard.heading"
    case backupStandardUnavailable = "recovery.center.backup.standard.unavailable"
    case encryptedBackupAction = "recovery.center.backup.encrypted.action"
    case encryptedBackupAvailable = "recovery.center.backup.encrypted.available"
    case encryptedBackupHeading = "recovery.center.backup.encrypted.heading"
    case encryptedBackupUnavailable = "recovery.center.backup.encrypted.unavailable"
    case failureFallback = "recovery.center.failure.fallback"
    case failureHeading = "recovery.center.failure.heading"
    case failureHelp = "recovery.center.failure.help"
    case failurePrimary = "recovery.center.failure.primary"
    case feedbackDraftAvailable = "recovery.center.feedback.draft_available"
    case feedbackExternalEffect = "recovery.center.feedback.external_effect"
    case feedbackHandoffAction = "recovery.center.feedback.handoff_action"
    case feedbackHandoffReady = "recovery.center.feedback.handoff_ready"
    case feedbackHandoffUnavailable = "recovery.center.feedback.handoff_unavailable"
    case feedbackHeading = "recovery.center.feedback.heading"
    case feedbackInvalid = "recovery.center.feedback.invalid"
    case freshnessCurrent = "recovery.center.freshness.current"
    case freshnessHeading = "recovery.center.freshness.heading"
    case freshnessHistoric = "recovery.center.freshness.historic"
    case freshnessUnavailable = "recovery.center.freshness.unavailable"
    case heading = "recovery.center.heading"
    case helpBackup = "recovery.center.help.backup"
    case helpCommerce = "recovery.center.help.commerce"
    case helpDiagnosticsReset = "recovery.center.help.diagnostics_reset"
    case helpPermissions = "recovery.center.help.permissions"
    case helpReports = "recovery.center.help.reports"
    case helpStorage = "recovery.center.help.storage"
    case helpSupportExport = "recovery.center.help.support_export"
    case intro = "recovery.center.intro"
    case privacyAction = "recovery.center.privacy.action"
    case privacyBlocked = "recovery.center.privacy.blocked"
    case privacyDraftLocal = "recovery.center.privacy.draft_local"
    case privacyHeading = "recovery.center.privacy.heading"
    case privacyLiveAvailable = "recovery.center.privacy.live_available"
    case refreshAction = "recovery.center.action.refresh"
    case reliabilityHeading = "recovery.center.reliability.heading"
    case sourceBackup = "recovery.center.source.backup"
    case sourceCommerce = "recovery.center.source.commerce"
    case sourceDiagnostics = "recovery.center.source.diagnostics"
    case sourceFinalization = "recovery.center.source.finalization"
    case sourceGeneration = "recovery.center.source.generation"
    case sourceJobs = "recovery.center.source.jobs"
    case sourcePackageReadiness = "recovery.center.source.package_readiness"
    case sourceProtectedData = "recovery.center.source.protected_data"
    case sourceReporting = "recovery.center.source.reporting"
    case sourceRestore = "recovery.center.source.restore"
    case sourceStorage = "recovery.center.source.storage"
    case stateActionable = "recovery.center.state.actionable"
    case stateChecking = "recovery.center.state.checking"
    case stateComplete = "recovery.center.state.complete"
    case stateExternalActionRequired = "recovery.center.state.external_action_required"
    case stateFileRequired = "recovery.center.state.file_required"
    case stateHealthy = "recovery.center.state.healthy"
    case stateInProgress = "recovery.center.state.in_progress"
    case stateInterrupted = "recovery.center.state.interrupted"
    case statePartialSafe = "recovery.center.state.partial_safe"
    case stateRestartRequired = "recovery.center.state.restart_required"
    case stateValidationFailed = "recovery.center.state.validation_failed"
    case statusHeading = "recovery.center.status.heading"
    case supportExportAction = "recovery.center.support.export_action"
    case supportExternalEffect = "recovery.center.support.external_effect"
    case supportHeading = "recovery.center.support.heading"
    case supportPrepareAction = "recovery.center.support.prepare_action"
    case supportPreviewAction = "recovery.center.support.preview_action"
    case supportPreviewBytes = "recovery.center.support.preview.bytes"
    case supportPreviewEntries = "recovery.center.support.preview.entries"
    case supportPreviewPrivacy = "recovery.center.support.preview.privacy"
    case supportPreviewUnavailable = "recovery.center.support.preview.unavailable"
    case supportPreviewHeading = "recovery.center.support.preview.heading"

    var localizationKey: LocalizationKeyV1 {
        // This is a closed repository-owned vocabulary; registry construction
        // remains the throwing validation boundary.
        // swiftlint:disable:next force_try
        try! LocalizationKeyV1(rawValue)
    }
}

enum RecoveryCenterLocalizationPolicyV1 {
    static let sourceLocale = "en"
    static let shippingLocale = "en"
    static let metadataLocale = "en-US"
    static let englishOnly = true
    static let semanticNamespace = "v23.p04.c01.recovery-center"
    static let keys = RecoveryCenterLocalizationKeyV1.allCases.map(\.rawValue).sorted()
    static let excludesCustomerContent = true
    static let excludesWorkContent = true
    static let excludesIdentifiersAndPaths = true
    static let excludesSecretsAndLegalCopy = true
    static let noOptimisticCompletionOrDeliveryClaim = true
    static let externalEffectsAreExplicit = true
    static let standardRecoveryIsIndependent = true

    static func english(_ key: RecoveryCenterLocalizationKeyV1) -> String {
        switch key {
        case .actionCancel: return "Cancel"
        case .actionChooseFile: return "Choose a file"
        case .actionCloseOtherOperation: return "Close the other operation"
        case .actionContactSupport: return "Contact support"
        case .actionFreeStorage: return "Free storage"
        case .actionOpenSettings: return "Open Settings"
        case .actionRestart: return "Restart"
        case .actionResume: return "Resume"
        case .actionRetry: return "Try again"
        case .actionUnlockDevice: return "Unlock this device"
        case .backupStandardAction: return "Create a standard backup"
        case .backupStandardDescription: return "Standard backup remains available independently of the optional encrypted-backup choice."
        case .backupStandardHeading: return "Standard backup"
        case .backupStandardUnavailable: return "Standard backup status is unavailable."
        case .encryptedBackupAction: return "Use encrypted backup"
        case .encryptedBackupAvailable: return "Encrypted backup is available as an optional choice."
        case .encryptedBackupHeading: return "Encrypted backup"
        case .encryptedBackupUnavailable: return "Encrypted backup is unavailable; standard recovery is not blocked."
        case .failureFallback: return "Fallback action"
        case .failureHeading: return "Recovery action"
        case .failureHelp: return "Help topic"
        case .failurePrimary: return "Primary action"
        case .feedbackDraftAvailable: return "A feedback draft is available for review."
        case .feedbackExternalEffect: return "Choosing Mail or Share opens another app; this does not confirm sending or delivery."
        case .feedbackHandoffAction: return "Review feedback handoff"
        case .feedbackHandoffReady: return "A feedback handoff preview is ready for review."
        case .feedbackHandoffUnavailable: return "No feedback handoff preview is available."
        case .feedbackHeading: return "Feedback"
        case .feedbackInvalid: return "The feedback preview could not be matched to its draft."
        case .freshnessCurrent: return "Current"
        case .freshnessHeading: return "Freshness"
        case .freshnessHistoric: return "Historic"
        case .freshnessUnavailable: return "Unavailable"
        case .heading: return "Support & Recovery"
        case .helpBackup: return "Backup help"
        case .helpCommerce: return "Subscription help"
        case .helpDiagnosticsReset: return "Diagnostics reset help"
        case .helpPermissions: return "Permissions help"
        case .helpReports: return "Reports help"
        case .helpStorage: return "Storage help"
        case .helpSupportExport: return "Support export help"
        case .intro: return "Review local reliability and recovery choices on this iPhone."
        case .privacyAction: return "Open the live privacy policy"
        case .privacyBlocked: return "Privacy details are unavailable until the bundled policy is available."
        case .privacyDraftLocal: return "A local privacy summary is available; the live policy is not available."
        case .privacyHeading: return "Privacy & Data"
        case .privacyLiveAvailable: return "A bundled privacy summary and live policy link are available."
        case .refreshAction: return "Check again"
        case .reliabilityHeading: return "Local reliability"
        case .sourceBackup: return "Backup"
        case .sourceCommerce: return "Subscription"
        case .sourceDiagnostics: return "Diagnostics"
        case .sourceFinalization: return "Finalization"
        case .sourceGeneration: return "Generation"
        case .sourceJobs: return "Jobs"
        case .sourcePackageReadiness: return "Package readiness"
        case .sourceProtectedData: return "Protected data"
        case .sourceReporting: return "Reporting"
        case .sourceRestore: return "Restore"
        case .sourceStorage: return "Storage"
        case .stateActionable: return "Action required"
        case .stateChecking: return "Checking"
        case .stateComplete: return "Complete"
        case .stateExternalActionRequired: return "External action required"
        case .stateFileRequired: return "File required"
        case .stateHealthy: return "Healthy"
        case .stateInProgress: return "In progress"
        case .stateInterrupted: return "Interrupted"
        case .statePartialSafe: return "Partial state available"
        case .stateRestartRequired: return "Restart required"
        case .stateValidationFailed: return "Validation failed"
        case .statusHeading: return "Recovery status"
        case .supportExportAction: return "Export support bundle"
        case .supportExternalEffect: return "Export opens a system share surface. The app cannot recall a copy after you choose a destination."
        case .supportHeading: return "Support"
        case .supportPrepareAction: return "Prepare support preview"
        case .supportPreviewAction: return "Review support preview"
        case .supportPreviewBytes: return "Bytes"
        case .supportPreviewEntries: return "Entries"
        case .supportPreviewPrivacy: return "This preview excludes customer content, identifiers, and raw logs."
        case .supportPreviewUnavailable: return "Support export preview is unavailable."
        case .supportPreviewHeading: return "Support export preview"
        }
    }

    static func validate() throws {
        let values = RecoveryCenterLocalizationKeyV1.allCases
        let rawValues = values.map(\.rawValue)
        guard sourceLocale == "en",
              shippingLocale == "en",
              metadataLocale == "en-US",
              englishOnly,
              rawValues.count == Set(rawValues).count,
              Set(rawValues) == Set(keys),
              values.allSatisfy({ !$0.localizationKey.rawValue.isEmpty && !english($0).isEmpty }),
              excludesCustomerContent,
              excludesWorkContent,
              excludesIdentifiersAndPaths,
              excludesSecretsAndLegalCopy,
              noOptimisticCompletionOrDeliveryClaim,
              externalEffectsAreExplicit,
              standardRecoveryIsIndependent else {
            throw LocalizationContractFailureV1.invalidValue
        }
    }
}

// MARK: - C02 evidence curation localization

/// C02 presentation labels distinguish immutable source material from
/// reversible derivatives. They never claim cause, compliance, or a changed
/// original.
enum EvidenceCurationLocalizationKeyV1: String, CaseIterable, Codable, Hashable, Sendable {
    case heading = "evidence.curation.heading"
    case detailPreviewHeading = "evidence.curation.detail_preview.heading"
    case originalHeading = "evidence.curation.original.heading"
    case referenceHeading = "evidence.curation.reference.heading"
    case comparisonHeading = "evidence.curation.comparison.heading"
    case overlayAdvisory = "evidence.curation.overlay.advisory"
    case markupHeading = "evidence.curation.markup.heading"
    case addArrowMarkup = "evidence.curation.markup.add_arrow"
    case addCircleMarkup = "evidence.curation.markup.add_circle"
    case addTextMarkup = "evidence.curation.markup.add_text"
    case removeMarkup = "evidence.curation.markup.remove"
    case retake = "evidence.curation.item.retake"
    case retakeReviewRequired = "evidence.curation.item.retake.review_required"
    case removeFromWork = "evidence.curation.item.remove_from_work"
    case removeHistoryDisclosure = "evidence.curation.item.remove_history_disclosure"
    case moveEarlier = "evidence.curation.item.move_earlier"
    case moveLater = "evidence.curation.item.move_later"
    case sequenceHeading = "evidence.curation.sequence.heading"
    case contactSheetHeading = "evidence.curation.contact_sheet.heading"
    case reducedMotion = "evidence.curation.sequence.reduced_motion"
    case reviewOrderHeading = "evidence.curation.review_order.heading"
    case roleHeading = "evidence.curation.role.heading"
    case roleContext = "evidence.curation.role.context"
    case roleDetail = "evidence.curation.role.detail"
    case roleBefore = "evidence.curation.role.before"
    case roleAfter = "evidence.curation.role.after"
    case roleOther = "evidence.curation.role.other"
    case captionHeading = "evidence.curation.caption.heading"
    case accessibilityDescriptionHeading = "evidence.curation.accessibility_description.heading"
    case metadataUnavailable = "evidence.curation.metadata.unavailable"
    case visualDerivativeReady = "evidence.curation.derivative.visual_ready"
    case derivativeManifestReady = "evidence.curation.derivative.manifest_ready"
    case visualDerivativeUnavailable = "evidence.curation.derivative.visual_unavailable"
    case missingReference = "evidence.curation.reference.missing"
    case immutableOriginal = "evidence.curation.original.immutable"
    case noMarkup = "evidence.curation.markup.none"

    var localizationKey: LocalizationKeyV1 {
        // This closed, repository-owned vocabulary has no dynamic keys.
        // swiftlint:disable:next force_try
        try! LocalizationKeyV1(rawValue)
    }
}

enum EvidenceCurationLocalizationPolicyV1 {
    static let sourceLocale = "en"
    static let shippingLocale = "en"
    static let semanticNamespace = "v23.p04.c02.evidence-curation"
    static let keys = EvidenceCurationLocalizationKeyV1.allCases.map(\.rawValue).sorted()
    static let immutableOriginalIsExplicit = true
    static let comparisonIsNotCausalProof = true
    static let markupIsReversible = true
    static let noLegalOrPrivacyClaim = true

    static func english(_ key: EvidenceCurationLocalizationKeyV1) -> String {
        switch key {
        case .heading: return "Evidence curation"
        case .detailPreviewHeading: return "Evidence detail preview"
        case .originalHeading: return "Original evidence"
        case .referenceHeading: return "Reference evidence"
        case .comparisonHeading: return "Side-by-side comparison"
        case .overlayAdvisory: return "Overlay is an advisory viewing aid; it does not establish cause or compliance."
        case .markupHeading: return "Reviewed markup"
        case .addArrowMarkup: return "Add arrow"
        case .addCircleMarkup: return "Add circle"
        case .addTextMarkup: return "Add text note"
        case .removeMarkup: return "Remove markup"
        case .retake: return "Retake evidence"
        case .retakeReviewRequired: return "Retake stages a new original and requires review of the caption and accessibility description for the new pixels."
        case .removeFromWork: return "Remove from this work/report"
        case .removeHistoryDisclosure: return "Immutable evidence history remains. If this evidence is required, completion returns to incomplete."
        case .moveEarlier: return "Move earlier"
        case .moveLater: return "Move later"
        case .sequenceHeading: return "Evidence sequence"
        case .contactSheetHeading: return "Contact sheet"
        case .reducedMotion: return "Motion is reduced; sequence frames are shown as still images."
        case .reviewOrderHeading: return "Review order"
        case .roleHeading: return "Role"
        case .roleContext: return "Context"
        case .roleDetail: return "Detail"
        case .roleBefore: return "Before"
        case .roleAfter: return "After"
        case .roleOther: return "Other"
        case .captionHeading: return "Caption"
        case .accessibilityDescriptionHeading: return "Accessibility description"
        case .metadataUnavailable: return "Reviewed evidence metadata is unavailable."
        case .visualDerivativeReady: return "Reviewed visual derivative is ready."
        case .derivativeManifestReady: return "Reviewed derivative manifest is ready; visual output is not available in this surface."
        case .visualDerivativeUnavailable: return "No completed visual derivative is available."
        case .missingReference: return "Reference content is unavailable."
        case .immutableOriginal: return "Original evidence is unchanged."
        case .noMarkup: return "No reviewed markup is shown."
        }
    }

    static func validate() throws {
        let values = EvidenceCurationLocalizationKeyV1.allCases
        let rawValues = values.map(\.rawValue)
        guard sourceLocale == "en",
              shippingLocale == "en",
              rawValues.count == Set(rawValues).count,
              Set(rawValues) == Set(keys),
              values.allSatisfy({ !$0.localizationKey.rawValue.isEmpty && !english($0).isEmpty }),
              immutableOriginalIsExplicit,
              comparisonIsNotCausalProof,
              markupIsReversible,
              noLegalOrPrivacyClaim else {
            throw LocalizationContractFailureV1.invalidValue
        }
    }
}

// MARK: - C10 evidence quality coach presentation

/// Closed system-copy vocabulary for the contained C10 coach. User-authored
/// content is supplied separately by the view state and is never made into a
/// localization key.
enum EvidenceQualityCoachLocalizationKeyV1: String, CaseIterable, Codable, Hashable, Sendable {
    case heading = "evidence.quality.coach.heading"
    case introduction = "evidence.quality.coach.introduction"
    case warning = "evidence.quality.coach.warning"
    case input = "evidence.quality.coach.input"
    case threshold = "evidence.quality.coach.threshold"
    case remedy = "evidence.quality.coach.remedy"
    case ruleVersion = "evidence.quality.coach.rule_version"
    case retake = "evidence.quality.coach.retake"
    case retakeHint = "evidence.quality.coach.retake.hint"
    case acceptWithReason = "evidence.quality.coach.accept_with_reason"
    case acceptWithReasonHint = "evidence.quality.coach.accept_with_reason.hint"
    case reasonHeading = "evidence.quality.coach.reason.heading"
    case reasonEvidenceUnavailable = "evidence.quality.coach.reason.evidence_unavailable"
    case reasonConditionsChanged = "evidence.quality.coach.reason.conditions_changed"
    case reasonRetakeNotPossible = "evidence.quality.coach.reason.retake_not_possible"
    case limitationHeading = "evidence.quality.coach.limitation.heading"
    case limitationRequired = "evidence.quality.coach.limitation.required"
    case cancel = "evidence.quality.coach.cancel"
    case cancelHint = "evidence.quality.coach.cancel.hint"
    case reasonRequired = "evidence.quality.coach.reason.required"
    case unavailableHeading = "evidence.quality.coach.unavailable.heading"
    case unavailable = "evidence.quality.coach.unavailable"
    case unavailableCorrupt = "evidence.quality.coach.unavailable.corrupt"
    case unavailableStale = "evidence.quality.coach.unavailable.stale"
    case unavailableCancelled = "evidence.quality.coach.unavailable.cancelled"
    case unavailableProtected = "evidence.quality.coach.unavailable.protected"
    case unavailableOffline = "evidence.quality.coach.unavailable.offline"
    case unavailableStorage = "evidence.quality.coach.unavailable.storage"
    case reducedMotion = "evidence.quality.coach.reduced_motion"
    case originalPreserved = "evidence.quality.coach.original_preserved"

    var localizationKey: LocalizationKeyV1 { try! LocalizationKeyV1(rawValue) }
}

enum EvidenceQualityCoachLocalizationPolicyV1 {
    static let sourceLocale = "en"
    static let shippingLocale = "en"
    static let semanticNamespace = "v23.p04.c10.evidence-quality-coach"
    static let keys = EvidenceQualityCoachLocalizationKeyV1.allCases.map(\.rawValue).sorted()
    static let closedReasonsOnly = true
    static let noAutomaticRequirementJudgment = true
    static let opaqueConfidenceProhibited = true
    static let uiAdoptionClaimed = false

    static func english(_ key: EvidenceQualityCoachLocalizationKeyV1) -> String {
        switch key {
        case .heading: return "Evidence quality review"
        case .introduction: return "Review each recorded warning and choose a next step. This review does not change any requirement outcome."
        case .warning: return "Warning"
        case .input: return "Recorded input"
        case .threshold: return "Rule threshold"
        case .remedy: return "Suggested retake"
        case .ruleVersion: return "Rule version"
        case .retake: return "Retake evidence"
        case .retakeHint: return "Starts a new capture attempt; the original evidence remains unchanged."
        case .acceptWithReason: return "Accept with reason"
        case .acceptWithReasonHint: return "Records the selected closed reason through the supplied coordinator action."
        case .reasonHeading: return "Reason"
        case .reasonEvidenceUnavailable: return "Required evidence is unavailable"
        case .reasonConditionsChanged: return "Capture conditions have changed"
        case .reasonRetakeNotPossible: return "A retake cannot be completed now"
        case .limitationHeading: return "Recorded limitation"
        case .limitationRequired: return "This reason requires the stated limitation to be included."
        case .cancel: return "Cancel"
        case .cancelHint: return "Closes this review and preserves the original evidence."
        case .reasonRequired: return "Choose a reason before continuing."
        case .unavailableHeading: return "Quality review unavailable"
        case .unavailable: return "The quality review is unavailable."
        case .unavailableCorrupt: return "The recorded quality data cannot be read."
        case .unavailableStale: return "The recorded quality data is stale and needs a new review."
        case .unavailableCancelled: return "The quality review was cancelled before it produced a reviewable result."
        case .unavailableProtected: return "Unlock this device to review protected recorded data."
        case .unavailableOffline: return "A local review is unavailable while this device is offline."
        case .unavailableStorage: return "There is not enough local storage to prepare this review."
        case .reducedMotion: return "Motion is reduced."
        case .originalPreserved: return "Cancelling keeps the original evidence unchanged."
        }
    }

    static func validate() throws {
        let values = EvidenceQualityCoachLocalizationKeyV1.allCases
        let rawValues = values.map(\.rawValue)
        guard sourceLocale == "en", shippingLocale == "en",
              rawValues.count == Set(rawValues).count,
              Set(rawValues) == Set(keys),
              values.allSatisfy({ !$0.localizationKey.rawValue.isEmpty && !english($0).isEmpty }),
              closedReasonsOnly,
              noAutomaticRequirementJudgment,
              opaqueConfidenceProhibited,
              !uiAdoptionClaimed else {
            throw LocalizationContractFailureV1.invalidValue
        }
    }
}

// MARK: - C03 illuminated-sign playbook presentation

enum IlluminatedSignPlaybookLocalizationKeyV1: String, CaseIterable, Codable, Hashable, Sendable {
    case heading = "illuminated.playbook.heading"
    case playbooksHeading = "illuminated.playbook.list.heading"
    case selectedPlaybook = "illuminated.playbook.list.selected"
    case generalVisibleCondition = "illuminated.playbook.general_visible_condition"
    case darkSection = "illuminated.playbook.dark_section"
    case dimOrUneven = "illuminated.playbook.dim_or_uneven"
    case flickerOrIntermittent = "illuminated.playbook.flicker_or_intermittent"
    case colorMismatch = "illuminated.playbook.color_mismatch"
    case physicalDamage = "illuminated.playbook.physical_damage"
    case otherVisibleCondition = "illuminated.playbook.other_visible_condition"
    case preflightHeading = "illuminated.playbook.preflight.heading"
    case afterDark = "illuminated.playbook.preflight.after_dark"
    case safeAuthorizedPosition = "illuminated.playbook.preflight.safe_authorized_position"
    case captureHeading = "illuminated.playbook.capture.heading"
    case wideCapture = "illuminated.playbook.capture.wide_context"
    case closeCapture = "illuminated.playbook.capture.close_detail"
    case workCapture = "illuminated.playbook.capture.work_context"
    case captureRequired = "illuminated.playbook.capture.required"
    case captureComplete = "illuminated.playbook.capture.complete"
    case captureMissing = "illuminated.playbook.capture.missing"
    case factsHeading = "illuminated.playbook.facts.heading"
    case checkedTime = "illuminated.playbook.facts.checked_time"
    case stageLabel = "illuminated.playbook.facts.stage"
    case stageCheck = "illuminated.playbook.facts.stage.check"
    case stageRecheck = "illuminated.playbook.facts.stage.recheck"
    case outcomeLabel = "illuminated.playbook.facts.outcome"
    case outcomeNoVisibleIssue = "illuminated.playbook.facts.outcome.no_visible_issue"
    case outcomeVisibleIssue = "illuminated.playbook.facts.outcome.visible_issue"
    case outcomeCouldNotVerify = "illuminated.playbook.facts.outcome.could_not_verify"
    case selectedCondition = "illuminated.playbook.facts.selected_condition"
    case couldNotVerifyReason = "illuminated.playbook.facts.could_not_verify_reason"
    case visibleConditionsOnly = "illuminated.playbook.facts.visible_conditions_only"
    case reportTrace = "illuminated.playbook.facts.report_trace"
    case poseHeading = "illuminated.playbook.pose.heading"
    case poseUnavailable = "illuminated.playbook.pose.unavailable"
    case poseReviewed = "illuminated.playbook.pose.reviewed"
    case poseReviewRequired = "illuminated.playbook.pose.review_required"
    case retakeDisclosure = "illuminated.playbook.retake.disclosure"
    case disclaimer = "illuminated.playbook.disclaimer"
    case offlineReady = "illuminated.playbook.state.offline_ready"
    case blocked = "illuminated.playbook.state.blocked"
    case permissionDenied = "illuminated.playbook.state.permission_denied"
    case protectedDataUnavailable = "illuminated.playbook.state.protected_data_unavailable"
    case lowStorage = "illuminated.playbook.state.low_storage"
    case cancelled = "illuminated.playbook.state.cancelled"
    case recoveryRequired = "illuminated.playbook.state.recovery_required"
    case recovered = "illuminated.playbook.state.recovered"

    var localizationKey: LocalizationKeyV1 {
        // This closed, repository-owned vocabulary has no dynamic keys.
        // swiftlint:disable:next force_try
        try! LocalizationKeyV1(rawValue)
    }
}

enum IlluminatedSignPlaybookLocalizationPolicyV1 {
    static let sourceLocale = "en"
    static let shippingLocale = "en"
    static let keys = IlluminatedSignPlaybookLocalizationKeyV1.allCases.map(\.rawValue).sorted()
    static let claimsAreVisibleConditionOnly = true
    static let nonCertificationDisclaimerIsExplicit = true
    static let preflightIsExplicit = true

    static func english(_ key: IlluminatedSignPlaybookLocalizationKeyV1) -> String {
        switch key {
        case .heading: return "Illuminated sign playbook"
        case .playbooksHeading: return "Visible-condition playbooks"
        case .selectedPlaybook: return "Selected playbook"
        case .generalVisibleCondition: return "General visible condition"
        case .darkSection: return "Dark section"
        case .dimOrUneven: return "Dim or uneven illumination"
        case .flickerOrIntermittent: return "Flicker or intermittent light"
        case .colorMismatch: return "Visible color mismatch"
        case .physicalDamage: return "Visible physical damage"
        case .otherVisibleCondition: return "Other visible condition"
        case .preflightHeading: return "Before capture"
        case .afterDark: return "Before capture, confirm conditions are dark enough to observe the sign's visible illumination."
        case .safeAuthorizedPosition: return "Capture only from a position you have determined is safe and authorized."
        case .captureHeading: return "Required capture"
        case .wideCapture: return "Wide view"
        case .closeCapture: return "Close view"
        case .workCapture: return "Optional work photo"
        case .captureRequired: return "Required"
        case .captureComplete: return "Captured"
        case .captureMissing: return "Missing"
        case .factsHeading: return "Structured report facts"
        case .checkedTime: return "Checked time"
        case .stageLabel: return "Stage"
        case .stageCheck: return "Check"
        case .stageRecheck: return "Recheck"
        case .outcomeLabel: return "Outcome"
        case .outcomeNoVisibleIssue: return "No visible issue"
        case .outcomeVisibleIssue: return "Visible issue"
        case .outcomeCouldNotVerify: return "Could not verify"
        case .selectedCondition: return "Selected visible condition"
        case .couldNotVerifyReason: return "Could-not-verify reason"
        case .visibleConditionsOnly: return "Record only conditions visible in the evidence."
        case .reportTrace: return "Facts retain their capture and playbook trace."
        case .poseHeading: return "Sign face or forward axis"
        case .poseUnavailable: return "Pose review is unavailable; no direction is recorded."
        case .poseReviewed: return "Reviewed pose is recorded through the typed pose authority."
        case .poseReviewRequired: return "A reviewed pose is required before this visible-condition report can complete."
        case .retakeDisclosure: return "A retake creates a new original. Prior evidence and finalized reports remain unchanged."
        case .disclaimer: return "This report records visible conditions from the listed photos and time. It is not an electrical, code, safety, or professional certification."
        case .offlineReady: return "Ready for offline review"
        case .blocked: return "Playbook is blocked"
        case .permissionDenied: return "Camera or photo access is unavailable."
        case .protectedDataUnavailable: return "Protected data is unavailable while the device is locked."
        case .lowStorage: return "Storage is too low to safely continue."
        case .cancelled: return "The operation was cancelled. No completed result is claimed."
        case .recoveryRequired: return "Recovery is required before this playbook can continue."
        case .recovered: return "A recovered playbook checkpoint is being shown for review."
        }
    }

    static func validate() throws {
        let values = IlluminatedSignPlaybookLocalizationKeyV1.allCases
        let rawValues = values.map(\.rawValue)
        guard sourceLocale == "en", shippingLocale == "en",
              rawValues.count == Set(rawValues).count,
              Set(rawValues) == Set(keys),
              values.allSatisfy({ !$0.localizationKey.rawValue.isEmpty && !english($0).isEmpty }),
              claimsAreVisibleConditionOnly,
              nonCertificationDisclaimerIsExplicit,
              preflightIsExplicit else {
            throw LocalizationContractFailureV1.invalidValue
        }
    }
}

// MARK: - C04 shop-profile open-evidence handoff presentation

enum ShopReportProfileLocalizationKeyV1: String, CaseIterable, Codable, Hashable, Sendable {
    case heading = "shop.profile.heading"
    case profileHeading = "shop.profile.profile.heading"
    case defaultOff = "shop.profile.default_off"
    case presetHeading = "shop.profile.preset.heading"
    case audienceHeading = "shop.profile.audience.heading"
    case activationHeading = "shop.profile.activation.heading"
    case activationOn = "shop.profile.activation.on"
    case activationOff = "shop.profile.activation.off"
    case packagingHeading = "shop.profile.packaging.heading"
    case combinedPackage = "shop.profile.packaging.combined"
    case separatePackage = "shop.profile.packaging.separate"
    case previewHeading = "shop.profile.preview.heading"
    case exactBytes = "shop.profile.preview.exact_bytes"
    case digest = "shop.profile.preview.digest"
    case detectorHeading = "shop.profile.detector.heading"
    case detectorPass = "shop.profile.detector.pass"
    case detectorBlocked = "shop.profile.detector.blocked"
    case semanticTextHeading = "shop.profile.semantic_text.heading"
    case confirmationHeading = "shop.profile.confirmation.heading"
    case confirmationRequired = "shop.profile.confirmation.required"
    case confirmationRecorded = "shop.profile.confirmation.recorded"
    case handoffHeading = "shop.profile.handoff.heading"
    case handoffAvailable = "shop.profile.handoff.available"
    case noDeliveryClaim = "shop.profile.no_delivery_claim"
    case statusUnavailable = "shop.profile.status.unavailable"
    case statusStale = "shop.profile.status.stale"
    case statusCancelled = "shop.profile.status.cancelled"
    case statusLowStorage = "shop.profile.status.low_storage"
    case statusProtectedData = "shop.profile.status.protected_data"
    case recoveryRequired = "shop.profile.recovery.required"
    case retry = "shop.profile.retry"
    case limitations = "shop.profile.limitations"

    var localizationKey: LocalizationKeyV1 {
        // Closed, repository-owned C04 vocabulary only.
        // swiftlint:disable:next force_try
        try! LocalizationKeyV1(rawValue)
    }
}

enum ShopReportProfileLocalizationPolicyV1 {
    static let sourceLocale = "en"
    static let shippingLocale = "en"
    static let keys = ShopReportProfileLocalizationKeyV1.allCases.map(\.rawValue).sorted()
    static let remoteDeliveryClaimed = false
    static let certificationClaimed = false

    static func english(_ key: ShopReportProfileLocalizationKeyV1) -> String {
        switch key {
        case .heading: return "Shop profile and open evidence"
        case .profileHeading: return "Shop profile"
        case .defaultOff: return "Evidence details are off until a profile is selected and recorded."
        case .presetHeading: return "Preset"
        case .audienceHeading: return "Audience"
        case .activationHeading: return "Evidence details"
        case .activationOn: return "On"
        case .activationOff: return "Off"
        case .packagingHeading: return "Package arrangement"
        case .combinedPackage: return "Combined archive"
        case .separatePackage: return "Separate files"
        case .previewHeading: return "Exact-byte preview"
        case .exactBytes: return "Composed bytes"
        case .digest: return "SHA-256 digest"
        case .detectorHeading: return "Audience privacy check"
        case .detectorPass: return "No prohibited audience facts were detected in this preview."
        case .detectorBlocked: return "This preview is blocked by the audience privacy check."
        case .semanticTextHeading: return "Semantic text alternative"
        case .confirmationHeading: return "Final privacy confirmation"
        case .confirmationRequired: return "Confirmation is available only after the privacy check passes for these exact composed bytes."
        case .confirmationRecorded: return "Exact-byte confirmation is present for this preview."
        case .handoffHeading: return "Open evidence handoff"
        case .handoffAvailable: return "The typed handoff receipt is available for review."
        case .noDeliveryClaim: return "This view does not claim that files were opened, shared, delivered, or received."
        case .statusUnavailable: return "Preview is unavailable. No partial handoff is shown."
        case .statusStale: return "Preview is stale. Refresh before reviewing or confirming."
        case .statusCancelled: return "Preview preparation was cancelled. No partial handoff is shown."
        case .statusLowStorage: return "Storage is too low to prepare this preview. No partial handoff is shown."
        case .statusProtectedData: return "Protected data is unavailable while the device is locked. No partial handoff is shown."
        case .recoveryRequired: return "Recovery is required before a preview can continue."
        case .retry: return "Retry preview"
        case .limitations: return "This material records reviewed evidence details. It is not a certification and does not verify capture time, location, or person."
        }
    }

    static func validate() throws {
        let values = ShopReportProfileLocalizationKeyV1.allCases
        let rawValues = values.map(\.rawValue)
        guard sourceLocale == "en", shippingLocale == "en",
              rawValues.count == Set(rawValues).count,
              Set(rawValues) == Set(keys),
              values.allSatisfy({ !$0.localizationKey.rawValue.isEmpty && !english($0).isEmpty }),
              !remoteDeliveryClaimed,
              !certificationClaimed else {
            throw LocalizationContractFailureV1.invalidValue
        }
    }
}

// MARK: - C06 round offline-readiness preflight presentation

enum OfflineReadinessPreflightLocalizationKeyV1: String, CaseIterable, Codable, Hashable, Sendable {
    case heading = "round.offline_readiness.heading"
    case loading = "round.offline_readiness.loading"
    case unavailable = "round.offline_readiness.unavailable"
    case ready = "round.offline_readiness.state.ready"
    case blocked = "round.offline_readiness.state.blocked"
    case warning = "round.offline_readiness.state.warning"
    case stale = "round.offline_readiness.state.stale"
    case safeToStart = "round.offline_readiness.safe_to_start"
    case safeToClose = "round.offline_readiness.safe_to_close"
    case notSafeToStartOrClose = "round.offline_readiness.not_safe_to_start_or_close"
    case requirementsHeading = "round.offline_readiness.requirements.heading"
    case reasonsHeading = "round.offline_readiness.reasons.heading"
    case required = "round.offline_readiness.required"
    case optional = "round.offline_readiness.optional"
    case remediation = "round.offline_readiness.remediation"
    case manualFallback = "round.offline_readiness.manual_fallback"
    case rebuild = "round.offline_readiness.rebuild"
    case cancel = "round.offline_readiness.cancel"
    case rebuildUnavailable = "round.offline_readiness.rebuild_unavailable"
    case localOnlyDisclosure = "round.offline_readiness.local_only_disclosure"
    case reasonPackageMismatch = "round.offline_readiness.reason.package_mismatch"
    case reasonSelectedAssetMismatch = "round.offline_readiness.reason.selected_asset_mismatch"
    case reasonGuidanceReferenceMismatch = "round.offline_readiness.reason.guidance_reference_mismatch"
    case reasonFieldReferenceUnavailable = "round.offline_readiness.reason.field_reference_unavailable"
    case reasonMissingMandatoryContent = "round.offline_readiness.reason.missing_mandatory_content"
    case reasonMissingOptionalContent = "round.offline_readiness.reason.missing_optional_content"
    case reasonCorruptMandatoryContent = "round.offline_readiness.reason.corrupt_mandatory_content"
    case reasonCorruptOptionalContent = "round.offline_readiness.reason.corrupt_optional_content"
    case reasonPartialMandatoryContent = "round.offline_readiness.reason.partial_mandatory_content"
    case reasonPartialOptionalContent = "round.offline_readiness.reason.partial_optional_content"
    case reasonWrongWorkspaceContent = "round.offline_readiness.reason.wrong_workspace_content"
    case reasonProtectedDataUnavailable = "round.offline_readiness.reason.protected_data_unavailable"
    case reasonStorageUncheckable = "round.offline_readiness.reason.storage_uncheckable"
    case reasonInsufficientStorage = "round.offline_readiness.reason.insufficient_storage"
    case reasonStorageArithmeticOverflow = "round.offline_readiness.reason.storage_arithmetic_overflow"
    case reasonClockUncheckable = "round.offline_readiness.reason.clock_uncheckable"
    case reasonClockOrTimeZoneChanged = "round.offline_readiness.reason.clock_or_time_zone_changed"
    case reasonSourceBindingDrift = "round.offline_readiness.reason.source_binding_drift"
    case remediationRebuild = "round.offline_readiness.remediation.rebuild"
    case remediationRestorePackage = "round.offline_readiness.remediation.restore_package"
    case remediationReselectAssets = "round.offline_readiness.remediation.reselect_assets"
    case remediationRestoreGuidance = "round.offline_readiness.remediation.restore_guidance"
    case remediationRestoreFieldReference = "round.offline_readiness.remediation.restore_field_reference"
    case remediationRestoreContent = "round.offline_readiness.remediation.restore_content"
    case remediationUnlock = "round.offline_readiness.remediation.unlock"
    case remediationFreeStorage = "round.offline_readiness.remediation.free_storage"
    case remediationCheckStorage = "round.offline_readiness.remediation.check_storage"
    case remediationCheckClock = "round.offline_readiness.remediation.check_clock"
    case fallbackDoNotStart = "round.offline_readiness.fallback.do_not_start"
    case fallbackDeferFieldWork = "round.offline_readiness.fallback.defer_field_work"
    case fallbackApprovedManualProcedure = "round.offline_readiness.fallback.approved_manual_procedure"
    case fallbackContactSupervisor = "round.offline_readiness.fallback.contact_supervisor"

    var localizationKey: LocalizationKeyV1 {
        // Closed C06 vocabulary; manifest facts are never used as localization keys.
        // swiftlint:disable:next force_try
        try! LocalizationKeyV1(rawValue)
    }
}

enum OfflineReadinessPreflightLocalizationPolicyV1 {
    static let sourceLocale = "en"
    static let shippingLocale = "en"
    static let keys = OfflineReadinessPreflightLocalizationKeyV1.allCases.map(\.rawValue).sorted()
    static let remoteSyncClaimed = false
    static let unknownIsSafe = false

    static func english(_ key: OfflineReadinessPreflightLocalizationKeyV1) -> String {
        switch key {
        case .heading: return "Offline readiness"
        case .loading: return "Checking local readiness…"
        case .unavailable: return "Local readiness is unavailable. No safe start or close status is shown."
        case .ready: return "Ready for local field work"
        case .blocked: return "Local readiness is blocked"
        case .warning: return "Local readiness needs attention"
        case .stale: return "Local readiness is out of date"
        case .safeToStart: return "Safe to start locally"
        case .safeToClose: return "Safe to close locally"
        case .notSafeToStartOrClose: return "Do not start or close until readiness is rebuilt."
        case .requirementsHeading: return "Readiness requirements"
        case .reasonsHeading: return "What needs attention"
        case .required: return "Required"
        case .optional: return "Optional"
        case .remediation: return "What to do"
        case .manualFallback: return "Manual fallback"
        case .rebuild: return "Rebuild local readiness"
        case .cancel: return "Cancel"
        case .rebuildUnavailable: return "Local readiness cannot be rebuilt from this screen."
        case .localOnlyDisclosure: return "This screen shows local readiness only. It does not report sync, upload, online, or account status."
        case .reasonPackageMismatch: return "The selected package does not match this round."
        case .reasonSelectedAssetMismatch: return "A selected asset no longer matches this round."
        case .reasonGuidanceReferenceMismatch: return "A required guidance reference does not match this round."
        case .reasonFieldReferenceUnavailable: return "A required local field reference is unavailable."
        case .reasonMissingMandatoryContent: return "Required local content is missing."
        case .reasonMissingOptionalContent: return "Optional local content is missing."
        case .reasonCorruptMandatoryContent: return "Required local content could not be verified."
        case .reasonCorruptOptionalContent: return "Optional local content could not be verified."
        case .reasonPartialMandatoryContent: return "Required local content is incomplete."
        case .reasonPartialOptionalContent: return "Optional local content is incomplete."
        case .reasonWrongWorkspaceContent: return "Local content belongs to a different workspace."
        case .reasonProtectedDataUnavailable: return "Protected local data is unavailable while the device is locked."
        case .reasonStorageUncheckable: return "Available local storage could not be checked."
        case .reasonInsufficientStorage: return "Available local storage is too low to continue safely."
        case .reasonStorageArithmeticOverflow: return "The local storage check could not be completed safely."
        case .reasonClockUncheckable: return "The device clock or time zone could not be checked."
        case .reasonClockOrTimeZoneChanged: return "The device clock or time zone changed after readiness was checked."
        case .reasonSourceBindingDrift: return "This readiness result no longer matches the current round."
        case .remediationRebuild: return "Rebuild local readiness."
        case .remediationRestorePackage: return "Restore the exact package selected for this round."
        case .remediationReselectAssets: return "Review the selected local assets for this round."
        case .remediationRestoreGuidance: return "Restore the required local guidance reference."
        case .remediationRestoreFieldReference: return "Restore the required local field reference."
        case .remediationRestoreContent: return "Restore the exact local content required for this round."
        case .remediationUnlock: return "Unlock the device, then rebuild local readiness."
        case .remediationFreeStorage: return "Free local storage, then rebuild local readiness."
        case .remediationCheckStorage: return "Check local storage again, then rebuild local readiness."
        case .remediationCheckClock: return "Check the device clock and time zone, then rebuild local readiness."
        case .fallbackDoNotStart: return "Do not start or close this round from this readiness result."
        case .fallbackDeferFieldWork: return "Defer field work until local readiness can be rebuilt."
        case .fallbackApprovedManualProcedure: return "Use the approved manual procedure if one applies."
        case .fallbackContactSupervisor: return "Contact your supervisor for the approved next step."
        }
    }

    static func validate() throws {
        let values = OfflineReadinessPreflightLocalizationKeyV1.allCases
        guard sourceLocale == "en", shippingLocale == "en",
              Set(values.map(\.rawValue)) == Set(keys),
              values.allSatisfy({ !$0.localizationKey.rawValue.isEmpty && !english($0).isEmpty }),
              !remoteSyncClaimed, !unknownIsSafe else {
            throw LocalizationContractFailureV1.invalidValue
        }
    }
}

enum RoundSessionLocalizationKeyV1: String, CaseIterable, Sendable {
    case heading = "round.session.heading", manualPathDisclosure = "round.session.manual_path", progressHeading = "round.session.progress"
    case completedCount = "round.session.completed_count", incompleteCount = "round.session.incomplete_count", flaggedCount = "round.session.flagged_count"
    case closeoutComplete = "round.session.closeout.complete", closeoutIncomplete = "round.session.closeout.incomplete"
    case readinessReady = "round.session.readiness.ready", readinessWarning = "round.session.readiness.warning", readinessBlocked = "round.session.readiness.blocked", readinessStale = "round.session.readiness.stale", readinessUnavailable = "round.session.readiness.unavailable", readinessBlockedDisclosure = "round.session.readiness.blocked_disclosure"
    case itemsHeading = "round.session.items", moveEarlier = "round.session.move_earlier", moveLater = "round.session.move_later", outOfOrderPermitted = "round.session.out_of_order", terminalState = "round.session.terminal", completed = "round.session.completed", incomplete = "round.session.incomplete"
    case jumpIncomplete = "round.session.jump_incomplete", jumpFlagged = "round.session.jump_flagged", batchHandoff = "round.session.batch_handoff", recovery = "round.session.recovery", positionPreserved = "round.session.position_preserved", saveFailure = "round.session.save_failure", saving = "round.session.saving", back = "round.session.back", orderedOnly = "round.session.ordered_only", projectionUnavailable = "round.session.projection_unavailable"
    case handoffUnavailable = "round.session.handoff.unavailable", handoffPending = "round.session.handoff.pending", handoffReady = "round.session.handoff.ready", handoffCompleted = "round.session.handoff.completed"
    var localizationKey: LocalizationKeyV1 { try! LocalizationKeyV1(rawValue) }
}

enum RoundSessionLocalizationPolicyV1 {
    static func english(_ key: RoundSessionLocalizationKeyV1) -> String { switch key {
    case .heading: return "Round session"; case .manualPathDisclosure: return "Manual work is available without permissions."
    case .progressHeading: return "Progress"; case .completedCount: return "Completed"; case .incompleteCount: return "Incomplete"; case .flaggedCount: return "Flagged"
    case .closeoutComplete: return "Local closeout is complete."; case .closeoutIncomplete: return "Local closeout is incomplete."
    case .readinessReady: return "Local readiness is ready"; case .readinessWarning: return "Local readiness has a warning"; case .readinessBlocked: return "Local readiness is blocked"; case .readinessStale: return "Local readiness is stale"; case .readinessUnavailable: return "Local readiness is unavailable"; case .readinessBlockedDisclosure: return "Resolve the listed local readiness reasons before starting field work."
    case .itemsHeading: return "Selected assets"; case .moveEarlier: return "Move earlier"; case .moveLater: return "Move later"; case .outOfOrderPermitted: return "Out-of-order work is permitted by this package."; case .terminalState: return "This item has a terminal local disposition."; case .completed: return "Completed"; case .incomplete: return "Incomplete"
    case .jumpIncomplete: return "Next incomplete"; case .jumpFlagged: return "Next flagged"; case .batchHandoff: return "Prepare local batch handoff"; case .recovery: return "Review recovery"; case .positionPreserved: return "Your field position is preserved for resume."; case .saveFailure: return "Changes could not be saved. Stay here and try again."; case .saving: return "Saving…"; case .back: return "Back"; case .orderedOnly: return "This package requires the listed order."; case .projectionUnavailable: return "Order permissions are unavailable; reordering is disabled."
    case .handoffUnavailable: return "Local batch handoff is unavailable."; case .handoffPending: return "Local batch handoff is pending."; case .handoffReady: return "Local batch handoff is ready for review."; case .handoffCompleted: return "Local batch handoff is complete." } }
    static func reason(_ reason: RoundItemReasonV1) -> String { switch reason {
    case .physicalAccessUnavailable: return "Physical access is unavailable."; case .permissionUnavailable: return "Required permission is unavailable."; case .protectedDataUnavailable: return "Protected data is unavailable while the device is locked."; case .requiredPackageUnavailable: return "The required package is unavailable."; case .requiredContentUnavailable: return "Required local content is unavailable."; case .assetDeletedDuringSession: return "This asset was deleted during the session."; case .assetRetiredOrReplaced: return "This asset was retired or replaced."; case .explicitlyOutOfScope: return "This item is explicitly out of scope."; case .duplicateSelection: return "This is a duplicate selection."; case .notRequired: return "This item is not required."; case .userDeferred: return "This item was deferred."; case .interruption: return "Work was interrupted."; case .followUpRequired: return "Follow-up is required." } }
}

enum ImportBulkPreviewLocalizationKeyV1: String, CaseIterable, Sendable { case heading = "import.preview.heading", previewOnly = "import.preview.no_write", identityDisclosure = "import.preview.identity_disclosure", source = "import.preview.source", schema = "import.preview.schema", mapping = "import.preview.mapping", plan = "import.preview.plan", noReceiptClaim = "import.preview.no_receipt_claim", create = "import.preview.create", update = "import.preview.update", unchanged = "import.preview.unchanged", duplicate = "import.preview.duplicate", ambiguous = "import.preview.ambiguous", conflict = "import.preview.conflict", invalid = "import.preview.invalid", unsupported = "import.preview.unsupported", skipped = "import.preview.skipped", allOrNothing = "import.preview.all_or_nothing", chunked = "import.preview.chunked", partial = "import.preview.partial", interrupted = "import.preview.interrupted", stale = "import.preview.stale" }
extension ImportBulkPreviewLocalizationKeyV1 { var english: String { switch self { case .heading: return "Import preview"; case .previewOnly: return "Preview only — no changes have been written."; case .identityDisclosure: return "Source, schema, mapping, and plan bindings were validated without exposing their values."; case .source: return "Source"; case .schema: return "Schema"; case .mapping: return "Mapping"; case .plan: return "Plan"; case .noReceiptClaim: return "Preview does not claim saved, complete, rolled back, or exported results. Review accepted receipts and published files separately."; case .create: return "Create"; case .update: return "Exact match update"; case .unchanged: return "Unchanged"; case .duplicate: return "Duplicate source"; case .ambiguous: return "Ambiguous target"; case .conflict: return "Conflict"; case .invalid: return "Invalid"; case .unsupported: return "Unsupported"; case .skipped: return "Skipped by user"; case .allOrNothing: return "All-or-nothing preview"; case .chunked: return "Chunked preview"; case .partial: return "Partial committed state"; case .interrupted: return "Interrupted"; case .stale: return "Stale preview" } } }

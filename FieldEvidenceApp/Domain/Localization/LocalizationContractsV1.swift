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

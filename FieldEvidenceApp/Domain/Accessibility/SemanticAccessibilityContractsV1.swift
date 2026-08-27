import Foundation

enum SemanticAccessibilityRoleV1: String, Codable, CaseIterable, Sendable {
    case screen = "SCREEN"
    case heading = "HEADING"
    case button = "BUTTON"
    case textField = "TEXT_FIELD"
    case status = "STATUS"
    case group = "GROUP"
}

enum SemanticAccessibilityReachabilityV1: String, Codable, CaseIterable, Sendable {
    case always = "ALWAYS"
    case whenAvailable = "WHEN_AVAILABLE"
}

enum AccessibilityDynamicSuffixPolicyV1: String, Codable, CaseIterable, Sendable {
    case none = "NONE"
    case opaqueLowercaseHex = "OPAQUE_LOWERCASE_HEX"
}

/// Closed C39 identifiers for the semantic asset projection.  These are
/// stable semantic identifiers, not phase-numbered IDs and not localized
/// display strings.  The state entries deliberately expose recorded/unknown
/// facts as text-capable status elements without implying operational safety
/// or verified product identity.
enum AssetSemanticAccessibilityIDV1: String, Codable, CaseIterable, Sendable {
    case screen = "asset.semantic.screen"
    case heading = "asset.semantic.heading"
    case kind = "asset.semantic.kind"
    case productIdentity = "asset.semantic.product-identity"
    case lifecycle = "asset.semantic.lifecycle"
    case workSubjectScope = "asset.semantic.work-subject-scope"
    case state = "asset.semantic.state"
    case unknownState = "asset.semantic.state.unknown"
    case duplicateState = "asset.semantic.state.duplicate"
    case retiredState = "asset.semantic.state.retired"
    case replacedState = "asset.semantic.state.replaced"
    case recordedState = "asset.semantic.state.recorded"
}

struct AccessibilityContractV1: Codable, Equatable, Sendable {
    let semanticID: String
    let role: SemanticAccessibilityRoleV1
    let reachability: SemanticAccessibilityReachabilityV1
    let labelKey: LocalizationKeyV1
    let hintKey: LocalizationKeyV1?
    let valueKey: LocalizationKeyV1?
    let dynamicSuffixPolicy: AccessibilityDynamicSuffixPolicyV1
    let deprecatedAliases: [String]
}

struct SemanticAccessibilityIDRegistryV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let entries: [AccessibilityContractV1]

    init(entries: [AccessibilityContractV1], localization: LocalizationKeyRegistryV1) throws {
        let ordered = entries.sorted { $0.semanticID < $1.semanticID }
        let primary = ordered.map(\.semanticID)
        let aliases = ordered.flatMap(\.deprecatedAliases)
        guard !ordered.isEmpty, Set(primary).count == primary.count,
              Set(aliases).count == aliases.count, Set(primary).isDisjoint(with: aliases) else {
            throw LocalizationContractFailureV1.duplicateSemanticID
        }
        for entry in ordered {
            guard Self.validSemanticID(entry.semanticID),
                  entry.deprecatedAliases == entry.deprecatedAliases.sorted(),
                  try localization.definition(for: entry.labelKey).state == .active else {
                throw LocalizationContractFailureV1.invalidAccessibilityBinding
            }
            for key in [entry.hintKey, entry.valueKey].compactMap({ $0 }) {
                guard try localization.definition(for: key).state == .active else {
                    throw LocalizationContractFailureV1.invalidAccessibilityBinding
                }
            }
        }
        schemaVersion = Self.schemaVersion
        self.entries = ordered
    }

    func identifier(semanticID: String, opaqueSuffix: String? = nil) throws -> String {
        guard let entry = entries.first(where: { $0.semanticID == semanticID }) else {
            throw LocalizationContractFailureV1.invalidAccessibilityBinding
        }
        switch (entry.dynamicSuffixPolicy, opaqueSuffix) {
        case (.none, nil): return semanticID
        case (.opaqueLowercaseHex, .some(let suffix)):
            guard (16...64).contains(suffix.utf8.count), suffix.utf8.allSatisfy({
                (0x30...0x39).contains($0) || (0x61...0x66).contains($0)
            }) else { throw LocalizationContractFailureV1.invalidOpaqueSuffix }
            return semanticID + "." + suffix
        default: throw LocalizationContractFailureV1.invalidOpaqueSuffix
        }
    }

    private static func validSemanticID(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 200, value == value.lowercased(),
              !isPhasePrefixed(value), !value.contains(" ") else { return false }
        return value.utf8.allSatisfy {
            (0x61...0x7A).contains($0) || (0x30...0x39).contains($0)
                || $0 == 0x2E || $0 == 0x5F || $0 == 0x2D
        }
    }

    private static func isPhasePrefixed(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard bytes.count >= 3, bytes[0] == 0x73 || bytes[0] == 0x76 else { return false }
        var index = 1
        while index < bytes.count, (0x30...0x39).contains(bytes[index]) { index += 1 }
        return index > 1 && index < bytes.count && bytes[index] == 0x2E
    }
}

extension SemanticAccessibilityIDRegistryV1 {
    /// Builds an additive registry while preserving the already-published
    /// semantic IDs and aliases.  C38 uses this for report accountability
    /// surfaces; callers that need the inherited V1 contract can continue to
    /// use the original registry unchanged.
    func appending(
        _ additionalEntries: [AccessibilityContractV1],
        localization: LocalizationKeyRegistryV1
    ) throws -> Self {
        guard !additionalEntries.isEmpty else { return self }
        return try Self(entries: entries + additionalEntries, localization: localization)
    }

    func containsSemanticID(_ semanticID: String) -> Bool {
        entries.contains { $0.semanticID == semanticID }
    }
}

enum LegacyLocalizationAccessibilityKindV1: String, Codable, Sendable {
    case userFacingLiteral = "USER_FACING_LITERAL"
    case phaseAccessibilityID = "PHASE_ACCESSIBILITY_ID"
}

struct LegacyLocalizationAccessibilityEntryV1: Codable, Equatable, Hashable, Sendable {
    let kind: LegacyLocalizationAccessibilityKindV1
    let stableFingerprint: String
}

struct LegacyLocalizationAccessibilityAllowlistV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let entries: [LegacyLocalizationAccessibilityEntryV1]

    init(entries: [LegacyLocalizationAccessibilityEntryV1]) throws {
        let ordered = entries.sorted {
            ($0.kind.rawValue, $0.stableFingerprint) < ($1.kind.rawValue, $1.stableFingerprint)
        }
        guard Set(ordered).count == ordered.count,
              ordered.allSatisfy({ KernelCanonicalHashV1.validSHA256($0.stableFingerprint) }) else {
            throw LocalizationContractFailureV1.invalidValue
        }
        schemaVersion = Self.schemaVersion
        self.entries = ordered
    }

    func validateObserved(_ observed: [LegacyLocalizationAccessibilityEntryV1]) throws {
        try validate()
        guard Set(observed).isSubset(of: Set(entries)) else {
            throw LocalizationContractFailureV1.legacyAllowlistGrowth
        }
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              self == (try Self(entries: entries)) else {
            throw LocalizationContractFailureV1.incompatibleVersion
        }
    }
}

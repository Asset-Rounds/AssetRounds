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

/// Closed C40 identifiers for authority, applicability, criterion-result, and
/// measurement presentation.  These IDs remain stable when a localized label
/// changes.  Indeterminate states are text-bearing status elements so VoiceOver,
/// Voice Control, Dynamic Type, and non-color presentation retain the same
/// meaning.
enum AuthorityCriterionAccessibilityIDV1: String, Codable, CaseIterable, Sendable {
    case screen = "authority.criterion.screen"
    case heading = "authority.criterion.heading"
    case authoritySource = "authority.criterion.authority-source"
    case applicability = "authority.criterion.applicability"
    case applicable = "authority.criterion.applicability.applicable"
    case notApplicableWithReason = "authority.criterion.applicability.not_applicable_with_reason"
    case unknownApplicability = "authority.criterion.applicability.unknown"
    case conflictReviewRequired = "authority.criterion.applicability.conflict_review_required"
    case unsupportedApplicability = "authority.criterion.applicability.unsupported"
    case criterionResult = "authority.criterion.result"
    case meetsScreeningCriterion = "authority.criterion.result.meets_screening_criterion"
    case doesNotMeet = "authority.criterion.result.does_not_meet"
    case inconclusive = "authority.criterion.result.inconclusive"
    case notEvaluated = "authority.criterion.result.not_evaluated"
    case severity = "authority.criterion.severity"
    case measurementProtocol = "authority.criterion.measurement-protocol"
    case technicalBasis = "authority.criterion.technical-basis"
    case nextStep = "authority.criterion.next-step"
    case assessedAgainst = "authority.criterion.assessed-against"

    // Additive aliases keep state names easy to discover without introducing
    // additional IDs or changing the closed CaseIterable surface.
    static var result: Self { .criterionResult }
    static var unknown: Self { .unknownApplicability }
    static var unsupported: Self { .unsupportedApplicability }
}

/// Closed C41 identifiers for functional-relationship type, direction, and
/// lifecycle/readiness presentation.  These IDs are stable semantic
/// identifiers, independent of localized display text or recorded UUIDs.
enum FunctionalRelationshipAccessibilityIDV1: String, Codable, CaseIterable, Sendable {
    case screen = "functional.relationship.screen"
    case heading = "functional.relationship.heading"
    case type = "functional.relationship.type"
    case directedSourceToTarget = "functional.relationship.direction.source-to-target"
    case symmetric = "functional.relationship.direction.symmetric"
    case activeState = "functional.relationship.state.active"
    case endedState = "functional.relationship.state.ended"
    case supersededState = "functional.relationship.state.superseded"
    case incompleteState = "functional.relationship.state.incomplete"
    case blockedState = "functional.relationship.state.blocked"
    case minimumNextRequirement = "functional.relationship.next-step.minimum-requirement"
    case descriptor = "functional.relationship.descriptor"
    case bounds = "functional.relationship.bounds"
    case site = "functional.relationship.site"
    case crossSiteState = "functional.relationship.site.cross-site"

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
}

/// C41 state presentation requires text in addition to any icon or color.
/// Incomplete and blocked records additionally expose an actionable minimum
/// requirement so a reader can recover without inferring an operation.
enum FunctionalRelationshipAccessibilityPolicyV1 {
    static let semanticIDs = FunctionalRelationshipAccessibilityIDV1.allCases.map(\.rawValue)
    static let stateSemanticIDs: Set<String> = [
        FunctionalRelationshipAccessibilityIDV1.activeState.rawValue,
        FunctionalRelationshipAccessibilityIDV1.endedState.rawValue,
        FunctionalRelationshipAccessibilityIDV1.supersededState.rawValue,
        FunctionalRelationshipAccessibilityIDV1.incompleteState.rawValue,
        FunctionalRelationshipAccessibilityIDV1.blockedState.rawValue,
    ]
    static let indeterminateSemanticIDs: Set<String> = [
        FunctionalRelationshipAccessibilityIDV1.incompleteState.rawValue,
        FunctionalRelationshipAccessibilityIDV1.blockedState.rawValue,
    ]
    static let statusSemanticIDs: Set<String> = stateSemanticIDs
    static let directionTextRequired = true
    static let stateTextRequired = true
    static let nonColorStateTextRequired = true
    static let textAndIconRequiredForIndeterminateStates = true
    static let actionableNextStepRequiredForIndeterminateStates = true
    static let colorOnlyStateAllowed = false
    static let iconOnlyStateAllowed = false
    static let rtlRequired = true
    static let dynamicTypeRequired = true
    static let voiceOverRequired = true
    static let voiceControlRequired = true
    static let switchControlRequired = true
    static let actionableNextStepRequired = true
    static let textIconActionableNextStepRequired = true

    static func requiresTextAndIcon(for semanticID: String) -> Bool {
        indeterminateSemanticIDs.contains(semanticID)
    }

    static func requiresActionableNextStep(for semanticID: String) -> Bool {
        indeterminateSemanticIDs.contains(semanticID)
    }
}

/// C40 accessibility requirements are represented as contract policy because
/// the existing accessibility record intentionally carries semantic identity,
/// role, and localized bindings—not rendering colors or icon assets.
enum AuthorityCriterionAccessibilityPolicyV1 {
    static let semanticIDs = AuthorityCriterionAccessibilityIDV1.allCases.map(\.rawValue)
    static let indeterminateSemanticIDs: Set<String> = [
        AuthorityCriterionAccessibilityIDV1.unknownApplicability.rawValue,
        AuthorityCriterionAccessibilityIDV1.conflictReviewRequired.rawValue,
        AuthorityCriterionAccessibilityIDV1.unsupportedApplicability.rawValue,
        AuthorityCriterionAccessibilityIDV1.inconclusive.rawValue,
        AuthorityCriterionAccessibilityIDV1.notEvaluated.rawValue,
    ]
    static let statusSemanticIDs: Set<String> = [
        AuthorityCriterionAccessibilityIDV1.applicable.rawValue,
        AuthorityCriterionAccessibilityIDV1.notApplicableWithReason.rawValue,
        AuthorityCriterionAccessibilityIDV1.unknownApplicability.rawValue,
        AuthorityCriterionAccessibilityIDV1.conflictReviewRequired.rawValue,
        AuthorityCriterionAccessibilityIDV1.unsupportedApplicability.rawValue,
        AuthorityCriterionAccessibilityIDV1.meetsScreeningCriterion.rawValue,
        AuthorityCriterionAccessibilityIDV1.doesNotMeet.rawValue,
        AuthorityCriterionAccessibilityIDV1.inconclusive.rawValue,
        AuthorityCriterionAccessibilityIDV1.notEvaluated.rawValue,
        AuthorityCriterionAccessibilityIDV1.severity.rawValue,
    ]
    static let nonColorStateTextRequired = true
    static let textAndIconRequiredForIndeterminateStates = true
    static let actionableNextStepRequiredForIndeterminateStates = true
    static let colorOnlySeverityAllowed = false
    static let iconOnlyStatusAllowed = false
    static let rtlRequired = true
    static let dynamicTypeRequired = true
    static let voiceOverRequired = true
    static let voiceControlRequired = true
    static let switchControlRequired = true
    static let actionableNextStepRequired = true
    static let textIconActionableNextStepRequired = true
    static let colorOnlyAllowed = false
    static let iconOnlyAllowed = false

    static func requiresTextAndIcon(for semanticID: String) -> Bool {
        indeterminateSemanticIDs.contains(semanticID)
    }

    static func requiresActionableNextStep(for semanticID: String) -> Bool {
        indeterminateSemanticIDs.contains(semanticID)
    }
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

import Foundation

enum SemanticAccessibilityRoleV1: String, Codable, CaseIterable, Sendable {
    case screen = "SCREEN"
    case heading = "HEADING"
    case button = "BUTTON"
    case textField = "TEXT_FIELD"
    case status = "STATUS"
    case group = "GROUP"
}

enum C50IncumbentAccessibilityBoundaryV1 {
    static let previewAnnouncesIncludedOmittedAndUnresolvedCounts = true
    static let quarantineAndDisabledStatesAreNotColorOnly = true
    static let profileVersionAndDirectionHaveAccessibleLabels = true
    static let keyboardFocusOrderIsDeterministic = true
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

/// Closed C13 identifiers for the evidence-assurance projection.  They remain
/// stable when English display text changes and identify recorded audience,
/// sensitivity, inclusion, preview, manifest, and attestation facts only.
enum EvidenceVisibilityAccessibilityIDV1: String, Codable, CaseIterable, Sendable {
    case screen = "evidence.visibility.screen"
    case heading = "evidence.visibility.heading"
    case audience = "evidence.visibility.audience"
    case audienceInternalReview = "evidence.visibility.audience.internal-review"
    case audienceCustomerReport = "evidence.visibility.audience.customer-report"
    case audienceExternalCollaborator = "evidence.visibility.audience.external-collaborator"
    case sensitivity = "evidence.visibility.sensitivity"
    case sensitivityRoutine = "evidence.visibility.sensitivity.routine"
    case sensitivityRestricted = "evidence.visibility.sensitivity.restricted"
    case sensitivityHighlyRestricted = "evidence.visibility.sensitivity.highly-restricted"
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
    case nextStep = "evidence.visibility.next-step"

    static var visibilityHeading: Self { .heading }
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
}

typealias EvidenceAssuranceAccessibilityIDV1 = EvidenceVisibilityAccessibilityIDV1

/// C13 status requirements make omission and indeterminate presentation
/// understandable without relying on color or an icon alone.  An explicit
/// next-step binding is required for every state that can deny or limit a
/// projection.
enum EvidenceVisibilityAccessibilityPolicyV1 {
    static let semanticIDs = EvidenceVisibilityAccessibilityIDV1.allCases.map(\.rawValue)
    static let stateSemanticIDs: Set<String> = [
        EvidenceVisibilityAccessibilityIDV1.included.rawValue,
        EvidenceVisibilityAccessibilityIDV1.excluded.rawValue,
        EvidenceVisibilityAccessibilityIDV1.omitted.rawValue,
        EvidenceVisibilityAccessibilityIDV1.limitation.rawValue,
        EvidenceVisibilityAccessibilityIDV1.unknown.rawValue,
        EvidenceVisibilityAccessibilityIDV1.previewReady.rawValue,
        EvidenceVisibilityAccessibilityIDV1.previewStale.rawValue,
        EvidenceVisibilityAccessibilityIDV1.attestationRecorded.rawValue,
        EvidenceVisibilityAccessibilityIDV1.attestationSuperseded.rawValue,
        EvidenceVisibilityAccessibilityIDV1.attestationVoid.rawValue,
    ]
    static let indeterminateSemanticIDs: Set<String> = [
        EvidenceVisibilityAccessibilityIDV1.excluded.rawValue,
        EvidenceVisibilityAccessibilityIDV1.omitted.rawValue,
        EvidenceVisibilityAccessibilityIDV1.limitation.rawValue,
        EvidenceVisibilityAccessibilityIDV1.unknown.rawValue,
        EvidenceVisibilityAccessibilityIDV1.previewStale.rawValue,
        EvidenceVisibilityAccessibilityIDV1.attestationSuperseded.rawValue,
        EvidenceVisibilityAccessibilityIDV1.attestationVoid.rawValue,
    ]
    static let statusSemanticIDs: Set<String> = stateSemanticIDs
    static let denyByDefault = true
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

typealias EvidenceAssuranceAccessibilityPolicyV1 = EvidenceVisibilityAccessibilityPolicyV1

/// Closed C14 identifiers for review, change-request, and corrective-action
/// projections.  These IDs are stable semantic identities, not localized text
/// or record IDs.  Recorded indeterminate states carry a next-step hint so
/// their meaning does not depend on color or an icon alone.
enum InspectionReviewAccessibilityIDV1: String, Codable, CaseIterable, Sendable {
    case screen = "inspection.review.screen"
    case heading = "inspection.review.heading"
    case state = "inspection.review.state"
    case draft = "inspection.review.state.draft"
    case fieldComplete = "inspection.review.state.field-complete"
    case readyForReview = "inspection.review.state.ready-for-review"
    case changesRequested = "inspection.review.state.changes-requested"
    case accepted = "inspection.review.state.accepted"
    case finalized = "inspection.review.state.finalized"
    case amended = "inspection.review.state.amended"
    case superseded = "inspection.review.state.superseded"
    case disposition = "inspection.review.disposition"
    case dispositionChangesRequested = "inspection.review.disposition.changes-requested"
    case dispositionAccepted = "inspection.review.disposition.accepted"
    case changeRequest = "inspection.review.change-request"
    case changeRequestState = "inspection.review.change-request.state"
    case changeRequestOpen = "inspection.review.change-request.state.open"
    case changeRequestResolved = "inspection.review.change-request.state.resolved"
    case changeRequestWithdrawn = "inspection.review.change-request.state.withdrawn"
    case changeRequestSuperseded = "inspection.review.change-request.state.superseded"
    case changeRequestResolution = "inspection.review.change-request.resolution"
    case changeRequestResolutionFulfilled = "inspection.review.change-request.resolution.fulfilled"
    case changeRequestResolutionWithdrawnWithReason = "inspection.review.change-request.resolution.withdrawn-with-reason"
    case changeRequestResolutionSuperseded = "inspection.review.change-request.resolution.superseded"
    case correctiveAction = "inspection.review.corrective-action"
    case correctiveActionState = "inspection.review.corrective-action.state"
    case correctiveActionOpen = "inspection.review.corrective-action.state.open"
    case correctiveActionInProgress = "inspection.review.corrective-action.state.in-progress"
    case correctiveActionAwaitingVerification = "inspection.review.corrective-action.state.awaiting-verification"
    case correctiveActionClosed = "inspection.review.corrective-action.state.closed"
    case correctiveActionReopened = "inspection.review.corrective-action.state.reopened"
    case correctiveActionSuperseded = "inspection.review.corrective-action.state.superseded"
    case nextStep = "inspection.review.next-step"
    case minimumNextRequirement = "inspection.review.next-step.minimum-requirement"

    static var reviewHeading: Self { .heading }
    static var reviewState: Self { .state }
    static var fieldCompleteState: Self { .fieldComplete }
    static var readyState: Self { .readyForReview }
    static var changesRequestedState: Self { .changesRequested }
    static var acceptedState: Self { .accepted }
    static var finalizedState: Self { .finalized }
    static var amendedState: Self { .amended }
    static var supersededState: Self { .superseded }
    static var changeRequestHeading: Self { .changeRequest }
    static var correctiveActionHeading: Self { .correctiveAction }
    static var actionableNextStep: Self { .nextStep }
}

typealias ReviewCorrectiveActionAccessibilityIDV1 = InspectionReviewAccessibilityIDV1
typealias ReviewAndCorrectiveActionAccessibilityIDV1 = InspectionReviewAccessibilityIDV1

/// Accessibility policy for C14's recorded review/action states.  The
/// contract deliberately says nothing about color or icon assets; consumers
/// must provide text, and indeterminate states also expose an actionable hint.
enum InspectionReviewAccessibilityPolicyV1 {
    static let semanticIDs = InspectionReviewAccessibilityIDV1.allCases.map(\.rawValue)
    static let stateSemanticIDs: Set<String> = [
        InspectionReviewAccessibilityIDV1.draft.rawValue,
        InspectionReviewAccessibilityIDV1.fieldComplete.rawValue,
        InspectionReviewAccessibilityIDV1.readyForReview.rawValue,
        InspectionReviewAccessibilityIDV1.changesRequested.rawValue,
        InspectionReviewAccessibilityIDV1.accepted.rawValue,
        InspectionReviewAccessibilityIDV1.finalized.rawValue,
        InspectionReviewAccessibilityIDV1.amended.rawValue,
        InspectionReviewAccessibilityIDV1.superseded.rawValue,
        InspectionReviewAccessibilityIDV1.dispositionChangesRequested.rawValue,
        InspectionReviewAccessibilityIDV1.dispositionAccepted.rawValue,
        InspectionReviewAccessibilityIDV1.changeRequestOpen.rawValue,
        InspectionReviewAccessibilityIDV1.changeRequestResolved.rawValue,
        InspectionReviewAccessibilityIDV1.changeRequestWithdrawn.rawValue,
        InspectionReviewAccessibilityIDV1.changeRequestSuperseded.rawValue,
        InspectionReviewAccessibilityIDV1.changeRequestResolutionFulfilled.rawValue,
        InspectionReviewAccessibilityIDV1.changeRequestResolutionWithdrawnWithReason.rawValue,
        InspectionReviewAccessibilityIDV1.changeRequestResolutionSuperseded.rawValue,
        InspectionReviewAccessibilityIDV1.correctiveActionOpen.rawValue,
        InspectionReviewAccessibilityIDV1.correctiveActionInProgress.rawValue,
        InspectionReviewAccessibilityIDV1.correctiveActionAwaitingVerification.rawValue,
        InspectionReviewAccessibilityIDV1.correctiveActionClosed.rawValue,
        InspectionReviewAccessibilityIDV1.correctiveActionReopened.rawValue,
        InspectionReviewAccessibilityIDV1.correctiveActionSuperseded.rawValue,
    ]
    static let indeterminateSemanticIDs: Set<String> = [
        InspectionReviewAccessibilityIDV1.draft.rawValue,
        InspectionReviewAccessibilityIDV1.fieldComplete.rawValue,
        InspectionReviewAccessibilityIDV1.readyForReview.rawValue,
        InspectionReviewAccessibilityIDV1.changesRequested.rawValue,
        InspectionReviewAccessibilityIDV1.amended.rawValue,
        InspectionReviewAccessibilityIDV1.superseded.rawValue,
        InspectionReviewAccessibilityIDV1.dispositionChangesRequested.rawValue,
        InspectionReviewAccessibilityIDV1.changeRequestOpen.rawValue,
        InspectionReviewAccessibilityIDV1.changeRequestResolutionSuperseded.rawValue,
        InspectionReviewAccessibilityIDV1.correctiveActionOpen.rawValue,
        InspectionReviewAccessibilityIDV1.correctiveActionInProgress.rawValue,
        InspectionReviewAccessibilityIDV1.correctiveActionAwaitingVerification.rawValue,
        InspectionReviewAccessibilityIDV1.correctiveActionReopened.rawValue,
        InspectionReviewAccessibilityIDV1.correctiveActionSuperseded.rawValue,
    ]
    static let statusSemanticIDs = stateSemanticIDs
    static let denyByDefault = true
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

typealias ReviewCorrectiveActionAccessibilityPolicyV1 = InspectionReviewAccessibilityPolicyV1
typealias ReviewAndCorrectiveActionAccessibilityPolicyV1 = InspectionReviewAccessibilityPolicyV1

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

/// Closed C15 semantic IDs for local packet coordination.  These IDs identify
/// packet concepts and recorded states, never packet contents or actor data.
/// Transitional, expired, conflicted, and quarantined states carry an
/// actionable next-step hint and must remain understandable without color or
/// an icon alone.
enum WorkPacketAccessibilityIDV1: String, Codable, CaseIterable, Sendable {
    case screen = "work.packet.screen"
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
    case conflictReviewRequired = "work.packet.conflict.state.review-required"
    case conflictResolved = "work.packet.conflict.state.resolved"
    case expiry = "work.packet.expiry"
    case expiryState = "work.packet.expiry.state"
    case expiryNotExpired = "work.packet.expiry.state.not-expired"
    case expiryExpiring = "work.packet.expiry.state.expiring"
    case expiryExpired = "work.packet.expiry.state.expired"
    case replay = "work.packet.replay"
    case replayState = "work.packet.replay.state"
    case replayPending = "work.packet.replay.state.pending"
    case replayApplied = "work.packet.replay.state.applied"
    case replayIdempotent = "work.packet.replay.state.idempotent"
    case replayQuarantined = "work.packet.replay.state.quarantined"
    case nextStep = "work.packet.next-step"
    case minimumNextRequirement = "work.packet.next-step.minimum-requirement"

    static var packetHeading: Self { .heading }
    static var packetManifest: Self { .manifest }
    static var packetItem: Self { .item }
    static var packetClaim: Self { .claim }
    static var packetLease: Self { .lease }
    static var packetRelease: Self { .release }
    static var packetHandoff: Self { .handoff }
    static var packetConflict: Self { .conflict }
    static var packetExpiry: Self { .expiry }
    static var packetReplay: Self { .replay }
    static var actionableNextStep: Self { .nextStep }
}

typealias WorkPacketManifestAccessibilityIDV1 = WorkPacketAccessibilityIDV1
typealias PacketCoordinationAccessibilityIDV1 = WorkPacketAccessibilityIDV1

/// C36 semantic IDs cover the reusable durability/status surface only.  They
/// identify recorded draft and attachment states, never draft contents,
/// customer/work data, private locators, or a feature screen implementation.
enum FieldDraftAccessibilityIDV1: String, Codable, CaseIterable, Sendable {
    case screen = "field.draft.screen"
    case heading = "field.draft.heading"
    case durability = "field.draft.durability"
    case durabilityState = "field.draft.durability.state"
    case nextStep = "field.draft.next-step"
    case minimumNextRequirement = "field.draft.next-step.minimum-requirement"
    case checkpoint = "field.draft.checkpoint"
    case checkpointState = "field.draft.checkpoint.state"
    case attachment = "field.draft.attachment"
    case attachmentState = "field.draft.attachment.state"
    case commitSaga = "field.draft.commit.saga"
    case commitSagaState = "field.draft.commit.saga.state"
    case recovery = "field.draft.recovery"
    case recoveryState = "field.draft.recovery.state"
    case recoverySafeAction = "field.draft.recovery.safe-action"
    case recoveryFallback = "field.draft.recovery.fallback"

    case durabilityUnsavedChanges = "field.draft.durability.state.unsaved-changes"
    case durabilitySavingOnThisIPhone = "field.draft.durability.state.saving-on-this-iphone"
    case durabilitySavedOnThisIPhone = "field.draft.durability.state.saved-on-this-iphone"
    case durabilitySaveBlocked = "field.draft.durability.state.save-blocked"
    case durabilityCommitting = "field.draft.durability.state.committing"
    case durabilityConflicted = "field.draft.durability.state.conflicted"
    case durabilityRecoveryRequired = "field.draft.durability.state.recovery-required"
    case durabilityCommitted = "field.draft.durability.state.committed"
    case durabilityDiscarding = "field.draft.durability.state.discarding"
    case durabilityDiscarded = "field.draft.durability.state.discarded"

    case checkpointActive = "field.draft.checkpoint.state.active"
    case checkpointCommitting = "field.draft.checkpoint.state.committing"
    case checkpointConflicted = "field.draft.checkpoint.state.conflicted"
    case checkpointRecoveryRequired = "field.draft.checkpoint.state.recovery-required"
    case checkpointCommitted = "field.draft.checkpoint.state.committed"
    case checkpointDiscardPending = "field.draft.checkpoint.state.discard-pending"
    case checkpointDiscarded = "field.draft.checkpoint.state.discarded"

    case attachmentSelected = "field.draft.attachment.state.selected"
    case attachmentLoading = "field.draft.attachment.state.loading"
    case attachmentStagedLocal = "field.draft.attachment.state.staged-local"
    case attachmentProcessing = "field.draft.attachment.state.processing"
    case attachmentReady = "field.draft.attachment.state.ready"
    case attachmentRetryableFailure = "field.draft.attachment.state.retryable-failure"
    case attachmentBlocked = "field.draft.attachment.state.blocked"
    case attachmentRemoved = "field.draft.attachment.state.removed"
    case attachmentPromoted = "field.draft.attachment.state.promoted"
    case attachmentCapturing = "field.draft.attachment.state.capturing"
    case attachmentHashing = "field.draft.attachment.state.hashing"
    case attachmentReadyLocal = "field.draft.attachment.state.ready-local"
    case attachmentFailedRetryable = "field.draft.attachment.state.failed-retryable"
    case attachmentFailedFinal = "field.draft.attachment.state.failed-final"
    case attachmentRemovePending = "field.draft.attachment.state.remove-pending"
    case attachmentCommitted = "field.draft.attachment.state.committed"
    case attachmentOrphanQuarantined = "field.draft.attachment.state.orphan-quarantined"

    case sagaPrepared = "field.draft.commit.saga.state.prepared"
    case sagaContentPromotedUnbound = "field.draft.commit.saga.state.content-promoted-unbound"
    case sagaTargetCommitted = "field.draft.commit.saga.state.target-committed"
    case sagaDraftRetirePending = "field.draft.commit.saga.state.draft-retire-pending"
    case sagaDraftRetired = "field.draft.commit.saga.state.draft-retired"
    case sagaConflicted = "field.draft.commit.saga.state.conflicted"
    case sagaRecoveryRequired = "field.draft.commit.saga.state.recovery-required"

    case recoveryResumeAvailable = "field.draft.recovery.state.resume-available"
    case recoveryConflict = "field.draft.recovery.state.conflict"
    case recoveryMissingMedia = "field.draft.recovery.state.missing-media"
    case recoveryLowStorage = "field.draft.recovery.state.low-storage"
    case recoveryProtectedData = "field.draft.recovery.state.protected-data"
    case recoveryUnsupportedCodec = "field.draft.recovery.state.unsupported-codec"
    case recoveryPartialStage = "field.draft.recovery.state.partial-stage"
    case recoveryStaleTarget = "field.draft.recovery.state.stale-target"
    case recoveryRecoveryRequired = "field.draft.recovery.state.recovery-required"

    static var actionableNextStep: Self { .nextStep }
    static var minimumRequirement: Self { .minimumNextRequirement }

    var localizationKey: FieldDraftLocalizationKeyV1 {
        // Accessibility IDs intentionally use hyphens while localization keys
        // use the existing underscore convention for compound words.
        // swiftlint:disable:next force_unwrapping
        FieldDraftLocalizationKeyV1(
            rawValue: rawValue.replacingOccurrences(of: "-", with: "_")
        )!
    }
}

/// C36 statuses are text-bearing and actionable wherever state is uncertain;
/// color, icon, motion, and haptic feedback are reinforcement only.
enum FieldDraftAccessibilityPolicyV1 {
    static let semanticIDs = FieldDraftAccessibilityIDV1.allCases.map(\.rawValue)
    static let stateSemanticIDs: Set<String> = Set(
        FieldDraftAccessibilityIDV1.allCases
            .filter { $0.rawValue.contains(".state.") }
            .map(\.rawValue)
    )
    static let indeterminateSemanticIDs: Set<String> = Set(
        ([
        FieldDraftAccessibilityIDV1.durabilityUnsavedChanges,
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
    ] as [FieldDraftAccessibilityIDV1]).map(\.rawValue)
    )
    static let statusSemanticIDs = stateSemanticIDs
    static let perItemDynamicSuffixPolicy = AccessibilityDynamicSuffixPolicyV1.opaqueLowercaseHex
    static let denyByDefault = true
    static let nonColorStateTextRequired = true
    static let textAndIconRequiredForIndeterminateStates = true
    static let actionableNextStepRequiredForIndeterminateStates = true
    static let colorOnlyStateAllowed = false
    static let iconOnlyStateAllowed = false
    static let motionOnlyStateAllowed = false
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

typealias FieldDraftResilienceAccessibilityIDV1 = FieldDraftAccessibilityIDV1
typealias FieldDraftResilienceAccessibilityPolicyV1 = FieldDraftAccessibilityPolicyV1

/// C15 accessibility policy keeps local packet coordination truthful and
/// usable with VoiceOver, Voice Control, Switch Control, Dynamic Type, RTL,
/// and non-color presentation.  It has no authority, delivery, or identity
/// semantics.
enum WorkPacketAccessibilityPolicyV1 {
    static let semanticIDs = WorkPacketAccessibilityIDV1.allCases.map(\.rawValue)
    static let stateSemanticIDs: Set<String> = [
        WorkPacketAccessibilityIDV1.manifestDraft.rawValue,
        WorkPacketAccessibilityIDV1.manifestReady.rawValue,
        WorkPacketAccessibilityIDV1.manifestInvalid.rawValue,
        WorkPacketAccessibilityIDV1.manifestReplayed.rawValue,
        WorkPacketAccessibilityIDV1.manifestConflicted.rawValue,
        WorkPacketAccessibilityIDV1.manifestSuperseded.rawValue,
        WorkPacketAccessibilityIDV1.claimUnclaimed.rawValue,
        WorkPacketAccessibilityIDV1.claimClaimed.rawValue,
        WorkPacketAccessibilityIDV1.claimReleased.rawValue,
        WorkPacketAccessibilityIDV1.claimConflicted.rawValue,
        WorkPacketAccessibilityIDV1.leaseActive.rawValue,
        WorkPacketAccessibilityIDV1.leaseExpiring.rawValue,
        WorkPacketAccessibilityIDV1.leaseExpired.rawValue,
        WorkPacketAccessibilityIDV1.leaseReclaimed.rawValue,
        WorkPacketAccessibilityIDV1.releaseRecorded.rawValue,
        WorkPacketAccessibilityIDV1.releaseAvailable.rawValue,
        WorkPacketAccessibilityIDV1.releaseSuperseded.rawValue,
        WorkPacketAccessibilityIDV1.handoffPending.rawValue,
        WorkPacketAccessibilityIDV1.handoffAccepted.rawValue,
        WorkPacketAccessibilityIDV1.handoffRejected.rawValue,
        WorkPacketAccessibilityIDV1.handoffCompleted.rawValue,
        WorkPacketAccessibilityIDV1.conflictDetected.rawValue,
        WorkPacketAccessibilityIDV1.conflictQuarantined.rawValue,
        WorkPacketAccessibilityIDV1.conflictReviewRequired.rawValue,
        WorkPacketAccessibilityIDV1.conflictResolved.rawValue,
        WorkPacketAccessibilityIDV1.expiryNotExpired.rawValue,
        WorkPacketAccessibilityIDV1.expiryExpiring.rawValue,
        WorkPacketAccessibilityIDV1.expiryExpired.rawValue,
        WorkPacketAccessibilityIDV1.replayPending.rawValue,
        WorkPacketAccessibilityIDV1.replayApplied.rawValue,
        WorkPacketAccessibilityIDV1.replayIdempotent.rawValue,
        WorkPacketAccessibilityIDV1.replayQuarantined.rawValue,
    ]
    static let indeterminateSemanticIDs: Set<String> = [
        WorkPacketAccessibilityIDV1.manifestDraft.rawValue,
        WorkPacketAccessibilityIDV1.manifestInvalid.rawValue,
        WorkPacketAccessibilityIDV1.manifestConflicted.rawValue,
        WorkPacketAccessibilityIDV1.claimUnclaimed.rawValue,
        WorkPacketAccessibilityIDV1.claimConflicted.rawValue,
        WorkPacketAccessibilityIDV1.leaseExpiring.rawValue,
        WorkPacketAccessibilityIDV1.leaseExpired.rawValue,
        WorkPacketAccessibilityIDV1.leaseReclaimed.rawValue,
        WorkPacketAccessibilityIDV1.releaseAvailable.rawValue,
        WorkPacketAccessibilityIDV1.releaseSuperseded.rawValue,
        WorkPacketAccessibilityIDV1.handoffPending.rawValue,
        WorkPacketAccessibilityIDV1.handoffRejected.rawValue,
        WorkPacketAccessibilityIDV1.conflictDetected.rawValue,
        WorkPacketAccessibilityIDV1.conflictQuarantined.rawValue,
        WorkPacketAccessibilityIDV1.conflictReviewRequired.rawValue,
        WorkPacketAccessibilityIDV1.expiryExpiring.rawValue,
        WorkPacketAccessibilityIDV1.expiryExpired.rawValue,
        WorkPacketAccessibilityIDV1.replayPending.rawValue,
        WorkPacketAccessibilityIDV1.replayQuarantined.rawValue,
    ]
    static let statusSemanticIDs = stateSemanticIDs
    static let denyByDefault = true
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

typealias WorkPacketManifestAccessibilityPolicyV1 = WorkPacketAccessibilityPolicyV1
typealias PacketCoordinationAccessibilityPolicyV1 = WorkPacketAccessibilityPolicyV1

/// C18 package-evolution IDs describe local, recorded lifecycle facts. They
/// are stable across localized labels and do not expose receipt, actor, or
/// package-byte identities through accessibility.
enum PackageEvolutionAccessibilityIDV1: String, Codable, CaseIterable, Sendable {
    case screen = "package.evolution.screen"
    case release = "package.evolution.release"
    case semanticClassification = "package.evolution.semantic-classification"
    case promotionStatus = "package.evolution.promotion-status"
    case sandboxStatus = "package.evolution.sandbox-status"
    case brandState = "package.evolution.brand-state"
    case nextStep = "package.evolution.next-step"
}

struct PackageEvolutionAccessibilityContractV1: Codable, Equatable, Sendable {
    let semanticID: PackageEvolutionAccessibilityIDV1
    let role: SemanticAccessibilityRoleV1
    let textAlternativeRequired: Bool
    let iconIsSupplemental: Bool
    let nonColorStateRequired: Bool
    let actionableNextStep: Bool

    init(
        semanticID: PackageEvolutionAccessibilityIDV1,
        role: SemanticAccessibilityRoleV1,
        textAlternativeRequired: Bool = true,
        iconIsSupplemental: Bool = true,
        nonColorStateRequired: Bool = true,
        actionableNextStep: Bool = false
    ) {
        self.semanticID = semanticID
        self.role = role
        self.textAlternativeRequired = textAlternativeRequired
        self.iconIsSupplemental = iconIsSupplemental
        self.nonColorStateRequired = nonColorStateRequired
        self.actionableNextStep = actionableNextStep
    }
}

enum PackageEvolutionAccessibilityPolicyV1 {
    static let semanticIDs = PackageEvolutionAccessibilityIDV1.allCases.map(\.rawValue)
    static let nonColorStateTextRequired = true
    static let iconOnlyStateAllowed = false
    static let motionOnlyStateAllowed = false
    static let packageBytesAndActorIdentityExposed = false
    static let contracts: [PackageEvolutionAccessibilityContractV1] = [
        .init(semanticID: .screen, role: .screen),
        .init(semanticID: .release, role: .heading),
        .init(semanticID: .semanticClassification, role: .status),
        .init(semanticID: .promotionStatus, role: .status),
        .init(semanticID: .sandboxStatus, role: .status),
        .init(semanticID: .brandState, role: .status),
        .init(semanticID: .nextStep, role: .button, actionableNextStep: true),
    ]

    static func validate() -> Bool {
        contracts.map { $0.semanticID.rawValue } == semanticIDs
            && contracts.allSatisfy {
                $0.textAlternativeRequired
                    && $0.iconIsSupplemental
                    && $0.nonColorStateRequired
            }
            && contracts.contains { $0.semanticID == .nextStep && $0.actionableNextStep }
            && !iconOnlyStateAllowed
            && !motionOnlyStateAllowed
            && !packageBytesAndActorIdentityExposed
    }
}

/// Closed C19 semantic IDs for local measurement-integrity presentation.
/// These IDs identify the meaning of a record, never an instrument serial,
/// actor identity, evidence locator, or localized display string.
enum MeasurementIntegrityAccessibilityIDV1: String, Codable, CaseIterable, Sendable {
    case screen = "measurement.integrity.screen"
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
    static var qualityDisposition: Self { .qualityResult }
    static var actionableNextStep: Self { .nextStep }
}

/// C19 states always have a text alternative.  Indeterminate records also
/// expose an actionable next-step hint, while icons, color, and motion remain
/// supplemental and cannot carry the recorded meaning alone.
enum MeasurementIntegrityAccessibilityPolicyV1 {
    static let semanticIDs = MeasurementIntegrityAccessibilityIDV1.allCases.map(\.rawValue)
    static let stateSemanticIDs: Set<String> = [
        MeasurementIntegrityAccessibilityIDV1.instrumentLifecycleActive.rawValue,
        MeasurementIntegrityAccessibilityIDV1.instrumentLifecycleOutOfService.rawValue,
        MeasurementIntegrityAccessibilityIDV1.instrumentLifecycleRetired.rawValue,
        MeasurementIntegrityAccessibilityIDV1.calibrationNotRequired.rawValue,
        MeasurementIntegrityAccessibilityIDV1.calibrationCurrent.rawValue,
        MeasurementIntegrityAccessibilityIDV1.calibrationExpired.rawValue,
        MeasurementIntegrityAccessibilityIDV1.calibrationUnknown.rawValue,
        MeasurementIntegrityAccessibilityIDV1.calibrationOutOfService.rawValue,
        MeasurementIntegrityAccessibilityIDV1.seriesOpen.rawValue,
        MeasurementIntegrityAccessibilityIDV1.seriesFinalized.rawValue,
        MeasurementIntegrityAccessibilityIDV1.qualityClear.rawValue,
        MeasurementIntegrityAccessibilityIDV1.qualityReviewRequired.rawValue,
        MeasurementIntegrityAccessibilityIDV1.qualityOverridden.rawValue,
    ]
    static let indeterminateSemanticIDs: Set<String> = [
        MeasurementIntegrityAccessibilityIDV1.instrumentLifecycleOutOfService.rawValue,
        MeasurementIntegrityAccessibilityIDV1.calibrationExpired.rawValue,
        MeasurementIntegrityAccessibilityIDV1.calibrationUnknown.rawValue,
        MeasurementIntegrityAccessibilityIDV1.calibrationOutOfService.rawValue,
        MeasurementIntegrityAccessibilityIDV1.seriesOpen.rawValue,
        MeasurementIntegrityAccessibilityIDV1.qualityReviewRequired.rawValue,
        MeasurementIntegrityAccessibilityIDV1.qualityOverridden.rawValue,
        MeasurementIntegrityAccessibilityIDV1.qualityReasonMissingUncertainty.rawValue,
        MeasurementIntegrityAccessibilityIDV1.qualityReasonIncompleteSampleSet.rawValue,
        MeasurementIntegrityAccessibilityIDV1.qualityReasonObservationLimitation.rawValue,
    ]
    static let statusSemanticIDs = stateSemanticIDs
    static let denyByDefault = true
    static let nonColorStateTextRequired = true
    static let textAlternativeRequired = true
    static let textAndIconRequiredForIndeterminateStates = true
    static let actionableNextStepRequiredForIndeterminateStates = true
    static let colorOnlyStateAllowed = false
    static let iconOnlyStateAllowed = false
    static let motionOnlyStateAllowed = false
    static let excludesOpaqueSerialAndOperatorIdentity = true
    static let excludesEvidenceLocators = true
    static let rtlRequired = true
    static let dynamicTypeRequired = true
    static let voiceOverRequired = true
    static let voiceControlRequired = true
    static let switchControlRequired = true

    static func requiresTextAndIcon(for semanticID: String) -> Bool {
        indeterminateSemanticIDs.contains(semanticID)
    }

    static func requiresActionableNextStep(for semanticID: String) -> Bool {
        indeterminateSemanticIDs.contains(semanticID)
    }
}

/// C20 semantic identifiers for the manual redaction-review projection.  The
/// IDs are stable meaning identifiers; they are never the original content
/// locator, reviewer identity, or a claim about anonymization.
enum PrivacyTransformAccessibilityIDV1: String, Codable, CaseIterable, Sendable {
    case screen = "privacy.transform.screen"
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
        // swiftlint:disable:next force_try
        try! LocalizationKeyV1(rawValue)
    }
}

enum PrivacyTransformAccessibilityPolicyV1 {
    static let semanticIDs = PrivacyTransformAccessibilityIDV1.allCases.map(\.rawValue)
    static let stateSemanticIDs: Set<String> = [
        PrivacyTransformAccessibilityIDV1.reviewApproved.rawValue,
        PrivacyTransformAccessibilityIDV1.reviewRejected.rawValue,
        PrivacyTransformAccessibilityIDV1.freshnessCurrent.rawValue,
        PrivacyTransformAccessibilityIDV1.projectionAllowed.rawValue,
        PrivacyTransformAccessibilityIDV1.projectionDenied.rawValue,
        PrivacyTransformAccessibilityIDV1.denialMissingReview.rawValue,
        PrivacyTransformAccessibilityIDV1.denialRejected.rawValue,
        PrivacyTransformAccessibilityIDV1.denialStale.rawValue,
        PrivacyTransformAccessibilityIDV1.denialWrongAudience.rawValue,
        PrivacyTransformAccessibilityIDV1.denialWrongPolicy.rawValue,
        PrivacyTransformAccessibilityIDV1.denialSourceChanged.rawValue,
        PrivacyTransformAccessibilityIDV1.denialDigestMismatch.rawValue,
        PrivacyTransformAccessibilityIDV1.denialMetadataNotSanitized.rawValue,
    ]
    static let indeterminateSemanticIDs: Set<String> = [
        PrivacyTransformAccessibilityIDV1.projectionDenied.rawValue,
        PrivacyTransformAccessibilityIDV1.denialMissingReview.rawValue,
        PrivacyTransformAccessibilityIDV1.denialRejected.rawValue,
        PrivacyTransformAccessibilityIDV1.denialStale.rawValue,
        PrivacyTransformAccessibilityIDV1.denialWrongAudience.rawValue,
        PrivacyTransformAccessibilityIDV1.denialWrongPolicy.rawValue,
        PrivacyTransformAccessibilityIDV1.denialSourceChanged.rawValue,
        PrivacyTransformAccessibilityIDV1.denialDigestMismatch.rawValue,
        PrivacyTransformAccessibilityIDV1.denialMetadataNotSanitized.rawValue,
    ]
    static let statusSemanticIDs = stateSemanticIDs
    static let denyByDefault = true
    static let nonColorStateTextRequired = true
    static let textAlternativeRequired = true
    static let textAndIconRequiredForIndeterminateStates = true
    static let actionableNextStepRequiredForIndeterminateStates = true
    static let colorOnlyStateAllowed = false
    static let iconOnlyStateAllowed = false
    static let motionOnlyStateAllowed = false
    static let excludesOriginalBytes = true
    static let excludesOriginalReferences = true
    static let excludesReviewerIdentity = true
    static let excludesReviewRationale = true
    static let rtlRequired = true
    static let dynamicTypeRequired = true
    static let voiceOverRequired = true
    static let voiceControlRequired = true
    static let switchControlRequired = true

    static func requiresTextAndIcon(for semanticID: String) -> Bool {
        indeterminateSemanticIDs.contains(semanticID)
    }

    static func requiresActionableNextStep(for semanticID: String) -> Bool {
        indeterminateSemanticIDs.contains(semanticID)
    }
}

// MARK: - C21 client admission and package lifecycle semantics

/// Stable meaning identifiers for the closed C21 admission and lifecycle
/// states.  These are document/report semantics, not device or user identity.
enum ClientCapabilityAccessibilityIDV1: String, Codable, CaseIterable, Sendable {
    case screen = "client.capability.screen"
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
        // swiftlint:disable:next force_try
        try! LocalizationKeyV1(rawValue)
    }
}

enum ClientCapabilityAccessibilityPolicyV1 {
    static let semanticIDs = ClientCapabilityAccessibilityIDV1.allCases.map(\.rawValue)
    static let stateSemanticIDs: Set<String> = Set(
        ClientCapabilityAccessibilityIDV1.allCases.filter {
            $0.rawValue.contains(".admission.")
                || $0.rawValue.contains(".reason.")
                || $0.rawValue.contains(".state.")
                || $0.rawValue.contains(".operation.")
                || $0 == .historicExport
                || $0 == .withdrawal
                || $0 == .blocked
        }.map(\.rawValue)
    )
    static let indeterminateSemanticIDs: Set<String> = [
        ClientCapabilityAccessibilityIDV1.admissionMigrationRequired.rawValue,
        ClientCapabilityAccessibilityIDV1.admissionQuarantine.rawValue,
        ClientCapabilityAccessibilityIDV1.admissionReject.rawValue,
        ClientCapabilityAccessibilityIDV1.reasonMigrationAvailable.rawValue,
        ClientCapabilityAccessibilityIDV1.reasonUnknownCapability.rawValue,
        ClientCapabilityAccessibilityIDV1.reasonUnsupportedRequiredRange.rawValue,
        ClientCapabilityAccessibilityIDV1.reasonPackageWithdrawn.rawValue,
        ClientCapabilityAccessibilityIDV1.reasonPackageQuarantined.rawValue,
        ClientCapabilityAccessibilityIDV1.reasonPackageSuperseded.rawValue,
        ClientCapabilityAccessibilityIDV1.reasonDigestMismatch.rawValue,
        ClientCapabilityAccessibilityIDV1.reasonStalePolicy.rawValue,
        ClientCapabilityAccessibilityIDV1.reasonOperationBlocked.rawValue,
        ClientCapabilityAccessibilityIDV1.stateDeprecated.rawValue,
        ClientCapabilityAccessibilityIDV1.stateWithdrawn.rawValue,
        ClientCapabilityAccessibilityIDV1.stateQuarantined.rawValue,
        ClientCapabilityAccessibilityIDV1.stateSuperseded.rawValue,
        ClientCapabilityAccessibilityIDV1.withdrawal.rawValue,
        ClientCapabilityAccessibilityIDV1.blocked.rawValue,
    ]
    static let statusSemanticIDs = stateSemanticIDs
    static let denyByDefault = true
    static let nonColorStateTextRequired = true
    static let textAlternativeRequired = true
    static let textAndIconRequiredForIndeterminateStates = true
    static let actionableNextStepRequiredForIndeterminateStates = true
    static let colorOnlyStateAllowed = false
    static let iconOnlyStateAllowed = false
    static let motionOnlyStateAllowed = false
    static let excludesDeviceIdentity = true
    static let excludesUserIdentity = true
    static let excludesEndpointProviderAccount = true
    static let excludesRemoteDeliveryAcknowledgement = true
    static let rtlRequired = true
    static let dynamicTypeRequired = true
    static let voiceOverRequired = true
    static let voiceControlRequired = true
    static let switchControlRequired = true

    static func requiresTextAndIcon(for semanticID: String) -> Bool {
        indeterminateSemanticIDs.contains(semanticID)
    }

    static func requiresActionableNextStep(for semanticID: String) -> Bool {
        indeterminateSemanticIDs.contains(semanticID)
    }
}

// MARK: - C23 version-bound field-reference semantics

/// Stable semantic IDs for the bounded field-reference report companion.
/// These identify recorded release/binding/readiness meaning only; they are
/// not content locators, subject identities, license notices, or authority
/// claims.
enum FieldReferenceAccessibilityIDV1: String, Codable, CaseIterable, Sendable {
    case screen = "field.reference.screen"
    case heading = "field.reference.heading"
    case provenance = "field.reference.provenance"
    case pack = "field.reference.pack"
    case kind = "field.reference.kind"
    case semanticVersion = "field.reference.semantic-version"
    case release = "field.reference.release"
    case binding = "field.reference.binding"
    case subject = "field.reference.subject"
    case availability = "field.reference.availability"
    case requiredContent = "field.reference.required-content"
    case missingContent = "field.reference.missing-content"
    case releaseActive = "field.reference.release.active"
    case releaseRevoked = "field.reference.release.revoked"
    case subjectActive = "field.reference.subject.active"
    case subjectFinalized = "field.reference.subject.finalized"
    case availabilityReadyOffline = "field.reference.availability.ready-offline"
    case availabilityMissingBytes = "field.reference.availability.missing-bytes"
    case availabilityExpired = "field.reference.availability.expired"
    case availabilityRevoked = "field.reference.availability.revoked"
    case availabilitySuperseded = "field.reference.availability.superseded"
    case availabilityStaleBinding = "field.reference.availability.stale-binding"
    case availabilityProtectedDataUnavailable = "field.reference.availability.protected-data-unavailable"
    case availabilityUnavailable = "field.reference.availability.unavailable"
    case nextStep = "field.reference.next-step"

    var localizationKey: LocalizationKeyV1 {
        let rawValue: String
        switch self {
        case .screen: rawValue = FieldReferenceLocalizationKeyV1.heading.rawValue
        case .heading: rawValue = FieldReferenceLocalizationKeyV1.heading.rawValue
        case .provenance: rawValue = FieldReferenceLocalizationKeyV1.provenance.rawValue
        case .pack: rawValue = FieldReferenceLocalizationKeyV1.pack.rawValue
        case .kind: rawValue = FieldReferenceLocalizationKeyV1.kind.rawValue
        case .semanticVersion: rawValue = FieldReferenceLocalizationKeyV1.semanticVersion.rawValue
        case .release: rawValue = FieldReferenceLocalizationKeyV1.release.rawValue
        case .binding: rawValue = FieldReferenceLocalizationKeyV1.binding.rawValue
        case .subject: rawValue = FieldReferenceLocalizationKeyV1.subject.rawValue
        case .availability: rawValue = FieldReferenceLocalizationKeyV1.availability.rawValue
        case .requiredContent: rawValue = FieldReferenceLocalizationKeyV1.requiredContent.rawValue
        case .missingContent: rawValue = FieldReferenceLocalizationKeyV1.missingContent.rawValue
        case .releaseActive: rawValue = FieldReferenceLocalizationKeyV1.releaseActive.rawValue
        case .releaseRevoked: rawValue = FieldReferenceLocalizationKeyV1.releaseRevoked.rawValue
        case .subjectActive: rawValue = FieldReferenceLocalizationKeyV1.subjectActive.rawValue
        case .subjectFinalized: rawValue = FieldReferenceLocalizationKeyV1.subjectFinalized.rawValue
        case .availabilityReadyOffline: rawValue = FieldReferenceLocalizationKeyV1.availabilityReadyOffline.rawValue
        case .availabilityMissingBytes: rawValue = FieldReferenceLocalizationKeyV1.availabilityMissingBytes.rawValue
        case .availabilityExpired: rawValue = FieldReferenceLocalizationKeyV1.availabilityExpired.rawValue
        case .availabilityRevoked: rawValue = FieldReferenceLocalizationKeyV1.availabilityRevoked.rawValue
        case .availabilitySuperseded: rawValue = FieldReferenceLocalizationKeyV1.availabilitySuperseded.rawValue
        case .availabilityStaleBinding: rawValue = FieldReferenceLocalizationKeyV1.availabilityStaleBinding.rawValue
        case .availabilityProtectedDataUnavailable: rawValue = FieldReferenceLocalizationKeyV1.availabilityProtectedDataUnavailable.rawValue
        case .availabilityUnavailable: rawValue = FieldReferenceLocalizationKeyV1.availabilityUnavailable.rawValue
        case .nextStep: rawValue = FieldReferenceLocalizationKeyV1.nextStep.rawValue
        }
        // swiftlint:disable:next force_try
        return try! LocalizationKeyV1(rawValue)
    }
}

enum FieldReferenceAccessibilityPolicyV1 {
    static let semanticIDs = FieldReferenceAccessibilityIDV1.allCases.map(\.rawValue)
    static let stateSemanticIDs: Set<String> = Set(
        FieldReferenceAccessibilityIDV1.allCases.filter {
            $0.rawValue.contains(".availability.")
                || $0.rawValue.contains(".release.")
                || $0.rawValue.contains(".subject.")
                || $0 == .requiredContent
                || $0 == .missingContent
        }.map(\.rawValue)
    )
    static let indeterminateSemanticIDs: Set<String> = [
        FieldReferenceAccessibilityIDV1.availabilityMissingBytes.rawValue,
        FieldReferenceAccessibilityIDV1.availabilityExpired.rawValue,
        FieldReferenceAccessibilityIDV1.availabilityRevoked.rawValue,
        FieldReferenceAccessibilityIDV1.availabilitySuperseded.rawValue,
        FieldReferenceAccessibilityIDV1.availabilityStaleBinding.rawValue,
        FieldReferenceAccessibilityIDV1.availabilityProtectedDataUnavailable.rawValue,
        FieldReferenceAccessibilityIDV1.availabilityUnavailable.rawValue,
    ]
    static let statusSemanticIDs = stateSemanticIDs
    static let denyByDefault = true
    static let nonColorStateTextRequired = true
    static let textAlternativeRequired = true
    static let textAndIconRequiredForIndeterminateStates = true
    static let actionableNextStepRequiredForIndeterminateStates = true
    static let colorOnlyStateAllowed = false
    static let iconOnlyStateAllowed = false
    static let motionOnlyStateAllowed = false
    static let excludesReferenceBytes = true
    static let excludesPrivateLocators = true
    static let excludesLicenseSecrets = true
    static let excludesSubjectIdentity = true
    static let excludesAuthorityClaims = true

    static func requiresTextAndIcon(for semanticID: String) -> Bool {
        indeterminateSemanticIDs.contains(semanticID)
    }

    static func requiresActionableNextStep(for semanticID: String) -> Bool {
        indeterminateSemanticIDs.contains(semanticID)
    }

    static func availabilityID(_ value: FieldReferenceAvailabilityV1) -> FieldReferenceAccessibilityIDV1 {
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
}

// MARK: - C24 accessible-document semantics

/// Stable semantic IDs for the canonical accessible-document tree.  The IDs
/// describe recorded structure and assessment facts only; they are not
/// conformance claims, evidence locators, or assessor identity.
enum AccessibleDocumentAccessibilityIDV1: String, Codable, CaseIterable, Sendable {
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
}

enum AccessibleDocumentAccessibilityPolicyV1 {
    static let semanticIDs = AccessibleDocumentAccessibilityIDV1.allCases.map(\.rawValue)
    static let stateSemanticIDs: Set<String> = Set([
        AccessibleDocumentAccessibilityIDV1.alternateTextAuthoredForSource,
        AccessibleDocumentAccessibilityIDV1.alternateTextSourceCaption,
        AccessibleDocumentAccessibilityIDV1.alternateTextNotProvided,
        AccessibleDocumentAccessibilityIDV1.decorativeFigure,
        AccessibleDocumentAccessibilityIDV1.describedFigure,
        AccessibleDocumentAccessibilityIDV1.assessmentInternalPass,
        AccessibleDocumentAccessibilityIDV1.assessmentInternalFail,
        AccessibleDocumentAccessibilityIDV1.assessmentIncomplete,
        AccessibleDocumentAccessibilityIDV1.assessmentExternallyProved,
        AccessibleDocumentAccessibilityIDV1.evidenceLimited,
        AccessibleDocumentAccessibilityIDV1.claimBoundary,
    ].map(\.rawValue))
    static let indeterminateSemanticIDs: Set<String> = Set([
        AccessibleDocumentAccessibilityIDV1.alternateTextNotProvided,
        AccessibleDocumentAccessibilityIDV1.assessmentInternalFail,
        AccessibleDocumentAccessibilityIDV1.assessmentIncomplete,
        AccessibleDocumentAccessibilityIDV1.evidenceLimited,
        AccessibleDocumentAccessibilityIDV1.claimBoundary,
    ].map(\.rawValue))
    static let statusSemanticIDs = stateSemanticIDs
    static let denyByDefault = true
    static let nonColorStateTextRequired = true
    static let textAlternativeRequired = true
    static let textAndIconRequiredForIndeterminateStates = true
    static let actionableNextStepRequiredForIndeterminateStates = true
    static let colorOnlyStateAllowed = false
    static let iconOnlyStateAllowed = false
    static let motionOnlyStateAllowed = false
    static let excludesOriginalEvidence = true
    static let excludesPrivateEvidence = true
    static let excludesAssessorIdentity = true
    static let excludesPrivateLocators = true
    static let excludesUnsupportedConformanceClaims = true

    static func requiresTextAndIcon(for semanticID: String) -> Bool {
        indeterminateSemanticIDs.contains(semanticID)
    }

    static func requiresActionableNextStep(for semanticID: String) -> Bool {
        indeterminateSemanticIDs.contains(semanticID)
    }

    static func roleID(
        _ value: AccessibleDocumentRoleV1
    ) -> AccessibleDocumentAccessibilityIDV1 {
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

    static func alternateTextProvenanceID(
        _ value: AccessibleAlternateTextProvenanceV1
    ) -> AccessibleDocumentAccessibilityIDV1 {
        switch value {
        case .authoredForSource: return .alternateTextAuthoredForSource
        case .sourceCaption: return .alternateTextSourceCaption
        case .notProvided: return .alternateTextNotProvided
        }
    }

    static func assessmentStateID(
        _ value: AccessibleDocumentAssessmentStateV1
    ) -> AccessibleDocumentAccessibilityIDV1 {
        switch value {
        case .internalPass: return .assessmentInternalPass
        case .internalFail: return .assessmentInternalFail
        case .incomplete: return .assessmentIncomplete
        case .externallyProved: return .assessmentExternallyProved
        }
    }
}

// MARK: - C27 asset-locator semantics

/// Stable semantic IDs for the C27 locator report companion.  These IDs
/// identify recorded metadata and offline resolution states; they do not
/// expose the opaque input or imply access, identity, or delivery.
enum AssetLocatorAccessibilityIDV1: String, Codable, CaseIterable, Sendable {
    case screen = "asset.locator.screen"
    case heading = "asset.locator.heading"
    case resolution = "asset.locator.resolution"
    case representation = "asset.locator.representation"
    case representationLocalSigned = "asset.locator.representation.local_signed"
    case representationExternalKey = "asset.locator.representation.external_key"
    case representationUnavailable = "asset.locator.representation.unavailable"
    case outcome = "asset.locator.outcome"
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
        let rawValue: String
        switch self {
        case .screen, .heading: rawValue = AssetLocatorLocalizationKeyV1.heading.rawValue
        case .resolution: rawValue = AssetLocatorLocalizationKeyV1.resolution.rawValue
        case .representation: rawValue = AssetLocatorLocalizationKeyV1.representation.rawValue
        case .representationLocalSigned: rawValue = AssetLocatorLocalizationKeyV1.representationLocalSigned.rawValue
        case .representationExternalKey: rawValue = AssetLocatorLocalizationKeyV1.representationExternalKey.rawValue
        case .representationUnavailable: rawValue = AssetLocatorLocalizationKeyV1.representationUnavailable.rawValue
        case .outcome: rawValue = AssetLocatorLocalizationKeyV1.resolution.rawValue
        case .outcomeMatched: rawValue = AssetLocatorLocalizationKeyV1.outcomeMatched.rawValue
        case .outcomeNoMatch: rawValue = AssetLocatorLocalizationKeyV1.outcomeNoMatch.rawValue
        case .outcomeForeignWorkspace: rawValue = AssetLocatorLocalizationKeyV1.outcomeForeignWorkspace.rawValue
        case .outcomeAmbiguous: rawValue = AssetLocatorLocalizationKeyV1.outcomeAmbiguous.rawValue
        case .outcomeDamagedOrIncomplete: rawValue = AssetLocatorLocalizationKeyV1.outcomeDamagedOrIncomplete.rawValue
        case .outcomeRetired: rawValue = AssetLocatorLocalizationKeyV1.outcomeRetired.rawValue
        case .outcomeRevoked: rawValue = AssetLocatorLocalizationKeyV1.outcomeRevoked.rawValue
        case .outcomeReplaced: rawValue = AssetLocatorLocalizationKeyV1.outcomeReplaced.rawValue
        case .lifecycle: rawValue = AssetLocatorLocalizationKeyV1.lifecycle.rawValue
        case .stateActive: rawValue = AssetLocatorLocalizationKeyV1.stateActive.rawValue
        case .stateRetired: rawValue = AssetLocatorLocalizationKeyV1.stateRetired.rawValue
        case .stateRevoked: rawValue = AssetLocatorLocalizationKeyV1.stateRevoked.rawValue
        case .stateReplaced: rawValue = AssetLocatorLocalizationKeyV1.stateReplaced.rawValue
        case .stateUnavailable: rawValue = AssetLocatorLocalizationKeyV1.stateUnavailable.rawValue
        case .claimBoundary: rawValue = AssetLocatorLocalizationKeyV1.claimBoundary.rawValue
        case .nextStep: rawValue = AssetLocatorLocalizationKeyV1.nextStep.rawValue
        }
        // swiftlint:disable:next force_try
        return try! LocalizationKeyV1(rawValue)
    }
}

enum AssetLocatorAccessibilityPolicyV1 {
    static let semanticIDs = AssetLocatorAccessibilityIDV1.allCases.map(\.rawValue)
    static let stateSemanticIDs: Set<String> = Set([
        AssetLocatorAccessibilityIDV1.stateActive,
        AssetLocatorAccessibilityIDV1.stateRetired,
        AssetLocatorAccessibilityIDV1.stateRevoked,
        AssetLocatorAccessibilityIDV1.stateReplaced,
        AssetLocatorAccessibilityIDV1.stateUnavailable,
        AssetLocatorAccessibilityIDV1.outcomeMatched,
        AssetLocatorAccessibilityIDV1.outcomeNoMatch,
        AssetLocatorAccessibilityIDV1.outcomeForeignWorkspace,
        AssetLocatorAccessibilityIDV1.outcomeAmbiguous,
        AssetLocatorAccessibilityIDV1.outcomeDamagedOrIncomplete,
        AssetLocatorAccessibilityIDV1.outcomeRetired,
        AssetLocatorAccessibilityIDV1.outcomeRevoked,
        AssetLocatorAccessibilityIDV1.outcomeReplaced,
    ].map(\.rawValue))
    static let indeterminateSemanticIDs: Set<String> = Set([
        AssetLocatorAccessibilityIDV1.outcomeNoMatch,
        AssetLocatorAccessibilityIDV1.outcomeForeignWorkspace,
        AssetLocatorAccessibilityIDV1.outcomeAmbiguous,
        AssetLocatorAccessibilityIDV1.outcomeDamagedOrIncomplete,
        AssetLocatorAccessibilityIDV1.outcomeRetired,
        AssetLocatorAccessibilityIDV1.outcomeRevoked,
        AssetLocatorAccessibilityIDV1.outcomeReplaced,
        AssetLocatorAccessibilityIDV1.stateUnavailable,
    ].map(\.rawValue))
    static let statusSemanticIDs = stateSemanticIDs
    static let denyByDefault = true
    static let nonColorStateTextRequired = true
    static let textAlternativeRequired = true
    static let textAndIconRequiredForIndeterminateStates = true
    static let actionableNextStepRequiredForIndeterminateStates = true
    static let colorOnlyStateAllowed = false
    static let iconOnlyStateAllowed = false
    static let motionOnlyStateAllowed = false
    static let excludesOpaqueInput = true
    static let excludesPrivateKeyMaterial = true
    static let excludesSecrets = true
    static let excludesVendorIdentifiers = true
    static let excludesPermissionClaims = true
    static let excludesNetworkResolutionClaims = true

    static func requiresTextAndIcon(for semanticID: String) -> Bool {
        indeterminateSemanticIDs.contains(semanticID)
    }

    static func requiresActionableNextStep(for semanticID: String) -> Bool {
        indeterminateSemanticIDs.contains(semanticID)
    }

    static func outcomeID(_ value: LocatorResolutionOutcomeV1) -> AssetLocatorAccessibilityIDV1 {
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

    static func stateID(_ value: AssetLocatorStateV1?) -> AssetLocatorAccessibilityIDV1 {
        guard let value else { return .stateUnavailable }
        switch value {
        case .active: return .stateActive
        case .retired: return .stateRetired
        case .revoked: return .stateRevoked
        case .replaced: return .stateReplaced
        }
    }

    static func representationID(_ value: AssetLocatorRepresentationV1?) -> AssetLocatorAccessibilityIDV1 {
        guard let value else { return .representationUnavailable }
        switch value {
        case .localSigned: return .representationLocalSigned
        case .externalKey: return .representationExternalKey
        }
    }
}

// MARK: - C28 schedule and occurrence accessibility

/// Stable semantic identifiers for the schedule projection. They describe
/// recorded facts and safe next steps; they are not route names or localized
/// display strings.
enum ScheduleAccessibilityIDV1: String, Codable, CaseIterable, Sendable {
    case screen = "schedule.screen"
    case heading = "schedule.heading"
    case definition = "schedule.definition"
    case occurrence = "schedule.occurrence"
    case occurrenceState = "schedule.occurrence.state"
    case timeBasis = "schedule.time_basis"
    case history = "schedule.history"
    case dueQueue = "schedule.due_queue"
    case reminder = "schedule.reminder"
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
        let key: ScheduleLocalizationKeyV1
        switch self {
        case .screen: key = .heading
        case .heading: key = .heading
        case .definition: key = .definition
        case .occurrence: key = .occurrence
        case .occurrenceState: key = .occurrenceState
        case .timeBasis: key = .timeBasis
        case .history: key = .history
        case .dueQueue: key = .dueQueue
        case .reminder: key = .reminder
        case .claimBoundary: key = .claimBoundary
        case .nextStep: key = .nextStep
        case .advancedRecurrence: key = .advancedRecurrence
        case .exceptionCalendar: key = .exceptionCalendar
        case .calendarRelease: key = .calendarRelease
        case .businessDayAdjustment: key = .businessDayAdjustment
        case .completionGap: key = .completionGap
        case .nominalBasis: key = .nominalBasis
        case .effectiveBasis: key = .effectiveBasis
        case .occurrenceLineage: key = .occurrenceLineage
        case .scheduleOverride: key = .scheduleOverride
        case .overridePrecedence: key = .overridePrecedence
        case .changePreview: key = .changePreview
        case .previewNotApplied: key = .previewNotApplied
        case .changeConflict: key = .changeConflict
        case .manualResolutionRequired: key = .manualResolutionRequired
        case .recovery: key = .recovery
        case .recoveryRebuilt: key = .recoveryRebuilt
        case .stateUpcoming: key = .stateUpcoming
        case .stateReady: key = .stateReady
        case .stateDue: key = .stateDue
        case .stateOverdue: key = .stateOverdue
        case .stateDeferred: key = .stateDeferred
        case .stateMissed: key = .stateMissed
        case .stateSkipped: key = .stateSkipped
        case .stateCancelled: key = .stateCancelled
        case .stateStarted: key = .stateStarted
        case .stateCompleted: key = .stateCompleted
        }
        return key.localizationKey
    }
}

enum ScheduleAccessibilityPolicyV1 {
    static let semanticIDs = ScheduleAccessibilityIDV1.allCases.map(\.rawValue)
    static let stateSemanticIDs: Set<String> = Set(
        [ScheduleAccessibilityIDV1](
            [
                .stateUpcoming, .stateReady, .stateDue, .stateOverdue,
                .stateDeferred, .stateMissed, .stateSkipped, .stateCancelled,
                .stateStarted, .stateCompleted,
            ]
        ).map(\.rawValue)
    )
    static let indeterminateSemanticIDs: Set<String> = Set(
        [ScheduleAccessibilityIDV1](
            [
                .stateUpcoming, .stateReady, .stateDue, .stateOverdue,
                .stateDeferred, .stateMissed, .stateSkipped, .stateCancelled,
            ]
        ).map(\.rawValue)
    )
    static let denyByDefault = true
    static let nonColorStateTextRequired = true
    static let textAlternativeRequired = true
    static let textAndIconRequiredForIndeterminateStates = true
    static let actionableNextStepRequiredForIndeterminateStates = true
    static let colorOnlyStateAllowed = false
    static let iconOnlyStateAllowed = false
    static let motionOnlyStateAllowed = false
    /// These are typed consumer requirements for a later UI implementation;
    /// C51 does not claim that an FJ07 screen exists or has been exercised.
    static let accessibilityContractDeclared = true
    static let rtlReadingOrderRequired = true
    static let dynamicTypeRequired = true
    static let voiceOverLabelAndValueRequired = true
    static let voiceControlStableNameRequired = true
    static let switchControlReachabilityRequired = true
    static let uiConformanceClaimed = false

    static func requiresTextAndIcon(for semanticID: String) -> Bool {
        indeterminateSemanticIDs.contains(semanticID)
    }

    static func requiresActionableNextStep(for semanticID: String) -> Bool {
        indeterminateSemanticIDs.contains(semanticID)
    }

    static func stateID(_ value: OccurrenceStateV1) -> ScheduleAccessibilityIDV1 {
        switch value {
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
}

// MARK: - C29 plan and rebase accessibility

/// Stable semantic identifiers for the plan/rebase projection. They expose
/// recorded document, placement, warning, and receipt facts without making
/// an unapplied preview sound like verified or applied truth.
enum PlanAccessibilityIDV1: String, Codable, CaseIterable, Sendable {
    case screen = "plan.screen"
    case heading = "plan.heading"
    case document = "plan.document"
    case revision = "plan.revision"
    case revisionState = "plan.revision.state"
    case placement = "plan.placement"
    case placementDisposition = "plan.placement.disposition"
    case coordinate = "plan.coordinate"
    case reference = "plan.reference"
    case contentBinding = "plan.content.binding"
    case spatialFrame = "plan.spatial.frame"
    case rebasePreview = "plan.rebase.preview"
    case rebaseReceipt = "plan.rebase.receipt"
    case rebaseDecision = "plan.rebase.decision"
    case rebaseWarning = "plan.rebase.warning"
    case rebaseComponent = "plan.rebase.component"
    case residual = "plan.rebase.residual"
    case expectedRevision = "plan.rebase.expected_revision"
    case historyImmutable = "plan.history.immutable"
    case previewNotApplied = "plan.rebase.preview.not_applied"
    case claimBoundary = "plan.claim_boundary"
    case nextStep = "plan.next_step"

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
        let key: PlanLocalizationKeyV1
        switch self {
        case .screen, .heading: key = .planHeading
        case .document: key = .planDocument
        case .revision: key = .planRevision
        case .revisionState: key = .planRevisionState
        case .placement: key = .planPlacement
        case .placementDisposition: key = .planPlacementDisposition
        case .coordinate: key = .planCoordinate
        case .reference: key = .planReference
        case .contentBinding: key = .planContentBinding
        case .spatialFrame: key = .planSpatialFrame
        case .rebasePreview: key = .planRebasePreview
        case .rebaseReceipt: key = .planRebaseReceipt
        case .rebaseDecision: key = .planRebaseDecision
        case .rebaseWarning: key = .planRebaseWarning
        case .rebaseComponent: key = .planRebaseComponent
        case .residual: key = .planResidual
        case .expectedRevision: key = .planExpectedRevision
        case .historyImmutable: key = .planHistoryImmutable
        case .previewNotApplied: key = .planPreviewNotApplied
        case .claimBoundary: key = .planClaimBoundary
        case .nextStep: key = .planNextStep
        case .documentActive: key = .documentActive
        case .documentRetired: key = .documentRetired
        case .revisionDraft: key = .revisionDraft
        case .revisionReleased: key = .revisionReleased
        case .revisionWithdrawn: key = .revisionWithdrawn
        case .placementAccepted: key = .placementAccepted
        case .placementReviewRequired: key = .placementReviewRequired
        case .placementOrphaned: key = .placementOrphaned
        case .placementOutOfBounds: key = .placementOutOfBounds
        case .decisionApplyRecorded: key = .decisionApplyRecorded
        case .decisionRejectRecorded: key = .decisionRejectRecorded
        case .warningPageMissing: key = .warningPageMissing
        case .warningPageReordered: key = .warningPageReordered
        case .warningOutOfBounds: key = .warningOutOfBounds
        case .warningOrphanedAnchor: key = .warningOrphanedAnchor
        case .warningResidualExceeded: key = .warningResidualExceeded
        case .warningCalibrationUnavailable: key = .warningCalibrationUnavailable
        case .warningComponentReviewRequired: key = .warningComponentReviewRequired
        case .errorStalePreview: key = .errorStalePreview
        case .errorWrongReference: key = .errorWrongReference
        case .errorComponentConflict: key = .errorComponentConflict
        case .errorReviewRequired: key = .errorReviewRequired
        case .errorInvalidDigest: key = .errorInvalidDigest
        }
        // swiftlint:disable:next force_try
        return try! LocalizationKeyV1(key.rawValue)
    }
}

enum PlanAccessibilityPolicyV1 {
    static let semanticIDs = PlanAccessibilityIDV1.allCases.map(\.rawValue)
    static let stateSemanticIDs: Set<String> = Set(
        [PlanAccessibilityIDV1]([
            .documentActive, .documentRetired,
            .revisionDraft, .revisionReleased, .revisionWithdrawn,
            .placementAccepted, .placementReviewRequired,
            .placementOrphaned, .placementOutOfBounds,
            .decisionApplyRecorded, .decisionRejectRecorded,
        ]).map(\.rawValue)
    )
    static let indeterminateSemanticIDs: Set<String> = Set(
        [PlanAccessibilityIDV1]([
            .placementReviewRequired, .placementOrphaned, .placementOutOfBounds,
            .warningPageMissing, .warningPageReordered, .warningOutOfBounds,
            .warningOrphanedAnchor, .warningResidualExceeded,
            .warningCalibrationUnavailable, .warningComponentReviewRequired,
            .errorStalePreview, .errorWrongReference, .errorComponentConflict,
            .errorReviewRequired, .errorInvalidDigest,
        ]).map(\.rawValue)
    )
    static let denyByDefault = true
    static let nonColorStateTextRequired = true
    static let textAlternativeRequired = true
    static let textAndIconRequiredForIndeterminateStates = true
    static let actionableNextStepRequiredForIndeterminateStates = true
    static let colorOnlyStateAllowed = false
    static let iconOnlyStateAllowed = false
    static let motionOnlyStateAllowed = false

    static func requiresTextAndIcon(for semanticID: String) -> Bool {
        indeterminateSemanticIDs.contains(semanticID)
    }

    static func requiresActionableNextStep(for semanticID: String) -> Bool {
        indeterminateSemanticIDs.contains(semanticID)
    }

    static func documentStateID(_ state: PlanDocumentStateV1) -> PlanAccessibilityIDV1 {
        switch state {
        case .active: return .documentActive
        case .retired: return .documentRetired
        }
    }

    static func revisionStateID(_ state: PlanRevisionStateV1) -> PlanAccessibilityIDV1 {
        switch state {
        case .draft: return .revisionDraft
        case .released: return .revisionReleased
        case .withdrawn: return .revisionWithdrawn
        }
    }

    static func placementDispositionID(
        _ disposition: PlanPlacementDispositionV1
    ) -> PlanAccessibilityIDV1 {
        switch disposition {
        case .accepted: return .placementAccepted
        case .reviewRequired: return .placementReviewRequired
        case .orphaned: return .placementOrphaned
        case .outOfBounds: return .placementOutOfBounds
        }
    }

    static func warningID(_ warning: PlanRebaseWarningCodeV1) -> PlanAccessibilityIDV1 {
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

// MARK: - C37 reference-framed pose accessibility

/// Stable semantic IDs for the C37 projection. They name recorded facts and
/// recovery states rather than claiming a pose is aligned, accurate, or
/// compliant. State IDs are spoken as text and are never color/icon-only.
enum C37PlacementPoseAccessibilityIDV1: String, Codable, CaseIterable, Sendable {
    case screen = "pose.screen"
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
        let key: C37PoseLocalizationKeyV1
        switch self {
        case .screen, .heading: key = .heading
        case .axis: key = .axis
        case .current: key = .current
        case .history: key = .history
        case .referenceFrame: key = .referenceFrame
        case .referenceTrue: key = .referenceTrue
        case .referenceMagnetic: key = .referenceMagnetic
        case .referencePlanRelative: key = .referencePlanRelative
        case .referenceUnknown: key = .referenceUnknown
        case .observation: key = .observation
        case .observed: key = .observed
        case .notObserved: key = .notObserved
        case .manualFallback: key = .manualFallback
        case .uncertainty: key = .uncertainty
        case .uncertaintyKnown: key = .uncertaintyKnown
        case .uncertaintyUnknown: key = .uncertaintyUnknown
        case .notObservedReason: key = .notObservedReason
        case .reasonNotYetObserved: key = .reasonNotYetObserved
        case .reasonPhysicalMove: key = .reasonPhysicalMove
        case .reasonPlanFrameLost: key = .reasonPlanFrameLost
        case .reasonObscured: key = .reasonObscured
        case .reasonSourceUnavailable: key = .reasonSourceUnavailable
        case .reasonUserDeclined: key = .reasonUserDeclined
        case .currentTip: key = .currentTip
        case .historyFrozen: key = .historyFrozen
        case .rebasePreview: key = .rebasePreview
        case .previewNotApplied: key = .previewNotApplied
        case .reviewRequired: key = .reviewRequired
        case .azimuth: key = .azimuth
        case .elevation: key = .elevation
        case .horizontalUncertainty: key = .horizontalUncertainty
        case .verticalUncertainty: key = .verticalUncertainty
        case .recordedSource: key = .recordedSource
        case .claimBoundary: key = .claimBoundary
        case .nextStep: key = .nextStep
        case .missing: key = .missing
        }
        return key.localizationKey
    }
}

enum C37PoseAccessibilityPolicyV1 {
    static let semanticIDs = C37PlacementPoseAccessibilityIDV1.allCases.map(\.rawValue)
    static let stateSemanticIDs: Set<String> = Set([
        C37PlacementPoseAccessibilityIDV1.referenceTrue,
        .referenceMagnetic, .referencePlanRelative, .referenceUnknown,
        .observed, .notObserved, .manualFallback, .uncertaintyKnown,
        .uncertaintyUnknown, .historyFrozen, .previewNotApplied,
        .reviewRequired, .missing,
    ].map(\.rawValue))
    static let indeterminateSemanticIDs: Set<String> = Set([
        C37PlacementPoseAccessibilityIDV1.notObserved,
        .manualFallback, .referenceUnknown, .uncertaintyUnknown,
        .previewNotApplied, .reviewRequired, .missing,
        .reasonNotYetObserved, .reasonPhysicalMove, .reasonPlanFrameLost,
        .reasonObscured, .reasonSourceUnavailable, .reasonUserDeclined,
    ].map(\.rawValue))
    static let denyByDefault = true
    static let nonColorStateTextRequired = true
    static let textAlternativeRequired = true
    static let textAndIconRequiredForIndeterminateStates = true
    static let actionableNextStepRequiredForIndeterminateStates = true
    static let colorOnlyStateAllowed = false
    static let iconOnlyStateAllowed = false
    static let motionOnlyStateAllowed = false
    static let sensorStreamStored = false
    static let networkInputUsed = false

    static func requiresTextAndIcon(for semanticID: String) -> Bool {
        indeterminateSemanticIDs.contains(semanticID)
    }

    static func requiresActionableNextStep(for semanticID: String) -> Bool {
        indeterminateSemanticIDs.contains(semanticID)
    }

    static func referenceFrameID(
        _ value: C37PoseReferenceFrameProjectionV1
    ) -> C37PlacementPoseAccessibilityIDV1 {
        switch value {
        case .trueBearing: return .referenceTrue
        case .magneticBearing: return .referenceMagnetic
        case .planRelative: return .referencePlanRelative
        case .unknown: return .referenceUnknown
        }
    }

    static func observationStateID(
        _ value: C37PoseObservationStateV1
    ) -> C37PlacementPoseAccessibilityIDV1 {
        switch value {
        case .observed: return .observed
        case .notObserved: return .notObserved
        case .manualFallback: return .manualFallback
        case .uncertaintyUnknown: return .uncertaintyUnknown
        case .reviewRequired: return .reviewRequired
        }
    }
}
// MARK: - C30 operating-context accessibility

/// Stable semantic IDs for the C30 context projection.  Condition and
/// comparison states are spoken as text and are never conveyed by color,
/// glyph, motion, or a claim about actual equipment behavior.
enum C30OperatingContextAccessibilityIDV1: String, Codable, CaseIterable, Sendable {
    case screen = "evidence.context.screen"
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
        switch self {
        case .screen, .heading: return C30OperatingContextLocalizationKeyV1.heading.localizationKey
        case .condition: return C30OperatingContextLocalizationKeyV1.condition.localizationKey
        case .daylight: return C30OperatingContextLocalizationKeyV1.daylight.localizationKey
        case .civilTwilight: return C30OperatingContextLocalizationKeyV1.civilTwilight.localizationKey
        case .night: return C30OperatingContextLocalizationKeyV1.night.localizationKey
        case .coveredDay: return C30OperatingContextLocalizationKeyV1.coveredDay.localizationKey
        case .coveredNight: return C30OperatingContextLocalizationKeyV1.coveredNight.localizationKey
        case .conditionUnknown: return C30OperatingContextLocalizationKeyV1.conditionUnknown.localizationKey
        case .userObserved: return C30OperatingContextLocalizationKeyV1.userObserved.localizationKey
        case .solarDerived: return C30OperatingContextLocalizationKeyV1.solarDerived.localizationKey
        case .temporalBasis: return C30OperatingContextLocalizationKeyV1.temporalBasis.localizationKey
        case .expectedControl: return C30OperatingContextLocalizationKeyV1.expectedControl.localizationKey
        case .expectedOperating: return C30OperatingContextLocalizationKeyV1.expectedOperating.localizationKey
        case .expectedNotOperating: return C30OperatingContextLocalizationKeyV1.expectedNotOperating.localizationKey
        case .expectedNone: return C30OperatingContextLocalizationKeyV1.expectedNone.localizationKey
        case .pairedComparison: return C30OperatingContextLocalizationKeyV1.pairedComparison.localizationKey
        case .pairedComparable: return C30OperatingContextLocalizationKeyV1.pairedComparable.localizationKey
        case .pairedMismatch: return C30OperatingContextLocalizationKeyV1.pairedMismatch.localizationKey
        case .pairedNotLinked: return C30OperatingContextLocalizationKeyV1.pairedNotLinked.localizationKey
        case .pairedMismatchReason: return C30OperatingContextLocalizationKeyV1.pairedMismatchReason.localizationKey
        case .historyFrozen: return C30OperatingContextLocalizationKeyV1.historyFrozen.localizationKey
        case .claimBoundary: return C30OperatingContextLocalizationKeyV1.claimBoundary.localizationKey
        case .nextStep: return C30OperatingContextLocalizationKeyV1.nextStep.localizationKey
        case .manualOffline: return C30OperatingContextLocalizationKeyV1.manualOffline.localizationKey
        case .derivedCondition: return C30OperatingContextLocalizationKeyV1.derivedCondition.localizationKey
        }
    }
}

enum C30OperatingContextAccessibilityPolicyV1 {
    static let textAndIconRequired = true
    static let stateIsNotColorOnly = true
    static let nextStepIsActionable = true
    static let screenUsesHeading = true
    static let sensorAndNetworkClaimsExcluded = true
    static let operationalFailureAndComplianceClaimsExcluded = true

    static let stateSemanticIDs: Set<String> = [
        C30OperatingContextAccessibilityIDV1.daylight.rawValue,
        C30OperatingContextAccessibilityIDV1.civilTwilight.rawValue,
        C30OperatingContextAccessibilityIDV1.night.rawValue,
        C30OperatingContextAccessibilityIDV1.coveredDay.rawValue,
        C30OperatingContextAccessibilityIDV1.coveredNight.rawValue,
        C30OperatingContextAccessibilityIDV1.conditionUnknown.rawValue,
        C30OperatingContextAccessibilityIDV1.pairedComparable.rawValue,
        C30OperatingContextAccessibilityIDV1.pairedMismatch.rawValue,
        C30OperatingContextAccessibilityIDV1.pairedNotLinked.rawValue,
    ]

    static func requiresActionableNextStep(for id: String) -> Bool {
        id == C30OperatingContextAccessibilityIDV1.nextStep.rawValue
            || id == C30OperatingContextAccessibilityIDV1.pairedMismatch.rawValue
            || id == C30OperatingContextAccessibilityIDV1.conditionUnknown.rawValue
    }

    static func validate() throws {
        guard textAndIconRequired, stateIsNotColorOnly, nextStepIsActionable,
              screenUsesHeading, sensorAndNetworkClaimsExcluded,
              operationalFailureAndComplianceClaimsExcluded,
              C30OperatingContextAccessibilityIDV1.allCases.contains(where: {
                  $0 == .screen
              }),
              C30OperatingContextAccessibilityIDV1.allCases
                .filter({ $0 != .screen })
                .allSatisfy({ !$0.localizationKey.rawValue.isEmpty }) else {
            throw LocalizationContractFailureV1.invalidAccessibilityBinding
        }
    }
}
// C30: this seam consumes only the frozen, metadata-only operating-context projection.
enum C30ConsumerBoundaryV1_Domain_Accessibility_SemanticAccessibilityContractsV1 {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Domain/Accessibility/SemanticAccessibilityContractsV1.swift", role: .accessibility)
}

// MARK: - C31 exterior/parking-lighting accessibility

/// Stable semantic IDs paired with the C31 English-only labels.  Every
/// indeterminate or stop state has spoken text, a non-color state, and an
/// actionable next step; no icon, motion, or color is the sole signal.
enum C31LightingAccessibilityIDV1: String, Codable, CaseIterable, Sendable {
    case screen = "lighting.screen"
    case heading = "lighting.heading"
    case topology = "lighting.topology"
    case observation = "lighting.observation"
    case issue = "lighting.issue"
    case measurement = "lighting.measurement"
    case calibration = "lighting.calibration"
    case claim = "lighting.claim"
    case claimBoundary = "lighting.claim.boundary"
    case safetyStop = "lighting.safety.stop"
    case nextStep = "lighting.safety.next_step"
    case historyFrozen = "lighting.history.frozen"
    case manualOffline = "lighting.manual_offline"

    var localizationKey: LocalizationKeyV1 {
        switch self {
        case .screen, .heading: return C31LightingLocalizationKeyV1.systemHeading.localizationKey
        case .topology: return C31LightingLocalizationKeyV1.topology.localizationKey
        case .observation: return C31LightingLocalizationKeyV1.observationHeading.localizationKey
        case .issue: return C31LightingLocalizationKeyV1.issueRecorded.localizationKey
        case .measurement: return C31LightingLocalizationKeyV1.measurementHeading.localizationKey
        case .calibration: return C31LightingLocalizationKeyV1.calibration.localizationKey
        case .claim: return C31LightingLocalizationKeyV1.claimUnavailable.localizationKey
        case .claimBoundary: return C31LightingLocalizationKeyV1.claimBoundary.localizationKey
        case .safetyStop: return C31LightingLocalizationKeyV1.safetyStop.localizationKey
        case .nextStep: return C31LightingLocalizationKeyV1.safetyNextStep.localizationKey
        case .historyFrozen: return C31LightingLocalizationKeyV1.historyFrozen.localizationKey
        case .manualOffline: return C31LightingLocalizationKeyV1.manualOffline.localizationKey
        }
    }
}

enum C31LightingAccessibilityPolicyV1 {
    static let textAndIconRequired = true
    static let stateIsNotColorOnly = true
    static let iconOnlyStateAllowed = false
    static let motionOnlyStateAllowed = false
    static let actionableNextStepRequired = true
    static let historicDisplayFrozen = true
    static let actorIdentityExcluded = true
    static let operationalSafetySecurityComplianceClaimsExcluded = true
    static let stateSemanticIDs: Set<String> = [
        C31LightingAccessibilityIDV1.issue.rawValue,
        C31LightingAccessibilityIDV1.claim.rawValue,
        C31LightingAccessibilityIDV1.claimBoundary.rawValue,
        C31LightingAccessibilityIDV1.safetyStop.rawValue,
        C31LightingAccessibilityIDV1.historyFrozen.rawValue,
        C31LightingAccessibilityIDV1.manualOffline.rawValue,
    ]

    static func requiresActionableNextStep(for id: String) -> Bool {
        id == C31LightingAccessibilityIDV1.safetyStop.rawValue
            || id == C31LightingAccessibilityIDV1.claim.rawValue
            || id == C31LightingAccessibilityIDV1.claimBoundary.rawValue
    }

    static func validate() throws {
        guard textAndIconRequired, stateIsNotColorOnly,
              !iconOnlyStateAllowed, !motionOnlyStateAllowed,
              actionableNextStepRequired, historicDisplayFrozen,
              actorIdentityExcluded,
              operationalSafetySecurityComplianceClaimsExcluded,
              C31LightingAccessibilityIDV1.allCases.allSatisfy({
                  !$0.localizationKey.rawValue.isEmpty
              }) else {
            throw LocalizationContractFailureV1.invalidAccessibilityBinding
        }
    }
}

// MARK: - C32 assistance review accessibility

enum C32AssistanceAccessibilityIDV1: String, CaseIterable, Codable, Sendable {
    case unverified = "assistance.proposal.unverified"
    case review = "assistance.proposal.review"
    case accept = "assistance.proposal.accept"
    case reject = "assistance.proposal.reject"
    case expired = "assistance.proposal.expired"
    case manualAvailable = "assistance.manual.available"
    case permissionDenied = "assistance.permission.denied"
    case interrupted = "assistance.interrupted"

    var localizationKey: LocalizationKeyV1 {
        // Accessibility semantics reuse the exact visible C32 review labels.
        // swiftlint:disable:next force_try
        try! LocalizationKeyV1(rawValue)
    }
}

enum C32AssistanceAccessibilityPolicyV1 {
    static let proposalStateHasSpokenUnverifiedText = true
    static let explicitReviewControlRequired = true
    static let acceptAndRejectAreDistinctActions = true
    static let manualFallbackRemainsFocusable = true
    static let permissionAndInterruptionHaveText = true
    static let colorOnlyStateAllowed = false
    static let motionOnlyStateAllowed = false

    static func requiresActionableNextStep(
        for id: C32AssistanceAccessibilityIDV1
    ) -> Bool {
        [.expired, .permissionDenied, .interrupted].contains(id)
    }

    static func validate() throws {
        let values = C32AssistanceAccessibilityIDV1.allCases
        guard values.map(\.rawValue).count == Set(values.map(\.rawValue)).count,
              values.allSatisfy({ !$0.localizationKey.rawValue.isEmpty }),
              proposalStateHasSpokenUnverifiedText,
              explicitReviewControlRequired,
              acceptAndRejectAreDistinctActions,
              manualFallbackRemainsFocusable,
              permissionAndInterruptionHaveText,
              !colorOnlyStateAllowed,
              !motionOnlyStateAllowed,
              requiresActionableNextStep(for: .expired),
              requiresActionableNextStep(for: .permissionDenied),
              requiresActionableNextStep(for: .interrupted) else {
            throw LocalizationContractFailureV1.invalidAccessibilityBinding
        }
    }
}


// MARK: - C33 temporal evidence accessibility

enum TemporalEvidenceAccessibilityIDV1: String, CaseIterable, Codable, Sendable {
    case reviewRequired = "temporal_evidence.review_required"
    case playback = "temporal_evidence.playback"
    case duration = "temporal_evidence.duration"
    case anchor = "temporal_evidence.anchor"
    case description = "temporal_evidence.description"
    case transcript = "temporal_evidence.transcript"
    case stoppedAtLimit = "temporal_evidence.stopped_at_limit"
    case permissionDenied = "temporal_evidence.permission.denied"
    case interrupted = "temporal_evidence.interrupted"
    case manualImport = "temporal_evidence.manual_import"
}

enum TemporalEvidenceAccessibilityPolicyV1 {
    static let playbackControlsAreNamed = true
    static let elapsedAndAnchorTimesAreSpoken = true
    static let stateIsNotColorOnly = true
    static let motionOnlyStateAllowed = false
    static let manualFallbackRemainsFocusable = true
    static let interruptionHasActionableRecovery = true

    static func validate() throws {
        let ids = TemporalEvidenceAccessibilityIDV1.allCases.map(\.rawValue)
        guard ids.count == Set(ids).count, playbackControlsAreNamed,
              elapsedAndAnchorTimesAreSpoken, stateIsNotColorOnly,
              !motionOnlyStateAllowed, manualFallbackRemainsFocusable,
              interruptionHasActionableRecovery else {
            throw LocalizationContractFailureV1.invalidAccessibilityBinding
        }
    }
}

enum AssetLabelAccessibilityIDV1: String, CaseIterable, Sendable {
    case preview = "asset_label.preview"
    case shortCode = "asset_label.short_code"
    case position = "asset_label.position"
    case start = "asset_label.start"
    case status = "asset_label.status"
    case structuredText = "asset_label.structured_text"
}

enum AssetLabelAccessibilityPolicyV1 {
    static let shortCodeIsSpokenCharacterByCharacter = true
    static let rowAndColumnAreSpoken = true
    static let stateIsNotColorOnly = true
    static let previewHasTextCompanion = true
    static let explicitStartIsFocusable = true
    static let qrImageHasNoStandaloneMeaning = true
    static func validate() throws {
        let ids = AssetLabelAccessibilityIDV1.allCases.map(\.rawValue)
        guard ids.count == Set(ids).count, shortCodeIsSpokenCharacterByCharacter,
              rowAndColumnAreSpoken, stateIsNotColorOnly, previewHasTextCompanion,
              explicitStartIsFocusable, qrImageHasNoStandaloneMeaning else {
            throw LocalizationContractFailureV1.invalidAccessibilityBinding
        }
    }
}

// MARK: - C46 explicit operational handoff accessibility

enum OperationalContactAccessibilityIDV1: String, CaseIterable, Codable, Sendable {
    case directions = "operational_contact.action.directions"
    case call = "operational_contact.action.call"
    case text = "operational_contact.action.text"
    case email = "operational_contact.action.email"
    case status = "operational_contact.handoff.status"
    case claimBoundary = "operational_contact.handoff.claim_boundary"
}

enum OperationalContactAccessibilityPolicyV1 {
    static let selectedContactLabelIsSpoken = true
    static let actionAndSystemAppHintAreDistinct = true
    static let statusIsNotColorOnly = true
    static let explicitActivationIsRequired = true
    static let historicIntentIsFocusableButNotActionable = true
    static let sentDeliveredConnectedOrArrivalClaimAllowed = false

    static func localizationKey(
        for id: OperationalContactAccessibilityIDV1
    ) -> OperationalContactLocalizationKeyV1 {
        switch id {
        case .directions: .directions
        case .call: .call
        case .text: .text
        case .email: .email
        case .status: .opensSystemApp
        case .claimBoundary: .claimBoundary
        }
    }

    static func validate() throws {
        let ids = OperationalContactAccessibilityIDV1.allCases
        guard ids.map(\.rawValue).count == Set(ids.map(\.rawValue)).count,
              ids.allSatisfy({ !localizationKey(for: $0).rawValue.isEmpty }),
              selectedContactLabelIsSpoken,
              actionAndSystemAppHintAreDistinct,
              statusIsNotColorOnly,
              explicitActivationIsRequired,
              historicIntentIsFocusableButNotActionable,
              !sentDeliveredConnectedOrArrivalClaimAllowed else {
            throw LocalizationContractFailureV1.invalidAccessibilityBinding
        }
    }
}

// MARK: - C48 portable-review derived-consumer accessibility

/// The accessible projection exposes only the recorded lifecycle/disposition
/// and the explicit trust limitation.  It never speaks capability bytes,
/// proof bytes, response text, private identifiers, or verified identity.
enum C48PortableReviewAccessibilityIDV1: String, CaseIterable, Codable, Hashable, Sendable {
    case responseState = "portable_review.response.state"
    case responseDisposition = "portable_review.response.disposition"
    case responseTrustBoundary = "portable_review.response.trust_boundary"
    case historyOnly = "portable_review.response.history_only"
}

enum C48PortableReviewAccessibilityPolicyV1 {
    static let statusIsNotColorOnly = true
    static let stateAndDispositionAreSpoken = true
    static let explicitTrustLimitationIsSpoken = true
    static let capabilityBytesSpoken = false
    static let capabilityProofSpoken = false
    static let responseBodySpoken = false
    static let rawRequestResponseBytesSpoken = false
    static let workspaceAndReplicaIdentitySpoken = false
    static let verifiedIdentitySpoken = false

    static func localizationKey(
        for id: C48PortableReviewAccessibilityIDV1
    ) -> C48PortableReviewLocalizationKeyV1 {
        switch id {
        case .responseState: .responseRecorded
        case .responseDisposition: .responseRecorded
        case .responseTrustBoundary: .responseNotVerified
        case .historyOnly: .historyOnly
        }
    }

    static func validate() throws {
        let ids = C48PortableReviewAccessibilityIDV1.allCases
        guard ids.map(\.rawValue).count == Set(ids.map(\.rawValue)).count,
              ids.allSatisfy({ !localizationKey(for: $0).rawValue.isEmpty }),
              statusIsNotColorOnly,
              stateAndDispositionAreSpoken,
              explicitTrustLimitationIsSpoken,
              !capabilityBytesSpoken,
              !capabilityProofSpoken,
              !responseBodySpoken,
              !rawRequestResponseBytesSpoken,
              !workspaceAndReplicaIdentitySpoken,
              !verifiedIdentitySpoken else {
            throw LocalizationContractFailureV1.invalidAccessibilityBinding
        }
    }
}

// MARK: - C49 work-resource accessibility

enum C49WorkResourceAccessibilityBoundaryV1 {
    static let durationAndExactMaterialFieldsAreSpoken = true
    static let directCostPreviewIsAudienceGated = true
    static let rawStockRowsAreSpoken = false
    static let liveInventoryClaimsAreSpoken = false

    static func spokenLines(
        _ projection: C49WorkResourceReportProjectionV1
    ) throws -> [String] {
        try C49WorkResourceAccessibleDocumentBoundaryV1.lines(projection)
    }
}

// MARK: - C34 typed route restoration accessibility

enum C34RouteAccessibilityIDV1: String, CaseIterable, Codable, Sendable {
    case safeFallbackContainer = "navigation.route.fallback"
    case safeFallbackHeading = "navigation.route.fallback.heading"
    case safeFallbackReason = "navigation.route.fallback.reason"
    case safeFallbackDestination = "navigation.route.fallback.destination"
    case explicitResumeAction = "navigation.route.resume.action"
}

/// Semantic declarations only; the UI owner must prove rendered behavior.
enum C34RouteAccessibilityConformanceV1 {
    static let conformanceReceiptType: Any.Type = RouteConformanceReceiptV1.self
    static let restorationReceiptType: Any.Type = RouteRestorationReceiptV1.self
    static let semanticIDs = C34RouteAccessibilityIDV1.allCases.map(\.rawValue)
    static let voiceOverLabelAndReasonRequired = true
    static let voiceControlSafeDestinationRequired = true
    static let switchControlSafeDestinationRequired = true
    static let dynamicTypeRequired = true
    static let rtlReadingOrderRequired = true
    static let nonColorReasonRequired = true
    static let automaticResumeAnnouncementForbidden = true
    static let uiConformanceClaimed = false

    static func validate(_ receipt: RouteConformanceReceiptV1) throws {
        try receipt.validate()
        guard semanticIDs.count == Set(semanticIDs).count,
              receipt.roots == AppRootV1.frozenOrder,
              receipt.mutationAuthorityCount == 0 else {
            throw SceneNavigationFailureV1.invalidConformance
        }
    }
}

enum C52ServiceRequestBoundary_SemanticAccessibilityContractsV1 {
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

// MARK: - C53 asset-service reliability accessibility

enum C53AssetServiceReliabilityAccessibilityIDV1: String, CaseIterable, Codable, Hashable, Sendable {
    case incidentRecorded = "service_reliability.incident.recorded"
    case segmentImpact = "service_reliability.segment.impact"
    case causeUnverified = "service_reliability.cause.unverified"
    case restorationRecorded = "service_reliability.restoration.recorded"
    case exposureQualified = "service_reliability.exposure.qualified"
    case metricUnavailable = "service_reliability.metric.unavailable"
}

enum C53AssetServiceReliabilityAccessibilityPolicyV1 {
    static let semanticIDs = C53AssetServiceReliabilityAccessibilityIDV1.allCases.map(\.rawValue)
    static let statusIsNotColorOnly = true
    static let causeAndQualificationStateAreSpoken = true
    static let unavailableReasonIsSpoken = true
    static let rawCapabilityOrSourceBytesAreSpoken = false
    static let releaseToServiceIsAnnounced = false
    static let dynamicTypeAndRTLRemainRequired = true

    static func localizationKey(
        for id: C53AssetServiceReliabilityAccessibilityIDV1
    ) -> C53AssetServiceReliabilityLocalizationKeyV1 {
        switch id {
        case .incidentRecorded: .incidentRecorded
        case .segmentImpact: .segmentImpact
        case .causeUnverified: .causeUnverified
        case .restorationRecorded: .restorationRecorded
        case .exposureQualified: .exposureQualified
        case .metricUnavailable: .metricUnavailable
        }
    }

    static func validate() throws {
        let keys = C53AssetServiceReliabilityAccessibilityIDV1.allCases.map {
            localizationKey(for: $0).rawValue
        }
        guard semanticIDs.count == Set(semanticIDs).count,
              keys.count == Set(keys).count,
              statusIsNotColorOnly,
              causeAndQualificationStateAreSpoken,
              unavailableReasonIsSpoken,
              !rawCapabilityOrSourceBytesAreSpoken,
              !releaseToServiceIsAnnounced,
              dynamicTypeAndRTLRemainRequired else {
            throw LocalizationContractFailureV1.invalidAccessibilityBinding
        }
    }
}

// MARK: - C01 Support & Recovery Center accessibility

/// C01 keeps the six UI selectors stable for VoiceOver, Voice Control, and
/// UI automation.  The phase-qualified values are view selectors, not
/// persistence identities or route keys.
enum RecoveryCenterAccessibilityIDV1: String, CaseIterable, Codable, Hashable, Sendable {
    case screen = "v23.p04.c01.recovery-center.screen"
    case status = "v23.p04.c01.recovery-center.status"
    case standardBackup = "v23.p04.c01.recovery-center.standard-backup"
    case encryptedBackup = "v23.p04.c01.recovery-center.encrypted-backup"
    case supportDraft = "v23.p04.c01.recovery-center.support-draft"
    case privacyBlocked = "v23.p04.c01.recovery-center.privacy-blocked"
}

enum RecoveryCenterAccessibilityPolicyV1 {
    static let semanticIDs = RecoveryCenterAccessibilityIDV1.allCases.map(\.rawValue)
    static let statusIsNotColorOnly = true
    static let stateAndFreshnessAreSpoken = true
    static let primaryFallbackAndHelpAreActionable = true
    static let requiresNonColorStateText = true
    static let requiresTextAndIconForIndeterminateStates = true
    static let requiresActionableNextStep = true
    static let dynamicTypeRequired = true
    static let voiceOverRequired = true
    static let voiceOverLabelAndValueRequired = true
    static let voiceControlRequired = true
    static let voiceControlSafeDestinationRequired = true
    static let switchControlRequired = true
    static let contrastWithoutColorRequired = true
    static let increasedContrastRequired = true
    static let reduceMotionSupported = true
    static let rtlReadingOrderRequired = true
    static let uiConformanceClaimed = false
    static let uiAdoptionClaimed = false

    static func localizationKey(
        for id: RecoveryCenterAccessibilityIDV1
    ) -> RecoveryCenterLocalizationKeyV1 {
        switch id {
        case .screen: return .heading
        case .status: return .statusHeading
        case .standardBackup: return .backupStandardHeading
        case .encryptedBackup: return .encryptedBackupHeading
        case .supportDraft: return .feedbackHeading
        case .privacyBlocked: return .privacyBlocked
        }
    }

    static func validate() throws {
        let values = RecoveryCenterAccessibilityIDV1.allCases
        let rawValues = values.map(\.rawValue)
        let keys = values.map { localizationKey(for: $0).rawValue }
        guard rawValues.count == Set(rawValues).count,
              Set(rawValues) == Set(semanticIDs),
              keys.count == Set(keys).count,
              statusIsNotColorOnly,
              stateAndFreshnessAreSpoken,
              primaryFallbackAndHelpAreActionable,
              requiresNonColorStateText,
              requiresTextAndIconForIndeterminateStates,
              requiresActionableNextStep,
              dynamicTypeRequired,
              voiceOverRequired,
              voiceOverLabelAndValueRequired,
              voiceControlRequired,
              voiceControlSafeDestinationRequired,
              switchControlRequired,
              contrastWithoutColorRequired,
              increasedContrastRequired,
              reduceMotionSupported,
              rtlReadingOrderRequired,
              !uiConformanceClaimed,
              !uiAdoptionClaimed else {
            throw LocalizationContractFailureV1.invalidAccessibilityBinding
        }
    }
}

// MARK: - C02 evidence curation accessibility

/// Stable semantic selectors for the unadopted C02 presentation. These are
/// presentation-only identifiers; none is a media, derivative, or canonical
/// association identity.
enum EvidenceCurationAccessibilityIDV1: String, CaseIterable, Codable, Hashable, Sendable {
    case screen = "v23.p04.c02.evidence-curation.screen"
    case detailPreview = "v23.p04.c02.evidence-curation.detail-preview"
    case original = "v23.p04.c02.evidence-curation.original"
    case reference = "v23.p04.c02.evidence-curation.reference"
    case comparison = "v23.p04.c02.evidence-curation.comparison"
    case overlayAdvisory = "v23.p04.c02.evidence-curation.overlay-advisory"
    case markupControls = "v23.p04.c02.evidence-curation.markup-controls"
    case removeMarkup = "v23.p04.c02.evidence-curation.remove-markup"
    case retake = "v23.p04.c02.evidence-curation.retake"
    case removeFromWork = "v23.p04.c02.evidence-curation.remove-from-work"
    case moveEarlier = "v23.p04.c02.evidence-curation.move-earlier"
    case moveLater = "v23.p04.c02.evidence-curation.move-later"
    case sequence = "v23.p04.c02.evidence-curation.sequence"
    case contactSheet = "v23.p04.c02.evidence-curation.contact-sheet"
    case reducedMotion = "v23.p04.c02.evidence-curation.reduced-motion"
    case reviewOrder = "v23.p04.c02.evidence-curation.review-order"
    case role = "v23.p04.c02.evidence-curation.role"
    case caption = "v23.p04.c02.evidence-curation.caption"
    case accessibilityDescription = "v23.p04.c02.evidence-curation.accessibility-description"
    case visualDerivativeReadiness = "v23.p04.c02.evidence-curation.visual-derivative-readiness"
}

enum EvidenceCurationAccessibilityPolicyV1 {
    static let semanticIDs = EvidenceCurationAccessibilityIDV1.allCases.map(\.rawValue)
    static let originalAndReferenceAreTextuallyDistinguished = true
    static let overlayIsAdvisoryAndNotCausal = true
    static let markupRemovalIsAvailable = true
    static let retakeAndRemovalEffectsAreDisclosed = true
    static let accessibleMoveControlsAreAvailable = true
    static let reviewOrderAndCaptionsAreSpoken = true
    static let sequenceRoleAndDescriptionAreSpoken = true
    static let reducedMotionReplacesFlicker = true
    static let dynamicTypeAndRTLRequired = true
    static let statusIsNotColorOnly = true
    static let derivativeReadinessIsTyped = true
    static let uiConformanceClaimed = false
    static let uiAdoptionClaimed = false

    static func localizationKey(
        for id: EvidenceCurationAccessibilityIDV1
    ) -> EvidenceCurationLocalizationKeyV1 {
        switch id {
        case .screen: return .heading
        case .detailPreview: return .detailPreviewHeading
        case .original: return .originalHeading
        case .reference: return .referenceHeading
        case .comparison: return .comparisonHeading
        case .overlayAdvisory: return .overlayAdvisory
        case .markupControls: return .markupHeading
        case .removeMarkup: return .removeMarkup
        case .retake: return .retake
        case .removeFromWork: return .removeFromWork
        case .moveEarlier: return .moveEarlier
        case .moveLater: return .moveLater
        case .sequence: return .sequenceHeading
        case .contactSheet: return .contactSheetHeading
        case .reducedMotion: return .reducedMotion
        case .reviewOrder: return .reviewOrderHeading
        case .role: return .roleHeading
        case .caption: return .captionHeading
        case .accessibilityDescription: return .accessibilityDescriptionHeading
        case .visualDerivativeReadiness: return .visualDerivativeUnavailable
        }
    }

    static func validate() throws {
        let ids = EvidenceCurationAccessibilityIDV1.allCases
        let keys = ids.map { localizationKey(for: $0).rawValue }
        guard ids.map(\.rawValue).count == Set(ids.map(\.rawValue)).count,
              keys.count == Set(keys).count,
              originalAndReferenceAreTextuallyDistinguished,
              overlayIsAdvisoryAndNotCausal,
              markupRemovalIsAvailable,
              retakeAndRemovalEffectsAreDisclosed,
              accessibleMoveControlsAreAvailable,
              reviewOrderAndCaptionsAreSpoken,
              sequenceRoleAndDescriptionAreSpoken,
              reducedMotionReplacesFlicker,
              dynamicTypeAndRTLRequired,
              statusIsNotColorOnly,
              derivativeReadinessIsTyped,
              !uiConformanceClaimed,
              !uiAdoptionClaimed else {
            throw LocalizationContractFailureV1.invalidAccessibilityBinding
        }
    }
}

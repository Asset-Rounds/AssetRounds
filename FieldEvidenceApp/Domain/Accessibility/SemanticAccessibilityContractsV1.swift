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

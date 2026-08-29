import Foundation

enum WorkflowGrammarScheduleBoundaryV1 { static let recurrenceIsPackageScriptable = false }

enum InspectionKernelFailureV1: Error, Equatable, Sendable {
    case invalidValue
    case unknownKind
    case limitExceeded
    case duplicateIdentity
    case missingTarget
    case missingFieldID
    case forwardPredicateReference
    case unreachableNode
    case cycleDetected
    case invalidCardinality
    case incompatibleVersion
    case hashMismatch
    case immutableRelease
    case invalidTransition
    case releaseNotFound
    case publicationInterrupted
}

enum C26SurveyRepeatGrammarV1 {
    static func validate(_ coordinates:[SurveyRepeatCoordinateV1],against release:SurveyDefinitionReleaseV1)throws{try release.validate();try coordinates.forEach{$0.validate()};let groupIDs=Set(release.sections.flatMap(\.facts).filter{$0.kind == .repeatableGroup}.map(\.factID));guard coordinates.allSatisfy({groupIDs.contains($0.groupFactID)}),coordinates==coordinates.sorted(),Set(coordinates).count==coordinates.count else{throw SurveySessionFailureV1.invalidValue}}
}

enum SurveyWorkflowGrammarBoundaryV1 {
    static let activityKindCount = 5
    static let fieldGrammar = "CLOSED_BOUNDED_V1"
    static let requiredVisibilityPolicy = "ACYCLIC_EXACT_FACT_REFERENCE"
    static func validateKindRegistry() throws {
        guard ActivityKindV1.allCases.count == activityKindCount else { throw InspectionKernelFailureV1.invalidValue }
    }
}

enum WorkflowNodeKindV1: String, CaseIterable, Codable, Hashable, Sendable {
    case section = "SECTION"
    case instruction = "INSTRUCTION"
    case fact = "FACT"
    case evidenceRequest = "EVIDENCE_REQUEST"
    case branch = "BRANCH"
    case repeatGroup = "REPEAT_GROUP"
    case review = "REVIEW"
    case terminal = "TERMINAL"
}

enum BranchPredicateKindV1: String, CaseIterable, Codable, Hashable, Sendable {
    case exists = "EXISTS"
    case isKnown = "IS_KNOWN"
    case equals = "EQUALS"
    case inSet = "IN_SET"
    case compareFixed = "COMPARE_FIXED"
    case not = "NOT"
    case all = "ALL"
    case any = "ANY"
}

enum BranchTruthValueV1: String, CaseIterable, Codable, Sendable {
    case trueValue = "TRUE"
    case falseValue = "FALSE"
    case unknown = "UNKNOWN"
}

enum FixedComparisonOperatorV1: String, CaseIterable, Codable, Sendable {
    case lessThan = "LESS_THAN"
    case lessThanOrEqual = "LESS_THAN_OR_EQUAL"
    case equal = "EQUAL"
    case greaterThanOrEqual = "GREATER_THAN_OR_EQUAL"
    case greaterThan = "GREATER_THAN"
}

struct BranchPredicateV1: Codable, Equatable, Sendable {
    let kind: BranchPredicateKindV1
    let fieldID: String?
    let optionID: String?
    let optionIDs: [String]
    let comparison: FixedComparisonOperatorV1?
    let fixedValue: Int64?
    let operands: [BranchPredicateV1]

    init(
        kind: BranchPredicateKindV1,
        fieldID: String? = nil,
        optionID: String? = nil,
        optionIDs: [String] = [],
        comparison: FixedComparisonOperatorV1? = nil,
        fixedValue: Int64? = nil,
        operands: [BranchPredicateV1] = []
    ) throws {
        self.kind = kind
        self.fieldID = fieldID
        self.optionID = optionID
        self.optionIDs = optionIDs
        self.comparison = comparison
        self.fixedValue = fixedValue
        self.operands = operands
        try validate(depth: 1)
    }

    func referencedFieldIDs() -> Set<String> {
        var result = Set(fieldID.map { [$0] } ?? [])
        for operand in operands { result.formUnion(operand.referencedFieldIDs()) }
        return result
    }

    func evaluate(facts: [String: WorkflowFactValueV1]) -> BranchTruthValueV1 {
        switch kind {
        case .exists:
            guard let fieldID else { return .unknown }
            return facts[fieldID] == nil ? .falseValue : .trueValue
        case .isKnown:
            guard let fieldID, let value = facts[fieldID] else { return .unknown }
            return value == .unknown ? .falseValue : .trueValue
        case .equals:
            guard let fieldID, let optionID, let value = facts[fieldID] else {
                return .unknown
            }
            guard case .option(let observed) = value else { return .unknown }
            return observed == optionID ? .trueValue : .falseValue
        case .inSet:
            guard let fieldID, let value = facts[fieldID] else { return .unknown }
            guard case .option(let observed) = value else { return .unknown }
            return optionIDs.contains(observed) ? .trueValue : .falseValue
        case .compareFixed:
            guard let fieldID, let comparison, let fixedValue,
                  let value = facts[fieldID], case .fixed(let observed) = value else {
                return .unknown
            }
            let result: Bool
            switch comparison {
            case .lessThan: result = observed < fixedValue
            case .lessThanOrEqual: result = observed <= fixedValue
            case .equal: result = observed == fixedValue
            case .greaterThanOrEqual: result = observed >= fixedValue
            case .greaterThan: result = observed > fixedValue
            }
            return result ? .trueValue : .falseValue
        case .not:
            guard let value = operands.first?.evaluate(facts: facts) else { return .unknown }
            switch value {
            case .trueValue: return .falseValue
            case .falseValue: return .trueValue
            case .unknown: return .unknown
            }
        case .all:
            let values = operands.map { $0.evaluate(facts: facts) }
            if values.contains(.falseValue) { return .falseValue }
            return values.contains(.unknown) ? .unknown : .trueValue
        case .any:
            let values = operands.map { $0.evaluate(facts: facts) }
            if values.contains(.trueValue) { return .trueValue }
            return values.contains(.unknown) ? .unknown : .falseValue
        }
    }

    func validate(depth: Int) throws {
        guard depth > 0, depth <= WorkflowGrammarLimitsV1.maximumPredicateDepth,
              operands.count <= WorkflowGrammarLimitsV1.maximumPredicateOperands,
              optionIDs.count <= WorkflowGrammarLimitsV1.maximumSetOperandCount,
              optionIDs == optionIDs.sorted(), Set(optionIDs).count == optionIDs.count else {
            throw InspectionKernelFailureV1.limitExceeded
        }
        if let fieldID {
            guard WorkflowGrammarValidationV1.validID(fieldID) else {
                throw InspectionKernelFailureV1.invalidValue
            }
        }
        if let optionID {
            guard WorkflowGrammarValidationV1.validID(optionID) else {
                throw InspectionKernelFailureV1.invalidValue
            }
        }
        guard optionIDs.allSatisfy(WorkflowGrammarValidationV1.validID) else {
            throw InspectionKernelFailureV1.invalidValue
        }
        switch kind {
        case .exists, .isKnown:
            guard fieldID != nil, optionID == nil, optionIDs.isEmpty,
                  comparison == nil, fixedValue == nil, operands.isEmpty else {
                throw InspectionKernelFailureV1.invalidValue
            }
        case .equals:
            guard fieldID != nil, optionID != nil, optionIDs.isEmpty,
                  comparison == nil, fixedValue == nil, operands.isEmpty else {
                throw InspectionKernelFailureV1.invalidValue
            }
        case .inSet:
            guard fieldID != nil, optionID == nil, !optionIDs.isEmpty,
                  comparison == nil, fixedValue == nil, operands.isEmpty else {
                throw InspectionKernelFailureV1.invalidValue
            }
        case .compareFixed:
            guard fieldID != nil, optionID == nil, optionIDs.isEmpty,
                  comparison != nil, fixedValue != nil, operands.isEmpty else {
                throw InspectionKernelFailureV1.invalidValue
            }
        case .not:
            guard fieldID == nil, optionID == nil, optionIDs.isEmpty,
                  comparison == nil, fixedValue == nil, operands.count == 1 else {
                throw InspectionKernelFailureV1.invalidValue
            }
        case .all, .any:
            guard fieldID == nil, optionID == nil, optionIDs.isEmpty,
                  comparison == nil, fixedValue == nil,
                  (2...WorkflowGrammarLimitsV1.maximumPredicateOperands).contains(operands.count) else {
                throw InspectionKernelFailureV1.invalidValue
            }
        }
        try operands.forEach { try $0.validate(depth: depth + 1) }
    }
}

struct WorkflowBranchDestinationsV1: Codable, Equatable, Sendable {
    let trueNodeID: String
    let falseNodeID: String
    let unknownNodeID: String

    func validate() throws {
        let values = [trueNodeID, falseNodeID, unknownNodeID]
        guard values.allSatisfy(WorkflowGrammarValidationV1.validID) else {
            throw InspectionKernelFailureV1.invalidValue
        }
    }

    func destination(for value: BranchTruthValueV1) -> String {
        switch value {
        case .trueValue: return trueNodeID
        case .falseValue: return falseNodeID
        case .unknown: return unknownNodeID
        }
    }
}

enum WorkflowFactValueV1: Equatable, Sendable {
    case unknown
    case known
    case option(String)
    case fixed(Int64)
}

extension WorkflowFactValueV1 {
    /// The workflow grammar consumes only the fact shapes its closed predicate
    /// language can evaluate. Other typed responses remain valid responses but
    /// deliberately evaluate as UNKNOWN rather than gaining implicit truth.
    init(responseValue: ResponseValueV1) {
        switch responseValue {
        case .noValue, .notApplicable:
            self = .unknown
        case .boolean:
            self = .known
        case .triState(let value):
            self = value == .unknown ? .unknown : .known
        case .singleOption(let optionID):
            self = .option(optionID)
        case .integer(let value):
            self = .fixed(value)
        case .decimal(let value) where value.scale == 0:
            self = .fixed(value.mantissa)
        default:
            self = .known
        }
    }
}

struct RepeatInstanceIDV1: Codable, Equatable, Hashable, Sendable {
    let rawValue: String
    init(_ rawValue: String) throws {
        guard WorkflowGrammarValidationV1.validID(rawValue) else {
            throw InspectionKernelFailureV1.invalidValue
        }
        self.rawValue = rawValue
    }
}

enum WorkflowPathActivityV1: String, CaseIterable, Codable, Sendable {
    case active = "ACTIVE"
    case inactiveByPath = "INACTIVE_BY_PATH"
    case reactivationReviewRequired = "REACTIVATION_REVIEW_REQUIRED"
}

struct RepeatInstanceStateV1: Codable, Equatable, Sendable {
    let instanceID: RepeatInstanceIDV1
    let repeatNodeID: String
    let stableOrder: Int
    let activity: WorkflowPathActivityV1

    var satisfiesCompletion: Bool { activity == .active }
    var includedInReporting: Bool { activity == .active }
    var requiresReview: Bool { activity == .reactivationReviewRequired }

    init(
        instanceID: RepeatInstanceIDV1,
        repeatNodeID: String,
        stableOrder: Int,
        activity: WorkflowPathActivityV1 = .active
    ) throws {
        guard WorkflowGrammarValidationV1.validID(repeatNodeID),
              stableOrder >= 0, stableOrder < WorkflowGrammarLimitsV1.maximumRepeatCount else {
            throw InspectionKernelFailureV1.limitExceeded
        }
        self.instanceID = instanceID
        self.repeatNodeID = repeatNodeID
        self.stableOrder = stableOrder
        self.activity = activity
    }

    func invalidatedByPath() throws -> RepeatInstanceStateV1 {
        try RepeatInstanceStateV1(
            instanceID: instanceID,
            repeatNodeID: repeatNodeID,
            stableOrder: stableOrder,
            activity: .inactiveByPath
        )
    }

    func reactivated() throws -> RepeatInstanceStateV1 {
        guard activity == .inactiveByPath else {
            throw InspectionKernelFailureV1.invalidTransition
        }
        return try RepeatInstanceStateV1(
            instanceID: instanceID,
            repeatNodeID: repeatNodeID,
            stableOrder: stableOrder,
            activity: .reactivationReviewRequired
        )
    }
}

enum WorkflowGrammarLimitsV1 {
    static let maximumNodeCount = 128
    static let maximumEdgeCount = 384
    static let maximumFieldCount = 128
    static let maximumGraphDepth = 32
    static let maximumBranchCount = 32
    static let maximumPredicateDepth = 8
    static let maximumPredicateOperands = 16
    static let maximumSetOperandCount = 32
    static let maximumRepeatCount = 32
    static let maximumTotalExecutions = 4_096
    static let maximumIDBytes = 128
}

enum WorkflowGrammarValidationV1 {
    static func validID(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= WorkflowGrammarLimitsV1.maximumIDBytes,
              value == value.lowercased() else { return false }
        return value.utf8.allSatisfy {
            (0x30...0x39).contains($0) || (0x61...0x7A).contains($0)
                || $0 == 0x2D || $0 == 0x2E || $0 == 0x5F
        }
    }
}

struct KernelDynamicCodingKeyV1: CodingKey {
    let stringValue: String
    let intValue: Int?
    init?(stringValue: String) { self.stringValue = stringValue; intValue = nil }
    init?(intValue: Int) { stringValue = String(intValue); self.intValue = intValue }
}

enum KernelClosedCodingV1 {
    static func require(
        _ decoder: any Decoder,
        keys: [String],
        required: [String]? = nil
    ) throws {
        let container = try decoder.container(keyedBy: KernelDynamicCodingKeyV1.self)
        let observed = Set(container.allKeys.map(\.stringValue))
        let allowed = Set(keys)
        let requiredSet = Set(required ?? keys)
        guard observed.isSubset(of: allowed), requiredSet.isSubset(of: observed) else {
            throw InspectionKernelFailureV1.invalidValue
        }
    }
}

extension BranchPredicateV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind, fieldID, optionID, optionIDs, comparison, fixedValue, operands
    }
    init(from decoder: any Decoder) throws {
        try KernelClosedCodingV1.require(
            decoder,
            keys: CodingKeys.allCases.map(\.rawValue),
            required: ["kind", "optionIDs", "operands"]
        )
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            kind: c.decode(BranchPredicateKindV1.self, forKey: .kind),
            fieldID: c.decodeIfPresent(String.self, forKey: .fieldID),
            optionID: c.decodeIfPresent(String.self, forKey: .optionID),
            optionIDs: c.decode([String].self, forKey: .optionIDs),
            comparison: c.decodeIfPresent(FixedComparisonOperatorV1.self, forKey: .comparison),
            fixedValue: c.decodeIfPresent(Int64.self, forKey: .fixedValue),
            operands: c.decode([BranchPredicateV1].self, forKey: .operands)
        )
    }
}

extension WorkflowBranchDestinationsV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case trueNodeID, falseNodeID, unknownNodeID
    }
    init(from decoder: any Decoder) throws {
        try KernelClosedCodingV1.require(decoder, keys: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            trueNodeID: try c.decode(String.self, forKey: .trueNodeID),
            falseNodeID: try c.decode(String.self, forKey: .falseNodeID),
            unknownNodeID: try c.decode(String.self, forKey: .unknownNodeID)
        )
        try validate()
    }
}

extension RepeatInstanceIDV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable { case rawValue }
    init(from decoder: any Decoder) throws {
        try KernelClosedCodingV1.require(decoder, keys: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(c.decode(String.self, forKey: .rawValue))
    }
}

extension RepeatInstanceStateV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case instanceID, repeatNodeID, stableOrder, activity
    }
    init(from decoder: any Decoder) throws {
        try KernelClosedCodingV1.require(decoder, keys: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            instanceID: c.decode(RepeatInstanceIDV1.self, forKey: .instanceID),
            repeatNodeID: c.decode(String.self, forKey: .repeatNodeID),
            stableOrder: c.decode(Int.self, forKey: .stableOrder),
            activity: c.decode(WorkflowPathActivityV1.self, forKey: .activity)
        )
    }
}

/// C29 typed integration anchor: this owner consumes an exact immutable plan
/// revision reference and may not reinterpret current plan state implicitly.
enum C29PlanIntegration_Domain_InspectionKernel_WorkflowGrammarContractsV1 {
    static func validatePlanRevision(_ value: PlanRevisionReferenceV1) throws {
        try value.validate()
    }
}

enum C37PoseIntegration_FieldEvidenceApp_Domain_InspectionKernel_WorkflowGrammarContractsV1_swift {
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
enum C30ConsumerBoundaryV1_Domain_InspectionKernel_WorkflowGrammarContractsV1 {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Domain/InspectionKernel/WorkflowGrammarContractsV1.swift", role: .evidence)
}

enum C31LightingWorkflowGrammarBoundaryV1 {
    static let topologyObservationMeasurementAndClaimAreSeparate = true
    static let safetyStopIsARecordedGateState = true
    static let unsupportedClaimVocabularyIsRejected = true
}
// MARK: - C32 assistance workflow grammar boundary

enum C32AssistanceLifecycleBoundary_FieldEvidenceApp_Domain_InspectionKernel_WorkflowGrammarContractsV1_swift {
    static let proposalIsPersistent = AssistancePersistenceEnrollmentV1.proposalIsPersistent
    static let rejectedProposalCorpusIsPersistent = AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent
    static let durableFamilyCount = AssistancePersistenceEnrollmentV1.durableModelCount
    static let acceptedMutationKind: WorkspaceCommandKindV1 = .applyAssistanceAcceptance
    static let manualFallback: ManualFallbackActionV1 = .typeManually
    static let grammarEmitsReviewCandidateOnly = true

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

enum C33TemporalEvidenceBoundary_Domain_InspectionKernel_WorkflowGrammarContractsV1_V1 {
    static let clipType: TemporalEvidenceClipV1.Type = TemporalEvidenceClipV1.self
    static let anchorType: TimecodedEvidenceAnchorV1.Type = TimecodedEvidenceAnchorV1.self
    static let persistentSchemaVersion: Int =
        TemporalEvidencePersistenceEnrollmentV1.persistentSchemaVersion
}

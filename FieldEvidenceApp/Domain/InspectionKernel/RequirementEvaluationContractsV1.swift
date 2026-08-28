import Foundation

enum RequirementAssuranceFailureV1: Error, Equatable, Sendable {
    case invalidValue
    case incompatibleVersion
    case duplicateIdentity
    case unknownRequirementType
    case missingEvaluator
    case staleRevision
    case invalidEvidence
    case invalidWaiver
    case nonCanonicalOrder
    case digestMismatch
    case revisionOverflow
}

enum RequirementAssuranceLimitsV1 {
    static let maximumRequirements = 512
    static let maximumEvidenceReferences = 2_048
    static let maximumReferencesPerRequirement = 64
    static let maximumReasonCodesPerRequirement = 32
    static let maximumExplanationBytes = 2_048
}

enum RequirementAssuranceValidationV1 {
    static func validID(_ value: String) -> Bool {
        WorkflowGrammarValidationV1.validID(value)
    }

    static func validSHA256(_ value: String) -> Bool {
        KernelCanonicalHashV1.validSHA256(value)
    }

    static func requireCanonicalIDs(_ values: [String], maximum: Int) throws {
        guard values.count <= maximum,
              values == values.sorted(),
              Set(values).count == values.count,
              values.allSatisfy(validID) else {
            throw RequirementAssuranceFailureV1.nonCanonicalOrder
        }
    }
}

enum RequirementAssuranceCanonicalV1 {
    static func data<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try encoder.encode(value)
    }

    static func sha256<T: Encodable>(_ value: T) throws -> String {
        KernelCanonicalHashV1.sha256(try data(value))
    }
}

enum RequirementEvaluationResultV1: String, Codable, CaseIterable, Hashable, Comparable, Sendable {
    case satisfied = "SATISFIED"
    case notSatisfied = "NOT_SATISFIED"
    case notApplicable = "NOT_APPLICABLE"
    case unknown = "UNKNOWN"
    case waived = "WAIVED"

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Explicit projection only. Screening language remains C40-owned and is never
/// represented as a compliance, safety, certification, or legal conclusion.
enum RequirementScreeningProjectionV1 {
    static func project(_ result: ScreeningCriterionResultV1) -> RequirementEvaluationResultV1 {
        switch result {
        case .meetsScreeningCriterion: return .satisfied
        case .doesNotMeet: return .notSatisfied
        case .inconclusive, .notEvaluated: return .unknown
        }
    }
}

enum RequirementGateEffectV1: String, Codable, CaseIterable, Hashable, Sendable {
    case hardBlocker = "HARD_BLOCKER"
    case warning = "WARNING"
}

enum RequirementResponseStateV1: String, Codable, CaseIterable, Hashable, Sendable {
    case satisfied = "SATISFIED"
    case notSatisfied = "NOT_SATISFIED"
    case notApplicable = "NOT_APPLICABLE"
    case unknown = "UNKNOWN"
    case unanswered = "UNANSWERED"
}

enum RequirementEvidenceStateV1: String, Codable, CaseIterable, Hashable, Sendable {
    case valid = "VALID"
    case invalid = "INVALID"
}

enum RequirementReasonCodeV1: String, Codable, CaseIterable, Hashable, Comparable, Sendable {
    case satisfied = "REQUIREMENT_SATISFIED"
    case responseNotSatisfied = "RESPONSE_NOT_SATISFIED"
    case notApplicableAccepted = "NOT_APPLICABLE_ACCEPTED"
    case notApplicableNotAllowed = "NOT_APPLICABLE_NOT_ALLOWED"
    case unknownResponse = "UNKNOWN_RESPONSE"
    case unansweredRequirement = "UNANSWERED_REQUIREMENT"
    case requiredEvidenceMissing = "REQUIRED_EVIDENCE_MISSING"
    case evidenceInvalid = "EVIDENCE_INVALID"
    case evidenceDuplicated = "EVIDENCE_DUPLICATED"
    case evidenceContradictory = "EVIDENCE_CONTRADICTORY"
    case waiverAccepted = "WAIVER_ACCEPTED"
    case waiverNotAllowed = "WAIVER_NOT_ALLOWED"
    case waiverReasonNotAllowed = "WAIVER_REASON_NOT_ALLOWED"
    case waiverRevisionMismatch = "WAIVER_REVISION_MISMATCH"
    case waiverScopeMismatch = "WAIVER_SCOPE_MISMATCH"

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct RequirementDefinitionV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let requirementID: String
    let requirementVersion: Int
    let requirementTypeID: String
    let policySHA256: String
    let gateEffect: RequirementGateEffectV1
    let allowsNotApplicable: Bool
    let requiredEvidenceKindIDs: [String]
    let allowedWaiverReasonCodes: [String]

    init(
        requirementID: String,
        requirementVersion: Int,
        requirementTypeID: String,
        policySHA256: String,
        gateEffect: RequirementGateEffectV1,
        allowsNotApplicable: Bool,
        requiredEvidenceKindIDs: [String] = [],
        allowedWaiverReasonCodes: [String] = []
    ) throws {
        schemaVersion = Self.schemaVersion
        self.requirementID = requirementID
        self.requirementVersion = requirementVersion
        self.requirementTypeID = requirementTypeID
        self.policySHA256 = policySHA256
        self.gateEffect = gateEffect
        self.allowsNotApplicable = allowsNotApplicable
        self.requiredEvidenceKindIDs = requiredEvidenceKindIDs
        self.allowedWaiverReasonCodes = allowedWaiverReasonCodes
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              RequirementAssuranceValidationV1.validID(requirementID),
              requirementVersion > 0,
              RequirementAssuranceValidationV1.validID(requirementTypeID),
              RequirementAssuranceValidationV1.validSHA256(policySHA256) else {
            throw RequirementAssuranceFailureV1.invalidValue
        }
        try RequirementAssuranceValidationV1.requireCanonicalIDs(
            requiredEvidenceKindIDs,
            maximum: RequirementAssuranceLimitsV1.maximumReferencesPerRequirement
        )
        try RequirementAssuranceValidationV1.requireCanonicalIDs(
            allowedWaiverReasonCodes,
            maximum: RequirementAssuranceLimitsV1.maximumReasonCodesPerRequirement
        )
    }
}

struct RequirementEvidenceReferenceV1: Codable, Equatable, Hashable, Comparable, Sendable {
    let referenceID: String
    let evidenceKindID: String
    let evidenceRevision: UInt64
    let state: RequirementEvidenceStateV1

    init(
        referenceID: String,
        evidenceKindID: String,
        evidenceRevision: UInt64,
        state: RequirementEvidenceStateV1
    ) throws {
        self.referenceID = referenceID
        self.evidenceKindID = evidenceKindID
        self.evidenceRevision = evidenceRevision
        self.state = state
        try validate()
    }

    func validate() throws {
        guard RequirementAssuranceValidationV1.validID(referenceID),
              RequirementAssuranceValidationV1.validID(evidenceKindID),
              evidenceRevision > 0 else {
            throw RequirementAssuranceFailureV1.invalidEvidence
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.referenceID != rhs.referenceID { return lhs.referenceID < rhs.referenceID }
        if lhs.evidenceKindID != rhs.evidenceKindID { return lhs.evidenceKindID < rhs.evidenceKindID }
        if lhs.evidenceRevision != rhs.evidenceRevision { return lhs.evidenceRevision < rhs.evidenceRevision }
        return lhs.state.rawValue < rhs.state.rawValue
    }
}

// MARK: - C19 quality projection

/// Measurement quality is evidence about capture integrity, not a
/// requirement conclusion. Callers may carry this state into an evaluation
/// context, but it is deliberately projected to UNKNOWN until an explicit
/// requirement rule evaluates its own evidence.
enum MeasurementIntegrityRequirementProjectionV1 {
    static func result(
        for assessment: MeasurementQualityAssessmentV1
    ) throws -> RequirementEvaluationResultV1 {
        try assessment.validate()
        return .unknown
    }
}

struct RequirementWaiverV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let waiverID: String
    let requirementID: String
    let requirementVersion: Int
    let evaluatedRevision: UInt64
    let reasonCode: String
    /// Opaque reference only. C38 owns actor/party semantics.
    let actorReference: String
    let scopeID: String
    let policySHA256: String

    init(
        waiverID: String,
        requirementID: String,
        requirementVersion: Int,
        evaluatedRevision: UInt64,
        reasonCode: String,
        actorReference: String,
        scopeID: String,
        policySHA256: String
    ) throws {
        schemaVersion = Self.schemaVersion
        self.waiverID = waiverID
        self.requirementID = requirementID
        self.requirementVersion = requirementVersion
        self.evaluatedRevision = evaluatedRevision
        self.reasonCode = reasonCode
        self.actorReference = actorReference
        self.scopeID = scopeID
        self.policySHA256 = policySHA256
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              [waiverID, requirementID, reasonCode, actorReference, scopeID]
                .allSatisfy(RequirementAssuranceValidationV1.validID),
              requirementVersion > 0, evaluatedRevision > 0,
              RequirementAssuranceValidationV1.validSHA256(policySHA256) else {
            throw RequirementAssuranceFailureV1.invalidWaiver
        }
    }
}

struct RequirementEvaluationInputV1: Codable, Equatable, Sendable {
    let definition: RequirementDefinitionV1
    let evaluatedRevision: UInt64
    let scopeID: String
    let responseState: RequirementResponseStateV1
    let evidenceReferences: [RequirementEvidenceReferenceV1]
    let waiver: RequirementWaiverV1?

    init(
        definition: RequirementDefinitionV1,
        evaluatedRevision: UInt64,
        scopeID: String,
        responseState: RequirementResponseStateV1,
        evidenceReferences: [RequirementEvidenceReferenceV1] = [],
        waiver: RequirementWaiverV1? = nil
    ) throws {
        self.definition = definition
        self.evaluatedRevision = evaluatedRevision
        self.scopeID = scopeID
        self.responseState = responseState
        self.evidenceReferences = evidenceReferences
        self.waiver = waiver
        try validate()
    }

    func validate() throws {
        try definition.validate()
        try waiver?.validate()
        guard evaluatedRevision > 0,
              RequirementAssuranceValidationV1.validID(scopeID),
              evidenceReferences.count <= RequirementAssuranceLimitsV1.maximumEvidenceReferences,
              evidenceReferences == evidenceReferences.sorted() else {
            throw RequirementAssuranceFailureV1.nonCanonicalOrder
        }
        try evidenceReferences.forEach { try $0.validate() }
    }
}

struct RequirementEvaluationV1: Codable, Equatable, Hashable, Comparable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let requirementID: String
    let requirementVersion: Int
    let requirementTypeID: String
    let evaluatedRevision: UInt64
    let policySHA256: String
    let gateEffect: RequirementGateEffectV1
    let result: RequirementEvaluationResultV1
    let reasonCodes: [RequirementReasonCodeV1]
    let missingEvidenceReferences: [String]
    let invalidEvidenceReferences: [String]
    let evidenceReferenceIDs: [String]
    let waiverID: String?

    init(
        definition: RequirementDefinitionV1,
        evaluatedRevision: UInt64,
        result: RequirementEvaluationResultV1,
        reasonCodes: [RequirementReasonCodeV1],
        missingEvidenceReferences: [String] = [],
        invalidEvidenceReferences: [String] = [],
        evidenceReferenceIDs: [String] = [],
        waiverID: String? = nil
    ) throws {
        schemaVersion = Self.schemaVersion
        requirementID = definition.requirementID
        requirementVersion = definition.requirementVersion
        requirementTypeID = definition.requirementTypeID
        self.evaluatedRevision = evaluatedRevision
        policySHA256 = definition.policySHA256
        gateEffect = definition.gateEffect
        self.result = result
        self.reasonCodes = reasonCodes
        self.missingEvidenceReferences = missingEvidenceReferences
        self.invalidEvidenceReferences = invalidEvidenceReferences
        self.evidenceReferenceIDs = evidenceReferenceIDs
        self.waiverID = waiverID
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              [requirementID, requirementTypeID].allSatisfy(RequirementAssuranceValidationV1.validID),
              requirementVersion > 0, evaluatedRevision > 0,
              RequirementAssuranceValidationV1.validSHA256(policySHA256),
              reasonCodes == reasonCodes.sorted(), Set(reasonCodes).count == reasonCodes.count,
              !reasonCodes.isEmpty, waiverID.map(RequirementAssuranceValidationV1.validID) ?? true,
              (result == .waived) == (waiverID != nil) else {
            throw RequirementAssuranceFailureV1.invalidValue
        }
        for values in [missingEvidenceReferences, invalidEvidenceReferences, evidenceReferenceIDs] {
            try RequirementAssuranceValidationV1.requireCanonicalIDs(
                values,
                maximum: RequirementAssuranceLimitsV1.maximumReferencesPerRequirement
            )
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.requirementID < rhs.requirementID }
}

extension RequirementEvaluationV1 {
    func inspectionReviewEvidenceReference() throws -> ReviewEvidenceReferenceV1 {
        try validate()
        return try .init(kind: .requirementEvaluation,
                         referenceID: requirementID,
                         revision: evaluatedRevision,
                         sha256: WorkspaceMutationCanonicalV1.sha256(self))
    }
}

extension RequirementEvaluationV1 {
    /// C13 binds the exact evaluated C40 claim without changing its result,
    /// reasons, policy digest, or criterion semantics.
    var assuranceClaimID: String {
        "requirement:\(requirementID):\(requirementVersion):\(evaluatedRevision)"
    }
}

extension RequirementEvidenceReferenceV1 {
    func assuranceLink(
        linkID: UUID,
        workspaceID: WorkspaceID,
        claimID: String,
        criterionID: String,
        evidenceSHA256: String,
        visibility: EvidenceVisibilityV1,
        audience: EvidenceAudienceV1,
        revision: UInt64 = 1,
        mutationID: MutationIDV1
    ) throws -> ClaimEvidenceLinkV1 {
        try ClaimEvidenceLinkV1(
            linkID: linkID,
            workspaceID: workspaceID,
            claimID: claimID,
            criterionID: criterionID,
            evidenceID: referenceID,
            evidenceRevision: evidenceRevision,
            evidenceSHA256: evidenceSHA256,
            visibility: visibility,
            audience: audience,
            limitation: state == .invalid ? .evidenceInvalid : nil,
            revision: revision,
            mutationID: mutationID
        )
    }
}

enum CompletionDispositionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case permitted = "PERMITTED"
    case blocked = "BLOCKED"
}

struct CompletionDecisionV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let evaluatedRevision: UInt64
    let policySetSHA256: String
    let disposition: CompletionDispositionV1
    let hardBlockerRequirementIDs: [String]
    let warningRequirementIDs: [String]
    let notApplicableRequirementIDs: [String]
    let unknownRequirementIDs: [String]
    let waivedRequirementIDs: [String]
    let evaluationSetSHA256: String

    init(
        evaluatedRevision: UInt64,
        policySetSHA256: String,
        disposition: CompletionDispositionV1,
        hardBlockerRequirementIDs: [String],
        warningRequirementIDs: [String],
        notApplicableRequirementIDs: [String],
        unknownRequirementIDs: [String],
        waivedRequirementIDs: [String],
        evaluationSetSHA256: String
    ) throws {
        schemaVersion = Self.schemaVersion
        self.evaluatedRevision = evaluatedRevision
        self.policySetSHA256 = policySetSHA256
        self.disposition = disposition
        self.hardBlockerRequirementIDs = hardBlockerRequirementIDs
        self.warningRequirementIDs = warningRequirementIDs
        self.notApplicableRequirementIDs = notApplicableRequirementIDs
        self.unknownRequirementIDs = unknownRequirementIDs
        self.waivedRequirementIDs = waivedRequirementIDs
        self.evaluationSetSHA256 = evaluationSetSHA256
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion, evaluatedRevision > 0,
              RequirementAssuranceValidationV1.validSHA256(policySetSHA256),
              RequirementAssuranceValidationV1.validSHA256(evaluationSetSHA256),
              (disposition == .blocked) == (!hardBlockerRequirementIDs.isEmpty || !unknownRequirementIDs.isEmpty) else {
            throw RequirementAssuranceFailureV1.invalidValue
        }
        for values in [hardBlockerRequirementIDs, warningRequirementIDs,
                       notApplicableRequirementIDs, unknownRequirementIDs, waivedRequirementIDs] {
            try RequirementAssuranceValidationV1.requireCanonicalIDs(
                values, maximum: RequirementAssuranceLimitsV1.maximumRequirements
            )
        }
    }
}

enum IntegrityFindingKindV1: String, Codable, CaseIterable, Hashable, Comparable, Sendable {
    case unansweredRequirement = "UNANSWERED_REQUIREMENT"
    case missingRequiredEvidence = "MISSING_REQUIRED_EVIDENCE"
    case orphanEvidenceReference = "ORPHAN_EVIDENCE_REFERENCE"
    case duplicateEvidenceReference = "DUPLICATE_EVIDENCE_REFERENCE"
    case contradictoryEvidence = "CONTRADICTORY_EVIDENCE"
    case invalidState = "INVALID_STATE"
    case snapshotReportDivergence = "SNAPSHOT_REPORT_DIVERGENCE"

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct IntegrityFindingV1: Codable, Equatable, Hashable, Comparable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let kind: IntegrityFindingKindV1
    let requirementID: String?
    let referenceIDs: [String]
    let reasonCode: String

    init(
        kind: IntegrityFindingKindV1,
        requirementID: String? = nil,
        referenceIDs: [String] = [],
        reasonCode: String
    ) throws {
        schemaVersion = Self.schemaVersion
        self.kind = kind
        self.requirementID = requirementID
        self.referenceIDs = referenceIDs
        self.reasonCode = reasonCode
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              requirementID.map(RequirementAssuranceValidationV1.validID) ?? true,
              RequirementAssuranceValidationV1.validID(reasonCode) else {
            throw RequirementAssuranceFailureV1.invalidValue
        }
        try RequirementAssuranceValidationV1.requireCanonicalIDs(
            referenceIDs, maximum: RequirementAssuranceLimitsV1.maximumReferencesPerRequirement
        )
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.kind != rhs.kind { return lhs.kind < rhs.kind }
        if lhs.requirementID != rhs.requirementID { return (lhs.requirementID ?? "") < (rhs.requirementID ?? "") }
        if lhs.referenceIDs != rhs.referenceIDs { return lhs.referenceIDs.lexicographicallyPrecedes(rhs.referenceIDs) }
        return lhs.reasonCode < rhs.reasonCode
    }
}

struct RequirementAssuranceSnapshotV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let workflowRecordID: UUID
    let workspaceID: UUID
    let evaluatedRevision: UInt64
    let policySetSHA256: String
    let evaluations: [RequirementEvaluationV1]
    let findings: [IntegrityFindingV1]
    let decision: CompletionDecisionV1
    let snapshotSHA256: String

    init(
        workflowRecordID: UUID,
        workspaceID: UUID,
        evaluatedRevision: UInt64,
        policySetSHA256: String,
        evaluations: [RequirementEvaluationV1],
        findings: [IntegrityFindingV1],
        decision: CompletionDecisionV1
    ) throws {
        schemaVersion = Self.schemaVersion
        self.workflowRecordID = workflowRecordID
        self.workspaceID = workspaceID
        self.evaluatedRevision = evaluatedRevision
        self.policySetSHA256 = policySetSHA256
        self.evaluations = evaluations
        self.findings = findings
        self.decision = decision
        snapshotSHA256 = try RequirementAssuranceCanonicalV1.sha256(
            DigestBasis(workflowRecordID: workflowRecordID, workspaceID: workspaceID,
                        evaluatedRevision: evaluatedRevision, policySetSHA256: policySetSHA256,
                        evaluations: evaluations, findings: findings, decision: decision)
        )
        try validate()
    }

    func validate() throws {
        guard workflowRecordID != Self.zero, workspaceID != Self.zero,
              evaluatedRevision > 0,
              RequirementAssuranceValidationV1.validSHA256(policySetSHA256),
              !evaluations.isEmpty,
              evaluations.count <= RequirementAssuranceLimitsV1.maximumRequirements,
              evaluations == evaluations.sorted(),
              Set(evaluations.map(\.requirementID)).count == evaluations.count,
              findings == findings.sorted(),
              evaluations.allSatisfy({ $0.evaluatedRevision == evaluatedRevision }),
              policySetSHA256 == (try RequirementAssuranceCanonicalV1.sha256(
                evaluations.map { PolicyBinding(requirementID: $0.requirementID, policySHA256: $0.policySHA256) }
              )),
              snapshotSHA256 == (try RequirementAssuranceCanonicalV1.sha256(
                DigestBasis(workflowRecordID: workflowRecordID, workspaceID: workspaceID,
                            evaluatedRevision: evaluatedRevision, policySetSHA256: policySetSHA256,
                            evaluations: evaluations, findings: findings, decision: decision)
              )) else { throw RequirementAssuranceFailureV1.digestMismatch }
        try evaluations.forEach { try $0.validate() }
        try findings.forEach { try $0.validate() }
        try decision.validate()
        guard decision == (try RequirementEvaluationEngineV1.completionDecision(
            evaluations: evaluations
        )) else {
            throw RequirementAssuranceFailureV1.digestMismatch
        }
    }

    private struct DigestBasis: Codable {
        let workflowRecordID: UUID; let workspaceID: UUID; let evaluatedRevision: UInt64
        let policySetSHA256: String; let evaluations: [RequirementEvaluationV1]
        let findings: [IntegrityFindingV1]; let decision: CompletionDecisionV1
    }
    private struct PolicyBinding: Codable {
        let requirementID: String
        let policySHA256: String
    }
    private static let zero = UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))
}

struct RequirementEvaluationRuleV1: Codable, Equatable, Hashable, Comparable, Sendable {
    let requirementTypeID: String
    let acceptedResponseStates: [RequirementResponseStateV1]

    init(requirementTypeID: String, acceptedResponseStates: [RequirementResponseStateV1]) throws {
        self.requirementTypeID = requirementTypeID
        self.acceptedResponseStates = acceptedResponseStates
        try validate()
    }

    func validate() throws {
        guard RequirementAssuranceValidationV1.validID(requirementTypeID),
              !acceptedResponseStates.isEmpty,
              acceptedResponseStates.map(\.rawValue) == acceptedResponseStates.map(\.rawValue).sorted(),
              Set(acceptedResponseStates).count == acceptedResponseStates.count else {
            throw RequirementAssuranceFailureV1.invalidValue
        }
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.requirementTypeID < rhs.requirementTypeID }
}

struct RequirementEvaluatorRegistryV1: Codable, Equatable, Sendable {
    let rules: [RequirementEvaluationRuleV1]

    init(rules: [RequirementEvaluationRuleV1]) throws {
        self.rules = rules
        try validate()
    }

    func validate() throws {
        guard !rules.isEmpty, rules.count <= RequirementAssuranceLimitsV1.maximumRequirements,
              rules == rules.sorted(), Set(rules.map(\.requirementTypeID)).count == rules.count else {
            throw RequirementAssuranceFailureV1.duplicateIdentity
        }
        try rules.forEach { try $0.validate() }
    }

    func rule(for requirementTypeID: String) throws -> RequirementEvaluationRuleV1 {
        try validate()
        guard let value = rules.first(where: { $0.requirementTypeID == requirementTypeID }) else {
            throw RequirementAssuranceFailureV1.missingEvaluator
        }
        return value
    }

    func validateCoverage(of definitions: [RequirementDefinitionV1]) throws {
        try validate()
        try definitions.forEach { try $0.validate() }
        let shipped = Set(definitions.map(\.requirementTypeID))
        guard shipped == Set(rules.map(\.requirementTypeID)) else {
            throw RequirementAssuranceFailureV1.missingEvaluator
        }
    }
}

struct RequirementIntegrityInputV1: Codable, Equatable, Sendable {
    let canonicalEvidenceReferenceIDs: [String]
    let snapshotSHA256: String?
    let reportSHA256: String?

    init(canonicalEvidenceReferenceIDs: [String], snapshotSHA256: String?, reportSHA256: String?) throws {
        self.canonicalEvidenceReferenceIDs = canonicalEvidenceReferenceIDs
        self.snapshotSHA256 = snapshotSHA256
        self.reportSHA256 = reportSHA256
        try RequirementAssuranceValidationV1.requireCanonicalIDs(
            canonicalEvidenceReferenceIDs,
            maximum: RequirementAssuranceLimitsV1.maximumEvidenceReferences
        )
        guard snapshotSHA256.map(RequirementAssuranceValidationV1.validSHA256) ?? true,
              reportSHA256.map(RequirementAssuranceValidationV1.validSHA256) ?? true else {
            throw RequirementAssuranceFailureV1.invalidValue
        }
    }
}

struct RequirementExplanationItemV1: Equatable, Sendable {
    let requirementID: String
    let result: RequirementEvaluationResultV1
    let localizationKeys: [String]
    let referenceIDs: [String]
}

enum RequirementExplanationProjectionV1 {
    static func project(_ evaluations: [RequirementEvaluationV1]) -> [RequirementExplanationItemV1] {
        evaluations.sorted().map {
            RequirementExplanationItemV1(
                requirementID: $0.requirementID,
                result: $0.result,
                localizationKeys: $0.reasonCodes.map { "requirement.reason." + $0.rawValue.lowercased() },
                referenceIDs: Array(Set($0.missingEvidenceReferences + $0.invalidEvidenceReferences + $0.evidenceReferenceIDs)).sorted()
            )
        }
    }
}

import Foundation

struct WorkflowNodeV1: Codable, Equatable, Identifiable, Sendable {
    let nodeID: String
    let kind: WorkflowNodeKindV1
    let localizationKey: String?
    let fieldID: String?
    let evidencePurposeID: String?
    let predicate: BranchPredicateV1?
    let branchDestinations: WorkflowBranchDestinationsV1?
    let repeatBodyEntryNodeID: String?
    let repeatBodyExitNodeID: String?
    let maximumRepeatInstances: Int?
    let outgoingNodeIDs: [String]

    var id: String { nodeID }

    init(
        nodeID: String,
        kind: WorkflowNodeKindV1,
        localizationKey: String? = nil,
        fieldID: String? = nil,
        evidencePurposeID: String? = nil,
        predicate: BranchPredicateV1? = nil,
        branchDestinations: WorkflowBranchDestinationsV1? = nil,
        repeatBodyEntryNodeID: String? = nil,
        repeatBodyExitNodeID: String? = nil,
        maximumRepeatInstances: Int? = nil,
        outgoingNodeIDs: [String]
    ) throws {
        self.nodeID = nodeID
        self.kind = kind
        self.localizationKey = localizationKey
        self.fieldID = fieldID
        self.evidencePurposeID = evidencePurposeID
        self.predicate = predicate
        self.branchDestinations = branchDestinations
        self.repeatBodyEntryNodeID = repeatBodyEntryNodeID
        self.repeatBodyExitNodeID = repeatBodyExitNodeID
        self.maximumRepeatInstances = maximumRepeatInstances
        self.outgoingNodeIDs = outgoingNodeIDs
        try validateShape()
    }

    func validateShape() throws {
        guard WorkflowGrammarValidationV1.validID(nodeID),
              outgoingNodeIDs.allSatisfy(WorkflowGrammarValidationV1.validID) else {
            throw InspectionKernelFailureV1.invalidValue
        }
        if let localizationKey {
            guard WorkflowGrammarValidationV1.validID(localizationKey) else {
                throw InspectionKernelFailureV1.invalidValue
            }
        }
        switch kind {
        case .section, .instruction, .review:
            guard localizationKey != nil, fieldID == nil, evidencePurposeID == nil,
                  predicate == nil, branchDestinations == nil,
                  repeatBodyEntryNodeID == nil, repeatBodyExitNodeID == nil,
                  maximumRepeatInstances == nil, outgoingNodeIDs.count == 1 else {
                throw InspectionKernelFailureV1.invalidCardinality
            }
        case .fact:
            guard fieldID.map(WorkflowGrammarValidationV1.validID) == true,
                  localizationKey != nil, evidencePurposeID == nil, predicate == nil,
                  branchDestinations == nil, repeatBodyEntryNodeID == nil,
                  repeatBodyExitNodeID == nil, maximumRepeatInstances == nil,
                  outgoingNodeIDs.count == 1 else {
                throw InspectionKernelFailureV1.invalidCardinality
            }
        case .evidenceRequest:
            guard evidencePurposeID.map(WorkflowGrammarValidationV1.validID) == true,
                  localizationKey != nil, fieldID == nil, predicate == nil,
                  branchDestinations == nil, repeatBodyEntryNodeID == nil,
                  repeatBodyExitNodeID == nil, maximumRepeatInstances == nil,
                  outgoingNodeIDs.count == 1 else {
                throw InspectionKernelFailureV1.invalidCardinality
            }
        case .branch:
            guard localizationKey == nil, fieldID == nil, evidencePurposeID == nil,
                  let predicate, let branchDestinations,
                  repeatBodyEntryNodeID == nil, repeatBodyExitNodeID == nil,
                  maximumRepeatInstances == nil, outgoingNodeIDs.count == 3 else {
                throw InspectionKernelFailureV1.invalidCardinality
            }
            try predicate.validate(depth: 1)
            try branchDestinations.validate()
            guard outgoingNodeIDs == [
                branchDestinations.trueNodeID,
                branchDestinations.falseNodeID,
                branchDestinations.unknownNodeID,
            ] else { throw InspectionKernelFailureV1.invalidCardinality }
        case .repeatGroup:
            guard localizationKey != nil, fieldID == nil, evidencePurposeID == nil,
                  predicate == nil, branchDestinations == nil,
                  let repeatBodyEntryNodeID, let repeatBodyExitNodeID,
                  let maximumRepeatInstances,
                  WorkflowGrammarValidationV1.validID(repeatBodyEntryNodeID),
                  WorkflowGrammarValidationV1.validID(repeatBodyExitNodeID),
                  (1...WorkflowGrammarLimitsV1.maximumRepeatCount).contains(maximumRepeatInstances),
                  outgoingNodeIDs.count == 2,
                  outgoingNodeIDs[0] == repeatBodyEntryNodeID else {
                throw InspectionKernelFailureV1.invalidCardinality
            }
        case .terminal:
            guard localizationKey != nil, fieldID == nil, evidencePurposeID == nil,
                  predicate == nil, branchDestinations == nil,
                  repeatBodyEntryNodeID == nil, repeatBodyExitNodeID == nil,
                  maximumRepeatInstances == nil, outgoingNodeIDs.isEmpty else {
                throw InspectionKernelFailureV1.invalidCardinality
            }
        }
    }
}

enum C26SurveyWorkflowDefinitionV1 {
    static func validate(_ workflow:WorkflowDefinitionV1,for release:SurveyDefinitionReleaseV1)throws{try release.validate();guard release.activityKind == .survey else{throw SurveySessionFailureV1.wrongDefinition};let surveyFacts=Set(release.sections.flatMap(\.facts).map(\.factID));guard Set(workflow.declaredFieldIDs).isSubset(of:surveyFacts)else{throw SurveySessionFailureV1.wrongDefinition};_ = try WorkflowGraphValidatorV1.validate(workflow)}
}

extension WorkflowDefinitionV1 {
    func validateSurveyDefinition(_ release: SurveyDefinitionReleaseV1) throws {
        try release.validate()
        guard Set(declaredFieldIDs) == Set(release.sections.flatMap(\.facts).map(\.factID)) else {
            throw InspectionKernelFailureV1.invalidValue
        }
    }
}

struct WorkflowDefinitionV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let workflowID: String
    let entryNodeID: String
    let declaredFieldIDs: [String]
    let nodes: [WorkflowNodeV1]

    init(
        workflowID: String,
        entryNodeID: String,
        declaredFieldIDs: [String],
        nodes: [WorkflowNodeV1]
    ) throws {
        schemaVersion = Self.schemaVersion
        self.workflowID = workflowID
        self.entryNodeID = entryNodeID
        self.declaredFieldIDs = declaredFieldIDs.sorted()
        self.nodes = nodes.sorted { $0.nodeID < $1.nodeID }
        guard WorkflowGrammarValidationV1.validID(workflowID),
              WorkflowGrammarValidationV1.validID(entryNodeID),
              self.declaredFieldIDs.allSatisfy(WorkflowGrammarValidationV1.validID),
              Set(self.declaredFieldIDs).count == self.declaredFieldIDs.count else {
            throw InspectionKernelFailureV1.invalidValue
        }
    }
}

extension WorkflowDefinitionV1 {
    /// Field descriptors are released beside, rather than encoded inside, the
    /// C02 workflow definition. This preserves every accepted workflow byte and
    /// package-release hash while proving a complete C03 typed binding.
    func validateResponseFieldDefinitions(
        _ definitions: [ResponseFieldDefinitionV1],
        packageReleaseID: String,
        workflowSHA256: String
    ) throws {
        guard KernelCanonicalHashV1.validSHA256(packageReleaseID),
              KernelCanonicalHashV1.validSHA256(workflowSHA256),
              definitions.map(\.fieldID) == definitions.map(\.fieldID).sorted(),
              Set(definitions.map(\.fieldID)).count == definitions.count,
              Set(definitions.map(\.fieldID)) == Set(declaredFieldIDs) else {
            throw ResponseContractFailureV1.invalidValue
        }
        for definition in definitions {
            guard definition.packageReleaseID == packageReleaseID,
                  definition.workflowSHA256 == workflowSHA256 else {
                throw ResponseContractFailureV1.hashMismatch
            }
            try definition.validate()
        }
    }
}

extension WorkflowNodeV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case nodeID, kind, localizationKey, fieldID, evidencePurposeID, predicate
        case branchDestinations, repeatBodyEntryNodeID, repeatBodyExitNodeID
        case maximumRepeatInstances, outgoingNodeIDs
    }
    init(from decoder: any Decoder) throws {
        try KernelClosedCodingV1.require(
            decoder,
            keys: CodingKeys.allCases.map(\.rawValue),
            required: ["nodeID", "kind", "outgoingNodeIDs"]
        )
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            nodeID: c.decode(String.self, forKey: .nodeID),
            kind: c.decode(WorkflowNodeKindV1.self, forKey: .kind),
            localizationKey: c.decodeIfPresent(String.self, forKey: .localizationKey),
            fieldID: c.decodeIfPresent(String.self, forKey: .fieldID),
            evidencePurposeID: c.decodeIfPresent(String.self, forKey: .evidencePurposeID),
            predicate: c.decodeIfPresent(BranchPredicateV1.self, forKey: .predicate),
            branchDestinations: c.decodeIfPresent(WorkflowBranchDestinationsV1.self, forKey: .branchDestinations),
            repeatBodyEntryNodeID: c.decodeIfPresent(String.self, forKey: .repeatBodyEntryNodeID),
            repeatBodyExitNodeID: c.decodeIfPresent(String.self, forKey: .repeatBodyExitNodeID),
            maximumRepeatInstances: c.decodeIfPresent(Int.self, forKey: .maximumRepeatInstances),
            outgoingNodeIDs: c.decode([String].self, forKey: .outgoingNodeIDs)
        )
    }
}

extension WorkflowDefinitionV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, workflowID, entryNodeID, declaredFieldIDs, nodes
    }
    init(from decoder: any Decoder) throws {
        try KernelClosedCodingV1.require(decoder, keys: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw InspectionKernelFailureV1.incompatibleVersion
        }
        let rawFields = try c.decode([String].self, forKey: .declaredFieldIDs)
        let rawNodes = try c.decode([WorkflowNodeV1].self, forKey: .nodes)
        try self.init(
            workflowID: c.decode(String.self, forKey: .workflowID),
            entryNodeID: c.decode(String.self, forKey: .entryNodeID),
            declaredFieldIDs: rawFields,
            nodes: rawNodes
        )
        guard rawFields == declaredFieldIDs, rawNodes == nodes else {
            throw InspectionKernelFailureV1.invalidValue
        }
        _ = try WorkflowGraphValidatorV1.validate(self)
    }
}

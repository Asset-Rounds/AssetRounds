import Foundation

struct RelatedWorkSuggestionV1: Codable, Equatable, Identifiable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let suggestionID: String
    let sourceWorkID: String
    let sourceWorkRevision: Int
    let candidateWorkID: String
    let candidateWorkRevision: Int
    let subjectID: String
    let categoryID: String
    let policySHA256: String
    let reason: String

    var id: String { suggestionID }

    init(
        sourceWorkID: String,
        sourceWorkRevision: Int,
        candidateWorkID: String,
        candidateWorkRevision: Int,
        subjectID: String,
        categoryID: String,
        policySHA256: String,
        reason: String
    ) throws {
        guard [sourceWorkID, candidateWorkID, subjectID, categoryID].allSatisfy(FindingContractValidationV1.validID),
              sourceWorkID != candidateWorkID, sourceWorkRevision >= 0, candidateWorkRevision >= 0,
              KernelCanonicalHashV1.validSHA256(policySHA256),
              FindingContractValidationV1.validText(reason, maximumBytes: FindingContractLimitsV1.maximumReasonBytes) else {
            if sourceWorkID == candidateWorkID { throw FindingContractFailureV1.selfRelationship }
            throw FindingContractFailureV1.invalidValue
        }
        schemaVersion = Self.schemaVersion
        suggestionID = Self.identity(
            sourceWorkID: sourceWorkID, sourceWorkRevision: sourceWorkRevision,
            candidateWorkID: candidateWorkID, candidateWorkRevision: candidateWorkRevision,
            policySHA256: policySHA256
        )
        self.sourceWorkID = sourceWorkID
        self.sourceWorkRevision = sourceWorkRevision
        self.candidateWorkID = candidateWorkID
        self.candidateWorkRevision = candidateWorkRevision
        self.subjectID = subjectID
        self.categoryID = categoryID
        self.policySHA256 = policySHA256
        self.reason = reason
    }

    static func identity(
        sourceWorkID: String, sourceWorkRevision: Int,
        candidateWorkID: String, candidateWorkRevision: Int,
        policySHA256: String
    ) -> String {
        let value = "\(sourceWorkID)\u{1f}\(sourceWorkRevision)\u{1f}\(candidateWorkID)\u{1f}\(candidateWorkRevision)\u{1f}\(policySHA256)"
        return KernelCanonicalHashV1.sha256(Data(value.utf8))
    }

    func isCurrent(sourceRevision: Int, candidateRevision: Int, policySHA256: String) -> Bool {
        sourceWorkRevision == sourceRevision && candidateWorkRevision == candidateRevision
            && self.policySHA256 == policySHA256
    }
}

enum WorkRelationshipKindV1: String, CaseIterable, Codable, Hashable, Sendable {
    case duplicateOf = "DUPLICATE_OF"
    case relatedTo = "RELATED_TO"
}

enum WorkRelationshipDirectionV1: String, CaseIterable, Codable, Hashable, Sendable {
    case directed = "DIRECTED"
    case symmetric = "SYMMETRIC"
}

struct WorkRelationshipV1: Codable, Equatable, Identifiable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let relationshipID: String
    let sourceWorkID: String
    let sourceWorkRevision: Int
    let targetWorkID: String
    let targetWorkRevision: Int
    let kind: WorkRelationshipKindV1
    let direction: WorkRelationshipDirectionV1
    let reason: String
    let actorID: String
    let mutationID: String
    let createdAt: String

    var id: String { relationshipID }

    init(
        relationshipID: String,
        sourceWorkID: String,
        sourceWorkRevision: Int,
        targetWorkID: String,
        targetWorkRevision: Int,
        kind: WorkRelationshipKindV1,
        direction: WorkRelationshipDirectionV1,
        reason: String,
        actorID: String,
        mutationID: String,
        createdAt: String
    ) throws {
        guard [relationshipID, sourceWorkID, targetWorkID, actorID, mutationID].allSatisfy(FindingContractValidationV1.validID),
              sourceWorkID != targetWorkID, sourceWorkRevision >= 0, targetWorkRevision >= 0,
              FindingContractValidationV1.validText(reason, maximumBytes: FindingContractLimitsV1.maximumReasonBytes),
              FindingContractValidationV1.validInstant(createdAt),
              (kind == .duplicateOf && direction == .directed) || (kind == .relatedTo && direction == .symmetric) else {
            if sourceWorkID == targetWorkID { throw FindingContractFailureV1.selfRelationship }
            throw FindingContractFailureV1.invalidValue
        }
        schemaVersion = Self.schemaVersion
        self.relationshipID = relationshipID
        self.sourceWorkID = sourceWorkID
        self.sourceWorkRevision = sourceWorkRevision
        self.targetWorkID = targetWorkID
        self.targetWorkRevision = targetWorkRevision
        self.kind = kind
        self.direction = direction
        self.reason = reason
        self.actorID = actorID
        self.mutationID = mutationID
        self.createdAt = createdAt
    }
}

enum WorkRelationshipDecisionKindV1: String, CaseIterable, Codable, Hashable, Sendable {
    case confirm = "CONFIRM"
    case notRelated = "NOT_RELATED"
    case removeRelation = "REMOVE_RELATION"
}

struct WorkRelationshipDecisionV1: Codable, Equatable, Identifiable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let decisionID: String
    let suggestionID: String
    let sourceWorkID: String
    let sourceWorkRevision: Int
    let candidateWorkID: String
    let candidateWorkRevision: Int
    let policySHA256: String
    let expectedDecisionRevision: Int
    let resultingDecisionRevision: Int
    let decision: WorkRelationshipDecisionKindV1
    let relationshipID: String?
    let actorID: String
    let reason: String
    let mutationID: String
    let effectiveAt: String

    var id: String { decisionID }

    init(
        decisionID: String,
        suggestion: RelatedWorkSuggestionV1,
        expectedDecisionRevision: Int,
        resultingDecisionRevision: Int,
        decision: WorkRelationshipDecisionKindV1,
        relationshipID: String? = nil,
        actorID: String,
        reason: String,
        mutationID: String,
        effectiveAt: String
    ) throws {
        guard [decisionID, actorID, mutationID].allSatisfy(FindingContractValidationV1.validID),
              expectedDecisionRevision >= 0, resultingDecisionRevision == expectedDecisionRevision + 1,
              relationshipID.map(FindingContractValidationV1.validID) ?? true,
              FindingContractValidationV1.validText(reason, maximumBytes: FindingContractLimitsV1.maximumReasonBytes),
              FindingContractValidationV1.validInstant(effectiveAt),
              (decision == .notRelated) == (relationshipID == nil) else {
            throw FindingContractFailureV1.invalidValue
        }
        schemaVersion = Self.schemaVersion
        self.decisionID = decisionID
        suggestionID = suggestion.suggestionID
        sourceWorkID = suggestion.sourceWorkID
        sourceWorkRevision = suggestion.sourceWorkRevision
        candidateWorkID = suggestion.candidateWorkID
        candidateWorkRevision = suggestion.candidateWorkRevision
        policySHA256 = suggestion.policySHA256
        self.expectedDecisionRevision = expectedDecisionRevision
        self.resultingDecisionRevision = resultingDecisionRevision
        self.decision = decision
        self.relationshipID = relationshipID
        self.actorID = actorID
        self.reason = reason
        self.mutationID = mutationID
        self.effectiveAt = effectiveAt
    }

    private init(
        decisionID: String, suggestionID: String, sourceWorkID: String, sourceWorkRevision: Int,
        candidateWorkID: String, candidateWorkRevision: Int, policySHA256: String,
        expectedDecisionRevision: Int,
        resultingDecisionRevision: Int, decision: WorkRelationshipDecisionKindV1,
        relationshipID: String?, actorID: String, reason: String, mutationID: String, effectiveAt: String
    ) throws {
        guard [decisionID, suggestionID, sourceWorkID, candidateWorkID, actorID, mutationID].allSatisfy(FindingContractValidationV1.validID),
              sourceWorkID != candidateWorkID, sourceWorkRevision >= 0, candidateWorkRevision >= 0,
              KernelCanonicalHashV1.validSHA256(policySHA256),
              expectedDecisionRevision >= 0, resultingDecisionRevision == expectedDecisionRevision + 1,
              relationshipID.map(FindingContractValidationV1.validID) ?? true,
              (decision == .notRelated) == (relationshipID == nil),
              FindingContractValidationV1.validText(reason, maximumBytes: FindingContractLimitsV1.maximumReasonBytes),
              FindingContractValidationV1.validInstant(effectiveAt) else { throw FindingContractFailureV1.invalidValue }
        guard RelatedWorkSuggestionV1.identity(
            sourceWorkID: sourceWorkID,
            sourceWorkRevision: sourceWorkRevision,
            candidateWorkID: candidateWorkID,
            candidateWorkRevision: candidateWorkRevision,
            policySHA256: policySHA256
        ) == suggestionID else { throw FindingContractFailureV1.hashMismatch }
        schemaVersion = Self.schemaVersion; self.decisionID = decisionID; self.suggestionID = suggestionID
        self.sourceWorkID = sourceWorkID; self.sourceWorkRevision = sourceWorkRevision
        self.candidateWorkID = candidateWorkID; self.candidateWorkRevision = candidateWorkRevision
        self.policySHA256 = policySHA256
        self.expectedDecisionRevision = expectedDecisionRevision; self.resultingDecisionRevision = resultingDecisionRevision
        self.decision = decision; self.relationshipID = relationshipID; self.actorID = actorID
        self.reason = reason; self.mutationID = mutationID; self.effectiveAt = effectiveAt
    }
}

enum WorkRelationshipValidatorV1 {
    static func validate(_ relationships: [WorkRelationshipV1]) throws {
        guard relationships.count <= FindingContractLimitsV1.maximumLinks else { throw FindingContractFailureV1.limitExceeded }
        var ids = Set<String>(), mutations = Set<String>(), directedPairs = Set<String>(), symmetricPairs = Set<String>()
        var duplicateEdges: [String: [String]] = [:]
        for item in relationships {
            guard ids.insert(item.relationshipID).inserted, mutations.insert(item.mutationID).inserted else { throw FindingContractFailureV1.duplicateIdentity }
            let direct = "\(item.sourceWorkID)>\(item.targetWorkID)"
            let reverse = "\(item.targetWorkID)>\(item.sourceWorkID)"
            if item.direction == .directed {
                guard !directedPairs.contains(direct), !directedPairs.contains(reverse) else { throw FindingContractFailureV1.reverseRelationship }
                directedPairs.insert(direct)
                duplicateEdges[item.sourceWorkID, default: []].append(item.targetWorkID)
            } else {
                let pair = [item.sourceWorkID, item.targetWorkID].sorted().joined(separator: "|")
                guard symmetricPairs.insert(pair).inserted else { throw FindingContractFailureV1.reverseRelationship }
            }
        }
        var visiting = Set<String>(), visited = Set<String>()
        func visit(_ node: String) throws {
            if visiting.contains(node) { throw FindingContractFailureV1.relationshipCycle }
            if visited.contains(node) { return }
            visiting.insert(node)
            for next in (duplicateEdges[node] ?? []).sorted() { try visit(next) }
            visiting.remove(node); visited.insert(node)
        }
        for node in duplicateEdges.keys.sorted() { try visit(node) }
    }

    static func validateSuggestions(_ suggestions: [RelatedWorkSuggestionV1]) throws {
        guard suggestions.count <= FindingContractLimitsV1.maximumLinks else { throw FindingContractFailureV1.limitExceeded }
        var ids = Set<String>(), pairs = Set<String>()
        for item in suggestions {
            guard ids.insert(item.suggestionID).inserted else { throw FindingContractFailureV1.duplicateIdentity }
            let endpoints = [
                "\(item.sourceWorkID)@\(item.sourceWorkRevision)",
                "\(item.candidateWorkID)@\(item.candidateWorkRevision)",
            ].sorted().joined(separator: "|")
            let pair = "\(endpoints)|\(item.policySHA256)"
            guard pairs.insert(pair).inserted else { throw FindingContractFailureV1.reverseRelationship }
        }
    }
}

enum WorkRelationshipDecisionLedgerV1 {
    static func validate(_ decisions: [WorkRelationshipDecisionV1]) throws {
        guard decisions.count <= FindingContractLimitsV1.maximumTransitions else {
            throw FindingContractFailureV1.limitExceeded
        }
        var decisionIDs = Set<String>()
        var mutationIDs = Set<String>()
        var grouped: [String: [WorkRelationshipDecisionV1]] = [:]
        for decision in decisions {
            guard decisionIDs.insert(decision.decisionID).inserted,
                  mutationIDs.insert(decision.mutationID).inserted else {
                throw FindingContractFailureV1.duplicateIdentity
            }
            grouped[decision.suggestionID, default: []].append(decision)
        }

        for suggestionID in grouped.keys.sorted() {
            guard let history = grouped[suggestionID], let basis = history.first else { continue }
            var expectedRevision = 0
            var activeRelationshipID: String?
            var terminal = false
            for decision in history {
                guard decision.suggestionID == suggestionID,
                      decision.sourceWorkID == basis.sourceWorkID,
                      decision.sourceWorkRevision == basis.sourceWorkRevision,
                      decision.candidateWorkID == basis.candidateWorkID,
                      decision.candidateWorkRevision == basis.candidateWorkRevision,
                      decision.policySHA256 == basis.policySHA256,
                      decision.expectedDecisionRevision == expectedRevision,
                      decision.resultingDecisionRevision == expectedRevision + 1,
                      !terminal else {
                    throw FindingContractFailureV1.historyRewrite
                }
                switch decision.decision {
                case .confirm:
                    guard activeRelationshipID == nil, let relationshipID = decision.relationshipID else {
                        throw FindingContractFailureV1.invalidTransition
                    }
                    activeRelationshipID = relationshipID
                case .notRelated:
                    guard activeRelationshipID == nil, decision.relationshipID == nil else {
                        throw FindingContractFailureV1.invalidTransition
                    }
                    terminal = true
                case .removeRelation:
                    guard let relationshipID = decision.relationshipID,
                          relationshipID == activeRelationshipID else {
                        throw FindingContractFailureV1.invalidTransition
                    }
                    activeRelationshipID = nil
                    terminal = true
                }
                expectedRevision = decision.resultingDecisionRevision
            }
        }
    }

    static func suppresses(
        _ suggestion: RelatedWorkSuggestionV1,
        decisions: [WorkRelationshipDecisionV1]
    ) throws -> Bool {
        try validate(decisions)
        return decisions.contains {
            $0.suggestionID == suggestion.suggestionID && $0.decision == .notRelated
        }
    }

    static func activeRelationshipID(
        for suggestion: RelatedWorkSuggestionV1,
        decisions: [WorkRelationshipDecisionV1]
    ) throws -> String? {
        try validate(decisions)
        var active: String?
        for decision in decisions where decision.suggestionID == suggestion.suggestionID {
            switch decision.decision {
            case .confirm: active = decision.relationshipID
            case .removeRelation: active = nil
            case .notRelated: break
            }
        }
        return active
    }
}

extension RelatedWorkSuggestionV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, suggestionID, sourceWorkID, sourceWorkRevision, candidateWorkID, candidateWorkRevision, subjectID, categoryID, policySHA256, reason }
    init(from decoder: any Decoder) throws {
        try FindingClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue)); let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else { throw FindingContractFailureV1.incompatibleVersion }
        try self.init(sourceWorkID: c.decode(String.self, forKey: .sourceWorkID), sourceWorkRevision: c.decode(Int.self, forKey: .sourceWorkRevision), candidateWorkID: c.decode(String.self, forKey: .candidateWorkID), candidateWorkRevision: c.decode(Int.self, forKey: .candidateWorkRevision), subjectID: c.decode(String.self, forKey: .subjectID), categoryID: c.decode(String.self, forKey: .categoryID), policySHA256: c.decode(String.self, forKey: .policySHA256), reason: c.decode(String.self, forKey: .reason))
        guard suggestionID == (try c.decode(String.self, forKey: .suggestionID)) else { throw FindingContractFailureV1.hashMismatch }
    }
}

extension WorkRelationshipV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, relationshipID, sourceWorkID, sourceWorkRevision, targetWorkID, targetWorkRevision, kind, direction, reason, actorID, mutationID, createdAt }
    init(from decoder: any Decoder) throws {
        try FindingClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue)); let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else { throw FindingContractFailureV1.incompatibleVersion }
        try self.init(relationshipID: c.decode(String.self, forKey: .relationshipID), sourceWorkID: c.decode(String.self, forKey: .sourceWorkID), sourceWorkRevision: c.decode(Int.self, forKey: .sourceWorkRevision), targetWorkID: c.decode(String.self, forKey: .targetWorkID), targetWorkRevision: c.decode(Int.self, forKey: .targetWorkRevision), kind: c.decode(WorkRelationshipKindV1.self, forKey: .kind), direction: c.decode(WorkRelationshipDirectionV1.self, forKey: .direction), reason: c.decode(String.self, forKey: .reason), actorID: c.decode(String.self, forKey: .actorID), mutationID: c.decode(String.self, forKey: .mutationID), createdAt: c.decode(String.self, forKey: .createdAt))
    }
}

extension WorkRelationshipDecisionV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, decisionID, suggestionID, sourceWorkID, sourceWorkRevision, candidateWorkID, candidateWorkRevision, policySHA256, expectedDecisionRevision, resultingDecisionRevision, decision, relationshipID, actorID, reason, mutationID, effectiveAt }
    init(from decoder: any Decoder) throws {
        try FindingClosedCodingV1.requireClosed(decoder, allowed: CodingKeys.allCases.map(\.rawValue), required: CodingKeys.allCases.filter { $0 != .relationshipID }.map(\.rawValue)); let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else { throw FindingContractFailureV1.incompatibleVersion }
        try self.init(decisionID: c.decode(String.self, forKey: .decisionID), suggestionID: c.decode(String.self, forKey: .suggestionID), sourceWorkID: c.decode(String.self, forKey: .sourceWorkID), sourceWorkRevision: c.decode(Int.self, forKey: .sourceWorkRevision), candidateWorkID: c.decode(String.self, forKey: .candidateWorkID), candidateWorkRevision: c.decode(Int.self, forKey: .candidateWorkRevision), policySHA256: c.decode(String.self, forKey: .policySHA256), expectedDecisionRevision: c.decode(Int.self, forKey: .expectedDecisionRevision), resultingDecisionRevision: c.decode(Int.self, forKey: .resultingDecisionRevision), decision: c.decode(WorkRelationshipDecisionKindV1.self, forKey: .decision), relationshipID: c.decodeIfPresent(String.self, forKey: .relationshipID), actorID: c.decode(String.self, forKey: .actorID), reason: c.decode(String.self, forKey: .reason), mutationID: c.decode(String.self, forKey: .mutationID), effectiveAt: c.decode(String.self, forKey: .effectiveAt))
    }
}

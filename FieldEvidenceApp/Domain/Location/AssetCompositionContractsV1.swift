import Foundation

enum AssetCompositionRelationshipV1: String, Codable, CaseIterable, Sendable {
    case componentOf = "COMPONENT_OF"
}

enum AssetCompositionActionV1: String, Codable, CaseIterable, Sendable {
    case add = "ADD"
    case reparent = "REPARENT"
    case remove = "REMOVE"
    case semanticReversal = "SEMANTIC_REVERSAL"
}

struct AssetCompositionEdgeV1: Codable, Equatable, Identifiable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int; let id: UUID; let workspaceID: WorkspaceID; let parentAssetID: UUID; let childAssetID: UUID
    let relationship: AssetCompositionRelationshipV1; let isActive: Bool; let revision: UInt64; let edgeSHA256: String
    init(id: UUID, workspaceID: WorkspaceID, parentAssetID: UUID, childAssetID: UUID, relationship: AssetCompositionRelationshipV1 = .componentOf, isActive: Bool, revision: UInt64) throws {
        schemaVersion = Self.schemaVersion; self.id = id; self.workspaceID = workspaceID; self.parentAssetID = parentAssetID; self.childAssetID = childAssetID; self.relationship = relationship; self.isActive = isActive; self.revision = revision
        edgeSHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(schemaVersion: Self.schemaVersion, id: id, workspaceID: workspaceID, parentAssetID: parentAssetID, childAssetID: childAssetID, relationship: relationship, isActive: isActive, revision: revision)); try validate()
    }
    func validate() throws { try LocationContractValidationV1.requireID(id); try LocationContractValidationV1.requireID(parentAssetID); try LocationContractValidationV1.requireID(childAssetID); guard schemaVersion == Self.schemaVersion, parentAssetID != childAssetID, revision > 0, edgeSHA256 == (try WorkspaceMutationCanonicalV1.sha256(Basis(schemaVersion: schemaVersion, id: id, workspaceID: workspaceID, parentAssetID: parentAssetID, childAssetID: childAssetID, relationship: relationship, isActive: isActive, revision: revision))) else { throw LocationContractFailureV1.digestMismatch } }
    private struct Basis: Codable { let schemaVersion: Int; let id: UUID; let workspaceID: WorkspaceID; let parentAssetID: UUID; let childAssetID: UUID; let relationship: AssetCompositionRelationshipV1; let isActive: Bool; let revision: UInt64 }
    private enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, id, workspaceID, parentAssetID, childAssetID, relationship, isActive, revision, edgeSHA256 }
    init(from decoder: Decoder) throws { try LocationClosedCodingV1.require(decoder, keys: CodingKeys.self, required: Set(CodingKeys.allCases.map(\.rawValue))); let c = try decoder.container(keyedBy: CodingKeys.self); let rebuilt = try Self(id: c.decode(UUID.self, forKey: .id), workspaceID: c.decode(WorkspaceID.self, forKey: .workspaceID), parentAssetID: c.decode(UUID.self, forKey: .parentAssetID), childAssetID: c.decode(UUID.self, forKey: .childAssetID), relationship: c.decode(AssetCompositionRelationshipV1.self, forKey: .relationship), isActive: c.decode(Bool.self, forKey: .isActive), revision: c.decode(UInt64.self, forKey: .revision)); guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion, try c.decode(String.self, forKey: .edgeSHA256) == rebuilt.edgeSHA256 else { throw LocationContractFailureV1.digestMismatch }; self = rebuilt }
}

struct AssetCompositionEventV1: Codable, Equatable, Identifiable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int; let id: UUID; let workspaceID: WorkspaceID; let edge: AssetCompositionEdgeV1
    let predecessorEventID: UUID?; let action: AssetCompositionActionV1; let mutationID: MutationIDV1; let occurredAt: Date; let eventSHA256: String
    init(id: UUID, workspaceID: WorkspaceID, edge: AssetCompositionEdgeV1, predecessorEventID: UUID?, action: AssetCompositionActionV1, mutationID: MutationIDV1, occurredAt: Date) throws {
        schemaVersion = Self.schemaVersion; self.id = id; self.workspaceID = workspaceID; self.edge = edge; self.predecessorEventID = predecessorEventID; self.action = action; self.mutationID = mutationID; self.occurredAt = occurredAt
        eventSHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(schemaVersion: Self.schemaVersion, id: id, workspaceID: workspaceID, edge: edge, predecessorEventID: predecessorEventID, action: action, mutationID: mutationID, occurredAt: occurredAt)); try validate()
    }
    func validate() throws {
        try LocationContractValidationV1.requireID(id)
        try edge.validate()
        let activeStateMatchesAction: Bool
        switch action {
        case .add, .reparent:
            activeStateMatchesAction = edge.isActive
        case .remove:
            activeStateMatchesAction = !edge.isActive
        case .semanticReversal:
            activeStateMatchesAction = true
        }
        guard schemaVersion == Self.schemaVersion,
              edge.workspaceID == workspaceID,
              predecessorEventID != id,
              occurredAt.timeIntervalSinceReferenceDate.isFinite,
              activeStateMatchesAction,
              eventSHA256 == (try WorkspaceMutationCanonicalV1.sha256(Basis(schemaVersion: schemaVersion, id: id, workspaceID: workspaceID, edge: edge, predecessorEventID: predecessorEventID, action: action, mutationID: mutationID, occurredAt: occurredAt))) else {
            throw LocationContractFailureV1.invalidValue
        }
    }
    private struct Basis: Codable { let schemaVersion: Int; let id: UUID; let workspaceID: WorkspaceID; let edge: AssetCompositionEdgeV1; let predecessorEventID: UUID?; let action: AssetCompositionActionV1; let mutationID: MutationIDV1; let occurredAt: Date }
    private enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, id, workspaceID, edge, predecessorEventID, action, mutationID, occurredAt, eventSHA256 }
    init(from decoder: Decoder) throws { try LocationClosedCodingV1.require(decoder, keys: CodingKeys.self, required: Set(CodingKeys.allCases.filter { $0 != .predecessorEventID }.map(\.rawValue))); let c = try decoder.container(keyedBy: CodingKeys.self); let rebuilt = try Self(id: c.decode(UUID.self, forKey: .id), workspaceID: c.decode(WorkspaceID.self, forKey: .workspaceID), edge: c.decode(AssetCompositionEdgeV1.self, forKey: .edge), predecessorEventID: LocationClosedCodingV1.optional(UUID.self, from: c, forKey: .predecessorEventID), action: c.decode(AssetCompositionActionV1.self, forKey: .action), mutationID: c.decode(MutationIDV1.self, forKey: .mutationID), occurredAt: c.decode(Date.self, forKey: .occurredAt)); guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion, try c.decode(String.self, forKey: .eventSHA256) == rebuilt.eventSHA256 else { throw LocationContractFailureV1.digestMismatch }; self = rebuilt }
}

enum AssetCompositionHistoryV1 {
    static func validate(
        _ events: [AssetCompositionEventV1],
        currentEdge: AssetCompositionEdgeV1
    ) throws {
        guard !events.isEmpty,
              events.count <= LocationContractLimitsV1.maximumCollectionCount,
              Set(events.map(\.id)).count == events.count,
              Set(events.map(\.workspaceID)).count == 1,
              Set(events.map { $0.edge.id }).count == 1,
              Set(events.map { $0.edge.childAssetID }).count == 1,
              events.allSatisfy({ $0.workspaceID == currentEdge.workspaceID && $0.edge.id == currentEdge.id }) else {
            throw LocationContractFailureV1.hierarchyViolation
        }
        try events.forEach { try $0.validate() }
        let byID = Dictionary(uniqueKeysWithValues: events.map { ($0.id, $0) })
        let referenced = Set(events.compactMap(\.predecessorEventID))
        let roots = events.filter { $0.predecessorEventID == nil }
        let tips = events.filter { !referenced.contains($0.id) }
        guard roots.count == 1, tips.count == 1,
              roots[0].action == .add, roots[0].edge.isActive,
              roots[0].edge.revision == 1,
              tips[0].edge == currentEdge else {
            throw LocationContractFailureV1.hierarchyViolation
        }
        for event in events where event.predecessorEventID != nil {
            guard let predecessorID = event.predecessorEventID,
                  let predecessor = byID[predecessorID],
                  predecessor.occurredAt <= event.occurredAt,
                  event.edge.revision == predecessor.edge.revision + 1,
                  event.edge.childAssetID == predecessor.edge.childAssetID,
                  event.edge.relationship == predecessor.edge.relationship else {
                throw LocationContractFailureV1.hierarchyViolation
            }
            switch event.action {
            case .add:
                throw LocationContractFailureV1.hierarchyViolation
            case .reparent:
                guard predecessor.edge.isActive, event.edge.isActive,
                      event.edge.parentAssetID != predecessor.edge.parentAssetID else {
                    throw LocationContractFailureV1.hierarchyViolation
                }
            case .remove:
                guard predecessor.edge.isActive, !event.edge.isActive,
                      event.edge.parentAssetID == predecessor.edge.parentAssetID else {
                    throw LocationContractFailureV1.hierarchyViolation
                }
            case .semanticReversal:
                if let reversedBasisID = predecessor.predecessorEventID,
                   let reversedBasis = byID[reversedBasisID] {
                    guard event.edge.isActive == reversedBasis.edge.isActive,
                          event.edge.parentAssetID == reversedBasis.edge.parentAssetID,
                          event.edge.childAssetID == reversedBasis.edge.childAssetID,
                          event.edge.relationship == reversedBasis.edge.relationship else {
                        throw LocationContractFailureV1.hierarchyViolation
                    }
                } else {
                    // Reversing the root ADD restores the pre-edge state. The
                    // immutable edge remains as an inactive historical value.
                    guard predecessor.action == .add,
                          predecessor.edge.isActive,
                          !event.edge.isActive,
                          event.edge.parentAssetID == predecessor.edge.parentAssetID,
                          event.edge.childAssetID == predecessor.edge.childAssetID,
                          event.edge.relationship == predecessor.edge.relationship else {
                        throw LocationContractFailureV1.hierarchyViolation
                    }
                }
            }
        }
        var reached = Set<UUID>()
        var cursor: AssetCompositionEventV1? = tips[0]
        while let event = cursor {
            guard reached.insert(event.id).inserted else {
                throw LocationContractFailureV1.hierarchyViolation
            }
            cursor = event.predecessorEventID.flatMap { byID[$0] }
        }
        guard reached.count == events.count, reached.contains(roots[0].id) else {
            throw LocationContractFailureV1.hierarchyViolation
        }
    }
}

enum AssetCompositionPolicyV1 {
    static let maximumDepth = 8
    static func validate(edges: [AssetCompositionEdgeV1], placementByAssetID: [UUID: AssetPlacementEventV1]) throws {
        try edges.forEach { try $0.validate() }; let active = edges.filter(\.isActive)
        guard edges.count <= LocationContractLimitsV1.maximumCollectionCount, Set(edges.map(\.id)).count == edges.count,
              Set(active.map(\.childAssetID)).count == active.count else { throw LocationContractFailureV1.duplicateIdentity }
        let parentByChild = Dictionary(uniqueKeysWithValues: active.map { ($0.childAssetID, $0.parentAssetID) })
        for edge in active {
            guard let parentPlacement = placementByAssetID[edge.parentAssetID], let childPlacement = placementByAssetID[edge.childAssetID],
                  parentPlacement.workspaceID == edge.workspaceID, childPlacement.workspaceID == edge.workspaceID,
                  parentPlacement.siteID == childPlacement.siteID,
                  parentPlacement.locationNodeID == childPlacement.locationNodeID else { throw LocationContractFailureV1.hierarchyViolation }
            var cursor = edge.childAssetID; var visited = Set<UUID>(); var depth = 0
            while let parent = parentByChild[cursor] { guard visited.insert(cursor).inserted, parent != edge.childAssetID else { throw LocationContractFailureV1.hierarchyViolation }; depth += 1; guard depth <= maximumDepth else { throw LocationContractFailureV1.hierarchyViolation }; cursor = parent }
        }
    }
}

extension AssetCompositionEdgeV1 {
    /// Freezes the component identity only; it deliberately declares no new
    /// composition endpoint, cardinality, depth, or cycle policy.
    func frozenWorkSubjectReference() throws -> WorkSubjectReferenceV1 {
        try validate()
        guard isActive else { throw LocationContractFailureV1.invalidValue }
        let value = WorkSubjectReferenceV1(
            kind: .compositionComponent,
            subjectID: id,
            revision: revision,
            ownerAssetID: childAssetID
        )
        try value.validate()
        return value
    }
}

struct AssetPlacementTipBindingV1: Codable, Equatable, Comparable, Sendable {
    let assetID: UUID; let placement: AssetPlacementEventV1
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.assetID.uuidString.lowercased() < rhs.assetID.uuidString.lowercased() }
    init(assetID: UUID, placement: AssetPlacementEventV1) { self.assetID = assetID; self.placement = placement }
    private enum CodingKeys: String, CodingKey, CaseIterable { case assetID, placement }
    init(from decoder: Decoder) throws { try LocationClosedCodingV1.require(decoder, keys: CodingKeys.self, required: Set(CodingKeys.allCases.map(\.rawValue))); let c = try decoder.container(keyedBy: CodingKeys.self); let assetID = try c.decode(UUID.self, forKey: .assetID); let placement = try c.decode(AssetPlacementEventV1.self, forKey: .placement); guard assetID == placement.assetID else { throw LocationContractFailureV1.invalidValue }; self.init(assetID: assetID, placement: placement) }
}

struct AssetCompositionChangePlanV1: Codable, Equatable, Sendable {
    let operationID: UUID
    let mutationID: MutationIDV1
    let workspaceID: WorkspaceID
    let expectedRevision: WorkspaceExpectedRevisionV1
    let event: AssetCompositionEventV1
    let currentPlacementTips: [AssetPlacementTipBindingV1]
    var currentPlacementByAssetID: [UUID: AssetPlacementEventV1] { Dictionary(uniqueKeysWithValues: currentPlacementTips.map { ($0.assetID, $0.placement) }) }
    let resultingActiveEdges: [AssetCompositionEdgeV1]
    let planSHA256: String

    init(operationID: UUID, mutationID: MutationIDV1, workspaceID: WorkspaceID, expectedRevision: WorkspaceExpectedRevisionV1, event: AssetCompositionEventV1, currentPlacementByAssetID: [UUID: AssetPlacementEventV1], resultingActiveEdges: [AssetCompositionEdgeV1]) throws {
        self.operationID = operationID; self.mutationID = mutationID; self.workspaceID = workspaceID; self.expectedRevision = expectedRevision
        self.event = event; currentPlacementTips = currentPlacementByAssetID.map { AssetPlacementTipBindingV1(assetID: $0.key, placement: $0.value) }.sorted(); self.resultingActiveEdges = resultingActiveEdges
        planSHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(operationID: operationID, mutationID: mutationID, workspaceID: workspaceID, expectedRevision: expectedRevision, event: event, currentPlacementTips: currentPlacementTips, resultingActiveEdges: resultingActiveEdges))
        try validate()
    }

    func validate() throws {
        try LocationContractValidationV1.requireID(operationID); try event.validate(); try currentPlacementTips.forEach { try $0.placement.validate() }; try AssetCompositionPolicyV1.validate(edges: resultingActiveEdges, placementByAssetID: currentPlacementByAssetID)
        let currentResultEdge = resultingActiveEdges.first { $0.id == event.edge.id }
        guard expectedRevision.workspaceID == workspaceID, event.workspaceID == workspaceID, event.mutationID == mutationID,
              resultingActiveEdges.allSatisfy({ $0.workspaceID == workspaceID }), currentPlacementTips.allSatisfy({ $0.placement.workspaceID == workspaceID }),
              resultingActiveEdges.map(\.id.uuidString) == resultingActiveEdges.map(\.id.uuidString).sorted(),
              currentPlacementTips == currentPlacementTips.sorted(), Set(currentPlacementTips.map(\.assetID)).count == currentPlacementTips.count,
              currentPlacementTips.allSatisfy({ $0.assetID == $0.placement.assetID }),
              currentPlacementByAssetID[event.edge.parentAssetID] != nil,
              currentPlacementByAssetID[event.edge.childAssetID] != nil,
              ((event.edge.isActive && currentResultEdge == event.edge)
                || (!event.edge.isActive && currentResultEdge == nil)),
              planSHA256 == (try WorkspaceMutationCanonicalV1.sha256(Basis(operationID: operationID, mutationID: mutationID, workspaceID: workspaceID, expectedRevision: expectedRevision, event: event, currentPlacementTips: currentPlacementTips, resultingActiveEdges: resultingActiveEdges))) else { throw LocationContractFailureV1.digestMismatch }
    }

    private struct Basis: Codable { let operationID: UUID; let mutationID: MutationIDV1; let workspaceID: WorkspaceID; let expectedRevision: WorkspaceExpectedRevisionV1; let event: AssetCompositionEventV1; let currentPlacementTips: [AssetPlacementTipBindingV1]; let resultingActiveEdges: [AssetCompositionEdgeV1] }
    private enum CodingKeys: String, CodingKey, CaseIterable { case operationID, mutationID, workspaceID, expectedRevision, event, currentPlacementTips, resultingActiveEdges, planSHA256 }
    init(from decoder: Decoder) throws { try LocationClosedCodingV1.require(decoder, keys: CodingKeys.self, required: Set(CodingKeys.allCases.map(\.rawValue))); let c = try decoder.container(keyedBy: CodingKeys.self); let tips = try c.decode([AssetPlacementTipBindingV1].self, forKey: .currentPlacementTips); guard tips == tips.sorted(), Set(tips.map(\.assetID)).count == tips.count else { throw LocationContractFailureV1.unorderedValue }; let rebuilt = try Self(operationID: c.decode(UUID.self, forKey: .operationID), mutationID: c.decode(MutationIDV1.self, forKey: .mutationID), workspaceID: c.decode(WorkspaceID.self, forKey: .workspaceID), expectedRevision: c.decode(WorkspaceExpectedRevisionV1.self, forKey: .expectedRevision), event: c.decode(AssetCompositionEventV1.self, forKey: .event), currentPlacementByAssetID: Dictionary(uniqueKeysWithValues: tips.map { ($0.assetID, $0.placement) }), resultingActiveEdges: c.decode([AssetCompositionEdgeV1].self, forKey: .resultingActiveEdges)); guard try c.decode(String.self, forKey: .planSHA256) == rebuilt.planSHA256 else { throw LocationContractFailureV1.digestMismatch }; self = rebuilt }
}

/// C29 typed integration anchor: this owner consumes an exact immutable plan
/// revision reference and may not reinterpret current plan state implicitly.
enum C29PlanIntegration_Domain_Location_AssetCompositionContractsV1 {
    static func validatePlanRevision(_ value: PlanRevisionReferenceV1) throws {
        try value.validate()
    }
}

enum C37PoseIntegration_FieldEvidenceApp_Domain_Location_AssetCompositionContractsV1_swift {
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
enum C30ConsumerBoundaryV1_Domain_Location_AssetCompositionContractsV1 {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Domain/Location/AssetCompositionContractsV1.swift", role: .location)
}

enum C31LightingAssetCompositionBoundaryV1 {
    static let controlGroupMembershipIsRecordedTopology = true
    static let compositionDoesNotInferControlBehavior = true
    static let emptyOrpartialCompositionRemainsVisible = true
}
// MARK: - C32 assistance asset composition boundary

enum C32AssistanceLifecycleBoundary_FieldEvidenceApp_Domain_Location_AssetCompositionContractsV1_swift {
    static let proposalIsPersistent = AssistancePersistenceEnrollmentV1.proposalIsPersistent
    static let rejectedProposalCorpusIsPersistent = AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent
    static let durableFamilyCount = AssistancePersistenceEnrollmentV1.durableModelCount
    static let acceptedMutationKind: WorkspaceCommandKindV1 = .applyAssistanceAcceptance
    static let manualFallback: ManualFallbackActionV1 = .typeManually
    static let proposalCannotCreateCompositionEdge = true

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

import Foundation

struct CompletedLocationCompositionSnapshotV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int; let workspaceID: WorkspaceID; let assetID: UUID
    let locationPath: LocationPathSnapshotV1; let placementTips: [AssetPlacementTipBindingV1]
    let compositionEdges: [AssetCompositionEdgeV1]
    let frozenAtRevision: UInt64; let snapshotSHA256: String
    init(workspaceID: WorkspaceID, assetID: UUID, locationPath: LocationPathSnapshotV1, placementTips: [AssetPlacementTipBindingV1], compositionEdges: [AssetCompositionEdgeV1], frozenAtRevision: UInt64) throws {
        schemaVersion = Self.schemaVersion; self.workspaceID = workspaceID; self.assetID = assetID; self.locationPath = locationPath; self.placementTips = placementTips; self.compositionEdges = compositionEdges; self.frozenAtRevision = frozenAtRevision
        snapshotSHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(schemaVersion: Self.schemaVersion, workspaceID: workspaceID, assetID: assetID, locationPath: locationPath, placementTips: placementTips, compositionEdges: compositionEdges, frozenAtRevision: frozenAtRevision)); try validate()
    }
    func validate() throws {
        try locationPath.validate(); try placementTips.forEach { try $0.placement.validate() }; try compositionEdges.forEach { try $0.validate() }
        guard placementTips == placementTips.sorted(),
              Set(placementTips.map(\.assetID)).count == placementTips.count,
              placementTips.allSatisfy({ $0.assetID == $0.placement.assetID }) else {
            throw LocationContractFailureV1.duplicateIdentity
        }
        let placements = Dictionary(uniqueKeysWithValues: placementTips.map { ($0.assetID, $0.placement) })
        let closure = Self.compositionClosure(containing: assetID, edges: compositionEdges)
        let subjectPlacement = placements[assetID]
        try AssetCompositionPolicyV1.validate(edges: compositionEdges, placementByAssetID: placements)
        guard schemaVersion == Self.schemaVersion, frozenAtRevision > 0,
              Set(placementTips.map(\.assetID)) == closure,
              subjectPlacement?.siteID == locationPath.siteID,
              subjectPlacement?.locationNodeID == locationPath.nodes.last?.nodeID,
              placementTips.allSatisfy({ $0.placement.workspaceID == workspaceID }),
              compositionEdges.map(\.id.uuidString) == compositionEdges.map(\.id.uuidString).sorted(),
              Set(compositionEdges.map(\.id)).count == compositionEdges.count,
              compositionEdges.allSatisfy({ $0.workspaceID == workspaceID && $0.isActive }),
              snapshotSHA256 == (try WorkspaceMutationCanonicalV1.sha256(Basis(schemaVersion: schemaVersion, workspaceID: workspaceID, assetID: assetID, locationPath: locationPath, placementTips: placementTips, compositionEdges: compositionEdges, frozenAtRevision: frozenAtRevision))) else { throw LocationContractFailureV1.digestMismatch }
    }
    static func build(workspaceID: WorkspaceID, assetID: UUID, currentLocationPath: LocationPathSnapshotV1, currentPlacementByAssetID: [UUID: AssetPlacementEventV1], activeCompositionEdges: [AssetCompositionEdgeV1], frozenAtRevision: UInt64) throws -> Self {
        guard activeCompositionEdges.allSatisfy(\.isActive) else { throw LocationContractFailureV1.invalidValue }
        let closure = compositionClosure(containing: assetID, edges: activeCompositionEdges)
        guard currentPlacementByAssetID[assetID] != nil,
              closure.allSatisfy({ currentPlacementByAssetID[$0] != nil }) else { throw LocationContractFailureV1.hierarchyViolation }
        let tips = closure.map { AssetPlacementTipBindingV1(assetID: $0, placement: currentPlacementByAssetID[$0]!) }.sorted()
        let edges = activeCompositionEdges.filter { closure.contains($0.parentAssetID) && closure.contains($0.childAssetID) }.sorted { $0.id.uuidString < $1.id.uuidString }
        return try Self(workspaceID: workspaceID, assetID: assetID, locationPath: currentLocationPath, placementTips: tips, compositionEdges: edges, frozenAtRevision: frozenAtRevision)
    }
    private static func compositionClosure(containing assetID: UUID, edges: [AssetCompositionEdgeV1]) -> Set<UUID> {
        var result: Set<UUID> = [assetID]; var changed = true
        while changed { changed = false; for edge in edges where edge.isActive && (result.contains(edge.parentAssetID) || result.contains(edge.childAssetID)) { changed = result.insert(edge.parentAssetID).inserted || changed; changed = result.insert(edge.childAssetID).inserted || changed } }
        return result
    }
    private struct Basis: Codable { let schemaVersion: Int; let workspaceID: WorkspaceID; let assetID: UUID; let locationPath: LocationPathSnapshotV1; let placementTips: [AssetPlacementTipBindingV1]; let compositionEdges: [AssetCompositionEdgeV1]; let frozenAtRevision: UInt64 }
    private enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, workspaceID, assetID, locationPath, placementTips, compositionEdges, frozenAtRevision, snapshotSHA256 }
    init(from decoder: Decoder) throws { try LocationClosedCodingV1.require(decoder, keys: CodingKeys.self, required: Set(CodingKeys.allCases.map(\.rawValue))); let c = try decoder.container(keyedBy: CodingKeys.self); let rebuilt = try Self(workspaceID: c.decode(WorkspaceID.self, forKey: .workspaceID), assetID: c.decode(UUID.self, forKey: .assetID), locationPath: c.decode(LocationPathSnapshotV1.self, forKey: .locationPath), placementTips: c.decode([AssetPlacementTipBindingV1].self, forKey: .placementTips), compositionEdges: c.decode([AssetCompositionEdgeV1].self, forKey: .compositionEdges), frozenAtRevision: c.decode(UInt64.self, forKey: .frozenAtRevision)); guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion, try c.decode(String.self, forKey: .snapshotSHA256) == rebuilt.snapshotSHA256 else { throw LocationContractFailureV1.digestMismatch }; self = rebuilt }
}

/// C29 typed integration anchor: this owner consumes an exact immutable plan
/// revision reference and may not reinterpret current plan state implicitly.
enum C29PlanIntegration_Domain_Location_CompletedLocationCompositionSnapshotV1 {
    static func validatePlanRevision(_ value: PlanRevisionReferenceV1) throws {
        try value.validate()
    }
}

enum C37PoseIntegration_FieldEvidenceApp_Domain_Location_CompletedLocationCompositionSnapshotV1_swift {
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
enum C30ConsumerBoundaryV1_Domain_Location_CompletedLocationCompositionSnapshotV1 {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Domain/Location/CompletedLocationCompositionSnapshotV1.swift", role: .location)
}

enum C31LightingLocationSnapshotBoundaryV1 {
    static let completedCompositionIsFrozenForDisplay = true
    static let snapshotCarriesNoOriginalBytes = true
    static let partialTopologyDoesNotBecomeAClaim = true
}

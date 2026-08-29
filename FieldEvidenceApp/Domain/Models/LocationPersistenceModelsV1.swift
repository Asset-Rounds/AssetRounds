import Foundation
enum EvidenceContextLocationBoundaryV1{static let derivedSolarContextUsesFrozenLocationInput=true;static let locationHistoryIsNotRewritten=true}
enum PlacementPoseLocationPersistenceBoundaryV1{static let poseEventsMustBindAnExactAssetPlacementEvent=true;static let poseHistoryNeverRewritesPlacementHistory=true}
import SwiftData

enum PlanLocationPersistenceBindingV1 { static let locationPlacementUsesStableSubjectIdentity = true; static let hierarchyRebaseDoesNotRewritePlanHistory = true }

enum LocationPersistenceReleaseV1: Int, Codable, CaseIterable, Sendable {
    case v6 = 6
    static let predecessorSchemaVersion = 5
}

enum LocationPersistenceCodecV1 {
    static func encode<T: Encodable>(_ value: T) throws -> Data { try WorkspaceMutationCanonicalV1.data(value) }
    static func decode<T: Codable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        let value = try decoder.decode(T.self, from: data)
        guard try encode(value) == data else { throw LocationContractFailureV1.digestMismatch }
        return value
    }
}

@Model
final class LocationNodeRow {
    @Attribute(.unique) var id: UUID
    var workspaceID: UUID; var siteID: UUID; var parentNodeID: UUID?; var kind: String
    var label: String; var shortCode: String?; var siblingOrder: Int; var state: String; var revision: Int64
    var mutationID: UUID; var occurredAt: Date; var canonicalData: Data

    init(_ value: LocationNodeV1) throws {
        try value.validate(); guard value.revision <= UInt64(Int64.max) else { throw LocationContractFailureV1.limitExceeded }
        id = value.id; workspaceID = value.workspaceID.rawValue; siteID = value.siteID; parentNodeID = value.parentNodeID
        kind = value.kind.rawValue; label = value.label; shortCode = value.shortCode; siblingOrder = value.siblingOrder
        state = value.state.rawValue; revision = Int64(value.revision); mutationID = value.provenance.mutationID.rawValue
        occurredAt = value.provenance.occurredAt
        canonicalData = try LocationPersistenceCodecV1.encode(value)
    }
    func value() throws -> LocationNodeV1 {
        guard revision > 0 else { throw LocationContractFailureV1.invalidValue }
        let value = try LocationPersistenceCodecV1.decode(LocationNodeV1.self, from: canonicalData)
        guard value.id == id, value.workspaceID.rawValue == workspaceID, value.siteID == siteID,
              value.parentNodeID == parentNodeID, value.kind.rawValue == kind, value.label == label,
              value.shortCode == shortCode, value.siblingOrder == siblingOrder, value.state.rawValue == state,
              value.revision == UInt64(revision), value.provenance.mutationID.rawValue == mutationID,
              value.provenance.occurredAt == occurredAt else {
            throw LocationContractFailureV1.digestMismatch
        }
        return value
    }
}

@Model
final class LocationHierarchyEventRow {
    @Attribute(.unique) var operationID: UUID
    var workspaceID: UUID; var planSHA256: String; var mutationReceiptIdentity: String
    var mutationReceiptSHA256: String?; var committedAt: Date; var planData: Data; var receiptData: Data
    init(plan: LocationHierarchyChangePlanV1, receipt: LocationHierarchyChangeReceiptV1) throws {
        try plan.validate(); guard receipt.planSHA256 == plan.planSHA256,
              receipt.mutationReceiptIdentity.workspaceID == plan.workspaceID else { throw LocationContractFailureV1.invalidValue }
        operationID = plan.operationID; workspaceID = plan.workspaceID.rawValue; planSHA256 = plan.planSHA256
        mutationReceiptIdentity = receipt.mutationReceiptIdentity.stableKey; mutationReceiptSHA256 = receipt.mutationReceiptSHA256
        committedAt = receipt.committedAt; planData = try LocationPersistenceCodecV1.encode(plan); receiptData = try LocationPersistenceCodecV1.encode(receipt)
    }
    func values() throws -> (plan: LocationHierarchyChangePlanV1, receipt: LocationHierarchyChangeReceiptV1) {
        let plan = try LocationPersistenceCodecV1.decode(LocationHierarchyChangePlanV1.self, from: planData)
        let receipt = try LocationPersistenceCodecV1.decode(LocationHierarchyChangeReceiptV1.self, from: receiptData)
        guard plan.operationID == operationID, plan.workspaceID.rawValue == workspaceID, plan.planSHA256 == planSHA256,
              receipt.planSHA256 == planSHA256, receipt.mutationReceiptIdentity.stableKey == mutationReceiptIdentity,
              receipt.mutationReceiptSHA256 == mutationReceiptSHA256, receipt.committedAt == committedAt else { throw LocationContractFailureV1.digestMismatch }
        return (plan, receipt)
    }
}

@Model
final class AssetPlacementEventRow {
    @Attribute(.unique) var id: UUID
    var workspaceID: UUID; var assetID: UUID; var siteID: UUID; var locationNodeID: UUID?; var predecessorEventID: UUID?
    var source: String; var physicalEpisodeID: UUID; var continuity: String; var mutationID: UUID
    var occurredAt: Date; var eventSHA256: String; var canonicalData: Data
    init(_ value: AssetPlacementEventV1) throws {
        try value.validate(); id = value.id; workspaceID = value.workspaceID.rawValue; assetID = value.assetID; siteID = value.siteID
        locationNodeID = value.locationNodeID; predecessorEventID = value.predecessorEventID; source = value.source.rawValue
        physicalEpisodeID = value.physicalEpisodeID.rawValue; continuity = value.continuity.rawValue; mutationID = value.mutationID.rawValue
        occurredAt = value.occurredAt; eventSHA256 = value.eventSHA256; canonicalData = try LocationPersistenceCodecV1.encode(value)
    }
    func value() throws -> AssetPlacementEventV1 {
        let value = try LocationPersistenceCodecV1.decode(AssetPlacementEventV1.self, from: canonicalData); try value.validate()
        guard value.id == id, value.workspaceID.rawValue == workspaceID, value.assetID == assetID, value.siteID == siteID,
              value.locationNodeID == locationNodeID, value.predecessorEventID == predecessorEventID,
              value.source.rawValue == source, value.physicalEpisodeID.rawValue == physicalEpisodeID,
              value.continuity.rawValue == continuity, value.mutationID.rawValue == mutationID,
              value.occurredAt == occurredAt, value.eventSHA256 == eventSHA256 else { throw LocationContractFailureV1.digestMismatch }
        return value
    }
}

@Model
final class AssetCompositionEdgeRow {
    @Attribute(.unique) var id: UUID
    var workspaceID: UUID; var parentAssetID: UUID; var childAssetID: UUID; var relationship: String
    var isActive: Bool; var revision: Int64; var edgeSHA256: String; var canonicalData: Data
    init(_ value: AssetCompositionEdgeV1) throws {
        try value.validate(); guard value.revision <= UInt64(Int64.max) else { throw LocationContractFailureV1.limitExceeded }
        id = value.id; workspaceID = value.workspaceID.rawValue; parentAssetID = value.parentAssetID; childAssetID = value.childAssetID
        relationship = value.relationship.rawValue; isActive = value.isActive; revision = Int64(value.revision); edgeSHA256 = value.edgeSHA256
        canonicalData = try LocationPersistenceCodecV1.encode(value)
    }
    func value() throws -> AssetCompositionEdgeV1 {
        guard revision > 0 else { throw LocationContractFailureV1.invalidValue }
        let value = try LocationPersistenceCodecV1.decode(AssetCompositionEdgeV1.self, from: canonicalData); try value.validate()
        guard value.id == id, value.workspaceID.rawValue == workspaceID, value.parentAssetID == parentAssetID,
              value.childAssetID == childAssetID, value.relationship.rawValue == relationship,
              value.isActive == isActive, value.revision == UInt64(revision), value.edgeSHA256 == edgeSHA256 else { throw LocationContractFailureV1.digestMismatch }
        return value
    }
}

@Model
final class AssetCompositionEventRow {
    @Attribute(.unique) var id: UUID
    var workspaceID: UUID; var edgeID: UUID; var predecessorEventID: UUID?; var action: String
    var mutationID: UUID; var occurredAt: Date; var eventSHA256: String; var canonicalData: Data
    init(_ value: AssetCompositionEventV1) throws {
        try value.validate(); id = value.id; workspaceID = value.workspaceID.rawValue; edgeID = value.edge.id
        predecessorEventID = value.predecessorEventID; action = value.action.rawValue; mutationID = value.mutationID.rawValue
        occurredAt = value.occurredAt; eventSHA256 = value.eventSHA256; canonicalData = try LocationPersistenceCodecV1.encode(value)
    }
    func value() throws -> AssetCompositionEventV1 {
        let value = try LocationPersistenceCodecV1.decode(AssetCompositionEventV1.self, from: canonicalData); try value.validate()
        guard value.id == id, value.workspaceID.rawValue == workspaceID, value.edge.id == edgeID,
              value.predecessorEventID == predecessorEventID, value.action.rawValue == action,
              value.mutationID.rawValue == mutationID, value.occurredAt == occurredAt, value.eventSHA256 == eventSHA256 else { throw LocationContractFailureV1.digestMismatch }
        return value
    }
}

struct LocationMigratedBaselineBindingV1: Codable, Equatable, Comparable, Sendable {
    let assetID: UUID; let siteID: UUID; let placementEventID: UUID; let physicalEpisodeID: PhysicalPlacementEpisodeIDV1
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.assetID.uuidString.lowercased() < rhs.assetID.uuidString.lowercased() }
    init(assetID: UUID, siteID: UUID, placementEventID: UUID, physicalEpisodeID: PhysicalPlacementEpisodeIDV1) { self.assetID = assetID; self.siteID = siteID; self.placementEventID = placementEventID; self.physicalEpisodeID = physicalEpisodeID }
    private enum CodingKeys: String, CodingKey, CaseIterable { case assetID, siteID, placementEventID, physicalEpisodeID }
    init(from decoder: Decoder) throws { try LocationClosedCodingV1.require(decoder, keys: CodingKeys.self, required: Set(CodingKeys.allCases.map(\.rawValue))); let c = try decoder.container(keyedBy: CodingKeys.self); let assetID = try c.decode(UUID.self, forKey: .assetID); let siteID = try c.decode(UUID.self, forKey: .siteID); let placementEventID = try c.decode(UUID.self, forKey: .placementEventID); try LocationContractValidationV1.requireID(assetID); try LocationContractValidationV1.requireID(siteID); try LocationContractValidationV1.requireID(placementEventID); self.init(assetID: assetID, siteID: siteID, placementEventID: placementEventID, physicalEpisodeID: try c.decode(PhysicalPlacementEpisodeIDV1.self, forKey: .physicalEpisodeID)) }
}

struct LocationMigrationReceiptV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int; let workspaceID: WorkspaceID; let sourceGenerationID: UUID; let candidateGenerationID: UUID
    let sourceSchemaVersion: Int; let targetSchemaVersion: Int; let sourceSiteCount: Int; let sourceAssetCount: Int
    let bindings: [LocationMigratedBaselineBindingV1]; let receiptSHA256: String
    init(workspaceID: WorkspaceID, sourceGenerationID: UUID, candidateGenerationID: UUID, sourceSiteCount: Int, sourceAssetCount: Int, bindings: [LocationMigratedBaselineBindingV1]) throws {
        schemaVersion = Self.schemaVersion; self.workspaceID = workspaceID; self.sourceGenerationID = sourceGenerationID; self.candidateGenerationID = candidateGenerationID
        sourceSchemaVersion = LocationPersistenceReleaseV1.predecessorSchemaVersion; targetSchemaVersion = LocationPersistenceReleaseV1.v6.rawValue
        self.sourceSiteCount = sourceSiteCount; self.sourceAssetCount = sourceAssetCount; self.bindings = bindings
        receiptSHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(workspaceID: workspaceID, sourceGenerationID: sourceGenerationID, candidateGenerationID: candidateGenerationID, sourceSiteCount: sourceSiteCount, sourceAssetCount: sourceAssetCount, bindings: bindings))
        try validate()
    }
    func validate() throws {
        try LocationContractValidationV1.requireID(sourceGenerationID); try LocationContractValidationV1.requireID(candidateGenerationID)
        guard schemaVersion == Self.schemaVersion, sourceGenerationID != candidateGenerationID, sourceSchemaVersion == 5, targetSchemaVersion == 6,
              sourceSiteCount >= 0, sourceAssetCount >= 0, bindings.count == sourceAssetCount, bindings == bindings.sorted(),
              bindings.allSatisfy({ $0.assetID != LocationContractValidationV1.zero && $0.siteID != LocationContractValidationV1.zero && $0.placementEventID != LocationContractValidationV1.zero }),
              Set(bindings.map(\.assetID)).count == bindings.count, Set(bindings.map(\.placementEventID)).count == bindings.count,
              receiptSHA256 == (try WorkspaceMutationCanonicalV1.sha256(Basis(workspaceID: workspaceID, sourceGenerationID: sourceGenerationID, candidateGenerationID: candidateGenerationID, sourceSiteCount: sourceSiteCount, sourceAssetCount: sourceAssetCount, bindings: bindings))) else { throw LocationContractFailureV1.digestMismatch }
    }
    private struct Basis: Codable { let workspaceID: WorkspaceID; let sourceGenerationID: UUID; let candidateGenerationID: UUID; let sourceSiteCount: Int; let sourceAssetCount: Int; let bindings: [LocationMigratedBaselineBindingV1] }
    private enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, workspaceID, sourceGenerationID, candidateGenerationID, sourceSchemaVersion, targetSchemaVersion, sourceSiteCount, sourceAssetCount, bindings, receiptSHA256 }
    init(from decoder: Decoder) throws { try LocationClosedCodingV1.require(decoder, keys: CodingKeys.self, required: Set(CodingKeys.allCases.map(\.rawValue))); let c = try decoder.container(keyedBy: CodingKeys.self); let rebuilt = try Self(workspaceID: c.decode(WorkspaceID.self, forKey: .workspaceID), sourceGenerationID: c.decode(UUID.self, forKey: .sourceGenerationID), candidateGenerationID: c.decode(UUID.self, forKey: .candidateGenerationID), sourceSiteCount: c.decode(Int.self, forKey: .sourceSiteCount), sourceAssetCount: c.decode(Int.self, forKey: .sourceAssetCount), bindings: c.decode([LocationMigratedBaselineBindingV1].self, forKey: .bindings)); guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion, try c.decode(Int.self, forKey: .sourceSchemaVersion) == 5, try c.decode(Int.self, forKey: .targetSchemaVersion) == 6, try c.decode(String.self, forKey: .receiptSHA256) == rebuilt.receiptSHA256 else { throw LocationContractFailureV1.digestMismatch }; self = rebuilt }
}

enum LocationMigrationIntegrityV1 {
    static func validate(
        receipt: LocationMigrationReceiptV1?,
        placementEvents: [AssetPlacementEventV1],
        knownAssetIDs: Set<UUID>,
        liveAssetSiteByID: [UUID: UUID]
    ) throws {
        let baselines = placementEvents.filter { $0.source == .migratedBaseline }
        guard Set(liveAssetSiteByID.keys).isSubset(of: knownAssetIDs) else {
            throw LocationContractFailureV1.hierarchyViolation
        }
        guard let receipt else {
            guard baselines.isEmpty else { throw LocationContractFailureV1.hierarchyViolation }
            return
        }
        try receipt.validate()
        let bindingsByEventID = Dictionary(uniqueKeysWithValues: receipt.bindings.map { ($0.placementEventID, $0) })
        guard baselines.count == receipt.sourceAssetCount,
              baselines.count == receipt.bindings.count,
              Set(baselines.map(\.id)) == Set(bindingsByEventID.keys),
              Set(baselines.map(\.assetID)) == Set(receipt.bindings.map(\.assetID)),
              Set(receipt.bindings.map(\.assetID)).isSubset(of: knownAssetIDs) else {
            throw LocationContractFailureV1.hierarchyViolation
        }
        for event in baselines {
            let liveSiteID = liveAssetSiteByID[event.assetID]
            guard let binding = bindingsByEventID[event.id],
                  event.workspaceID == receipt.workspaceID,
                  event.assetID == binding.assetID,
                  event.siteID == binding.siteID,
                  event.locationNodeID == nil,
                  event.predecessorEventID == nil,
                  event.physicalEpisodeID == binding.physicalEpisodeID,
                  knownAssetIDs.contains(event.assetID),
                  liveSiteID == nil || liveSiteID == event.siteID else {
                throw LocationContractFailureV1.hierarchyViolation
            }
        }
    }
}

@Model
final class LocationMigrationReceiptRow {
    @Attribute(.unique) var candidateGenerationID: UUID
    var workspaceID: UUID; var sourceGenerationID: UUID; var sourceSchemaVersion: Int; var targetSchemaVersion: Int
    var sourceSiteCount: Int; var sourceAssetCount: Int; var receiptSHA256: String; var canonicalData: Data
    init(_ value: LocationMigrationReceiptV1) throws {
        try value.validate(); candidateGenerationID = value.candidateGenerationID; workspaceID = value.workspaceID.rawValue
        sourceGenerationID = value.sourceGenerationID; sourceSchemaVersion = value.sourceSchemaVersion; targetSchemaVersion = value.targetSchemaVersion
        sourceSiteCount = value.sourceSiteCount; sourceAssetCount = value.sourceAssetCount; receiptSHA256 = value.receiptSHA256
        canonicalData = try LocationPersistenceCodecV1.encode(value)
    }
    func value() throws -> LocationMigrationReceiptV1 {
        let value = try LocationPersistenceCodecV1.decode(LocationMigrationReceiptV1.self, from: canonicalData); try value.validate()
        guard value.candidateGenerationID == candidateGenerationID, value.workspaceID.rawValue == workspaceID,
              value.sourceGenerationID == sourceGenerationID, value.sourceSchemaVersion == sourceSchemaVersion,
              value.targetSchemaVersion == targetSchemaVersion, value.sourceSiteCount == sourceSiteCount,
              value.sourceAssetCount == sourceAssetCount, value.receiptSHA256 == receiptSHA256 else { throw LocationContractFailureV1.digestMismatch }
        return value
    }
}

enum LightingLocationTopologyReuseV1 { static let systemAggregateReferencesExistingLocationSubjects = true; static let createsNoParallelLocationGraph = true }

enum C31LightingLocationPersistenceBoundaryV1 {
    static let locationHierarchyRemainsCanonical = true
    static let topologyCarriesStableLocationReferences = true
    static let geometryAndPrivateLocatorsAreNotCopied = true
}
// MARK: - C32 assistance location persistence boundary

enum C32AssistanceLifecycleBoundary_FieldEvidenceApp_Domain_Models_LocationPersistenceModelsV1_swift {
    static let proposalIsPersistent = AssistancePersistenceEnrollmentV1.proposalIsPersistent
    static let rejectedProposalCorpusIsPersistent = AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent
    static let durableFamilyCount = AssistancePersistenceEnrollmentV1.durableModelCount
    static let acceptedMutationKind: WorkspaceCommandKindV1 = .applyAssistanceAcceptance
    static let manualFallback: ManualFallbackActionV1 = .typeManually
    static let acceptedLocationUsesExistingRows = true

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

enum C33TemporalEvidenceBoundary_Domain_Models_LocationPersistenceModelsV1_V1 {
    static let clipType: TemporalEvidenceClipV1.Type = TemporalEvidenceClipV1.self
    static let anchorType: TimecodedEvidenceAnchorV1.Type = TimecodedEvidenceAnchorV1.self
    static let persistentSchemaVersion: Int =
        TemporalEvidencePersistenceEnrollmentV1.persistentSchemaVersion
}

// MARK: - C45 canonical asset-label integration
enum C45AssetLabelBoundary_Row148 {
    static let reusesCanonicalAssetLocatorAndWriter = true
    static func validateAcceptedSnapshot(_ snapshot: AcceptedLabelGenerationSnapshotV1) throws {
        try snapshot.validate()
    }
}

enum C46LocationPersistenceBoundaryV1 {
    static let handoffDestinationCreatesLocationRow = false
    static let routeOrIntentStoresAddressOrCoordinate = false
    static let platformOutcomeCreatesLocationRow = false
    static func validateEphemeral(_ value: SiteDirectionsTargetSnapshotV1) throws {
        guard value.currentTarget.kind == .site else {
            throw OperationalContactFailureV1.invalidHandoffTarget
        }
        _ = try value.preferredDestination()
    }
}

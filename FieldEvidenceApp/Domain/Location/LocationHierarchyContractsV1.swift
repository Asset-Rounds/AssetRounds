import Foundation

enum LocationContractFailureV1: Error, Equatable, Sendable {
    case invalidValue
    case incompatibleVersion
    case unknownKey
    case missingKey
    case duplicateIdentity
    case unorderedValue
    case hierarchyViolation
    case staleRevision
    case digestMismatch
    case reviewRequired
    case limitExceeded
}

enum LocationContractLimitsV1 {
    static let maximumHierarchyDepth = 8
    static let maximumCompositionDepth = 8
    static let maximumTextBytes = 4_096
    static let maximumShortCodeBytes = 64
    static let maximumCollectionCount = 100_000
}

enum LocationContractValidationV1 {
    static let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    static func requireID(_ value: UUID) throws {
        guard value != zero else { throw LocationContractFailureV1.invalidValue }
    }

    static func requireText(_ value: String, maximumBytes: Int = LocationContractLimitsV1.maximumTextBytes) throws {
        guard !value.isEmpty, value.utf8.count <= maximumBytes,
              value == value.precomposedStringWithCanonicalMapping else {
            throw LocationContractFailureV1.invalidValue
        }
        for scalar in value.unicodeScalars {
            let n = scalar.value
            guard n >= 0x20, n != 0x7f, !(0x80...0x9f).contains(n),
                  ![0x202a, 0x202b, 0x202c, 0x202d, 0x202e, 0x2066, 0x2067, 0x2068, 0x2069].contains(n),
                  (n & 0xffff) != 0xfffe, (n & 0xffff) != 0xffff else {
                throw LocationContractFailureV1.invalidValue
            }
        }
    }

    static func requireSortedUnique<T: Comparable & Hashable>(_ values: [T]) throws {
        guard values.count <= LocationContractLimitsV1.maximumCollectionCount,
              values == values.sorted(), Set(values).count == values.count else {
            throw LocationContractFailureV1.unorderedValue
        }
    }

    static func requireDigest(_ value: String) throws {
        guard value.count == 64, value.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else {
            throw LocationContractFailureV1.digestMismatch
        }
    }
}

enum LocationClosedCodingV1 {
    static func require<Key: CodingKey & CaseIterable>(
        _ decoder: Decoder,
        keys: Key.Type,
        required: Set<String>
    ) throws where Key.AllCases: Collection {
        let raw = try decoder.container(keyedBy: LocationAnyCodingKeyV1.self)
        let allowed = Set(Key.allCases.map(\.stringValue))
        guard Set(raw.allKeys.map(\.stringValue)).isSubset(of: allowed) else {
            throw LocationContractFailureV1.unknownKey
        }
        guard required.isSubset(of: Set(raw.allKeys.map(\.stringValue))) else {
            throw LocationContractFailureV1.missingKey
        }
    }

    static func optional<T: Decodable, Key: CodingKey>(
        _ type: T.Type,
        from container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) throws -> T? {
        guard container.contains(key) else { return nil }
        guard try !container.decodeNil(forKey: key) else { throw LocationContractFailureV1.invalidValue }
        return try container.decode(T.self, forKey: key)
    }
}

private struct LocationAnyCodingKeyV1: CodingKey {
    let stringValue: String
    let intValue: Int?
    init?(stringValue: String) { self.stringValue = stringValue; intValue = nil }
    init?(intValue: Int) { stringValue = String(intValue); self.intValue = intValue }
}

enum LocationKindV1: String, Codable, CaseIterable, Hashable, Sendable {
    case campus = "CAMPUS"
    case building = "BUILDING"
    case level = "LEVEL"
    case area = "AREA"
    case zone = "ZONE"
    case exteriorArea = "EXTERIOR_AREA"
    case other = "OTHER"
}

enum LocationNodeStateV1: String, Codable, CaseIterable, Sendable {
    case active = "ACTIVE"
    case archived = "ARCHIVED"
}

struct LocationMutationProvenanceV1: Codable, Equatable, Sendable {
    let mutationID: MutationIDV1
    let occurredAt: Date

    init(mutationID: MutationIDV1, occurredAt: Date) throws {
        guard occurredAt.timeIntervalSinceReferenceDate.isFinite else { throw LocationContractFailureV1.invalidValue }
        self.mutationID = mutationID; self.occurredAt = occurredAt
    }
    private enum CodingKeys: String, CodingKey, CaseIterable { case mutationID, occurredAt }
    init(from decoder: Decoder) throws { try LocationClosedCodingV1.require(decoder, keys: CodingKeys.self, required: Set(CodingKeys.allCases.map(\.rawValue))); let c = try decoder.container(keyedBy: CodingKeys.self); try self.init(mutationID: c.decode(MutationIDV1.self, forKey: .mutationID), occurredAt: c.decode(Date.self, forKey: .occurredAt)) }
}

struct LocationNodeV1: Codable, Equatable, Identifiable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let id: UUID
    let workspaceID: WorkspaceID
    let siteID: UUID
    let parentNodeID: UUID?
    let kind: LocationKindV1
    let label: String
    let shortCode: String?
    let siblingOrder: Int
    let state: LocationNodeStateV1
    let revision: UInt64
    let provenance: LocationMutationProvenanceV1

    init(id: UUID, workspaceID: WorkspaceID, siteID: UUID, parentNodeID: UUID?, kind: LocationKindV1, label: String, shortCode: String?, siblingOrder: Int, state: LocationNodeStateV1, revision: UInt64, provenance: LocationMutationProvenanceV1) throws {
        schemaVersion = Self.schemaVersion; self.id = id; self.workspaceID = workspaceID; self.siteID = siteID
        self.parentNodeID = parentNodeID; self.kind = kind; self.label = label; self.shortCode = shortCode
        self.siblingOrder = siblingOrder; self.state = state; self.revision = revision; self.provenance = provenance
        try validate()
    }

    func validate() throws {
        try LocationContractValidationV1.requireID(id); try LocationContractValidationV1.requireID(workspaceID.rawValue)
        try LocationContractValidationV1.requireID(siteID); if let parentNodeID { try LocationContractValidationV1.requireID(parentNodeID) }
        try LocationContractValidationV1.requireText(label)
        if let shortCode { try LocationContractValidationV1.requireText(shortCode, maximumBytes: LocationContractLimitsV1.maximumShortCodeBytes) }
        guard schemaVersion == Self.schemaVersion, parentNodeID != id, siblingOrder >= 0, revision > 0 else { throw LocationContractFailureV1.invalidValue }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, id, workspaceID, siteID, parentNodeID, kind, label, shortCode, siblingOrder, state, revision, provenance }
    init(from decoder: Decoder) throws {
        try LocationClosedCodingV1.require(decoder, keys: CodingKeys.self, required: Set(CodingKeys.allCases.filter { $0 != .parentNodeID && $0 != .shortCode }.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else { throw LocationContractFailureV1.incompatibleVersion }
        try self.init(id: c.decode(UUID.self, forKey: .id), workspaceID: c.decode(WorkspaceID.self, forKey: .workspaceID), siteID: c.decode(UUID.self, forKey: .siteID), parentNodeID: LocationClosedCodingV1.optional(UUID.self, from: c, forKey: .parentNodeID), kind: c.decode(LocationKindV1.self, forKey: .kind), label: c.decode(String.self, forKey: .label), shortCode: LocationClosedCodingV1.optional(String.self, from: c, forKey: .shortCode), siblingOrder: c.decode(Int.self, forKey: .siblingOrder), state: c.decode(LocationNodeStateV1.self, forKey: .state), revision: c.decode(UInt64.self, forKey: .revision), provenance: c.decode(LocationMutationProvenanceV1.self, forKey: .provenance))
    }
}

struct LocationPathComponentV1: Codable, Equatable, Hashable, Sendable {
    let nodeID: UUID
    let kind: LocationKindV1
    let label: String
    let shortCode: String?
    let revision: UInt64

    init(nodeID: UUID, kind: LocationKindV1, label: String, shortCode: String?, revision: UInt64) throws {
        try LocationContractValidationV1.requireID(nodeID); try LocationContractValidationV1.requireText(label)
        if let shortCode { try LocationContractValidationV1.requireText(shortCode, maximumBytes: LocationContractLimitsV1.maximumShortCodeBytes) }
        guard revision > 0 else { throw LocationContractFailureV1.invalidValue }
        self.nodeID = nodeID; self.kind = kind; self.label = label; self.shortCode = shortCode; self.revision = revision
    }
    private enum CodingKeys: String, CodingKey, CaseIterable { case nodeID, kind, label, shortCode, revision }
    init(from decoder: Decoder) throws { try LocationClosedCodingV1.require(decoder, keys: CodingKeys.self, required: Set(CodingKeys.allCases.filter { $0 != .shortCode }.map(\.rawValue))); let c = try decoder.container(keyedBy: CodingKeys.self); try self.init(nodeID: c.decode(UUID.self, forKey: .nodeID), kind: c.decode(LocationKindV1.self, forKey: .kind), label: c.decode(String.self, forKey: .label), shortCode: LocationClosedCodingV1.optional(String.self, from: c, forKey: .shortCode), revision: c.decode(UInt64.self, forKey: .revision)) }
}

struct LocationPathSnapshotV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let siteID: UUID
    let siteDisplay: String
    let nodes: [LocationPathComponentV1]
    let pathSHA256: String

    init(siteID: UUID, siteDisplay: String, nodes: [LocationPathComponentV1]) throws {
        schemaVersion = Self.schemaVersion; self.siteID = siteID; self.siteDisplay = siteDisplay; self.nodes = nodes
        pathSHA256 = try WorkspaceMutationCanonicalV1.sha256(DigestBasis(schemaVersion: Self.schemaVersion, siteID: siteID, siteDisplay: siteDisplay, nodes: nodes))
        try validate()
    }
    func validate() throws {
        try LocationContractValidationV1.requireID(siteID); try LocationContractValidationV1.requireText(siteDisplay)
        guard schemaVersion == Self.schemaVersion, nodes.count <= LocationContractLimitsV1.maximumHierarchyDepth,
              Set(nodes.map(\.nodeID)).count == nodes.count,
              nodes.enumerated().allSatisfy({ index, node in
                  index == 0 || LocationHierarchyPolicyV1.permits(parent: nodes[index - 1].kind, child: node.kind)
              }),
              pathSHA256 == (try WorkspaceMutationCanonicalV1.sha256(DigestBasis(schemaVersion: schemaVersion, siteID: siteID, siteDisplay: siteDisplay, nodes: nodes))) else { throw LocationContractFailureV1.digestMismatch }
    }
    private struct DigestBasis: Codable { let schemaVersion: Int; let siteID: UUID; let siteDisplay: String; let nodes: [LocationPathComponentV1] }
    private enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, siteID, siteDisplay, nodes, pathSHA256 }
    init(from decoder: Decoder) throws {
        try LocationClosedCodingV1.require(decoder, keys: CodingKeys.self, required: Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rebuilt = try Self(siteID: c.decode(UUID.self, forKey: .siteID), siteDisplay: c.decode(String.self, forKey: .siteDisplay), nodes: c.decode([LocationPathComponentV1].self, forKey: .nodes))
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion, try c.decode(String.self, forKey: .pathSHA256) == rebuilt.pathSHA256 else { throw LocationContractFailureV1.digestMismatch }
        self = rebuilt
    }
}

enum LocationHierarchyPolicyV1 {
    static let maximumDepth = 8
    static func permits(parent: LocationKindV1?, child: LocationKindV1) -> Bool {
        guard let parent else { return true }
        switch parent {
        case .campus: return [.building, .area, .exteriorArea, .other].contains(child)
        case .building: return [.level, .area, .exteriorArea, .other].contains(child)
        case .level: return [.area, .zone, .other].contains(child)
        case .area, .exteriorArea: return [.zone, .other].contains(child)
        case .zone, .other: return child == .other
        }
    }

    static func validate(_ nodes: [LocationNodeV1]) throws {
        guard nodes.count <= LocationContractLimitsV1.maximumCollectionCount else { throw LocationContractFailureV1.limitExceeded }
        try nodes.forEach { try $0.validate() }
        guard Set(nodes.map(\.id)).count == nodes.count else { throw LocationContractFailureV1.duplicateIdentity }
        let byID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        for node in nodes {
            var visited = Set<UUID>(); var cursor: LocationNodeV1? = node; var depth = 0
            while let current = cursor {
                guard visited.insert(current.id).inserted else { throw LocationContractFailureV1.hierarchyViolation }
                if current.id != node.id { depth += 1 }
                guard depth < maximumDepth else { throw LocationContractFailureV1.hierarchyViolation }
                guard let parentID = current.parentNodeID else { cursor = nil; continue }
                guard let parent = byID[parentID], parent.workspaceID == node.workspaceID, parent.siteID == node.siteID,
                      (current.state == .archived || parent.state == .active),
                      permits(parent: parent.kind, child: current.kind) else { throw LocationContractFailureV1.hierarchyViolation }
                cursor = parent
            }
        }
        let groups = Dictionary(grouping: nodes, by: { "\($0.siteID.uuidString.lowercased())|\($0.parentNodeID?.uuidString.lowercased() ?? "root")" })
        guard groups.values.allSatisfy({ group in
            let orders = group.map(\.siblingOrder).sorted()
            return Set(orders).count == orders.count && orders == Array(0..<orders.count)
        }) else { throw LocationContractFailureV1.hierarchyViolation }
    }

    /// Validates a mutation's bounded before/after closure. A parent may be
    /// outside the affected set, but every included ancestry edge and sibling
    /// position must remain internally coherent. The writer separately
    /// validates the resulting complete workspace graph.
    static func validatePartialChangeSet(_ nodes: [LocationNodeV1]) throws {
        guard nodes.count <= LocationContractLimitsV1.maximumCollectionCount else {
            throw LocationContractFailureV1.limitExceeded
        }
        try nodes.forEach { try $0.validate() }
        guard Set(nodes.map(\.id)).count == nodes.count else {
            throw LocationContractFailureV1.duplicateIdentity
        }
        let byID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        for node in nodes {
            var visited = Set<UUID>()
            var cursor: LocationNodeV1? = node
            var depth = 0
            while let current = cursor {
                guard visited.insert(current.id).inserted else {
                    throw LocationContractFailureV1.hierarchyViolation
                }
                guard let parentID = current.parentNodeID,
                      let parent = byID[parentID] else {
                    cursor = nil
                    continue
                }
                depth += 1
                guard depth < maximumDepth,
                      parent.workspaceID == node.workspaceID,
                      parent.siteID == node.siteID,
                      current.state == .archived || parent.state == .active,
                      permits(parent: parent.kind, child: current.kind) else {
                    throw LocationContractFailureV1.hierarchyViolation
                }
                cursor = parent
            }
        }
        let groups = Dictionary(grouping: nodes, by: {
            "\($0.siteID.uuidString.lowercased())|\($0.parentNodeID?.uuidString.lowercased() ?? "root")"
        })
        guard groups.values.allSatisfy({ group in
            let orders = group.map(\.siblingOrder)
            return Set(orders).count == orders.count
        }) else {
            throw LocationContractFailureV1.hierarchyViolation
        }
    }
}

struct LocationDescendantProjectionV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int; let workspaceID: WorkspaceID; let siteID: UUID; let ancestorNodeID: UUID
    let descendantNodeIDs: [UUID]; let sourceHierarchyRevision: UInt64; let projectionSHA256: String
    init(workspaceID: WorkspaceID, siteID: UUID, ancestorNodeID: UUID, descendantNodeIDs: [UUID], sourceHierarchyRevision: UInt64) throws {
        schemaVersion = Self.schemaVersion; self.workspaceID = workspaceID; self.siteID = siteID; self.ancestorNodeID = ancestorNodeID
        self.descendantNodeIDs = descendantNodeIDs; self.sourceHierarchyRevision = sourceHierarchyRevision
        projectionSHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(workspaceID: workspaceID, siteID: siteID, ancestorNodeID: ancestorNodeID, descendantNodeIDs: descendantNodeIDs, sourceHierarchyRevision: sourceHierarchyRevision))
        try validate()
    }
    func validate() throws { try LocationContractValidationV1.requireSortedUnique(descendantNodeIDs); guard sourceHierarchyRevision > 0, !descendantNodeIDs.contains(ancestorNodeID), projectionSHA256 == (try WorkspaceMutationCanonicalV1.sha256(Basis(workspaceID: workspaceID, siteID: siteID, ancestorNodeID: ancestorNodeID, descendantNodeIDs: descendantNodeIDs, sourceHierarchyRevision: sourceHierarchyRevision))) else { throw LocationContractFailureV1.digestMismatch } }
    private struct Basis: Codable { let workspaceID: WorkspaceID; let siteID: UUID; let ancestorNodeID: UUID; let descendantNodeIDs: [UUID]; let sourceHierarchyRevision: UInt64 }
    private enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, workspaceID, siteID, ancestorNodeID, descendantNodeIDs, sourceHierarchyRevision, projectionSHA256 }
    init(from decoder: Decoder) throws { try LocationClosedCodingV1.require(decoder, keys: CodingKeys.self, required: Set(CodingKeys.allCases.map(\.rawValue))); let c = try decoder.container(keyedBy: CodingKeys.self); let rebuilt = try Self(workspaceID: c.decode(WorkspaceID.self, forKey: .workspaceID), siteID: c.decode(UUID.self, forKey: .siteID), ancestorNodeID: c.decode(UUID.self, forKey: .ancestorNodeID), descendantNodeIDs: c.decode([UUID].self, forKey: .descendantNodeIDs), sourceHierarchyRevision: c.decode(UInt64.self, forKey: .sourceHierarchyRevision)); guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion, try c.decode(String.self, forKey: .projectionSHA256) == rebuilt.projectionSHA256 else { throw LocationContractFailureV1.digestMismatch }; self = rebuilt }
}

struct AssetContinuityReviewV1: Codable, Equatable, Comparable, Sendable {
    let assetID: UUID; let disposition: PhysicalContinuityDispositionV1
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.assetID.uuidString.lowercased() < rhs.assetID.uuidString.lowercased() }
    init(assetID: UUID, disposition: PhysicalContinuityDispositionV1) { self.assetID = assetID; self.disposition = disposition }
    private enum CodingKeys: String, CodingKey, CaseIterable { case assetID, disposition }
    init(from decoder: Decoder) throws { try LocationClosedCodingV1.require(decoder, keys: CodingKeys.self, required: Set(CodingKeys.allCases.map(\.rawValue))); let c = try decoder.container(keyedBy: CodingKeys.self); let id = try c.decode(UUID.self, forKey: .assetID); try LocationContractValidationV1.requireID(id); self.init(assetID: id, disposition: try c.decode(PhysicalContinuityDispositionV1.self, forKey: .disposition)) }
}

struct AssetLocationPathChangeV1: Codable, Equatable, Comparable, Sendable {
    let assetID: UUID
    let beforePath: LocationPathSnapshotV1
    let afterPath: LocationPathSnapshotV1
    var changesAssetBinding: Bool {
        beforePath.siteID != afterPath.siteID
            || beforePath.nodes.map(\.nodeID) != afterPath.nodes.map(\.nodeID)
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.assetID.uuidString.lowercased() < rhs.assetID.uuidString.lowercased() }
    init(assetID: UUID, beforePath: LocationPathSnapshotV1, afterPath: LocationPathSnapshotV1) throws { try LocationContractValidationV1.requireID(assetID); try beforePath.validate(); try afterPath.validate(); self.assetID = assetID; self.beforePath = beforePath; self.afterPath = afterPath }
    private enum CodingKeys: String, CodingKey, CaseIterable { case assetID, beforePath, afterPath }
    init(from decoder: Decoder) throws { try LocationClosedCodingV1.require(decoder, keys: CodingKeys.self, required: Set(CodingKeys.allCases.map(\.rawValue))); let c = try decoder.container(keyedBy: CodingKeys.self); try self.init(assetID: c.decode(UUID.self, forKey: .assetID), beforePath: c.decode(LocationPathSnapshotV1.self, forKey: .beforePath), afterPath: c.decode(LocationPathSnapshotV1.self, forKey: .afterPath)) }
}

/// Frozen preview of every current/future consumer class invalidated by one
/// hierarchy operation. Empty ID arrays are explicit "none affected" facts;
/// the two derived projections always rebuild from the committed revision.
struct LocationHierarchyConsumerImpactV1: Codable, Equatable, Sendable {
    let planIDs: [UUID]
    let referenceIDs: [UUID]
    let openRoundIDs: [UUID]
    let scheduleIDs: [UUID]
    let reportConsumerIDs: [UUID]
    let searchRebuildRequired: Bool
    let currentPathProjectionRebuildRequired: Bool

    init(
        planIDs: [UUID],
        referenceIDs: [UUID],
        openRoundIDs: [UUID],
        scheduleIDs: [UUID],
        reportConsumerIDs: [UUID],
        searchRebuildRequired: Bool = true,
        currentPathProjectionRebuildRequired: Bool = true
    ) throws {
        self.planIDs = planIDs
        self.referenceIDs = referenceIDs
        self.openRoundIDs = openRoundIDs
        self.scheduleIDs = scheduleIDs
        self.reportConsumerIDs = reportConsumerIDs
        self.searchRebuildRequired = searchRebuildRequired
        self.currentPathProjectionRebuildRequired = currentPathProjectionRebuildRequired
        try validate()
    }

    func validate() throws {
        for values in [planIDs, referenceIDs, openRoundIDs, scheduleIDs, reportConsumerIDs] {
            try LocationContractValidationV1.requireSortedUnique(values)
            try values.forEach(LocationContractValidationV1.requireID)
        }
        guard searchRebuildRequired, currentPathProjectionRebuildRequired else {
            throw LocationContractFailureV1.invalidValue
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case planIDs, referenceIDs, openRoundIDs, scheduleIDs, reportConsumerIDs
        case searchRebuildRequired, currentPathProjectionRebuildRequired
    }

    init(from decoder: Decoder) throws {
        try LocationClosedCodingV1.require(
            decoder,
            keys: CodingKeys.self,
            required: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            planIDs: c.decode([UUID].self, forKey: .planIDs),
            referenceIDs: c.decode([UUID].self, forKey: .referenceIDs),
            openRoundIDs: c.decode([UUID].self, forKey: .openRoundIDs),
            scheduleIDs: c.decode([UUID].self, forKey: .scheduleIDs),
            reportConsumerIDs: c.decode([UUID].self, forKey: .reportConsumerIDs),
            searchRebuildRequired: c.decode(Bool.self, forKey: .searchRebuildRequired),
            currentPathProjectionRebuildRequired: c.decode(
                Bool.self,
                forKey: .currentPathProjectionRebuildRequired
            )
        )
    }
}

struct LocationHierarchyChangePlanV1: Codable, Equatable, Sendable {
    let operationID: UUID; let workspaceID: WorkspaceID; let expectedRevision: WorkspaceExpectedRevisionV1
    let beforeNodes: [LocationNodeV1]; let afterNodes: [LocationNodeV1]; let affectedAssetIDs: [UUID]
    let assetPathChanges: [AssetLocationPathChangeV1]
    let immutablePlacementReferencedNodeIDs: [UUID]
    let consumerImpact: LocationHierarchyConsumerImpactV1
    let assetBindingsChange: Bool; let operationContinuityDisposition: PhysicalContinuityDispositionV1?
    let continuityReviews: [AssetContinuityReviewV1]; let planSHA256: String
    var beforePaths: [LocationPathSnapshotV1] { assetPathChanges.map(\.beforePath) }
    var afterPaths: [LocationPathSnapshotV1] { assetPathChanges.map(\.afterPath) }
    var bindingChangedAssetIDs: [UUID] {
        assetPathChanges.filter(\.changesAssetBinding).map(\.assetID)
    }
    var continuityByAssetID: [UUID: PhysicalContinuityDispositionV1] {
        if let operationContinuityDisposition { return Dictionary(uniqueKeysWithValues: bindingChangedAssetIDs.map { ($0, operationContinuityDisposition) }) }
        return Dictionary(uniqueKeysWithValues: continuityReviews.map { ($0.assetID, $0.disposition) })
    }
    init(operationID: UUID, workspaceID: WorkspaceID, expectedRevision: WorkspaceExpectedRevisionV1, beforeNodes: [LocationNodeV1], afterNodes: [LocationNodeV1], affectedAssetIDs: [UUID], assetPathChanges: [AssetLocationPathChangeV1], immutablePlacementReferencedNodeIDs: [UUID], consumerImpact: LocationHierarchyConsumerImpactV1, assetBindingsChange: Bool, operationContinuityDisposition: PhysicalContinuityDispositionV1?, continuityByAssetID: [UUID: PhysicalContinuityDispositionV1]) throws {
        self.operationID = operationID; self.workspaceID = workspaceID; self.expectedRevision = expectedRevision; self.beforeNodes = beforeNodes; self.afterNodes = afterNodes; self.affectedAssetIDs = affectedAssetIDs; self.assetPathChanges = assetPathChanges; self.immutablePlacementReferencedNodeIDs = immutablePlacementReferencedNodeIDs; self.consumerImpact = consumerImpact; self.assetBindingsChange = assetBindingsChange; self.operationContinuityDisposition = operationContinuityDisposition
        continuityReviews = continuityByAssetID.map { AssetContinuityReviewV1(assetID: $0.key, disposition: $0.value) }.sorted()
        planSHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(operationID: operationID, workspaceID: workspaceID, expectedRevision: expectedRevision, beforeNodes: beforeNodes, afterNodes: afterNodes, affectedAssetIDs: affectedAssetIDs, assetPathChanges: assetPathChanges, immutablePlacementReferencedNodeIDs: immutablePlacementReferencedNodeIDs, consumerImpact: consumerImpact, assetBindingsChange: assetBindingsChange, operationContinuityDisposition: operationContinuityDisposition, continuityReviews: continuityReviews))
        try validate()
    }
    func validate() throws {
        try LocationContractValidationV1.requireID(operationID); try LocationContractValidationV1.requireID(workspaceID.rawValue); try LocationHierarchyPolicyV1.validatePartialChangeSet(beforeNodes); try LocationHierarchyPolicyV1.validatePartialChangeSet(afterNodes); try assetPathChanges.forEach { try $0.beforePath.validate(); try $0.afterPath.validate() }; try LocationContractValidationV1.requireSortedUnique(affectedAssetIDs); try LocationContractValidationV1.requireSortedUnique(immutablePlacementReferencedNodeIDs); try consumerImpact.validate()
        guard Set(beforeNodes.map(\.id)).count == beforeNodes.count,
              Set(afterNodes.map(\.id)).count == afterNodes.count,
              beforeNodes.allSatisfy({ $0.workspaceID == workspaceID }),
              afterNodes.allSatisfy({ $0.workspaceID == workspaceID }) else {
            throw LocationContractFailureV1.duplicateIdentity
        }
        let mutationID = try MutationIDV1(rawValue: operationID); let beforeByID = Dictionary(uniqueKeysWithValues: beforeNodes.map { ($0.id, $0) }); let afterByID = Dictionary(uniqueKeysWithValues: afterNodes.map { ($0.id, $0) }); let removed = Set(beforeByID.keys).subtracting(afterByID.keys)
        let changedProvenanceIsExact = afterNodes.allSatisfy { after in guard let before = beforeByID[after.id] else { return after.provenance.mutationID == mutationID }; return after == before || (after.provenance.mutationID == mutationID && after.revision == before.revision + 1) }
        let newNodesBeginAtRevisionOne = afterNodes.allSatisfy { beforeByID[$0.id] != nil || $0.revision == 1 }
        let pathAssetIDs = assetPathChanges.map(\.assetID); let bindingAssetIDs = bindingChangedAssetIDs; let reviewAssetIDs = continuityReviews.map(\.assetID)
        let continuityIsExact: Bool
        if !assetBindingsChange { continuityIsExact = operationContinuityDisposition == nil && continuityReviews.isEmpty }
        else if let operationContinuityDisposition { continuityIsExact = operationContinuityDisposition == .samePhysicalInstallation && continuityReviews.isEmpty && !bindingAssetIDs.isEmpty }
        else { continuityIsExact = reviewAssetIDs == bindingAssetIDs && !continuityReviews.isEmpty }
        guard changedProvenanceIsExact, newNodesBeginAtRevisionOne,
              beforeNodes != afterNodes || !assetPathChanges.isEmpty,
              assetBindingsChange == !bindingAssetIDs.isEmpty,
              assetPathChanges.allSatisfy({ $0.beforePath != $0.afterPath }),
              removed.isDisjoint(with: Set(immutablePlacementReferencedNodeIDs)), beforeNodes.map(\.id.uuidString) == beforeNodes.map(\.id.uuidString).sorted(), afterNodes.map(\.id.uuidString) == afterNodes.map(\.id.uuidString).sorted(), assetPathChanges == assetPathChanges.sorted(), Set(pathAssetIDs).count == pathAssetIDs.count, pathAssetIDs == affectedAssetIDs, continuityReviews == continuityReviews.sorted(), Set(reviewAssetIDs).count == reviewAssetIDs.count, expectedRevision.workspaceID == workspaceID, continuityIsExact, !continuityByAssetID.values.contains(.unknownReviewRequired), planSHA256 == (try WorkspaceMutationCanonicalV1.sha256(Basis(operationID: operationID, workspaceID: workspaceID, expectedRevision: expectedRevision, beforeNodes: beforeNodes, afterNodes: afterNodes, affectedAssetIDs: affectedAssetIDs, assetPathChanges: assetPathChanges, immutablePlacementReferencedNodeIDs: immutablePlacementReferencedNodeIDs, consumerImpact: consumerImpact, assetBindingsChange: assetBindingsChange, operationContinuityDisposition: operationContinuityDisposition, continuityReviews: continuityReviews))) else { throw LocationContractFailureV1.reviewRequired }
    }
    private struct Basis: Codable { let operationID: UUID; let workspaceID: WorkspaceID; let expectedRevision: WorkspaceExpectedRevisionV1; let beforeNodes: [LocationNodeV1]; let afterNodes: [LocationNodeV1]; let affectedAssetIDs: [UUID]; let assetPathChanges: [AssetLocationPathChangeV1]; let immutablePlacementReferencedNodeIDs: [UUID]; let consumerImpact: LocationHierarchyConsumerImpactV1; let assetBindingsChange: Bool; let operationContinuityDisposition: PhysicalContinuityDispositionV1?; let continuityReviews: [AssetContinuityReviewV1] }
    private enum CodingKeys: String, CodingKey, CaseIterable { case operationID, workspaceID, expectedRevision, beforeNodes, afterNodes, affectedAssetIDs, assetPathChanges, immutablePlacementReferencedNodeIDs, consumerImpact, assetBindingsChange, operationContinuityDisposition, continuityReviews, planSHA256 }
    init(from decoder: Decoder) throws { try LocationClosedCodingV1.require(decoder, keys: CodingKeys.self, required: Set(CodingKeys.allCases.filter { $0 != .operationContinuityDisposition }.map(\.rawValue))); let c = try decoder.container(keyedBy: CodingKeys.self); let reviews = try c.decode([AssetContinuityReviewV1].self, forKey: .continuityReviews); guard reviews == reviews.sorted(), Set(reviews.map(\.assetID)).count == reviews.count else { throw LocationContractFailureV1.unorderedValue }; let operation = try LocationClosedCodingV1.optional(PhysicalContinuityDispositionV1.self, from: c, forKey: .operationContinuityDisposition); let rebuilt = try Self(operationID: c.decode(UUID.self, forKey: .operationID), workspaceID: c.decode(WorkspaceID.self, forKey: .workspaceID), expectedRevision: c.decode(WorkspaceExpectedRevisionV1.self, forKey: .expectedRevision), beforeNodes: c.decode([LocationNodeV1].self, forKey: .beforeNodes), afterNodes: c.decode([LocationNodeV1].self, forKey: .afterNodes), affectedAssetIDs: c.decode([UUID].self, forKey: .affectedAssetIDs), assetPathChanges: c.decode([AssetLocationPathChangeV1].self, forKey: .assetPathChanges), immutablePlacementReferencedNodeIDs: c.decode([UUID].self, forKey: .immutablePlacementReferencedNodeIDs), consumerImpact: c.decode(LocationHierarchyConsumerImpactV1.self, forKey: .consumerImpact), assetBindingsChange: c.decode(Bool.self, forKey: .assetBindingsChange), operationContinuityDisposition: operation, continuityByAssetID: Dictionary(uniqueKeysWithValues: reviews.map { ($0.assetID, $0.disposition) })); guard try c.decode(String.self, forKey: .planSHA256) == rebuilt.planSHA256 else { throw LocationContractFailureV1.digestMismatch }; self = rebuilt }
    func encode(to encoder: Encoder) throws { try validate(); var c = encoder.container(keyedBy: CodingKeys.self); try c.encode(operationID, forKey: .operationID); try c.encode(workspaceID, forKey: .workspaceID); try c.encode(expectedRevision, forKey: .expectedRevision); try c.encode(beforeNodes, forKey: .beforeNodes); try c.encode(afterNodes, forKey: .afterNodes); try c.encode(affectedAssetIDs, forKey: .affectedAssetIDs); try c.encode(assetPathChanges, forKey: .assetPathChanges); try c.encode(immutablePlacementReferencedNodeIDs, forKey: .immutablePlacementReferencedNodeIDs); try c.encode(consumerImpact, forKey: .consumerImpact); try c.encode(assetBindingsChange, forKey: .assetBindingsChange); if let operationContinuityDisposition { try c.encode(operationContinuityDisposition, forKey: .operationContinuityDisposition) }; try c.encode(continuityReviews, forKey: .continuityReviews); try c.encode(planSHA256, forKey: .planSHA256) }
}

struct LocationHierarchyRebindProvenanceV1: Codable, Equatable, Sendable {
    let sourceWorkspaceID: WorkspaceID
    let sourcePlanSHA256: String
    let sourceMutationReceiptIdentity: MutationReceiptIdentityV1
    let sourceMutationReceiptSHA256: String

    init(sourceWorkspaceID: WorkspaceID, sourcePlanSHA256: String, sourceMutationReceiptIdentity: MutationReceiptIdentityV1, sourceMutationReceiptSHA256: String) throws {
        self.sourceWorkspaceID = sourceWorkspaceID; self.sourcePlanSHA256 = sourcePlanSHA256
        self.sourceMutationReceiptIdentity = sourceMutationReceiptIdentity; self.sourceMutationReceiptSHA256 = sourceMutationReceiptSHA256
        try validate()
    }
    func validate() throws { try sourceMutationReceiptIdentity.validate(); try LocationContractValidationV1.requireDigest(sourcePlanSHA256); try LocationContractValidationV1.requireDigest(sourceMutationReceiptSHA256); guard sourceMutationReceiptIdentity.workspaceID == sourceWorkspaceID else { throw LocationContractFailureV1.invalidValue } }
    private enum CodingKeys: String, CodingKey, CaseIterable { case sourceWorkspaceID, sourcePlanSHA256, sourceMutationReceiptIdentity, sourceMutationReceiptSHA256 }
    init(from decoder: Decoder) throws { try LocationClosedCodingV1.require(decoder, keys: CodingKeys.self, required: Set(CodingKeys.allCases.map(\.rawValue))); let c = try decoder.container(keyedBy: CodingKeys.self); try self.init(sourceWorkspaceID: c.decode(WorkspaceID.self, forKey: .sourceWorkspaceID), sourcePlanSHA256: c.decode(String.self, forKey: .sourcePlanSHA256), sourceMutationReceiptIdentity: c.decode(MutationReceiptIdentityV1.self, forKey: .sourceMutationReceiptIdentity), sourceMutationReceiptSHA256: c.decode(String.self, forKey: .sourceMutationReceiptSHA256)) }
}

struct LocationHierarchyChangeReceiptV1: Codable, Equatable, Sendable {
    let planSHA256: String; let mutationReceiptIdentity: MutationReceiptIdentityV1
    let placementPosePostImagesSHA256: String?; let commandBodySHA256: String?
    let mutationReceiptSHA256: String?; let committedAt: Date
    let rebindProvenance: LocationHierarchyRebindProvenanceV1?
    init(plan: LocationHierarchyChangePlanV1,
         placementChanges: [AssetPlacementChangePlanV1],
         mutationReceipt: MutationReceiptV1) throws {
        let mutation = try LocationHierarchyMutationV1(plan: plan, placementChanges: placementChanges)
        try mutationReceipt.validate()
        let commandBodySHA256 = try WorkspaceMutationCanonicalV1.sha256(
            WorkspaceCommandV1.applyLocationHierarchyChange(mutation))
        guard mutationReceipt.identity.workspaceID == plan.workspaceID,
              mutationReceipt.mutationID.rawValue == plan.operationID,
              mutationReceipt.commandBodySHA256 == commandBodySHA256 else {
            throw LocationContractFailureV1.invalidValue
        }
        let poseDigests = placementChanges.compactMap(\.posePostImageSHA256).sorted()
        planSHA256 = plan.planSHA256
        placementPosePostImagesSHA256 = poseDigests.isEmpty ? nil : try WorkspaceMutationCanonicalV1.sha256(poseDigests)
        self.commandBodySHA256 = commandBodySHA256
        mutationReceiptIdentity = mutationReceipt.identity
        mutationReceiptSHA256 = try mutationReceipt.canonicalSHA256()
        committedAt = mutationReceipt.committedAt; rebindProvenance = nil
        try validate()
    }
    init(plan: LocationHierarchyChangePlanV1, mutationReceipt: MutationReceiptV1) throws {
        try self.init(plan: plan, placementChanges: [], mutationReceipt: mutationReceipt)
    }
    private init(planSHA256: String, mutationReceiptIdentity: MutationReceiptIdentityV1, committedAt: Date, rebindProvenance: LocationHierarchyRebindProvenanceV1) throws { self.planSHA256 = planSHA256; self.mutationReceiptIdentity = mutationReceiptIdentity; placementPosePostImagesSHA256 = nil; commandBodySHA256 = nil; mutationReceiptSHA256 = nil; self.committedAt = committedAt; self.rebindProvenance = rebindProvenance; try validate() }
    static func importedCloneFork(destinationPlan: LocationHierarchyChangePlanV1, sourcePlan: LocationHierarchyChangePlanV1, sourceReceipt: Self) throws -> Self {
        try destinationPlan.validate(); try sourcePlan.validate(); try sourceReceipt.validate()
        guard sourceReceipt.planSHA256 == sourcePlan.planSHA256,
              sourceReceipt.mutationReceiptIdentity.workspaceID == sourcePlan.workspaceID,
              destinationPlan.workspaceID != sourcePlan.workspaceID,
              destinationPlan.operationID == sourcePlan.operationID,
              isRebind(destinationPlan, of: sourcePlan) else { throw LocationContractFailureV1.invalidValue }
        let provenance: LocationHierarchyRebindProvenanceV1
        if let existing = sourceReceipt.rebindProvenance {
            provenance = existing
        } else {
            guard let sourceReceiptSHA256 = sourceReceipt.mutationReceiptSHA256 else {
                throw LocationContractFailureV1.invalidValue
            }
            provenance = try LocationHierarchyRebindProvenanceV1(
                sourceWorkspaceID: sourcePlan.workspaceID,
                sourcePlanSHA256: sourcePlan.planSHA256,
                sourceMutationReceiptIdentity: sourceReceipt.mutationReceiptIdentity,
                sourceMutationReceiptSHA256: sourceReceiptSHA256
            )
        }
        let destinationIdentity = MutationReceiptIdentityV1(workspaceID: destinationPlan.workspaceID, replicaID: sourceReceipt.mutationReceiptIdentity.replicaID, localSequence: sourceReceipt.mutationReceiptIdentity.localSequence)
        return try Self(planSHA256: destinationPlan.planSHA256, mutationReceiptIdentity: destinationIdentity, committedAt: sourceReceipt.committedAt, rebindProvenance: provenance)
    }
    func validate() throws {
        try LocationContractValidationV1.requireDigest(planSHA256); try mutationReceiptIdentity.validate()
        guard committedAt.timeIntervalSinceReferenceDate.isFinite else { throw LocationContractFailureV1.invalidValue }
        if let provenance = rebindProvenance {
            try provenance.validate()
            guard mutationReceiptSHA256 == nil, commandBodySHA256 == nil,
                  placementPosePostImagesSHA256 == nil,
                  provenance.sourceWorkspaceID != mutationReceiptIdentity.workspaceID,
                  provenance.sourcePlanSHA256 != planSHA256,
                  provenance.sourceMutationReceiptIdentity.replicaID == mutationReceiptIdentity.replicaID,
                  provenance.sourceMutationReceiptIdentity.localSequence == mutationReceiptIdentity.localSequence else { throw LocationContractFailureV1.invalidValue }
        } else {
            guard let mutationReceiptSHA256, let commandBodySHA256 else { throw LocationContractFailureV1.invalidValue }
            try LocationContractValidationV1.requireDigest(mutationReceiptSHA256)
            try LocationContractValidationV1.requireDigest(commandBodySHA256)
            try placementPosePostImagesSHA256.map(LocationContractValidationV1.requireDigest)
        }
    }
    func validate(plan: LocationHierarchyChangePlanV1,
                  placementChanges: [AssetPlacementChangePlanV1],
                  mutationReceipt: MutationReceiptV1) throws {
        let rebuilt = try Self(plan: plan, placementChanges: placementChanges,
                               mutationReceipt: mutationReceipt)
        guard rebuilt == self else { throw LocationContractFailureV1.digestMismatch }
    }
    private static func isRebind(_ destination: LocationHierarchyChangePlanV1, of source: LocationHierarchyChangePlanV1) -> Bool {
        func sameNodes(_ lhs: [LocationNodeV1], _ rhs: [LocationNodeV1]) -> Bool {
            lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { left, right in
                left.id == right.id && left.siteID == right.siteID && left.parentNodeID == right.parentNodeID
                    && left.kind == right.kind && left.label == right.label && left.shortCode == right.shortCode
                    && left.siblingOrder == right.siblingOrder && left.state == right.state && left.revision == right.revision
                    && left.provenance == right.provenance
            }
        }
        return sameNodes(destination.beforeNodes, source.beforeNodes)
            && sameNodes(destination.afterNodes, source.afterNodes)
            && destination.affectedAssetIDs == source.affectedAssetIDs
            && destination.assetPathChanges == source.assetPathChanges
            && destination.immutablePlacementReferencedNodeIDs == source.immutablePlacementReferencedNodeIDs
            && destination.consumerImpact == source.consumerImpact
            && destination.assetBindingsChange == source.assetBindingsChange
            && destination.operationContinuityDisposition == source.operationContinuityDisposition
            && destination.continuityReviews == source.continuityReviews
    }
    private enum CodingKeys: String, CodingKey, CaseIterable { case planSHA256, placementPosePostImagesSHA256, commandBodySHA256, mutationReceiptIdentity, mutationReceiptSHA256, committedAt, rebindProvenance }
    init(from decoder: Decoder) throws { try LocationClosedCodingV1.require(decoder, keys: CodingKeys.self, required: Set([CodingKeys.planSHA256.rawValue, CodingKeys.mutationReceiptIdentity.rawValue, CodingKeys.committedAt.rawValue])); let c = try decoder.container(keyedBy: CodingKeys.self); planSHA256 = try c.decode(String.self, forKey: .planSHA256); placementPosePostImagesSHA256 = try LocationClosedCodingV1.optional(String.self, from: c, forKey: .placementPosePostImagesSHA256); commandBodySHA256 = try LocationClosedCodingV1.optional(String.self, from: c, forKey: .commandBodySHA256); mutationReceiptIdentity = try c.decode(MutationReceiptIdentityV1.self, forKey: .mutationReceiptIdentity); mutationReceiptSHA256 = try LocationClosedCodingV1.optional(String.self, from: c, forKey: .mutationReceiptSHA256); committedAt = try c.decode(Date.self, forKey: .committedAt); rebindProvenance = try LocationClosedCodingV1.optional(LocationHierarchyRebindProvenanceV1.self, from: c, forKey: .rebindProvenance); try validate() }
    func encode(to encoder: Encoder) throws { try validate(); var c = encoder.container(keyedBy: CodingKeys.self); try c.encode(planSHA256, forKey: .planSHA256); if let placementPosePostImagesSHA256 { try c.encode(placementPosePostImagesSHA256, forKey: .placementPosePostImagesSHA256) }; if let commandBodySHA256 { try c.encode(commandBodySHA256, forKey: .commandBodySHA256) }; try c.encode(mutationReceiptIdentity, forKey: .mutationReceiptIdentity); if let mutationReceiptSHA256 { try c.encode(mutationReceiptSHA256, forKey: .mutationReceiptSHA256) }; try c.encode(committedAt, forKey: .committedAt); if let rebindProvenance { try c.encode(rebindProvenance, forKey: .rebindProvenance) } }
}

struct LocationDeletionPlanV1: Codable, Equatable, Sendable {
    let operationID: UUID; let workspaceID: WorkspaceID; let nodeID: UUID; let expectedRevision: WorkspaceExpectedRevisionV1
    let affectedNodeIDs: [UUID]; let affectedAssetIDs: [UUID]; let archiveOnly: Bool; let planSHA256: String
    init(operationID: UUID, workspaceID: WorkspaceID, nodeID: UUID, expectedRevision: WorkspaceExpectedRevisionV1, affectedNodeIDs: [UUID], affectedAssetIDs: [UUID], archiveOnly: Bool) throws { self.operationID = operationID; self.workspaceID = workspaceID; self.nodeID = nodeID; self.expectedRevision = expectedRevision; self.affectedNodeIDs = affectedNodeIDs; self.affectedAssetIDs = affectedAssetIDs; self.archiveOnly = archiveOnly; try LocationContractValidationV1.requireSortedUnique(affectedNodeIDs); try LocationContractValidationV1.requireSortedUnique(affectedAssetIDs); guard expectedRevision.workspaceID == workspaceID, affectedNodeIDs.contains(nodeID), archiveOnly || affectedAssetIDs.isEmpty else { throw LocationContractFailureV1.hierarchyViolation }; planSHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(operationID: operationID, workspaceID: workspaceID, nodeID: nodeID, expectedRevision: expectedRevision, affectedNodeIDs: affectedNodeIDs, affectedAssetIDs: affectedAssetIDs, archiveOnly: archiveOnly)); try validate() }
    func validate() throws { try LocationContractValidationV1.requireID(operationID); try LocationContractValidationV1.requireID(nodeID); try LocationContractValidationV1.requireSortedUnique(affectedNodeIDs); try LocationContractValidationV1.requireSortedUnique(affectedAssetIDs); guard expectedRevision.workspaceID == workspaceID, affectedNodeIDs.contains(nodeID), archiveOnly || affectedAssetIDs.isEmpty, planSHA256 == (try WorkspaceMutationCanonicalV1.sha256(Basis(operationID: operationID, workspaceID: workspaceID, nodeID: nodeID, expectedRevision: expectedRevision, affectedNodeIDs: affectedNodeIDs, affectedAssetIDs: affectedAssetIDs, archiveOnly: archiveOnly))) else { throw LocationContractFailureV1.hierarchyViolation } }
    private struct Basis: Codable { let operationID: UUID; let workspaceID: WorkspaceID; let nodeID: UUID; let expectedRevision: WorkspaceExpectedRevisionV1; let affectedNodeIDs: [UUID]; let affectedAssetIDs: [UUID]; let archiveOnly: Bool }
    private enum CodingKeys: String, CodingKey, CaseIterable { case operationID, workspaceID, nodeID, expectedRevision, affectedNodeIDs, affectedAssetIDs, archiveOnly, planSHA256 }
    init(from decoder: Decoder) throws { try LocationClosedCodingV1.require(decoder, keys: CodingKeys.self, required: Set(CodingKeys.allCases.map(\.rawValue))); let c = try decoder.container(keyedBy: CodingKeys.self); let rebuilt = try Self(operationID: c.decode(UUID.self, forKey: .operationID), workspaceID: c.decode(WorkspaceID.self, forKey: .workspaceID), nodeID: c.decode(UUID.self, forKey: .nodeID), expectedRevision: c.decode(WorkspaceExpectedRevisionV1.self, forKey: .expectedRevision), affectedNodeIDs: c.decode([UUID].self, forKey: .affectedNodeIDs), affectedAssetIDs: c.decode([UUID].self, forKey: .affectedAssetIDs), archiveOnly: c.decode(Bool.self, forKey: .archiveOnly)); guard try c.decode(String.self, forKey: .planSHA256) == rebuilt.planSHA256 else { throw LocationContractFailureV1.digestMismatch }; self = rebuilt }
}

enum LocationConsumerKindV1: String, Codable, CaseIterable, Sendable {
    case completedSnapshot = "COMPLETED_SNAPSHOT"
    case reportProjection = "REPORT_PROJECTION"
    case backupRestore = "BACKUP_RESTORE"
    case journalReplay = "JOURNAL_REPLAY"
    case deletion = "DELETION"
    case futureSearch = "FUTURE_SEARCH"
    case futurePlan = "FUTURE_PLAN"
    case futureSurvey = "FUTURE_SURVEY"
    case futureSchedule = "FUTURE_SCHEDULE"
    case futureLighting = "FUTURE_LIGHTING"
    case futureImport = "FUTURE_IMPORT"
}

struct LocationConsumerAdapterContractV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int; let consumer: LocationConsumerKindV1; let adapterVersion: Int
    let readsFrozenPaths: Bool; let mayWriteCanonicalLocation: Bool; let contractSHA256: String
    init(consumer: LocationConsumerKindV1, adapterVersion: Int, readsFrozenPaths: Bool, mayWriteCanonicalLocation: Bool = false) throws {
        schemaVersion = Self.schemaVersion; self.consumer = consumer; self.adapterVersion = adapterVersion
        self.readsFrozenPaths = readsFrozenPaths; self.mayWriteCanonicalLocation = mayWriteCanonicalLocation
        contractSHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(consumer: consumer, adapterVersion: adapterVersion, readsFrozenPaths: readsFrozenPaths, mayWriteCanonicalLocation: mayWriteCanonicalLocation))
        guard adapterVersion > 0, !mayWriteCanonicalLocation else { throw LocationContractFailureV1.invalidValue }
    }
    private struct Basis: Codable { let consumer: LocationConsumerKindV1; let adapterVersion: Int; let readsFrozenPaths: Bool; let mayWriteCanonicalLocation: Bool }
    private enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, consumer, adapterVersion, readsFrozenPaths, mayWriteCanonicalLocation, contractSHA256 }
    init(from decoder: Decoder) throws { try LocationClosedCodingV1.require(decoder, keys: CodingKeys.self, required: Set(CodingKeys.allCases.map(\.rawValue))); let c = try decoder.container(keyedBy: CodingKeys.self); let rebuilt = try Self(consumer: c.decode(LocationConsumerKindV1.self, forKey: .consumer), adapterVersion: c.decode(Int.self, forKey: .adapterVersion), readsFrozenPaths: c.decode(Bool.self, forKey: .readsFrozenPaths), mayWriteCanonicalLocation: c.decode(Bool.self, forKey: .mayWriteCanonicalLocation)); guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion, try c.decode(String.self, forKey: .contractSHA256) == rebuilt.contractSHA256 else { throw LocationContractFailureV1.digestMismatch }; self = rebuilt }
}

/// C29 typed integration anchor: this owner consumes an exact immutable plan
/// revision reference and may not reinterpret current plan state implicitly.
enum C29PlanIntegration_Domain_Location_LocationHierarchyContractsV1 {
    static func validatePlanRevision(_ value: PlanRevisionReferenceV1) throws {
        try value.validate()
    }
}

enum C37PoseIntegration_FieldEvidenceApp_Domain_Location_LocationHierarchyContractsV1_swift {
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

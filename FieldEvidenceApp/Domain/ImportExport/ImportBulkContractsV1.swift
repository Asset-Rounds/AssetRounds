import Foundation

enum ImportBulkFailureV1: Error, Equatable, Sendable {
    case invalidValue
    case incompatibleVersion
    case limitExceeded
    case digestMismatch
    case staleRevision
    case changedInputQuarantined
    case adapterCollision
    case dependencyCycle
    case unsupportedSchema
    case nonAllowlistedField
}

enum ImportBulkLimitsV1 {
    static let maximumSourceBytes: Int64 = 64 * 1_024 * 1_024
    static let maximumRows = 100_000
    static let maximumColumns = 128
    static let maximumCellBytes = 16 * 1_024
    static let maximumScalarsPerCell = 8_192
    static let maximumTextBytes = 1_024
    static let maximumReasonsPerRow = 16
    static let maximumCommandsPerRow = 16
    static let maximumChunks = 4_096
    static let maximumRowsPerChunk = 1_000
    static let maximumAdapterDependencies = 32
}

private let importBulkNilUUIDV1 = UUID(
    uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
)

enum ImportBulkCanonicalCodecV1 {
    private struct DeterministicIdentityBasis: Codable {
        let namespace: String
        let basisSHA256: String
    }

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        try WorkspaceMutationCanonicalV1.data(value)
    }

    static func decode<T: Decodable & Encodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let value = try decoder.decode(T.self, from: data)
        guard try encode(value) == data else { throw ImportBulkFailureV1.digestMismatch }
        return value
    }

    static func sha256<T: Encodable>(_ value: T) throws -> String {
        try WorkspaceMutationCanonicalV1.sha256(value)
    }

    static func deterministicUUID<T: Encodable>(namespace: String, basis: T) throws -> UUID {
        try requireText(namespace)
        let basisSHA256 = try sha256(basis)
        let entropy = try sha256(
            DeterministicIdentityBasis(namespace: namespace, basisSHA256: basisSHA256)
        )
        let value = "\(entropy.prefix(8))-\(entropy.dropFirst(8).prefix(4))-\(entropy.dropFirst(12).prefix(4))-\(entropy.dropFirst(16).prefix(4))-\(entropy.dropFirst(20).prefix(12))"
        guard let result = UUID(uuidString: value) else { throw ImportBulkFailureV1.digestMismatch }
        try requireID(result)
        return result
    }

    static func requireText(_ value: String, maximumBytes: Int = ImportBulkLimitsV1.maximumTextBytes) throws {
        guard !value.isEmpty,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              value == value.precomposedStringWithCanonicalMapping,
              value.utf8.count <= maximumBytes else {
            throw ImportBulkFailureV1.invalidValue
        }
    }

    static func requireID(_ value: UUID) throws {
        guard value != importBulkNilUUIDV1 else { throw ImportBulkFailureV1.invalidValue }
    }

    static func requireDigest(_ value: String) throws {
        guard KernelCanonicalHashV1.validSHA256(value) else { throw ImportBulkFailureV1.invalidValue }
    }

    static func requireSortedUnique<T: Comparable & Hashable>(_ values: [T]) throws {
        guard values == values.sorted(), Set(values).count == values.count else {
            throw ImportBulkFailureV1.invalidValue
        }
    }

    static func rejectUnknownKeys<K: CodingKey & CaseIterable>(_ decoder: Decoder, _ type: K.Type) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(
            decoder,
            allowed: Set(K.allCases.map(\.stringValue))
        )
    }
}

struct ImportStreamingBudgetV1: Codable, Equatable, Hashable, Sendable {
    static let version = 1
    let version: Int
    let maximumSourceBytes: Int64
    let maximumRows: Int
    let maximumColumns: Int
    let maximumCellBytes: Int
    let maximumScalarsPerCell: Int

    init(
        maximumSourceBytes: Int64,
        maximumRows: Int,
        maximumColumns: Int,
        maximumCellBytes: Int,
        maximumScalarsPerCell: Int
    ) throws {
        version = Self.version
        self.maximumSourceBytes = maximumSourceBytes
        self.maximumRows = maximumRows
        self.maximumColumns = maximumColumns
        self.maximumCellBytes = maximumCellBytes
        self.maximumScalarsPerCell = maximumScalarsPerCell
        try validate()
    }

    func validate() throws {
        guard version == Self.version,
              (1...ImportBulkLimitsV1.maximumSourceBytes).contains(maximumSourceBytes),
              (1...ImportBulkLimitsV1.maximumRows).contains(maximumRows),
              (1...ImportBulkLimitsV1.maximumColumns).contains(maximumColumns),
              (1...ImportBulkLimitsV1.maximumCellBytes).contains(maximumCellBytes),
              (1...ImportBulkLimitsV1.maximumScalarsPerCell).contains(maximumScalarsPerCell) else {
            throw ImportBulkFailureV1.limitExceeded
        }
    }

}

enum ImportSourceKindV1: String, Codable, CaseIterable, Hashable, Sendable {
    case userSelectedFile = "USER_SELECTED_FILE"
    case correctionArtifact = "CORRECTION_ARTIFACT"
    case deterministicUpdateTemplate = "DETERMINISTIC_UPDATE_TEMPLATE"
}

struct ImportSourceV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let sourceID: UUID
    let workspaceID: WorkspaceID
    let kind: ImportSourceKindV1
    let sourceSHA256: String
    let byteCount: Int64
    let leaseID: UUID
    let importedAt: Date

    init(
        sourceID: UUID,
        workspaceID: WorkspaceID,
        kind: ImportSourceKindV1,
        sourceSHA256: String,
        byteCount: Int64,
        leaseID: UUID,
        importedAt: Date
    ) throws {
        schemaVersion = Self.schemaVersion
        self.sourceID = sourceID
        self.workspaceID = workspaceID
        self.kind = kind
        self.sourceSHA256 = sourceSHA256
        self.byteCount = byteCount
        self.leaseID = leaseID
        self.importedAt = importedAt
        try validate()
    }

    func validate() throws {
        try ImportBulkCanonicalCodecV1.requireID(sourceID)
        try ImportBulkCanonicalCodecV1.requireID(leaseID)
        try ImportBulkCanonicalCodecV1.requireDigest(sourceSHA256)
        guard schemaVersion == Self.schemaVersion,
              (1...ImportBulkLimitsV1.maximumSourceBytes).contains(byteCount),
              importedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw ImportBulkFailureV1.invalidValue
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, sourceID, workspaceID, kind, sourceSHA256, byteCount, leaseID, importedAt
    }

    init(from decoder: Decoder) throws {
        try ImportBulkCanonicalCodecV1.rejectUnknownKeys(decoder, CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            sourceID: c.decode(UUID.self, forKey: .sourceID),
            workspaceID: c.decode(WorkspaceID.self, forKey: .workspaceID),
            kind: c.decode(ImportSourceKindV1.self, forKey: .kind),
            sourceSHA256: c.decode(String.self, forKey: .sourceSHA256),
            byteCount: c.decode(Int64.self, forKey: .byteCount),
            leaseID: c.decode(UUID.self, forKey: .leaseID),
            importedAt: c.decode(Date.self, forKey: .importedAt)
        )
        guard schemaVersion == (try c.decode(Int.self, forKey: .schemaVersion)) else {
            throw ImportBulkFailureV1.incompatibleVersion
        }
    }
}

enum ImportEntityKindV1: String, Codable, CaseIterable, Comparable, Hashable, Sendable {
    case locationNode = "LOCATION_NODE"
    case asset = "ASSET"
    case assetPlacement = "ASSET_PLACEMENT"
    case placementPose = "PLACEMENT_POSE"
    /// A bounded, synthetic import row which materializes one already
    /// allowlisted workspace command. It is not a canonical workspace entity.
    case atomicWorkspaceBundle = "ATOMIC_WORKSPACE_BUNDLE"
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

enum ImportColumnScalarV1: String, Codable, CaseIterable, Hashable, Sendable {
    case text = "TEXT"
    case integer = "INTEGER"
    case decimal = "DECIMAL"
    case boolean = "BOOLEAN"
    case identifier = "IDENTIFIER"
}

struct ImportSchemaColumnV1: Codable, Equatable, Hashable, Comparable, Sendable {
    let key: String
    let scalar: ImportColumnScalarV1
    let required: Bool
    let editableOnExactUpdate: Bool
    let maximumCellBytes: Int
    let maximumScalars: Int

    init(
        key: String,
        scalar: ImportColumnScalarV1,
        required: Bool,
        editableOnExactUpdate: Bool,
        maximumCellBytes: Int,
        maximumScalars: Int
    ) throws {
        try ImportBulkCanonicalCodecV1.requireText(key)
        guard key == key.lowercased(),
              key.allSatisfy({ $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "_") }),
              (1...ImportBulkLimitsV1.maximumCellBytes).contains(maximumCellBytes),
              (1...ImportBulkLimitsV1.maximumScalarsPerCell).contains(maximumScalars) else {
            throw ImportBulkFailureV1.invalidValue
        }
        self.key = key
        self.scalar = scalar
        self.required = required
        self.editableOnExactUpdate = editableOnExactUpdate
        self.maximumCellBytes = maximumCellBytes
        self.maximumScalars = maximumScalars
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.key < rhs.key }
}

struct ImportSchemaReleaseV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let releaseID: String
    let release: UInt64
    let entityKind: ImportEntityKindV1
    let externalKeyColumn: String
    let columns: [ImportSchemaColumnV1]
    let budget: ImportStreamingBudgetV1
    let schemaSHA256: String

    init(
        releaseID: String,
        release: UInt64,
        entityKind: ImportEntityKindV1,
        externalKeyColumn: String,
        columns: [ImportSchemaColumnV1],
        budget: ImportStreamingBudgetV1
    ) throws {
        schemaVersion = Self.schemaVersion
        self.releaseID = releaseID
        self.release = release
        self.entityKind = entityKind
        self.externalKeyColumn = externalKeyColumn
        self.columns = columns
        self.budget = budget
        schemaSHA256 = try ImportBulkCanonicalCodecV1.sha256(
            DigestBasis(
                schemaVersion: Self.schemaVersion,
                releaseID: releaseID,
                release: release,
                entityKind: entityKind,
                externalKeyColumn: externalKeyColumn,
                columns: columns,
                budget: budget
            )
        )
        try validate()
    }

    func validate() throws {
        try ImportBulkCanonicalCodecV1.requireText(releaseID)
        try ImportBulkCanonicalCodecV1.requireText(externalKeyColumn)
        try budget.validate()
        guard schemaVersion == Self.schemaVersion,
              release > 0,
              !columns.isEmpty,
              columns.count <= budget.maximumColumns,
              columns == columns.sorted(),
              Set(columns.map(\.key)).count == columns.count,
              columns.contains(where: { $0.key == externalKeyColumn && $0.required }),
              schemaSHA256 == (try ImportBulkCanonicalCodecV1.sha256(digestBasis)) else {
            throw ImportBulkFailureV1.digestMismatch
        }
    }

    var editableColumns: [String] { columns.filter(\.editableOnExactUpdate).map(\.key) }
    private var digestBasis: DigestBasis {
        DigestBasis(schemaVersion: schemaVersion, releaseID: releaseID, release: release,
                    entityKind: entityKind, externalKeyColumn: externalKeyColumn,
                    columns: columns, budget: budget)
    }
    private struct DigestBasis: Codable {
        let schemaVersion: Int
        let releaseID: String
        let release: UInt64
        let entityKind: ImportEntityKindV1
        let externalKeyColumn: String
        let columns: [ImportSchemaColumnV1]
        let budget: ImportStreamingBudgetV1
    }
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, releaseID, release, entityKind, externalKeyColumn, columns, budget, schemaSHA256
    }
    init(from decoder: Decoder) throws {
        try ImportBulkCanonicalCodecV1.rejectUnknownKeys(decoder, CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        releaseID = try c.decode(String.self, forKey: .releaseID)
        release = try c.decode(UInt64.self, forKey: .release)
        entityKind = try c.decode(ImportEntityKindV1.self, forKey: .entityKind)
        externalKeyColumn = try c.decode(String.self, forKey: .externalKeyColumn)
        columns = try c.decode([ImportSchemaColumnV1].self, forKey: .columns)
        budget = try c.decode(ImportStreamingBudgetV1.self, forKey: .budget)
        schemaSHA256 = try c.decode(String.self, forKey: .schemaSHA256)
        try validate()
    }
}

struct ImportColumnMappingV1: Codable, Equatable, Hashable, Comparable, Sendable {
    let sourceColumn: String
    let targetColumn: String

    init(sourceColumn: String, targetColumn: String) throws {
        try ImportBulkCanonicalCodecV1.requireText(sourceColumn)
        try ImportBulkCanonicalCodecV1.requireText(targetColumn)
        self.sourceColumn = sourceColumn
        self.targetColumn = targetColumn
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.sourceColumn == rhs.sourceColumn
            ? lhs.targetColumn < rhs.targetColumn
            : lhs.sourceColumn < rhs.sourceColumn
    }
}

/// A saved, workspace-scoped mapping. Source bytes and preview rows remain
/// scratch; only an explicitly saved mapping can enter the durable row family.
struct ImportMappingProfileV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let profileID: UUID
    let workspaceID: WorkspaceID
    let profileName: String
    let schemaReleaseID: String
    let schemaRelease: UInt64
    let schemaSHA256: String
    let mappings: [ImportColumnMappingV1]
    let profileSHA256: String

    init(
        profileID: UUID,
        workspaceID: WorkspaceID,
        profileName: String,
        schemaRelease: ImportSchemaReleaseV1,
        mappings: [ImportColumnMappingV1]
    ) throws {
        try schemaRelease.validate()
        schemaVersion = Self.schemaVersion
        self.profileID = profileID
        self.workspaceID = workspaceID
        self.profileName = profileName
        schemaReleaseID = schemaRelease.releaseID
        self.schemaRelease = schemaRelease.release
        schemaSHA256 = schemaRelease.schemaSHA256
        self.mappings = mappings
        profileSHA256 = try ImportBulkCanonicalCodecV1.sha256(
            DigestBasis(
                schemaVersion: Self.schemaVersion,
                profileID: profileID,
                workspaceID: workspaceID,
                profileName: profileName,
                schemaReleaseID: schemaRelease.releaseID,
                schemaRelease: schemaRelease.release,
                schemaSHA256: schemaRelease.schemaSHA256,
                mappings: mappings
            )
        )
        try validate()
    }

    func validate() throws {
        try ImportBulkCanonicalCodecV1.requireID(profileID)
        try ImportBulkCanonicalCodecV1.requireText(profileName)
        try ImportBulkCanonicalCodecV1.requireText(schemaReleaseID)
        try ImportBulkCanonicalCodecV1.requireDigest(schemaSHA256)
        guard schemaVersion == Self.schemaVersion,
              schemaRelease > 0,
              !mappings.isEmpty,
              mappings.count <= ImportBulkLimitsV1.maximumColumns,
              mappings == mappings.sorted(),
              Set(mappings.map(\.sourceColumn)).count == mappings.count,
              Set(mappings.map(\.targetColumn)).count == mappings.count,
              profileSHA256 == (try ImportBulkCanonicalCodecV1.sha256(digestBasis)) else {
            throw ImportBulkFailureV1.digestMismatch
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, profileID, workspaceID, profileName, schemaReleaseID,
             schemaRelease, schemaSHA256, mappings, profileSHA256
    }

    init(from decoder: Decoder) throws {
        try ImportBulkCanonicalCodecV1.rejectUnknownKeys(decoder, CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        profileID = try container.decode(UUID.self, forKey: .profileID)
        workspaceID = try container.decode(WorkspaceID.self, forKey: .workspaceID)
        profileName = try container.decode(String.self, forKey: .profileName)
        schemaReleaseID = try container.decode(String.self, forKey: .schemaReleaseID)
        schemaRelease = try container.decode(UInt64.self, forKey: .schemaRelease)
        schemaSHA256 = try container.decode(String.self, forKey: .schemaSHA256)
        mappings = try container.decode([ImportColumnMappingV1].self, forKey: .mappings)
        profileSHA256 = try container.decode(String.self, forKey: .profileSHA256)
        try validate()
    }

    private var digestBasis: DigestBasis {
        DigestBasis(
            schemaVersion: schemaVersion,
            profileID: profileID,
            workspaceID: workspaceID,
            profileName: profileName,
            schemaReleaseID: schemaReleaseID,
            schemaRelease: schemaRelease,
            schemaSHA256: schemaSHA256,
            mappings: mappings
        )
    }

    private struct DigestBasis: Codable {
        let schemaVersion: Int
        let profileID: UUID
        let workspaceID: WorkspaceID
        let profileName: String
        let schemaReleaseID: String
        let schemaRelease: UInt64
        let schemaSHA256: String
        let mappings: [ImportColumnMappingV1]
    }
}

struct ImportRowIdentityV1: Codable, Equatable, Hashable, Comparable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let workspaceID: WorkspaceID
    let sourceSHA256: String
    let sourceOrdinal: UInt64
    let canonicalRowSHA256: String
    let stableExternalKey: String
    let schemaReleaseID: String
    let schemaRelease: UInt64
    let identitySHA256: String

    init(
        workspaceID: WorkspaceID,
        sourceSHA256: String,
        sourceOrdinal: UInt64,
        canonicalRowSHA256: String,
        stableExternalKey: String,
        schemaReleaseID: String,
        schemaRelease: UInt64
    ) throws {
        schemaVersion = Self.schemaVersion
        self.workspaceID = workspaceID
        self.sourceSHA256 = sourceSHA256
        self.sourceOrdinal = sourceOrdinal
        self.canonicalRowSHA256 = canonicalRowSHA256
        self.stableExternalKey = stableExternalKey
        self.schemaReleaseID = schemaReleaseID
        self.schemaRelease = schemaRelease
        identitySHA256 = try ImportBulkCanonicalCodecV1.sha256(
            DigestBasis(schemaVersion: Self.schemaVersion, workspaceID: workspaceID,
                        sourceSHA256: sourceSHA256, sourceOrdinal: sourceOrdinal,
                        canonicalRowSHA256: canonicalRowSHA256, stableExternalKey: stableExternalKey,
                        schemaReleaseID: schemaReleaseID, schemaRelease: schemaRelease)
        )
        try validate()
    }

    func validate() throws {
        try ImportBulkCanonicalCodecV1.requireDigest(sourceSHA256)
        try ImportBulkCanonicalCodecV1.requireDigest(canonicalRowSHA256)
        try ImportBulkCanonicalCodecV1.requireText(stableExternalKey)
        try ImportBulkCanonicalCodecV1.requireText(schemaReleaseID)
        guard schemaVersion == Self.schemaVersion,
              sourceOrdinal > 0,
              schemaRelease > 0,
              identitySHA256 == (try ImportBulkCanonicalCodecV1.sha256(digestBasis)) else {
            throw ImportBulkFailureV1.digestMismatch
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.sourceOrdinal != rhs.sourceOrdinal { return lhs.sourceOrdinal < rhs.sourceOrdinal }
        return lhs.identitySHA256 < rhs.identitySHA256
    }
    private var digestBasis: DigestBasis {
        DigestBasis(schemaVersion: schemaVersion, workspaceID: workspaceID,
                    sourceSHA256: sourceSHA256, sourceOrdinal: sourceOrdinal,
                    canonicalRowSHA256: canonicalRowSHA256, stableExternalKey: stableExternalKey,
                    schemaReleaseID: schemaReleaseID, schemaRelease: schemaRelease)
    }
    private struct DigestBasis: Codable {
        let schemaVersion: Int
        let workspaceID: WorkspaceID
        let sourceSHA256: String
        let sourceOrdinal: UInt64
        let canonicalRowSHA256: String
        let stableExternalKey: String
        let schemaReleaseID: String
        let schemaRelease: UInt64
    }
}

enum ImportRowDispositionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case create = "CREATE"
    case updateExactMatch = "UPDATE_EXACT_MATCH"
    case unchanged = "UNCHANGED"
    case duplicateSource = "DUPLICATE_SOURCE"
    case ambiguousTarget = "AMBIGUOUS_TARGET"
    case conflict = "CONFLICT"
    case invalid = "INVALID"
    case unsupported = "UNSUPPORTED"
    case skippedByUser = "SKIPPED_BY_USER"

    var proposesMutation: Bool { self == .create || self == .updateExactMatch }
}

enum ImportReasonCodeV1: String, Codable, CaseIterable, Comparable, Hashable, Sendable {
    case exactStableKeyCreate = "EXACT_STABLE_KEY_CREATE"
    case exactStableKeyUpdate = "EXACT_STABLE_KEY_UPDATE"
    case noMaterialChange = "NO_MATERIAL_CHANGE"
    case duplicateExternalKey = "DUPLICATE_EXTERNAL_KEY"
    case multipleExactTargets = "MULTIPLE_EXACT_TARGETS"
    case staleExpectedRevision = "STALE_EXPECTED_REVISION"
    case invalidCell = "INVALID_CELL"
    case unknownSchemaRelease = "UNKNOWN_SCHEMA_RELEASE"
    case nonAllowlistedColumn = "NONALLOWLISTED_COLUMN"
    case displayNameMatchForbidden = "DISPLAY_NAME_MATCH_FORBIDDEN"
    case userSkipped = "USER_SKIPPED"
    case missingDependency = "MISSING_DEPENDENCY"
    case adapterRejected = "ADAPTER_REJECTED"
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct ImportExpectedRevisionV1: Codable, Equatable, Hashable, Sendable {
    let entityKind: ImportEntityKindV1
    let stableID: UUID
    let expectedRevision: UInt64
    init(entityKind: ImportEntityKindV1, stableID: UUID, expectedRevision: UInt64) throws {
        try ImportBulkCanonicalCodecV1.requireID(stableID)
        guard expectedRevision > 0 else { throw ImportBulkFailureV1.invalidValue }
        self.entityKind = entityKind
        self.stableID = stableID
        self.expectedRevision = expectedRevision
    }
}

enum ImportCommandKindV1: String, Codable, CaseIterable, Comparable, Hashable, Sendable {
    case createLocationNode = "CREATE_LOCATION_NODE"
    case createAsset = "CREATE_ASSET"
    case placeAsset = "PLACE_ASSET"
    case updateAssetExactKey = "UPDATE_ASSET_EXACT_KEY"
    case appendPlacementPose = "APPEND_PLACEMENT_POSE"
    /// One C08 row/chunk/request may stand for an already-defined compound
    /// workspace command. The row has no fabricated entity revision.
    case applyAtomicWorkspaceBundle = "APPLY_ATOMIC_WORKSPACE_BUNDLE"

    var createsAggregate: Bool { self == .applyAtomicWorkspaceBundle }
    var allowsNilExpectedRevision: Bool {
        self == .createLocationNode || self == .createAsset || createsAggregate
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Canonical row input made available to an existing workspace-command adapter.
/// It is implementation support for materialization, not an additional import
/// authority contract or a persisted source-byte representation.
struct ImportMappedFieldV1: Codable, Equatable, Hashable, Comparable, Sendable {
    let key: String
    let value: String

    init(key: String, value: String) throws {
        try ImportBulkCanonicalCodecV1.requireText(key)
        guard key == key.lowercased(),
              key.allSatisfy({ $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "_") }),
              value == value.precomposedStringWithCanonicalMapping,
              value.utf8.count <= ImportBulkLimitsV1.maximumCellBytes,
              value.unicodeScalars.count <= ImportBulkLimitsV1.maximumScalarsPerCell,
              !value.unicodeScalars.contains(where: { $0.value == 0 }) else {
            throw ImportBulkFailureV1.invalidValue
        }
        self.key = key
        self.value = value
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.key < rhs.key }

    private enum CodingKeys: String, CodingKey, CaseIterable { case key, value }

    init(from decoder: Decoder) throws {
        try ImportBulkCanonicalCodecV1.rejectUnknownKeys(decoder, CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            key: container.decode(String.self, forKey: .key),
            value: container.decode(String.self, forKey: .value)
        )
    }
}

struct ImportProposedCommandV1: Codable, Equatable, Hashable, Comparable, Sendable {
    let commandID: String
    let kind: ImportCommandKindV1
    let targetStableID: UUID?
    let expectedRevision: ImportExpectedRevisionV1?
    let dependencyCommandIDs: [String]
    let payloadSHA256: String

    init(commandID: String, kind: ImportCommandKindV1, targetStableID: UUID?,
         expectedRevision: ImportExpectedRevisionV1?, dependencyCommandIDs: [String],
         payloadSHA256: String) throws {
        self.commandID = commandID
        self.kind = kind
        self.targetStableID = targetStableID
        self.expectedRevision = expectedRevision
        self.dependencyCommandIDs = dependencyCommandIDs
        self.payloadSHA256 = payloadSHA256
        try validate()
    }

    func validate() throws {
        try ImportBulkCanonicalCodecV1.requireText(commandID)
        try targetStableID.map(ImportBulkCanonicalCodecV1.requireID)
        try dependencyCommandIDs.forEach(ImportBulkCanonicalCodecV1.requireText)
        try ImportBulkCanonicalCodecV1.requireSortedUnique(dependencyCommandIDs)
        try ImportBulkCanonicalCodecV1.requireDigest(payloadSHA256)
        guard dependencyCommandIDs.count <= ImportBulkLimitsV1.maximumAdapterDependencies,
              !dependencyCommandIDs.contains(commandID),
              kind.allowsNilExpectedRevision == (expectedRevision == nil),
              !kind.createsAggregate || (targetStableID == nil && expectedRevision == nil) else {
            throw ImportBulkFailureV1.invalidValue
        }
    }

    /// Computes the pre-plan payload digest. It intentionally excludes plan,
    /// chunk, mutation, and workspace-request identities so construction is
    /// acyclic: payload -> row -> plan -> bulk mutation identity.
    static func canonicalPayloadSHA256(
        commandID: String,
        kind: ImportCommandKindV1,
        targetStableID: UUID?,
        expectedRevision: ImportExpectedRevisionV1?,
        dependencyCommandIDs: [String],
        rowIdentity: ImportRowIdentityV1,
        schemaRelease: ImportSchemaReleaseV1,
        mappedFields: [ImportMappedFieldV1]
    ) throws -> String {
        try ImportBulkCanonicalCodecV1.requireText(commandID)
        try targetStableID.map(ImportBulkCanonicalCodecV1.requireID)
        try dependencyCommandIDs.forEach(ImportBulkCanonicalCodecV1.requireText)
        try ImportBulkCanonicalCodecV1.requireSortedUnique(dependencyCommandIDs)
        try rowIdentity.validate()
        try schemaRelease.validate()
        try ImportBulkCanonicalCodecV1.requireSortedUnique(mappedFields)
        guard dependencyCommandIDs.count <= ImportBulkLimitsV1.maximumAdapterDependencies,
              !dependencyCommandIDs.contains(commandID),
              mappedFields.count <= ImportBulkLimitsV1.maximumColumns,
              kind.allowsNilExpectedRevision == (expectedRevision == nil),
              !kind.createsAggregate || (targetStableID == nil && expectedRevision == nil),
              kind.createsAggregate == (schemaRelease.entityKind == .atomicWorkspaceBundle),
              rowIdentity.schemaReleaseID == schemaRelease.releaseID,
              rowIdentity.schemaRelease == schemaRelease.release else {
            throw ImportBulkFailureV1.invalidValue
        }
        return try ImportBulkCanonicalCodecV1.sha256(
            PayloadBasis(
                commandID: commandID,
                kind: kind,
                targetStableID: targetStableID,
                expectedRevision: expectedRevision,
                dependencyCommandIDs: dependencyCommandIDs,
                rowIdentity: rowIdentity,
                schemaReleaseID: schemaRelease.releaseID,
                schemaRelease: schemaRelease.release,
                schemaSHA256: schemaRelease.schemaSHA256,
                mappedFields: mappedFields
            )
        )
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.commandID < rhs.commandID }
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case commandID, kind, targetStableID, expectedRevision, dependencyCommandIDs, payloadSHA256
    }
    init(from decoder: Decoder) throws {
        try ImportBulkCanonicalCodecV1.rejectUnknownKeys(decoder, CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            commandID: container.decode(String.self, forKey: .commandID),
            kind: container.decode(ImportCommandKindV1.self, forKey: .kind),
            targetStableID: container.decodeIfPresent(UUID.self, forKey: .targetStableID),
            expectedRevision: container.decodeIfPresent(
                ImportExpectedRevisionV1.self,
                forKey: .expectedRevision
            ),
            dependencyCommandIDs: container.decode([String].self, forKey: .dependencyCommandIDs),
            payloadSHA256: container.decode(String.self, forKey: .payloadSHA256)
        )
    }

    private struct PayloadBasis: Codable {
        let commandID: String
        let kind: ImportCommandKindV1
        let targetStableID: UUID?
        let expectedRevision: ImportExpectedRevisionV1?
        let dependencyCommandIDs: [String]
        let rowIdentity: ImportRowIdentityV1
        let schemaReleaseID: String
        let schemaRelease: UInt64
        let schemaSHA256: String
        let mappedFields: [ImportMappedFieldV1]
    }
}

struct ImportPlanRowV1: Codable, Equatable, Hashable, Comparable, Sendable {
    let identity: ImportRowIdentityV1
    let disposition: ImportRowDispositionV1
    let reasons: [ImportReasonCodeV1]
    let mappedFields: [ImportMappedFieldV1]
    let commands: [ImportProposedCommandV1]
    let expectedTargetRevision: ImportExpectedRevisionV1?
    let rowResultSHA256: String

    init(identity: ImportRowIdentityV1, disposition: ImportRowDispositionV1,
         reasons: [ImportReasonCodeV1], mappedFields: [ImportMappedFieldV1],
         commands: [ImportProposedCommandV1],
         expectedTargetRevision: ImportExpectedRevisionV1?) throws {
        self.identity = identity
        self.disposition = disposition
        self.reasons = reasons
        self.mappedFields = mappedFields
        self.commands = commands
        self.expectedTargetRevision = expectedTargetRevision
        rowResultSHA256 = try ImportBulkCanonicalCodecV1.sha256(
            Basis(identity: identity, disposition: disposition, reasons: reasons,
                  mappedFields: mappedFields,
                  commands: commands, expectedTargetRevision: expectedTargetRevision)
        )
        try validate()
    }

    func validate() throws {
        try identity.validate()
        try ImportBulkCanonicalCodecV1.requireSortedUnique(reasons)
        try ImportBulkCanonicalCodecV1.requireSortedUnique(mappedFields)
        try commands.forEach { try $0.validate() }
        try ImportBulkCanonicalCodecV1.requireSortedUnique(commands)
        guard !reasons.isEmpty,
              mappedFields.count <= ImportBulkLimitsV1.maximumColumns,
              reasons.count <= ImportBulkLimitsV1.maximumReasonsPerRow,
              commands.count <= ImportBulkLimitsV1.maximumCommandsPerRow,
              Set(commands.map(\.commandID)).count == commands.count,
              disposition.proposesMutation == !commands.isEmpty,
              (disposition == .updateExactMatch) == (expectedTargetRevision != nil),
              rowResultSHA256 == (try ImportBulkCanonicalCodecV1.sha256(basis)) else {
            throw ImportBulkFailureV1.invalidValue
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.identity < rhs.identity }
    private var basis: Basis { Basis(identity: identity, disposition: disposition,
                                     reasons: reasons, mappedFields: mappedFields,
                                     commands: commands,
                                     expectedTargetRevision: expectedTargetRevision) }
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case identity, disposition, reasons, mappedFields, commands,
             expectedTargetRevision, rowResultSHA256
    }
    init(from decoder: Decoder) throws {
        try ImportBulkCanonicalCodecV1.rejectUnknownKeys(decoder, CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        identity = try container.decode(ImportRowIdentityV1.self, forKey: .identity)
        disposition = try container.decode(ImportRowDispositionV1.self, forKey: .disposition)
        reasons = try container.decode([ImportReasonCodeV1].self, forKey: .reasons)
        mappedFields = try container.decode([ImportMappedFieldV1].self, forKey: .mappedFields)
        commands = try container.decode([ImportProposedCommandV1].self, forKey: .commands)
        expectedTargetRevision = try container.decodeIfPresent(
            ImportExpectedRevisionV1.self,
            forKey: .expectedTargetRevision
        )
        rowResultSHA256 = try container.decode(String.self, forKey: .rowResultSHA256)
        try validate()
    }
    private struct Basis: Codable {
        let identity: ImportRowIdentityV1
        let disposition: ImportRowDispositionV1
        let reasons: [ImportReasonCodeV1]
        let mappedFields: [ImportMappedFieldV1]
        let commands: [ImportProposedCommandV1]
        let expectedTargetRevision: ImportExpectedRevisionV1?
    }
}

/// Immutable zero-write preview evidence. Constructing or validating a plan
/// cannot mutate canonical state, publish a file, append a receipt, or alter an index.
struct ImportPlanV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let planID: UUID
    let workspaceID: WorkspaceID
    let source: ImportSourceV1
    let schemaRelease: ImportSchemaReleaseV1
    let mappingProfileSHA256: String?
    let workspaceRevisionSHA256: String
    let rows: [ImportPlanRowV1]
    let previewWritesCanonicalState: Bool
    let planSHA256: String

    init(planID: UUID, workspaceID: WorkspaceID, source: ImportSourceV1,
         schemaRelease: ImportSchemaReleaseV1, mappingProfileSHA256: String?,
         workspaceRevisionSHA256: String, rows: [ImportPlanRowV1]) throws {
        guard planID == (try Self.deterministicPlanID(
            workspaceID: workspaceID,
            source: source,
            schemaRelease: schemaRelease,
            mappingProfileSHA256: mappingProfileSHA256,
            workspaceRevisionSHA256: workspaceRevisionSHA256,
            rows: rows
        )) else { throw ImportBulkFailureV1.invalidValue }
        schemaVersion = Self.schemaVersion
        self.planID = planID
        self.workspaceID = workspaceID
        self.source = source
        self.schemaRelease = schemaRelease
        self.mappingProfileSHA256 = mappingProfileSHA256
        self.workspaceRevisionSHA256 = workspaceRevisionSHA256
        self.rows = rows
        previewWritesCanonicalState = false
        planSHA256 = try ImportBulkCanonicalCodecV1.sha256(
            DigestBasis(schemaVersion: Self.schemaVersion, planID: planID, workspaceID: workspaceID,
                        source: source, schemaRelease: schemaRelease,
                        mappingProfileSHA256: mappingProfileSHA256,
                        workspaceRevisionSHA256: workspaceRevisionSHA256, rows: rows,
                        previewWritesCanonicalState: false)
        )
        try validate()
    }

    func validate() throws {
        try ImportBulkCanonicalCodecV1.requireID(planID)
        try source.validate()
        try schemaRelease.validate()
        try mappingProfileSHA256.map(ImportBulkCanonicalCodecV1.requireDigest)
        try ImportBulkCanonicalCodecV1.requireDigest(workspaceRevisionSHA256)
        try rows.forEach { try $0.validate() }
        guard schemaVersion == Self.schemaVersion,
              source.workspaceID == workspaceID,
              rows.count <= schemaRelease.budget.maximumRows,
              rows == rows.sorted(),
              Set(rows.map(\.identity)).count == rows.count,
              rows.allSatisfy({ $0.identity.workspaceID == workspaceID
                    && $0.identity.sourceSHA256 == source.sourceSHA256
                    && $0.identity.schemaReleaseID == schemaRelease.releaseID
                    && $0.identity.schemaRelease == schemaRelease.release
                    && $0.commands.allSatisfy {
                        $0.kind.createsAggregate
                            == (schemaRelease.entityKind == .atomicWorkspaceBundle)
                    } }),
              !previewWritesCanonicalState,
              planSHA256 == (try ImportBulkCanonicalCodecV1.sha256(digestBasis)) else {
            throw ImportBulkFailureV1.digestMismatch
        }
    }

    func validateCurrent(workspaceRevisionSHA256 current: String, sourceSHA256: String) throws {
        try validate()
        guard self.workspaceRevisionSHA256 == current, source.sourceSHA256 == sourceSHA256 else {
            throw ImportBulkFailureV1.changedInputQuarantined
        }
    }

    static func deterministicPlanID(
        workspaceID: WorkspaceID,
        source: ImportSourceV1,
        schemaRelease: ImportSchemaReleaseV1,
        mappingProfileSHA256: String?,
        workspaceRevisionSHA256: String,
        rows: [ImportPlanRowV1]
    ) throws -> UUID {
        try ImportBulkCanonicalCodecV1.deterministicUUID(
            namespace: "import-plan-v1",
            basis: DeterministicIDBasis(
                workspaceID: workspaceID,
                sourceSHA256: source.sourceSHA256,
                schemaSHA256: schemaRelease.schemaSHA256,
                mappingProfileSHA256: mappingProfileSHA256,
                workspaceRevisionSHA256: workspaceRevisionSHA256,
                rows: rows
            )
        )
    }

    private var digestBasis: DigestBasis {
        DigestBasis(schemaVersion: schemaVersion, planID: planID, workspaceID: workspaceID,
                    source: source, schemaRelease: schemaRelease,
                    mappingProfileSHA256: mappingProfileSHA256,
                    workspaceRevisionSHA256: workspaceRevisionSHA256, rows: rows,
                    previewWritesCanonicalState: previewWritesCanonicalState)
    }
    private struct DigestBasis: Codable {
        let schemaVersion: Int
        let planID: UUID
        let workspaceID: WorkspaceID
        let source: ImportSourceV1
        let schemaRelease: ImportSchemaReleaseV1
        let mappingProfileSHA256: String?
        let workspaceRevisionSHA256: String
        let rows: [ImportPlanRowV1]
        let previewWritesCanonicalState: Bool
    }
    private struct DeterministicIDBasis: Codable {
        let workspaceID: WorkspaceID
        let sourceSHA256: String
        let schemaSHA256: String
        let mappingProfileSHA256: String?
        let workspaceRevisionSHA256: String
        let rows: [ImportPlanRowV1]
    }
}

/// The typed, non-persistent bridge from a validated import row to one of the
/// existing workspace command cases. It never grants a command kind by itself.
struct ImportCommandMaterializationContextV1: Sendable {
    let plan: ImportPlanV1
    let rowIdentity: ImportRowIdentityV1
    let row: ImportPlanRowV1
    let command: ImportProposedCommandV1
    let chunkIndex: Int
    let mutationID: MutationIDV1
    let expectedRevision: WorkspaceExpectedRevisionV1

    init(
        plan: ImportPlanV1,
        rowIdentity: ImportRowIdentityV1,
        row: ImportPlanRowV1,
        command: ImportProposedCommandV1,
        chunkIndex: Int,
        mutationID: MutationIDV1,
        expectedRevision: WorkspaceExpectedRevisionV1
    ) throws {
        self.plan = plan
        self.rowIdentity = rowIdentity
        self.row = row
        self.command = command
        self.chunkIndex = chunkIndex
        self.mutationID = mutationID
        self.expectedRevision = expectedRevision
        try validate()
    }

    func validate() throws {
        try plan.validate()
        try rowIdentity.validate()
        try row.validate()
        try command.validate()
        guard chunkIndex >= 0,
              plan.rows.contains(row),
              rowIdentity == row.identity,
              row.commands.contains(command),
              expectedRevision.workspaceID == plan.workspaceID,
              mutationID == (try BulkCommandPlanV1.deterministicMutationID(
                  importPlanID: plan.planID,
                  chunkIndex: chunkIndex,
                  rowIdentitySHA256: row.identity.identitySHA256
              )),
              command.payloadSHA256 == (try ImportProposedCommandV1.canonicalPayloadSHA256(
                  commandID: command.commandID,
                  kind: command.kind,
                  targetStableID: command.targetStableID,
                  expectedRevision: command.expectedRevision,
                  dependencyCommandIDs: command.dependencyCommandIDs,
                  rowIdentity: rowIdentity,
                  schemaRelease: plan.schemaRelease,
                  mappedFields: row.mappedFields
              )) else {
            throw ImportBulkFailureV1.invalidValue
        }
    }

    func validate(materialized request: WorkspaceMutationRequestV1) throws {
        try validate()
        guard request.mutationID == mutationID,
              request.expectedRevision == expectedRevision else {
            throw ImportBulkFailureV1.invalidValue
        }
    }

}

/// Implementations may materialize only an already-supported
/// `WorkspaceCommandV1` case. Unsupported rows must throw rather than invent a
/// command, writer, or persistent side channel.
protocol ImportWorkspaceCommandMaterializingV1: Sendable {
    func materialize(
        _ context: ImportCommandMaterializationContextV1
    ) throws -> WorkspaceMutationRequestV1
}

extension ImportWorkspaceCommandMaterializingV1 {
    func materializeValidated(
        _ context: ImportCommandMaterializationContextV1
    ) throws -> WorkspaceMutationRequestV1 {
        try context.validate()
        let request = try materialize(context)
        try context.validate(materialized: request)
        return request
    }
}

enum BulkAtomicityV1: String, Codable, CaseIterable, Hashable, Sendable {
    case allOrNothing = "ALL_OR_NOTHING"
    case chunkedAtomic = "CHUNKED_ATOMIC"
}

struct BulkChunkPlanV1: Codable, Equatable, Hashable, Comparable, Sendable {
    let chunkID: UUID
    let chunkIndex: Int
    let rowIdentitySHA256s: [String]
    let mutationIDs: [MutationIDV1]
    let chunkSHA256: String

    init(chunkIndex: Int, rowIdentitySHA256s: [String], mutationIDs: [MutationIDV1]) throws {
        chunkID = try ImportBulkCanonicalCodecV1.deterministicUUID(
            namespace: "bulk-chunk-v1",
            basis: IDBasis(
                chunkIndex: chunkIndex,
                rowIdentitySHA256s: rowIdentitySHA256s,
                mutationIDs: mutationIDs
            )
        )
        self.chunkIndex = chunkIndex
        self.rowIdentitySHA256s = rowIdentitySHA256s
        self.mutationIDs = mutationIDs
        chunkSHA256 = try ImportBulkCanonicalCodecV1.sha256(
            Basis(chunkIndex: chunkIndex, rowIdentitySHA256s: rowIdentitySHA256s,
                  mutationIDs: mutationIDs)
        )
        try validate()
    }

    func validate() throws {
        try rowIdentitySHA256s.forEach(ImportBulkCanonicalCodecV1.requireDigest)
        guard chunkIndex >= 0,
              chunkID == (try ImportBulkCanonicalCodecV1.deterministicUUID(
                  namespace: "bulk-chunk-v1",
                  basis: IDBasis(
                      chunkIndex: chunkIndex,
                      rowIdentitySHA256s: rowIdentitySHA256s,
                      mutationIDs: mutationIDs
                  )
              )),
              !rowIdentitySHA256s.isEmpty,
              rowIdentitySHA256s.count <= ImportBulkLimitsV1.maximumRowsPerChunk,
              Set(rowIdentitySHA256s).count == rowIdentitySHA256s.count,
              mutationIDs.count == rowIdentitySHA256s.count,
              Set(mutationIDs).count == mutationIDs.count,
              chunkSHA256 == (try ImportBulkCanonicalCodecV1.sha256(basis)) else {
            throw ImportBulkFailureV1.invalidValue
        }
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.chunkIndex < rhs.chunkIndex }
    private var basis: Basis { Basis(chunkIndex: chunkIndex,
                                     rowIdentitySHA256s: rowIdentitySHA256s,
                                     mutationIDs: mutationIDs) }
    private struct Basis: Codable {
        let chunkIndex: Int
        let rowIdentitySHA256s: [String]
        let mutationIDs: [MutationIDV1]
    }
    private struct IDBasis: Codable {
        let chunkIndex: Int
        let rowIdentitySHA256s: [String]
        let mutationIDs: [MutationIDV1]
    }
}

struct BulkCommandPlanV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let bulkPlanID: UUID
    let importPlanID: UUID
    let importPlanSHA256: String
    let workspaceID: WorkspaceID
    let atomicity: BulkAtomicityV1
    let chunks: [BulkChunkPlanV1]
    let planSHA256: String

    init(bulkPlanID: UUID, importPlan: ImportPlanV1, atomicity: BulkAtomicityV1,
         chunks: [BulkChunkPlanV1]) throws {
        try importPlan.validate()
        guard bulkPlanID == (try Self.deterministicBulkPlanID(
            importPlan: importPlan,
            atomicity: atomicity,
            chunks: chunks
        )) else { throw ImportBulkFailureV1.invalidValue }
        schemaVersion = Self.schemaVersion
        self.bulkPlanID = bulkPlanID
        importPlanID = importPlan.planID
        importPlanSHA256 = importPlan.planSHA256
        workspaceID = importPlan.workspaceID
        self.atomicity = atomicity
        self.chunks = chunks
        planSHA256 = try ImportBulkCanonicalCodecV1.sha256(
            DigestBasis(schemaVersion: Self.schemaVersion, bulkPlanID: bulkPlanID,
                        importPlanID: importPlan.planID, importPlanSHA256: importPlan.planSHA256,
                        workspaceID: importPlan.workspaceID, atomicity: atomicity, chunks: chunks)
        )
        try validate(importPlan: importPlan)
    }

    func validate(importPlan: ImportPlanV1? = nil) throws {
        try ImportBulkCanonicalCodecV1.requireID(bulkPlanID)
        try ImportBulkCanonicalCodecV1.requireID(importPlanID)
        try ImportBulkCanonicalCodecV1.requireDigest(importPlanSHA256)
        try chunks.forEach { try $0.validate() }
        let indexes = chunks.map(\.chunkIndex)
        let expectedIndexes = Array(0..<chunks.count)
        let mutationRowIDs = chunks.flatMap(\.rowIdentitySHA256s)
        guard schemaVersion == Self.schemaVersion,
              !chunks.isEmpty,
              chunks.count <= ImportBulkLimitsV1.maximumChunks,
              chunks == chunks.sorted(),
              indexes == expectedIndexes,
              Set(mutationRowIDs).count == mutationRowIDs.count,
              (atomicity == .chunkedAtomic || chunks.count == 1),
              planSHA256 == (try ImportBulkCanonicalCodecV1.sha256(digestBasis)) else {
            throw ImportBulkFailureV1.invalidValue
        }
        if let importPlan {
            try importPlan.validate()
            let expectedRows = importPlan.rows.filter(\.disposition.proposesMutation)
                .map(\.identity.identitySHA256)
            guard importPlan.planID == importPlanID,
                  importPlan.planSHA256 == importPlanSHA256,
                  importPlan.workspaceID == workspaceID,
                  mutationRowIDs == expectedRows else {
                throw ImportBulkFailureV1.digestMismatch
            }
            for chunk in chunks {
                for (rowIndex, rowIdentitySHA256) in chunk.rowIdentitySHA256s.enumerated() {
                    guard chunk.mutationIDs[rowIndex] == (try Self.deterministicMutationID(
                        importPlanID: importPlan.planID,
                        chunkIndex: chunk.chunkIndex,
                        rowIdentitySHA256: rowIdentitySHA256
                    )) else { throw ImportBulkFailureV1.digestMismatch }
                }
            }
        }
    }

    static func deterministicBulkPlanID(
        importPlan: ImportPlanV1,
        atomicity: BulkAtomicityV1,
        chunks: [BulkChunkPlanV1]
    ) throws -> UUID {
        try ImportBulkCanonicalCodecV1.deterministicUUID(
            namespace: "bulk-command-plan-v1",
            basis: DeterministicIDBasis(
                importPlanID: importPlan.planID,
                importPlanSHA256: importPlan.planSHA256,
                atomicity: atomicity,
                chunks: chunks.map { ChunkIdentity(chunkIndex: $0.chunkIndex, chunkID: $0.chunkID) }
            )
        )
    }

    static func deterministicMutationID(
        importPlanID: UUID,
        chunkIndex: Int,
        rowIdentitySHA256: String
    ) throws -> MutationIDV1 {
        let value = try ImportBulkCanonicalCodecV1.deterministicUUID(
            namespace: "bulk-mutation-v1",
            basis: MutationIDBasis(
                importPlanID: importPlanID,
                chunkIndex: chunkIndex,
                rowIdentitySHA256: rowIdentitySHA256
            )
        )
        return try MutationIDV1(rawValue: value)
    }

    func mutationID(chunkIndex: Int, rowIndex: Int) throws -> MutationIDV1 {
        guard chunks.indices.contains(chunkIndex),
              chunks[chunkIndex].mutationIDs.indices.contains(rowIndex) else {
            throw ImportBulkFailureV1.invalidValue
        }
        return chunks[chunkIndex].mutationIDs[rowIndex]
    }
    private var digestBasis: DigestBasis {
        DigestBasis(schemaVersion: schemaVersion, bulkPlanID: bulkPlanID,
                    importPlanID: importPlanID, importPlanSHA256: importPlanSHA256,
                    workspaceID: workspaceID, atomicity: atomicity, chunks: chunks)
    }
    private struct DigestBasis: Codable {
        let schemaVersion: Int
        let bulkPlanID: UUID
        let importPlanID: UUID
        let importPlanSHA256: String
        let workspaceID: WorkspaceID
        let atomicity: BulkAtomicityV1
        let chunks: [BulkChunkPlanV1]
    }
    private struct DeterministicIDBasis: Codable {
        let importPlanID: UUID
        let importPlanSHA256: String
        let atomicity: BulkAtomicityV1
        let chunks: [ChunkIdentity]
    }
    private struct ChunkIdentity: Codable {
        let chunkIndex: Int
        let chunkID: UUID
    }
    private struct MutationIDBasis: Codable {
        let importPlanID: UUID
        let chunkIndex: Int
        let rowIdentitySHA256: String
    }
}

enum BulkCommitDispositionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case noEffect = "NO_EFFECT"
    case committed = "COMMITTED"
    case partialCommitted = "PARTIAL_COMMITTED"
    case cancelledBeforeCommit = "CANCELLED_BEFORE_COMMIT"
    case cancelledAfterPartialCommit = "CANCELLED_AFTER_PARTIAL_COMMIT"
    case quarantinedChangedInput = "QUARANTINED_CHANGED_INPUT"
}

/// Immutable audit evidence for one exact chunk of one exact bulk plan.
struct BulkCommitReceiptV1: Codable, Equatable, Hashable, Comparable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let receiptID: UUID
    let workspaceID: WorkspaceID
    let bulkPlanID: UUID
    let bulkPlanSHA256: String
    let chunkIndex: Int
    let rowIdentitySHA256s: [String]
    let mutationIDs: [MutationIDV1]
    let expectedWorkspaceRevisionSHA256: String
    let disposition: BulkCommitDispositionV1
    let committedMutationIDs: [MutationIDV1]
    let receiptSHA256: String

    init(
        receiptID: UUID,
        workspaceID: WorkspaceID,
        bulkPlan: BulkCommandPlanV1,
        chunkIndex: Int,
        expectedWorkspaceRevisionSHA256: String,
        disposition: BulkCommitDispositionV1,
        committedMutationIDs: [MutationIDV1]
    ) throws {
        try bulkPlan.validate()
        guard bulkPlan.chunks.indices.contains(chunkIndex) else {
            throw ImportBulkFailureV1.invalidValue
        }
        let chunk = bulkPlan.chunks[chunkIndex]
        schemaVersion = Self.schemaVersion
        self.receiptID = receiptID
        self.workspaceID = workspaceID
        bulkPlanID = bulkPlan.bulkPlanID
        bulkPlanSHA256 = bulkPlan.planSHA256
        self.chunkIndex = chunkIndex
        rowIdentitySHA256s = chunk.rowIdentitySHA256s
        mutationIDs = chunk.mutationIDs
        self.expectedWorkspaceRevisionSHA256 = expectedWorkspaceRevisionSHA256
        self.disposition = disposition
        self.committedMutationIDs = committedMutationIDs
        receiptSHA256 = try ImportBulkCanonicalCodecV1.sha256(
            DigestBasis(
                schemaVersion: Self.schemaVersion,
                receiptID: receiptID,
                workspaceID: workspaceID,
                bulkPlanID: bulkPlan.bulkPlanID,
                bulkPlanSHA256: bulkPlan.planSHA256,
                chunkIndex: chunkIndex,
                rowIdentitySHA256s: chunk.rowIdentitySHA256s,
                mutationIDs: chunk.mutationIDs,
                expectedWorkspaceRevisionSHA256: expectedWorkspaceRevisionSHA256,
                disposition: disposition,
                committedMutationIDs: committedMutationIDs
            )
        )
        try validate()
    }

    func validate() throws {
        try ImportBulkCanonicalCodecV1.requireID(receiptID)
        try ImportBulkCanonicalCodecV1.requireID(bulkPlanID)
        try ImportBulkCanonicalCodecV1.requireDigest(bulkPlanSHA256)
        try ImportBulkCanonicalCodecV1.requireDigest(expectedWorkspaceRevisionSHA256)
        try rowIdentitySHA256s.forEach(ImportBulkCanonicalCodecV1.requireDigest)
        guard schemaVersion == Self.schemaVersion,
              chunkIndex >= 0,
              !rowIdentitySHA256s.isEmpty,
              rowIdentitySHA256s.count == mutationIDs.count,
              Set(rowIdentitySHA256s).count == rowIdentitySHA256s.count,
              Set(mutationIDs).count == mutationIDs.count,
              Set(committedMutationIDs).count == committedMutationIDs.count,
              Set(committedMutationIDs).isSubset(of: Set(mutationIDs)),
              receiptTruthIsExact,
              receiptSHA256 == (try ImportBulkCanonicalCodecV1.sha256(digestBasis)) else {
            throw ImportBulkFailureV1.digestMismatch
        }
    }

    var isTerminalWithoutMutation: Bool {
        disposition == .noEffect || disposition == .cancelledBeforeCommit
            || disposition == .quarantinedChangedInput
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, receiptID, workspaceID, bulkPlanID, bulkPlanSHA256,
             chunkIndex, rowIdentitySHA256s, mutationIDs, expectedWorkspaceRevisionSHA256,
             disposition, committedMutationIDs, receiptSHA256
    }

    init(from decoder: Decoder) throws {
        try ImportBulkCanonicalCodecV1.rejectUnknownKeys(decoder, CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        receiptID = try container.decode(UUID.self, forKey: .receiptID)
        workspaceID = try container.decode(WorkspaceID.self, forKey: .workspaceID)
        bulkPlanID = try container.decode(UUID.self, forKey: .bulkPlanID)
        bulkPlanSHA256 = try container.decode(String.self, forKey: .bulkPlanSHA256)
        chunkIndex = try container.decode(Int.self, forKey: .chunkIndex)
        rowIdentitySHA256s = try container.decode([String].self, forKey: .rowIdentitySHA256s)
        mutationIDs = try container.decode([MutationIDV1].self, forKey: .mutationIDs)
        expectedWorkspaceRevisionSHA256 = try container.decode(String.self, forKey: .expectedWorkspaceRevisionSHA256)
        disposition = try container.decode(BulkCommitDispositionV1.self, forKey: .disposition)
        committedMutationIDs = try container.decode([MutationIDV1].self, forKey: .committedMutationIDs)
        receiptSHA256 = try container.decode(String.self, forKey: .receiptSHA256)
        try validate()
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.chunkIndex == rhs.chunkIndex
            ? lhs.receiptSHA256 < rhs.receiptSHA256
            : lhs.chunkIndex < rhs.chunkIndex
    }

    private var receiptTruthIsExact: Bool {
        switch disposition {
        case .noEffect, .cancelledBeforeCommit, .quarantinedChangedInput:
            return committedMutationIDs.isEmpty
        case .committed:
            return committedMutationIDs == mutationIDs
        case .partialCommitted, .cancelledAfterPartialCommit:
            return !committedMutationIDs.isEmpty && committedMutationIDs.count < mutationIDs.count
        }
    }

    private var digestBasis: DigestBasis {
        DigestBasis(
            schemaVersion: schemaVersion,
            receiptID: receiptID,
            workspaceID: workspaceID,
            bulkPlanID: bulkPlanID,
            bulkPlanSHA256: bulkPlanSHA256,
            chunkIndex: chunkIndex,
            rowIdentitySHA256s: rowIdentitySHA256s,
            mutationIDs: mutationIDs,
            expectedWorkspaceRevisionSHA256: expectedWorkspaceRevisionSHA256,
            disposition: disposition,
            committedMutationIDs: committedMutationIDs
        )
    }

    private struct DigestBasis: Codable {
        let schemaVersion: Int
        let receiptID: UUID
        let workspaceID: WorkspaceID
        let bulkPlanID: UUID
        let bulkPlanSHA256: String
        let chunkIndex: Int
        let rowIdentitySHA256s: [String]
        let mutationIDs: [MutationIDV1]
        let expectedWorkspaceRevisionSHA256: String
        let disposition: BulkCommitDispositionV1
        let committedMutationIDs: [MutationIDV1]
    }
}

enum BulkSessionStateV1: String, Codable, CaseIterable, Hashable, Sendable {
    case active = "ACTIVE"
    case cancellationRequested = "CANCELLATION_REQUESTED"
    case cancelled = "CANCELLED"
    case completed = "COMPLETED"
    case quarantinedChangedInput = "QUARANTINED_CHANGED_INPUT"
}

/// Recoverable operational progress. The first missing chunk receipt is the
/// only resumable cursor; plan and input changes are quarantined, never merged.
struct BulkSessionV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let sessionID: UUID
    let workspaceID: WorkspaceID
    let bulkPlanID: UUID
    let bulkPlanSHA256: String
    let sourceSHA256: String
    let expectedWorkspaceRevisionSHA256: String
    let state: BulkSessionStateV1
    let chunkReceipts: [BulkCommitReceiptV1]
    let sessionSHA256: String

    init(
        sessionID: UUID,
        workspaceID: WorkspaceID,
        bulkPlan: BulkCommandPlanV1,
        sourceSHA256: String,
        expectedWorkspaceRevisionSHA256: String,
        state: BulkSessionStateV1 = .active,
        chunkReceipts: [BulkCommitReceiptV1] = []
    ) throws {
        try bulkPlan.validate()
        schemaVersion = Self.schemaVersion
        self.sessionID = sessionID
        self.workspaceID = workspaceID
        bulkPlanID = bulkPlan.bulkPlanID
        bulkPlanSHA256 = bulkPlan.planSHA256
        self.sourceSHA256 = sourceSHA256
        self.expectedWorkspaceRevisionSHA256 = expectedWorkspaceRevisionSHA256
        self.state = state
        self.chunkReceipts = chunkReceipts
        sessionSHA256 = try ImportBulkCanonicalCodecV1.sha256(
            DigestBasis(
                schemaVersion: Self.schemaVersion,
                sessionID: sessionID,
                workspaceID: workspaceID,
                bulkPlanID: bulkPlan.bulkPlanID,
                bulkPlanSHA256: bulkPlan.planSHA256,
                sourceSHA256: sourceSHA256,
                expectedWorkspaceRevisionSHA256: expectedWorkspaceRevisionSHA256,
                state: state,
                chunkReceipts: chunkReceipts
            )
        )
        try validate()
    }

    func validate() throws {
        try ImportBulkCanonicalCodecV1.requireID(sessionID)
        try ImportBulkCanonicalCodecV1.requireID(bulkPlanID)
        try ImportBulkCanonicalCodecV1.requireDigest(bulkPlanSHA256)
        try ImportBulkCanonicalCodecV1.requireDigest(sourceSHA256)
        try ImportBulkCanonicalCodecV1.requireDigest(expectedWorkspaceRevisionSHA256)
        try chunkReceipts.forEach { try $0.validate() }
        let chunkIndices = chunkReceipts.map(\.chunkIndex)
        guard schemaVersion == Self.schemaVersion,
              chunkReceipts == chunkReceipts.sorted(),
              Set(chunkIndices).count == chunkIndices.count,
              chunkReceipts.allSatisfy {
                  $0.workspaceID == workspaceID && $0.bulkPlanID == bulkPlanID
                      && $0.bulkPlanSHA256 == bulkPlanSHA256
                      && $0.expectedWorkspaceRevisionSHA256 == expectedWorkspaceRevisionSHA256
              },
              sessionTruthIsExact,
              sessionSHA256 == (try ImportBulkCanonicalCodecV1.sha256(digestBasis)) else {
            throw ImportBulkFailureV1.digestMismatch
        }
    }

    func validateResumption(
        bulkPlan: BulkCommandPlanV1,
        sourceSHA256 currentSourceSHA256: String,
        workspaceRevisionSHA256 currentWorkspaceRevisionSHA256: String
    ) throws {
        try validate()
        try bulkPlan.validate()
        guard bulkPlan.bulkPlanID == bulkPlanID,
              bulkPlan.planSHA256 == bulkPlanSHA256,
              bulkPlan.workspaceID == workspaceID,
              sourceSHA256 == currentSourceSHA256,
              expectedWorkspaceRevisionSHA256 == currentWorkspaceRevisionSHA256,
              state != .quarantinedChangedInput else {
            throw ImportBulkFailureV1.changedInputQuarantined
        }
    }

    func firstMissingReceiptChunkIndex(in bulkPlan: BulkCommandPlanV1) throws -> Int? {
        try validateResumption(
            bulkPlan: bulkPlan,
            sourceSHA256: sourceSHA256,
            workspaceRevisionSHA256: expectedWorkspaceRevisionSHA256
        )
        let recorded = Set(chunkReceipts.map(\.chunkIndex))
        return bulkPlan.chunks.indices.first(where: { !recorded.contains($0) })
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, sessionID, workspaceID, bulkPlanID, bulkPlanSHA256,
             sourceSHA256, expectedWorkspaceRevisionSHA256, state, chunkReceipts, sessionSHA256
    }

    init(from decoder: Decoder) throws {
        try ImportBulkCanonicalCodecV1.rejectUnknownKeys(decoder, CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        sessionID = try container.decode(UUID.self, forKey: .sessionID)
        workspaceID = try container.decode(WorkspaceID.self, forKey: .workspaceID)
        bulkPlanID = try container.decode(UUID.self, forKey: .bulkPlanID)
        bulkPlanSHA256 = try container.decode(String.self, forKey: .bulkPlanSHA256)
        sourceSHA256 = try container.decode(String.self, forKey: .sourceSHA256)
        expectedWorkspaceRevisionSHA256 = try container.decode(String.self, forKey: .expectedWorkspaceRevisionSHA256)
        state = try container.decode(BulkSessionStateV1.self, forKey: .state)
        chunkReceipts = try container.decode([BulkCommitReceiptV1].self, forKey: .chunkReceipts)
        sessionSHA256 = try container.decode(String.self, forKey: .sessionSHA256)
        try validate()
    }

    private var sessionTruthIsExact: Bool {
        switch state {
        case .active:
            return !chunkReceipts.contains { $0.disposition == .cancelledBeforeCommit
                || $0.disposition == .cancelledAfterPartialCommit
                || $0.disposition == .quarantinedChangedInput }
        case .cancellationRequested:
            return true
        case .cancelled:
            return chunkReceipts.last.map {
                $0.disposition == .cancelledBeforeCommit || $0.disposition == .cancelledAfterPartialCommit
            } ?? false
        case .completed:
            return !chunkReceipts.isEmpty && !chunkReceipts.contains {
                $0.disposition == .partialCommitted || $0.disposition == .cancelledAfterPartialCommit
                    || $0.disposition == .quarantinedChangedInput
            }
        case .quarantinedChangedInput:
            return chunkReceipts.last?.disposition == .quarantinedChangedInput
        }
    }

    private var digestBasis: DigestBasis {
        DigestBasis(
            schemaVersion: schemaVersion,
            sessionID: sessionID,
            workspaceID: workspaceID,
            bulkPlanID: bulkPlanID,
            bulkPlanSHA256: bulkPlanSHA256,
            sourceSHA256: sourceSHA256,
            expectedWorkspaceRevisionSHA256: expectedWorkspaceRevisionSHA256,
            state: state,
            chunkReceipts: chunkReceipts
        )
    }

    private struct DigestBasis: Codable {
        let schemaVersion: Int
        let sessionID: UUID
        let workspaceID: WorkspaceID
        let bulkPlanID: UUID
        let bulkPlanSHA256: String
        let sourceSHA256: String
        let expectedWorkspaceRevisionSHA256: String
        let state: BulkSessionStateV1
        let chunkReceipts: [BulkCommitReceiptV1]
    }
}

enum ImportCorrectionCodeV1: String, Codable, CaseIterable, Hashable, Sendable {
    case invalidValue = "INVALID_VALUE"
    case missingRequiredValue = "MISSING_REQUIRED_VALUE"
    case duplicateExternalKey = "DUPLICATE_EXTERNAL_KEY"
    case ambiguousTarget = "AMBIGUOUS_TARGET"
    case staleExpectedRevision = "STALE_EXPECTED_REVISION"
    case nonAllowlistedColumn = "NONALLOWLISTED_COLUMN"
    case unknownSchemaRelease = "UNKNOWN_SCHEMA_RELEASE"
}

struct ImportCorrectionArtifactV1: Codable, Equatable, Hashable, Comparable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let rowIdentity: ImportRowIdentityV1
    let errorCode: ImportCorrectionCodeV1
    let offendingColumn: String
    let boundedCorrectionHint: String
    let retryIdentitySHA256: String
    let artifactSHA256: String

    init(rowIdentity: ImportRowIdentityV1, errorCode: ImportCorrectionCodeV1,
         offendingColumn: String, boundedCorrectionHint: String) throws {
        schemaVersion = Self.schemaVersion
        self.rowIdentity = rowIdentity
        self.errorCode = errorCode
        self.offendingColumn = offendingColumn
        self.boundedCorrectionHint = boundedCorrectionHint
        retryIdentitySHA256 = try ImportBulkCanonicalCodecV1.sha256(
            RetryBasis(rowIdentitySHA256: rowIdentity.identitySHA256,
                       errorCode: errorCode, offendingColumn: offendingColumn)
        )
        artifactSHA256 = try ImportBulkCanonicalCodecV1.sha256(
            DigestBasis(schemaVersion: Self.schemaVersion, rowIdentity: rowIdentity,
                        errorCode: errorCode, offendingColumn: offendingColumn,
                        boundedCorrectionHint: boundedCorrectionHint,
                        retryIdentitySHA256: retryIdentitySHA256)
        )
        try validate()
    }

    func validate() throws {
        try rowIdentity.validate()
        try ImportBulkCanonicalCodecV1.requireText(offendingColumn)
        try ImportBulkCanonicalCodecV1.requireText(boundedCorrectionHint)
        guard schemaVersion == Self.schemaVersion,
              retryIdentitySHA256 == (try ImportBulkCanonicalCodecV1.sha256(retryBasis)),
              artifactSHA256 == (try ImportBulkCanonicalCodecV1.sha256(digestBasis)) else {
            throw ImportBulkFailureV1.digestMismatch
        }
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rowIdentity < rhs.rowIdentity }
    private var retryBasis: RetryBasis { RetryBasis(rowIdentitySHA256: rowIdentity.identitySHA256,
                                                    errorCode: errorCode,
                                                    offendingColumn: offendingColumn) }
    private var digestBasis: DigestBasis {
        DigestBasis(schemaVersion: schemaVersion, rowIdentity: rowIdentity,
                    errorCode: errorCode, offendingColumn: offendingColumn,
                    boundedCorrectionHint: boundedCorrectionHint,
                    retryIdentitySHA256: retryIdentitySHA256)
    }
    private struct RetryBasis: Codable { let rowIdentitySHA256: String; let errorCode: ImportCorrectionCodeV1; let offendingColumn: String }
    private struct DigestBasis: Codable {
        let schemaVersion: Int
        let rowIdentity: ImportRowIdentityV1
        let errorCode: ImportCorrectionCodeV1
        let offendingColumn: String
        let boundedCorrectionHint: String
        let retryIdentitySHA256: String
    }
}

struct ExportSchemaReleaseV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let releaseID: String
    let release: UInt64
    let sourceImportSchemaSHA256: String
    let stableExternalKeyColumn: String
    let expectedRevisionColumn: String
    let editableColumns: [String]
    let schemaSHA256: String

    init(releaseID: String, release: UInt64, importSchema: ImportSchemaReleaseV1,
         expectedRevisionColumn: String) throws {
        try importSchema.validate()
        schemaVersion = Self.schemaVersion
        self.releaseID = releaseID
        self.release = release
        sourceImportSchemaSHA256 = importSchema.schemaSHA256
        stableExternalKeyColumn = importSchema.externalKeyColumn
        self.expectedRevisionColumn = expectedRevisionColumn
        editableColumns = importSchema.editableColumns.sorted()
        schemaSHA256 = try ImportBulkCanonicalCodecV1.sha256(
            DigestBasis(schemaVersion: Self.schemaVersion, releaseID: releaseID, release: release,
                        sourceImportSchemaSHA256: importSchema.schemaSHA256,
                        stableExternalKeyColumn: importSchema.externalKeyColumn,
                        expectedRevisionColumn: expectedRevisionColumn,
                        editableColumns: importSchema.editableColumns.sorted())
        )
        try validate()
    }

    func validate() throws {
        try ImportBulkCanonicalCodecV1.requireText(releaseID)
        try ImportBulkCanonicalCodecV1.requireText(stableExternalKeyColumn)
        try ImportBulkCanonicalCodecV1.requireText(expectedRevisionColumn)
        try ImportBulkCanonicalCodecV1.requireDigest(sourceImportSchemaSHA256)
        try editableColumns.forEach(ImportBulkCanonicalCodecV1.requireText)
        try ImportBulkCanonicalCodecV1.requireSortedUnique(editableColumns)
        guard schemaVersion == Self.schemaVersion,
              release > 0,
              !editableColumns.isEmpty,
              !editableColumns.contains(stableExternalKeyColumn),
              !editableColumns.contains(expectedRevisionColumn),
              schemaSHA256 == (try ImportBulkCanonicalCodecV1.sha256(digestBasis)) else {
            throw ImportBulkFailureV1.nonAllowlistedField
        }
    }

    func permitsUpdate(column: String) -> Bool { editableColumns.binarySearchContains(column) }
    private var digestBasis: DigestBasis {
        DigestBasis(schemaVersion: schemaVersion, releaseID: releaseID, release: release,
                    sourceImportSchemaSHA256: sourceImportSchemaSHA256,
                    stableExternalKeyColumn: stableExternalKeyColumn,
                    expectedRevisionColumn: expectedRevisionColumn,
                    editableColumns: editableColumns)
    }
    private struct DigestBasis: Codable {
        let schemaVersion: Int
        let releaseID: String
        let release: UInt64
        let sourceImportSchemaSHA256: String
        let stableExternalKeyColumn: String
        let expectedRevisionColumn: String
        let editableColumns: [String]
    }
}

enum DeterministicCSVExportKindV1: String, Codable, CaseIterable, Hashable, Sendable {
    case inventory = "INVENTORY"
    case currentIssues = "CURRENT_ISSUES"
    case correctionArtifacts = "CORRECTION_ARTIFACTS"
    case roundTripUpdateTemplate = "ROUND_TRIP_UPDATE_TEMPLATE"
}

struct DeterministicCSVExportV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let exportID: UUID
    let workspaceID: WorkspaceID
    let kind: DeterministicCSVExportKindV1
    let exportSchema: ExportSchemaReleaseV1
    let rowCount: Int
    let utf8NFC: Bool
    let localeNeutralCanonicalFields: Bool
    let formulaAndControlPrefixesNeutralized: Bool
    let bytes: Data
    let bytesSHA256: String
    let exportSHA256: String

    init(exportID: UUID, workspaceID: WorkspaceID, kind: DeterministicCSVExportKindV1,
         exportSchema: ExportSchemaReleaseV1, rowCount: Int, bytes: Data) throws {
        schemaVersion = Self.schemaVersion
        self.exportID = exportID
        self.workspaceID = workspaceID
        self.kind = kind
        self.exportSchema = exportSchema
        self.rowCount = rowCount
        utf8NFC = true
        localeNeutralCanonicalFields = true
        formulaAndControlPrefixesNeutralized = true
        self.bytes = bytes
        bytesSHA256 = KernelCanonicalHashV1.sha256(bytes)
        exportSHA256 = try ImportBulkCanonicalCodecV1.sha256(
            DigestBasis(schemaVersion: Self.schemaVersion, exportID: exportID,
                        workspaceID: workspaceID, kind: kind, exportSchema: exportSchema,
                        rowCount: rowCount, utf8NFC: true,
                        localeNeutralCanonicalFields: true,
                        formulaAndControlPrefixesNeutralized: true,
                        bytesSHA256: KernelCanonicalHashV1.sha256(bytes))
        )
        try validate()
    }

    func validate() throws {
        try ImportBulkCanonicalCodecV1.requireID(exportID)
        try exportSchema.validate()
        guard schemaVersion == Self.schemaVersion,
              (0...ImportBulkLimitsV1.maximumRows).contains(rowCount),
              bytes.count <= Int(ImportBulkLimitsV1.maximumSourceBytes),
              let text = String(data: bytes, encoding: .utf8),
              text == text.precomposedStringWithCanonicalMapping,
              !text.contains("\r\n\r"),
              !text.unicodeScalars.contains(where: { $0.value == 0 || ($0.value < 0x20 && $0 != "\r" && $0 != "\n" && $0 != "\t") }),
              utf8NFC, localeNeutralCanonicalFields, formulaAndControlPrefixesNeutralized,
              bytesSHA256 == KernelCanonicalHashV1.sha256(bytes),
              exportSHA256 == (try ImportBulkCanonicalCodecV1.sha256(digestBasis)) else {
            throw ImportBulkFailureV1.digestMismatch
        }
    }
    private var digestBasis: DigestBasis {
        DigestBasis(schemaVersion: schemaVersion, exportID: exportID, workspaceID: workspaceID,
                    kind: kind, exportSchema: exportSchema, rowCount: rowCount,
                    utf8NFC: utf8NFC, localeNeutralCanonicalFields: localeNeutralCanonicalFields,
                    formulaAndControlPrefixesNeutralized: formulaAndControlPrefixesNeutralized,
                    bytesSHA256: bytesSHA256)
    }
    private struct DigestBasis: Codable {
        let schemaVersion: Int
        let exportID: UUID
        let workspaceID: WorkspaceID
        let kind: DeterministicCSVExportKindV1
        let exportSchema: ExportSchemaReleaseV1
        let rowCount: Int
        let utf8NFC: Bool
        let localeNeutralCanonicalFields: Bool
        let formulaAndControlPrefixesNeutralized: Bool
        let bytesSHA256: String
    }
}

enum ImportLifecycleDispositionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case sourceBytesLeasedScratchNotBackedUp = "SOURCE_BYTES_LEASED_SCRATCH_NOT_BACKED_UP"
    case previewDerivedNotBackedUp = "PREVIEW_DERIVED_NOT_BACKED_UP"
    case unsavedMappingDerived = "UNSAVED_MAPPING_DERIVED"
    case savedMappingWorkspaceConfiguration = "SAVED_MAPPING_WORKSPACE_CONFIGURATION"
    case activeBulkSessionRecoverableOperationalState = "ACTIVE_BULK_SESSION_RECOVERABLE_OPERATIONAL_STATE"
    case bulkCommitReceiptImmutableCanonicalAudit = "BULK_COMMIT_RECEIPT_IMMUTABLE_CANONICAL_AUDIT"
    case importedEntityUsesOrdinaryLifecycle = "IMPORTED_ENTITY_USES_ORDINARY_LIFECYCLE"
    case correctionArtifactDeterministicPortableOutput = "CORRECTION_ARTIFACT_DETERMINISTIC_PORTABLE_OUTPUT"
}

enum ImportAdapterPrivacyClassV1: String, Codable, CaseIterable, Hashable, Sendable {
    case localOperational = "LOCAL_OPERATIONAL"
    case purposeBoundSensitive = "PURPOSE_BOUND_SENSITIVE"
    case prohibited = "PROHIBITED"
}

struct ImportAdapterRegistrationV1: Codable, Equatable, Hashable, Comparable, Sendable {
    let adapterID: String
    let adapterVersion: UInt64
    let schemaReleaseID: String
    let schemaRelease: UInt64
    let entityKinds: [ImportEntityKindV1]
    let requiredSourceKeys: [String]
    let dependencyAdapterIDs: [String]
    let commandKinds: [ImportCommandKindV1]
    let lifecycleDispositions: [ImportLifecycleDispositionV1]
    let privacyClass: ImportAdapterPrivacyClassV1
    let supportsDeterministicExport: Bool
    let fixtureSHA256s: [String]
    let registrationSHA256: String

    init(adapterID: String, adapterVersion: UInt64, schemaReleaseID: String,
         schemaRelease: UInt64, entityKinds: [ImportEntityKindV1],
         requiredSourceKeys: [String], dependencyAdapterIDs: [String],
         commandKinds: [ImportCommandKindV1],
         lifecycleDispositions: [ImportLifecycleDispositionV1],
         privacyClass: ImportAdapterPrivacyClassV1, supportsDeterministicExport: Bool,
         fixtureSHA256s: [String]) throws {
        try ImportBulkCanonicalCodecV1.requireText(adapterID)
        try ImportBulkCanonicalCodecV1.requireText(schemaReleaseID)
        try requiredSourceKeys.forEach(ImportBulkCanonicalCodecV1.requireText)
        try dependencyAdapterIDs.forEach(ImportBulkCanonicalCodecV1.requireText)
        try fixtureSHA256s.forEach(ImportBulkCanonicalCodecV1.requireDigest)
        self.adapterID = adapterID
        self.adapterVersion = adapterVersion
        self.schemaReleaseID = schemaReleaseID
        self.schemaRelease = schemaRelease
        self.entityKinds = entityKinds
        self.requiredSourceKeys = requiredSourceKeys
        self.dependencyAdapterIDs = dependencyAdapterIDs
        self.commandKinds = commandKinds
        self.lifecycleDispositions = lifecycleDispositions
        self.privacyClass = privacyClass
        self.supportsDeterministicExport = supportsDeterministicExport
        self.fixtureSHA256s = fixtureSHA256s
        registrationSHA256 = try ImportBulkCanonicalCodecV1.sha256(
            DigestBasis(adapterID: adapterID, adapterVersion: adapterVersion,
                        schemaReleaseID: schemaReleaseID, schemaRelease: schemaRelease,
                        entityKinds: entityKinds, requiredSourceKeys: requiredSourceKeys,
                        dependencyAdapterIDs: dependencyAdapterIDs, commandKinds: commandKinds,
                        lifecycleDispositions: lifecycleDispositions, privacyClass: privacyClass,
                        supportsDeterministicExport: supportsDeterministicExport,
                        fixtureSHA256s: fixtureSHA256s)
        )
        try validate()
    }

    func validate() throws {
        try ImportBulkCanonicalCodecV1.requireSortedUnique(entityKinds)
        try ImportBulkCanonicalCodecV1.requireSortedUnique(requiredSourceKeys)
        try ImportBulkCanonicalCodecV1.requireSortedUnique(dependencyAdapterIDs)
        try ImportBulkCanonicalCodecV1.requireSortedUnique(commandKinds)
        try fixtureSHA256s.forEach(ImportBulkCanonicalCodecV1.requireDigest)
        guard adapterVersion > 0, schemaRelease > 0,
              !entityKinds.isEmpty, !requiredSourceKeys.isEmpty, !commandKinds.isEmpty,
              dependencyAdapterIDs.count <= ImportBulkLimitsV1.maximumAdapterDependencies,
              !dependencyAdapterIDs.contains(adapterID),
              Set(lifecycleDispositions).count == lifecycleDispositions.count,
              lifecycleDispositions.contains(.importedEntityUsesOrdinaryLifecycle),
              privacyClass != .prohibited,
              registrationSHA256 == (try ImportBulkCanonicalCodecV1.sha256(digestBasis)) else {
            throw ImportBulkFailureV1.invalidValue
        }
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.adapterID < rhs.adapterID }
    private var digestBasis: DigestBasis {
        DigestBasis(adapterID: adapterID, adapterVersion: adapterVersion,
                    schemaReleaseID: schemaReleaseID, schemaRelease: schemaRelease,
                    entityKinds: entityKinds, requiredSourceKeys: requiredSourceKeys,
                    dependencyAdapterIDs: dependencyAdapterIDs, commandKinds: commandKinds,
                    lifecycleDispositions: lifecycleDispositions, privacyClass: privacyClass,
                    supportsDeterministicExport: supportsDeterministicExport,
                    fixtureSHA256s: fixtureSHA256s)
    }
    private struct DigestBasis: Codable {
        let adapterID: String
        let adapterVersion: UInt64
        let schemaReleaseID: String
        let schemaRelease: UInt64
        let entityKinds: [ImportEntityKindV1]
        let requiredSourceKeys: [String]
        let dependencyAdapterIDs: [String]
        let commandKinds: [ImportCommandKindV1]
        let lifecycleDispositions: [ImportLifecycleDispositionV1]
        let privacyClass: ImportAdapterPrivacyClassV1
        let supportsDeterministicExport: Bool
        let fixtureSHA256s: [String]
    }
}

enum ImportAdapterRegistryV1 {
    static func validate(_ registrations: [ImportAdapterRegistrationV1]) throws {
        try registrations.forEach { try $0.validate() }
        guard registrations == registrations.sorted(),
              Set(registrations.map(\.adapterID)).count == registrations.count else {
            throw ImportBulkFailureV1.adapterCollision
        }
        let ids = Set(registrations.map(\.adapterID))
        guard registrations.allSatisfy({ Set($0.dependencyAdapterIDs).isSubset(of: ids) }) else {
            throw ImportBulkFailureV1.invalidValue
        }
        var visited = Set<String>()
        var active = Set<String>()
        let byID = Dictionary(uniqueKeysWithValues: registrations.map { ($0.adapterID, $0) })
        func visit(_ id: String) throws {
            if active.contains(id) { throw ImportBulkFailureV1.dependencyCycle }
            if visited.contains(id) { return }
            active.insert(id)
            for dependency in byID[id]?.dependencyAdapterIDs ?? [] { try visit(dependency) }
            active.remove(id)
            visited.insert(id)
        }
        for id in ids.sorted() { try visit(id) }
    }
}

enum ImportBulkWorkspaceRebindSubjectV1: String, Codable, CaseIterable, Hashable, Sendable {
    case savedMappingProfile = "SAVED_MAPPING_PROFILE"
    case bulkSession = "BULK_SESSION"
    case bulkCommitReceipt = "BULK_COMMIT_RECEIPT"
}

enum ImportBulkWorkspaceRebindRejectionReasonV1: String, Codable, CaseIterable, Hashable, Sendable {
    case targetEqualsSource = "TARGET_EQUALS_SOURCE"
    case schemaBindingMismatch = "SCHEMA_BINDING_MISMATCH"
    case targetPlanWorkspaceMismatch = "TARGET_PLAN_WORKSPACE_MISMATCH"
    case sourceDigestMismatch = "SOURCE_DIGEST_MISMATCH"
    case activeSessionRequired = "ACTIVE_SESSION_REQUIRED"
    case committedSessionCannotBeReplayed = "COMMITTED_SESSION_CANNOT_BE_REPLAYED"
    case immutableAuditReceiptCannotBeRebound = "IMMUTABLE_AUDIT_RECEIPT_CANNOT_BE_REBOUND"
}

/// Deterministic, target-scoped evidence that a clone/fork restore refused to
/// invent plan, revision, or immutable-audit history. It deliberately keeps no
/// source workspace identifier; the source artifact is represented only by its
/// already-validated canonical digest.
struct ImportBulkWorkspaceRebindRejectionV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let targetWorkspaceID: WorkspaceID
    let subject: ImportBulkWorkspaceRebindSubjectV1
    let sourceArtifactSHA256: String
    let reason: ImportBulkWorkspaceRebindRejectionReasonV1
    let rejectionSHA256: String

    init(
        targetWorkspaceID: WorkspaceID,
        subject: ImportBulkWorkspaceRebindSubjectV1,
        sourceArtifactSHA256: String,
        reason: ImportBulkWorkspaceRebindRejectionReasonV1
    ) throws {
        schemaVersion = Self.schemaVersion
        self.targetWorkspaceID = targetWorkspaceID
        self.subject = subject
        self.sourceArtifactSHA256 = sourceArtifactSHA256
        self.reason = reason
        rejectionSHA256 = try ImportBulkCanonicalCodecV1.sha256(
            Basis(
                schemaVersion: Self.schemaVersion,
                targetWorkspaceID: targetWorkspaceID,
                subject: subject,
                sourceArtifactSHA256: sourceArtifactSHA256,
                reason: reason
            )
        )
        try validate()
    }

    func validate() throws {
        try ImportBulkCanonicalCodecV1.requireID(targetWorkspaceID.rawValue)
        try ImportBulkCanonicalCodecV1.requireDigest(sourceArtifactSHA256)
        guard schemaVersion == Self.schemaVersion,
              rejectionSHA256 == (try ImportBulkCanonicalCodecV1.sha256(basis)) else {
            throw ImportBulkFailureV1.digestMismatch
        }
    }

    private var basis: Basis {
        Basis(
            schemaVersion: schemaVersion,
            targetWorkspaceID: targetWorkspaceID,
            subject: subject,
            sourceArtifactSHA256: sourceArtifactSHA256,
            reason: reason
        )
    }

    private struct Basis: Codable {
        let schemaVersion: Int
        let targetWorkspaceID: WorkspaceID
        let subject: ImportBulkWorkspaceRebindSubjectV1
        let sourceArtifactSHA256: String
        let reason: ImportBulkWorkspaceRebindRejectionReasonV1
    }
}

enum ImportBulkWorkspaceRebindOutcomeV1: Codable, Equatable, Hashable, Sendable {
    case mappingProfile(ImportMappingProfileV1)
    case bulkSession(BulkSessionV1)
    case rejected(ImportBulkWorkspaceRebindRejectionV1)
}

/// Clone/fork restore factory. It returns a rebuilt value only where every
/// workspace-bound digest, plan reference, and revision input is supplied and
/// provable; otherwise it returns deterministic rejection evidence.
enum ImportBulkWorkspaceRebindingFactoryV1 {
    static func rebind(
        mappingProfile source: ImportMappingProfileV1,
        to targetWorkspaceID: WorkspaceID,
        schemaRelease targetSchemaRelease: ImportSchemaReleaseV1
    ) throws -> ImportBulkWorkspaceRebindOutcomeV1 {
        try source.validate()
        try targetSchemaRelease.validate()
        try ImportBulkCanonicalCodecV1.requireID(targetWorkspaceID.rawValue)
        guard source.workspaceID != targetWorkspaceID else {
            return try rejected(
                targetWorkspaceID: targetWorkspaceID,
                subject: .savedMappingProfile,
                sourceArtifactSHA256: source.profileSHA256,
                reason: .targetEqualsSource
            )
        }
        guard source.schemaReleaseID == targetSchemaRelease.releaseID,
              source.schemaRelease == targetSchemaRelease.release,
              source.schemaSHA256 == targetSchemaRelease.schemaSHA256 else {
            return try rejected(
                targetWorkspaceID: targetWorkspaceID,
                subject: .savedMappingProfile,
                sourceArtifactSHA256: source.profileSHA256,
                reason: .schemaBindingMismatch
            )
        }
        return .mappingProfile(try ImportMappingProfileV1(
            profileID: source.profileID,
            workspaceID: targetWorkspaceID,
            profileName: source.profileName,
            schemaRelease: targetSchemaRelease,
            mappings: source.mappings
        ))
    }

    static func rebind(
        session source: BulkSessionV1,
        to targetWorkspaceID: WorkspaceID,
        bulkPlan targetBulkPlan: BulkCommandPlanV1,
        sourceSHA256 targetSourceSHA256: String,
        expectedWorkspaceRevisionSHA256 targetWorkspaceRevisionSHA256: String
    ) throws -> ImportBulkWorkspaceRebindOutcomeV1 {
        try source.validate()
        try targetBulkPlan.validate()
        try ImportBulkCanonicalCodecV1.requireID(targetWorkspaceID.rawValue)
        try ImportBulkCanonicalCodecV1.requireDigest(targetSourceSHA256)
        try ImportBulkCanonicalCodecV1.requireDigest(targetWorkspaceRevisionSHA256)
        guard source.workspaceID != targetWorkspaceID else {
            return try rejected(
                targetWorkspaceID: targetWorkspaceID,
                subject: .bulkSession,
                sourceArtifactSHA256: source.sessionSHA256,
                reason: .targetEqualsSource
            )
        }
        guard targetBulkPlan.workspaceID == targetWorkspaceID else {
            return try rejected(
                targetWorkspaceID: targetWorkspaceID,
                subject: .bulkSession,
                sourceArtifactSHA256: source.sessionSHA256,
                reason: .targetPlanWorkspaceMismatch
            )
        }
        guard source.sourceSHA256 == targetSourceSHA256 else {
            return try rejected(
                targetWorkspaceID: targetWorkspaceID,
                subject: .bulkSession,
                sourceArtifactSHA256: source.sessionSHA256,
                reason: .sourceDigestMismatch
            )
        }
        guard source.state == .active else {
            return try rejected(
                targetWorkspaceID: targetWorkspaceID,
                subject: .bulkSession,
                sourceArtifactSHA256: source.sessionSHA256,
                reason: .activeSessionRequired
            )
        }
        guard source.chunkReceipts.isEmpty else {
            return try rejected(
                targetWorkspaceID: targetWorkspaceID,
                subject: .bulkSession,
                sourceArtifactSHA256: source.sessionSHA256,
                reason: .committedSessionCannotBeReplayed
            )
        }
        return .bulkSession(try BulkSessionV1(
            sessionID: source.sessionID,
            workspaceID: targetWorkspaceID,
            bulkPlan: targetBulkPlan,
            sourceSHA256: targetSourceSHA256,
            expectedWorkspaceRevisionSHA256: targetWorkspaceRevisionSHA256,
            state: .active,
            chunkReceipts: []
        ))
    }

    static func rebind(
        receipt source: BulkCommitReceiptV1,
        to targetWorkspaceID: WorkspaceID
    ) throws -> ImportBulkWorkspaceRebindOutcomeV1 {
        try source.validate()
        try ImportBulkCanonicalCodecV1.requireID(targetWorkspaceID.rawValue)
        return try rejected(
            targetWorkspaceID: targetWorkspaceID,
            subject: .bulkCommitReceipt,
            sourceArtifactSHA256: source.receiptSHA256,
            reason: .immutableAuditReceiptCannotBeRebound
        )
    }

    private static func rejected(
        targetWorkspaceID: WorkspaceID,
        subject: ImportBulkWorkspaceRebindSubjectV1,
        sourceArtifactSHA256: String,
        reason: ImportBulkWorkspaceRebindRejectionReasonV1
    ) throws -> ImportBulkWorkspaceRebindOutcomeV1 {
        .rejected(try ImportBulkWorkspaceRebindRejectionV1(
            targetWorkspaceID: targetWorkspaceID,
            subject: subject,
            sourceArtifactSHA256: sourceArtifactSHA256,
            reason: reason
        ))
    }
}

private extension Array where Element == String {
    func binarySearchContains(_ value: String) -> Bool {
        var lower = startIndex
        var upper = endIndex
        while lower < upper {
            let middle = index(lower, offsetBy: distance(from: lower, to: upper) / 2)
            if self[middle] == value { return true }
            if self[middle] < value { lower = index(after: middle) } else { upper = middle }
        }
        return false
    }
}

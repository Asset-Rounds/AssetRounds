import Foundation
import SwiftData

enum SearchPersistenceReleaseV1: Int, Codable, CaseIterable, Sendable {
    case v7 = 7
    static let predecessorSchemaVersion = 6
    static let canonicalSemanticLabel = "SMART_VIEW_DESCRIPTOR_V1"
    static let derivedProjectionFormatVersion = 1
}

/// C38 keeps accountability rows in the same disposable derived index as the
/// legacy search projection.  This policy is descriptive only: it does not
/// promote search rows into canonical persistence or bump the V7 smart-view
/// schema.
enum SearchAccountabilityPersistencePolicyV1 {
    static let semanticLabel = "ACCOUNTABILITY_SEARCH_PROJECTION_V1"
    static let sourceKind = "PARTY"
    static let fieldIDs = [
        "party_identifier",
        "party_label",
        "party_role",
        "status",
    ]
    static let excludesContactPoints = true
    static let excludesIdentityAndLegalClaims = true

    static func accepts(fieldID: String) -> Bool {
        fieldIDs.contains(fieldID)
    }
}

/// C39's privacy-safe semantic search projection. It stores stable semantic
/// labels and recorded lifecycle/product states, never raw product identifier
/// values or operational/safety/recall claims.
enum SearchAssetSemanticsPersistencePolicyV1 {
    static let semanticLabel = "ASSET_SEMANTICS_SEARCH_PROJECTION_V1"
    static let sourceKind = "ASSET"
    static let fieldIDs = [
        "asset_semantic_kind",
        "asset_semantic_capability",
        "asset_lifecycle_event",
        "asset_product_identity_state",
        "work_subject_scope",
    ]
    static let excludesProductIdentifierValues = true
    static let excludesOperationalDisposition = true
    static let excludesSafetyAndRecallClaims = true

    static func accepts(fieldID: String) -> Bool {
        fieldIDs.contains(fieldID)
    }
}

enum SearchAuthorityCriterionPersistencePolicyV1 {
    static let semanticLabel = "AUTHORITY_CRITERION_SEARCH_PROJECTION_V1"
    static let sourceKind = "WORK"
    static let fieldIDs = [
        "authority_source", "applicability_disposition", "criterion_result",
        "severity_level", "measurement_protocol",
    ]
    static let excludesLicensedSourceBytes = true
    static let excludesRawLocators = true
    static let excludesLegalSafetyComplianceClaims = true

    static func accepts(fieldID: String) -> Bool { fieldIDs.contains(fieldID) }
}

enum SearchPersistenceCodecV1 {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    static func decodeCanonical<T: Codable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let value = try decoder.decode(type, from: data)
        guard try encode(value) == data else { throw SearchContractFailureV1.invalidSmartView }
        return value
    }
}

/// Schema-V7 canonical persistence for a workspace-owned smart-view descriptor.
/// Search projection rows are intentionally not SwiftData models: they live in
/// the separately versioned, droppable index store and never become truth here.
@Model
final class SavedSmartView {
    @Attribute(.unique) private(set) var id: UUID
    @Attribute(.unique) private(set) var workspaceStableKey: String
    private(set) var schemaVersion: Int
    private(set) var workspaceID: UUID
    private(set) var stableID: String
    private(set) var origin: String
    private(set) var builtInKind: String?
    private(set) var name: String
    private(set) var query: String
    private(set) var scope: String
    private(set) var filtersData: Data
    private(set) var sort: String
    private(set) var revision: Int64
    private(set) var mutationID: UUID
    private(set) var createdAt: Date
    private(set) var updatedAt: Date
    private(set) var canonicalData: Data

    init(_ descriptor: SavedSmartViewDescriptorV1) throws {
        try descriptor.validate()
        guard descriptor.revision <= UInt64(Int64.max) else {
            throw SearchContractFailureV1.invalidRevision
        }
        let encoded = try SearchPersistenceCodecV1.encode(descriptor)
        let canonical = try SearchPersistenceCodecV1.decodeCanonical(
            SavedSmartViewDescriptorV1.self,
            from: encoded
        )
        id = canonical.id
        workspaceStableKey = Self.key(workspaceID: canonical.workspaceID, stableID: canonical.stableID)
        schemaVersion = canonical.schemaVersion
        workspaceID = canonical.workspaceID
        stableID = canonical.stableID
        origin = canonical.origin.rawValue
        builtInKind = canonical.builtInKind?.rawValue
        name = canonical.name
        query = canonical.query
        scope = canonical.scope.rawValue
        filtersData = try SearchPersistenceCodecV1.encode(canonical.filters)
        sort = canonical.sort.rawValue
        revision = Int64(canonical.revision)
        mutationID = canonical.mutationID
        createdAt = canonical.createdAt
        updatedAt = canonical.updatedAt
        canonicalData = encoded
    }

    func descriptor() throws -> SavedSmartViewDescriptorV1 {
        guard schemaVersion == SavedSmartViewDescriptorV1.schemaVersion, revision > 0 else {
            throw SearchContractFailureV1.unsupportedSchemaVersion
        }
        let value = try SearchPersistenceCodecV1.decodeCanonical(
            SavedSmartViewDescriptorV1.self,
            from: canonicalData
        )
        try value.validate()
        guard value.id == id,
              value.workspaceID == workspaceID,
              value.stableID == stableID,
              workspaceStableKey == Self.key(workspaceID: value.workspaceID, stableID: value.stableID),
              value.origin.rawValue == origin,
              value.builtInKind?.rawValue == builtInKind,
              value.name == name,
              value.query == query,
              value.scope.rawValue == scope,
              try SearchPersistenceCodecV1.encode(value.filters) == filtersData,
              value.sort.rawValue == sort,
              value.revision == UInt64(revision),
              value.mutationID == mutationID,
              value.createdAt == createdAt,
              value.updatedAt == updatedAt else {
            throw SearchContractFailureV1.invalidSmartView
        }
        return value
    }

    static func key(workspaceID: UUID, stableID: String) -> String {
        workspaceID.uuidString.lowercased() + ":" + stableID
    }
}

typealias SavedSmartViewRowV1 = SavedSmartView

enum SavedSmartViewLifecycleDispositionV1: String, CaseIterable, Codable, Sendable {
    case migrateCanonical = "MIGRATE_CANONICAL"
    case includeCanonicalBackup = "INCLUDE_CANONICAL_BACKUP"
    case replaceRestoreCanonical = "REPLACE_RESTORE_CANONICAL"
    case remapWorkspaceOnCloneOrFork = "REMAP_WORKSPACE_ON_CLONE_OR_FORK"
    case includeCanonicalExport = "INCLUDE_CANONICAL_EXPORT"
    case journalAndReplayCanonical = "JOURNAL_AND_REPLAY_CANONICAL"
    case deleteWithWorkspace = "DELETE_WITH_WORKSPACE"
    case erase = "ERASE"
    case forwardFixReadCompatible = "FORWARD_FIX_READ_COMPATIBLE"
}

enum SearchIndexLifecycleDispositionV1: String, CaseIterable, Codable, Sendable {
    case excludedFromMigration = "EXCLUDED_FROM_MIGRATION"
    case excludedFromBackup = "EXCLUDED_FROM_BACKUP"
    case excludedFromExport = "EXCLUDED_FROM_EXPORT"
    case purgeOnDelete = "PURGE_ON_DELETE"
    case purgeOnErase = "PURGE_ON_ERASE"
    case dropAndRebuildAfterRestore = "DROP_AND_REBUILD_AFTER_RESTORE"
    case dropAndRebuildOnDowngrade = "DROP_AND_REBUILD_ON_DOWNGRADE"
}

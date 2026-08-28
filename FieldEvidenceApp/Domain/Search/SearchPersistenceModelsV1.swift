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

/// C41 keeps functional-relationship search disposable and bounded to the
/// current descriptor/event-derived view. It never indexes historical graph
/// bytes, actor/provenance details, locators, ownership, authorization,
/// compliance, safety, telemetry, or remote claims.
enum SearchFunctionalRelationshipsPersistencePolicyV1 {
    static let semanticLabel = "FUNCTIONAL_RELATIONSHIPS_SEARCH_PROJECTION_V1"
    static let sourceKind = "ASSET"
    static let fieldIDs = [
        "functional_relationship_descriptor",
        "functional_relationship_direction",
        "functional_relationship_state",
        "functional_relationship_endpoint",
    ]
    static let indexesCurrentHeadsOnly = true
    static let excludesHistoricalEvents = true
    static let excludesGraphTruth = true
    static let excludesOwnershipAuthorizationComplianceClaims = true
    static let excludesTelemetryAndRemoteClaims = true

    static func accepts(fieldID: String) -> Bool { fieldIDs.contains(fieldID) }
}

/// C13 search is an audience-safe status projection only. It may answer
/// whether a report has included/omitted evidence and which typed limitation
/// applies, but it never indexes claim text, evidence identifiers/digests,
/// media/content, or actor/private detail.
enum SearchEvidenceAssurancePersistencePolicyV1 {
    static let semanticLabel = "EVIDENCE_ASSURANCE_SEARCH_PROJECTION_V1"
    static let sourceKind = "REPORT"
    static let fieldIDs = [
        "assurance_audience",
        "assurance_disposition",
        "assurance_limitation",
        "assurance_projection_version",
    ]
    static let indexesCurrentManifestHeadsOnly = true
    static let excludesClaimAndEvidenceContent = true
    static let excludesEvidenceIdentifiersAndDigests = true
    static let excludesActorPrivateDetail = true
    static let excludesInternalEvidence = true
    static let acceptedProjectionVersionMarkers = [
        "C13_EVIDENCE_ASSURANCE_V1",
        "report-evidence-assurance-v1",
    ]

    static func accepts(fieldID: String) -> Bool { fieldIDs.contains(fieldID) }

    static func acceptsMetadata(fieldID: String, tokens: [String], snippet: String?) -> Bool {
        guard accepts(fieldID: fieldID), !tokens.isEmpty else { return false }
        let allowed: Set<String>
        switch fieldID {
        case "assurance_audience":
            allowed = Set(EvidenceAudienceV1.allCases.map { $0.rawValue.lowercased() })
        case "assurance_disposition":
            allowed = Set(EvidenceInclusionDispositionV1.allCases.map { $0.rawValue.lowercased() })
        case "assurance_limitation":
            allowed = Set(EvidenceLimitationV1.allCases.map { $0.rawValue.lowercased() })
        case "assurance_projection_version":
            guard tokens.allSatisfy(SearchContractValidationV1.isCanonicalSearchToken),
                  tokens.count <= 8,
                  let snippet,
                  SearchContractValidationV1.validDisplayText(
                      snippet, maximumBytes: SearchContractLimitsV1.maximumSnippetBytes
                  ) else { return false }
            let candidateTokens = normalizedMetadataTokens(snippet)
            guard candidateTokens == tokens else { return false }
            let candidateMarker = candidateTokens.joined(separator: " ")
            return acceptedProjectionVersionMarkers.contains {
                normalizedMetadataTokens($0).joined(separator: " ") == candidateMarker
            }
        default:
            return false
        }
        let allowedTokens = Set(allowed.flatMap {
            SearchContractValidationV1.normalizeSearchText($0)
                .split { !CharacterSet.alphanumerics.contains($0) }
                .map(String.init)
        })
        guard Set(tokens).isSubset(of: allowedTokens),
              Set(tokens).count == tokens.count else { return false }
        return snippet == nil || SearchContractValidationV1.validDisplayText(
            snippet!, maximumBytes: SearchContractLimitsV1.maximumSnippetBytes
        )
    }

    private static func normalizedMetadataTokens(_ value: String) -> [String] {
        SearchContractValidationV1.normalizeSearchText(value)
            .unicodeScalars
            .split { !CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
    }
}

/// C14 search admits only bounded typed review/change/action state metadata.
/// The exact histories, reasons, actors, and evidence references remain in the
/// completed snapshot and are rebuilt from the canonical source when needed.
enum SearchInspectionReviewPersistencePolicyV1 {
    static let semanticLabel = "INSPECTION_REVIEW_HISTORY_SEARCH_PROJECTION_V1"
    static let sourceKind = "REPORT"
    static let fieldIDs = [
        "inspection_review_state",
        "inspection_review_disposition",
        "change_request_state",
        "corrective_action_state",
        "inspection_review_projection_version",
    ]
    static let indexesCurrentHeadsOnly = true
    static let excludesReviewReasons = true
    static let excludesActorPrivateDetail = true
    static let excludesEvidenceContentAndIdentifiers = true
    static let excludesOwnershipAuthorizationAndClaims = true
    static let acceptedProjectionVersionMarkers = [
        "C14_INSPECTION_REVIEW_V1",
        "report-inspection-review-history-v1",
    ]

    static func accepts(fieldID: String) -> Bool { fieldIDs.contains(fieldID) }

    static func acceptsMetadata(
        fieldID: String,
        tokens: [String],
        snippet: String?
    ) -> Bool {
        guard accepts(fieldID: fieldID), !tokens.isEmpty,
              tokens.allSatisfy(SearchContractValidationV1.isCanonicalSearchToken),
              tokens.count <= 8,
              let snippet,
              SearchContractValidationV1.validDisplayText(
                  snippet,
                  maximumBytes: SearchContractLimitsV1.maximumSnippetBytes
              ),
              normalizedMetadataTokens(snippet) == tokens else {
            return false
        }
        let allowed: Set<String>
        switch fieldID {
        case "inspection_review_state":
            allowed = Set(InspectionReviewStateV1.allCases.map { $0.rawValue.lowercased() })
        case "inspection_review_disposition":
            allowed = Set(ReviewDispositionKindV1.allCases.map { $0.rawValue.lowercased() })
        case "change_request_state":
            allowed = Set(ChangeRequestStateV1.allCases.map { $0.rawValue.lowercased() })
        case "corrective_action_state":
            allowed = Set(CorrectiveActionStateV1.allCases.map { $0.rawValue.lowercased() })
        case "inspection_review_projection_version":
            return acceptedProjectionVersionMarkers.contains {
                normalizedMetadataTokens($0) == tokens
            }
        default:
            return false
        }
        let allowedTokens = Set(allowed.flatMap {
            SearchContractValidationV1.normalizeSearchText($0)
                .split { !CharacterSet.alphanumerics.contains($0) }
                .map(String.init)
        })
        return Set(tokens).isSubset(of: allowedTokens)
            && Set(tokens).count == tokens.count
    }

    private static func normalizedMetadataTokens(_ value: String) -> [String] {
        SearchContractValidationV1.normalizeSearchText(value)
            .unicodeScalars
            .split { !CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
    }
}

typealias SearchReviewHistoryPersistencePolicyV1 = SearchInspectionReviewPersistencePolicyV1

typealias SearchFunctionalRelationshipPersistencePolicyV1 =
    SearchFunctionalRelationshipsPersistencePolicyV1

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

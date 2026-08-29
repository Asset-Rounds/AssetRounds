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

/// C15 search is a disposable current-head projection of packet coordination.
/// Only stable packet identity, typed manifest/item/conflict state, and the
/// projection marker are admitted; actor, lease, result, evidence, and review
/// exception details remain canonical-only.
enum SearchWorkPacketPersistencePolicyV1 {
    static let semanticLabel = "WORK_PACKET_COORDINATION_SEARCH_PROJECTION_V1"
    static let sourceKind = "WORK"
    static let fieldIDs = [
        "work_packet_identifier",
        "work_packet_manifest_state",
        "work_packet_item_state",
        "work_packet_conflict_state",
        "work_packet_projection_version",
    ]
    static let indexesCurrentHeadsOnly = true
    static let excludesActorPrivateDetail = true
    static let excludesClaimLeaseData = true
    static let excludesResultAndEvidenceLinks = true
    static let excludesAuthorizationAndTelemetry = true
    static let acceptedProjectionVersionMarkers = [
        "C15_WORK_PACKET_V1",
        "report-work-packet-v1",
    ]

    static func accepts(fieldID: String) -> Bool { fieldIDs.contains(fieldID) }

    static func acceptsMetadata(
        fieldID: String,
        tokens: [String],
        snippet: String?
    ) -> Bool {
        guard accepts(fieldID: fieldID), !tokens.isEmpty,
              tokens.allSatisfy(SearchContractValidationV1.isCanonicalSearchToken),
              tokens.count <= 16,
              let snippet,
              SearchContractValidationV1.validDisplayText(
                  snippet,
                  maximumBytes: SearchContractLimitsV1.maximumSnippetBytes
              ),
              normalizedMetadataTokens(snippet) == tokens else {
            return false
        }
        if fieldID == "work_packet_projection_version" {
            return acceptedProjectionVersionMarkers.contains {
                normalizedMetadataTokens($0) == tokens
            }
        }
        if fieldID == "work_packet_identifier" {
            return true
        }
        let allowed: Set<String>
        switch fieldID {
        case "work_packet_manifest_state":
            allowed = ["ready", "conflicted", "replayed", "superseded"]
        case "work_packet_item_state":
            allowed = Set(CompletedWorkPacketItemStateV1.allCases.map {
                $0.rawValue.lowercased()
            })
        case "work_packet_conflict_state":
            allowed = ["none", "review_required"]
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

/// Package-evolution search rows are disposable projections of the canonical
/// V17 lifecycle. They are never migrated, backed up, exported, or replayed as
/// canonical data; restore and replay rebuild them from the active source.
struct PackageEvolutionSearchPersistencePolicyV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let sourceSchema: String
    let searchPersistenceRelease: SearchPersistenceReleaseV1
    let fieldIDs: [String]
    let lifecycleDispositions: [SearchIndexLifecycleDispositionV1]
    let metadataOnly: Bool
    let excludesCanonicalPackageBytes: Bool
    let excludesDraftPayload: Bool
    let excludesActorIdentity: Bool

    init() {
        schemaVersion = Self.schemaVersion
        sourceSchema = PackageEvolutionLifecycleV1.schema
        searchPersistenceRelease = .v7
        fieldIDs = PackageEvolutionSearchProjectionPolicyV1.fieldIDs.sorted()
        lifecycleDispositions = [
            .excludedFromMigration,
            .excludedFromBackup,
            .excludedFromExport,
            .purgeOnDelete,
            .purgeOnErase,
            .dropAndRebuildAfterRestore,
            .dropAndRebuildOnDowngrade,
        ]
        metadataOnly = true
        excludesCanonicalPackageBytes = true
        excludesDraftPayload = true
        excludesActorIdentity = true
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              sourceSchema == PackageEvolutionLifecycleV1.schema,
              searchPersistenceRelease == .v7,
              fieldIDs == PackageEvolutionSearchProjectionPolicyV1.fieldIDs.sorted(),
              lifecycleDispositions == SearchIndexLifecycleDispositionV1.allCases,
              metadataOnly,
              excludesCanonicalPackageBytes,
              excludesDraftPayload,
              excludesActorIdentity else {
            throw PackageEvolutionConsumerFailureV1.invalidMetadata
        }
    }
}

extension SearchPersistenceReleaseV1 {
    static let packageEvolutionPolicy = PackageEvolutionSearchPersistencePolicyV1()
}

/// C19 measurement rows are disposable derived metadata. The V7 search
/// schema remains unchanged; restore, replay, delete, and Erase drop these
/// rows and rebuild them from canonical measurement snapshots.
struct MeasurementIntegritySearchPersistencePolicyV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let sourceSchema: String
    let searchPersistenceRelease: SearchPersistenceReleaseV1
    let fieldIDs: [String]
    let lifecycleDispositions: [SearchIndexLifecycleDispositionV1]
    let metadataOnly: Bool
    let excludesExactCanonicalValues: Bool
    let excludesOpaqueSerials: Bool
    let excludesOperatorIdentity: Bool
    let excludesResponsePayload: Bool
    let excludesEvidenceLocators: Bool

    init() {
        schemaVersion = Self.schemaVersion
        sourceSchema = MeasurementIntegritySearchProjectionPolicyV1.semanticLabel
        searchPersistenceRelease = .v7
        fieldIDs = MeasurementIntegritySearchProjectionPolicyV1.fieldIDs.sorted()
        lifecycleDispositions = SearchIndexLifecycleDispositionV1.allCases
        metadataOnly = true
        excludesExactCanonicalValues = true
        excludesOpaqueSerials = true
        excludesOperatorIdentity = true
        excludesResponsePayload = true
        excludesEvidenceLocators = true
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              sourceSchema == MeasurementIntegritySearchProjectionPolicyV1.semanticLabel,
              searchPersistenceRelease == .v7,
              fieldIDs == MeasurementIntegritySearchProjectionPolicyV1.fieldIDs.sorted(),
              lifecycleDispositions == SearchIndexLifecycleDispositionV1.allCases,
              metadataOnly, excludesExactCanonicalValues, excludesOpaqueSerials,
              excludesOperatorIdentity, excludesResponsePayload,
              excludesEvidenceLocators else {
            throw SearchContractFailureV1.invalidField
        }
    }
}

extension SearchPersistenceReleaseV1 {
    static let measurementIntegrityPolicy = MeasurementIntegritySearchPersistencePolicyV1()
}

/// C20 search rows are disposable, metadata-only projections of approved
/// derivatives. They are never migrated, backed up, exported, or replayed as
/// canonical privacy-transform content.
struct PrivacyTransformSearchPersistencePolicyV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let sourceSchema: String
    let searchPersistenceRelease: SearchPersistenceReleaseV1
    let fieldIDs: [String]
    let lifecycleDispositions: [SearchIndexLifecycleDispositionV1]
    let metadataOnly: Bool
    let approvedNonStaleOnly: Bool
    let requiresMatchingSourceAndDerivativeDigest: Bool
    let requiresExplicitRedactionDeclaration: Bool
    let excludesOriginalReferences: Bool
    let excludesOriginalBytes: Bool
    let excludesDerivativeBytes: Bool
    let excludesReviewerIdentity: Bool
    let excludesReviewRationale: Bool

    init() {
        schemaVersion = Self.schemaVersion
        sourceSchema = PrivacyTransformSearchProjectionPolicyV1.semanticLabel
        searchPersistenceRelease = .v7
        fieldIDs = PrivacyTransformSearchProjectionPolicyV1.fieldIDs.sorted()
        lifecycleDispositions = SearchIndexLifecycleDispositionV1.allCases
        metadataOnly = true
        approvedNonStaleOnly = true
        requiresMatchingSourceAndDerivativeDigest = true
        requiresExplicitRedactionDeclaration = true
        excludesOriginalReferences = true
        excludesOriginalBytes = true
        excludesDerivativeBytes = true
        excludesReviewerIdentity = true
        excludesReviewRationale = true
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              sourceSchema == PrivacyTransformSearchProjectionPolicyV1.semanticLabel,
              searchPersistenceRelease == .v7,
              fieldIDs == PrivacyTransformSearchProjectionPolicyV1.fieldIDs.sorted(),
              lifecycleDispositions == SearchIndexLifecycleDispositionV1.allCases,
              metadataOnly,
              approvedNonStaleOnly,
              requiresMatchingSourceAndDerivativeDigest,
              requiresExplicitRedactionDeclaration,
              excludesOriginalReferences,
              excludesOriginalBytes,
              excludesDerivativeBytes,
              excludesReviewerIdentity,
              excludesReviewRationale else {
            throw SearchContractFailureV1.invalidField
        }
    }
}

extension SearchPersistenceReleaseV1 {
    static let privacyTransformPolicy = PrivacyTransformSearchPersistencePolicyV1()
}

/// C21 search rows remain disposable metadata projections. They are rebuilt
/// from canonical admission decisions after restore/replay and never become
/// backup, export, or package-lifecycle source records.
struct ClientCapabilitySearchPersistencePolicyV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let sourceSchema: String
    let searchPersistenceRelease: SearchPersistenceReleaseV1
    let fieldIDs: [String]
    let lifecycleDispositions: [SearchIndexLifecycleDispositionV1]
    let metadataOnly: Bool
    let closedValuesOnly: Bool
    let dropAndRebuildAfterRestore: Bool
    let dropAndRebuildOnReplay: Bool
    let excludesDeviceIdentity: Bool
    let excludesUserIdentity: Bool
    let excludesEndpointProviderAccount: Bool
    let excludesRemoteDeliveryAcknowledgement: Bool
    let excludesPackagePayload: Bool

    init() {
        schemaVersion = Self.schemaVersion
        sourceSchema = ClientCapabilitySearchProjectionPolicyV1.semanticLabel
        searchPersistenceRelease = .v7
        fieldIDs = ClientCapabilitySearchProjectionPolicyV1.fieldIDs.sorted()
        lifecycleDispositions = SearchIndexLifecycleDispositionV1.allCases
        metadataOnly = true
        closedValuesOnly = true
        dropAndRebuildAfterRestore = true
        dropAndRebuildOnReplay = true
        excludesDeviceIdentity = true
        excludesUserIdentity = true
        excludesEndpointProviderAccount = true
        excludesRemoteDeliveryAcknowledgement = true
        excludesPackagePayload = true
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              sourceSchema == ClientCapabilitySearchProjectionPolicyV1.semanticLabel,
              searchPersistenceRelease == .v7,
              fieldIDs == ClientCapabilitySearchProjectionPolicyV1.fieldIDs.sorted(),
              lifecycleDispositions == SearchIndexLifecycleDispositionV1.allCases,
              metadataOnly,
              closedValuesOnly,
              dropAndRebuildAfterRestore,
              dropAndRebuildOnReplay,
              excludesDeviceIdentity,
              excludesUserIdentity,
              excludesEndpointProviderAccount,
              excludesRemoteDeliveryAcknowledgement,
              excludesPackagePayload else {
            throw SearchContractFailureV1.invalidField
        }
    }
}

extension SearchPersistenceReleaseV1 {
    static let clientCapabilityPolicy = ClientCapabilitySearchPersistencePolicyV1()
}

// MARK: - C23 version-bound field-reference search persistence

/// C23 rows are disposable derived metadata. They are rebuilt from the
/// canonical release/binding projection after restore or replay and have no
/// persistence authority over reference bytes or locators.
struct FieldReferenceSearchPersistencePolicyV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let sourceSchema: String
    let searchPersistenceRelease: SearchPersistenceReleaseV1
    let fieldIDs: [String]
    let metadataOnly: Bool
    let derivedOnly: Bool
    let dropAndRebuildAfterRestore: Bool
    let dropAndRebuildOnReplay: Bool
    let excludesReferenceBytes: Bool
    let excludesContentIDs: Bool
    let excludesPrivateLocators: Bool
    let excludesLicenseSecrets: Bool
    let excludesSubjectIdentity: Bool

    init() {
        schemaVersion = Self.schemaVersion
        sourceSchema = FieldReferenceSearchProjectionPolicyV1.semanticLabel
        searchPersistenceRelease = .v7
        fieldIDs = FieldReferenceSearchProjectionPolicyV1.fieldIDs.sorted()
        metadataOnly = true
        derivedOnly = true
        dropAndRebuildAfterRestore = true
        dropAndRebuildOnReplay = true
        excludesReferenceBytes = true
        excludesContentIDs = true
        excludesPrivateLocators = true
        excludesLicenseSecrets = true
        excludesSubjectIdentity = true
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              sourceSchema == FieldReferenceSearchProjectionPolicyV1.semanticLabel,
              searchPersistenceRelease == .v7,
              fieldIDs == FieldReferenceSearchProjectionPolicyV1.fieldIDs.sorted(),
              metadataOnly,
              derivedOnly,
              dropAndRebuildAfterRestore,
              dropAndRebuildOnReplay,
              excludesReferenceBytes,
              excludesContentIDs,
              excludesPrivateLocators,
              excludesLicenseSecrets,
              excludesSubjectIdentity else {
            throw SearchContractFailureV1.invalidField
        }
    }
}

extension SearchPersistenceReleaseV1 {
    static let fieldReferencePolicy = FieldReferenceSearchPersistencePolicyV1()
}

// MARK: - C24 accessible-document search persistence

/// C24 search rows are disposable summaries rebuilt from the canonical
/// audience-safe semantic tree.  No semantic tree, node text, evidence link,
/// original byte, locator, or assessor identity is a persistence input.
struct AccessibleDocumentSearchPersistencePolicyV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let sourceSchema: String
    let searchPersistenceRelease: SearchPersistenceReleaseV1
    let fieldIDs: [String]
    let metadataOnly: Bool
    let derivedOnly: Bool
    let customerSafeOnly: Bool
    let excludesSemanticTree: Bool
    let excludesNodeText: Bool
    let excludesOriginalEvidence: Bool
    let excludesEvidenceLinks: Bool
    let excludesAssessorIdentity: Bool
    let excludesPrivateLocators: Bool
    let excludesUnsupportedClaims: Bool
    let dropAndRebuildAfterRestore: Bool
    let dropAndRebuildOnReplay: Bool

    init() {
        schemaVersion = Self.schemaVersion
        sourceSchema = AccessibleDocumentSearchProjectionPolicyV1.semanticLabel
        searchPersistenceRelease = .v7
        fieldIDs = AccessibleDocumentSearchProjectionPolicyV1.fieldIDs.sorted()
        metadataOnly = true
        derivedOnly = true
        customerSafeOnly = true
        excludesSemanticTree = true
        excludesNodeText = true
        excludesOriginalEvidence = true
        excludesEvidenceLinks = true
        excludesAssessorIdentity = true
        excludesPrivateLocators = true
        excludesUnsupportedClaims = true
        dropAndRebuildAfterRestore = true
        dropAndRebuildOnReplay = true
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              sourceSchema == AccessibleDocumentSearchProjectionPolicyV1.semanticLabel,
              searchPersistenceRelease == .v7,
              fieldIDs == AccessibleDocumentSearchProjectionPolicyV1.fieldIDs.sorted(),
              metadataOnly,
              derivedOnly,
              customerSafeOnly,
              excludesSemanticTree,
              excludesNodeText,
              excludesOriginalEvidence,
              excludesEvidenceLinks,
              excludesAssessorIdentity,
              excludesPrivateLocators,
              excludesUnsupportedClaims,
              dropAndRebuildAfterRestore,
              dropAndRebuildOnReplay else {
            throw SearchContractFailureV1.invalidField
        }
    }
}

extension SearchPersistenceReleaseV1 {
    static let accessibleDocumentPolicy = AccessibleDocumentSearchPersistencePolicyV1()
}

// MARK: - C25 survey-definition search persistence boundary

struct SurveyDefinitionSearchPersistencePolicyV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let sourceSchema: String
    let searchPersistenceRelease: SearchPersistenceReleaseV1
    let fieldIDs: [String]
    let metadataOnly: Bool
    let derivedOnly: Bool
    let excludesAnswers: Bool
    let excludesPromptText: Bool
    let excludesActorIdentity: Bool
    let excludesPrivateLocators: Bool
    let excludesEvidenceBytes: Bool
    let backupDisposition: String
    let replayDisposition: String

    init() {
        schemaVersion = Self.schemaVersion
        sourceSchema = SurveyDefinitionSearchProjectionPolicyV1.semanticLabel
        searchPersistenceRelease = .v7
        fieldIDs = SurveyDefinitionSearchProjectionPolicyV1.fieldIDs
        metadataOnly = true
        derivedOnly = true
        excludesAnswers = true
        excludesPromptText = true
        excludesActorIdentity = true
        excludesPrivateLocators = true
        excludesEvidenceBytes = true
        backupDisposition = "EXCLUDED_DERIVED_REBUILD"
        replayDisposition = "DROP_AND_REBUILD_FROM_CANONICAL_RELEASES"
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              sourceSchema == SurveyDefinitionSearchProjectionPolicyV1.semanticLabel,
              searchPersistenceRelease == .v7,
              fieldIDs == SurveyDefinitionSearchProjectionPolicyV1.fieldIDs,
              metadataOnly, derivedOnly,
              excludesAnswers, excludesPromptText, excludesActorIdentity,
              excludesPrivateLocators, excludesEvidenceBytes,
              backupDisposition == "EXCLUDED_DERIVED_REBUILD",
              replayDisposition == "DROP_AND_REBUILD_FROM_CANONICAL_RELEASES" else {
            throw SurveyDefinitionConsumerFailureV1.invalidValue
        }
    }
}

extension SearchPersistenceReleaseV1 {
    static let surveyDefinitionPolicy = SurveyDefinitionSearchPersistencePolicyV1()
}

// MARK: - C26 guided-survey session search persistence boundary

/// Session search rows are disposable, metadata-only derivatives.  Device
/// favorites/recents and canonical fact values remain outside this store and
/// are rebuilt or omitted at restore/replay boundaries.
struct SurveySessionSearchPersistencePolicyV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let sourceSchema: String
    let searchPersistenceRelease: SearchPersistenceReleaseV1
    let fieldIDs: [String]
    let metadataOnly: Bool
    let derivedOnly: Bool
    let excludesFactValues: Bool
    let excludesPromptText: Bool
    let excludesProvisionalSubjectLabels: Bool
    let excludesActorIdentity: Bool
    let excludesEvidenceReferences: Bool
    let excludesEvidenceBytes: Bool
    let excludesPrivateLocators: Bool
    let excludesCustomerAndWorkData: Bool
    let excludesUnsupportedClaims: Bool
    let backupDisposition: String
    let replayDisposition: String

    init() {
        schemaVersion = Self.schemaVersion
        sourceSchema = SurveySessionSearchProjectionPolicyV1.semanticLabel
        searchPersistenceRelease = .v7
        fieldIDs = SurveySessionSearchProjectionPolicyV1.fieldIDs
        metadataOnly = true
        derivedOnly = true
        excludesFactValues = true
        excludesPromptText = true
        excludesProvisionalSubjectLabels = true
        excludesActorIdentity = true
        excludesEvidenceReferences = true
        excludesEvidenceBytes = true
        excludesPrivateLocators = true
        excludesCustomerAndWorkData = true
        excludesUnsupportedClaims = true
        backupDisposition = "EXCLUDED_DERIVED_REBUILD"
        replayDisposition = "DROP_AND_REBUILD_FROM_CANONICAL_SURVEY_SESSIONS"
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              sourceSchema == SurveySessionSearchProjectionPolicyV1.semanticLabel,
              searchPersistenceRelease == .v7,
              fieldIDs == SurveySessionSearchProjectionPolicyV1.fieldIDs,
              metadataOnly, derivedOnly,
              excludesFactValues, excludesPromptText,
              excludesProvisionalSubjectLabels, excludesActorIdentity,
              excludesEvidenceReferences, excludesEvidenceBytes,
              excludesPrivateLocators, excludesCustomerAndWorkData,
              excludesUnsupportedClaims,
              backupDisposition == "EXCLUDED_DERIVED_REBUILD",
              replayDisposition == "DROP_AND_REBUILD_FROM_CANONICAL_SURVEY_SESSIONS" else {
            throw SearchContractFailureV1.invalidField
        }
    }
}

extension SearchPersistenceReleaseV1 {
    static let surveySessionPolicy = SurveySessionSearchPersistencePolicyV1()
}

// MARK: - C27 asset-locator search persistence boundary

/// Locator search rows are disposable metadata derivatives.  Restore and
/// replay discard them and rebuild from canonical locators/resolution history;
/// no opaque lookup input is included in the V7 search store.
struct AssetLocatorSearchPersistencePolicyV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let sourceSchema: String
    let searchPersistenceRelease: SearchPersistenceReleaseV1
    let fieldIDs: [String]
    let metadataOnly: Bool
    let derivedOnly: Bool
    let excludesOpaqueInput: Bool
    let excludesPrivateKeyMaterial: Bool
    let excludesSecrets: Bool
    let excludesVendorIdentifiers: Bool
    let excludesPrivateLocators: Bool
    let excludesActorIdentity: Bool
    let excludesUnsupportedClaims: Bool
    let backupDisposition: String
    let replayDisposition: String

    init() {
        schemaVersion = Self.schemaVersion
        sourceSchema = AssetLocatorSearchProjectionPolicyV1.semanticLabel
        searchPersistenceRelease = .v7
        fieldIDs = AssetLocatorSearchProjectionPolicyV1.fieldIDs
        metadataOnly = true
        derivedOnly = true
        excludesOpaqueInput = true
        excludesPrivateKeyMaterial = true
        excludesSecrets = true
        excludesVendorIdentifiers = true
        excludesPrivateLocators = true
        excludesActorIdentity = true
        excludesUnsupportedClaims = true
        backupDisposition = "EXCLUDED_DERIVED_REBUILD"
        replayDisposition = "DROP_AND_REBUILD_FROM_CANONICAL_ASSET_LOCATORS"
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              sourceSchema == AssetLocatorSearchProjectionPolicyV1.semanticLabel,
              searchPersistenceRelease == .v7,
              fieldIDs == AssetLocatorSearchProjectionPolicyV1.fieldIDs,
              metadataOnly, derivedOnly,
              excludesOpaqueInput, excludesPrivateKeyMaterial,
              excludesSecrets, excludesVendorIdentifiers,
              excludesPrivateLocators, excludesActorIdentity,
              excludesUnsupportedClaims,
              backupDisposition == "EXCLUDED_DERIVED_REBUILD",
              replayDisposition == "DROP_AND_REBUILD_FROM_CANONICAL_ASSET_LOCATORS" else {
            throw SearchContractFailureV1.invalidField
        }
    }
}

extension SearchPersistenceReleaseV1 {
    static let assetLocatorPolicy = AssetLocatorSearchPersistencePolicyV1()
}

// MARK: - C28 schedule occurrence search persistence boundary

/// Schedule search rows are disposable metadata derivatives. Canonical
/// release/history records are rebuilt first after restore, replay, or Erase;
/// notification requests and work-instance details never enter this store.
struct ScheduleOccurrenceSearchPersistencePolicyV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let sourceSchema: String
    let searchPersistenceRelease: SearchPersistenceReleaseV1
    let fieldIDs: [String]
    let metadataOnly: Bool
    let derivedOnly: Bool
    let notificationDeliveryIsTruth: Bool
    let excludesNotificationPayload: Bool
    let excludesWorkInstanceIdentity: Bool
    let excludesActorIdentity: Bool
    let excludesDraftValues: Bool
    let backupDisposition: String
    let replayDisposition: String
    let deleteDisposition: String

    init() {
        schemaVersion = Self.schemaVersion
        sourceSchema = ScheduleOccurrenceSearchProjectionPolicyV1.semanticLabel
        searchPersistenceRelease = .v7
        fieldIDs = ScheduleOccurrenceSearchProjectionPolicyV1.fieldIDs
        metadataOnly = true
        derivedOnly = true
        notificationDeliveryIsTruth = false
        excludesNotificationPayload = true
        excludesWorkInstanceIdentity = true
        excludesActorIdentity = true
        excludesDraftValues = true
        backupDisposition = "EXCLUDED_DERIVED_REBUILD"
        replayDisposition = "DROP_AND_REBUILD_FROM_CANONICAL_SCHEDULE_HISTORY"
        deleteDisposition = "DROP_AND_REBUILD_AFTER_SCHEDULE_ERASE"
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              sourceSchema == ScheduleOccurrenceSearchProjectionPolicyV1.semanticLabel,
              searchPersistenceRelease == .v7,
              fieldIDs == ScheduleOccurrenceSearchProjectionPolicyV1.fieldIDs,
              metadataOnly, derivedOnly,
              !notificationDeliveryIsTruth,
              excludesNotificationPayload, excludesWorkInstanceIdentity,
              excludesActorIdentity, excludesDraftValues,
              backupDisposition == "EXCLUDED_DERIVED_REBUILD",
              replayDisposition == "DROP_AND_REBUILD_FROM_CANONICAL_SCHEDULE_HISTORY",
              deleteDisposition == "DROP_AND_REBUILD_AFTER_SCHEDULE_ERASE" else {
            throw SearchContractFailureV1.invalidField
        }
    }
}

extension SearchPersistenceReleaseV1 {
    static let scheduleOccurrencePolicy = ScheduleOccurrenceSearchPersistencePolicyV1()
}

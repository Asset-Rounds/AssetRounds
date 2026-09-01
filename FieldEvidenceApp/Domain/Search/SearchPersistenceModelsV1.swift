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

// MARK: - C30 operating-context persistence boundary

enum C30OperatingContextSearchPersistencePolicyV1 {
    static let sourceSemanticLabel = "C30_OPERATING_CONTEXT_SEARCH_PROJECTION_V1"
    static let storageIsDisposableDerivedMetadata = true
    static let sourceOfTruth = "EvidenceContextV1"
    static let pairedSourceOfTruth = "PairedObservationLinkV1"
    static let indexesFrozenCurrentProjectionOnly = true
    static let excludesTemporalNotesCoordinatesAndImages = true
    static let excludesActorAndControlResultClaims = true
    static let backupDisposition = "EXCLUDED_DERIVED_REBUILD"
    static let replayDisposition = "DROP_AND_REBUILD_FROM_C30_CONTEXT"
    static let deleteDisposition = "DROP_AND_REBUILD_AFTER_C30_ERASE"

    static func validate() throws {
        guard storageIsDisposableDerivedMetadata,
              indexesFrozenCurrentProjectionOnly,
              excludesTemporalNotesCoordinatesAndImages,
              excludesActorAndControlResultClaims,
              sourceOfTruth == "EvidenceContextV1",
              pairedSourceOfTruth == "PairedObservationLinkV1" else {
            throw SearchContractFailureV1.forbiddenField
        }
    }
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

struct AdvancedScheduleOccurrenceSearchPersistencePolicyV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let sourceSchema: String
    let searchPersistenceRelease: SearchPersistenceReleaseV1
    let fieldIDs: [String]
    let backupDisposition: String
    let replayDisposition: String
    let excludesFreeText: Bool
    let excludesActorWorkAndNotificationPayload: Bool
    init() {
        schemaVersion = Self.schemaVersion
        sourceSchema = AdvancedScheduleOccurrenceSearchProjectionPolicyV1.semanticLabel
        searchPersistenceRelease = .v7
        fieldIDs = AdvancedScheduleOccurrenceSearchProjectionPolicyV1.fieldIDs
        backupDisposition = "EXCLUDED_DERIVED_REBUILD"
        replayDisposition = "DROP_AND_REBUILD_FROM_FROZEN_SCHEDULE_CALENDAR_OVERRIDE_LINEAGE"
        excludesFreeText = true
        excludesActorWorkAndNotificationPayload = true
    }
    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              sourceSchema == AdvancedScheduleOccurrenceSearchProjectionPolicyV1.semanticLabel,
              fieldIDs == AdvancedScheduleOccurrenceSearchProjectionPolicyV1.fieldIDs,
              searchPersistenceRelease == .v7, backupDisposition == "EXCLUDED_DERIVED_REBUILD",
              replayDisposition == "DROP_AND_REBUILD_FROM_FROZEN_SCHEDULE_CALENDAR_OVERRIDE_LINEAGE",
              excludesFreeText, excludesActorWorkAndNotificationPayload else {
            throw SearchContractFailureV1.invalidField
        }
    }
}

// MARK: - C29 plan placement search persistence boundary

/// Plan placement rows are disposable metadata derivatives. They are rebuilt
/// from frozen report projections after restore, replay, or erase; plan
/// source bytes, subject identifiers, private locators, and component input
/// payloads are never part of the V7 search store.
struct PlanPlacementSearchPersistencePolicyV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let sourceSchema: String
    let searchPersistenceRelease: SearchPersistenceReleaseV1
    let fieldIDs: [String]
    let metadataOnly: Bool
    let derivedOnly: Bool
    let normalizedCoordinatesOnly: Bool
    let excludesSubjectIdentity: Bool
    let excludesSourceBytes: Bool
    let excludesPrivateLocators: Bool
    let excludesActorIdentity: Bool
    let excludesComponentInputs: Bool
    let excludesUnsupportedClaims: Bool
    let backupDisposition: String
    let replayDisposition: String
    let deleteDisposition: String

    init() {
        schemaVersion = Self.schemaVersion
        sourceSchema = PlanPlacementSearchProjectionPolicyV1.semanticLabel
        searchPersistenceRelease = .v7
        fieldIDs = PlanPlacementSearchProjectionPolicyV1.fieldIDs
        metadataOnly = true
        derivedOnly = true
        normalizedCoordinatesOnly = true
        excludesSubjectIdentity = true
        excludesSourceBytes = true
        excludesPrivateLocators = true
        excludesActorIdentity = true
        excludesComponentInputs = true
        excludesUnsupportedClaims = true
        backupDisposition = "EXCLUDED_DERIVED_REBUILD"
        replayDisposition = "DROP_AND_REBUILD_FROM_FROZEN_PLAN_PROJECTIONS"
        deleteDisposition = "DROP_AND_REBUILD_AFTER_PLAN_ERASE"
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              sourceSchema == PlanPlacementSearchProjectionPolicyV1.semanticLabel,
              searchPersistenceRelease == .v7,
              fieldIDs == PlanPlacementSearchProjectionPolicyV1.fieldIDs,
              metadataOnly, derivedOnly, normalizedCoordinatesOnly,
              excludesSubjectIdentity, excludesSourceBytes,
              excludesPrivateLocators, excludesActorIdentity,
              excludesComponentInputs, excludesUnsupportedClaims,
              backupDisposition == "EXCLUDED_DERIVED_REBUILD",
              replayDisposition == "DROP_AND_REBUILD_FROM_FROZEN_PLAN_PROJECTIONS",
              deleteDisposition == "DROP_AND_REBUILD_AFTER_PLAN_ERASE" else {
            throw SearchContractFailureV1.invalidField
        }
    }
}

extension SearchPersistenceReleaseV1 {
    static let planPlacementPolicy = PlanPlacementSearchPersistencePolicyV1()
}

// MARK: - C37 current placement-pose search persistence boundary

/// Pose rows are disposable, current-tip-only metadata. The canonical pose
/// event history is the rebuild source; no angle, sensor stream, actor, or
/// private locator is admitted to this persistence projection.
struct C37PoseSearchPersistencePolicyV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let sourceSchema: String
    let searchPersistenceRelease: SearchPersistenceReleaseV1
    let fieldIDs: [String]
    let metadataOnly: Bool
    let currentTipsOnly: Bool
    let derivedOnly: Bool
    let excludesAngles: Bool
    let excludesSensorStream: Bool
    let excludesActorIdentity: Bool
    let excludesPrivateLocators: Bool
    let excludesSourceBytes: Bool
    let excludesUnsupportedClaims: Bool
    let backupDisposition: String
    let replayDisposition: String
    let deleteDisposition: String

    init() {
        schemaVersion = Self.schemaVersion
        sourceSchema = C37PoseSearchProjectionPolicyV1.semanticLabel
        searchPersistenceRelease = .v7
        fieldIDs = C37PoseSearchProjectionPolicyV1.fieldIDs
        metadataOnly = true
        currentTipsOnly = true
        derivedOnly = true
        excludesAngles = true
        excludesSensorStream = true
        excludesActorIdentity = true
        excludesPrivateLocators = true
        excludesSourceBytes = true
        excludesUnsupportedClaims = true
        backupDisposition = "EXCLUDED_DERIVED_REBUILD"
        replayDisposition = "DROP_AND_REBUILD_FROM_CANONICAL_POSE_HISTORY"
        deleteDisposition = "DROP_AND_REBUILD_AFTER_POSE_ERASE"
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              sourceSchema == C37PoseSearchProjectionPolicyV1.semanticLabel,
              searchPersistenceRelease == .v7,
              fieldIDs == C37PoseSearchProjectionPolicyV1.fieldIDs,
              metadataOnly, currentTipsOnly, derivedOnly, excludesAngles,
              excludesSensorStream, excludesActorIdentity, excludesPrivateLocators,
              excludesSourceBytes, excludesUnsupportedClaims,
              backupDisposition == "EXCLUDED_DERIVED_REBUILD",
              replayDisposition == "DROP_AND_REBUILD_FROM_CANONICAL_POSE_HISTORY",
              deleteDisposition == "DROP_AND_REBUILD_AFTER_POSE_ERASE" else {
            throw SearchContractFailureV1.invalidField
        }
    }
}

extension SearchPersistenceReleaseV1 {
    static let placementPosePolicy = C37PoseSearchPersistencePolicyV1()
}
// C30: this seam consumes only the frozen, metadata-only operating-context projection.
enum C30ConsumerBoundaryV1_Domain_Search_SearchPersistenceModelsV1 {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Domain/Search/SearchPersistenceModelsV1.swift", role: .search)
}

// MARK: - C31 lighting search persistence

struct C31LightingSearchPersistencePolicyV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let metadataOnly: Bool
    let localOnly: Bool
    let sourceProjection: String
    let currentFrozenProjectionOnly: Bool
    let dropAndRebuildAfterRestoreReplayDelete: Bool
    let excludesBytesNotesActorsPrivateLocators: Bool
    let excludesOperationalClaims: Bool

    init() {
        schemaVersion = Self.schemaVersion
        metadataOnly = true
        localOnly = true
        sourceProjection = "C31_LIGHTING_REPORT_PROJECTION_V1"
        currentFrozenProjectionOnly = true
        dropAndRebuildAfterRestoreReplayDelete = true
        excludesBytesNotesActorsPrivateLocators = true
        excludesOperationalClaims = true
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion, metadataOnly, localOnly,
              sourceProjection == "C31_LIGHTING_REPORT_PROJECTION_V1",
              currentFrozenProjectionOnly,
              dropAndRebuildAfterRestoreReplayDelete,
              excludesBytesNotesActorsPrivateLocators,
              excludesOperationalClaims else {
            throw SearchContractFailureV1.invalidField
        }
    }
}

extension SearchPersistenceReleaseV1 {
    static let lightingPolicy = C31LightingSearchPersistencePolicyV1()
}
// MARK: - C32 assistance search persistence boundary

enum C32AssistanceLifecycleBoundary_FieldEvidenceApp_Domain_Search_SearchPersistenceModelsV1_swift {
    static let proposalIsPersistent = AssistancePersistenceEnrollmentV1.proposalIsPersistent
    static let rejectedProposalCorpusIsPersistent = AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent
    static let durableFamilyCount = AssistancePersistenceEnrollmentV1.durableModelCount
    static let acceptedMutationKind: WorkspaceCommandKindV1 = .applyAssistanceAcceptance
    static let manualFallback: ManualFallbackActionV1 = .typeManually
    static let proposalRowsAreNotSearchPersisted = true

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

enum C33TemporalEvidenceConformance_FieldEvidenceApp_Domain_Search_SearchPersistenceModelsV1_swift {
    static let durableFamilyCount = TemporalEvidencePersistenceEnrollmentV1.durableModelCount
    static func validate(clip: TemporalEvidenceClipV1,
                         anchor: TimecodedEvidenceAnchorV1) throws {
        try clip.validateIntrinsic()
        try anchor.validate(clip: clip)
        guard durableFamilyCount == 2 else {
            throw TemporalEvidenceContractFailureV1.invalidValue
        }
    }
}

enum C45AcceptedLabelSearchPersistenceBoundaryV1 { static let createsSearchRowFamily=false;static let canonicalSnapshotRemainsOutsideIndex=true }

enum C46OperationalContactBoundary_34{static let permittedProjection="PARTY_METADATA_ONLY";static let rawPhoneOrEmailIndexed=false}

enum C47ActivityContractSearchPersistenceBoundaryV2 {
    static let sourceFamily = "ActivitySessionEnvelopeV2"
    static let currentEnvelopeHeadsOnly = true
    static let transitionAndReceiptHistoryIndexed = false
    static let conformanceReceiptsIndexed = false
    static let noPlanFallbackIndexed = false
    static let projectionIsDerivedAndBackupExcluded = true
}

// MARK: - C48 portable-review search persistence boundary

enum C48PortableReviewSearchPersistenceBoundaryV1 {
    static let derivedProjectionType = C48PortableReviewDerivedHistoryProjectionV1.self
    static let createsCanonicalReviewRow = false
    static let createsSearchRowFamily = false
    static let currentStateProjectionOnly = true
    static let historyMetadataMayBeRebuilt = true
    static let capabilityBytesPersisted = false
    static let capabilityProofBytesPersisted = false
    static let responseBodyPersisted = false
    static let rawRequestResponseBytesPersisted = false
    static let workspaceAndReplicaIdentityPersisted = false
    static let indexIsDisposableAndRebuildable = true

    static func validate(_ projection: C48PortableReviewDerivedHistoryProjectionV1) throws {
        try projection.validate()
    }
}

// MARK: - C49 work-resource search persistence boundary

enum C49WorkResourceSearchPersistenceBoundaryV1 {
    static let indexRowsAreDisposable = true
    static let canonicalWorkResourceRowsAreNotSearchRows = true
    static let rawStockRowsPersisted = false
    static let liveInventoryRowsPersisted = false

    static func row(
        _ projection: C49WorkResourceReportProjectionV1
    ) throws -> C49WorkResourceSearchProjectionV1 {
        try C49WorkResourceSearchBoundaryV1.projection(projection)
    }

    static func encode(
        _ projection: C49WorkResourceReportProjectionV1
    ) throws -> Data {
        let envelope = try C49WorkResourceProjectionSupportV1.envelope(projection, format: "SEARCH")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(envelope)
    }
}


enum C50IncumbentFileExchangeSearchPersistenceBoundaryV1 {
    static let canonicalSearchRowFamilyCount = 0
    static let scratchProjectionRowFamilyCount = 0
    static let profileSelectionRowFamilyCount = 0
    static let indexIsDisposableAndRebuildable = true
    static let targetCanonicalRowsUseExistingPersistencePolicies = true

    static func validate() -> Bool {
        canonicalSearchRowFamilyCount == 0
            && scratchProjectionRowFamilyCount == 0
            && profileSelectionRowFamilyCount == 0
            && indexIsDisposableAndRebuildable
            && targetCanonicalRowsUseExistingPersistencePolicies
            && C50IncumbentFileExchangeSearchBoundaryV1.validate()
    }
}

enum C34SceneNavigationSearchPersistenceBoundaryV1 {
    static let persistentRowFamilyCount = 0
    static let indexesSceneSnapshot = false
    static let indexesRouteRestorationReceipt = false
    static func validate() -> Bool { persistentRowFamilyCount == 0 && !indexesSceneSnapshot && !indexesRouteRestorationReceipt && C34SceneNavigationCanonicalExclusionV1.validate() }
}
// C52_BOUNDARY_ANCHOR: canonical-service-request-search
enum C52ServiceRequestSearchPersistenceBoundaryV1 {
    static let canonicalSourceFamily = "ServiceRequestRecordV1"
    static let indexedFields = ["requestText", "category", "requester.displayName", "requester.organization"]
    static let currentAcceptedRecordOnly = true
    static let indexIsDisposableAndRebuildable = true
    static let rawContactValueIndexed = false
    static let rawCapabilityIndexed = false
    static let acceptedSourceBytesIndexed = false
    static let duplicateCandidateProjectionPersisted = false
}

// MARK: - C53 service-reliability search persistence

/// This envelope is a disposable search projection. It is never a SwiftData
/// row, backup source, journal entry, or canonical service-reliability event.
struct C53ServiceReliabilitySearchPersistenceEnvelopeV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let projection: C53ServiceReliabilitySearchProjectionV1
    let lifecycle: [SearchIndexLifecycleDispositionV1]

    init(projection: C53ServiceReliabilitySearchProjectionV1) throws {
        try projection.validate()
        schemaVersion = Self.schemaVersion
        self.projection = projection
        lifecycle = Self.expectedLifecycle
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              lifecycle == Self.expectedLifecycle else {
            throw SearchContractFailureV1.unsupportedSchemaVersion
        }
        try projection.validate()
    }

    static let expectedLifecycle: [SearchIndexLifecycleDispositionV1] = [
        .excludedFromMigration,
        .excludedFromBackup,
        .excludedFromExport,
        .purgeOnDelete,
        .purgeOnErase,
        .dropAndRebuildAfterRestore,
        .dropAndRebuildOnDowngrade,
    ]
}

enum C53ServiceReliabilitySearchPersistenceBoundaryV1 {
    static let projectionRowsAreNonPersistent = true
    static let excludedFromBackupExportReplay = true
    static let rebuiltAfterRestoreDeleteErase = true
    static let canonicalServiceReliabilityEventsAreNotSearchRows = true

    static func envelope(
        _ projection: C53ServiceReliabilitySearchProjectionV1
    ) throws -> C53ServiceReliabilitySearchPersistenceEnvelopeV1 {
        try .init(projection: projection)
    }

    static func encode(
        _ projection: C53ServiceReliabilitySearchProjectionV1
    ) throws -> Data {
        let envelope = try envelope(projection)
        return try SearchPersistenceCodecV1.encode(envelope)
    }
}

// MARK: - C57 My Day search persistence boundary

/// Serialized only as a disposable local-index envelope. It is excluded from
/// canonical My Day persistence, journal replay, backup, and export.
struct C57MyDaySearchPersistenceEnvelopeV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let reportProjectionSHA256: String
    let sourceClosureSHA256: String
    let records: [C57MyDaySearchRecordV1]
    let lifecycle: [SearchIndexLifecycleDispositionV1]

    init(report: C57MyDayReportProjectionV1,
         plan: MyDayPlanV1,
         readiness: MyDayReadinessProjectionV1) throws {
        try report.validate(plan: plan, readiness: readiness)
        schemaVersion = Self.schemaVersion
        reportProjectionSHA256 = report.projectionSHA256
        sourceClosureSHA256 = report.sourceClosureSHA256
        records = try C57MyDaySearchProjectionBoundaryV1.records(from: report)
        lifecycle = Self.expectedLifecycle
        try validate()
    }

    func validate() throws {
        try records.forEach { try $0.validate() }
        guard schemaVersion == Self.schemaVersion,
              MutationEnvelopeV1.isSHA256(reportProjectionSHA256),
              MutationEnvelopeV1.isSHA256(sourceClosureSHA256),
              lifecycle == Self.expectedLifecycle,
              records == records.sorted(by: { $0.projectionIdentity < $1.projectionIdentity }),
              Set(records.map(\.projectionIdentity)).count == records.count,
              records.allSatisfy({
                  $0.reportProjectionSHA256 == reportProjectionSHA256
                      && $0.sourceClosureSHA256 == sourceClosureSHA256
              }) else {
            throw SearchContractFailureV1.staleIndex
        }
    }

    static let expectedLifecycle: [SearchIndexLifecycleDispositionV1] = [
        .excludedFromMigration, .excludedFromBackup, .excludedFromExport,
        .purgeOnDelete, .purgeOnErase, .dropAndRebuildAfterRestore,
        .dropAndRebuildOnDowngrade,
    ]
}

enum C57MyDaySearchPersistenceBoundaryV1 {
    static let createsCanonicalMyDayRowFamily = false
    static let readinessStatusAndDueAreNotCanonicalPersistence = true
    static let indexIsDisposableAndRebuildable = true

    static func envelope(report: C57MyDayReportProjectionV1,
                         plan: MyDayPlanV1,
                         readiness: MyDayReadinessProjectionV1) throws
        -> C57MyDaySearchPersistenceEnvelopeV1 {
        try .init(report: report, plan: plan, readiness: readiness)
    }

    static func encode(report: C57MyDayReportProjectionV1,
                       plan: MyDayPlanV1,
                       readiness: MyDayReadinessProjectionV1) throws -> Data {
        try SearchPersistenceCodecV1.encode(envelope(
            report: report, plan: plan, readiness: readiness
        ))
    }
}

// MARK: - C05 round-session search persistence boundary

/// This envelope is a disposable local-search derivative. It is never a
/// canonical session row, backup/export source, mutation receipt, or replay
/// input; restore and replay must discard it and rebuild from canonical
/// round-session frontiers.
struct C05RoundSessionSearchPersistenceEnvelopeV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let projection: C05RoundSessionSearchProjectionV1
    let lifecycle: [SearchIndexLifecycleDispositionV1]

    init(projection: C05RoundSessionSearchProjectionV1) throws {
        try projection.validate()
        schemaVersion = Self.schemaVersion
        self.projection = projection
        lifecycle = Self.expectedLifecycle
        try validate()
    }

    func validate() throws {
        try projection.validate()
        guard schemaVersion == Self.schemaVersion,
              lifecycle == Self.expectedLifecycle else {
            throw SearchContractFailureV1.unsupportedSchemaVersion
        }
    }

    static let expectedLifecycle: [SearchIndexLifecycleDispositionV1] = [
        .excludedFromMigration,
        .excludedFromBackup,
        .excludedFromExport,
        .purgeOnDelete,
        .purgeOnErase,
        .dropAndRebuildAfterRestore,
        .dropAndRebuildOnDowngrade,
    ]
}

enum C05RoundSessionSearchPersistenceBoundaryV1 {
    static let projectionRowsAreNonPersistent = true
    static let excludedFromBackupExportJournalAndReplay = true
    static let rebuiltOnlyFromCanonicalFrontiers = true
    static let createsCanonicalRoundSessionRows = false

    static func envelope(
        _ projection: C05RoundSessionSearchProjectionV1
    ) throws -> C05RoundSessionSearchPersistenceEnvelopeV1 {
        try .init(projection: projection)
    }

    static func encode(
        _ projection: C05RoundSessionSearchProjectionV1
    ) throws -> Data {
        try SearchPersistenceCodecV1.encode(envelope(projection))
    }
}


enum PrivateSystemDiscoverySearchPersistenceBoundaryV1 {
    static let persistenceMode = "DERIVED_ONLY"
    static let canonicalRowCount = 0
    static let backupPayloadCount = 0
    static let exportPayloadCount = 0
    static let restoreDisposition = "DROP_AND_REBUILD"

    static func validate() throws {
        guard persistenceMode == "DERIVED_ONLY",
              canonicalRowCount == 0,
              backupPayloadCount == 0,
              exportPayloadCount == 0,
              restoreDisposition == "DROP_AND_REBUILD",
              PrivateSystemDiscoveryLifecycleV1.dropAndRebuildOnRestore else {
            throw SearchContractFailureV1.unsupportedSchemaVersion
        }
    }
}

struct PrivateSystemDiscoveryIndexRebuildPayloadV1: Codable, Equatable, Sendable {
    let request: PrivateSystemDiscoveryRebuildRequestV1
    let descriptors: [PrivateSystemDiscoveryProjectionDescriptorV1]
    let manifest: PrivateSystemDiscoveryManifestV1
    let optIn: PrivateSystemDiscoveryOptInV1
    let availability: [AppIntentAvailabilityV1]
    let requestedAt: Date
}

struct PrivateSystemDiscoveryPendingOperationV1: Codable, Equatable, Sendable {
    let operationID: PrivateSystemDiscoveryOperationIDV1
    let operation: PrivateSystemDiscoveryJournalOperationV1
    let workspaceID: WorkspaceID
    let expectedPriorStateSHA256: String
    let resultingStateSHA256: String
    let rebuild: PrivateSystemDiscoveryIndexRebuildPayloadV1?
    let preparedAt: Date
}

struct PrivateSystemDiscoveryWorkspaceInventoryV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID
    let deletionFrontier: UInt64
}

struct PrivateSystemDiscoveryClientStateV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    var stateMap: PrivateSystemDiscoveryStateMapV1
    var knownWorkspaceIDs: [WorkspaceID]
    var workspaceInventory: [PrivateSystemDiscoveryWorkspaceInventoryV1]
    var journal: [PrivateSystemDiscoveryJournalEntryV1]
    var pendingOperation: PrivateSystemDiscoveryPendingOperationV1?

    init(
        stateMap: PrivateSystemDiscoveryStateMapV1,
        knownWorkspaceIDs: [WorkspaceID],
        workspaceInventory: [PrivateSystemDiscoveryWorkspaceInventoryV1],
        journal: [PrivateSystemDiscoveryJournalEntryV1],
        pendingOperation: PrivateSystemDiscoveryPendingOperationV1?
    ) throws {
        schemaVersion = Self.schemaVersion
        self.stateMap = stateMap
        self.knownWorkspaceIDs = knownWorkspaceIDs
        self.workspaceInventory = workspaceInventory
        self.journal = journal
        self.pendingOperation = pendingOperation
        try validate()
    }

    static var empty: Self {
        try! Self(
            stateMap: PrivateSystemDiscoveryStateMapV1(workspaces: []),
            knownWorkspaceIDs: [], workspaceInventory: [], journal: [], pendingOperation: nil
        )
    }

    func validate() throws {
        try stateMap.validate()
        try journal.forEach { try $0.validate() }
        if let pendingOperation {
            try pendingOperation.operationID.validate()
            guard pendingOperation.operationID.operation == pendingOperation.operation,
                  pendingOperation.operationID.workspaceID == pendingOperation.workspaceID,
                  CompatibilityCanonicalV1.validSHA256(pendingOperation.expectedPriorStateSHA256),
                  CompatibilityCanonicalV1.validSHA256(pendingOperation.resultingStateSHA256) else {
                throw PrivateSystemDiscoveryFailureV1.invalidValue
            }
            if let rebuild = pendingOperation.rebuild {
                try rebuild.request.validate(); try rebuild.manifest.validate(); try rebuild.optIn.validate()
                try rebuild.descriptors.forEach { try $0.validate() }
                try rebuild.availability.forEach { try $0.validate() }
                guard rebuild.request.operationID == pendingOperation.operationID,
                      rebuild.requestedAt == rebuild.request.requestedAt else {
                    throw PrivateSystemDiscoveryFailureV1.invalidValue
                }
            }
        }
        let sortedKnown = knownWorkspaceIDs.sorted {
            $0.rawValue.uuidString < $1.rawValue.uuidString
        }
        let sortedInventory = workspaceInventory.sorted {
            $0.workspaceID.rawValue.uuidString < $1.workspaceID.rawValue.uuidString
        }
        guard schemaVersion == Self.schemaVersion,
              knownWorkspaceIDs == sortedKnown,
              Set(knownWorkspaceIDs).count == knownWorkspaceIDs.count,
              workspaceInventory == sortedInventory,
              workspaceInventory.map(\.workspaceID) == knownWorkspaceIDs,
              Set(stateMap.workspaces.map(\.workspaceID)).isSubset(of: Set(knownWorkspaceIDs)) else {
            throw PrivateSystemDiscoveryFailureV1.invalidValue
        }
        let groups = Dictionary(grouping: journal, by: \.operationID)
        for entries in groups.values {
            guard let first = entries.first,
                  entries.allSatisfy({
                      $0.workspaceID == first.workspaceID
                          && $0.operation == first.operation
                          && $0.expectedPriorStateSHA256 == first.expectedPriorStateSHA256
                  }),
                  entries.map(\.state) == Array(PrivateSystemDiscoveryJournalStateV1.allCases.prefix(entries.count)),
                  entries.count <= PrivateSystemDiscoveryJournalStateV1.allCases.count,
                  Set(entries.map(\.state)).count == entries.count else {
                throw PrivateSystemDiscoveryFailureV1.invalidValue
            }
        }
        if let pendingOperation {
            let entries = groups[pendingOperation.operationID.rawValue] ?? []
            guard entries.count == 1 || entries.count == 2,
                  entries.first?.state == .prepared,
                  entries.first?.operation == pendingOperation.operation,
                  entries.first?.workspaceID == pendingOperation.workspaceID,
                  entries.first?.expectedPriorStateSHA256 == pendingOperation.expectedPriorStateSHA256,
                  entries.first?.resultingStateSHA256 == nil,
                  (entries.count == 1 || entries.last?.state == .effectApplied),
                  (pendingOperation.operation == .rebuild) == (pendingOperation.rebuild != nil) else {
                throw PrivateSystemDiscoveryFailureV1.invalidValue
            }
        } else {
            guard groups.values.allSatisfy({ $0.last?.state == .committed }) else {
                throw PrivateSystemDiscoveryFailureV1.invalidValue
            }
        }
    }
}

// MARK: - C17 exterior-lighting day inventory disposable search metadata

enum C17LightingDaySearchPersistencePolicyV1 {
    static let semanticLabel = "LIGHTING_DAY_INVENTORY_SEARCH_PROJECTION_V1"
    static let persistenceMode = "DERIVED_DISPOSABLE"
    static let fieldIDs = [
        "lighting_day_workflow_state",
        "lighting_day_condition_state",
        "lighting_day_pose_disposition",
        "lighting_day_night_followup_state",
        "lighting_day_projection_version",
    ]
    static let indexesCurrentWorkflowHeadsOnly = true
    static let excludesSafetyIntakeAndStopReasons = true
    static let excludesRouteAndLocationDetail = true
    static let excludesActorAndPrivateNotes = true
    static let excludesMediaIdentifiersDigestsAndBytes = true
    static let excludesConditionEvidenceAndIssueDetail = true
    static let excludesPhotometryAdequacyCommissioningDiagnosisAndNightPassClaims = true
}

struct C17LightingDaySearchRecordV1: Codable, Equatable, Comparable, Sendable {
    static let projectionVersion = "C17_LIGHTING_DAY_SEARCH_V1"
    let workspaceID: WorkspaceID
    let workflowID: UUID
    let workflowRevision: UInt64
    let workflowSHA256: String
    let state: LightingDayInventoryWorkflowStateV1
    let unknownOrNotObservedCount: Int
    let conditionCount: Int
    let poseNotDeclaredCount: Int
    let poseObservedCount: Int
    let poseNotObservedCount: Int
    let hasNightFollowup: Bool
    let normalizedTokens: [String]
    let displayIdentity: String
    let status: String
    let projectionSHA256: String

    init(workflow: LightingDayInventoryWorkflowV1) throws {
        let source = try LightingDayInventoryProjectionV1(workflow)
        guard source.searchEligible else { throw SearchContractFailureV1.forbiddenField }
        workspaceID = workflow.workspaceID
        workflowID = workflow.workflowID
        workflowRevision = workflow.revision
        workflowSHA256 = workflow.workflowSHA256
        state = workflow.state
        unknownOrNotObservedCount = source.unknownOrNotObservedCount
        conditionCount = workflow.conditionSnapshots.count
        poseNotDeclaredCount = workflow.conditionSnapshots.filter { $0.poseDisposition == .notDeclared }.count
        poseObservedCount = workflow.conditionSnapshots.filter { $0.poseDisposition == .observed }.count
        poseNotObservedCount = workflow.conditionSnapshots.filter { $0.poseDisposition == .notObserved }.count
        hasNightFollowup = workflow.nightFollowupPlan != nil
        let safeText = [
            "day lighting inventory",
            workflow.state.rawValue,
            source.unknownOrNotObservedCount == 0 ? "conditions recorded" : "unknown not observed",
            poseNotDeclaredCount == 0 ? "" : "pose not declared",
            poseObservedCount == 0 ? "" : "pose observed",
            poseNotObservedCount == 0 ? "" : "pose not observed",
            workflow.nightFollowupPlan == nil ? "night followup not prepared" : "night followup prepared",
            Self.projectionVersion,
        ].joined(separator: " ")
        normalizedTokens = Array(Set(SearchContractValidationV1.normalizeSearchText(safeText)
            .unicodeScalars
            .split { !CharacterSet.alphanumerics.contains($0) }
            .map(String.init))).sorted()
        displayIdentity = "Day lighting inventory"
        status = workflow.state.rawValue
        projectionSHA256 = try LightingDayInventoryCanonicalCodecV1.sha256(Basis(
            projectionVersion: Self.projectionVersion, workspaceID: workflow.workspaceID,
            workflowID: workflow.workflowID, workflowRevision: workflow.revision,
            workflowSHA256: workflow.workflowSHA256, state: workflow.state,
            unknownOrNotObservedCount: source.unknownOrNotObservedCount,
            conditionCount: conditionCount, poseNotDeclaredCount: poseNotDeclaredCount,
            poseObservedCount: poseObservedCount, poseNotObservedCount: poseNotObservedCount,
            hasNightFollowup: workflow.nightFollowupPlan != nil,
            normalizedTokens: normalizedTokens, displayIdentity: displayIdentity, status: status
        ))
        try validate()
    }

    var projectionIdentity: String {
        workspaceID.rawValue.uuidString.lowercased() + "|" + workflowID.uuidString.lowercased()
    }

    func validate() throws {
        try LightingDayInventoryLimitsV1.id(workflowID)
        try LightingDayInventoryLimitsV1.revision(workflowRevision)
        try [workflowSHA256, projectionSHA256].forEach(LightingDayInventoryLimitsV1.digest)
        guard state != .safetyStopped,
              unknownOrNotObservedCount >= 0,
              conditionCount > 0,
              poseNotDeclaredCount >= 0,
              poseObservedCount >= 0,
              poseNotObservedCount >= 0,
              poseNotDeclaredCount + poseObservedCount + poseNotObservedCount == conditionCount,
              normalizedTokens.count <= SearchContractLimitsV1.maximumProjectionTokens,
              !normalizedTokens.isEmpty,
              normalizedTokens == normalizedTokens.sorted(),
              Set(normalizedTokens).count == normalizedTokens.count,
              normalizedTokens.allSatisfy(SearchContractValidationV1.isCanonicalSearchToken),
              SearchContractValidationV1.validDisplayText(displayIdentity, maximumBytes: 240),
              SearchContractValidationV1.validDisplayText(status, maximumBytes: 120),
              projectionSHA256 == (try LightingDayInventoryCanonicalCodecV1.sha256(basis)) else {
            throw SearchContractFailureV1.invalidField
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.projectionIdentity < rhs.projectionIdentity
    }

    private var basis: Basis {
        .init(projectionVersion: Self.projectionVersion, workspaceID: workspaceID,
              workflowID: workflowID, workflowRevision: workflowRevision,
              workflowSHA256: workflowSHA256, state: state,
              unknownOrNotObservedCount: unknownOrNotObservedCount,
              conditionCount: conditionCount, poseNotDeclaredCount: poseNotDeclaredCount,
              poseObservedCount: poseObservedCount, poseNotObservedCount: poseNotObservedCount,
              hasNightFollowup: hasNightFollowup, normalizedTokens: normalizedTokens,
              displayIdentity: displayIdentity, status: status)
    }
    private struct Basis: Codable {
        let projectionVersion: String; let workspaceID: WorkspaceID; let workflowID: UUID
        let workflowRevision: UInt64; let workflowSHA256: String
        let state: LightingDayInventoryWorkflowStateV1; let unknownOrNotObservedCount: Int
        let conditionCount: Int; let poseNotDeclaredCount: Int
        let poseObservedCount: Int; let poseNotObservedCount: Int
        let hasNightFollowup: Bool; let normalizedTokens: [String]
        let displayIdentity: String; let status: String
    }
}

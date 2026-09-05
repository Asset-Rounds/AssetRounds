import Foundation

enum LocalSearchIndexStoreFailureV1: Error, Equatable, Sendable {
    case invalidRoot
    case corruptStore
    case protectedDataUnavailable
    case storageUnavailable
    case writeFailed
    case staleMutation
    case incompatibleCheckpoint
}

struct SearchIndexRebuildStagingV1: Equatable, Sendable {
    let checkpoint: SearchIndexRebuildCheckpointV1
    let records: [SearchIndexProjectionRecordV1]
}

struct SearchCanonicalRecordIdentityV1: Hashable, Sendable {
    let sourceKind: SearchSourceKindV1
    let stableID: String

    init(sourceKind: SearchSourceKindV1, stableID: String) throws {
        guard SearchContractValidationV1.validID(stableID) else {
            throw SearchContractFailureV1.invalidIdentifier
        }
        self.sourceKind = sourceKind
        self.stableID = stableID
    }
}

/// Process-local publication authority for one canonical derived-index path.
/// A rebuild captures this token before reading canonical rows and must present
/// the same token when publishing its complete projection.
struct SearchIndexPublicationTokenV1: Equatable, Sendable {
    fileprivate let canonicalFilePath: String
    fileprivate let invalidationGeneration: UInt64
}

/// Distinct store actors intentionally share one derived file. This registry
/// serializes their destructive lifecycle operations with guarded rebuild
/// publication, while the on-disk envelope remains disposable across launch.
private final class SearchIndexPublicationFenceV1: @unchecked Sendable {
    static let shared = SearchIndexPublicationFenceV1()

    private let lock = NSLock()
    private var invalidationGenerationByPath: [String: UInt64] = [:]

    private init() {}

    func token(for fileURL: URL) -> SearchIndexPublicationTokenV1 {
        let path = canonicalPath(fileURL)
        lock.lock()
        defer { lock.unlock() }
        return SearchIndexPublicationTokenV1(
            canonicalFilePath: path,
            invalidationGeneration: invalidationGenerationByPath[path, default: 0]
        )
    }

    func withInvalidation<T>(
        for fileURL: URL,
        _ operation: () throws -> T
    ) throws -> T {
        let path = canonicalPath(fileURL)
        lock.lock()
        defer { lock.unlock() }
        let current = invalidationGenerationByPath[path, default: 0]
        guard current < UInt64.max else {
            throw LocalSearchIndexStoreFailureV1.staleMutation
        }
        // Advance before touching bytes. Even a failed purge permanently
        // rejects a rebuild that started before the invalidation attempt.
        let (nextGeneration, overflowed) = current.addingReportingOverflow(1)
        guard !overflowed else { throw LocalSearchIndexStoreFailureV1.staleMutation }
        invalidationGenerationByPath[path] = nextGeneration
        return try operation()
    }

    func withGuardedPublication<T>(
        _ token: SearchIndexPublicationTokenV1,
        for fileURL: URL,
        _ operation: () throws -> T
    ) throws -> T {
        let path = canonicalPath(fileURL)
        lock.lock()
        defer { lock.unlock() }
        guard token.canonicalFilePath == path,
              token.invalidationGeneration
                == invalidationGenerationByPath[path, default: 0] else {
            throw LocalSearchIndexStoreFailureV1.staleMutation
        }
        return try operation()
    }

    private func canonicalPath(_ fileURL: URL) -> String {
        fileURL.standardizedFileURL.path
    }
}

/// File-backed, backup-excluded storage for the disposable search projection.
/// Every mutation publishes one complete envelope with an atomic replacement.
actor LocalSearchIndexStoreV1: SearchIndexSnapshotProvidingV1, SearchIndexLifecyclePortV1 {
    static let directoryName = "LocalSearchIndexV1"
    static let fileName = "projection.json"
    static let maximumStoreBytes = 16 * 1_024 * 1_024

    private struct StoredProjection: Codable, Equatable {
        let schemaVersion: Int
        let source: SearchSourceRevisionV1
        let index: SearchIndexRevisionV1
        let records: [SearchIndexProjectionRecordV1]

        init(_ projection: SearchIndexProjectionV1) {
            schemaVersion = projection.schemaVersion
            source = projection.source
            index = projection.index
            records = projection.records
        }

        func validateStructure() throws {
            guard schemaVersion == SearchIndexProjectionV1.schemaVersion,
                  source.workspaceID == index.workspaceID,
                  source.generationID == index.generationID,
                  index.indexedCommitRevision == source.commitRevision,
                  records.count <= SearchContractLimitsV1.maximumProjectionRecords,
                  records == records.sorted(),
                  Set(records.map(\.projectionIdentity)).count == records.count,
                  records.filter({ $0.sourceKind == .party }).allSatisfy({
                      SearchAccountabilityPersistencePolicyV1.accepts(fieldID: $0.fieldID)
                  }),
                  records.filter {
                      $0.sourceKind == .asset
                          && SearchAssetSemanticsPersistencePolicyV1.accepts(fieldID: $0.fieldID)
                  }.allSatisfy {
                      SearchAssetSemanticsPersistencePolicyV1.accepts(fieldID: $0.fieldID)
                  },
                  records.filter {
                      $0.sourceKind == .work
                          && SearchAuthorityCriterionPersistencePolicyV1.accepts(fieldID: $0.fieldID)
                  }.allSatisfy {
                      !AuthorityCriterionClaimVocabularyV1.containsProhibitedClaim(
                          in: $0.normalizedTokens + [$0.permittedSnippet].compactMap { $0 }
                      )
                  },
                  records.filter {
                      $0.sourceKind == .asset
                          && SearchFunctionalRelationshipsPersistencePolicyV1.accepts(fieldID: $0.fieldID)
                  }.allSatisfy {
                      SearchFunctionalRelationshipsPersistencePolicyV1.accepts(fieldID: $0.fieldID)
                          && !FunctionalRelationshipClaimVocabularyV1.containsProhibitedClaim(
                              in: $0.normalizedTokens + [$0.permittedSnippet].compactMap { $0 }
                          )
                  },
                  records.filter {
                      $0.sourceKind == .report
                          && SearchEvidenceAssurancePersistencePolicyV1.accepts(fieldID: $0.fieldID)
                  }.allSatisfy {
                      SearchEvidenceAssurancePersistencePolicyV1.acceptsMetadata(
                          fieldID: $0.fieldID,
                          tokens: $0.normalizedTokens,
                          snippet: $0.permittedSnippet
                      )
                  },
                  records.filter {
                      $0.sourceKind == .report
                          && SearchInspectionReviewPersistencePolicyV1.accepts(fieldID: $0.fieldID)
                  }.allSatisfy {
                      SearchInspectionReviewPersistencePolicyV1.acceptsMetadata(
                          fieldID: $0.fieldID,
                          tokens: $0.normalizedTokens,
                          snippet: $0.permittedSnippet
                      )
                  },
                  records.filter {
                      $0.sourceKind == .work
                          && SearchWorkPacketPersistencePolicyV1.accepts(fieldID: $0.fieldID)
                  }.allSatisfy {
                      SearchWorkPacketPersistencePolicyV1.acceptsMetadata(
                          fieldID: $0.fieldID,
                          tokens: $0.normalizedTokens,
                          snippet: $0.permittedSnippet
                      )
                  },
                  records.allSatisfy({
                      $0.workspaceID == source.workspaceID
                          && $0.sourceRevision <= source.commitRevision
                  }) else {
                throw LocalSearchIndexStoreFailureV1.corruptStore
            }
            try records.forEach { try $0.validate() }
        }

        func materialize(registry: SearchableFieldRegistryV1) throws -> SearchIndexProjectionV1 {
            try SearchIndexProjectionV1(
                source: source,
                index: index,
                records: records,
                registry: registry
            )
        }
    }

    private struct Envelope: Codable, Equatable {
        static let schemaVersion = 1
        let schemaVersion: Int
        var projection: StoredProjection?
        var rebuildCheckpoint: SearchIndexRebuildCheckpointV1?
        var stagedRecords: [SearchIndexProjectionRecordV1]

        init(
            projection: StoredProjection? = nil,
            rebuildCheckpoint: SearchIndexRebuildCheckpointV1? = nil,
            stagedRecords: [SearchIndexProjectionRecordV1] = []
        ) {
            schemaVersion = Self.schemaVersion
            self.projection = projection
            self.rebuildCheckpoint = rebuildCheckpoint
            self.stagedRecords = stagedRecords
        }

        func validate() throws {
            guard schemaVersion == Self.schemaVersion,
                  stagedRecords.count <= SearchContractLimitsV1.maximumProjectionRecords else {
                throw LocalSearchIndexStoreFailureV1.corruptStore
            }
            if let projection {
                let source = try SearchSourceRevisionV1(
                    workspaceID: projection.source.workspaceID,
                    generationID: projection.source.generationID,
                    commitRevision: projection.source.commitRevision
                )
                let index = try SearchIndexRevisionV1(
                    workspaceID: projection.index.workspaceID,
                    generationID: projection.index.generationID,
                    projectionFormatVersion: projection.index.projectionFormatVersion,
                    indexedCommitRevision: projection.index.indexedCommitRevision
                )
                guard source == projection.source,
                      index == projection.index,
                      projection.records == projection.records.sorted(),
                      Set(projection.records.map(\.projectionIdentity)).count
                        == projection.records.count else {
                    throw LocalSearchIndexStoreFailureV1.corruptStore
                }
                try projection.validateStructure()
            }
            if let rebuildCheckpoint {
                let source = try SearchSourceRevisionV1(
                    workspaceID: rebuildCheckpoint.source.workspaceID,
                    generationID: rebuildCheckpoint.source.generationID,
                    commitRevision: rebuildCheckpoint.source.commitRevision
                )
                let validatedCheckpoint = try SearchIndexRebuildCheckpointV1(
                    operationID: rebuildCheckpoint.operationID,
                    source: source,
                    projectionFormatVersion: rebuildCheckpoint.projectionFormatVersion,
                    nextCanonicalOffset: rebuildCheckpoint.nextCanonicalOffset,
                    projectedRecordCount: rebuildCheckpoint.projectedRecordCount,
                    state: rebuildCheckpoint.state
                )
                guard rebuildCheckpoint.projectedRecordCount == stagedRecords.count,
                      validatedCheckpoint == rebuildCheckpoint,
                      rebuildCheckpoint.projectionFormatVersion
                        == SearchPersistenceReleaseV1.derivedProjectionFormatVersion,
                      (stagedRecords.isEmpty || rebuildCheckpoint.nextCanonicalOffset > 0),
                      stagedRecords == stagedRecords.sorted(),
                      stagedRecords.allSatisfy({
                        $0.workspaceID == rebuildCheckpoint.source.workspaceID
                            && $0.sourceRevision <= rebuildCheckpoint.source.commitRevision
                      }),
                      Set(stagedRecords.map(\.projectionIdentity)).count == stagedRecords.count else {
                    throw LocalSearchIndexStoreFailureV1.corruptStore
                }
                try stagedRecords.forEach { try $0.validate() }
            } else if !stagedRecords.isEmpty {
                throw LocalSearchIndexStoreFailureV1.corruptStore
            }
        }
    }

    private let rootURL: URL
    private let fileURL: URL
    private let fileManager: FileManager
    private var envelope: Envelope?

    init(applicationSupportURL: URL, fileManager: FileManager = .default) throws {
        guard applicationSupportURL.isFileURL else {
            throw LocalSearchIndexStoreFailureV1.invalidRoot
        }
        rootURL = applicationSupportURL.standardizedFileURL.appendingPathComponent(
            Self.directoryName,
            isDirectory: true
        )
        fileURL = rootURL.appendingPathComponent(Self.fileName, isDirectory: false)
        self.fileManager = fileManager
    }

    /// Synchronous fail-closed bridge for canonical writer/startup paths that
    /// cannot cross an actor boundary before returning. Removal is safe for
    /// corrupt bytes because the derived envelope is never decoded.
    nonisolated static func synchronouslyInvalidateAfterCanonicalCommit(
        source: SearchSourceRevisionV1,
        applicationSupportURL: URL,
        fileManager: FileManager = .default
    ) throws {
        _ = try SearchSourceRevisionV1(
            workspaceID: source.workspaceID,
            generationID: source.generationID,
            commitRevision: source.commitRevision
        )
        try synchronouslyRemoveDerivedBytes(
            applicationSupportURL: applicationSupportURL,
            fileManager: fileManager
        )
    }

    nonisolated static func synchronouslyDropProjection(
        workspaceID: UUID,
        applicationSupportURL: URL,
        fileManager: FileManager = .default
    ) throws {
        guard workspaceID != SearchContractValidationV1.zeroUUID else {
            throw SearchContractFailureV1.invalidRevision
        }
        try synchronouslyRemoveDerivedBytes(
            applicationSupportURL: applicationSupportURL,
            fileManager: fileManager
        )
    }

    nonisolated static func synchronouslyEraseAll(
        applicationSupportURL: URL,
        fileManager: FileManager = .default
    ) throws {
        try synchronouslyRemoveDerivedBytes(
            applicationSupportURL: applicationSupportURL,
            fileManager: fileManager
        )
    }

    /// Capture immediately before a rebuild begins reading canonical rows.
    /// The returned token is valid only for this store's canonical file path.
    func publicationToken() -> SearchIndexPublicationTokenV1 {
        SearchIndexPublicationFenceV1.shared.token(for: fileURL)
    }

    func projection(
        for source: SearchSourceRevisionV1,
        registry: SearchableFieldRegistryV1
    ) throws -> SearchIndexProjectionV1 {
        try ensureLoaded()
        let stored = envelope?.projection
        switch SearchIndexReconciliationV1.disposition(source: source, index: stored?.index) {
        case .current:
            guard let stored else { throw SearchContractFailureV1.staleIndex }
            return try stored.materialize(registry: registry)
        case .aheadDropAndRebuild:
            throw SearchContractFailureV1.indexAheadOfSource
        case .absentBuild, .staleDropAndRebuild, .wrongGenerationDropAndRebuild,
             .incompatibleFormatDropAndRebuild:
            throw SearchContractFailureV1.staleIndex
        }
    }

    /// Reads the current projection through the opt-in C38 binding.  The
    /// derived store remains disposable, but party rows are still checked for
    /// the explicit non-contact, non-identity/legal field policy before being
    /// handed to report/search consumers.
    func accountabilityProjection(
        for source: SearchSourceRevisionV1,
        registry: SearchableFieldRegistryV1
    ) throws -> SearchIndexProjectionV1 {
        guard registry.fields.contains(where: { $0.sourceKind == .party }) else {
            throw SearchContractFailureV1.forbiddenField
        }
        let value = try projection(for: source, registry: registry)
        guard value.records.filter({ $0.sourceKind == .party }).allSatisfy({
            SearchAccountabilityPersistencePolicyV1.accepts(fieldID: $0.fieldID)
        }) else {
            throw LocalSearchIndexStoreFailureV1.corruptStore
        }
        return value
    }

    /// Reads the additive C39 semantic projection through its explicit
    /// allowlist. It remains disposable and source-revision bound.
    func assetSemanticsProjection(
        for source: SearchSourceRevisionV1,
        registry: SearchableFieldRegistryV1
    ) throws -> SearchIndexProjectionV1 {
        guard registry.fields.contains(where: {
            $0.sourceKind == .asset
                && SearchAssetSemanticsPersistencePolicyV1.accepts(fieldID: $0.fieldID)
        }) else {
            throw SearchContractFailureV1.forbiddenField
        }
        let value = try projection(for: source, registry: registry)
        guard value.records.filter({
            $0.sourceKind == .asset
                && SearchAssetSemanticsPersistencePolicyV1.accepts(fieldID: $0.fieldID)
        }).allSatisfy({
            SearchAssetSemanticsPersistencePolicyV1.accepts(fieldID: $0.fieldID)
        }) else {
            throw LocalSearchIndexStoreFailureV1.corruptStore
        }
        return value
    }

    /// Reads the disposable C41 relationship projection through its explicit
    /// allowlist. Only descriptor/current-head fields are admitted; the
    /// canonical event history remains in SwiftData and is rebuilt on demand.
    func functionalRelationshipsProjection(
        for source: SearchSourceRevisionV1,
        registry: SearchableFieldRegistryV1
    ) throws -> SearchIndexProjectionV1 {
        guard registry.fields.contains(where: {
            $0.sourceKind == .asset
                && SearchFunctionalRelationshipsPersistencePolicyV1.accepts(fieldID: $0.fieldID)
        }) else {
            throw SearchContractFailureV1.forbiddenField
        }
        let value = try projection(for: source, registry: registry)
        guard value.records.filter({
            $0.sourceKind == .asset
                && SearchFunctionalRelationshipsPersistencePolicyV1.accepts(fieldID: $0.fieldID)
        }).allSatisfy({
            SearchFunctionalRelationshipsPersistencePolicyV1.accepts(fieldID: $0.fieldID)
                && !FunctionalRelationshipClaimVocabularyV1.containsProhibitedClaim(
                    in: $0.normalizedTokens + [$0.permittedSnippet].compactMap { $0 }
                )
        }) else {
            throw LocalSearchIndexStoreFailureV1.corruptStore
        }
        return value
    }

    /// Reads the disposable C13 assurance projection through its explicit
    /// metadata allowlist. No claim/evidence bytes, evidence identifiers or
    /// actor/private fields are admitted to this consumer.
    func evidenceAssuranceProjection(
        for source: SearchSourceRevisionV1,
        registry: SearchableFieldRegistryV1
    ) throws -> SearchIndexProjectionV1 {
        guard registry.fields.contains(where: {
            $0.sourceKind == .report
                && SearchEvidenceAssurancePersistencePolicyV1.accepts(fieldID: $0.fieldID)
        }) else {
            throw SearchContractFailureV1.forbiddenField
        }
        let value = try projection(for: source, registry: registry)
        guard value.records.filter({
            $0.sourceKind == .report
                && SearchEvidenceAssurancePersistencePolicyV1.accepts(fieldID: $0.fieldID)
        }).allSatisfy({
            SearchEvidenceAssurancePersistencePolicyV1.acceptsMetadata(
                fieldID: $0.fieldID,
                tokens: $0.normalizedTokens,
                snippet: $0.permittedSnippet
            )
        }) else {
            throw LocalSearchIndexStoreFailureV1.corruptStore
        }
        return value
    }

    /// Reads the disposable C14 review/change/action projection through its
    /// exact current-head metadata allowlist. History, reasons, actors,
    /// evidence references, ownership, and claim text remain unavailable to
    /// the search consumer.
    func inspectionReviewProjection(
        for source: SearchSourceRevisionV1,
        registry: SearchableFieldRegistryV1
    ) throws -> SearchIndexProjectionV1 {
        guard registry.fields.contains(where: {
            $0.sourceKind == .report
                && SearchInspectionReviewPersistencePolicyV1.accepts(fieldID: $0.fieldID)
        }) else {
            throw SearchContractFailureV1.forbiddenField
        }
        let value = try projection(for: source, registry: registry)
        guard value.records.filter({
            $0.sourceKind == .report
                && SearchInspectionReviewPersistencePolicyV1.accepts(fieldID: $0.fieldID)
        }).allSatisfy({
            SearchInspectionReviewPersistencePolicyV1.acceptsMetadata(
                fieldID: $0.fieldID,
                tokens: $0.normalizedTokens,
                snippet: $0.permittedSnippet
            )
        }) else {
            throw LocalSearchIndexStoreFailureV1.corruptStore
        }
        return value
    }

    /// Compatibility spelling for clients that call the section a review
    /// history projection rather than an inspection-review projection.
    func reviewHistoryProjection(
        for source: SearchSourceRevisionV1,
        registry: SearchableFieldRegistryV1
    ) throws -> SearchIndexProjectionV1 {
        try inspectionReviewProjection(for: source, registry: registry)
    }

    /// Reads the disposable C15 packet projection through its current-head
    /// metadata allowlist. Canonical claim/lease/result rows stay in the
    /// workspace store and are never returned by this search surface.
    func workPacketProjection(
        for source: SearchSourceRevisionV1,
        registry: SearchableFieldRegistryV1
    ) throws -> SearchIndexProjectionV1 {
        guard registry.fields.contains(where: {
            $0.sourceKind == .work
                && SearchWorkPacketPersistencePolicyV1.accepts(fieldID: $0.fieldID)
        }) else {
            throw SearchContractFailureV1.forbiddenField
        }
        let value = try projection(for: source, registry: registry)
        guard value.records.filter({
            $0.sourceKind == .work
                && SearchWorkPacketPersistencePolicyV1.accepts(fieldID: $0.fieldID)
        }).allSatisfy({
            SearchWorkPacketPersistencePolicyV1.acceptsMetadata(
                fieldID: $0.fieldID,
                tokens: $0.normalizedTokens,
                snippet: $0.permittedSnippet
            )
        }) else {
            throw LocalSearchIndexStoreFailureV1.corruptStore
        }
        return value
    }

    /// Singular compatibility spelling for callers that model one bounded
    /// relationship projection rather than the collection of current heads.
    func functionalRelationshipProjection(
        for source: SearchSourceRevisionV1,
        registry: SearchableFieldRegistryV1
    ) throws -> SearchIndexProjectionV1 {
        try functionalRelationshipsProjection(for: source, registry: registry)
    }

    func revision() throws -> SearchIndexRevisionV1? {
        try ensureLoaded()
        return envelope?.projection?.index
    }

    /// Invalidates only after an accepted canonical commit. A replay at an
    /// already-indexed revision is idempotent; an older callback can never
    /// remove a newer complete projection or rebuild checkpoint.
    func invalidateAfterCanonicalCommit(source: SearchSourceRevisionV1) throws {
        let validatedSource = try SearchSourceRevisionV1(
            workspaceID: source.workspaceID,
            generationID: source.generationID,
            commitRevision: source.commitRevision
        )
        guard validatedSource == source else { throw SearchContractFailureV1.invalidRevision }
        do {
            try ensureLoaded()
        } catch LocalSearchIndexStoreFailureV1.corruptStore {
            try replaceWithEmptyStoreWithoutReading()
            return
        }

        let observedSources = [
            envelope?.projection?.source,
            envelope?.rebuildCheckpoint?.source,
        ].compactMap { $0 }.filter {
            $0.workspaceID == source.workspaceID && $0.generationID == source.generationID
        }
        if observedSources.contains(where: { $0.commitRevision > source.commitRevision }) {
            throw LocalSearchIndexStoreFailureV1.staleMutation
        }
        if envelope?.projection?.source == source {
            if let checkpointSource = envelope?.rebuildCheckpoint?.source,
               checkpointSource != source {
                var next = envelope!
                next.rebuildCheckpoint = nil
                next.stagedRecords = []
                try persist(next)
            }
            return
        }
        if envelope?.projection == nil,
           envelope?.rebuildCheckpoint?.source == source {
            return
        }
        try replaceWithEmptyStoreWithoutReading()
    }

    /// Reconciles one accepted canonical commit. Deletes are applied before
    /// upserts so amendments cannot leave an older field row or duplicate hit.
    func applyCanonicalCommit(
        source: SearchSourceRevisionV1,
        upserting records: [SearchIndexProjectionRecordV1],
        deleting identities: Set<SearchCanonicalRecordIdentityV1>,
        registry: SearchableFieldRegistryV1
    ) throws {
        guard C08ImportBulkLocalSearchIndexBoundaryV1.validate() else {
            throw LocalSearchIndexStoreFailureV1.corruptStore
        }
        try ensureLoaded()
        guard let prior = envelope?.projection,
              prior.source.workspaceID == source.workspaceID,
              prior.source.generationID == source.generationID,
              (source.commitRevision == prior.source.commitRevision
                || (prior.source.commitRevision < UInt64.max
                    && source.commitRevision == prior.source.commitRevision + 1)),
              identities.allSatisfy({ SearchContractValidationV1.validID($0.stableID) }),
              records.allSatisfy({
                $0.workspaceID == source.workspaceID && $0.sourceRevision == source.commitRevision
              }) else {
            throw LocalSearchIndexStoreFailureV1.staleMutation
        }

        let amendedIdentities = Set(records.map {
            CanonicalIdentity(sourceKind: $0.sourceKind, stableID: $0.sourceStableID)
        })
        let deletingIdentities = Set(identities.map {
            CanonicalIdentity(sourceKind: $0.sourceKind, stableID: $0.stableID)
        })
        var byIdentity = Dictionary(
            uniqueKeysWithValues: prior.records
                .filter {
                    let identity = CanonicalIdentity(
                        sourceKind: $0.sourceKind,
                        stableID: $0.sourceStableID
                    )
                    return !deletingIdentities.contains(identity)
                        && !amendedIdentities.contains(identity)
                }
                .map { ($0.projectionIdentity, $0) }
        )
        for record in records {
            try record.validate()
            _ = try registry.descriptor(fieldID: record.fieldID, sourceKind: record.sourceKind)
            byIdentity[record.projectionIdentity] = record
        }
        let index = try SearchIndexRevisionV1(
            workspaceID: source.workspaceID,
            generationID: source.generationID,
            projectionFormatVersion: SearchPersistenceReleaseV1.derivedProjectionFormatVersion,
            indexedCommitRevision: source.commitRevision
        )
        let replacement = try SearchIndexProjectionV1(
            source: source,
            index: index,
            records: Array(byIdentity.values),
            registry: registry
        )
        if source.commitRevision == prior.source.commitRevision,
           StoredProjection(replacement) != prior {
            throw LocalSearchIndexStoreFailureV1.staleMutation
        }
        var next = envelope!
        next.projection = StoredProjection(replacement)
        try persist(next)
    }

    /// Compatibility for callers that have not yet adopted composite
    /// identities. It fails closed if one stable ID names multiple source
    /// kinds instead of deleting unrelated canonical records.
    func applyCanonicalCommit(
        source: SearchSourceRevisionV1,
        upserting records: [SearchIndexProjectionRecordV1],
        deletingStableIDs: Set<String>,
        registry: SearchableFieldRegistryV1
    ) throws {
        guard C08ImportBulkLocalSearchIndexBoundaryV1.validate() else {
            throw LocalSearchIndexStoreFailureV1.corruptStore
        }
        try ensureLoaded()
        guard deletingStableIDs.allSatisfy({ SearchContractValidationV1.validID($0) }) else {
            throw LocalSearchIndexStoreFailureV1.staleMutation
        }
        let priorRecords = envelope?.projection?.records ?? []
        var identities = Set<SearchCanonicalRecordIdentityV1>()
        for stableID in deletingStableIDs {
            let kinds = Set(
                priorRecords.lazy
                    .filter { $0.sourceStableID == stableID }
                    .map(\.sourceKind)
            )
            guard kinds.count <= 1, let kind = kinds.first else {
                throw LocalSearchIndexStoreFailureV1.staleMutation
            }
            identities.insert(
                try SearchCanonicalRecordIdentityV1(sourceKind: kind, stableID: stableID)
            )
        }
        try applyCanonicalCommit(
            source: source,
            upserting: records,
            deleting: identities,
            registry: registry
        )
    }

    /// Publishes a fully-built projection only after exact-revision validation.
    /// A failed write leaves the previous complete projection intact.
    func replaceProjection(
        source: SearchSourceRevisionV1,
        records: [SearchIndexProjectionRecordV1],
        registry: SearchableFieldRegistryV1
    ) throws {
        try ensureLoaded()
        if let existing = envelope?.projection,
           existing.source.workspaceID == source.workspaceID,
           existing.source.generationID == source.generationID,
           existing.index.indexedCommitRevision > source.commitRevision {
            throw LocalSearchIndexStoreFailureV1.staleMutation
        }
        let index = try SearchIndexRevisionV1(
            workspaceID: source.workspaceID,
            generationID: source.generationID,
            projectionFormatVersion: SearchPersistenceReleaseV1.derivedProjectionFormatVersion,
            indexedCommitRevision: source.commitRevision
        )
        let projection = try SearchIndexProjectionV1(
            source: source,
            index: index,
            records: records,
            registry: registry
        )
        try persist(Envelope(projection: StoredProjection(projection)))
    }

    /// Rebuild-only publication route. The fence check and atomic protected
    /// write occur under the same process-wide per-path lock as every purge
    /// and invalidation, so a stale rebuild cannot publish after either one.
    func replaceProjection(
        source: SearchSourceRevisionV1,
        records: [SearchIndexProjectionRecordV1],
        registry: SearchableFieldRegistryV1,
        publicationToken: SearchIndexPublicationTokenV1
    ) throws {
        try ensureLoaded()
        if let existing = envelope?.projection,
           existing.source.workspaceID == source.workspaceID,
           existing.source.generationID == source.generationID,
           existing.index.indexedCommitRevision > source.commitRevision {
            throw LocalSearchIndexStoreFailureV1.staleMutation
        }
        let index = try SearchIndexRevisionV1(
            workspaceID: source.workspaceID,
            generationID: source.generationID,
            projectionFormatVersion: SearchPersistenceReleaseV1.derivedProjectionFormatVersion,
            indexedCommitRevision: source.commitRevision
        )
        let projection = try SearchIndexProjectionV1(
            source: source,
            index: index,
            records: records,
            registry: registry
        )
        try SearchIndexPublicationFenceV1.shared.withGuardedPublication(
            publicationToken,
            for: fileURL
        ) {
            try persist(Envelope(projection: StoredProjection(projection)))
        }
    }

    func rebuildStaging() throws -> SearchIndexRebuildStagingV1? {
        try ensureLoaded()
        guard let checkpoint = envelope?.rebuildCheckpoint else { return nil }
        return SearchIndexRebuildStagingV1(
            checkpoint: checkpoint,
            records: envelope?.stagedRecords ?? []
        )
    }

    /// Rebuild-only staging read. A token captured before an intervening
    /// invalidation cannot observe or resume staging recreated afterward.
    func rebuildStaging(
        publicationToken: SearchIndexPublicationTokenV1
    ) throws -> SearchIndexRebuildStagingV1? {
        try SearchIndexPublicationFenceV1.shared.withGuardedPublication(
            publicationToken,
            for: fileURL
        ) {
            try ensureLoaded()
            guard let checkpoint = envelope?.rebuildCheckpoint else { return nil }
            return SearchIndexRebuildStagingV1(
                checkpoint: checkpoint,
                records: envelope?.stagedRecords ?? []
            )
        }
    }

    func saveRebuildStaging(
        checkpoint: SearchIndexRebuildCheckpointV1,
        records: [SearchIndexProjectionRecordV1],
        registry: SearchableFieldRegistryV1
    ) throws {
        try ensureLoaded()
        let sorted = try SearchIndexProjectionRecordV1.validateProjection(records, against: registry)
        guard checkpoint.projectedRecordCount == sorted.count,
              sorted.allSatisfy({
                $0.workspaceID == checkpoint.source.workspaceID
                    && $0.sourceRevision <= checkpoint.source.commitRevision
              }) else {
            throw LocalSearchIndexStoreFailureV1.incompatibleCheckpoint
        }
        var next = envelope!
        next.rebuildCheckpoint = checkpoint
        next.stagedRecords = sorted
        try persist(next)
    }

    /// Rebuild-only staging write. Validation, current-envelope loading, and
    /// protected persistence are serialized with every invalidation so stale
    /// staged rows cannot be recreated after a purge.
    func saveRebuildStaging(
        checkpoint: SearchIndexRebuildCheckpointV1,
        records: [SearchIndexProjectionRecordV1],
        registry: SearchableFieldRegistryV1,
        publicationToken: SearchIndexPublicationTokenV1
    ) throws {
        try SearchIndexPublicationFenceV1.shared.withGuardedPublication(
            publicationToken,
            for: fileURL
        ) {
            try ensureLoaded()
            let sorted = try SearchIndexProjectionRecordV1.validateProjection(
                records,
                against: registry
            )
            guard checkpoint.projectedRecordCount == sorted.count,
                  sorted.allSatisfy({
                    $0.workspaceID == checkpoint.source.workspaceID
                        && $0.sourceRevision <= checkpoint.source.commitRevision
                  }) else {
                throw LocalSearchIndexStoreFailureV1.incompatibleCheckpoint
            }
            var next = envelope!
            next.rebuildCheckpoint = checkpoint
            next.stagedRecords = sorted
            try persist(next)
        }
    }

    func clearRebuildStaging(operationID: UUID? = nil) throws {
        try ensureLoaded()
        if let operationID,
           envelope?.rebuildCheckpoint?.operationID != operationID {
            throw LocalSearchIndexStoreFailureV1.incompatibleCheckpoint
        }
        var next = envelope!
        next.rebuildCheckpoint = nil
        next.stagedRecords = []
        try persist(next)
    }

    /// Rebuild-only staging clear. The same captured token prevents an older
    /// task from clearing or replacing staging belonging to a post-purge run.
    func clearRebuildStaging(
        operationID: UUID? = nil,
        publicationToken: SearchIndexPublicationTokenV1
    ) throws {
        try SearchIndexPublicationFenceV1.shared.withGuardedPublication(
            publicationToken,
            for: fileURL
        ) {
            try ensureLoaded()
            if let operationID,
               envelope?.rebuildCheckpoint?.operationID != operationID {
                throw LocalSearchIndexStoreFailureV1.incompatibleCheckpoint
            }
            var next = envelope!
            next.rebuildCheckpoint = nil
            next.stagedRecords = []
            try persist(next)
        }
    }

    func dropProjection() throws {
        try dropProjectionAuthorized(workspaceID: nil, generationID: nil)
    }

    func dropProjection(workspaceID: UUID) throws {
        try dropProjectionAuthorized(workspaceID: workspaceID, generationID: nil)
    }

    func dropProjection(workspaceID: UUID, generationID: UUID) throws {
        try dropProjectionAuthorized(workspaceID: workspaceID, generationID: generationID)
    }

    private func dropProjectionAuthorized(
        workspaceID: UUID?,
        generationID: UUID?
    ) throws {
        guard workspaceID.map({ $0 != SearchContractValidationV1.zeroUUID }) ?? true,
              generationID.map({ $0 != SearchContractValidationV1.zeroUUID }) ?? true else {
            throw SearchContractFailureV1.invalidRevision
        }
        if let cached = envelope?.projection {
            if let workspaceID, cached.source.workspaceID != workspaceID { return }
            if let generationID, cached.source.generationID != generationID { return }
        }
        // The index is derived and scoped by the active store session. Never
        // decode potentially corrupt bytes before an authorized purge.
        try replaceWithEmptyStoreWithoutReading()
    }

    func purgeWorkspace(_ workspaceID: UUID) throws {
        try dropProjection(workspaceID: workspaceID)
    }

    func eraseAll() throws {
        // Erase must remain available specifically when derived bytes cannot
        // be decoded. The fixed store URL is deleted and recreated empty.
        try replaceWithEmptyStoreWithoutReading()
    }
}

extension LocalSearchIndexStoreV1 {
    /// Validates the disposable C18 package row at the local-index boundary.
    /// This is intentionally separate from SearchIndexProjectionRecordV1 so a
    /// package receipt can never be mistaken for a canonical search source.
    static func packageEvolutionRecord(
        metadata: PackageEvolutionConsumerMetadataV1
    ) throws -> PackageEvolutionSearchRecordV1 {
        try PackageEvolutionSearchRecordV1(metadata: metadata)
    }

    static func validatePackageEvolutionRecord(
        _ record: PackageEvolutionSearchRecordV1
    ) throws {
        try record.validate()
        guard PackageEvolutionSearchProjectionPolicyV1.fieldIDs.count ==
                PackageEvolutionSearchFieldV1.allCases.count,
              PackageEvolutionSearchProjectionPolicyV1.derivedOnly,
              PackageEvolutionSearchProjectionPolicyV1.excludesCanonicalPackageBytes,
              PackageEvolutionSearchProjectionPolicyV1.excludesDraftPayload,
              PackageEvolutionSearchProjectionPolicyV1.excludesActorIdentity else {
            throw PackageEvolutionConsumerFailureV1.forbiddenSensitiveMetadata
        }
    }
}

enum C34RouteAdoptionBoundary_LocalSearchIndexStoreV1 {
    static let searchAnchorType = RouteSearchAnchorV1.self
    static let resolutionResultType = RouteResolutionResultV1.self
    static let routeStateIsIndexed = false
}

extension LocalSearchIndexStoreV1 {
    static func advancedScheduleOccurrenceSearchRecord(
        from projection: AdvancedScheduleReportProjectionV1,
        occurrence: AdvancedScheduleOccurrenceReportProjectionV1
    ) throws -> AdvancedScheduleOccurrenceSearchRecordV1 {
        let value = try AdvancedScheduleOccurrenceSearchRecordV1(
            projection: projection, occurrence: occurrence)
        try AdvancedScheduleOccurrenceSearchProjectionPolicyV1.validate(value)
        try AdvancedScheduleOccurrenceSearchPersistencePolicyV1().validate()
        return value
    }
}


enum C50IncumbentFileExchangeLocalSearchBoundaryV1 {
    static let existingIndexRemainsSoleSearchStore = true
    static let storesAdapterSessionRows = false
    static let storesInputOrQuarantineDigests = false
    static let storesExternalKeysPathsOrAvailability = false
    static let targetProjectionRebuildRemainsExistingOwner = true

    static func validate() -> Bool {
        existingIndexRemainsSoleSearchStore
            && !storesAdapterSessionRows
            && !storesInputOrQuarantineDigests
            && !storesExternalKeysPathsOrAvailability
            && targetProjectionRebuildRemainsExistingOwner
            && C50IncumbentFileExchangeSearchPersistenceBoundaryV1.validate()
    }
}

// MARK: - C49 work-resource local-search boundary

enum C49WorkResourceLocalSearchBoundaryV1 {
    static let canonicalRecordType = "WorkResourceEntryV1"
    static let localPartReferenceType = "LocalPartReferenceSnapshotV1"
    static let permittedFields = ["work_resource.subject", "work_resource.state", "work_resource.summary"]
    static let indexIsDerivedAndRebuildable = true
    static let directCostIndexed = false
    static let internalNoteIndexed = false
    static let contentLocatorIndexed = false
    static let liveInventoryLookup = false

    static func validateField(_ fieldID: String) throws {
        guard permittedFields.contains(fieldID) else {
            throw SearchContractFailureV1.forbiddenField
        }
    }
}

enum C55PartsStockLocalSearchBoundaryV1 {
    static let canonicalRecordType = "LocalPartDefinitionV1"
    static let permittedFields = ["parts_stock.display_name", "parts_stock.product_identity"]
    static let prohibitedFields = ["parts_stock.balance", "parts_stock.storage_label", "parts_stock.movement_reason"]
    static func validateField(_ fieldID: String) throws { guard permittedFields.contains(fieldID), !prohibitedFields.contains(fieldID) else { throw LocalSearchIndexStoreFailureV1.invalidQuery } }
}

// MARK: - C30 operating-context search adapter

extension LocalSearchIndexStoreV1 {
    static func operatingContextSearchRecord(
        from projection: C30EvidenceContextReportReferenceV1
    ) throws -> C30OperatingContextSearchRecordV1 {
        let record = try C30OperatingContextSearchRecordV1(projection)
        try C30OperatingContextSearchPersistencePolicyV1.validate()
        return record
    }

    static let c30OperatingContextIndexIsLocalOnly = true
    static let c30OperatingContextRowsAreRebuiltFromCanonicalContext = true
}

// MARK: - C25 survey-definition adapter

extension LocalSearchIndexStoreV1 {
    /// Survey definitions contribute only disposable, bounded release
    /// metadata.  Definition answers, prompts, locators, package payloads,
    /// and actor identity never enter the local search store.
    static func surveyDefinitionSearchRecord(
        from release: SurveyDefinitionReleaseV1,
        lifecycleState: SurveyDefinitionLifecycleStateV1
    ) throws -> SurveyDefinitionSearchRecordV1 {
        let record = try SurveyDefinitionSearchRecordV1(
            release: release,
            lifecycleState: lifecycleState
        )
        try SurveyDefinitionSearchProjectionPolicyV1.validate(record)
        try SurveyDefinitionSearchPersistencePolicyV1().validate()
        return record
    }

    static func validateSurveyDefinitionSearchRecord(
        _ record: SurveyDefinitionSearchRecordV1
    ) throws -> SurveyDefinitionSearchRecordV1 {
        try SurveyDefinitionSearchProjectionPolicyV1.validate(record)
        try SurveyDefinitionSearchPersistencePolicyV1().validate()
        return record
    }
}

private extension LocalSearchIndexStoreV1 {
    nonisolated static func synchronouslyRemoveDerivedBytes(
        applicationSupportURL: URL,
        fileManager: FileManager
    ) throws {
        guard applicationSupportURL.isFileURL else {
            throw LocalSearchIndexStoreFailureV1.invalidRoot
        }
        let root = applicationSupportURL.standardizedFileURL.appendingPathComponent(
            directoryName,
            isDirectory: true
        )
        let target = root.appendingPathComponent(fileName, isDirectory: false)
        do {
            try SearchIndexPublicationFenceV1.shared.withInvalidation(for: target) {
                if fileManager.fileExists(atPath: target.path) {
                    do {
                        try fileManager.removeItem(at: target)
                    } catch {
                        guard fileManager.fileExists(atPath: target.path) else { return }
                        throw error
                    }
                }
            }
        } catch {
            throw map(error)
        }
    }

    struct CanonicalIdentity: Hashable {
        let sourceKind: SearchSourceKindV1
        let stableID: String
    }

    func replaceWithEmptyStoreWithoutReading() throws {
        do {
            try SearchIndexPublicationFenceV1.shared.withInvalidation(for: fileURL) {
                try fileManager.createDirectory(
                    at: rootURL,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
                if fileManager.fileExists(atPath: fileURL.path) {
                    do {
                        try fileManager.removeItem(at: fileURL)
                    } catch {
                        guard !fileManager.fileExists(atPath: fileURL.path) else { throw error }
                    }
                }
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                var mutableRoot = rootURL
                try mutableRoot.setResourceValues(values)
                envelope = nil
                let empty = Envelope()
                try persistWithoutLoading(empty)
                envelope = empty
            }
        } catch {
            envelope = nil
            throw Self.map(error)
        }
    }

    func ensureLoaded() throws {
        // Several production lifecycle services intentionally bind separate
        // actor instances to this one derived file. Re-read for every public
        // operation so a purge or invalidation by another instance cannot be
        // hidden by this actor's previously validated cache.
        envelope = nil
        do {
            try fileManager.createDirectory(
                at: rootURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutableRoot = rootURL
            try mutableRoot.setResourceValues(values)

            guard fileManager.fileExists(atPath: fileURL.path) else {
                let empty = Envelope()
                try persistWithoutLoading(empty)
                envelope = empty
                return
            }
            let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
            guard let size = attributes[.size] as? NSNumber,
                  size.intValue <= Self.maximumStoreBytes else {
                throw LocalSearchIndexStoreFailureV1.corruptStore
            }
            let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
            guard data.count <= Self.maximumStoreBytes else {
                throw LocalSearchIndexStoreFailureV1.corruptStore
            }
            let decoded = try Self.decoder().decode(Envelope.self, from: data)
            try decoded.validate()
            guard try Self.encoder().encode(decoded) == data else {
                throw LocalSearchIndexStoreFailureV1.corruptStore
            }
            envelope = decoded
        } catch {
            throw Self.mapRead(error)
        }
    }

    func persist(_ next: Envelope) throws {
        try next.validate()
        do {
            try persistWithoutLoading(next)
            let readBack = try Data(contentsOf: fileURL)
            let decoded = try Self.decoder().decode(Envelope.self, from: readBack)
            try decoded.validate()
            guard decoded == next else { throw LocalSearchIndexStoreFailureV1.writeFailed }
            envelope = decoded
        } catch {
            throw Self.map(error)
        }
    }

    func persistWithoutLoading(_ next: Envelope) throws {
        let data = try Self.encoder().encode(next)
        guard data.count <= Self.maximumStoreBytes else {
            throw SearchContractFailureV1.limitExceeded
        }
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        try ProtectedFilePolicyV1.applyAndVerify(.searchIndex, at: fileURL)
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }

    static func map(_ error: Error) -> Error {
        if error is SearchContractFailureV1 || error is LocalSearchIndexStoreFailureV1 {
            return error
        }
        if error is DecodingError {
            return LocalSearchIndexStoreFailureV1.corruptStore
        }
        let cocoa = error as NSError
        guard cocoa.domain == NSCocoaErrorDomain else {
            return LocalSearchIndexStoreFailureV1.writeFailed
        }
        switch cocoa.code {
        case NSFileReadNoPermissionError, NSFileWriteNoPermissionError:
            return LocalSearchIndexStoreFailureV1.protectedDataUnavailable
        case NSFileWriteOutOfSpaceError, NSFileWriteVolumeReadOnlyError:
            return LocalSearchIndexStoreFailureV1.storageUnavailable
        default:
            return LocalSearchIndexStoreFailureV1.writeFailed
        }
    }

    static func mapRead(_ error: Error) -> Error {
        if error is DecodingError || error is SearchContractFailureV1 {
            return LocalSearchIndexStoreFailureV1.corruptStore
        }
        return map(error)
    }
}

extension LocalSearchIndexStoreV1 {
    /// Validates the disposable C19 row before it can be handed to the
    /// existing derived-index publisher. No measurement bytes are read or
    /// persisted by this adapter.
    static func measurementIntegritySearchRecord(
        from projection: MeasurementIntegrityReportProjectionV1,
        sourceRevision: UInt64 = 0
    ) throws -> MeasurementIntegritySearchRecordV1 {
        let record = try MeasurementIntegritySearchRecordV1(
            projection: projection,
            sourceRevision: sourceRevision
        )
        try record.validate()
        return record
    }

    static func validateMeasurementIntegritySearchRecord(
        _ record: MeasurementIntegritySearchRecordV1
    ) throws -> MeasurementIntegritySearchRecordV1 {
        try record.validate()
        return record
    }

    /// Creates the disposable C20 search row from a validated projection.
    /// This adapter stores only bounded metadata; it never reads or writes
    /// either original or derivative bytes.
    static func privacyTransformSearchRecord(
        from projection: PrivacyTransformReportProjectionV1
    ) throws -> PrivacyTransformSearchRecordV1 {
        let record = try PrivacyTransformSearchRecordV1(projection: projection)
        try record.validate()
        return record
    }

    static func validatePrivacyTransformSearchRecord(
        _ record: PrivacyTransformSearchRecordV1
    ) throws -> PrivacyTransformSearchRecordV1 {
        try record.validate()
        try PrivacyTransformSearchPersistencePolicyV1().validate()
        return record
    }

    /// Creates a disposable C21 row from the canonical local admission
    /// projection. The index receives closed values and digests only; package
    /// payloads and client/device identity never cross this boundary.
    static func clientCapabilitySearchRecord(
        from projection: ClientCapabilityReportProjectionV1
    ) throws -> ClientCapabilitySearchRecordV1 {
        let record = try ClientCapabilitySearchRecordV1(projection: projection)
        try record.validate()
        try ClientCapabilitySearchPersistencePolicyV1().validate()
        return record
    }

    static func validateClientCapabilitySearchRecord(
        _ record: ClientCapabilitySearchRecordV1
    ) throws -> ClientCapabilitySearchRecordV1 {
        try record.validate()
        try ClientCapabilitySearchPersistencePolicyV1().validate()
        return record
    }

    /// Creates a disposable C23 row from the frozen report projection. The
    /// local index receives digests and closed state values only; it never
    /// reads reference bytes, content IDs, locators, or subject identity.
    static func fieldReferenceSearchRecord(
        from projection: FieldReferenceReportProjectionV1
    ) throws -> FieldReferenceSearchRecordV1 {
        let record = try FieldReferenceSearchRecordV1(projection: projection)
        try record.validate()
        try FieldReferenceSearchPersistencePolicyV1().validate()
        return record
    }

    static func validateFieldReferenceSearchRecord(
        _ record: FieldReferenceSearchRecordV1
    ) throws -> FieldReferenceSearchRecordV1 {
        try record.validate()
        try FieldReferenceSearchPersistencePolicyV1().validate()
        return record
    }
}

// MARK: - C24 accessible-document search adapter

extension LocalSearchIndexStoreV1 {
    /// Admits only the bounded customer-safe semantic summary to the
    /// disposable local index.  The canonical tree and its evidence links
    /// remain outside this store.
    static func accessibleDocumentSearchRecord(
        from tree: AccessibleDocumentSemanticTreeV1,
        assessment: AccessibleDocumentAssessmentReceiptV1? = nil
    ) throws -> AccessibleDocumentSearchRecordV1 {
        let record = try AccessibleDocumentSearchRecordV1(
            tree: tree,
            assessment: assessment
        )
        try record.validate()
        try AccessibleDocumentSearchPersistencePolicyV1().validate()
        return record
    }

    static func validateAccessibleDocumentSearchRecord(
        _ record: AccessibleDocumentSearchRecordV1
    ) throws -> AccessibleDocumentSearchRecordV1 {
        try record.validate()
        try AccessibleDocumentSearchPersistencePolicyV1().validate()
        return record
    }
}

// MARK: - C26 guided-survey session search adapter

extension LocalSearchIndexStoreV1 {
    /// Admits only the bounded session metadata projection to the disposable
    /// local index.  The adapter never persists answer values, prompts,
    /// provisional labels, actors, evidence references, or publication bytes.
    static func surveySessionSearchRecord(
        from session: SurveySessionV1,
        publication: SurveyPublicationSnapshotV1? = nil,
        provisionalSubject: ProvisionalSubjectV1? = nil,
        factState: SurveySessionFactLocalizationStateV1? = nil,
        publicationState: SurveySessionPublicationLocalizationStateV1? = nil
    ) throws -> SurveySessionSearchRecordV1 {
        let record = try SurveySessionSearchRecordV1(
            session: session,
            publication: publication,
            provisionalSubject: provisionalSubject,
            factState: factState,
            publicationState: publicationState
        )
        try SurveySessionSearchProjectionPolicyV1.validate(record)
        try SurveySessionSearchPersistencePolicyV1().validate()
        return record
    }

    static func validateSurveySessionSearchRecord(
        _ record: SurveySessionSearchRecordV1
    ) throws -> SurveySessionSearchRecordV1 {
        try SurveySessionSearchProjectionPolicyV1.validate(record)
        try SurveySessionSearchPersistencePolicyV1().validate()
        return record
    }
}

// MARK: - C27 asset-locator search adapter

extension LocalSearchIndexStoreV1 {
    /// Converts an already validated locator report into a disposable,
    /// privacy-bounded row.  Resolution never mutates canonical locator
    /// state and this adapter never receives the opaque input bytes.
    static func assetLocatorSearchRecord(
        from projection: AssetLocatorReportProjectionV1
    ) throws -> AssetLocatorSearchRecordV1 {
        let record = try AssetLocatorSearchRecordV1(projection: projection)
        try AssetLocatorSearchProjectionPolicyV1.validate(record)
        try AssetLocatorSearchPersistencePolicyV1().validate()
        return record
    }

    static func assetLocatorSearchRecord(
        from locator: AssetLocatorV1,
        resolution: LocatorResolutionV1? = nil
    ) throws -> AssetLocatorSearchRecordV1 {
        let record = try AssetLocatorSearchRecordV1(
            locator: locator,
            resolution: resolution
        )
        try AssetLocatorSearchProjectionPolicyV1.validate(record)
        try AssetLocatorSearchPersistencePolicyV1().validate()
        return record
    }

    static func validateAssetLocatorSearchRecord(
        _ record: AssetLocatorSearchRecordV1
    ) throws -> AssetLocatorSearchRecordV1 {
        try AssetLocatorSearchProjectionPolicyV1.validate(record)
        try AssetLocatorSearchPersistencePolicyV1().validate()
        return record
    }
}

// MARK: - C28 schedule occurrence search adapter

extension LocalSearchIndexStoreV1 {
    /// Admits the bounded schedule occurrence projection to the disposable
    /// local index. The adapter intentionally has no notification, actor,
    /// draft, or work-instance inputs.
    static func scheduleOccurrenceSearchRecord(
        from projection: ScheduleReportProjectionV1,
        occurrence: ScheduleOccurrenceReportProjectionV1
    ) throws -> ScheduleOccurrenceSearchRecordV1 {
        let record = try ScheduleOccurrenceSearchRecordV1(
            projection: projection,
            occurrence: occurrence
        )
        try ScheduleOccurrenceSearchProjectionPolicyV1.validate(record)
        try ScheduleOccurrenceSearchPersistencePolicyV1().validate()
        return record
    }

    static func validateScheduleOccurrenceSearchRecord(
        _ record: ScheduleOccurrenceSearchRecordV1
    ) throws -> ScheduleOccurrenceSearchRecordV1 {
        try ScheduleOccurrenceSearchProjectionPolicyV1.validate(record)
        try ScheduleOccurrenceSearchPersistencePolicyV1().validate()
        return record
    }
}

// MARK: - C29 plan placement search adapter

extension LocalSearchIndexStoreV1 {
    /// Admits only the bounded plan placement report derivative to the local
    /// disposable index. Rebase previews and receipts remain report metadata,
    /// never searchable source or mutation input.
    static func planPlacementSearchRecord(
        from projection: PlanReportProjectionV1,
        placement: PlanPlacementReportProjectionV1
    ) throws -> PlanPlacementSearchRecordV1 {
        let record = try PlanPlacementSearchRecordV1(
            projection: projection,
            placement: placement
        )
        try PlanPlacementSearchProjectionPolicyV1.validate(record)
        try PlanPlacementSearchPersistencePolicyV1().validate()
        return record
    }

    static func validatePlanPlacementSearchRecord(
        _ record: PlanPlacementSearchRecordV1
    ) throws -> PlanPlacementSearchRecordV1 {
        try PlanPlacementSearchProjectionPolicyV1.validate(record)
        try PlanPlacementSearchPersistencePolicyV1().validate()
        return record
    }
}

// MARK: - C19 current plan-document search adapter

extension LocalSearchIndexStoreV1 {
    static func planDocumentSearchRecord(
        currentDocument: PlanDocumentV1,
        currentRevision: PlanRevisionV1,
        currentPlacementCount: Int,
        offlineReadiness: [PlanOfflineReadinessSearchMetadataV1] = [],
        workSurfaces: [PlanWorkSurfaceSearchMetadataV1] = []
    ) throws -> PlanDocumentSearchRecordV1 {
        let record = try PlanDocumentSearchRecordV1(
            currentDocument: currentDocument,
            currentRevision: currentRevision,
            currentPlacementCount: currentPlacementCount,
            offlineReadiness: offlineReadiness,
            workSurfaces: workSurfaces
        )
        try PlanDocumentSearchProjectionPolicyV1.validate(record)
        try PlanDocumentSearchPersistencePolicyV1().validate()
        return record
    }

    static func validatePlanDocumentSearchRecord(
        _ record: PlanDocumentSearchRecordV1
    ) throws -> PlanDocumentSearchRecordV1 {
        try PlanDocumentSearchProjectionPolicyV1.validate(record)
        try PlanDocumentSearchPersistencePolicyV1().validate()
        return record
    }
}

// MARK: - C37 current placement-pose search adapter

extension LocalSearchIndexStoreV1 {
    /// Admits only a current-tip pose row to the disposable local index. The
    /// immutable history remains available through the report projection and
    /// is never flattened into searchable storage.
    static func placementPoseSearchRecord(
        from projection: C37PlacementPoseReportProjectionV1,
        row: C37PoseHistoryProjectionV1
    ) throws -> C37PoseSearchRecordV1 {
        let record = try C37PoseSearchRecordV1(projection: projection, row: row)
        try C37PoseSearchProjectionPolicyV1.validate(record)
        try C37PoseSearchPersistencePolicyV1().validate()
        return record
    }

    static func validatePlacementPoseSearchRecord(
        _ record: C37PoseSearchRecordV1
    ) throws -> C37PoseSearchRecordV1 {
        try C37PoseSearchProjectionPolicyV1.validate(record)
        try C37PoseSearchPersistencePolicyV1().validate()
        return record
    }
}
// C30: this seam consumes only the frozen, metadata-only operating-context projection.
enum C30ConsumerBoundaryV1_Infrastructure_Search_LocalSearchIndexStoreV1 {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Infrastructure/Search/LocalSearchIndexStoreV1.swift", role: .search)
}

// MARK: - C31 lighting local index adapter

extension LocalSearchIndexStoreV1 {
    static func lightingSearchRecord(
        from projection: C31LightingReportProjectionV1
    ) throws -> C31LightingSearchRecordV1 {
        let record = try C31LightingSearchRecordV1(projection: projection)
        try C31LightingSearchProjectionPolicyV1.validate(record)
        try C31LightingSearchPersistencePolicyV1().validate()
        return record
    }

    static func validateLightingSearchRecord(
        _ record: C31LightingSearchRecordV1
    ) throws -> C31LightingSearchRecordV1 {
        try C31LightingSearchProjectionPolicyV1.validate(record)
        try C31LightingSearchPersistencePolicyV1().validate()
        return record
    }

    static let c31LightingIndexIsDisposableAndRebuildable = true
    static let c31LightingIndexExcludesBytesActorsAndPrivateLocators = true
}

// MARK: - C32 assistance index exclusion

enum AssistanceSearchIndexBoundaryV1 {
    /// A rebuilt index contains neither ephemeral proposals nor durable
    /// acceptance metadata. The accepted target's existing projection owner
    /// remains the only route into search.
    static func validateExcludedAssistanceRows(
        proposals: [AssistanceProposalV1],
        receipts: [AssistanceAcceptanceReceiptV1]
    ) throws {
        for proposal in proposals {
            let mayIndex = try AssistanceSearchIsolationPolicyV1.mayIndex(proposal)
            guard !mayIndex else {
                throw SearchContractFailureV1.forbiddenField
            }
        }
        for receipt in receipts {
            let mayIndex = try AssistanceSearchIsolationPolicyV1.mayIndex(receipt)
            guard !mayIndex else {
                throw SearchContractFailureV1.forbiddenField
            }
        }
    }
}


// MARK: - C33 disposable temporal evidence search adapter

extension LocalSearchIndexStoreV1 {
    nonisolated static func temporalEvidenceRecord(
        clip: TemporalEvidenceClipV1,
        anchors: [TimecodedEvidenceAnchorV1]
    ) throws -> TemporalEvidenceSearchRecordV1 {
        let record = try TemporalEvidenceSearchRecordV1(clip: clip, anchors: anchors)
        try TemporalEvidenceSearchProjectionPolicyV1.validate(record)
        return record
    }
}

enum C45AcceptedLabelIndexStoreBoundaryV1 {
    static let storesSnapshotDigest=true
    static let storesShortCode=false
    static func metadata(_ snapshot:AcceptedLabelGenerationSnapshotV1)throws->AcceptedLabelSearchMetadataV1{try .init(snapshot)}
}

enum C46OperationalContactBoundary_36{static let permittedProjection="PARTY_METADATA_ONLY";static let rawPhoneOrEmailIndexed=false}
enum C47ActivityContractLocalSearchBoundaryV2 { static let projectsCurrentEnvelopeHeads=true;static let permittedFields=["work_identifier","work_summary","status"];static let transitionReceiptAndNoPlanBytesAreExcluded=true;static let indexIsDerivedAndBackupExcluded=true }

// MARK: - C48 portable-review local search boundary

enum C48PortableReviewLocalSearchBoundaryV1 {
    static let existingIndexRemainsTheOnlySearchStore = true
    static let derivedMetadataOnly = true
    static let capabilityBytesIndexed = false
    static let capabilityProofBytesIndexed = false
    static let responseBodyIndexed = false
    static let rawRequestResponseBytesIndexed = false
    static let workspaceAndReplicaIdentityIndexed = false
    static let authorIdentityIndexed = false
    static let externalResponseCannotMutateCanonicalState = true

    static func validate(_ projection: C48PortableReviewDerivedHistoryProjectionV1) throws {
        try projection.validate()
    }
}

extension LocalSearchIndexStoreV1 {
    nonisolated static func portableReviewDerivedHistory(
        state: ReviewRequestStateProjectionV1,
        response: ExternalReviewResponseRecordV1? = nil,
        conflictCount: Int = 0
    ) throws -> C48PortableReviewDerivedHistoryProjectionV1 {
        let projection = try C48PortableReviewSearchBoundaryV1.derivedHistory(
            state: state, response: response, conflictCount: conflictCount
        )
        try C48PortableReviewLocalSearchBoundaryV1.validate(projection)
        return projection
    }
}

// MARK: - C52 lifecycle and privacy boundary
enum C52ServiceRequestBoundary_FieldEvidenceApp_Infrastructure_Search_LocalSearchIndexStoreV1_swift {
    static let acceptedCanonicalRecordPersistence: ServiceRequestPersistenceClassV1 = .canonicalPersistent
    static let acceptedEventPersistence: ServiceRequestPersistenceClassV1 = .canonicalPersistent
    static let duplicateProjectionPersistence: ServiceRequestPersistenceClassV1 = .nonpersistentDerived
    static let rawCapabilityPersistence: ServiceRequestPersistenceClassV1 = .prohibitedPersistent
    static let acceptedLifecycleEnrollment: ServiceRequestPersistenceEnrollmentV1.Type = ServiceRequestPersistenceEnrollmentV1.self
    static let cloneOrForkInvalidatesActiveCapabilities: Bool =
        ServiceRequestLifecycleRegistrationBoundaryV1.cloneOrForkInvalidatesOutstandingCapabilities
    static let duplicateProjectionIsRebuildable: Bool =
        ServiceRequestLifecycleRegistrationBoundaryV1.derivedProjectionIsRebuildable &&
        !ServiceRequestNoncanonicalBoundaryV1.duplicateProjectionIsPersistent
    static let rawCapabilityIsExcludedFromReportsAndDiagnostics: Bool =
        !ServiceRequestLifecycleRegistrationBoundaryV1.rawCapabilityAppearsInReportsOrDiagnostics
    static let sharedPortableFilesAreRecallable: Bool =
        ServiceRequestLifecycleRegistrationBoundaryV1.escapedPortableFilesCanBeRecalled
    static let unverifiedAssertionsAreVerified: Bool = false
    static let automaticWorkNetworkSLAOrAIClaimsPermitted: Bool = false
}

// MARK: - C53 service-reliability local-index boundary

enum C53ServiceReliabilityLocalSearchIndexBoundaryV1 {
    static let storeType: LocalSearchIndexStoreV1.Type = LocalSearchIndexStoreV1.self
    static let rowsAreDerivedOnly = true
    static let rowsAreDisposable = true
    static let rebuildAfterRestoreReplayDelete = true
    static let exactMetricValuesAreNotIndexed = true
    static let rawServiceReliabilityEventBytesAreNotIndexed = true

    static func record(
        _ projection: C53ServiceReliabilityReportProjectionV1
    ) throws -> C53ServiceReliabilitySearchProjectionV1 {
        try C53ServiceReliabilitySearchProjectionBoundaryV1.projection(projection)
    }

    static func serializedRecord(
        _ projection: C53ServiceReliabilityReportProjectionV1
    ) throws -> Data {
        let record = try record(projection)
        return try C53ServiceReliabilitySearchPersistenceBoundaryV1.encode(record)
    }
}

// MARK: - C57 My Day local-index boundary

enum C57MyDayLocalSearchIndexBoundaryV1 {
    static let storeType: LocalSearchIndexStoreV1.Type = LocalSearchIndexStoreV1.self
    static let rowsAreDerivedAndDisposable = true
    static let staleRowsAreDroppedNotReconciledAsTruth = true

    static func records(
        plan: MyDayPlanV1,
        readiness: MyDayReadinessProjectionV1
    ) throws -> [C57MyDaySearchRecordV1] {
        let report = try C57MyDayReportProjectionRegistryV1.projection(
            plan: plan, readiness: readiness
        )
        return try C57MyDaySearchProjectionBoundaryV1.records(from: report)
    }

    static func serializedEnvelope(
        plan: MyDayPlanV1,
        readiness: MyDayReadinessProjectionV1
    ) throws -> Data {
        let report = try C57MyDayReportProjectionRegistryV1.projection(
            plan: plan, readiness: readiness
        )
        try C57MyDaySearchPersistenceBoundaryV1.encode(
            report: report, plan: plan, readiness: readiness
        )
    }
}

// MARK: - C05 round-session local-index boundary

enum C05RoundSessionLocalSearchIndexBoundaryV1 {
    static let storeType: LocalSearchIndexStoreV1.Type = LocalSearchIndexStoreV1.self
    static let rowsAreDerivedAndDisposable = true
    static let staleRowsAreDroppedNotReconciledAsTruth = true
    static let contentReferencesActorsReasonsAndAssetLabelsIndexed = false
    static let routeDueReminderNetworkOrTeamStateIndexed = false

    static func record(
        progress: C05RoundSessionProgressReportProjectionV1,
        closeout: C05RoundSessionCloseoutReportProjectionV1?
    ) throws -> C05RoundSessionSearchProjectionV1 {
        try C05RoundSessionSearchProjectionBoundaryV1.projection(
            progress: progress,
            closeout: closeout
        )
    }

    static func serializedRecord(
        progress: C05RoundSessionProgressReportProjectionV1,
        closeout: C05RoundSessionCloseoutReportProjectionV1?
    ) throws -> Data {
        try C05RoundSessionSearchPersistenceBoundaryV1.encode(
            record(progress: progress, closeout: closeout)
        )
    }
}

/// C08 search enrollment is deliberately metadata-only.  The incumbent local
/// index owns derived storage; import source/customer columns and row bytes do
/// not cross this boundary.
enum C08ImportBulkLocalSearchIndexBoundaryV1 {
    static let storeType: LocalSearchIndexStoreV1.Type = LocalSearchIndexStoreV1.self
    static let indexesSavedMappingSessionAndReceiptMetadata = true
    static let indexesRawSourceOrCustomerFields = false
    static let rowsAreDerivedAndRebuildable = true
    static func validate() -> Bool {
        indexesSavedMappingSessionAndReceiptMetadata
            && !indexesRawSourceOrCustomerFields
            && rowsAreDerivedAndRebuildable
    }
}


/// C14 does not add rows to the incumbent file-backed search envelope. The
/// protected named index actor is the sole system-discovery store.
enum PrivateSystemDiscoveryLocalSearchBoundaryV1 {
    static let usesLocalSearchIndexStore = false
    static let usesDefaultSystemIndex = false
    static let protectedNamedIndex = PrivateSystemDiscoveryLifecycleV1.namedIndex
    static let actorType: Any.Type = PrivateSystemDiscoveryIndexStoreV1.self

    static func validate() throws {
        try PrivateSystemDiscoverySearchPersistenceBoundaryV1.validate()
        guard !usesLocalSearchIndexStore,
              !usesDefaultSystemIndex,
              protectedNamedIndex == "PRIVATE_SYSTEM_DISCOVERY_INDEX_V1" else {
            throw SearchContractFailureV1.invalidContext
        }
    }
}
enum EntityIdentityResolutionLocalSearchEnrollmentV1 {
    static let aliasAwareRebuildUsesCanonicalRows = true
    static let staleIndexRowsAreDropped = true
    static let indexOwnsIdentityTruth = false
    static let automaticAliasOrConsolidationPermitted = false
}

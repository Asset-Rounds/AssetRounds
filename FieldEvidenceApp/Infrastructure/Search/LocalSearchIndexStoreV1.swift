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
                  records.filter { $0.sourceKind == .party }.allSatisfy {
                      SearchAccountabilityPersistencePolicyV1.accepts(fieldID: $0.fieldID)
                  },
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
}

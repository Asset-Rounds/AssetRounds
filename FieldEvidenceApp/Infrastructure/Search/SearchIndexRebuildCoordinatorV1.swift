import Foundation
import SwiftData

struct SearchCanonicalProjectionPageV1: Equatable, Sendable {
    let requestedCanonicalOffset: Int
    let nextCanonicalOffset: Int
    let isComplete: Bool
    let records: [SearchIndexProjectionRecordV1]

    init(
        requestedCanonicalOffset: Int,
        nextCanonicalOffset: Int,
        isComplete: Bool,
        records: [SearchIndexProjectionRecordV1]
    ) throws {
        guard requestedCanonicalOffset >= 0,
              nextCanonicalOffset >= requestedCanonicalOffset else {
            throw SearchContractFailureV1.limitExceeded
        }
        let canonicalIdentityCount = Set(records.map {
            $0.sourceKind.rawValue + "\u{0}" + $0.sourceStableID
        }).count
        let canonicalAdvance = nextCanonicalOffset - requestedCanonicalOffset
        guard canonicalAdvance <= SearchIndexRebuildCoordinatorV1.pageSize,
              (isComplete || nextCanonicalOffset > requestedCanonicalOffset),
              (records.isEmpty || nextCanonicalOffset > requestedCanonicalOffset),
              canonicalIdentityCount <= canonicalAdvance,
              records.count <= SearchIndexRebuildCoordinatorV1.maximumProjectionRowsPerPage,
              records == records.sorted(),
              Set(records.map(\.projectionIdentity)).count == records.count else {
            throw SearchContractFailureV1.limitExceeded
        }
        self.requestedCanonicalOffset = requestedCanonicalOffset
        self.nextCanonicalOffset = nextCanonicalOffset
        self.isComplete = isComplete
        self.records = records
    }
}

/// The source must read from an immutable snapshot at the supplied revision.
/// It must fail rather than silently advance to a newer canonical commit.
protocol SearchCanonicalProjectionSourceV1: Sendable {
    func currentSearchSourceRevision() async throws -> SearchSourceRevisionV1
    func searchProjectionPage(
        at source: SearchSourceRevisionV1,
        canonicalOffset: Int,
        limit: Int
    ) async throws -> SearchCanonicalProjectionPageV1
    func discardCachedSearchProjectionSnapshot() async
}

extension SearchCanonicalProjectionSourceV1 {
    func discardCachedSearchProjectionSnapshot() async {}
}

protocol SearchOperationalStatusProvidingV1: Sendable {
    func backupStaleCanonicalIdentities(
        at source: SearchSourceRevisionV1
    ) async throws -> Set<SearchCanonicalRecordIdentityV1>
}

/// Main-actor SwiftData projection source for the active generation. Paging is
/// over canonical entities (not projection rows) and is bound to the writer's
/// exact revision before and after every fetch.
@MainActor
final class SwiftDataSearchCanonicalProjectionSourceV1: SearchCanonicalProjectionSourceV1 {
    private struct CanonicalValue {
        let kind: SearchSourceKindV1
        let stableID: String
        let display: String
        let summary: String
        let breadcrumb: [String]
        let status: String
        let dueAt: Date?
        let timestamp: Date
    }

    let registry: SearchableFieldRegistryV1
    private let modelContext: ModelContext
    private let workspaceID: UUID
    private let generationID: UUID
    private let revisionProvider: @MainActor () throws -> SearchSourceRevisionV1
    private let operationalStatusProvider: (any SearchOperationalStatusProvidingV1)?
    private var snapshotRevision: SearchSourceRevisionV1?
    private var snapshotValues: [CanonicalValue]?
    private var snapshotBackupStaleIdentities: Set<SearchCanonicalRecordIdentityV1> = []

    init(
        modelContext: ModelContext,
        workspaceID: UUID,
        generationID: UUID,
        revisionProvider: @escaping @MainActor () throws -> SearchSourceRevisionV1,
        operationalStatusProvider: (any SearchOperationalStatusProvidingV1)? = nil
    ) throws {
        guard workspaceID != SearchContractValidationV1.zeroUUID,
              generationID != SearchContractValidationV1.zeroUUID else {
            throw SearchContractFailureV1.invalidRevision
        }
        self.modelContext = modelContext
        self.workspaceID = workspaceID
        self.generationID = generationID
        self.revisionProvider = revisionProvider
        self.operationalStatusProvider = operationalStatusProvider
        registry = try Self.makeRegistry()
    }

    func currentSearchSourceRevision() async throws -> SearchSourceRevisionV1 {
        try validatedCurrentRevision()
    }

    func discardCachedSearchProjectionSnapshot() async {
        snapshotRevision = nil
        snapshotValues = nil
        snapshotBackupStaleIdentities = []
    }

    func searchProjectionPage(
        at source: SearchSourceRevisionV1,
        canonicalOffset: Int,
        limit: Int
    ) async throws -> SearchCanonicalProjectionPageV1 {
        try Task.checkCancellation()
        guard source == (try validatedCurrentRevision()),
              canonicalOffset >= 0,
              limit > 0,
              limit <= SearchIndexRebuildCoordinatorV1.pageSize else {
            throw SearchIndexRebuildFailureV1.sourceChangedDuringRebuild
        }
        let canonical = try await canonicalValues(at: source)
        guard canonical.count <= SearchContractLimitsV1.maximumCanonicalRecords,
              canonicalOffset <= canonical.count else {
            throw SearchIndexRebuildFailureV1.recordLimitExceeded
        }
        let end = min(canonical.count, canonicalOffset + limit)
        var records: [SearchIndexProjectionRecordV1] = []
        for (index, value) in canonical[canonicalOffset..<end].enumerated() {
            if index.isMultiple(of: 64) { try Task.checkCancellation() }
            records.append(contentsOf: try project(value, source: source))
        }
        try Task.checkCancellation()
        guard source == (try validatedCurrentRevision()) else {
            throw SearchIndexRebuildFailureV1.sourceChangedDuringRebuild
        }
        let page = try SearchCanonicalProjectionPageV1(
            requestedCanonicalOffset: canonicalOffset,
            nextCanonicalOffset: end,
            isComplete: end == canonical.count,
            records: records.sorted()
        )
        if page.isComplete {
            snapshotRevision = nil
            snapshotValues = nil
            snapshotBackupStaleIdentities = []
        }
        return page
    }
}

@MainActor
private extension SwiftDataSearchCanonicalProjectionSourceV1 {
    func validatedCurrentRevision() throws -> SearchSourceRevisionV1 {
        let revision = try revisionProvider()
        guard revision.workspaceID == workspaceID,
              revision.generationID == generationID else {
            throw SearchContractFailureV1.invalidRevision
        }
        if let snapshotRevision, snapshotRevision != revision {
            self.snapshotRevision = nil
            snapshotValues = nil
            snapshotBackupStaleIdentities = []
        }
        return revision
    }

    func canonicalValues(at source: SearchSourceRevisionV1) async throws -> [CanonicalValue] {
        if snapshotRevision == source, let snapshotValues { return snapshotValues }
        var values: [CanonicalValue] = []
        values += try modelContext.fetch(FetchDescriptor<Asset>()).map {
            CanonicalValue(kind: .asset, stableID: try stableKey(kind: .asset, id: $0.id),
                display: $0.label, summary: $0.label, breadcrumb: [], status: "active",
                dueAt: nil, timestamp: $0.updatedAt)
        }
        values += try modelContext.fetch(FetchDescriptor<Site>()).map {
            CanonicalValue(kind: .location, stableID: try stableKey(kind: .site, id: $0.id),
                display: $0.label, summary: $0.address ?? $0.label,
                breadcrumb: [$0.label], status: "active", dueAt: nil, timestamp: $0.updatedAt)
        }
        values += try modelContext.fetch(FetchDescriptor<LocationNodeRow>())
            .filter { $0.workspaceID == workspaceID }
            .map {
                CanonicalValue(kind: .location, stableID: try stableKey(kind: .locationNode, id: $0.id),
                    display: $0.label, summary: $0.shortCode ?? $0.label,
                    breadcrumb: [$0.label], status: $0.state, dueAt: nil, timestamp: $0.occurredAt)
            }
        values += try modelContext.fetch(FetchDescriptor<WorkflowRecord>()).map {
            let summary = $0.workDescription ?? $0.note ?? $0.outcomeKey ?? $0.stage
            return CanonicalValue(kind: .work, stableID: try stableKey(kind: .workflowRecord, id: $0.id),
                display: summary, summary: summary, breadcrumb: [], status: $0.state,
                dueAt: nil, timestamp: $0.completedAt ?? $0.startedAt)
        }
        values += try modelContext.fetch(FetchDescriptor<Issue>()).map {
            CanonicalValue(kind: .work, stableID: try stableKey(kind: .issue, id: $0.id),
                display: $0.labelDisplaySnapshot, summary: $0.labelDisplaySnapshot,
                breadcrumb: [], status: $0.status, dueAt: $0.updatedAt,
                timestamp: $0.updatedAt)
        }
        values += try modelContext.fetch(FetchDescriptor<Report>()).map {
            let display = "Report \($0.id.uuidString.lowercased())"
            return CanonicalValue(kind: .report, stableID: try stableKey(kind: .report, id: $0.id),
                display: display, summary: display, breadcrumb: [], status: $0.pdfState,
                dueAt: nil, timestamp: $0.createdAt)
        }
        guard values.count <= SearchContractLimitsV1.maximumCanonicalRecords else {
            throw SearchIndexRebuildFailureV1.recordLimitExceeded
        }
        let identities = values.map { $0.kind.rawValue + "\u{0}" + $0.stableID }
        guard Set(identities).count == identities.count else {
            throw SearchContractFailureV1.duplicateProjection
        }
        values.sort {
            if $0.kind != $1.kind { return $0.kind.rawValue < $1.kind.rawValue }
            return $0.stableID < $1.stableID
        }
        guard source == (try validatedCurrentRevision()) else {
            throw SearchIndexRebuildFailureV1.sourceChangedDuringRebuild
        }
        let staleIdentities = try await operationalStatusProvider?
            .backupStaleCanonicalIdentities(at: source) ?? []
        var knownIdentities = Set<SearchCanonicalRecordIdentityV1>()
        for value in values {
            knownIdentities.insert(try SearchCanonicalRecordIdentityV1(
                sourceKind: value.kind,
                stableID: value.stableID
            ))
        }
        guard staleIdentities.isSubset(of: knownIdentities) else {
            throw SearchContractFailureV1.invalidContext
        }
        guard source == (try validatedCurrentRevision()) else {
            throw SearchIndexRebuildFailureV1.sourceChangedDuringRebuild
        }
        snapshotRevision = source
        snapshotValues = values
        snapshotBackupStaleIdentities = staleIdentities
        return values
    }

    func stableKey(kind: WorkspaceEntityKindV1, id: UUID) throws -> String {
        try WorkspaceEntityIdentityV1(kind: kind, id: id).stableKey
    }

    func project(
        _ value: CanonicalValue,
        source: SearchSourceRevisionV1
    ) throws -> [SearchIndexProjectionRecordV1] {
        let fields: [(String, String)]
        switch value.kind {
        case .asset:
            fields = [("asset_identifier", value.stableID), ("asset_label", value.display),
                      ("status", value.status)]
        case .location:
            fields = [("location_identifier", value.stableID), ("location_label", value.display),
                      ("location_breadcrumb", value.breadcrumb.joined(separator: " ")),
                      ("status", value.status)]
        case .work:
            fields = [("work_identifier", value.stableID), ("work_summary", value.summary),
                      ("status", value.status)]
        case .report:
            fields = [("report_identifier", value.stableID), ("report_summary", value.summary),
                      ("status", value.status)]
        }
        return try fields.map { fieldID, text in
            let searchable = text.isEmpty ? value.stableID : text
            let identity = try SearchCanonicalRecordIdentityV1(
                sourceKind: value.kind,
                stableID: value.stableID
            )
            let operationalSuffix = fieldID == "status"
                && snapshotBackupStaleIdentities.contains(identity)
                ? " backup stale" : ""
            return try SearchIndexProjectionRecordV1(
                workspaceID: workspaceID,
                sourceKind: value.kind,
                sourceStableID: value.stableID,
                sourceRevision: source.commitRevision,
                fieldID: fieldID,
                normalizedTokens: SearchCoordinatorV1.normalizedTokens(
                    searchable + operationalSuffix
                ),
                displayIdentity: value.display,
                locationBreadcrumb: value.breadcrumb,
                status: value.status,
                permittedSnippet: searchable,
                dueAt: value.dueAt,
                sourceTimestamp: value.timestamp
            )
        }
    }

    static func makeRegistry() throws -> SearchableFieldRegistryV1 {
        var fields: [SearchableFieldDescriptorV1] = []
        func append(_ id: String, _ kind: SearchSourceKindV1, identity: Bool = false,
                    operational: Bool = false) throws {
            fields.append(try SearchableFieldDescriptorV1(
                fieldID: id, sourceKind: kind,
                privacyClass: identity ? .userVisibleIdentifier
                    : (operational ? .approvedOperationalState : .approvedCustomerText),
                tokenization: identity ? .exactIdentity : (operational ? .keyword : .unicodeWords),
                normalization: identity ? .stableIdentity : .unicodeCaseAndDiacriticFoldedNFC,
                snippetPermission: (identity || operational)
                    ? .exactDisplayValue : .boundedUserVisibleExcerpt,
                retention: .untilSourceFieldIsAmended, purgeOwner: .indexRebuildCoordinator
            ))
        }
        try append("asset_identifier", .asset, identity: true); try append("asset_label", .asset)
        try append("location_identifier", .location, identity: true); try append("location_label", .location)
        try append("location_breadcrumb", .location)
        try append("work_identifier", .work, identity: true); try append("work_summary", .work)
        try append("report_identifier", .report, identity: true); try append("report_summary", .report)
        for kind in SearchSourceKindV1.allCases { try append("status", kind, operational: true) }
        return try SearchableFieldRegistryV1(fields: fields)
    }
}

enum SearchIndexRebuildFailureV1: Error, Equatable, Sendable {
    case sourceChangedDuringRebuild
    case invalidPage
    case recordLimitExceeded
}

struct SearchIndexRebuildResultV1: Equatable, Sendable {
    let disposition: SearchIndexReconciliationV1
    let source: SearchSourceRevisionV1
    let indexedRecordCount: Int
    let resumedFromCheckpoint: Bool
}

/// Rebuilds into durable staging pages and publishes only after the source
/// revision is re-read and proven unchanged. Cancellation retains the last
/// complete checkpoint; storage failures never replace a complete index.
actor SearchIndexRebuildCoordinatorV1 {
    static let pageSize = 250
    static let maximumCanonicalRecords = SearchContractLimitsV1.maximumCanonicalRecords
    static let maximumProjectionRowsPerPage = pageSize
        * SearchContractLimitsV1.exactSearchableFieldCount

    private let store: LocalSearchIndexStoreV1
    private let source: any SearchCanonicalProjectionSourceV1
    private let registry: SearchableFieldRegistryV1
    private let makeOperationID: @Sendable () -> UUID

    init(
        store: LocalSearchIndexStoreV1,
        source: any SearchCanonicalProjectionSourceV1,
        registry: SearchableFieldRegistryV1,
        makeOperationID: @escaping @Sendable () -> UUID = { UUID() }
    ) throws {
        try registry.validate()
        self.store = store
        self.source = source
        self.registry = registry
        self.makeOperationID = makeOperationID
    }

    func rebuildIfNeeded() async throws -> SearchIndexRebuildResultV1 {
        do {
            return try await performRebuildIfNeeded()
        } catch {
            await source.discardCachedSearchProjectionSnapshot()
            throw error
        }
    }

    private func performRebuildIfNeeded() async throws -> SearchIndexRebuildResultV1 {
        try Task.checkCancellation()
        let target = try await source.currentSearchSourceRevision()
        let existingRevision = try await store.revision()
        let disposition = SearchIndexReconciliationV1.disposition(
            source: target,
            index: existingRevision
        )
        if disposition == .current {
            let projection = try await store.projection(for: target, registry: registry)
            return SearchIndexRebuildResultV1(
                disposition: disposition,
                source: target,
                indexedRecordCount: projection.records.count,
                resumedFromCheckpoint: false
            )
        }

        switch disposition {
        case .staleDropAndRebuild, .aheadDropAndRebuild,
             .incompatibleFormatDropAndRebuild, .wrongGenerationDropAndRebuild:
            // A complete projection that is not current must not survive into
            // publication. In particular, an ahead watermark would otherwise
            // cause replaceProjection to reject the revision-bound rebuild.
            try await store.dropProjection()
        case .absentBuild:
            break
        case .current:
            preconditionFailure("Handled above")
        }
        let publicationToken = await store.publicationToken()

        var staging = try await store.rebuildStaging(publicationToken: publicationToken)
        let canResume = staging.map {
            $0.checkpoint.source == target
                && $0.checkpoint.projectionFormatVersion
                    == SearchPersistenceReleaseV1.derivedProjectionFormatVersion
                && $0.checkpoint.state == .building
        } ?? false
        if !canResume {
            if staging != nil {
                try await store.clearRebuildStaging(
                    publicationToken: publicationToken
                )
            }
            let operationID = makeOperationID()
            guard operationID != SearchContractValidationV1.zeroUUID else {
                throw SearchContractFailureV1.invalidRevision
            }
            let checkpoint = try SearchIndexRebuildCheckpointV1(
                operationID: operationID,
                source: target,
                nextCanonicalOffset: 0,
                projectedRecordCount: 0,
                state: .building
            )
            try await store.saveRebuildStaging(
                checkpoint: checkpoint,
                records: [],
                registry: registry,
                publicationToken: publicationToken
            )
            staging = SearchIndexRebuildStagingV1(checkpoint: checkpoint, records: [])
        }

        guard var active = staging else { throw SearchIndexRebuildFailureV1.invalidPage }
        let resumed = canResume && active.checkpoint.nextCanonicalOffset > 0
        var records = active.records
        var offset = active.checkpoint.nextCanonicalOffset
        var isComplete = false

        while !isComplete {
            try Task.checkCancellation()
            let page = try await source.searchProjectionPage(
                at: target,
                canonicalOffset: offset,
                limit: Self.pageSize
            )
            guard page.requestedCanonicalOffset == offset,
                  page.nextCanonicalOffset >= offset,
                  page.nextCanonicalOffset - offset <= Self.pageSize,
                  (page.records.isEmpty || page.nextCanonicalOffset > offset),
                  (page.isComplete || page.nextCanonicalOffset > offset),
                  page.nextCanonicalOffset <= Self.maximumCanonicalRecords,
                  page.records.allSatisfy({
                    $0.workspaceID == target.workspaceID
                        && $0.sourceRevision <= target.commitRevision
                  }) else {
                throw SearchIndexRebuildFailureV1.invalidPage
            }
            let projectionRowCapacity = Self.maximumCanonicalRecords
                * SearchContractLimitsV1.exactSearchableFieldCount
            if records.count + page.records.count > projectionRowCapacity {
                throw SearchIndexRebuildFailureV1.recordLimitExceeded
            }

            records.append(contentsOf: page.records)
            records = try SearchIndexProjectionRecordV1.validateProjection(records, against: registry)
            offset = page.nextCanonicalOffset
            isComplete = page.isComplete
            let checkpoint = try SearchIndexRebuildCheckpointV1(
                operationID: active.checkpoint.operationID,
                source: target,
                nextCanonicalOffset: offset,
                projectedRecordCount: records.count,
                state: .building
            )
            try await store.saveRebuildStaging(
                checkpoint: checkpoint,
                records: records,
                registry: registry,
                publicationToken: publicationToken
            )
            active = SearchIndexRebuildStagingV1(checkpoint: checkpoint, records: records)
        }

        try Task.checkCancellation()
        let finalSource = try await source.currentSearchSourceRevision()
        guard finalSource == target else {
            throw SearchIndexRebuildFailureV1.sourceChangedDuringRebuild
        }
        try Task.checkCancellation()
        try await store.replaceProjection(
            source: target,
            records: records,
            registry: registry,
            publicationToken: publicationToken
        )
        return SearchIndexRebuildResultV1(
            disposition: disposition,
            source: target,
            indexedRecordCount: records.count,
            resumedFromCheckpoint: resumed
        )
    }

    func cancelAndRetainCheckpoint() {
        // Cooperative cancellation belongs to the calling Task. Staging is
        // already durable after every page, so no write is required here.
    }

    func dropAndRebuild() async throws -> SearchIndexRebuildResultV1 {
        try await store.dropProjection()
        return try await rebuildIfNeeded()
    }

    func purgeWorkspace(_ workspaceID: UUID) async throws {
        try await store.purgeWorkspace(workspaceID)
    }

    func eraseAll() async throws {
        try await store.eraseAll()
    }
}

@MainActor
struct ProductionSearchServicesV1 {
    let source: SwiftDataSearchCanonicalProjectionSourceV1
    let registry: SearchableFieldRegistryV1
    let searchCoordinator: SearchCoordinatorV1
    let rebuildCoordinator: SearchIndexRebuildCoordinatorV1

    init(
        store: LocalSearchIndexStoreV1,
        modelContext: ModelContext,
        workspaceID: UUID,
        generationID: UUID,
        revisionProvider: @escaping @MainActor () throws -> SearchSourceRevisionV1,
        operationalStatusProvider: (any SearchOperationalStatusProvidingV1)? = nil
    ) throws {
        let source = try SwiftDataSearchCanonicalProjectionSourceV1(
            modelContext: modelContext,
            workspaceID: workspaceID,
            generationID: generationID,
            revisionProvider: revisionProvider,
            operationalStatusProvider: operationalStatusProvider
        )
        self.source = source
        registry = source.registry
        searchCoordinator = SearchCoordinatorV1(index: store)
        rebuildCoordinator = try SearchIndexRebuildCoordinatorV1(
            store: store,
            source: source,
            registry: source.registry
        )
    }
}

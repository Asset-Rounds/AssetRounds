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

private struct AuthorityCriterionClassificationChainKeyV1: Hashable {
    let activityID: UUID
    let findingID: UUID
    let criterionID: String
}

private struct AuthorityCriterionClassificationSearchRecordV1 {
    let value: FindingClassificationBindingV1
    let activityID: UUID
}

/// Resolves an append-only predecessor chain to exactly one current head for
/// every logical group. A search rebuild must not choose a newest row, merge
/// forks, or silently bridge a chain into another workspace/group.
private func authorityCriterionUniqueHeadsV1<Value, Group: Hashable>(
    values: [Value],
    expectedWorkspace: WorkspaceID,
    id: (Value) -> UUID,
    workspace: (Value) -> WorkspaceID,
    predecessor: (Value) -> UUID?,
    group: (Value) -> Group
) throws -> [Value] {
    var byID: [UUID: Value] = [:]
    for value in values {
        let valueID = id(value)
        guard valueID != SearchContractValidationV1.zeroUUID,
              workspace(value) == expectedWorkspace,
              byID[valueID] == nil else {
            throw SearchContractFailureV1.invalidContext
        }
        byID[valueID] = value
    }

    var childCounts: [UUID: Int] = [:]
    for value in values {
        guard let predecessorID = predecessor(value) else { continue }
        guard predecessorID != id(value),
              let parent = byID[predecessorID],
              workspace(parent) == expectedWorkspace,
              group(parent) == group(value) else {
            throw SearchContractFailureV1.invalidContext
        }
        childCounts[predecessorID, default: 0] += 1
        guard childCounts[predecessorID] == 1 else {
            throw SearchContractFailureV1.invalidContext
        }
    }

    // A cycle has no head, so detect it explicitly rather than allowing a
    // cyclic group to disappear behind an empty head set.
    for value in values {
        var visited: Set<UUID> = []
        var cursor = value
        while let predecessorID = predecessor(cursor) {
            let cursorID = id(cursor)
            guard visited.insert(cursorID).inserted,
                  predecessorID != cursorID,
                  let parent = byID[predecessorID],
                  workspace(parent) == expectedWorkspace,
                  group(parent) == group(cursor) else {
                throw SearchContractFailureV1.invalidContext
            }
            cursor = parent
        }
    }

    var headsByGroup: [Group: [Value]] = [:]
    for value in values where childCounts[id(value), default: 0] == 0 {
        headsByGroup[group(value), default: []].append(value)
    }
    guard headsByGroup.count == Set(values.map(group)).count,
          headsByGroup.values.allSatisfy({ $0.count == 1 }) else {
        throw SearchContractFailureV1.invalidContext
    }
    return headsByGroup.values.compactMap { $0.first }
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
        /// Role history is intentionally a bounded, non-contact summary.  It
        /// is only populated for the additive C38 party projection.
        let roleSummary: String = ""
        /// C39 fields contain stable semantic labels and recorded states only;
        /// raw product identifier values never enter the disposable index.
        let semanticKindSummary: String = ""
        let semanticCapabilitySummary: String = ""
        let lifecycleEventSummary: String = ""
        let productIdentityStateSummary: String = ""
        let workSubjectScopeSummary: String = ""
        let authoritySourceSummary: String = ""
        let applicabilityDispositionSummary: String = ""
        let criterionResultSummary: String = ""
        let severityLevelSummary: String = ""
        let measurementProtocolSummary: String = ""
        /// C41 fields are restricted to descriptor and current-head facts.
        /// Relationship history, actors, locators, and topology internals
        /// never enter the disposable index.
        let functionalRelationshipDescriptorSummary: String = ""
        let functionalRelationshipDirectionSummary: String = ""
        let functionalRelationshipStateSummary: String = ""
        let functionalRelationshipEndpointSummary: String = ""
    }

    let registry: SearchableFieldRegistryV1
    private let modelContext: ModelContext
    private let workspaceID: UUID
    private let generationID: UUID
    private let revisionProvider: @MainActor () throws -> SearchSourceRevisionV1
    private let operationalStatusProvider: (any SearchOperationalStatusProvidingV1)?
    private let includeAccountability: Bool
    private let includeAssetSemantics: Bool
    private let includeAuthorityCriterion: Bool
    private let includeFunctionalRelationships: Bool
    private var snapshotRevision: SearchSourceRevisionV1?
    private var snapshotValues: [CanonicalValue]?
    private var snapshotBackupStaleIdentities: Set<SearchCanonicalRecordIdentityV1> = []

    init(
        modelContext: ModelContext,
        workspaceID: UUID,
        generationID: UUID,
        revisionProvider: @escaping @MainActor () throws -> SearchSourceRevisionV1,
        operationalStatusProvider: (any SearchOperationalStatusProvidingV1)? = nil,
        includeAccountability: Bool = false,
        includeAssetSemantics: Bool = false,
        includeAuthorityCriterion: Bool = false,
        includeFunctionalRelationships: Bool = false
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
        self.includeAccountability = includeAccountability
        self.includeAssetSemantics = includeAssetSemantics
        self.includeAuthorityCriterion = includeAuthorityCriterion
        self.includeFunctionalRelationships = includeFunctionalRelationships
        registry = try Self.makeExtendedRegistry(
            includeAccountability: includeAccountability,
            includeAssetSemantics: includeAssetSemantics,
            includeAuthorityCriterion: includeAuthorityCriterion,
            includeFunctionalRelationships: includeFunctionalRelationships
        )
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
        let semanticByAsset = includeAssetSemantics
            ? try assetSemanticSearchValues()
            : [:]
        let authorityByActivity = includeAuthorityCriterion
            ? try authorityCriterionSearchValues()
            : [:]
        let functionalRelationshipValues = includeFunctionalRelationships
            ? try functionalRelationshipSearchValues()
            : []
        values += try modelContext.fetch(FetchDescriptor<Asset>()).map {
            let semantic = semanticByAsset[$0.id]
            return CanonicalValue(kind: .asset, stableID: try stableKey(kind: .asset, id: $0.id),
                display: $0.label, summary: $0.label, breadcrumb: [], status: "active",
                dueAt: nil, timestamp: $0.updatedAt,
                semanticKindSummary: semantic?.kind ?? "",
                semanticCapabilitySummary: semantic?.capability ?? "",
                lifecycleEventSummary: semantic?.lifecycle ?? "",
                productIdentityStateSummary: semantic?.productState ?? "",
                workSubjectScopeSummary: semantic?.scope ?? "")
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
            let authority = authorityByActivity[$0.id]
            return CanonicalValue(kind: .work, stableID: try stableKey(kind: .workflowRecord, id: $0.id),
                display: summary, summary: summary, breadcrumb: [], status: $0.state,
                dueAt: nil, timestamp: $0.completedAt ?? $0.startedAt,
                authoritySourceSummary: authority?.sources.sorted().joined(separator: " ") ?? "",
                applicabilityDispositionSummary: authority?.dispositions.sorted().joined(separator: " ") ?? "",
                criterionResultSummary: authority?.results.sorted().joined(separator: " ") ?? "",
                severityLevelSummary: authority?.severityLevels.sorted().joined(separator: " ") ?? "",
                measurementProtocolSummary: authority?.measurementProtocols.sorted().joined(separator: " ") ?? "")
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
        values += functionalRelationshipValues
        if includeAccountability {
            var rolesByParty: [UUID: Set<String>] = [:]
            let roleRows = try modelContext.fetch(FetchDescriptor<SitePartyRoleEventRow>())
                .filter { $0.workspaceID == workspaceID }
            for row in roleRows {
                let event = try row.value()
                rolesByParty[event.partyID, default: []].insert(event.role.rawValue)
            }
            values += try modelContext.fetch(FetchDescriptor<ServicePartyRow>())
                .filter { $0.workspaceID == workspaceID }
                .map { row in
                    let party = try row.value()
                    let roles = (rolesByParty[party.partyID] ?? []).sorted()
                    return CanonicalValue(
                        kind: .party,
                        stableID: try stableKey(kind: .serviceParty, id: party.partyID),
                        display: party.displayName,
                        summary: party.profileDescriptor ?? party.displayName,
                        breadcrumb: [],
                        status: party.state.rawValue,
                        dueAt: party.retiredAt,
                        timestamp: party.effectiveAt,
                        roleSummary: roles.isEmpty ? "NO_ROLE_RECORDED" : roles.joined(separator: " ")
                    )
                }
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

    private struct AssetSemanticSearchValue {
        var kinds: Set<String> = []
        var capabilities: Set<String> = []
        var lifecycleEvents: Set<String> = []
        var productStates: Set<String> = []
        var scopes: Set<String> = []

        var kind: String { kinds.sorted().joined(separator: " ") }
        var capability: String { capabilities.sorted().joined(separator: " ") }
        var lifecycle: String { lifecycleEvents.sorted().joined(separator: " ") }
        var productState: String { productStates.sorted().joined(separator: " ") }
        var scope: String { scopes.sorted().joined(separator: " ") }
    }

    func assetSemanticSearchValues() throws -> [UUID: AssetSemanticSearchValue] {
        var result: [UUID: AssetSemanticSearchValue] = [:]
        for row in try modelContext.fetch(FetchDescriptor<AssetKindBindingEventRow>())
            where row.workspaceID == workspaceID {
            let value = try row.value()
            var entry = result[value.assetID] ?? AssetSemanticSearchValue()
            entry.kinds.insert(value.semanticID)
            result[value.assetID] = entry
        }
        for row in try modelContext.fetch(FetchDescriptor<AssetWorkflowCapabilityBindingEventRow>())
            where row.workspaceID == workspaceID {
            let value = try row.value()
            var entry = result[value.assetID] ?? AssetSemanticSearchValue()
            entry.capabilities.formUnion(value.capabilityIDs.map(\.rawValue))
            result[value.assetID] = entry
        }
        for row in try modelContext.fetch(FetchDescriptor<AssetProductIdentityRow>())
            where row.workspaceID == workspaceID {
            let value = try row.value()
            var entry = result[value.assetID] ?? AssetSemanticSearchValue()
            entry.productStates.formUnion(value.identifiers.map { $0.reviewState.rawValue })
            result[value.assetID] = entry
        }
        for row in try modelContext.fetch(FetchDescriptor<AssetLifecycleEventRow>())
            where row.workspaceID == workspaceID {
            let value = try row.value()
            var entry = result[value.record.assetID] ?? AssetSemanticSearchValue()
            entry.lifecycleEvents.insert(value.kind.rawValue)
            result[value.record.assetID] = entry
        }
        for row in try modelContext.fetch(FetchDescriptor<WorkSubjectScopeSnapshotRow>())
            where row.workspaceID == workspaceID {
            let value = try row.value()
            for subject in value.subjects {
                let assetID = subject.kind == .asset ? subject.subjectID : subject.ownerAssetID
                guard let assetID else { continue }
                var entry = result[assetID] ?? AssetSemanticSearchValue()
                entry.scopes.insert(subject.kind.rawValue)
                result[assetID] = entry
            }
            for semanticBinding in value.semanticBindings {
                var entry = result[semanticBinding.assetID] ?? AssetSemanticSearchValue()
                entry.kinds.insert(semanticBinding.semanticID)
                result[semanticBinding.assetID] = entry
            }
        }
        return result
    }

    private struct AuthorityCriterionSearchValue {
        var sources: Set<String> = []
        var dispositions: Set<String> = []
        var results: Set<String> = []
        var severityLevels: Set<String> = []
        var measurementProtocols: Set<String> = []
    }

    /// Reads only descriptor releases and the one current head selected by the
    /// canonical C41 projection builder. Any orphan, fork, cycle, unknown
    /// descriptor, or invalid transition fails the rebuild rather than being
    /// silently indexed.
    func functionalRelationshipSearchValues() throws -> [CanonicalValue] {
        let expectedWorkspace = WorkspaceID(rawValue: workspaceID)
        let descriptorRows = try modelContext.fetch(
            FetchDescriptor<FunctionalRelationshipTypeDescriptorRow>()
        ).filter { $0.workspaceID == workspaceID }
        let descriptors = try descriptorRows.map { try $0.value() }
        var descriptorByID: [UUID: FunctionalRelationshipTypeDescriptorV1] = [:]
        for descriptor in descriptors {
            guard descriptor.workspaceID == expectedWorkspace,
                  descriptorByID[descriptor.descriptorReleaseID] == nil else {
                throw SearchContractFailureV1.invalidContext
            }
            descriptorByID[descriptor.descriptorReleaseID] = descriptor
        }
        let eventRows = try modelContext.fetch(
            FetchDescriptor<AssetFunctionalRelationshipEventRow>()
        ).filter { $0.workspaceID == workspaceID }
        let events = try eventRows.map { try $0.value() }
        let current = try FunctionalRelationshipProjectionBuilderV1.rebuild(
            workspaceID: expectedWorkspace,
            events: events,
            descriptors: descriptors
        ).currentRelationships

        // Placement history is canonical context, never indexed content. When
        // both endpoints have a current placement, same-site descriptors must
        // agree with it; a cross-site row is rejected instead of becoming a
        // misleading search hit. Missing placement is left unresolved for a
        // descriptor that explicitly permits cross-site local associations.
        let placementValues = try modelContext.fetch(
            FetchDescriptor<AssetPlacementEventRow>()
        ).filter { $0.workspaceID == workspaceID }.map { try $0.value() }
        let currentPlacements = try authorityCriterionUniqueHeadsV1(
            values: placementValues,
            expectedWorkspace: expectedWorkspace,
            id: { $0.id },
            workspace: { $0.workspaceID },
            predecessor: { $0.predecessorEventID },
            group: { $0.assetID }
        )
        let siteByAsset = Dictionary(uniqueKeysWithValues: currentPlacements.map {
            ($0.assetID, $0.siteID)
        })
        for event in current {
            guard let descriptor = descriptorByID[event.descriptor.descriptorReleaseID] else {
                throw SearchContractFailureV1.invalidContext
            }
            if descriptor.sitePolicy == .sameSiteRequired,
               let sourceSite = siteByAsset[event.sourceAssetID],
               let targetSite = siteByAsset[event.targetAssetID],
               sourceSite != targetSite {
                throw SearchContractFailureV1.invalidContext
            }
        }

        var values: [CanonicalValue] = []
        for descriptor in descriptors.sorted(by: {
            ($0.semanticID, $0.descriptorReleaseID.uuidString)
                < ($1.semanticID, $1.descriptorReleaseID.uuidString)
        }) {
            values.append(CanonicalValue(
                kind: .asset,
                stableID: "functional-descriptor-\(descriptor.descriptorReleaseID.uuidString.lowercased())",
                display: descriptor.semanticID,
                summary: descriptor.semanticID,
                breadcrumb: [],
                status: "descriptor",
                dueAt: nil,
                timestamp: descriptor.releasedAt,
                functionalRelationshipDescriptorSummary: descriptor.semanticID,
                functionalRelationshipDirectionSummary: descriptor.direction.rawValue,
                functionalRelationshipStateSummary: "DESCRIPTOR",
                functionalRelationshipEndpointSummary: ""
            ))
        }
        for event in current.sorted(by: {
            ($0.relationshipID.uuidString, $0.revision)
                < ($1.relationshipID.uuidString, $1.revision)
        }) {
            guard let descriptor = descriptorByID[event.descriptor.descriptorReleaseID],
                  descriptor.descriptorSHA256 == event.descriptor.descriptorSHA256 else {
                throw SearchContractFailureV1.invalidContext
            }
            let state = event.action == .superseded ? "SUPERSEDED" : "ACTIVE"
            values.append(CanonicalValue(
                kind: .asset,
                stableID: "functional-relationship-\(event.relationshipID.uuidString.lowercased())",
                display: descriptor.semanticID,
                summary: descriptor.semanticID,
                breadcrumb: [],
                status: state.lowercased(),
                dueAt: nil,
                timestamp: event.recordedAt,
                functionalRelationshipDescriptorSummary: descriptor.semanticID,
                functionalRelationshipDirectionSummary: descriptor.direction.rawValue,
                functionalRelationshipStateSummary: state,
                functionalRelationshipEndpointSummary: "\(event.sourceAssetID.uuidString.lowercased()) \(event.targetAssetID.uuidString.lowercased())"
            ))
        }
        return values
    }

    /// Builds only exact activity-bound summaries. Licensed content, clause/raw
    /// locators, external locator values, and derived facts without an explicit
    /// activity reference are intentionally excluded.
    func authorityCriterionSearchValues() throws -> [UUID: AuthorityCriterionSearchValue] {
        let expectedWorkspace = WorkspaceID(rawValue: workspaceID)
        let releases = try modelContext.fetch(FetchDescriptor<AuthoritySourceReleaseRow>())
            .filter { $0.workspaceID == workspaceID }.map { try $0.value() }
        var releaseByID: [UUID: AuthoritySourceReleaseV1] = [:]
        for release in releases {
            guard release.workspaceID == expectedWorkspace,
                  releaseByID[release.releaseID] == nil else {
                throw SearchContractFailureV1.invalidContext
            }
            releaseByID[release.releaseID] = release
        }

        let contexts = try modelContext.fetch(FetchDescriptor<ApplicabilityContextSnapshotRow>())
            .filter { $0.workspaceID == workspaceID }.map { try $0.value() }
        var contextByID: [UUID: ApplicabilityContextSnapshotV1] = [:]
        for context in contexts {
            guard context.workspaceID == expectedWorkspace,
                  contextByID[context.snapshotID] == nil else {
                throw SearchContractFailureV1.invalidContext
            }
            contextByID[context.snapshotID] = context
            for basis in context.basisBindings {
                guard basis.workspaceID == expectedWorkspace,
                      let release = releaseByID[basis.authorityReleaseID],
                      release.workspaceID == expectedWorkspace else {
                    throw SearchContractFailureV1.invalidContext
                }
            }
        }
        let currentContexts = try authorityCriterionUniqueHeadsV1(
            values: contexts,
            expectedWorkspace: expectedWorkspace,
            id: { $0.snapshotID },
            workspace: { $0.workspaceID },
            predecessor: { $0.supersedesSnapshotID },
            group: { $0.activityID }
        )
        var currentContextByID: [UUID: ApplicabilityContextSnapshotV1] = [:]
        for context in currentContexts {
            guard currentContextByID[context.snapshotID] == nil else {
                throw SearchContractFailureV1.invalidContext
            }
            currentContextByID[context.snapshotID] = context
        }

        let classifications = try modelContext.fetch(FetchDescriptor<FindingClassificationBindingRow>())
            .filter { $0.workspaceID == workspaceID }.map { try $0.value() }
        var classificationRecords: [AuthorityCriterionClassificationSearchRecordV1] = []
        for classification in classifications {
            guard classification.workspaceID == expectedWorkspace,
                  let context = contextByID[classification.applicabilityContextID],
                  context.workspaceID == expectedWorkspace else {
                throw SearchContractFailureV1.invalidContext
            }
            classificationRecords.append(.init(
                value: classification,
                activityID: context.activityID
            ))
        }
        let currentClassificationRecords = try authorityCriterionUniqueHeadsV1(
            values: classificationRecords,
            expectedWorkspace: expectedWorkspace,
            id: { $0.value.bindingID },
            workspace: { $0.value.workspaceID },
            predecessor: { $0.value.supersedesBindingID },
            group: {
                AuthorityCriterionClassificationChainKeyV1(
                    activityID: $0.activityID,
                    findingID: $0.value.findingID,
                    criterionID: $0.value.criterionID
                )
            }
        )
        var classificationsByContext: [UUID: [FindingClassificationBindingV1]] = [:]
        for record in currentClassificationRecords {
            guard currentContextByID[record.value.applicabilityContextID] != nil else {
                throw SearchContractFailureV1.invalidContext
            }
            classificationsByContext[record.value.applicabilityContextID, default: []]
                .append(record.value)
        }

        var result: [UUID: AuthorityCriterionSearchValue] = [:]
        for context in currentContexts {
            var value = result[context.activityID] ?? AuthorityCriterionSearchValue()
            value.dispositions.insert(context.disposition.rawValue)
            for basis in context.basisBindings {
                guard let release = releaseByID[basis.authorityReleaseID] else {
                    throw SearchContractFailureV1.invalidContext
                }
                value.sources.insert([release.designation, release.editionOrRevision]
                    .joined(separator: " "))
            }
            for classification in classificationsByContext[context.snapshotID] ?? [] {
                value.results.insert("\(classification.criterionID) \(classification.result.rawValue)")
                if let severity = classification.severityLevelID { value.severityLevels.insert(severity) }
            }
            result[context.activityID] = value
        }
        return result
    }

    func stableKey(kind: WorkspaceEntityKindV1, id: UUID) throws -> String {
        try WorkspaceEntityIdentityV1(kind: kind, id: id).stableKey
    }

    func project(
        _ value: CanonicalValue,
        source: SearchSourceRevisionV1
    ) throws -> [SearchIndexProjectionRecordV1] {
        var fields: [(String, String)]
        switch value.kind {
        case .asset:
            if includeFunctionalRelationships,
               value.stableID.hasPrefix("functional-") {
                fields = [
                    ("functional_relationship_descriptor", value.functionalRelationshipDescriptorSummary),
                    ("functional_relationship_direction", value.functionalRelationshipDirectionSummary),
                    ("functional_relationship_state", value.functionalRelationshipStateSummary),
                    ("functional_relationship_endpoint", value.functionalRelationshipEndpointSummary),
                ].filter { !$0.1.isEmpty }
            } else {
                fields = [("asset_identifier", value.stableID), ("asset_label", value.display),
                          ("status", value.status)]
            }
            if includeAssetSemantics && !value.stableID.hasPrefix("functional-") {
                fields += [
                    ("asset_semantic_kind", value.semanticKindSummary),
                    ("asset_semantic_capability", value.semanticCapabilitySummary),
                    ("asset_lifecycle_event", value.lifecycleEventSummary),
                    ("asset_product_identity_state", value.productIdentityStateSummary),
                    ("work_subject_scope", value.workSubjectScopeSummary),
                ].filter { !$0.1.isEmpty }
            }
        case .location:
            fields = [("location_identifier", value.stableID), ("location_label", value.display),
                      ("location_breadcrumb", value.breadcrumb.joined(separator: " ")),
                      ("status", value.status)]
        case .work:
            fields = [("work_identifier", value.stableID), ("work_summary", value.summary),
                      ("status", value.status)]
            if includeAuthorityCriterion {
                fields += [
                    ("authority_source", value.authoritySourceSummary),
                    ("applicability_disposition", value.applicabilityDispositionSummary),
                    ("criterion_result", value.criterionResultSummary),
                    ("severity_level", value.severityLevelSummary),
                    ("measurement_protocol", value.measurementProtocolSummary),
                ].filter { !$0.1.isEmpty }
            }
        case .report:
            fields = [("report_identifier", value.stableID), ("report_summary", value.summary),
                      ("status", value.status)]
        case .party:
            fields = [("party_identifier", value.stableID), ("party_label", value.display),
                      ("party_role", value.roleSummary), ("status", value.status)]
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
        // Keep the legacy V1 registry byte-for-byte stable.  The additive
        // party status registration belongs only to the opt-in C38 registry.
        for kind in [.asset, .location, .work, .report] as [SearchSourceKindV1] {
            try append("status", kind, operational: true)
        }
        return try SearchableFieldRegistryV1(fields: fields)
    }

    static func makeAccountabilityRegistry() throws -> SearchableFieldRegistryV1 {
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
        try append("asset_identifier", .asset, identity: true)
        try append("asset_label", .asset)
        try append("location_identifier", .location, identity: true)
        try append("location_label", .location)
        try append("location_breadcrumb", .location)
        try append("work_identifier", .work, identity: true)
        try append("work_summary", .work)
        try append("report_identifier", .report, identity: true)
        try append("report_summary", .report)
        try append("party_identifier", .party, identity: true)
        try append("party_label", .party)
        try append("party_role", .party)
        for kind in [.asset, .location, .work, .report, .party] as [SearchSourceKindV1] {
            try append("status", kind, operational: true)
        }
        return try SearchableFieldRegistryV1(fields: fields)
    }

    static func makeAssetSemanticsRegistry(
        includeAccountability: Bool
    ) throws -> SearchableFieldRegistryV1 {
        try makeExtendedRegistry(
            includeAccountability: includeAccountability,
            includeAssetSemantics: true,
            includeAuthorityCriterion: false
        )
    }

    static func makeFunctionalRelationshipsRegistry(
        includeAccountability: Bool = false,
        includeAssetSemantics: Bool = false,
        includeAuthorityCriterion: Bool = false
    ) throws -> SearchableFieldRegistryV1 {
        try makeExtendedRegistry(
            includeAccountability: includeAccountability,
            includeAssetSemantics: includeAssetSemantics,
            includeAuthorityCriterion: includeAuthorityCriterion,
            includeFunctionalRelationships: true
        )
    }

    static func makeExtendedRegistry(
        includeAccountability: Bool,
        includeAssetSemantics: Bool,
        includeAuthorityCriterion: Bool,
        includeFunctionalRelationships: Bool = false
    ) throws -> SearchableFieldRegistryV1 {
        var fields = try (includeAccountability ? makeAccountabilityRegistry() : makeRegistry()).fields
        func append(_ id: String, _ kind: SearchSourceKindV1) throws {
            fields.append(try SearchableFieldDescriptorV1(
                fieldID: id, sourceKind: kind, privacyClass: .approvedCustomerText,
                tokenization: .unicodeWords,
                normalization: .unicodeCaseAndDiacriticFoldedNFC,
                snippetPermission: .boundedUserVisibleExcerpt,
                retention: .untilSourceFieldIsAmended,
                purgeOwner: .indexRebuildCoordinator
            ))
        }
        if includeAssetSemantics {
            for id in SearchAssetSemanticsPersistencePolicyV1.fieldIDs { try append(id, .asset) }
        }
        if includeAuthorityCriterion {
            for id in SearchAuthorityCriterionPersistencePolicyV1.fieldIDs { try append(id, .work) }
        }
        if includeFunctionalRelationships {
            for id in SearchFunctionalRelationshipsPersistencePolicyV1.fieldIDs {
                try append(id, .asset)
            }
        }
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
        operationalStatusProvider: (any SearchOperationalStatusProvidingV1)? = nil,
        includeAccountability: Bool = false,
        includeAssetSemantics: Bool = true,
        includeAuthorityCriterion: Bool = true
    ) throws {
        let source = try SwiftDataSearchCanonicalProjectionSourceV1(
            modelContext: modelContext,
            workspaceID: workspaceID,
            generationID: generationID,
            revisionProvider: revisionProvider,
            operationalStatusProvider: operationalStatusProvider,
            includeAccountability: includeAccountability,
            includeAssetSemantics: includeAssetSemantics,
            includeAuthorityCriterion: includeAuthorityCriterion
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

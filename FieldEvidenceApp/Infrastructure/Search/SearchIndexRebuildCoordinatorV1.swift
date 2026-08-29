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
        /// C13 search values are intentionally limited to audience,
        /// disposition, limitation, and projection-version metadata.
        let assuranceAudienceSummary: String = ""
        let assuranceDispositionSummary: String = ""
        let assuranceLimitationSummary: String = ""
        let assuranceProjectionVersionSummary: String = ""
        /// C14 search values are current-head, typed review/change/action
        /// state only. Reasons, actor snapshots, evidence references, and
        /// historical revisions never become disposable index text.
        let inspectionReviewStateSummary: String = ""
        let inspectionReviewDispositionSummary: String = ""
        let changeRequestStateSummary: String = ""
        let correctiveActionStateSummary: String = ""
        let inspectionReviewProjectionVersionSummary: String = ""
        /// C15 search values are packet/item current-head metadata only.
        /// Claims, leases, actors, result links, and review-exception digests
        /// remain in the canonical packet snapshot.
        let workPacketManifestStateSummary: String = ""
        let workPacketItemStateSummary: String = ""
        let workPacketConflictStateSummary: String = ""
        let workPacketProjectionVersionSummary: String = ""
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
    private let includeAssurance: Bool
    private let includeInspectionReview: Bool
    private let includeWorkPacket: Bool
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
        includeFunctionalRelationships: Bool = false,
        includeAssurance: Bool = false,
        includeInspectionReview: Bool = false,
        includeWorkPacket: Bool = false
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
        // C14 is a complete additive registry. Enabling its review history
        // also enables every preceding public projection so the registry's
        // exact identity set remains unambiguous.
        let c15 = includeWorkPacket
        let c14 = includeInspectionReview || c15
        let resolvedAccountability = includeAccountability || c14
        let resolvedAssetSemantics = includeAssetSemantics || c14
        let resolvedAuthorityCriterion = includeAuthorityCriterion || c14
        let resolvedFunctionalRelationships = includeFunctionalRelationships || c14
        let resolvedAssurance = includeAssurance || c14
        self.includeAccountability = resolvedAccountability
        self.includeAssetSemantics = resolvedAssetSemantics
        self.includeAuthorityCriterion = resolvedAuthorityCriterion
        self.includeFunctionalRelationships = resolvedFunctionalRelationships
        self.includeAssurance = resolvedAssurance
        self.includeInspectionReview = c14
        self.includeWorkPacket = c15
        registry = try Self.makeExtendedRegistry(
            includeAccountability: resolvedAccountability,
            includeAssetSemantics: resolvedAssetSemantics,
            includeAuthorityCriterion: resolvedAuthorityCriterion,
            includeFunctionalRelationships: resolvedFunctionalRelationships,
            includeAssurance: resolvedAssurance,
            includeInspectionReview: c14,
            includeWorkPacket: c15
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
        let assuranceValues = includeAssurance
            ? try assuranceSearchValues()
            : []
        let inspectionReviewValues = includeInspectionReview
            ? try inspectionReviewSearchValues()
            : []
        let workPacketValues = includeWorkPacket
            ? try workPacketSearchValues()
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
        values += assuranceValues
        values += inspectionReviewValues
        values += workPacketValues
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

    /// Reads only current assurance-manifest heads. The index contains typed
    /// audience/disposition/limitation/version metadata; it never contains
    /// claim text, evidence identifiers/digests, media/content, or actor data.
    func assuranceSearchValues() throws -> [CanonicalValue] {
        let expectedWorkspace = WorkspaceID(rawValue: workspaceID)
        let manifests = try modelContext.fetch(FetchDescriptor<AssuranceManifestRow>())
            .filter { $0.workspaceID == workspaceID }
            .map { try $0.value() }
        let heads = try authorityCriterionUniqueHeadsV1(
            values: manifests,
            expectedWorkspace: expectedWorkspace,
            id: { $0.manifestID },
            workspace: { $0.workspaceID },
            predecessor: { $0.supersedesManifestID },
            group: { "\($0.snapshotSHA256):\($0.audience.rawValue):\($0.projectionVersion)" }
        )
        return try heads.sorted {
            $0.manifestID.uuidString.lowercased() < $1.manifestID.uuidString.lowercased()
        }.map { manifest in
            try manifest.validate()
            for link in manifest.includedLinks + manifest.excludedLinks {
                try link.validate(visibility: link.visibility)
            }
            let limitationValues = Set(manifest.excludedLinks.map { $0.decision.limitation.rawValue })
            let limitationSummary = limitationValues.isEmpty
                ? EvidenceLimitationV1.none.rawValue
                : limitationValues.sorted().joined(separator: " ")
            let dispositionValues = Set((manifest.includedLinks.map {
                EvidenceInclusionDispositionV1.included.rawValue
            } + manifest.excludedLinks.map {
                EvidenceInclusionDispositionV1.excluded.rawValue
            }))
            return CanonicalValue(
                kind: .report,
                stableID: "assurance-\(manifest.manifestID.uuidString.lowercased())",
                display: "Evidence assurance",
                summary: "Evidence assurance",
                breadcrumb: [],
                status: "provisional",
                dueAt: nil,
                timestamp: manifest.recordedAt,
                assuranceAudienceSummary: manifest.audience.rawValue,
                assuranceDispositionSummary: dispositionValues.sorted().joined(separator: " "),
                assuranceLimitationSummary: limitationSummary,
                assuranceProjectionVersionSummary: manifest.projectionVersion
            )
        }
    }

    private struct InspectionReviewSearchValue {
        var reviewState: String = ""
        var dispositions: Set<String> = []
        var changeStates: Set<String> = []
        var actionStates: Set<String> = []
        var timestamp: Date?

        mutating func record(_ value: Date) {
            timestamp = max(timestamp ?? value, value)
        }
    }

    /// Reads the C14 rows only through their current-head projections. The
    /// resulting records carry typed state/version metadata; reasons, actor
    /// snapshots, evidence references, and historical revisions stay in the
    /// canonical completed snapshot and are never copied into the index.
    func inspectionReviewSearchValues() throws -> [CanonicalValue] {
        let expectedWorkspace = WorkspaceID(rawValue: workspaceID)
        let transitions = try modelContext.fetch(
            FetchDescriptor<InspectionReviewTransitionRow>()
        ).filter { $0.workspaceID == workspaceID }.map { try $0.value() }
        let dispositions = try modelContext.fetch(
            FetchDescriptor<ReviewDispositionRow>()
        ).filter { $0.workspaceID == workspaceID }.map { try $0.value() }
        let requests = try modelContext.fetch(
            FetchDescriptor<ChangeRequestRow>()
        ).filter { $0.workspaceID == workspaceID }.map { try $0.value() }
        let actions = try modelContext.fetch(
            FetchDescriptor<CorrectiveActionEventRow>()
        ).filter { $0.workspaceID == workspaceID }.map { try $0.value() }
        let policies = try modelContext.fetch(
            FetchDescriptor<CorrectiveActionPolicyRow>()
        ).filter { $0.workspaceID == workspaceID }.map { try $0.value() }

        guard !transitions.isEmpty else {
            guard dispositions.isEmpty, requests.isEmpty, actions.isEmpty else {
                throw SearchContractFailureV1.invalidContext
            }
            return []
        }

        try transitions.forEach {
            try $0.validate()
            guard $0.workspaceID == expectedWorkspace else {
                throw SearchContractFailureV1.invalidContext
            }
        }
        try dispositions.forEach {
            try $0.validate()
            guard $0.workspaceID == expectedWorkspace else {
                throw SearchContractFailureV1.invalidContext
            }
        }
        try requests.forEach {
            try $0.validate()
            guard $0.workspaceID == expectedWorkspace else {
                throw SearchContractFailureV1.invalidContext
            }
        }
        try actions.forEach {
            try $0.validate()
            guard $0.workspaceID == expectedWorkspace else {
                throw SearchContractFailureV1.invalidContext
            }
        }
        try policies.forEach {
            try $0.validate()
            guard $0.workspaceID == expectedWorkspace else {
                throw SearchContractFailureV1.invalidContext
            }
        }

        let transitionsByReview = Dictionary(grouping: transitions, by: \.reviewID)
        var result: [UUID: InspectionReviewSearchValue] = [:]
        for reviewID in transitionsByReview.keys.sorted(by: {
            $0.uuidString.lowercased() < $1.uuidString.lowercased()
        }) {
            let reviewTransitions = transitionsByReview[reviewID] ?? []
            let reviewDispositions = dispositions.filter { $0.reviewID == reviewID }
            let reviewRequests = requests.filter { $0.reviewID == reviewID }
            let projection = try InspectionReviewProjectionBuilderV1.rebuild(
                workspaceID: expectedWorkspace,
                reviewID: reviewID,
                transitions: reviewTransitions,
                dispositions: reviewDispositions,
                changeRequests: reviewRequests
            )
            var value = InspectionReviewSearchValue(
                reviewState: projection.state.rawValue,
                timestamp: nil
            )
            for transition in reviewTransitions { value.record(transition.recordedAt) }

            let dispositionHeads = try authorityCriterionUniqueHeadsV1(
                values: reviewDispositions,
                expectedWorkspace: expectedWorkspace,
                id: { $0.dispositionID },
                workspace: { $0.workspaceID },
                predecessor: { $0.supersedesDispositionID },
                group: { $0.reviewID }
            )
            for disposition in dispositionHeads {
                value.dispositions.insert(disposition.kind.rawValue)
                value.record(disposition.recordedAt)
            }

            let requestHeads = try authorityCriterionUniqueHeadsV1(
                values: reviewRequests,
                expectedWorkspace: expectedWorkspace,
                id: { $0.requestRevisionID },
                workspace: { $0.workspaceID },
                predecessor: { $0.supersedesRequestRevisionID },
                group: { $0.requestID }
            )
            for request in requestHeads {
                value.changeStates.insert(request.state.rawValue)
                value.record(request.recordedAt)
            }
            result[reviewID] = value
        }

        // Corrective-action rows name the exact change-request item rather
        // than a review directly. Resolve that immutable item reference to
        // one review; an orphan or ambiguous reference is rejected closed.
        let actionHeads = try authorityCriterionUniqueHeadsV1(
            values: actions,
            expectedWorkspace: expectedWorkspace,
            id: { $0.eventID },
            workspace: { $0.workspaceID },
            predecessor: { $0.predecessorEventID },
            group: { $0.actionID }
        )
        let requestsByReview = Dictionary(grouping: requests, by: \.reviewID)
        for action in actionHeads {
            guard let policy = policies.first(where: {
                guard let reference = try? CorrectiveActionPolicyReferenceV1($0) else {
                    return false
                }
                return reference == action.policy
            }) else {
                throw SearchContractFailureV1.invalidContext
            }
            _ = try CorrectiveActionProjectionBuilderV1.rebuild(
                workspaceID: expectedWorkspace,
                actionID: action.actionID,
                events: actions.filter { $0.actionID == action.actionID },
                policies: [policy],
                now: action.recordedAt
            )
            let candidateReviews = requestsByReview.compactMap { reviewID, values in
                values.contains(where: {
                    let candidate = $0.item.itemID.lowercased()
                    let source = action.source.itemID.lowercased()
                    return candidate == source
                        || $0.requestID.uuidString.lowercased() == source
                        || $0.requestRevisionID.uuidString.lowercased() == source
                }) ? reviewID : nil
            }
            guard candidateReviews.count == 1,
                  let reviewID = candidateReviews.first,
                  var value = result[reviewID] else {
                throw SearchContractFailureV1.invalidContext
            }
            value.actionStates.insert(action.state.rawValue)
            value.record(action.recordedAt)
            result[reviewID] = value
        }

        return try result.keys.sorted(by: {
            $0.uuidString.lowercased() < $1.uuidString.lowercased()
        }).map { reviewID in
            guard let value = result[reviewID], let timestamp = value.timestamp else {
                throw SearchContractFailureV1.invalidContext
            }
            return CanonicalValue(
                kind: .report,
                stableID: "inspection-review-\(reviewID.uuidString.lowercased())",
                display: "Inspection review",
                summary: "Inspection review",
                breadcrumb: [],
                status: value.reviewState,
                dueAt: nil,
                timestamp: timestamp,
                inspectionReviewStateSummary: value.reviewState,
                inspectionReviewDispositionSummary: value.dispositions.sorted().joined(separator: " "),
                changeRequestStateSummary: value.changeStates.sorted().joined(separator: " "),
                correctiveActionStateSummary: value.actionStates.sorted().joined(separator: " "),
                inspectionReviewProjectionVersionSummary:
                    SearchInspectionReviewPersistencePolicyV1.acceptedProjectionVersionMarkers[1]
            )
        }
    }

    /// Builds one disposable current-head value per packet manifest. Full
    /// claim/lease/release/handoff history is validated by the canonical
    /// projection builder, but only typed state/count metadata is sent to the
    /// search index. Any orphan, fork, stale result, or cross-workspace row
    /// fails the rebuild closed.
    func workPacketSearchValues() throws -> [CanonicalValue] {
        let expectedWorkspace = WorkspaceID(rawValue: workspaceID)
        let manifests = try modelContext.fetch(FetchDescriptor<WorkPacketManifestRow>())
            .filter { $0.workspaceID == workspaceID }
            .map { try $0.value() }
        let claims = try modelContext.fetch(FetchDescriptor<WorkItemClaimRow>())
            .filter { $0.workspaceID == workspaceID }
            .map { try $0.value() }
        let leases = try modelContext.fetch(FetchDescriptor<WorkLeaseRow>())
            .filter { $0.workspaceID == workspaceID }
            .map { try $0.value() }
        let releases = try modelContext.fetch(FetchDescriptor<WorkReleaseRow>())
            .filter { $0.workspaceID == workspaceID }
            .map { try $0.value() }
        let handoffs = try modelContext.fetch(FetchDescriptor<WorkHandoffRow>())
            .filter { $0.workspaceID == workspaceID }
            .map { try $0.value() }
        var identities: Set<UUID> = []
        var packetIdentities: Set<UUID> = []
        let manifestIDs = Set(manifests.map(\.manifestID))
        let packetIDs = Set(manifests.map(\.packetID))
        guard manifestIDs.count == manifests.count,
              packetIDs.count == manifests.count,
              claims.allSatisfy({ manifestIDs.contains($0.manifest.manifestID) }),
              leases.allSatisfy({ packetIDs.contains($0.item.packetID) }),
              releases.allSatisfy({ packetIDs.contains($0.item.packetID) }),
              handoffs.allSatisfy({ packetIDs.contains($0.item.packetID) }) else {
            throw SearchContractFailureV1.invalidContext
        }
        var values: [CanonicalValue] = []
        for manifest in manifests.sorted(by: {
            $0.manifestID.uuidString.lowercased() < $1.manifestID.uuidString.lowercased()
        }) {
            guard identities.insert(manifest.manifestID).inserted,
                  packetIdentities.insert(manifest.packetID).inserted,
                  manifest.workspaceID == expectedWorkspace else {
                throw SearchContractFailureV1.invalidContext
            }
            let manifestReference = try WorkPacketManifestReferenceV1(manifest)
            let itemReferences = try manifest.items.map {
                try WorkPacketItemReferenceV1(manifest: manifest, item: $0)
            }
            let packetClaims = claims.filter {
                $0.manifest.manifestID == manifest.manifestID
            }
            let packetLeases = leases.filter { $0.item.packetID == manifest.packetID }
            let packetReleases = releases.filter { $0.item.packetID == manifest.packetID }
            let packetHandoffs = handoffs.filter { $0.item.packetID == manifest.packetID }
            guard packetClaims.allSatisfy({
                      $0.workspaceID == expectedWorkspace
                          && $0.manifest == manifestReference
                          && itemReferences.contains($0.item)
                  }),
                  packetLeases.allSatisfy({
                      $0.workspaceID == expectedWorkspace
                          && itemReferences.contains($0.item)
                  }),
                  packetReleases.allSatisfy({
                      $0.workspaceID == expectedWorkspace
                          && itemReferences.contains($0.item)
                  }),
                  packetHandoffs.allSatisfy({
                      $0.workspaceID == expectedWorkspace
                          && itemReferences.contains($0.item)
                  }) else {
                throw SearchContractFailureV1.invalidContext
            }
            let timestamp = ([manifest.createdAt]
                + packetClaims.map(\.claimedAt)
                + packetLeases.map(\.startsAt)
                + packetReleases.map(\.releasedAt)
                + packetHandoffs.map(\.handedOffAt)).max() ?? manifest.createdAt
            let projection = try WorkPacketProjectionBuilderV1.rebuild(
                workspaceID: expectedWorkspace,
                manifest: manifest,
                claims: packetClaims,
                leases: packetLeases,
                releases: packetReleases,
                handoffs: packetHandoffs,
                at: timestamp
            )
            let itemSnapshots = try projection.items.map {
                try CompletedWorkPacketItemSnapshotV1(item: $0.item, projection: $0)
            }
            let states = Set(itemSnapshots.map { $0.state.rawValue })
            let hasConflict = itemSnapshots.contains { !$0.conflictKinds.isEmpty }
            values.append(CanonicalValue(
                kind: .work,
                stableID: "work-packet-\(manifest.packetID.uuidString.lowercased())",
                display: "Work packet",
                summary: "Work packet",
                breadcrumb: [],
                status: hasConflict ? "conflicted" : "ready",
                dueAt: nil,
                timestamp: timestamp,
                workPacketManifestStateSummary: hasConflict ? "CONFLICTED" : "READY",
                workPacketItemStateSummary: states.sorted().joined(separator: " "),
                workPacketConflictStateSummary: hasConflict ? "REVIEW_REQUIRED" : "NONE",
                workPacketProjectionVersionSummary:
                    SearchWorkPacketPersistencePolicyV1.acceptedProjectionVersionMarkers[1]
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
            if includeWorkPacket, value.stableID.hasPrefix("work-packet-") {
                fields = [
                    ("work_packet_identifier", value.stableID),
                    ("work_packet_manifest_state", value.workPacketManifestStateSummary),
                    ("work_packet_item_state", value.workPacketItemStateSummary),
                    ("work_packet_conflict_state", value.workPacketConflictStateSummary),
                    ("work_packet_projection_version", value.workPacketProjectionVersionSummary),
                ].filter { !$0.1.isEmpty }
            } else {
                fields = [("work_identifier", value.stableID), ("work_summary", value.summary),
                          ("status", value.status)]
            }
            if includeAuthorityCriterion, !value.stableID.hasPrefix("work-packet-") {
                fields += [
                    ("authority_source", value.authoritySourceSummary),
                    ("applicability_disposition", value.applicabilityDispositionSummary),
                    ("criterion_result", value.criterionResultSummary),
                    ("severity_level", value.severityLevelSummary),
                    ("measurement_protocol", value.measurementProtocolSummary),
                ].filter { !$0.1.isEmpty }
            }
        case .report:
            if includeInspectionReview, value.stableID.hasPrefix("inspection-review-") {
                fields = [
                    ("inspection_review_state", value.inspectionReviewStateSummary),
                    ("inspection_review_disposition", value.inspectionReviewDispositionSummary),
                    ("change_request_state", value.changeRequestStateSummary),
                    ("corrective_action_state", value.correctiveActionStateSummary),
                    ("inspection_review_projection_version",
                     value.inspectionReviewProjectionVersionSummary),
                ].filter { !$0.1.isEmpty }
            } else if includeAssurance, value.stableID.hasPrefix("assurance-") {
                fields = [
                    ("assurance_audience", value.assuranceAudienceSummary),
                    ("assurance_disposition", value.assuranceDispositionSummary),
                    ("assurance_limitation", value.assuranceLimitationSummary),
                    ("assurance_projection_version", value.assuranceProjectionVersionSummary),
                ].filter { !$0.1.isEmpty }
            } else {
                fields = [("report_identifier", value.stableID), ("report_summary", value.summary),
                          ("status", value.status)]
            }
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
        includeAccountability: Bool,
        includeInspectionReview: Bool = false
    ) throws -> SearchableFieldRegistryV1 {
        try makeExtendedRegistry(
            includeAccountability: includeAccountability || includeInspectionReview,
            includeAssetSemantics: true,
            includeAuthorityCriterion: includeInspectionReview,
            includeFunctionalRelationships: includeInspectionReview,
            includeAssurance: includeInspectionReview,
            includeInspectionReview: includeInspectionReview
        )
    }

    static func makeEvidenceAssuranceRegistry(
        includeAccountability: Bool = false,
        includeAssetSemantics: Bool = false,
        includeAuthorityCriterion: Bool = false,
        includeFunctionalRelationships: Bool = false,
        includeInspectionReview: Bool = false
    ) throws -> SearchableFieldRegistryV1 {
        try makeExtendedRegistry(
            includeAccountability: includeAccountability || includeInspectionReview,
            includeAssetSemantics: includeAssetSemantics || includeInspectionReview,
            includeAuthorityCriterion: includeAuthorityCriterion || includeInspectionReview,
            includeFunctionalRelationships: includeFunctionalRelationships || includeInspectionReview,
            includeAssurance: true,
            includeInspectionReview: includeInspectionReview
        )
    }

    static func makeFunctionalRelationshipsRegistry(
        includeAccountability: Bool = false,
        includeAssetSemantics: Bool = false,
        includeAuthorityCriterion: Bool = false,
        includeAssurance: Bool = false,
        includeInspectionReview: Bool = false
    ) throws -> SearchableFieldRegistryV1 {
        try makeExtendedRegistry(
            includeAccountability: includeAccountability || includeInspectionReview,
            includeAssetSemantics: includeAssetSemantics || includeInspectionReview,
            includeAuthorityCriterion: includeAuthorityCriterion || includeInspectionReview,
            includeFunctionalRelationships: true,
            includeAssurance: includeAssurance || includeInspectionReview,
            includeInspectionReview: includeInspectionReview
        )
    }

    static func makeInspectionReviewRegistry() throws -> SearchableFieldRegistryV1 {
        try makeExtendedRegistry(
            includeAccountability: true,
            includeAssetSemantics: true,
            includeAuthorityCriterion: true,
            includeFunctionalRelationships: true,
            includeAssurance: true,
            includeInspectionReview: true
        )
    }

    static func makeWorkPacketRegistry() throws -> SearchableFieldRegistryV1 {
        try makeExtendedRegistry(
            includeAccountability: true,
            includeAssetSemantics: true,
            includeAuthorityCriterion: true,
            includeFunctionalRelationships: true,
            includeAssurance: true,
            includeInspectionReview: true,
            includeWorkPacket: true
        )
    }

    static func makeExtendedRegistry(
        includeAccountability: Bool,
        includeAssetSemantics: Bool,
        includeAuthorityCriterion: Bool,
        includeFunctionalRelationships: Bool = false,
        includeAssurance: Bool = false,
        includeInspectionReview: Bool = false,
        includeWorkPacket: Bool = false
    ) throws -> SearchableFieldRegistryV1 {
        let resolvedInspectionReview = includeInspectionReview || includeWorkPacket
        let resolvedAccountability = includeAccountability || resolvedInspectionReview
        let resolvedAssetSemantics = includeAssetSemantics || resolvedInspectionReview
        let resolvedAuthorityCriterion = includeAuthorityCriterion || resolvedInspectionReview
        let resolvedFunctionalRelationships = includeFunctionalRelationships || resolvedInspectionReview
        let resolvedAssurance = includeAssurance || resolvedInspectionReview
        var fields = try (resolvedAccountability ? makeAccountabilityRegistry() : makeRegistry()).fields
        func append(_ id: String, _ kind: SearchSourceKindV1) throws {
            let identity = id == FrozenSearchableFieldV1.workPacketIdentifier.rawValue
            fields.append(try SearchableFieldDescriptorV1(
                fieldID: id,
                sourceKind: kind,
                privacyClass: identity
                    ? .userVisibleIdentifier : .approvedCustomerText,
                tokenization: identity ? .exactIdentity : .unicodeWords,
                normalization: identity
                    ? .stableIdentity : .unicodeCaseAndDiacriticFoldedNFC,
                snippetPermission: identity
                    ? .exactDisplayValue : .boundedUserVisibleExcerpt,
                retention: .untilSourceFieldIsAmended,
                purgeOwner: .indexRebuildCoordinator
            ))
        }
        if resolvedAssetSemantics {
            for id in SearchAssetSemanticsPersistencePolicyV1.fieldIDs { try append(id, .asset) }
        }
        if resolvedAuthorityCriterion {
            for id in SearchAuthorityCriterionPersistencePolicyV1.fieldIDs { try append(id, .work) }
        }
        if resolvedFunctionalRelationships {
            for id in SearchFunctionalRelationshipsPersistencePolicyV1.fieldIDs {
                try append(id, .asset)
            }
        }
        if resolvedAssurance {
            for id in SearchEvidenceAssurancePersistencePolicyV1.fieldIDs {
                try append(id, .report)
            }
        }
        if resolvedInspectionReview {
            for id in SearchInspectionReviewPersistencePolicyV1.fieldIDs {
                try append(id, .report)
            }
        }
        if includeWorkPacket {
            for id in SearchWorkPacketPersistencePolicyV1.fieldIDs {
                try append(id, .work)
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
        * SearchContractLimitsV1.maximumSearchableFieldCount

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
                * registry.fields.count
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
        includeAuthorityCriterion: Bool = true,
        includeFunctionalRelationships: Bool = false,
        includeAssurance: Bool = false,
        includeInspectionReview: Bool = false
    ) throws {
        let source = try SwiftDataSearchCanonicalProjectionSourceV1(
            modelContext: modelContext,
            workspaceID: workspaceID,
            generationID: generationID,
            revisionProvider: revisionProvider,
            operationalStatusProvider: operationalStatusProvider,
            includeAccountability: includeAccountability,
            includeAssetSemantics: includeAssetSemantics,
            includeAuthorityCriterion: includeAuthorityCriterion,
            includeFunctionalRelationships: includeFunctionalRelationships,
            includeAssurance: includeAssurance,
            includeInspectionReview: includeInspectionReview
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

extension SearchIndexRebuildCoordinatorV1 {
    /// Rebuilds only the bounded package-evolution search projection from the
    /// canonical lifecycle closure. Search never replays package bytes,
    /// payloads, actor identity, or exact candidate heads.
    static func packageEvolutionSearchRecords(
        from closure: PackageEvolutionLifecycleClosureV1
    ) throws -> [PackageEvolutionSearchRecordV1] {
        try closure.validate()
        let releases = Dictionary(uniqueKeysWithValues: closure.promotedReleases.map {
            ($0.releaseRecordID, $0)
        })
        let runs = Dictionary(uniqueKeysWithValues: closure.sandboxRuns.map { ($0.runID, $0) })
        let pointers = Dictionary(uniqueKeysWithValues: closure.activePointers.map {
            ($0.pointerSHA256, $0)
        })
        return try closure.promotionReceipts.map { receipt in
            guard let release = releases[receipt.promotedReleaseRecordID],
                  let run = runs[receipt.sandboxRunID],
                  let pointer = pointers[receipt.resultingPointerSHA256] else {
                throw PackageEvolutionConsumerFailureV1.mismatchedRelease
            }
            let predecessor = receipt.predecessorPointerSHA256
                == String(repeating: "0", count: 64)
                ? nil
                : pointers[receipt.predecessorPointerSHA256]
            let bundle = PackagePromotionAtomicBundleV1(
                promotedRelease: release,
                sandboxRun: run,
                semanticDiff: receipt.semanticDiff,
                predecessorPointer: predecessor,
                resultingPointer: pointer,
                actor: receipt.declaredActor,
                receipt: receipt
            )
            return try PackageEvolutionSearchRecordV1(
                metadata: PackageEvolutionConsumerMetadataV1(bundle: bundle)
            )
        }.sorted {
            if $0.packageID != $1.packageID { return $0.packageID < $1.packageID }
            return $0.packageReleaseID < $1.packageReleaseID
        }
    }

    static let packageEvolutionReplayDisposition =
        "REBUILD_FROM_CANONICAL_PACKAGE_PROMOTION_RECEIPT"

    /// Rebuilds the C19 disposable metadata rows from frozen report
    /// projections. Sorting and duplicate rejection make replay deterministic;
    /// exact values and private provenance never enter the searchable rows.
    static func measurementIntegritySearchRecords(
        from projections: [MeasurementIntegrityReportProjectionV1],
        sourceRevision: UInt64 = 0
    ) throws -> [MeasurementIntegritySearchRecordV1] {
        let records = try projections.map {
            try MeasurementIntegritySearchRecordV1(
                projection: $0,
                sourceRevision: sourceRevision
            )
        }.sorted { lhs, rhs in
            lhs.captureID.uuidString.lowercased() < rhs.captureID.uuidString.lowercased()
        }
        guard Set(records.map(\.captureID)).count == records.count else {
            throw SearchContractFailureV1.duplicateProjection
        }
        try records.forEach { try $0.validate() }
        return records
    }

    static let measurementIntegrityReplayDisposition =
        "DROP_AND_REBUILD_FROM_FROZEN_MEASUREMENT_PROJECTION"

    /// C20 replay reconstructs disposable rows from the approved derivative
    /// projection, never from original/derivative bytes or review payloads.
    static func privacyTransformSearchRecords(
        from projections: [PrivacyTransformReportProjectionV1]
    ) throws -> [PrivacyTransformSearchRecordV1] {
        try PrivacyTransformSearchPersistencePolicyV1().validate()
        let records = try projections.map {
            try PrivacyTransformSearchRecordV1(projection: $0)
        }.sorted {
            $0.manifestID.uuidString.lowercased() < $1.manifestID.uuidString.lowercased()
        }
        guard Set(records.map(\.manifestID)).count == records.count else {
            throw SearchContractFailureV1.duplicateProjection
        }
        try records.forEach { try $0.validate() }
        return records
    }

    static let privacyTransformReplayDisposition =
        "DROP_AND_REBUILD_FROM_APPROVED_PRIVACY_DERIVATIVE_PROJECTION"

    /// C21 search replay consumes canonical admission decisions and emits
    /// disposable metadata rows. It never replays package payloads or tries
    /// to infer a missing client/device identity.
    static func clientCapabilitySearchRecords(
        from projections: [ClientCapabilityReportProjectionV1]
    ) throws -> [ClientCapabilitySearchRecordV1] {
        try ClientCapabilitySearchPersistencePolicyV1().validate()
        let records = try projections.map {
            try ClientCapabilitySearchRecordV1(projection: $0)
        }.sorted {
            $0.decisionID.uuidString.lowercased() < $1.decisionID.uuidString.lowercased()
        }
        guard Set(records.map(\.decisionID)).count == records.count else {
            throw SearchContractFailureV1.duplicateProjection
        }
        try records.forEach { try $0.validate() }
        return records
    }

    static let clientCapabilityReplayDisposition =
        "DROP_AND_REBUILD_FROM_CANONICAL_CLIENT_CAPABILITY_DECISION"

    /// Rebuilds the C23 disposable search rows from immutable report
    /// projections. No replay path consults a current pointer or reference
    /// content store.
    static func fieldReferenceSearchRecords(
        from projections: [FieldReferenceReportProjectionV1]
    ) throws -> [FieldReferenceSearchRecordV1] {
        try FieldReferenceSearchPersistencePolicyV1().validate()
        let records = try projections.map {
            try FieldReferenceSearchRecordV1(projection: $0)
        }.sorted {
            $0.projectionSHA256 < $1.projectionSHA256
        }
        guard Set(records.map(\.projectionSHA256)).count == records.count else {
            throw SearchContractFailureV1.duplicateProjection
        }
        try records.forEach { try $0.validate() }
        return records
    }

    static let fieldReferenceReplayDisposition =
        "DROP_AND_REBUILD_FROM_FROZEN_FIELD_REFERENCE_BINDING"
}

// MARK: - C30 operating-context rebuild

extension SearchIndexRebuildCoordinatorV1 {
    static func rebuildOperatingContextRecords(
        from projections: [C30EvidenceContextReportReferenceV1]
    ) throws -> [C30OperatingContextSearchRecordV1] {
        try C30OperatingContextSearchPersistencePolicyV1.validate()
        let records = try projections.map {
            try LocalSearchIndexStoreV1.operatingContextSearchRecord(from: $0)
        }.sorted {
            ($0.evidenceID, $0.contextRevision) < ($1.evidenceID, $1.contextRevision)
        }
        guard Set(records.map(\.contextID)).count == records.count,
              records.count <= SearchContractLimitsV1.maximumCanonicalRecords else {
            throw SearchContractFailureV1.duplicateProjection
        }
        try records.forEach { try C30OperatingContextSearchPolicyV1.validate($0) }
        return records
    }

    static let c30OperatingContextRestoreDisposition =
        "DROP_AND_REBUILD_FROM_CANONICAL_CONTEXT"
    static let c30OperatingContextReplayDisposition =
        "DROP_AND_REBUILD_FROM_CANONICAL_CONTEXT"
}

// MARK: - C24 accessible-document search rebuild

extension SearchIndexRebuildCoordinatorV1 {
    /// Rebuilds disposable C24 rows from canonical semantic trees.  The
    /// ordering is digest-based and assessment matching is transient; no
    /// semantic tree or evidence payload is persisted in the index.
    static func accessibleDocumentSearchRecords(
        from trees: [AccessibleDocumentSemanticTreeV1],
        assessments: [AccessibleDocumentAssessmentReceiptV1] = []
    ) throws -> [AccessibleDocumentSearchRecordV1] {
        try AccessibleDocumentSearchPersistencePolicyV1().validate()
        guard trees.count <= AccessibleDocumentSearchRecordV1.maximumValues,
              assessments.count <= AccessibleDocumentSearchRecordV1.maximumValues else {
            throw SearchContractFailureV1.limitExceeded
        }
        let grouped = Dictionary(grouping: assessments, by: \.treeSHA256)
        guard grouped.values.allSatisfy({ $0.count <= 1 }) else {
            throw SearchContractFailureV1.duplicateProjection
        }
        let records = try trees.map { tree in
            try AccessibleDocumentSearchRecordV1(
                tree: tree,
                assessment: grouped[tree.treeSHA256]?.first
            )
        }.sorted { $0.treeSHA256 < $1.treeSHA256 }
        guard Set(records.map(\.treeSHA256)).count == records.count else {
            throw SearchContractFailureV1.duplicateProjection
        }
        try records.forEach { try $0.validate() }
        return records
    }

    static let accessibleDocumentReplayDisposition =
        "DROP_AND_REBUILD_FROM_CANONICAL_ACCESSIBLE_DOCUMENT_TREE"
}

// MARK: - C25 survey-definition search rebuild

extension SearchIndexRebuildCoordinatorV1 {
    /// Rebuilds the disposable survey-definition index from immutable release
    /// facts and the canonical identity's recorded lifecycle state.  A
    /// missing state is rejected rather than inferred, and no draft answer,
    /// prompt, locator, or actor value is accepted by this consumer.
    static func surveyDefinitionSearchRecords(
        from releases: [SurveyDefinitionReleaseV1],
        lifecycleStates: [UUID: SurveyDefinitionLifecycleStateV1]
    ) throws -> [SurveyDefinitionSearchRecordV1] {
        try SurveyDefinitionSearchPersistencePolicyV1().validate()
        guard releases.count <= 4_096 else {
            throw SurveyDefinitionConsumerFailureV1.limitExceeded
        }
        let sorted = releases.sorted {
            $0.releaseID.uuidString.lowercased() < $1.releaseID.uuidString.lowercased()
        }
        guard Set(sorted.map(\.releaseID)).count == sorted.count else {
            throw SurveyDefinitionConsumerFailureV1.duplicateIdentity
        }
        let records = try sorted.map { release in
            guard let state = lifecycleStates[release.definitionID] else {
                throw SurveyDefinitionConsumerFailureV1.staleBinding
            }
            return try LocalSearchIndexStoreV1.surveyDefinitionSearchRecord(
                from: release,
                lifecycleState: state
            )
        }
        guard records == records.sorted(by: {
            $0.releaseID < $1.releaseID
        }) else {
            throw SurveyDefinitionConsumerFailureV1.invalidValue
        }
        return records
    }

    static let surveyDefinitionReplayDisposition =
        "DROP_AND_REBUILD_FROM_CANONICAL_SURVEY_DEFINITION_RELEASES"
    static let surveyDefinitionRestoreDisposition =
        "EXCLUDE_INDEX_ROWS_AND_REBUILD_AFTER_CANONICAL_RESTORE"
}

// MARK: - C26 guided-survey session search rebuild

extension SearchIndexRebuildCoordinatorV1 {
    /// Rebuilds disposable session rows from validated canonical snapshots.
    /// Only IDs, closed state values, revisions, and a bounded fact count are
    /// retained; answer payloads, prompts, labels, actors, and evidence are
    /// intentionally consumed transiently and never become index data.
    static func surveySessionSearchRecords(
        from sessions: [SurveySessionV1],
        publications: [SurveyPublicationSnapshotV1] = [],
        provisionalSubjects: [ProvisionalSubjectV1] = [],
        factStates: [UUID: SurveySessionFactLocalizationStateV1] = [:],
        publicationStates: [UUID: SurveySessionPublicationLocalizationStateV1] = [:]
    ) throws -> [SurveySessionSearchRecordV1] {
        try SurveySessionSearchPersistencePolicyV1().validate()
        guard sessions.count <= 4_096,
              publications.count <= 4_096,
              provisionalSubjects.count <= 4_096 else {
            throw SearchContractFailureV1.limitExceeded
        }

        let orderedSessions = sessions.sorted {
            $0.sessionID.uuidString.lowercased() < $1.sessionID.uuidString.lowercased()
        }
        guard Set(orderedSessions.map(\.sessionID)).count == orderedSessions.count else {
            throw SearchContractFailureV1.duplicateProjection
        }

        var subjectsByID: [UUID: ProvisionalSubjectV1] = [:]
        for subject in provisionalSubjects {
            guard subjectsByID.updateValue(subject, forKey: subject.provisionalSubjectID) == nil else {
                throw SearchContractFailureV1.duplicateProjection
            }
        }
        let orderedPublications = publications.sorted {
            if $0.sessionID != $1.sessionID { return $0.sessionID.uuidString < $1.sessionID.uuidString }
            if $0.revision != $1.revision { return $0.revision < $1.revision }
            return $0.snapshotID.uuidString < $1.snapshotID.uuidString
        }
        var publicationsBySession: [UUID: [SurveyPublicationSnapshotV1]] = [:]
        for publication in orderedPublications {
            guard !publicationsBySession[publication.sessionID, default: []].contains(where: {
                $0.snapshotID == publication.snapshotID
            }) else {
                throw SearchContractFailureV1.duplicateProjection
            }
            publicationsBySession[publication.sessionID, default: []].append(publication)
        }

        var records: [SurveySessionSearchRecordV1] = []
        for session in orderedSessions {
            let provisional: ProvisionalSubjectV1?
            if case let .provisional(reference) = session.subject {
                provisional = subjectsByID[reference.provisionalSubjectID]
            } else {
                provisional = nil
            }
            let sessionPublications = publicationsBySession[session.sessionID] ?? []
            if sessionPublications.isEmpty {
                records.append(try LocalSearchIndexStoreV1.surveySessionSearchRecord(
                    from: session,
                    provisionalSubject: provisional,
                    factState: factStates[session.sessionID],
                    publicationState: publicationStates[session.sessionID]
                ))
            } else {
                for publication in sessionPublications {
                    records.append(try LocalSearchIndexStoreV1.surveySessionSearchRecord(
                        from: session,
                        publication: publication,
                        provisionalSubject: provisional,
                        factState: factStates[session.sessionID],
                        publicationState: publicationStates[session.sessionID]
                    ))
                }
            }
        }
        records.sort { $0.projectionIdentity < $1.projectionIdentity }
        guard Set(records.map(\.projectionIdentity)).count == records.count else {
            throw SearchContractFailureV1.duplicateProjection
        }
        try records.forEach { try SurveySessionSearchProjectionPolicyV1.validate($0) }
        return records
    }

    static let surveySessionReplayDisposition =
        "DROP_AND_REBUILD_FROM_CANONICAL_SURVEY_SESSION_SNAPSHOTS"
    static let surveySessionRestoreDisposition =
        "EXCLUDE_SESSION_ROWS_AND_REBUILD_AFTER_CANONICAL_RESTORE"
}

// MARK: - C27 asset-locator search rebuild

extension SearchIndexRebuildCoordinatorV1 {
    /// Rebuilds the disposable locator rows from canonical locator heads and
    /// recorded resolution results.  It never accepts raw input bytes and it
    /// never promotes a search row into canonical locator state.
    static func assetLocatorSearchRecords(
        from locators: [AssetLocatorV1],
        resolutions: [LocatorResolutionV1] = []
    ) throws -> [AssetLocatorSearchRecordV1] {
        try AssetLocatorSearchPersistencePolicyV1().validate()
        guard locators.count <= SearchContractLimitsV1.maximumCanonicalRecords,
              resolutions.count <= SearchContractLimitsV1.maximumCanonicalRecords else {
            throw SearchContractFailureV1.limitExceeded
        }
        try locators.forEach { try $0.validate() }
        try resolutions.forEach { try $0.validate() }

        let orderedLocators = locators.sorted {
            if $0.locatorID != $1.locatorID {
                return $0.locatorID.uuidString.lowercased()
                    < $1.locatorID.uuidString.lowercased()
            }
            return $0.revision < $1.revision
        }
        var latestByLocatorID: [UUID: AssetLocatorV1] = [:]
        for locator in orderedLocators {
            if let prior = latestByLocatorID[locator.locatorID],
               prior.revision == locator.revision {
                throw SearchContractFailureV1.duplicateProjection
            }
            latestByLocatorID[locator.locatorID] = locator
        }

        let currentLocators = latestByLocatorID.values.sorted {
            $0.locatorID.uuidString.lowercased() < $1.locatorID.uuidString.lowercased()
        }
        var records: [AssetLocatorSearchRecordV1] = []
        for locator in currentLocators {
            let matchingResolution = resolutions
                .filter {
                    $0.workspaceID == locator.workspaceID
                        && $0.matchedLocator?.locatorID == locator.locatorID
                        && $0.matchedLocator?.revision == locator.revision
                }
                .sorted {
                    if $0.evaluatedAt != $1.evaluatedAt {
                        return $0.evaluatedAt < $1.evaluatedAt
                    }
                    return $0.resolutionSHA256 < $1.resolutionSHA256
                }
                .last
            records.append(try LocalSearchIndexStoreV1.assetLocatorSearchRecord(
                from: locator,
                resolution: matchingResolution
            ))
        }

        // Keep bounded negative/ambiguous results searchable without copying
        // the input digest or candidate locator references into the index.
        for resolution in resolutions where resolution.matchedLocator == nil {
            let projection = try AssetLocatorReportProjectionV1(resolution: resolution)
            records.append(try LocalSearchIndexStoreV1.assetLocatorSearchRecord(
                from: projection
            ))
        }

        records.sort { $0.projectionIdentity < $1.projectionIdentity }
        guard records.count <= SearchContractLimitsV1.maximumCanonicalRecords,
              Set(records.map(\.projectionIdentity)).count == records.count else {
            throw SearchContractFailureV1.duplicateProjection
        }
        try records.forEach { try AssetLocatorSearchProjectionPolicyV1.validate($0) }
        return records
    }

    static let assetLocatorReplayDisposition =
        "DROP_AND_REBUILD_FROM_CANONICAL_ASSET_LOCATORS_AND_RESOLUTION_HISTORY"
    static let assetLocatorRestoreDisposition =
        "EXCLUDE_LOCATOR_ROWS_AND_REBUILD_AFTER_CANONICAL_RESTORE"
}

// MARK: - C28 schedule occurrence search rebuild

extension SearchIndexRebuildCoordinatorV1 {
    /// Rebuilds the disposable schedule rows from frozen report projections.
    /// Inputs are already derived from canonical release/history records; this
    /// path never reinterprets a device time zone or treats notification
    /// delivery as an occurrence transition.
    static func scheduleOccurrenceSearchRecords(
        from projections: [ScheduleReportProjectionV1]
    ) throws -> [ScheduleOccurrenceSearchRecordV1] {
        try ScheduleOccurrenceSearchPersistencePolicyV1().validate()
        guard projections.count <= SearchContractLimitsV1.maximumCanonicalRecords else {
            throw SearchContractFailureV1.limitExceeded
        }
        try projections.forEach {
            try ScheduleReportProjectionPolicyV1.validate($0)
        }

        var records: [ScheduleOccurrenceSearchRecordV1] = []
        for projection in projections.sorted(by: { $0.projectionSHA256 < $1.projectionSHA256 }) {
            for occurrence in projection.occurrences {
                records.append(try LocalSearchIndexStoreV1.scheduleOccurrenceSearchRecord(
                    from: projection,
                    occurrence: occurrence
                ))
            }
        }
        guard records.count <= SearchContractLimitsV1.maximumProjectionRecords else {
            throw SearchContractFailureV1.limitExceeded
        }
        records.sort { $0.projectionIdentity < $1.projectionIdentity }
        guard Set(records.map(\.projectionIdentity)).count == records.count else {
            throw SearchContractFailureV1.duplicateProjection
        }
        try records.forEach { try ScheduleOccurrenceSearchProjectionPolicyV1.validate($0) }
        return records
    }

    static let scheduleOccurrenceReplayDisposition =
        "DROP_AND_REBUILD_FROM_CANONICAL_SCHEDULE_RELEASE_AND_OCCURRENCE_HISTORY"
    static let scheduleOccurrenceRestoreDisposition =
        "EXCLUDE_SCHEDULE_ROWS_AND_REBUILD_AFTER_CANONICAL_RESTORE"
}

// MARK: - C29 plan placement search rebuild

extension SearchIndexRebuildCoordinatorV1 {
    /// Rebuilds disposable plan placement rows from frozen report projections
    /// in deterministic order. Rebase previews, receipts, source bytes, and
    /// private locator bindings never become search rows.
    static func planPlacementSearchRecords(
        from projections: [PlanReportProjectionV1]
    ) throws -> [PlanPlacementSearchRecordV1] {
        try PlanPlacementSearchPersistencePolicyV1().validate()
        guard projections.count <= SearchContractLimitsV1.maximumCanonicalRecords else {
            throw SearchContractFailureV1.limitExceeded
        }
        try projections.forEach {
            try PlanReportProjectionPolicyV1.validate($0)
        }

        var records: [PlanPlacementSearchRecordV1] = []
        for projection in projections.sorted(by: { $0.projectionSHA256 < $1.projectionSHA256 }) {
            guard projection.placements.count <= PlanLimitsV1.maximumPlacements,
                  records.count <= SearchContractLimitsV1.maximumProjectionRecords
            else {
                throw SearchContractFailureV1.limitExceeded
            }
            for placement in projection.placements {
                records.append(try LocalSearchIndexStoreV1.planPlacementSearchRecord(
                    from: projection,
                    placement: placement
                ))
            }
        }
        guard records.count <= SearchContractLimitsV1.maximumProjectionRecords else {
            throw SearchContractFailureV1.limitExceeded
        }
        records.sort { $0.projectionIdentity < $1.projectionIdentity }
        guard Set(records.map(\.projectionIdentity)).count == records.count else {
            throw SearchContractFailureV1.duplicateProjection
        }
        try records.forEach { try PlanPlacementSearchProjectionPolicyV1.validate($0) }
        return records
    }

    static let planPlacementReplayDisposition =
        "DROP_AND_REBUILD_FROM_FROZEN_PLAN_REPORT_PROJECTIONS"
    static let planPlacementRestoreDisposition =
        "EXCLUDE_PLAN_ROWS_AND_REBUILD_AFTER_CANONICAL_RESTORE"
    static let planPlacementEraseDisposition =
        "DROP_AND_REBUILD_AFTER_PLAN_ERASE"
}

// MARK: - C37 current placement-pose search rebuild

extension SearchIndexRebuildCoordinatorV1 {
    /// Rebuilds current pose-tip rows from immutable report projections in a
    /// stable order. Replays, restores, and Erase drop these rows and invoke
    /// this route again; no sensor or private locator input is accepted.
    static func placementPoseSearchRecords(
        from projections: [C37PlacementPoseReportProjectionV1]
    ) throws -> [C37PoseSearchRecordV1] {
        try C37PoseSearchPersistencePolicyV1().validate()
        guard projections.count <= SearchContractLimitsV1.maximumCanonicalRecords else {
            throw SearchContractFailureV1.limitExceeded
        }
        try projections.forEach { try C37PoseReportProjectionPolicyV1.validate($0) }

        var records: [C37PoseSearchRecordV1] = []
        for projection in projections.sorted(by: { $0.projectionSHA256 < $1.projectionSHA256 }) {
            let rowsByTip = projection.currentTipReferences.compactMap { reference in
                projection.history.first {
                    $0.eventID == reference.eventID
                        && $0.axisID == reference.axisID.rawValue
                        && $0.revision == reference.revision
                        && $0.eventSHA256 == reference.eventSHA256
                }
            }
            guard rowsByTip.count == projection.currentTipReferences.count else {
                throw SearchContractFailureV1.staleIndex
            }
            for row in rowsByTip {
                records.append(try LocalSearchIndexStoreV1.placementPoseSearchRecord(
                    from: projection, row: row
                ))
            }
        }
        guard records.count <= SearchContractLimitsV1.maximumProjectionRecords else {
            throw SearchContractFailureV1.limitExceeded
        }
        records.sort { $0.projectionIdentity < $1.projectionIdentity }
        guard Set(records.map(\.projectionIdentity)).count == records.count else {
            throw SearchContractFailureV1.duplicateProjection
        }
        try records.forEach { try C37PoseSearchProjectionPolicyV1.validate($0) }
        return records
    }

    static let placementPoseReplayDisposition =
        "DROP_AND_REBUILD_FROM_CANONICAL_POSE_HISTORY"
    static let placementPoseRestoreDisposition =
        "EXCLUDE_POSE_ROWS_AND_REBUILD_AFTER_CANONICAL_RESTORE"
    static let placementPoseEraseDisposition =
        "DROP_AND_REBUILD_AFTER_POSE_ERASE"
}
// C30: this seam consumes only the frozen, metadata-only operating-context projection.
enum C30ConsumerBoundaryV1_Infrastructure_Search_SearchIndexRebuildCoordinatorV1 {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Infrastructure/Search/SearchIndexRebuildCoordinatorV1.swift", role: .search)
}

enum C31LightingConsumerBoundary_Infrastructure_Search_SearchIndexRebuildCoordinatorV1 {
    static let registrationID = "C31_LIGHTING_CONSUMER/search-index-rebuild-coordinator"
    static let compatibility = C31LightingCompatibilityPolicyV1()
    static func validate(projection: C31LightingReportProjectionV1) throws {
        try compatibility.validate()
        try C31LightingProjectionPolicyV1.validate(projection)
    }
}

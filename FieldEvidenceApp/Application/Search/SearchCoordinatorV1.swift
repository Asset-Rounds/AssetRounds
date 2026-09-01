import Foundation

protocol SearchIndexSnapshotProvidingV1: Sendable {
    func projection(
        for source: SearchSourceRevisionV1,
        registry: SearchableFieldRegistryV1
    ) async throws -> SearchIndexProjectionV1
}

/// Narrow post-commit and destructive-lifecycle boundary. Canonical writers
/// supply their accepted source revision; consumers never mutate index rows or
/// infer revision authority from derived bytes.
protocol SearchIndexLifecyclePortV1: Sendable {
    func invalidateAfterCanonicalCommit(source: SearchSourceRevisionV1) async throws
    func dropProjection(workspaceID: UUID) async throws
    func purgeWorkspace(_ workspaceID: UUID) async throws
    func eraseAll() async throws
}

struct SearchResponseV1: Equatable, Sendable {
    let plan: SearchQueryPlanV1
    let results: [SearchResultContextV1]
    let suggestions: [SearchSuggestionV1]
}

extension WorkspaceExperienceSearchScopeV1 {
    /// C16 deliberately exposes the five workflow scopes, not the broader
    /// internal index enum. This keeps party records out of product search.
    var searchScope: SearchScopeV1 {
        switch self {
        case .all: return .all
        case .assets: return .assets
        case .locations: return .locations
        case .work: return .work
        case .reports: return .reports
        }
    }
}

/// Executes bounded, deterministic searches over a disposable local projection.
/// Canonical records and their commit revision remain the sole source of truth.
struct SearchCoordinatorV1: Sendable {
    private struct Candidate {
        let record: SearchIndexProjectionRecordV1
        let tier: SearchMatchTierV1
    }

    private let index: any SearchIndexSnapshotProvidingV1

    init(index: any SearchIndexSnapshotProvidingV1) {
        self.index = index
    }

    func makePlan(
        query: String,
        scope: SearchScopeV1 = .all,
        filters: [SearchFilterV1] = [],
        sort: SearchSortV1 = .deterministicRelevance,
        maximumResults: Int = 100,
        sourceRevision: UInt64,
        permitsTypoSuggestions: Bool = true
    ) throws -> SearchQueryPlanV1 {
        let normalizedTokens = Self.normalizedTokens(query)
        guard !normalizedTokens.isEmpty || !filters.isEmpty || sort == .mostRecent else {
            throw SearchContractFailureV1.invalidQuery
        }
        return try SearchQueryPlanV1(
            query: query,
            normalizedTokens: normalizedTokens,
            scope: scope,
            filters: filters,
            sort: sort,
            maximumResults: maximumResults,
            sourceRevision: sourceRevision,
            permitsTypoSuggestions: permitsTypoSuggestions
        )
    }

    func makePlan(
        query: String,
        scope: WorkspaceExperienceSearchScopeV1,
        filters: [SearchFilterV1] = [],
        sort: SearchSortV1 = .deterministicRelevance,
        maximumResults: Int = 100,
        sourceRevision: UInt64,
        permitsTypoSuggestions: Bool = true
    ) throws -> SearchQueryPlanV1 {
        try makePlan(
            query: query,
            scope: scope.searchScope,
            filters: filters,
            sort: sort,
            maximumResults: maximumResults,
            sourceRevision: sourceRevision,
            permitsTypoSuggestions: permitsTypoSuggestions
        )
    }

    func search(
        _ plan: SearchQueryPlanV1,
        source: SearchSourceRevisionV1,
        registry: SearchableFieldRegistryV1
    ) async throws -> SearchResponseV1 {
        try Task.checkCancellation()
        try plan.validate()
        try registry.validate()
        guard plan.sourceRevision == source.commitRevision else {
            throw SearchContractFailureV1.staleIndex
        }

        let projection = try await index.projection(for: source, registry: registry)
        try Task.checkCancellation()

        var bestByCanonicalIdentity: [String: Candidate] = [:]
        var inspected = 0
        for record in projection.records {
            inspected += 1
            if inspected.isMultiple(of: 128) { try Task.checkCancellation() }
            guard plan.scope.contains(record.sourceKind),
                  Self.passes(plan.filters, record: record),
                  let tier = Self.matchTier(plan: plan, record: record) else { continue }

            let identity = record.sourceKind.rawValue + ":" + record.sourceStableID
            let candidate = Candidate(record: record, tier: tier)
            if let prior = bestByCanonicalIdentity[identity] {
                if Self.isBetter(candidate, than: prior) {
                    bestByCanonicalIdentity[identity] = candidate
                }
            } else {
                bestByCanonicalIdentity[identity] = candidate
            }
        }

        var results = try bestByCanonicalIdentity.values.map { candidate in
            try SearchResultContextV1(
                workspaceID: source.workspaceID,
                sourceKind: candidate.record.sourceKind,
                stableID: candidate.record.sourceStableID,
                displayIdentity: candidate.record.displayIdentity,
                locationBreadcrumb: candidate.record.locationBreadcrumb,
                status: candidate.record.status,
                openWorkStableIDs: candidate.record.openWorkStableIDs,
                snippet: candidate.record.permittedSnippet,
                dueAt: candidate.record.dueAt,
                rankingKey: SearchRankingKeyV1(
                    tier: candidate.tier,
                    stableID: candidate.record.sourceStableID,
                    timestamp: candidate.record.sourceTimestamp
                ),
                sourceRevision: source.commitRevision,
                indexRevision: projection.index.indexedCommitRevision
            )
        }
        results.sort { Self.resultPrecedes($0, $1, sort: plan.sort) }
        if results.count > plan.maximumResults {
            results.removeLast(results.count - plan.maximumResults)
        }

        let suggestions = plan.permitsTypoSuggestions
            ? try Self.suggestions(plan: plan, records: projection.records)
            : []
        return SearchResponseV1(plan: plan, results: results, suggestions: suggestions)
    }

    /// Query text remains only in the in-memory plan supplied by this call;
    /// it is never made a device preference or durable navigation state.
    func search(
        _ plan: SearchQueryPlanV1,
        source: SearchSourceRevisionV1,
        registry: SearchableFieldRegistryV1,
        accessGate: any AppAccessGatePortV1
    ) async throws -> SearchResponseV1 {
        _ = try await accessGate.requireContentAccess(for: .search)
        return try await search(plan, source: source, registry: registry)
    }

    /// Locale-independent normalization used both by canonical projectors and
    /// query planning. Formatting/control scalars cannot become search tokens.
    static func normalize(_ value: String) -> String {
        SearchContractValidationV1.normalizeSearchText(value)
    }

    static func normalizedTokens(_ value: String) -> [String] {
        let normalized = normalize(value)
        let pieces = normalized.unicodeScalars.split {
            !CharacterSet.alphanumerics.contains($0)
        }
        var observed = Set<String>()
        var result: [String] = []
        for piece in pieces {
            let token = String(String.UnicodeScalarView(piece))
                .precomposedStringWithCanonicalMapping
            guard !token.isEmpty,
                  token.utf8.count <= SearchContractLimitsV1.maximumNormalizedTokenBytes,
                  observed.insert(token).inserted else { continue }
            result.append(token)
            if result.count == SearchContractLimitsV1.maximumQueryTokens { break }
        }
        return result
    }
}

extension SearchCoordinatorV1 {
    /// Converts an already-authorized safe asset result into the same canonical
    /// preview used by scan and manual entry. The index contributes only its
    /// stable asset identity; raw scan payloads are never accepted or stored.
    static func scanToWorkPreview(
        from result: SearchResultContextV1,
        assetID: UUID,
        workspaceID: WorkspaceID,
        selectedAssetIDs: Set<UUID>,
        existingRound: RoundSessionReferenceV1?,
        resolver: any ScanToWorkExactResolvingV1,
        accessGate: any AppAccessGatePortV1
    ) async throws -> AssetPreviewStateV1 {
        _ = try await accessGate.requireContentAccess(for: .search)
        try result.validate()
        let expectedStableID = try WorkspaceEntityIdentityV1(kind: .asset, id: assetID).stableKey
        guard result.workspaceID == workspaceID.rawValue,
              result.sourceKind == .asset,
              result.stableID == expectedStableID,
              result.sourceRevision == result.indexRevision,
              existingRound.map({ $0.workspaceID == workspaceID }) ?? true else {
            throw ScanToWorkFailureV1.authorityMismatch
        }
        let preview = try await resolver.preview(
            workspaceID: workspaceID,
            source: .search,
            rawBytes: Data(expectedStableID.utf8),
            selectedAssetIDs: selectedAssetIDs,
            existingRound: existingRound
        )
        try preview.validateIntrinsic()
        guard preview.workspaceID == workspaceID, preview.source == .search,
              preview.asset.map({ $0.assetID == assetID }) ?? (preview.outcome != .ready) else {
            throw ScanToWorkFailureV1.authorityMismatch
        }
        return preview
    }
}

private extension SearchCoordinatorV1 {
    static func matchTier(
        plan: SearchQueryPlanV1,
        record: SearchIndexProjectionRecordV1
    ) -> SearchMatchTierV1? {
        if plan.normalizedTokens.isEmpty { return .normalizedExactToken }
        let stableIdentity = normalize(record.sourceStableID)
        let displayIdentity = normalize(record.displayIdentity)
        let normalizedQuery = normalize(plan.query).trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedQuery == stableIdentity || normalizedQuery == displayIdentity {
            return .exactStableOrDisplayIdentity
        }

        let recordTokens = record.normalizedTokens
        guard !recordTokens.isEmpty else { return nil }
        var worstTier = SearchMatchTierV1.normalizedExactToken
        for queryToken in plan.normalizedTokens {
            let tier: SearchMatchTierV1?
            if recordTokens.contains(queryToken) {
                tier = .normalizedExactToken
            } else if stableIdentity.hasPrefix(queryToken) || displayIdentity.hasPrefix(queryToken) {
                tier = .prefix
            } else if recordTokens.contains(where: { $0.hasPrefix(queryToken) }) {
                tier = .tokenPrefix
            } else if recordTokens.contains(where: { $0.contains(queryToken) })
                        || displayIdentity.contains(queryToken) {
                tier = .substring
            } else {
                tier = nil
            }
            guard let tier else { return nil }
            if tier > worstTier { worstTier = tier }
        }
        return worstTier
    }

    static func passes(
        _ filters: [SearchFilterV1],
        record: SearchIndexProjectionRecordV1
    ) -> Bool {
        guard !filters.isEmpty else { return true }
        let statusTerms = Set(normalizedTokens(record.status))
        let terms = statusTerms.union(record.normalizedTokens)
        return filters.allSatisfy { filter in
            switch filter.kind {
            case .incomplete:
                let terminal: Set<String> = ["completed", "resolved", "ready", "failed"]
                guard terminal.isDisjoint(with: statusTerms) else { return false }
                let unfinished: Set<String> = ["draft", "open", "pending", "incomplete"]
                return !unfinished.isDisjoint(with: statusTerms)
                    || (statusTerms.contains("recheck") && statusTerms.contains("due"))
                    || (statusTerms.contains("in") && statusTerms.contains("progress"))
            case .recheckDue:
                return statusTerms.contains("recheck") && statusTerms.contains("due")
            case .reportFailed:
                return record.sourceKind == .report && statusTerms.contains("failed")
            case .backupStale:
                return terms.contains("backup") && terms.contains("stale")
            }
        }
    }

    static func isBetter(_ lhs: Candidate, than rhs: Candidate) -> Bool {
        if lhs.tier != rhs.tier { return lhs.tier < rhs.tier }
        if lhs.record.projectionIdentity != rhs.record.projectionIdentity {
            return lhs.record.projectionIdentity < rhs.record.projectionIdentity
        }
        if lhs.record.sourceTimestamp != rhs.record.sourceTimestamp {
            return lhs.record.sourceTimestamp > rhs.record.sourceTimestamp
        }
        return false
    }

    static func resultPrecedes(
        _ lhs: SearchResultContextV1,
        _ rhs: SearchResultContextV1,
        sort: SearchSortV1
    ) -> Bool {
        switch sort {
        case .deterministicRelevance:
            if lhs.rankingKey != rhs.rankingKey {
                return lhs.rankingKey < rhs.rankingKey
            }
        case .mostRecent:
            if lhs.rankingKey.timestamp != rhs.rankingKey.timestamp {
                return lhs.rankingKey.timestamp > rhs.rankingKey.timestamp
            }
        case .oldestFirst:
            if lhs.rankingKey.timestamp != rhs.rankingKey.timestamp {
                return lhs.rankingKey.timestamp < rhs.rankingKey.timestamp
            }
        case .statusThenStableID:
            let lhsStatus = normalize(lhs.status)
            let rhsStatus = normalize(rhs.status)
            if lhsStatus != rhsStatus { return lhsStatus < rhsStatus }
            if lhs.stableID != rhs.stableID { return lhs.stableID < rhs.stableID }
            return lhs.sourceKind.rawValue < rhs.sourceKind.rawValue
        case .dueDateThenStableID:
            switch (lhs.dueAt, rhs.dueAt) {
            case let (left?, right?) where left != right:
                return left < right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                break
            }
            if lhs.stableID != rhs.stableID { return lhs.stableID < rhs.stableID }
            return lhs.sourceKind.rawValue < rhs.sourceKind.rawValue
        }
        if lhs.sourceKind != rhs.sourceKind { return lhs.sourceKind.rawValue < rhs.sourceKind.rawValue }
        return lhs.stableID < rhs.stableID
    }

    static func suggestions(
        plan: SearchQueryPlanV1,
        records: [SearchIndexProjectionRecordV1]
    ) throws -> [SearchSuggestionV1] {
        var bestByToken: [String: SearchSuggestionV1] = [:]
        let unmatchedQueryTokens = plan.normalizedTokens.filter { queryToken in
            !records.lazy.filter({ plan.scope.contains($0.sourceKind) }).contains(where: { record in
                record.normalizedTokens.contains(where: {
                    $0 == queryToken || $0.hasPrefix(queryToken) || $0.contains(queryToken)
                })
            })
        }
        guard !unmatchedQueryTokens.isEmpty else { return [] }
        var inspected = 0
        for record in records where plan.scope.contains(record.sourceKind) {
            for candidate in record.normalizedTokens {
                inspected += 1
                if inspected.isMultiple(of: 256) { try Task.checkCancellation() }
                guard !plan.normalizedTokens.contains(candidate) else { continue }
                for queryToken in unmatchedQueryTokens {
                    let maximumDistance = maximumTypoDistance(forQueryToken: queryToken)
                    guard maximumDistance > 0,
                          abs(candidate.count - queryToken.count) <= maximumDistance,
                          let distance = boundedEditDistance(
                            queryToken,
                            candidate,
                            maximum: maximumDistance
                          ), distance > 0 else { continue }
                    let suggestion = try SearchSuggestionV1(
                        suggestedToken: candidate,
                        editDistance: distance,
                        sourceStableID: record.sourceStableID
                    )
                    if let prior = bestByToken[candidate] {
                        if suggestion < prior { bestByToken[candidate] = suggestion }
                    } else {
                        bestByToken[candidate] = suggestion
                    }
                }
            }
        }
        return try SearchSuggestionV1.validatedSet(
            Array(bestByToken.values.sorted().prefix(SearchContractLimitsV1.maximumSuggestions))
        )
    }

    static func boundedEditDistance(
        _ lhs: String,
        _ rhs: String,
        maximum: Int
    ) -> Int? {
        let left = Array(lhs)
        let right = Array(rhs)
        guard abs(left.count - right.count) <= maximum else { return nil }
        var previous = Array(0...right.count)
        for (leftIndex, leftCharacter) in left.enumerated() {
            var current = [leftIndex + 1]
            var rowMinimum = current[0]
            for (rightIndex, rightCharacter) in right.enumerated() {
                let insertion = current[rightIndex] + 1
                let deletion = previous[rightIndex + 1] + 1
                let substitution = previous[rightIndex] + (leftCharacter == rightCharacter ? 0 : 1)
                let value = min(insertion, deletion, substitution)
                current.append(value)
                rowMinimum = min(rowMinimum, value)
            }
            if rowMinimum > maximum { return nil }
            previous = current
        }
        guard let result = previous.last, result <= maximum else { return nil }
        return result
    }

    static func maximumTypoDistance(forQueryToken token: String) -> Int {
        switch token.count {
        case 0...3: return 0
        case 4...7: return 1
        default: return 2
        }
    }
}

// MARK: - C26 guided-survey session metadata search

extension SearchCoordinatorV1 {
    private static func searchSurveyDefinitionMetadataAfterAccess(
        query: String,
        workspaceID: WorkspaceID,
        records: [SurveyDefinitionSearchRecordV1],
        identities: [SurveyDefinitionIdentityV1],
        maximumResults: Int
    ) throws -> [SurveyDefinitionSearchRecordV1] {
        guard maximumResults > 0,
              maximumResults <= SearchContractLimitsV1.maximumCanonicalRecords,
              records.count <= SearchContractLimitsV1.maximumProjectionRecords,
              identities.count <= SearchContractLimitsV1.maximumCanonicalRecords,
              identities.allSatisfy({ $0.workspaceID == workspaceID }) else {
            throw SearchContractFailureV1.scopeMismatch
        }
        try records.forEach { try SurveyDefinitionSearchProjectionPolicyV1.validate($0) }
        try identities.forEach { try $0.validateIntrinsic() }
        guard Set(identities.map(\.definitionID)).count == identities.count else {
            throw SearchContractFailureV1.duplicateProjection
        }
        let currentByDefinitionID = Dictionary(uniqueKeysWithValues: identities.map {
            ($0.definitionID.uuidString.lowercased(), $0)
        })
        guard records.allSatisfy({ record in
                  guard let identity = currentByDefinitionID[record.definitionID] else { return false }
                  return record.releaseID == identity.currentRelease.releaseID.uuidString.lowercased()
                      && record.releaseRevision == identity.currentRelease.revision
                      && record.releaseSHA256 == identity.currentRelease.releaseSHA256
                      && record.lifecycleState == identity.lifecycleState
              }) else {
            throw SearchContractFailureV1.staleIndex
        }
        let tokens = normalizedTokens(query)
        guard !tokens.isEmpty else { throw SearchContractFailureV1.invalidQuery }
        return Array(records.filter { record in
            tokens.allSatisfy { queryToken in
                record.normalizedTokens.contains {
                    $0 == queryToken || $0.hasPrefix(queryToken)
                }
            }
        }.sorted { ($0.definitionID, $0.releaseID) < ($1.definitionID, $1.releaseID) }
            .prefix(maximumResults))
    }

    /// Searches the derived current-template library only. Identity bindings
    /// prove workspace scope and prevent a historical release from being
    /// presented as the current definition. Favorites and recents are caller
    /// overlays and never enter this index contract.
    static func searchSurveyDefinitionMetadata(
        query: String,
        workspaceID: WorkspaceID,
        records: [SurveyDefinitionSearchRecordV1],
        identities: [SurveyDefinitionIdentityV1],
        maximumResults: Int = 100,
        accessGate: any AppAccessGatePortV1
    ) async throws -> [SurveyDefinitionSearchRecordV1] {
        let permit = try await accessGate.requireContentAccess(for: .search)
        guard permit.surface == .search, permit.state.permitsContentAccess else {
            throw AppAccessContentReadFailureV1.denied(surface: .search, state: permit.state)
        }
        return try searchSurveyDefinitionMetadataAfterAccess(
            query: query,
            workspaceID: workspaceID,
            records: records,
            identities: identities,
            maximumResults: maximumResults
        )
    }

    /// Returns the C20 derived library rows corresponding to current-tip
    /// search matches. Device-local favorite/recent values may order the
    /// presentation result but are never copied into an index record.
    static func searchSurveyDefinitionLibrary(
        query: String,
        workspaceID: WorkspaceID,
        records: [SurveyDefinitionSearchRecordV1],
        libraryRows: [SurveyDefinitionLibraryRowV1],
        authoringPolicy: SurveyAuthoringPolicyV1,
        maximumResults: Int = 100,
        accessGate: any AppAccessGatePortV1
    ) async throws -> [SurveyDefinitionLibraryRowV1] {
        let permit = try await accessGate.requireContentAccess(for: .search)
        guard permit.surface == .search, permit.state.permitsContentAccess else {
            throw AppAccessContentReadFailureV1.denied(surface: .search, state: permit.state)
        }
        try authoringPolicy.validate()
        guard libraryRows.count <= SearchContractLimitsV1.maximumCanonicalRecords,
              libraryRows.allSatisfy({ $0.identity.workspaceID == workspaceID }),
              Set(libraryRows.map { $0.identity.definitionID }).count == libraryRows.count else {
            throw SearchContractFailureV1.scopeMismatch
        }
        try libraryRows.forEach { row in
            try row.identity.validateIntrinsic()
            try row.release.validate()
            guard row.identity.currentRelease == row.release,
                  row.identity.lifecycleState == row.lifecycleState else {
                throw SearchContractFailureV1.staleIndex
            }
        }
        let matches = try searchSurveyDefinitionMetadataAfterAccess(
            query: query,
            workspaceID: workspaceID,
            records: records,
            identities: libraryRows.map(\.identity),
            maximumResults: SearchContractLimitsV1.maximumCanonicalRecords
        )
        let matchedIDs = Set(matches.map(\.definitionID))
        let ordered = libraryRows.filter {
            matchedIDs.contains($0.identity.definitionID.uuidString.lowercased())
        }.sorted {
            if $0.favorite != $1.favorite { return $0.favorite && !$1.favorite }
            switch ($0.recentOrdinal, $1.recentOrdinal) {
            case let (left?, right?) where left != right: return left < right
            case (_?, nil): return true
            case (nil, _?): return false
            default:
                return $0.identity.definitionID.uuidString.lowercased()
                    < $1.identity.definitionID.uuidString.lowercased()
            }
        }
        guard maximumResults > 0,
              maximumResults <= SearchContractLimitsV1.maximumCanonicalRecords else {
            throw SearchContractFailureV1.limitExceeded
        }
        return Array(ordered.prefix(maximumResults))
    }

    /// Searches only the C26 disposable metadata rows.  This path is kept
    /// separate from the general index response so it cannot accidentally
    /// surface answers, prompts, actor identity, or evidence references.
    static func searchSurveySessionMetadata(
        query: String,
        records: [SurveySessionSearchRecordV1],
        maximumResults: Int = 100
    ) throws -> [SurveySessionSearchRecordV1] {
        guard maximumResults > 0,
              maximumResults <= SearchContractLimitsV1.maximumCanonicalRecords else {
            throw SearchContractFailureV1.limitExceeded
        }
        let tokens = normalizedTokens(query)
        guard !tokens.isEmpty else { throw SearchContractFailureV1.invalidQuery }
        try records.forEach { try SurveySessionSearchProjectionPolicyV1.validate($0) }
        let matches = records.filter { record in
            tokens.allSatisfy { queryToken in
                record.normalizedTokens.contains { indexedToken in
                    indexedToken == queryToken || indexedToken.hasPrefix(queryToken)
                }
            }
        }.sorted {
            if $0.sessionID != $1.sessionID {
                return $0.sessionID.uuidString < $1.sessionID.uuidString
            }
            return $0.projectionIdentity < $1.projectionIdentity
        }
        return Array(matches.prefix(maximumResults))
    }

    /// Access is checked before scope, record, or query validation so a denied
    /// caller cannot probe another workspace through error differences.
    static func searchSurveySessionMetadata(
        query: String,
        workspaceID: WorkspaceID,
        records: [SurveySessionSearchRecordV1],
        maximumResults: Int = 100,
        accessGate: any AppAccessGatePortV1
    ) async throws -> [SurveySessionSearchRecordV1] {
        let permit = try await accessGate.requireContentAccess(for: .search)
        guard permit.surface == .search, permit.state.permitsContentAccess else {
            throw AppAccessContentReadFailureV1.denied(surface: .search, state: permit.state)
        }
        guard records.count <= SearchContractLimitsV1.maximumProjectionRecords,
              records.allSatisfy({ $0.workspaceID == workspaceID.rawValue }) else {
            throw SearchContractFailureV1.scopeMismatch
        }
        return try searchSurveySessionMetadata(
            query: query,
            records: records,
            maximumResults: maximumResults
        )
    }

    /// Resolves session metadata matches to C20 nonpersistent flow projections.
    /// Exact session revision and definition bindings prevent a historic flow
    /// from being surfaced as current; overlay ordering remains device-local.
    static func searchGuidedSurveyFlows(
        query: String,
        workspaceID: WorkspaceID,
        records: [SurveySessionSearchRecordV1],
        flows: [GuidedSurveyFlowV1],
        authoringPolicy: SurveyAuthoringPolicyV1,
        maximumResults: Int = 100,
        accessGate: any AppAccessGatePortV1
    ) async throws -> [GuidedSurveyFlowV1] {
        let permit = try await accessGate.requireContentAccess(for: .search)
        guard permit.surface == .search, permit.state.permitsContentAccess else {
            throw AppAccessContentReadFailureV1.denied(surface: .search, state: permit.state)
        }
        try authoringPolicy.validate()
        try flows.forEach { try $0.validate() }
        guard flows.count <= SearchContractLimitsV1.maximumCanonicalRecords,
              flows.allSatisfy({ $0.workspaceID == workspaceID }),
              Set(flows.map(\.sessionID)).count == flows.count,
              records.allSatisfy({ $0.workspaceID == workspaceID.rawValue }),
              Set(records.map(\.sessionID)).count == records.count else {
            throw SearchContractFailureV1.scopeMismatch
        }
        let recordsBySessionID = Dictionary(uniqueKeysWithValues: records.map { ($0.sessionID, $0) })
        guard flows.allSatisfy({ flow in
                  guard let record = recordsBySessionID[flow.sessionID] else { return false }
                  return record.sessionRevision == flow.sessionRevision
                      && record.definitionID == flow.definition.definitionID
                      && record.definitionReleaseID == flow.definition.releaseID
              }) else {
            throw SearchContractFailureV1.staleIndex
        }
        let matches = try searchSurveySessionMetadata(
            query: query,
            records: records,
            maximumResults: SearchContractLimitsV1.maximumCanonicalRecords
        )
        let matchedIDs = Set(matches.map(\.sessionID))
        let ordered = flows.filter { matchedIDs.contains($0.sessionID) }.sorted {
            if $0.favorite != $1.favorite { return $0.favorite && !$1.favorite }
            switch ($0.recentOrdinal, $1.recentOrdinal) {
            case let (left?, right?) where left != right: return left < right
            case (_?, nil): return true
            case (nil, _?): return false
            default: return $0.sessionID.uuidString < $1.sessionID.uuidString
            }
        }
        guard maximumResults > 0,
              maximumResults <= SearchContractLimitsV1.maximumCanonicalRecords else {
            throw SearchContractFailureV1.limitExceeded
        }
        return Array(ordered.prefix(maximumResults))
    }
}

enum C20GuidedSurveySearchBoundaryV1 {
    static let definitionRowsAreCurrentIdentityTipsOnly = true
    static let sessionRowsAreTerminalCurrentTipsOnly = true
    static let historicOpeningIsSeparateFromCurrentSearch = true
    static let favoritesAndRecentsAreDeviceLocalOverlays = true
    static let accessSurface: AppAccessContentReadSurfaceV1 = .search
}

extension SearchCoordinatorV1 {
    static func searchAdvancedScheduleOccurrenceMetadata(
        query: String,
        records: [AdvancedScheduleOccurrenceSearchRecordV1],
        maximumResults: Int = 100
    ) throws -> [AdvancedScheduleOccurrenceSearchRecordV1] {
        guard maximumResults > 0, maximumResults <= SearchContractLimitsV1.maximumCanonicalRecords else {
            throw SearchContractFailureV1.limitExceeded
        }
        let tokens = normalizedTokens(query)
        guard !tokens.isEmpty else { throw SearchContractFailureV1.invalidQuery }
        try records.forEach(AdvancedScheduleOccurrenceSearchProjectionPolicyV1.validate)
        return Array(records.filter { record in tokens.allSatisfy { query in
            record.normalizedTokens.contains { $0 == query || $0.hasPrefix(query) }
        }}.sorted { $0.projectionIdentity < $1.projectionIdentity }.prefix(maximumResults))
    }
}

// MARK: - C30 operating-context search

extension SearchCoordinatorV1 {
    static func searchOperatingContextMetadata(
        query: String,
        records: [C30OperatingContextSearchRecordV1],
        maximumResults: Int = 100
    ) throws -> [C30OperatingContextSearchRecordV1] {
        guard maximumResults > 0,
              maximumResults <= SearchContractLimitsV1.maximumCanonicalRecords else {
            throw SearchContractFailureV1.limitExceeded
        }
        let tokens = normalizedTokens(query)
        guard !tokens.isEmpty else { throw SearchContractFailureV1.invalidQuery }
        try records.forEach { try C30OperatingContextSearchPolicyV1.validate($0) }
        return Array(records.filter { record in
            tokens.allSatisfy { queryToken in
                record.normalizedTokens.contains {
                    $0 == queryToken || $0.hasPrefix(queryToken)
                }
            }
        }.sorted {
            ($0.evidenceID, $0.contextRevision) < ($1.evidenceID, $1.contextRevision)
        }.prefix(maximumResults))
    }
}

// MARK: - C29 plan placement metadata search

extension SearchCoordinatorV1 {
    /// Searches only the disposable plan placement metadata projection. A
    /// preview, source reference, subject identifier, or component payload is
    /// never treated as searchable report truth.
    static func searchPlanPlacementMetadata(
        query: String,
        records: [PlanPlacementSearchRecordV1],
        maximumResults: Int = 100
    ) throws -> [PlanPlacementSearchRecordV1] {
        guard maximumResults > 0,
              maximumResults <= SearchContractLimitsV1.maximumCanonicalRecords else {
            throw SearchContractFailureV1.limitExceeded
        }
        let tokens = normalizedTokens(query)
        guard !tokens.isEmpty else { throw SearchContractFailureV1.invalidQuery }
        try records.forEach { try PlanPlacementSearchProjectionPolicyV1.validate($0) }
        let matches = records.filter { record in
            tokens.allSatisfy { queryToken in
                record.normalizedTokens.contains { indexedToken in
                    indexedToken == queryToken || indexedToken.hasPrefix(queryToken)
                }
            }
        }.sorted { $0.projectionIdentity < $1.projectionIdentity }
        return Array(matches.prefix(maximumResults))
    }
}

// MARK: - C19 current plan-document metadata search

extension SearchCoordinatorV1 {
    private static func searchPlanDocumentMetadataAfterAccess(
        query: String,
        workspaceID: WorkspaceID,
        records: [PlanDocumentSearchRecordV1],
        maximumResults: Int = 100
    ) throws -> [PlanDocumentSearchRecordV1] {
        guard maximumResults > 0,
              maximumResults <= SearchContractLimitsV1.maximumCanonicalRecords,
              records.count <= SearchContractLimitsV1.maximumProjectionRecords,
              records.allSatisfy({ $0.workspaceID == workspaceID }) else {
            throw SearchContractFailureV1.scopeMismatch
        }
        try records.forEach { try PlanDocumentSearchProjectionPolicyV1.validate($0) }
        let tokens = normalizedTokens(query)
        guard !tokens.isEmpty else { throw SearchContractFailureV1.invalidQuery }
        return Array(records.filter { record in
            tokens.allSatisfy { queryToken in
                record.normalizedTokens.contains {
                    $0 == queryToken || $0.hasPrefix(queryToken)
                }
            }
        }.sorted { $0.projectionIdentity < $1.projectionIdentity }
            .prefix(maximumResults))
    }

    /// Access is checked before any record validation or query normalization,
    /// so denied callers cannot probe index shape through error differences.
    static func searchPlanDocumentMetadata(
        query: String,
        workspaceID: WorkspaceID,
        records: [PlanDocumentSearchRecordV1],
        maximumResults: Int = 100,
        accessGate: any AppAccessGatePortV1
    ) async throws -> [PlanDocumentSearchRecordV1] {
        let permit = try await accessGate.requireContentAccess(for: .search)
        guard permit.surface == .search, permit.state.permitsContentAccess else {
            throw AppAccessContentReadFailureV1.denied(surface: .search, state: permit.state)
        }
        return try searchPlanDocumentMetadataAfterAccess(
            query: query,
            workspaceID: workspaceID,
            records: records,
            maximumResults: maximumResults
        )
    }
}

enum C19PlanDocumentSearchCoordinatorBoundaryV1 {
    static let currentTipsComeOnlyFromCanonicalHistoryRebuild = true
    static let historicOpenSelectionIsNeverPublishedAsCurrent = true
    static let zeroPlacementDocumentsRemainSearchable = true
    static let queryTextIsNeverDurable = true
    static let accessSurface: AppAccessContentReadSurfaceV1 = .search
}

// MARK: - C27 asset-locator metadata search

extension SearchCoordinatorV1 {
    /// Searches only the disposable C27 metadata rows.  Queries are matched
    /// against canonical IDs and closed state tokens; raw locator input and
    /// external-key values are intentionally absent from the rows.
    static func searchAssetLocatorMetadata(
        query: String,
        records: [AssetLocatorSearchRecordV1],
        maximumResults: Int = 100
    ) throws -> [AssetLocatorSearchRecordV1] {
        guard maximumResults > 0,
              maximumResults <= SearchContractLimitsV1.maximumCanonicalRecords else {
            throw SearchContractFailureV1.limitExceeded
        }
        let tokens = normalizedTokens(query)
        guard !tokens.isEmpty else { throw SearchContractFailureV1.invalidQuery }
        try records.forEach { try AssetLocatorSearchProjectionPolicyV1.validate($0) }
        let matches = records.filter { record in
            tokens.allSatisfy { queryToken in
                record.normalizedTokens.contains { indexedToken in
                    indexedToken == queryToken || indexedToken.hasPrefix(queryToken)
                }
            }
        }.sorted { $0.projectionIdentity < $1.projectionIdentity }
        return Array(matches.prefix(maximumResults))
    }
}

// MARK: - C28 schedule occurrence metadata search

extension SearchCoordinatorV1 {
    /// Searches only the disposable schedule metadata projection. Matching is
    /// limited to canonical IDs, frozen local-basis values, and the closed
    /// occurrence state; a reminder request can never become search truth.
    static func searchScheduleOccurrenceMetadata(
        query: String,
        records: [ScheduleOccurrenceSearchRecordV1],
        maximumResults: Int = 100
    ) throws -> [ScheduleOccurrenceSearchRecordV1] {
        guard maximumResults > 0,
              maximumResults <= SearchContractLimitsV1.maximumCanonicalRecords else {
            throw SearchContractFailureV1.limitExceeded
        }
        let tokens = normalizedTokens(query)
        guard !tokens.isEmpty else { throw SearchContractFailureV1.invalidQuery }
        try records.forEach { try ScheduleOccurrenceSearchProjectionPolicyV1.validate($0) }
        let matches = records.filter { record in
            tokens.allSatisfy { queryToken in
                record.normalizedTokens.contains { indexedToken in
                    indexedToken == queryToken || indexedToken.hasPrefix(queryToken)
                }
            }
        }.sorted { $0.projectionIdentity < $1.projectionIdentity }
        return Array(matches.prefix(maximumResults))
    }

    /// Access is checked before inspecting the disposable index. Every row is
    /// then constrained to one workspace and an explicitly supplied current
    /// release frontier; reminder state is neither accepted nor queried.
    static func searchCurrentScheduleOccurrenceMetadata(
        query: String,
        workspaceID: WorkspaceID,
        records: [ScheduleOccurrenceSearchRecordV1],
        currentReleases: [ScheduleDefinitionReleaseReferenceV1],
        maximumResults: Int = 100,
        accessGate: any AppAccessGatePortV1
    ) async throws -> [ScheduleOccurrenceSearchRecordV1] {
        let permit = try await accessGate.requireContentAccess(for: .search)
        guard permit.surface == .search, permit.state.permitsContentAccess else {
            throw AppAccessContentReadFailureV1.denied(surface: .search, state: permit.state)
        }
        try currentReleases.forEach { try $0.validate() }
        guard records.allSatisfy({ $0.workspaceID == workspaceID.rawValue }),
              currentReleases.allSatisfy({ $0.workspaceID == workspaceID }),
              Set(currentReleases.map(\.scheduleDefinitionID)).count == currentReleases.count else {
            throw SearchContractFailureV1.scopeMismatch
        }
        guard records.allSatisfy({ record in
            currentReleases.contains {
                $0.scheduleDefinitionID == record.scheduleDefinitionID &&
                $0.releaseID == record.releaseID &&
                $0.releaseSHA256 == record.releaseSHA256
            }
        }) else { throw SearchContractFailureV1.scopeMismatch }
        return try searchScheduleOccurrenceMetadata(
            query: query,
            records: records,
            maximumResults: maximumResults
        )
    }
}

// MARK: - C37 current placement-pose metadata search

extension SearchCoordinatorV1 {
    /// Searches only current pose tips. Full pose history is intentionally
    /// rendered by the report timeline and is not flattened into the index.
    static func searchPlacementPoseMetadata(
        query: String,
        records: [C37PoseSearchRecordV1],
        maximumResults: Int = 100
    ) throws -> [C37PoseSearchRecordV1] {
        guard maximumResults > 0,
              maximumResults <= SearchContractLimitsV1.maximumCanonicalRecords else {
            throw SearchContractFailureV1.limitExceeded
        }
        let tokens = normalizedTokens(query)
        guard !tokens.isEmpty else { throw SearchContractFailureV1.invalidQuery }
        try records.forEach { try C37PoseSearchProjectionPolicyV1.validate($0) }
        let matches = records.filter { record in
            tokens.allSatisfy { queryToken in
                record.normalizedTokens.contains { indexedToken in
                    indexedToken == queryToken || indexedToken.hasPrefix(queryToken)
                }
            }
        }.sorted { $0.projectionIdentity < $1.projectionIdentity }
        return Array(matches.prefix(maximumResults))
    }
}
// C30: this seam consumes only the frozen, metadata-only operating-context projection.
enum C30ConsumerBoundaryV1_Application_Search_SearchCoordinatorV1 {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Application/Search/SearchCoordinatorV1.swift", role: .search)
}

enum C31LightingConsumerBoundary_Application_Search_SearchCoordinatorV1 {
    static let registrationID = "C31_LIGHTING_CONSUMER/search-coordinator"
    static let compatibility = C31LightingCompatibilityPolicyV1()
    static func validate(projection: C31LightingReportProjectionV1) throws {
        try compatibility.validate()
        try C31LightingProjectionPolicyV1.validate(projection)
    }
}

// MARK: - C32 assistance search isolation boundary

enum C32AssistanceSearchBoundaryV1_Application_Search_SearchCoordinatorV1 {
    static let proposalPersistenceDisposition = "NONPERSISTENT"
    static let durableFamily = "AssistanceAcceptanceReceiptV1"
    static let acceptedMutationKind: WorkspaceCommandKindV1 = .applyAssistanceAcceptance
    static let proposalsAreExcludedFromIndex = true

    static func validateProposal(
        _ proposal: AssistanceProposalV1,
        in context: AssistanceProposalEvaluationContextV1
    ) throws {
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

enum C33TemporalEvidenceBoundary_Application_Search_SearchCoordinatorV1_V1 {
    static let clipType: TemporalEvidenceClipV1.Type = TemporalEvidenceClipV1.self
    static let anchorType: TimecodedEvidenceAnchorV1.Type = TimecodedEvidenceAnchorV1.self
    static let persistentSchemaVersion: Int =
        TemporalEvidencePersistenceEnrollmentV1.persistentSchemaVersion
}

enum C45AcceptedLabelSearchCoordinatorBoundaryV1 { static let acceptedSnapshotMetadataIsProjected=true;static let forbiddenCustomerTextIsProjected=false;static let reprintUsesTypedQuery=true }

enum C46OperationalContactBoundary_35{static let permittedProjection="PARTY_METADATA_ONLY";static let rawPhoneOrEmailIndexed=false}

enum C34RouteAdoptionBoundary_SearchCoordinatorV1 {
    static let searchAnchorType = RouteSearchAnchorV1.self
    static let canonicalTargetType = NavigationTargetV1.self
    static let routeStoresQueryText = false
}

// MARK: - C52 lifecycle and privacy boundary
enum C52ServiceRequestBoundary_FieldEvidenceApp_Application_Search_SearchCoordinatorV1_swift {
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


// MARK: - C57 My Day derived metadata search

extension SearchCoordinatorV1 {
    static func searchMyDayMetadata(
        query: String,
        workspaceID: WorkspaceID,
        records: [C57MyDaySearchRecordV1],
        maximumResults: Int = 100
    ) throws -> [C57MyDaySearchRecordV1] {
        guard maximumResults > 0,
              maximumResults <= SearchContractLimitsV1.maximumCanonicalRecords,
              records.count <= SearchContractLimitsV1.maximumProjectionRecords else {
            throw SearchContractFailureV1.limitExceeded
        }
        guard records.allSatisfy({ $0.workspaceID == workspaceID }) else {
            throw SearchContractFailureV1.scopeMismatch
        }
        try records.forEach { try $0.validate() }
        let tokens = normalizedTokens(query)
        guard !tokens.isEmpty else { throw SearchContractFailureV1.invalidQuery }
        let matches = records.filter { record in
            tokens.allSatisfy { queryToken in
                record.normalizedTokens.contains { indexedToken in
                    indexedToken == queryToken || indexedToken.hasPrefix(queryToken)
                }
            }
        }.sorted { $0.projectionIdentity < $1.projectionIdentity }
        return Array(matches.prefix(maximumResults))
    }
}

enum C57MyDaySearchCoordinatorBoundaryV1 {
    static let queryReadsDerivedRowsOnly = true
    static let queryCannotMutatePlanOrSourceWork = true
    static let workspaceScopeIsRequired = true
}

// MARK: - C14 private system-discovery lifecycle

/// Application-level adapter used by the incumbent composition root. It owns
/// no index and forwards only validated lifecycle inputs to the one actor.
struct PrivateSystemDiscoverySearchLifecycleV1: Sendable {
    private let index: any PrivateSystemDiscoveryIndexLifecyclePortV1

    init(index: any PrivateSystemDiscoveryIndexLifecyclePortV1) {
        self.index = index
    }

    func removeDeletedWorkspace(
        operationID: PrivateSystemDiscoveryOperationIDV1,
        workspaceID: WorkspaceID,
        now: Date
    ) async throws {
        try await index.remove(operationID: operationID, workspaceID: workspaceID, now: now)
    }

    func eraseAll(operationID: PrivateSystemDiscoveryOperationIDV1, now: Date) async throws {
        try await index.eraseAll(operationID: operationID, now: now)
    }

    func restoreOrReplayCompleted() async throws {
        try await index.dropAndRebuild()
    }

    func reportState() async throws -> PrivateSystemDiscoveryStateMapV1 {
        try await index.state()
    }
}

// MARK: - C17 exterior-lighting day inventory metadata search

extension SearchCoordinatorV1 {
    static func searchC17LightingDayMetadata(
        query: String,
        workspaceID: WorkspaceID,
        records: [C17LightingDaySearchRecordV1],
        maximumResults: Int = 100
    ) throws -> [C17LightingDaySearchRecordV1] {
        guard maximumResults > 0,
              maximumResults <= SearchContractLimitsV1.maximumCanonicalRecords,
              records.count <= SearchContractLimitsV1.maximumProjectionRecords,
              records.allSatisfy({ $0.workspaceID == workspaceID }) else {
            throw SearchContractFailureV1.scopeMismatch
        }
        try records.forEach { try $0.validate() }
        let tokens = normalizedTokens(query)
        guard !tokens.isEmpty else { throw SearchContractFailureV1.invalidQuery }
        let matches = records.filter { record in
            tokens.allSatisfy { queryToken in
                record.normalizedTokens.contains { indexedToken in
                    indexedToken == queryToken || indexedToken.hasPrefix(queryToken)
                }
            }
        }.sorted()
        return Array(matches.prefix(maximumResults))
    }

    static func searchC17LightingDayMetadata(
        query: String,
        workspaceID: WorkspaceID,
        records: [C17LightingDaySearchRecordV1],
        maximumResults: Int = 100,
        accessGate: any AppAccessGatePortV1
    ) async throws -> [C17LightingDaySearchRecordV1] {
        let permit = try await accessGate.requireContentAccess(for: .search)
        guard permit.surface == .search, permit.state.permitsContentAccess else {
            throw AppAccessContentReadFailureV1.denied(surface: .search, state: permit.state)
        }
        return try searchC17LightingDayMetadata(
            query: query, workspaceID: workspaceID,
            records: records, maximumResults: maximumResults
        )
    }
}

enum C17LightingDaySearchCoordinatorBoundaryV1 {
    static let queryReadsDerivedRowsOnly = true
    static let queryTextIsNeverDurable = true
    static let workspaceScopeIsRequired = true
    static let privateSafetyRouteActorNotesAndMediaAreExcluded = true
}

extension SearchCoordinatorV1 {
    static func searchC18LightingNightMetadata(query:String,workspaceID:WorkspaceID,
        records:[C18LightingNightSearchRecordV1],maximumResults:Int=100)throws->[C18LightingNightSearchRecordV1]{
        guard maximumResults>0,maximumResults<=SearchContractLimitsV1.maximumCanonicalRecords,
              records.allSatisfy({$0.workspaceID==workspaceID}) else{throw SearchContractFailureV1.scopeMismatch}
        try records.forEach{$0.validate()};let tokens=normalizedTokens(query)
        guard !tokens.isEmpty else{throw SearchContractFailureV1.invalidQuery}
        return Array(records.filter{r in tokens.allSatisfy{q in r.normalizedTokens.contains{$0==q||$0.hasPrefix(q)}}}.sorted().prefix(maximumResults))
    }
    static func searchC18LightingNightMetadata(query:String,workspaceID:WorkspaceID,
        records:[C18LightingNightSearchRecordV1],maximumResults:Int=100,
        accessGate:any AppAccessGatePortV1)async throws->[C18LightingNightSearchRecordV1]{
        let permit=try await accessGate.requireContentAccess(for:.search)
        guard permit.surface == .search,permit.state.permitsContentAccess else{throw AppAccessContentReadFailureV1.denied(surface:.search,state:permit.state)}
        return try searchC18LightingNightMetadata(query:query,workspaceID:workspaceID,records:records,maximumResults:maximumResults)
    }
}

enum C18LightingNightSearchCoordinatorBoundaryV1{static let currentTipOnly=true;static let queryTextIsNeverDurable=true;static let excludesActorRouteNotesMeterSerialPrivateLocatorsAndMedia=true}

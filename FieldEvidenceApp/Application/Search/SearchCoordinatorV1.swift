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

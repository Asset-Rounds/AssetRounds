import Foundation

enum OperationsMetricsCoordinatorFailureV1: Error, Equatable, Sendable {
    case sourceRevisionMismatch
    case definitionRevisionMismatch
    case corruptDerivedProjection
    case cancelled
}

/// Application façade for C09's derived metrics.  It owns no persistence and
/// has no writer of its own: projection reads canonical C53 event values, and
/// any exposure mutation is delegated unchanged to the C53 coordinator.
@MainActor
final class OperationsMetricsCoordinatorV1 {
    private let reliabilityCoordinator: AssetServiceReliabilityCoordinatorV1
    private let rebuildCoordinator: OperationsMetricsRebuildCoordinatorV1

    init(
        reliabilityCoordinator: AssetServiceReliabilityCoordinatorV1,
        rebuildCoordinator: OperationsMetricsRebuildCoordinatorV1
    ) {
        self.reliabilityCoordinator = reliabilityCoordinator
        self.rebuildCoordinator = rebuildCoordinator
    }

    /// Projects exactly the supplied C53 event revisions.  When a caller has
    /// already observed a source closure, reconciliation fails closed instead
    /// of presenting a newer or partially-derived dashboard as that revision.
    func project(
        source: OperationsMetricsCanonicalSourceV1,
        expectedSourceClosureSHA256: String? = nil
    ) async throws -> OperationsMetricsDerivedProjectionV1 {
        let sourceClosureSHA256 = try source.canonicalSourceClosureSHA256()
        if let expectedSourceClosureSHA256 {
            try ServiceReliabilityLimitsV1.digest(expectedSourceClosureSHA256)
            guard expectedSourceClosureSHA256 == sourceClosureSHA256 else {
                throw OperationsMetricsCoordinatorFailureV1.sourceRevisionMismatch
            }
        }
        do {
            let result = try await rebuildCoordinator.rebuild(sources: [source])
            guard result.continuation == nil, let projection = result.projections.first else {
                throw OperationsMetricsCoordinatorFailureV1.corruptDerivedProjection
            }
            try reconcile(
                projection,
                expectedSourceClosureSHA256: sourceClosureSHA256
            )
            return projection
        } catch is CancellationError {
            throw OperationsMetricsCoordinatorFailureV1.cancelled
        } catch let error as OperationsMetricsRebuildFailureV1 where error == .corruptDerivedProjection {
            throw OperationsMetricsCoordinatorFailureV1.corruptDerivedProjection
        }
    }

    /// Rebuilds bounded batches without retaining a card-local cache.  The
    /// caller may retain the continuation only in its current operation; after
    /// termination it must restart from canonical C53 input, which is safe and
    /// deterministic at 10,000-asset scale.
    func rebuild(
        sources: [OperationsMetricsCanonicalSourceV1],
        continuation: OperationsMetricsRebuildContinuationV1? = nil,
        maximumOutputs: Int? = nil
    ) async throws -> OperationsMetricsRebuildResultV1 {
        do {
            let result = try await rebuildCoordinator.rebuild(
                sources: sources,
                continuation: continuation,
                maximumOutputs: maximumOutputs
            )
            try result.projections.forEach { try reconcile($0, expectedSourceClosureSHA256: nil) }
            return result
        } catch is CancellationError {
            throw OperationsMetricsCoordinatorFailureV1.cancelled
        } catch let error as OperationsMetricsRebuildFailureV1 where error == .corruptDerivedProjection {
            throw OperationsMetricsCoordinatorFailureV1.corruptDerivedProjection
        }
    }

    /// C09 may surface exposure editing, but it never obtains a writer,
    /// receipt, lifecycle adapter, or transaction of its own.  These methods
    /// intentionally forward to the sole C53 canonical owner.
    func previewC53Commit(
        expectedRevision: WorkspaceExpectedRevisionV1,
        mutationID: MutationIDV1,
        payloads: [ServiceReliabilityMutationPayloadV1]
    ) throws -> AssetServiceReliabilityCommitPlanV1 {
        try reliabilityCoordinator.previewCommit(
            expectedRevision: expectedRevision,
            mutationID: mutationID,
            payloads: payloads
        )
    }

    func commitC53(
        _ plan: AssetServiceReliabilityCommitPlanV1
    ) async throws -> ServiceReliabilityMutationReceiptV1 {
        try await reliabilityCoordinator.commit(plan)
    }

    private func reconcile(
        _ projection: OperationsMetricsDerivedProjectionV1,
        expectedSourceClosureSHA256: String?
    ) throws {
        do {
            try projection.validate()
            try OperationsMetricsContractV1.validateRegistry()
            let definitions = try OperationsMetricsContractV1.metricDefinitions()
            guard projection.dashboard.metricProjections.map(\.definition) == definitions else {
                throw OperationsMetricsCoordinatorFailureV1.definitionRevisionMismatch
            }
            for metric in projection.dashboard.metricProjections {
                let registered = try OperationsMetricsContractV1.definition(for: metric.definition.identifier)
                guard metric.definition == registered else {
                    throw OperationsMetricsCoordinatorFailureV1.definitionRevisionMismatch
                }
            }
            guard expectedSourceClosureSHA256 == nil
                    || projection.canonicalSourceClosureSHA256 == expectedSourceClosureSHA256 else {
                throw OperationsMetricsCoordinatorFailureV1.sourceRevisionMismatch
            }
        } catch let error as OperationsMetricsCoordinatorFailureV1 {
            throw error
        } catch {
            throw OperationsMetricsCoordinatorFailureV1.corruptDerivedProjection
        }
    }
}

enum C09OperationsMetricsApplicationBoundaryV1 {
    static let createsSecondWriter = false
    static let createsCanonicalReceipt = false
    static let persistsMetricProjection = false
    static let ownsMigration = false
    static let ownsBackupRestore = false
    static let ownsDeleteOrErase = false
    static let exposureEditsDelegateToC53 = true
    static let reportAndOpenJSONUseDerivedHandoffs = true
}

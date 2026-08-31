import Foundation

/// Derived lifecycle bridge for the canonical round-session coordinator. This
/// adapter owns no session rows, writers, renderer, or search store: it proves
/// the live canonical frontier before producing metadata-only derivatives.
@MainActor
final class RoundSessionLifecycleAdapterV1 {
    private let roundCoordinator: RoundSessionCoordinatorV1

    init(roundCoordinator: RoundSessionCoordinatorV1) {
        self.roundCoordinator = roundCoordinator
    }

    func progress(
        at frontier: RoundSessionReferenceV1
    ) throws -> C05RoundSessionProgressReportProjectionV1 {
        let current = try roundCoordinator.validateCurrentFrontier(frontier)
        return try ReportProjectionRegistryV1.roundSessionProgress(session: current)
    }

    func closeout(
        at frontier: RoundSessionReferenceV1
    ) throws -> C05RoundSessionCloseoutReportProjectionV1 {
        let current = try roundCoordinator.validateCurrentFrontier(frontier)
        return try ReportProjectionRegistryV1.roundSessionCloseout(session: current)
    }

    func searchProjection(
        at frontier: RoundSessionReferenceV1
    ) throws -> C05RoundSessionSearchProjectionV1 {
        let current = try roundCoordinator.validateCurrentFrontier(frontier)
        let progress = try ReportProjectionRegistryV1.roundSessionProgress(session: current)
        let closeout = current.state == .completed
            ? try ReportProjectionRegistryV1.roundSessionCloseout(session: current)
            : nil
        return try C05RoundSessionSearchProjectionBoundaryV1.projection(
            progress: progress,
            closeout: closeout
        )
    }

    func recoverProgress(
        _ projection: C05RoundSessionProgressReportProjectionV1
    ) throws -> C05RoundSessionProgressReportProjectionV1 {
        let current = try roundCoordinator.validateCurrentFrontier(projection.session)
        return try ReportRecoveryService.recoverRoundSessionProgress(
            projection,
            source: current
        )
    }

    func recoverCloseout(
        _ projection: C05RoundSessionCloseoutReportProjectionV1
    ) throws -> C05RoundSessionCloseoutReportProjectionV1 {
        let current = try roundCoordinator.validateCurrentFrontier(projection.progress.session)
        return try ReportRecoveryService.recoverRoundSessionCloseout(
            projection,
            source: current
        )
    }

    /// Index invalidation occurs strictly after the incumbent coordinator has
    /// accepted the canonical mutation and after the caller supplies its new
    /// workspace-wide source revision. The index remains disposable truth.
    func save(
        _ mutation: RoundSessionMutationV1,
        postCommitSearchSource: SearchSourceRevisionV1,
        searchLifecycle: any SearchIndexLifecyclePortV1
    ) async throws -> RoundSessionMutationReceiptV1 {
        try mutation.validate()
        guard postCommitSearchSource.workspaceID == mutation.workspaceID.rawValue else {
            throw RoundSessionFailureV1.authorityMismatch
        }
        let receipt = try roundCoordinator.save(mutation)
        try receipt.validate()
        guard receipt.sessionFrontier == (try mutation.session.reference) else {
            throw RoundSessionFailureV1.authorityMismatch
        }
        try await searchLifecycle.invalidateAfterCanonicalCommit(
            source: postCommitSearchSource
        )
        return receipt
    }

    func rebuildSearch(
        using rebuildCoordinator: SearchIndexRebuildCoordinatorV1
    ) async throws -> SearchIndexRebuildResultV1 {
        try await rebuildCoordinator.rebuildIfNeeded()
    }
}

enum C05RoundSessionLifecycleBoundaryV1 {
    static let canonicalWriterIsRoundSessionCoordinatorOnly = true
    static let derivedReportRequiresCurrentFrontierValidation = true
    static let closeoutRequiresCompletedFullyDispositionedSession = true
    static let searchInvalidationOccursAfterCanonicalCommitOnly = true
    static let adapterCreatesNoRendererStoreOrRoute = true
    static let qrRecurrenceDueReminderNetworkAndTeamDispatchAreAbsent = true
}

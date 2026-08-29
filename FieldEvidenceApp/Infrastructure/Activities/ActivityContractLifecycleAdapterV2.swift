import Foundation

@MainActor
final class ActivityContractBundledReleaseProviderV2: ActivityContractBundledReleaseSelectingV2 {
    private let packageLifecycle: PackageEvolutionLifecycleAdapterV1
    private let registry: InspectionPackageRegistryV2

    init(packageLifecycle: PackageEvolutionLifecycleAdapterV1,
         registry: InspectionPackageRegistryV2) {
        self.packageLifecycle = packageLifecycle
        self.registry = registry
    }

    func bundledRelease(kind: ActivityKindV2,
                        use: ActivityWorkflowReleaseUseV2,
                        workspaceID: WorkspaceID) throws -> BundledActivityWorkflowReleaseV2 {
        switch try packageLifecycle.activityWorkflowRelease(
            kind: kind, use: use, registry: registry, workspaceID: workspaceID
        ) {
        case let .installation(release): return .installation(release)
        case let .punch(release): return .punch(release)
        }
    }
}

enum ActivityContractLifecycleEventV2: String, Codable, CaseIterable, Hashable, Sendable {
    case accepted = "ACCEPTED"
    case backup = "BACKUP"
    case restore = "RESTORE"
    case delete = "DELETE"
    case erase = "ERASE"
    case search = "SEARCH"
    case replay = "REPLAY"
}

struct ActivityContractProjectionScopeV2: Equatable, Sendable {
    let workspaceID: WorkspaceID
    let activityID: UUID?
    let axes: Set<ActivityContractInvalidationAxisV1>
    let event: ActivityContractLifecycleEventV2
}

@MainActor
protocol ActivityContractDerivedProjectionMaintainingV2: AnyObject {
    func invalidateActivityContractProjections(_ scope: ActivityContractProjectionScopeV2) async throws
    func rebuildActivityContractSearch(_ scope: ActivityContractProjectionScopeV2) async throws
    func rebuildActivityContractReports(_ scope: ActivityContractProjectionScopeV2) async throws
    func purgeActivityContractProjections(_ scope: ActivityContractProjectionScopeV2) async throws
}

extension ActivityContractDerivedProjectionMaintainingV2 {
    func purgeActivityContractProjections(_ scope: ActivityContractProjectionScopeV2) async throws {
        try await invalidateActivityContractProjections(scope)
    }
}

/// C47 uses the already-installed disposable search store and its canonical
/// rebuild coordinator. Report projections have no independent cache: their
/// sole registry and recovery paths receive resolved canonical projections at
/// render/reopen time.
@MainActor
final class ActivityContractDerivedProjectionBridgeV2:
    ActivityContractDerivedProjectionMaintainingV2 {
    private let searchStore: LocalSearchIndexStoreV1
    private let searchRebuildCoordinator: SearchIndexRebuildCoordinatorV1

    init(searchStore: LocalSearchIndexStoreV1,
         searchRebuildCoordinator: SearchIndexRebuildCoordinatorV1) {
        self.searchStore = searchStore
        self.searchRebuildCoordinator = searchRebuildCoordinator
    }

    func invalidateActivityContractProjections(_ scope: ActivityContractProjectionScopeV2) async throws {
        // C47 mutations normally reach this bridge through the sole workspace
        // writer, while ordinary deletion reaches it after its direct
        // canonical transaction commits. In both cases the only safe derived
        // operation is to discard the existing workspace projection before a
        // rebuild; this bridge never writes a parallel index or report cache.
        guard scope.event != .erase else { return }
        try await searchStore.dropProjection(workspaceID: scope.workspaceID.rawValue)
    }

    func rebuildActivityContractSearch(_ scope: ActivityContractProjectionScopeV2) async throws {
        guard scope.event != .erase else { return }
        _ = try await searchRebuildCoordinator.rebuildIfNeeded()
    }

    func rebuildActivityContractReports(_ scope: ActivityContractProjectionScopeV2) async throws {
        // ReportProjectionRegistryV1 and ReportRecoveryService rebuild from a
        // resolved canonical projection on demand; there is no C47 report
        // store to invalidate or rebuild here.
        guard scope.event != .erase else { return }
    }

    func purgeActivityContractProjections(_ scope: ActivityContractProjectionScopeV2) async throws {
        try await searchStore.purgeWorkspace(scope.workspaceID.rawValue)
    }
}

@MainActor
final class ActivityContractLifecycleAdapterV2 {
    private let coordinator: ActivityContractCoordinatorV2
    private let projections: any ActivityContractDerivedProjectionMaintainingV2
    private let releaseSelector: (any ActivityContractBundledReleaseSelectingV2)?

    init(coordinator: ActivityContractCoordinatorV2,
         projections: any ActivityContractDerivedProjectionMaintainingV2) {
        self.coordinator = coordinator
        self.projections = projections
        releaseSelector = nil
    }

    init(coordinator: ActivityContractCoordinatorV2,
         searchStore: LocalSearchIndexStoreV1,
         searchRebuildCoordinator: SearchIndexRebuildCoordinatorV1) {
        self.coordinator = coordinator
        projections = ActivityContractDerivedProjectionBridgeV2(
            searchStore: searchStore,
            searchRebuildCoordinator: searchRebuildCoordinator
        )
        releaseSelector = nil
    }

    init(coordinator: ActivityContractCoordinatorV2,
         projections: any ActivityContractDerivedProjectionMaintainingV2,
         releaseSelector: any ActivityContractBundledReleaseSelectingV2) {
        self.coordinator = coordinator
        self.projections = projections
        self.releaseSelector = releaseSelector
    }

    /// Selects and publishes exactly one bundled family through the existing
    /// package lifecycle authority. Callers choose the operation, never a
    /// lifecycle disposition or package release.
    func bundledRelease(kind: ActivityKindV2,
                        use: ActivityWorkflowReleaseUseV2,
                        workspaceID: WorkspaceID) throws -> BundledActivityWorkflowReleaseV2 {
        guard let releaseSelector else {
            throw InspectionPackageFailureV2.incompatiblePackage
        }
        return try releaseSelector.bundledRelease(
            kind: kind, use: use, workspaceID: workspaceID
        )
    }

    func accept(_ request: ActivityContractAcceptanceRequestV2) async throws
        -> ActivityContractAcceptanceResultV2 {
        let result = try await coordinator.accept(request)
        let scope = ActivityContractProjectionScopeV2(
            workspaceID: result.workspaceID,
            activityID: result.activityID,
            axes: invalidatedAxes(for: request.family),
            event: .accepted
        )
        try await projections.invalidateActivityContractProjections(scope)
        try await projections.rebuildActivityContractSearch(scope)
        try await projections.rebuildActivityContractReports(scope)
        return result
    }

    /// Backup includes the six canonical durable families. The three C47
    /// conformance receipts and NoPlanFallback remain nonpersistent.
    func prepareForBackup(workspaceID: WorkspaceID) async throws {
        // Derived search/report state is excluded by the existing backup
        // registry; preparing a backup must not discard the live projection.
        _ = workspaceID
    }

    func restore(workspaceID: WorkspaceID) async throws {
        try await replay(workspaceID: workspaceID, event: .restore)
    }

    func delete(workspaceID: WorkspaceID, activityID: UUID) async throws {
        let scope = ActivityContractProjectionScopeV2(
            workspaceID: workspaceID, activityID: activityID,
            axes: [.shared, .installation, .punch], event: .delete
        )
        try await projections.invalidateActivityContractProjections(scope)
        try await projections.rebuildActivityContractSearch(scope)
        try await projections.rebuildActivityContractReports(scope)
    }

    /// Erase removes derived search/report state after canonical persistence
    /// has erased the workspace. It never records an ephemeral receipt.
    func Erase(workspaceID: WorkspaceID) async throws {
        try await projections.purgeActivityContractProjections(.init(
            workspaceID: workspaceID, activityID: nil,
            axes: [.shared, .installation, .punch], event: .erase
        ))
    }

    func rebuildSearch(workspaceID: WorkspaceID) async throws {
        let scope = ActivityContractProjectionScopeV2(
            workspaceID: workspaceID, activityID: nil,
            axes: [.shared, .installation, .punch], event: .search
        )
        try await projections.rebuildActivityContractSearch(scope)
    }

    func replay(workspaceID: WorkspaceID) async throws {
        try await replay(workspaceID: workspaceID, event: .replay)
    }

    private func replay(workspaceID: WorkspaceID,
                        event: ActivityContractLifecycleEventV2) async throws {
        let scope = ActivityContractProjectionScopeV2(
            workspaceID: workspaceID, activityID: nil,
            axes: [.shared, .installation, .punch], event: event
        )
        try await projections.invalidateActivityContractProjections(scope)
        try await projections.rebuildActivityContractSearch(scope)
        try await projections.rebuildActivityContractReports(scope)
    }

    private func invalidatedAxes(for family: ActivityContractAcceptanceFamilyV2)
        -> Set<ActivityContractInvalidationAxisV1> {
        switch family {
        case .shared: return [.shared, .installation, .punch]
        case .installation: return [.installation]
        case .punch: return [.punch]
        }
    }
}

enum C47ActivityContractLifecycleBoundaryV2 {
    static let backupRestoreDeleteEraseUseExistingLifecycle = true
    static let searchAndReportAreDerivedAndReplayable = true
    static let sharedInvalidationAffectsBothFamilies = true
    static let installationAndPunchInvalidationRemainIsolated = true
    static let conformanceReceiptsAreNeverBackedUp = true
    static let backupPreparationLeavesLiveDerivedStateIntact = true
    static let erasePurgesDerivedStateWithoutRebuild = true
    static let bundledFamiliesAreSelectedAndPublishedIndependently = true
    static let standalonePunchLoadsInstallationReleaseCount = 0
    static let callerSuppliedPackageLifecycleIsForbidden = true
}

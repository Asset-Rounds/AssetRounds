import Combine
import Foundation

/// Device-local presentation over the original publication's scene port.
/// Canonical reads and availability remain with StartupRouter and its store.
@MainActor
final class AppShellSceneStateV1: ObservableObject {
    @Published private(set) var snapshot: SceneNavigationSnapshotV1?
    @Published private(set) var lastRestoration: SceneNavigationRestorationResultV1?

    private let workspaceID: WorkspaceID
    private let access: AppAccessPresentationV1.SceneNavigationAccess
    private let routes: RouteCoordinatorV1

    init(workspaceID: WorkspaceID,
         access: AppAccessPresentationV1.SceneNavigationAccess,
         registry: RouteRegistryV1) {
        self.workspaceID = workspaceID
        self.access = access
        routes = RouteCoordinatorV1(registry: registry)
    }

    func restore() throws {
        try update {
            try access.restore(loaded: access.load(), using: routes, evidenceKind: .recovery)
        }
    }

    func select(_ root: AppRootV1) throws {
        try update {
            let current = try currentSnapshot()
            let candidate = try SceneNavigationSnapshotV1(workspaceID: workspaceID,
                selectedRoot: root, paths: current.paths, snapshotID: UUID())
            return try access.restore(loaded: .restored(candidate), using: routes,
                evidenceKind: .alternate)
        }
    }

    func setPath(_ targets: [NavigationTargetV1], for root: AppRootV1) throws {
        try update {
            let current = try currentSnapshot()
            let paths = current.paths.map {
                $0.root == root ? SceneRootPathV1(root: root, targets: targets) : $0
            }
            let candidate = try SceneNavigationSnapshotV1(workspaceID: workspaceID,
                selectedRoot: root, paths: paths, snapshotID: UUID())
            return try access.restore(loaded: .restored(candidate), using: routes,
                evidenceKind: .alternate)
        }
    }

    func open(_ target: NavigationTargetV1) throws {
        try update {
            let current = try currentSnapshot()
            return try access.restore(loaded: .restored(current), explicitIngressTarget: target,
                using: routes, evidenceKind: .alternate)
        }
    }

    func discardPresentation() {
        snapshot = nil
        lastRestoration = nil
    }

    private func currentSnapshot() throws -> SceneNavigationSnapshotV1 {
        guard let snapshot else { throw SceneNavigationFailureV1.invalidSnapshot }
        return snapshot
    }

    private func update(_ resolve: () throws -> SceneNavigationRestorationResultV1) throws {
        do {
            let result = try resolve()
            let reconciled = try SceneNavigationSnapshotV1(workspaceID: workspaceID,
                selectedRoot: result.selectedRoot, paths: result.paths, snapshotID: UUID())
            // Each entry owns its own synchronous token hold. Do not wrap one
            // scene operation inside another surface's nonrecursive hold.
            try access.save(reconciled)
            lastRestoration = result
            snapshot = reconciled
        } catch {
            discardPresentation()
            throw error
        }
    }
}

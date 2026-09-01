import Foundation

struct RouteRestorationRequestV1: Sendable {
    let context: RouteResolutionContextV1
    let startupMaintenanceTarget: NavigationTargetV1?
    let incompleteMutationRecoveryTarget: NavigationTargetV1?
    let explicitIngressTarget: NavigationTargetV1?
    let sceneSnapshot: SceneNavigationSnapshotV1?
    let discardedSnapshotReason: RouteFallbackReasonV1?
    let evidenceKind: RouteEvidenceKindV1
    let receiptID: UUID
}

struct RouteCoordinatorV1: Sendable {
    let registry: RouteRegistryV1

    init(registry: RouteRegistryV1) { self.registry = registry }

    func restore(_ request: RouteRestorationRequestV1) throws -> RouteRestorationReceiptV1 {
        let selected: (RouteRestorationSourceV1, NavigationTargetV1, UUID?)
        if let target = request.startupMaintenanceTarget {
            guard target.destination == .startupMaintenance else { throw RouteCoordinatorFailureV1.invalidPriorityTarget }
            selected = (.startupMaintenance, target, nil)
        } else if let target = request.incompleteMutationRecoveryTarget {
            guard target.destination == .mutationRecovery else { throw RouteCoordinatorFailureV1.invalidPriorityTarget }
            selected = (.incompleteMutationRecovery, target, nil)
        } else if let target = request.explicitIngressTarget {
            selected = (.explicitIngress, target, nil)
        } else if let snapshot = request.sceneSnapshot,
                  snapshot.workspaceID == request.context.currentWorkspaceID,
                  (try? snapshot.validate()) != nil {
            let target: NavigationTargetV1
            if let selectedTarget = snapshot.selectedTarget {
                target = selectedTarget
            } else {
                target = try NavigationTargetV1(workspaceID: snapshot.workspaceID, destination: RouteRegistryV1.rootDestination(for: snapshot.selectedRoot))
            }
            selected = (.sceneSnapshot, target, snapshot.snapshotID)
        } else {
            let target = try NavigationTargetV1(workspaceID: request.context.currentWorkspaceID, destination: .today)
            selected = (.todayFallback, target, nil)
        }

        var result = try registry.resolve(selected.1, context: request.context)
        let derivedDiscardReason: RouteFallbackReasonV1? = request.discardedSnapshotReason ?? request.sceneSnapshot.map {
            $0.workspaceID == request.context.currentWorkspaceID ? .corruptSnapshot : .wrongWorkspace
        }
        if selected.0 == .todayFallback, let reason = derivedDiscardReason {
            result = RouteResolutionResultV1(disposition: .safeFallback, target: result.target, reason: reason, canonicalMutationCount: 0, startsAutomaticWork: false)
        }
        return try RouteRestorationReceiptV1(receiptID: request.receiptID, evidenceKind: request.evidenceKind, source: selected.0, result: result, snapshotID: selected.2)
    }

    func restore(
        _ request: RouteRestorationRequestV1,
        accessGate: any AppAccessGatePortV1
    ) async throws -> RouteRestorationReceiptV1 {
        _ = try await accessGate.requireContentAccess(for: .sceneRestoration)
        return try restore(request)
    }

    func resolve(
        _ target: NavigationTargetV1,
        context: RouteResolutionContextV1,
        accessGate: any AppAccessGatePortV1
    ) async throws -> RouteResolutionResultV1 {
        _ = try await accessGate.requireContentAccess(for: .routeResolution)
        return try registry.resolve(target, context: context)
    }
}

extension RouteCoordinatorV1 {
    func resolvePrivateSystemDiscovery(_ target: NavigationTargetV1,
                                       context: RouteResolutionContextV1) throws -> RouteResolutionResultV1 {
        try PrivateSystemDiscoveryRouteBoundaryV1.validate(target)
        let result = try registry.resolve(target, context: context)
        guard result.canonicalMutationCount == 0, !result.startsAutomaticWork else {
            throw RouteCoordinatorFailureV1.invalidPriorityTarget
        }
        return result
    }

    func resolvePrivateSystemDiscovery(
        _ target: NavigationTargetV1,
        context: RouteResolutionContextV1,
        accessGate: any AppAccessGatePortV1
    ) async throws -> RouteResolutionResultV1 {
        _ = try await accessGate.requireContentAccess(for: .privateSystemDiscovery)
        return try resolvePrivateSystemDiscovery(target, context: context)
    }
}

enum RouteCoordinatorFailureV1: Error, Equatable {
    case invalidPriorityTarget
}

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
        try restoreScene(request).receipt
    }

    func restoreScene(
        _ request: RouteRestorationRequestV1
    ) throws -> SceneNavigationRestorationResultV1 {
        let reconciliation = try reconciledSnapshot(
            request.sceneSnapshot,
            context: request.context
        )
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
                  let reconciliation {
            let target = try selectedTarget(
                root: snapshot.selectedRoot,
                paths: reconciliation.paths,
                workspaceID: snapshot.workspaceID
            )
            selected = (.sceneSnapshot, target, snapshot.snapshotID)
        } else {
            let target = try NavigationTargetV1(workspaceID: request.context.currentWorkspaceID, destination: .today)
            selected = (.todayFallback, target, nil)
        }

        var result: RouteResolutionResultV1
        if selected.0 == .sceneSnapshot,
           let failedResolution = reconciliation?.selectedPathFailure {
            result = failedResolution
        } else {
            result = try registry.resolve(selected.1, context: request.context)
        }
        let derivedDiscardReason: RouteFallbackReasonV1? = request.discardedSnapshotReason ?? request.sceneSnapshot.map {
            $0.workspaceID == request.context.currentWorkspaceID ? .corruptSnapshot : .wrongWorkspace
        }
        if selected.0 == .todayFallback, let reason = derivedDiscardReason {
            result = RouteResolutionResultV1(disposition: .safeFallback, target: result.target, reason: reason, canonicalMutationCount: 0, startsAutomaticWork: false)
        }
        let receipt = try RouteRestorationReceiptV1(
            receiptID: request.receiptID,
            evidenceKind: request.evidenceKind,
            source: selected.0,
            result: result,
            snapshotID: selected.2
        )
        var paths = reconciliation?.paths ?? emptyPaths()
        if selected.0 != .sceneSnapshot {
            paths = installing(result.target, in: paths)
        }
        return try SceneNavigationRestorationResultV1(
            receipt: receipt,
            selectedRoot: result.target.root,
            paths: paths
        )
    }

    func restoreScene(
        _ request: RouteRestorationRequestV1,
        using token: AppAccessGateV1.ContentReadToken
    ) throws -> SceneNavigationRestorationResultV1 {
        try token.withContentRead(for: .sceneRestoration) {
            try restoreScene(request)
        }
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

    private func reconciledSnapshot(
        _ snapshot: SceneNavigationSnapshotV1?,
        context: RouteResolutionContextV1
    ) throws -> ReconciledSceneSnapshotV1? {
        guard let snapshot,
              snapshot.workspaceID == context.currentWorkspaceID,
              (try? snapshot.validate()) != nil else { return nil }
        var selectedPathFailure: RouteResolutionResultV1?
        let paths = try snapshot.paths.map { path in
            var targets: [NavigationTargetV1] = []
            var candidates = Array(path.targets[...])
            if candidates.first?.isIdentitylessSceneRootMarker == true {
                candidates.removeFirst()
            }
            for target in candidates {
                guard !target.isIdentitylessSceneRootMarker else {
                    break
                }
                let resolution = try registry.resolve(target, context: context)
                guard resolution.disposition == .resolved,
                      resolution.target == target else {
                    if path.root == snapshot.selectedRoot,
                       selectedPathFailure == nil,
                       resolution.disposition == .safeFallback {
                        let safeParent: NavigationTargetV1
                        if let retained = targets.last {
                            safeParent = retained
                        } else {
                            safeParent = try NavigationTargetV1(
                                workspaceID: snapshot.workspaceID,
                                destination: RouteRegistryV1.rootDestination(for: path.root)
                            )
                        }
                        selectedPathFailure = RouteResolutionResultV1(
                            disposition: .safeFallback,
                            target: safeParent,
                            reason: resolution.reason,
                            canonicalMutationCount: 0,
                            startsAutomaticWork: false
                        )
                    }
                    break
                }
                targets.append(target)
            }
            return SceneRootPathV1(root: path.root, targets: targets)
        }
        return ReconciledSceneSnapshotV1(
            paths: paths,
            selectedPathFailure: selectedPathFailure
        )
    }

    private func selectedTarget(
        root: AppRootV1,
        paths: [SceneRootPathV1],
        workspaceID: WorkspaceID
    ) throws -> NavigationTargetV1 {
        if let target = paths.first(where: { $0.root == root })?.targets.last {
            return target
        }
        return try NavigationTargetV1(
            workspaceID: workspaceID,
            destination: RouteRegistryV1.rootDestination(for: root)
        )
    }

    private func emptyPaths() -> [SceneRootPathV1] {
        AppRootV1.frozenOrder.map { SceneRootPathV1(root: $0, targets: []) }
    }

    private func installing(
        _ target: NavigationTargetV1,
        in paths: [SceneRootPathV1]
    ) -> [SceneRootPathV1] {
        paths.map { path in
            guard path.root == target.root else { return path }
            let targets = target.isIdentitylessSceneRootMarker
                ? [] : [target]
            return SceneRootPathV1(root: path.root, targets: targets)
        }
    }

    private struct ReconciledSceneSnapshotV1 {
        let paths: [SceneRootPathV1]
        let selectedPathFailure: RouteResolutionResultV1?
    }
}

extension RouteCoordinatorV1 {
    func resolveScanToWork(
        _ flow: ScanToWorkFlowV1,
        currentSession: RoundSessionReferenceV1,
        requestedMode: NavigationRequestedModeV1 = .read,
        context: RouteResolutionContextV1
    ) throws -> ScanToWorkNavigationProjectionV1 {
        try flow.validateIntrinsic(); try currentSession.validate()
        guard flow.preview.workspaceID == context.currentWorkspaceID,
              currentSession.workspaceID == context.currentWorkspaceID else {
            throw ScanToWorkFailureV1.authorityMismatch
        }
        guard flow.preview.outcome == .ready else {
            return try ScanToWorkNavigationProjectionV1(flow: flow, route: nil, resolution: nil)
        }
        let route = try ScanToWorkRouteV1(flow: flow, requestedMode: requestedMode)
        guard route.identity.session == currentSession else {
            throw ScanToWorkFailureV1.stale
        }
        let resolution = try registry.resolve(route.target, context: context)
        guard resolution.disposition == .resolved,
              resolution.canonicalMutationCount == 0,
              !resolution.startsAutomaticWork else {
            throw ScanToWorkFailureV1.stale
        }
        return try ScanToWorkNavigationProjectionV1(
            flow: flow, route: route, resolution: resolution
        )
    }

    func resolveScanToWork(
        _ flow: ScanToWorkFlowV1,
        currentSession: RoundSessionReferenceV1,
        requestedMode: NavigationRequestedModeV1 = .read,
        context: RouteResolutionContextV1,
        accessGate: any AppAccessGatePortV1
    ) async throws -> ScanToWorkNavigationProjectionV1 {
        _ = try await accessGate.requireContentAccess(for: .routeResolution)
        return try resolveScanToWork(
            flow, currentSession: currentSession,
            requestedMode: requestedMode, context: context
        )
    }

    /// Scan, manual-code, and search entry must converge on the same exact
    /// asset/session/pose authority. Source-specific input digests may differ;
    /// their canonical resolution and route identities may not.
    func resolveEquivalentScanToWorkEntrances(
        scan: ScanToWorkFlowV1,
        manual: ScanToWorkFlowV1,
        search: ScanToWorkFlowV1,
        currentSession: RoundSessionReferenceV1,
        requestedMode: NavigationRequestedModeV1 = .read,
        context: RouteResolutionContextV1
    ) throws -> [ScanToWorkNavigationProjectionV1] {
        let flows = [scan, manual, search]
        try flows.forEach { try $0.validateIntrinsic() }
        guard Set(flows.map { $0.preview.source }) == Set(ScanToWorkEntrySourceV1.allCases),
              Set(flows.map { $0.preview.outcome }).count == 1,
              Set(flows.map { $0.preview.primaryAction }).count == 1,
              flows.allSatisfy({ $0.preview.asset == scan.preview.asset }),
              flows.allSatisfy({ $0.preview.candidateLocators == scan.preview.candidateLocators }) else {
            throw ScanToWorkFailureV1.authorityMismatch
        }
        let projections = try flows.map {
            try resolveScanToWork(
                $0, currentSession: currentSession,
                requestedMode: requestedMode, context: context
            )
        }
        if let identity = projections.first?.route?.identity {
            guard projections.allSatisfy({ $0.route?.identity == identity }) else {
                throw ScanToWorkFailureV1.authorityMismatch
            }
        }
        return projections
    }

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

import XCTest
@testable import FieldEvidenceApp

final class V9_59RouteRegistryRestorationTests: XCTestCase {
    private let workspace = WorkspaceID(rawValue: UUID(uuid: (0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x41, 0x11, 0x81, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11)))

    func testExactlyFourFrozenRootsAndNoAutomaticWork() throws {
        XCTAssertEqual(AppRootV1.frozenOrder.map(\.rawValue), ["TODAY", "WORK", "ASSETS", "REPORTS"])
        XCTAssertEqual(AppRootV1.allCases.count, 4)
        let registry = try RouteRegistryV1()
        let target = try NavigationTargetV1(workspaceID: workspace, destination: .today)
        let result = try registry.resolve(target, context: .init(currentWorkspaceID: workspace, currentRevision: 0))
        XCTAssertEqual(result.canonicalMutationCount, 0)
        XCTAssertFalse(result.startsAutomaticWork)
        let conformance = RouteConformanceReceiptV1(registry: registry, evidenceKind: .golden, observedShellCount: 1, observedParserCount: 1, observedMutationAuthorityCount: 0)
        XCTAssertNoThrow(try conformance.validate())
        let fabricatedSecondParser = RouteConformanceReceiptV1(registry: registry, evidenceKind: .hostile, observedShellCount: 1, observedParserCount: 2, observedMutationAuthorityCount: 0)
        XCTAssertThrowsError(try fabricatedSecondParser.validate())
    }

    func testPackageRejectsAuthorityEscalationAndDuplicateRoute() throws {
        let route = PackageSurfaceRouteV1(routeID: "package.route", root: .assets, destination: .packageSurface, kind: .destination, startsAutomaticWork: false)
        XCTAssertThrowsError(try PackageSurfaceManifestV1(packageID: "package", routes: [route], addsMutationAuthority: true))
        let one = try PackageSurfaceManifestV1(packageID: "one", routes: [route])
        let two = try PackageSurfaceManifestV1(packageID: "two", routes: [route])
        XCTAssertThrowsError(try RouteRegistryV1(manifests: [one, two]))
    }

    func testStartupPrecedenceIsExact() throws {
        let registry = try RouteRegistryV1()
        let coordinator = RouteCoordinatorV1(registry: registry)
        let maintenance = try NavigationTargetV1(workspaceID: workspace, destination: .startupMaintenance)
        let mutation = try NavigationTargetV1(workspaceID: workspace, destination: .mutationRecovery)
        let ingress = try NavigationTargetV1(workspaceID: workspace, destination: .reports)
        let snapshotTarget = try NavigationTargetV1(workspaceID: workspace, destination: .assets)
        let snapshot = try SceneNavigationSnapshotV1(workspaceID: workspace, selectedRoot: .assets, paths: completePaths(root: .assets, target: snapshotTarget), snapshotID: UUID())
        let receipt = try coordinator.restore(.init(context: .init(currentWorkspaceID: workspace, currentRevision: 0), startupMaintenanceTarget: maintenance, incompleteMutationRecoveryTarget: mutation, explicitIngressTarget: ingress, sceneSnapshot: snapshot, discardedSnapshotReason: nil, evidenceKind: .golden, receiptID: UUID()))
        XCTAssertEqual(receipt.source, .startupMaintenance)
        XCTAssertEqual(receipt.result.target.destination, .startupMaintenance)
        XCTAssertEqual(receipt.canonicalMutationCount, 0)
    }

    func testRemainingPrecedenceFallsThroughInFrozenOrder() throws {
        let coordinator = RouteCoordinatorV1(registry: try RouteRegistryV1())
        let context = RouteResolutionContextV1(currentWorkspaceID: workspace, currentRevision: 0)
        let mutation = try NavigationTargetV1(workspaceID: workspace, destination: .mutationRecovery)
        let ingress = try NavigationTargetV1(workspaceID: workspace, destination: .reports)
        let snapshotTarget = try NavigationTargetV1(workspaceID: workspace, destination: .assets)
        let snapshot = try SceneNavigationSnapshotV1(workspaceID: workspace, selectedRoot: .assets, paths: completePaths(root: .assets, target: snapshotTarget), snapshotID: UUID())
        let mutationReceipt = try coordinator.restore(.init(context: context, startupMaintenanceTarget: nil, incompleteMutationRecoveryTarget: mutation, explicitIngressTarget: ingress, sceneSnapshot: snapshot, discardedSnapshotReason: nil, evidenceKind: .alternate, receiptID: UUID()))
        XCTAssertEqual(mutationReceipt.source, .incompleteMutationRecovery)
        let ingressReceipt = try coordinator.restore(.init(context: context, startupMaintenanceTarget: nil, incompleteMutationRecoveryTarget: nil, explicitIngressTarget: ingress, sceneSnapshot: snapshot, discardedSnapshotReason: nil, evidenceKind: .alternate, receiptID: UUID()))
        XCTAssertEqual(ingressReceipt.source, .explicitIngress)
        let snapshotReceipt = try coordinator.restore(.init(context: context, startupMaintenanceTarget: nil, incompleteMutationRecoveryTarget: nil, explicitIngressTarget: nil, sceneSnapshot: snapshot, discardedSnapshotReason: nil, evidenceKind: .alternate, receiptID: UUID()))
        XCTAssertEqual(snapshotReceipt.source, .sceneSnapshot)
        let todayReceipt = try coordinator.restore(.init(context: context, startupMaintenanceTarget: nil, incompleteMutationRecoveryTarget: nil, explicitIngressTarget: nil, sceneSnapshot: nil, discardedSnapshotReason: nil, evidenceKind: .alternate, receiptID: UUID()))
        XCTAssertEqual(todayReceipt.source, .todayFallback)
        XCTAssertEqual(todayReceipt.result.target.destination, .today)
    }

    func testCrossWorkspaceAndStaleTargetFallBack() throws {
        let foreign = WorkspaceID(rawValue: UUID())
        let target = try NavigationTargetV1(workspaceID: foreign, destination: .work, expectedRevision: 2)
        let result = try RouteRegistryV1().resolve(target, context: .init(currentWorkspaceID: workspace, currentRevision: 1))
        XCTAssertEqual(result.disposition, .safeFallback)
        XCTAssertEqual(result.reason, .wrongWorkspace)
        XCTAssertEqual(result.target.workspaceID, workspace)
        XCTAssertEqual(result.target.destination, .today)
    }

    func testScheduleAndOccurrenceAnchorsRequireExactCurrentRevisions() throws {
        let scheduleID = UUID()
        let releaseID = UUID()
        let occurrenceID = OccurrenceIDV1(rawValue: String(repeating: "a", count: 64))
        let target = try NavigationTargetV1(workspaceID: workspace, destination: .scheduleOccurrence, stableScheduleDefinitionID: scheduleID, stableScheduleReleaseID: releaseID, stableOccurrenceID: occurrenceID, expectedScheduleRevision: 3, expectedOccurrenceRevision: 7)
        let registry = try RouteRegistryV1()
        let current = RouteResolutionContextV1(currentWorkspaceID: workspace, currentRevision: 0, currentScheduleRevisions: [scheduleID: 3], currentScheduleReleaseIDs: [scheduleID: releaseID], currentOccurrenceRevisions: [occurrenceID: 7])
        XCTAssertEqual(try registry.resolve(target, context: current).disposition, .resolved)
        let stale = RouteResolutionContextV1(currentWorkspaceID: workspace, currentRevision: 0, currentScheduleRevisions: [scheduleID: 4], currentScheduleReleaseIDs: [scheduleID: releaseID], currentOccurrenceRevisions: [occurrenceID: 7])
        XCTAssertEqual(try registry.resolve(target, context: stale).reason, .staleRevision)
        let unavailable = RouteResolutionContextV1(currentWorkspaceID: workspace, currentRevision: 0)
        XCTAssertEqual(try registry.resolve(target, context: unavailable).reason, .deletedOrTombstoned)
    }

    func testTolerantStateDecodeDiscardsFutureAndCorruptBytesAndEraseClears() throws {
        let port = InMemorySceneNavigationDeviceStatePortV1()
        let adapter = SceneNavigationStateAdapterV1(port: port)
        try port.saveSceneNavigationData(Data(#"{"schemaVersion":99}"#.utf8))
        XCTAssertEqual(try adapter.loadAndReconcile(), .discarded(.unsupportedSnapshotVersion))
        XCTAssertNil(port.data)
        try port.saveSceneNavigationData(Data("not-json".utf8))
        XCTAssertEqual(try adapter.loadAndReconcile(), .discarded(.corruptSnapshot))
        XCTAssertNil(port.data)
        try port.saveSceneNavigationData(
            Data(repeating: 0x7b, count: SceneNavigationSnapshotV1.maximumEncodedByteCount + 1)
        )
        XCTAssertEqual(try adapter.loadAndReconcile(), .discarded(.corruptSnapshot))
        XCTAssertNil(port.data)
    }

    func testSnapshotRoundTripIsDeviceOperationalOnly() throws {
        let target = try NavigationTargetV1(workspaceID: workspace, destination: .draftReview, requestedMode: .resume, fieldPosition: .init(sectionID: "section", fieldID: "field", boundedPosition: 4))
        let snapshot = try SceneNavigationSnapshotV1(workspaceID: workspace, selectedRoot: .work, paths: completePaths(root: .work, target: target), snapshotID: UUID())
        let port = InMemorySceneNavigationDeviceStatePortV1()
        let adapter = SceneNavigationStateAdapterV1(port: port)
        try adapter.save(snapshot)
        XCTAssertEqual(try adapter.loadAndReconcile(), .restored(snapshot))
        let lifecycle = SceneNavigationLifecycleDispositionV1()
        XCTAssertFalse(lifecycle.workspaceTruth)
        XCTAssertFalse(lifecycle.backupIncluded)
        XCTAssertFalse(lifecycle.journalIncluded)
        XCTAssertTrue(lifecycle.eraseClears)
        XCTAssertTrue(C34SceneNavigationSyncBoundaryV1.validate())
        XCTAssertEqual(C34SceneNavigationSyncBoundaryV1.filesystemBackup, .excluded)
        XCTAssertEqual(C34SceneNavigationSyncBoundaryV1.semanticBackup, .exclude)
        XCTAssertEqual(C34SceneNavigationSyncBoundaryV1.portableExport, .exclude)
        XCTAssertFalse(C34SceneNavigationSyncBoundaryV1.journalParticipation)
        XCTAssertFalse(C34SceneNavigationSyncBoundaryV1.customerExportParticipation)
    }

    func testSignoffRoutesBindStableIdentity() throws {
        let signoffID = UUID()
        let editor = SignoffEditorRouteV1(workspaceID: workspace, signoffID: signoffID, expectedRevision: 3)
        let history = SignoffHistoryRouteV1(workspaceID: workspace, signoffID: signoffID)
        XCTAssertEqual(try editor.target.destination, .signoffEditor)
        XCTAssertEqual(try history.target.destination, .signoffHistory)
        XCTAssertEqual(try editor.target.stableEntityID, signoffID)
    }

    func testDraftAndSearchRestorationPersistAnchorsButNotUserContent() throws {
        let search = try SearchSessionStateV1(query: "private search text", scope: .assets, selectedStableID: "asset-1")
        let sanitized = try RouteSearchAnchorV1(sanitizing: search)
        let draft = try DraftResumeAnchorV1(sectionID: "inspection", fieldID: "condition", selectedStableID: "asset-1", boundedPosition: 7)
        let target = try NavigationTargetV1(workspaceID: workspace, destination: .draftReview, requestedMode: .resume, draftResumeAnchor: draft, searchAnchor: sanitized)
        let snapshot = try SceneNavigationSnapshotV1(workspaceID: workspace, selectedRoot: .work, paths: completePaths(root: .work, target: target), snapshotID: UUID())
        let encoded = try RouteCanonicalCodecV1.encode(snapshot)
        let text = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        XCTAssertFalse(text.contains("private search text"))
        XCTAssertFalse(text.lowercased().contains("payload"))
        XCTAssertEqual(snapshot.selectedTarget?.draftResumeAnchor, draft)
    }

    func testAllEvidenceReceiptsAreZeroWriteAndExactRetryIsIdempotent() throws {
        let result = try RouteRegistryV1().resolve(try NavigationTargetV1(workspaceID: workspace, destination: .today), context: .init(currentWorkspaceID: workspace, currentRevision: 0))
        let receiptID = UUID(uuid: (0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x42, 0x22, 0x82, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22))
        for kind in [RouteEvidenceKindV1.golden, .alternate, .hostile, .interruption, .recovery] {
            let first = try RouteRestorationReceiptV1(receiptID: receiptID, evidenceKind: kind, source: .todayFallback, result: result, snapshotID: nil)
            let retry = try RouteRestorationReceiptV1(receiptID: receiptID, evidenceKind: kind, source: .todayFallback, result: result, snapshotID: nil)
            try first.validate()
            XCTAssertEqual(first.receiptSHA256, retry.receiptSHA256)
            XCTAssertEqual(first.canonicalMutationCount, 0)
            XCTAssertFalse(first.startsAutomaticWork)
            XCTAssertEqual(try RouteRestorationReceiptV1.reconcile(candidate: retry, existing: first), .sameReceipt)
        }
        let changedResult = RouteResolutionResultV1(disposition: .safeFallback, target: result.target, reason: .invalidTarget, canonicalMutationCount: 0, startsAutomaticWork: false)
        let changed = try RouteRestorationReceiptV1(receiptID: receiptID, evidenceKind: .golden, source: .todayFallback, result: changedResult, snapshotID: nil)
        let original = try RouteRestorationReceiptV1(receiptID: receiptID, evidenceKind: .golden, source: .todayFallback, result: result, snapshotID: nil)
        XCTAssertEqual(try RouteRestorationReceiptV1.reconcile(candidate: changed, existing: original), .quarantineChangedInput)
    }

    func testSnapshotRejectsMissingAndDuplicateRootsAndDecoderRejectsFifthRoot() throws {
        XCTAssertThrowsError(try SceneNavigationSnapshotV1(workspaceID: workspace, selectedRoot: .today, paths: [.init(root: .today, targets: [])], snapshotID: UUID()))
        XCTAssertThrowsError(try SceneNavigationSnapshotV1(workspaceID: workspace, selectedRoot: .today, paths: [
            .init(root: .today, targets: []), .init(root: .today, targets: []),
            .init(root: .assets, targets: []), .init(root: .reports, targets: [])
        ], snapshotID: UUID()))
        let fifthRoot = Data(#"{"schemaVersion":1,"workspaceID":{"rawValue":"11111111-1111-4111-8111-111111111111"},"selectedRoot":"SEARCH","paths":[],"snapshotID":"22222222-2222-4222-8222-222222222222"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(SceneNavigationSnapshotV1.self, from: fifthRoot))
    }

    func testRestoreSceneReconcilesLongestAvailablePrefixForEveryRoot() throws {
        let destinations: [AppRootV1: NavigationDestinationV1] = [
            .today: .startupMaintenance,
            .work: .draftReview,
            .assets: .searchResults,
            .reports: .settings
        ]
        var unavailable: Set<UUID> = []
        var expected: [AppRootV1: NavigationTargetV1] = [:]
        let paths = try AppRootV1.frozenOrder.map { root -> SceneRootPathV1 in
            let destination = try XCTUnwrap(destinations[root])
            let rootTarget = try NavigationTargetV1(
                workspaceID: workspace,
                destination: RouteRegistryV1.rootDestination(for: root)
            )
            let retained = try NavigationTargetV1(
                workspaceID: workspace,
                destination: destination,
                stableEntityID: UUID()
            )
            let unavailableID = UUID()
            unavailable.insert(unavailableID)
            let unavailableTarget = try NavigationTargetV1(
                workspaceID: workspace,
                destination: destination,
                stableEntityID: unavailableID
            )
            let unreachableTail = try NavigationTargetV1(
                workspaceID: workspace,
                destination: destination,
                stableEntityID: UUID()
            )
            expected[root] = retained
            return SceneRootPathV1(
                root: root,
                targets: [rootTarget, retained, unavailableTarget, unreachableTail]
            )
        }
        let snapshot = try SceneNavigationSnapshotV1(
            workspaceID: workspace,
            selectedRoot: .assets,
            paths: paths,
            snapshotID: UUID()
        )
        let context = RouteResolutionContextV1(
            currentWorkspaceID: workspace,
            currentRevision: 0,
            unavailableStableIDs: unavailable
        )
        let restored = try RouteCoordinatorV1(registry: try RouteRegistryV1()).restoreScene(
            request(context: context, sceneSnapshot: snapshot)
        )

        XCTAssertEqual(restored.receipt.source, .sceneSnapshot)
        XCTAssertEqual(restored.selectedRoot, .assets)
        XCTAssertEqual(restored.paths.map(\.root), AppRootV1.frozenOrder)
        for root in AppRootV1.frozenOrder {
            XCTAssertEqual(restored.path(for: root)?.targets, [try XCTUnwrap(expected[root])])
            XCTAssertFalse(restored.path(for: root)?.targets.contains(where: {
                $0.destination == RouteRegistryV1.rootDestination(for: root)
            }) ?? true)
        }
        XCTAssertEqual(restored.receipt.result.target, try XCTUnwrap(expected[.assets]))
        XCTAssertEqual(restored.receipt.result.disposition, .safeFallback)
        XCTAssertEqual(restored.receipt.result.reason, .deletedOrTombstoned)
        XCTAssertEqual(restored.receipt.canonicalMutationCount, 0)
        XCTAssertFalse(restored.receipt.startsAutomaticWork)
    }

    func testSemanticRootDestinationIsRetainedForSnapshotAndExplicitIngress() throws {
        let marker = try NavigationTargetV1(
            workspaceID: workspace,
            destination: .assets
        )
        let semanticAsset = try NavigationTargetV1(
            workspaceID: workspace,
            destination: .assets,
            stableEntityID: UUID()
        )
        XCTAssertTrue(marker.isIdentitylessSceneRootMarker)
        XCTAssertFalse(semanticAsset.isIdentitylessSceneRootMarker)
        let snapshot = try SceneNavigationSnapshotV1(
            workspaceID: workspace,
            selectedRoot: .assets,
            paths: AppRootV1.frozenOrder.map { root in
                SceneRootPathV1(
                    root: root,
                    targets: root == .assets ? [marker, semanticAsset] : []
                )
            },
            snapshotID: UUID()
        )
        let context = RouteResolutionContextV1(
            currentWorkspaceID: workspace,
            currentRevision: 0
        )
        let coordinator = RouteCoordinatorV1(registry: try RouteRegistryV1())

        let restored = try coordinator.restoreScene(
            request(context: context, sceneSnapshot: snapshot)
        )
        XCTAssertEqual(restored.path(for: .assets)?.targets, [semanticAsset])
        XCTAssertEqual(restored.receipt.result.target, semanticAsset)
        XCTAssertEqual(restored.receipt.result.disposition, .resolved)

        let ingress = try coordinator.restoreScene(
            request(context: context, explicitIngressTarget: semanticAsset)
        )
        XCTAssertEqual(ingress.receipt.source, .explicitIngress)
        XCTAssertEqual(ingress.path(for: .assets)?.targets, [semanticAsset])
        XCTAssertEqual(ingress.receipt.result.target, semanticAsset)
        XCTAssertEqual(ingress.receipt.result.disposition, .resolved)
        XCTAssertEqual(ingress.receipt.canonicalMutationCount, 0)
        XCTAssertFalse(ingress.receipt.startsAutomaticWork)
    }

    func testSelectedSnapshotCutoffPreservesStaleReasonAndPriorityOverridesIt() throws {
        let marker = try NavigationTargetV1(
            workspaceID: workspace,
            destination: .work
        )
        let safeParent = try NavigationTargetV1(
            workspaceID: workspace,
            destination: .draftReview,
            stableSessionID: UUID()
        )
        let staleTarget = try NavigationTargetV1(
            workspaceID: workspace,
            destination: .draftReview,
            stableSessionID: UUID(),
            expectedRevision: 2
        )
        let unreachableTail = try NavigationTargetV1(
            workspaceID: workspace,
            destination: .draftReview,
            stableSessionID: UUID()
        )
        let snapshot = try SceneNavigationSnapshotV1(
            workspaceID: workspace,
            selectedRoot: .work,
            paths: AppRootV1.frozenOrder.map { root in
                SceneRootPathV1(
                    root: root,
                    targets: root == .work
                        ? [marker, safeParent, staleTarget, unreachableTail] : []
                )
            },
            snapshotID: UUID()
        )
        let context = RouteResolutionContextV1(
            currentWorkspaceID: workspace,
            currentRevision: 1
        )
        let coordinator = RouteCoordinatorV1(registry: try RouteRegistryV1())

        let restored = try coordinator.restoreScene(
            request(context: context, sceneSnapshot: snapshot)
        )
        XCTAssertEqual(restored.path(for: .work)?.targets, [safeParent])
        XCTAssertEqual(restored.receipt.result.target, safeParent)
        XCTAssertEqual(restored.receipt.result.disposition, .safeFallback)
        XCTAssertEqual(restored.receipt.result.reason, .staleRevision)
        XCTAssertEqual(restored.receipt.canonicalMutationCount, 0)
        XCTAssertFalse(restored.receipt.startsAutomaticWork)

        let maintenance = try NavigationTargetV1(
            workspaceID: workspace,
            destination: .startupMaintenance
        )
        let priority = try coordinator.restoreScene(
            request(
                context: context,
                startupMaintenanceTarget: maintenance,
                sceneSnapshot: snapshot
            )
        )
        XCTAssertEqual(priority.receipt.source, .startupMaintenance)
        XCTAssertEqual(priority.receipt.result.target, maintenance)
        XCTAssertEqual(priority.receipt.result.disposition, .resolved)
        XCTAssertNil(priority.receipt.result.reason)
        XCTAssertEqual(priority.path(for: .work)?.targets, [safeParent])
        XCTAssertEqual(priority.receipt.canonicalMutationCount, 0)
        XCTAssertFalse(priority.receipt.startsAutomaticWork)
    }

    func testRestoreSceneRetainsPriorityAndNeverPushesRootDestination() throws {
        let snapshotTarget = try NavigationTargetV1(
            workspaceID: workspace,
            destination: .assets
        )
        let snapshot = try SceneNavigationSnapshotV1(
            workspaceID: workspace,
            selectedRoot: .assets,
            paths: completePaths(root: .assets, target: snapshotTarget),
            snapshotID: UUID()
        )
        let context = RouteResolutionContextV1(currentWorkspaceID: workspace, currentRevision: 0)
        let coordinator = RouteCoordinatorV1(registry: try RouteRegistryV1())
        let snapshotResult = try coordinator.restoreScene(
            request(context: context, sceneSnapshot: snapshot)
        )
        XCTAssertEqual(snapshotResult.selectedRoot, .assets)
        XCTAssertEqual(snapshotResult.path(for: .assets)?.targets, [])
        XCTAssertEqual(snapshotResult.receipt.result.target.destination, .assets)

        let maintenance = try NavigationTargetV1(
            workspaceID: workspace,
            destination: .startupMaintenance
        )
        let priority = try coordinator.restoreScene(
            request(
                context: context,
                startupMaintenanceTarget: maintenance,
                sceneSnapshot: snapshot
            )
        )
        XCTAssertEqual(priority.receipt.source, .startupMaintenance)
        XCTAssertEqual(priority.selectedRoot, .today)
        XCTAssertEqual(priority.path(for: .today)?.targets, [maintenance])
        XCTAssertEqual(priority.path(for: .assets)?.targets, [])
    }

    func testSceneSnapshotEnforcesPerRootDepthAndStorageFailureBoundary() throws {
        XCTAssertEqual(SceneNavigationSnapshotV1.maximumEncodedByteCount, 64 * 1024)
        XCTAssertEqual(SceneNavigationSnapshotV1.maximumPathDepth, 32)
        let target = try NavigationTargetV1(workspaceID: workspace, destination: .settings)
        let overDepth = AppRootV1.frozenOrder.map { root in
            SceneRootPathV1(
                root: root,
                targets: root == .reports
                    ? Array(repeating: target, count: SceneNavigationSnapshotV1.maximumPathDepth + 1)
                    : []
            )
        }
        XCTAssertThrowsError(try SceneNavigationSnapshotV1(
            workspaceID: workspace,
            selectedRoot: .reports,
            paths: overDepth,
            snapshotID: UUID()
        )) { error in
            XCTAssertEqual(error as? SceneNavigationFailureV1, .invalidPath)
        }

        let corruptPort = V959ThrowingSceneNavigationPort(loadError: SceneNavigationFailureV1.invalidSnapshot)
        XCTAssertEqual(
            try SceneNavigationStateAdapterV1(port: corruptPort).loadAndReconcile(),
            .discarded(.corruptSnapshot)
        )
        XCTAssertEqual(corruptPort.eraseCount, 1)

        let failingPort = V959ThrowingSceneNavigationPort(loadError: V959ScenePortFailure.io)
        XCTAssertThrowsError(
            try SceneNavigationStateAdapterV1(port: failingPort).loadAndReconcile()
        ) { error in
            XCTAssertEqual(error as? V959ScenePortFailure, .io)
        }
        XCTAssertEqual(failingPort.eraseCount, 0)
    }

    @MainActor
    func testConcreteSceneTokenFencesLoadSaveRestoreAndRejectsRevocationABA() async throws {
        let gate = AppAccessGateV1(
            setting: .absentDisabled,
            authentication: V959AuthenticationClient(),
            clock: V959Clock(),
            identifiers: V959IDs()
        )
        let sceneToken = try await gate.beginContentRead(for: .sceneRestoration)
        let wrongSurfaceToken = try await gate.beginContentRead(for: .search)
        let target = try NavigationTargetV1(workspaceID: workspace, destination: .draftReview)
        let snapshot = try SceneNavigationSnapshotV1(
            workspaceID: workspace,
            selectedRoot: .work,
            paths: completePaths(root: .work, target: target),
            snapshotID: UUID()
        )
        let port = InMemorySceneNavigationDeviceStatePortV1()
        let adapter = SceneNavigationStateAdapterV1(port: port)
        try adapter.save(snapshot, using: sceneToken)
        XCTAssertEqual(try adapter.loadAndReconcile(using: sceneToken), .restored(snapshot))
        let coordinator = RouteCoordinatorV1(registry: try RouteRegistryV1())
        let restorationRequest = request(
            context: .init(currentWorkspaceID: workspace, currentRevision: 0),
            sceneSnapshot: snapshot
        )
        XCTAssertEqual(
            try coordinator.restoreScene(restorationRequest, using: sceneToken).receipt.source,
            .sceneSnapshot
        )
        XCTAssertThrowsError(try adapter.loadAndReconcile(using: wrongSurfaceToken)) { error in
            XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied)
        }
        XCTAssertThrowsError(
            try coordinator.restoreScene(restorationRequest, using: wrongSurfaceToken)
        ) { error in
            XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied)
        }

        await gate.markProtectedDataUnavailable()
        XCTAssertThrowsError(try adapter.loadAndReconcile(using: sceneToken)) { error in
            XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied)
        }
        XCTAssertNotNil(port.data, "denied token must not enter device-state storage")
        let pendingRecoveryGeneration = await gate.protectedDataAvailabilityRecoveryGeneration()
        let recoveryGeneration = try XCTUnwrap(pendingRecoveryGeneration)
        try await gate.recoverProtectedDataAvailability(
            setting: .absentDisabled,
            configurationVerified: true,
            expectedGeneration: recoveryGeneration
        )
        let freshToken = try await gate.beginContentRead(for: .sceneRestoration)
        XCTAssertEqual(try adapter.loadAndReconcile(using: freshToken), .restored(snapshot))
        XCTAssertThrowsError(try adapter.save(snapshot, using: sceneToken)) { error in
            XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied)
        }
    }

    private func request(
        context: RouteResolutionContextV1,
        startupMaintenanceTarget: NavigationTargetV1? = nil,
        incompleteMutationRecoveryTarget: NavigationTargetV1? = nil,
        explicitIngressTarget: NavigationTargetV1? = nil,
        sceneSnapshot: SceneNavigationSnapshotV1? = nil,
        discardedSnapshotReason: RouteFallbackReasonV1? = nil
    ) -> RouteRestorationRequestV1 {
        RouteRestorationRequestV1(
            context: context,
            startupMaintenanceTarget: startupMaintenanceTarget,
            incompleteMutationRecoveryTarget: incompleteMutationRecoveryTarget,
            explicitIngressTarget: explicitIngressTarget,
            sceneSnapshot: sceneSnapshot,
            discardedSnapshotReason: discardedSnapshotReason,
            evidenceKind: .golden,
            receiptID: UUID()
        )
    }

    private func completePaths(root: AppRootV1, target: NavigationTargetV1) -> [SceneRootPathV1] {
        AppRootV1.frozenOrder.map { SceneRootPathV1(root: $0, targets: $0 == root ? [target] : []) }
    }
}

private enum V959ScenePortFailure: Error, Equatable {
    case io
}

private final class V959ThrowingSceneNavigationPort: SceneNavigationDeviceStatePortV1 {
    let loadError: Error
    private(set) var eraseCount = 0

    init(loadError: Error) { self.loadError = loadError }
    func loadSceneNavigationData() throws -> Data? { throw loadError }
    func saveSceneNavigationData(_ data: Data) throws {}
    func eraseSceneNavigationData() throws { eraseCount += 1 }
}

private struct V959Clock: ApplicationClock {
    func now() -> Date { Date(timeIntervalSince1970: 1_800_000_000) }
}

private struct V959IDs: ApplicationIDSource {
    func makeID() -> UUID {
        UUID(uuid: (0x59, 0x59, 0x59, 0x59, 0x59, 0x59, 0x49, 0x59,
                    0x89, 0x59, 0x59, 0x59, 0x59, 0x59, 0x59, 0x59))
    }
}

private actor V959AuthenticationClient: LocalAuthenticationClient {
    func availability() -> LocalAuthenticationAvailabilityV1 {
        .systemValue(status: .available, biometry: .faceID)
    }

    func authenticate(_ attempt: LocalAuthenticationAttemptV1) -> LocalAuthenticationOutcomeV1 {
        .authenticated
    }

    func cancel(attemptID: UUID) {}
}

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

    private func completePaths(root: AppRootV1, target: NavigationTargetV1) -> [SceneRootPathV1] {
        AppRootV1.frozenOrder.map { SceneRootPathV1(root: $0, targets: $0 == root ? [target] : []) }
    }
}

import Combine
import Foundation
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import FieldEvidenceApp

final class V23ProductionWorkAssetTests: V23ProductionFourRootShellTestSupport {
    @MainActor
    func testActualWorkAssetPreflightRestoresWithoutDraftOrCameraAndBackClearsPath() async throws {
        #if DEBUG
        // These objects are deliberately outside the mounted production host.
        let direct = UIView()
        direct.accessibilityIdentifier = "container-regression-target"
        XCTAssertEqual(direct.accessibilityIdentifier, "container-regression-target")
        XCTAssertTrue(containsAccessibilityIdentifier(identifiedBy: "container-regression-target", in: direct))
        let ordinaryRoot = UIView()
        ordinaryRoot.addSubview(direct)
        XCTAssertTrue(containsAccessibilityIdentifier(identifiedBy: "container-regression-target", in: ordinaryRoot))
        direct.removeFromSuperview()
        let nestedRoot = UIView()
        let nested = UIAccessibilityElement(accessibilityContainer: nestedRoot)
        let leaf = UIAccessibilityElement(accessibilityContainer: nested)
        leaf.accessibilityIdentifier = "container-regression-target"
        nestedRoot.accessibilityElements = [nested]
        nested.accessibilityElements = [leaf]
        XCTAssertTrue(containsAccessibilityIdentifier(identifiedBy: "container-regression-target", in: nestedRoot))
        let indexedRoot = UIView()
        let indexed = V23IndexedAccessibilityContainer()
        indexed.elements = [leaf]
        indexedRoot.accessibilityElements = [indexed]
        XCTAssertTrue(containsAccessibilityIdentifier(identifiedBy: "container-regression-target", in: indexedRoot))
        indexed.elements = [indexed, indexedRoot]
        let cyclic = accessibilityObservation("absent", in: indexedRoot)
        XCTAssertFalse(cyclic.found)
        XCTAssertEqual(cyclic.visited, 2)
        XCTAssertFalse(cyclic.truncated)
        XCTAssertFalse(containsAccessibilityIdentifier(identifiedBy: "container-regression-target", in: UIView()))
        indexed.elements = []
        indexedRoot.accessibilityElements = nil
        nested.accessibilityElements = nil
        nestedRoot.accessibilityElements = nil
        let fixture = try await makeFixture("work-asset-preflight")
        defer { fixture.cleanUp() }
        let sign = try await makeWorkAsset(in: fixture, label: "preflight")
        let target = try validatedWorkTarget(sign, in: fixture)
        let sceneAccess = try XCTUnwrap(fixture.presentation.sceneNavigationAccess)
        let scene = AppShellSceneStateV1(workspaceID: fixture.coordinator.workspaceID,
            access: sceneAccess, registry: try RouteRegistryV1())
        try scene.restore()
        let before = try fixture.coordinator.workspaceWriter.currentRevision()
        try scene.open(target)
        var statusReads = 0
        var permissionRequests = 0
        var availabilityReads = 0
        let camera = CameraAdapter(
            authorizationStatus: { statusReads += 1; return .denied },
            requestAuthorization: { permissionRequests += 1; return .denied },
            isCameraAvailable: { availabilityReads += 1; return false }
        )
        var actualScene: AppShellSceneStateV1?
        var shell = AppShellView(packLoadResult: .available(.illuminatedSignV1),
            storeSession: fixture.coordinator,
            contentAccess: try XCTUnwrap(fixture.presentation.renderAccess),
            sceneNavigationAccess: sceneAccess,
            myDayAccess: try XCTUnwrap(fixture.presentation.myDayAccess),
            diagnosticsStore: fixture.diagnostics,
            metricKitDiagnosticsAdapter: MetricKitDiagnosticsAdapter(manager: nil),
            feedbackConfiguration: .production, mailComposerAdapter: .unavailable,
            cameraAdapter: camera, entitlementProcessor: fixture.router.entitlementProcessor)
        shell.onProductionSceneBoundForTesting = { composed in
            actualScene = composed
            print("WorkStartupDiagnostic scene_bound work_selected=\(composed.snapshot?.selectedRoot == .work) exact_target=\(composed.snapshot?.path(for: .work)?.targets == [target])")
        }
        let windowScene = try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = windowScene.windows.first { $0.isKeyWindow }
        let host = UIHostingController(rootView: shell.modelContext(fixture.coordinator.modelContext))
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previousKeyWindow?.makeKeyAndVisible() }
        host.view.layoutIfNeeded()
        let visible = await waitForAccessibilityIdentifier(
            PreflightView.screenAccessibilityIdentifier, in: host.view)
        print("WorkStartupDiagnostic after_wait scene_bound=\(actualScene != nil) work_selected=\(actualScene?.snapshot?.selectedRoot == .work) exact_target=\(actualScene?.snapshot?.path(for: .work)?.targets == [target])")
        if !visible { logNativeObservation(PreflightView.screenAccessibilityIdentifier, from: host, phase: "initial_preflight") }
        XCTAssertTrue(visible)
        XCTAssertEqual(scene.snapshot?.path(for: .work)?.targets, [target])
        XCTAssertEqual(statusReads, 0)
        XCTAssertEqual(permissionRequests, 0)
        XCTAssertEqual(availabilityReads, 0)
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), before)
        XCTAssertEqual(try fixture.coordinator.modelContext.fetchCount(FetchDescriptor<WorkflowRecord>()), 0)
        let navigation = try XCTUnwrap(navigationControllerPresenting(
            accessibilityIdentifier: PreflightView.screenAccessibilityIdentifier, from: host))
        navigation.popToRootViewController(animated: false)
        let returnedToWorkRoot = await waitForPersistedWorkRoot(sceneAccess)
        XCTAssertTrue(returnedToWorkRoot)
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), before)
        XCTAssertFalse(fixture.coordinator.modelContext.hasChanges)
        #else
        throw XCTSkip("Native work preflight observation is DEBUG-only")
        #endif
    }

    @MainActor
    func testActualHiddenWorkPathActivatesCoalescesAndCancelPreservesReports() async throws {
        #if DEBUG
        let fixture = try await makeFixture("work-hidden-activation")
        defer { fixture.cleanUp() }
        let context = try await V23WorkRouteHarness.make(in: fixture, label: "first")
        let second = try await makeWorkAsset(in: fixture, label: "second")
        let firstTarget = try context.target(expectedRevision: context.assetRevision())
        let secondTarget = try validatedWorkTarget(second, in: fixture)
        let report = try await makeReadyReport(in: fixture, label: "retained")
        let reportTarget = try validatedReportTarget(report, in: fixture)
        try context.scene.open(reportTarget)
        try context.scene.open(firstTarget)
        try context.scene.select(.today)
        XCTAssertFalse(context.admission(for: firstTarget).isActiveWorkRoute())
        XCTAssertThrowsError(try context.admission(for: firstTarget).loadForActivePresentation())
        let before = try context.store.workspaceWriter.currentRevision()
        let recordCount = try context.store.modelContext.fetchCount(FetchDescriptor<WorkflowRecord>())
        let sceneBound = expectation(description: "The actual shell exposes its composed scene")
        let tabsBound = expectation(description: "The actual shell restores Today")
        var actualScene: AppShellSceneStateV1?
        var actualTabBar: UITabBar?
        var shell = AppShellView(packLoadResult: .available(.illuminatedSignV1),
            storeSession: context.store, contentAccess: context.contentAccess,
            sceneNavigationAccess: context.sceneAccess,
            myDayAccess: try XCTUnwrap(fixture.presentation.myDayAccess),
            diagnosticsStore: fixture.diagnostics,
            metricKitDiagnosticsAdapter: MetricKitDiagnosticsAdapter(manager: nil),
            feedbackConfiguration: .production, mailComposerAdapter: .unavailable,
            entitlementProcessor: fixture.router.entitlementProcessor)
        shell.onProductionSceneBoundForTesting = { scene in
            guard actualScene == nil else { return }
            actualScene = scene
            sceneBound.fulfill()
        }
        shell.onNativeTabsBoundForTesting = { tabBar in
            guard actualTabBar == nil, tabBar.selectedItem?.title == "Today" else { return }
            actualTabBar = tabBar
            tabsBound.fulfill()
        }
        let windowScene = try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = windowScene.windows.first { $0.isKeyWindow }
        let host = UIHostingController(rootView: shell.modelContext(context.store.modelContext))
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previousKeyWindow?.makeKeyAndVisible() }
        host.view.layoutIfNeeded()
        await fulfillment(of: [sceneBound, tabsBound], timeout: 20)
        let scene = try XCTUnwrap(actualScene)
        let tabBar = try XCTUnwrap(actualTabBar)
        XCTAssertEqual(scene.snapshot?.selectedRoot, .today)
        XCTAssertEqual(scene.snapshot?.path(for: .work)?.targets, [firstTarget])
        // Drive the production scene observed by the mounted shell, including
        // its hidden-to-selected task identity, rather than a second scene.
        try scene.select(.work)
        let visible = await waitForAccessibilityIdentifier(
            PreflightView.screenAccessibilityIdentifier, in: host.view)
        if !visible { logNativeObservation(PreflightView.screenAccessibilityIdentifier, from: host, phase: "activated_preflight") }
        XCTAssertTrue(visible)
        XCTAssertEqual(tabBar.selectedItem?.title, "Work")
        let beforeCoalescing = scene.snapshot?.snapshotID
        try scene.setPath([secondTarget], for: .work)
        try scene.setPath([firstTarget], for: .work)
        XCTAssertNotEqual(scene.snapshot?.snapshotID, beforeCoalescing)
        let admission = WorkAssetPreflightRouteAdmissionV1(target: firstTarget,
            workflow: context.workflow, scene: scene, contentAccess: context.contentAccess)
        XCTAssertEqual(try admission.loadForActivePresentation().assetID, context.sign.assetID)
        XCTAssertEqual(scene.snapshot?.path(for: .work)?.targets, [firstTarget])
        XCTAssertEqual(scene.snapshot?.path(for: .reports)?.targets, [reportTarget])
        try scene.setPath([secondTarget], for: .work)
        try admission.cancel()
        XCTAssertEqual(scene.snapshot?.path(for: .work)?.targets, [secondTarget],
            "An old A cancellation cannot clear the current B route")
        XCTAssertEqual(scene.snapshot?.path(for: .reports)?.targets, [reportTarget])
        try scene.setPath([firstTarget], for: .work)
        try admission.cancel()
        let cleared = await waitForPersistedWorkRoot(context.sceneAccess)
        XCTAssertTrue(cleared)
        XCTAssertEqual(scene.snapshot?.selectedRoot, .work)
        XCTAssertEqual(scene.snapshot?.path(for: .reports)?.targets, [reportTarget])
        try context.scene.restore()
        XCTAssertEqual(context.scene.snapshot?.path(for: .work)?.targets, [])
        XCTAssertEqual(context.scene.snapshot?.path(for: .reports)?.targets, [reportTarget])
        // The one-destination adapter must leave a legitimate longer saved
        // path intact while showing Work root. Mounting [] cannot erase it.
        try scene.setPath([firstTarget, secondTarget], for: .work)
        let rootVisible = await waitForAccessibilityIdentifier(
            ProductionWorkRootViewV1.screenAccessibilityIdentifier, in: host.view)
        if !rootVisible { logNativeObservation(ProductionWorkRootViewV1.screenAccessibilityIdentifier, from: host, phase: "long_path_root") }
        XCTAssertTrue(rootVisible)
        let atNativeRoot = await waitForNativeRoot(
            ProductionWorkRootViewV1.screenAccessibilityIdentifier, from: host)
        if !atNativeRoot { logNativeObservation(ProductionWorkRootViewV1.screenAccessibilityIdentifier, from: host, phase: "long_path_native_root") }
        XCTAssertTrue(atNativeRoot)
        XCTAssertEqual(scene.snapshot?.path(for: .work)?.targets, [firstTarget, secondTarget])
        try context.scene.restore()
        XCTAssertEqual(context.scene.snapshot?.path(for: .work)?.targets, [firstTarget, secondTarget])
        XCTAssertEqual(context.scene.snapshot?.path(for: .reports)?.targets, [reportTarget])
        XCTAssertEqual(try context.store.workspaceWriter.currentRevision(), before)
        XCTAssertEqual(try context.store.modelContext.fetchCount(FetchDescriptor<WorkflowRecord>()), recordCount)
        XCTAssertFalse(context.store.modelContext.hasChanges)
        #else
        throw XCTSkip("Native Work activation observation is DEBUG-only")
        #endif
    }

    @MainActor
    func testActualWorkAdmissionRejectsStaleForeignWrongFamilyAndAmbiguousAssetIDsWithoutBegin() async throws {
        let fixture = try await makeFixture("work-source-admission")
        defer { fixture.cleanUp() }
        let context = try await V23WorkRouteHarness.make(in: fixture, label: "admission")
        let current = try context.target(expectedRevision: context.assetRevision())
        try context.scene.open(current)
        let displayed = try context.admission(for: current).loadForActivePresentation()
        XCTAssertEqual(displayed.assetID, context.sign.assetID)
        let fallback = try NavigationFallbackV1(root: .work, destination: .work)
        let stale = try context.target(expectedRevision: context.assetRevision() + 1)
        let foreign = try NavigationTargetV1(workspaceID: WorkspaceID(), destination: .work,
            stableEntityID: context.sign.assetID, requestedMode: .read, fallback: fallback)
        let wrongDestination = try NavigationTargetV1(workspaceID: context.store.workspaceID,
            destination: .assets, stableEntityID: context.sign.assetID)
        let wrongFamily = try NavigationTargetV1(workspaceID: context.store.workspaceID,
            destination: .work, stableEntityID: context.sign.siteID,
            requestedMode: .read, fallback: fallback)
        let before = try context.store.workspaceWriter.currentRevision()
        for target in [stale, foreign, wrongDestination, wrongFamily] {
            try context.scene.open(target)
            let admission = context.admission(for: target)
            XCTAssertThrowsError(try admission.loadForActivePresentation())
            XCTAssertThrowsError(try context.begin(using: admission, displayed: displayed)) {
                XCTAssertEqual($0 as? PreflightBeginOperationFailureV1, .routeValidationDenied)
            }
            XCTAssertEqual(try context.store.workspaceWriter.currentRevision(), before)
            XCTAssertEqual(try context.store.modelContext.fetchCount(FetchDescriptor<WorkflowRecord>()), 0)
            XCTAssertFalse(context.store.modelContext.hasChanges)
        }

        // An actual canonical packet is a Work route, but cannot supply an Asset.
        // A packet sharing the Asset UUID makes that bare ID ambiguous.
        let packetFixture = try C15WorkPacketManifestTestSupportV1.makeFixture(seed: 179_000)
        let source = try packetFixture.manifest.rebound(to: context.store.workspaceID)
        _ = try context.store.workspaceWriter.execute(
            .applyPartyAccountability(.appendActorSnapshot(source.creator)),
            mutationID: MutationIDV1(rawValue: UUID()))
        for packetID in [UUID(), context.sign.assetID] {
            let packet = try WorkPacketManifestV1(manifestID: UUID(), packetID: packetID,
                packetVersion: 1, workspaceID: context.store.workspaceID,
                items: [.init(itemID: "source-item", kind: .inspection,
                    expectedRevision: 1, itemSHA256: String(repeating: "a", count: 64))],
                packageReleases: [], creationBasis: .explicitLocalSelection,
                creator: source.creator, createdAt: source.createdAt,
                mutationID: MutationIDV1(rawValue: UUID()))
            let mutation = try WorkPacketMutationV1(workspaceID: context.store.workspaceID,
                expectedRevision: 0, mutationID: packet.mutationID, postImage: .appendManifest(packet))
            _ = try context.store.workspaceWriter.execute(.applyWorkPacket(mutation),
                mutationID: packet.mutationID)
            let target = try NavigationTargetV1(workspaceID: context.store.workspaceID,
                destination: .work, stableEntityID: packetID, requestedMode: .read, fallback: fallback)
            let afterPacket = try context.store.workspaceWriter.currentRevision()
            try context.scene.open(target)
            if packetID == context.sign.assetID {
                XCTAssertEqual(context.scene.lastRestoration?.receipt.result.reason, .invalidTarget)
            } else {
                XCTAssertEqual(context.scene.lastRestoration?.receipt.result.disposition, .resolved)
            }
            let admission = context.admission(for: target)
            XCTAssertThrowsError(try admission.loadForActivePresentation())
            XCTAssertThrowsError(try context.begin(using: admission, displayed: displayed)) {
                XCTAssertEqual($0 as? PreflightBeginOperationFailureV1, .routeValidationDenied)
            }
            XCTAssertEqual(try context.store.workspaceWriter.currentRevision(), afterPacket)
            XCTAssertEqual(try context.store.modelContext.fetchCount(FetchDescriptor<WorkflowRecord>()), 0)
            XCTAssertFalse(context.store.modelContext.hasChanges)
        }
    }

    @MainActor
    func testActualWorkBeginRejectsChangedDisplayedFactsAndFreshReadResumesOneDraft() async throws {
        let fixture = try await makeFixture("work-facts-before-begin")
        defer { fixture.cleanUp() }
        let context = try await V23WorkRouteHarness.make(in: fixture, label: "facts")
        let target = try context.target(expectedRevision: nil)
        try context.scene.open(target)
        let admission = context.admission(for: target)
        let displayed = try admission.loadForActivePresentation()
        let originalRevision = try context.store.workspaceWriter.currentRevision()
        XCTAssertNil(try context.workflow.checkRunner.prepare(assetID: context.sign.assetID).existingDraftID)
        XCTAssertEqual(try context.store.workspaceWriter.currentRevision(), originalRevision)

        _ = try context.store.workspaceWriter.execute(.updateSiteTimeZone(.init(
            siteID: context.sign.siteID, timeZoneID: "America/Chicago", confirmedAt: Date()
        )), mutationID: MutationIDV1(rawValue: UUID()))
        let changedRevision = try context.store.workspaceWriter.currentRevision()
        XCTAssertNotEqual(changedRevision, originalRevision)
        XCTAssertThrowsError(try context.begin(using: admission, displayed: displayed)) {
            XCTAssertEqual($0 as? PreflightBeginOperationFailureV1, .routeValidationDenied)
        }
        XCTAssertEqual(context.scene.snapshot?.path(for: .work)?.targets, [])
        XCTAssertEqual(try context.store.workspaceWriter.currentRevision(), changedRevision)
        XCTAssertEqual(try context.store.modelContext.fetchCount(FetchDescriptor<WorkflowRecord>()), 0)
        XCTAssertFalse(context.store.modelContext.hasChanges)

        // Nil remains the original current-availability route. A new read,
        // rather than a synthesized revision, supplies the newly shown facts.
        try context.scene.open(target)
        let fresh = try admission.loadForActivePresentation()
        XCTAssertEqual(fresh.timeZoneID, "America/Chicago")
        XCTAssertNotEqual(fresh, displayed)
        XCTAssertNil(context.scene.snapshot?.path(for: .work)?.targets.first?.expectedRevision)
        let first = try context.begin(using: admission, displayed: fresh)
        XCTAssertEqual(try context.store.modelContext.fetchCount(FetchDescriptor<WorkflowRecord>()), 1)
        let afterBegin = try context.store.workspaceWriter.currentRevision()
        let prepared = try context.workflow.checkRunner.prepare(assetID: context.sign.assetID)
        XCTAssertEqual(prepared.existingDraftID, first.id)
        let resumed = try context.begin(using: admission, displayed: fresh)
        XCTAssertEqual(resumed.id, first.id)
        XCTAssertEqual(try context.store.workspaceWriter.currentRevision(), afterBegin)
        XCTAssertEqual(try context.store.modelContext.fetchCount(FetchDescriptor<WorkflowRecord>()), 1)
        XCTAssertFalse(context.store.modelContext.hasChanges)
        // A later denied callback must not fall through into preparation or
        // create another record even when a resumable draft already exists.
        _ = try context.store.workspaceWriter.execute(.updateSiteTimeZone(.init(
            siteID: context.sign.siteID, timeZoneID: "America/Denver", confirmedAt: Date()
        )), mutationID: MutationIDV1(rawValue: UUID()))
        let afterSecondChange = try context.store.workspaceWriter.currentRevision()
        XCTAssertThrowsError(try context.begin(using: admission, displayed: fresh)) {
            XCTAssertEqual($0 as? PreflightBeginOperationFailureV1, .routeValidationDenied)
        }
        XCTAssertEqual(try context.store.workspaceWriter.currentRevision(), afterSecondChange)
        let retainedRecords = try context.store.modelContext.fetch(FetchDescriptor<WorkflowRecord>())
        XCTAssertEqual(retainedRecords.map(\.id), [first.id])
        XCTAssertFalse(context.store.modelContext.hasChanges)
    }

    @MainActor
    func testActualWorkBeginRejectsOldPublicationAfterPauseAndFreshPublicationResumes() async throws {
        let fixture = try await makeFixture("work-original-publication")
        defer { fixture.cleanUp() }
        let context = try await V23WorkRouteHarness.make(in: fixture, label: "publication")
        let target = try context.target(expectedRevision: context.assetRevision())
        try context.scene.open(target)
        let admission = context.admission(for: target)
        let displayed = try admission.loadForActivePresentation()
        let first = try context.begin(using: admission, displayed: displayed)
        let beforePause = try context.store.workspaceWriter.currentRevision()

        fixture.presentation.receive(.sceneInactive)
        XCTAssertFalse(fixture.presentation.permitsContentPresentation)
        XCTAssertThrowsError(try context.begin(using: admission, displayed: displayed)) {
            XCTAssertEqual($0 as? PreflightBeginOperationFailureV1, .routeValidationDenied)
        }
        XCTAssertNil(context.scene.snapshot)
        XCTAssertEqual(try context.store.workspaceWriter.currentRevision(), beforePause)
        XCTAssertEqual(try context.store.modelContext.fetchCount(FetchDescriptor<WorkflowRecord>()), 1)
        XCTAssertFalse(context.store.modelContext.hasChanges)

        let republished = expectation(description: "Actual scene activation publishes fresh Work capabilities")
        let observation = fixture.presentation.$permitsContentPresentation
            .filter { $0 }.prefix(1).sink { _ in republished.fulfill() }
        fixture.presentation.receive(.sceneActive)
        await fulfillment(of: [republished], timeout: 30)
        observation.cancel()
        XCTAssertTrue(fixture.presentation.permitsContentPresentation)
        XCTAssertThrowsError(try context.begin(using: admission, displayed: displayed)) {
            XCTAssertEqual($0 as? PreflightBeginOperationFailureV1, .routeValidationDenied)
        }

        let fresh = try await V23WorkRouteHarness.make(
            in: fixture, label: "fresh-publication", existingSign: context.sign
        )
        try fresh.scene.open(target)
        let freshAdmission = fresh.admission(for: target)
        let freshDisplayed = try freshAdmission.loadForActivePresentation()
        let beforeResume = try fresh.store.workspaceWriter.currentRevision()
        let resumed = try fresh.begin(using: freshAdmission, displayed: freshDisplayed)
        XCTAssertEqual(resumed.id, first.id)
        XCTAssertEqual(try fresh.store.workspaceWriter.currentRevision(), beforeResume)
        XCTAssertEqual(try fresh.store.modelContext.fetchCount(FetchDescriptor<WorkflowRecord>()), 1)
        XCTAssertFalse(fresh.store.modelContext.hasChanges)
    }
}

@MainActor
private final class V23IndexedAccessibilityContainer: NSObject {
    var elements: [Any] = []
    override func accessibilityElementCount() -> Int { elements.count }
    override func accessibilityElement(at index: Int) -> Any? {
        guard elements.indices.contains(index) else { return nil }
        return elements[index]
    }
}

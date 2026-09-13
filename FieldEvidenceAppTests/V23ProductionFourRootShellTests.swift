import Combine
import Foundation
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import FieldEvidenceApp

final class V23ProductionFourRootShellTests: XCTestCase {
    @MainActor
    func testActualNativeShellRestoresEachPersistedRootAndPreservesAcceptedTabIdentities() async throws {
        #if DEBUG
        let fixture = try await makeFixture("native-tabs")
        defer { fixture.cleanUp() }
        let sceneAccess = try XCTUnwrap(fixture.presentation.sceneNavigationAccess)
        let state = AppShellSceneStateV1(workspaceID: fixture.coordinator.workspaceID,
            access: sceneAccess, registry: try RouteRegistryV1())
        try state.restore()
        let before = try fixture.coordinator.workspaceWriter.currentRevision()
        let windowScene = try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = windowScene.windows.first { $0.isKeyWindow }
        let expectedTitles = ["Today", "Work", "Assets", "Reports"]
        let expectedIdentifiers = ["v23.tab.today", "v23.tab.work", "s1.tab.signs", "s1.tab.reports"]
        for (root, title) in zip(AppRootV1.frozenOrder, expectedTitles) {
            try state.select(root)
            let bound = expectation(description: "Actual native shell restores \(title)")
            var observedTabBar: UITabBar?
            var shell = AppShellView(packLoadResult: .available(.illuminatedSignV1),
                storeSession: fixture.coordinator,
                contentAccess: try XCTUnwrap(fixture.presentation.renderAccess),
                sceneNavigationAccess: sceneAccess,
                myDayAccess: try XCTUnwrap(fixture.presentation.myDayAccess),
                diagnosticsStore: fixture.diagnostics,
                metricKitDiagnosticsAdapter: MetricKitDiagnosticsAdapter(manager: nil),
                feedbackConfiguration: .production,
                mailComposerAdapter: .unavailable,
                entitlementProcessor: fixture.router.entitlementProcessor)
            shell.onNativeTabsBoundForTesting = { tabBar in
                guard observedTabBar == nil, tabBar.selectedItem?.title == title else { return }
                observedTabBar = tabBar
                bound.fulfill()
            }
            let host = UIHostingController(rootView: shell.modelContext(fixture.coordinator.modelContext))
            let window = UIWindow(windowScene: windowScene)
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
                previousKeyWindow?.makeKeyAndVisible()
            }
            host.view.layoutIfNeeded()
            await fulfillment(of: [bound], timeout: 20)
            let tabBar = try XCTUnwrap(observedTabBar)
            XCTAssertEqual(tabBar.items?.map(\.title), expectedTitles.map(Optional.some))
            XCTAssertEqual(tabBar.items?.map(\.accessibilityIdentifier),
                expectedIdentifiers.map(Optional.some))
            XCTAssertEqual(tabBar.selectedItem?.title, title)
            let restored = AppShellSceneStateV1(workspaceID: fixture.coordinator.workspaceID,
                access: sceneAccess, registry: try RouteRegistryV1())
            try restored.restore()
            XCTAssertEqual(restored.snapshot?.selectedRoot, root)
            XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), before)
            XCTAssertFalse(fixture.coordinator.modelContext.hasChanges)
        }
        #else
        throw XCTSkip("Native tab observation is DEBUG-only")
        #endif
    }

    @MainActor
    func testAllRootsShareActualMyDayReadWithQuantizedClockAndNoCanonicalEffects() async throws {
        let fixture = try await makeFixture("four-roots")
        defer { fixture.cleanUp() }
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let scene = AppShellSceneStateV1(workspaceID: fixture.coordinator.workspaceID,
            access: try XCTUnwrap(fixture.presentation.sceneNavigationAccess),
            registry: try RouteRegistryV1())
        let clock = V23ShellReadClock(Date(timeIntervalSince1970: 1_800_300_000.1234))
        let source = ProductionMyDaySourceStateV1(workspaceID: fixture.coordinator.workspaceID,
            access: access, clock: clock)
        let before = try fixture.coordinator.workspaceWriter.currentRevision()
        try scene.restore()
        for root in AppRootV1.frozenOrder {
            try scene.select(root)
            await source.refresh()
            let snapshot = try XCTUnwrap(source.snapshot)
            XCTAssertEqual(scene.snapshot?.selectedRoot, root)
            XCTAssertEqual(snapshot.workspaceID, fixture.coordinator.workspaceID)
            XCTAssertEqual(snapshot.evaluatedAt,
                Date(timeIntervalSince1970: 1_800_300_000.123))
            XCTAssertFalse(source.isLoading)
            XCTAssertFalse(source.couldNotLoad)
        }
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), before)
        XCTAssertEqual(try fixture.coordinator.modelContext.fetchCount(
            FetchDescriptor<MyDayPlanRowV1>()), 0)
        XCTAssertEqual(try fixture.coordinator.modelContext.fetchCount(
            FetchDescriptor<MyDayCarryoverReceiptRowV1>()), 0)
        XCTAssertFalse(fixture.coordinator.modelContext.hasChanges)
    }

    @MainActor
    func testActualStartupRestoresReadyReportIntoExistingDetailAndBackPersistsThroughScenePort() async throws {
        #if DEBUG
        let fixture = try await makeFixture("reports-detail-route")
        defer { fixture.cleanUp() }
        let report = try await makeReadyReport(in: fixture)
        let revision = try fixture.coordinator.workspaceWriter.currentRevision()
        let reportIdentity = try WorkspaceEntityIdentityV1(kind: .report, id: report.reportID)
        let reportRevision = try XCTUnwrap(
            revision.entityRevisions.first { $0.identity == reportIdentity }
        ).revision
        let target = try NavigationTargetV1(
            workspaceID: fixture.coordinator.workspaceID,
            destination: .reports,
            stableEntityID: report.reportID,
            requestedMode: .read,
            expectedRevision: reportRevision,
            fallback: try NavigationFallbackV1(root: .reports, destination: .reports)
        )
        let sceneAccess = try XCTUnwrap(fixture.presentation.sceneNavigationAccess)
        let scene = AppShellSceneStateV1(workspaceID: fixture.coordinator.workspaceID,
            access: sceneAccess, registry: try RouteRegistryV1())
        try scene.restore()
        let beforeRoute = try fixture.coordinator.workspaceWriter.currentRevision()
        let missing = try NavigationTargetV1(
            workspaceID: fixture.coordinator.workspaceID,
            destination: .reports,
            stableEntityID: UUID(),
            requestedMode: .read,
            fallback: try NavigationFallbackV1(root: .reports, destination: .reports)
        )
        let stale = try NavigationTargetV1(
            workspaceID: fixture.coordinator.workspaceID,
            destination: .reports,
            stableEntityID: report.reportID,
            requestedMode: .read,
            expectedRevision: reportRevision + 1,
            fallback: try NavigationFallbackV1(root: .reports, destination: .reports)
        )
        let wrongFamily = try NavigationTargetV1(
            workspaceID: fixture.coordinator.workspaceID,
            destination: .reports,
            stableEntityID: report.assetID,
            requestedMode: .read,
            fallback: try NavigationFallbackV1(root: .reports, destination: .reports)
        )
        let foreign = try NavigationTargetV1(
            workspaceID: WorkspaceID(),
            destination: .reports,
            stableEntityID: report.reportID,
            requestedMode: .read,
            fallback: try NavigationFallbackV1(root: .reports, destination: .reports)
        )
        for (candidate, reason) in [
            (missing, RouteFallbackReasonV1.deletedOrTombstoned),
            (stale, .staleRevision),
            (wrongFamily, .invalidTarget),
            (foreign, .wrongWorkspace),
        ] {
            try scene.open(candidate)
            XCTAssertEqual(scene.lastRestoration?.receipt.result.reason, reason)
            XCTAssertEqual(scene.lastRestoration?.receipt.canonicalMutationCount, 0)
            XCTAssertFalse(scene.lastRestoration?.receipt.startsAutomaticWork ?? true)
            XCTAssertEqual(scene.snapshot?.path(for: .reports)?.targets, [])
            XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), beforeRoute)
            XCTAssertFalse(fixture.coordinator.modelContext.hasChanges)
        }
        try scene.open(target)
        XCTAssertEqual(scene.snapshot?.selectedRoot, .reports)
        XCTAssertEqual(scene.snapshot?.path(for: .reports)?.targets, [target])
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), beforeRoute)
        XCTAssertFalse(fixture.coordinator.modelContext.hasChanges)

        let windowScene = try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = windowScene.windows.first { $0.isKeyWindow }
        let shell = AppShellView(packLoadResult: .available(.illuminatedSignV1),
            storeSession: fixture.coordinator,
            contentAccess: try XCTUnwrap(fixture.presentation.renderAccess),
            sceneNavigationAccess: sceneAccess,
            myDayAccess: try XCTUnwrap(fixture.presentation.myDayAccess),
            diagnosticsStore: fixture.diagnostics,
            metricKitDiagnosticsAdapter: MetricKitDiagnosticsAdapter(manager: nil),
            feedbackConfiguration: .production,
            mailComposerAdapter: .unavailable,
            entitlementProcessor: fixture.router.entitlementProcessor)
        let host = UIHostingController(rootView: shell.modelContext(fixture.coordinator.modelContext))
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKeyAndVisible()
        }
        host.view.layoutIfNeeded()
        let detailVisible = await Task { @MainActor in
            for _ in 0..<200 {
                if self.containsAccessibilityIdentifier(
                    identifiedBy: ReportDetailView.screenAccessibilityIdentifier,
                    in: host.view
                ) {
                    return true
                }
                try? await Task.sleep(nanoseconds: 25_000_000)
            }
            return false
        }.value
        XCTAssertTrue(detailVisible, "Actual Reports startup must render ready detail")

        let navigation = try XCTUnwrap(
            navigationControllerPresentingDetail(from: host)
        )
        navigation.popToRootViewController(animated: false)
        let persistedBackPath = await Task { @MainActor in
            for _ in 0..<200 {
                if let loaded = try? sceneAccess.load(),
                   case let .restored(snapshot) = loaded,
                   snapshot.path(for: .reports)?.targets == [] {
                    return true
                }
                try? await Task.sleep(nanoseconds: 25_000_000)
            }
            return false
        }.value
        XCTAssertTrue(persistedBackPath, "Shell back navigation must clear the saved Reports path")
        XCTAssertFalse(containsAccessibilityIdentifier(
            identifiedBy: ReportDetailView.screenAccessibilityIdentifier,
            in: host.view
        ))
        let reopened = AppShellSceneStateV1(workspaceID: fixture.coordinator.workspaceID,
            access: sceneAccess, registry: try RouteRegistryV1())
        try reopened.restore()
        XCTAssertEqual(reopened.snapshot?.selectedRoot, .reports)
        XCTAssertEqual(reopened.snapshot?.path(for: .reports)?.targets, [])
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), beforeRoute)
        XCTAssertFalse(fixture.coordinator.modelContext.hasChanges)
        #else
        throw XCTSkip("Native report-detail observation is DEBUG-only")
        #endif
    }

    @MainActor
    func testTransientReportComparisonSuffixCannotReattachAfterValidatedCanonicalPathChanges() async throws {
        let fixture = try await makeFixture("reports-transient-anchor")
        defer { fixture.cleanUp() }
        let first = try await makeReadyReport(in: fixture, label: "first")
        let second = try await makeReadyReport(in: fixture, label: "second")
        let firstTarget = try validatedReportTarget(first, in: fixture)
        let secondTarget = try validatedReportTarget(second, in: fixture)
        let scene = AppShellSceneStateV1(workspaceID: fixture.coordinator.workspaceID,
            access: try XCTUnwrap(fixture.presentation.sceneNavigationAccess),
            registry: try RouteRegistryV1())
        try scene.restore()
        try scene.open(firstTarget)
        var presentation = ReportsNavigationPresentationV1()
        let comparisonID = UUID()
        let descendantReportID = UUID()
        let initialRoutes: [ReportHistoryRoute] = [
            .report(first.reportID),
            .comparison(comparisonID),
            .report(descendantReportID),
        ]
        let original = presentation.setPresentedRoutes(
            initialRoutes,
            snapshotID: scene.snapshot?.snapshotID
        )
        XCTAssertEqual(original, [.report(first.reportID)])
        XCTAssertEqual(
            presentation.presentedRoutes(
                for: reportRoutes(in: scene),
                snapshotID: scene.snapshot?.snapshotID
            ),
            initialRoutes,
            "comparison descendants remain transient only while their canonical prefix is current"
        )
        let beforeSelectRoutes = reportRoutes(in: scene)
        let beforeSelectSnapshotID = scene.snapshot?.snapshotID
        try scene.select(.today)
        presentation.refreshCanonicalSnapshot(
            from: beforeSelectRoutes,
            snapshotIDBefore: beforeSelectSnapshotID,
            to: reportRoutes(in: scene),
            snapshotIDAfter: scene.snapshot?.snapshotID
        )
        XCTAssertEqual(
            presentation.presentedRoutes(
                for: reportRoutes(in: scene),
                snapshotID: scene.snapshot?.snapshotID
            ),
            initialRoutes,
            "A root selection with the same Reports path keeps its in-memory comparison suffix"
        )
        let beforeRestoreRoutes = reportRoutes(in: scene)
        let beforeRestoreSnapshotID = scene.snapshot?.snapshotID
        try scene.restore()
        presentation.refreshCanonicalSnapshot(
            from: beforeRestoreRoutes,
            snapshotIDBefore: beforeRestoreSnapshotID,
            to: reportRoutes(in: scene),
            snapshotIDAfter: scene.snapshot?.snapshotID
        )
        XCTAssertEqual(
            presentation.presentedRoutes(
                for: reportRoutes(in: scene),
                snapshotID: scene.snapshot?.snapshotID
            ),
            initialRoutes,
            "Restoring the same persisted Reports path keeps its in-memory comparison suffix"
        )

        // Do not reconcile between these writes: the final canonical route starts with the
        // original report again, but its snapshot is a different persisted state.
        let anchoredSnapshotID = scene.snapshot?.snapshotID
        try scene.open(secondTarget)
        try scene.open(firstTarget)
        let changedCanonicalRoutes = reportRoutes(in: scene)
        XCTAssertEqual(changedCanonicalRoutes, [.report(first.reportID)])
        XCTAssertNotEqual(scene.snapshot?.snapshotID, anchoredSnapshotID)
        let beforeChangedSelectSnapshotID = scene.snapshot?.snapshotID
        try scene.select(.reports)
        presentation.refreshCanonicalSnapshot(
            from: changedCanonicalRoutes,
            snapshotIDBefore: beforeChangedSelectSnapshotID,
            to: reportRoutes(in: scene),
            snapshotIDAfter: scene.snapshot?.snapshotID
        )
        XCTAssertEqual(
            presentation.presentedRoutes(
                for: reportRoutes(in: scene),
                snapshotID: scene.snapshot?.snapshotID
            ),
            reportRoutes(in: scene),
            "A coalesced A-to-B-to-A canonical change cannot reattach the stale comparison suffix"
        )
        let beforeChangedRestoreRoutes = reportRoutes(in: scene)
        let beforeChangedRestoreSnapshotID = scene.snapshot?.snapshotID
        try scene.restore()
        presentation.refreshCanonicalSnapshot(
            from: beforeChangedRestoreRoutes,
            snapshotIDBefore: beforeChangedRestoreSnapshotID,
            to: reportRoutes(in: scene),
            snapshotIDAfter: scene.snapshot?.snapshotID
        )
        XCTAssertEqual(
            presentation.presentedRoutes(
                for: reportRoutes(in: scene),
                snapshotID: scene.snapshot?.snapshotID
            ),
            reportRoutes(in: scene),
            "Restoring after the coalesced change cannot recover the stale comparison suffix"
        )
    }

    @MainActor
    func testCoverAfterCompletedAccessReadDeniesFinalStatePublication() async throws {
        #if DEBUG
        let fixture = try await makeFixture("final-cover")
        defer { fixture.cleanUp() }
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let source = ProductionMyDaySourceStateV1(workspaceID: fixture.coordinator.workspaceID,
            access: access)
        var reachedFinalBoundary = false
        source.afterSnapshotReadyForTesting = {
            reachedFinalBoundary = true
            fixture.presentation.receive(.sceneInactive)
        }
        await source.refresh()
        XCTAssertTrue(reachedFinalBoundary)
        XCTAssertNil(source.snapshot)
        XCTAssertFalse(source.isLoading)
        XCTAssertTrue(source.couldNotLoad)
        XCTAssertThrowsError(try access.withCurrentPresentation {}) {
            XCTAssertEqual($0 as? AppAccessContractFailureV1, .accessDenied)
        }
        #else
        throw XCTSkip("Publication fault injection is DEBUG-only")
        #endif
    }

    @MainActor
    func testStateChangeObserverCanCoverBeforePublicationWithoutReenteringTokenLock() async throws {
        let fixture = try await makeFixture("observer-cover")
        defer { fixture.cleanUp() }
        let source = ProductionMyDaySourceStateV1(workspaceID: fixture.coordinator.workspaceID,
            access: try XCTUnwrap(fixture.presentation.myDayAccess))
        var covered = false
        let observation = source.objectWillChange.sink {
            if source.isLoading && !covered {
                covered = true
                fixture.presentation.receive(.sceneInactive)
            }
        }
        await source.refresh()
        observation.cancel()
        XCTAssertTrue(covered)
        XCTAssertNil(source.snapshot)
        XCTAssertFalse(source.isLoading)
        XCTAssertTrue(source.couldNotLoad)
    }

    @MainActor
    func testDiscardDuringCompletedReadPreventsSuccessOrErrorFromReappearing() async throws {
        #if DEBUG
        let fixture = try await makeFixture("discard")
        defer { fixture.cleanUp() }
        let source = ProductionMyDaySourceStateV1(workspaceID: fixture.coordinator.workspaceID,
            access: try XCTUnwrap(fixture.presentation.myDayAccess))
        for shouldThrow in [false, true] {
            source.afterSnapshotReadyForTesting = {
                source.discard()
                if shouldThrow { throw CancellationError() }
            }
            await source.refresh()
            XCTAssertNil(source.snapshot)
            XCTAssertFalse(source.isLoading)
            XCTAssertFalse(source.couldNotLoad)
        }
        source.afterSnapshotReadyForTesting = nil
        #else
        throw XCTSkip("Publication fault injection is DEBUG-only")
        #endif
    }

    @MainActor
    func testOlderCompletedReadCannotReplaceNewerSuccessWithValueOrFailure() async throws {
        #if DEBUG
        let fixture = try await makeFixture("overlap")
        defer { fixture.cleanUp() }
        let clock = V23ShellReadClock(Date(timeIntervalSince1970: 1_800_300_100))
        let source = ProductionMyDaySourceStateV1(workspaceID: fixture.coordinator.workspaceID,
            access: try XCTUnwrap(fixture.presentation.myDayAccess), clock: clock)
        for shouldThrow in [false, true] {
            let parked = expectation(description: "Older real snapshot reached final boundary")
            let gate = V23ShellReadGate()
            clock.set(Date(timeIntervalSince1970: 1_800_300_100))
            source.afterSnapshotReadyForTesting = {
                source.afterSnapshotReadyForTesting = nil
                parked.fulfill()
                await gate.wait()
                if shouldThrow { throw CancellationError() }
            }
            let older = Task { await source.refresh() }
            await fulfillment(of: [parked], timeout: 10)
            guard gate.isWaiting else {
                gate.release()
                older.cancel()
                await older.value
                return XCTFail("The original production read never reached its final boundary")
            }
            clock.set(Date(timeIntervalSince1970: 1_800_300_200))
            await source.refresh()
            XCTAssertEqual(source.snapshot?.evaluatedAt,
                Date(timeIntervalSince1970: 1_800_300_200))
            gate.release()
            await older.value
            XCTAssertEqual(source.snapshot?.evaluatedAt,
                Date(timeIntervalSince1970: 1_800_300_200))
            XCTAssertFalse(source.isLoading)
            XCTAssertFalse(source.couldNotLoad)
        }
        #else
        throw XCTSkip("Publication fault injection is DEBUG-only")
        #endif
    }

    @MainActor
    func testWrongWorkspaceAndCancelledReadNeverPublishSourceValues() async throws {
        let fixture = try await makeFixture("denied")
        defer { fixture.cleanUp() }
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let foreign = ProductionMyDaySourceStateV1(workspaceID: WorkspaceID(), access: access)
        await foreign.refresh()
        XCTAssertNil(foreign.snapshot)
        XCTAssertTrue(foreign.couldNotLoad)
        XCTAssertFalse(foreign.isLoading)
        #if DEBUG
        let source = ProductionMyDaySourceStateV1(workspaceID: fixture.coordinator.workspaceID,
            access: access)
        let parked = expectation(description: "Real read completed before cancellation")
        let gate = V23ShellReadGate()
        source.afterSnapshotReadyForTesting = {
            parked.fulfill()
            await gate.wait()
        }
        let read = Task { await source.refresh() }
        await fulfillment(of: [parked], timeout: 10)
        read.cancel()
        gate.release()
        await read.value
        source.afterSnapshotReadyForTesting = nil
        XCTAssertNil(source.snapshot)
        XCTAssertTrue(source.couldNotLoad)
        XCTAssertFalse(source.isLoading)
        #endif
    }

    @MainActor
    private func makeFixture(_ name: String) async throws -> V23ProductionMyDayPresentationHarness {
        try await V23ProductionMyDayPresentationHarness.start(testCase: self, name: name)
    }

    @MainActor
    private func makeReadyReport(
        in fixture: V23ProductionMyDayPresentationHarness,
        label: String = "ready"
    ) async throws -> (reportID: UUID, assetID: UUID) {
        let access = try XCTUnwrap(fixture.presentation.renderAccess)
        let workflow = try access.withRead {
            let profiles = try WorkspacePackageLifecycleCompatibilityV1
                .legacyV3Registry(package: .illuminatedSignV1)
            let root = try ProductionCompositionRoot(
                storeSession: fixture.coordinator,
                diagnosticsStore: fixture.diagnostics,
                profileRegistry: profiles
            )
            return try root.makeSignWorkflow(
                signPack: .illuminatedSignV1,
                accessState: { .entitled }
            )
        }
        let sign = try await workflow.firstSign.create(.init(
            siteLabel: "Reports route site \(label)",
            signLabel: "Reports route sign \(label)",
            timeZoneID: "America/New_York",
            isTimeZoneConfirmed: true
        ))
        _ = try workflow.checkRunner.beginCheck(
            assetID: sign.assetID,
            timeZoneID: "America/New_York",
            isTimeZoneConfirmed: true,
            afterDarkAccepted: true,
            safePositionAccepted: true,
            observedAt: Date(timeIntervalSince1970: 1_800_500_000)
        )
        let result = try await workflow.checkRunner.finalize(
            assetID: sign.assetID,
            selection: .couldNotVerify(
                reasonKey: "required_view_obstructed",
                note: nil
            ),
            completedAt: Date(timeIntervalSince1970: 1_800_500_010),
            snapshotCreatedAt: Date(timeIntervalSince1970: 1_800_500_011),
            sourceApp: SourceAppSnapshotV1(build: "v23-reports-route", version: "1")
        )
        guard case .ready = try workflow.checkRunner.prepareReportDelivery(result: result)
        else { throw AppAccessContractFailureV1.configurationUnknown }
        return (result.reportID, sign.assetID)
    }

    @MainActor
    private func validatedReportTarget(
        _ report: (reportID: UUID, assetID: UUID),
        in fixture: V23ProductionMyDayPresentationHarness
    ) throws -> NavigationTargetV1 {
        let revision = try fixture.coordinator.workspaceWriter.currentRevision()
        let identity = try WorkspaceEntityIdentityV1(kind: .report, id: report.reportID)
        let reportRevision = try XCTUnwrap(
            revision.entityRevisions.first { $0.identity == identity }
        ).revision
        return try NavigationTargetV1(
            workspaceID: fixture.coordinator.workspaceID,
            destination: .reports,
            stableEntityID: report.reportID,
            requestedMode: .read,
            expectedRevision: reportRevision,
            fallback: try NavigationFallbackV1(root: .reports, destination: .reports)
        )
    }

    @MainActor
    private func reportRoutes(in scene: AppShellSceneStateV1) -> [ReportHistoryRoute] {
        scene.snapshot?.path(for: .reports)?.targets.compactMap { target in
            guard target.destination == .reports,
                  target.requestedMode == .read,
                  let reportID = target.stableEntityID else { return nil }
            return .report(reportID)
        } ?? []
    }

    @MainActor
    private func containsAccessibilityIdentifier(
        identifiedBy identifier: String,
        in view: UIView
    ) -> Bool {
        if view.accessibilityIdentifier == identifier { return true }
        for case let element as UIAccessibilityIdentification in view.accessibilityElements ?? [] {
            if element.accessibilityIdentifier == identifier { return true }
        }
        for child in view.subviews {
            if containsAccessibilityIdentifier(identifiedBy: identifier, in: child) { return true }
        }
        return false
    }

    @MainActor
    private func navigationControllerPresentingDetail(
        from controller: UIViewController
    ) -> UINavigationController? {
        if let navigation = controller as? UINavigationController,
           navigation.viewControllers.contains(where: {
               containsAccessibilityIdentifier(
                   identifiedBy: ReportDetailView.screenAccessibilityIdentifier,
                   in: $0.view
               )
           }) {
            return navigation
        }
        for child in controller.children {
            if let navigation = navigationControllerPresentingDetail(from: child) {
                return navigation
            }
        }
        return nil
    }
}

private final class V23ShellReadClock: ApplicationClock, @unchecked Sendable {
    private let lock = NSLock()
    private var instant: Date
    init(_ instant: Date) { self.instant = instant }
    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return instant
    }
    func set(_ instant: Date) {
        lock.lock()
        defer { lock.unlock() }
        self.instant = instant
    }
}

@MainActor
private final class V23ShellReadGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    var isWaiting: Bool { continuation != nil }
    func wait() async {
        guard !released else { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}

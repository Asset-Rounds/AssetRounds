import Combine
import Foundation
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import FieldEvidenceApp

#if DEBUG
/// One hosted production `AppShellView` in its own key window.
@MainActor
final class SIG1MountedShellV1 {
    let window: UIWindow
    let host: UIHostingController<AnyView>
    private let previousKeyWindow: UIWindow?
    private var isMounted = true

    init(window: UIWindow, host: UIHostingController<AnyView>, previousKeyWindow: UIWindow?) {
        self.window = window
        self.host = host
        self.previousKeyWindow = previousKeyWindow
    }

    func unmount() {
        guard isMounted else { return }
        isMounted = false
        window.isHidden = true
        window.rootViewController = nil
        previousKeyWindow?.makeKeyAndVisible()
    }
}

extension V23ProductionFourRootShellTestSupport {
    /// Hosts the real production shell over the given published authority.
    /// The observer only records the composed scene; it cannot supply state.
    @MainActor
    func mountCompletedWorkShell(
        store: StoreSessionCoordinator,
        presentation: AppAccessPresentationV1,
        diagnostics: DiagnosticsStore,
        router: StartupRouter,
        onScene: @escaping @MainActor (AppShellSceneStateV1) -> Void
    ) throws -> SIG1MountedShellV1 {
        var shell = AppShellView(packLoadResult: .available(.illuminatedSignV1),
            storeSession: store,
            contentAccess: try XCTUnwrap(presentation.renderAccess),
            sceneNavigationAccess: try XCTUnwrap(presentation.sceneNavigationAccess),
            myDayAccess: try XCTUnwrap(presentation.myDayAccess),
            diagnosticsStore: diagnostics,
            metricKitDiagnosticsAdapter: MetricKitDiagnosticsAdapter(manager: nil),
            feedbackConfiguration: .production, mailComposerAdapter: .unavailable,
            entitlementProcessor: router.entitlementProcessor)
        shell.onProductionSceneBoundForTesting = onScene
        let windowScene = try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = windowScene.windows.first { $0.isKeyWindow }
        let host = UIHostingController(rootView: AnyView(shell.modelContext(store.modelContext)))
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        return SIG1MountedShellV1(window: window, host: host, previousKeyWindow: previousKeyWindow)
    }

    @MainActor
    func waitUntilCompletedWork(_ condition: @escaping @MainActor () -> Bool) async -> Bool {
        for _ in 0..<200 {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        return condition()
    }

    /// Persists Work as the selected root before the shell restores.
    @MainActor
    func selectWorkBeforeLaunch(
        _ fixture: V23ProductionMyDayPresentationHarness
    ) throws {
        let scene = AppShellSceneStateV1(workspaceID: fixture.coordinator.workspaceID,
            access: try XCTUnwrap(fixture.presentation.sceneNavigationAccess),
            registry: try RouteRegistryV1())
        try scene.restore()
        try scene.select(.work)
    }


    /// A SwiftUI accessibility identifier need not be exported as a UIView's
    /// accessibilityIdentifier. Observe the real mounted menu and its enabled
    /// action instead, then dismiss without invoking the action. Discovery,
    /// presentation and dismissal share the former 200 x 25 ms More wait budget.
    @MainActor
    private func waitForCompletedWorkMoreMenu(from host: UIViewController) async -> Bool {
        guard #available(iOS 17.4, *) else { return false }
        guard let root = host.viewIfLoaded, let window = root.window else { return false }
        var remainingWaits = 200
        @MainActor
        func nextSample() async -> Bool {
            guard remainingWaits > 0, !Task.isCancelled else { return false }
            remainingWaits -= 1
            do {
                try await Task.sleep(nanoseconds: 25_000_000)
                return !Task.isCancelled
            } catch {
                return false
            }
        }
        @MainActor
        func visiblyAttached(_ button: UIButton) -> Bool {
            guard button.window === window, button.isDescendant(of: root),
                  button.isEnabled, !button.bounds.isEmpty else { return false }
            var visible = button.convert(button.bounds, to: window)
            guard !visible.isNull, !visible.isInfinite, !visible.isEmpty else { return false }
            var ancestor: UIView? = button
            var seen = Set<ObjectIdentifier>()
            while let current = ancestor {
                guard seen.count < 64, seen.insert(ObjectIdentifier(current)).inserted,
                      (current === window || current.window === window),
                      !current.isHidden, current.alpha > 0,
                      current.isUserInteractionEnabled else { return false }
                if current.clipsToBounds || current === window {
                    visible = visible.intersection(current.convert(current.bounds, to: window))
                    guard !visible.isNull, !visible.isInfinite, !visible.isEmpty else { return false }
                }
                if current === window { return true }
                ancestor = current.superview
            }
            return false
        }
        @MainActor
        func findControls() -> (buttons: [UIButton], truncated: Bool) {
            var seenViews = Set<ObjectIdentifier>()
            var candidates: [UIButton] = []
            var truncated = false
            @MainActor
            func visit(_ view: UIView, depth: Int) {
                guard depth <= 32, seenViews.count < 256 else { truncated = true; return }
                guard seenViews.insert(ObjectIdentifier(view)).inserted else { return }
                if let button = view as? UIButton, button.menu != nil,
                   button.showsMenuAsPrimaryAction, visiblyAttached(button) {
                    candidates.append(button)
                }
                if view.subviews.count > 64 { truncated = true }
                for child in view.subviews.prefix(64) { visit(child, depth: depth + 1) }
            }
            visit(root, depth: 0)
            return (candidates, truncated)
        }
        var selected: UIButton?
        repeat {
            guard root.window === window,
                  nativeScreenObservation(
                    SignoffEnrollmentView.immutableDetailAccessibilityIdentifier, from: host).found else {
                print("CompletedWorkMoreMenu refused=detail-not-mounted")
                return false
            }
            let controls = findControls()
            guard !controls.truncated, controls.buttons.count <= 1 else {
                print("CompletedWorkMoreMenu refused=nonunique-or-truncated"
                    + " candidates=\(controls.buttons.count) truncated=\(controls.truncated)")
                return false
            }
            if let button = controls.buttons.first {
                selected = button
                break
            }
        } while await nextSample()
        guard let button = selected, !Task.isCancelled,
              button.isContextMenuInteractionEnabled,
              let interaction = button.contextMenuInteraction else {
            print("CompletedWorkMoreMenu refused=control-or-interaction-unavailable")
            return false
        }

        // Refuse an already visible menu so this observation proves a new
        // presentation by this control. Returning the menu invokes no item.
        var initiallyVisible = false
        interaction.updateVisibleMenu { menu in
            initiallyVisible = true
            return menu
        }
        guard !initiallyVisible else { return false }
        button.performPrimaryAction()
        var callbacks = 0
        var expectedActionVisible = false
        repeat {
            interaction.updateVisibleMenu { menu in
                callbacks += 1
                if menu.children.count == 1, let action = menu.children.first as? UIAction {
                    expectedActionVisible = action.title == SignoffEnrollmentManifestV1.actionTitle
                        && !action.attributes.contains(.disabled)
                        && !action.attributes.contains(.hidden)
                    print("CompletedWorkMoreMenu event=visible-action"
                        + " expectedTitle=\(action.title == SignoffEnrollmentManifestV1.actionTitle)"
                        + " attributes=\(action.attributes.rawValue)")
                } else {
                    expectedActionVisible = false
                    print("CompletedWorkMoreMenu refused=unexpected-menu-shape children=\(menu.children.count)")
                }
                return menu
            }
            if callbacks > 0 { break }
        } while await nextSample()

        // Always dismiss after activation, including an invalid or absent menu.
        // isHeld is not a visibility contract for primary-action menus. Require
        // two no-callback samples separated by a shared-budget yield instead;
        // the earlier positive callback binds them to this actual interaction.
        interaction.dismissMenu()
        var consecutiveAbsentSamples = 0
        var dismissed = false
        repeat {
            var stillVisible = false
            interaction.updateVisibleMenu { menu in
                stillVisible = true
                return menu
            }
            consecutiveAbsentSamples = stillVisible ? 0 : consecutiveAbsentSamples + 1
            if consecutiveAbsentSamples == 2 {
                dismissed = true
                break
            }
        } while await nextSample()
        let finalControls = findControls()
        let sameMountedControl = !finalControls.truncated && finalControls.buttons.count == 1
            && finalControls.buttons.first === button && root.window === window
            && nativeScreenObservation(
                SignoffEnrollmentView.immutableDetailAccessibilityIdentifier, from: host).found
        let observed = callbacks == 1 && expectedActionVisible && dismissed
            && sameMountedControl && !Task.isCancelled
        print("CompletedWorkMoreMenu event=observation-ended observed=\(observed)"
            + " callbacks=\(callbacks) expectedActionVisible=\(expectedActionVisible)"
            + " dismissed=\(dismissed) sameMountedControl=\(sameMountedControl)"
            + " waitsUsed=\(200 - remainingWaits)")
        return observed
    }

    /// Visible journey: Work root -> Completed work section -> immutable
    /// detail -> More -> Record approval response -> editor. Each step is
    /// observed on the mounted production host; the presentation calls are the
    /// exact actions the rows, menu item and editor buttons invoke.
    @MainActor
    func driveCompletedWorkToEditor(
        key: CompletedWorkSubjectKeyV1,
        host: UIViewController,
        presentation provider: @MainActor () -> CompletedWorkPresentationV1?
    ) async throws -> CompletedWorkPresentationV1 {
        let rootMounted = await waitForMountedScreen(
            ProductionWorkRootViewV1.screenAccessibilityIdentifier, from: host)
        XCTAssertTrue(rootMounted, "The Work root is visible")
        let sectionMounted = await waitForMountedScreen(
            SignoffEnrollmentView.workRootAccessibilityIdentifier, from: host)
        XCTAssertTrue(sectionMounted, "The Completed work section is visible on the Work root")
        let presentation = try XCTUnwrap(provider(), "The hosted shell composes its presentation")
        let listed = await waitUntilCompletedWork {
            if case let .loaded(items) = presentation.list {
                return items.contains { $0.key == key }
            }
            return false
        }
        XCTAssertTrue(listed, "The section lists the current-tip completed work")
        guard case let .loaded(items) = presentation.list,
              let item = items.first(where: { $0.key == key }) else {
            throw CompletedWorkResponseFailureV1.notFound
        }
        XCTAssertEqual(item.eligibility, .eligible)
        XCTAssertEqual(item.responseCount, 0)

        presentation.open(item)
        let detailMounted = await waitForMountedScreen(
            SignoffEnrollmentView.immutableDetailAccessibilityIdentifier, from: host)
        XCTAssertTrue(detailMounted, "The immutable detail is pushed inside the Work stack")
        let moreVisible = await waitForCompletedWorkMoreMenu(from: host)
        XCTAssertTrue(moreVisible, "The detail offers More")
        if !moreVisible {
            if case let .loaded(detail) = presentation.detail {
                print("CompletedWorkMoreObservation phase=OBSERVATION_FAILED state=loaded"
                    + " keyMatchesExpected=\(detail.key == key)"
                    + " eligible=\(detail.eligibility == .eligible) proofPresent=\(detail.proof != nil)")
            } else {
                print("CompletedWorkMoreObservation phase=OBSERVATION_FAILED state=notLoaded"
                    + " keyMatchesExpected=UNKNOWN eligible=UNKNOWN proofPresent=UNKNOWN")
            }
        }
        guard case let .loaded(detail) = presentation.detail else {
            throw CompletedWorkResponseFailureV1.unavailable
        }
        XCTAssertEqual(detail.key, key)
        XCTAssertEqual(detail.eligibility, .eligible)
        XCTAssertNotNil(detail.proof)

        presentation.requestRecord()
        let editorMounted = await waitForMountedScreen(
            SignoffEnrollmentView.screenAccessibilityIdentifier, from: host)
        XCTAssertTrue(editorMounted, "Record approval response opens the existing editor")
        XCTAssertNotNil(presentation.editorRoute)
        return presentation
    }
}
#endif

final class V23ProductionSignoffResponseJourneyTests: V23ProductionFourRootShellTestSupport {
    @MainActor
    func testWorkRootCompletedDetailMoreRecordOpensFocusedHistory() async throws {
        #if DEBUG
        let fixture = try await makeFixture("sig1-journey-record")
        defer { fixture.cleanUp() }
        let report = try await makeReadyReport(in: fixture, label: "sig1-journey")
        let key = try completedWorkKey(report.reportID, revision: 1, in: fixture)
        let sceneAccess = try XCTUnwrap(fixture.presentation.sceneNavigationAccess)
        try selectWorkBeforeLaunch(fixture)

        var captured: CompletedWorkPresentationV1?
        CompletedWorkPresentationV1.didCreateForTesting = { value in
            if captured == nil { captured = value }
        }
        defer { CompletedWorkPresentationV1.didCreateForTesting = nil }
        var shellScene: AppShellSceneStateV1?
        let mounted = try mountCompletedWorkShell(store: fixture.coordinator,
            presentation: fixture.presentation, diagnostics: fixture.diagnostics,
            router: fixture.router) { scene in
            if shellScene == nil { shellScene = scene }
        }
        defer { mounted.unmount() }
        let host = mounted.host
        let presentation = try await driveCompletedWorkToEditor(key: key, host: host) { captured }
        // Measured once the editor is open, so only the Record action counts.
        let revisionBefore = try fixture.coordinator.workspaceWriter.currentRevision()

        let route = try XCTUnwrap(presentation.editorRoute)
        XCTAssertEqual(route.metadata.subject.versionText, "Version 1")
        XCTAssertFalse(route.resumesRetainedAttempt)
        let submission = SignoffEnrollmentSubmissionV1(route: route.metadata,
            typedName: "Jordan Hosted", claimedRole: "Facilities lead",
            claimedRelationship: .client)
        XCTAssertEqual(presentation.submit(submission), .saved)
        XCTAssertEqual(presentation.lastResult, .saved)
        XCTAssertNil(presentation.editorRoute)
        XCTAssertNil(presentation.detailRoute)

        let signoffs = try fixture.coordinator.modelContext
            .fetch(FetchDescriptor<SignoffSnapshotRow>()).map { try $0.value() }
        XCTAssertEqual(signoffs.count, 1)
        let signoff = try XCTUnwrap(signoffs.first)
        XCTAssertEqual(signoff.subjectID, report.reportID)
        XCTAssertEqual(signoff.subjectRevision, 1)
        XCTAssertEqual(signoff.roleAssertion?.actor.responsibility, .acknowledgedBy)
        let historyTarget = try SignoffHistoryRouteV1(
            workspaceID: fixture.coordinator.workspaceID, signoffID: signoff.snapshotID
        ).reportsTarget
        let scene = try XCTUnwrap(shellScene)
        XCTAssertEqual(scene.snapshot?.selectedRoot, .reports)
        XCTAssertEqual(scene.snapshot?.path(for: .reports)?.targets, [historyTarget])
        XCTAssertEqual(scene.snapshot?.path(for: .work)?.targets, [],
            "The detail and editor are local pushes, never saved routes")
        let historyMounted = await waitForMountedScreen(
            SignoffEnrollmentView.historyAccessibilityIdentifier, from: host)
        XCTAssertTrue(historyMounted, "The focused history lands on Reports")
        let persisted = await waitUntilCompletedWork {
            guard let loaded = try? sceneAccess.load(),
                  case let .restored(snapshot) = loaded else { return false }
            return snapshot.selectedRoot == .reports
                && snapshot.path(for: .reports)?.targets == [historyTarget]
        }
        XCTAssertTrue(persisted, "The history route is the saved Reports route")
        XCTAssertFalse(containsAccessibilityIdentifier(
            identifiedBy: SignoffEnrollmentView.confirmAccessibilityIdentifier, in: host.view))

        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision().revision,
            revisionBefore.revision + 2)
        let workflow = try makeCompletedWorkWorkflow(in: fixture)
        let history = try workflow.completedWorkResponses.history(focusedSignoffID: signoff.snapshotID)
        XCTAssertEqual(history.current.count, 1)
        XCTAssertEqual(history.current.first?.facts?.typedName, "Jordan Hosted")
        XCTAssertEqual(history.current.first?.facts?.claimedRole, "Facilities lead")
        XCTAssertEqual(history.subject?.versionText, "Version 1")
        XCTAssertFalse(fixture.coordinator.modelContext.hasChanges)
        #else
        throw XCTSkip("Native hosted journey observation is DEBUG-only")
        #endif
    }

    @MainActor
    func testCancelFromEditorReturnsToDetailWithNoEffect() async throws {
        #if DEBUG
        let fixture = try await makeFixture("sig1-journey-cancel")
        defer { fixture.cleanUp() }
        let report = try await makeReadyReport(in: fixture, label: "sig1-cancel")
        let key = try completedWorkKey(report.reportID, revision: 1, in: fixture)
        try selectWorkBeforeLaunch(fixture)
        var captured: CompletedWorkPresentationV1?
        CompletedWorkPresentationV1.didCreateForTesting = { value in
            if captured == nil { captured = value }
        }
        defer { CompletedWorkPresentationV1.didCreateForTesting = nil }
        var shellScene: AppShellSceneStateV1?
        let mounted = try mountCompletedWorkShell(store: fixture.coordinator,
            presentation: fixture.presentation, diagnostics: fixture.diagnostics,
            router: fixture.router) { scene in
            if shellScene == nil { shellScene = scene }
        }
        defer { mounted.unmount() }
        let host = mounted.host
        let presentation = try await driveCompletedWorkToEditor(key: key, host: host) { captured }
        let revisionBefore = try fixture.coordinator.workspaceWriter.currentRevision()
        let actorsBefore = try completedWorkRowCount(ActorSnapshotRow.self,
            in: fixture.coordinator.modelContext)

        presentation.cancelEditor()
        XCTAssertNil(presentation.editorRoute)
        XCTAssertEqual(presentation.detailRoute, key)
        let returned = await waitUntilCompletedWork {
            !self.nativeScreenObservation(SignoffEnrollmentView.screenAccessibilityIdentifier, from: host).found
                && self.nativeScreenObservation(
                    SignoffEnrollmentView.immutableDetailAccessibilityIdentifier, from: host).found
        }
        XCTAssertTrue(returned, "Cancel returns to the completed-work detail")
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), revisionBefore)
        XCTAssertEqual(try completedWorkRowCount(SignoffSnapshotRow.self,
            in: fixture.coordinator.modelContext), 0)
        XCTAssertEqual(try completedWorkRowCount(ActorSnapshotRow.self,
            in: fixture.coordinator.modelContext), actorsBefore)
        XCTAssertEqual(shellScene?.snapshot?.selectedRoot, .work)
        XCTAssertEqual(shellScene?.snapshot?.path(for: .work)?.targets, [])
        XCTAssertFalse(fixture.coordinator.modelContext.hasChanges)
        #else
        throw XCTSkip("Native hosted journey observation is DEBUG-only")
        #endif
    }

    @MainActor
    func testStaleRevisionShowsBlockedRecordAndPreservesTypedFields() async throws {
        #if DEBUG
        let fixture = try await makeFixture("sig1-journey-stale")
        defer { fixture.cleanUp() }
        let report = try await makeReadyReport(in: fixture, label: "sig1-stale")
        let key = try completedWorkKey(report.reportID, revision: 1, in: fixture)
        try selectWorkBeforeLaunch(fixture)
        var captured: CompletedWorkPresentationV1?
        CompletedWorkPresentationV1.didCreateForTesting = { value in
            if captured == nil { captured = value }
        }
        defer { CompletedWorkPresentationV1.didCreateForTesting = nil }
        let mounted = try mountCompletedWorkShell(store: fixture.coordinator,
            presentation: fixture.presentation, diagnostics: fixture.diagnostics,
            router: fixture.router) { _ in }
        defer { mounted.unmount() }
        let host = mounted.host
        let presentation = try await driveCompletedWorkToEditor(key: key, host: host) { captured }
        let route = try XCTUnwrap(presentation.editorRoute)

        // A correction appears after the editor opened.
        let workflow = try makeCompletedWorkWorkflow(in: fixture)
        _ = try await correctCompletedReport(report.reportID, workflow: workflow,
            note: "Correction while the editor is open")
        let afterCorrection = try fixture.coordinator.workspaceWriter.currentRevision()
        let actorsBefore = try completedWorkRowCount(ActorSnapshotRow.self,
            in: fixture.coordinator.modelContext)

        let submission = SignoffEnrollmentSubmissionV1(route: route.metadata,
            typedName: "Kept Name", claimedRole: "Kept Role", claimedRelationship: .owner)
        XCTAssertEqual(presentation.submit(submission), .stale)
        XCTAssertEqual(presentation.lastResult, .stale)
        XCTAssertEqual(presentation.editorRoute, route, "Record is blocked in place")
        XCTAssertEqual(presentation.draft, CompletedWorkResponseDraftV1(
            typedName: "Kept Name", claimedRole: "Kept Role", claimedRelationship: .owner))
        XCTAssertNil(presentation.retainedOperation(for: key))
        guard case let .loaded(reloaded) = presentation.detail else {
            return XCTFail("A stale result reloads the detail")
        }
        XCTAssertEqual(reloaded.eligibility, .superseded, "Record is no longer offered on the detail")
        XCTAssertTrue(nativeScreenObservation(
            SignoffEnrollmentView.screenAccessibilityIdentifier, from: host).found)
        XCTAssertEqual(presentation.submit(submission), .stale)
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), afterCorrection)
        XCTAssertEqual(try completedWorkRowCount(SignoffSnapshotRow.self,
            in: fixture.coordinator.modelContext), 0)
        XCTAssertEqual(try completedWorkRowCount(ActorSnapshotRow.self,
            in: fixture.coordinator.modelContext), actorsBefore)
        XCTAssertFalse(fixture.coordinator.modelContext.hasChanges)
        #else
        throw XCTSkip("Native hosted journey observation is DEBUG-only")
        #endif
    }

    @MainActor
    func testRevokedContentAccessDeniesRecordWithNoEffect() async throws {
        #if DEBUG
        let fixture = try await makeFixture("sig1-journey-revoked")
        defer { fixture.cleanUp() }
        let report = try await makeReadyReport(in: fixture, label: "sig1-revoked")
        let key = try completedWorkKey(report.reportID, revision: 1, in: fixture)
        try selectWorkBeforeLaunch(fixture)
        var captured: CompletedWorkPresentationV1?
        CompletedWorkPresentationV1.didCreateForTesting = { value in
            if captured == nil { captured = value }
        }
        defer { CompletedWorkPresentationV1.didCreateForTesting = nil }
        let mounted = try mountCompletedWorkShell(store: fixture.coordinator,
            presentation: fixture.presentation, diagnostics: fixture.diagnostics,
            router: fixture.router) { _ in }
        defer { mounted.unmount() }
        let presentation = try await driveCompletedWorkToEditor(key: key, host: mounted.host) { captured }
        let route = try XCTUnwrap(presentation.editorRoute)
        let revisionBefore = try fixture.coordinator.workspaceWriter.currentRevision()
        let actorsBefore = try completedWorkRowCount(ActorSnapshotRow.self,
            in: fixture.coordinator.modelContext)

        fixture.presentation.receive(.sceneInactive)
        XCTAssertFalse(fixture.presentation.permitsContentPresentation)
        let submission = SignoffEnrollmentSubmissionV1(route: route.metadata,
            typedName: "Locked Responder", claimedRole: "Visitor")
        XCTAssertEqual(presentation.submit(submission), .accessDenied)
        XCTAssertEqual(presentation.lastResult, .accessDenied)
        XCTAssertNil(presentation.retainedOperation(for: key))
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), revisionBefore)
        XCTAssertEqual(try completedWorkRowCount(SignoffSnapshotRow.self,
            in: fixture.coordinator.modelContext), 0)
        XCTAssertEqual(try completedWorkRowCount(ActorSnapshotRow.self,
            in: fixture.coordinator.modelContext), actorsBefore)
        XCTAssertFalse(fixture.coordinator.modelContext.hasChanges)
        #else
        throw XCTSkip("Native hosted journey observation is DEBUG-only")
        #endif
    }

    @MainActor
    func testColdRelaunchRestoresHistoryRouteAndResponse() async throws {
        #if DEBUG
        let fixture = try await makeFixture("sig1-journey-relaunch")
        defer { fixture.cleanUp() }
        let report = try await makeReadyReport(in: fixture, label: "sig1-relaunch")
        let key = try completedWorkKey(report.reportID, revision: 1, in: fixture)
        try selectWorkBeforeLaunch(fixture)
        var captured: CompletedWorkPresentationV1?
        CompletedWorkPresentationV1.didCreateForTesting = { value in
            if captured == nil { captured = value }
        }
        defer { CompletedWorkPresentationV1.didCreateForTesting = nil }
        let mounted = try mountCompletedWorkShell(store: fixture.coordinator,
            presentation: fixture.presentation, diagnostics: fixture.diagnostics,
            router: fixture.router) { _ in }
        defer { mounted.unmount() }
        let presentation = try await driveCompletedWorkToEditor(key: key, host: mounted.host) { captured }
        let route = try XCTUnwrap(presentation.editorRoute)
        XCTAssertEqual(presentation.submit(SignoffEnrollmentSubmissionV1(route: route.metadata,
            typedName: "Relaunch Responder", claimedRole: "Owner representative",
            claimedRelationship: .owner)), .saved)
        let signoff = try XCTUnwrap(try fixture.coordinator.modelContext
            .fetch(FetchDescriptor<SignoffSnapshotRow>()).first).value()
        let historyTarget = try SignoffHistoryRouteV1(
            workspaceID: fixture.coordinator.workspaceID, signoffID: signoff.snapshotID
        ).reportsTarget
        let firstHistory = await waitForMountedScreen(
            SignoffEnrollmentView.historyAccessibilityIdentifier, from: mounted.host)
        XCTAssertTrue(firstHistory)
        let workflow = try makeCompletedWorkWorkflow(in: fixture)
        let historyBefore = try workflow.completedWorkResponses.history(focusedSignoffID: signoff.snapshotID)
        let sceneAccess = try XCTUnwrap(fixture.presentation.sceneNavigationAccess)
        let persisted = await waitUntilCompletedWork {
            guard let loaded = try? sceneAccess.load(),
                  case let .restored(snapshot) = loaded else { return false }
            return snapshot.path(for: .reports)?.targets == [historyTarget]
        }
        XCTAssertTrue(persisted)

        mounted.unmount()
        fixture.presentation.receive(.sceneInactive)
        try fixture.coordinator.invalidateAndReleaseWriter()
        let reopened = try await reopenActualCaptureAuthority(
            support: fixture.support, defaults: fixture.defaults)
        guard case .ready(_, let diagnostics, _) = reopened.router.route else {
            return XCTFail("The cold launch did not publish a ready store")
        }
        let reopenedSceneAccess = try XCTUnwrap(reopened.presentation.sceneNavigationAccess)
        if case let .restored(saved) = try reopenedSceneAccess.load() {
            XCTAssertEqual(saved.selectedRoot, .reports)
            XCTAssertEqual(saved.path(for: .reports)?.targets, [historyTarget])
        } else {
            XCTFail("Expected the persisted Reports history route")
        }
        var relaunchedScene: AppShellSceneStateV1?
        let relaunched = try mountCompletedWorkShell(store: reopened.coordinator,
            presentation: reopened.presentation, diagnostics: diagnostics,
            router: reopened.router) { scene in
            if relaunchedScene == nil { relaunchedScene = scene }
        }
        defer { relaunched.unmount() }
        let restoredHistory = await waitForMountedScreen(
            SignoffEnrollmentView.historyAccessibilityIdentifier, from: relaunched.host)
        XCTAssertTrue(restoredHistory, "Cold relaunch restores the history route")
        XCTAssertEqual(relaunchedScene?.snapshot?.selectedRoot, .reports)
        XCTAssertEqual(relaunchedScene?.snapshot?.path(for: .reports)?.targets, [historyTarget])
        let reopenedWorkflow = try makeCompletedWorkWorkflow(store: reopened.coordinator,
            diagnostics: diagnostics, access: try XCTUnwrap(reopened.presentation.renderAccess))
        XCTAssertEqual(try reopenedWorkflow.completedWorkResponses
            .history(focusedSignoffID: signoff.snapshotID), historyBefore)
        XCTAssertEqual(try reopened.coordinator.modelContext
            .fetchCount(FetchDescriptor<SignoffSnapshotRow>()), 1)
        #else
        throw XCTSkip("Native hosted journey observation is DEBUG-only")
        #endif
    }

    @MainActor
    func testDeepLinkTargetsDoNotOfferRecordOrCreateEffects() async throws {
        #if DEBUG
        let fixture = try await makeFixture("sig1-journey-deep-link")
        defer { fixture.cleanUp() }
        let report = try await makeReadyReport(in: fixture, label: "sig1-deep-link")
        let workflow = try makeCompletedWorkWorkflow(in: fixture)
        let service = workflow.completedWorkResponses
        let key = try completedWorkKey(report.reportID, revision: 1, in: fixture)
        let proof = try XCTUnwrap(try service.subjectDetail(key).proof)
        let prepared = try service.prepare(submission: completedWorkSubmission(for: proof),
            expectedProof: proof)
        guard case let .saved(receipt) = service.record(prepared) else {
            return XCTFail("Expected a saved response")
        }
        let workspaceID = fixture.coordinator.workspaceID
        let revisionBefore = try fixture.coordinator.workspaceWriter.currentRevision()
        let actorsBefore = try completedWorkRowCount(ActorSnapshotRow.self,
            in: fixture.coordinator.modelContext)

        // An editor deep link resolves to its Work root, never to the editor.
        let seed = AppShellSceneStateV1(workspaceID: workspaceID,
            access: try XCTUnwrap(fixture.presentation.sceneNavigationAccess),
            registry: try RouteRegistryV1())
        try seed.restore()
        let editorTarget = try SignoffEditorRouteV1(workspaceID: workspaceID,
            signoffID: receipt.snapshotID, expectedRevision: nil).target
        try seed.open(editorTarget)
        XCTAssertEqual(seed.snapshot?.selectedRoot, .work)

        var captured: CompletedWorkPresentationV1?
        CompletedWorkPresentationV1.didCreateForTesting = { value in
            if captured == nil { captured = value }
        }
        defer { CompletedWorkPresentationV1.didCreateForTesting = nil }
        var shellScene: AppShellSceneStateV1?
        let mounted = try mountCompletedWorkShell(store: fixture.coordinator,
            presentation: fixture.presentation, diagnostics: fixture.diagnostics,
            router: fixture.router) { scene in
            if shellScene == nil { shellScene = scene }
        }
        defer { mounted.unmount() }
        let host = mounted.host
        let rootMounted = await waitForMountedScreen(
            ProductionWorkRootViewV1.screenAccessibilityIdentifier, from: host)
        XCTAssertTrue(rootMounted)
        XCTAssertFalse(nativeScreenObservation(
            SignoffEnrollmentView.screenAccessibilityIdentifier, from: host).found,
            "An editor deep link never presents the editor")
        let presentation = try XCTUnwrap(captured, "The hosted shell composes its presentation")
        let listed = await waitUntilCompletedWork {
            if case let .loaded(items) = presentation.list {
                return items.contains { $0.key == key && $0.responseCount == 1 }
            }
            return false
        }
        XCTAssertTrue(listed, "The live Work root lists the subject with its one response")
        XCTAssertNil(presentation.editorRoute, "The editor deep link opened no editor")
        XCTAssertNil(presentation.detailRoute, "The editor deep link pushed no detail")
        XCTAssertNil(presentation.lastResult, "No Record action ran")
        let scene = try XCTUnwrap(shellScene)
        XCTAssertEqual(scene.snapshot?.selectedRoot, .work)
        XCTAssertEqual(scene.snapshot?.path(for: .work)?.targets, [editorTarget],
            "The saved editor target is kept but never presented")

        // A history deep link is read-only.
        let historyTarget = try SignoffHistoryRouteV1(workspaceID: workspaceID,
            signoffID: receipt.snapshotID).reportsTarget
        try scene.open(historyTarget)
        let historyMounted = await waitForMountedScreen(
            SignoffEnrollmentView.historyAccessibilityIdentifier, from: host)
        XCTAssertTrue(historyMounted)
        XCTAssertFalse(containsAccessibilityIdentifier(
            identifiedBy: SignoffEnrollmentView.confirmAccessibilityIdentifier, in: host.view))
        XCTAssertFalse(containsAccessibilityIdentifier(
            identifiedBy: SignoffEnrollmentView.moreAccessibilityIdentifier, in: host.view))
        XCTAssertEqual(scene.snapshot?.selectedRoot, .reports)
        XCTAssertEqual(scene.snapshot?.path(for: .reports)?.targets, [historyTarget])
        XCTAssertNil(presentation.editorRoute)
        XCTAssertNil(presentation.lastResult)

        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), revisionBefore)
        XCTAssertEqual(try completedWorkRowCount(SignoffSnapshotRow.self,
            in: fixture.coordinator.modelContext), 1)
        XCTAssertEqual(try completedWorkRowCount(ActorSnapshotRow.self,
            in: fixture.coordinator.modelContext), actorsBefore)
        XCTAssertFalse(fixture.coordinator.modelContext.hasChanges)
        #else
        throw XCTSkip("Native hosted journey observation is DEBUG-only")
        #endif
    }
}

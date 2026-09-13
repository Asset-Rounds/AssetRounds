import Combine
import Foundation
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import FieldEvidenceApp

final class V23ProductionRoundSessionTransitionPresentationTests: V23ProductionFourRootShellTestSupport {
    @MainActor
    func testActualSessionTransitionRevisionBoundLostAcknowledgementRetainsOriginalSceneOnRetry() async throws {
        #if DEBUG
        let fixture = try await makeFixture("round-transition-bound-retry")
        defer { fixture.cleanUp() }
        let seed = try await V23RoundRouteHarness.make(in: fixture, label: "bound-retry")
        let context = try await seed.addingDraftItems(1)
        let target = try context.target(for: context.round, expectedRevision: context.round.revision)
        try context.work.scene.open(target)
        let state = ProductionRoundSessionPresentationV1(target: target,
            scene: context.work.scene, access: context.access)
        await state.refresh()
        state.requestSessionTransition(.start)
        context.access.setAfterSessionTransitionReceiptForTesting { throw CancellationError() }
        let interrupted = await state.confirmSessionTransition(recordedByName: "Bound retry recorder")
        XCTAssertFalse(interrupted)
        let retained = try XCTUnwrap(state.pendingTransition)
        let afterEffect = try context.work.store.workspaceWriter.currentRevision()
        XCTAssertEqual(context.work.scene.snapshot?.path(for: .work)?.targets, [target])
        XCTAssertThrowsError(try state.validateForLeaving())
        context.access.setAfterSessionTransitionReceiptForTesting(nil)
        let retried = await state.confirmSessionTransition(recordedByName: "Never recapture this recorder")
        XCTAssertTrue(retried)
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), afterEffect)
        let successorTarget = try context.target(for: retained.proposedSession,
            expectedRevision: retained.proposedSession.revision)
        XCTAssertEqual(context.work.scene.snapshot?.path(for: .work)?.targets, [successorTarget])
        let successorState = ProductionRoundSessionPresentationV1(target: successorTarget,
            scene: context.work.scene, access: context.access)
        await successorState.refresh()
        XCTAssertEqual(successorState.session, retained.proposedSession)
        XCTAssertEqual(successorState.session?.recordedBy.displayNameAtTime, "Bound retry recorder")
        XCTAssertNil(state.pendingTransition)
        XCTAssertFalse(context.work.store.modelContext.hasChanges)
        #else
        throw XCTSkip("Publication fault injection is DEBUG-only")
        #endif
    }

    @MainActor
    func testActualSessionTransitionRejectsOriginalSceneABAReportsOnlySourceAndCoverChanges() async throws {
        #if DEBUG
        for change in ["reportsOnly", "workABA", "source", "cover"] {
            let fixture = try await makeFixture("round-transition-original-intent-" + change)
            defer { fixture.cleanUp() }
            let seed = try await V23RoundRouteHarness.make(in: fixture, label: change)
            let context = try await seed.addingDraftItems(1)
            let target = try context.target(for: context.round)
            let report = try await makeReadyReport(in: fixture, label: "original-intent-" + change)
            let reportTarget = try validatedReportTarget(report, in: fixture)
            try context.work.scene.open(target)
            let state = ProductionRoundSessionPresentationV1(target: target,
                scene: context.work.scene, access: context.access)
            await state.refresh()
            let before = try context.work.store.workspaceWriter.currentRevision()
            var afterSuspension = before
            var changedScene: SceneNavigationSnapshotV1?
            var reachedSuspension = false
            state.requestSessionTransition(.start)
            context.access.setAfterSessionTransitionContentMaterializationForTesting {
                reachedSuspension = true
                switch change {
                case "reportsOnly":
                    try context.work.scene.setPath([reportTarget], for: .reports)
                    XCTAssertEqual(context.work.scene.snapshot?.selectedRoot, .work)
                case "workABA":
                    try context.work.scene.open(context.work.target(expectedRevision: nil))
                    try context.work.scene.open(target)
                case "source":
                    _ = try await context.work.workflow.firstSign.create(.init(
                        siteLabel: "Concurrent source", signLabel: "Concurrent source asset",
                        timeZoneID: "America/New_York", isTimeZoneConfirmed: true))
                default:
                    fixture.presentation.receive(.sceneInactive)
                }
                afterSuspension = try context.work.store.workspaceWriter.currentRevision()
                changedScene = context.work.scene.snapshot
            }
            let saved = await state.confirmSessionTransition(recordedByName: "Original intent recorder")
            context.access.setAfterSessionTransitionContentMaterializationForTesting(nil)
            XCTAssertTrue(reachedSuspension)
            XCTAssertFalse(saved)
            XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), afterSuspension)
            if change == "source" { XCTAssertGreaterThan(afterSuspension.revision, before.revision) }
            else { XCTAssertEqual(afterSuspension, before) }
            XCTAssertEqual(context.work.scene.snapshot, changedScene)
            if change == "reportsOnly" {
                XCTAssertEqual(changedScene?.path(for: .reports)?.targets, [reportTarget])
                XCTAssertEqual(changedScene?.path(for: .work)?.targets, [target])
            }
            if change == "workABA" { XCTAssertEqual(changedScene?.path(for: .work)?.targets, [target]) }
            XCTAssertEqual(state.session, context.round)
            XCTAssertNil(state.pendingTransition)
            XCTAssertFalse(state.hasUnacknowledgedTransition)
            XCTAssertEqual(try context.work.store.modelContext.fetchCount(FetchDescriptor<RoundSessionRevisionRowV1>()), 2)
            XCTAssertFalse(context.work.store.modelContext.hasChanges)
        }
        #else
        throw XCTSkip("Publication fault injection is DEBUG-only")
        #endif
    }

    @MainActor
    func testActualSessionTransitionCancellationWhileSuspendedLeavesDisplayedDraftAndNoEffect() async throws {
        #if DEBUG
        let fixture = try await makeFixture("round-transition-cancellation")
        defer { fixture.cleanUp() }
        let seed = try await V23RoundRouteHarness.make(in: fixture, label: "cancellation")
        let context = try await seed.addingDraftItems(1)
        let target = try context.target(for: context.round)
        try context.work.scene.open(target)
        let state = ProductionRoundSessionPresentationV1(target: target,
            scene: context.work.scene, access: context.access)
        await state.refresh()
        let before = try context.work.store.workspaceWriter.currentRevision()
        var reachedSuspension = false
        context.access.setAfterSessionTransitionContentMaterializationForTesting {
            reachedSuspension = true
            try await Task.sleep(nanoseconds: 30_000_000_000)
        }
        state.requestSessionTransition(.start)
        let operation = Task { await state.confirmSessionTransition(recordedByName: "Cancelled recorder") }
        for _ in 0..<200 {
            if reachedSuspension { break }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertTrue(reachedSuspension, "The actual async service must yield MainActor before saving")
        XCTAssertTrue(state.isTransitioning)
        XCTAssertFalse(state.hasUnacknowledgedTransition)
        operation.cancel()
        let saved = await operation.value
        context.access.setAfterSessionTransitionContentMaterializationForTesting(nil)
        XCTAssertFalse(saved)
        XCTAssertFalse(state.isTransitioning)
        XCTAssertFalse(state.couldNotLoad)
        XCTAssertEqual(state.session, context.round)
        XCTAssertNil(state.transitionIntent)
        XCTAssertNil(state.pendingTransition)
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), before)
        XCTAssertEqual(context.work.scene.snapshot?.path(for: .work)?.targets, [target])
        XCTAssertFalse(context.work.store.modelContext.hasChanges)
        #else
        throw XCTSkip("Publication fault injection is DEBUG-only")
        #endif
    }

    @MainActor
    func testActualNativeSessionTransitionConfirmationPublishesOneHostedRoundSuccessor() async throws {
        #if DEBUG
        let fixture = try await makeFixture("round-transition-native-host")
        defer { fixture.cleanUp() }
        let seed = try await V23RoundRouteHarness.make(in: fixture, label: "native-order")
        let context = try await seed.addingDraftItems(1)
        let report = try await makeReadyReport(in: fixture, label: "native-order-report")
        let reportTarget = try validatedReportTarget(report, in: fixture)
        try context.work.scene.setPath([reportTarget], for: .reports)
        let target = try context.target(for: context.round)
        try context.work.scene.open(target)
        var actualState: ProductionRoundSessionPresentationV1?
        let bound = expectation(description: "Hosted StateObject constructs the production Round state")
        ProductionRoundSessionPresentationV1.didCreateForTesting = { value in
            guard actualState == nil else { return }
            actualState = value
            bound.fulfill()
        }
        defer { ProductionRoundSessionPresentationV1.didCreateForTesting = nil }
        let shell = AppShellView(packLoadResult: .available(.illuminatedSignV1),
            storeSession: context.work.store, contentAccess: context.work.contentAccess,
            sceneNavigationAccess: context.work.sceneAccess,
            myDayAccess: try XCTUnwrap(fixture.presentation.myDayAccess), roundAccess: context.access,
            diagnosticsStore: fixture.diagnostics,
            metricKitDiagnosticsAdapter: MetricKitDiagnosticsAdapter(manager: nil),
            feedbackConfiguration: .production, mailComposerAdapter: .unavailable,
            entitlementProcessor: fixture.router.entitlementProcessor)
        let windowScene = try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = windowScene.windows.first { $0.isKeyWindow }
        let host = UIHostingController(rootView: shell.modelContext(context.work.store.modelContext))
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previousKeyWindow?.makeKeyAndVisible() }
        host.view.layoutIfNeeded()
        await fulfillment(of: [bound], timeout: 20)
        let visible = await waitForAccessibilityIdentifier(RoundSessionView.screenAccessibilityIdentifier, in: host.view)
        XCTAssertTrue(visible)
        let state = try XCTUnwrap(actualState)
        XCTAssertEqual(state.session, context.round)
        let startVisible = await waitForAccessibilityIdentifier("production.round.transition.start", in: host.view)
        XCTAssertTrue(startVisible)
        let before = try context.work.store.workspaceWriter.currentRevision()
        state.requestSessionTransition(.start)
        let confirmation = await waitForAccessibilityIdentifier("production.round.transition.confirmation", in: window)
        XCTAssertTrue(confirmation, "Explicit hosted intent presents its real confirmation")
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), before)
        let saved = await state.confirmSessionTransition(recordedByName: "Hosted recorder")
        XCTAssertTrue(saved)
        let successor = try XCTUnwrap(state.session)
        XCTAssertEqual(successor.items.map(\.itemID), context.round.items.map(\.itemID))
        XCTAssertEqual(successor.recordedBy.displayNameAtTime, "Hosted recorder")
        let current = try await context.access.readSession(sessionID: context.round.sessionID, expectedRevision: nil)
        XCTAssertEqual(current, successor)
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision().revision, before.revision + 1)
        let navigation = try XCTUnwrap(navigationControllerPresenting(
            accessibilityIdentifier: RoundSessionView.screenAccessibilityIdentifier, from: host))
        XCTAssertEqual(navigation.viewControllers.count, 2, "One Work stack contains one canonical Round destination")
        state.leave()
        let returned = await waitForPersistedWorkRoot(context.work.sceneAccess)
        XCTAssertTrue(returned)
        if case let .restored(snapshot) = try context.work.sceneAccess.load() {
            XCTAssertEqual(snapshot.path(for: .reports)?.targets, [reportTarget])
        } else { XCTFail("Expected persisted original scene") }
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision().revision, before.revision + 1)
        XCTAssertFalse(context.work.store.modelContext.hasChanges)
        #else
        throw XCTSkip("Native hosted Round observation is DEBUG-only")
        #endif
    }

    @MainActor
    func testActualSessionTransitionRevisionBoundRoutePublishesSuccessorAndPreservesReports() async throws {
        let fixture = try await makeFixture("round-transition-revision-route")
        defer { fixture.cleanUp() }
        let seed = try await V23RoundRouteHarness.make(in: fixture, label: "revision-route")
        let context = try await seed.addingDraftItems(1)
        let target = try context.target(for: context.round, expectedRevision: context.round.revision)
        let report = try await makeReadyReport(in: fixture, label: "round-transition-retained-report")
        let reportTarget = try validatedReportTarget(report, in: fixture)
        try context.work.scene.open(reportTarget)
        try context.work.scene.open(target)
        let state = ProductionRoundSessionPresentationV1(target: target,
            scene: context.work.scene, access: context.access)
        await state.refresh()
        state.requestSessionTransition(.start)
        let didOrder = await state.confirmSessionTransition(recordedByName: "Revision route recorder")
        XCTAssertTrue(didOrder)
        let current = try await context.access.readSession(sessionID: context.round.sessionID,
            expectedRevision: context.round.revision + 1)
        XCTAssertEqual(current.revision, context.round.revision + 1)
        let successorTarget = try context.target(for: current, expectedRevision: current.revision)
        XCTAssertEqual(context.work.scene.snapshot?.path(for: .work)?.targets, [successorTarget])
        XCTAssertEqual(context.work.scene.snapshot?.path(for: .reports)?.targets, [reportTarget])
        XCTAssertNil(state.session, "A revision-bound route must reconstruct the successor presentation")
        let successorState = ProductionRoundSessionPresentationV1(target: successorTarget,
            scene: context.work.scene, access: context.access)
        await successorState.refresh()
        XCTAssertEqual(successorState.session, current)
        successorState.leave()
        XCTAssertEqual(context.work.scene.snapshot?.path(for: .work)?.targets, [])
        XCTAssertEqual(context.work.scene.snapshot?.path(for: .reports)?.targets, [reportTarget])
        XCTAssertFalse(context.work.store.modelContext.hasChanges)
    }

    @MainActor
    func testActualRoundPresentationConfirmsPauseThenResumeForCompletedItem() async throws {
        let fixture = try await makeFixture("round-completed-presentation")
        defer { fixture.cleanUp() }
        let context = try await V23RoundRouteHarness.make(in: fixture, label: "completed-presentation")
        let active = try await makeActualCompletedActiveRound(in: context, label: "presentation")
        let target = try context.target(for: active)
        try context.work.scene.open(target)
        let state = ProductionRoundSessionPresentationV1(target: target, scene: context.work.scene,
            access: context.access)
        await state.refresh()
        XCTAssertEqual(state.session, active)

        state.requestSessionTransition(.pause)
        XCTAssertEqual(state.transitionIntent?.transition, .pause)
        let didPause = await state.confirmSessionTransition(recordedByName: "Presentation pause recorder")
        XCTAssertTrue(didPause)
        let paused = try XCTUnwrap(state.session)
        XCTAssertEqual(paused.state, .paused)
        XCTAssertEqual(paused.items, active.items)

        state.requestSessionTransition(.resume)
        XCTAssertEqual(state.transitionIntent?.transition, .resume)
        let didResume = await state.confirmSessionTransition(recordedByName: "Presentation resume recorder")
        XCTAssertTrue(didResume)
        let resumed = try XCTUnwrap(state.session)
        XCTAssertEqual(resumed.state, .active)
        XCTAssertEqual(resumed.items, active.items)
        XCTAssertNil(state.transitionIntent)
        XCTAssertNil(state.pendingTransition)
        XCTAssertFalse(state.couldNotTransition)
        XCTAssertFalse(context.work.store.modelContext.hasChanges)
    }
}

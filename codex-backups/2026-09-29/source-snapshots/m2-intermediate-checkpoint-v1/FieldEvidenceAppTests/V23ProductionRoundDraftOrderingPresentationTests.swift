import Combine
import Foundation
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import FieldEvidenceApp

final class V23ProductionRoundDraftOrderingPresentationTests: V23ProductionFourRootShellTestSupport {
    @MainActor
    func testActualDraftOrderingIntentChecksBoundsCoalescesAndCancelsWithoutWrites() async throws {
        let fixture = try await makeFixture("round-order-intent")
        defer { fixture.cleanUp() }
        let seed = try await V23RoundRouteHarness.make(in: fixture, label: "order-intent")
        let context = try await seed.addingDraftItems(2)
        let target = try context.target(for: context.round)
        try context.work.scene.open(target)
        let state = ProductionRoundSessionPresentationV1(target: target,
            scene: context.work.scene, access: context.access)
        await state.refresh()
        XCTAssertEqual(state.session, context.round)
        let before = try context.work.store.workspaceWriter.currentRevision()
        let snapshot = context.work.scene.snapshot
        let first = try XCTUnwrap(context.round.items.first)
        let last = try XCTUnwrap(context.round.items.last)
        let middle = context.round.items[1]
        for (itemID, delta) in [(first.itemID, -1), (last.itemID, 1),
                                (middle.itemID, 0), (middle.itemID, 2), (UUID(), 1)] {
            state.requestDraftReorder(itemID: itemID, delta: delta)
            XCTAssertNil(state.orderingIntent)
            XCTAssertNil(state.pendingReorder)
        }
        state.requestDraftReorder(itemID: middle.itemID, delta: -1)
        let intent = try XCTUnwrap(state.orderingIntent)
        XCTAssertEqual(intent.expectedSession, context.round)
        XCTAssertEqual(intent.itemID, middle.itemID)
        XCTAssertEqual(intent.delta, -1)
        XCTAssertNil(state.pendingReorder)
        XCTAssertFalse(state.hasUnacknowledgedReorder)
        state.requestDraftReorder(itemID: first.itemID, delta: 1)
        XCTAssertEqual(state.orderingIntent, intent)
        XCTAssertTrue(state.cancelDraftReorder())
        XCTAssertNil(state.orderingIntent)
        XCTAssertEqual(state.session, context.round)
        XCTAssertEqual(context.work.scene.snapshot, snapshot)
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), before)
        XCTAssertEqual(try context.work.store.modelContext.fetchCount(
            FetchDescriptor<RoundSessionRevisionRowV1>()), 2)
        XCTAssertFalse(context.work.store.modelContext.hasChanges)
    }

    @MainActor
    func testActualDraftOrderingIntentRejectsEveryNonDraftFrontierAndOldPublication() async throws {
        let fixture = try await makeFixture("round-order-frontier-denials")
        defer { fixture.cleanUp() }
        let initial = try await V23RoundRouteHarness.make(in: fixture, label: "order-denials")
        let context = try await initial.addingDraftItems(1)
        let target = try context.target(for: context.round)
        try context.work.scene.open(target)
        let state = ProductionRoundSessionPresentationV1(target: target,
            scene: context.work.scene, access: context.access)
        var current = context.round
        let steps: [(RoundSessionStateV1, RoundSessionTransitionV1, Int?)] = [
            (.active, .start, nil), (.paused, .pause, nil), (.active, .resume, nil),
            (.active, .skipItem, 0), (.active, .skipItem, 1),
            (.completed, .close, nil), (.archived, .archive, nil),
        ]
        for (nextState, transition, itemIndex) in steps {
            if let itemIndex {
                var items = current.items
                let item = items[itemIndex]
                items[itemIndex] = try RoundItemV1(itemID: item.itemID, order: item.order,
                    selection: item.selection, requirement: item.requirement,
                    disposition: .skipped, reason: .notRequired)
                let next = try RoundSessionV1(workspaceID: current.workspaceID,
                    sessionID: current.sessionID, predecessor: current, revision: current.revision + 1,
                    mutationID: MutationIDV1(rawValue: UUID()), state: nextState,
                    transition: transition, transitionItemID: item.itemID, items: items,
                    recordedBy: current.recordedBy, recordedAt: current.recordedAt)
                _ = try context.work.store.workspaceWriter.commitRoundSession(.init(
                    workspaceID: current.workspaceID, expectedRevision: current.revision,
                    mutationID: next.mutationID, session: next))
                current = next
            } else {
                current = try context.successor(of: current, state: nextState, transition: transition)
            }
            await state.refresh()
            XCTAssertEqual(state.session, current)
            let before = try context.work.store.workspaceWriter.currentRevision()
            state.requestDraftReorder(itemID: current.items[0].itemID, delta: 1)
            XCTAssertNil(state.orderingIntent)
            XCTAssertNil(state.pendingReorder)
            XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), before)
        }

        let seed = try await V23RoundRouteHarness.make(in: fixture, label: "order-old-publication")
        let draft = try await seed.addingDraftItems(1)
        let draftTarget = try draft.target(for: draft.round)
        try draft.work.scene.open(draftTarget)
        let old = ProductionRoundSessionPresentationV1(target: draftTarget,
            scene: draft.work.scene, access: draft.access)
        await old.refresh()
        let beforeCover = try draft.work.store.workspaceWriter.currentRevision()
        fixture.presentation.receive(.sceneInactive)
        old.requestDraftReorder(itemID: draft.round.items[0].itemID, delta: 1)
        XCTAssertNil(old.orderingIntent)
        XCTAssertNil(old.pendingReorder)
        XCTAssertEqual(try draft.work.store.workspaceWriter.currentRevision(), beforeCover)
        XCTAssertFalse(draft.work.store.modelContext.hasChanges)
    }

    @MainActor
    func testActualDraftOrderingRevisionBoundRoutePublishesSuccessorAndPreservesReports() async throws {
        let fixture = try await makeFixture("round-order-revision-route")
        defer { fixture.cleanUp() }
        let seed = try await V23RoundRouteHarness.make(in: fixture, label: "revision-route")
        let context = try await seed.addingDraftItems(1)
        let target = try context.target(for: context.round, expectedRevision: context.round.revision)
        let report = try await makeReadyReport(in: fixture, label: "round-order-retained-report")
        let reportTarget = try validatedReportTarget(report, in: fixture)
        try context.work.scene.open(reportTarget)
        try context.work.scene.open(target)
        let state = ProductionRoundSessionPresentationV1(target: target,
            scene: context.work.scene, access: context.access)
        await state.refresh()
        state.requestDraftReorder(itemID: context.round.items[0].itemID, delta: 1)
        let didOrder = await state.confirmDraftReorder(recordedByName: "Revision route recorder")
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
    func testActualDraftOrderingPostMaterializationRouteDriftDeniesBeforeWrite() async throws {
        #if DEBUG
        let fixture = try await makeFixture("round-order-route-drift")
        defer { fixture.cleanUp() }
        let seed = try await V23RoundRouteHarness.make(in: fixture, label: "route-drift")
        let context = try await seed.addingDraftItems(1)
        let target = try context.target(for: context.round)
        let report = try await makeReadyReport(in: fixture, label: "round-order-drift-report")
        let reportTarget = try validatedReportTarget(report, in: fixture)
        try context.work.scene.open(target)
        let state = ProductionRoundSessionPresentationV1(target: target,
            scene: context.work.scene, access: context.access)
        await state.refresh()
        let before = try context.work.store.workspaceWriter.currentRevision()
        state.requestDraftReorder(itemID: context.round.items[0].itemID, delta: 1)
        context.access.setAfterDraftReorderContentMaterializationForTesting {
            try context.work.scene.open(reportTarget)
        }
        let didOrder = await state.confirmDraftReorder(recordedByName: "Route drift recorder")
        context.access.setAfterDraftReorderContentMaterializationForTesting(nil)
        XCTAssertFalse(didOrder)
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), before)
        XCTAssertEqual(context.work.scene.snapshot?.path(for: .reports)?.targets, [reportTarget])
        XCTAssertFalse(context.work.store.modelContext.hasChanges)
        #else
        throw XCTSkip("Publication fault injection is DEBUG-only")
        #endif
    }

    @MainActor
    func testActualDraftOrderingRejectsOriginalSceneABAReportsOnlySourceAndCoverChanges() async throws {
        #if DEBUG
        for change in ["reportsOnly", "workABA", "source", "cover"] {
            let fixture = try await makeFixture("round-order-original-intent-" + change)
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
            state.requestDraftReorder(itemID: context.round.items[0].itemID, delta: 1)
            context.access.setAfterDraftReorderContentMaterializationForTesting {
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
            let saved = await state.confirmDraftReorder(recordedByName: "Original intent recorder")
            context.access.setAfterDraftReorderContentMaterializationForTesting(nil)
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
            XCTAssertNil(state.pendingReorder)
            XCTAssertFalse(state.hasUnacknowledgedReorder)
            XCTAssertEqual(try context.work.store.modelContext.fetchCount(FetchDescriptor<RoundSessionRevisionRowV1>()), 2)
            XCTAssertFalse(context.work.store.modelContext.hasChanges)
        }
        #else
        throw XCTSkip("Publication fault injection is DEBUG-only")
        #endif
    }

    @MainActor
    func testActualDraftOrderingCancellationWhileSuspendedLeavesDisplayedDraftAndNoEffect() async throws {
        #if DEBUG
        let fixture = try await makeFixture("round-order-cancellation")
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
        context.access.setAfterDraftReorderContentMaterializationForTesting {
            reachedSuspension = true
            try await Task.sleep(nanoseconds: 30_000_000_000)
        }
        state.requestDraftReorder(itemID: context.round.items[0].itemID, delta: 1)
        let operation = Task { await state.confirmDraftReorder(recordedByName: "Cancelled recorder") }
        for _ in 0..<200 {
            if reachedSuspension { break }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertTrue(reachedSuspension, "The actual async service must yield MainActor before saving")
        XCTAssertTrue(state.isOrdering)
        XCTAssertFalse(state.hasUnacknowledgedReorder)
        operation.cancel()
        let saved = await operation.value
        context.access.setAfterDraftReorderContentMaterializationForTesting(nil)
        XCTAssertFalse(saved)
        XCTAssertFalse(state.isOrdering)
        XCTAssertFalse(state.couldNotLoad)
        XCTAssertEqual(state.session, context.round)
        XCTAssertNil(state.orderingIntent)
        XCTAssertNil(state.pendingReorder)
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), before)
        XCTAssertEqual(context.work.scene.snapshot?.path(for: .work)?.targets, [target])
        XCTAssertFalse(context.work.store.modelContext.hasChanges)
        #else
        throw XCTSkip("Publication fault injection is DEBUG-only")
        #endif
    }

    @MainActor
    func testActualNativeDraftOrderingConfirmationPublishesOneHostedRoundSuccessor() async throws {
        #if DEBUG
        let fixture = try await makeFixture("round-order-native-host")
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
        let before = try context.work.store.workspaceWriter.currentRevision()
        state.requestDraftReorder(itemID: context.round.items[1].itemID, delta: -1)
        let confirmation = await waitForAccessibilityIdentifier("production.round.ordering.confirmation", in: window)
        XCTAssertTrue(confirmation, "Explicit hosted intent presents its real confirmation")
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), before)
        let saved = await state.confirmDraftReorder(recordedByName: "Hosted recorder")
        XCTAssertTrue(saved)
        let successor = try XCTUnwrap(state.session)
        XCTAssertEqual(successor.items.map(\.itemID), context.round.items.reversed().map(\.itemID))
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
    func testActualDraftOrderingRevisionBoundLostAcknowledgementRetainsOriginalSceneOnRetry() async throws {
        #if DEBUG
        let fixture = try await makeFixture("round-order-bound-retry")
        defer { fixture.cleanUp() }
        let seed = try await V23RoundRouteHarness.make(in: fixture, label: "bound-retry")
        let context = try await seed.addingDraftItems(1)
        let target = try context.target(for: context.round, expectedRevision: context.round.revision)
        try context.work.scene.open(target)
        let state = ProductionRoundSessionPresentationV1(target: target,
            scene: context.work.scene, access: context.access)
        await state.refresh()
        state.requestDraftReorder(itemID: context.round.items[0].itemID, delta: 1)
        context.access.setAfterDraftReorderReceiptForTesting { throw CancellationError() }
        let interrupted = await state.confirmDraftReorder(recordedByName: "Bound retry recorder")
        XCTAssertFalse(interrupted)
        let retained = try XCTUnwrap(state.pendingReorder)
        let afterEffect = try context.work.store.workspaceWriter.currentRevision()
        XCTAssertEqual(context.work.scene.snapshot?.path(for: .work)?.targets, [target])
        XCTAssertThrowsError(try state.validateForLeaving())
        context.access.setAfterDraftReorderReceiptForTesting(nil)
        let retried = await state.confirmDraftReorder(recordedByName: "Never recapture this recorder")
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
        XCTAssertNil(state.pendingReorder)
        XCTAssertFalse(context.work.store.modelContext.hasChanges)
        #else
        throw XCTSkip("Publication fault injection is DEBUG-only")
        #endif
    }
}

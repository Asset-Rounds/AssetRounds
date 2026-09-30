import Combine
import Foundation
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import FieldEvidenceApp

final class V23ProductionRoundSessionTransitionTests: V23ProductionFourRootShellTestSupport {
    @MainActor
    func testActualSessionTransitionsStartPauseResumePreserveItemsAndRequireExplicitIntent() async throws {
        let fixture = try await makeFixture("round-transitions-explicit")
        defer { fixture.cleanUp() }
        let seed = try await V23RoundRouteHarness.make(in: fixture, label: "explicit")
        let context = try await seed.addingDraftItems(2)
        let target = try context.target(for: context.round, mode: .resume)
        try context.work.scene.open(target)
        let state = ProductionRoundSessionPresentationV1(target: target,
            scene: context.work.scene, access: context.access)
        let initialRevision = try context.work.store.workspaceWriter.currentRevision()
        await state.refresh()
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), initialRevision)
        XCTAssertEqual(state.session, context.round, "Route resume alone cannot start the draft")
        let actions: [(RoundSessionTransitionV1, RoundSessionStateV1)] = [(.start, .active), (.pause, .paused), (.resume, .active)]
        var expected = context.round
        for (action, nextState) in actions {
            let before = try context.work.store.workspaceWriter.currentRevision()
            let rows = try context.work.store.modelContext.fetchCount(FetchDescriptor<RoundSessionRevisionRowV1>())
            XCTAssertEqual(state.availableSessionTransition, action)
            state.requestSessionTransition(action)
            XCTAssertNotNil(state.transitionIntent)
            XCTAssertFalse(state.permitsDraftOrdering)
            state.requestDraftReorder(itemID: expected.items[0].itemID, delta: 1)
            XCTAssertNil(state.orderingIntent)
            await state.rebuildReadiness()
            XCTAssertNil(state.readiness)
            XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), before)
            let saved = await state.confirmSessionTransition(recordedByName: "Recorder \(action.rawValue)")
            XCTAssertTrue(saved)
            let current = try XCTUnwrap(state.session)
            XCTAssertEqual(current.predecessor, try expected.reference)
            XCTAssertEqual(current.revision, expected.revision + 1)
            XCTAssertEqual(current.state, nextState)
            XCTAssertEqual(current.transition, action)
            XCTAssertNil(current.transitionItemID)
            XCTAssertEqual(current.items, context.round.items)
            XCTAssertEqual(current.recordedBy.displayNameAtTime, "Recorder \(action.rawValue)")
            XCTAssertNotEqual(current.recordedBy.snapshotID, expected.recordedBy.snapshotID)
            XCTAssertNotEqual(current.recordedBy.actor.actorReferenceID, expected.recordedBy.actor.actorReferenceID)
            XCTAssertNotEqual(current.mutationID, expected.mutationID)
            XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision().revision, before.revision + 1)
            XCTAssertEqual(try context.work.store.modelContext.fetchCount(FetchDescriptor<RoundSessionRevisionRowV1>()), rows + 1)
            let readBack = try await context.access.readSession(sessionID: current.sessionID, expectedRevision: current.revision)
            XCTAssertEqual(readBack, current)
            XCTAssertNil(state.transitionIntent)
            XCTAssertNil(state.pendingTransition)
            XCTAssertFalse(state.couldNotTransition)
            XCTAssertEqual(context.work.scene.snapshot?.path(for: .work)?.targets, [target])
            expected = current
        }
        XCTAssertFalse(context.work.store.modelContext.hasChanges)
    }

    @MainActor
    func testActualSessionTransitionRejectsWrongStateForeignCommandBlankRecorderAndStaleFrontier() async throws {
        let fixture = try await makeFixture("round-transition-denials")
        defer { fixture.cleanUp() }
        let otherFixture = try await makeFixture("round-transition-foreign")
        defer { otherFixture.cleanUp() }
        let context = try await V23RoundRouteHarness.make(in: fixture, label: "denials")
        let other = try await V23RoundRouteHarness.make(in: otherFixture, label: "foreign")
        let before = try context.work.store.workspaceWriter.currentRevision()
        let otherBefore = try other.work.store.workspaceWriter.currentRevision()
        for invalid: RoundSessionTransitionV1 in [.pause, .resume, .create, .reviseSelection, .visitItem, .close, .archive] {
            XCTAssertThrowsError(try context.access.prepareSessionTransition(expected: context.round,
                transition: invalid, recordedByName: "Invalid state recorder"))
        }
        XCTAssertThrowsError(try context.access.prepareSessionTransition(expected: context.round,
            transition: .start, recordedByName: " \n "))
        let prepared = try context.access.prepareSessionTransition(expected: context.round,
            transition: .start, recordedByName: "Original recorder")
        var intentCalled = false
        do {
            _ = try await other.access.executeSessionTransition(prepared) { intentCalled = true }
            XCTFail("A foreign publication cannot consume the original prepared command")
        } catch { }
        XCTAssertFalse(intentCalled)
        XCTAssertEqual(prepared.attemptState, .notAttempted)
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), before)
        XCTAssertEqual(try other.work.store.workspaceWriter.currentRevision(), otherBefore)
        let competing = try context.successor(of: context.round, state: .active, transition: .start)
        let afterCompeting = try context.work.store.workspaceWriter.currentRevision()
        do {
            _ = try await context.access.executeSessionTransition(prepared) { intentCalled = true }
            XCTFail("A different canonical successor cannot be overwritten by stale preparation")
        } catch { }
        XCTAssertFalse(intentCalled)
        XCTAssertEqual(prepared.attemptState, .notAttempted)
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), afterCompeting)
        let readBack = try await context.access.readSession(sessionID: competing.sessionID, expectedRevision: competing.revision)
        XCTAssertEqual(readBack, competing)
        XCTAssertFalse(context.work.store.modelContext.hasChanges)
        XCTAssertFalse(other.work.store.modelContext.hasChanges)
    }

    @MainActor
    func testActualSessionTransitionLaterFrontierCannotReplayUnacknowledgedEarlierCommand() async throws {
        #if DEBUG
        let fixture = try await makeFixture("round-transition-later-frontier")
        defer { fixture.cleanUp() }
        let context = try await V23RoundRouteHarness.make(in: fixture, label: "later-frontier")
        let target = try context.target(for: context.round)
        try context.work.scene.open(target)
        let state = ProductionRoundSessionPresentationV1(target: target, scene: context.work.scene, access: context.access)
        await state.refresh()
        state.requestSessionTransition(.start)
        context.access.setAfterSessionTransitionReceiptForTesting { throw CancellationError() }
        let first = await state.confirmSessionTransition(recordedByName: "Pending recorder")
        XCTAssertFalse(first)
        let retained = try XCTUnwrap(state.pendingTransition)
        context.access.setAfterSessionTransitionReceiptForTesting(nil)
        let later = try context.successor(of: retained.proposedSession, state: .paused, transition: .pause)
        let afterLater = try context.work.store.workspaceWriter.currentRevision()
        let retried = await state.confirmSessionTransition(recordedByName: "Do not replace")
        XCTAssertFalse(retried)
        XCTAssertTrue(state.pendingTransition === retained)
        XCTAssertTrue(state.hasUnacknowledgedTransition)
        XCTAssertEqual(state.session, context.round)
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), afterLater)
        let readBack = try await context.access.readSession(sessionID: later.sessionID, expectedRevision: later.revision)
        XCTAssertEqual(readBack, later)
        XCTAssertThrowsError(try state.validateForLeaving())
        XCTAssertFalse(context.work.store.modelContext.hasChanges)
        #else
        throw XCTSkip("Publication fault injection is DEBUG-only")
        #endif
    }

    @MainActor
    func testActualSessionTransitionUsesRealPresentMissingCorruptAndConflictingContent() async throws {
        #if DEBUG
        for kind in ["present", "missing", "corrupt", "collision"] {
            let fixture = try await makeFixture("round-transition-content-" + kind)
            defer { fixture.cleanUp() }
            let seed = try await V23RoundRouteHarness.make(in: fixture, label: kind)
            let expanded = try await seed.addingDraftItems(1)
            let bytes = Data("Transition protected original".utf8)
            let original: ContentReferenceV1
            if kind == "missing" {
                original = try makeRoundContentReference(workspaceID: expanded.work.store.workspaceID,
                    label: kind, bytes: bytes)
            } else {
                original = try await persistRoundContent(in: expanded.work, label: kind, bytes: bytes)
            }
            let second = kind == "collision"
                ? try makeRoundContentReference(workspaceID: expanded.work.store.workspaceID,
                    label: "collision-other", bytes: Data("Different protected content".utf8), contentID: original.contentID)
                : original
            let context = try expanded.requiringContent([[original], [second]])
            if kind == "corrupt" {
                let url = context.work.store.generationRootURL.appendingPathComponent("content")
                    .appendingPathComponent(original.workspaceID).appendingPathComponent(original.contentID)
                    .appendingPathComponent("original.bin")
                let handle = try FileHandle(forWritingTo: url)
                try handle.write(contentsOf: Data(repeating: 0x7F, count: Int(original.byteLength)))
                try handle.close()
            }
            let target = try context.target(for: context.round)
            try context.work.scene.open(target)
            let state = ProductionRoundSessionPresentationV1(target: target, scene: context.work.scene, access: context.access)
            await state.refresh()
            let before = try context.work.store.workspaceWriter.currentRevision()
            let rows = try context.work.store.modelContext.fetchCount(FetchDescriptor<RoundSessionRevisionRowV1>())
            var resolutions = 0
            context.access.setAfterSessionTransitionContentResolutionForTesting { resolutions += 1 }
            state.requestSessionTransition(.start)
            let saved = await state.confirmSessionTransition(recordedByName: "Content recorder")
            context.access.setAfterSessionTransitionContentResolutionForTesting(nil)
            if kind == "present" || kind == "missing" {
                XCTAssertTrue(saved)
                XCTAssertEqual(resolutions, 1, "Equal references share one actual resolution in this invocation")
                XCTAssertEqual(state.session?.items, context.round.items)
                XCTAssertEqual(state.session?.state, .active)
                XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision().revision, before.revision + 1)
                XCTAssertEqual(try context.work.store.modelContext.fetchCount(FetchDescriptor<RoundSessionRevisionRowV1>()), rows + 1)
            } else {
                XCTAssertFalse(saved)
                XCTAssertEqual(state.session, context.round)
                XCTAssertNil(state.pendingTransition)
                XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), before)
                XCTAssertEqual(try context.work.store.modelContext.fetchCount(FetchDescriptor<RoundSessionRevisionRowV1>()), rows)
            }
            XCTAssertFalse(context.work.store.modelContext.hasChanges)
        }
        #else
        throw XCTSkip("Actual content observation hook is DEBUG-only")
        #endif
    }

    @MainActor
    func testActualSessionTransitionLostAcknowledgementRetriesSamePreparedWriteWithoutSecondEffect() async throws {
        #if DEBUG
        let fixture = try await makeFixture("round-transition-retry")
        defer { fixture.cleanUp() }
        let seed = try await V23RoundRouteHarness.make(in: fixture, label: "retry")
        let context = try await seed.addingDraftItems(1)
        let target = try context.target(for: context.round)
        try context.work.scene.open(target)
        let state = ProductionRoundSessionPresentationV1(target: target,
            scene: context.work.scene, access: context.access)
        await state.refresh()
        let original = context.round
        state.requestSessionTransition(.start)
        var interrupted = false
        context.access.setAfterSessionTransitionReceiptForTesting {
            interrupted = true
            throw CancellationError()
        }
        let didLoseAcknowledgement = await state.confirmSessionTransition(recordedByName: "Retry recorder")
        XCTAssertFalse(didLoseAcknowledgement)
        XCTAssertTrue(interrupted)
        let afterEffect = try context.work.store.workspaceWriter.currentRevision()
        XCTAssertTrue(state.hasUnacknowledgedTransition)
        let retained = try XCTUnwrap(state.pendingTransition)
        XCTAssertEqual(state.session, original)
        XCTAssertThrowsError(try state.validateForLeaving())
        let pendingScene = context.work.scene.snapshot
        state.leave()
        XCTAssertEqual(context.work.scene.snapshot, pendingScene)
        XCTAssertTrue(state.pendingTransition === retained)
        XCTAssertFalse(state.cancelSessionTransition())
        context.access.setAfterSessionTransitionReceiptForTesting(nil)
        let didRetry = await state.confirmSessionTransition(recordedByName: "Different retry label is ignored")
        XCTAssertTrue(didRetry)
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), afterEffect)
        let current = try XCTUnwrap(state.session)
        XCTAssertEqual(current.items.map(\.itemID), original.items.map(\.itemID))
        XCTAssertEqual(current.recordedBy.displayNameAtTime, "Retry recorder")
        XCTAssertEqual(current, retained.proposedSession)
        XCTAssertNil(state.pendingTransition)
        XCTAssertNil(state.transitionIntent)
        XCTAssertFalse(context.work.store.modelContext.hasChanges)
        #else
        throw XCTSkip("Publication fault injection is DEBUG-only")
        #endif
    }

    @MainActor
    func testActualCompletedRoundPauseAndResumeUseOneReceiptEach() async throws {
        let fixture = try await makeFixture("round-completed-pause-resume")
        defer { fixture.cleanUp() }
        let context = try await V23RoundRouteHarness.make(in: fixture, label: "completed-pause-resume")
        let active = try await makeActualCompletedActiveRound(in: context, label: "pause-resume")
        let before = try context.work.store.workspaceWriter.currentRevision()

        let pause = try context.access.prepareSessionTransition(expected: active, transition: .pause,
            recordedByName: "Pause receipt recorder")
        let pauseReceipt = try await context.access.executeSessionTransition(pause) {}
        XCTAssertEqual(pauseReceipt.sessionFrontier, try pause.proposedSession.reference)
        XCTAssertEqual(pause.proposedSession.state, .paused)
        XCTAssertEqual(pause.proposedSession.items, active.items)
        XCTAssertEqual(pause.proposedSession.items.first?.completion?.completionID,
            active.items.first?.completion?.completionID)

        let resume = try context.access.prepareSessionTransition(expected: pause.proposedSession, transition: .resume,
            recordedByName: "Resume receipt recorder")
        let resumeReceipt = try await context.access.executeSessionTransition(resume) {}
        XCTAssertEqual(resumeReceipt.sessionFrontier, try resume.proposedSession.reference)
        XCTAssertEqual(resume.proposedSession.state, .active)
        XCTAssertEqual(resume.proposedSession.items, active.items)
        XCTAssertEqual(resume.proposedSession.items.first?.completion?.completionID,
            active.items.first?.completion?.completionID)
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision().revision, before.revision + 2)
        XCTAssertFalse(context.work.store.modelContext.hasChanges)
    }

    @MainActor
    func testCompletedRoundTransitionRejectsMissingMismatchedUnsupportedAndCorruptCompletionWithoutWrite() async throws {
        let fixture = try await makeFixture("round-completion-denial")
        defer { fixture.cleanUp() }

        // The source record/report and CompletionReference are produced by the
        // normal CheckRunner -> FinalizationService flow.  Only the hostile
        // stored Round reference/package or immutable snapshot is changed.
        let mismatchedContext = try await V23RoundRouteHarness.make(in: fixture, label: "completion-mismatch")
        let finalized = try await makeActualFinalizedCompletion(in: mismatchedContext, label: "mismatch")
        let missing = try RoundItemCompletionReferenceV1(completionID: UUID(), revision: finalized.reference.revision,
            completionSHA256: finalized.reference.completionSHA256)
        let mismatched = try makeCompletedActiveRound(in: mismatchedContext, completion: missing,
            requirement: mismatchedContext.round.items[0].requirement, recordedAt: Date())
        try await assertCompletionTransitionDenied(context: mismatchedContext, active: mismatched)

        let wrongAssetContext = try await V23RoundRouteHarness.make(in: fixture, label: "completion-wrong-asset")
        let otherAsset = try await wrongAssetContext.work.workflow.firstSign.create(.init(
            siteLabel: "Round wrong-completion site", signLabel: "Round wrong-completion asset",
            timeZoneID: "America/New_York", isTimeZoneConfirmed: true))
        let actualWrongAsset = try await makeActualFinalizedCompletion(in: wrongAssetContext,
            label: "wrong-asset", asset: otherAsset)
        let wrongAsset = try makeCompletedActiveRound(in: wrongAssetContext, completion: actualWrongAsset.reference,
            requirement: wrongAssetContext.round.items[0].requirement, recordedAt: Date())
        try await assertCompletionTransitionDenied(context: wrongAssetContext, active: wrongAsset)

        let unavailableContext = try await V23RoundRouteHarness.make(in: fixture, label: "completion-unavailable")
        let unavailableFinalized = try await makeActualFinalizedCompletion(in: unavailableContext, label: "unavailable")
        let unsupportedRelease = try roundShippingRelease(stage: .recheck)
        XCTAssertNotEqual(unsupportedRelease.workflowSHA256,
            unavailableContext.round.items[0].requirement.packageRelease.workflowSHA256)
        let unsupportedRequirement = try RoundPackageContentRequirementV1(packageRelease: .init(unsupportedRelease),
            requiredContent: [])
        let unavailable = try makeCompletedActiveRound(in: unavailableContext,
            completion: unavailableFinalized.reference, requirement: unsupportedRequirement, recordedAt: Date())
        try await assertCompletionTransitionDenied(context: unavailableContext, active: unavailable)

        let corruptContext = try await V23RoundRouteHarness.make(in: fixture, label: "completion-corrupt")
        let corruptFinalized = try await makeActualFinalizedCompletion(in: corruptContext, label: "corrupt")
        let corrupt = try makeCompletedActiveRound(in: corruptContext, completion: corruptFinalized.reference,
            requirement: corruptContext.round.items[0].requirement, recordedAt: Date())
        let original = try Data(contentsOf: corruptFinalized.snapshotURL)
        defer { try? original.write(to: corruptFinalized.snapshotURL) }
        try Data("corrupt actual finalized inspection".utf8).write(to: corruptFinalized.snapshotURL)
        try await assertCompletionTransitionDenied(context: corruptContext, active: corrupt)
    }

    @MainActor
    func testActualSessionTransitionDirectCancelledCallerCannotAttemptCanonicalWrite() async throws {
        let fixture = try await makeFixture("round-transition-direct-cancel")
        defer { fixture.cleanUp() }
        let context = try await V23RoundRouteHarness.make(in: fixture, label: "direct-cancel")
        let prepared = try context.access.prepareSessionTransition(expected: context.round,
            transition: .start, recordedByName: "Cancelled direct recorder")
        let before = try context.work.store.workspaceWriter.currentRevision()
        var intentCalled = false
        let operation = Task { @MainActor in
            try await context.access.executeSessionTransition(prepared) { intentCalled = true }
        }
        operation.cancel()
        do {
            _ = try await operation.value
            XCTFail("Cancellation before service entry must deny even with no required content")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertFalse(intentCalled)
        XCTAssertEqual(prepared.attemptState, .notAttempted)
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), before)
        XCTAssertEqual(try context.work.store.modelContext.fetchCount(FetchDescriptor<RoundSessionRevisionRowV1>()), 1)
        XCTAssertFalse(context.work.store.modelContext.hasChanges)
    }
}

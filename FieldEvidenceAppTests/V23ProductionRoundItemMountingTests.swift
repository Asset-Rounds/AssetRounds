import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

/// Stage A of C36 Round item mounting: an explicit Continue resumes or launches
/// the Round's one capture source, records ENTRY once and opens the existing
/// durable item host. Reopening reuses every acknowledged write.
final class V23ProductionRoundItemMountingTests: V23ProductionFourRootShellTestSupport {
    @MainActor
    func testContinueLaunchesEntersOnceOpensDurableHostAndColdReopenAddsNoWrites() async throws {
        let fixture = try await makeFixture("round-item-mount")
        defer { fixture.cleanUp() }
        let seed = try await V23RoundRouteHarness.make(in: fixture, label: "round-item-mount")
        let context = try await seed.addingDraftItems(1)
        let active = try await startActualRound(in: context, recorder: "Mount start")
        let ordered = active.items.sorted { $0.order < $1.order }
        let first = ordered[0], second = ordered[1]
        let target = try context.target(for: active, mode: .resume)
        try context.work.scene.open(target)
        let state = ProductionRoundSessionPresentationV1(target: target,
            scene: context.work.scene, access: context.access)
        await state.refresh()
        XCTAssertEqual(state.session, active)
        XCTAssertTrue(state.permitsCapture)
        XCTAssertTrue(try context.access.readRepetitiveCaptureSources(round: active).isEmpty)

        // A later item never launches the linear chain and writes nothing.
        let untouched = try context.work.store.workspaceWriter.currentRevision()
        state.requestCapture(itemID: second.itemID)
        XCTAssertEqual(state.captureIntent, second.itemID)
        let outOfOrder = await state.confirmCapture(recordedByName: "Mount recorder")
        XCTAssertFalse(outOfOrder)
        XCTAssertTrue(state.couldNotOpenCapture)
        XCTAssertTrue(state.captureOutOfOrder)
        XCTAssertNil(state.captureHost)
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), untouched)
        XCTAssertTrue(try context.access.readRepetitiveCaptureSources(round: active).isEmpty)
        XCTAssertTrue(state.cancelCapture())
        XCTAssertNil(state.captureIntent)

        state.requestCapture(itemID: first.itemID)
        let opened = await state.confirmCapture(recordedByName: "Mount recorder")
        XCTAssertTrue(opened, state.lastCaptureFailureForTesting ?? "")
        let host = try XCTUnwrap(state.captureHost)
        XCTAssertNil(state.captureIntent)
        XCTAssertEqual(host.source.originalItem.itemID, first.itemID)
        XCTAssertEqual(host.source.requestedEntry, .check)
        XCTAssertNotNil(host.editor)
        XCTAssertNotNil(host.preflight)
        let parent = try XCTUnwrap(host.checkpoint)
        let sources = try context.access.readRepetitiveCaptureSources(round: active)
        XCTAssertEqual(sources.count, 1)
        let chain = try XCTUnwrap(sources.first).chain
        XCTAssertEqual(chain.nodes.map { $0.step.action }, [.enter])
        XCTAssertEqual(chain.nodes.first?.step.itemID, first.itemID)
        XCTAssertFalse(try XCTUnwrap(chain.nodes.last).isPendingRoundEffect)
        XCTAssertEqual(chain.currentRound.items.first { $0.itemID == first.itemID }?.disposition, .visited)
        XCTAssertEqual(host.source.sourceCheckpoint.draftID, chain.sourceCheckpoint.draftID)
        XCTAssertEqual(state.session, chain.currentRound)
        XCTAssertFalse(state.permitsCapture)
        XCTAssertThrowsError(try state.validateForLeaving())
        let afterOpen = try context.work.store.workspaceWriter.currentRevision()
        XCTAssertGreaterThan(afterOpen.revision, untouched.revision)
        state.dismissCapture()
        XCTAssertNil(state.captureHost)
        await host.retire()
        XCTAssertNoThrow(try state.validateForLeaving())

        // A cold presentation reuses the same source, ENTRY and parent draft.
        let reopened = ProductionRoundSessionPresentationV1(target: target,
            scene: context.work.scene, access: context.access)
        await reopened.refresh()
        XCTAssertEqual(reopened.session, chain.currentRound)
        reopened.requestCapture(itemID: first.itemID)
        let resumedOpen = await reopened.confirmCapture(recordedByName: "Another recorder")
        XCTAssertTrue(resumedOpen, reopened.lastCaptureFailureForTesting ?? "")
        let resumed = try XCTUnwrap(reopened.captureHost)
        XCTAssertEqual(resumed.checkpoint?.draftID, parent.draftID)
        XCTAssertEqual(resumed.source, host.source)
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), afterOpen)
        XCTAssertEqual(try context.access.readRepetitiveCaptureSources(round: active).first?.chain, chain)
        reopened.dismissCapture()
        await resumed.retire()
        XCTAssertFalse(context.work.store.modelContext.hasChanges)
    }

    @MainActor
    func testContinueDeniesDraftPausedAndCompetingSourcesWithoutEffects() async throws {
        let fixture = try await makeFixture("round-item-mount-denials")
        defer { fixture.cleanUp() }
        let context = try await V23RoundRouteHarness.make(in: fixture, label: "round-item-mount-denials")
        let item = try XCTUnwrap(context.round.items.first)
        let target = try context.target(for: context.round, mode: .resume)
        try context.work.scene.open(target)
        let draftState = ProductionRoundSessionPresentationV1(target: target,
            scene: context.work.scene, access: context.access)
        await draftState.refresh()
        XCTAssertEqual(draftState.session?.state, .draft)
        XCTAssertFalse(draftState.permitsCapture)
        draftState.requestCapture(itemID: item.itemID)
        XCTAssertNil(draftState.captureIntent)
        let draftOpened = await draftState.confirmCapture(recordedByName: "Draft recorder")
        XCTAssertFalse(draftOpened)

        let active = try await step("start") { try await startActualRound(in: context, recorder: "Denial start") }
        let pause = try await step("prepare-pause") {
            try context.access.prepareSessionTransition(expected: active, transition: .pause,
                recordedByName: "Denial pause")
        }
        _ = try await step("execute-pause") { try await context.access.executeSessionTransition(pause) {} }
        let pausedState = ProductionRoundSessionPresentationV1(target: target,
            scene: context.work.scene, access: context.access)
        await pausedState.refresh()
        XCTAssertEqual(pausedState.session?.state, .paused)
        XCTAssertFalse(pausedState.permitsCapture)
        pausedState.requestCapture(itemID: item.itemID)
        XCTAssertNil(pausedState.captureIntent)
        let resume = try await step("prepare-resume") {
            try context.access.prepareSessionTransition(expected: pause.proposedSession,
                transition: .resume, recordedByName: "Denial resume")
        }
        _ = try await step("execute-resume") { try await context.access.executeSessionTransition(resume) {} }
        let resumedRound = resume.proposedSession

        // The writer admits a second plan-scoped source; the Round surface must not choose.
        for index in 0..<2 {
            let readiness = try await step("readiness-\(index)") {
                try await context.access.rebuildReadiness(for: resumedRound, previous: nil)
            }
            let launch = try await step("prepare-launch-\(index)") {
                try context.access.prepareRepetitiveCaptureLaunch(round: resumedRound, readiness: readiness)
            }
            _ = try await step("persist-launch-\(index)") {
                try context.access.persistRepetitiveCaptureLaunch(launch) {}
            }
        }
        XCTAssertEqual(try context.access.readRepetitiveCaptureSources(round: resumedRound).count, 2)
        let state = ProductionRoundSessionPresentationV1(target: target,
            scene: context.work.scene, access: context.access)
        await state.refresh()
        XCTAssertEqual(state.session?.state, .active)
        let before = try context.work.store.workspaceWriter.currentRevision()
        state.requestCapture(itemID: item.itemID)
        let opened = await state.confirmCapture(recordedByName: "Denial recorder")
        XCTAssertFalse(opened)
        XCTAssertTrue(state.couldNotOpenCapture)
        XCTAssertFalse(state.captureOutOfOrder)
        XCTAssertNil(state.captureHost)
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), before)
        XCTAssertFalse(context.work.store.modelContext.hasChanges)
    }

    @MainActor
    func testForeignCanonicalDraftDeniesEntryBeforeAnyWrite() async throws {
        let fixture = try await makeFixture("round-item-mount-foreign-draft")
        defer { fixture.cleanUp() }
        let context = try await V23RoundRouteHarness.make(in: fixture, label: "round-item-mount-foreign-draft")
        let active = try await startActualRound(in: context, recorder: "Foreign start")
        let item = try XCTUnwrap(active.items.first)
        // A standalone check begun outside this Round owns the asset's canonical draft.
        _ = try context.work.workflow.checkRunner.beginCheck(assetID: item.selection.assetID,
            timeZoneID: "America/New_York", isTimeZoneConfirmed: true,
            afterDarkAccepted: true, safePositionAccepted: true, observedAt: roundTimestamp())
        let target = try context.target(for: active, mode: .resume)
        try context.work.scene.open(target)
        let state = ProductionRoundSessionPresentationV1(target: target,
            scene: context.work.scene, access: context.access)
        await state.refresh()
        let before = try context.work.store.workspaceWriter.currentRevision()
        state.requestCapture(itemID: item.itemID)
        let opened = await state.confirmCapture(recordedByName: "Foreign recorder")
        XCTAssertFalse(opened)
        XCTAssertTrue(state.couldNotOpenCapture)
        XCTAssertFalse(state.captureOutOfOrder)
        XCTAssertNil(state.captureHost)
        XCTAssertTrue(try context.access.readRepetitiveCaptureSources(round: active).isEmpty)
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), before)
        XCTAssertFalse(context.work.store.modelContext.hasChanges)
    }

    @MainActor
    func testContinueRecoversSourceAndEntryAcknowledgementLossWithOneOfEach() async throws {
        #if DEBUG
        let fixture = try await makeFixture("round-item-mount-ack-loss")
        defer { fixture.cleanUp() }
        let context = try await V23RoundRouteHarness.make(in: fixture, label: "round-item-mount-ack-loss")
        let active = try await startActualRound(in: context, recorder: "Ack start")
        let item = try XCTUnwrap(active.items.first)
        let target = try context.target(for: active, mode: .resume)
        try context.work.scene.open(target)
        let state = ProductionRoundSessionPresentationV1(target: target,
            scene: context.work.scene, access: context.access)
        await state.refresh()

        context.access.setAfterRepetitiveCaptureSourceReceiptForTesting { throw CancellationError() }
        state.requestCapture(itemID: item.itemID)
        let sourceLoss = await state.confirmCapture(recordedByName: "Ack recorder")
        context.access.setAfterRepetitiveCaptureSourceReceiptForTesting(nil)
        XCTAssertFalse(sourceLoss)
        XCTAssertNil(state.captureHost)
        XCTAssertEqual(try context.access.readRepetitiveCaptureSources(round: active).count, 1)

        context.access.setAfterRepetitiveCaptureStepReceiptForTesting { throw CancellationError() }
        state.requestCapture(itemID: item.itemID)
        let stepLoss = await state.confirmCapture(recordedByName: "Ack recorder")
        context.access.setAfterRepetitiveCaptureStepReceiptForTesting(nil)
        XCTAssertFalse(stepLoss)
        XCTAssertNil(state.captureHost)
        let pending = try XCTUnwrap(context.access.readRepetitiveCaptureSources(round: active).first).chain
        XCTAssertEqual(pending.nodes.count, 1)
        XCTAssertTrue(try XCTUnwrap(pending.nodes.last).isPendingRoundEffect)

        state.requestCapture(itemID: item.itemID)
        let recovered = await state.confirmCapture(recordedByName: "Ack recorder")
        XCTAssertTrue(recovered, state.lastCaptureFailureForTesting ?? "")
        let host = try XCTUnwrap(state.captureHost)
        let sources = try context.access.readRepetitiveCaptureSources(round: active)
        XCTAssertEqual(sources.count, 1)
        let chain = try XCTUnwrap(sources.first).chain
        XCTAssertEqual(chain.nodes.map { $0.step.action }, [.enter])
        XCTAssertEqual(chain.nodes.first?.checkpoint, pending.nodes.first?.checkpoint)
        XCTAssertFalse(try XCTUnwrap(chain.nodes.last).isPendingRoundEffect)
        state.dismissCapture()
        await host.retire()
        #endif
    }

    @MainActor
    func testPendingEffectForAnotherItemIsNotSettledByAnOutOfOrderTap() async throws {
        #if DEBUG
        let fixture = try await makeFixture("round-item-mount-pending-other")
        defer { fixture.cleanUp() }
        let seed = try await V23RoundRouteHarness.make(in: fixture, label: "round-item-mount-pending-other")
        let context = try await seed.addingDraftItems(1)
        let active = try await startActualRound(in: context, recorder: "Pending start")
        let ordered = active.items.sorted { $0.order < $1.order }
        let first = ordered[0], second = ordered[1]
        let target = try context.target(for: active, mode: .resume)
        try context.work.scene.open(target)
        let state = ProductionRoundSessionPresentationV1(target: target,
            scene: context.work.scene, access: context.access)
        await state.refresh()
        state.requestCapture(itemID: first.itemID)
        let opened = await state.confirmCapture(recordedByName: "Pending recorder")
        XCTAssertTrue(opened, state.lastCaptureFailureForTesting ?? "")
        let host = try XCTUnwrap(state.captureHost)
        state.dismissCapture()
        await host.retire()

        // DEFER_AND_NEXT stores its Round effect and navigates to the second item.
        let sourceID = try XCTUnwrap(context.access.readRepetitiveCaptureSources(round: active).first)
            .chain.sourceCheckpoint.draftID
        let deferStep = try await prepareActualCaptureStep(in: context, sourceDraftID: sourceID, action: .defer)
        context.access.setAfterRepetitiveCaptureStepReceiptForTesting { throw CancellationError() }
        do { _ = try await context.access.executeRepetitiveCaptureStep(deferStep) {}; XCTFail("Injected loss") }
        catch { XCTAssertTrue(error is CancellationError) }
        context.access.setAfterRepetitiveCaptureStepReceiptForTesting(nil)
        let pending = try context.access.readRepetitiveCaptureProgress(sourceDraftID: sourceID)
        XCTAssertTrue(try XCTUnwrap(pending.chain.nodes.last).isPendingRoundEffect)
        XCTAssertEqual(pending.chain.nodes.last?.step.navigationItemID, second.itemID)

        let reopened = ProductionRoundSessionPresentationV1(target: target,
            scene: context.work.scene, access: context.access)
        await reopened.refresh()
        let before = try context.work.store.workspaceWriter.currentRevision()
        reopened.requestCapture(itemID: first.itemID)
        let wrongItem = await reopened.confirmCapture(recordedByName: "Pending recorder")
        XCTAssertFalse(wrongItem)
        XCTAssertTrue(reopened.captureOutOfOrder)
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), before)
        XCTAssertTrue(try XCTUnwrap(context.access.readRepetitiveCaptureProgress(sourceDraftID: sourceID)
            .chain.nodes.last).isPendingRoundEffect)
        XCTAssertTrue(reopened.cancelCapture())

        reopened.requestCapture(itemID: second.itemID)
        let next = await reopened.confirmCapture(recordedByName: "Pending recorder")
        XCTAssertTrue(next)
        let nextHost = try XCTUnwrap(reopened.captureHost)
        XCTAssertEqual(nextHost.source.originalItem.itemID, second.itemID)
        let settled = try context.access.readRepetitiveCaptureProgress(sourceDraftID: sourceID).chain
        XCTAssertEqual(settled.nodes.map { $0.step.action }, [.enter, .defer, .enter])
        XCTAssertEqual(settled.currentRound.items.first { $0.itemID == first.itemID }?.disposition, .deferred)
        reopened.dismissCapture()
        await nextHost.retire()
        #endif
    }

    @MainActor
    func testRevisionPinnedRouteRetargetsThenReusesEntryAndBegunParentReopens() async throws {
        let fixture = try await makeFixture("round-item-mount-pinned")
        defer { fixture.cleanUp() }
        let context = try await V23RoundRouteHarness.make(in: fixture, label: "round-item-mount-pinned")
        let active = try await startActualRound(in: context, recorder: "Pinned start")
        let item = try XCTUnwrap(active.items.first)
        let pinned = try context.target(for: active, mode: .resume, expectedRevision: active.revision)
        try context.work.scene.open(pinned)
        let state = ProductionRoundSessionPresentationV1(target: pinned,
            scene: context.work.scene, access: context.access)
        await state.refresh()
        state.requestCapture(itemID: item.itemID)
        let retargeted = await state.confirmCapture(recordedByName: "Pinned recorder")
        XCTAssertFalse(retargeted)
        XCTAssertNil(state.captureHost)
        XCTAssertNil(state.captureIntent)
        let entered = try XCTUnwrap(context.access.readRepetitiveCaptureSources(round: active).first).chain
        XCTAssertEqual(entered.nodes.map { $0.step.action }, [.enter])
        let successor = try context.target(for: entered.currentRound, mode: .resume,
            expectedRevision: entered.currentRound.revision)
        XCTAssertEqual(context.work.scene.snapshot?.path(for: .work)?.targets, [successor])
        let afterEntry = try context.work.store.workspaceWriter.currentRevision()

        let next = ProductionRoundSessionPresentationV1(target: successor,
            scene: context.work.scene, access: context.access)
        await next.refresh()
        next.requestCapture(itemID: item.itemID)
        let opened = await next.confirmCapture(recordedByName: "Pinned recorder")
        XCTAssertTrue(opened, next.lastCaptureFailureForTesting ?? "")
        let host = try XCTUnwrap(next.captureHost)
        // ENTRY is reused; only the parent draft is created.
        XCTAssertEqual(try context.access.readRepetitiveCaptureSources(round: active).first?.chain, entered)
        XCTAssertGreaterThan(try context.work.store.workspaceWriter.currentRevision().revision, afterEntry.revision)
        XCTAssertNotNil(host.editor)

        // Begin through the existing durable host, then reopen the begun parent.
        let editor = try XCTUnwrap(host.editor)
        var preflight = editor.values.preflight
        preflight.afterDarkAccepted = true
        preflight.safePositionAccepted = true
        if !preflight.isTimeZoneConfirmed {
            preflight.timeZoneID = "America/New_York"
            preflight.isTimeZoneConfirmed = true
        }
        try host.replaceEditableValues(.init(preflight: preflight, outcome: editor.values.outcome,
            semanticAnchor: editor.values.semanticAnchor))
        XCTAssertEqual(host.durableBegin, .notBegun)
        try await host.begin(observedAtUTC: roundTimestamp())
        XCTAssertTrue(host.hasBoundBegin)
        let begun = try XCTUnwrap(host.checkpoint)
        next.dismissCapture()
        await host.retire()
        let afterBegin = try context.work.store.workspaceWriter.currentRevision()

        let reopened = ProductionRoundSessionPresentationV1(target: successor,
            scene: context.work.scene, access: context.access)
        await reopened.refresh()
        reopened.requestCapture(itemID: item.itemID)
        let begunOpen = await reopened.confirmCapture(recordedByName: "Pinned recorder")
        XCTAssertTrue(begunOpen, reopened.lastCaptureFailureForTesting ?? "")
        let begunHost = try XCTUnwrap(reopened.captureHost)
        XCTAssertTrue(begunHost.hasBoundBegin)
        XCTAssertEqual(begunHost.checkpoint?.draftID, begun.draftID)
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), afterBegin)
        reopened.dismissCapture()
        await begunHost.retire()
        XCTAssertNoThrow(try reopened.validateForLeaving())
    }

    @MainActor
    func testInterruptedPreparedBeginReopensForExplicitRecoveryAndCompletesOnce() async throws {
        let fixture = try await makeFixture("round-item-mount-prepared-begin")
        defer { fixture.cleanUp() }
        let context = try await V23RoundRouteHarness.make(in: fixture, label: "round-item-mount-prepared-begin")
        let active = try await startActualRound(in: context, recorder: "Prepared start")
        let item = try XCTUnwrap(active.items.sorted { $0.order < $1.order }.first)
        let target = try context.target(for: active, mode: .resume)
        try context.work.scene.open(target)
        let state = ProductionRoundSessionPresentationV1(target: target,
            scene: context.work.scene, access: context.access)
        await state.refresh()
        state.requestCapture(itemID: item.itemID)
        let opened = await state.confirmCapture(recordedByName: "Prepared recorder")
        XCTAssertTrue(opened, state.lastCaptureFailureForTesting ?? "")
        let host = try XCTUnwrap(state.captureHost)
        let editor = try XCTUnwrap(host.editor)
        var preflight = editor.values.preflight
        preflight.afterDarkAccepted = true
        preflight.safePositionAccepted = true
        if !preflight.isTimeZoneConfirmed {
            preflight.timeZoneID = "America/New_York"
            preflight.isTimeZoneConfirmed = true
        }
        try host.replaceEditableValues(.init(preflight: preflight, outcome: editor.values.outcome,
            semanticAnchor: editor.values.semanticAnchor))
        try await host.flushAndPerform(reason: .back) { }
        let saved = try XCTUnwrap(host.checkpoint)

        // Interrupt Begin after its frozen PREPARED write, before any canonical record.
        let prepared = try context.access.captureCheckRunnerItemOperation(service: host.service,
            scene: context.work.scene, target: target).withAuthorization {
            try host.service.prepareBegin(draftID: saved.draftID,
                expectedCheckpointSHA256: saved.checkpointSHA256, observedAtUTC: roundTimestamp())
        }
        guard case let .prepared(attempt) = try CheckRunnerItemDraftCodecV1.validateCheckpoint(prepared).field.begin else {
            return XCTFail("Expected an interrupted PREPARED Begin")
        }
        let recordID = attempt.recordCommand.recordID
        let workflowRecordCount: @MainActor () throws -> Int = {
            try context.work.store.modelContext.fetch(FetchDescriptor<WorkflowRecord>(
                predicate: #Predicate { $0.id == recordID })).count
        }
        state.dismissCapture()
        await host.retire()
        XCTAssertEqual(try workflowRecordCount(), 0)
        let afterPrepare = try context.work.store.workspaceWriter.currentRevision()

        // Reopening is read-only. A PREPARED parent admits no field flush, so
        // it has no editor and is neither Preflight nor a started check.
        let reopened = ProductionRoundSessionPresentationV1(target: target,
            scene: context.work.scene, access: context.access)
        await reopened.refresh()
        reopened.requestCapture(itemID: item.itemID)
        let reopenedOpen = await reopened.confirmCapture(recordedByName: "Prepared recorder")
        XCTAssertTrue(reopenedOpen, reopened.lastCaptureFailureForTesting ?? "")
        let resumed = try XCTUnwrap(reopened.captureHost)
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), afterPrepare)
        XCTAssertEqual(resumed.checkpoint, prepared)
        XCTAssertEqual(resumed.durableBegin, .prepared(attempt: attempt))
        XCTAssertTrue(resumed.hasPreparedBegin)
        XCTAssertFalse(resumed.hasBoundBegin)
        XCTAssertNil(resumed.editor)
        do {
            try await resumed.begin(observedAtUTC: roundTimestamp())
            XCTFail("A PREPARED parent must not be re-flushed through Begin")
        } catch {
            XCTAssertEqual(error as? ProductionCheckRunnerItemCaptureFailureV1, .missingEditor)
        }
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), afterPrepare)

        // Explicit recovery binds the frozen original once, without a new sample.
        try resumed.finishPreparedBegin()
        XCTAssertTrue(resumed.hasBoundBegin)
        guard case let .bound(boundAttempt, _, _)? = resumed.durableBegin else {
            return XCTFail("Expected the original Begin to be bound")
        }
        XCTAssertEqual(boundAttempt, attempt)
        XCTAssertEqual(try workflowRecordCount(), 1)
        XCTAssertNotNil(resumed.editor)
        XCTAssertThrowsError(try resumed.finishPreparedBegin()) { error in
            XCTAssertEqual(error as? ProductionCheckRunnerItemCaptureFailureV1, .notPreparedBegin)
        }
        XCTAssertEqual(try workflowRecordCount(), 1)
        reopened.dismissCapture()
        await resumed.retire()
        XCTAssertNoThrow(try reopened.validateForLeaving())
    }

    /// Diagnostic only: names the step that threw, then rethrows unchanged.
    @MainActor
    private func step<T>(_ name: String, _ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch {
            print("V23_ROUND_STEP_FAILURE step=\(name) error=\(String(reflecting: error))")
            throw error
        }
    }
}

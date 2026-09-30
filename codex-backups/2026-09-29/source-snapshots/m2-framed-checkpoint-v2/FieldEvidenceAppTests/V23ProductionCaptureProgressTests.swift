import Combine
import Foundation
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import FieldEvidenceApp

final class V23ProductionCaptureProgressTests: V23ProductionFourRootShellTestSupport {
    @MainActor
    func testActualCaptureProgressPreservesOrderedMixedActionsAndCanonicalCompletion() async throws {
        let fixture = try await makeFixture("capture-mixed")
        defer { fixture.cleanUp() }
        let seed = try await V23RoundRouteHarness.make(in: fixture, label: "capture-mixed")
        let context = try await seed.addingDraftItems(2)
        let active = try await startActualRound(in: context, recorder: "Capture start")
        let readiness = try await context.access.rebuildReadiness(for: active, previous: nil)
        let launch = try context.access.prepareRepetitiveCaptureLaunch(round: active, readiness: readiness)
        let before = try context.work.store.workspaceWriter.currentRevision()
        let source = try context.access.persistRepetitiveCaptureLaunch(launch) {}
        XCTAssertEqual(source.chain.currentRound, active)
        XCTAssertTrue(source.chain.nodes.isEmpty)
        XCTAssertEqual(source.chain.launch.round.items, active.items)
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision().revision, before.revision + 1)
        let sourceID = launch.checkpoint.draftID
        let entry = try await prepareActualCaptureStep(in: context, sourceDraftID: sourceID, action: .enter)
        let entered = try await context.access.executeRepetitiveCaptureStep(entry) {}
        XCTAssertEqual(entered.progress.chain.currentRound.items[0].disposition, .visited)
        let finalized = try await makeActualFinalizedCompletion(in: context, label: "capture-mixed")
        let complete = try await prepareActualCaptureStep(in: context, sourceDraftID: sourceID,
            action: .complete, completionRecordID: finalized.reference.completionID)
        let completed = try await context.access.executeRepetitiveCaptureStep(complete) {}
        XCTAssertEqual(completed.progress.chain.currentRound.items[0].completion, finalized.reference)
        XCTAssertEqual(completed.progress.chain.nodes.last?.step.navigationItemID, active.items[1].itemID)
        let entryB = try await prepareActualCaptureStep(in: context, sourceDraftID: sourceID, action: .enter)
        _ = try await context.access.executeRepetitiveCaptureStep(entryB) {}
        let keep = try await prepareActualCaptureStep(in: context, sourceDraftID: sourceID, action: .keepOpenAndNext)
        let beforeKeep = try context.work.store.workspaceWriter.currentRevision()
        let kept = try await context.access.executeRepetitiveCaptureStep(keep) {}
        XCTAssertNil(kept.progress.chain.nodes.last?.roundReceipt)
        XCTAssertEqual(kept.progress.chain.currentRound.items[1].disposition, .visited)
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision().revision, beforeKeep.revision + 1)
        let deferC = try await prepareActualCaptureStep(in: context, sourceDraftID: sourceID, action: .defer)
        let final = try await context.access.executeRepetitiveCaptureStep(deferC) {}
        try context.access.validateRepetitiveCaptureProgressForPublication(final)
        XCTAssertEqual(final.progress.chain.nodes.map { $0.step.action }, [.enter, .complete, .enter, .keepOpenAndNext, .defer])
        XCTAssertEqual(final.progress.chain.currentRound.items.map(\.itemID), active.items.map(\.itemID))
        XCTAssertEqual(final.progress.chain.currentRound.items.map(\.disposition), [.completed, .visited, .deferred])
        XCTAssertNil(final.progress.chain.nodes.last?.step.navigationItemID)
        XCTAssertEqual(final.progress.chain.nodes.compactMap(\.roundReceipt).count, 4)
        XCTAssertFalse(context.work.store.modelContext.hasChanges)
    }

    @MainActor
    func testActualCaptureSourceAcknowledgementRetryUsesExactCheckpointDespiteOldReadiness() async throws {
        #if DEBUG
        let fixture = try await makeFixture("capture-source-retry")
        defer { fixture.cleanUp() }
        let context = try await V23RoundRouteHarness.make(in: fixture, label: "capture-source-retry")
        let active = try await startActualRound(in: context, recorder: "Capture start")
        let readiness = try await context.access.rebuildReadiness(for: active, previous: nil)
        let launch = try context.access.prepareRepetitiveCaptureLaunch(round: active, readiness: readiness)
        context.access.setAfterRepetitiveCaptureSourceReceiptForTesting { throw CancellationError() }
        XCTAssertThrowsError(try context.access.persistRepetitiveCaptureLaunch(launch) {})
        context.access.setAfterRepetitiveCaptureSourceReceiptForTesting(nil)
        let afterWrite = try context.work.store.workspaceWriter.currentRevision()
        XCTAssertEqual(launch.attemptState, .checkpointWriteAttempted)
        XCTAssertThrowsError(try context.access.validateReadinessForPublication(readiness))
        let replay = try context.access.persistRepetitiveCaptureLaunch(launch) {}
        XCTAssertEqual(replay.chain.sourceCheckpoint, launch.checkpoint)
        XCTAssertEqual(replay.chain.currentRound, active)
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), afterWrite)
        XCTAssertThrowsError(try context.access.prepareRepetitiveCaptureStep(read: replay, readiness: readiness,
            action: .enter, focus: .facts, recordedByName: "Stale readiness"))
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), afterWrite)
        #endif
    }

    @MainActor
    func testActualCaptureStepAcknowledgementRetryAppliesTheStoredRoundMutationOnce() async throws {
        #if DEBUG
        let fixture = try await makeFixture("capture-step-retry")
        defer { fixture.cleanUp() }
        let context = try await V23RoundRouteHarness.make(in: fixture, label: "capture-step-retry")
        let active = try await startActualRound(in: context, recorder: "Capture start")
        let readiness = try await context.access.rebuildReadiness(for: active, previous: nil)
        let launch = try context.access.prepareRepetitiveCaptureLaunch(round: active, readiness: readiness)
        _ = try context.access.persistRepetitiveCaptureLaunch(launch) {}
        let step = try await prepareActualCaptureStep(in: context, sourceDraftID: launch.checkpoint.draftID, action: .enter)
        let before = try context.work.store.workspaceWriter.currentRevision()
        context.access.setAfterRepetitiveCaptureStepReceiptForTesting { throw CancellationError() }
        do { _ = try await context.access.executeRepetitiveCaptureStep(step) {}; XCTFail("Injected checkpoint acknowledgement must interrupt") }
        catch { XCTAssertTrue(error is CancellationError) }
        context.access.setAfterRepetitiveCaptureStepReceiptForTesting(nil)
        let checkpointOnly = try context.access.readRepetitiveCaptureProgress(sourceDraftID: launch.checkpoint.draftID)
        XCTAssertEqual(checkpointOnly.chain.currentRound, active)
        XCTAssertTrue(try XCTUnwrap(checkpointOnly.chain.nodes.last).isPendingRoundEffect)
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision().revision, before.revision + 1)
        let replay = try await context.access.executeRepetitiveCaptureStep(step) {}
        XCTAssertEqual(replay.progress.chain.nodes.count, 1)
        XCTAssertEqual(replay.progress.chain.nodes.first?.checkpoint, step.checkpoint)
        XCTAssertEqual(replay.progress.chain.currentRound.mutationID, step.step.roundMutation?.mutationID)
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision().revision, before.revision + 2)
        let settled = try context.work.store.workspaceWriter.currentRevision()
        let repeated = try await context.access.executeRepetitiveCaptureStep(step) {}
        XCTAssertEqual(repeated.progress.chain, replay.progress.chain)
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), settled)
        #endif
    }

    @MainActor
    func testActualCaptureRoundAcknowledgementRecoveryNeverDuplicatesItsCommittedEffect() async throws {
        #if DEBUG
        let fixture = try await makeFixture("capture-round-retry")
        defer { fixture.cleanUp() }
        let context = try await V23RoundRouteHarness.make(in: fixture, label: "capture-round-retry")
        let active = try await startActualRound(in: context, recorder: "Capture start")
        let readiness = try await context.access.rebuildReadiness(for: active, previous: nil)
        let launch = try context.access.prepareRepetitiveCaptureLaunch(round: active, readiness: readiness)
        _ = try context.access.persistRepetitiveCaptureLaunch(launch) {}
        let step = try await prepareActualCaptureStep(in: context, sourceDraftID: launch.checkpoint.draftID, action: .enter)
        context.access.setAfterSessionTransitionReceiptForTesting { throw CancellationError() }
        do { _ = try await context.access.executeRepetitiveCaptureStep(step) {}; XCTFail("Round acknowledgement must interrupt") }
        catch { XCTAssertTrue(error is CancellationError) }
        context.access.setAfterSessionTransitionReceiptForTesting(nil)
        let committed = try context.access.readRepetitiveCaptureProgress(sourceDraftID: launch.checkpoint.draftID)
        let beforeResume = try context.work.store.workspaceWriter.currentRevision()
        XCTAssertNotNil(committed.chain.nodes.last?.roundReceipt)
        let resumed = try await context.access.resumeRepetitiveCaptureProgress(sourceDraftID: launch.checkpoint.draftID,
            stepDraftID: step.checkpoint.draftID) {}
        XCTAssertEqual(resumed.progress.chain, committed.chain)
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), beforeResume)
        #endif
    }

    @MainActor
    func testActualCaptureCompletionDeniesMissingRecordAndAssetIDsBeforeCheckpoint() async throws {
        let fixture = try await makeFixture("capture-invalid-completion")
        defer { fixture.cleanUp() }
        let context = try await V23RoundRouteHarness.make(in: fixture, label: "capture-invalid-completion")
        let active = try await startActualRound(in: context, recorder: "Capture start")
        let readiness = try await context.access.rebuildReadiness(for: active, previous: nil)
        let launch = try context.access.prepareRepetitiveCaptureLaunch(round: active, readiness: readiness)
        _ = try context.access.persistRepetitiveCaptureLaunch(launch) {}
        let entry = try await prepareActualCaptureStep(in: context, sourceDraftID: launch.checkpoint.draftID, action: .enter)
        _ = try await context.access.executeRepetitiveCaptureStep(entry) {}
        let read = try context.access.readRepetitiveCaptureProgress(sourceDraftID: launch.checkpoint.draftID)
        let fresh = try await context.access.rebuildReadiness(for: read.chain.currentRound, previous: nil)
        let before = try context.work.store.workspaceWriter.currentRevision()
        for id in [UUID(), context.work.sign.assetID] {
            XCTAssertThrowsError(try context.access.prepareRepetitiveCaptureStep(read: read, readiness: fresh,
                action: .complete, focus: .review, completionRecordID: id, recordedByName: "Invalid completion"))
        }
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), before)
        XCTAssertEqual(try context.access.readRepetitiveCaptureProgress(sourceDraftID: launch.checkpoint.draftID).chain, read.chain)
        XCTAssertFalse(context.work.store.modelContext.hasChanges)
    }

    @MainActor
    func testActualCaptureCancelledStepDoesNotWriteCheckpointOrInvokeIntent() async throws {
        let fixture = try await makeFixture("capture-cancel")
        defer { fixture.cleanUp() }
        let context = try await V23RoundRouteHarness.make(in: fixture, label: "capture-cancel")
        let active = try await startActualRound(in: context, recorder: "Capture start")
        let readiness = try await context.access.rebuildReadiness(for: active, previous: nil)
        let launch = try context.access.prepareRepetitiveCaptureLaunch(round: active, readiness: readiness)
        _ = try context.access.persistRepetitiveCaptureLaunch(launch) {}
        let step = try await prepareActualCaptureStep(in: context, sourceDraftID: launch.checkpoint.draftID, action: .enter)
        let before = try context.work.store.workspaceWriter.currentRevision()
        var intentCalled = false
        let operation = Task { @MainActor in
            try await context.access.executeRepetitiveCaptureStep(step) { intentCalled = true }
        }
        operation.cancel()
        do { _ = try await operation.value; XCTFail("Cancelled caller must be denied") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(intentCalled)
        XCTAssertEqual(step.attemptState, .notAttempted)
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), before)
    }

    @MainActor
    func testActualCaptureCorruptFinalizedSnapshotDeniesCompletionBeforeCheckpoint() async throws {
        let fixture = try await makeFixture("capture-corrupt-completion")
        defer { fixture.cleanUp() }
        let context = try await V23RoundRouteHarness.make(in: fixture, label: "capture-corrupt-completion")
        let active = try await startActualRound(in: context, recorder: "Capture start")
        let readiness = try await context.access.rebuildReadiness(for: active, previous: nil)
        let launch = try context.access.prepareRepetitiveCaptureLaunch(round: active, readiness: readiness)
        _ = try context.access.persistRepetitiveCaptureLaunch(launch) {}
        let enter = try await prepareActualCaptureStep(in: context, sourceDraftID: launch.checkpoint.draftID, action: .enter)
        _ = try await context.access.executeRepetitiveCaptureStep(enter) {}
        let finalized = try await makeActualFinalizedCompletion(in: context, label: "capture-corrupt")
        let original = try Data(contentsOf: finalized.snapshotURL)
        defer { try? original.write(to: finalized.snapshotURL) }
        try Data("damaged actual completion snapshot".utf8).write(to: finalized.snapshotURL)
        let before = try context.work.store.workspaceWriter.currentRevision()
        do {
            _ = try await prepareActualCaptureStep(in: context, sourceDraftID: launch.checkpoint.draftID,
                action: .complete, completionRecordID: finalized.reference.completionID)
            XCTFail("Corrupt finalized content cannot authorize a progress checkpoint")
        } catch {}
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), before)
        XCTAssertEqual(try context.access.readRepetitiveCaptureProgress(sourceDraftID: launch.checkpoint.draftID).chain.nodes.count, 1)
        XCTAssertFalse(context.work.store.modelContext.hasChanges)
    }
}

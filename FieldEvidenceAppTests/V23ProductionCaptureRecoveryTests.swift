import Combine
import Foundation
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import FieldEvidenceApp

final class V23ProductionCaptureRecoveryTests: V23ProductionFourRootShellTestSupport {
    @MainActor
    func testActualCaptureRepublishedCapabilityReadsPendingHistoryWithoutEffectsThenExplicitlyResumes() async throws {
        #if DEBUG
        let fixture = try await makeFixture("capture-republish")
        defer { fixture.cleanUp() }
        let context = try await V23RoundRouteHarness.make(in: fixture, label: "capture-republish")
        let active = try await startActualRound(in: context, recorder: "Capture start")
        let readiness = try await context.access.rebuildReadiness(for: active, previous: nil)
        let launch = try context.access.prepareRepetitiveCaptureLaunch(round: active, readiness: readiness)
        _ = try context.access.persistRepetitiveCaptureLaunch(launch) {}
        let step = try await prepareActualCaptureStep(in: context, sourceDraftID: launch.checkpoint.draftID, action: .enter)
        context.access.setAfterRepetitiveCaptureStepReceiptForTesting { throw CancellationError() }
        do { _ = try await context.access.executeRepetitiveCaptureStep(step) {}; XCTFail("Checkpoint acknowledgement must interrupt") }
        catch { XCTAssertTrue(error is CancellationError) }
        context.access.setAfterRepetitiveCaptureStepReceiptForTesting(nil)
        let before = try context.work.store.workspaceWriter.currentRevision()
        fixture.presentation.receive(.sceneInactive)
        let republished = expectation(description: "Fresh publication after capture checkpoint")
        let observation = fixture.presentation.$permitsContentPresentation
            .filter { $0 }.prefix(1).sink { _ in republished.fulfill() }
        fixture.presentation.receive(.sceneActive)
        await fulfillment(of: [republished], timeout: 30)
        observation.cancel()
        let fresh = try XCTUnwrap(fixture.presentation.roundAccess)
        XCTAssertThrowsError(try context.access.readRepetitiveCaptureProgress(sourceDraftID: launch.checkpoint.draftID))
        let read = try fresh.readRepetitiveCaptureProgress(sourceDraftID: launch.checkpoint.draftID)
        XCTAssertEqual(read.chain.currentRound, active)
        XCTAssertEqual(read.chain.nodes.last?.checkpoint, step.checkpoint)
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), before)
        do { _ = try await fresh.executeRepetitiveCaptureStep(step) {}; XCTFail("Fresh owner must reject old prepared authority") }
        catch {}
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), before)
        let result = try await fresh.resumeRepetitiveCaptureProgress(sourceDraftID: launch.checkpoint.draftID,
            stepDraftID: step.checkpoint.draftID) {}
        try fresh.validateRepetitiveCaptureProgressForPublication(result)
        XCTAssertEqual(result.progress.chain.currentRound.mutationID, step.step.roundMutation?.mutationID)
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision().revision, before.revision + 1)
        XCTAssertThrowsError(try context.access.validateRepetitiveCaptureProgressForPublication(result))
        #endif
    }

    @MainActor
    func testActualCaptureKeepOpenRequiresFreshReadinessAfterItsCheckpointAndDeniesDrift() async throws {
        #if DEBUG
        let fixture = try await makeFixture("capture-keep-drift")
        defer { fixture.cleanUp() }
        let context = try await V23RoundRouteHarness.make(in: fixture, label: "capture-keep-drift")
        let active = try await startActualRound(in: context, recorder: "Capture start")
        let readiness = try await context.access.rebuildReadiness(for: active, previous: nil)
        let launch = try context.access.prepareRepetitiveCaptureLaunch(round: active, readiness: readiness)
        _ = try context.access.persistRepetitiveCaptureLaunch(launch) {}
        let enter = try await prepareActualCaptureStep(in: context, sourceDraftID: launch.checkpoint.draftID, action: .enter)
        let entered = try await context.access.executeRepetitiveCaptureStep(enter) {}
        let keep = try await prepareActualCaptureStep(in: context, sourceDraftID: launch.checkpoint.draftID, action: .keepOpenAndNext)
        XCTAssertNil(keep.step.roundMutation)
        var reachedReadiness = false
        context.access.setAfterRoundReadinessMaterializationForTesting {
            context.access.setAfterRoundReadinessMaterializationForTesting(nil)
            reachedReadiness = true
            _ = try context.work.workflow.checkRunner.beginCheck(assetID: context.work.sign.assetID,
                timeZoneID: "America/New_York", isTimeZoneConfirmed: true, afterDarkAccepted: true,
                safePositionAccepted: true, observedAt: self.roundTimestamp())
        }
        do { _ = try await context.access.executeRepetitiveCaptureStep(keep) {}; XCTFail("Post-readiness canonical drift must deny publication") }
        catch {}
        context.access.setAfterRoundReadinessMaterializationForTesting(nil)
        XCTAssertTrue(reachedReadiness)
        let retained = try context.access.readRepetitiveCaptureProgress(sourceDraftID: launch.checkpoint.draftID)
        XCTAssertEqual(retained.chain.currentRound, entered.progress.chain.currentRound)
        XCTAssertEqual(retained.chain.nodes.count, 2)
        XCTAssertEqual(retained.chain.nodes.last?.checkpoint, keep.checkpoint)
        XCTAssertNil(retained.chain.nodes.last?.roundReceipt)
        XCTAssertThrowsError(try context.access.validateRepetitiveCaptureProgressForPublication(entered))
        let beforeResume = try context.work.store.workspaceWriter.currentRevision()
        let resumed = try await context.access.resumeRepetitiveCaptureProgress(sourceDraftID: launch.checkpoint.draftID,
            stepDraftID: keep.checkpoint.draftID) {}
        try context.access.validateRepetitiveCaptureProgressForPublication(resumed)
        XCTAssertEqual(resumed.progress.chain, retained.chain)
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), beforeResume)
        #endif
    }

    @MainActor
    func testActualCaptureDiskColdReadIsEffectFreeAndExplicitResumeUsesStoredMutation() async throws {
        #if DEBUG
        let fixture = try await makeFixture("capture-disk-cold")
        var reopened: C36ActualCaptureReopenedAuthority?
        defer {
            try? reopened?.coordinator.invalidateAndReleaseWriter()
            fixture.cleanUp()
        }
        let context = try await V23RoundRouteHarness.make(in: fixture, label: "capture-disk-cold")
        let active = try await startActualRound(in: context, recorder: "Capture start")
        let readiness = try await context.access.rebuildReadiness(for: active, previous: nil)
        let launch = try context.access.prepareRepetitiveCaptureLaunch(round: active, readiness: readiness)
        _ = try context.access.persistRepetitiveCaptureLaunch(launch) {}
        let step = try await prepareActualCaptureStep(in: context,
            sourceDraftID: launch.checkpoint.draftID, action: .enter)
        context.access.setAfterRepetitiveCaptureStepReceiptForTesting { throw CancellationError() }
        do {
            _ = try await context.access.executeRepetitiveCaptureStep(step) {}
            XCTFail("Checkpoint acknowledgement must interrupt before the Round effect")
        } catch { XCTAssertTrue(error is CancellationError) }
        context.access.setAfterRepetitiveCaptureStepReceiptForTesting(nil)
        let hotRevision = try context.work.store.workspaceWriter.currentRevision()
        let storedMutation = try XCTUnwrap(step.step.roundMutation)
        fixture.presentation.receive(.sceneInactive)
        try fixture.coordinator.invalidateAndReleaseWriter()

        reopened = try await reopenActualCaptureAuthority(support: fixture.support, defaults: fixture.defaults)
        let cold = try XCTUnwrap(reopened)
        let coldAccess = try XCTUnwrap(cold.presentation.roundAccess)
        let beforeRead = try cold.coordinator.workspaceWriter.currentRevision()
        XCTAssertNotEqual(beforeRead.writerInstanceID, hotRevision.writerInstanceID)
        XCTAssertEqual(beforeRead.revision, hotRevision.revision)
        let read = try coldAccess.readRepetitiveCaptureProgress(sourceDraftID: launch.checkpoint.draftID)
        XCTAssertEqual(read.chain.currentRound, active)
        XCTAssertEqual(read.chain.nodes.last?.checkpoint, step.checkpoint)
        XCTAssertEqual(read.chain.nodes.last?.step.roundMutation, storedMutation)
        XCTAssertTrue(try XCTUnwrap(read.chain.nodes.last).isPendingRoundEffect)
        XCTAssertEqual(try cold.coordinator.workspaceWriter.currentRevision(), beforeRead)
        XCTAssertThrowsError(try context.access.readRepetitiveCaptureProgress(
            sourceDraftID: launch.checkpoint.draftID))
        do {
            _ = try await coldAccess.executeRepetitiveCaptureStep(step) {}
            XCTFail("A reopened service must reject the old prepared owner")
        } catch {}
        XCTAssertEqual(try cold.coordinator.workspaceWriter.currentRevision(), beforeRead)

        var intentCalled = false
        let resumed = try await coldAccess.resumeRepetitiveCaptureProgress(
            sourceDraftID: launch.checkpoint.draftID, stepDraftID: step.checkpoint.draftID
        ) { intentCalled = true }
        XCTAssertTrue(intentCalled)
        XCTAssertEqual(resumed.progress.chain.nodes.last?.checkpoint, step.checkpoint)
        XCTAssertEqual(resumed.progress.chain.nodes.last?.step.roundMutation, storedMutation)
        XCTAssertEqual(resumed.progress.chain.currentRound.mutationID, storedMutation.mutationID)
        XCTAssertNotNil(resumed.progress.chain.nodes.last?.roundReceipt)
        XCTAssertEqual(try cold.coordinator.workspaceWriter.currentRevision().revision, beforeRead.revision + 1)
        let settled = try cold.coordinator.workspaceWriter.currentRevision()
        let repeated = try await coldAccess.resumeRepetitiveCaptureProgress(
            sourceDraftID: launch.checkpoint.draftID, stepDraftID: step.checkpoint.draftID) {}
        XCTAssertEqual(repeated.progress.chain, resumed.progress.chain)
        XCTAssertEqual(try cold.coordinator.workspaceWriter.currentRevision(), settled)
        XCTAssertFalse(cold.coordinator.modelContext.hasChanges)
        #endif
    }

    @MainActor
    func testActualCaptureRoundAcknowledgementSamePreparedCommandAndExplicitResumeAreExact() async throws {
        #if DEBUG
        let fixture = try await makeFixture("capture-round-command-retry")
        defer { fixture.cleanUp() }
        let context = try await V23RoundRouteHarness.make(in: fixture, label: "capture-round-command-retry")
        let active = try await startActualRound(in: context, recorder: "Capture start")
        let readiness = try await context.access.rebuildReadiness(for: active, previous: nil)
        let launch = try context.access.prepareRepetitiveCaptureLaunch(round: active, readiness: readiness)
        _ = try context.access.persistRepetitiveCaptureLaunch(launch) {}
        let step = try await prepareActualCaptureStep(in: context,
            sourceDraftID: launch.checkpoint.draftID, action: .enter)
        context.access.setAfterSessionTransitionReceiptForTesting { throw CancellationError() }
        do {
            _ = try await context.access.executeRepetitiveCaptureStep(step) {}
            XCTFail("Round acknowledgement must interrupt after the committed effect")
        } catch { XCTAssertTrue(error is CancellationError) }
        context.access.setAfterSessionTransitionReceiptForTesting(nil)
        let committed = try context.access.readRepetitiveCaptureProgress(
            sourceDraftID: launch.checkpoint.draftID)
        let beforeRetry = try context.work.store.workspaceWriter.currentRevision()
        XCTAssertNotNil(committed.chain.nodes.last?.roundReceipt)
        XCTAssertEqual(committed.chain.currentRound.mutationID, step.step.roundMutation?.mutationID)

        var commandIntentCount = 0
        let commandRetry = try await context.access.executeRepetitiveCaptureStep(step) {
            commandIntentCount += 1
        }
        XCTAssertGreaterThan(commandIntentCount, 0)
        XCTAssertEqual(commandRetry.progress.chain, committed.chain)
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), beforeRetry)
        var resumeIntentCount = 0
        let explicitRetry = try await context.access.resumeRepetitiveCaptureProgress(
            sourceDraftID: launch.checkpoint.draftID, stepDraftID: step.checkpoint.draftID
        ) { resumeIntentCount += 1 }
        XCTAssertGreaterThan(resumeIntentCount, 0)
        XCTAssertEqual(explicitRetry.progress.chain.nodes.last?.checkpoint, step.checkpoint)
        XCTAssertEqual(explicitRetry.progress.chain, committed.chain)
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), beforeRetry)
        XCTAssertFalse(context.work.store.modelContext.hasChanges)
        #endif
    }

    @MainActor
    func testActualCaptureForeignOwnersAndCrossedSourceStepIDsHaveNoEffects() async throws {
        #if DEBUG
        let fixture = try await makeFixture("capture-hostile-a")
        let foreignFixture = try await makeFixture("capture-hostile-b")
        defer { fixture.cleanUp(); foreignFixture.cleanUp() }
        let context = try await V23RoundRouteHarness.make(in: fixture, label: "capture-hostile-a")
        let foreign = try await V23RoundRouteHarness.make(in: foreignFixture, label: "capture-hostile-b")
        let active = try await startActualRound(in: context, recorder: "Capture start")
        let readiness = try await context.access.rebuildReadiness(for: active, previous: nil)
        let launch = try context.access.prepareRepetitiveCaptureLaunch(round: active, readiness: readiness)
        XCTAssertNotEqual(context.work.store.workspaceID, foreign.work.store.workspaceID)
        let originalBefore = try context.work.store.workspaceWriter.currentRevision()
        let foreignBefore = try foreign.work.store.workspaceWriter.currentRevision()
        XCTAssertThrowsError(try foreign.access.persistRepetitiveCaptureLaunch(launch) {})
        XCTAssertThrowsError(try foreign.access.readRepetitiveCaptureProgress(
            sourceDraftID: launch.checkpoint.draftID))
        XCTAssertEqual(try foreign.work.store.workspaceWriter.currentRevision(), foreignBefore)
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), originalBefore)
        XCTAssertEqual(launch.attemptState, .notAttempted)

        _ = try context.access.persistRepetitiveCaptureLaunch(launch) {}
        let firstStep = try await prepareActualCaptureStep(in: context,
            sourceDraftID: launch.checkpoint.draftID, action: .enter)
        let originalBeforeStep = try context.work.store.workspaceWriter.currentRevision()
        let foreignBeforeStep = try foreign.work.store.workspaceWriter.currentRevision()
        do {
            _ = try await foreign.access.executeRepetitiveCaptureStep(firstStep) {}
            XCTFail("A foreign production owner must reject the prepared step")
        } catch {}
        XCTAssertEqual(try foreign.work.store.workspaceWriter.currentRevision(), foreignBeforeStep)
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), originalBeforeStep)
        XCTAssertEqual(firstStep.attemptState, .notAttempted)
        context.access.setAfterRepetitiveCaptureStepReceiptForTesting { throw CancellationError() }
        do {
            _ = try await context.access.executeRepetitiveCaptureStep(firstStep) {}
            XCTFail("First crossed-source checkpoint acknowledgement must interrupt")
        }
        catch { XCTAssertTrue(error is CancellationError) }
        context.access.setAfterRepetitiveCaptureStepReceiptForTesting(nil)

        let current = try context.access.readRepetitiveCaptureProgress(
            sourceDraftID: launch.checkpoint.draftID).chain.currentRound
        let secondReadiness = try await context.access.rebuildReadiness(for: current, previous: nil)
        let secondLaunch = try context.access.prepareRepetitiveCaptureLaunch(
            round: current, readiness: secondReadiness)
        _ = try context.access.persistRepetitiveCaptureLaunch(secondLaunch) {}
        let secondStep = try await prepareActualCaptureStep(in: context,
            sourceDraftID: secondLaunch.checkpoint.draftID, action: .enter)
        context.access.setAfterRepetitiveCaptureStepReceiptForTesting { throw CancellationError() }
        do {
            _ = try await context.access.executeRepetitiveCaptureStep(secondStep) {}
            XCTFail("Second crossed-source checkpoint acknowledgement must interrupt")
        }
        catch { XCTAssertTrue(error is CancellationError) }
        context.access.setAfterRepetitiveCaptureStepReceiptForTesting(nil)

        let beforeCrossed = try context.work.store.workspaceWriter.currentRevision()
        XCTAssertThrowsError(try context.access.readRepetitiveCaptureProgress(sourceDraftID: UUID()))
        do {
            _ = try await context.access.resumeRepetitiveCaptureProgress(
                sourceDraftID: launch.checkpoint.draftID,
                stepDraftID: secondStep.checkpoint.draftID) {}
            XCTFail("A step from another authenticated source must be rejected")
        } catch {}
        do {
            _ = try await context.access.resumeRepetitiveCaptureProgress(
                sourceDraftID: secondLaunch.checkpoint.draftID,
                stepDraftID: firstStep.checkpoint.draftID) {}
            XCTFail("A crossed source and step identity must be rejected")
        } catch {}
        do {
            _ = try await context.access.resumeRepetitiveCaptureProgress(
                sourceDraftID: UUID(), stepDraftID: firstStep.checkpoint.draftID) {}
            XCTFail("An unknown source identity must be rejected")
        } catch {}
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), beforeCrossed)
        let firstPending = try context.access.readRepetitiveCaptureProgress(
            sourceDraftID: launch.checkpoint.draftID)
        let secondPending = try context.access.readRepetitiveCaptureProgress(
            sourceDraftID: secondLaunch.checkpoint.draftID)
        XCTAssertTrue(try XCTUnwrap(firstPending.chain.nodes.last).isPendingRoundEffect)
        XCTAssertTrue(try XCTUnwrap(secondPending.chain.nodes.last).isPendingRoundEffect)
        XCTAssertEqual(firstPending.chain.currentRound, active)
        XCTAssertEqual(secondPending.chain.currentRound, active)
        XCTAssertFalse(context.work.store.modelContext.hasChanges)
        XCTAssertFalse(foreign.work.store.modelContext.hasChanges)
        #endif
    }

    @MainActor
    func testActualCaptureTaskCancellationAfterCheckpointRetainsPendingEffectForExplicitResume() async throws {
        #if DEBUG
        let fixture = try await makeFixture("capture-cancel-after-checkpoint")
        defer { fixture.cleanUp() }
        let context = try await V23RoundRouteHarness.make(in: fixture, label: "capture-cancel-after-checkpoint")
        let active = try await startActualRound(in: context, recorder: "Capture start")
        let readiness = try await context.access.rebuildReadiness(for: active, previous: nil)
        let launch = try context.access.prepareRepetitiveCaptureLaunch(round: active, readiness: readiness)
        _ = try context.access.persistRepetitiveCaptureLaunch(launch) {}
        let step = try await prepareActualCaptureStep(in: context, sourceDraftID: launch.checkpoint.draftID, action: .enter)
        let before = try context.work.store.workspaceWriter.currentRevision()
        var reachedCheckpoint = false
        context.access.setAfterRepetitiveCaptureStepReceiptForTesting {
            reachedCheckpoint = true
            withUnsafeCurrentTask { $0?.cancel() }
        }
        let operation = Task { @MainActor in
            try await context.access.executeRepetitiveCaptureStep(step) {}
        }
        do { _ = try await operation.value; XCTFail("Actual task cancellation must stop before the Round effect") }
        catch { XCTAssertTrue(error is CancellationError) }
        context.access.setAfterRepetitiveCaptureStepReceiptForTesting(nil)
        XCTAssertTrue(reachedCheckpoint)
        XCTAssertTrue(operation.isCancelled)
        let pending = try context.access.readRepetitiveCaptureProgress(sourceDraftID: launch.checkpoint.draftID)
        XCTAssertEqual(pending.chain.currentRound, active)
        XCTAssertEqual(pending.chain.nodes.last?.checkpoint, step.checkpoint)
        XCTAssertTrue(try XCTUnwrap(pending.chain.nodes.last).isPendingRoundEffect)
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision().revision, before.revision + 1)
        let resumed = try await context.access.resumeRepetitiveCaptureProgress(sourceDraftID: launch.checkpoint.draftID,
            stepDraftID: step.checkpoint.draftID) {}
        XCTAssertEqual(resumed.progress.chain.currentRound.mutationID, step.step.roundMutation?.mutationID)
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision().revision, before.revision + 2)
        XCTAssertFalse(context.work.store.modelContext.hasChanges)
        #endif
    }

    @MainActor
    func testActualCaptureOriginalSceneABAAfterCheckpointDeniesEffectAndFreshIntentRetriesSameStep() async throws {
        #if DEBUG
        let fixture = try await makeFixture("capture-scene-aba-after-checkpoint")
        defer { fixture.cleanUp() }
        let context = try await V23RoundRouteHarness.make(in: fixture, label: "capture-scene-aba-after-checkpoint")
        let active = try await startActualRound(in: context, recorder: "Capture start")
        let target = try context.target(for: active)
        try context.work.scene.open(target)
        let captured = try XCTUnwrap(context.work.scene.snapshot)
        let readiness = try await context.access.rebuildReadiness(for: active, previous: nil)
        let launch = try context.access.prepareRepetitiveCaptureLaunch(round: active, readiness: readiness)
        _ = try context.access.persistRepetitiveCaptureLaunch(launch) {
            try context.work.scene.validatePersistedIntent(target, expectedSnapshot: captured)
        }
        let step = try await prepareActualCaptureStep(in: context, sourceDraftID: launch.checkpoint.draftID, action: .enter)
        let before = try context.work.store.workspaceWriter.currentRevision()
        var reachedCheckpoint = false
        context.access.setAfterRepetitiveCaptureStepReceiptForTesting {
            reachedCheckpoint = true
            try context.work.scene.open(context.work.target(expectedRevision: nil))
            try context.work.scene.open(target)
        }
        do {
            _ = try await context.access.executeRepetitiveCaptureStep(step) {
                try context.work.scene.validatePersistedIntent(target, expectedSnapshot: captured)
            }
            XCTFail("Returning to the same visible path cannot revive the original scene intent")
        } catch {}
        context.access.setAfterRepetitiveCaptureStepReceiptForTesting(nil)
        XCTAssertTrue(reachedCheckpoint)
        XCTAssertEqual(context.work.scene.snapshot?.path(for: .work)?.targets, [target])
        let pending = try context.access.readRepetitiveCaptureProgress(sourceDraftID: launch.checkpoint.draftID)
        XCTAssertEqual(pending.chain.currentRound, active)
        XCTAssertEqual(pending.chain.nodes.last?.checkpoint, step.checkpoint)
        XCTAssertTrue(try XCTUnwrap(pending.chain.nodes.last).isPendingRoundEffect)
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision().revision, before.revision + 1)
        let fresh = try XCTUnwrap(context.work.scene.snapshot)
        let resumed = try await context.access.executeRepetitiveCaptureStep(step) {
            try context.work.scene.validatePersistedIntent(target, expectedSnapshot: fresh)
        }
        XCTAssertEqual(resumed.progress.chain.nodes.last?.checkpoint, step.checkpoint)
        XCTAssertEqual(resumed.progress.chain.currentRound.mutationID, step.step.roundMutation?.mutationID)
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision().revision, before.revision + 2)
        XCTAssertFalse(context.work.store.modelContext.hasChanges)
        #endif
    }
}

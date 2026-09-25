import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

private enum CompletionInjectedFailure: Error, Equatable {
    case lostAcknowledgement
}

/// Stage B1 of the C36 Round item host: explicit finish, defer and keep-open
/// from the durable host. Each Round step is receipt-backed; a lost
/// acknowledgement resumes the original finalization and step exactly once.
final class V23ProductionRoundItemCompletionTests: V23ProductionFourRootShellTestSupport {
    @MainActor
    func testCouldNotVerifyFinishRecordsOneReportAndOneCompleteThenShowsNextItem() async throws {
        let fixture = try await makeFixture("round-item-complete-cnv")
        defer { fixture.cleanUp() }
        let seed = try await V23RoundRouteHarness.make(in: fixture, label: "round-item-complete-cnv")
        let context = try await seed.addingDraftItems(1)
        let active = try await startActualRound(in: context, recorder: "Completion start")
        let ordered = active.items.sorted { $0.order < $1.order }
        let target = try context.target(for: active, mode: .resume)
        try context.work.scene.open(target)
        let (state, host) = try await openBegunItem(in: context, itemID: ordered[0].itemID, target: target)
        XCTAssertEqual(host.stage, .capture(.wide))
        try chooseCouldNotVerify(host)

        let review = try await host.readReview()
        XCTAssertNotNil(review.couldNotVerifyReasonDisplay)
        XCTAssertNil(review.wideEvidence)
        XCTAssertNil(review.closeEvidence)
        let beforeFinish = try context.work.store.workspaceWriter.currentRevision()
        let result = try await host.finish(recordedByName: "Completion recorder",
            sourceApp: SourceAppSnapshotV1(build: "round-complete", version: "1.0"))
        XCTAssertEqual(host.stage, .completed)
        XCTAssertNil(host.editor)
        let committed = try XCTUnwrap(host.checkpoint)
        let attempt = try XCTUnwrap(CheckRunnerItemDraftCodecV1.validateCheckpoint(committed).finalizationAttempt)
        let mutationID = try MutationIDV1(rawValue: attempt.identifiers.mutationID)
        let receipt = try XCTUnwrap(context.work.store.workspaceWriter.durableReceipt(mutationID: mutationID))
        let chain = result.progress.chain
        XCTAssertEqual(chain.nodes.map { $0.step.action }, [.enter, .complete])
        XCTAssertFalse(try XCTUnwrap(chain.nodes.last).isPendingRoundEffect)
        XCTAssertEqual(chain.nodes.last?.step.navigationItemID, ordered[1].itemID)
        XCTAssertEqual(chain.currentRound.items.first { $0.itemID == ordered[0].itemID }?.disposition, .completed)
        XCTAssertGreaterThan(try context.work.store.workspaceWriter.currentRevision().revision, beforeFinish.revision)

        state.acceptCaptureProgress(result)
        XCTAssertNil(state.captureHost)
        XCTAssertEqual(state.session, chain.currentRound)
        XCTAssertFalse(state.couldNotLoad)
        // The finished item is terminal and never reopens or refinalizes.
        let afterAccept = try context.work.store.workspaceWriter.currentRevision()
        state.requestCapture(itemID: ordered[0].itemID)
        XCTAssertNil(state.captureIntent)
        XCTAssertEqual(try context.work.store.workspaceWriter.durableReceipt(mutationID: mutationID), receipt)
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), afterAccept)
        await host.retire()
    }

    @MainActor
    func testLostFinalizationAndCompleteAcknowledgementsResumeOriginalsOnce() async throws {
        let fixture = try await makeFixture("round-item-complete-recovery")
        defer { fixture.cleanUp() }
        let seed = try await V23RoundRouteHarness.make(in: fixture, label: "round-item-complete-recovery")
        let context = try await seed.addingDraftItems(1)
        let active = try await startActualRound(in: context, recorder: "Recovery start")
        let ordered = active.items.sorted { $0.order < $1.order }
        let target = try context.target(for: active, mode: .resume)
        try context.work.scene.open(target)
        let (state, host) = try await openBegunItem(in: context, itemID: ordered[0].itemID, target: target)
        try chooseCouldNotVerify(host)
        let sourceApp = SourceAppSnapshotV1(build: "round-complete-recovery", version: "1.0")

        // The canonical report publishes, then its parent acknowledgement is lost.
        host.service.beforeParentTargetAcknowledgementForTesting = { throw CompletionInjectedFailure.lostAcknowledgement }
        do {
            _ = try await host.finish(recordedByName: "Recovery recorder", sourceApp: sourceApp)
            XCTFail("The finalizer must reach the lost acknowledgement boundary")
        } catch {
            XCTAssertEqual(error as? CompletionInjectedFailure, .lostAcknowledgement)
        }
        host.service.beforeParentTargetAcknowledgementForTesting = nil
        XCTAssertEqual(host.stage, .preparedFinalization)
        XCTAssertNil(host.editor)
        let prepared = try XCTUnwrap(host.checkpoint)
        let attempt = try XCTUnwrap(CheckRunnerItemDraftCodecV1.validateCheckpoint(prepared).finalizationAttempt)
        let mutationID = try MutationIDV1(rawValue: attempt.identifiers.mutationID)
        let receipt = try XCTUnwrap(context.work.store.workspaceWriter.durableReceipt(mutationID: mutationID))
        let sourceDraftID = host.source.sourceCheckpoint.draftID
        XCTAssertEqual(try context.access.readRepetitiveCaptureProgress(sourceDraftID: sourceDraftID)
            .chain.nodes.map { $0.step.action }, [.enter])

        // COMPLETE's step saves, then its acknowledgement is lost before the Round effect.
        context.access.setAfterRepetitiveCaptureStepReceiptForTesting {
            throw CompletionInjectedFailure.lostAcknowledgement
        }
        do {
            _ = try await host.finish(recordedByName: "Recovery recorder", sourceApp: sourceApp)
            XCTFail("The COMPLETE step must reach its lost acknowledgement boundary")
        } catch {
            XCTAssertEqual(error as? CompletionInjectedFailure, .lostAcknowledgement)
        }
        context.access.setAfterRepetitiveCaptureStepReceiptForTesting(nil)
        XCTAssertEqual(host.stage, .completed)
        let pending = try context.access.readRepetitiveCaptureProgress(sourceDraftID: sourceDraftID).chain
        XCTAssertEqual(pending.nodes.map { $0.step.action }, [.enter, .complete])
        XCTAssertTrue(try XCTUnwrap(pending.nodes.last).isPendingRoundEffect)
        XCTAssertEqual(try context.work.store.workspaceWriter.durableReceipt(mutationID: mutationID), receipt)

        // Explicit recovery settles the original step; nothing is refinalized.
        let result = try await host.finish(recordedByName: "Recovery recorder", sourceApp: sourceApp)
        let chain = result.progress.chain
        XCTAssertEqual(chain.nodes.map { $0.step.action }, [.enter, .complete])
        XCTAssertEqual(chain.nodes.last?.checkpoint.draftID, pending.nodes.last?.checkpoint.draftID)
        XCTAssertFalse(try XCTUnwrap(chain.nodes.last).isPendingRoundEffect)
        XCTAssertEqual(chain.currentRound.items.first { $0.itemID == ordered[0].itemID }?.disposition, .completed)
        XCTAssertEqual(try context.work.store.workspaceWriter.durableReceipt(mutationID: mutationID), receipt)
        let settled = try context.work.store.workspaceWriter.currentRevision()
        let replay = try await host.finish(recordedByName: "Recovery recorder", sourceApp: sourceApp)
        XCTAssertEqual(replay.progress.chain, chain)
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), settled)
        state.acceptCaptureProgress(replay)
        XCTAssertEqual(state.session, chain.currentRound)
        await host.retire()
    }

    @MainActor
    func testDeferAndKeepOpenRetainParentsAndAdvanceOnce() async throws {
        let fixture = try await makeFixture("round-item-advance")
        defer { fixture.cleanUp() }
        let seed = try await V23RoundRouteHarness.make(in: fixture, label: "round-item-advance")
        let context = try await seed.addingDraftItems(2)
        let active = try await startActualRound(in: context, recorder: "Advance start")
        let ordered = active.items.sorted { $0.order < $1.order }
        let target = try context.target(for: active, mode: .resume)
        try context.work.scene.open(target)

        let (state, first) = try await openBegunItem(in: context, itemID: ordered[0].itemID, target: target)
        let firstParent = try XCTUnwrap(first.checkpoint)
        let deferred = try await first.advance(.defer, recordedByName: "Advance recorder")
        XCTAssertEqual(deferred.progress.chain.nodes.map { $0.step.action }, [.enter, .defer])
        XCTAssertEqual(deferred.progress.chain.nodes.last?.step.navigationItemID, ordered[1].itemID)
        XCTAssertEqual(deferred.progress.chain.currentRound.items.first { $0.itemID == ordered[0].itemID }?.disposition,
                       .deferred)
        // The deferred item's durable parent is retained, not discarded or finalized.
        let retained = try XCTUnwrap(first.service.readCurrentDraft(source: first.source))
        XCTAssertEqual(retained.draftID, firstParent.draftID)
        XCTAssertEqual(retained.state, .active)
        state.acceptCaptureProgress(deferred)
        XCTAssertNil(state.captureHost)
        XCTAssertEqual(state.session, deferred.progress.chain.currentRound)
        await first.retire()

        let (_, second) = try await openBegunItem(in: context, itemID: ordered[1].itemID, target: target,
                                                  state: state)
        let kept = try await second.advance(.keepOpenAndNext, recordedByName: "Advance recorder")
        let chain = kept.progress.chain
        XCTAssertEqual(chain.nodes.map { $0.step.action }, [.enter, .defer, .enter, .keepOpenAndNext])
        XCTAssertEqual(chain.nodes.last?.step.navigationItemID, ordered[2].itemID)
        XCTAssertEqual(chain.currentRound.items.first { $0.itemID == ordered[1].itemID }?.disposition, .visited)
        XCTAssertEqual(try second.service.readCurrentDraft(source: second.source)?.state, .active)
        // A repeated request reuses the saved step instead of writing another.
        let afterKeep = try context.work.store.workspaceWriter.currentRevision()
        let replay = try await second.advance(.keepOpenAndNext, recordedByName: "Advance recorder")
        XCTAssertEqual(replay.progress.chain, chain)
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), afterKeep)
        state.acceptCaptureProgress(kept)
        XCTAssertEqual(state.session, chain.currentRound)
        await second.retire()
    }

    @MainActor
    func testRetiredSceneDeniesFinishAndAdvanceWithoutEffects() async throws {
        let fixture = try await makeFixture("round-item-complete-retired")
        defer { fixture.cleanUp() }
        let context = try await V23RoundRouteHarness.make(in: fixture, label: "round-item-complete-retired")
        let active = try await startActualRound(in: context, recorder: "Retired start")
        let item = try XCTUnwrap(active.items.first)
        let target = try context.target(for: active, mode: .resume)
        try context.work.scene.open(target)
        let (_, host) = try await openBegunItem(in: context, itemID: item.itemID, target: target)
        try chooseCouldNotVerify(host)
        try await host.flushAndPerform(reason: .back) { }
        let saved = try XCTUnwrap(host.checkpoint)
        let sourceDraftID = host.source.sourceCheckpoint.draftID
        let chain = try context.access.readRepetitiveCaptureProgress(sourceDraftID: sourceDraftID).chain
        let before = try context.work.store.workspaceWriter.currentRevision()

        try context.work.scene.select(.reports)
        do {
            _ = try await host.finish(recordedByName: "Retired recorder",
                sourceApp: SourceAppSnapshotV1(build: "retired", version: "1.0"))
            XCTFail("A retired scene must not flush, finalize or complete")
        } catch { }
        do {
            _ = try await host.advance(.defer, recordedByName: "Retired recorder")
            XCTFail("A retired scene must not record a Round step")
        } catch { }
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), before)
        XCTAssertEqual(try context.access.readRepetitiveCaptureProgress(sourceDraftID: sourceDraftID).chain, chain)
        XCTAssertEqual(try host.service.readCurrentDraft(source: host.source), saved)
        XCTAssertEqual(try CheckRunnerItemDraftCodecV1.validateCheckpoint(saved).phase, .editing)
        await host.retire()
    }

    @MainActor
    func testTwoPhotoJourneyCommitsEachSlotOnceRecoversAndFinishes() async throws {
        let fixture = try await makeFixture("round-item-photos")
        defer { fixture.cleanUp() }
        let seed = try await V23RoundRouteHarness.make(in: fixture, label: "round-item-photos")
        let context = try await seed.addingDraftItems(1)
        let active = try await startActualRound(in: context, recorder: "Photo start")
        let ordered = active.items.sorted { $0.order < $1.order }
        let target = try context.target(for: active, mode: .resume)
        try context.work.scene.open(target)
        let (state, host) = try await openBegunItem(in: context, itemID: ordered[0].itemID, target: target)
        XCTAssertEqual(host.stage, .capture(.wide))
        XCTAssertEqual(host.capturePreparation?.step, .wide)

        // Selection stages only through the normalized pair; nothing commits.
        let wide = try WorkCanonicalIntegrationTestSupportV1.makePNG(seed: 211)
        try await host.stagePhoto(wide, origin: .localImport)
        XCTAssertEqual(host.stage, .pendingPhoto(.wide))
        guard case .pairReady? = host.pendingPhoto?.phase else {
            return XCTFail("Selection must stop at the normalized pair")
        }
        XCTAssertEqual(host.selectedPhotoPreview, wide)

        // The target publishes, then its acknowledgement is lost; Use Photo
        // resumes the one saved attempt instead of freezing another.
        host.service.beforePhotoTargetAcknowledgementForTesting = {
            throw CompletionInjectedFailure.lostAcknowledgement
        }
        do {
            try await host.usePhoto()
            XCTFail("The photo commit must reach its lost acknowledgement boundary")
        } catch {
            XCTAssertEqual(error as? CompletionInjectedFailure, .lostAcknowledgement)
        }
        host.service.beforePhotoTargetAcknowledgementForTesting = nil
        XCTAssertEqual(host.stage, .pendingPhoto(.wide))
        guard case let .preparedCommit(_, attempt)? = host.pendingPhoto?.phase else {
            return XCTFail("Expected the saved commit attempt")
        }
        try await host.usePhoto()
        XCTAssertEqual(host.stage, .capture(.close))
        let adopted = try CheckRunnerItemDraftCodecV1.validateCheckpoint(try XCTUnwrap(host.checkpoint))
        guard case let .committed(_, _, _, _, _, _, _, _, targetMutationID, _)? = adopted.field.wideContext else {
            return XCTFail("The wide slot must adopt its committed child")
        }
        XCTAssertEqual(targetMutationID, attempt.targetMutationID)

        // A cold reopen at the saved close pair offers Use Photo without a
        // preview, the camera or any write.
        let close = try WorkCanonicalIntegrationTestSupportV1.makePNG(seed: 212)
        try await host.stagePhoto(close, origin: .humanCapture)
        XCTAssertEqual(host.stage, .pendingPhoto(.close))
        state.dismissCapture()
        await host.retire()
        let afterStage = try context.work.store.workspaceWriter.currentRevision()
        let reopened = ProductionRoundSessionPresentationV1(target: target,
            scene: context.work.scene, access: context.access)
        await reopened.refresh()
        reopened.requestCapture(itemID: ordered[0].itemID)
        let reopenedOpen = await reopened.confirmCapture(recordedByName: "Photo recorder")
        XCTAssertTrue(reopenedOpen)
        let resumed = try XCTUnwrap(reopened.captureHost)
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), afterStage)
        XCTAssertEqual(resumed.stage, .pendingPhoto(.close))
        XCTAssertNil(resumed.selectedPhotoPreview)
        try await resumed.usePhoto()
        XCTAssertEqual(resumed.stage, .outcome(photosIncomplete: false))

        // Outcome, review over both committed photos, and one finish.
        let editor = try XCTUnwrap(resumed.editor)
        var outcome = editor.values.outcome
        outcome.selectNoVisibleIssue()
        try resumed.replaceEditableValues(.init(preflight: editor.values.preflight, outcome: outcome,
            semanticAnchor: editor.values.semanticAnchor))
        let review = try await resumed.readReview()
        XCTAssertNotNil(review.wideEvidence)
        XCTAssertNotNil(review.closeEvidence)
        XCTAssertTrue(review.missingPurposeDisplays.isEmpty)
        let result = try await resumed.finish(recordedByName: "Photo recorder",
            sourceApp: SourceAppSnapshotV1(build: "round-photos", version: "1.0"))
        XCTAssertEqual(resumed.stage, .completed)
        XCTAssertEqual(result.progress.chain.nodes.map { $0.step.action }, [.enter, .complete])
        XCTAssertEqual(result.progress.chain.currentRound.items.first { $0.itemID == ordered[0].itemID }?.disposition,
                       .completed)
        reopened.acceptCaptureProgress(result)
        XCTAssertEqual(reopened.session, result.progress.chain.currentRound)
        await resumed.retire()
    }

    /// Audited original36075174540: every Round readiness rebuild rejected at
    /// storage publication because free bytes drifted by a few kilobytes.
    func testStoragePublicationAcceptsFreeByteDriftOnlyWithTheSameVerdict() throws {
        let required: Int64 = 1_000
        let recorded = try OfflineReadinessStorageObservationV1(capacityState: .checked, availableBytes: 5_000,
            reservedBytes: 10, operationReserveBytes: 20)
        func observed(_ available: Int64?, reserved: Int64 = 10, operation: Int64 = 20) throws
            -> OfflineReadinessStorageObservationV1 {
            try .init(capacityState: available == nil ? .unavailable : .checked, availableBytes: available,
                      reservedBytes: reserved, operationReserveBytes: operation)
        }
        XCTAssertTrue(try observed(5_000).supportsPublication(ofRecorded: recorded, requiredBytes: required))
        XCTAssertTrue(try observed(4_321).supportsPublication(ofRecorded: recorded, requiredBytes: required))
        XCTAssertTrue(try observed(1_000).supportsPublication(ofRecorded: recorded, requiredBytes: required))
        // Any change in the storage verdict, reservations or capacity state rejects.
        XCTAssertFalse(try observed(999).supportsPublication(ofRecorded: recorded, requiredBytes: required))
        XCTAssertFalse(try observed(5_000, reserved: 11).supportsPublication(ofRecorded: recorded, requiredBytes: required))
        XCTAssertFalse(try observed(5_000, operation: 21).supportsPublication(ofRecorded: recorded, requiredBytes: required))
        XCTAssertFalse(try observed(nil).supportsPublication(ofRecorded: recorded, requiredBytes: required))
        let insufficient = try observed(500)
        XCTAssertTrue(try observed(700).supportsPublication(ofRecorded: insufficient, requiredBytes: required))
        XCTAssertFalse(try observed(1_500).supportsPublication(ofRecorded: insufficient, requiredBytes: required))
        // Without a computable requirement only the exact observation is accepted.
        XCTAssertTrue(try observed(5_000).supportsPublication(ofRecorded: recorded, requiredBytes: nil))
        XCTAssertFalse(try observed(4_999).supportsPublication(ofRecorded: recorded, requiredBytes: nil))
        let unavailable = try observed(nil)
        XCTAssertTrue(try observed(nil).supportsPublication(ofRecorded: unavailable, requiredBytes: required))
    }

    // MARK: Helpers

    @MainActor
    private func openBegunItem(in context: V23RoundRouteHarness, itemID: UUID, target: NavigationTargetV1,
                               state existing: ProductionRoundSessionPresentationV1? = nil) async throws
        -> (ProductionRoundSessionPresentationV1, ProductionCheckRunnerItemCapturePresentationV1) {
        let state: ProductionRoundSessionPresentationV1
        if let existing {
            state = existing
        } else {
            state = ProductionRoundSessionPresentationV1(target: target,
                scene: context.work.scene, access: context.access)
            await state.refresh()
        }
        state.requestCapture(itemID: itemID)
        let opened = await state.confirmCapture(recordedByName: "Completion recorder")
        XCTAssertTrue(opened)
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
        try await host.begin(observedAtUTC: roundTimestamp())
        XCTAssertTrue(host.hasBoundBegin)
        XCTAssertNotNil(host.editor)
        return (state, host)
    }

    @MainActor
    private func chooseCouldNotVerify(_ host: ProductionCheckRunnerItemCapturePresentationV1) throws {
        try host.openCouldNotVerify()
        XCTAssertEqual(host.stage, .outcome(photosIncomplete: true))
        let presentation = try XCTUnwrap(host.outcomePresentation)
        let reason = try XCTUnwrap(presentation.couldNotVerifyReasons.first { $0.key == "conditions_changed" }
            ?? presentation.couldNotVerifyReasons.first)
        let editor = try XCTUnwrap(host.editor)
        var outcome = editor.values.outcome
        outcome.selectCouldNotVerifyReason(key: reason.key)
        try host.replaceEditableValues(.init(preflight: editor.values.preflight, outcome: outcome,
            semanticAnchor: editor.values.semanticAnchor))
        XCTAssertNotNil(host.editor?.values.outcome.selection)
    }
}

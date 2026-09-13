import Combine
import Foundation
import SwiftData
import SwiftUI
import UIKit
import XCTest

@testable import FieldEvidenceApp

final class V23MyDayPlanningEditorTests: XCTestCase {
    @MainActor
    func testExplicitContextCaptureAndCheckpointEnumerationUseExactDayWithoutWriting() async throws {
        let fixture = try await makeFixture("editor-context")
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let writer = fixture.coordinator.workspaceWriter
        let key = try day(fixture)
        let before = try writer.currentRevision()
        XCTAssertTrue(try access.planningCheckpoints(for: key).isEmpty)
        let context = try access.captureConfirmedPlanningContext(for: key, recordedByName: "Field recorder")
        XCTAssertEqual(context.key, key)
        XCTAssertEqual(context.recordedBy.displayNameAtTime, "Field recorder")
        XCTAssertEqual(context.recordedBy.responsibility, .recordedBy)
        XCTAssertTrue(context.keyWasExplicitlyConfirmed)
        XCTAssertTrue(context.recordedByWasExplicitlySelectedOrCaptured)
        XCTAssertNotEqual(context.recordedBy.snapshotID, context.recordedBy.actor.actorReferenceID)
        try MyDayLimitsV1.millisecondInstant(context.recordedBy.capturedAt)
        XCTAssertThrowsError(try access.captureConfirmedPlanningContext(for: key, recordedByName: ""))
        let foreign = try MyDayKeyV1(workspaceID: .init(rawValue: UUID()),
            civilDate: key.civilDate, ianaTimeZoneIdentifier: key.ianaTimeZoneIdentifier)
        XCTAssertThrowsError(try access.captureConfirmedPlanningContext(for: foreign, recordedByName: "Recorder"))
        XCTAssertThrowsError(try access.planningCheckpoints(for: foreign))
        let firstMembership = try access.nextPlanningMembershipID()
        let secondMembership = try access.nextPlanningMembershipID()
        XCTAssertNotEqual(firstMembership, secondMembership)
        XCTAssertEqual(try writer.currentRevision(), before)
        XCTAssertEqual(try count(ActorSnapshotRow.self, fixture), 0)
        XCTAssertEqual(try count(FieldDraftCheckpointRow.self, fixture), 0)

        let request = try MyDayPlanningPlanSaveRequestV1(confirmedContext: context,
            draft: .init(key: key, items: [], eligibleReferences: []), predecessor: nil)
        let write = try access.prepareEditingWrite(request, replacing: nil,
                                                   resumeAnchor: .init(sectionID: "my-day"))
        let acknowledgement = try access.persistEditingWrite(write)
        let afterWrite = try writer.currentRevision()
        XCTAssertEqual(try access.planningCheckpoints(for: key), [acknowledgement.checkpoint])
        let neighbor = try MyDayKeyV1(workspaceID: key.workspaceID, civilDate: .init("2026-09-13"),
            ianaTimeZoneIdentifier: key.ianaTimeZoneIdentifier)
        XCTAssertTrue(try access.planningCheckpoints(for: neighbor).isEmpty)
        XCTAssertEqual(try writer.currentRevision(), afterWrite)
        let outcome = try await access.retryPlanSave(draftID: write.checkpoint.draftID)
        XCTAssertEqual(outcome.checkpoint.state, .committed)
        XCTAssertTrue(try access.planningCheckpoints(for: key).isEmpty)
        XCTAssertEqual(try access.loadPlanningCheckpoint(draftID: write.checkpoint.draftID), outcome.checkpoint)
        XCTAssertFalse(fixture.coordinator.modelContext.hasChanges)
    }

    @MainActor
    func testTodayEditorAddsOrdersEstimatesRemovesAndSavesWithoutChangingSourceWork() async throws {
        let fixture = try await makeFixture("editor-work")
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let first = try seedSource(fixture)
        let second = try seedSource(fixture)
        let sourceState = ProductionMyDaySourceStateV1(workspaceID: fixture.coordinator.workspaceID, access: access)
        let editor = try sourceState.makePlanningEditor()
        let beforeOpen = try fixture.coordinator.workspaceWriter.currentRevision()
        let opened = await editor.openDay(civilDate: "2026-09-12", timeZone: "America/New_York")
        XCTAssertTrue(opened)
        XCTAssertNil(editor.editingSession)
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), beforeOpen)
        let began = await editor.beginNew(recordedByName: "Field recorder")
        XCTAssertTrue(began)
        let session = try XCTUnwrap(editor.editingSession)
        let changedDay = await editor.openDay(civilDate: "2026-09-13", timeZone: "America/New_York")
        XCTAssertFalse(changedDay)
        XCTAssertTrue(editor.editingSession === session)
        XCTAssertEqual(session.request.confirmedContext.key.civilDate.canonicalString, "2026-09-12")
        let addedFirst = await editor.add(reference(first))
        XCTAssertTrue(addedFirst)
        let firstMembership = try XCTUnwrap(session.request.draft.items.first?.membershipID)
        let addedSecond = await editor.add(reference(second))
        XCTAssertTrue(addedSecond)
        let secondMembership = try XCTUnwrap(session.request.draft.items.last?.membershipID)
        let estimated = await editor.estimate(membershipID: firstMembership, wholeMinutes: 30)
        XCTAssertTrue(estimated)
        let moved = await editor.move(.up(membershipID: secondMembership))
        XCTAssertTrue(moved)
        XCTAssertEqual(session.request.draft.items.map(\.membershipID), [secondMembership, firstMembership])
        let removed = await editor.remove(membershipID: firstMembership)
        XCTAssertTrue(removed)
        let finalEstimate = await editor.estimate(membershipID: secondMembership, wholeMinutes: 45)
        XCTAssertTrue(finalEstimate)
        let saved = await editor.save()
        #if DEBUG
        if !saved {
            print("V23 My Day editor diagnostic phase=today-editor-save error=\(editor.lastOperationFailureForTesting ?? "missing")")
        }
        #endif
        XCTAssertTrue(saved)
        let outcome = try XCTUnwrap(editor.outcome)
        XCTAssertEqual(outcome.targetResult.plan.items.map(\.membershipID), [secondMembership])
        XCTAssertEqual(outcome.targetResult.plan.items.map(\.reference), [reference(second)])
        XCTAssertEqual(outcome.targetResult.plan.items.first?.estimate?.wholeMinutes, 45)
        XCTAssertEqual(outcome.targetResult.plan.authoredBy, session.request.confirmedContext.recordedBy)
        XCTAssertEqual(outcome.checkpoint.draftID, session.draftID)
        XCTAssertEqual(session.durabilityState, .committed)
        XCTAssertEqual(try count(MyDayPlanRowV1.self, fixture), 1)
        XCTAssertEqual(try count(DraftCommitReceiptRow.self, fixture), 1)
        XCTAssertEqual(try count(DraftContentReservationRow.self, fixture), 0)
        let adapter = try fixture.coordinator.workspaceWriter.makeFieldDraftLifecycleAdapter(modelContext: fixture.coordinator.modelContext)
        XCTAssertEqual(try adapter.currentCheckpoint(workspaceID: first.workspaceID, draftID: first.draftID), first)
        XCTAssertEqual(try adapter.currentCheckpoint(workspaceID: second.workspaceID, draftID: second.draftID), second)
        let host = UIHostingController(rootView: ProductionMyDayPlanningEditorV1(state: editor))
        host.loadViewIfNeeded()
        XCTAssertNotNil(host.view)
        let repeatedInvalidation = editor.objectWillChange.sink { editor.discardPresentation() }
        sourceState.discard()
        repeatedInvalidation.cancel()
        XCTAssertNil(editor.editingSession)
        XCTAssertNil(editor.context)
        XCTAssertNil(editor.outcome)
        XCTAssertFalse(fixture.coordinator.modelContext.hasChanges)
    }

    @MainActor
    func testFailedCloseFlushKeepsSameEditorAndReopenedEditorResumesExactAcknowledgedDraft() async throws {
        let fixture = try await makeFixture("editor-close-retry")
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let editor = makeEditor(fixture, access: access)
        let opened = await editor.openDay(civilDate: "2026-09-12", timeZone: "America/New_York")
        let began = await editor.beginNew(recordedByName: "Field recorder")
        XCTAssertTrue(opened && began)
        let session = try XCTUnwrap(editor.editingSession)
        let originalRequest = session.request
        #if DEBUG
        access.setPlanningEffectHookForTesting { point in
            if point == .editingCheckpoint { throw EditorInterruption.injected }
        }
        let firstClose = await editor.flush(reason: .navigation)
        XCTAssertFalse(firstClose)
        XCTAssertTrue(editor.editingSession === session)
        XCTAssertEqual(session.request, originalRequest)
        XCTAssertNotNil(editor.errorMessage)
        XCTAssertTrue(session.hasDirtyChanges)
        let durable = try access.loadPlanningCheckpoint(draftID: session.draftID)
        let receiptsAfterEffect = try count(MutationReceiptRow.self, fixture)
        access.setPlanningEffectHookForTesting(nil)
        let retryClose = await editor.flush(reason: .navigation)
        XCTAssertTrue(retryClose)
        XCTAssertEqual(session.checkpoint, durable)
        XCTAssertEqual(session.durabilityState, .savedOnThisIPhone)
        XCTAssertEqual(try count(MutationReceiptRow.self, fixture), receiptsAfterEffect)
        #else
        let closed = await editor.flush(reason: .navigation)
        XCTAssertTrue(closed)
        #endif
        let draftID = session.draftID
        editor.discardPresentation()
        await session.invalidate()
        let reopened = makeEditor(fixture, access: access)
        let reopenedDay = await reopened.openDay(civilDate: "2026-09-12", timeZone: "America/New_York")
        XCTAssertTrue(reopenedDay)
        XCTAssertEqual(reopened.checkpoints.map(\.draftID), [draftID])
        let duplicate = await reopened.beginNew(recordedByName: "Another recorder")
        XCTAssertFalse(duplicate)
        let beforeResume = try fixture.coordinator.workspaceWriter.currentRevision()
        let resumed = await reopened.resume(draftID: draftID)
        XCTAssertTrue(resumed)
        let resumedSession = try XCTUnwrap(reopened.editingSession)
        XCTAssertEqual(resumedSession.request, originalRequest)
        XCTAssertEqual(resumedSession.draftID, draftID)
        XCTAssertFalse(resumedSession.hasDirtyChanges)
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), beforeResume)
        let saved = await reopened.save()
        XCTAssertTrue(saved)
        XCTAssertEqual(reopened.outcome?.checkpoint.draftID, draftID)
        XCTAssertEqual(try count(FieldDraftCheckpointRow.self, fixture), 1)
        XCTAssertEqual(try count(MyDayPlanRowV1.self, fixture), 1)
        reopened.discardPresentation()
    }

    @MainActor
    func testPostEffectSaveFailureRetainsExactAttemptWithoutPublishingSuccessAndRetriesOnce() async throws {
        #if DEBUG
        let fixture = try await makeFixture("editor-save-effect")
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let editor = makeEditor(fixture, access: access)
        let opened = await editor.openDay(civilDate: "2026-09-12", timeZone: "America/New_York")
        let began = await editor.beginNew(recordedByName: "Field recorder")
        XCTAssertTrue(opened && began)
        let session = try XCTUnwrap(editor.editingSession)
        var interrupted = false
        access.setPlanningEffectHookForTesting { point in
            if point == .targetCommit, !interrupted {
                interrupted = true
                throw EditorInterruption.injected
            }
        }
        let firstSave = await editor.save()
        if !firstSave {
            print("V23 My Day editor diagnostic phase=post-effect-save error=\(editor.lastOperationFailureForTesting ?? "missing")")
        }
        XCTAssertFalse(firstSave)
        XCTAssertTrue(interrupted)
        XCTAssertNil(editor.outcome)
        XCTAssertNotNil(editor.errorMessage)
        XCTAssertTrue(editor.editingSession === session)
        XCTAssertEqual(session.durabilityState, .saveBlocked)
        XCTAssertFalse(session.hasDirtyChanges)
        let pending = try access.loadPlanningCheckpoint(draftID: session.draftID)
        let attempt = try XCTUnwrap(MyDayPlanningDraftCodecV1.validateCheckpointPayload(pending).commitAttempt)
        XCTAssertEqual(try count(MyDayPlanRowV1.self, fixture), 1)
        access.setPlanningEffectHookForTesting(nil)
        let retried = await editor.save()
        XCTAssertTrue(retried)
        let outcome = try XCTUnwrap(editor.outcome)
        XCTAssertEqual(try MyDayPlanningDraftCodecV1.validateCheckpointPayload(outcome.checkpoint).commitAttempt, attempt)
        XCTAssertEqual(try count(MyDayPlanRowV1.self, fixture), 1)
        XCTAssertEqual(try count(DraftCommitReceiptRow.self, fixture), 1)
        XCTAssertEqual(try count(DraftCommitSagaRow.self, fixture), 5)
        editor.discardPresentation()
        #endif
    }

    @MainActor
    func testReopenedEditorContinuesCommittingDraftWithoutTreatingItAsEditable() async throws {
        #if DEBUG
        let fixture = try await makeFixture("editor-continue-save")
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let original = makeEditor(fixture, access: access)
        let opened = await original.openDay(civilDate: "2026-09-12", timeZone: "America/New_York")
        let began = await original.beginNew(recordedByName: "Field recorder")
        XCTAssertTrue(opened && began)
        let session = try XCTUnwrap(original.editingSession)
        access.setPlanningEffectHookForTesting { point in
            if point == .committingCheckpoint { throw EditorInterruption.injected }
        }
        let saved = await original.save()
        XCTAssertFalse(saved)
        access.setPlanningEffectHookForTesting(nil)
        let checkpoint = try access.loadPlanningCheckpoint(draftID: session.draftID)
        XCTAssertEqual(checkpoint.state, .committing)
        let canClose = await original.flush(reason: .navigation)
        XCTAssertFalse(canClose)
        XCTAssertTrue(original.editingSession === session)
        XCTAssertNotNil(original.errorMessage)
        XCTAssertNil(original.outcome)
        // An involuntary loss of the presentation still leaves the original
        // durable COMMITTING checkpoint available on the next presentation.
        original.discardPresentation()
        await session.invalidate()
        let fresh = makeEditor(fixture, access: access)
        let freshOpened = await fresh.openDay(civilDate: "2026-09-12", timeZone: "America/New_York")
        XCTAssertTrue(freshOpened)
        XCTAssertEqual(fresh.checkpoints, [checkpoint])
        let resumedAsEditing = await fresh.resume(draftID: checkpoint.draftID)
        XCTAssertFalse(resumedAsEditing)
        XCTAssertNil(fresh.editingSession)
        XCTAssertEqual(try count(MyDayPlanRowV1.self, fixture), 0)
        let finished = await fresh.finishSave(draftID: checkpoint.draftID)
        XCTAssertTrue(finished)
        XCTAssertEqual(fresh.outcome?.checkpoint.draftID, checkpoint.draftID)
        XCTAssertEqual(try count(MyDayPlanRowV1.self, fixture), 1)
        let terminalResume = await fresh.resume(draftID: checkpoint.draftID)
        XCTAssertFalse(terminalResume)
        XCTAssertNil(fresh.editingSession)
        fresh.discardPresentation()
        #endif
    }

    @MainActor
    func testRevocationDuringSourceReadClearsEditorAndOldPublicationCannotReturnAfterRepublish() async throws {
        #if DEBUG
        let fixture = try await makeFixture("editor-source-revocation")
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let editor = makeEditor(fixture, access: access)
        let before = try fixture.coordinator.workspaceWriter.currentRevision()
        access.setAfterSourceMaterializationForTesting { fixture.presentation.receive(.sceneInactive) }
        let opened = await editor.openDay(civilDate: "2026-09-12", timeZone: "America/New_York")
        XCTAssertFalse(opened)
        XCTAssertNil(editor.context)
        XCTAssertNil(editor.sources)
        XCTAssertTrue(editor.checkpoints.isEmpty)
        XCTAssertNil(editor.editingSession)
        access.setAfterSourceMaterializationForTesting(nil)
        let published = expectation(description: "Fresh editor publication")
        let observer = fixture.presentation.$permitsContentPresentation.filter { $0 }.prefix(1)
            .sink { _ in published.fulfill() }
        fixture.presentation.receive(.sceneActive)
        await fulfillment(of: [published], timeout: 30)
        observer.cancel()
        let oldRead = await editor.openDay(civilDate: "2026-09-12", timeZone: "America/New_York")
        XCTAssertFalse(oldRead)
        let freshAccess = try XCTUnwrap(fixture.presentation.myDayAccess)
        let fresh = makeEditor(fixture, access: freshAccess)
        let freshRead = await fresh.openDay(civilDate: "2026-09-12", timeZone: "America/New_York")
        XCTAssertTrue(freshRead)
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), before)
        XCTAssertEqual(try count(FieldDraftCheckpointRow.self, fixture), 0)
        fresh.discardPresentation()
        #endif
    }

    @MainActor
    func testEditorRejectsInvalidDayAndObserverRevocationBeforeAnyCheckpointWrite() async throws {
        let fixture = try await makeFixture("editor-invalid-and-observer")
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let editor = makeEditor(fixture, access: access)
        let before = try fixture.coordinator.workspaceWriter.currentRevision()
        let invalid = await editor.openDay(civilDate: "2026-02-31", timeZone: "America/New_York")
        XCTAssertFalse(invalid)
        XCTAssertNil(editor.context)
        let opened = await editor.openDay(civilDate: "2026-09-12", timeZone: "America/New_York")
        XCTAssertTrue(opened)
        var revoke = true
        let observation = editor.objectWillChange.sink {
            if revoke { revoke = false; fixture.presentation.receive(.sceneInactive) }
        }
        let began = await editor.beginNew(recordedByName: "Recorder")
        XCTAssertFalse(began)
        observation.cancel()
        XCTAssertNil(editor.editingSession)
        XCTAssertNil(editor.context)
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), before)
        XCTAssertEqual(try count(FieldDraftCheckpointRow.self, fixture), 0)
        XCTAssertFalse(fixture.coordinator.modelContext.hasChanges)
    }

    @MainActor
    func testResumeRejectsCheckpointAdvanceAfterActualSourceReadWithoutPublishingStaleEditor() async throws {
        #if DEBUG
        let fixture = try await makeFixture("editor-resume-checkpoint-drift")
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let key = try day(fixture)
        let context = try access.captureConfirmedPlanningContext(for: key, recordedByName: "Recorder")
        let request = try MyDayPlanningPlanSaveRequestV1(confirmedContext: context,
            draft: .init(key: key, items: [], eligibleReferences: []), predecessor: nil)
        let first = try access.prepareEditingWrite(request, replacing: nil, resumeAnchor: .init(sectionID: "my-day"))
        let acknowledged = try access.persistEditingWrite(first)
        let editor = makeEditor(fixture, access: access)
        let opened = await editor.openDay(civilDate: "2026-09-12", timeZone: "America/New_York")
        XCTAssertTrue(opened)
        var successor: MyDayPlanningCheckpointAcknowledgementV1?
        var receiptCountAfterAdvance: Int?
        editor.afterResumeSourcesReadyForTesting = {
            let write = try access.prepareEditingWrite(request, replacing: acknowledged.checkpoint,
                                                       resumeAnchor: .init(sectionID: "changed-focus"))
            successor = try access.persistEditingWrite(write)
            receiptCountAfterAdvance = try self.count(MutationReceiptRow.self, fixture)
        }
        let resumed = await editor.resume(draftID: acknowledged.checkpoint.draftID)
        XCTAssertFalse(resumed)
        XCTAssertNotNil(successor)
        XCTAssertNil(editor.editingSession)
        XCTAssertNotNil(editor.errorMessage)
        XCTAssertEqual(try access.loadPlanningCheckpoint(draftID: acknowledged.checkpoint.draftID), successor?.checkpoint)
        XCTAssertEqual(try count(MutationReceiptRow.self, fixture), receiptCountAfterAdvance)
        XCTAssertEqual(try count(MyDayPlanRowV1.self, fixture), 0)
        editor.afterResumeSourcesReadyForTesting = nil
        editor.discardPresentation()
        #endif
    }

    @MainActor
    func testResumeRejectsStalePlanBaseBeforeAndAfterSourceReadWithoutRebasingOrWriting() async throws {
        #if DEBUG
        for advanceDuringRead in [false, true] {
            let fixture = try await makeFixture("editor-resume-plan-drift-\(advanceDuringRead)")
            let access = try XCTUnwrap(fixture.presentation.myDayAccess)
            let key = try day(fixture)
            let context = try access.captureConfirmedPlanningContext(for: key, recordedByName: "Recorder")
            let request = try MyDayPlanningPlanSaveRequestV1(confirmedContext: context,
                draft: .init(key: key, items: [], eligibleReferences: []), predecessor: nil)
            let first = try access.prepareEditingWrite(request, replacing: nil, resumeAnchor: .init(sectionID: "my-day"))
            let acknowledged = try access.persistEditingWrite(first)
            var competing: MyDayPlanningCommitOutcomeV1?
            var receiptsAfterCompetingSave: Int?
            if !advanceDuringRead {
                competing = try await access.savePlan(request)
                receiptsAfterCompetingSave = try count(MutationReceiptRow.self, fixture)
            }
            let editor = makeEditor(fixture, access: access)
            let opened = await editor.openDay(civilDate: "2026-09-12", timeZone: "America/New_York")
            XCTAssertTrue(opened)
            if advanceDuringRead {
                editor.afterResumeSourcesReadyForTesting = {
                    competing = try await access.savePlan(request)
                    receiptsAfterCompetingSave = try self.count(MutationReceiptRow.self, fixture)
                }
            }
            let resumed = await editor.resume(draftID: acknowledged.checkpoint.draftID)
            XCTAssertFalse(resumed)
            XCTAssertNil(editor.editingSession)
            XCTAssertNotNil(editor.errorMessage)
            XCTAssertNotNil(competing)
            XCTAssertEqual(try access.loadPlanningCheckpoint(draftID: acknowledged.checkpoint.draftID), acknowledged.checkpoint)
            XCTAssertEqual(try access.planningContext(for: key).currentPlan, competing?.targetResult.plan)
            XCTAssertEqual(try count(MutationReceiptRow.self, fixture), receiptsAfterCompetingSave)
            XCTAssertEqual(try count(MyDayPlanRowV1.self, fixture), 1)
            XCTAssertFalse(fixture.coordinator.modelContext.hasChanges)
            editor.afterResumeSourcesReadyForTesting = nil
            editor.discardPresentation()
        }
        #endif
    }

    @MainActor
    func testCancelledResumeAfterActualSourceReadDoesNotPublishAnEditingSession() async throws {
        #if DEBUG
        let fixture = try await makeFixture("editor-resume-cancelled")
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let key = try day(fixture)
        let context = try access.captureConfirmedPlanningContext(for: key, recordedByName: "Recorder")
        let request = try MyDayPlanningPlanSaveRequestV1(confirmedContext: context,
            draft: .init(key: key, items: [], eligibleReferences: []), predecessor: nil)
        let write = try access.prepareEditingWrite(request, replacing: nil, resumeAnchor: .init(sectionID: "my-day"))
        let acknowledged = try access.persistEditingWrite(write)
        let editor = makeEditor(fixture, access: access)
        let opened = await editor.openDay(civilDate: "2026-09-12", timeZone: "America/New_York")
        XCTAssertTrue(opened)
        let before = try fixture.coordinator.workspaceWriter.currentRevision()
        editor.afterResumeSourcesReadyForTesting = { withUnsafeCurrentTask { $0?.cancel() } }
        let task = Task { @MainActor in await editor.resume(draftID: acknowledged.checkpoint.draftID) }
        let resumed = await task.value
        XCTAssertFalse(resumed)
        XCTAssertNil(editor.editingSession)
        XCTAssertNil(editor.context)
        XCTAssertNil(editor.sources)
        XCTAssertFalse(editor.isBusy)
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), before)
        XCTAssertEqual(try access.loadPlanningCheckpoint(draftID: acknowledged.checkpoint.draftID), acknowledged.checkpoint)
        editor.afterResumeSourcesReadyForTesting = nil
        #endif
    }


    @MainActor
    func testCarryoverEditorCapturesBothZonesKeepsSourceOrderAndUsesOneSessionThroughSave() async throws {
        let fixture = try await makeFixture("carryover-editor-save")
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let seed = try await seedCarryoverEditorSource(fixture, access: access)
        let before = try fixture.coordinator.workspaceWriter.currentRevision()
        let editor = try await openCarryoverEditor(fixture, access: access)
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), before)
        XCTAssertEqual(editor.carryoverSourcePlan, seed.source)
        XCTAssertEqual(editor.carryoverSelectableItems, seed.source.items)
        let began = await editor.beginCarryover(selectedMembershipIDs: seed.source.items.reversed().map(\.membershipID),
            recordedByName: "Carryover recorder")
        XCTAssertTrue(began)
        let session = try XCTUnwrap(editor.carryoverEditingSession)
        XCTAssertNil(editor.editingSession)
        XCTAssertTrue(editor.hasEditingSession)
        XCTAssertEqual(session.request.sourcePlan.key.ianaTimeZoneIdentifier, "America/New_York")
        XCTAssertEqual(session.request.confirmedContext.key.ianaTimeZoneIdentifier, "Europe/London")
        XCTAssertEqual(session.request.selectedMembershipIDs, seed.source.items.map(\.membershipID))
        let ordinary = await editor.beginNew(recordedByName: "Other recorder")
        let changedDay = await editor.openDay(civilDate: "2026-09-14", timeZone: "Europe/London")
        XCTAssertFalse(ordinary || changedDay)
        XCTAssertTrue(editor.carryoverEditingSession === session)
        let removed = await editor.selectCarryover(membershipID: seed.source.items[0].membershipID, selected: false)
        XCTAssertTrue(removed)
        XCTAssertEqual(session.request.selectedMembershipIDs, [seed.source.items[1].membershipID])
        let host = UIHostingController(rootView: ProductionMyDayPlanningEditorV1(state: editor))
        host.loadViewIfNeeded()
        XCTAssertNotNil(host.view)
        let saved = await editor.save()
        XCTAssertTrue(saved)
        let outcome = try XCTUnwrap(editor.outcome)
        XCTAssertEqual(outcome.targetResult.plan.items.map(\.reference), [seed.source.items[1].reference])
        XCTAssertEqual(outcome.targetResult.plan.items.map(\.estimate), [seed.source.items[1].estimate])
        XCTAssertEqual(outcome.targetResult.plan.authoredBy, session.request.confirmedContext.recordedBy)
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentPlan(for: seed.source.key), seed.source)
        let adapter = try fixture.coordinator.workspaceWriter.makeFieldDraftLifecycleAdapter(modelContext: fixture.coordinator.modelContext)
        for work in seed.work {
            XCTAssertEqual(try adapter.currentCheckpoint(workspaceID: work.workspaceID, draftID: work.draftID), work)
        }
        XCTAssertEqual(try count(MyDayCarryoverReceiptRowV1.self, fixture), 1)
        editor.discardPresentation()
        await session.invalidate()
        XCTAssertNil(editor.carryoverEditingSession)
        XCTAssertNil(editor.carryoverSourcePlan)
        XCTAssertNil(editor.carryoverSources)
        XCTAssertFalse(editor.hasEditingSession)
    }

    @MainActor
    func testCarryoverFailedCloseRetainsExactWriteAndFreshEditorResumesTypedSelection() async throws {
        #if DEBUG
        let fixture = try await makeFixture("carryover-editor-close")
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let seed = try await seedCarryoverEditorSource(fixture, access: access)
        let editor = try await openCarryoverEditor(fixture, access: access)
        let began = await editor.beginCarryover(selectedMembershipIDs: seed.source.items.map(\.membershipID), recordedByName: "Recorder")
        XCTAssertTrue(began)
        let session = try XCTUnwrap(editor.carryoverEditingSession)
        var interrupted = false
        access.setPlanningEffectHookForTesting { point in
            if point == .editingCheckpoint, !interrupted { interrupted = true; throw EditorInterruption.injected }
        }
        let closed = await editor.flush(reason: .navigation)
        XCTAssertFalse(closed)
        XCTAssertTrue(interrupted)
        XCTAssertTrue(editor.carryoverEditingSession === session)
        XCTAssertNil(session.acknowledgement)
        let durable = try access.loadPlanningCheckpoint(draftID: session.draftID)
        let afterEffect = try fixture.coordinator.workspaceWriter.currentRevision()
        access.setPlanningEffectHookForTesting(nil)
        let retried = await editor.flush(reason: .navigation)
        XCTAssertTrue(retried)
        XCTAssertEqual(session.checkpoint, durable)
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), afterEffect)
        let request = session.request
        editor.discardPresentation()
        await session.invalidate()
        let fresh = makeEditor(fixture, access: access)
        let opened = await fresh.openDay(civilDate: "2026-09-13", timeZone: "Europe/London")
        XCTAssertTrue(opened)
        XCTAssertEqual(fresh.checkpoints, [durable])
        let resumed = await fresh.resume(draftID: durable.draftID)
        XCTAssertTrue(resumed)
        let restored = try XCTUnwrap(fresh.carryoverEditingSession)
        XCTAssertNil(fresh.editingSession)
        XCTAssertEqual(restored.request, request)
        XCTAssertEqual(restored.checkpoint, durable)
        XCTAssertEqual(fresh.carryoverSourcePlan, seed.source)
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), afterEffect)
        fresh.discardPresentation()
        await restored.invalidate()
        #endif
    }

    @MainActor
    func testCarryoverCommittingEditorBlocksCloseAndFreshEditorContinuesSameCommand() async throws {
        #if DEBUG
        for point in [MyDayPlanningEffectPointV1.committingCheckpoint, .targetCommit] {
            let fixture = try await makeFixture("carryover-editor-committing-\(point.rawValue)")
            let access = try XCTUnwrap(fixture.presentation.myDayAccess)
            let seed = try await seedCarryoverEditorSource(fixture, access: access)
            let editor = try await openCarryoverEditor(fixture, access: access)
            let began = await editor.beginCarryover(selectedMembershipIDs: seed.source.items.map(\.membershipID), recordedByName: "Recorder")
            XCTAssertTrue(began)
            let session = try XCTUnwrap(editor.carryoverEditingSession)
            access.setPlanningEffectHookForTesting { observed in if observed == point { throw EditorInterruption.injected } }
            let saved = await editor.save()
            XCTAssertFalse(saved)
            access.setPlanningEffectHookForTesting(nil)
            XCTAssertNil(editor.outcome)
            let checkpoint = try access.loadPlanningCheckpoint(draftID: session.draftID)
            XCTAssertEqual(checkpoint.state, .committing)
            let attempt = try XCTUnwrap(MyDayPlanningDraftCodecV1.validateCheckpointPayload(checkpoint).commitAttempt)
            let close = await editor.flush(reason: .navigation)
            XCTAssertFalse(close)
            XCTAssertTrue(editor.carryoverEditingSession === session)
            editor.discardPresentation()
            await session.invalidate()
            let fresh = makeEditor(fixture, access: access)
            let opened = await fresh.openDay(civilDate: "2026-09-13", timeZone: "Europe/London")
            XCTAssertTrue(opened)
            let resumed = await fresh.resume(draftID: checkpoint.draftID)
            XCTAssertFalse(resumed)
            XCTAssertFalse(fresh.hasEditingSession)
            let finished = await fresh.finishSave(draftID: checkpoint.draftID)
            XCTAssertTrue(finished)
            let outcome = try XCTUnwrap(fresh.outcome)
            XCTAssertEqual(try MyDayPlanningDraftCodecV1.validateCheckpointPayload(outcome.checkpoint).commitAttempt, attempt)
            XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentPlan(for: seed.source.key), seed.source)
            XCTAssertEqual(try count(MyDayCarryoverReceiptRowV1.self, fixture), 1)
            XCTAssertEqual(try count(MyDayPlanRowV1.self, fixture), 2)
            fresh.discardPresentation()
        }
        #endif
    }

    @MainActor
    func testCarryoverSourceRevocationClearsBothContextsAndCannotCreateDraft() async throws {
        #if DEBUG
        let fixture = try await makeFixture("carryover-editor-revoked")
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let seed = try await seedCarryoverEditorSource(fixture, access: access)
        let editor = makeEditor(fixture, access: access)
        let opened = await editor.openDay(civilDate: "2026-09-13", timeZone: "Europe/London")
        XCTAssertTrue(opened)
        let before = try fixture.coordinator.workspaceWriter.currentRevision()
        access.setAfterSourceMaterializationForTesting { fixture.presentation.receive(.sceneInactive) }
        let sourceOpened = await editor.openCarryoverSource(civilDate: "2026-09-12", timeZone: "America/New_York")
        XCTAssertFalse(sourceOpened)
        access.setAfterSourceMaterializationForTesting(nil)
        XCTAssertNil(editor.context)
        XCTAssertNil(editor.carryoverSourcePlan)
        XCTAssertNil(editor.carryoverSources)
        XCTAssertFalse(editor.hasEditingSession)
        let began = await editor.beginCarryover(selectedMembershipIDs: seed.source.items.map(\.membershipID), recordedByName: "Recorder")
        XCTAssertFalse(began)
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), before)
        XCTAssertEqual(try count(MyDayCarryoverReceiptRowV1.self, fixture), 0)
        editor.discardPresentation()
        #endif
    }

    @MainActor
    func testCarryoverResumeRejectsExactSourceDriftAcrossSourceReadWithoutRebasingDraft() async throws {
        #if DEBUG
        let fixture = try await makeFixture("carryover-editor-stale-source")
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let seed = try await seedCarryoverEditorSource(fixture, access: access)
        let editor = try await openCarryoverEditor(fixture, access: access)
        let began = await editor.beginCarryover(selectedMembershipIDs: seed.source.items.map(\.membershipID), recordedByName: "Recorder")
        XCTAssertTrue(began)
        let flushed = await editor.flush(reason: .navigation)
        XCTAssertTrue(flushed)
        let session = try XCTUnwrap(editor.carryoverEditingSession)
        let checkpoint = try XCTUnwrap(session.checkpoint)
        editor.discardPresentation()
        await session.invalidate()
        let fresh = makeEditor(fixture, access: access)
        let opened = await fresh.openDay(civilDate: "2026-09-13", timeZone: "Europe/London")
        XCTAssertTrue(opened)
        var afterCompetingSave: WorkspaceRevisionV1?
        fresh.afterResumeSourcesReadyForTesting = {
            let context = try access.captureConfirmedPlanningContext(for: seed.source.key, recordedByName: "Source recorder")
            _ = try await access.savePlan(.init(confirmedContext: context,
                draft: .init(key: seed.source.key, items: [], eligibleReferences: []), predecessor: seed.source))
            afterCompetingSave = try fixture.coordinator.workspaceWriter.currentRevision()
        }
        let resumed = await fresh.resume(draftID: checkpoint.draftID)
        XCTAssertFalse(resumed)
        XCTAssertFalse(fresh.hasEditingSession)
        XCTAssertNotNil(fresh.errorMessage)
        XCTAssertNotNil(afterCompetingSave)
        XCTAssertEqual(try access.loadPlanningCheckpoint(draftID: checkpoint.draftID), checkpoint)
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), afterCompetingSave)
        XCTAssertEqual(try count(MyDayCarryoverReceiptRowV1.self, fixture), 0)
        fresh.afterResumeSourcesReadyForTesting = nil
        fresh.discardPresentation()
        #endif
    }


    @MainActor
    func testCarryoverEditorExcludesTargetMembershipCollisionWithDifferentSourceReference() async throws {
        let fixture = try await makeFixture("carryover-editor-membership-collision")
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let seed = try await seedCarryoverEditorSource(fixture, access: access)
        let otherWork = try seedSource(fixture)
        let targetKey = try MyDayKeyV1(workspaceID: fixture.coordinator.workspaceID,
            civilDate: .init("2026-09-13"), ianaTimeZoneIdentifier: "Europe/London")
        let context = try access.captureConfirmedPlanningContext(for: targetKey, recordedByName: "Target recorder")
        let otherReference = reference(otherWork)
        let collidingItem = try MyDayDraftItemV1(membershipID: seed.source.items[0].membershipID, reference: otherReference)
        let target = try await access.savePlan(.init(confirmedContext: context,
            draft: .init(key: targetKey, items: [collidingItem], eligibleReferences: [otherReference]), predecessor: nil)).targetResult.plan
        XCTAssertNotEqual(target.items[0].reference.stableKey, seed.source.items[0].reference.stableKey)
        let before = try fixture.coordinator.workspaceWriter.currentRevision()
        let editor = try await openCarryoverEditor(fixture, access: access)
        XCTAssertEqual(editor.carryoverSelectableItems, [seed.source.items[1]])
        let rejected = await editor.beginCarryover(selectedMembershipIDs: [seed.source.items[0].membershipID], recordedByName: "Recorder")
        XCTAssertFalse(rejected)
        XCTAssertFalse(editor.hasEditingSession)
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), before)
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentPlan(for: targetKey), target)
        let began = await editor.beginCarryover(selectedMembershipIDs: [seed.source.items[1].membershipID], recordedByName: "Recorder")
        XCTAssertTrue(began)
        let session = try XCTUnwrap(editor.carryoverEditingSession)
        let saved = await editor.save()
        XCTAssertTrue(saved)
        let outcome = try XCTUnwrap(editor.outcome)
        XCTAssertEqual(outcome.targetResult.plan.items.map(\.membershipID), [target.items[0].membershipID, seed.source.items[1].membershipID])
        XCTAssertEqual(outcome.targetResult.plan.items.map(\.reference), [otherReference, seed.source.items[1].reference])
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentPlan(for: seed.source.key), seed.source)
        editor.discardPresentation()
        await session.invalidate()
    }

    @MainActor
    private func seedCarryoverEditorSource(_ fixture: V23ProductionMyDayPresentationHarness,
                                           access: AppAccessPresentationV1.MyDayAccess) async throws
        -> (work: [FieldDraftCheckpointV1], source: MyDayPlanV1) {
        let work = try diagnoseMyDayPreparation(phase: "carryover-source-records") {
            try [seedSource(fixture), seedSource(fixture)]
        }
        let key = try diagnoseMyDayPreparation(phase: "carryover-source-key") { try day(fixture) }
        let context = try diagnoseMyDayPreparation(phase: "carryover-source-context") {
            try access.captureConfirmedPlanningContext(for: key, recordedByName: "Source recorder")
        }
        let items = try diagnoseMyDayPreparation(phase: "carryover-source-items") {
            try work.enumerated().map { index, checkpoint in
                try MyDayDraftItemV1(membershipID: UUID(), reference: reference(checkpoint),
                    estimate: .init(wholeMinutes: 15 * (index + 1)))
            }
        }
        let outcome = try await diagnoseMyDayFailure(phase: "carryover-source-save") {
            try await access.savePlan(.init(confirmedContext: context,
                draft: .init(key: key, items: items, eligibleReferences: work.map(reference)), predecessor: nil))
        }
        return (work, outcome.targetResult.plan)
    }

    @MainActor
    private func openCarryoverEditor(_ fixture: V23ProductionMyDayPresentationHarness,
                                     access: AppAccessPresentationV1.MyDayAccess) async throws -> ProductionMyDayPlanningEditorStateV1 {
        let editor = makeEditor(fixture, access: access)
        let target = await editor.openDay(civilDate: "2026-09-13", timeZone: "Europe/London")
        XCTAssertTrue(target)
        let source = await editor.openCarryoverSource(civilDate: "2026-09-12", timeZone: "America/New_York")
        XCTAssertTrue(source)
        return editor
    }

    @MainActor
    func testSavedDraftDiscardReviewAndCancelAreZeroWriteAndCompletionUsesActualReceipt() async throws {
        let fixture = try await makeFixture("discard-editor-confirm")
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let values = try await makeDiscardChooser(fixture, access: access)
        let editor = values.editor
        let before = try fixture.coordinator.workspaceWriter.currentRevision()
        XCTAssertTrue(editor.canDiscard(values.checkpoint))
        let requested = await editor.requestDiscard(checkpoint: values.checkpoint)
        XCTAssertTrue(requested)
        let first = try XCTUnwrap(editor.discardWrite)
        XCTAssertEqual(first.expectedCheckpoint, values.checkpoint)
        XCTAssertNil(editor.discardOutcome)
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), before)
        let changedDay = await editor.openDay(civilDate: "2026-09-13", timeZone: "Europe/London")
        let resumed = await editor.resume(draftID: values.checkpoint.draftID)
        XCTAssertFalse(changedDay)
        XCTAssertFalse(resumed)
        XCTAssertEqual(editor.discardWrite, first)
        let cancelled = await editor.cancelDiscard(first)
        XCTAssertTrue(cancelled)
        XCTAssertNil(editor.discardWrite)
        XCTAssertNil(editor.discardOutcome)
        XCTAssertEqual(editor.checkpoints, [values.checkpoint])
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), before)
        let requestedAgain = await editor.requestDiscard(checkpoint: values.checkpoint)
        XCTAssertTrue(requestedAgain)
        let write = try XCTUnwrap(editor.discardWrite)
        let confirmed = await editor.confirmDiscard(write)
        XCTAssertTrue(confirmed)
        let outcome = try XCTUnwrap(editor.discardOutcome)
        XCTAssertEqual(outcome.checkpoint, write.terminalBundle.discardedCheckpoint)
        XCTAssertEqual(outcome.draftReceipt, write.terminalBundle.receipt)
        XCTAssertEqual(try access.discardedPlanningAcknowledgement(expectedCheckpoint: outcome.checkpoint), outcome)
        XCTAssertNil(editor.discardWrite)
        XCTAssertNil(editor.outcome)
        XCTAssertTrue(editor.checkpoints.isEmpty)
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision().revision, before.revision + 2)
        XCTAssertEqual(try count(DraftDiscardReceiptRow.self, fixture), 1)
        try assertDiscardSourcePreserved(values.source, fixture: fixture)
        editor.discardPresentation()
    }

    @MainActor
    func testSavedDraftDiscardRefusesStaleConfirmationAndRefreshesWithoutAdoptingNewEdits() async throws {
        let fixture = try await makeFixture("discard-editor-stale")
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let values = try await makeDiscardChooser(fixture, access: access)
        let requested = await values.editor.requestDiscard(checkpoint: values.checkpoint)
        XCTAssertTrue(requested)
        let shown = try XCTUnwrap(values.editor.discardWrite)
        let change = try access.prepareEditingWrite(values.request, replacing: values.checkpoint,
                                                    resumeAnchor: .init(sectionID: "newer-scene"))
        let newer = try access.persistEditingWrite(change).checkpoint
        let beforeConfirmation = try fixture.coordinator.workspaceWriter.currentRevision()
        let confirmed = await values.editor.confirmDiscard(shown)
        XCTAssertFalse(confirmed)
        XCTAssertNil(values.editor.discardOutcome)
        XCTAssertNotNil(values.editor.errorMessage)
        XCTAssertEqual(values.editor.checkpoints, [newer])
        XCTAssertNotEqual(values.editor.discardWrite?.expectedCheckpoint, newer)
        XCTAssertEqual(try access.loadPlanningCheckpoint(draftID: newer.draftID), newer)
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), beforeConfirmation)
        XCTAssertEqual(try count(DraftDiscardReceiptRow.self, fixture), 0)
        try assertDiscardSourcePreserved(values.source, fixture: fixture)
        values.editor.discardPresentation()
    }

    @MainActor
    func testSavedDraftDiscardIsUnavailableToLiveEditorAndPreparedCommit() async throws {
        let fixture = try await makeFixture("discard-editor-unavailable")
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let values = try await makeDiscardChooser(fixture, access: access)
        let resumed = await values.editor.resume(draftID: values.checkpoint.draftID)
        XCTAssertTrue(resumed)
        let session = try XCTUnwrap(values.editor.editingSession)
        let before = try fixture.coordinator.workspaceWriter.currentRevision()
        XCTAssertFalse(values.editor.canDiscard(values.checkpoint))
        let requestedLive = await values.editor.requestDiscard(checkpoint: values.checkpoint)
        XCTAssertFalse(requestedLive)
        XCTAssertNil(values.editor.discardWrite)
        XCTAssertTrue(values.editor.editingSession === session)
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), before)
        values.editor.discardPresentation()
        await session.invalidate()
        #if DEBUG
        access.setPlanningEffectHookForTesting { point in
            if point == .committingCheckpoint { throw EditorInterruption.injected }
        }
        do {
            _ = try await access.retryPlanSave(draftID: values.checkpoint.draftID)
            XCTFail("The committing checkpoint acknowledgement should be interrupted")
        } catch {
            XCTAssertTrue(error is EditorInterruption)
        }
        access.setPlanningEffectHookForTesting(nil)
        let prepared = try access.loadPlanningCheckpoint(draftID: values.checkpoint.draftID)
        XCTAssertEqual(prepared.state, .committing)
        let chooser = makeEditor(fixture, access: access)
        let opened = await chooser.openDay(civilDate: "2026-09-12", timeZone: "America/New_York")
        XCTAssertTrue(opened)
        XCTAssertFalse(chooser.canDiscard(prepared))
        let beforePreparedRequest = try fixture.coordinator.workspaceWriter.currentRevision()
        let requestedPrepared = await chooser.requestDiscard(checkpoint: prepared)
        XCTAssertFalse(requestedPrepared)
        XCTAssertNil(chooser.discardWrite)
        XCTAssertNil(chooser.discardOutcome)
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), beforePreparedRequest)
        chooser.discardPresentation()
        #endif
        XCTAssertEqual(try count(DraftDiscardReceiptRow.self, fixture), 0)
        try assertDiscardSourcePreserved(values.source, fixture: fixture)
    }

    @MainActor
    func testSavedDraftDiscardRetainsOneFrozenRequestAcrossBothLostAcknowledgements() async throws {
        #if DEBUG
        for edge in [MyDayPlanningEffectPointV1.discardPendingCheckpoint, .discardTerminalBundle] {
            let fixture = try await makeFixture("discard-editor-retry-\(edge.rawValue)")
            let access = try XCTUnwrap(fixture.presentation.myDayAccess)
            let values = try await makeDiscardChooser(fixture, access: access)
            let requested = await values.editor.requestDiscard(checkpoint: values.checkpoint)
            XCTAssertTrue(requested)
            let frozen = try XCTUnwrap(values.editor.discardWrite)
            access.setPlanningEffectHookForTesting { point in
                if point == edge { throw EditorInterruption.injected }
            }
            let first = await values.editor.confirmDiscard(frozen)
            XCTAssertFalse(first)
            XCTAssertEqual(values.editor.discardWrite, frozen)
            XCTAssertNil(values.editor.discardOutcome)
            XCTAssertNotNil(values.editor.errorMessage)
            XCTAssertTrue(values.editor.checkpoints.contains { $0.draftID == values.checkpoint.draftID })
            let durable = try access.loadPlanningCheckpoint(draftID: values.checkpoint.draftID)
            XCTAssertEqual(durable, edge == .discardPendingCheckpoint
                ? frozen.pendingCheckpoint : frozen.terminalBundle.discardedCheckpoint)
            let afterEffect = try fixture.coordinator.workspaceWriter.currentRevision()
            access.setPlanningEffectHookForTesting(nil)
            let retried = await values.editor.confirmDiscard(frozen)
            XCTAssertTrue(retried)
            let outcome = try XCTUnwrap(values.editor.discardOutcome)
            XCTAssertEqual(outcome.checkpoint, frozen.terminalBundle.discardedCheckpoint)
            XCTAssertEqual(outcome.draftReceipt, frozen.terminalBundle.receipt)
            XCTAssertNil(values.editor.discardWrite)
            XCTAssertTrue(values.editor.checkpoints.isEmpty)
            let extra: UInt64 = edge == .discardPendingCheckpoint ? 1 : 0
            XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision().revision,
                           afterEffect.revision + extra)
            XCTAssertEqual(try count(DraftDiscardReceiptRow.self, fixture), 1)
            try assertDiscardSourcePreserved(values.source, fixture: fixture)
            values.editor.discardPresentation()
        }
        #endif
    }

    @MainActor
    func testSavedDraftDiscardFreshChooserRequiresExplicitPendingContinuation() async throws {
        #if DEBUG
        let fixture = try await makeFixture("discard-editor-pending-reopen")
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let values = try await makeDiscardChooser(fixture, access: access)
        let requested = await values.editor.requestDiscard(checkpoint: values.checkpoint)
        XCTAssertTrue(requested)
        let original = try XCTUnwrap(values.editor.discardWrite)
        access.setPlanningEffectHookForTesting { point in
            if point == .discardPendingCheckpoint { throw EditorInterruption.injected }
        }
        let first = await values.editor.confirmDiscard(original)
        XCTAssertFalse(first)
        access.setPlanningEffectHookForTesting(nil)
        values.editor.discardPresentation()
        let pending = try access.loadPlanningCheckpoint(draftID: values.checkpoint.draftID)
        XCTAssertEqual(pending, original.pendingCheckpoint)
        let beforeOpen = try fixture.coordinator.workspaceWriter.currentRevision()
        let reopened = makeEditor(fixture, access: access)
        let opened = await reopened.openDay(civilDate: "2026-09-12", timeZone: "America/New_York")
        XCTAssertTrue(opened)
        XCTAssertEqual(reopened.checkpoints, [pending])
        XCTAssertNil(reopened.discardWrite)
        XCTAssertNil(reopened.discardOutcome)
        XCTAssertTrue(reopened.canDiscard(pending))
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), beforeOpen)
        let continued = await reopened.requestDiscard(checkpoint: pending)
        XCTAssertTrue(continued)
        let write = try XCTUnwrap(reopened.discardWrite)
        XCTAssertEqual(write.pendingCheckpoint, pending)
        XCTAssertEqual(write.plan, original.plan)
        let completed = await reopened.confirmDiscard(write)
        XCTAssertTrue(completed)
        XCTAssertEqual(reopened.discardOutcome?.draftReceipt, write.terminalBundle.receipt)
        XCTAssertEqual(try count(DraftDiscardReceiptRow.self, fixture), 1)
        try assertDiscardSourcePreserved(values.source, fixture: fixture)
        reopened.discardPresentation()
        #endif
    }

    @MainActor
    func testSavedDraftDiscardRevocationDuringQuarantineCannotPublishOldSuccess() async throws {
        #if DEBUG
        let fixture = try await makeFixture("discard-editor-cover")
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let values = try await makeDiscardChooser(fixture, access: access)
        let requested = await values.editor.requestDiscard(checkpoint: values.checkpoint)
        XCTAssertTrue(requested)
        let write = try XCTUnwrap(values.editor.discardWrite)
        let presentation = fixture.presentation
        access.setPlanningDiscardHookForTesting { presentation.receive(.sceneInactive) }
        let confirmed = await values.editor.confirmDiscard(write)
        XCTAssertFalse(confirmed)
        access.setPlanningDiscardHookForTesting(nil)
        XCTAssertNil(values.editor.discardOutcome)
        XCTAssertNil(values.editor.context)
        XCTAssertNil(values.editor.discardWrite)
        XCTAssertThrowsError(try access.discardedPlanningAcknowledgement(
            expectedCheckpoint: write.terminalBundle.discardedCheckpoint))
        let published = expectation(description: "Fresh discard chooser publication")
        let observation = presentation.$permitsContentPresentation.filter { $0 }.prefix(1)
            .sink { _ in published.fulfill() }
        presentation.receive(.sceneActive)
        await fulfillment(of: [published], timeout: 30)
        observation.cancel()
        let fresh = try XCTUnwrap(presentation.myDayAccess)
        XCTAssertEqual(try fresh.loadPlanningCheckpoint(draftID: values.checkpoint.draftID), write.pendingCheckpoint)
        let oldRetry = await values.editor.confirmDiscard(write)
        XCTAssertFalse(oldRetry)
        let reopened = makeEditor(fixture, access: fresh)
        let opened = await reopened.openDay(civilDate: "2026-09-12", timeZone: "America/New_York")
        XCTAssertTrue(opened)
        let request = await reopened.requestDiscard(checkpoint: write.pendingCheckpoint)
        XCTAssertTrue(request)
        let resumedWrite = try XCTUnwrap(reopened.discardWrite)
        let resumed = await reopened.confirmDiscard(resumedWrite)
        XCTAssertTrue(resumed)
        XCTAssertEqual(try count(DraftDiscardReceiptRow.self, fixture), 1)
        try assertDiscardSourcePreserved(values.source, fixture: fixture)
        reopened.discardPresentation()
        #endif
    }

    @MainActor
    func testSavedDraftDiscardFinalPublicationRechecksOriginalAccessAfterObserverCover() async throws {
        let fixture = try await makeFixture("discard-editor-final-publication")
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let values = try await makeDiscardChooser(fixture, access: access)
        let requested = await values.editor.requestDiscard(checkpoint: values.checkpoint)
        XCTAssertTrue(requested)
        let write = try XCTUnwrap(values.editor.discardWrite)
        var covered = false
        let observer = values.editor.objectWillChange.sink {
            guard !covered,
                  (try? access.loadPlanningCheckpoint(draftID: values.checkpoint.draftID))?.state == .discarded else { return }
            covered = true
            fixture.presentation.receive(.sceneInactive)
        }
        let result = await values.editor.confirmDiscard(write)
        observer.cancel()
        XCTAssertTrue(covered)
        XCTAssertFalse(result)
        XCTAssertNil(values.editor.discardOutcome)
        XCTAssertNil(values.editor.context)
        XCTAssertNil(values.editor.discardWrite)
        XCTAssertEqual(try count(DraftDiscardReceiptRow.self, fixture), 1)
        try assertDiscardSourcePreserved(values.source, fixture: fixture)
    }

    @MainActor
    func testConflictReviewRefusesAnOrdinaryActiveDraftWithoutClassifyingSaveFailure() async throws {
        let fixture = try await makeFixture("conflict-editor-active-denial")
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let key = try day(fixture)
        let context = try access.captureConfirmedPlanningContext(for: key, recordedByName: "Conflict recorder")
        let request = try MyDayPlanningPlanSaveRequestV1(confirmedContext: context,
            draft: .init(key: key, items: [], eligibleReferences: []), predecessor: nil)
        let checkpoint = try access.persistEditingWrite(access.prepareEditingWrite(request, replacing: nil,
            resumeAnchor: .init(sectionID: "my-day"))).checkpoint
        let editor = makeEditor(fixture, access: access)
        let opened = await editor.openDay(civilDate: key.civilDate.canonicalString,
                                          timeZone: key.ianaTimeZoneIdentifier)
        XCTAssertTrue(opened)
        let revision = try fixture.coordinator.workspaceWriter.currentRevision()
        let reviewed = await editor.requestExistingConflictReview(draftID: checkpoint.draftID)
        XCTAssertFalse(reviewed)
        XCTAssertNil(editor.conflictReview)
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), revision)
        XCTAssertEqual(try access.loadPlanningCheckpoint(draftID: checkpoint.draftID), checkpoint)
        let host = UIHostingController(rootView: ProductionMyDayPlanningEditorV1(state: editor))
        host.loadViewIfNeeded()
        XCTAssertNotNil(host.view)
        editor.discardPresentation()
    }

    @MainActor
    func testConflictReviewCancellationRequiresOnlyTheEffectFreePreparedState() async throws {
        let fixture = try await makeFixture("conflict-editor-cancel-denial")
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let editor = makeEditor(fixture, access: access)
        let opened = await editor.openDay(civilDate: "2026-09-12", timeZone: "America/New_York")
        XCTAssertTrue(opened)
        let revision = try fixture.coordinator.workspaceWriter.currentRevision()
        let cancelled = await editor.cancelPreparedConflictReview()
        XCTAssertFalse(cancelled)
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), revision)
        XCTAssertNil(editor.classificationWrite)
        XCTAssertNil(editor.reviewedRebaseWrite)
        editor.discardPresentation()
    }

    @MainActor
    func testFailedCleanPlanSaveClassifiesReviewsRebasesAndResumesTheSameDraftID() async throws {
        let fixture = try await makeFixture("conflict-editor-full-local-flow")
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let key = try day(fixture)
        let editor = makeEditor(fixture, access: access)
        let opened = await editor.openDay(civilDate: key.civilDate.canonicalString,
                                          timeZone: key.ianaTimeZoneIdentifier)
        let began = await editor.beginNew(recordedByName: "Conflict recorder")
        XCTAssertTrue(opened && began)
        let oldSession = try XCTUnwrap(editor.editingSession)
        try await oldSession.forceFlush(reason: .navigation)
        let originalDraftID = oldSession.draftID
        let target = try await access.savePlan(makeEmptyPlanRequest(access: access, key: key,
                                                                     recorder: "Other recorder", predecessor: nil))
        let failedSave = await editor.save()
        XCTAssertFalse(failedSave)
        XCTAssertTrue(editor.editingSession === oldSession)
        XCTAssertEqual(oldSession.durabilityState, .saveBlocked)
        XCTAssertFalse(oldSession.hasDirtyChanges)
        XCTAssertTrue(editor.canOfferStalePlanReview)
        let requested = await editor.requestStalePlanReview()
        XCTAssertTrue(requested)
        let classification = try XCTUnwrap(editor.classificationWrite)
        XCTAssertEqual(classification.evidence.currentCheckpoint.draftID, originalDraftID)
        let classified = await editor.confirmStalePlanReview()
        XCTAssertTrue(classified)
        let review = try XCTUnwrap(editor.conflictReview)
        XCTAssertNil(editor.editingSession)
        XCTAssertEqual(review.originalEditingRequest.confirmedContext.recordedBy.displayNameAtTime,
                       "Conflict recorder")
        XCTAssertEqual(review.reviewRequest.predecessor, target.targetResult.plan)
        let revisionBeforeRead = try fixture.coordinator.workspaceWriter.currentRevision()
        let backed = await editor.backToSavedDrafts()
        XCTAssertTrue(backed)
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), revisionBeforeRead)
        let reread = await editor.requestExistingConflictReview(draftID: originalDraftID)
        let rebased = await editor.confirmReviewedRebase()
        XCTAssertTrue(reread && rebased)
        XCTAssertNil(editor.reviewedRebaseWrite)
        let resumed = try XCTUnwrap(editor.editingSession)
        XCTAssertEqual(resumed.draftID, originalDraftID)
        XCTAssertEqual(resumed.request.predecessor, target.targetResult.plan)
        let saved = await editor.save()
        XCTAssertTrue(saved)
        XCTAssertEqual(try XCTUnwrap(editor.outcome).checkpoint.draftID, originalDraftID)
        editor.discardPresentation()
    }

    @MainActor
    func testReviewedRebaseTargetDriftRetainsExactWriteWithoutAPlanSaveOutcome() async throws {
        let fixture = try await makeFixture("conflict-editor-rebase-drift")
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let key = try day(fixture)
        let editor = makeEditor(fixture, access: access)
        let opened = await editor.openDay(civilDate: key.civilDate.canonicalString,
                                          timeZone: key.ianaTimeZoneIdentifier)
        let began = await editor.beginNew(recordedByName: "Conflict recorder")
        XCTAssertTrue(opened && began)
        let session = try XCTUnwrap(editor.editingSession)
        try await session.forceFlush(reason: .navigation)
        let target = try await access.savePlan(makeEmptyPlanRequest(access: access, key: key,
                                                                     recorder: "Other recorder", predecessor: nil))
        let failedSave = await editor.save()
        let requested = await editor.requestStalePlanReview()
        let classified = await editor.confirmStalePlanReview()
        XCTAssertFalse(failedSave)
        XCTAssertTrue(requested && classified)
        let changed = try await access.savePlan(makeEmptyPlanRequest(access: access, key: key,
            recorder: "Later recorder", predecessor: target.targetResult.plan))
        let revision = try fixture.coordinator.workspaceWriter.currentRevision()
        let rebased = await editor.confirmReviewedRebase()
        XCTAssertFalse(rebased)
        XCTAssertNil(editor.reviewedRebaseWrite)
        XCTAssertNil(editor.outcome)
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), revision)
        XCTAssertEqual((try access.loadPlanningCheckpoint(draftID: session.draftID)).state, .conflicted)
        XCTAssertEqual(changed.targetResult.plan.key, key)
        editor.discardPresentation()
    }

    @MainActor
    func testStalePlanReviewAuthenticatesActualActiveAndPreTargetCommittingPrefixesThenResumesSameDraft() async throws {
        #if DEBUG
        for interruption in [nil, .committingCheckpoint, .preparedSaga, .contentPromotedSaga] as [MyDayPlanningEffectPointV1?] {
            let fixture = try await makeFixture("conflict-editor-prefix-\(interruption?.rawValue ?? "active")")
            let access = try XCTUnwrap(fixture.presentation.myDayAccess)
            let key = try day(fixture)
            let original = makeEditor(fixture, access: access)
            let openedOriginal = await original.openDay(civilDate: key.civilDate.canonicalString,
                                                        timeZone: key.ianaTimeZoneIdentifier)
            XCTAssertTrue(openedOriginal)
            let beganOriginal = await original.beginNew(recordedByName: "Conflict recorder")
            XCTAssertTrue(beganOriginal)
            let session = try XCTUnwrap(original.editingSession)
            let draftID = session.draftID
            if let interruption {
                var injected = false
                access.setPlanningEffectHookForTesting { point in
                    guard point == interruption, !injected else { return }
                    injected = true
                    throw EditorInterruption.injected
                }
                let interruptedSave = await original.save()
                XCTAssertFalse(interruptedSave)
                access.setPlanningEffectHookForTesting(nil)
                XCTAssertTrue(injected)
                XCTAssertEqual((try access.loadPlanningCheckpoint(draftID: draftID)).state, .committing)
            } else {
                try await session.forceFlush(reason: .navigation)
                XCTAssertEqual((try access.loadPlanningCheckpoint(draftID: draftID)).state, .active)
            }
            original.discardPresentation()
            let reviewing = makeEditor(fixture, access: access)
            let openedChooser = await reviewing.openDay(civilDate: key.civilDate.canonicalString,
                                                        timeZone: key.ianaTimeZoneIdentifier)
            XCTAssertTrue(openedChooser)
            let target = try await access.savePlan(makeEmptyPlanRequest(access: access, key: key,
                recorder: "Other recorder", predecessor: nil))
            let requested = await reviewing.requestStalePlanReview(draftID: draftID)
            XCTAssertTrue(requested)
            XCTAssertEqual(try XCTUnwrap(reviewing.classificationWrite).evidence.currentCheckpoint.draftID, draftID)
            let classified = await reviewing.confirmStalePlanReview()
            XCTAssertTrue(classified)
            let review = try XCTUnwrap(reviewing.conflictReview)
            XCTAssertEqual(review.reviewRequest.predecessor, target.targetResult.plan)
            let rebased = await reviewing.confirmReviewedRebase()
            XCTAssertTrue(rebased)
            let resumed = try XCTUnwrap(reviewing.editingSession)
            XCTAssertEqual(resumed.draftID, draftID)
            XCTAssertEqual(resumed.request.predecessor, target.targetResult.plan)
            let saved = await reviewing.save()
            XCTAssertTrue(saved)
            XCTAssertEqual(try XCTUnwrap(reviewing.outcome).checkpoint.draftID, draftID)
            reviewing.discardPresentation()
        }
        #else
        throw XCTSkip("Planning interruption hooks require DEBUG.")
        #endif
    }
    @MainActor
    func testConflictAcknowledgementRetriesReuseExactClassificationAndRebaseWritesWithoutExtraRevision() async throws {
        #if DEBUG
        let fixture = try await makeFixture("conflict-editor-acknowledgement-retry")
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let key = try day(fixture)
        let context = try access.captureConfirmedPlanningContext(for: key, recordedByName: "Conflict recorder")
        let request = try MyDayPlanningPlanSaveRequestV1(confirmedContext: context,
            draft: .init(key: key, items: [], eligibleReferences: []), predecessor: nil)
        let checkpoint = try access.persistEditingWrite(access.prepareEditingWrite(request, replacing: nil,
            resumeAnchor: .init(sectionID: "my-day"))).checkpoint
        _ = try await access.savePlan(makeEmptyPlanRequest(access: access, key: key,
            recorder: "Other recorder", predecessor: nil))
        let editor = makeEditor(fixture, access: access)
        let opened = await editor.openDay(civilDate: key.civilDate.canonicalString,
                                          timeZone: key.ianaTimeZoneIdentifier)
        XCTAssertTrue(opened)
        let requested = await editor.requestStalePlanReview(draftID: checkpoint.draftID)
        XCTAssertTrue(requested)
        let classification = try XCTUnwrap(editor.classificationWrite)
        var classificationAcknowledged = false
        editor.afterClassificationAcknowledgementForTesting = { acknowledgement in
            classificationAcknowledged = acknowledgement.checkpoint == classification.checkpoint
            throw EditorInterruption.injected
        }
        let firstClassification = await editor.confirmStalePlanReview()
        XCTAssertFalse(firstClassification)
        XCTAssertTrue(classificationAcknowledged)
        let classificationRevision = try fixture.coordinator.workspaceWriter.currentRevision()
        XCTAssertEqual(try access.loadPlanningCheckpoint(draftID: checkpoint.draftID), classification.checkpoint)
        XCTAssertEqual(editor.classificationWrite, classification)
        let cancelledClassification = await editor.cancelPreparedConflictReview()
        XCTAssertFalse(cancelledClassification)
        let closedClassification = await editor.flush(reason: .navigation)
        XCTAssertFalse(closedClassification)
        let backgroundClassification = await editor.flush(reason: .background)
        XCTAssertFalse(backgroundClassification)
        XCTAssertEqual(editor.classificationWrite, classification)
        editor.afterClassificationAcknowledgementForTesting = nil
        let retriedClassification = await editor.retryStalePlanReview()
        XCTAssertTrue(retriedClassification)
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), classificationRevision)
        XCTAssertNotNil(editor.conflictReview)

        let review = try XCTUnwrap(editor.conflictReview)
        var rebaseAcknowledged = false
        editor.afterReviewedRebaseAcknowledgementForTesting = { acknowledgement in
            rebaseAcknowledged = acknowledgement.checkpoint.draftID == checkpoint.draftID
            throw EditorInterruption.injected
        }
        let firstRebase = await editor.confirmReviewedRebase()
        XCTAssertFalse(firstRebase)
        XCTAssertTrue(rebaseAcknowledged)
        let rebase = try XCTUnwrap(editor.reviewedRebaseWrite)
        let rebaseRevision = try fixture.coordinator.workspaceWriter.currentRevision()
        XCTAssertEqual(try access.loadPlanningCheckpoint(draftID: checkpoint.draftID), rebase.resolution.successorCheckpoint)
        let cancelledRebase = await editor.cancelPreparedConflictReview()
        XCTAssertFalse(cancelledRebase)
        let closedRebase = await editor.flush(reason: .navigation)
        XCTAssertFalse(closedRebase)
        let backgroundRebase = await editor.flush(reason: .background)
        XCTAssertFalse(backgroundRebase)
        XCTAssertEqual(editor.reviewedRebaseWrite, rebase)
        let replacedRebase = await editor.confirmReviewedRebase()
        XCTAssertFalse(replacedRebase)
        XCTAssertEqual(editor.reviewedRebaseWrite, rebase)
        editor.afterReviewedRebaseAcknowledgementForTesting = nil
        let retriedRebase = await editor.retryReviewedRebase()
        XCTAssertTrue(retriedRebase)
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), rebaseRevision)
        XCTAssertEqual(try XCTUnwrap(editor.editingSession).draftID, checkpoint.draftID)
        XCTAssertEqual(try XCTUnwrap(editor.editingSession).request.predecessor, review.reviewRequest.predecessor)
        editor.discardPresentation()
        #else
        throw XCTSkip("Planning acknowledgement hooks require DEBUG.")
        #endif
    }

    @MainActor
    func testPreparedConflictReviewCancellationReturnsTheVisibleActiveDraftWithoutEffects() async throws {
        let fixture = try await makeFixture("conflict-editor-cancel-prepared")
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let key = try day(fixture)
        let context = try access.captureConfirmedPlanningContext(for: key, recordedByName: "Conflict recorder")
        let request = try MyDayPlanningPlanSaveRequestV1(confirmedContext: context,
            draft: .init(key: key, items: [], eligibleReferences: []), predecessor: nil)
        let checkpoint = try access.persistEditingWrite(access.prepareEditingWrite(request, replacing: nil,
            resumeAnchor: .init(sectionID: "my-day"))).checkpoint
        _ = try await access.savePlan(makeEmptyPlanRequest(access: access, key: key,
            recorder: "Other recorder", predecessor: nil))
        let editor = makeEditor(fixture, access: access)
        let opened = await editor.openDay(civilDate: key.civilDate.canonicalString,
                                          timeZone: key.ianaTimeZoneIdentifier)
        XCTAssertTrue(opened)
        let before = try fixture.coordinator.workspaceWriter.currentRevision()
        let requested = await editor.requestStalePlanReview(draftID: checkpoint.draftID)
        XCTAssertTrue(requested)
        XCTAssertNotNil(editor.classificationWrite)
        XCTAssertTrue(editor.canCancelPreparedConflictReview)
        let cancelled = await editor.cancelPreparedConflictReview()
        XCTAssertTrue(cancelled)
        XCTAssertNil(editor.classificationWrite)
        XCTAssertNil(editor.conflictReview)
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), before)
        XCTAssertEqual(try access.loadPlanningCheckpoint(draftID: checkpoint.draftID), checkpoint)
        XCTAssertEqual(editor.checkpoints, [checkpoint])
        editor.discardPresentation()
    }
    @MainActor
    func testConflictReviewDeniesUnchangedGenericAndCarryoverChooserWithoutEffects() async throws {
        let fixture = try await makeFixture("conflict-editor-unchanged-and-generic")
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let key = try day(fixture)
        let request = try makeEmptyPlanRequest(access: access, key: key, recorder: "Recorder", predecessor: nil)
        let checkpoint = try access.persistEditingWrite(access.prepareEditingWrite(request,
            replacing: nil, resumeAnchor: .init(sectionID: "my-day"))).checkpoint
        let generic = try seedSource(fixture)
        let editor = makeEditor(fixture, access: access)
        let opened = await editor.openDay(civilDate: key.civilDate.canonicalString,
                                          timeZone: key.ianaTimeZoneIdentifier)
        XCTAssertTrue(opened)
        let before = try fixture.coordinator.workspaceWriter.currentRevision()
        let unchanged = await editor.requestStalePlanReview(draftID: checkpoint.draftID)
        let foreign = await editor.requestStalePlanReview(draftID: generic.draftID)
        XCTAssertFalse(unchanged || foreign)
        XCTAssertNil(editor.classificationWrite)
        XCTAssertEqual(try access.loadPlanningCheckpoint(draftID: checkpoint.draftID), checkpoint)
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), before)
        editor.discardPresentation()

        let carryFixture = try await makeFixture("conflict-editor-carryover-denial")
        let carryAccess = try XCTUnwrap(carryFixture.presentation.myDayAccess)
        let seed = try await seedCarryoverEditorSource(carryFixture, access: carryAccess)
        let original = try await openCarryoverEditor(carryFixture, access: carryAccess)
        let began = await original.beginCarryover(selectedMembershipIDs: seed.source.items.map(\.membershipID),
                                                  recordedByName: "Carryover recorder")
        XCTAssertTrue(began)
        let session = try XCTUnwrap(original.carryoverEditingSession)
        try await session.forceFlush(reason: .navigation)
        let carryCheckpoint = try carryAccess.loadPlanningCheckpoint(draftID: session.draftID)
        let carryKey = session.request.confirmedContext.key
        original.discardPresentation()
        let chooser = makeEditor(carryFixture, access: carryAccess)
        let carryOpened = await chooser.openDay(civilDate: carryKey.civilDate.canonicalString,
                                                timeZone: carryKey.ianaTimeZoneIdentifier)
        XCTAssertTrue(carryOpened)
        let carryBefore = try carryFixture.coordinator.workspaceWriter.currentRevision()
        let reviewed = await chooser.requestStalePlanReview(draftID: carryCheckpoint.draftID)
        XCTAssertFalse(reviewed)
        XCTAssertNil(chooser.classificationWrite)
        XCTAssertEqual(try carryAccess.loadPlanningCheckpoint(draftID: carryCheckpoint.draftID), carryCheckpoint)
        XCTAssertEqual(try carryFixture.coordinator.workspaceWriter.currentRevision(), carryBefore)
        chooser.discardPresentation()
    }

    @MainActor
    func testConflictChooserRejectsActualPostTargetSavePrefixesEvenAfterLaterTargetChange() async throws {
        #if DEBUG
        for point in [MyDayPlanningEffectPointV1.targetCommit, .targetCommittedSaga, .retirePendingSaga] {
            let fixture = try await makeFixture("conflict-editor-post-target-\(point.rawValue)")
            let access = try XCTUnwrap(fixture.presentation.myDayAccess)
            let key = try day(fixture)
            let original = makeEditor(fixture, access: access)
            let opened = await original.openDay(civilDate: key.civilDate.canonicalString,
                                                timeZone: key.ianaTimeZoneIdentifier)
            let began = await original.beginNew(recordedByName: "Recorder")
            XCTAssertTrue(opened && began)
            let session = try XCTUnwrap(original.editingSession)
            var injected = false
            access.setPlanningEffectHookForTesting { actual in
                guard actual == point, !injected else { return }
                injected = true
                throw EditorInterruption.injected
            }
            let saved = await original.save()
            access.setPlanningEffectHookForTesting(nil)
            XCTAssertFalse(saved)
            XCTAssertTrue(injected)
            let checkpoint = try access.loadPlanningCheckpoint(draftID: session.draftID)
            XCTAssertEqual(checkpoint.state, .committing)
            let target = try XCTUnwrap(access.planningContext(for: key).currentPlan)
            _ = try await access.savePlan(makeEmptyPlanRequest(access: access, key: key,
                recorder: "Later recorder", predecessor: target))
            original.discardPresentation()
            let chooser = makeEditor(fixture, access: access)
            let chooserOpened = await chooser.openDay(civilDate: key.civilDate.canonicalString,
                                                       timeZone: key.ianaTimeZoneIdentifier)
            XCTAssertTrue(chooserOpened)
            let before = try fixture.coordinator.workspaceWriter.currentRevision()
            let denied = await chooser.requestStalePlanReview(draftID: checkpoint.draftID)
            XCTAssertFalse(denied)
            XCTAssertNil(chooser.classificationWrite)
            XCTAssertNil(chooser.conflictReview)
            XCTAssertNil(chooser.outcome)
            XCTAssertEqual(try access.loadPlanningCheckpoint(draftID: checkpoint.draftID), checkpoint)
            XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), before)
            chooser.discardPresentation()
        }
        #endif
    }

    @MainActor
    func testConflictAcknowledgementAndRebaseResumeAccessRevocationCannotPublishOldState() async throws {
        #if DEBUG
        for stage in ["classification", "rebase", "resume"] {
            let fixture = try await makeFixture("conflict-editor-cover-\(stage)")
            let access = try XCTUnwrap(fixture.presentation.myDayAccess)
            let values = try await makeStaleConflictChooser(fixture, access: access)
            let editor = values.editor
            var durable: FieldDraftCheckpointV1?
            if stage == "classification" {
                editor.afterClassificationAcknowledgementForTesting = { acknowledgement in
                    durable = acknowledgement.checkpoint
                    fixture.presentation.receive(.sceneInactive)
                }
            } else {
                let classified = await editor.confirmStalePlanReview()
                XCTAssertTrue(classified)
                editor.afterReviewedRebaseAcknowledgementForTesting = { acknowledgement in
                    durable = acknowledgement.checkpoint
                    if stage == "rebase" { fixture.presentation.receive(.sceneInactive) }
                }
                if stage == "resume" {
                    editor.afterResumeSourcesReadyForTesting = { fixture.presentation.receive(.sceneInactive) }
                }
            }
            let completed = stage == "classification"
                ? await editor.confirmStalePlanReview() : await editor.confirmReviewedRebase()
            // Rebase is acknowledged before its subsequent source/session resume starts.
            XCTAssertEqual(completed, stage == "resume")
            let actual = try XCTUnwrap(durable)
            XCTAssertEqual(actual.draftID, values.checkpoint.draftID)
            XCTAssertEqual(actual.state, stage == "classification" ? .conflicted : .active)
            XCTAssertNil(editor.context)
            XCTAssertNil(editor.classificationWrite)
            XCTAssertNil(editor.reviewedRebaseWrite)
            XCTAssertNil(editor.conflictReview)
            XCTAssertNil(editor.editingSession)
            XCTAssertNil(editor.outcome)
            XCTAssertTrue(editor.checkpoints.isEmpty)
            let before = try fixture.coordinator.workspaceWriter.currentRevision()
            let published = expectation(description: "Fresh conflict chooser publication \(stage)")
            let observer = fixture.presentation.$permitsContentPresentation.filter { $0 }.prefix(1)
                .sink { _ in published.fulfill() }
            fixture.presentation.receive(.sceneActive)
            await fulfillment(of: [published], timeout: 30)
            observer.cancel()
            let fresh = try XCTUnwrap(fixture.presentation.myDayAccess)
            XCTAssertEqual(try fresh.loadPlanningCheckpoint(draftID: actual.draftID), actual)
            let oldClassify = await editor.retryStalePlanReview()
            let oldRebase = await editor.retryReviewedRebase()
            XCTAssertFalse(oldClassify || oldRebase)
            XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), before)
            let chooser = makeEditor(fixture, access: fresh)
            let key = try day(fixture)
            let opened = await chooser.openDay(civilDate: key.civilDate.canonicalString,
                                               timeZone: key.ianaTimeZoneIdentifier)
            XCTAssertTrue(opened)
            XCTAssertEqual(chooser.checkpoints, [actual])
            chooser.discardPresentation()
        }
        #endif
    }

    @MainActor
    func testAcknowledgedRebaseLeavesActiveChooserWhenSourceReadFailsOrTargetChanges() async throws {
        #if DEBUG
        for drift in [false, true] {
            let fixture = try await makeFixture("conflict-editor-resume-failure-\(drift)")
            let access = try XCTUnwrap(fixture.presentation.myDayAccess)
            let values = try await makeStaleConflictChooser(fixture, access: access)
            let editor = values.editor
            let classified = await editor.confirmStalePlanReview()
            XCTAssertTrue(classified)
            let review = try XCTUnwrap(editor.conflictReview)
            var acknowledged: FieldDraftCheckpointV1?
            editor.afterReviewedRebaseAcknowledgementForTesting = { acknowledged = $0.checkpoint }
            editor.afterResumeSourcesReadyForTesting = {
                if drift {
                    _ = try await access.savePlan(self.makeEmptyPlanRequest(access: access,
                        key: review.originalEditingRequest.confirmedContext.key,
                        recorder: "Later recorder", predecessor: review.reviewRequest.predecessor))
                } else {
                    throw EditorInterruption.injected
                }
            }
            let rebased = await editor.confirmReviewedRebase()
            XCTAssertTrue(rebased)
            let actual = try XCTUnwrap(acknowledged)
            XCTAssertEqual(actual.state, .active)
            XCTAssertEqual(try access.loadPlanningCheckpoint(draftID: actual.draftID), actual)
            XCTAssertNil(editor.classificationWrite)
            XCTAssertNil(editor.reviewedRebaseWrite)
            XCTAssertNil(editor.conflictReview)
            XCTAssertNil(editor.editingSession)
            XCTAssertNil(editor.outcome)
            XCTAssertEqual(editor.checkpoints, [actual])
            XCTAssertNotNil(editor.errorMessage)
            XCTAssertFalse(editor.hasPendingPlanningOperation)
            editor.afterResumeSourcesReadyForTesting = nil
            if !drift {
                let resumed = await editor.resume(draftID: actual.draftID)
                XCTAssertTrue(resumed)
                XCTAssertEqual(try XCTUnwrap(editor.editingSession).draftID, actual.draftID)
            }
            editor.discardPresentation()
        }
        #endif
    }

    @MainActor
    func testCarryoverConflictEditorReviewsActualActiveAndPreTargetSavePrefixesThenSavesSameDraft() async throws {
        #if DEBUG
        for interruption in [nil, .committingCheckpoint, .preparedSaga, .contentPromotedSaga] as [MyDayPlanningEffectPointV1?] {
            let fixture = try await makeFixture("carryover-conflict-prefix-\(interruption?.rawValue ?? "active")")
            let access = try XCTUnwrap(fixture.presentation.myDayAccess)
            let values = try await makeStaleCarryoverConflictChooser(fixture, access: access, interruption: interruption?.rawValue)
            let editor = values.editor
            let beforeReview = try fixture.coordinator.workspaceWriter.currentRevision()
            let requested = await editor.requestStaleCarryoverReview(draftID: values.checkpoint.draftID)
            XCTAssertTrue(requested)
            XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), beforeReview)
            let classification = try XCTUnwrap(editor.carryoverClassificationWrite)
            XCTAssertEqual(classification.evidence.currentCheckpoint, values.checkpoint)
            let classified = await editor.confirmStaleCarryoverReview()
            XCTAssertTrue(classified)
            let review = try XCTUnwrap(editor.carryoverConflictReview)
            XCTAssertEqual(review.originalEditingRequest, values.request)
            XCTAssertEqual(review.reviewRequest.sourcePlan, values.request.sourcePlan)
            XCTAssertEqual(review.reviewRequest.selectedMembershipIDs, values.request.selectedMembershipIDs)
            XCTAssertEqual(review.reviewRequest.confirmedContext, values.request.confirmedContext)
            XCTAssertEqual(review.reviewRequest.targetPredecessor, try MyDayPlanReferenceV1(values.target))
            XCTAssertTrue(editor.isCarryoverConflictCandidate(review.pending.conflictedCheckpoint))
            let beforeBack = try fixture.coordinator.workspaceWriter.currentRevision()
            let backed = await editor.backToSavedDrafts()
            let reread = await editor.requestExistingCarryoverConflictReview(draftID: values.checkpoint.draftID)
            XCTAssertTrue(backed && reread)
            XCTAssertEqual(editor.carryoverConflictReview, review)
            XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), beforeBack)
            let rebased = await editor.confirmReviewedCarryoverRebase()
            XCTAssertTrue(rebased)
            let session = try XCTUnwrap(editor.carryoverEditingSession)
            XCTAssertNil(editor.editingSession)
            XCTAssertEqual(session.draftID, values.checkpoint.draftID)
            XCTAssertEqual(session.request, review.reviewRequest)
            let saved = await editor.save()
            XCTAssertTrue(saved)
            let outcome = try XCTUnwrap(editor.outcome)
            XCTAssertEqual(outcome.checkpoint.draftID, values.checkpoint.draftID)
            XCTAssertEqual(outcome.checkpoint.state, .committed)
            XCTAssertEqual(outcome.targetResult.plan.items.map(\.reference), values.source.items.map(\.reference))
            XCTAssertEqual(outcome.targetResult.plan.items.map(\.estimate), values.source.items.map(\.estimate))
            XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentPlan(for: values.source.key), values.source)
            let adapter = try fixture.coordinator.workspaceWriter.makeFieldDraftLifecycleAdapter(modelContext: fixture.coordinator.modelContext)
            for work in values.work {
                XCTAssertEqual(try adapter.currentCheckpoint(workspaceID: work.workspaceID, draftID: work.draftID), work)
            }
            XCTAssertEqual(try count(MyDayCarryoverReceiptRowV1.self, fixture), 1)
            editor.discardPresentation()
            await session.invalidate()
        }
        #endif
    }

    @MainActor
    func testCarryoverConflictEditorRetainsActualCleanFailedSaveSessionUntilClassificationAcknowledges() async throws {
        let fixture = try await makeFixture("carryover-conflict-live-session")
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let seed = try await seedCarryoverEditorSource(fixture, access: access)
        let editor = try await openCarryoverEditor(fixture, access: access)
        let began = await editor.beginCarryover(selectedMembershipIDs: seed.source.items.reversed().map(\.membershipID), recordedByName: "Carryover recorder")
        XCTAssertTrue(began)
        let session = try XCTUnwrap(editor.carryoverEditingSession)
        try await session.forceFlush(reason: .navigation)
        _ = try await access.savePlan(makeEmptyPlanRequest(access: access, key: session.request.confirmedContext.key, recorder: "Other recorder", predecessor: nil))
        let failed = await editor.save()
        XCTAssertFalse(failed)
        XCTAssertEqual(session.durabilityState, .saveBlocked)
        XCTAssertFalse(session.hasDirtyChanges)
        let before = try fixture.coordinator.workspaceWriter.currentRevision()
        let requested = await editor.requestStaleCarryoverReview()
        XCTAssertTrue(requested)
        XCTAssertTrue(editor.carryoverEditingSession === session)
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), before)
        let classified = await editor.confirmStaleCarryoverReview()
        XCTAssertTrue(classified)
        XCTAssertNil(editor.carryoverEditingSession)
        XCTAssertEqual(try XCTUnwrap(editor.carryoverConflictReview).originalEditingRequest, session.request)
        XCTAssertEqual(try count(MyDayCarryoverReceiptRowV1.self, fixture), 0)
        editor.discardPresentation()
        await session.invalidate()
    }

    @MainActor
    func testCarryoverConflictEditorExactAcknowledgementRetriesBlockCancelCloseAndBackground() async throws {
        #if DEBUG
        let fixture = try await makeFixture("carryover-conflict-ack-retry")
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let values = try await makeStaleCarryoverConflictChooser(fixture, access: access)
        let editor = values.editor
        let requested = await editor.requestStaleCarryoverReview(draftID: values.checkpoint.draftID)
        XCTAssertTrue(requested)
        let classification = try XCTUnwrap(editor.carryoverClassificationWrite)
        var acknowledged = false
        editor.afterClassificationAcknowledgementForTesting = {
            acknowledged = $0.checkpoint == classification.checkpoint
            throw EditorInterruption.injected
        }
        let classified = await editor.confirmStaleCarryoverReview()
        XCTAssertFalse(classified)
        XCTAssertTrue(acknowledged)
        let afterClassification = try fixture.coordinator.workspaceWriter.currentRevision()
        XCTAssertEqual(try access.loadPlanningCheckpoint(draftID: values.checkpoint.draftID), classification.checkpoint)
        XCTAssertEqual(editor.carryoverClassificationWrite, classification)
        let cancelClassify = await editor.cancelPreparedConflictReview()
        let closeClassify = await editor.flush(reason: .navigation)
        let backgroundClassify = await editor.flush(reason: .background)
        XCTAssertFalse(cancelClassify || closeClassify || backgroundClassify)
        XCTAssertEqual(editor.carryoverClassificationWrite, classification)
        editor.afterClassificationAcknowledgementForTesting = nil
        let retriedClassify = await editor.retryStaleCarryoverReview()
        XCTAssertTrue(retriedClassify)
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), afterClassification)
        let review = try XCTUnwrap(editor.carryoverConflictReview)
        acknowledged = false
        editor.afterReviewedRebaseAcknowledgementForTesting = {
            acknowledged = $0.checkpoint.draftID == values.checkpoint.draftID
            throw EditorInterruption.injected
        }
        let rebased = await editor.confirmReviewedCarryoverRebase()
        XCTAssertFalse(rebased)
        XCTAssertTrue(acknowledged)
        let write = try XCTUnwrap(editor.reviewedCarryoverRebaseWrite)
        let afterRebase = try fixture.coordinator.workspaceWriter.currentRevision()
        XCTAssertEqual(try access.loadPlanningCheckpoint(draftID: values.checkpoint.draftID), write.resolution.successorCheckpoint)
        let cancelRebase = await editor.cancelPreparedConflictReview()
        let closeRebase = await editor.flush(reason: .navigation)
        let backgroundRebase = await editor.flush(reason: .background)
        let replaceWrite = await editor.confirmReviewedCarryoverRebase()
        XCTAssertFalse(cancelRebase || closeRebase || backgroundRebase || replaceWrite)
        XCTAssertEqual(editor.reviewedCarryoverRebaseWrite, write)
        editor.afterReviewedRebaseAcknowledgementForTesting = nil
        let retriedRebase = await editor.retryReviewedCarryoverRebase()
        XCTAssertTrue(retriedRebase)
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), afterRebase)
        let session = try XCTUnwrap(editor.carryoverEditingSession)
        XCTAssertEqual(session.request, review.reviewRequest)
        XCTAssertEqual(session.draftID, values.checkpoint.draftID)
        XCTAssertEqual(try count(MyDayCarryoverReceiptRowV1.self, fixture), 0)
        editor.discardPresentation()
        await session.invalidate()
        #endif
    }

    @MainActor
    func testCarryoverConflictEditorCancelsPreparedClassificationWithoutAnyEffect() async throws {
        let fixture = try await makeFixture("carryover-conflict-cancel")
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let values = try await makeStaleCarryoverConflictChooser(fixture, access: access)
        let before = try fixture.coordinator.workspaceWriter.currentRevision()
        let requested = await values.editor.requestStaleCarryoverReview(draftID: values.checkpoint.draftID)
        XCTAssertTrue(requested)
        XCTAssertTrue(values.editor.canCancelPreparedConflictReview)
        let cancelled = await values.editor.cancelPreparedConflictReview()
        XCTAssertTrue(cancelled)
        XCTAssertNil(values.editor.carryoverClassificationWrite)
        XCTAssertNil(values.editor.carryoverConflictReview)
        XCTAssertNil(values.editor.reviewedCarryoverRebaseWrite)
        XCTAssertEqual(values.editor.checkpoints, [values.checkpoint])
        XCTAssertEqual(try access.loadPlanningCheckpoint(draftID: values.checkpoint.draftID), values.checkpoint)
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), before)
        XCTAssertEqual(try count(MyDayCarryoverReceiptRowV1.self, fixture), 0)
        XCTAssertFalse(fixture.coordinator.modelContext.hasChanges)
        values.editor.discardPresentation()
    }

    @MainActor
    func testCarryoverConflictEditorTargetOrSourceDriftAtClassificationOrRebaseLeavesNoNewEffect() async throws {
        for (stage, sourceDrift) in [("classification", false), ("rebase", false), ("classification", true), ("rebase", true)] {
            let fixture = try await makeFixture("carryover-conflict-target-drift-\(stage)-\(sourceDrift)")
            let access = try XCTUnwrap(fixture.presentation.myDayAccess)
            let values = try await makeStaleCarryoverConflictChooser(fixture, access: access)
            let editor = values.editor
            let requested = await editor.requestStaleCarryoverReview(draftID: values.checkpoint.draftID)
            XCTAssertTrue(requested)
            if stage == "rebase" {
                let classified = await editor.confirmStaleCarryoverReview()
                XCTAssertTrue(classified)
            }
            let original = try access.loadPlanningCheckpoint(draftID: values.checkpoint.draftID)
            _ = try await access.savePlan(makeEmptyPlanRequest(access: access, key: sourceDrift ? values.source.key : values.request.confirmedContext.key, recorder: "Later recorder", predecessor: sourceDrift ? values.source : values.target))
            let before = try fixture.coordinator.workspaceWriter.currentRevision()
            let completed = stage == "classification" ? await editor.confirmStaleCarryoverReview() : await editor.confirmReviewedCarryoverRebase()
            XCTAssertFalse(completed)
            XCTAssertEqual(try access.loadPlanningCheckpoint(draftID: original.draftID), original)
            XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), before)
            XCTAssertEqual(try count(MyDayCarryoverReceiptRowV1.self, fixture), 0)
            XCTAssertNil(editor.outcome)
            XCTAssertNil(editor.carryoverEditingSession)
            XCTAssertFalse(fixture.coordinator.modelContext.hasChanges)
            editor.discardPresentation()
        }
    }

    @MainActor
    func testCarryoverConflictEditorAcknowledgedRebaseKeepsVisibleActiveDraftWhenResumeFails() async throws {
        #if DEBUG
        for drift in [false, true] {
            let fixture = try await makeFixture("carryover-conflict-resume-failure-\(drift)")
            let access = try XCTUnwrap(fixture.presentation.myDayAccess)
            let values = try await makeStaleCarryoverConflictChooser(fixture, access: access)
            let editor = values.editor
            let requested = await editor.requestStaleCarryoverReview(draftID: values.checkpoint.draftID)
            let classified = await editor.confirmStaleCarryoverReview()
            XCTAssertTrue(requested && classified)
            var acknowledged: FieldDraftCheckpointV1?
            editor.afterReviewedRebaseAcknowledgementForTesting = { acknowledged = $0.checkpoint }
            editor.afterResumeSourcesReadyForTesting = {
                if drift {
                    _ = try await access.savePlan(self.makeEmptyPlanRequest(access: access, key: values.request.confirmedContext.key, recorder: "Later recorder", predecessor: values.target))
                } else { throw EditorInterruption.injected }
            }
            let completed = await editor.confirmReviewedCarryoverRebase()
            XCTAssertTrue(completed)
            let actual = try XCTUnwrap(acknowledged)
            XCTAssertEqual(actual.draftID, values.checkpoint.draftID)
            XCTAssertEqual(actual.state, .active)
            XCTAssertEqual(try access.loadPlanningCheckpoint(draftID: actual.draftID), actual)
            XCTAssertEqual(editor.checkpoints, [actual])
            XCTAssertNil(editor.carryoverClassificationWrite)
            XCTAssertNil(editor.reviewedCarryoverRebaseWrite)
            XCTAssertNil(editor.carryoverConflictReview)
            XCTAssertNil(editor.carryoverEditingSession)
            XCTAssertNil(editor.outcome)
            XCTAssertNotNil(editor.errorMessage)
            XCTAssertFalse(editor.hasPendingPlanningOperation)
            editor.afterResumeSourcesReadyForTesting = nil
            editor.discardPresentation()
            let fresh = makeEditor(fixture, access: access)
            let opened = await fresh.openDay(civilDate: "2026-09-13", timeZone: "Europe/London")
            XCTAssertTrue(opened)
            XCTAssertEqual(fresh.checkpoints, [actual])
            if !drift {
                let resumed = await fresh.resume(draftID: actual.draftID)
                XCTAssertTrue(resumed)
                XCTAssertEqual(try XCTUnwrap(fresh.carryoverEditingSession).draftID, actual.draftID)
            }
            fresh.discardPresentation()
        }
        #endif
    }

    @MainActor
    func testCarryoverConflictEditorCoverAtAcknowledgementOrResumeRevokesOldPublication() async throws {
        #if DEBUG
        for stage in ["classification", "rebase", "resume"] {
            let fixture = try await makeFixture("carryover-conflict-cover-\(stage)")
            let access = try XCTUnwrap(fixture.presentation.myDayAccess)
            let values = try await makeStaleCarryoverConflictChooser(fixture, access: access)
            let editor = values.editor
            let requested = await editor.requestStaleCarryoverReview(draftID: values.checkpoint.draftID)
            XCTAssertTrue(requested)
            var durable: FieldDraftCheckpointV1?
            if stage == "classification" {
                editor.afterClassificationAcknowledgementForTesting = {
                    durable = $0.checkpoint
                    fixture.presentation.receive(.sceneInactive)
                }
            } else {
                let classified = await editor.confirmStaleCarryoverReview()
                XCTAssertTrue(classified)
                editor.afterReviewedRebaseAcknowledgementForTesting = {
                    durable = $0.checkpoint
                    if stage == "rebase" { fixture.presentation.receive(.sceneInactive) }
                }
                if stage == "resume" {
                    editor.afterResumeSourcesReadyForTesting = { fixture.presentation.receive(.sceneInactive) }
                }
            }
            let completed = stage == "classification" ? await editor.confirmStaleCarryoverReview() : await editor.confirmReviewedCarryoverRebase()
            XCTAssertEqual(completed, stage == "resume")
            let actual = try XCTUnwrap(durable)
            XCTAssertEqual(actual.state, stage == "classification" ? .conflicted : .active)
            XCTAssertNil(editor.context)
            XCTAssertNil(editor.carryoverClassificationWrite)
            XCTAssertNil(editor.reviewedCarryoverRebaseWrite)
            XCTAssertNil(editor.carryoverConflictReview)
            XCTAssertNil(editor.carryoverEditingSession)
            XCTAssertNil(editor.carryoverSourcePlan)
            XCTAssertNil(editor.carryoverSources)
            XCTAssertTrue(editor.checkpoints.isEmpty)
            let before = try fixture.coordinator.workspaceWriter.currentRevision()
            let published = expectation(description: "Fresh carryover conflict publication \(stage)")
            let observer = fixture.presentation.$permitsContentPresentation.filter { $0 }.prefix(1).sink { _ in published.fulfill() }
            fixture.presentation.receive(.sceneActive)
            await fulfillment(of: [published], timeout: 30)
            observer.cancel()
            let fresh = try XCTUnwrap(fixture.presentation.myDayAccess)
            XCTAssertEqual(try fresh.loadPlanningCheckpoint(draftID: actual.draftID), actual)
            let oldClassify = await editor.retryStaleCarryoverReview()
            let oldRebase = await editor.retryReviewedCarryoverRebase()
            XCTAssertFalse(oldClassify || oldRebase)
            XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), before)
            let chooser = makeEditor(fixture, access: fresh)
            let opened = await chooser.openDay(civilDate: "2026-09-13", timeZone: "Europe/London")
            XCTAssertTrue(opened)
            XCTAssertEqual(chooser.checkpoints, [actual])
            chooser.discardPresentation()
        }
        #endif
    }

    @MainActor
    func testCarryoverConflictChooserRejectsOrdinaryConflictedGenericAndUnchangedCarryoverWithoutEffects() async throws {
        let fixture = try await makeFixture("carryover-conflict-hostile-plan")
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let values = try await makeStaleConflictChooser(fixture, access: access)
        let cancelled = await values.editor.cancelPreparedConflictReview()
        XCTAssertTrue(cancelled)
        let generic = try seedSource(fixture)
        let before = try fixture.coordinator.workspaceWriter.currentRevision()
        let plan = await values.editor.requestStaleCarryoverReview(draftID: values.checkpoint.draftID)
        let other = await values.editor.requestStaleCarryoverReview(draftID: generic.draftID)
        XCTAssertFalse(plan || other)
        XCTAssertFalse(values.editor.isCarryoverConflictCandidate(values.checkpoint))
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), before)
        let requested = await values.editor.requestStalePlanReview(draftID: values.checkpoint.draftID)
        let classified = await values.editor.confirmStalePlanReview()
        let backed = await values.editor.backToSavedDrafts()
        XCTAssertTrue(requested && classified && backed)
        let localConflict = try access.loadPlanningCheckpoint(draftID: values.checkpoint.draftID)
        let after = try fixture.coordinator.workspaceWriter.currentRevision()
        XCTAssertFalse(values.editor.isCarryoverConflictCandidate(localConflict))
        let existing = await values.editor.requestExistingCarryoverConflictReview(draftID: localConflict.draftID)
        XCTAssertFalse(existing)
        XCTAssertNil(values.editor.carryoverConflictReview)
        XCTAssertEqual(try access.loadPlanningCheckpoint(draftID: localConflict.draftID), localConflict)
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), after)
        values.editor.discardPresentation()

        let carryFixture = try await makeFixture("carryover-conflict-unchanged")
        let carryAccess = try XCTUnwrap(carryFixture.presentation.myDayAccess)
        let seed = try await seedCarryoverEditorSource(carryFixture, access: carryAccess)
        let original = try await openCarryoverEditor(carryFixture, access: carryAccess)
        let began = await original.beginCarryover(selectedMembershipIDs: seed.source.items.map(\.membershipID), recordedByName: "Carryover recorder")
        XCTAssertTrue(began)
        let session = try XCTUnwrap(original.carryoverEditingSession)
        try await session.forceFlush(reason: .navigation)
        let checkpoint = try carryAccess.loadPlanningCheckpoint(draftID: session.draftID)
        original.discardPresentation()
        await session.invalidate()
        let chooser = makeEditor(carryFixture, access: carryAccess)
        let opened = await chooser.openDay(civilDate: "2026-09-13", timeZone: "Europe/London")
        XCTAssertTrue(opened)
        let carryBefore = try carryFixture.coordinator.workspaceWriter.currentRevision()
        let unchanged = await chooser.requestStaleCarryoverReview(draftID: checkpoint.draftID)
        XCTAssertFalse(unchanged)
        XCTAssertNil(chooser.carryoverClassificationWrite)
        XCTAssertEqual(try carryAccess.loadPlanningCheckpoint(draftID: checkpoint.draftID), checkpoint)
        XCTAssertEqual(try carryFixture.coordinator.workspaceWriter.currentRevision(), carryBefore)
        XCTAssertEqual(try count(MyDayCarryoverReceiptRowV1.self, carryFixture), 0)
        XCTAssertFalse(carryFixture.coordinator.modelContext.hasChanges)
        chooser.discardPresentation()
    }

    @MainActor
    func testCarryoverConflictChooserRejectsActualPostTargetSavePrefixesEvenAfterTargetAdvance() async throws {
        #if DEBUG
        for point in [MyDayPlanningEffectPointV1.targetCommit, .targetCommittedSaga, .retirePendingSaga] {
            let fixture = try await makeFixture("carryover-conflict-post-target-\(point.rawValue)")
            let access = try XCTUnwrap(fixture.presentation.myDayAccess)
            let values = try await makeStaleCarryoverConflictChooser(fixture, access: access, interruption: point.rawValue)
            let before = try fixture.coordinator.workspaceWriter.currentRevision()
            let receiptsBefore = try count(MyDayCarryoverReceiptRowV1.self, fixture)
            let reviewed = await values.editor.requestStaleCarryoverReview(draftID: values.checkpoint.draftID)
            XCTAssertFalse(reviewed)
            XCTAssertNil(values.editor.carryoverClassificationWrite)
            XCTAssertNil(values.editor.carryoverConflictReview)
            XCTAssertNil(values.editor.outcome)
            XCTAssertEqual(try access.loadPlanningCheckpoint(draftID: values.checkpoint.draftID), values.checkpoint)
            XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), before)
            XCTAssertEqual(try count(MyDayCarryoverReceiptRowV1.self, fixture), receiptsBefore)
            XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentPlan(for: values.source.key), values.source)
            XCTAssertFalse(fixture.coordinator.modelContext.hasChanges)
            values.editor.discardPresentation()
        }
        #endif
    }

    @MainActor
    func testCarryoverConflictEditorRejectsActualDamagedStagedAndRecoveryRowsWithoutEffects() async throws {
        for variant in ["damaged", "staged", "recovery"] {
            let fixture = try await makeFixture("carryover-conflict-invalid-row-\(variant)")
            let access = try XCTUnwrap(fixture.presentation.myDayAccess)
            let values = try await makeStaleCarryoverConflictChooser(fixture, access: access)
            let original = values.checkpoint
            let hostile = try FieldDraftCheckpointV1(draftID: original.draftID,
                workspaceID: original.workspaceID, scope: original.scope, purpose: original.purpose,
                codec: original.codec, baseCanonicalRevision: original.baseCanonicalRevision,
                draftRevision: original.draftRevision,
                payloadData: variant == "damaged" ? Data("invalid-carryover-payload".utf8) : original.payloadData,
                stageIDs: variant == "staged" ? [UUID()] : [], resumeAnchor: original.resumeAnchor,
                state: variant == "recovery" ? .recoveryRequired : .active,
                lastDurableMutationID: original.lastDurableMutationID,
                lastReceiptSHA256: original.lastReceiptSHA256,
                updatedAt: original.updatedAt, mutationID: original.mutationID)
            let context = fixture.coordinator.modelContext
            let oldRow = try XCTUnwrap(context.fetch(FetchDescriptor<FieldDraftCheckpointRow>()).first { $0.draftID == original.draftID })
            context.delete(oldRow)
            try context.save()
            let hostileRow = try FieldDraftCheckpointRow(hostile)
            context.insert(hostileRow)
            try context.save()
            XCTAssertFalse(values.editor.isCarryoverConflictCandidate(hostile))
            let before = try fixture.coordinator.workspaceWriter.currentRevision()
            let rowsBefore = try count(FieldDraftCheckpointRow.self, fixture)
            let plansBefore = try count(MyDayPlanRowV1.self, fixture)
            let staleAction = await values.editor.requestStaleCarryoverReview(draftID: original.draftID)
            XCTAssertFalse(staleAction)
            XCTAssertNil(values.editor.carryoverClassificationWrite)
            values.editor.discardPresentation()
            let fresh = makeEditor(fixture, access: access)
            let opened = await fresh.openDay(civilDate: "2026-09-13", timeZone: "Europe/London")
            XCTAssertEqual(opened, variant == "recovery")
            let requested = await fresh.requestStaleCarryoverReview(draftID: original.draftID)
            let reviewed = await fresh.requestExistingCarryoverConflictReview(draftID: original.draftID)
            XCTAssertFalse(requested || reviewed)
            XCTAssertNil(fresh.carryoverClassificationWrite)
            XCTAssertNil(fresh.carryoverConflictReview)
            XCTAssertNil(fresh.outcome)
            XCTAssertEqual(try hostileRow.value(), hostile)
            XCTAssertEqual(try count(FieldDraftCheckpointRow.self, fixture), rowsBefore)
            XCTAssertEqual(try count(MyDayPlanRowV1.self, fixture), plansBefore)
            XCTAssertEqual(try count(MyDayCarryoverReceiptRowV1.self, fixture), 0)
            XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), before)
            XCTAssertFalse(context.hasChanges)
            fresh.discardPresentation()
        }
    }

    @MainActor
    func testCarryoverConflictChooserRejectsGenuineImportedCarryoverCheckpointWithoutEffects() async throws {
        let fixture = try await makeFixture("carryover-editor-genuine-import")
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let seed = try await seedCarryoverEditorSource(fixture, access: access)
        let targetKey = try MyDayKeyV1(workspaceID: fixture.coordinator.workspaceID,
            civilDate: .init("2026-09-13"), ianaTimeZoneIdentifier: "Europe/London")
        let confirmed = try access.captureConfirmedPlanningContext(for: targetKey, recordedByName: "Carryover recorder")
        let request = try MyDayPlanningCarryoverRequestV1(confirmedContext: confirmed,
            sourcePlan: MyDayPlanReferenceV1(seed.source),
            selectedMembershipIDs: seed.source.items.map(\.membershipID), targetPredecessor: nil)
        let prepared = try access.prepareCarryoverEditingWrite(request, replacing: nil,
            resumeAnchor: .init(sectionID: "carryover"))
        let checkpoint = prepared.checkpoint
        let producer = try CarryoverEditorImportedJournalNodeV1(workspaceID: fixture.coordinator.workspaceID,
            replicaID: .init(rawValue: UUID()))
        defer { producer.removeFiles() }
        for actor in [seed.source.authoredBy, confirmed.recordedBy] {
            producer.context.insert(try ActorSnapshotRow(actor))
        }
        try producer.context.save()
        let sourceAdapter = try producer.writer.makeFieldDraftLifecycleAdapter(modelContext: producer.context)
        for work in seed.work {
            _ = try sourceAdapter.compareAndSwap(checkpoint: work, expectedDraftRevision: 0, expectedBaseRevision: 0)
        }
        _ = try producer.writer.commit(MyDayCommandV1.save(successor: seed.source, predecessor: nil))
        let preparation = try producer.journal.prepareCheckpoint(supplement: .init(contentEntries: [], reversalEligibility: []))
        _ = try producer.journal.activatePreparedCheckpoint(preparation)
        _ = try producer.writer.commitFieldDraft(.init(workspaceID: checkpoint.workspaceID,
            expectedRevision: 0, expectedBaseCanonicalRevision: checkpoint.baseCanonicalRevision,
            mutationID: checkpoint.mutationID, postImage: .createCheckpoint(checkpoint)))
        XCTAssertEqual(try producer.writer.classifiableMyDayCarryoverEvidence(draftID: checkpoint.draftID).currentCheckpoint, checkpoint)
        let cursor = try producer.journal.initialCursor(consumerReplicaID: fixture.coordinator.replicaID)
        let page = try producer.journal.page(after: cursor)
        XCTAssertEqual(page.changes.map(\.envelope.mutationID), [checkpoint.mutationID])
        for change in page.changes { _ = try fixture.coordinator.workspaceWriter.executeImported(change) }
        let history = try fixture.coordinator.workspaceWriter.sourceMutationHistorySnapshot()
        XCTAssertFalse(history.receipts.isEmpty)
        let imported = try XCTUnwrap(fixture.coordinator.workspaceWriter.fieldDraftEvidence(mutationID: checkpoint.mutationID))
        XCTAssertEqual(imported.receipt.sourceKind, .importedHistory)
        _ = try await access.savePlan(makeEmptyPlanRequest(access: access, key: targetKey,
            recorder: "Other recorder", predecessor: nil))
        let editor = makeEditor(fixture, access: access)
        let opened = await editor.openDay(civilDate: "2026-09-13", timeZone: "Europe/London")
        XCTAssertTrue(opened)
        XCTAssertEqual(editor.checkpoints, [checkpoint])
        let before = try fixture.coordinator.workspaceWriter.currentRevision()
        let targetBefore = try fixture.coordinator.workspaceWriter.currentPlan(for: targetKey)
        let reviewed = await editor.requestStaleCarryoverReview(draftID: checkpoint.draftID)
        XCTAssertFalse(reviewed)
        XCTAssertNil(editor.carryoverClassificationWrite)
        XCTAssertNil(editor.carryoverConflictReview)
        XCTAssertNil(editor.reviewedCarryoverRebaseWrite)
        XCTAssertNil(editor.outcome)
        XCTAssertEqual(try access.loadPlanningCheckpoint(draftID: checkpoint.draftID), checkpoint)
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.fieldDraftEvidence(mutationID: checkpoint.mutationID), imported)
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), before)
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentPlan(for: targetKey), targetBefore)
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentPlan(for: seed.source.key), seed.source)
        let targetAdapter = try fixture.coordinator.workspaceWriter.makeFieldDraftLifecycleAdapter(modelContext: fixture.coordinator.modelContext)
        for work in seed.work {
            XCTAssertEqual(try targetAdapter.currentCheckpoint(workspaceID: work.workspaceID, draftID: work.draftID), work)
        }
        XCTAssertEqual(try count(MyDayCarryoverReceiptRowV1.self, fixture), 0)
        XCTAssertFalse(fixture.coordinator.modelContext.hasChanges)
        editor.discardPresentation()
    }

    @MainActor
    private func makeStaleCarryoverConflictChooser(_ fixture: V23ProductionMyDayPresentationHarness,
        access: AppAccessPresentationV1.MyDayAccess,
        interruption: String? = nil) async throws -> (
            editor: ProductionMyDayPlanningEditorStateV1, checkpoint: FieldDraftCheckpointV1,
            request: MyDayPlanningCarryoverRequestV1, source: MyDayPlanV1,
            target: MyDayPlanV1, work: [FieldDraftCheckpointV1]) {
        let seed = try await seedCarryoverEditorSource(fixture, access: access)
        let original = try await openCarryoverEditor(fixture, access: access)
        let began = await original.beginCarryover(selectedMembershipIDs: seed.source.items.reversed().map(\.membershipID), recordedByName: "Carryover recorder")
        XCTAssertTrue(began)
        let session = try XCTUnwrap(original.carryoverEditingSession)
        let request = session.request
        #if DEBUG
        if let interruption {
            var injected = false
            access.setPlanningEffectHookForTesting { point in
                guard point.rawValue == interruption, !injected else { return }
                injected = true
                throw EditorInterruption.injected
            }
            let completed = await original.save()
            access.setPlanningEffectHookForTesting(nil)
            XCTAssertFalse(completed)
            XCTAssertTrue(injected)
        } else { try await session.forceFlush(reason: .navigation) }
        #else
        try await session.forceFlush(reason: .navigation)
        #endif
        let checkpoint = try access.loadPlanningCheckpoint(draftID: session.draftID)
        XCTAssertEqual(checkpoint.state, interruption == nil ? .active : .committing)
        original.discardPresentation()
        await session.invalidate()
        let target = try await access.savePlan(makeEmptyPlanRequest(access: access,
            key: request.confirmedContext.key, recorder: "Other recorder",
            predecessor: try access.planningContext(for: request.confirmedContext.key).currentPlan))
        let editor = makeEditor(fixture, access: access)
        let opened = await editor.openDay(civilDate: "2026-09-13", timeZone: "Europe/London")
        XCTAssertTrue(opened)
        XCTAssertEqual(editor.checkpoints, [checkpoint])
        return (editor, checkpoint, request, seed.source, target.targetResult.plan, seed.work)
    }

    @MainActor
    private func makeStaleConflictChooser(_ fixture: V23ProductionMyDayPresentationHarness,
        access: AppAccessPresentationV1.MyDayAccess) async throws -> (
            editor: ProductionMyDayPlanningEditorStateV1, checkpoint: FieldDraftCheckpointV1) {
        let key = try day(fixture)
        let request = try makeEmptyPlanRequest(access: access, key: key, recorder: "Original recorder", predecessor: nil)
        let checkpoint = try access.persistEditingWrite(access.prepareEditingWrite(request,
            replacing: nil, resumeAnchor: .init(sectionID: "my-day"))).checkpoint
        _ = try await access.savePlan(makeEmptyPlanRequest(access: access, key: key,
            recorder: "Other recorder", predecessor: nil))
        let editor = makeEditor(fixture, access: access)
        let opened = await editor.openDay(civilDate: key.civilDate.canonicalString,
                                          timeZone: key.ianaTimeZoneIdentifier)
        let requested = await editor.requestStalePlanReview(draftID: checkpoint.draftID)
        XCTAssertTrue(opened && requested)
        XCTAssertNotNil(editor.classificationWrite)
        return (editor, checkpoint)
    }

    @MainActor
    private func makeDiscardChooser(_ fixture: V23ProductionMyDayPresentationHarness,
        access: AppAccessPresentationV1.MyDayAccess) async throws -> (
            editor: ProductionMyDayPlanningEditorStateV1, checkpoint: FieldDraftCheckpointV1,
            request: MyDayPlanningPlanSaveRequestV1, source: FieldDraftCheckpointV1) {
        let source = try seedSource(fixture)
        let key = try day(fixture)
        let context = try access.captureConfirmedPlanningContext(for: key, recordedByName: "Discard test recorder")
        let draft = try MyDayWorkflowCoordinatorV1.projectDraft(key: key,
            selectedItems: [.init(membershipID: access.nextPlanningMembershipID(), reference: reference(source), estimate: nil)],
            eligibleReferences: [reference(source)], predecessor: nil)
        let request = try MyDayPlanningPlanSaveRequestV1(confirmedContext: context, draft: draft, predecessor: nil)
        let write = try access.prepareEditingWrite(request, replacing: nil, resumeAnchor: .init(sectionID: "my-day"))
        let checkpoint = try access.persistEditingWrite(write).checkpoint
        let editor = makeEditor(fixture, access: access)
        let opened = await editor.openDay(civilDate: key.civilDate.canonicalString,
                                           timeZone: key.ianaTimeZoneIdentifier)
        XCTAssertTrue(opened)
        XCTAssertEqual(editor.checkpoints, [checkpoint])
        return (editor, checkpoint, request, source)
    }

    @MainActor
    private func makeEmptyPlanRequest(access: AppAccessPresentationV1.MyDayAccess, key: MyDayKeyV1,
                                      recorder: String, predecessor: MyDayPlanV1?) throws -> MyDayPlanningPlanSaveRequestV1 {
        let context = try access.captureConfirmedPlanningContext(for: key, recordedByName: recorder)
        return try .init(confirmedContext: context,
            draft: .init(key: key, items: [], eligibleReferences: []), predecessor: predecessor)
    }

    @MainActor
    private func assertDiscardSourcePreserved(_ source: FieldDraftCheckpointV1,
        fixture: V23ProductionMyDayPresentationHarness, file: StaticString = #filePath, line: UInt = #line) throws {
        let adapter = try fixture.coordinator.workspaceWriter.makeFieldDraftLifecycleAdapter(
            modelContext: fixture.coordinator.modelContext)
        XCTAssertEqual(try adapter.currentCheckpoint(workspaceID: source.workspaceID, draftID: source.draftID),
                       source, file: file, line: line)
        XCTAssertEqual(try count(MyDayPlanRowV1.self, fixture), 0, file: file, line: line)
        XCTAssertEqual(try count(DraftCommitReceiptRow.self, fixture), 0, file: file, line: line)
        XCTAssertEqual(try count(AttachmentStagingItemRow.self, fixture), 0, file: file, line: line)
        XCTAssertEqual(try count(DraftContentReservationRow.self, fixture), 0, file: file, line: line)
        XCTAssertFalse(fixture.coordinator.modelContext.hasChanges, file: file, line: line)
    }

    @MainActor
    private func makeFixture(_ name: String) async throws -> V23ProductionMyDayPresentationHarness {
        let fixture = try await V23ProductionMyDayPresentationHarness.start(testCase: self, name: name)
        addTeardownBlock { [support = fixture.support, defaults = fixture.defaults, suite = fixture.suiteName] in
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: support)
        }
        return fixture
    }

    @MainActor
    private func diagnoseMyDayPreparation<Value>(phase: String,
                                                 _ operation: () throws -> Value) throws -> Value {
        do {
            return try operation()
        } catch {
            print("V23 My Day diagnostic phase=\(phase) error=\(String(reflecting: error))")
            throw error
        }
    }

    @MainActor
    private func diagnoseMyDayFailure<Value>(phase: String,
                                             _ operation: () async throws -> Value) async throws -> Value {
        do {
            return try await operation()
        } catch {
            print("V23 My Day diagnostic phase=\(phase) error=\(String(reflecting: error))")
            throw error
        }
    }

    @MainActor
    private func makeEditor(_ fixture: V23ProductionMyDayPresentationHarness,
                            access: AppAccessPresentationV1.MyDayAccess) -> ProductionMyDayPlanningEditorStateV1 {
        .init(workspaceID: fixture.coordinator.workspaceID, access: access)
    }

    @MainActor
    private func day(_ fixture: V23ProductionMyDayPresentationHarness) throws -> MyDayKeyV1 {
        try .init(workspaceID: fixture.coordinator.workspaceID, civilDate: .init("2026-09-12"),
                  ianaTimeZoneIdentifier: "America/New_York")
    }

    @MainActor
    private func count<T: PersistentModel>(_ type: T.Type,
                                          _ fixture: V23ProductionMyDayPresentationHarness) throws -> Int {
        try fixture.coordinator.modelContext.fetch(FetchDescriptor<T>()).count
    }

    @MainActor
    private func seedSource(_ fixture: V23ProductionMyDayPresentationHarness) throws -> FieldDraftCheckpointV1 {
        let writer = fixture.coordinator.workspaceWriter
        let checkpoint = try FieldDraftCheckpointV1(draftID: UUID(), workspaceID: fixture.coordinator.workspaceID,
            scope: .init(scopeKind: "V23_MY_DAY_EDITOR_SOURCE", stableComponentIDs: ["source"]),
            purpose: .assetFieldEdit,
            codec: .init(codecID: "v23.my-day.editor-source.v1", codecVersion: 1,
                         releaseSHA256: String(repeating: "a", count: 64)),
            baseCanonicalRevision: 0, draftRevision: 1, payloadData: Data("source".utf8),
            stageIDs: [], resumeAnchor: .init(sectionID: "source"), state: .active,
            updatedAt: Date(timeIntervalSince1970: 1_789_084_800), mutationID: writer.makeMutationID())
        let adapter = try writer.makeFieldDraftLifecycleAdapter(modelContext: fixture.coordinator.modelContext)
        _ = try adapter.compareAndSwap(checkpoint: checkpoint, expectedDraftRevision: 0, expectedBaseRevision: 0)
        return checkpoint
    }

    private func reference(_ checkpoint: FieldDraftCheckpointV1) -> MyDayEligibleReferenceV1 {
        .resumableDraft(workspaceID: checkpoint.workspaceID, draftID: checkpoint.draftID,
            revision: checkpoint.draftRevision, checkpointSHA256: checkpoint.checkpointSHA256,
            anchor: checkpoint.resumeAnchor)
    }
}

private enum EditorInterruption: Error { case injected }

@MainActor
private final class CarryoverEditorImportedJournalNodeV1 {
    let root: URL
    let identity: WorkspaceReplicaIdentityV1
    let session: StoreGenerationSession
    let coordinator: StoreSessionCoordinator
    let journal: LocalChangeJournalV1

    init(workspaceID: WorkspaceID, replicaID: ReplicaID) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "V23-carryover-editor-import-journal-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        identity = try .init(workspaceID: workspaceID, replicaID: replicaID)
        session = try StoreGenerationFactory(applicationSupportURL: root,
            pointerEnrichmentIdentity: identity).openOrBootstrapCurrent()
        let profiles = try WorkspacePackageLifecycleCompatibilityV1.shippingRegistry()
        coordinator = try StoreSessionCoordinator(validatingSession: session, lifecycleProfileRegistry: profiles)
        let dependencies = try coordinator.packageLifecycleDependencies(profileRegistry: profiles)
        let backup = BackupExportService(modelContext: session.modelContext,
            generationRootURL: session.generationRootURL, lifecycleDependencies: dependencies,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in Int64.max }))
        let catalog = try CurrentSyncClassificationCatalogV1.current
        let draftPolicy = try catalog.registration(for: .init(category: .persistentModel,
            stableName: "FieldDraftCheckpointRow")).conflictPolicy
        let planPolicy = try catalog.registration(for: .init(category: .persistentModel,
            stableName: "MyDayPlanRowV1")).conflictPolicy
        journal = try coordinator.localChangeJournal(backupExport: backup,
            policyResolver: { identity, _ in
                switch identity.kind {
                case .fieldDraftCheckpoint: return draftPolicy
                case .myDayPlan: return planPolicy
                default: throw ChangeJournalFailureV1.tamperedBatch
                }
            },
            contentReferenceResolver: { _ in throw ContentContractFailureV1.missingContent },
            contentEntryResolver: { _ in throw ContentContractFailureV1.missingContent })
    }

    var context: ModelContext { coordinator.modelContext }
    var writer: WorkspaceWriterV1 { coordinator.workspaceWriter }
    func removeFiles() {
        try? coordinator.invalidateAndReleaseWriter()
        try? FileManager.default.removeItem(at: root)
    }
}

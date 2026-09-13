import Combine
import Foundation
import SwiftData
import XCTest

@testable import FieldEvidenceApp

final class V23MyDayPlanningEditingSessionTests: XCTestCase {
    @MainActor
    func testConstructionIsEffectFreeAndForcedFlushPublishesExactReceiptBackedCheckpoint() async throws {
        let fixture = try await makeFixture("editing-effect-free")
        defer { fixture.cleanUp() }
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let beforeRevision = try fixture.coordinator.workspaceWriter.currentRevision()
        let request = try makeRequest(workspaceID: fixture.coordinator.workspaceID)
        let anchor = try DraftResumeAnchorV1(sectionID: "my-day", fieldID: "plan")

        let session = try MyDayPlanningEditingSessionV1(
            request: request, resumeAnchor: anchor, access: access
        )

        XCTAssertTrue(session.hasDirtyChanges)
        XCTAssertEqual(session.durabilityState, .unsavedChanges)
        XCTAssertNil(session.checkpoint)
        XCTAssertEqual(try count(FieldDraftCheckpointRow.self, in: fixture.coordinator.modelContext), 0)
        XCTAssertEqual(try count(MyDayPlanRowV1.self, in: fixture.coordinator.modelContext), 0)
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), beforeRevision)

        try await session.forceFlush(reason: .navigation)

        let acknowledgement = try XCTUnwrap(session.acknowledgement)
        XCTAssertEqual(session.checkpoint, acknowledgement.checkpoint)
        XCTAssertEqual(session.draftID, acknowledgement.checkpoint.draftID)
        XCTAssertEqual(session.lastFlushReason, .navigation)
        XCTAssertEqual(session.durabilityState, .savedOnThisIPhone)
        XCTAssertFalse(session.hasDirtyChanges)
        XCTAssertEqual(try access.loadPlanningCheckpoint(draftID: session.draftID),
                       acknowledgement.checkpoint)
        XCTAssertEqual(try access.editingAcknowledgement(draftID: session.draftID),
                       acknowledgement)
        XCTAssertEqual(try count(FieldDraftCheckpointRow.self, in: fixture.coordinator.modelContext), 1)
        XCTAssertEqual(try count(MyDayPlanRowV1.self, in: fixture.coordinator.modelContext), 0)
    }

    @MainActor
    func testInjectedClockUsesTheExactTrailingAutosaveDeadline() async throws {
        let fixture = try await makeFixture("editing-trailing")
        defer { fixture.cleanUp() }
        let clock = V23EditingAutosaveClock()
        let session = try MyDayPlanningEditingSessionV1(
            request: makeRequest(workspaceID: fixture.coordinator.workspaceID),
            resumeAnchor: .init(sectionID: "my-day"),
            access: try XCTUnwrap(fixture.presentation.myDayAccess),
            policy: DraftAutosavePolicyV1(),
            clock: clock
        )

        try await session.start()
        try await waitForDeadline(750_000_000, clock: clock)
        await clock.advance(to: 749_999_999)
        await drainTasks()
        XCTAssertNil(session.acknowledgement)

        await clock.advance(to: 750_000_000)
        try await waitUntil { session.acknowledgement != nil }
        XCTAssertEqual(session.lastFlushReason, .automatic)
        XCTAssertEqual(session.durabilityState, .savedOnThisIPhone)
    }

    @MainActor
    func testInjectedClockCapsContinuousEditsAtFiveSecondsFromFirstDirty() async throws {
        let fixture = try await makeFixture("editing-max-dirty")
        defer { fixture.cleanUp() }
        let clock = V23EditingAutosaveClock()
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let request = try makeRequest(workspaceID: fixture.coordinator.workspaceID)
        let session = try MyDayPlanningEditingSessionV1(
            request: request,
            resumeAnchor: .init(sectionID: "my-day", boundedPosition: 0),
            access: access,
            policy: DraftAutosavePolicyV1(),
            clock: clock
        )
        try await session.start()

        for position in 1...9 {
            let instant = UInt64(position) * 500_000_000
            await clock.advance(to: instant)
            try await session.meaningfulEdit(
                request,
                resumeAnchor: .init(sectionID: "my-day", boundedPosition: position)
            )
        }
        try await waitForDeadline(5_000_000_000, clock: clock)
        await clock.advance(to: 4_999_999_999)
        await drainTasks()
        XCTAssertNil(session.acknowledgement)

        await clock.advance(to: 5_000_000_000)
        try await waitUntil { session.acknowledgement != nil }
        XCTAssertEqual(session.checkpoint?.draftRevision, 2)
        XCTAssertEqual(session.checkpoint?.resumeAnchor.boundedPosition, 9)
        XCTAssertEqual(session.durabilityState, .savedOnThisIPhone)
    }

    @MainActor
    func testEffectBeforeAcknowledgementRetriesTheSameImmutableWrite() async throws {
        let fixture = try await makeFixture("editing-uncertain")
        defer { fixture.cleanUp() }
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let clock = V23EditingAutosaveClock()
        let session = try MyDayPlanningEditingSessionV1(
            request: makeRequest(workspaceID: fixture.coordinator.workspaceID),
            resumeAnchor: .init(sectionID: "my-day"),
            access: access,
            policy: DraftAutosavePolicyV1(),
            clock: clock
        )
        #if DEBUG
        var interrupted = false
        access.setPlanningEffectHookForTesting { point in
            if point == .editingCheckpoint, !interrupted {
                interrupted = true
                throw V23EditingSessionTestFailure.injectedInterruption
            }
        }
        do {
            try await session.forceFlush(reason: .navigation)
            XCTFail("The injected post-effect interruption must escape")
        } catch {
            XCTAssertEqual(error as? V23EditingSessionTestFailure, .injectedInterruption)
        }
        XCTAssertEqual(session.durabilityState, .saveBlocked)
        XCTAssertTrue(session.hasDirtyChanges)
        XCTAssertNil(session.acknowledgement)
        XCTAssertEqual(try count(FieldDraftCheckpointRow.self, in: fixture.coordinator.modelContext), 1)
        let revisionAfterEffect = try fixture.coordinator.workspaceWriter.currentRevision()

        access.setPlanningEffectHookForTesting(nil)
        try await session.forceFlush(reason: .navigation)

        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), revisionAfterEffect)
        XCTAssertEqual(session.acknowledgement?.checkpoint.draftRevision, 1)
        XCTAssertFalse(session.hasDirtyChanges)
        XCTAssertEqual(session.durabilityState, .savedOnThisIPhone)
        #else
        throw XCTSkip("Effect interruption is DEBUG-only")
        #endif
    }

    @MainActor
    func testNewerEditDuringAcknowledgementIsPersistedAsSuccessorBeforeFlushReturns() async throws {
        let fixture = try await makeFixture("editing-newer-generation")
        defer { fixture.cleanUp() }
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let request = try makeRequest(workspaceID: fixture.coordinator.workspaceID)
        let session = try MyDayPlanningEditingSessionV1(
            request: request,
            resumeAnchor: .init(sectionID: "my-day", boundedPosition: 1),
            access: access
        )
        let receiptCountBefore = try count(
            MutationReceiptRow.self, in: fixture.coordinator.modelContext
        )
        #if DEBUG
        var insertedNewerEdit = false
        session.afterAcknowledgementReadyForTesting = { _ in
            guard !insertedNewerEdit else { return }
            insertedNewerEdit = true
            try await session.meaningfulEdit(
                request,
                resumeAnchor: .init(sectionID: "my-day", boundedPosition: 2)
            )
        }

        try await session.forceFlush(reason: .navigation)
        session.afterAcknowledgementReadyForTesting = nil

        XCTAssertTrue(insertedNewerEdit)
        XCTAssertEqual(session.checkpoint?.draftRevision, 2)
        XCTAssertEqual(session.checkpoint?.resumeAnchor.boundedPosition, 2)
        XCTAssertEqual(session.acknowledgement?.checkpoint, session.checkpoint)
        XCTAssertFalse(session.hasDirtyChanges)
        XCTAssertEqual(session.durabilityState, .savedOnThisIPhone)
        XCTAssertEqual(try count(FieldDraftCheckpointRow.self, in: fixture.coordinator.modelContext), 1)
        XCTAssertEqual(
            try count(MutationReceiptRow.self, in: fixture.coordinator.modelContext),
            receiptCountBefore + 2
        )
        #else
        throw XCTSkip("Acknowledgement suspension is DEBUG-only")
        #endif
    }

    @MainActor
    func testObserverRaisedCoverRejectsPublicationBeforeAnyEditingEffect() async throws {
        let fixture = try await makeFixture("editing-observer-cover")
        defer { fixture.cleanUp() }
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let session = try MyDayPlanningEditingSessionV1(
            request: makeRequest(workspaceID: fixture.coordinator.workspaceID),
            resumeAnchor: .init(sectionID: "my-day"),
            access: access
        )
        var raisedCover = false
        let observation = session.objectWillChange.sink {
            guard !raisedCover else { return }
            raisedCover = true
            fixture.presentation.receive(.sceneInactive)
        }
        defer { observation.cancel() }

        do {
            try await session.forceFlush(reason: .background)
            XCTFail("The observer-raised cover must revoke the original publication")
        } catch {
            XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied)
        }

        XCTAssertTrue(raisedCover)
        XCTAssertFalse(fixture.presentation.permitsContentPresentation)
        XCTAssertNil(session.checkpoint)
        XCTAssertNil(session.acknowledgement)
        XCTAssertTrue(session.hasDirtyChanges)
        XCTAssertEqual(try count(FieldDraftCheckpointRow.self, in: fixture.coordinator.modelContext), 0)
    }

    @MainActor
    func testCoverDuringAcknowledgementKeepsTheDurableWritePendingAndUnpublished() async throws {
        let fixture = try await makeFixture("editing-ack-cover")
        defer { fixture.cleanUp() }
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let session = try MyDayPlanningEditingSessionV1(
            request: makeRequest(workspaceID: fixture.coordinator.workspaceID),
            resumeAnchor: .init(sectionID: "my-day"),
            access: access
        )
        #if DEBUG
        session.afterAcknowledgementReadyForTesting = { _ in
            fixture.presentation.receive(.sceneInactive)
        }
        do {
            try await session.forceFlush(reason: .background)
            XCTFail("The covered completion must not publish through the old access")
        } catch {
            XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied)
        }
        access.setPlanningEffectHookForTesting(nil)
        session.afterAcknowledgementReadyForTesting = nil

        XCTAssertFalse(fixture.presentation.permitsContentPresentation)
        XCTAssertNil(session.checkpoint)
        XCTAssertNil(session.acknowledgement)
        XCTAssertTrue(session.hasDirtyChanges)
        XCTAssertEqual(try count(FieldDraftCheckpointRow.self, in: fixture.coordinator.modelContext), 1)
        XCTAssertEqual(try count(MutationReceiptRow.self, in: fixture.coordinator.modelContext), 1)
        XCTAssertEqual(try count(MyDayPlanRowV1.self, in: fixture.coordinator.modelContext), 0)
        #else
        throw XCTSkip("Acknowledgement suspension is DEBUG-only")
        #endif
    }

    @MainActor
    func testOrdinarySessionRejectsAChangedConfirmedContextBeforeSchedulingAWrite() async throws {
        let fixture = try await makeFixture("editing-context-change")
        defer { fixture.cleanUp() }
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let original = try makeRequest(workspaceID: fixture.coordinator.workspaceID)
        let changed = try makeRequest(workspaceID: fixture.coordinator.workspaceID)
        let session = try MyDayPlanningEditingSessionV1(
            request: original,
            resumeAnchor: .init(sectionID: "my-day"),
            access: access
        )

        do {
            try await session.meaningfulEdit(
                changed,
                resumeAnchor: .init(sectionID: "my-day", fieldID: "recorder")
            )
            XCTFail("Changing the confirmed context requires a separate explicit flow")
        } catch {
            XCTAssertEqual(
                error as? MyDayPlanningEditingSessionFailureV1,
                .changedEditingContext
            )
        }

        XCTAssertEqual(session.request.confirmedContext, original.confirmedContext)
        XCTAssertTrue(session.hasDirtyChanges)
        XCTAssertEqual(try count(FieldDraftCheckpointRow.self, in: fixture.coordinator.modelContext), 0)
    }

    @MainActor
    func testColdProductionReopenReusesDurableReceiptThenSavesTheLatestEditingRevision() async throws {
        let fixture = try await makeFixture("editing-cold-resume-save")
        var reopened: V23EditingSessionReopenedAuthority?
        defer {
            try? reopened?.coordinator.invalidateAndReleaseWriter()
            fixture.cleanUp()
        }
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let request = try makeRequest(workspaceID: fixture.coordinator.workspaceID)
        let original = try MyDayPlanningEditingSessionV1(
            request: request,
            resumeAnchor: .init(sectionID: "my-day", boundedPosition: 1),
            access: access
        )
        try await original.forceFlush(reason: .navigation)
        let originalAcknowledgement = try XCTUnwrap(original.acknowledgement)
        let revisionBeforeResume = try fixture.coordinator.workspaceWriter.currentRevision()
        let originalWriterID = revisionBeforeResume.writerInstanceID

        try fixture.coordinator.invalidateAndReleaseWriter()
        reopened = try await V23EditingSessionReopenedAuthority.start(
            testCase: self,
            support: fixture.support,
            defaults: fixture.defaults
        )
        let fresh = try XCTUnwrap(reopened)
        let freshAccess = try XCTUnwrap(fresh.presentation.myDayAccess)
        let reopenedRevision = try fresh.coordinator.workspaceWriter.currentRevision()
        XCTAssertNotEqual(reopenedRevision.writerInstanceID, originalWriterID)

        let resumed = try MyDayPlanningEditingSessionV1(
            resumingDraftID: original.draftID,
            access: freshAccess
        )

        XCTAssertEqual(resumed.acknowledgement, originalAcknowledgement)
        XCTAssertEqual(resumed.durabilityState, .savedOnThisIPhone)
        XCTAssertFalse(resumed.hasDirtyChanges)
        XCTAssertEqual(try fresh.coordinator.workspaceWriter.currentRevision(), reopenedRevision)

        try await resumed.meaningfulEdit(
            request,
            resumeAnchor: .init(sectionID: "my-day", boundedPosition: 2)
        )
        let outcome = try await resumed.save()

        XCTAssertEqual(outcome.checkpoint.draftID, original.draftID)
        XCTAssertEqual(outcome.checkpoint.state, .committed)
        XCTAssertEqual(resumed.checkpoint, outcome.checkpoint)
        XCTAssertEqual(resumed.commitOutcome, outcome)
        XCTAssertEqual(resumed.durabilityState, .committed)
        XCTAssertFalse(resumed.hasDirtyChanges)
        XCTAssertEqual(try count(MyDayPlanRowV1.self, in: fresh.coordinator.modelContext), 1)
    }

    @MainActor
    func testSameSessionSaveRetriesFrozenAttemptAfterCommittingCanonicalAndTerminalEffects() async throws {
        #if DEBUG
        let interruptionPoints: [MyDayPlanningEffectPointV1] = [
            .committingCheckpoint,
            .targetCommit,
            .terminalBundle
        ]
        for point in interruptionPoints {
            let fixture = try await makeFixture("editing-save-\(point.rawValue.lowercased())")
            defer { fixture.cleanUp() }
            let access = try XCTUnwrap(fixture.presentation.myDayAccess)
            let request = try makeRequest(workspaceID: fixture.coordinator.workspaceID)
            let session = try MyDayPlanningEditingSessionV1(
                request: request,
                resumeAnchor: .init(sectionID: "my-day"),
                access: access
            )
            let revisionBefore = try fixture.coordinator.workspaceWriter.currentRevision()
            let receiptCountBefore = try count(
                MutationReceiptRow.self, in: fixture.coordinator.modelContext
            )
            try await session.forceFlush(reason: .navigation)
            var interrupted = false
            access.setPlanningEffectHookForTesting { observed in
                guard observed == point, !interrupted else { return }
                interrupted = true
                throw V23EditingSessionTestFailure.injectedInterruption
            }

            do {
                _ = try await session.save()
                XCTFail("The requested post-effect interruption must escape: \(point.rawValue)")
            } catch {
                XCTAssertEqual(
                    error as? V23EditingSessionTestFailure,
                    .injectedInterruption
                )
            }
            XCTAssertTrue(interrupted)
            XCTAssertEqual(session.durabilityState, .saveBlocked)
            XCTAssertFalse(session.isCommitInFlight)
            access.setPlanningEffectHookForTesting(nil)
            let frozenCheckpoint = try access.loadPlanningCheckpoint(draftID: session.draftID)
            let frozenPayload = try MyDayPlanningDraftCodecV1.validateCheckpointPayload(
                frozenCheckpoint
            )
            let frozenAttempt = try XCTUnwrap(frozenPayload.commitAttempt)

            let outcome = try await session.save()

            let committedPayload = try MyDayPlanningDraftCodecV1.validateCheckpointPayload(
                outcome.checkpoint
            )
            XCTAssertEqual(committedPayload.commitAttempt, frozenAttempt)
            XCTAssertEqual(session.commitOutcome, outcome)
            XCTAssertEqual(session.durabilityState, .committed)
            XCTAssertEqual(try count(MyDayPlanRowV1.self, in: fixture.coordinator.modelContext), 1)
            XCTAssertEqual(try count(FieldDraftCheckpointRow.self,
                                     in: fixture.coordinator.modelContext), 1)
            XCTAssertEqual(try count(DraftCommitSagaRow.self,
                                     in: fixture.coordinator.modelContext), 5)
            XCTAssertEqual(try count(DraftCommitReceiptRow.self,
                                     in: fixture.coordinator.modelContext), 1)
            XCTAssertEqual(
                try count(MutationReceiptRow.self, in: fixture.coordinator.modelContext),
                receiptCountBefore + 8
            )
            XCTAssertEqual(
                try fixture.coordinator.workspaceWriter.currentRevision().revision,
                revisionBefore.revision + 8
            )
        }
        #else
        throw XCTSkip("Planning effect interruption is DEBUG-only")
        #endif
    }

    @MainActor
    func testCarryoverSessionSaveRetriesOriginalTypedAttemptAcrossCommittingTargetAndTerminalEffects() async throws {
        #if DEBUG
        let interruptionPoints: [MyDayPlanningEffectPointV1] = [
            .committingCheckpoint,
            .targetCommit,
            .terminalBundle
        ]
        for point in interruptionPoints {
            let fixture = try await makeFixture("carryover-session-save-\(point.rawValue.lowercased())")
            defer { fixture.cleanUp() }
            let access = try XCTUnwrap(fixture.presentation.myDayAccess)
            let seed = try await makeCarryoverRequest(in: fixture)
            let request = seed.request
            let session = try MyDayPlanningCarryoverEditingSessionV1(
                request: request,
                resumeAnchor: .init(sectionID: "my-day"),
                access: access
            )
            let revisionBefore = try fixture.coordinator.workspaceWriter.currentRevision()
            let receiptCountBefore = try count(
                MutationReceiptRow.self, in: fixture.coordinator.modelContext
            )
            try await session.forceFlush(reason: .navigation)
            var interrupted = false
            access.setPlanningEffectHookForTesting { observed in
                guard observed == point, !interrupted else { return }
                interrupted = true
                throw V23EditingSessionTestFailure.injectedInterruption
            }

            do {
                _ = try await session.save()
                XCTFail("The requested post-effect interruption must escape: \(point.rawValue)")
            } catch {
                XCTAssertEqual(
                    error as? V23EditingSessionTestFailure,
                    .injectedInterruption
                )
            }
            XCTAssertTrue(interrupted)
            XCTAssertEqual(session.durabilityState, .saveBlocked)
            XCTAssertFalse(session.isCommitInFlight)
            access.setPlanningEffectHookForTesting(nil)
            let frozenCheckpoint = try access.loadPlanningCheckpoint(draftID: session.draftID)
            let frozenPayload = try MyDayPlanningDraftCodecV1.validateCheckpointPayload(
                frozenCheckpoint
            )
            let frozenAttempt = try XCTUnwrap(frozenPayload.commitAttempt)

            let outcome = try await session.save()

            let committedPayload = try MyDayPlanningDraftCodecV1.validateCheckpointPayload(
                outcome.checkpoint
            )
            guard case .carryover = frozenAttempt.command else { return XCTFail("Expected frozen carryover") }
            XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentPlan(for: seed.source.key), seed.source)
            XCTAssertEqual(committedPayload.commitAttempt, frozenAttempt)
            XCTAssertEqual(session.commitOutcome, outcome)
            XCTAssertEqual(session.durabilityState, .committed)
            XCTAssertEqual(try count(MyDayPlanRowV1.self, in: fixture.coordinator.modelContext), 2)
            XCTAssertEqual(try count(FieldDraftCheckpointRow.self,
                                     in: fixture.coordinator.modelContext), 4)
            XCTAssertEqual(try count(DraftCommitSagaRow.self,
                                     in: fixture.coordinator.modelContext), 10)
            XCTAssertEqual(try count(DraftCommitReceiptRow.self,
                                     in: fixture.coordinator.modelContext), 2)
            XCTAssertEqual(
                try count(MutationReceiptRow.self, in: fixture.coordinator.modelContext),
                receiptCountBefore + 8
            )
            XCTAssertEqual(
                try fixture.coordinator.workspaceWriter.currentRevision().revision,
                revisionBefore.revision + 8
            )
        }
        #else
        throw XCTSkip("Planning effect interruption is DEBUG-only")
        #endif
    }


    @MainActor
    func testCarryoverSessionResumesExactAcknowledgementAndRejectsOrdinaryPlanIntent() async throws {
        let fixture = try await makeFixture("carryover-session-resume")
        defer { fixture.cleanUp() }
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let seed = try await makeCarryoverRequest(in: fixture)
        let before = try fixture.coordinator.workspaceWriter.currentRevision()
        let session = try MyDayPlanningCarryoverEditingSessionV1(request: seed.request,
            resumeAnchor: .init(sectionID: "carryover"), access: access)
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), before)
        try await session.forceFlush(reason: .navigation)
        let checkpoint = try XCTUnwrap(session.checkpoint)
        let acknowledgement = try XCTUnwrap(session.acknowledgement)
        let resumed = try MyDayPlanningCarryoverEditingSessionV1(resumingDraftID: session.draftID, access: access)
        XCTAssertEqual(resumed.request, seed.request)
        XCTAssertEqual(resumed.checkpoint, checkpoint)
        XCTAssertEqual(resumed.acknowledgement, acknowledgement)
        XCTAssertFalse(resumed.hasDirtyChanges)
        let after = try fixture.coordinator.workspaceWriter.currentRevision()
        XCTAssertThrowsError(try MyDayPlanningEditingSessionV1(resumingDraftID: session.draftID, access: access)) {
            XCTAssertEqual($0 as? MyDayPlanningExecutionFailureV1, .unsupportedCommand)
        }
        let ordinary = try MyDayPlanningEditingSessionV1(
            request: makeRequest(workspaceID: fixture.coordinator.workspaceID),
            resumeAnchor: .init(sectionID: "plan"), access: access)
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), after)
        try await ordinary.forceFlush(reason: .navigation)
        let beforeDenial = try fixture.coordinator.workspaceWriter.currentRevision()
        XCTAssertThrowsError(try MyDayPlanningCarryoverEditingSessionV1(resumingDraftID: ordinary.draftID, access: access)) {
            XCTAssertEqual($0 as? MyDayPlanningExecutionFailureV1, .unsupportedCommand)
        }
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), beforeDenial)
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentPlan(for: seed.source.key), seed.source)
        XCTAssertNil(try fixture.coordinator.workspaceWriter.currentPlan(for: seed.request.confirmedContext.key))
        await session.invalidate()
        await resumed.invalidate()
        await ordinary.invalidate()
    }

    @MainActor
    func testCarryoverNewerMembershipEditDuringAcknowledgementPersistsExactSuccessor() async throws {
        #if DEBUG
        let fixture = try await makeFixture("carryover-session-newer-edit")
        defer { fixture.cleanUp() }
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let seed = try await makeCarryoverRequest(in: fixture)
        let session = try MyDayPlanningCarryoverEditingSessionV1(request: seed.request,
            resumeAnchor: .init(sectionID: "carryover"), access: access)
        let changed = try MyDayPlanningCarryoverRequestV1(confirmedContext: seed.request.confirmedContext,
            sourcePlan: seed.request.sourcePlan, selectedMembershipIDs: [seed.request.selectedMembershipIDs[1]],
            targetPredecessor: seed.request.targetPredecessor)
        let beforeReceipts = try count(MutationReceiptRow.self, in: fixture.coordinator.modelContext)
        var changedDuringAcknowledgement = false
        session.afterAcknowledgementReadyForTesting = { acknowledgement in
            guard !changedDuringAcknowledgement else { return }
            changedDuringAcknowledgement = true
            let first = try MyDayPlanningDraftCodecV1.validateCheckpointPayload(acknowledgement.checkpoint)
            XCTAssertEqual(first.editingIntent, seed.request.editingIntent)
            try await session.meaningfulEdit(changed, resumeAnchor: .init(sectionID: "carryover", boundedPosition: 1))
        }
        try await session.forceFlush(reason: .navigation)
        session.afterAcknowledgementReadyForTesting = nil
        XCTAssertTrue(changedDuringAcknowledgement)
        XCTAssertEqual(session.request, changed)
        XCTAssertEqual(session.checkpoint?.draftRevision, 2)
        XCTAssertEqual(session.acknowledgement?.checkpoint, session.checkpoint)
        let payload = try MyDayPlanningDraftCodecV1.validateCheckpointPayload(XCTUnwrap(session.checkpoint))
        XCTAssertEqual(payload.editingIntent, changed.editingIntent)
        XCTAssertEqual(try count(MutationReceiptRow.self, in: fixture.coordinator.modelContext), beforeReceipts + 2)
        XCTAssertFalse(session.hasDirtyChanges)
        XCTAssertEqual(session.durabilityState, .savedOnThisIPhone)
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentPlan(for: seed.source.key), seed.source)
        XCTAssertNil(try fixture.coordinator.workspaceWriter.currentPlan(for: changed.confirmedContext.key))
        await session.invalidate()
        #else
        throw MyDayPlanningExecutionFailureV1.unsupportedState
        #endif
    }

    @MainActor
    func testCarryoverSessionRejectsChangedSourceBaseAndConfirmedRecorderBeforeScheduling() async throws {
        let fixture = try await makeFixture("carryover-session-base")
        defer { fixture.cleanUp() }
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let seed = try await makeCarryoverRequest(in: fixture)
        let session = try MyDayPlanningCarryoverEditingSessionV1(request: seed.request,
            resumeAnchor: .init(sectionID: "carryover"), access: access)
        try await session.forceFlush(reason: .navigation)
        let before = try fixture.coordinator.workspaceWriter.currentRevision()
        let original = try XCTUnwrap(session.checkpoint)
        let newRecorder = try access.captureConfirmedPlanningContext(for: seed.request.confirmedContext.key,
            recordedByName: "Different recorder")
        let empty = try makeRequest(workspaceID: fixture.coordinator.workspaceID)
        let replacement = try MyDayPlanningPlanSaveRequestV1(confirmedContext: empty.confirmedContext,
            draft: empty.draft, predecessor: seed.source)
        let otherPlan = try await access.savePlan(replacement).targetResult.plan
        let requests = [
            try MyDayPlanningCarryoverRequestV1(confirmedContext: seed.request.confirmedContext,
                sourcePlan: MyDayPlanReferenceV1(otherPlan), selectedMembershipIDs: seed.request.selectedMembershipIDs,
                targetPredecessor: nil),
            try MyDayPlanningCarryoverRequestV1(confirmedContext: newRecorder,
                sourcePlan: seed.request.sourcePlan, selectedMembershipIDs: seed.request.selectedMembershipIDs,
                targetPredecessor: nil)
        ]
        let afterIndependentSave = try fixture.coordinator.workspaceWriter.currentRevision()
        XCTAssertGreaterThan(afterIndependentSave.revision, before.revision)
        for request in requests {
            do {
                try await session.meaningfulEdit(request, resumeAnchor: .init(sectionID: "carryover"))
                XCTFail("A carryover editing session cannot change its captured base or recorder")
            } catch { XCTAssertEqual(error as? MyDayPlanningEditingSessionFailureV1, .changedEditingContext) }
            XCTAssertEqual(session.request, seed.request)
            XCTAssertEqual(session.checkpoint, original)
            XCTAssertFalse(session.hasDirtyChanges)
            XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), afterIndependentSave)
        }
        await session.invalidate()
    }

    @MainActor
    private func makeCarryoverRequest(in fixture: V23ProductionMyDayPresentationHarness) async throws
        -> (source: MyDayPlanV1, request: MyDayPlanningCarryoverRequestV1) {
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let writer = fixture.coordinator.workspaceWriter
        let workspace = fixture.coordinator.workspaceID
        let adapter = try writer.makeFieldDraftLifecycleAdapter(modelContext: fixture.coordinator.modelContext)
        var references: [MyDayEligibleReferenceV1] = []
        for position in 0..<2 {
            let checkpoint = try FieldDraftCheckpointV1(draftID: UUID(), workspaceID: workspace,
                scope: .init(scopeKind: "V23_MY_DAY_SESSION_SOURCE", stableComponentIDs: [String(position)]),
                purpose: .assetFieldEdit, codec: .init(codecID: "v23.my-day.session-source.v1",
                    codecVersion: 1, releaseSHA256: String(repeating: "a", count: 64)),
                baseCanonicalRevision: 0, draftRevision: 1, payloadData: Data("source".utf8), stageIDs: [],
                resumeAnchor: .init(sectionID: "source"), state: .active,
                updatedAt: Date(timeIntervalSince1970: 1_789_084_801), mutationID: writer.makeMutationID())
            _ = try adapter.compareAndSwap(checkpoint: checkpoint, expectedDraftRevision: 0, expectedBaseRevision: 0)
            references.append(.resumableDraft(workspaceID: workspace, draftID: checkpoint.draftID,
                revision: checkpoint.draftRevision, checkpointSHA256: checkpoint.checkpointSHA256,
                anchor: checkpoint.resumeAnchor))
        }
        let original = try makeRequest(workspaceID: workspace)
        let items = try references.map { try MyDayDraftItemV1(membershipID: UUID(), reference: $0) }
        let sourceRequest = try MyDayPlanningPlanSaveRequestV1(confirmedContext: original.confirmedContext,
            draft: .init(key: original.confirmedContext.key, items: items, eligibleReferences: references), predecessor: nil)
        let source = try await access.savePlan(sourceRequest).targetResult.plan
        let targetKey = try MyDayKeyV1(workspaceID: workspace, civilDate: .init("2026-09-13"),
            ianaTimeZoneIdentifier: "America/New_York")
        let context = try access.captureConfirmedPlanningContext(for: targetKey, recordedByName: "Carryover recorder")
        let request = try MyDayPlanningCarryoverRequestV1(confirmedContext: context,
            sourcePlan: MyDayPlanReferenceV1(source), selectedMembershipIDs: source.items.map(\.membershipID),
            targetPredecessor: nil)
        return (source, request)
    }

    @MainActor
    private func makeFixture(_ name: String) async throws
        -> V23ProductionMyDayPresentationHarness {
        try await V23ProductionMyDayPresentationHarness.start(testCase: self, name: name)
    }

    @MainActor
    private func makeRequest(workspaceID: WorkspaceID) throws
        -> MyDayPlanningPlanSaveRequestV1 {
        let key = try MyDayKeyV1(
            workspaceID: workspaceID,
            civilDate: .init("2026-09-12"),
            ianaTimeZoneIdentifier: "America/New_York"
        )
        let actorReference = try LocalActorReferenceV1(
            actorReferenceID: UUID(),
            workspaceID: workspaceID,
            displayName: "My Day editing recorder"
        )
        let actor = try ActorSnapshotV1(
            snapshotID: UUID(),
            workspaceID: workspaceID,
            actor: actorReference,
            responsibility: .recordedBy,
            displayNameAtTime: actorReference.displayName,
            capturedAt: Date(timeIntervalSince1970: 1_789_084_800)
        )
        let context = try MyDayPlanningConfirmedContextV1(
            key: key,
            recordedBy: actor,
            keyWasExplicitlyConfirmed: true,
            recordedByWasExplicitlySelectedOrCaptured: true
        )
        return try .init(
            confirmedContext: context,
            draft: .init(key: key, items: [], eligibleReferences: []),
            predecessor: nil
        )
    }

    @MainActor
    private func count<T: PersistentModel>(_ type: T.Type, in context: ModelContext) throws -> Int {
        try context.fetchCount(FetchDescriptor<T>())
    }

    @MainActor
    private func waitUntil(
        _ predicate: @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        for _ in 0..<1_000 {
            if predicate() { return }
            await Task.yield()
        }
        XCTFail("Condition did not become true", file: file, line: line)
        throw V23EditingSessionTestFailure.timeout
    }

    private func waitForDeadline(
        _ deadline: UInt64,
        clock: V23EditingAutosaveClock,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        for _ in 0..<1_000 {
            if await clock.deadlines().contains(deadline) { return }
            await Task.yield()
        }
        XCTFail("Autosave deadline was not registered", file: file, line: line)
        throw V23EditingSessionTestFailure.timeout
    }

    private func drainTasks() async {
        for _ in 0..<20 { await Task.yield() }
    }
}

private enum V23EditingSessionTestFailure: Error, Equatable {
    case injectedInterruption
    case timeout
}

private actor V23EditingAutosaveClock: DraftAutosaveClockV1 {
    private struct Waiter {
        let deadline: UInt64
        let continuation: CheckedContinuation<Void, Error>
    }

    private var now: UInt64 = 0
    private var waiters: [UUID: Waiter] = [:]

    func nowNanoseconds() async -> UInt64 { now }

    func sleep(untilNanoseconds deadline: UInt64) async throws {
        guard deadline > now else { return }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if deadline <= now {
                    continuation.resume()
                } else {
                    waiters[id] = Waiter(deadline: deadline, continuation: continuation)
                }
            }
        } onCancel: {
            Task { await self.cancel(id: id) }
        }
    }

    func advance(to instant: UInt64) {
        precondition(instant >= now)
        now = instant
        let ready = waiters.filter { $0.value.deadline <= instant }
        for (id, waiter) in ready {
            waiters[id] = nil
            waiter.continuation.resume()
        }
    }

    func deadlines() -> [UInt64] {
        waiters.values.map(\.deadline).sorted()
    }

    private func cancel(id: UUID) {
        guard let waiter = waiters.removeValue(forKey: id) else { return }
        waiter.continuation.resume(throwing: CancellationError())
    }
}

@MainActor
private struct V23EditingSessionReopenedAuthority {
    let router: StartupRouter
    let session: ProductionAppAccessSessionV1
    let presentation: AppAccessPresentationV1
    let coordinator: StoreSessionCoordinator

    static func start(
        testCase: XCTestCase,
        support: URL,
        defaults: UserDefaults
    ) async throws -> Self {
        let router = StartupRouter(applicationSupportURL: support)
        let session = try await ProductionCompositionRoot.makeAppAccessSession(
            applicationSupportURL: support,
            startupRouter: router,
            defaults: defaults,
            authenticationClient: V23EditingSessionAuthentication(),
            notificationSystem: V23EditingSessionNotificationSystem()
        )
        let presentation = AppAccessPresentationV1(
            startupRouter: router,
            sessionFactory: { session }
        )
        let published = testCase.expectation(
            description: "Cold My Day editing session authority"
        )
        let observation = presentation.$permitsContentPresentation
            .filter { $0 }.prefix(1).sink { _ in published.fulfill() }
        await presentation.bootstrapIfNeeded()
        await testCase.fulfillment(of: [published], timeout: 30)
        observation.cancel()
        guard case .ready(let coordinator, _, _) = router.route else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        return .init(
            router: router,
            session: session,
            presentation: presentation,
            coordinator: coordinator
        )
    }
}

private actor V23EditingSessionAuthentication: LocalAuthenticationClient {
    func availability() -> LocalAuthenticationAvailabilityV1 {
        .systemValue(status: .available, biometry: .faceID)
    }

    func authenticate(_ attempt: LocalAuthenticationAttemptV1)
        -> LocalAuthenticationOutcomeV1 {
        .authenticated
    }

    func cancel(attemptID: UUID) {}
}

@MainActor
private final class V23EditingSessionNotificationSystem: NotificationSystemPortV1 {
    private var requests: [NotificationSystemRequestV1] = []

    func authorization() async throws -> LocalReminderAuthorizationV1 { .authorized }

    func observations() async throws -> [NotificationSystemObservationV1] {
        requests.map {
            .init(requestID: $0.notification.requestID, request: $0, delivered: false)
        }
    }

    func add(_ request: NotificationSystemRequestV1) async throws {
        requests.append(request)
    }

    func remove(_ requestIDs: [String]) async throws {
        requests.removeAll { requestIDs.contains($0.notification.requestID) }
    }
}

import Combine
import Foundation
import SwiftData
import XCTest

@testable import FieldEvidenceApp

final class V23MyDayPlanningCheckpointTests: XCTestCase {
    @MainActor
    func testEditingPreparationIsZeroWriteAndAcknowledgedRevisionsReplayAfterOtherDraftWrites() async throws {
        let fixture = try await makeFixture("editing-receipts")
        defer { fixture.cleanUp() }
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let writer = fixture.coordinator.workspaceWriter
        let before = try writer.currentRevision()
        let request = try makeRequest(workspaceID: fixture.coordinator.workspaceID, name: "First recorder")
        let first = try access.prepareEditingWrite(request, replacing: nil, resumeAnchor: anchor("items"))
        XCTAssertEqual(try writer.currentRevision(), before)
        XCTAssertEqual(try rowCount(FieldDraftCheckpointRow.self, fixture), 0)
        XCTAssertFalse(fixture.coordinator.modelContext.hasChanges)

        let firstAck = try access.persistEditingWrite(first)
        XCTAssertEqual(firstAck.checkpoint, first.checkpoint)
        XCTAssertEqual(firstAck.receipt.mutationID, first.checkpoint.mutationID)
        XCTAssertEqual(try access.editingAcknowledgement(draftID: first.checkpoint.draftID), firstAck)
        XCTAssertEqual(try writer.currentRevision().revision, before.revision + 1)

        let changed = try makeRequest(workspaceID: fixture.coordinator.workspaceID, name: "Reviewed recorder")
        let second = try access.prepareEditingWrite(changed, replacing: firstAck.checkpoint,
                                                   resumeAnchor: anchor("recorder"))
        XCTAssertEqual(try access.loadPlanningCheckpoint(draftID: first.checkpoint.draftID), firstAck.checkpoint)
        XCTAssertNotEqual(second.checkpoint.payloadData, first.checkpoint.payloadData)
        XCTAssertEqual(second.checkpoint.draftID, first.checkpoint.draftID)
        XCTAssertEqual(second.checkpoint.draftRevision, 2)
        let secondAck = try access.persistEditingWrite(second)

        let neighbor = try access.prepareEditingWrite(request, replacing: nil, resumeAnchor: anchor("items"))
        _ = try access.persistEditingWrite(neighbor)
        let afterNeighbor = try writer.currentRevision()
        XCTAssertEqual(try access.persistEditingWrite(second), secondAck)
        XCTAssertEqual(try access.editingAcknowledgement(draftID: second.checkpoint.draftID), secondAck)
        XCTAssertEqual(try writer.currentRevision(), afterNeighbor)
        XCTAssertEqual(try rowCount(FieldDraftCheckpointRow.self, fixture), 2)
        XCTAssertEqual(try rowCount(MutationReceiptRow.self, fixture), 3)
        XCTAssertEqual(try rowCount(MyDayPlanRowV1.self, fixture), 0)
        XCTAssertEqual(try rowCount(DraftCommitSagaRow.self, fixture), 0)
        XCTAssertEqual(try rowCount(DraftCommitReceiptRow.self, fixture), 0)
        XCTAssertFalse(fixture.coordinator.modelContext.hasChanges)
    }

    @MainActor
    func testCompetingEditingCASAndHistoricalAcknowledgementCannotOverwriteLatestDraft() async throws {
        let fixture = try await makeFixture("competing-editors")
        defer { fixture.cleanUp() }
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let request = try makeRequest(workspaceID: fixture.coordinator.workspaceID)
        let initial = try access.prepareEditingWrite(request, replacing: nil, resumeAnchor: anchor("items"))
        let initialAck = try access.persistEditingWrite(initial)
        let left = try access.prepareEditingWrite(request, replacing: initialAck.checkpoint,
                                                 resumeAnchor: anchor("left"))
        let right = try access.prepareEditingWrite(request, replacing: initialAck.checkpoint,
                                                  resumeAnchor: anchor("right"))
        let leftAck = try access.persistEditingWrite(left)
        let beforeDenied = try fixture.coordinator.workspaceWriter.currentRevision()
        XCTAssertThrowsError(try access.persistEditingWrite(right)) {
            XCTAssertEqual($0 as? FieldDraftFailureV1, .staleDraftRevision)
        }
        XCTAssertThrowsError(try access.prepareEditingWrite(request, replacing: initialAck.checkpoint,
                                                            resumeAnchor: anchor("stale"))) {
            XCTAssertEqual($0 as? FieldDraftFailureV1, .staleDraftRevision)
        }
        XCTAssertThrowsError(try access.persistEditingWrite(initial)) {
            XCTAssertEqual($0 as? MyDayPlanningExecutionFailureV1, .incompleteReadback)
        }
        XCTAssertEqual(try access.editingAcknowledgement(draftID: initial.checkpoint.draftID), leftAck)
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), beforeDenied)
        XCTAssertEqual(try rowCount(MutationReceiptRow.self, fixture), 2)
        XCTAssertFalse(fixture.coordinator.modelContext.hasChanges)
    }

    #if DEBUG
    @MainActor
    func testUncertainCreationAndRevisionRetainExactPendingWriteAndReceipt() async throws {
        let fixture = try await makeFixture("uncertain-editing")
        defer { fixture.cleanUp() }
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        var previous: FieldDraftCheckpointV1?
        for index in 0..<2 {
            let request = try makeRequest(workspaceID: fixture.coordinator.workspaceID,
                                          name: "Recorder \(index)")
            let write = try access.prepareEditingWrite(request, replacing: previous,
                                                      resumeAnchor: anchor("step-\(index)"))
            let before = try fixture.coordinator.workspaceWriter.currentRevision()
            var interrupted = false
            access.setPlanningEffectHookForTesting { point in
                guard point == .editingCheckpoint, !interrupted else { return }
                interrupted = true
                throw CheckpointTestFailure.interrupted
            }
            XCTAssertThrowsError(try access.persistEditingWrite(write)) {
                XCTAssertEqual($0 as? CheckpointTestFailure, .interrupted)
            }
            XCTAssertTrue(interrupted)
            access.setPlanningEffectHookForTesting(nil)
            XCTAssertEqual(try access.loadPlanningCheckpoint(draftID: write.checkpoint.draftID), write.checkpoint)
            let afterEffect = try fixture.coordinator.workspaceWriter.currentRevision()
            XCTAssertEqual(afterEffect.revision, before.revision + 1)
            let acknowledgement = try access.persistEditingWrite(write)
            XCTAssertEqual(acknowledgement.checkpoint, write.checkpoint)
            XCTAssertEqual(acknowledgement.receipt.mutationID, write.checkpoint.mutationID)
            XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), afterEffect)
            previous = acknowledgement.checkpoint
        }
        XCTAssertEqual(try rowCount(MutationReceiptRow.self, fixture), 2)
        XCTAssertEqual(try rowCount(FieldDraftCheckpointRow.self, fixture), 1)
        XCTAssertEqual(try rowCount(MyDayPlanRowV1.self, fixture), 0)
    }

    @MainActor
    func testPendingEditingWriteReplaysAfterGenuineProductionAuthorityReopen() async throws {
        let fixture = try await makeFixture("cold-editing")
        var reopened: CheckpointReopenedAuthority?
        defer {
            try? reopened?.coordinator.invalidateAndReleaseWriter()
            fixture.cleanUp()
        }
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let write = try access.prepareEditingWrite(makeRequest(workspaceID: fixture.coordinator.workspaceID),
                                                   replacing: nil, resumeAnchor: anchor("items"))
        access.setPlanningEffectHookForTesting { point in
            if point == .editingCheckpoint { throw CheckpointTestFailure.interrupted }
        }
        XCTAssertThrowsError(try access.persistEditingWrite(write))
        access.setPlanningEffectHookForTesting(nil)
        let originalAck = try access.editingAcknowledgement(draftID: write.checkpoint.draftID)
        let oldWriter = try fixture.coordinator.workspaceWriter.currentRevision().writerInstanceID
        try fixture.coordinator.invalidateAndReleaseWriter()
        reopened = try await CheckpointReopenedAuthority.start(testCase: self,
            support: fixture.support, defaults: fixture.defaults)
        let fresh = try XCTUnwrap(reopened)
        let freshAccess = try XCTUnwrap(fresh.presentation.myDayAccess)
        let beforeRetry = try fresh.coordinator.workspaceWriter.currentRevision()
        XCTAssertNotEqual(beforeRetry.writerInstanceID, oldWriter)
        XCTAssertEqual(try freshAccess.persistEditingWrite(write), originalAck)
        XCTAssertEqual(try freshAccess.editingAcknowledgement(draftID: write.checkpoint.draftID), originalAck)
        XCTAssertEqual(try fresh.coordinator.workspaceWriter.currentRevision(), beforeRetry)
        XCTAssertEqual(try fresh.coordinator.modelContext.fetch(FetchDescriptor<MutationReceiptRow>()).count, 1)
        XCTAssertEqual(try fresh.coordinator.modelContext.fetch(FetchDescriptor<MyDayPlanRowV1>()).count, 0)
        XCTAssertFalse(fresh.coordinator.modelContext.hasChanges)
    }

    @MainActor
    func testCoverAfterEditingEffectDeniesOldPublicationAndFreshAccessAcknowledgesSameWrite() async throws {
        let fixture = try await makeFixture("editing-cover")
        defer { fixture.cleanUp() }
        let original = try XCTUnwrap(fixture.presentation.myDayAccess)
        let write = try original.prepareEditingWrite(makeRequest(workspaceID: fixture.coordinator.workspaceID),
                                                     replacing: nil, resumeAnchor: anchor("items"))
        original.setPlanningEffectHookForTesting { point in
            if point == .editingCheckpoint { fixture.presentation.receive(.sceneInactive) }
        }
        XCTAssertThrowsError(try original.persistEditingWrite(write))
        original.setPlanningEffectHookForTesting(nil)
        let afterEffect = try fixture.coordinator.workspaceWriter.currentRevision()
        XCTAssertThrowsError(try original.editingAcknowledgement(draftID: write.checkpoint.draftID))
        let published = expectation(description: "Fresh original publication after cover")
        let observation = fixture.presentation.$permitsContentPresentation.filter { $0 }.prefix(1)
            .sink { _ in published.fulfill() }
        fixture.presentation.receive(.sceneActive)
        await fulfillment(of: [published], timeout: 30)
        observation.cancel()
        let fresh = try XCTUnwrap(fixture.presentation.myDayAccess)
        XCTAssertThrowsError(try original.persistEditingWrite(write))
        let acknowledgement = try fresh.persistEditingWrite(write)
        XCTAssertEqual(acknowledgement.checkpoint, write.checkpoint)
        XCTAssertEqual(acknowledgement.receipt.mutationID, write.checkpoint.mutationID)
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), afterEffect)
        XCTAssertEqual(try rowCount(MutationReceiptRow.self, fixture), 1)
    }

    @MainActor
    func testPlanningDiscardCapacityMatchesPersistedRevisionBoundsWithoutFabricatedHistory() throws {
        let ceiling = UInt64(Int64.max)
        for state in [FieldDraftStateV1.active, .recoveryRequired, .discardPending] {
            let steps: UInt64 = state == .discardPending ? 1 : 2
            let last = ceiling - steps
            XCTAssertNoThrow(try ProductionMyDayPlanningCommitServiceV1.validateDiscardCapacity(
                state: state, draftRevision: 1, workspaceRevision: 1))
            XCTAssertNoThrow(try ProductionMyDayPlanningCommitServiceV1.validateDiscardCapacity(
                state: state, draftRevision: last, workspaceRevision: last))
            for revisions in [(last + 1, UInt64(1)), (UInt64(1), last + 1),
                              (ceiling, ceiling), (UInt64.max, UInt64.max), (UInt64(0), UInt64(1))] {
                XCTAssertThrowsError(try ProductionMyDayPlanningCommitServiceV1.validateDiscardCapacity(
                    state: state, draftRevision: revisions.0, workspaceRevision: revisions.1)) {
                    XCTAssertEqual($0 as? MyDayPlanningExecutionFailureV1, .unsupportedState)
                }
            }
        }
        for state in [FieldDraftStateV1.committing, .conflicted, .committed, .discarded] {
            XCTAssertThrowsError(try ProductionMyDayPlanningCommitServiceV1.validateDiscardCapacity(
                state: state, draftRevision: 1, workspaceRevision: 1))
        }
    }

    @MainActor
    func testPlanningDiscardPreparationIsZeroWriteAndTerminalReceiptClosesOnlyTheDraft() async throws {
        let fixture = try await makeFixture("discard-prepare")
        defer { fixture.cleanUp() }
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let request = try makeRequest(workspaceID: fixture.coordinator.workspaceID)
        let editing = try access.prepareEditingWrite(request, replacing: nil, resumeAnchor: anchor("items"))
        let acknowledged = try access.persistEditingWrite(editing)
        let before = try fixture.coordinator.workspaceWriter.currentRevision()

        let write = try access.preparePlanningDiscard(expectedCheckpoint: acknowledged.checkpoint)

        XCTAssertEqual(write.expectedCheckpoint, acknowledged.checkpoint)
        XCTAssertEqual(write.pendingCheckpoint.state, .discardPending)
        XCTAssertEqual(write.pendingCheckpoint.payloadData, acknowledged.checkpoint.payloadData)
        XCTAssertEqual(write.plan.planID, acknowledged.checkpoint.draftID)
        XCTAssertEqual(write.plan.draftID, acknowledged.checkpoint.draftID)
        XCTAssertEqual(write.plan.stageIDs, [])
        XCTAssertEqual(write.plan.reservationIDs, [])
        XCTAssertEqual(write.terminalBundle.discardedCheckpoint.state, .discarded)
        XCTAssertEqual(write.terminalBundle.discardedCheckpoint.payloadData, acknowledged.checkpoint.payloadData)
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), before)
        XCTAssertEqual(try rowCount(FieldDraftCheckpointRow.self, fixture), 1)
        XCTAssertEqual(try rowCount(MutationReceiptRow.self, fixture), 1)
        XCTAssertEqual(try rowCount(MyDayPlanRowV1.self, fixture), 0)
        XCTAssertEqual(try rowCount(DraftCommitSagaRow.self, fixture), 0)
        XCTAssertEqual(try rowCount(DraftContentReservationRow.self, fixture), 0)
        XCTAssertEqual(try rowCount(DraftCommitReceiptRow.self, fixture), 0)
        XCTAssertEqual(try rowCount(DraftDiscardReceiptRow.self, fixture), 0)

        let outcome = try await access.discardPlanningDraft(write)
        XCTAssertEqual(outcome.checkpoint, write.terminalBundle.discardedCheckpoint)
        XCTAssertEqual(outcome.draftReceipt, write.terminalBundle.receipt)
        XCTAssertEqual(outcome.terminalReceipt.mutationID, write.terminalBundle.mutationID)
        XCTAssertEqual(try access.discardedPlanningAcknowledgement(expectedCheckpoint: outcome.checkpoint), outcome)
        XCTAssertThrowsError(try access.preparePlanningDiscard(expectedCheckpoint: outcome.checkpoint)) {
            XCTAssertEqual($0 as? MyDayPlanningExecutionFailureV1, .unsupportedState)
        }
        XCTAssertEqual(try rowCount(FieldDraftCheckpointRow.self, fixture), 1)
        XCTAssertEqual(try rowCount(MutationReceiptRow.self, fixture), 3)
        XCTAssertEqual(try rowCount(DraftDiscardReceiptRow.self, fixture), 1)
        XCTAssertEqual(try rowCount(MyDayPlanRowV1.self, fixture), 0)
        XCTAssertEqual(try rowCount(DraftCommitSagaRow.self, fixture), 0)
        XCTAssertEqual(try rowCount(DraftContentReservationRow.self, fixture), 0)
        XCTAssertEqual(try rowCount(DraftCommitReceiptRow.self, fixture), 0)
        XCTAssertFalse(fixture.coordinator.modelContext.hasChanges)
    }

    @MainActor
    func testPlanningDiscardRefusesStaleForeignAndPreparedCheckpointsWithoutNewRows() async throws {
        let fixture = try await makeFixture("discard-denial")
        let other = try await makeFixture("discard-foreign")
        defer { fixture.cleanUp(); other.cleanUp() }
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let foreign = try XCTUnwrap(other.presentation.myDayAccess)
        let request = try makeRequest(workspaceID: fixture.coordinator.workspaceID)
        let first = try access.persistEditingWrite(try access.prepareEditingWrite(
            request, replacing: nil, resumeAnchor: anchor("items")))
        let changed = try makeRequest(workspaceID: fixture.coordinator.workspaceID, name: "Changed")
        let current = try access.persistEditingWrite(try access.prepareEditingWrite(
            changed, replacing: first.checkpoint, resumeAnchor: anchor("changed")))
        let before = try fixture.coordinator.workspaceWriter.currentRevision()
        let foreignBefore = try other.coordinator.workspaceWriter.currentRevision()

        XCTAssertThrowsError(try access.preparePlanningDiscard(expectedCheckpoint: first.checkpoint)) {
            XCTAssertEqual($0 as? FieldDraftFailureV1, .staleDraftRevision)
        }
        XCTAssertThrowsError(try foreign.preparePlanningDiscard(expectedCheckpoint: current.checkpoint))
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), before)
        XCTAssertEqual(try other.coordinator.workspaceWriter.currentRevision(), foreignBefore)
        XCTAssertEqual(try rowCount(FieldDraftCheckpointRow.self, fixture), 1)
        XCTAssertEqual(try rowCount(FieldDraftCheckpointRow.self, other), 0)
        XCTAssertEqual(try rowCount(DraftDiscardReceiptRow.self, fixture), 0)
        XCTAssertEqual(try rowCount(DraftDiscardReceiptRow.self, other), 0)

        var interrupted = false
        access.setPlanningEffectHookForTesting { point in
            guard point == .committingCheckpoint, !interrupted else { return }
            interrupted = true
            throw CheckpointTestFailure.interrupted
        }
        do {
            _ = try await access.retryPlanSave(draftID: current.checkpoint.draftID)
            XCTFail("The injected committing acknowledgement failure must escape")
        } catch {
            XCTAssertEqual(error as? CheckpointTestFailure, .interrupted)
        }
        access.setPlanningEffectHookForTesting(nil)
        XCTAssertTrue(interrupted)
        let prepared = try access.loadPlanningCheckpoint(draftID: current.checkpoint.draftID)
        XCTAssertEqual(prepared.state, .committing)
        XCTAssertThrowsError(try access.preparePlanningDiscard(expectedCheckpoint: prepared)) {
            XCTAssertEqual($0 as? MyDayPlanningExecutionFailureV1, .unsupportedState)
        }
        XCTAssertEqual(try rowCount(DraftDiscardReceiptRow.self, fixture), 0)
        XCTAssertEqual(try rowCount(MyDayPlanRowV1.self, fixture), 0)
        XCTAssertFalse(fixture.coordinator.modelContext.hasChanges)
        XCTAssertFalse(other.coordinator.modelContext.hasChanges)
    }

    @MainActor
    func testPlanningDiscardPendingEffectHotRetryUsesFrozenWrite() async throws {
        let fixture = try await makeFixture("discard-pending-hot")
        defer { fixture.cleanUp() }
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let editing = try access.persistEditingWrite(try access.prepareEditingWrite(
            makeRequest(workspaceID: fixture.coordinator.workspaceID), replacing: nil,
            resumeAnchor: anchor("items")))
        let write = try access.preparePlanningDiscard(expectedCheckpoint: editing.checkpoint)
        let changedPlan = try DraftDiscardPlanV1(planID: write.plan.planID,
            workspaceID: write.plan.workspaceID, draftID: write.plan.draftID,
            expectedDraftRevision: write.plan.expectedDraftRevision,
            nonemptyPayload: write.plan.nonemptyPayload, stageIDs: write.plan.stageIDs,
            reservationIDs: write.plan.reservationIDs,
            estimatedBytes: write.plan.estimatedBytes + 1)
        let changedWrite = MyDayPlanningDiscardWriteV1(expectedCheckpoint: write.expectedCheckpoint,
            pendingCheckpoint: write.pendingCheckpoint, plan: changedPlan,
            terminalBundle: write.terminalBundle)
        do {
            _ = try await access.discardPlanningDraft(changedWrite)
            XCTFail("A changed frozen discard plan must be rejected before a pending write")
        } catch {
            XCTAssertEqual(error as? FieldDraftFailureV1, .invalidValue)
        }
        XCTAssertEqual(try rowCount(MutationReceiptRow.self, fixture), 1)
        XCTAssertEqual(try rowCount(DraftDiscardReceiptRow.self, fixture), 0)
        access.setPlanningEffectHookForTesting { point in
            guard point == .discardPendingCheckpoint else { return }
            throw CheckpointTestFailure.interrupted
        }
        do {
            _ = try await access.discardPlanningDraft(write)
            XCTFail("The pending checkpoint acknowledgement must be uncertain after its durable CAS")
        } catch {
            XCTAssertEqual(error as? CheckpointTestFailure, .interrupted)
        }
        access.setPlanningEffectHookForTesting(nil)
        XCTAssertEqual(try access.loadPlanningCheckpoint(draftID: editing.checkpoint.draftID), write.pendingCheckpoint)
        XCTAssertEqual(try rowCount(MutationReceiptRow.self, fixture), 2)
        XCTAssertEqual(try rowCount(DraftDiscardReceiptRow.self, fixture), 0)

        let outcome = try await access.discardPlanningDraft(write)
        XCTAssertEqual(outcome.checkpoint, write.terminalBundle.discardedCheckpoint)
        XCTAssertEqual(outcome.draftReceipt, write.terminalBundle.receipt)
        let replay = try await access.discardPlanningDraft(write)
        XCTAssertEqual(replay, outcome)
        XCTAssertEqual(try rowCount(MutationReceiptRow.self, fixture), 3)
        XCTAssertEqual(try rowCount(DraftDiscardReceiptRow.self, fixture), 1)
        XCTAssertEqual(try rowCount(MyDayPlanRowV1.self, fixture), 0)
        XCTAssertFalse(fixture.coordinator.modelContext.hasChanges)
    }

    @MainActor
    func testPlanningDiscardTerminalEffectHotRetryAndFreshAcknowledgementRemainFrozen() async throws {
        let fixture = try await makeFixture("discard-terminal-hot")
        defer { fixture.cleanUp() }
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let editing = try access.persistEditingWrite(try access.prepareEditingWrite(
            makeRequest(workspaceID: fixture.coordinator.workspaceID), replacing: nil,
            resumeAnchor: anchor("items")))
        let write = try access.preparePlanningDiscard(expectedCheckpoint: editing.checkpoint)
        var interrupted = false
        access.setPlanningEffectHookForTesting { point in
            guard point == .discardTerminalBundle, !interrupted else { return }
            interrupted = true
            throw CheckpointTestFailure.interrupted
        }
        do {
            _ = try await access.discardPlanningDraft(write)
            XCTFail("The terminal acknowledgement must be uncertain after its durable effect")
        } catch {
            XCTAssertEqual(error as? CheckpointTestFailure, .interrupted)
        }
        access.setPlanningEffectHookForTesting(nil)
        XCTAssertTrue(interrupted)
        XCTAssertEqual(try access.loadPlanningCheckpoint(draftID: editing.checkpoint.draftID),
                       write.terminalBundle.discardedCheckpoint)
        XCTAssertEqual(try rowCount(MutationReceiptRow.self, fixture), 3)
        XCTAssertEqual(try rowCount(DraftDiscardReceiptRow.self, fixture), 1)

        let outcome = try await access.discardPlanningDraft(write)
        XCTAssertEqual(outcome.checkpoint, write.terminalBundle.discardedCheckpoint)
        XCTAssertEqual(try access.discardedPlanningAcknowledgement(expectedCheckpoint: outcome.checkpoint), outcome)
        XCTAssertEqual(try rowCount(MutationReceiptRow.self, fixture), 3)
        XCTAssertEqual(try rowCount(DraftDiscardReceiptRow.self, fixture), 1)
        XCTAssertEqual(try rowCount(MyDayPlanRowV1.self, fixture), 0)
        XCTAssertFalse(fixture.coordinator.modelContext.hasChanges)
    }

    @MainActor
    func testPlanningDiscardColdPendingResumeRequiresCurrentCheckpointAndAuthenticReceipt() async throws {
        let fixture = try await makeFixture("discard-pending-cold")
        var reopened: CheckpointReopenedAuthority?
        defer {
            try? reopened?.coordinator.invalidateAndReleaseWriter()
            fixture.cleanUp()
        }
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let editing = try access.persistEditingWrite(try access.prepareEditingWrite(
            makeRequest(workspaceID: fixture.coordinator.workspaceID), replacing: nil,
            resumeAnchor: anchor("items")))
        let write = try access.preparePlanningDiscard(expectedCheckpoint: editing.checkpoint)
        access.setPlanningDiscardHookForTesting { throw CheckpointTestFailure.interrupted }
        do {
            _ = try await access.discardPlanningDraft(write)
            XCTFail("The quarantine interruption must retain the pending checkpoint")
        } catch {
            XCTAssertEqual(error as? CheckpointTestFailure, .interrupted)
        }
        access.setPlanningDiscardHookForTesting(nil)
        let pending = try access.loadPlanningCheckpoint(draftID: editing.checkpoint.draftID)
        XCTAssertEqual(pending, write.pendingCheckpoint)
        let oldWriter = try fixture.coordinator.workspaceWriter.currentRevision().writerInstanceID
        try fixture.coordinator.invalidateAndReleaseWriter()
        reopened = try await CheckpointReopenedAuthority.start(testCase: self,
            support: fixture.support, defaults: fixture.defaults)
        let fresh = try XCTUnwrap(reopened)
        let freshAccess = try XCTUnwrap(fresh.presentation.myDayAccess)
        XCTAssertNotEqual(try fresh.coordinator.workspaceWriter.currentRevision().writerInstanceID, oldWriter)
        XCTAssertThrowsError(try freshAccess.preparePlanningDiscard(expectedCheckpoint: editing.checkpoint)) {
            XCTAssertEqual($0 as? FieldDraftFailureV1, .staleDraftRevision)
        }
        let resumed = try freshAccess.preparePlanningDiscard(expectedCheckpoint: pending)
        XCTAssertEqual(resumed.expectedCheckpoint, pending)
        XCTAssertEqual(resumed.pendingCheckpoint, pending)
        XCTAssertEqual(resumed.plan, write.plan)
        XCTAssertNotEqual(resumed.terminalBundle, write.terminalBundle)
        let outcome = try await freshAccess.discardPlanningDraft(resumed)
        XCTAssertEqual(outcome.checkpoint, resumed.terminalBundle.discardedCheckpoint)
        XCTAssertEqual(try rowCount(DraftDiscardReceiptRow.self, fresh), 1)
        XCTAssertEqual(try rowCount(MyDayPlanRowV1.self, fresh), 0)
        XCTAssertFalse(fresh.coordinator.modelContext.hasChanges)
    }

    @MainActor
    func testPlanningDiscardColdTerminalAcknowledgementReadsTheExactFrozenOutcome() async throws {
        let fixture = try await makeFixture("discard-terminal-cold")
        var reopened: CheckpointReopenedAuthority?
        defer {
            try? reopened?.coordinator.invalidateAndReleaseWriter()
            fixture.cleanUp()
        }
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let editing = try access.persistEditingWrite(try access.prepareEditingWrite(
            makeRequest(workspaceID: fixture.coordinator.workspaceID), replacing: nil,
            resumeAnchor: anchor("items")))
        let write = try access.preparePlanningDiscard(expectedCheckpoint: editing.checkpoint)
        access.setPlanningEffectHookForTesting { point in
            if point == .discardTerminalBundle { throw CheckpointTestFailure.interrupted }
        }
        do {
            _ = try await access.discardPlanningDraft(write)
            XCTFail("The terminal acknowledgement interruption must retain its durable result")
        } catch {
            XCTAssertEqual(error as? CheckpointTestFailure, .interrupted)
        }
        access.setPlanningEffectHookForTesting(nil)
        XCTAssertEqual(try access.loadPlanningCheckpoint(draftID: editing.checkpoint.draftID),
                       write.terminalBundle.discardedCheckpoint)
        try fixture.coordinator.invalidateAndReleaseWriter()
        reopened = try await CheckpointReopenedAuthority.start(testCase: self,
            support: fixture.support, defaults: fixture.defaults)
        let fresh = try XCTUnwrap(reopened)
        let freshAccess = try XCTUnwrap(fresh.presentation.myDayAccess)
        let outcome = try freshAccess.discardedPlanningAcknowledgement(
            expectedCheckpoint: write.terminalBundle.discardedCheckpoint)
        XCTAssertEqual(outcome.checkpoint, write.terminalBundle.discardedCheckpoint)
        XCTAssertEqual(outcome.draftReceipt, write.terminalBundle.receipt)
        XCTAssertEqual(outcome.terminalReceipt.mutationID, write.terminalBundle.mutationID)
        XCTAssertEqual(try rowCount(MutationReceiptRow.self, fresh), 3)
        XCTAssertEqual(try rowCount(DraftDiscardReceiptRow.self, fresh), 1)
        XCTAssertEqual(try rowCount(MyDayPlanRowV1.self, fresh), 0)
        XCTAssertFalse(fresh.coordinator.modelContext.hasChanges)
    }

    @MainActor
    func testPlanningDiscardCoverDuringQuarantineDeniesOldPublicationAndFreshAccessFinishesFrozenWrite() async throws {
        let fixture = try await makeFixture("discard-cover")
        defer { fixture.cleanUp() }
        let original = try XCTUnwrap(fixture.presentation.myDayAccess)
        let editing = try original.persistEditingWrite(try original.prepareEditingWrite(
            makeRequest(workspaceID: fixture.coordinator.workspaceID), replacing: nil,
            resumeAnchor: anchor("items")))
        let write = try original.preparePlanningDiscard(expectedCheckpoint: editing.checkpoint)
        let presentation = fixture.presentation
        original.setPlanningDiscardHookForTesting { presentation.receive(.sceneInactive) }
        do {
            _ = try await original.discardPlanningDraft(write)
            XCTFail("Cover during quarantine must deny the original publication before terminal write")
        } catch {
            XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied)
        }
        original.setPlanningDiscardHookForTesting(nil)
        XCTAssertThrowsError(try original.loadPlanningCheckpoint(draftID: editing.checkpoint.draftID))
        let published = expectation(description: "Fresh discard publication after cover")
        let observation = fixture.presentation.$permitsContentPresentation.filter { $0 }.prefix(1)
            .sink { _ in published.fulfill() }
        fixture.presentation.receive(.sceneActive)
        await fulfillment(of: [published], timeout: 30)
        observation.cancel()
        let fresh = try XCTUnwrap(fixture.presentation.myDayAccess)
        do {
            _ = try await original.discardPlanningDraft(write)
            XCTFail("The covered publication must remain revoked after a fresh publication exists")
        } catch {
            XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied)
        }
        XCTAssertEqual(try fresh.loadPlanningCheckpoint(draftID: editing.checkpoint.draftID), write.pendingCheckpoint)
        let resumed = try fresh.preparePlanningDiscard(expectedCheckpoint: write.pendingCheckpoint)
        let outcome = try await fresh.discardPlanningDraft(resumed)
        XCTAssertEqual(outcome.checkpoint, resumed.terminalBundle.discardedCheckpoint)
        XCTAssertEqual(try rowCount(DraftDiscardReceiptRow.self, fixture), 1)
        XCTAssertEqual(try rowCount(MyDayPlanRowV1.self, fixture), 0)
        XCTAssertFalse(fixture.coordinator.modelContext.hasChanges)
    }
    #endif

    @MainActor
    func testForeignWorkspaceAndChangedPredecessorAreDeniedAndTerminalPlanIsNotAnEditingAcknowledgement() async throws {
        let fixture = try await makeFixture("bound-context")
        let other = try await makeFixture("foreign-context")
        defer { fixture.cleanUp(); other.cleanUp() }
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let foreign = try XCTUnwrap(other.presentation.myDayAccess)
        let request = try makeRequest(workspaceID: fixture.coordinator.workspaceID)
        let write = try access.prepareEditingWrite(request, replacing: nil, resumeAnchor: anchor("items"))
        let foreignBefore = try other.coordinator.workspaceWriter.currentRevision()
        XCTAssertThrowsError(try foreign.persistEditingWrite(write))
        XCTAssertThrowsError(try foreign.prepareEditingWrite(request, replacing: nil,
                                                             resumeAnchor: anchor("items"))) {
            XCTAssertEqual($0 as? MyDayFailureV1, .wrongWorkspace)
        }
        XCTAssertEqual(try other.coordinator.workspaceWriter.currentRevision(), foreignBefore)
        XCTAssertEqual(try rowCount(FieldDraftCheckpointRow.self, other), 0)
        let acknowledgement = try access.persistEditingWrite(write)
        let saved = try await access.savePlan(request)
        let changedBase = try makeRequest(workspaceID: fixture.coordinator.workspaceID,
                                          predecessor: saved.targetResult.plan)
        let beforeDenied = try fixture.coordinator.workspaceWriter.currentRevision()
        XCTAssertThrowsError(try access.prepareEditingWrite(changedBase,
            replacing: acknowledgement.checkpoint, resumeAnchor: anchor("items"))) {
            XCTAssertEqual($0 as? MyDayPlanningExecutionFailureV1, .unsupportedState)
        }
        XCTAssertEqual(try access.loadPlanningCheckpoint(draftID: saved.checkpoint.draftID), saved.checkpoint)
        XCTAssertThrowsError(try access.editingAcknowledgement(draftID: saved.checkpoint.draftID)) {
            XCTAssertEqual($0 as? MyDayPlanningExecutionFailureV1, .unsupportedState)
        }
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), beforeDenied)
        XCTAssertFalse(fixture.coordinator.modelContext.hasChanges)
        XCTAssertFalse(other.coordinator.modelContext.hasChanges)
    }

    @MainActor
    func testPlanningContextReadsExactCivilDayHistoryAndRecordedByValuesWithoutWriting() async throws {
        let fixture = try await makeFixture("planning-context-values")
        contextReadCleanup(fixture)
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let writer = fixture.coordinator.workspaceWriter
        let request = try makeRequest(workspaceID: fixture.coordinator.workspaceID)
        let key = request.confirmedContext.key
        let before = try writer.currentRevision()
        let empty = try access.planningContext(for: key)
        XCTAssertEqual(empty.key, key)
        XCTAssertNil(empty.currentPlan)
        XCTAssertTrue(empty.recordedBySnapshots.isEmpty)
        XCTAssertEqual(try writer.currentRevision(), before)
        XCTAssertFalse(fixture.coordinator.modelContext.hasChanges)

        let recorder = request.confirmedContext.recordedBy
        let assignee = try ActorSnapshotV1(snapshotID: UUID(), workspaceID: key.workspaceID,
            actor: recorder.actor, responsibility: .assignedTo,
            displayNameAtTime: recorder.displayNameAtTime, capturedAt: recorder.capturedAt)
        _ = try writer.execute(.applyPartyAccountability(.appendActorSnapshot(recorder)),
                               mutationID: MutationIDV1(rawValue: UUID()))
        _ = try writer.execute(.applyPartyAccountability(.appendActorSnapshot(assignee)),
                               mutationID: MutationIDV1(rawValue: UUID()))
        let first = try await access.savePlan(request)
        let next = try MyDayPlanningPlanSaveRequestV1(confirmedContext: request.confirmedContext,
            draft: request.draft, predecessor: first.targetResult.plan)
        let second = try await access.savePlan(next)
        let beforeReads = try writer.currentRevision()
        let receiptCount = try rowCount(MutationReceiptRow.self, fixture)
        let value = try access.planningContext(for: key)
        XCTAssertEqual(value.currentPlan, second.targetResult.plan)
        XCTAssertEqual(value.currentPlan?.revision, 2)
        XCTAssertEqual(value.recordedBySnapshots, [recorder])
        XCTAssertEqual(try rowCount(MyDayPlanRowV1.self, fixture), 2)
        for neighbor in [
            try MyDayKeyV1(workspaceID: key.workspaceID, civilDate: .init("2026-09-13"),
                           ianaTimeZoneIdentifier: key.ianaTimeZoneIdentifier),
            try MyDayKeyV1(workspaceID: key.workspaceID, civilDate: key.civilDate,
                           ianaTimeZoneIdentifier: "Europe/London")
        ] {
            let other = try access.planningContext(for: neighbor)
            XCTAssertEqual(other.key, neighbor)
            XCTAssertNil(other.currentPlan)
            XCTAssertEqual(other.recordedBySnapshots, [recorder])
        }
        let foreign = try MyDayKeyV1(workspaceID: .init(rawValue: UUID()),
            civilDate: key.civilDate, ianaTimeZoneIdentifier: key.ianaTimeZoneIdentifier)
        XCTAssertThrowsError(try access.planningContext(for: foreign)) {
            XCTAssertEqual($0 as? MyDayFailureV1, .wrongWorkspace)
        }
        XCTAssertEqual(try writer.currentRevision(), beforeReads)
        XCTAssertEqual(try rowCount(MutationReceiptRow.self, fixture), receiptCount)
        XCTAssertFalse(fixture.coordinator.modelContext.hasChanges)
    }

    @MainActor
    func testPlanningContextRejectsOldPublicationAfterCoverAndFreshRepublish() async throws {
        let fixture = try await makeFixture("planning-context-cover")
        contextReadCleanup(fixture)
        let original = try XCTUnwrap(fixture.presentation.myDayAccess)
        let request = try makeRequest(workspaceID: fixture.coordinator.workspaceID)
        let saved = try await original.savePlan(request)
        let key = request.confirmedContext.key
        let before = try fixture.coordinator.workspaceWriter.currentRevision()
        fixture.presentation.receive(.sceneInactive)
        XCTAssertThrowsError(try original.planningContext(for: key))
        let published = expectation(description: "Fresh planning context publication")
        let observation = fixture.presentation.$permitsContentPresentation.filter { $0 }.prefix(1)
            .sink { _ in published.fulfill() }
        fixture.presentation.receive(.sceneActive)
        await fulfillment(of: [published], timeout: 30)
        observation.cancel()
        let fresh = try XCTUnwrap(fixture.presentation.myDayAccess)
        XCTAssertThrowsError(try original.planningContext(for: key))
        XCTAssertEqual(try fresh.planningContext(for: key).currentPlan, saved.targetResult.plan)
        XCTAssertEqual(try fixture.coordinator.workspaceWriter.currentRevision(), before)
        XCTAssertFalse(fixture.coordinator.modelContext.hasChanges)
    }

    @MainActor
    func testPlanningContextRejectsCorruptRetainedPlanWithoutRepairOrNewReceipts() async throws {
        let fixture = try await makeFixture("planning-context-corrupt")
        contextReadCleanup(fixture)
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let request = try makeRequest(workspaceID: fixture.coordinator.workspaceID)
        _ = try await access.savePlan(request)
        let context = fixture.coordinator.modelContext
        let row = try XCTUnwrap(context.fetch(FetchDescriptor<MyDayPlanRowV1>()).first)
        let originalBytes = row.canonicalData
        let hostileBytes = Data("{corrupt-retained-plan}".utf8)
        row.canonicalData = hostileBytes
        try context.save()
        let receipts = try rowCount(MutationReceiptRow.self, fixture)
        XCTAssertThrowsError(try access.planningContext(for: request.confirmedContext.key))
        XCTAssertEqual(row.canonicalData, hostileBytes)
        XCTAssertNotEqual(row.canonicalData, originalBytes)
        XCTAssertEqual(try rowCount(MyDayPlanRowV1.self, fixture), 1)
        XCTAssertEqual(try rowCount(MutationReceiptRow.self, fixture), receipts)
        XCTAssertFalse(context.hasChanges)
    }

    @MainActor
    private func contextReadCleanup(_ fixture: V23ProductionMyDayPresentationHarness) {
        addTeardownBlock { [support = fixture.support, defaults = fixture.defaults,
                            suite = fixture.suiteName] in
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: support)
        }
    }

    @MainActor
    private func makeFixture(_ name: String) async throws -> V23ProductionMyDayPresentationHarness {
        try await .start(testCase: self, name: "checkpoint-\(name)")
    }

    private func anchor(_ section: String) throws -> DraftResumeAnchorV1 { try .init(sectionID: section) }

    private func makeRequest(workspaceID: WorkspaceID, name: String = "Recorder",
                             predecessor: MyDayPlanV1? = nil) throws -> MyDayPlanningPlanSaveRequestV1 {
        let key = try MyDayKeyV1(workspaceID: workspaceID, civilDate: .init("2026-09-12"),
                                 ianaTimeZoneIdentifier: "America/New_York")
        let actor = try LocalActorReferenceV1(actorReferenceID: UUID(), workspaceID: workspaceID,
                                             displayName: name)
        let snapshot = try ActorSnapshotV1(snapshotID: UUID(), workspaceID: workspaceID, actor: actor,
            responsibility: .recordedBy, displayNameAtTime: name,
            capturedAt: Date(timeIntervalSince1970: 1_789_084_800))
        let context = try MyDayPlanningConfirmedContextV1(key: key, recordedBy: snapshot,
            keyWasExplicitlyConfirmed: true, recordedByWasExplicitlySelectedOrCaptured: true)
        return try .init(confirmedContext: context,
            draft: .init(key: key, items: [], eligibleReferences: []), predecessor: predecessor)
    }

    @MainActor
    private func rowCount<T: PersistentModel>(_ type: T.Type,
        _ authority: CheckpointReopenedAuthority) throws -> Int {
        try authority.coordinator.modelContext.fetch(FetchDescriptor<T>()).count
    }

    @MainActor
    private func rowCount<T: PersistentModel>(_ type: T.Type,
        _ fixture: V23ProductionMyDayPresentationHarness) throws -> Int {
        try fixture.coordinator.modelContext.fetch(FetchDescriptor<T>()).count
    }
}

private enum CheckpointTestFailure: Error, Equatable { case interrupted }

@MainActor
private struct CheckpointReopenedAuthority {
    let router: StartupRouter
    let session: ProductionAppAccessSessionV1
    let presentation: AppAccessPresentationV1
    let coordinator: StoreSessionCoordinator

    static func start(testCase: XCTestCase, support: URL, defaults: UserDefaults) async throws -> Self {
        let router = StartupRouter(applicationSupportURL: support)
        let session = try await ProductionCompositionRoot.makeAppAccessSession(
            applicationSupportURL: support, startupRouter: router, defaults: defaults,
            authenticationClient: CheckpointAuthentication(), notificationSystem: CheckpointNotificationSystem())
        let presentation = AppAccessPresentationV1(startupRouter: router, sessionFactory: { session })
        let published = testCase.expectation(description: "Cold My Day editing authority")
        let observation = presentation.$permitsContentPresentation.filter { $0 }.prefix(1)
            .sink { _ in published.fulfill() }
        await presentation.bootstrapIfNeeded()
        await testCase.fulfillment(of: [published], timeout: 30)
        observation.cancel()
        guard case .ready(let coordinator, _, _) = router.route else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        return .init(router: router, session: session, presentation: presentation, coordinator: coordinator)
    }
}

private actor CheckpointAuthentication: LocalAuthenticationClient {
    func availability() -> LocalAuthenticationAvailabilityV1 {
        .systemValue(status: .available, biometry: .faceID)
    }
    func authenticate(_ attempt: LocalAuthenticationAttemptV1) -> LocalAuthenticationOutcomeV1 { .authenticated }
    func cancel(attemptID: UUID) {}
}

@MainActor
private final class CheckpointNotificationSystem: NotificationSystemPortV1 {
    private var requests: [NotificationSystemRequestV1] = []
    func authorization() async throws -> LocalReminderAuthorizationV1 { .authorized }
    func observations() async throws -> [NotificationSystemObservationV1] {
        requests.map { .init(requestID: $0.notification.requestID, request: $0, delivered: false) }
    }
    func add(_ request: NotificationSystemRequestV1) async throws { requests.append(request) }
    func remove(_ requestIDs: [String]) async throws {
        requests.removeAll { requestIDs.contains($0.notification.requestID) }
    }
}


extension V23MyDayPlanningCheckpointTests {
    @MainActor
    func testResolvedEditingAcknowledgementUsesOriginalReceiptAndOrdinarySaveRetainsReviewedHistory() async throws {
        let fixture = try await makeFixture("resolved-editing-origin")
        defer { fixture.cleanUp() }
        let originalAccess = try XCTUnwrap(fixture.presentation.myDayAccess)
        let writer = fixture.coordinator.workspaceWriter
        let original = try seedReviewedEditingResolution(in: fixture.coordinator)
        let resolved = original.resolution.successorCheckpoint

        let acknowledgement = try originalAccess.editingAcknowledgement(draftID: resolved.draftID)
        XCTAssertEqual(acknowledgement.checkpoint, resolved)
        XCTAssertEqual(acknowledgement.receipt, original.original.receipt)
        XCTAssertEqual(try writer.reviewedFieldDraftResolutionEvidence(
            mutationID: original.original.mutation.mutationID), original)

        let beforeCover = try writer.currentRevision()
        let rowsBeforeCover = try editingOriginRowCounts(in: fixture.coordinator.modelContext)
        fixture.presentation.receive(.sceneInactive)
        XCTAssertThrowsError(try originalAccess.editingAcknowledgement(draftID: resolved.draftID))
        XCTAssertThrowsError(try originalAccess.prepareEditingWrite(
            try resolvedPlanRequest(from: resolved),
            replacing: resolved, resumeAnchor: anchor("covered")))
        XCTAssertEqual(try writer.currentRevision(), beforeCover)
        XCTAssertEqual(try editingOriginRowCounts(in: fixture.coordinator.modelContext), rowsBeforeCover)
        let published = expectation(description: "Fresh resolved editing publication")
        let observation = fixture.presentation.$permitsContentPresentation.filter { $0 }.prefix(1)
            .sink { _ in published.fulfill() }
        fixture.presentation.receive(.sceneActive)
        await fulfillment(of: [published], timeout: 30)
        observation.cancel()
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        XCTAssertEqual(try access.editingAcknowledgement(draftID: resolved.draftID), acknowledgement)
        XCTAssertThrowsError(try originalAccess.editingAcknowledgement(draftID: resolved.draftID))

        let beforePrepare = try writer.currentRevision()
        let beforeRows = try editingOriginRowCounts(in: fixture.coordinator.modelContext)
        let ordinary = try access.prepareEditingWrite(
            try resolvedPlanRequest(from: resolved),
            replacing: resolved, resumeAnchor: anchor("ordinary-after-resolution")
        )
        XCTAssertEqual(ordinary.checkpoint.draftID, resolved.draftID)
        XCTAssertEqual(ordinary.checkpoint.draftRevision, resolved.draftRevision + 1)
        XCTAssertEqual(try writer.currentRevision(), beforePrepare)
        XCTAssertEqual(try editingOriginRowCounts(in: fixture.coordinator.modelContext), beforeRows)

        let ordinaryAck = try access.persistEditingWrite(ordinary)
        XCTAssertEqual(ordinaryAck.checkpoint, ordinary.checkpoint)
        XCTAssertNotEqual(ordinaryAck.receipt, original.original.receipt)
        let outcome = try await access.retryPlanSave(draftID: ordinary.checkpoint.draftID)
        XCTAssertEqual(outcome.checkpoint.state, .committed)
        XCTAssertEqual(try writer.reviewedFieldDraftResolutionEvidence(
            mutationID: original.original.mutation.mutationID), original)
        XCTAssertFalse(fixture.coordinator.modelContext.hasChanges)
    }

    @MainActor
    func testResolvedEditingRejectsStaleCoveredAndCorruptOriginsWithoutWrites() async throws {
        let fixture = try await makeFixture("resolved-editing-stale")
        defer { fixture.cleanUp() }
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let writer = fixture.coordinator.workspaceWriter
        let original = try seedReviewedEditingResolution(in: fixture.coordinator)
        let resolved = original.resolution.successorCheckpoint
        let newer = try access.prepareEditingWrite(
            try resolvedPlanRequest(from: resolved),
            replacing: resolved, resumeAnchor: anchor("newer")
        )
        _ = try access.persistEditingWrite(newer)
        let revision = try writer.currentRevision()
        let rows = try editingOriginRowCounts(in: fixture.coordinator.modelContext)
        XCTAssertThrowsError(try access.prepareEditingWrite(
            try resolvedPlanRequest(from: resolved),
            replacing: resolved, resumeAnchor: anchor("stale"))) {
            XCTAssertEqual($0 as? FieldDraftFailureV1, .staleDraftRevision)
        }
        XCTAssertEqual(try writer.currentRevision(), revision)
        XCTAssertEqual(try editingOriginRowCounts(in: fixture.coordinator.modelContext), rows)
        XCTAssertFalse(fixture.coordinator.modelContext.hasChanges)

        let corrupt = try await makeFixture("resolved-editing-corrupt")
        defer { corrupt.cleanUp() }
        let corruptAccess = try XCTUnwrap(corrupt.presentation.myDayAccess)
        let corruptWriter = corrupt.coordinator.workspaceWriter
        let corruptOriginal = try seedReviewedEditingResolution(in: corrupt.coordinator)
        let corruptResolved = corruptOriginal.resolution.successorCheckpoint
        let key = MutationWorkspaceKeyV1.value(
            workspaceID: corrupt.coordinator.workspaceID,
            mutationID: corruptOriginal.original.mutation.mutationID
        )
        let context = corrupt.coordinator.modelContext
        let originalRow = try XCTUnwrap(context.fetch(FetchDescriptor<MutationReceiptRow>(
            predicate: #Predicate { $0.workspaceMutationKey == key }
        )).first)
        context.delete(originalRow)
        try context.save()
        let corruptRevision = try corruptWriter.currentRevision()
        let corruptRows = try editingOriginRowCounts(in: context)
        XCTAssertThrowsError(try corruptAccess.editingAcknowledgement(draftID: corruptResolved.draftID))
        XCTAssertThrowsError(try corruptAccess.prepareEditingWrite(
            try resolvedPlanRequest(from: corruptResolved),
            replacing: corruptResolved, resumeAnchor: anchor("corrupt")))
        XCTAssertEqual(try corruptWriter.currentRevision(), corruptRevision)
        XCTAssertEqual(try editingOriginRowCounts(in: context), corruptRows)
        XCTAssertFalse(context.hasChanges)
    }

    @MainActor
    private func resolvedPlanRequest(
        from checkpoint: FieldDraftCheckpointV1
    ) throws -> MyDayPlanningPlanSaveRequestV1 {
        let payload = try MyDayPlanningDraftCodecV1.validateCheckpointPayload(checkpoint)
        guard case .editing = payload.phase,
              let context = payload.confirmedContext,
              case let .plan(draft, predecessor)? = payload.editingIntent else {
            throw FieldDraftFailureV1.invalidValue
        }
        return try MyDayPlanningPlanSaveRequestV1(
            confirmedContext: context,
            draft: draft,
            predecessor: predecessor
        )
    }

    @MainActor
    private func seedReviewedEditingResolution(
        in coordinator: StoreSessionCoordinator
    ) throws -> ReviewedFieldDraftResolutionEvidenceV1 {
        let instant = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        let fixture = try ReviewedResolutionTestFixtureV1(
            workspaceID: coordinator.workspaceID,
            now: instant
        )
        let writer = coordinator.workspaceWriter
        _ = try writer.commitFieldDraft(fixture.ordinary(fixture.initial))
        _ = try writer.commitFieldDraft(fixture.ordinary(fixture.conflicted))
        let resolution = try fixture.resolution(
            target: nil,
            workspaceRevision: writer.currentRevision().revision
        )
        let receipt = try writer.commitFieldDraft(resolution)
        let original = try XCTUnwrap(writer.reviewedFieldDraftResolutionEvidence(
            mutationID: resolution.mutationID
        ))
        XCTAssertEqual(original.original.receipt, receipt)
        XCTAssertFalse(coordinator.modelContext.hasChanges)
        return original
    }

    @MainActor
    private func editingOriginRowCounts(in context: ModelContext) throws -> [Int] {
        try [
            context.fetchCount(FetchDescriptor<MutationReceiptRow>()),
            context.fetchCount(FetchDescriptor<FieldDraftCheckpointRow>()),
            context.fetchCount(FetchDescriptor<DraftCommitSagaRow>()),
            context.fetchCount(FetchDescriptor<DraftCommitReceiptRow>()),
            context.fetchCount(FetchDescriptor<MyDayPlanRowV1>()),
            context.fetchCount(FetchDescriptor<AttachmentStagingItemRow>()),
            context.fetchCount(FetchDescriptor<DraftContentReservationRow>())
        ]
    }
}

extension V23MyDayPlanningCheckpointTests {
    @MainActor
    func testReviewedResolutionSurvivesProductionDiscardReplayAndColdAuthority() async throws {
        for existingTarget in [false, true] {
            let fixture = try await makeFixture("reviewed-discard-\(existingTarget)")
            var reopened: CheckpointReopenedAuthority?
            defer {
                try? reopened?.coordinator.invalidateAndReleaseWriter()
                fixture.cleanUp()
            }
            let access = try XCTUnwrap(fixture.presentation.myDayAccess)
            let writer = fixture.coordinator.workspaceWriter
            let original = try seedReviewedDiscardResolution(in: fixture.coordinator, existingTarget: existingTarget)
            let resolved = original.resolution.successorCheckpoint
            let request = try resolvedPlanRequest(from: resolved)
            let targetBefore = try writer.currentPlan(for: request.confirmedContext.key)
            let before = try writer.currentRevision()
            let write = try access.preparePlanningDiscard(expectedCheckpoint: resolved)
            XCTAssertEqual(try writer.currentRevision(), before)

            let outcome = try await access.discardPlanningDraft(write)
            XCTAssertEqual(outcome.checkpoint, write.terminalBundle.discardedCheckpoint)
            XCTAssertEqual(outcome.checkpoint.state, .discarded)
            XCTAssertEqual(try writer.currentRevision().revision, before.revision + 2)
            XCTAssertEqual(try writer.currentPlan(for: request.confirmedContext.key), targetBefore)
            XCTAssertEqual(try rowCount(DraftDiscardReceiptRow.self, fixture), 1)
            XCTAssertEqual(try rowCount(DraftCommitSagaRow.self, fixture), 0)
            XCTAssertEqual(try rowCount(DraftCommitReceiptRow.self, fixture), 0)
            XCTAssertEqual(try rowCount(AttachmentStagingItemRow.self, fixture), 0)
            XCTAssertEqual(try rowCount(DraftContentReservationRow.self, fixture), 0)
            XCTAssertEqual(try writer.reviewedFieldDraftResolutionEvidence(
                mutationID: original.original.mutation.mutationID), original)
            let revision = try writer.currentRevision()
            let rows = try editingOriginRowCounts(in: fixture.coordinator.modelContext)
            let replay = try await access.discardPlanningDraft(write)
            XCTAssertEqual(replay, outcome)
            XCTAssertEqual(try writer.currentRevision(), revision)
            XCTAssertEqual(try editingOriginRowCounts(in: fixture.coordinator.modelContext), rows)

            try fixture.coordinator.invalidateAndReleaseWriter()
            reopened = try await CheckpointReopenedAuthority.start(
                testCase: self, support: fixture.support, defaults: fixture.defaults)
            let cold = try XCTUnwrap(reopened)
            let coldAccess = try XCTUnwrap(cold.presentation.myDayAccess)
            let coldWriter = cold.coordinator.workspaceWriter
            XCTAssertNotEqual(try coldWriter.currentRevision().writerInstanceID, revision.writerInstanceID)
            XCTAssertEqual(try coldWriter.reviewedFieldDraftResolutionEvidence(
                mutationID: original.original.mutation.mutationID), original)
            XCTAssertEqual(try coldAccess.discardedPlanningAcknowledgement(expectedCheckpoint: outcome.checkpoint), outcome)
            XCTAssertEqual(try coldWriter.commitFieldDraft(original.original.mutation), original.original.receipt)
            XCTAssertEqual(try coldWriter.currentPlan(for: request.confirmedContext.key), targetBefore)
            XCTAssertEqual(try coldWriter.currentRevision().revision, revision.revision)
            XCTAssertEqual(try editingOriginRowCounts(in: cold.coordinator.modelContext), rows)
            XCTAssertEqual(try rowCount(DraftDiscardReceiptRow.self, cold), 1)
            XCTAssertFalse(cold.coordinator.modelContext.hasChanges)
        }
    }

    #if DEBUG
    @MainActor
    func testReviewedResolutionPendingDiscardRemainsUnreadableUntilActualTerminalRetry() async throws {
        let fixture = try await makeFixture("reviewed-discard-pending")
        defer { fixture.cleanUp() }
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let writer = fixture.coordinator.workspaceWriter
        let original = try seedReviewedDiscardResolution(in: fixture.coordinator, existingTarget: false)
        let write = try access.preparePlanningDiscard(expectedCheckpoint: original.resolution.successorCheckpoint)
        var interrupted = false
        access.setPlanningEffectHookForTesting { point in
            guard point == .discardPendingCheckpoint, !interrupted else { return }
            interrupted = true
            throw CheckpointTestFailure.interrupted
        }
        do {
            _ = try await access.discardPlanningDraft(write)
            XCTFail("Expected actual durable pending interruption")
        } catch { XCTAssertEqual(error as? CheckpointTestFailure, .interrupted) }
        access.setPlanningEffectHookForTesting(nil)
        XCTAssertTrue(interrupted)
        XCTAssertEqual(try access.loadPlanningCheckpoint(draftID: write.pendingCheckpoint.draftID), write.pendingCheckpoint)
        XCTAssertEqual(try rowCount(DraftDiscardReceiptRow.self, fixture), 0)
        let revision = try writer.currentRevision()
        let rows = try editingOriginRowCounts(in: fixture.coordinator.modelContext)
        XCTAssertThrowsError(try writer.reviewedFieldDraftResolutionEvidence(
            mutationID: original.original.mutation.mutationID))
        XCTAssertEqual(try writer.currentRevision(), revision)
        XCTAssertEqual(try editingOriginRowCounts(in: fixture.coordinator.modelContext), rows)
        let completed = try await access.discardPlanningDraft(write)
        XCTAssertEqual(completed.checkpoint.state, .discarded)
        XCTAssertEqual(try writer.reviewedFieldDraftResolutionEvidence(
            mutationID: original.original.mutation.mutationID), original)
        XCTAssertFalse(fixture.coordinator.modelContext.hasChanges)
    }
    #endif

    @MainActor
    func testReviewedResolutionDiscardRejectsMissingExtraOrSubstitutedPhysicalReceiptWithoutWrites() async throws {
        for corruption in 0..<3 {
            let fixture = try await makeFixture("reviewed-discard-corrupt-\(corruption)")
            defer { fixture.cleanUp() }
            let access = try XCTUnwrap(fixture.presentation.myDayAccess)
            let writer = fixture.coordinator.workspaceWriter
            let context = fixture.coordinator.modelContext
            let original = try seedReviewedDiscardResolution(in: fixture.coordinator, existingTarget: false)
            let write = try access.preparePlanningDiscard(expectedCheckpoint: original.resolution.successorCheckpoint)
            let outcome = try await access.discardPlanningDraft(write)
            XCTAssertEqual(try writer.reviewedFieldDraftResolutionEvidence(
                mutationID: original.original.mutation.mutationID), original)
            let row = try XCTUnwrap(context.fetch(FetchDescriptor<DraftDiscardReceiptRow>()).first)
            let receipt = outcome.draftReceipt
            if corruption != 1 { context.delete(row) }
            if corruption != 0 {
                context.insert(try DraftDiscardReceiptRow(DraftDiscardReceiptV1(
                    receiptID: UUID(), workspaceID: receipt.workspaceID, draftID: receipt.draftID,
                    planSHA256: corruption == 2 ? String(repeating: "a", count: 64) : receipt.planSHA256,
                    disposedStageIDs: [], quarantinedReservationIDs: [], discardedAt: receipt.discardedAt,
                    mutationID: .init(rawValue: UUID()))))
            }
            try context.save()
            let revision = try writer.currentRevision()
            let rows = try editingOriginRowCounts(in: context)
            let discardRows = try rowCount(DraftDiscardReceiptRow.self, fixture)
            XCTAssertThrowsError(try writer.reviewedFieldDraftResolutionEvidence(
                mutationID: original.original.mutation.mutationID))
            XCTAssertEqual(try writer.currentRevision(), revision)
            XCTAssertEqual(try editingOriginRowCounts(in: context), rows)
            XCTAssertEqual(try rowCount(DraftDiscardReceiptRow.self, fixture), discardRows)
            XCTAssertFalse(context.hasChanges)
        }
    }

    @MainActor
    private func seedReviewedDiscardResolution(in coordinator: StoreSessionCoordinator,
                                               existingTarget: Bool) throws -> ReviewedFieldDraftResolutionEvidenceV1 {
        let instant = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        let fixture = try ReviewedResolutionTestFixtureV1(workspaceID: coordinator.workspaceID, now: instant)
        let writer = coordinator.workspaceWriter
        _ = try writer.commitFieldDraft(fixture.ordinary(fixture.initial))
        if existingTarget {
            _ = try writer.commit(MyDayCommandV1.save(successor: fixture.target, predecessor: nil))
        }
        _ = try writer.commitFieldDraft(fixture.ordinary(fixture.conflicted))
        let mutation = try fixture.resolution(target: existingTarget ? fixture.target : nil,
            workspaceRevision: writer.currentRevision().revision)
        _ = try writer.commitFieldDraft(mutation)
        return try XCTUnwrap(writer.reviewedFieldDraftResolutionEvidence(mutationID: mutation.mutationID))
    }
}

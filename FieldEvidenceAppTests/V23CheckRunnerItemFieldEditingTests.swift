import Foundation
import SwiftData
import XCTest

@testable import FieldEvidenceApp

@MainActor
final class V23CheckRunnerItemFieldEditingTests: XCTestCase {
    // Default-off observations for the two unresolved methods in original35942432840.
    private var fieldTiming: RestoreReviewTimingV1?

    func testFieldEditsPersistIncompleteValuesAndColdReopenWithoutEffects() async throws {
        let entries: [CheckRunnerRequestedEntryV1] = [.check, .recheck(issueID: beginPreparationUUID(49_001))]
        for (offset, entry) in entries.enumerated() {
            try await withAsyncFrozenBeginFixture("field-cold-\(offset)", entry: entry,
                                                 storedTimeZoneID: "America/New_York") { h in
                let service = try self.service(h)
                let created = try service.create(source: h.captureSource(), preflight: .init())
                let initial = try service.readEditableFields(draftID: created.draftID)
                let editor = try CheckRunnerItemEditingSessionV1(service: service, initialRead: initial,
                    clock: FieldEditingClock(), validateIntent: {})
                let original = try h.snapshot()
                var last = initial
                for anchor in CheckRunnerItemSemanticAnchorV1.allCases {
                    let raw = "  e\u{301}\n\u{0001}  " + String(repeating: "unfinished ", count: 80)
                    let desired = CheckRunnerEditableItemValuesV1(
                        preflight: .init(timeZoneID: "  unfinished zone  "),
                        outcome: .init(couldNotVerifyNote: raw, recheckNote: ""), semanticAnchor: anchor)
                    try editor.replaceEditableValues(desired)
                    let proof = try await editor.forceFlushAndReadBack(reason: .back)
                    try editor.validateForPublication(proof)
                    XCTAssertEqual(Array(proof.parent.values.outcome.couldNotVerifyNote.utf8), Array(raw.utf8))
                    XCTAssertEqual(proof.parent.values, desired)
                    last = proof.parent
                }
                let beforeNoOp = try h.snapshot(), ids = h.ids.callCount
                _ = try await editor.forceFlushAndReadBack(reason: .share)
                XCTAssertEqual(try h.snapshot(), beforeNoOp)
                XCTAssertEqual(h.ids.callCount, ids)
                let after = try h.snapshot()
                XCTAssertEqual(after.rows.workflows, original.rows.workflows)
                XCTAssertEqual(after.rows.sites, original.rows.sites)
                XCTAssertEqual(after.rows.assets, original.rows.assets)
                XCTAssertEqual(after.rows.issues, original.rows.issues)
                XCTAssertEqual(after.rows.roundBytes, original.rows.roundBytes)
                XCTAssertEqual(after.rows.packageBytes, original.rows.packageBytes)

                let oversized = self.changed(last.values, note: String(repeating: "x", count: 2_097_153))
                try editor.replaceEditableValues(oversized)
                do { _ = try await editor.forceFlushAndReadBack(reason: .leave); XCTFail("Payload bound") }
                catch { XCTAssertEqual(error as? FieldDraftFailureV1, .limitExceeded) }
                XCTAssertEqual(editor.values, oversized)
                XCTAssertTrue(editor.hasUnacknowledgedEdits)
                XCTAssertEqual(try h.snapshot(), after)
                try editor.replaceEditableValues(last.values)
                _ = try await editor.forceFlushAndReadBack(reason: .back)

                await editor.retire()
                try h.closeCoordinator()
                let reopenedSession = try h.factory.openOrBootstrapCurrent()
                let reopened = try StoreSessionCoordinator(validatingSession: reopenedSession,
                    clock: h.clock, idSource: h.ids,
                    lifecycleProfileRegistry: h.coordinator.lifecycleProfileRegistry)
                defer { XCTAssertNoThrow(try reopened.invalidateAndReleaseWriter()) }
                let gate = AppAccessGateV1(setting: .absentDisabled,
                    authentication: FrozenBeginAuthentication(), clock: h.clock, identifiers: h.ids)
                let transitions = try reopened.makeRoundSessionTransitionService(accessGate: gate)
                let progress = try reopened.makeRepetitiveCaptureProgressService(transitions: transitions)
                let runner = try CheckRunnerCoordinator(modelContext: reopenedSession.modelContext,
                    packageLifecycleDependencies: reopened.packageLifecycleDependencies(
                        profileRegistry: reopened.lifecycleProfileRegistry), packageLifecycleProfile: h.profile)
                let cold = try ProductionCheckRunnerItemDraftServiceV1(session: reopened, progress: progress,
                    coordinator: runner, publishedRelease: h.publishedRelease, clock: h.clock, ids: h.ids)
                let revision = try reopened.workspaceWriter.currentRevision()
                let read = try cold.readEditableFields(draftID: created.draftID)
                XCTAssertEqual(read.checkpoint, last.checkpoint)
                XCTAssertEqual(read.receipt, last.receipt)
                XCTAssertEqual(read.values, last.values)
                XCTAssertEqual(try reopened.workspaceWriter.currentRevision(), revision)
                XCTAssertThrowsError(try service.validateForPublication(read))
            }
        }
    }

    func testFieldEditCASPreservesBeginAndPhotoSlotsAndRejectsFrozenOrForeignState() async throws {
        fieldTiming = RestoreReviewTimingV1(enabled: true)
        fieldTiming?.mark("field-cas.enter")
        defer { fieldTiming?.mark("field-cas.exit"); fieldTiming = nil }
        try await withAsyncFrozenBeginFixture("field-photo", entry: .check,
            storedTimeZoneID: "America/New_York",
            diagnosticPhase: { self.fieldTiming?.mark("field-photo.\($0)") }) { h in
            self.fieldTiming?.mark("field-photo.media.begin")
            let photo = try await h.persistCurrentPhotoApplicationFixture()
            self.fieldTiming?.mark("field-photo.media.end")
            let service = photo.service
            let read = try service.readEditableFields(draftID: photo.value.parentCheckpoint.draftID)
            // Photo adoption freezes a later time than the fixture's initial clock.
            h.clock.value = max(h.clock.value, read.checkpoint.updatedAt).addingTimeInterval(1)
            let old = try CheckRunnerItemDraftCodecV1.validateCheckpoint(read.checkpoint)
            let before = try h.snapshot()
            let desired = self.changed(read.values, note: "  Incomplete observation \n")
            let attempt = try XCTUnwrap(service.prepareFieldEdit(draftID: read.checkpoint.draftID,
                expectedCheckpointSHA256: read.checkpoint.checkpointSHA256,
                values: desired, validateIntent: {}))
            let foreign = try self.service(h)
            XCTAssertThrowsError(try foreign.persistFieldEdit(attempt, validateIntent: {}))
            XCTAssertEqual(try h.snapshot(), before)
            let saved = try service.persistFieldEdit(attempt, validateIntent: {})
            let payload = try CheckRunnerItemDraftCodecV1.validateCheckpoint(saved.checkpoint)
            XCTAssertEqual(payload.source, old.source)
            XCTAssertEqual(payload.field.begin, old.field.begin)
            XCTAssertEqual(payload.field.wideContext, old.field.wideContext)
            XCTAssertEqual(payload.field.closeDetail, old.field.closeDetail)
            XCTAssertEqual(saved.values, desired)
            XCTAssertTrue(saved.checkpoint.stageIDs.isEmpty)
            let after = try h.snapshot(), ids = h.ids.callCount
            XCTAssertEqual(after.rows.workflows, before.rows.workflows)
            XCTAssertThrowsError(try service.prepareFieldEdit(draftID: read.checkpoint.draftID,
                expectedCheckpointSHA256: read.checkpoint.checkpointSHA256,
                values: desired, validateIntent: {}))
            let forbidden = CheckRunnerEditableItemValuesV1(preflight: .init(timeZoneID: "UTC"),
                outcome: desired.outcome, semanticAnchor: desired.semanticAnchor)
            XCTAssertThrowsError(try service.prepareFieldEdit(draftID: saved.checkpoint.draftID,
                expectedCheckpointSHA256: saved.checkpoint.checkpointSHA256,
                values: forbidden, validateIntent: {}))
            let oldOutcome = desired.outcome
            let changedMode = CheckRunnerEditableOutcomeV1(selection: oldOutcome.selection,
                choice: oldOutcome.choice,
                selectedCouldNotVerifyReasonKey: oldOutcome.selectedCouldNotVerifyReasonKey,
                couldNotVerifyNote: oldOutcome.couldNotVerifyNote, recheckNote: oldOutcome.recheckNote,
                startsWithCouldNotVerify: !oldOutcome.startsWithCouldNotVerify)
            XCTAssertThrowsError(try service.prepareFieldEdit(draftID: saved.checkpoint.draftID,
                expectedCheckpointSHA256: saved.checkpoint.checkpointSHA256,
                values: .init(preflight: desired.preflight, outcome: changedMode,
                              semanticAnchor: desired.semanticAnchor), validateIntent: {})) {
                XCTAssertEqual($0 as? FieldDraftFailureV1, .invalidTransition)
            }
            XCTAssertEqual(try h.snapshot(), after)
            XCTAssertEqual(h.ids.callCount, ids)
        }
        fieldTiming?.mark("field-prepared.begin")
        try withFrozenBeginFixture("field-prepared", entry: .check,
                                   storedTimeZoneID: "America/New_York") { h in
            let service = try self.service(h)
            let created = try service.create(source: h.captureSource(),
                preflight: .init(afterDarkAccepted: true, safePositionAccepted: true))
            let prepared = try service.prepareBegin(draftID: created.draftID,
                expectedCheckpointSHA256: created.checkpointSHA256,
                observedAtUTC: XCTUnwrap(h.validSubmission().observedAtUTC))
            let payload = try CheckRunnerItemDraftCodecV1.validateCheckpoint(prepared)
            let before = try h.snapshot(), ids = h.ids.callCount
            XCTAssertThrowsError(try service.prepareFieldEdit(draftID: prepared.draftID,
                expectedCheckpointSHA256: prepared.checkpointSHA256,
                values: .init(preflight: payload.field.preflight, outcome: payload.field.outcome,
                              semanticAnchor: .outcome), validateIntent: {}))
            XCTAssertEqual(try h.snapshot(), before)
            XCTAssertEqual(h.ids.callCount, ids)
        }
        fieldTiming?.mark("field-prepared.end")
        for variant in 0..<3 {
            try await withAsyncFrozenBeginFixture("field-pending-photo-\(variant)", entry: .check,
                storedTimeZoneID: "America/Chicago",
                diagnosticPhase: { self.fieldTiming?.mark("field-pending-photo-\(variant).\($0)") }) { h in
                self.fieldTiming?.mark("field-pending-photo-\(variant).media.begin")
                let photo = try await FrozenProductionPhotoV1.make(h, publishRaw: variant != 0)
                if variant == 2 {
                    _ = try await photo.service.preparePhotoPair(parentDraftID: photo.parentID,
                                                                 childDraftID: photo.childID)
                }
                self.fieldTiming?.mark("field-pending-photo-\(variant).media.end")
                let childBefore = try photo.checkpoint()
                let childPayload = try CheckRunnerPhotoDraftCodecV1.validateCheckpoint(childBefore)
                switch (variant, childPayload.phase) {
                case (0, .awaitingRawStage), (1, .rawReady), (2, .pairReady): break
                default: XCTFail("Expected the actual requested pending-photo phase")
                }
                let read = try photo.service.readEditableFields(draftID: photo.parentID)
                h.clock.value = max(read.checkpoint.updatedAt, childBefore.updatedAt).addingTimeInterval(1)
                let parentBefore = try CheckRunnerItemDraftCodecV1.validateCheckpoint(read.checkpoint)
                let before = try h.snapshot()
                let desired = self.changed(read.values, note: "  pending photo \(variant)  ")
                let attempt = try XCTUnwrap(photo.service.prepareFieldEdit(draftID: photo.parentID,
                    expectedCheckpointSHA256: read.checkpoint.checkpointSHA256,
                    values: desired, validateIntent: {}))
                let saved = try photo.service.persistFieldEdit(attempt, validateIntent: {})
                let parentAfter = try CheckRunnerItemDraftCodecV1.validateCheckpoint(saved.checkpoint)
                XCTAssertEqual(parentAfter.source, parentBefore.source)
                XCTAssertEqual(parentAfter.field.begin, parentBefore.field.begin)
                XCTAssertEqual(parentAfter.field.wideContext, parentBefore.field.wideContext)
                XCTAssertEqual(parentAfter.field.closeDetail, parentBefore.field.closeDetail)
                XCTAssertEqual(parentAfter.field.wideContext?.childDraftID, photo.childID)
                XCTAssertEqual(saved.values, desired)
                XCTAssertEqual(try photo.checkpoint(), childBefore)
                let after = try h.snapshot()
                XCTAssertEqual(after.revision.revision, before.revision.revision + 1)
                XCTAssertEqual(after.rows.workflows, before.rows.workflows)
                XCTAssertEqual(after.rows.roundBytes, before.rows.roundBytes)
                if variant == 2 {
                    let commit = try photo.attempt(pairCheckpoint: childBefore)
                    _ = try photo.service.preparePhotoCommit(parentDraftID: photo.parentID,
                        childDraftID: photo.childID, expectedCheckpointSHA256: childBefore.checkpointSHA256,
                        proposal: commit)
                    let beforeDenied = try h.snapshot(), idCalls = h.ids.callCount
                    XCTAssertThrowsError(try photo.service.prepareFieldEdit(draftID: photo.parentID,
                        expectedCheckpointSHA256: saved.checkpoint.checkpointSHA256,
                        values: self.changed(saved.values, note: "must first recover photo"), validateIntent: {})) {
                        XCTAssertEqual($0 as? FieldDraftFailureV1, .invalidTransition)
                    }
                    XCTAssertEqual(try h.snapshot(), beforeDenied)
                    XCTAssertEqual(h.ids.callCount, idCalls)
                }
            }
        }
        try await withAsyncFrozenBeginFixture("field-finalization-denials", entry: .check,
            storedTimeZoneID: "America/Chicago",
            diagnosticPhase: { self.fieldTiming?.mark("field-finalization-denials.\($0)") }) { h in
            self.fieldTiming?.mark("field-finalization-denials.draft.begin")
            let draft = try await makeFrozenParentFinalizationDraft(h,
                selection: .couldNotVerify(reasonKey: "conditions_changed", note: nil), photoCount: 0)
            self.fieldTiming?.mark("field-finalization-denials.draft.end")
            let editing = try draft.service.readEditableFields(draftID: draft.checkpoint.draftID)
            self.fieldTiming?.mark("field-finalization-denials.prepare.begin")
            let prepared = try await draft.service.prepareFinalization(draftID: draft.checkpoint.draftID,
                expectedCheckpointSHA256: draft.checkpoint.checkpointSHA256,
                sourceApp: SourceAppSnapshotV1(build: "field-edit-denials", version: "1.0")) {}
            self.fieldTiming?.mark("field-finalization-denials.prepare.end")
            let preparedSnapshot = try h.snapshot(), preparedIDs = h.ids.callCount
            XCTAssertEqual(prepared.state, .committing)
            XCTAssertThrowsError(try draft.service.readEditableFields(draftID: prepared.draftID)) {
                XCTAssertEqual($0 as? FieldDraftFailureV1, .invalidTransition)
            }
            XCTAssertThrowsError(try draft.service.prepareFieldEdit(draftID: prepared.draftID,
                expectedCheckpointSHA256: prepared.checkpointSHA256,
                values: self.changed(editing.values, note: "after prepared finalization"), validateIntent: {})) {
                XCTAssertEqual($0 as? FieldDraftFailureV1, .invalidTransition)
            }
            XCTAssertEqual(try h.snapshot(), preparedSnapshot)
            XCTAssertEqual(h.ids.callCount, preparedIDs)
            self.fieldTiming?.mark("field-finalization-denials.resume.begin")
            let terminal = try await draft.service.resumeFinalization(draftID: prepared.draftID) {}
            self.fieldTiming?.mark("field-finalization-denials.resume.end")
            let terminalSnapshot = try h.snapshot(), terminalIDs = h.ids.callCount
            XCTAssertEqual(terminal.state, .committed)
            XCTAssertThrowsError(try draft.service.readEditableFields(draftID: terminal.draftID)) {
                XCTAssertEqual($0 as? FieldDraftFailureV1, .invalidTransition)
            }
            XCTAssertThrowsError(try draft.service.prepareFieldEdit(draftID: terminal.draftID,
                expectedCheckpointSHA256: terminal.checkpointSHA256,
                values: self.changed(editing.values, note: "after terminal finalization"), validateIntent: {})) {
                XCTAssertEqual($0 as? FieldDraftFailureV1, .invalidTransition)
            }
            XCTAssertEqual(try h.snapshot(), terminalSnapshot)
            XCTAssertEqual(h.ids.callCount, terminalIDs)
        }
    }

    func testFieldEditAcknowledgementLossRecoversOriginalBeforeNewerEdits() async throws {
        try await withAsyncFrozenBeginFixture("field-ack", entry: .check,
                                             storedTimeZoneID: "America/New_York") { h in
            let service = try self.service(h)
            let created = try service.create(source: h.captureSource(), preflight: .init())
            let initial = try service.readEditableFields(draftID: created.draftID)
            let editor = try CheckRunnerItemEditingSessionV1(service: service, initialRead: initial,
                clock: FieldEditingClock(), validateIntent: {})
            let first = self.changed(initial.values, note: "first unacknowledged bytes")
            try editor.replaceEditableValues(first)
            service.beforeFieldEditAcknowledgementForTesting = { throw FieldEditingInjectedFailure.lostAcknowledgement }
            do {
                _ = try await editor.forceFlushAndReadBack(reason: .leave)
                XCTFail("Expected loss after the actual CAS")
            } catch { XCTAssertEqual(error as? FieldEditingInjectedFailure, .lostAcknowledgement) }
            XCTAssertTrue(editor.hasUnacknowledgedEdits)
            let savedOriginal = try service.readEditableFields(draftID: created.draftID)
            XCTAssertEqual(savedOriginal.values, first)
            XCTAssertEqual(savedOriginal.checkpoint.draftRevision, created.draftRevision + 1)
            let afterOriginal = try h.snapshot(), idCalls = h.ids.callCount
            var acknowledgements: [CheckRunnerFieldReadbackV1] = []
            editor.afterAcknowledgementReadyForTesting = { read in acknowledgements.append(read) }
            let second = self.changed(first, note: "newer pending bytes")
            try editor.replaceEditableValues(second)
            service.beforeFieldEditAcknowledgementForTesting = nil
            let proof = try await editor.forceFlushAndReadBack(reason: .leave)
            XCTAssertEqual(acknowledgements.map { $0.checkpoint.draftRevision },
                           [created.draftRevision + 1, created.draftRevision + 2])
            XCTAssertEqual(acknowledgements.first?.receipt, savedOriginal.receipt)
            XCTAssertEqual(proof.parent.values, second)
            XCTAssertEqual(try h.snapshot().revision.revision, afterOriginal.revision.revision + 1)
            XCTAssertEqual(h.ids.callCount, idCalls + 1)
            XCTAssertFalse(editor.hasUnacknowledgedEdits)
            try editor.validateForPublication(proof)
            await editor.retire()
        }
        try withFrozenBeginFixture("field-competing-tip", entry: .check,
                                   storedTimeZoneID: "America/New_York") { h in
            let firstOwner = try self.service(h)
            let created = try firstOwner.create(source: h.captureSource(), preflight: .init())
            let initial = try firstOwner.readEditableFields(draftID: created.draftID)
            let originalAttempt = try XCTUnwrap(firstOwner.prepareFieldEdit(draftID: created.draftID,
                expectedCheckpointSHA256: created.checkpointSHA256,
                values: self.changed(initial.values, note: "original uncertain acknowledgement"), validateIntent: {}))
            firstOwner.beforeFieldEditAcknowledgementForTesting = {
                throw FieldEditingInjectedFailure.lostAcknowledgement
            }
            XCTAssertThrowsError(try firstOwner.persistFieldEdit(originalAttempt, validateIntent: {})) {
                XCTAssertEqual($0 as? FieldEditingInjectedFailure, .lostAcknowledgement)
            }
            let original = try firstOwner.readEditableFields(draftID: created.draftID)
            let secondOwner = try self.service(h)
            let competingAttempt = try XCTUnwrap(secondOwner.prepareFieldEdit(draftID: created.draftID,
                expectedCheckpointSHA256: original.checkpoint.checkpointSHA256,
                values: self.changed(original.values, note: "other editor saved later"), validateIntent: {}))
            let competing = try secondOwner.persistFieldEdit(competingAttempt, validateIntent: {})
            XCTAssertEqual(competing.checkpoint.draftRevision, original.checkpoint.draftRevision + 1)
            let beforeDenied = try h.snapshot(), ids = h.ids.callCount
            firstOwner.beforeFieldEditAcknowledgementForTesting = nil
            XCTAssertThrowsError(try firstOwner.persistFieldEdit(originalAttempt, validateIntent: {})) {
                XCTAssertEqual($0 as? FieldDraftFailureV1, .staleDraftRevision)
            }
            XCTAssertThrowsError(try firstOwner.prepareFieldEdit(draftID: created.draftID,
                expectedCheckpointSHA256: competing.checkpoint.checkpointSHA256,
                values: self.changed(competing.values, note: "must not overwrite other editor"), validateIntent: {})) {
                XCTAssertEqual($0 as? FieldDraftFailureV1, .staleDraftRevision)
            }
            let retained = try XCTUnwrap(h.coordinator.workspaceWriter.fieldDraftEvidence(
                mutationID: original.checkpoint.mutationID))
            XCTAssertEqual(retained.receipt, original.receipt)
            XCTAssertEqual(try secondOwner.readEditableFields(draftID: created.draftID).checkpoint,
                           competing.checkpoint)
            XCTAssertEqual(try h.snapshot(), beforeDenied)
            XCTAssertEqual(h.ids.callCount, ids)
        }
    }

    func testFieldAutosaveUsesTrailingMaximumAndRetainsFailedAttempt() async throws {
        fieldTiming = RestoreReviewTimingV1(enabled: true)
        fieldTiming?.mark("field-autosave.enter")
        defer { fieldTiming?.mark("field-autosave.exit"); fieldTiming = nil }
        try await withAsyncFrozenBeginFixture("field-clock", entry: .check,
            storedTimeZoneID: "America/New_York",
            diagnosticPhase: { self.fieldTiming?.mark("field-clock.\($0)") }) { h in
            let service = try self.service(h)
            let created = try service.create(source: h.captureSource(), preflight: .init())
            let initial = try service.readEditableFields(draftID: created.draftID)
            let clock = FieldEditingClock()
            let editor = try CheckRunnerItemEditingSessionV1(service: service, initialRead: initial,
                clock: clock, validateIntent: {})
            try editor.replaceEditableValues(self.changed(initial.values, note: "trailing"))
            try await self.waitUntil { await clock.deadlines().contains(750_000_000) }
            await clock.advance(to: 749_999_999)
            XCTAssertEqual(try service.read(draftID: created.draftID), created)
            await clock.advance(to: 750_000_000)
            try await self.waitUntil { !editor.hasUnacknowledgedEdits }
            XCTAssertEqual(try service.readEditableFields(draftID: created.draftID).values.outcome.recheckNote,
                           "trailing")
            _ = try await editor.forceFlushAndReadBack(reason: .back)
            let firstSaved = editor.acknowledgement.checkpoint
            // Keep moving the trailing deadline without exceeding maximum dirty.
            for step in 0..<10 {
                let time = UInt64(1_000_000_000 + step * 500_000_000)
                await clock.advance(to: time)
                try editor.replaceEditableValues(self.changed(editor.values, note: "continuous \(step)"))
                let deadline = min(time + 750_000_000, 6_000_000_000)
                try await self.waitUntil { await clock.deadlines().contains(deadline) }
                XCTAssertEqual(try service.read(draftID: created.draftID), firstSaved)
            }
            await clock.advance(to: 6_000_000_000)
            try await self.waitUntil { !editor.hasUnacknowledgedEdits }
            XCTAssertEqual(try service.readEditableFields(draftID: created.draftID).values.outcome.recheckNote,
                           "continuous 9")
            service.beforeFieldEditAcknowledgementForTesting = { throw FieldEditingInjectedFailure.lostAcknowledgement }
            self.fieldTiming?.mark("field-clock.injected-acknowledgement-loss")
            try editor.replaceEditableValues(self.changed(editor.values, note: "failed automatic acknowledgement"))
            try await self.waitUntil { await clock.deadlines().contains(6_750_000_000) }
            await clock.advance(to: 6_750_000_000)
            try await self.waitUntil { editor.durabilityState == .saveBlocked }
            XCTAssertTrue(editor.hasUnacknowledgedEdits)
            let saved = try service.readEditableFields(draftID: created.draftID)
            let revision = try h.coordinator.workspaceWriter.currentRevision()
            service.beforeFieldEditAcknowledgementForTesting = nil
            self.fieldTiming?.mark("field-clock.explicit-recovery.begin")
            let proof = try await editor.forceFlushAndReadBack(reason: .back)
            self.fieldTiming?.mark("field-clock.explicit-recovery.end")
            XCTAssertEqual(proof.parent.receipt, saved.receipt)
            XCTAssertEqual(try h.coordinator.workspaceWriter.currentRevision(), revision)
            await editor.retire()
        }
        try await withAsyncFrozenBeginFixture("field-automatic-exhaustion", entry: .check,
            storedTimeZoneID: "America/New_York",
            diagnosticPhase: { self.fieldTiming?.mark("field-automatic-exhaustion.\($0)") }) { h in
            let service = try self.service(h)
            let created = try service.create(source: h.captureSource(), preflight: .init())
            let initial = try service.readEditableFields(draftID: created.draftID)
            let clock = FieldEditingClock()
            let editor = try CheckRunnerItemEditingSessionV1(service: service, initialRead: initial,
                clock: clock, validateIntent: {})
            var attemptedReceipts: [MutationReceiptV1] = []
            editor.afterAcknowledgementReadyForTesting = { read in
                attemptedReceipts.append(read.receipt)
                throw FieldEditingInjectedFailure.lostAcknowledgement
            }
            let desired = self.changed(initial.values, note: "saved once; acknowledgement keeps failing")
            let before = try h.snapshot(), idsBefore = h.ids.callCount
            try editor.replaceEditableValues(desired)
            for attemptNumber in 1...4 {
                self.fieldTiming?.mark("field-automatic-exhaustion.attempt-\(attemptNumber).begin")
                let deadline = UInt64(attemptNumber) * 750_000_000
                try await self.waitUntil { await clock.deadlines().contains(deadline) }
                await clock.advance(to: deadline)
                try await self.waitUntil {
                    let failure = await editor.autosaveFailureStateForTesting()
                    return failure?.attempt == attemptNumber && editor.durabilityState == .saveBlocked
                }
                XCTAssertEqual(attemptedReceipts.count, attemptNumber)
                let saved = try service.readEditableFields(draftID: created.draftID)
                XCTAssertEqual(saved.values, desired)
                XCTAssertEqual(saved.checkpoint.draftRevision, created.draftRevision + 1)
                XCTAssertEqual(try h.snapshot().revision.revision, before.revision.revision + 1)
                XCTAssertEqual(h.ids.callCount, idsBefore + 1)
                XCTAssertTrue(attemptedReceipts.allSatisfy { $0 == saved.receipt })
                XCTAssertEqual(editor.acknowledgement.checkpoint, initial.checkpoint)
                XCTAssertTrue(editor.hasUnacknowledgedEdits)
                self.fieldTiming?.mark("field-automatic-exhaustion.attempt-\(attemptNumber).end")
            }
            let exhaustedState = await editor.autosaveFailureStateForTesting()
            let exhausted = try XCTUnwrap(exhaustedState)
            XCTAssertEqual(exhausted.attempt, 4)
            XCTAssertNil(exhausted.nextRetryNanoseconds)
            XCTAssertEqual(exhausted.firstDirtyNanoseconds, 0)
            let original = try service.readEditableFields(draftID: created.draftID)
            let savedSnapshot = try h.snapshot(), savedIDs = h.ids.callCount
            await clock.advance(to: 10_000_000_000)
            let stillExhausted = await editor.autosaveFailureStateForTesting()
            XCTAssertEqual(stillExhausted, exhausted)
            XCTAssertEqual(attemptedReceipts.count, 4)
            XCTAssertEqual(try h.snapshot(), savedSnapshot)
            XCTAssertEqual(h.ids.callCount, savedIDs)
            editor.afterAcknowledgementReadyForTesting = nil
            self.fieldTiming?.mark("field-automatic-exhaustion.explicit-recovery.begin")
            let recovered = try await editor.forceFlushAndReadBack(reason: .leave)
            self.fieldTiming?.mark("field-automatic-exhaustion.explicit-recovery.end")
            XCTAssertEqual(recovered.parent.receipt, original.receipt)
            XCTAssertEqual(recovered.parent.checkpoint, original.checkpoint)
            XCTAssertEqual(recovered.parent.values, desired)
            XCTAssertEqual(try h.snapshot(), savedSnapshot)
            XCTAssertEqual(h.ids.callCount, savedIDs)
            XCTAssertFalse(editor.hasUnacknowledgedEdits)
            try editor.validateForPublication(recovered)
            await editor.retire()
        }
        try await withAsyncFrozenBeginFixture("field-before-save", entry: .check,
            storedTimeZoneID: "America/New_York",
            diagnosticPhase: { self.fieldTiming?.mark("field-before-save.\($0)") }) { h in
            let originalService = try self.service(h)
            let created = try originalService.create(source: h.captureSource(), preflight: .init())
            try h.closeCoordinator()
            let reopenedSession = try h.factory.openOrBootstrapCurrent()
            let reopened = try StoreSessionCoordinator(validatingSessionForTesting: reopenedSession,
                clock: h.clock, idSource: h.ids,
                lifecycleProfileRegistry: h.coordinator.lifecycleProfileRegistry,
                mutationJournalFailureInjection: .init(failOnceAt: .afterReceiptBeforeSave))
            defer { XCTAssertNoThrow(try reopened.invalidateAndReleaseWriter()) }
            let gate = AppAccessGateV1(setting: .absentDisabled,
                authentication: FrozenBeginAuthentication(), clock: h.clock, identifiers: h.ids)
            let transitions = try reopened.makeRoundSessionTransitionService(accessGate: gate)
            let progress = try reopened.makeRepetitiveCaptureProgressService(transitions: transitions)
            let runner = try CheckRunnerCoordinator(modelContext: reopenedSession.modelContext,
                packageLifecycleDependencies: reopened.packageLifecycleDependencies(
                    profileRegistry: reopened.lifecycleProfileRegistry), packageLifecycleProfile: h.profile)
            let service = try ProductionCheckRunnerItemDraftServiceV1(session: reopened, progress: progress,
                coordinator: runner, publishedRelease: h.publishedRelease, clock: h.clock, ids: h.ids)
            let initial = try service.readEditableFields(draftID: created.draftID)
            let editor = try CheckRunnerItemEditingSessionV1(service: service, initialRead: initial,
                clock: FieldEditingClock(), validateIntent: {})
            let context = reopened.modelContext
            let writer = reopened.workspaceWriter
            func checkpoints(in context: ModelContext) throws -> [FieldDraftCheckpointV1] {
                try context.fetch(FetchDescriptor<FieldDraftCheckpointRow>()).map { try $0.value() }
                    .sorted { $0.draftID.uuidString < $1.draftID.uuidString }
            }
            let beforeCheckpoints = try checkpoints(in: context)
            let beforeRevision = try writer.currentRevision()
            let beforeHistory = try writer.sourceMutationHistorySnapshot()
            let beforeReceiptCount = try context.fetchCount(FetchDescriptor<MutationReceiptRow>())
            let frozenMutationID = try MutationIDV1(rawValue: beginPreparationUUID(49_901))
            h.ids.enqueue([frozenMutationID.rawValue])
            let idCalls = h.ids.callCount
            h.clock.value = h.clock.millisecondValue.addingTimeInterval(1)
            let preparedAt = h.clock.millisecondValue
            let desired = self.changed(initial.values, note: "  incomplete before-save field\n")
            try editor.replaceEditableValues(desired)
            do {
                _ = try await editor.forceFlushAndReadBack(reason: .back)
                XCTFail("The real field checkpoint transaction must fail before save")
            } catch {
                XCTAssertEqual(error as? MutationJournalFailureV1, .injected(.afterReceiptBeforeSave))
            }
            XCTAssertEqual(editor.durabilityState, .saveBlocked)
            XCTAssertTrue(editor.hasUnacknowledgedEdits)
            XCTAssertEqual(editor.values, desired)
            XCTAssertEqual(editor.acknowledgement.checkpoint, initial.checkpoint)
            XCTAssertEqual(editor.acknowledgement.receipt, initial.receipt)
            XCTAssertEqual(h.ids.callCount, idCalls + 1)
            XCTAssertEqual(try service.readEditableFields(draftID: created.draftID).checkpoint, created)
            XCTAssertEqual(try checkpoints(in: context), beforeCheckpoints)
            XCTAssertEqual(try writer.currentRevision(), beforeRevision)
            XCTAssertEqual(try writer.sourceMutationHistorySnapshot(), beforeHistory)
            XCTAssertNil(try writer.fieldDraftEvidence(mutationID: frozenMutationID))
            XCTAssertNil(try writer.durableReceipt(mutationID: frozenMutationID))
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<MutationReceiptRow>()), beforeReceiptCount)
            XCTAssertFalse(context.hasChanges)
            // A fresh context must see the same durable predecessor after rollback.
            let durableContext = ModelContext(context.container)
            durableContext.autosaveEnabled = false
            XCTAssertEqual(try checkpoints(in: durableContext), beforeCheckpoints)
            XCTAssertEqual(try durableContext.fetchCount(FetchDescriptor<MutationReceiptRow>()), beforeReceiptCount)
            XCTAssertFalse(durableContext.hasChanges)

            // Advancing the application clock detects replacement of the frozen attempt.
            h.clock.value = preparedAt.addingTimeInterval(1)
            let recovered = try await editor.forceFlushAndReadBack(reason: .leave)
            XCTAssertEqual(recovered.parent.values, desired)
            XCTAssertEqual(recovered.parent.checkpoint.mutationID, frozenMutationID)
            XCTAssertEqual(recovered.parent.receipt.mutationID, frozenMutationID)
            XCTAssertEqual(recovered.parent.checkpoint.updatedAt, preparedAt)
            XCTAssertEqual(recovered.parent.checkpoint.draftRevision, created.draftRevision + 1)
            XCTAssertEqual(h.ids.callCount, idCalls + 1)
            let evidence = try XCTUnwrap(writer.fieldDraftEvidence(mutationID: frozenMutationID))
            guard case let .reviseCheckpoint(savedCheckpoint) = evidence.mutation.postImage else {
                await editor.retire()
                return XCTFail("Retry must commit the original field checkpoint revision")
            }
            XCTAssertEqual(savedCheckpoint, recovered.parent.checkpoint)
            XCTAssertEqual(evidence.receipt, recovered.parent.receipt)
            XCTAssertEqual(evidence.mutation.expectedRevision, created.draftRevision)
            let oldPayload = try CheckRunnerItemDraftCodecV1.validateCheckpoint(created)
            let savedPayload = try CheckRunnerItemDraftCodecV1.validateCheckpoint(savedCheckpoint)
            XCTAssertEqual(savedPayload.source, oldPayload.source)
            XCTAssertEqual(savedPayload.field.begin, oldPayload.field.begin)
            XCTAssertEqual(savedPayload.field.wideContext, oldPayload.field.wideContext)
            XCTAssertEqual(savedPayload.field.closeDetail, oldPayload.field.closeDetail)
            let savedRevision = try writer.currentRevision()
            let savedHistory = try writer.sourceMutationHistorySnapshot()
            XCTAssertEqual(savedRevision.revision, beforeRevision.revision + 1)
            XCTAssertEqual(savedHistory.receipts.count, beforeHistory.receipts.count + 1)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<MutationReceiptRow>()), beforeReceiptCount + 1)
            XCTAssertFalse(context.hasChanges)
            XCTAssertFalse(editor.hasUnacknowledgedEdits)
            try editor.validateForPublication(recovered)
            let replayed = try await editor.forceFlushAndReadBack(reason: .share)
            XCTAssertEqual(replayed.parent.checkpoint, recovered.parent.checkpoint)
            XCTAssertEqual(replayed.parent.receipt, recovered.parent.receipt)
            XCTAssertEqual(try writer.currentRevision(), savedRevision)
            XCTAssertEqual(try writer.sourceMutationHistorySnapshot(), savedHistory)
            XCTAssertEqual(h.ids.callCount, idCalls + 1)
            await editor.retire()
        }
    }

    func testFieldFlushDrainsEditsArrivingDuringAwaitAndAuthenticatesReadback() async throws {
        try await withAsyncFrozenBeginFixture("field-flight", entry: .check,
                                             storedTimeZoneID: "America/New_York") { h in
            let service = try self.service(h)
            let created = try service.create(source: h.captureSource(), preflight: .init())
            let initial = try service.readEditableFields(draftID: created.draftID)
            var intentAllowed = true
            let editor = try CheckRunnerItemEditingSessionV1(service: service, initialRead: initial,
                clock: FieldEditingClock(), validateIntent: {
                    guard intentAllowed else { throw FieldEditingInjectedFailure.revoked }
                })
            let barrier = FieldEditingBarrier()
            var suspended = false
            editor.afterAcknowledgementReadyForTesting = { _ in
                if !suspended { suspended = true; await barrier.wait() }
            }
            try editor.replaceEditableValues(self.changed(initial.values, note: "first"))
            let first = Task { @MainActor in try await editor.forceFlushAndReadBack(reason: .back) }
            try await self.waitUntil { suspended }
            try editor.replaceEditableValues(self.changed(editor.values, note: "second during await"))
            let second = Task { @MainActor in try await editor.forceFlushAndReadBack(reason: .camera) }
            await barrier.release()
            let firstProof = try await first.value
            let secondProof = try await second.value
            try editor.validateForPublication(firstProof)
            try editor.validateForPublication(secondProof)
            XCTAssertEqual(firstProof.parent.values.outcome.recheckNote, "second during await")
            XCTAssertEqual(firstProof.parent.receipt, secondProof.parent.receipt)
            XCTAssertEqual(firstProof.parent.checkpoint.draftRevision, created.draftRevision + 2)
            let anotherEditor = try CheckRunnerItemEditingSessionV1(service: service,
                initialRead: secondProof.parent, clock: FieldEditingClock(), validateIntent: {})
            XCTAssertThrowsError(try anotherEditor.validateForPublication(secondProof))
            try editor.replaceEditableValues(self.changed(editor.values, note: "still in RAM"))
            XCTAssertThrowsError(try editor.validateForPublication(secondProof))
            intentAllowed = false
            let beforeDenied = try h.snapshot()
            do { _ = try await editor.forceFlushAndReadBack(reason: .leave); XCTFail("Revoked intent") }
            catch { XCTAssertEqual(error as? FieldEditingInjectedFailure, .revoked) }
            XCTAssertEqual(try h.snapshot(), beforeDenied)
            XCTAssertTrue(editor.hasUnacknowledgedEdits)
            await editor.retire()
            await anotherEditor.retire()
        }
        for interruption in ["cancel", "retire", "revoke"] {
            try await withAsyncFrozenBeginFixture("field-readback-\(interruption)", entry: .check,
                                                 storedTimeZoneID: "America/New_York") { h in
                let service = try self.service(h)
                let created = try service.create(source: h.captureSource(), preflight: .init())
                let initial = try service.readEditableFields(draftID: created.draftID)
                var intentAllowed = true
                let editor = try CheckRunnerItemEditingSessionV1(service: service, initialRead: initial,
                    clock: FieldEditingClock(), validateIntent: {
                        guard intentAllowed else { throw FieldEditingInjectedFailure.revoked }
                    })
                let barrier = FieldEditingBarrier()
                var suspended = false
                editor.afterAcknowledgementReadyForTesting = { _ in
                    suspended = true
                    await barrier.wait()
                }
                let desired = self.changed(initial.values, note: "saved before \(interruption)")
                try editor.replaceEditableValues(desired)
                let flush = Task { @MainActor in try await editor.forceFlushAndReadBack(reason: .leave) }
                try await self.waitUntil { suspended }
                let durable = try service.readEditableFields(draftID: created.draftID)
                XCTAssertEqual(durable.values, desired)
                XCTAssertEqual(durable.checkpoint.draftRevision, created.draftRevision + 1)
                let savedSnapshot = try h.snapshot(), savedIDs = h.ids.callCount
                switch interruption {
                case "cancel": flush.cancel()
                case "retire": await editor.retire()
                default: intentAllowed = false
                }
                await barrier.release()
                do {
                    _ = try await flush.value
                    XCTFail("Interrupted caller must receive no usable flush proof")
                } catch {
                    switch interruption {
                    case "cancel": XCTAssertTrue(error is CancellationError)
                    case "retire": XCTAssertEqual(error as? CheckRunnerItemEditingSessionFailureV1, .retired)
                    default: XCTAssertEqual(error as? FieldEditingInjectedFailure, .revoked)
                    }
                }
                XCTAssertEqual(try service.readEditableFields(draftID: created.draftID).receipt, durable.receipt)
                XCTAssertEqual(try h.snapshot(), savedSnapshot)
                XCTAssertEqual(h.ids.callCount, savedIDs)
                if interruption != "cancel" {
                    XCTAssertEqual(editor.acknowledgement.checkpoint, initial.checkpoint)
                    XCTAssertTrue(editor.hasUnacknowledgedEdits)
                }
                if interruption == "retire" {
                    XCTAssertThrowsError(try editor.replaceEditableValues(
                        self.changed(editor.values, note: "retired editor cannot write"))) {
                        XCTAssertEqual($0 as? CheckRunnerItemEditingSessionFailureV1, .retired)
                    }
                    XCTAssertEqual(try h.snapshot(), savedSnapshot)
                }
                await editor.retire()
            }
        }
    }

    private func service(_ h: FrozenBeginFixture) throws -> ProductionCheckRunnerItemDraftServiceV1 {
        try .init(session: h.coordinator, progress: h.progress, coordinator: h.runner,
                  publishedRelease: h.publishedRelease, clock: h.clock, ids: h.ids)
    }

    private func changed(_ old: CheckRunnerEditableItemValuesV1, note: String) -> CheckRunnerEditableItemValuesV1 {
        var outcome = old.outcome
        outcome.recheckNote = note
        return .init(preflight: old.preflight, outcome: outcome, semanticAnchor: old.semanticAnchor)
    }

    private func waitUntil(line: UInt = #line,
                           _ predicate: @MainActor () async throws -> Bool) async throws {
        let deadline = ContinuousClock().now.advanced(by: .seconds(10))
        fieldTiming?.mark("field-wait.line-\(line).begin")
        do {
            while !(try await predicate()) {
                guard ContinuousClock().now < deadline else {
                    fieldTiming?.mark("field-wait.line-\(line).timeout")
                    XCTFail("Timed out waiting for the real editing/scheduler boundary")
                    throw FieldEditingInjectedFailure.timedOut
                }
                try await Task.sleep(nanoseconds: 1_000_000)
            }
        } catch {
            fieldTiming?.mark("field-wait.line-\(line).error-\(String(reflecting: error))")
            throw error
        }
        fieldTiming?.mark("field-wait.line-\(line).end")
    }
}

private enum FieldEditingInjectedFailure: Error, Equatable {
    case lostAcknowledgement, revoked, timedOut
}

private actor FieldEditingClock: DraftAutosaveClockV1 {
    private struct Waiter {
        let deadline: UInt64
        let continuation: CheckedContinuation<Void, Error>
    }
    private var now: UInt64 = 0
    private var waiters: [UUID: Waiter] = [:]
    func nowNanoseconds() async -> UInt64 { now }
    func sleep(untilNanoseconds deadline: UInt64) async throws {
        try Task.checkCancellation()
        guard deadline > now else { return }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()) }
                else if deadline <= now { continuation.resume() }
                else { waiters[id] = Waiter(deadline: deadline, continuation: continuation) }
            }
        } onCancel: { Task { await self.cancel(id) } }
    }
    func advance(to instant: UInt64) {
        precondition(instant >= now)
        now = instant
        for (id, waiter) in waiters.filter({ $0.value.deadline <= instant }) {
            waiters[id] = nil
            waiter.continuation.resume()
        }
    }
    func deadlines() -> [UInt64] { waiters.values.map(\.deadline).sorted() }
    private func cancel(_ id: UUID) {
        waiters.removeValue(forKey: id)?.continuation.resume(throwing: CancellationError())
    }
}

private actor FieldEditingBarrier {
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    func wait() async {
        guard !released else { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func release() { released = true; continuation?.resume(); continuation = nil }
}

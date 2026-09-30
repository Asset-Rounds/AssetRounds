import Foundation
import SwiftData
import XCTest

@testable import FieldEvidenceApp

@MainActor
final class V23CheckRunnerDurableInitialBeginTests: XCTestCase {
    func testDurableInitialBeginPersistsRawParentWithoutWorkflowOrBeginEffects() throws {
        try withFrozenBeginFixture("durable-raw", entry: .check, storedTimeZoneID: nil) { h in
            let service = try durableBeginService(h)
            let raw = CheckRunnerEditablePreflightV1(timeZoneID: "  e\u{301} / unfinished  ",
                isTimeZoneConfirmed: false, confirmedTimeZoneID: "  invalid stored input  ",
                afterDarkAccepted: false, safePositionAccepted: false)
            let outcome = CheckRunnerEditableOutcomeV1(couldNotVerifyNote: "  untrimmed\n", recheckNote: "e\u{301}  ")
            let before = try h.snapshot()
            let source = try h.captureSource()
            let checkpoint = try service.create(source: source, preflight: raw, outcome: outcome)
            let payload = try CheckRunnerItemDraftCodecV1.validateCheckpoint(checkpoint)
            XCTAssertEqual(payload.field.preflight, raw)
            XCTAssertEqual(payload.field.outcome, outcome)
            XCTAssertEqual(payload.field.begin, .notBegun)
            XCTAssertEqual(checkpoint.baseCanonicalRevision, source.roundAtEntry.revision)
            XCTAssertTrue(checkpoint.stageIDs.isEmpty)
            let after = try h.snapshot()
            XCTAssertEqual(after.revision.revision, before.revision.revision + 1)
            XCTAssertEqual(after.rows.workflows, before.rows.workflows)
            XCTAssertEqual(after.rows.sites, before.rows.sites)
            let idCalls = h.ids.callCount
            XCTAssertThrowsError(try service.create(source: source, preflight: raw))
            XCTAssertThrowsError(try service.prepareBegin(draftID: checkpoint.draftID,
                expectedCheckpointSHA256: checkpoint.checkpointSHA256,
                observedAtUTC: h.validSubmission().observedAtUTC!))
            XCTAssertEqual(try h.snapshot(), after)
            XCTAssertEqual(h.ids.callCount, idCalls)
        }
    }

    func testDurableInitialBeginPersistsPreparedBeforeTargetsAndBindsCheck() throws {
        try withFrozenBeginFixture("durable-check", entry: .check, storedTimeZoneID: "America/New_York") { h in
            let (service, prepared, attempt) = try durablePreparedBegin(h, recordID: 9_601)
            let writer = h.coordinator.workspaceWriter
            XCTAssertNil(try writer.checkRunnerBeginEvidence(workspaceID: h.workspaceID,
                                                            mutationID: attempt.recordMutationID))
            XCTAssertTrue(try h.context.fetch(FetchDescriptor<WorkflowRecord>()).isEmpty)
            let before = try h.snapshot(), idCalls = h.ids.callCount
            XCTAssertEqual(try service.prepareBegin(draftID: prepared.draftID,
                expectedCheckpointSHA256: prepared.checkpointSHA256,
                observedAtUTC: Date(timeIntervalSince1970: 1)), prepared)
            XCTAssertEqual(try h.snapshot(), before)
            XCTAssertEqual(h.ids.callCount, idCalls)
            let bound = try service.resumeInitialBegin(draftID: prepared.draftID)
            let payload = try CheckRunnerItemDraftCodecV1.validateCheckpoint(bound)
            let receipt = try XCTUnwrap(writer.checkRunnerBeginEvidence(workspaceID: h.workspaceID,
                                                                        mutationID: attempt.recordMutationID))
            XCTAssertEqual(payload.field.begin.attempt, attempt)
            try XCTUnwrap(payload.field.begin.workflowReceiptReference).validate(evidence: receipt)
            XCTAssertEqual(bound.draftRevision, prepared.draftRevision + 1)
            XCTAssertEqual(try writer.currentRevision().revision, before.revision.revision + 2)
            XCTAssertEqual(h.ids.callCount, idCalls + 1)
        }
    }

    func testDurableInitialBeginRecoversSavedTimeZoneBeforeRecheck() throws {
        try withFrozenBeginFixture("durable-recheck", entry: .recheck(issueID: beginPreparationUUID(9_610)),
                                   storedTimeZoneID: nil) { h in
            let (service, prepared, attempt) = try durablePreparedBegin(h, recordID: 9_611, zoneID: 9_612)
            let writer = h.coordinator.workspaceWriter
            let originalZone = try writer.commitFrozenCheckRunnerTimeZone(attempt)
            XCTAssertEqual(try service.read(draftID: prepared.draftID), prepared)
            XCTAssertNil(try writer.checkRunnerBeginEvidence(workspaceID: h.workspaceID,
                                                            mutationID: attempt.recordMutationID))
            let bound = try service.resumeInitialBegin(draftID: prepared.draftID)
            let payload = try CheckRunnerItemDraftCodecV1.validateCheckpoint(bound)
            guard case let .bound(saved, workflow, zone) = payload.field.begin else { return XCTFail("Expected BOUND") }
            XCTAssertEqual(saved, attempt)
            try XCTUnwrap(zone).validate(evidence: originalZone)
            let originalWorkflow = try XCTUnwrap(writer.checkRunnerBeginEvidence(workspaceID: h.workspaceID,
                mutationID: attempt.recordMutationID))
            try workflow.validate(evidence: originalWorkflow)
            XCTAssertEqual(originalWorkflow.receipt.committedAt, attempt.recordCommittedAt)
            XCTAssertEqual(try writer.commitFrozenCheckRunnerTimeZone(attempt), originalZone)
        }
    }

    func testDurableInitialBeginRecoversWorkflowAndBoundAcknowledgementLoss() throws {
        try withFrozenBeginFixture("durable-workflow-ack", entry: .check, storedTimeZoneID: nil) { h in
            let (service, prepared, attempt) = try durablePreparedBegin(h, recordID: 9_621, zoneID: 9_622)
            let writer = h.coordinator.workspaceWriter
            let originalZone = try writer.commitFrozenCheckRunnerTimeZone(attempt)
            let originalWorkflow = try writer.commitFrozenCheckRunnerDraft(attempt)
            XCTAssertEqual(try service.read(draftID: prepared.draftID), prepared)
            let before = try h.snapshot()
            let bound = try service.resumeInitialBegin(draftID: prepared.draftID)
            XCTAssertEqual(try writer.currentRevision().revision, before.revision.revision + 1)
            let saved = try h.snapshot(), idCalls = h.ids.callCount
            XCTAssertEqual(try service.resumeInitialBegin(draftID: prepared.draftID), bound)
            XCTAssertEqual(try h.snapshot(), saved)
            XCTAssertEqual(h.ids.callCount, idCalls)
            XCTAssertEqual(try writer.commitFrozenCheckRunnerTimeZone(attempt), originalZone)
            XCTAssertEqual(try writer.commitFrozenCheckRunnerDraft(attempt), originalWorkflow)
            XCTAssertEqual(try h.snapshot(), saved)
        }
    }

    func testDurableInitialBeginRejectsSourceAdvanceBeforeEitherTargetEffect() throws {
        try withFrozenBeginFixture("durable-source-drift", entry: .check, storedTimeZoneID: nil) { h in
            let (service, prepared, attempt) = try durablePreparedBegin(h, recordID: 9_631, zoneID: 9_632)
            let latest = try h.progress.read(sourceDraftID: attempt.source.sourceCheckpoint.draftID)
            let advanced = try h.progress.prepareStep(read: latest, action: .keepOpenAndNext, focus: .facts,
                completionRecordID: nil, recordedByName: "Different actual progress tip")
            _ = try h.progress.persistStep(advanced)
            let before = try h.snapshot()
            XCTAssertThrowsError(try service.resumeInitialBegin(draftID: prepared.draftID))
            XCTAssertEqual(try h.snapshot(), before)
            XCTAssertNil(try h.coordinator.workspaceWriter.checkRunnerBeginEvidence(workspaceID: h.workspaceID,
                mutationID: attempt.recordMutationID))
            XCTAssertNil(try h.coordinator.workspaceWriter.checkRunnerBeginEvidence(workspaceID: h.workspaceID,
                mutationID: XCTUnwrap(attempt.timeZone).mutationID))
        }
    }

    func testDurableInitialBeginRejectsChangedCommandAndForeignWorkflowWithoutEffects() throws {
        try withFrozenBeginFixture("durable-forged-command", entry: .check, storedTimeZoneID: nil) { h in
            let (service, prepared, attempt) = try durablePreparedBegin(h, recordID: 9_641, zoneID: 9_642)
            var object = try frozenBeginJSONObject(FieldDraftCanonicalCodecV1.encode(attempt))
            XCTAssertEqual(try decodeFrozenBeginJSON(CheckRunnerFrozenBeginAttemptV1.self, object: object), attempt)
            var command = try XCTUnwrap(object["recordCommand"] as? [String: Any])
            command["afterDarkAcknowledgementCopy"] = "Foreign but well-formed package text"
            object["recordCommand"] = command
            let changed = try decodeFrozenBeginJSON(CheckRunnerFrozenBeginAttemptV1.self, object: object)
            XCTAssertNotEqual(changed.recordCommand.afterDarkAcknowledgementCopy,
                              attempt.recordCommand.afterDarkAcknowledgementCopy)
            let payload = try CheckRunnerItemDraftCodecV1.validateCheckpoint(prepared)
            let field = payload.field
            let forged = try CheckRunnerItemDraftPayloadV1(editing: payload.source, field: .init(
                preflight: field.preflight, begin: .prepared(attempt: changed), outcome: field.outcome,
                wideContext: nil, closeDetail: nil, semanticAnchor: field.semanticAnchor))
            _ = try persistDurableBeginReplacement(h, predecessor: prepared, payload: forged, mutation: 9_643)
            let before = try h.snapshot()
            XCTAssertThrowsError(try service.resumeInitialBegin(draftID: prepared.draftID))
            XCTAssertEqual(try h.snapshot(), before)
        }
        try withFrozenBeginFixture("durable-foreign-workflow", entry: .check,
                                   storedTimeZoneID: "America/New_York") { h in
            let (service, prepared, attempt) = try durablePreparedBegin(h, recordID: 9_644)
            var command = try frozenBeginJSONObject(FieldDraftCanonicalCodecV1.encode(attempt.recordCommand))
            XCTAssertEqual(try FieldDraftCanonicalCodecV1.encode(decodeFrozenBeginJSON(CheckDraftMutationV1.self,
                object: command)), try FieldDraftCanonicalCodecV1.encode(attempt.recordCommand))
            command["recordID"] = beginPreparationUUID(9_645).uuidString.lowercased()
            let foreign = try decodeFrozenBeginJSON(CheckDraftMutationV1.self, object: command)
            XCTAssertNotEqual(foreign.recordID, attempt.recordCommand.recordID)
            _ = try h.coordinator.workspaceWriter.execute(.createCheckDraft(foreign),
                mutationID: .init(rawValue: foreign.recordID))
            let before = try h.snapshot()
            XCTAssertThrowsError(try service.resumeInitialBegin(draftID: prepared.draftID))
            XCTAssertEqual(try h.snapshot(), before)
        }
    }

    func testDurableInitialBeginRejectsChangedSiteAndInitialPostimage() throws {
        try withFrozenBeginFixture("durable-site-drift", entry: .check, storedTimeZoneID: nil) { h in
            let (service, prepared, attempt) = try durablePreparedBegin(h, recordID: 9_651, zoneID: 9_652)
            let writer = h.coordinator.workspaceWriter
            _ = try writer.commitFrozenCheckRunnerTimeZone(attempt)
            let zone = try XCTUnwrap(attempt.timeZone)
            _ = try writer.execute(.updateSiteTimeZone(.init(siteID: h.siteID, timeZoneID: zone.command.timeZoneID,
                confirmedAt: zone.command.confirmedAt.addingTimeInterval(1))),
                mutationID: .init(rawValue: beginPreparationUUID(9_653)))
            let before = try h.snapshot()
            XCTAssertThrowsError(try service.resumeInitialBegin(draftID: prepared.draftID))
            XCTAssertEqual(try h.snapshot(), before)
        }
        try withFrozenBeginFixture("durable-record-postimage", entry: .check,
                                   storedTimeZoneID: "America/New_York") { h in
            let (service, prepared, attempt) = try durablePreparedBegin(h, recordID: 9_654)
            _ = try h.coordinator.workspaceWriter.commitFrozenCheckRunnerDraft(attempt)
            let before = try h.snapshot()
            let record = try XCTUnwrap(h.context.fetch(FetchDescriptor<WorkflowRecord>()).first {
                $0.id == attempt.recordCommand.recordID
            })
            let originalCopy = record.afterDarkAcknowledgementCopy
            record.afterDarkAcknowledgementCopy = "Unjournaled persisted substitution"
            try h.context.save()
            XCTAssertThrowsError(try service.resumeInitialBegin(draftID: prepared.draftID))
            XCTAssertEqual(record.afterDarkAcknowledgementCopy, "Unjournaled persisted substitution")
            XCTAssertFalse(h.context.hasChanges)
            record.afterDarkAcknowledgementCopy = originalCopy
            try h.context.save()
            XCTAssertEqual(try h.snapshot(), before)
            _ = try service.resumeInitialBegin(draftID: prepared.draftID)
        }
    }

    func testDurableInitialBeginColdReopenReusesPreparedAttemptAndOriginalReceipts() throws {
        try withFrozenBeginFixture("durable-cold", entry: .check, storedTimeZoneID: nil) { h in
            let (_, prepared, attempt) = try durablePreparedBegin(h, recordID: 9_661, zoneID: 9_662)
            let originalZone = try h.coordinator.workspaceWriter.commitFrozenCheckRunnerTimeZone(attempt)
            let originalWorkflow = try h.coordinator.workspaceWriter.commitFrozenCheckRunnerDraft(attempt)
            try h.closeCoordinator()
            let opened = try h.factory.openOrBootstrapCurrent()
            let reopened = try StoreSessionCoordinator(validatingSession: opened, clock: h.clock, idSource: h.ids,
                lifecycleProfileRegistry: h.coordinator.lifecycleProfileRegistry)
            defer { XCTAssertNoThrow(try reopened.invalidateAndReleaseWriter()) }
            let gate = AppAccessGateV1(setting: .absentDisabled, authentication: FrozenBeginAuthentication(),
                clock: h.clock, identifiers: h.ids)
            let transitions = try reopened.makeRoundSessionTransitionService(accessGate: gate)
            let progress = try reopened.makeRepetitiveCaptureProgressService(transitions: transitions)
            let runner = try CheckRunnerCoordinator(modelContext: opened.modelContext,
                packageLifecycleDependencies: reopened.packageLifecycleDependencies(profileRegistry: reopened.lifecycleProfileRegistry),
                packageLifecycleProfile: h.profile)
            let service = try ProductionCheckRunnerItemDraftServiceV1(session: reopened, progress: progress,
                coordinator: runner, publishedRelease: h.publishedRelease, clock: h.clock, ids: h.ids)
            XCTAssertEqual(try service.read(draftID: prepared.draftID), prepared)
            let bound = try service.resumeInitialBegin(draftID: prepared.draftID)
            let saved = try CheckRunnerItemDraftCodecV1.validateCheckpoint(bound)
            XCTAssertEqual(saved.field.begin.attempt, attempt)
            XCTAssertEqual(try reopened.workspaceWriter.commitFrozenCheckRunnerTimeZone(attempt), originalZone)
            XCTAssertEqual(try reopened.workspaceWriter.commitFrozenCheckRunnerDraft(attempt), originalWorkflow)
            let revision = try reopened.workspaceWriter.currentRevision()
            XCTAssertEqual(try service.resumeInitialBegin(draftID: prepared.draftID), bound)
            XCTAssertEqual(try reopened.workspaceWriter.currentRevision(), revision)
        }
    }

    func testDurableInitialBeginUsesOriginalCreationReceiptForContinuationAccess() throws {
        try withFrozenBeginFixture("durable-access-time", entry: .check,
                                   storedTimeZoneID: "America/New_York") { h in
            var access: DraftAccessNormalizedStateV1 = .entitled
            let runner = try h.makeRunner(draftAccessState: { access })
            let service = try ProductionCheckRunnerItemDraftServiceV1(session: h.coordinator, progress: h.progress,
                coordinator: runner, publishedRelease: h.publishedRelease, clock: h.clock, ids: h.ids)
            let parent = try service.create(source: h.captureSource(), preflight: .init(
                afterDarkAccepted: true, safePositionAccepted: true))
            let futureObservation = h.clock.value.addingTimeInterval(600)
            h.ids.enqueue([beginPreparationUUID(9_671)])
            let prepared = try service.prepareBegin(draftID: parent.draftID,
                expectedCheckpointSHA256: parent.checkpointSHA256, observedAtUTC: futureObservation)
            let attempt = try XCTUnwrap(CheckRunnerItemDraftCodecV1.validateCheckpoint(prepared).field.begin.attempt)
            access = .formerPaidInactive
            let before = try h.snapshot()
            XCTAssertThrowsError(try service.resumeInitialBegin(draftID: prepared.draftID))
            XCTAssertEqual(try h.snapshot(), before)
            access = .entitled
            let original = try h.coordinator.workspaceWriter.commitFrozenCheckRunnerDraft(attempt)
            access = .formerPaidInactive
            let bound = try service.resumeInitialBegin(draftID: prepared.draftID)
            let payload = try CheckRunnerItemDraftCodecV1.validateCheckpoint(bound)
            XCTAssertEqual(payload.field.begin.attempt?.recordCommand.startedAt, futureObservation)
            XCTAssertLessThan(original.receipt.committedAt, h.clock.value)
            try XCTUnwrap(payload.field.begin.workflowReceiptReference).validate(evidence: original)
        }
    }

    private func durableBeginService(_ h: FrozenBeginFixture) throws -> ProductionCheckRunnerItemDraftServiceV1 {
        try .init(session: h.coordinator, progress: h.progress, coordinator: h.runner,
            publishedRelease: h.publishedRelease, clock: h.clock, ids: h.ids)
    }

    private func durablePreparedBegin(_ h: FrozenBeginFixture, recordID: Int, zoneID: Int? = nil) throws
        -> (ProductionCheckRunnerItemDraftServiceV1, FieldDraftCheckpointV1, CheckRunnerFrozenBeginAttemptV1) {
        let service = try durableBeginService(h)
        let parent = try service.create(source: h.captureSource(), preflight: .init(timeZoneID: "  America/New_York  ",
            isTimeZoneConfirmed: true, confirmedTimeZoneID: "  America/New_York  ",
            afterDarkAccepted: true, safePositionAccepted: true))
        h.ids.enqueue([beginPreparationUUID(recordID)] + (zoneID.map { [beginPreparationUUID($0)] } ?? []))
        let prepared = try service.prepareBegin(draftID: parent.draftID,
            expectedCheckpointSHA256: parent.checkpointSHA256,
            observedAtUTC: XCTUnwrap(h.validSubmission().observedAtUTC))
        let attempt = try XCTUnwrap(CheckRunnerItemDraftCodecV1.validateCheckpoint(prepared).field.begin.attempt)
        return (service, prepared, attempt)
    }

    private func persistDurableBeginReplacement(_ h: FrozenBeginFixture, predecessor: FieldDraftCheckpointV1,
        payload: CheckRunnerItemDraftPayloadV1, mutation: Int) throws -> FieldDraftCheckpointV1 {
        let replacement = try FieldDraftCheckpointV1(draftID: predecessor.draftID, workspaceID: predecessor.workspaceID,
            scope: predecessor.scope, purpose: predecessor.purpose, codec: predecessor.codec,
            baseCanonicalRevision: predecessor.baseCanonicalRevision, draftRevision: predecessor.draftRevision + 1,
            payloadData: CheckRunnerItemDraftCodecV1.encode(payload), stageIDs: [],
            resumeAnchor: CheckRunnerItemDraftCodecV1.resumeAnchor(payload: payload), state: .active,
            updatedAt: predecessor.updatedAt, mutationID: .init(rawValue: beginPreparationUUID(mutation)))
        _ = try h.coordinator.workspaceWriter.makeFieldDraftLifecycleAdapter(modelContext: h.context)
            .compareAndSwap(checkpoint: replacement, expectedDraftRevision: predecessor.draftRevision,
                            expectedBaseRevision: predecessor.baseCanonicalRevision)
        return replacement
    }

}

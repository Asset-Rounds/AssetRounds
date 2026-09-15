import Foundation
import SwiftData
import XCTest

@testable import FieldEvidenceApp

@MainActor
final class V23CheckRunnerFrozenBeginWriterTests: XCTestCase {
    func testFrozenBeginWriterCommitsOriginalTimeAndReplaysWithoutEffects() throws {
        try withFrozenBeginFixture("writer-check", entry: .check,
                                   storedTimeZoneID: "America/New_York") { h in
            let attempt = try prepareWriterAttempt(h, recordID: 9_501)
            let writer = h.coordinator.workspaceWriter
            let before = try writer.currentRevision()
            let original = try writer.commitFrozenCheckRunnerDraft(attempt)
            XCTAssertEqual(original.command, .createCheckDraft(attempt.recordCommand))
            XCTAssertEqual(original.receipt.committedAt, attempt.recordCommittedAt)
            XCTAssertEqual(original.envelope.expectedRevision.workspaceRevision, before.revision)
            XCTAssertEqual(original.envelope.expectedRevision.entityRevisions, attempt.recordExpectedEntityRevisions)
            let record = try XCTUnwrap(h.context.fetch(FetchDescriptor<WorkflowRecord>()).first {
                $0.id == attempt.recordCommand.recordID
            })
            XCTAssertEqual(record.assetID, h.assetID)
            XCTAssertEqual(record.stage, WorkflowStage.check.rawValue)
            XCTAssertEqual(record.startedAt, attempt.recordCommand.startedAt)
            let saved = try h.snapshot(), idCalls = h.ids.callCount
            let restoredAttempt = try FieldDraftCanonicalCodecV1.decode(CheckRunnerFrozenBeginAttemptV1.self,
                from: FieldDraftCanonicalCodecV1.encode(attempt))
            XCTAssertEqual(try writer.commitFrozenCheckRunnerDraft(restoredAttempt), original)
            XCTAssertEqual(try h.snapshot(), saved)
            XCTAssertEqual(h.ids.callCount, idCalls)
        }
    }

    func testFrozenBeginWriterRecoversSavedTimeZoneBeforeRecheckDraft() throws {
        try withFrozenBeginFixture("writer-recheck", entry: .recheck(issueID: beginPreparationUUID(9_510)),
                                   storedTimeZoneID: nil) { h in
            let attempt = try prepareWriterAttempt(h, recordID: 9_511, zoneID: 9_512)
            let writer = h.coordinator.workspaceWriter
            let zone = try XCTUnwrap(attempt.timeZone)
            let zoneOriginal = try writer.commitFrozenCheckRunnerTimeZone(attempt)
            XCTAssertEqual(zoneOriginal.command, .updateSiteTimeZone(zone.command))
            XCTAssertEqual(zoneOriginal.receipt.committedAt, zone.committedAt)
            let savedZone = try h.snapshot()
            XCTAssertEqual(try writer.commitFrozenCheckRunnerTimeZone(attempt), zoneOriginal)
            XCTAssertEqual(try h.snapshot(), savedZone)
            let original = try writer.commitFrozenCheckRunnerDraft(attempt)
            XCTAssertEqual(original.receipt.committedAt, attempt.recordCommittedAt)
            XCTAssertEqual(original.envelope.expectedRevision.entityRevisions, attempt.recordExpectedEntityRevisions)
            XCTAssertEqual(original.envelope.expectedRevision.workspaceRevision, savedZone.revision.revision)
            let record = try XCTUnwrap(h.context.fetch(FetchDescriptor<WorkflowRecord>()).first {
                $0.id == attempt.recordCommand.recordID
            })
            XCTAssertEqual(record.issueID, h.issueID)
            XCTAssertEqual(record.parentRecordID, h.recheckParentID)
            XCTAssertEqual(record.stage, WorkflowStage.recheck.rawValue)
            let savedBoth = try h.snapshot()
            XCTAssertEqual(try writer.commitFrozenCheckRunnerTimeZone(attempt), zoneOriginal)
            XCTAssertEqual(try writer.commitFrozenCheckRunnerDraft(attempt), original)
            XCTAssertEqual(try h.snapshot(), savedBoth)
        }
    }

    func testFrozenBeginWriterRejectsReceiptBodyTimeAndRevisionChangesWithoutQuarantine() throws {
        try withFrozenBeginFixture("writer-mismatch", entry: .check,
                                   storedTimeZoneID: "America/New_York") { h in
            let attempt = try prepareWriterAttempt(h, recordID: 9_521)
            let writer = h.coordinator.workspaceWriter
            let original = try writer.commitFrozenCheckRunnerDraft(attempt)
            var body = try frozenBeginJSONObject(FieldDraftCanonicalCodecV1.encode(attempt))
            var command = try XCTUnwrap(body["recordCommand"] as? [String: Any])
            command["afterDarkAcknowledgementCopy"] = "Different retained acknowledgement"
            body["recordCommand"] = command
            let changedBody = try FieldDraftCanonicalCodecV1.decode(CheckRunnerFrozenBeginAttemptV1.self,
                from: frozenBeginJSONData(body))
            let changedTime = try writerAttempt(attempt,
                committedAt: attempt.recordCommittedAt.addingTimeInterval(1))
            let changedRevisions = attempt.recordExpectedEntityRevisions.map {
                WorkspaceEntityRevisionV1(identity: $0.identity,
                    revision: $0.identity.kind == .asset ? $0.revision + 1 : $0.revision)
            }
            let changedRevision = try writerAttempt(attempt, revisions: changedRevisions)
            for changed in [changedBody, changedTime, changedRevision] {
                let before = try h.snapshot()
                XCTAssertThrowsError(try writer.commitFrozenCheckRunnerDraft(changed))
                XCTAssertEqual(try h.snapshot(), before)
                XCTAssertEqual(try writer.commitFrozenCheckRunnerDraft(attempt), original)
                XCTAssertEqual(try h.snapshot(), before)
            }
        }
    }

    func testFrozenBeginWriterUsesFreshWorkspaceCASButRejectsStaleTarget() throws {
        try withFrozenBeginFixture("writer-global", entry: .check,
                                   storedTimeZoneID: "America/New_York") { h in
            let attempt = try prepareWriterAttempt(h, recordID: 9_531)
            let writer = h.coordinator.workspaceWriter
            let before = try writer.currentRevision()
            _ = try writer.execute(.updateSiteTimeZone(.init(siteID: h.siteID,
                timeZoneID: "America/New_York", confirmedAt: attempt.recordCommand.startedAt)),
                mutationID: .init(rawValue: beginPreparationUUID(9_532)))
            let advanced = try writer.currentRevision()
            XCTAssertGreaterThan(advanced.revision, before.revision)
            let original = try writer.commitFrozenCheckRunnerDraft(attempt)
            XCTAssertEqual(original.envelope.expectedRevision.workspaceRevision, advanced.revision)
            XCTAssertEqual(original.envelope.expectedRevision.entityRevisions, attempt.recordExpectedEntityRevisions)
        }
        try withFrozenBeginFixture("writer-stale", entry: .check,
                                   storedTimeZoneID: "America/New_York") { h in
            let attempt = try prepareWriterAttempt(h, recordID: 9_533)
            let writer = h.coordinator.workspaceWriter
            _ = try writer.execute(.createCheckDraft(attempt.recordCommand),
                mutationID: .init(rawValue: beginPreparationUUID(9_534)))
            let before = try h.snapshot()
            XCTAssertThrowsError(try writer.commitFrozenCheckRunnerDraft(attempt)) {
                XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .staleWorkspaceRevision)
            }
            XCTAssertEqual(try h.snapshot(), before)
            XCTAssertNil(try writer.checkRunnerBeginEvidence(workspaceID: h.workspaceID,
                mutationID: attempt.recordMutationID))
        }
    }

    func testFrozenBeginWriterRejectsMissingOrChangedTimeZoneProofBeforeDraft() throws {
        try withFrozenBeginFixture("writer-missing-zone", entry: .check, storedTimeZoneID: nil) { h in
            let attempt = try prepareWriterAttempt(h, recordID: 9_541, zoneID: 9_542)
            let writer = h.coordinator.workspaceWriter
            let zone = try XCTUnwrap(attempt.timeZone)
            let before = try h.snapshot()
            XCTAssertThrowsError(try writer.commitFrozenCheckRunnerDraft(attempt))
            XCTAssertEqual(try h.snapshot(), before)
            _ = try writer.execute(.updateSiteTimeZone(zone.command),
                mutationID: .init(rawValue: beginPreparationUUID(9_543)))
            let equalText = try h.snapshot()
            XCTAssertThrowsError(try writer.commitFrozenCheckRunnerDraft(attempt))
            XCTAssertThrowsError(try writer.commitFrozenCheckRunnerTimeZone(attempt))
            XCTAssertEqual(try h.snapshot(), equalText)
            XCTAssertNil(try writer.checkRunnerBeginEvidence(workspaceID: h.workspaceID,
                mutationID: attempt.recordMutationID))
        }
        try withFrozenBeginFixture("writer-changed-zone", entry: .check, storedTimeZoneID: nil) { h in
            let attempt = try prepareWriterAttempt(h, recordID: 9_544, zoneID: 9_545)
            let writer = h.coordinator.workspaceWriter
            let zone = try XCTUnwrap(attempt.timeZone)
            let original = try writer.commitFrozenCheckRunnerTimeZone(attempt)
            let changedZone = try CheckRunnerBeginTimeZoneAttemptV1(command: zone.command,
                mutationID: zone.mutationID, expectedSiteRevision: zone.expectedSiteRevision + 1,
                committedAt: zone.committedAt)
            let changed = try writerAttempt(attempt, zone: changedZone)
            let before = try h.snapshot()
            XCTAssertThrowsError(try writer.commitFrozenCheckRunnerTimeZone(changed))
            XCTAssertThrowsError(try writer.commitFrozenCheckRunnerDraft(changed))
            XCTAssertEqual(try h.snapshot(), before)
            XCTAssertEqual(try writer.commitFrozenCheckRunnerTimeZone(attempt), original)
            _ = try writer.commitFrozenCheckRunnerDraft(attempt)
        }
    }

    func testFrozenBeginWriterRejectsDirtyAndRetiredSessionsWithoutEffects() throws {
        try withFrozenBeginFixture("writer-owner", entry: .check, storedTimeZoneID: nil) { h in
            let attempt = try prepareWriterAttempt(h, recordID: 9_551, zoneID: 9_552)
            let writer = h.coordinator.workspaceWriter
            let site = try XCTUnwrap(h.context.fetch(FetchDescriptor<Site>()).first { $0.id == h.siteID })
            site.label = "Unsaved writer precondition"
            let dirty = try h.rowSnapshot()
            XCTAssertThrowsError(try writer.commitFrozenCheckRunnerTimeZone(attempt))
            XCTAssertThrowsError(try writer.commitFrozenCheckRunnerDraft(attempt))
            XCTAssertEqual(try h.rowSnapshot(), dirty)
            h.context.rollback()
            let rows = try h.rowSnapshot()
            try h.closeCoordinator()
            XCTAssertThrowsError(try writer.commitFrozenCheckRunnerTimeZone(attempt))
            XCTAssertThrowsError(try writer.commitFrozenCheckRunnerDraft(attempt))
            XCTAssertEqual(try h.rowSnapshot(), rows)
        }
    }

    private func prepareWriterAttempt(_ h: FrozenBeginFixture, recordID: Int, zoneID: Int? = nil) throws
        -> CheckRunnerFrozenBeginAttemptV1 {
        h.ids.enqueue([beginPreparationUUID(recordID)] + (zoneID.map { [beginPreparationUUID($0)] } ?? []))
        return try h.runner.prepareFrozenBegin(source: h.captureSource(), progress: h.progress,
            publishedRelease: h.publishedRelease, submission: h.validSubmission())
    }

    private func writerAttempt(_ original: CheckRunnerFrozenBeginAttemptV1,
        committedAt: Date? = nil, revisions: [WorkspaceEntityRevisionV1]? = nil,
        zone: CheckRunnerBeginTimeZoneAttemptV1? = nil) throws -> CheckRunnerFrozenBeginAttemptV1 {
        try .init(source: original.source, sourceWorkspaceID: original.sourceWorkspaceID,
            recordCommand: original.recordCommand, recordMutationID: original.recordMutationID,
            recordExpectedEntityRevisions: revisions ?? original.recordExpectedEntityRevisions,
            recordCommittedAt: committedAt ?? original.recordCommittedAt,
            timeZone: zone ?? original.timeZone, siteID: original.siteID,
            resolvedSiteTimeZoneID: original.resolvedSiteTimeZoneID)
    }

}

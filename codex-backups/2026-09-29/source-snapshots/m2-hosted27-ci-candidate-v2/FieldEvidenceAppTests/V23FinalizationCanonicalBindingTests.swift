import Foundation
import XCTest
@testable import FieldEvidenceApp

/// Replay and recovery bindings compare finalized rows with the caller's
/// finalization at the precision the finalization contract persists (UTC
/// milliseconds for instants, every other member exactly). A row written
/// back through the canonical writer may differ from the caller's `Date` by a
/// floating-point ULP; that is the same persisted instant. Anything the
/// persisted contract distinguishes must still be rejected.
final class V23FinalizationCanonicalBindingTests: XCTestCase {
    private let instant = Date(timeIntervalSince1970: 1_790_361_825.894925)

    private var ulpDrifted: Date {
        Date(timeIntervalSince1970: instant.timeIntervalSince1970.nextUp)
    }

    private var nextMillisecond: Date {
        instant.addingTimeInterval(0.001)
    }

    func testInstantMatchesAcrossULPDriftButNotAcrossPersistedMilliseconds() {
        XCTAssertNotEqual(instant, ulpDrifted)
        XCTAssertTrue(FinalizationCanonicalBindingV1.sameInstant(instant, ulpDrifted))
        XCTAssertFalse(FinalizationCanonicalBindingV1.sameInstant(instant, nextMillisecond))
        XCTAssertTrue(FinalizationCanonicalBindingV1.sameInstant(nil, nil))
        XCTAssertFalse(FinalizationCanonicalBindingV1.sameInstant(instant, nil))
        XCTAssertFalse(FinalizationCanonicalBindingV1.sameInstant(nil, instant))
    }

    func testRecordBindingNormalizesOnlyInstantDrift() {
        let base = record(completedAt: instant, note: "Checked")
        XCTAssertTrue(FinalizationCanonicalBindingV1.sameRecord(base, record(completedAt: ulpDrifted, note: "Checked")))
        XCTAssertFalse(FinalizationCanonicalBindingV1.sameRecord(base, record(completedAt: nextMillisecond, note: "Checked")))
        XCTAssertFalse(FinalizationCanonicalBindingV1.sameRecord(base, record(completedAt: nil, note: "Checked")))
        XCTAssertFalse(FinalizationCanonicalBindingV1.sameRecord(base, record(completedAt: instant, note: "Checked again")))
    }

    func testIssueBindingNormalizesOnlyInstantDrift() {
        let base = issue(updatedAt: instant, status: "open")
        XCTAssertTrue(FinalizationCanonicalBindingV1.sameIssue(base, issue(updatedAt: ulpDrifted, status: "open")))
        XCTAssertFalse(FinalizationCanonicalBindingV1.sameIssue(base, issue(updatedAt: nextMillisecond, status: "open")))
        XCTAssertFalse(FinalizationCanonicalBindingV1.sameIssue(base, issue(updatedAt: instant, status: "resolved")))
        XCTAssertTrue(FinalizationCanonicalBindingV1.sameIssue(nil, nil))
        XCTAssertFalse(FinalizationCanonicalBindingV1.sameIssue(base, nil))
    }

    func testPacketBindingNormalizesOnlyInstantDrift() {
        let base = packet(createdAt: instant, evaluationCounted: true)
        XCTAssertTrue(FinalizationCanonicalBindingV1.samePacket(base, packet(createdAt: ulpDrifted, evaluationCounted: true)))
        XCTAssertFalse(FinalizationCanonicalBindingV1.samePacket(base, packet(createdAt: nextMillisecond, evaluationCounted: true)))
        XCTAssertFalse(FinalizationCanonicalBindingV1.samePacket(base, packet(createdAt: instant, evaluationCounted: false)))
    }

    private func id(_ slot: Int) -> UUID {
        UUID(uuidString: String(format: "f1a00000-0000-4000-8000-%012x", slot))!
    }

    private func record(completedAt: Date?, note: String) -> WorkflowRecordPayloadV1 {
        WorkflowRecordPayloadV1(
            id: id(1), schemaVersion: 1, assetID: id(2), packetID: id(3), issueID: nil,
            parentRecordID: nil, recordRevisionRootID: id(1), revisesRecordID: nil,
            evidenceSourceRecordID: nil, revisionKind: WorkflowRevisionKind.original.rawValue,
            stage: "check", state: WorkflowState.completed.rawValue, draftStepKey: nil,
            startedAt: instant.addingTimeInterval(-60), completedAt: completedAt, observedAtUTC: instant,
            timeZoneID: "UTC", utcOffsetMinutes: 0, localDate: "2026-09-25", localTime: "17:23:45",
            afterDarkAcknowledgementKey: nil, afterDarkAcknowledgementCopy: nil,
            afterDarkAcknowledgementVersion: nil, afterDarkAcknowledgementAccepted: false,
            safePositionAcknowledgementKey: nil, safePositionAcknowledgementCopy: nil,
            safePositionAcknowledgementVersion: nil, safePositionAcknowledgementAccepted: false,
            packID: "binding-pack", packSchemaVersion: 1, packContentVersion: 1,
            pdfTemplateID: "binding-pdf", pdfTemplateVersion: 1, outcomeKey: "completed",
            couldNotVerifyKey: nil, couldNotVerifyDisplaySnapshot: nil,
            couldNotVerifyRegistryVersion: nil, workPerformedLocalDate: nil,
            workDescription: nil, note: note, finalizationMutationID: id(4))
    }

    private func issue(updatedAt: Date, status: String) -> IssuePayloadV1 {
        IssuePayloadV1(
            id: id(5), schemaVersion: 1, assetID: id(2), openedByRecordID: id(1),
            labelKey: "dark_section", labelDisplaySnapshot: "Section appears dark",
            status: status, resolvedByRecordID: nil,
            createdAt: instant.addingTimeInterval(-120), updatedAt: updatedAt)
    }

    private func packet(createdAt: Date, evaluationCounted: Bool) -> PacketPayloadV1 {
        PacketPayloadV1(
            id: id(3), schemaVersion: 1, stableRootID: id(6), currentRecordID: id(1),
            evaluationCounted: evaluationCounted, contentDeletedAt: nil, createdAt: createdAt)
    }
}

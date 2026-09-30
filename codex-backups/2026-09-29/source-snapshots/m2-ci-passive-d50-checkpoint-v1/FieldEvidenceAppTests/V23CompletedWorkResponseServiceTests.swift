import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

@MainActor
private struct SIG1ServiceFixture {
    let fixture: V23ProductionMyDayPresentationHarness
    let report: (reportID: UUID, assetID: UUID)
    let workflow: ProductionSignWorkflow

    var service: CompletedWorkResponseServiceV1 { workflow.completedWorkResponses }
    var context: ModelContext { fixture.coordinator.modelContext }
    var writer: WorkspaceWriterV1 { fixture.coordinator.workspaceWriter }

    func workflowRecordFacts() throws -> [String] {
        try context.fetch(FetchDescriptor<WorkflowRecord>()).map { record in
            "\(record.id.uuidString)|\(record.state)|\(record.stage)|\(record.revisionKind)|"
                + "\(record.completedAt?.timeIntervalSince1970 ?? -1)"
        }.sorted()
    }

    func packetFacts() throws -> [String] {
        try context.fetch(FetchDescriptor<Packet>()).map { packet in
            "\(packet.id.uuidString)|\(packet.currentRecordID?.uuidString ?? "nil")|"
                + "\(packet.contentDeletedAt?.timeIntervalSince1970 ?? -1)"
        }.sorted()
    }

    func actorRows(_ snapshotID: UUID) throws -> [ActorSnapshotRow] {
        try context.fetch(FetchDescriptor<ActorSnapshotRow>()).filter { $0.snapshotID == snapshotID }
    }

    func signoffs() throws -> [SignoffSnapshotV1] {
        try context.fetch(FetchDescriptor<SignoffSnapshotRow>()).map { try $0.value() }
    }

    func currentProof() throws -> CompletedWorkSubjectProofV1 {
        let key = try CompletedWorkSubjectKeyV1(
            workspaceID: fixture.coordinator.workspaceID,
            subjectID: report.reportID,
            subjectRevision: 1
        )
        return try XCTUnwrap(try service.subjectDetail(key).proof)
    }
}

final class V23CompletedWorkResponseServiceTests: V23ProductionFourRootShellTestSupport {
    @MainActor
    private func makeServiceFixture(_ name: String) async throws -> SIG1ServiceFixture {
        let fixture = try await makeFixture(name)
        let report = try await makeReadyReport(in: fixture, label: name)
        let workflow = try makeCompletedWorkWorkflow(in: fixture)
        return SIG1ServiceFixture(fixture: fixture, report: report, workflow: workflow)
    }

    @MainActor
    func testRecordAppendsOneActorAndOneSignoffWithValidReceiptAndNoWorkflowTransition() async throws {
        let value = try await makeServiceFixture("sig1-service-record")
        defer { value.fixture.cleanUp() }
        let service = value.service
        let listing = try service.completedWork()
        XCTAssertEqual(listing.count, 1)
        let item = try XCTUnwrap(listing.first)
        XCTAssertEqual(item.key.subjectID, value.report.reportID)
        XCTAssertEqual(item.key.subjectRevision, 1)
        XCTAssertEqual(item.responseCount, 0)
        let proof = try XCTUnwrap(try service.subjectDetail(item.key).proof)

        let recordsBefore = try value.workflowRecordFacts()
        let packetsBefore = try value.packetFacts()
        let reportsBefore = try completedWorkRowCount(Report.self, in: value.context)
        let actorsBefore = try completedWorkRowCount(ActorSnapshotRow.self, in: value.context)
        let revisionBefore = try value.writer.currentRevision()

        let prepared = try service.prepare(
            submission: completedWorkSubmission(for: proof),
            expectedProof: proof
        )
        XCTAssertEqual(try value.writer.currentRevision(), revisionBefore, "Prepare writes nothing")
        XCTAssertEqual(prepared.attemptState, .notAttempted)

        let outcome = service.record(prepared)
        guard case let .saved(receipt) = outcome else {
            return XCTFail("Expected a saved response, got \(outcome)")
        }
        try receipt.validate()
        XCTAssertEqual(prepared.receipt, receipt)
        XCTAssertEqual(prepared.attemptState, .canonicalWriteAttempted)

        XCTAssertEqual(try completedWorkRowCount(ActorSnapshotRow.self, in: value.context), actorsBefore + 1)
        let actor = try XCTUnwrap(try value.actorRows(prepared.actorSnapshotID).first).value()
        XCTAssertEqual(actor.responsibility, .acknowledgedBy)
        XCTAssertNotEqual(actor.responsibility, .approvedBy)
        XCTAssertEqual(actor.displayNameAtTime, "Casey Responder")
        XCTAssertNil(actor.actor.partyID, "No join to current Party data")

        let signoffs = try value.signoffs()
        XCTAssertEqual(signoffs.count, 1)
        let signoff = try XCTUnwrap(signoffs.first)
        XCTAssertEqual(signoff.snapshotID, receipt.snapshotID)
        XCTAssertEqual(signoff.mutationID, receipt.mutationID)
        XCTAssertEqual(signoff.purpose, "WORK_DETAIL_COMPLETED_RESPONSE_V1")
        XCTAssertEqual(signoff.workspaceID, value.fixture.coordinator.workspaceID)
        XCTAssertEqual(signoff.subjectID, value.report.reportID)
        XCTAssertEqual(signoff.subjectRevision, 1)
        XCTAssertNil(signoff.supersedesSnapshotID)
        XCTAssertEqual(signoff.disposition, .recordedLocalAssertion)
        XCTAssertEqual(signoff.method, .typedLocalAssertion)
        XCTAssertEqual(signoff.roleAssertion?.actor, actor)
        XCTAssertEqual(signoff.roleAssertion?.claimedRole, "Site manager")
        XCTAssertEqual(signoff.roleAssertion?.claimedRelationship, .client)
        XCTAssertEqual(
            signoff.roleAssertion?.disclosureRelease.disclosureText,
            SignoffEnrollmentDisclosureV1.disclosureText
        )
        try C43SignoffEnrollmentBoundaryV1.validate(signoff)

        // Exactly the two accountability writes; no workflow transition.
        XCTAssertEqual(try value.writer.currentRevision().revision, revisionBefore.revision + 2)
        XCTAssertEqual(try value.workflowRecordFacts(), recordsBefore)
        XCTAssertEqual(try value.packetFacts(), packetsBefore)
        XCTAssertEqual(try completedWorkRowCount(Report.self, in: value.context), reportsBefore)
        XCTAssertFalse(value.context.hasChanges)

        XCTAssertEqual(try service.completedWork().first?.responseCount, 1)
        let history = try service.history(focusedSignoffID: receipt.snapshotID)
        XCTAssertEqual(history.subject, proof.display)
        XCTAssertNil(history.unavailableReason)
        XCTAssertTrue(history.earlier.isEmpty)
        let entry = try XCTUnwrap(history.current.first)
        XCTAssertEqual(history.current.count, 1)
        XCTAssertTrue(entry.isFocused)
        XCTAssertEqual(entry.version, 1)
        XCTAssertEqual(entry.facts?.typedName, "Casey Responder")
        XCTAssertEqual(entry.facts?.claimedRole, "Site manager")
        XCTAssertEqual(entry.facts?.relationshipText, "Client")
        XCTAssertEqual(entry.facts?.methodText, "Typed response")
        XCTAssertEqual(entry.facts?.disclosureText, SignoffEnrollmentDisclosureV1.disclosureText)

        // Recording the same operation again returns the same receipt.
        let revisionAfter = try value.writer.currentRevision()
        XCTAssertEqual(service.record(prepared), .saved(receipt))
        XCTAssertEqual(try value.writer.currentRevision(), revisionAfter)
        XCTAssertEqual(try value.signoffs().count, 1)
    }

    @MainActor
    func testLostSignoffAcknowledgementRetryReturnsSameReceiptWithoutDuplicate() async throws {
        #if DEBUG
        let value = try await makeServiceFixture("sig1-service-lost-signoff")
        defer { value.fixture.cleanUp() }
        let service = value.service
        let proof = try value.currentProof()
        let prepared = try service.prepare(
            submission: completedWorkSubmission(for: proof),
            expectedProof: proof
        )
        // The signoff save is durable, then its acknowledgement is lost.
        service.afterSignoffCommitForTesting = { throw CancellationError() }
        XCTAssertEqual(service.record(prepared), .uncertain)
        service.afterSignoffCommitForTesting = nil
        XCTAssertEqual(prepared.attemptState, .canonicalWriteAttempted)
        XCTAssertNil(prepared.receipt)
        let durable = try value.signoffs()
        XCTAssertEqual(durable.count, 1, "The signoff is durable although its acknowledgement was lost")
        let durableSignoff = try XCTUnwrap(durable.first)
        XCTAssertEqual(try value.actorRows(prepared.actorSnapshotID).count, 1)
        let actorCount = try completedWorkRowCount(ActorSnapshotRow.self, in: value.context)
        let revisionAfterLoss = try value.writer.currentRevision()

        let retried = service.record(prepared)
        guard case let .saved(receipt) = retried else {
            return XCTFail("Try again must find the existing receipt, got \(retried)")
        }
        XCTAssertEqual(receipt.snapshotID, durableSignoff.snapshotID)
        XCTAssertEqual(receipt.mutationID, durableSignoff.mutationID)
        XCTAssertEqual(try value.writer.currentRevision(), revisionAfterLoss, "Try again writes nothing")
        XCTAssertEqual(try value.signoffs(), [durableSignoff])
        XCTAssertEqual(try completedWorkRowCount(ActorSnapshotRow.self, in: value.context), actorCount)
        XCTAssertEqual(service.record(prepared), .saved(receipt))
        XCTAssertEqual(try value.writer.currentRevision(), revisionAfterLoss)
        #else
        throw XCTSkip("Acknowledgement interruption is DEBUG-only")
        #endif
    }

    @MainActor
    func testLostActorAcknowledgementRetryReusesActorAndCommitsOneSignoff() async throws {
        #if DEBUG
        let value = try await makeServiceFixture("sig1-service-lost-actor")
        defer { value.fixture.cleanUp() }
        let service = value.service
        let proof = try value.currentProof()
        let revisionBefore = try value.writer.currentRevision()
        let prepared = try service.prepare(
            submission: completedWorkSubmission(for: proof),
            expectedProof: proof
        )
        service.afterActorAppendForTesting = { throw CancellationError() }
        XCTAssertEqual(service.record(prepared), .uncertain)
        service.afterActorAppendForTesting = nil
        XCTAssertEqual(try value.actorRows(prepared.actorSnapshotID).count, 1)
        XCTAssertTrue(try value.signoffs().isEmpty)
        let actorCount = try completedWorkRowCount(ActorSnapshotRow.self, in: value.context)
        XCTAssertEqual(try value.writer.currentRevision().revision, revisionBefore.revision + 1)

        let retried = service.record(prepared)
        guard case let .saved(receipt) = retried else {
            return XCTFail("Try again must reuse the actor and save, got \(retried)")
        }
        XCTAssertEqual(
            try completedWorkRowCount(ActorSnapshotRow.self, in: value.context), actorCount,
            "The durable actor snapshot is reused, never appended twice"
        )
        let signoffs = try value.signoffs()
        XCTAssertEqual(signoffs.count, 1)
        XCTAssertEqual(signoffs.first?.snapshotID, receipt.snapshotID)
        XCTAssertEqual(signoffs.first?.roleAssertion?.actor.snapshotID, prepared.actorSnapshotID)
        XCTAssertEqual(try value.writer.currentRevision().revision, revisionBefore.revision + 2)
        #else
        throw XCTSkip("Acknowledgement interruption is DEBUG-only")
        #endif
    }

    @MainActor
    func testStaleSubjectAfterPrepareRecordsNothing() async throws {
        let value = try await makeServiceFixture("sig1-service-stale")
        defer { value.fixture.cleanUp() }
        let service = value.service
        let proof = try value.currentProof()
        let submission = completedWorkSubmission(for: proof)
        let prepared = try service.prepare(submission: submission, expectedProof: proof)
        let actorsBefore = try completedWorkRowCount(ActorSnapshotRow.self, in: value.context)

        _ = try await correctCompletedReport(
            value.report.reportID, workflow: value.workflow, note: "Correction after prepare"
        )
        let afterCorrection = try value.writer.currentRevision()

        XCTAssertEqual(service.record(prepared), .stale)
        XCTAssertEqual(prepared.attemptState, .notAttempted)
        XCTAssertNil(prepared.receipt)
        XCTAssertEqual(try value.writer.currentRevision(), afterCorrection)
        XCTAssertTrue(try value.signoffs().isEmpty)
        XCTAssertEqual(try completedWorkRowCount(ActorSnapshotRow.self, in: value.context), actorsBefore)
        XCTAssertThrowsError(try service.prepare(submission: submission, expectedProof: proof)) {
            XCTAssertEqual($0 as? CompletedWorkResponseFailureV1, .stale)
        }
        XCTAssertFalse(value.context.hasChanges)
    }

    @MainActor
    func testInvalidatedWriterForeignGenerationAndChangedContextDenyWithoutEffects() async throws {
        let value = try await makeServiceFixture("sig1-service-denied")
        defer { value.fixture.cleanUp() }
        let service = value.service
        let proof = try value.currentProof()
        let submission = completedWorkSubmission(for: proof)
        let prepared = try service.prepare(submission: submission, expectedProof: proof)
        let revisionBefore = try value.writer.currentRevision()
        let actorsBefore = try completedWorkRowCount(ActorSnapshotRow.self, in: value.context)

        // A context with unsaved changes denies before any write.
        value.context.insert(DeletionLedgerRow(
            typedID: "sig1.unsaved-context-change",
            deletedAt: Date(timeIntervalSince1970: 1_800_500_400)
        ))
        XCTAssertTrue(value.context.hasChanges)
        XCTAssertEqual(service.record(prepared), .unavailable)
        XCTAssertThrowsError(try service.completedWork())
        value.context.rollback()
        XCTAssertFalse(value.context.hasChanges)
        XCTAssertEqual(prepared.attemptState, .notAttempted)
        XCTAssertEqual(try value.writer.currentRevision(), revisionBefore)

        // A service bound to a different generation owns nothing here.
        let foreign = CompletedWorkResponseServiceV1(
            modelContext: value.context,
            writer: value.writer,
            workspaceID: value.fixture.coordinator.workspaceID,
            generationID: UUID(),
            generationRootURL: value.fixture.coordinator.generationRootURL,
            clock: SystemApplicationClock(),
            idSource: SystemApplicationIDSource(),
            signPack: .illuminatedSignV1
        )
        XCTAssertEqual(foreign.record(prepared), .unavailable, "A foreign owner never adopts the operation")
        XCTAssertThrowsError(try foreign.completedWork()) {
            XCTAssertEqual($0 as? CompletedWorkResponseFailureV1, .unavailable)
        }
        XCTAssertThrowsError(try foreign.prepare(submission: submission, expectedProof: proof)) {
            XCTAssertEqual($0 as? CompletedWorkResponseFailureV1, .unavailable)
        }
        XCTAssertEqual(try value.writer.currentRevision(), revisionBefore)

        // An invalidated writer denies without effects.
        try value.fixture.coordinator.invalidateAndReleaseWriter()
        XCTAssertEqual(service.record(prepared), .unavailable)
        XCTAssertThrowsError(try service.completedWork()) {
            XCTAssertEqual($0 as? CompletedWorkResponseFailureV1, .unavailable)
        }
        XCTAssertEqual(prepared.attemptState, .notAttempted)
        XCTAssertTrue(try value.signoffs().isEmpty)
        XCTAssertEqual(try completedWorkRowCount(ActorSnapshotRow.self, in: value.context), actorsBefore)
        XCTAssertFalse(value.context.hasChanges)
    }

    @MainActor
    func testColdReopenReadsBackIdenticalResponseAndSubjectBinding() async throws {
        let value = try await makeServiceFixture("sig1-service-cold")
        defer { value.fixture.cleanUp() }
        let service = value.service
        let proof = try value.currentProof()
        let prepared = try service.prepare(
            submission: completedWorkSubmission(for: proof),
            expectedProof: proof
        )
        guard case let .saved(receipt) = service.record(prepared) else {
            return XCTFail("Expected a saved response")
        }
        let row = try XCTUnwrap(value.context.fetch(FetchDescriptor<SignoffSnapshotRow>()).first)
        let bytes = row.canonicalData
        let history = try service.history(focusedSignoffID: receipt.snapshotID)
        let listing = try service.completedWork()

        value.fixture.presentation.receive(.sceneInactive)
        try value.fixture.coordinator.invalidateAndReleaseWriter()
        let reopened = try await reopenActualCaptureAuthority(
            support: value.fixture.support, defaults: value.fixture.defaults
        )
        guard case .ready(_, let diagnostics, _) = reopened.router.route else {
            return XCTFail("The cold launch did not publish a ready store")
        }
        let reopenedWorkflow = try makeCompletedWorkWorkflow(
            store: reopened.coordinator,
            diagnostics: diagnostics,
            access: try XCTUnwrap(reopened.presentation.renderAccess)
        )
        let reopenedService = reopenedWorkflow.completedWorkResponses
        let reopenedRows = try reopened.coordinator.modelContext.fetch(FetchDescriptor<SignoffSnapshotRow>())
        XCTAssertEqual(reopenedRows.count, 1)
        XCTAssertEqual(reopenedRows.first?.canonicalData, bytes)
        let reopenedSignoff = try XCTUnwrap(reopenedRows.first).value()
        XCTAssertEqual(reopenedSignoff.subjectID, value.report.reportID)
        XCTAssertEqual(reopenedSignoff.subjectRevision, 1)
        XCTAssertEqual(try reopenedService.history(focusedSignoffID: receipt.snapshotID), history)
        XCTAssertEqual(try reopenedService.completedWork(), listing)
        let reopenedProof = try XCTUnwrap(try reopenedService.subjectDetail(try proof.key).proof)
        XCTAssertEqual(reopenedProof.reportID, proof.reportID)
        XCTAssertEqual(reopenedProof.chainPosition, proof.chainPosition)
        XCTAssertEqual(reopenedProof.snapshotSHA256, proof.snapshotSHA256)
        XCTAssertEqual(reopenedProof.display, proof.display)
        XCTAssertEqual(
            reopenedService.record(prepared), .unavailable,
            "A prepared operation from an earlier launch is never adopted"
        )
        XCTAssertEqual(try reopened.coordinator.modelContext.fetchCount(FetchDescriptor<SignoffSnapshotRow>()), 1)
    }

    @MainActor
    func testActorPrefixResidueIsNeverPresentedAsAResponse() async throws {
        #if DEBUG
        let value = try await makeServiceFixture("sig1-service-residue")
        defer { value.fixture.cleanUp() }
        let service = value.service
        let proof = try value.currentProof()
        let actorsBefore = try completedWorkRowCount(ActorSnapshotRow.self, in: value.context)
        let abandoned = try service.prepare(
            submission: completedWorkSubmission(for: proof, typedName: "Interrupted Responder"),
            expectedProof: proof
        )
        // A crash between the two writes leaves only the actor snapshot.
        service.afterActorAppendForTesting = { throw CancellationError() }
        XCTAssertEqual(service.record(abandoned), .uncertain)
        service.afterActorAppendForTesting = nil
        XCTAssertEqual(try value.actorRows(abandoned.actorSnapshotID).count, 1)
        XCTAssertTrue(try value.signoffs().isEmpty)
        XCTAssertEqual(try service.completedWork().first?.responseCount, 0)
        XCTAssertEqual(try service.subjectDetail(try proof.key).responseCount, 0)
        XCTAssertThrowsError(try service.history(focusedSignoffID: abandoned.actorSnapshotID)) {
            XCTAssertEqual($0 as? CompletedWorkResponseFailureV1, .notFound)
        }

        let second = try service.prepare(
            submission: completedWorkSubmission(for: proof, typedName: "Second Responder"),
            expectedProof: proof
        )
        guard case let .saved(receipt) = service.record(second) else {
            return XCTFail("A new response after residue must save")
        }
        XCTAssertNotEqual(second.actorSnapshotID, abandoned.actorSnapshotID)
        let history = try service.history(focusedSignoffID: receipt.snapshotID)
        let entries = history.current + history.earlier
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.facts?.typedName, "Second Responder")
        XCTAssertFalse(entries.contains { $0.facts?.typedName == "Interrupted Responder" })
        XCTAssertEqual(try service.completedWork().first?.responseCount, 1)
        XCTAssertEqual(try completedWorkRowCount(ActorSnapshotRow.self, in: value.context), actorsBefore + 2)
        XCTAssertEqual(try value.signoffs().count, 1)
        #else
        throw XCTSkip("Write interruption is DEBUG-only")
        #endif
    }

    @MainActor
    func testExistingResponseOnCorrectedWorkStaysBoundToOriginalVersion() async throws {
        let value = try await makeServiceFixture("sig1-service-corrected")
        defer { value.fixture.cleanUp() }
        let service = value.service
        let proof = try value.currentProof()
        let submission = completedWorkSubmission(for: proof)
        let prepared = try service.prepare(submission: submission, expectedProof: proof)
        guard case let .saved(receipt) = service.record(prepared) else {
            return XCTFail("Expected a saved response on the original version")
        }
        let bytesBefore = try XCTUnwrap(value.context.fetch(FetchDescriptor<SignoffSnapshotRow>()).first)
            .canonicalData

        let correctedID = try await correctCompletedReport(
            value.report.reportID, workflow: value.workflow, note: "Correction after response"
        )
        let originalKey = try proof.key
        let correctedKey = try CompletedWorkSubjectKeyV1(
            workspaceID: value.fixture.coordinator.workspaceID,
            subjectID: correctedID,
            subjectRevision: 2
        )

        let stored = try XCTUnwrap(try value.signoffs().first)
        XCTAssertEqual(stored.subjectID, value.report.reportID)
        XCTAssertEqual(stored.subjectRevision, 1)
        XCTAssertEqual(
            try value.context.fetch(FetchDescriptor<SignoffSnapshotRow>()).first?.canonicalData,
            bytesBefore
        )
        let history = try service.history(focusedSignoffID: receipt.snapshotID)
        XCTAssertEqual(history.subject?.version, 1)
        XCTAssertTrue(history.current.isEmpty)
        XCTAssertEqual(history.earlier.count, 1)
        XCTAssertEqual(history.earlier.first?.version, 1)
        XCTAssertEqual(history.earlier.first?.facts?.typedName, "Casey Responder")

        let listing = try service.completedWork()
        XCTAssertEqual(listing.map(\.key), [correctedKey])
        XCTAssertEqual(listing.first?.responseCount, 0)
        let originalDetail = try service.subjectDetail(originalKey)
        XCTAssertEqual(originalDetail.eligibility, .superseded)
        XCTAssertEqual(originalDetail.responseCount, 1)
        XCTAssertThrowsError(try service.prepare(submission: submission, expectedProof: proof)) {
            XCTAssertEqual($0 as? CompletedWorkResponseFailureV1, .stale)
        }

        let tipProof = try XCTUnwrap(try service.subjectDetail(correctedKey).proof)
        let tipPrepared = try service.prepare(
            submission: completedWorkSubmission(for: tipProof, typedName: "Tip Responder"),
            expectedProof: tipProof
        )
        guard case let .saved(tipReceipt) = service.record(tipPrepared) else {
            return XCTFail("Expected a saved response on the current version")
        }
        let tipHistory = try service.history(focusedSignoffID: tipReceipt.snapshotID)
        XCTAssertEqual(tipHistory.subject?.version, 2)
        XCTAssertEqual(tipHistory.current.map { $0.facts?.typedName }, ["Tip Responder"])
        XCTAssertEqual(tipHistory.earlier.map { $0.facts?.typedName }, ["Casey Responder"])
        XCTAssertEqual(tipHistory.current.first?.version, 2)
        XCTAssertEqual(try value.signoffs().count, 2)
    }
}

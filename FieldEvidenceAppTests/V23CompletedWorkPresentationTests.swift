import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

/// Presentation-level SIG-1 coverage over the real production service. The
/// operations mirror the shell's composition: every service call runs inside
/// the published content-access read; the history transition is recorded.
final class V23CompletedWorkPresentationTests: V23ProductionFourRootShellTestSupport {
    @MainActor
    private func makePresentation(
        service: CompletedWorkResponseServiceV1,
        access: AppAccessPresentationV1.ContentAccess,
        openedHistory: @escaping CompletedWorkOpenHistoryOperationV1
    ) -> CompletedWorkPresentationV1 {
        let list: CompletedWorkListOperationV1 = {
            try access.withRead { try service.completedWork() }
        }
        let detail: CompletedWorkDetailOperationV1 = { key in
            try access.withRead { try service.subjectDetail(key) }
        }
        let prepare: CompletedWorkPrepareOperationV1 = { submission, proof in
            try access.withRead {
                try service.prepare(submission: submission, expectedProof: proof)
            }
        }
        let record: CompletedWorkRecordOperationV1 = { prepared in
            try access.withRead { service.record(prepared) }
        }
        return CompletedWorkPresentationV1(operations: CompletedWorkPresentationV1.Operations(
            list: list, detail: detail, prepare: prepare, record: record,
            openHistory: openedHistory
        ))
    }

    @MainActor
    private func listing(
        _ key: CompletedWorkSubjectKeyV1,
        in presentation: CompletedWorkPresentationV1
    ) throws -> CompletedWorkSubjectListingV1 {
        guard case let .loaded(items) = presentation.list,
              let item = items.first(where: { $0.key == key }) else {
            throw CompletedWorkResponseFailureV1.notFound
        }
        return item
    }

    @MainActor
    func testUncertainTryAgainRetainsOperationPerSubjectAndReopensInTryAgainMode() async throws {
        #if DEBUG
        let fixture = try await makeFixture("sig1-presentation-retry")
        defer { fixture.cleanUp() }
        let first = try await makeReadyReport(in: fixture, label: "sig1-presentation-a")
        let second = try await makeReadyReport(in: fixture, label: "sig1-presentation-b")
        let workflow = try makeCompletedWorkWorkflow(in: fixture)
        let service = workflow.completedWorkResponses
        let access = try XCTUnwrap(fixture.presentation.renderAccess)
        let writer = fixture.coordinator.workspaceWriter
        let context = fixture.coordinator.modelContext
        var openedHistory: [SignoffHistoryRouteV1] = []
        let presentation = makePresentation(service: service, access: access) { route in
            openedHistory.append(route)
        }
        let keyA = try completedWorkKey(first.reportID, revision: 1, in: fixture)
        let keyB = try completedWorkKey(second.reportID, revision: 1, in: fixture)
        presentation.refresh()

        // Subject A: the signoff is durable but its acknowledgement is lost.
        presentation.open(try listing(keyA, in: presentation))
        presentation.requestRecord()
        let routeA = try XCTUnwrap(presentation.editorRoute)
        XCTAssertFalse(routeA.resumesRetainedAttempt)
        service.afterSignoffCommitForTesting = { throw CancellationError() }
        let alpha = SignoffEnrollmentSubmissionV1(route: routeA.metadata,
            typedName: "Alpha Responder", claimedRole: "Site manager", claimedRelationship: .client)
        XCTAssertEqual(presentation.submit(alpha), .uncertain)
        service.afterSignoffCommitForTesting = nil
        XCTAssertEqual(presentation.lastResult, .uncertain)
        let retainedA = try XCTUnwrap(presentation.retainedOperation(for: keyA))
        XCTAssertEqual(retainedA.attemptState, .canonicalWriteAttempted)
        XCTAssertEqual(try completedWorkRowCount(SignoffSnapshotRow.self, in: context), 1)
        XCTAssertTrue(openedHistory.isEmpty)

        // Cancel keeps the retained attempt and reloads the detail.
        presentation.cancelEditor()
        XCTAssertNil(presentation.editorRoute)
        XCTAssertEqual(presentation.detailRoute, keyA)
        guard case let .loaded(reloadedA) = presentation.detail else {
            return XCTFail("Cancel reloads the detail")
        }
        XCTAssertEqual(reloadedA.responseCount, 1, "The durable response is already counted")
        XCTAssertTrue(presentation.retainedOperation(for: keyA) === retainedA)

        // Reopening A resumes the retained attempt in Try-again mode with its
        // own entries; Record cannot substitute different entries.
        presentation.requestRecord()
        let reopenedA = try XCTUnwrap(presentation.editorRoute)
        XCTAssertTrue(reopenedA.resumesRetainedAttempt)
        XCTAssertEqual(presentation.lastResult, .uncertain)
        XCTAssertEqual(presentation.draft, CompletedWorkResponseDraftV1(
            typedName: "Alpha Responder", claimedRole: "Site manager", claimedRelationship: .client))
        let beforeSubstitution = try writer.currentRevision()
        let changed = SignoffEnrollmentSubmissionV1(route: reopenedA.metadata,
            typedName: "Changed Responder", claimedRole: "Changed role")
        XCTAssertEqual(presentation.submit(changed), .uncertain, "No silent substitution")
        XCTAssertEqual(try writer.currentRevision(), beforeSubstitution)
        XCTAssertTrue(presentation.retainedOperation(for: keyA) === retainedA)
        presentation.cancelEditor()

        // Subject B never inherits A's operation or entries.
        presentation.open(try listing(keyB, in: presentation))
        presentation.requestRecord()
        let routeB = try XCTUnwrap(presentation.editorRoute)
        XCTAssertFalse(routeB.resumesRetainedAttempt)
        XCTAssertNil(presentation.draft, "A's entries never prefill B's editor")
        XCTAssertNil(presentation.retainedOperation(for: keyB))
        let bravo = SignoffEnrollmentSubmissionV1(route: routeB.metadata,
            typedName: "Bravo Responder", claimedRole: "Owner representative")
        XCTAssertEqual(presentation.submit(bravo), .saved)
        XCTAssertTrue(presentation.retainedOperation(for: keyA) === retainedA,
            "Recording B never replaces A's retained attempt")
        XCTAssertEqual(openedHistory.count, 1)
        XCTAssertEqual(try completedWorkRowCount(SignoffSnapshotRow.self, in: context), 2)

        // Back on A, Try again finds the durable receipt and writes nothing.
        presentation.open(try listing(keyA, in: presentation))
        presentation.requestRecord()
        XCTAssertEqual(presentation.editorRoute?.resumesRetainedAttempt, true)
        let beforeRetry = try writer.currentRevision()
        XCTAssertEqual(presentation.retry(), .saved)
        XCTAssertEqual(try writer.currentRevision(), beforeRetry, "Try again never writes twice")
        XCTAssertNil(presentation.retainedOperation(for: keyA))
        XCTAssertNil(presentation.editorRoute)
        XCTAssertNil(presentation.detailRoute)
        XCTAssertEqual(presentation.lastResult, .saved)
        XCTAssertEqual(try completedWorkRowCount(SignoffSnapshotRow.self, in: context), 2)
        let alphaRow = try XCTUnwrap(context.fetch(FetchDescriptor<SignoffSnapshotRow>())
            .map { try $0.value() }
            .first { $0.subjectID == first.reportID })
        XCTAssertEqual(alphaRow.roleAssertion?.actor.displayNameAtTime, "Alpha Responder")
        XCTAssertEqual(openedHistory.count, 2)
        XCTAssertEqual(openedHistory.last?.signoffID, alphaRow.snapshotID)
        XCTAssertEqual(openedHistory.last?.workspaceID, fixture.coordinator.workspaceID)
        XCTAssertEqual(try listing(keyA, in: presentation).responseCount, 1)
        XCTAssertEqual(try listing(keyB, in: presentation).responseCount, 1)
        XCTAssertFalse(context.hasChanges)
        #else
        throw XCTSkip("Acknowledgement interruption is DEBUG-only")
        #endif
    }

    @MainActor
    func testRetryWithoutRetainedOperationAndStaleResultReloadDetailWithoutEffects() async throws {
        let fixture = try await makeFixture("sig1-presentation-stale")
        defer { fixture.cleanUp() }
        let report = try await makeReadyReport(in: fixture, label: "sig1-presentation-stale")
        let workflow = try makeCompletedWorkWorkflow(in: fixture)
        let service = workflow.completedWorkResponses
        let access = try XCTUnwrap(fixture.presentation.renderAccess)
        let writer = fixture.coordinator.workspaceWriter
        let context = fixture.coordinator.modelContext
        var openedHistory: [SignoffHistoryRouteV1] = []
        let presentation = makePresentation(service: service, access: access) { route in
            openedHistory.append(route)
        }
        let key = try completedWorkKey(report.reportID, revision: 1, in: fixture)
        presentation.refresh()
        presentation.open(try listing(key, in: presentation))
        presentation.requestRecord()
        XCTAssertNotNil(presentation.editorRoute)
        XCTAssertEqual(presentation.retry(), .unavailable, "Try again needs a retained attempt")
        let route = try XCTUnwrap(presentation.editorRoute)

        _ = try await correctCompletedReport(report.reportID, workflow: workflow,
            note: "Correction while the presentation editor is open")
        let afterCorrection = try writer.currentRevision()
        let entries = SignoffEnrollmentSubmissionV1(route: route.metadata,
            typedName: "Stale Responder", claimedRole: "Site contact")
        XCTAssertEqual(presentation.submit(entries), .stale)
        XCTAssertNotNil(presentation.editorRoute, "The editor stays open with its entries")
        XCTAssertEqual(presentation.draft?.typedName, "Stale Responder")
        XCTAssertNil(presentation.retainedOperation(for: key))
        guard case let .loaded(reloaded) = presentation.detail else {
            return XCTFail("A stale result reloads the detail")
        }
        XCTAssertEqual(reloaded.eligibility, .superseded)
        presentation.cancelEditor()
        presentation.requestRecord()
        XCTAssertNil(presentation.editorRoute, "A superseded subject never reopens the editor")
        XCTAssertEqual(try writer.currentRevision(), afterCorrection)
        XCTAssertEqual(try completedWorkRowCount(SignoffSnapshotRow.self, in: context), 0)
        XCTAssertTrue(openedHistory.isEmpty)
        XCTAssertFalse(context.hasChanges)
    }
}

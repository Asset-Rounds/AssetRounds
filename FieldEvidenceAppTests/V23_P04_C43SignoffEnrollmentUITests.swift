import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

final class V23_P04_C43SignoffEnrollmentUITests: V23ProductionFourRootShellTestSupport {
    @MainActor
    func testV23P04C43JourneyIdentifiersAreClosedAndOrdered() {
        let journey = [
            SignoffEnrollmentView.workRootAccessibilityIdentifier,
            SignoffEnrollmentView.immutableDetailAccessibilityIdentifier,
            SignoffEnrollmentView.moreAccessibilityIdentifier,
            SignoffEnrollmentView.recordResponseAccessibilityIdentifier,
            SignoffEnrollmentView.editorAccessibilityIdentifier,
            SignoffEnrollmentView.historyAccessibilityIdentifier
        ]
        XCTAssertEqual(journey, [
            "v23.p04.c43.signoff-enrollment.work-root",
            "v23.p04.c43.signoff-enrollment.immutable-work-detail",
            "v23.p04.c43.signoff-enrollment.more",
            "v23.p04.c43.signoff-enrollment.record-approval-response",
            "v23.p04.c43.signoff-enrollment.editor",
            "v23.p04.c43.signoff-enrollment.history"
        ])
        XCTAssertEqual(Set(journey).count, journey.count)
        let finalViewIdentifiers = [
            SignoffEnrollmentView.screenAccessibilityIdentifier,
            SignoffEnrollmentView.disclosureAccessibilityIdentifier,
            SignoffEnrollmentView.typedNameAccessibilityIdentifier,
            SignoffEnrollmentView.confirmAccessibilityIdentifier
        ]
        XCTAssertEqual(finalViewIdentifiers, [
            "v23.p04.c43.signoff-enrollment.screen",
            "v23.p04.c43.signoff-enrollment.disclosure",
            "v23.p04.c43.signoff-enrollment.typed-name",
            "v23.p04.c43.signoff-enrollment.confirm"
        ])
        XCTAssertTrue((journey + finalViewIdentifiers).allSatisfy {
            $0.hasPrefix("v23.p04.c43.signoff-enrollment.") && $0 == $0.lowercased()
        })
    }

    @MainActor
    func testV23P04C43RequiresVisibleWorkJourneyBeforeLaunchAdoption() async throws {
        #if DEBUG
        let fixture = try await makeFixture("c43-visible-work-response-journey")
        defer { fixture.cleanUp() }
        let report = try await makeReadyReport(in: fixture, label: "c43-visible-response")
        let key = try completedWorkKey(report.reportID, revision: 1, in: fixture)
        let context = fixture.coordinator.modelContext
        let writer = fixture.coordinator.workspaceWriter
        let sceneAccess = try XCTUnwrap(fixture.presentation.sceneNavigationAccess)
        try selectWorkBeforeLaunch(fixture)

        var captured: CompletedWorkPresentationV1?
        let previousObserver = CompletedWorkPresentationV1.didCreateForTesting
        CompletedWorkPresentationV1.didCreateForTesting = { value in
            if captured == nil { captured = value }
        }
        defer { CompletedWorkPresentationV1.didCreateForTesting = previousObserver }
        var shellScene: AppShellSceneStateV1?
        let mounted = try mountCompletedWorkShell(store: fixture.coordinator,
            presentation: fixture.presentation, diagnostics: fixture.diagnostics,
            router: fixture.router) { scene in
            if shellScene == nil { shellScene = scene }
        }
        defer { mounted.unmount() }

        let revisionBefore = try writer.currentRevision()
        let receiptsBefore = try completedWorkRowCount(MutationReceiptRow.self, in: context)
        let actorsBefore = try completedWorkRowCount(ActorSnapshotRow.self, in: context)
        let signoffsBefore = try completedWorkRowCount(SignoffSnapshotRow.self, in: context)
        let reportsBefore = try completedWorkRowCount(Report.self, in: context)
        let recordsBefore = try c43WorkflowRecordFacts(in: context)
        let packetsBefore = try c43PacketFacts(in: context)
        XCTAssertFalse(context.hasChanges)

        // This existing helper requires the real Work/Completed/detail/More
        // observations and invokes the exact row/menu production callbacks.
        // Its known More visibility failure remains a failure of this test.
        let presentation = try await driveCompletedWorkToEditor(key: key,
            host: mounted.host) { captured }
        XCTAssertEqual(try writer.currentRevision(), revisionBefore,
            "Opening detail and its editor makes no canonical write")
        XCTAssertEqual(try completedWorkRowCount(MutationReceiptRow.self, in: context), receiptsBefore)
        XCTAssertEqual(try completedWorkRowCount(ActorSnapshotRow.self, in: context), actorsBefore)
        XCTAssertEqual(try completedWorkRowCount(SignoffSnapshotRow.self, in: context), signoffsBefore)
        XCTAssertEqual(try completedWorkRowCount(Report.self, in: context), reportsBefore)
        XCTAssertEqual(try c43WorkflowRecordFacts(in: context), recordsBefore)
        XCTAssertEqual(try c43PacketFacts(in: context), packetsBefore)
        XCTAssertFalse(context.hasChanges)

        let route = try XCTUnwrap(presentation.editorRoute)
        XCTAssertEqual(route.metadata.subject.versionText, "Version 1")
        XCTAssertFalse(route.resumesRetainedAttempt)
        let submission = SignoffEnrollmentSubmissionV1(route: route.metadata,
            typedName: "Jordan Hosted", claimedRole: "Facilities lead",
            claimedRelationship: .client)
        XCTAssertEqual(presentation.submit(submission), .saved)
        XCTAssertEqual(presentation.lastResult, .saved)
        XCTAssertNil(presentation.editorRoute)
        XCTAssertNil(presentation.detailRoute)

        let signoffs = try context.fetch(FetchDescriptor<SignoffSnapshotRow>())
            .map { try $0.value() }
        XCTAssertEqual(signoffs.count, signoffsBefore + 1)
        let signoff = try XCTUnwrap(signoffs.first { $0.subjectID == report.reportID })
        XCTAssertEqual(signoff.workspaceID, fixture.coordinator.workspaceID)
        XCTAssertEqual(signoff.subjectID, report.reportID)
        XCTAssertEqual(signoff.subjectRevision, key.subjectRevision)
        XCTAssertEqual(signoff.purpose, "WORK_DETAIL_COMPLETED_RESPONSE_V1")
        XCTAssertEqual(signoff.method, .typedLocalAssertion)
        XCTAssertEqual(signoff.disposition, .recordedLocalAssertion)
        XCTAssertNil(signoff.supersedesSnapshotID)
        let assertion = try XCTUnwrap(signoff.roleAssertion)
        XCTAssertEqual(assertion.actor.responsibility, .acknowledgedBy)
        XCTAssertNotEqual(assertion.actor.responsibility, .approvedBy)
        XCTAssertEqual(assertion.actor.displayNameAtTime, "Jordan Hosted")
        XCTAssertNil(assertion.actor.actor.partyID)
        XCTAssertEqual(assertion.claimedRole, "Facilities lead")
        XCTAssertEqual(assertion.claimedRelationship, .client)
        XCTAssertEqual(assertion.disclosureRelease.disclosureText,
            SignoffEnrollmentDisclosureV1.disclosureText)
        let actorRow = try XCTUnwrap(try context.fetch(FetchDescriptor<ActorSnapshotRow>())
            .first { $0.snapshotID == assertion.actor.snapshotID })
        XCTAssertEqual(try actorRow.value(), assertion.actor)
        try C43SignoffEnrollmentBoundaryV1.validate(signoff)
        let receipt = try XCTUnwrap(try writer.durableReceipt(mutationID: signoff.mutationID))
        try receipt.validate()
        XCTAssertEqual(receipt.mutationID, signoff.mutationID)
        XCTAssertEqual(receipt.identity.workspaceID, signoff.workspaceID)
        XCTAssertEqual(receipt.resultingRevision.workspaceRevision, revisionBefore.revision + 2)

        XCTAssertEqual(try writer.currentRevision().revision, revisionBefore.revision + 2)
        XCTAssertEqual(try completedWorkRowCount(MutationReceiptRow.self, in: context),
            receiptsBefore + 2)
        XCTAssertEqual(try completedWorkRowCount(ActorSnapshotRow.self, in: context), actorsBefore + 1)
        XCTAssertEqual(try completedWorkRowCount(Report.self, in: context), reportsBefore)
        XCTAssertEqual(try c43WorkflowRecordFacts(in: context), recordsBefore)
        XCTAssertEqual(try c43PacketFacts(in: context), packetsBefore)
        XCTAssertFalse(context.hasChanges)

        let historyTarget = try SignoffHistoryRouteV1(
            workspaceID: fixture.coordinator.workspaceID,
            signoffID: signoff.snapshotID).reportsTarget
        let scene = try XCTUnwrap(shellScene)
        XCTAssertEqual(scene.snapshot?.selectedRoot, .reports)
        XCTAssertEqual(scene.snapshot?.path(for: .reports)?.targets, [historyTarget])
        XCTAssertEqual(scene.snapshot?.path(for: .work)?.targets, [],
            "Detail and editor are local pushes, never saved Work routes")
        let historyMounted = await waitForMountedScreen(
            SignoffEnrollmentView.historyAccessibilityIdentifier, from: mounted.host)
        XCTAssertTrue(historyMounted, "The shell opens focused response history on Reports")
        let persisted = await waitUntilCompletedWork {
            guard let loaded = try? sceneAccess.load(),
                  case let .restored(snapshot) = loaded else { return false }
            return snapshot.selectedRoot == .reports
                && snapshot.path(for: .reports)?.targets == [historyTarget]
        }
        XCTAssertTrue(persisted, "The exact focused Reports route is persisted")
        XCTAssertFalse(containsAccessibilityIdentifier(
            identifiedBy: SignoffEnrollmentView.confirmAccessibilityIdentifier,
            in: mounted.host.view))

        let workflow = try makeCompletedWorkWorkflow(in: fixture)
        let history = try workflow.completedWorkResponses.history(
            focusedSignoffID: signoff.snapshotID)
        XCTAssertNil(history.unavailableReason)
        XCTAssertTrue(history.earlier.isEmpty)
        XCTAssertEqual(history.current.count, 1)
        XCTAssertTrue(try XCTUnwrap(history.current.first).isFocused)
        XCTAssertEqual(history.current.first?.facts?.typedName, "Jordan Hosted")
        XCTAssertEqual(history.current.first?.facts?.claimedRole, "Facilities lead")
        XCTAssertEqual(history.current.first?.facts?.relationshipText, "Client")
        XCTAssertEqual(history.current.first?.facts?.methodText, "Typed response")
        XCTAssertEqual(history.current.first?.facts?.disclosureText,
            SignoffEnrollmentDisclosureV1.disclosureText)
        XCTAssertEqual(history.subject?.versionText, "Version 1")
        XCTAssertEqual(try writer.currentRevision().revision, revisionBefore.revision + 2)
        XCTAssertFalse(context.hasChanges)
        #else
        throw XCTSkip("Native hosted Work response journey observation is DEBUG-only")
        #endif
    }

    @MainActor
    private func c43WorkflowRecordFacts(in context: ModelContext) throws -> [String] {
        try context.fetch(FetchDescriptor<WorkflowRecord>()).map { record in
            "\(record.id.uuidString)|\(record.state)|\(record.stage)|\(record.revisionKind)|"
                + "\(record.completedAt?.timeIntervalSince1970 ?? -1)"
        }.sorted()
    }

    @MainActor
    private func c43PacketFacts(in context: ModelContext) throws -> [String] {
        try context.fetch(FetchDescriptor<Packet>()).map { packet in
            "\(packet.id.uuidString)|\(packet.currentRecordID?.uuidString ?? "nil")|"
                + "\(packet.contentDeletedAt?.timeIntervalSince1970 ?? -1)"
        }.sorted()
    }
}

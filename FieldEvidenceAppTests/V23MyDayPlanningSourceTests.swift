import Foundation
import SwiftData
import XCTest

@testable import FieldEvidenceApp

final class V23MyDayPlanningSourceTests: XCTestCase {
    private let instant = Date(timeIntervalSince1970: 1_800_300_000)

    @MainActor
    func testAllPreexistingDraftPurposesRemainSelectableThroughProductionAccess() async throws {
        let fixture = try await V23ProductionMyDayPresentationHarness.start(
            testCase: self, name: "planning-source-existing-purposes")
        defer { fixture.cleanUp() }
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let coordinator = fixture.coordinator
        let purposes: [DraftPurposeV1] = [.inspectionReview, .workPacket,
            .correctiveAction, .requirementEvaluation, .evidenceCuration,
            .assetFieldEdit, .serviceRequest]
        let checkpoints = try purposes.map {
            try ordinaryCheckpoint(workspaceID: coordinator.workspaceID, purpose: $0)
        }
        for checkpoint in checkpoints {
            coordinator.modelContext.insert(try FieldDraftCheckpointRow(checkpoint))
        }
        try coordinator.modelContext.save()
        let beforeRevision = try coordinator.workspaceWriter.currentRevision()
        let snapshot = try await access.snapshot(evaluatedAt: instant)

        XCTAssertEqual(snapshot.sources.count, 7)
        XCTAssertEqual(snapshot.eligibleReferences.count, 7)
        for checkpoint in checkpoints {
            let expected = reference(checkpoint)
            let source = try XCTUnwrap(snapshot.sources.first { $0.reference == expected })
            XCTAssertEqual(source.state, .draft)
            XCTAssertTrue(source.isSelectable)
            XCTAssertTrue(snapshot.eligibleReferences.contains(expected))
        }
        XCTAssertEqual(try coordinator.workspaceWriter.currentRevision(), beforeRevision)
        XCTAssertEqual(try coordinator.modelContext.fetchCount(FetchDescriptor<FieldDraftCheckpointRow>()), 7)
        XCTAssertEqual(try coordinator.modelContext.fetchCount(FetchDescriptor<MyDayPlanRowV1>()), 0)
        XCTAssertFalse(coordinator.modelContext.hasChanges)
    }

    @MainActor
    func testPlanningDraftsAreExcludedButRemainHashBoundAndReconcileAsMissing() async throws {
        let fixture = try await V23ProductionMyDayPresentationHarness.start(
            testCase: self, name: "planning-source-exclusion")
        defer { fixture.cleanUp() }
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let coordinator = fixture.coordinator
        let ordinary = try ordinaryCheckpoint(workspaceID: coordinator.workspaceID, purpose: .assetFieldEdit)
        coordinator.modelContext.insert(try FieldDraftCheckpointRow(ordinary))
        try coordinator.modelContext.save()
        let beforeRevision = try coordinator.workspaceWriter.currentRevision()
        let before = try await access.snapshot(evaluatedAt: instant)

        let planning = try planningCheckpoint(workspaceID: coordinator.workspaceID)
        try MyDayPlanningDraftCodecV1.validateCheckpointPayload(planning)
        let planningRow = try FieldDraftCheckpointRow(planning)
        coordinator.modelContext.insert(planningRow)
        try coordinator.modelContext.save()
        let retainedReference = reference(planning)
        let plan = try MyDayPlanV1(planID: UUID(), key: key(workspaceID: coordinator.workspaceID),
            items: [.init(membershipID: UUID(), reference: retainedReference, manualOrder: 0)],
            predecessor: nil, revision: 1, mutationID: MutationIDV1(rawValue: UUID()),
            authoredBy: actor(workspaceID: coordinator.workspaceID), authoredAt: instant)
        let after = try await access.snapshot(for: plan, evaluatedAt: instant)

        XCTAssertEqual(after.sources.map(\.reference), [reference(ordinary)])
        XCTAssertEqual(after.eligibleReferences, [reference(ordinary)])
        XCTAssertNotEqual(after.sourceClosureSHA256, before.sourceClosureSHA256)
        let frontier = try XCTUnwrap(after.frontiers.first)
        XCTAssertEqual(after.frontiers.count, 1)
        XCTAssertEqual(frontier.plannedReference, retainedReference)
        XCTAssertNil(frontier.currentReference)
        XCTAssertEqual(frontier.state, .missing)
        XCTAssertEqual(frontier.readiness, .unavailable)

        let revised = try FieldDraftCheckpointV1(draftID: planning.draftID,
            workspaceID: planning.workspaceID, scope: planning.scope, purpose: planning.purpose,
            codec: planning.codec, baseCanonicalRevision: 0, draftRevision: 2,
            payloadData: planning.payloadData, stageIDs: [], resumeAnchor: planning.resumeAnchor,
            state: .active, updatedAt: instant.addingTimeInterval(1),
            mutationID: MutationIDV1(rawValue: UUID()))
        try planningRow.replace(with: revised, expectedRevision: 1)
        try coordinator.modelContext.save()
        let afterRevision = try await access.snapshot(for: plan, evaluatedAt: instant)
        XCTAssertEqual(afterRevision.sources.map(\.reference), after.sources.map(\.reference))
        XCTAssertNotEqual(afterRevision.sourceClosureSHA256, after.sourceClosureSHA256)
        XCTAssertEqual(afterRevision.frontiers.first?.state, .missing)
        XCTAssertEqual(try coordinator.workspaceWriter.currentRevision(), beforeRevision)
        XCTAssertEqual(try coordinator.modelContext.fetchCount(FetchDescriptor<FieldDraftCheckpointRow>()), 2)
        XCTAssertEqual(try coordinator.modelContext.fetchCount(FetchDescriptor<MyDayPlanRowV1>()), 0)
        XCTAssertFalse(coordinator.modelContext.hasChanges)
    }

    @MainActor
    func testExcludedPlanningPayloadStillMustValidateBeforeSourcePublication() async throws {
        let fixture = try await V23ProductionMyDayPresentationHarness.start(
            testCase: self, name: "planning-source-invalid-payload")
        defer { fixture.cleanUp() }
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        let coordinator = fixture.coordinator
        let malformed = try planningCheckpoint(workspaceID: coordinator.workspaceID,
            payloadData: Data("{\"schemaVersion\":1}".utf8))
        let row = try FieldDraftCheckpointRow(malformed)
        // The generic envelope is valid: exclusion must not hide a payload that
        // fails the actual My Day codec's closed grammar.
        XCTAssertEqual(try row.value(), malformed)
        XCTAssertThrowsError(try MyDayPlanningDraftCodecV1.validateCheckpointPayload(malformed))
        coordinator.modelContext.insert(row)
        try coordinator.modelContext.save()
        let beforeRevision = try coordinator.workspaceWriter.currentRevision()

        do {
            _ = try await access.snapshot(evaluatedAt: instant)
            XCTFail("A malformed excluded planning payload must not produce a source snapshot")
        } catch {
            XCTAssertFalse(error is CancellationError)
        }
        XCTAssertEqual(try coordinator.workspaceWriter.currentRevision(), beforeRevision)
        XCTAssertEqual(try row.value(), malformed)
        XCTAssertFalse(coordinator.modelContext.hasChanges)
    }

    private func key(workspaceID: WorkspaceID) throws -> MyDayKeyV1 {
        try .init(workspaceID: workspaceID, civilDate: .init(year: 2026, month: 9, day: 12),
                  ianaTimeZoneIdentifier: "America/New_York")
    }

    private func actor(workspaceID: WorkspaceID) throws -> ActorSnapshotV1 {
        let actor = try LocalActorReferenceV1(actorReferenceID: UUID(), workspaceID: workspaceID,
                                             partyID: nil, displayName: "Source test recorder")
        return try .init(snapshotID: UUID(), workspaceID: workspaceID, actor: actor,
            responsibility: .recordedBy, displayNameAtTime: actor.displayName, capturedAt: instant)
    }

    private func planningCheckpoint(workspaceID: WorkspaceID,
                                    payloadData: Data? = nil) throws -> FieldDraftCheckpointV1 {
        let key = try key(workspaceID: workspaceID)
        let payload = try MyDayPlanningDraftPayloadV1(
            editing: .init(key: key, recordedBy: actor(workspaceID: workspaceID),
                keyWasExplicitlyConfirmed: true, recordedByWasExplicitlySelectedOrCaptured: true),
            intent: .plan(draft: .init(key: key, items: [], eligibleReferences: []), predecessor: nil))
        return try FieldDraftCheckpointV1(draftID: UUID(), workspaceID: workspaceID,
            scope: MyDayPlanningDraftCodecV1.scope(for: key), purpose: .myDayPlanning,
            codec: MyDayPlanningDraftCodecV1.release(), baseCanonicalRevision: 0, draftRevision: 1,
            payloadData: payloadData ?? MyDayPlanningDraftCodecV1.encode(payload), stageIDs: [],
            resumeAnchor: .init(sectionID: "planning"), state: .active, updatedAt: instant,
            mutationID: MutationIDV1(rawValue: UUID()))
    }

    private func reference(_ checkpoint: FieldDraftCheckpointV1) -> MyDayEligibleReferenceV1 {
        .resumableDraft(workspaceID: checkpoint.workspaceID, draftID: checkpoint.draftID,
            revision: checkpoint.draftRevision, checkpointSHA256: checkpoint.checkpointSHA256,
            anchor: checkpoint.resumeAnchor)
    }

    /// These are explicit test-only payload definitions for the already supported
    /// source purposes. They never stand in for a production purpose registry.
    private func ordinaryCheckpoint(workspaceID: WorkspaceID,
                                    purpose: DraftPurposeV1) throws -> FieldDraftCheckpointV1 {
        try FieldDraftCheckpointV1(draftID: UUID(), workspaceID: workspaceID,
            scope: .init(scopeKind: "V23_MY_DAY_SOURCE_TEST", stableComponentIDs: [purpose.rawValue]),
            purpose: purpose,
            codec: .init(codecID: "v23.source-test.\(purpose.rawValue.lowercased())", codecVersion: 1,
                releaseSHA256: FieldDraftCanonicalCodecV1.sha256(Data(purpose.rawValue.utf8))),
            baseCanonicalRevision: 0, draftRevision: 1, payloadData: Data(purpose.rawValue.utf8),
            stageIDs: [], resumeAnchor: .init(sectionID: "source-test"), state: .active,
            updatedAt: instant, mutationID: MutationIDV1(rawValue: UUID()))
    }
}

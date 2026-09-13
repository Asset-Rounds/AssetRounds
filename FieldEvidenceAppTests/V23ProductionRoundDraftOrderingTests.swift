import Combine
import Foundation
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import FieldEvidenceApp

final class V23ProductionRoundDraftOrderingTests: V23ProductionFourRootShellTestSupport {
    @MainActor
    func testActualDraftOrderingExecutionSwapsExactlyOneAdjacentPairWithFreshRecorder() async throws {
        let fixture = try await makeFixture("round-order-execution")
        defer { fixture.cleanUp() }
        let seed = try await V23RoundRouteHarness.make(in: fixture, label: "execution")
        let context = try await seed.addingDraftItems(2)
        let target = try context.target(for: context.round)
        try context.work.scene.open(target)
        let state = ProductionRoundSessionPresentationV1(target: target,
            scene: context.work.scene, access: context.access)
        await state.refresh()
        let before = try context.work.store.workspaceWriter.currentRevision()
        let original = context.round
        let moving = original.items[1]
        state.requestDraftReorder(itemID: moving.itemID, delta: -1)
        let didOrder = await state.confirmDraftReorder(recordedByName: "Draft ordering recorder")
        XCTAssertTrue(didOrder)
        let current = try XCTUnwrap(state.session)
        XCTAssertEqual(current.revision, original.revision + 1)
        XCTAssertEqual(current.transition, .reviseSelection)
        XCTAssertEqual(current.items.map(\.itemID), [original.items[1].itemID, original.items[0].itemID, original.items[2].itemID])
        XCTAssertEqual(current.items.map(\.selection), [original.items[1].selection, original.items[0].selection, original.items[2].selection])
        XCTAssertEqual(current.items.map(\.requirement), [original.items[1].requirement, original.items[0].requirement, original.items[2].requirement])
        XCTAssertEqual(current.items.map(\.disposition), [original.items[1].disposition, original.items[0].disposition, original.items[2].disposition])
        XCTAssertEqual(current.items.map(\.order), [0, 1, 2])
        XCTAssertEqual(current.recordedBy.displayNameAtTime, "Draft ordering recorder")
        XCTAssertNotEqual(current.recordedBy.snapshotID, original.recordedBy.snapshotID)
        XCTAssertNotEqual(current.recordedBy.actor.actorReferenceID, original.recordedBy.actor.actorReferenceID)
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision().revision,
                       before.revision + 1)
        XCTAssertNil(state.orderingIntent)
        XCTAssertNil(state.pendingReorder)
        XCTAssertFalse(state.couldNotOrder)
        XCTAssertFalse(context.work.store.modelContext.hasChanges)
    }

    @MainActor
    func testActualDraftOrderingLostAcknowledgementRetriesSamePreparedWriteWithoutSecondEffect() async throws {
        #if DEBUG
        let fixture = try await makeFixture("round-order-retry")
        defer { fixture.cleanUp() }
        let seed = try await V23RoundRouteHarness.make(in: fixture, label: "retry")
        let context = try await seed.addingDraftItems(1)
        let target = try context.target(for: context.round)
        try context.work.scene.open(target)
        let state = ProductionRoundSessionPresentationV1(target: target,
            scene: context.work.scene, access: context.access)
        await state.refresh()
        let original = context.round
        state.requestDraftReorder(itemID: original.items[0].itemID, delta: 1)
        var interrupted = false
        context.access.setAfterDraftReorderReceiptForTesting {
            interrupted = true
            throw CancellationError()
        }
        let didLoseAcknowledgement = await state.confirmDraftReorder(recordedByName: "Retry recorder")
        XCTAssertFalse(didLoseAcknowledgement)
        XCTAssertTrue(interrupted)
        let afterEffect = try context.work.store.workspaceWriter.currentRevision()
        XCTAssertTrue(state.hasUnacknowledgedReorder)
        let retained = try XCTUnwrap(state.pendingReorder)
        XCTAssertEqual(state.session, original)
        XCTAssertThrowsError(try state.validateForLeaving())
        let pendingScene = context.work.scene.snapshot
        state.leave()
        XCTAssertEqual(context.work.scene.snapshot, pendingScene)
        XCTAssertTrue(state.pendingReorder === retained)
        XCTAssertFalse(state.cancelDraftReorder())
        context.access.setAfterDraftReorderReceiptForTesting(nil)
        let didRetry = await state.confirmDraftReorder(recordedByName: "Different retry label is ignored")
        XCTAssertTrue(didRetry)
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), afterEffect)
        let current = try XCTUnwrap(state.session)
        XCTAssertEqual(current.items.map(\.itemID), [original.items[1].itemID, original.items[0].itemID])
        XCTAssertEqual(current.recordedBy.displayNameAtTime, "Retry recorder")
        XCTAssertEqual(current, retained.proposedSession)
        XCTAssertNil(state.pendingReorder)
        XCTAssertNil(state.orderingIntent)
        XCTAssertFalse(context.work.store.modelContext.hasChanges)
        #else
        throw XCTSkip("Publication fault injection is DEBUG-only")
        #endif
    }

    @MainActor
    func testActualDraftOrderingMaterializesDistinctRequiredContentAndPublishesCanonicalSuccessor() async throws {
        let fixture = try await makeFixture("round-order-content-present")
        defer { fixture.cleanUp() }
        let seed = try await V23RoundRouteHarness.make(in: fixture, label: "content-present")
        let expanded = try await seed.addingDraftItems(1)
        let first = try await persistRoundContent(in: expanded.work, label: "present-a", bytes: Data("round content A".utf8))
        let second = try await persistRoundContent(in: expanded.work, label: "present-b", bytes: Data("round content B".utf8))
        let context = try expanded.requiringContent([[first], [second]])
        let target = try context.target(for: context.round)
        try context.work.scene.open(target)
        let state = ProductionRoundSessionPresentationV1(target: target, scene: context.work.scene, access: context.access)
        await state.refresh()
        let before = try context.work.store.workspaceWriter.currentRevision()
        state.requestDraftReorder(itemID: context.round.items[0].itemID, delta: 1)
        let didOrder = await state.confirmDraftReorder(recordedByName: "Content recorder")
        XCTAssertTrue(didOrder)
        let successor = try XCTUnwrap(state.session)
        XCTAssertEqual(successor.items.map(\.itemID), Array(context.round.items.map(\.itemID).reversed()))
        XCTAssertEqual(successor.items.map(\.requirement.requiredContent), [[second], [first]])
        XCTAssertEqual(successor.transition, .reviseSelection)
        XCTAssertEqual(successor.revision, context.round.revision + 1)
        let after = try context.work.store.workspaceWriter.currentRevision()
        XCTAssertNotEqual(after, before)
        XCTAssertEqual(after.revision, before.revision + 1)
        let reread = try await context.access.readSession(sessionID: successor.sessionID,
            expectedRevision: successor.revision)
        XCTAssertEqual(reread, successor)
        XCTAssertEqual(try context.work.store.modelContext.fetchCount(FetchDescriptor<RoundSessionRevisionRowV1>()), 4)
        XCTAssertFalse(context.work.store.modelContext.hasChanges)
    }

    @MainActor
    func testActualDraftOrderingDeduplicatesEqualRequiredContentMaterialization() async throws {
        #if DEBUG
        let fixture = try await makeFixture("round-order-content-dedup")
        defer { fixture.cleanUp() }
        let seed = try await V23RoundRouteHarness.make(in: fixture, label: "content-dedup")
        let expanded = try await seed.addingDraftItems(1)
        let content = try await persistRoundContent(in: expanded.work, label: "duplicate", bytes: Data("one shared original".utf8))
        let context = try expanded.requiringContent([[content], [content]])
        let target = try context.target(for: context.round)
        try context.work.scene.open(target)
        let state = ProductionRoundSessionPresentationV1(target: target, scene: context.work.scene, access: context.access)
        await state.refresh()
        var resolutions = 0
        context.access.setAfterDraftReorderContentResolutionForTesting { resolutions += 1 }
        defer { context.access.setAfterDraftReorderContentResolutionForTesting(nil) }
        state.requestDraftReorder(itemID: context.round.items[0].itemID, delta: 1)
        let didOrder = await state.confirmDraftReorder(recordedByName: "Duplicate recorder")
        XCTAssertTrue(didOrder)
        XCTAssertEqual(resolutions, 1)
        let successor = try XCTUnwrap(state.session)
        XCTAssertEqual(successor.items.map(\.requirement.requiredContent), [[content], [content]])
        XCTAssertFalse(context.work.store.modelContext.hasChanges)
        #else
        throw XCTSkip("Materialization observation is DEBUG-only")
        #endif
    }

    @MainActor
    func testActualDraftOrderingPermitsMissingRequiredOriginalForDraft() async throws {
        let fixture = try await makeFixture("round-order-content-missing")
        defer { fixture.cleanUp() }
        let seed = try await V23RoundRouteHarness.make(in: fixture, label: "content-missing")
        let expanded = try await seed.addingDraftItems(1)
        let missing = try makeRoundContentReference(workspaceID: expanded.work.store.workspaceID,
            label: "missing", bytes: Data("never persisted".utf8))
        let context = try expanded.requiringContent([[missing], []])
        let target = try context.target(for: context.round)
        try context.work.scene.open(target)
        let state = ProductionRoundSessionPresentationV1(target: target, scene: context.work.scene, access: context.access)
        await state.refresh()
        let before = try context.work.store.workspaceWriter.currentRevision()
        state.requestDraftReorder(itemID: context.round.items[0].itemID, delta: 1)
        let didOrder = await state.confirmDraftReorder(recordedByName: "Missing recorder")
        XCTAssertTrue(didOrder)
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision().revision, before.revision + 1)
        XCTAssertEqual(try XCTUnwrap(state.session).items.map(\.requirement.requiredContent), [[], [missing]])
        XCTAssertFalse(context.work.store.modelContext.hasChanges)
    }

    @MainActor
    func testActualDraftOrderingRejectsCorruptAndConflictingRequiredContentWithoutEffect() async throws {
        let fixture = try await makeFixture("round-order-content-denial")
        defer { fixture.cleanUp() }
        let seed = try await V23RoundRouteHarness.make(in: fixture, label: "content-denial")
        let expanded = try await seed.addingDraftItems(1)
        let persisted = try await persistRoundContent(in: expanded.work, label: "corrupt", bytes: Data("protected round original".utf8))
        let corrupt = try expanded.requiringContent([[persisted], []])
        let originalURL = corrupt.work.store.generationRootURL.appendingPathComponent("content")
            .appendingPathComponent(persisted.workspaceID).appendingPathComponent(persisted.contentID)
            .appendingPathComponent("original.bin")
        let handle = try FileHandle(forWritingTo: originalURL)
        try handle.write(contentsOf: Data(repeating: 0x7F, count: Int(persisted.byteLength)))
        try handle.close()
        let corruptTarget = try corrupt.target(for: corrupt.round)
        try corrupt.work.scene.open(corruptTarget)
        let corruptState = ProductionRoundSessionPresentationV1(target: corruptTarget, scene: corrupt.work.scene, access: corrupt.access)
        await corruptState.refresh()
        let corruptBefore = try corrupt.work.store.workspaceWriter.currentRevision()
        corruptState.requestDraftReorder(itemID: corrupt.round.items[0].itemID, delta: 1)
        let didOrder = await corruptState.confirmDraftReorder(recordedByName: "Corrupt recorder")
        XCTAssertFalse(didOrder)
        XCTAssertEqual(try corrupt.work.store.workspaceWriter.currentRevision(), corruptBefore)
        let corruptReread = try await corrupt.access.readSession(sessionID: corrupt.round.sessionID,
            expectedRevision: corrupt.round.revision)
        XCTAssertEqual(corruptReread, corrupt.round)
        XCTAssertFalse(corrupt.work.store.modelContext.hasChanges)

        let otherSeed = try await V23RoundRouteHarness.make(in: fixture, label: "content-collision")
        let otherExpanded = try await otherSeed.addingDraftItems(1)
        let original = try await persistRoundContent(in: otherExpanded.work, label: "collision", bytes: Data("collision source".utf8))
        let conflicting = try makeRoundContentReference(workspaceID: otherExpanded.work.store.workspaceID,
            label: "conflicting", bytes: Data("collision other!".utf8), contentID: original.contentID)
        let collision = try otherExpanded.requiringContent([[original], [conflicting]])
        let collisionTarget = try collision.target(for: collision.round)
        try collision.work.scene.open(collisionTarget)
        let collisionState = ProductionRoundSessionPresentationV1(target: collisionTarget, scene: collision.work.scene, access: collision.access)
        await collisionState.refresh()
        let collisionBefore = try collision.work.store.workspaceWriter.currentRevision()
        collisionState.requestDraftReorder(itemID: collision.round.items[0].itemID, delta: 1)
        let didOrderCollision = await collisionState.confirmDraftReorder(recordedByName: "Collision recorder")
        XCTAssertFalse(didOrderCollision)
        XCTAssertEqual(try collision.work.store.workspaceWriter.currentRevision(), collisionBefore)
        let collisionReread = try await collision.access.readSession(sessionID: collision.round.sessionID,
            expectedRevision: collision.round.revision)
        XCTAssertEqual(collisionReread, collision.round)
        XCTAssertFalse(collision.work.store.modelContext.hasChanges)
    }

    @MainActor
    func testActualDraftOrderingRejectsForeignPreparedCommandAndBlankRecorderWithoutEffect() async throws {
        let fixture = try await makeFixture("round-order-foreign")
        defer { fixture.cleanUp() }
        let otherFixture = try await makeFixture("round-order-other-workspace")
        defer { otherFixture.cleanUp() }
        let seed = try await V23RoundRouteHarness.make(in: fixture, label: "origin")
        let context = try await seed.addingDraftItems(1)
        let other = try await V23RoundRouteHarness.make(in: otherFixture, label: "foreign")
        let before = try context.work.store.workspaceWriter.currentRevision()
        let otherBefore = try other.work.store.workspaceWriter.currentRevision()
        XCTAssertThrowsError(try context.access.prepareDraftReorder(expected: context.round,
            itemID: context.round.items[0].itemID, delta: 1, recordedByName: "  "))
        let prepared = try context.access.prepareDraftReorder(expected: context.round,
            itemID: context.round.items[0].itemID, delta: 1, recordedByName: "Origin recorder")
        var intentCalled = false
        do {
            _ = try await other.access.executeDraftReorder(prepared) { intentCalled = true }
            XCTFail("Foreign publication cannot consume another service's immutable command")
        } catch { }
        XCTAssertFalse(intentCalled)
        XCTAssertEqual(prepared.attemptState, .notAttempted)
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), before)
        XCTAssertEqual(try other.work.store.workspaceWriter.currentRevision(), otherBefore)
        XCTAssertFalse(context.work.store.modelContext.hasChanges)
        XCTAssertFalse(other.work.store.modelContext.hasChanges)
    }
}

import Combine
import Foundation
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import FieldEvidenceApp

final class V23ProductionRoundItemTests: V23ProductionFourRootShellTestSupport {
    @MainActor
    func testActualRoundItemTransitionsMutateOnlyTheirActiveItemAndPersistEveryLegalPath() async throws {
        let fixture = try await makeFixture("round-item-all-paths")
        defer { fixture.cleanUp() }
        let seed = try await V23RoundRouteHarness.make(in: fixture, label: "all-paths")
        let context = try await seed.addingDraftItems(5)
        let started = try await startActualRound(in: context, recorder: "Item start recorder")
        let originalItems = started.items
        var current = started

        func apply(_ itemIndex: Int, _ transition: RoundSessionTransitionV1,
                   reason: RoundItemReasonV1? = nil,
                   completion: RoundItemCompletionReferenceV1? = nil) async throws -> RoundSessionV1 {
            let item = current.items[itemIndex]
            let write = try context.access.prepareItemTransition(expected: current, itemID: item.itemID,
                transition: transition, reason: reason, completion: completion,
                recordedByName: "Item \(transition.rawValue) recorder")
            let receipt = try await context.access.executeSessionTransition(write) {}
            XCTAssertEqual(receipt.sessionFrontier, try write.proposedSession.reference)
            XCTAssertEqual(write.proposedSession.transitionItemID, item.itemID)
            XCTAssertEqual(write.proposedSession.state, .active)
            XCTAssertEqual(write.proposedSession.revision, current.revision + 1)
            XCTAssertEqual(write.proposedSession.predecessor, try current.reference)
            XCTAssertEqual(write.proposedSession.items.enumerated().filter { $0.offset != itemIndex }
                .map(\.element), current.items.enumerated().filter { $0.offset != itemIndex }.map(\.element))
            XCTAssertEqual(write.proposedSession.items.map(\.itemID), originalItems.map(\.itemID))
            XCTAssertEqual(write.proposedSession.items.map(\.order), originalItems.map(\.order))
            XCTAssertEqual(write.proposedSession.items.map(\.selection), originalItems.map(\.selection))
            XCTAssertEqual(write.proposedSession.items.map(\.requirement), originalItems.map(\.requirement))
            XCTAssertEqual(write.proposedSession.recordedBy.displayNameAtTime, "Item \(transition.rawValue) recorder")
            XCTAssertGreaterThanOrEqual(write.proposedSession.recordedAt, current.recordedAt)
            let readBack = try await context.access.readSession(sessionID: current.sessionID,
                expectedRevision: write.proposedSession.revision)
            XCTAssertEqual(readBack, write.proposedSession)
            return readBack
        }

        current = try await apply(0, .visitItem)
        current = try await apply(1, .visitItem)
        let finalized = try await makeActualFinalizedCompletion(in: context, label: "all-paths-complete",
            asset: context.work.sign)
        current = try await apply(0, .completeItem, completion: finalized.reference)
        current = try await apply(2, .markInaccessible, reason: .physicalAccessUnavailable)
        current = try await apply(3, .skipItem, reason: .notRequired)
        current = try await apply(4, .deferItem, reason: .userDeferred)
        current = try await apply(5, .markInaccessible, reason: .permissionUnavailable)
        current = try await apply(5, .retryItem)

        XCTAssertEqual(current.items.map(\.disposition), [.completed, .visited, .inaccessible,
            .skipped, .deferred, .pending])
        XCTAssertEqual(current.counts, .init(items: current.items))
        XCTAssertEqual(current.counts.expected, 6)
        XCTAssertEqual(current.counts.visited, 2)
        XCTAssertEqual(current.counts.completed, 1)
        XCTAssertEqual(current.counts.inaccessible, 1)
        XCTAssertEqual(current.counts.skipped, 1)
        XCTAssertEqual(current.counts.deferred, 1)
        XCTAssertEqual(current.counts.undispositioned, 2)
        XCTAssertEqual(try context.work.store.modelContext.fetchCount(FetchDescriptor<RoundSessionRevisionRowV1>()),
            Int(current.revision))
        XCTAssertFalse(context.work.store.modelContext.hasChanges)
    }

    @MainActor
    func testActualRoundItemPreparationRejectsWrongStateItemReasonAndExtraneousCompletionWithoutEffect() async throws {
        let fixture = try await makeFixture("round-item-argument-denials")
        defer { fixture.cleanUp() }
        let context = try await V23RoundRouteHarness.make(in: fixture, label: "argument-denials")
        let before = try context.work.store.workspaceWriter.currentRevision()
        let item = try XCTUnwrap(context.round.items.first)
        for transition in [RoundSessionTransitionV1.visitItem, .completeItem, .markInaccessible,
                           .skipItem, .deferItem, .retryItem] {
            XCTAssertThrowsError(try context.access.prepareItemTransition(expected: context.round,
                itemID: item.itemID, transition: transition, recordedByName: "Draft item recorder"))
        }
        let active = try await startActualRound(in: context, recorder: "Argument start recorder")
        let activeBefore = try context.work.store.workspaceWriter.currentRevision()
        let activeItem = try XCTUnwrap(active.items.first)
        let arbitraryCompletion = try RoundItemCompletionReferenceV1(completionID: UUID(), revision: 1,
            completionSHA256: String(repeating: "a", count: 64))
        let invalid: [(RoundSessionTransitionV1, RoundItemReasonV1?, RoundItemCompletionReferenceV1?)] = [
            (.visitItem, .notRequired, nil), (.visitItem, nil, arbitraryCompletion),
            (.completeItem, nil, nil), (.completeItem, .notRequired, arbitraryCompletion),
            (.markInaccessible, .notRequired, nil), (.markInaccessible, .physicalAccessUnavailable, arbitraryCompletion),
            (.skipItem, .physicalAccessUnavailable, nil), (.deferItem, .notRequired, nil),
            (.retryItem, .userDeferred, nil), (.retryItem, nil, arbitraryCompletion),
        ]
        for (transition, reason, completion) in invalid {
            XCTAssertThrowsError(try context.access.prepareItemTransition(expected: active,
                itemID: activeItem.itemID, transition: transition, reason: reason, completion: completion,
                recordedByName: "Invalid item recorder"))
        }
        XCTAssertThrowsError(try context.access.prepareItemTransition(expected: active, itemID: UUID(),
            transition: .visitItem, recordedByName: "Unknown item recorder"))
        XCTAssertThrowsError(try context.access.prepareItemTransition(expected: active, itemID: activeItem.itemID,
            transition: .visitItem, recordedByName: " \n "))
        XCTAssertEqual(before.revision + 1, activeBefore.revision)
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), activeBefore)
        XCTAssertEqual(try context.work.store.modelContext.fetchCount(FetchDescriptor<RoundSessionRevisionRowV1>()),
            Int(active.revision))
        XCTAssertFalse(context.work.store.modelContext.hasChanges)
    }

    @MainActor
    func testActualRoundItemTransitionRejectsForeignRevokedAndStalePreparedAuthorityWithoutEffect() async throws {
        let fixture = try await makeFixture("round-item-authority-denials")
        defer { fixture.cleanUp() }
        let otherFixture = try await makeFixture("round-item-foreign")
        defer { otherFixture.cleanUp() }
        let context = try await V23RoundRouteHarness.make(in: fixture, label: "authority-denials")
        let other = try await V23RoundRouteHarness.make(in: otherFixture, label: "foreign")
        let active = try await startActualRound(in: context, recorder: "Authority start recorder")
        let prepared = try context.access.prepareItemTransition(expected: active,
            itemID: try XCTUnwrap(active.items.first).itemID, transition: .visitItem,
            recordedByName: "Original item recorder")
        let before = try context.work.store.workspaceWriter.currentRevision()
        let otherBefore = try other.work.store.workspaceWriter.currentRevision()
        var intentCalled = false
        do {
            _ = try await other.access.executeSessionTransition(prepared) { intentCalled = true }
            XCTFail("A foreign publication cannot consume the prepared item command")
        } catch { }
        XCTAssertFalse(intentCalled)
        XCTAssertEqual(prepared.attemptState, .notAttempted)
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), before)
        XCTAssertEqual(try other.work.store.workspaceWriter.currentRevision(), otherBefore)

        let competing = try context.access.prepareItemTransition(expected: active,
            itemID: try XCTUnwrap(active.items.last).itemID, transition: .skipItem, reason: .notRequired,
            recordedByName: "Competing item recorder")
        _ = try await context.access.executeSessionTransition(competing) {}
        let afterCompeting = try context.work.store.workspaceWriter.currentRevision()
        do {
            _ = try await context.access.executeSessionTransition(prepared) { intentCalled = true }
            XCTFail("A changed active frontier cannot consume stale item preparation")
        } catch { }
        XCTAssertFalse(intentCalled)
        XCTAssertEqual(prepared.attemptState, .notAttempted)
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), afterCompeting)

        let revoked = try await V23RoundRouteHarness.make(in: fixture, label: "revoked")
        let revokedActive = try await startActualRound(in: revoked, recorder: "Revoked start recorder")
        let revokedWrite = try revoked.access.prepareItemTransition(expected: revokedActive,
            itemID: try XCTUnwrap(revokedActive.items.first).itemID, transition: .visitItem,
            recordedByName: "Revoked item recorder")
        let revokedBefore = try revoked.work.store.workspaceWriter.currentRevision()
        fixture.presentation.receive(.sceneInactive)
        do {
            _ = try await revoked.access.executeSessionTransition(revokedWrite) {}
            XCTFail("A revoked publication cannot consume an item command")
        } catch { }
        XCTAssertEqual(revokedWrite.attemptState, .notAttempted)
        XCTAssertEqual(try revoked.work.store.workspaceWriter.currentRevision(), revokedBefore)
        XCTAssertFalse(context.work.store.modelContext.hasChanges)
        XCTAssertFalse(other.work.store.modelContext.hasChanges)
        XCTAssertFalse(revoked.work.store.modelContext.hasChanges)
    }

    @MainActor
    func testActualRoundItemTransitionCancellationAndLostAcknowledgementRetryHaveOneEffect() async throws {
        #if DEBUG
        let fixture = try await makeFixture("round-item-cancel-retry")
        defer { fixture.cleanUp() }
        let context = try await V23RoundRouteHarness.make(in: fixture, label: "cancel-retry")
        let active = try await startActualRound(in: context, recorder: "Cancel start recorder")
        let write = try context.access.prepareItemTransition(expected: active,
            itemID: try XCTUnwrap(active.items.first).itemID, transition: .visitItem,
            recordedByName: "Cancelled item recorder")
        let before = try context.work.store.workspaceWriter.currentRevision()
        var reachedSuspension = false
        context.access.setAfterSessionTransitionContentMaterializationForTesting {
            reachedSuspension = true
            try await Task.sleep(nanoseconds: 30_000_000_000)
        }
        let operation = Task { @MainActor in try await context.access.executeSessionTransition(write) {} }
        for _ in 0..<200 {
            if reachedSuspension { break }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertTrue(reachedSuspension)
        operation.cancel()
        do {
            _ = try await operation.value
            XCTFail("Cancelled item execution must not write")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        context.access.setAfterSessionTransitionContentMaterializationForTesting(nil)
        XCTAssertEqual(write.attemptState, .notAttempted)
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), before)

        let retry = try context.access.prepareItemTransition(expected: active,
            itemID: try XCTUnwrap(active.items.last).itemID, transition: .skipItem, reason: .notRequired,
            recordedByName: "Lost acknowledgement recorder")
        var interrupted = false
        context.access.setAfterSessionTransitionReceiptForTesting {
            interrupted = true
            throw CancellationError()
        }
        do {
            _ = try await context.access.executeSessionTransition(retry) {}
            XCTFail("The test fault must hide the first real item receipt")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertTrue(interrupted)
        let afterEffect = try context.work.store.workspaceWriter.currentRevision()
        XCTAssertEqual(retry.attemptState, .canonicalWriteAttempted)
        context.access.setAfterSessionTransitionReceiptForTesting(nil)
        let receipt = try await context.access.executeSessionTransition(retry) {}
        XCTAssertEqual(receipt.sessionFrontier, try retry.proposedSession.reference)
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), afterEffect)
        let readBack = try await context.access.readSession(sessionID: active.sessionID,
            expectedRevision: retry.proposedSession.revision)
        XCTAssertEqual(readBack, retry.proposedSession)
        XCTAssertFalse(context.work.store.modelContext.hasChanges)
        #else
        throw XCTSkip("Publication fault injection is DEBUG-only")
        #endif
    }

    @MainActor
    func testActualRoundItemCompletionDeniesMissingWrongAssetAndCorruptFinalizedSourceWithoutEffect() async throws {
        for kind in ["missing", "wrong-asset", "corrupt"] {
            let fixture = try await makeFixture("round-item-completion-" + kind)
            defer { fixture.cleanUp() }
            var corruptSnapshot: (url: URL, bytes: Data)?
            defer {
                if let corruptSnapshot = corruptSnapshot {
                    try? corruptSnapshot.bytes.write(to: corruptSnapshot.url)
                }
            }
            let context = try await V23RoundRouteHarness.make(in: fixture, label: "completion-" + kind)
            let active = try await startActualRound(in: context, recorder: "Completion start recorder")
            let itemID = try XCTUnwrap(active.items.first).itemID
            let visitedWrite = try context.access.prepareItemTransition(expected: active, itemID: itemID,
                transition: .visitItem, recordedByName: "Completion visit recorder")
            let visitedReceipt = try await context.access.executeSessionTransition(visitedWrite) {}
            XCTAssertEqual(visitedReceipt.sessionFrontier, try visitedWrite.proposedSession.reference)
            let actual = try await makeActualFinalizedCompletion(in: context, label: kind)
            let completion: RoundItemCompletionReferenceV1
            if kind == "missing" {
                completion = try .init(completionID: UUID(), revision: actual.reference.revision,
                    completionSHA256: actual.reference.completionSHA256)
            } else if kind == "wrong-asset" {
                let otherAsset = try await context.work.workflow.firstSign.create(.init(
                    siteLabel: "Round wrong item completion site", signLabel: "Round wrong item completion asset",
                    timeZoneID: "America/New_York", isTimeZoneConfirmed: true))
                completion = try await makeActualFinalizedCompletion(in: context, label: "wrong-asset-other",
                    asset: otherAsset).reference
            } else {
                let original = try Data(contentsOf: actual.snapshotURL)
                try Data("corrupt actual item completion".utf8).write(to: actual.snapshotURL)
                corruptSnapshot = (actual.snapshotURL, original)
                completion = actual.reference
            }
            let before = try context.work.store.workspaceWriter.currentRevision()
            let denied = try context.access.prepareItemTransition(expected: visitedWrite.proposedSession,
                itemID: itemID, transition: .completeItem, completion: completion,
                recordedByName: "Denied completion recorder")
            do {
                _ = try await context.access.executeSessionTransition(denied) {}
                XCTFail("\(kind) finalized completion source must not be accepted")
            } catch { }
            XCTAssertEqual(denied.attemptState, .notAttempted)
            XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), before)
            XCTAssertFalse(context.work.store.modelContext.hasChanges)
        }
    }

    @MainActor
    func testActualRoundItemPresentationRequestIsZeroWriteAndConfirmationPreservesExactReason() async throws {
        let fixture = try await makeFixture("round-item-presentation-confirm")
        defer { fixture.cleanUp() }
        let context = try await V23RoundRouteHarness.make(in: fixture, label: "presentation-confirm")
        let active = try await startActualRound(in: context, recorder: "Presentation start recorder")
        let target = try context.target(for: active)
        try context.work.scene.open(target)
        let state = ProductionRoundSessionPresentationV1(target: target, scene: context.work.scene,
            access: context.access)
        await state.refresh()
        let item = try XCTUnwrap(active.items.first)
        let before = try context.work.store.workspaceWriter.currentRevision()
        state.requestItemTransition(itemID: item.itemID, transition: .skipItem, reason: .notRequired)
        let intent = try XCTUnwrap(state.transitionIntent)
        XCTAssertEqual(intent.expectedSession, active)
        XCTAssertEqual(intent.transition, .skipItem)
        XCTAssertEqual(intent.itemID, item.itemID)
        XCTAssertEqual(intent.reason, .notRequired)
        XCTAssertNil(intent.completion)
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), before)
        let saved = await state.confirmSessionTransition(recordedByName: "Item presentation recorder")
        XCTAssertTrue(saved)
        let successor = try XCTUnwrap(state.session)
        XCTAssertEqual(successor.transition, .skipItem)
        XCTAssertEqual(successor.transitionItemID, item.itemID)
        XCTAssertEqual(successor.items.first?.disposition, .skipped)
        XCTAssertEqual(successor.items.first?.reason, .notRequired)
        XCTAssertEqual(successor.recordedBy.displayNameAtTime, "Item presentation recorder")
        XCTAssertNil(state.transitionIntent)
        XCTAssertNil(state.pendingTransition)
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision().revision, before.revision + 1)
        XCTAssertFalse(context.work.store.modelContext.hasChanges)
    }

    @MainActor
    func testActualRoundItemPresentationRejectsForeignItemAndOriginalSceneABAWithoutWrite() async throws {
        #if DEBUG
        let fixture = try await makeFixture("round-item-presentation-scene")
        defer { fixture.cleanUp() }
        let seed = try await V23RoundRouteHarness.make(in: fixture, label: "presentation-scene")
        let context = try await seed.addingDraftItems(1)
        let active = try await startActualRound(in: context, recorder: "Scene start recorder")
        let target = try context.target(for: active)
        try context.work.scene.open(target)
        let state = ProductionRoundSessionPresentationV1(target: target, scene: context.work.scene,
            access: context.access)
        await state.refresh()
        let before = try context.work.store.workspaceWriter.currentRevision()
        state.requestItemTransition(itemID: UUID(), transition: .visitItem)
        XCTAssertNil(state.transitionIntent)
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), before)

        let item = active.items[1]
        state.requestItemTransition(itemID: item.itemID, transition: .deferItem, reason: .userDeferred)
        XCTAssertEqual(state.transitionIntent?.itemID, item.itemID)
        var reachedSuspension = false
        context.access.setAfterSessionTransitionContentMaterializationForTesting {
            reachedSuspension = true
            try context.work.scene.open(context.work.target(expectedRevision: nil))
            try context.work.scene.open(target)
        }
        let saved = await state.confirmSessionTransition(recordedByName: "Scene item recorder")
        context.access.setAfterSessionTransitionContentMaterializationForTesting(nil)
        XCTAssertTrue(reachedSuspension)
        XCTAssertFalse(saved)
        XCTAssertEqual(state.session, active)
        XCTAssertNil(state.pendingTransition)
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), before)
        XCTAssertEqual(context.work.scene.snapshot?.path(for: .work)?.targets, [target])
        XCTAssertFalse(context.work.store.modelContext.hasChanges)
        #else
        throw XCTSkip("Original-scene item transition proof is DEBUG-only")
        #endif
    }

    @MainActor
    func testActualRoundItemPresentationLostAcknowledgementRetainsExactItemAndRecorderAcrossRetry() async throws {
        #if DEBUG
        let fixture = try await makeFixture("round-item-presentation-retry")
        defer { fixture.cleanUp() }
        let seed = try await V23RoundRouteHarness.make(in: fixture, label: "presentation-retry")
        let context = try await seed.addingDraftItems(1)
        let active = try await startActualRound(in: context, recorder: "Retry start recorder")
        let target = try context.target(for: active)
        try context.work.scene.open(target)
        let state = ProductionRoundSessionPresentationV1(target: target, scene: context.work.scene,
            access: context.access)
        await state.refresh()
        let item = active.items[1]
        state.requestItemTransition(itemID: item.itemID, transition: .deferItem, reason: .userDeferred)
        context.access.setAfterSessionTransitionReceiptForTesting { throw CancellationError() }
        let interrupted = await state.confirmSessionTransition(recordedByName: "Original item retry recorder")
        XCTAssertFalse(interrupted)
        let retained = try XCTUnwrap(state.pendingTransition)
        let afterEffect = try context.work.store.workspaceWriter.currentRevision()
        XCTAssertTrue(state.hasUnacknowledgedTransition)
        XCTAssertEqual(retained.proposedSession.transition, .deferItem)
        XCTAssertEqual(retained.proposedSession.transitionItemID, item.itemID)
        XCTAssertEqual(retained.proposedSession.items[1].reason, .userDeferred)
        XCTAssertEqual(retained.proposedSession.recordedBy.displayNameAtTime, "Original item retry recorder")
        context.access.setAfterSessionTransitionReceiptForTesting(nil)
        let retried = await state.confirmSessionTransition(recordedByName: "Replacement must be ignored")
        XCTAssertTrue(retried)
        XCTAssertEqual(try context.work.store.workspaceWriter.currentRevision(), afterEffect)
        let successor = try XCTUnwrap(state.session)
        XCTAssertEqual(successor, retained.proposedSession)
        XCTAssertEqual(successor.items[1].reason, .userDeferred)
        XCTAssertEqual(successor.recordedBy.displayNameAtTime, "Original item retry recorder")
        XCTAssertNil(state.pendingTransition)
        XCTAssertFalse(context.work.store.modelContext.hasChanges)
        #else
        throw XCTSkip("Publication receipt fault injection is DEBUG-only")
        #endif
    }
}

import Foundation
import SwiftData
import XCTest

@testable import FieldEvidenceApp

final class V23RepetitiveCaptureProgressDraftPayloadV2Tests: XCTestCase {
    func testExistingRoundSourceUsesActualOrderedProofsAtOneTwoHundredAndMaximumItems() throws {
        for count in [1, 2, 100, 200] {
            let fixture = try ProgressFixture(count: count)
            let source = try fixture.source()
            let value = try RepetitiveCaptureProgressDraftCodecV2.source(source)
            XCTAssertEqual(value.round, fixture.active)
            XCTAssertEqual(value.readiness.map(\.assetID), fixture.active.items.map { $0.selection.assetID })
            XCTAssertEqual(value.firstIncompleteItemID, fixture.active.items.first?.itemID)
            XCTAssertEqual(try RepetitiveCaptureProgressDraftCodecV2.decode(source.payloadData), .source(value))
            XCTAssertLessThanOrEqual(source.payloadData.count, FieldDraftLimitsV1.maximumPayloadBytes)
            XCTAssertNil(source.payloadData.range(of: Data(source.checkpointSHA256.utf8)))
            for proof in value.readiness { try proof.validate(manifest: fixture.manifest) }
        }
    }

    func testSourceRejectsMissingDuplicatedForeignAndMixedReadinessWithoutManufacturingReady() throws {
        let fixture = try ProgressFixture(count: 2), other = try ProgressFixture(count: 2)
        let proofs = try fixture.active.items.map { try ScanToWorkOfflineReadinessProofV1(manifest: fixture.manifest, assetID: $0.selection.assetID) }
        XCTAssertThrowsError(try RepetitiveCaptureLaunchSourceV2(planID: fixture.planID, round: fixture.active, readiness: Array(proofs.dropLast())))
        XCTAssertThrowsError(try RepetitiveCaptureLaunchSourceV2(planID: fixture.planID, round: fixture.active, readiness: Array(proofs.reversed())))
        XCTAssertThrowsError(try RepetitiveCaptureLaunchSourceV2(planID: fixture.planID, round: fixture.active, readiness: [proofs[0], proofs[0]]))
        XCTAssertThrowsError(try RepetitiveCaptureLaunchSourceV2(planID: fixture.planID, round: other.active, readiness: proofs))
        let laterManifest = try fixture.makeManifest(round: fixture.active, checkedAt: ProgressFixture.date.addingTimeInterval(1))
        let later = try ScanToWorkOfflineReadinessProofV1(manifest: laterManifest, assetID: fixture.active.items[1].selection.assetID)
        XCTAssertThrowsError(try RepetitiveCaptureLaunchSourceV2(planID: fixture.planID, round: fixture.active, readiness: [proofs[0], later]))
        XCTAssertThrowsError(try RepetitiveCaptureLaunchSourceV2(planID: fixture.planID, round: fixture.draft, readiness: proofs))
        let wrongAnchor = try fixture.source(anchorOverride: .init(selectedStableID: fixture.active.items[1].selection.assetID.uuidString.lowercased()))
        XCTAssertThrowsError(try RepetitiveCaptureProgressDraftCodecV2.source(wrongAnchor))
    }

    func testClosedV2GrammarAndExactV1ReleaseRemainSeparate() throws {
        let fixture = try ProgressFixture(count: 1), source = try fixture.source()
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: source.payloadData) as? [String: Any])
        root["future"] = true
        XCTAssertThrowsError(try RepetitiveCaptureProgressDraftCodecV2.decode(JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])))
        root.removeValue(forKey: "future")
        var payload = try XCTUnwrap(root["source"] as? [String: Any]); payload["unknownAuthority"] = true; root["source"] = payload
        XCTAssertThrowsError(try RepetitiveCaptureProgressDraftCodecV2.decode(JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])))
        XCTAssertThrowsError(try RepetitiveCaptureProgressDraftCodecV2.decode(Data(repeating: 0, count: FieldDraftLimitsV1.maximumPayloadBytes + 1)))
        XCTAssertThrowsError(try RepetitiveCaptureDraftCodecV1.decode(source.payloadData))
        let authority = try RepetitiveCaptureDraftPurposeAuthorityV1()
        XCTAssertEqual(try authority.require(.repetitiveCapture, codec: RepetitiveCaptureDraftCodecV1.release()), try RepetitiveCaptureDraftCodecV1.definition())
        XCTAssertEqual(try authority.require(.repetitiveCapture, codec: RepetitiveCaptureProgressDraftCodecV2.release()), try RepetitiveCaptureProgressDraftCodecV2.definition())
        let forged = try DraftPayloadCodecReleaseV1(codecID: "assetrounds.repetitive-capture.v2", codecVersion: 2, releaseSHA256: String(repeating: "a", count: 64))
        XCTAssertThrowsError(try authority.require(.repetitiveCapture, codec: forged))
    }

    func testEntryAndAdvanceUseRealRoundTransitionsAndPreserveTerminalTruth() throws {
        let fixture = try ProgressFixture(count: 2), source = try fixture.source()
        let first = fixture.active.items[0]
        let visit = try fixture.mutation(from: fixture.active, itemID: first.itemID, transition: .visitItem)
        let entry = try fixture.step(source: source, expected: fixture.active, itemID: first.itemID, action: .enter, mutation: visit)
        XCTAssertEqual(entry.navigationItemID, first.itemID)
        XCTAssertThrowsError(try fixture.step(source: source, expected: fixture.active, itemID: first.itemID, action: .keepOpenAndNext, mutation: nil))
        XCTAssertThrowsError(try fixture.step(source: source, expected: fixture.active, itemID: first.itemID, action: .enter, mutation: nil))
        let enteredAgain = try fixture.step(source: source, expected: visit.session, itemID: first.itemID, action: .enter, mutation: nil)
        XCTAssertEqual(enteredAgain.resultingRound, visit.session)
        XCTAssertThrowsError(try fixture.step(source: source, expected: visit.session, itemID: first.itemID, action: .enter, mutation: visit))
        let keep = try fixture.step(source: source, expected: visit.session, itemID: first.itemID, action: .keepOpenAndNext, mutation: nil)
        XCTAssertNil(keep.roundMutation)
        XCTAssertEqual(keep.navigationItemID, fixture.active.items[1].itemID)
        XCTAssertEqual(keep.resultingRound.items[0].disposition, .visited)
        let deferred = try fixture.mutation(from: visit.session, itemID: first.itemID, transition: .deferItem)
        let deferStep = try fixture.step(source: source, expected: visit.session, itemID: first.itemID, action: .defer, mutation: deferred)
        XCTAssertEqual(deferStep.resultingRound.counts.deferred, 1)
        XCTAssertEqual(deferStep.resultingRound.counts.completed, 0)
        XCTAssertThrowsError(try fixture.step(source: source, expected: deferred.session, itemID: first.itemID, action: .enter, mutation: nil))
        let completed = try fixture.mutation(from: visit.session, itemID: first.itemID, transition: .completeItem)
        let completeStep = try fixture.step(source: source, expected: visit.session, itemID: first.itemID, action: .complete, mutation: completed)
        XCTAssertEqual(completeStep.resultingRound.counts.completed, 1)
        XCTAssertEqual(completeStep.navigationItemID, fixture.active.items[1].itemID)
    }

    @MainActor
    func testActualDiskReopenRecoversPendingSecondItemAndNeverRunsItUntilExplicitReplay() throws {
        let fixture = try ProgressFixture(count: 2), disk = try ProgressDisk(workspaceID: fixture.workspace)
        defer { disk.removeClosedFiles() }
        let source = try fixture.source()
        let pending = try disk.withSession { session -> FieldDraftCheckpointV1 in
            _ = try session.writer.commitRoundSession(fixture.creationMutation)
            _ = try session.writer.commitRoundSession(fixture.activationMutation)
            _ = try session.adapter.persistRepetitiveCaptureProgressSource(source)
            let first = fixture.active.items[0]
            let visit = try fixture.mutation(from: fixture.active, itemID: first.itemID, transition: .visitItem)
            let entry = try fixture.progressCheckpoint(fixture.step(source: source, expected: fixture.active, itemID: first.itemID, action: .enter, mutation: visit))
            let prepared = try session.adapter.persistRepetitiveCaptureProgressStep(entry)
            XCTAssertTrue(try XCTUnwrap(prepared.nodes.last).isPendingRoundEffect)
            XCTAssertEqual(prepared.currentRound, fixture.active)
            let receipt = try session.writer.commitRoundSession(visit)
            let keep = try fixture.progressCheckpoint(fixture.step(source: source, prior: entry, priorReceipt: receipt,
                expected: visit.session, itemID: first.itemID, action: .keepOpenAndNext, mutation: nil))
            let afterKeep = try session.adapter.persistRepetitiveCaptureProgressStep(keep)
            XCTAssertEqual(afterKeep.currentRound, visit.session)
            XCTAssertNil(afterKeep.nodes.last?.roundReceipt)
            let second = visit.session.items[1]
            let secondVisit = try fixture.mutation(from: visit.session, itemID: second.itemID, transition: .visitItem)
            let pending = try fixture.progressCheckpoint(fixture.step(source: source, prior: keep,
                expected: visit.session, itemID: second.itemID, action: .enter, mutation: secondVisit))
            _ = try session.adapter.persistRepetitiveCaptureProgressStep(pending)
            return pending
        }
        try disk.withSession { session in
            let before = try session.writer.currentRevision()
            let passes = session.journal.fullValidationPassCountForTesting
            let recovered = try session.adapter.reviewedRepetitiveCaptureProgress(workspaceID: fixture.workspace, sourceDraftID: source.draftID)
            XCTAssertEqual(session.journal.fullValidationPassCountForTesting - passes, 1)
            let last = try XCTUnwrap(recovered.nodes.last)
            XCTAssertEqual(last.checkpoint, pending)
            XCTAssertTrue(last.isPendingRoundEffect)
            XCTAssertEqual(recovered.nodes.count, 3)
            XCTAssertEqual(try session.writer.currentRevision(), before)
            XCTAssertEqual(try session.adapter.persistRepetitiveCaptureProgressStep(pending), recovered)
            let mutation = try XCTUnwrap(last.step.roundMutation)
            let receipt = try session.writer.commitRoundSession(mutation)
            let deferMutation = try fixture.mutation(from: mutation.session, itemID: mutation.session.items[1].itemID, transition: .deferItem)
            let next = try fixture.progressCheckpoint(fixture.step(source: source, prior: pending, priorReceipt: receipt,
                expected: mutation.session, itemID: mutation.session.items[1].itemID, action: .defer, mutation: deferMutation))
            _ = try session.adapter.persistRepetitiveCaptureProgressStep(next)
            _ = try session.writer.commitRoundSession(deferMutation)
            let final = try session.adapter.reviewedRepetitiveCaptureProgress(workspaceID: fixture.workspace, sourceDraftID: source.draftID)
            XCTAssertEqual(final.nodes.count, 4)
            XCTAssertNil(final.nodes.last?.step.navigationItemID)
            XCTAssertEqual(final.currentRound.items.map(\.disposition), [.visited, .deferred])
            XCTAssertEqual(final.currentRound.counts.completed, 0)
            XCTAssertEqual(try session.context.fetchCount(FetchDescriptor<FieldDraftCheckpointRow>()), 5)
            XCTAssertEqual(try session.context.fetchCount(FetchDescriptor<RoundSessionRevisionRowV1>()), 5)
        }
        try disk.withSession { session in
            let before = try session.writer.currentRevision()
            let final = try session.adapter.reviewedRepetitiveCaptureProgress(workspaceID: fixture.workspace, sourceDraftID: source.draftID)
            XCTAssertFalse(try XCTUnwrap(final.nodes.last).isPendingRoundEffect)
            XCTAssertEqual(try session.writer.currentRevision(), before)
            let passes = session.journal.fullValidationPassCountForTesting
            XCTAssertEqual(try session.adapter.reviewedRepetitiveCaptureProgress(
                workspaceID: fixture.workspace, sourceDraftID: source.draftID), final)
            XCTAssertEqual(session.journal.fullValidationPassCountForTesting - passes, 1)

            // No prior read can hide later corruption, even on a receipt the
            // progress callbacks do not request (the pre-launch Round creation).
            let creationID = fixture.draft.mutationID.rawValue
            let creation = try XCTUnwrap(session.context.fetch(FetchDescriptor<MutationReceiptRow>(
                predicate: #Predicate { $0.mutationID == creationID })).first)
            let originalSHA = creation.envelopeSHA256
            creation.envelopeSHA256 = String(repeating: "0", count: 64)
            XCTAssertTrue(session.context.hasChanges)
            XCTAssertThrowsError(try session.adapter.reviewedRepetitiveCaptureProgress(
                workspaceID: fixture.workspace, sourceDraftID: source.draftID)) {
                XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .persistenceFailed)
            }
            try session.context.save()
            XCTAssertThrowsError(try session.adapter.reviewedRepetitiveCaptureProgress(
                workspaceID: fixture.workspace, sourceDraftID: source.draftID))
            creation.envelopeSHA256 = originalSHA
            try session.context.save()
            XCTAssertEqual(try session.adapter.reviewedRepetitiveCaptureProgress(
                workspaceID: fixture.workspace, sourceDraftID: source.draftID), final)

            let sourceID = source.mutationID.rawValue
            let sourceRow = try XCTUnwrap(session.context.fetch(FetchDescriptor<MutationReceiptRow>(
                predicate: #Predicate { $0.mutationID == sourceID })).first)
            let quarantine = MutationQuarantineRow(workspaceID: fixture.workspace,
                mutationID: source.mutationID, identityDomain: .mutationEnvelope,
                acceptedIdentitySHA256: sourceRow.envelopeSHA256,
                conflictingIdentitySHA256: String(repeating: "0", count: 64), detectedAt: ProgressFixture.date)
            session.context.insert(quarantine)
            try session.context.save()
            XCTAssertThrowsError(try session.adapter.reviewedRepetitiveCaptureProgress(
                workspaceID: fixture.workspace, sourceDraftID: source.draftID)) {
                XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
            }
            session.context.delete(quarantine)
            try session.context.save()
            XCTAssertEqual(try session.adapter.reviewedRepetitiveCaptureProgress(
                workspaceID: fixture.workspace, sourceDraftID: source.draftID), final)
            // Observe this exact graph's fence-read count, then fail its final
            // epoch reproof with a non-registry error. No fixed count is assumed.
            let readsBefore = disk.fenceProbe.reads
            XCTAssertEqual(try session.adapter.reviewedRepetitiveCaptureProgress(
                workspaceID: fixture.workspace, sourceDraftID: source.draftID), final)
            let readsPerChain = disk.fenceProbe.reads - readsBefore
            XCTAssertGreaterThan(readsPerChain, 1)
            disk.fenceProbe.failOnRead = disk.fenceProbe.reads + readsPerChain
            XCTAssertThrowsError(try session.adapter.reviewedRepetitiveCaptureProgress(
                workspaceID: fixture.workspace, sourceDraftID: source.draftID)) {
                XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .persistenceFailed)
            }
            disk.fenceProbe.failOnRead = nil
            XCTAssertEqual(try session.adapter.reviewedRepetitiveCaptureProgress(
                workspaceID: fixture.workspace, sourceDraftID: source.draftID), final)

            try session.writer.withProvenLease {
                disk.fenceProbe.failOnRead = disk.fenceProbe.reads + 1
                XCTAssertThrowsError(try session.adapter.reviewedRepetitiveCaptureProgress(
                    workspaceID: fixture.workspace, sourceDraftID: source.draftID)) {
                    XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .persistenceFailed)
                }
                // Failure must poison the outer proof, so this subsequent read
                // cannot silently reuse it and bypass the newly failing fence.
                disk.fenceProbe.failOnRead = disk.fenceProbe.reads + 1
                XCTAssertThrowsError(try session.writer.currentRevision()) {
                    XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .persistenceFailed)
                }
                disk.fenceProbe.failOnRead = nil
            }
            let wrongContext = ModelContext(session.context.container)
            XCTAssertThrowsError(try session.writer.reviewedRepetitiveCaptureProgressInReadScope(
                workspaceID: fixture.workspace, sourceDraftID: source.draftID, modelContext: wrongContext)) {
                XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .persistenceFailed)
            }
        }
    }

    @MainActor
    func testSourceRequiresActualRoundAndRejectsPhysicalOnlyDraftAndStaleWriter() throws {
        let fixture = try ProgressFixture(count: 1), disk = try ProgressDisk(workspaceID: fixture.workspace)
        defer { disk.removeClosedFiles() }
        try disk.withSession { session in
            let source = try fixture.source(), before = try session.writer.currentRevision()
            XCTAssertThrowsError(try session.adapter.persistRepetitiveCaptureProgressSource(source))
            XCTAssertEqual(try session.writer.currentRevision(), before)
            _ = try session.writer.commitRoundSession(fixture.creationMutation)
            _ = try session.writer.commitRoundSession(fixture.activationMutation)
            session.context.insert(try FieldDraftCheckpointRow(source)); try session.context.save()
            XCTAssertThrowsError(try session.adapter.reviewedRepetitiveCaptureProgress(workspaceID: fixture.workspace, sourceDraftID: source.draftID))
            session.writer.invalidate()
            XCTAssertThrowsError(try session.adapter.persistRepetitiveCaptureProgressSource(source))
        }
    }

    @MainActor
    func testPendingChainRejectsMissingPriorForkAndExternalRoundTransitionBeforeEffects() throws {
        let fixture = try ProgressFixture(count: 2), disk = try ProgressDisk(workspaceID: fixture.workspace)
        defer { disk.removeClosedFiles() }
        try disk.withSession { session in
            _ = try session.writer.commitRoundSession(fixture.creationMutation)
            _ = try session.writer.commitRoundSession(fixture.activationMutation)
            let source = try fixture.source()
            _ = try session.adapter.persistRepetitiveCaptureProgressSource(source)
            let first = fixture.active.items[0]
            let visit = try fixture.mutation(from: fixture.active, itemID: first.itemID, transition: .visitItem)
            let entry = try fixture.progressCheckpoint(fixture.step(source: source, expected: fixture.active, itemID: first.itemID, action: .enter, mutation: visit))
            _ = try session.adapter.persistRepetitiveCaptureProgressStep(entry)
            let competing = try fixture.progressCheckpoint(fixture.step(source: source, expected: fixture.active, itemID: first.itemID, action: .enter, mutation: visit))
            let before = try session.writer.currentRevision()
            XCTAssertThrowsError(try session.adapter.persistRepetitiveCaptureProgressStep(competing))
            XCTAssertEqual(try session.writer.currentRevision(), before)
            let external = try fixture.mutation(from: fixture.active, itemID: fixture.active.items[1].itemID, transition: .deferItem)
            _ = try session.writer.commitRoundSession(external)
            let afterExternal = try session.writer.currentRevision()
            XCTAssertThrowsError(try session.adapter.reviewedRepetitiveCaptureProgress(workspaceID: fixture.workspace, sourceDraftID: source.draftID))
            XCTAssertEqual(try session.writer.currentRevision(), afterExternal)
        }
    }

    @MainActor
    func testOrphanRoundSuccessorIsNotAnInterruptedCanonicalEffect() throws {
        let fixture = try ProgressFixture(count: 1), disk = try ProgressDisk(workspaceID: fixture.workspace)
        defer { disk.removeClosedFiles() }
        try disk.withSession { session in
            _ = try session.writer.commitRoundSession(fixture.creationMutation)
            _ = try session.writer.commitRoundSession(fixture.activationMutation)
            let source = try fixture.source()
            _ = try session.adapter.persistRepetitiveCaptureProgressSource(source)
            let visit = try fixture.mutation(from: fixture.active, itemID: fixture.active.items[0].itemID, transition: .visitItem)
            let entry = try fixture.progressCheckpoint(fixture.step(source: source, expected: fixture.active,
                itemID: fixture.active.items[0].itemID, action: .enter, mutation: visit))
            _ = try session.adapter.persistRepetitiveCaptureProgressStep(entry)
            session.context.insert(try RoundSessionRevisionRowV1(visit.session)); try session.context.save()
            let beforeRows = try session.context.fetchCount(FetchDescriptor<MutationReceiptRow>())
            XCTAssertThrowsError(try session.adapter.reviewedRepetitiveCaptureProgress(workspaceID: fixture.workspace, sourceDraftID: source.draftID))
            XCTAssertEqual(try session.context.fetchCount(FetchDescriptor<MutationReceiptRow>()), beforeRows)
        }
    }

    @MainActor
    func testDistinctRepeatedEntryAfterReceiptIsRejectedButExactCheckpointRetryRemainsValid() throws {
        let fixture = try ProgressFixture(count: 1), disk = try ProgressDisk(workspaceID: fixture.workspace)
        defer { disk.removeClosedFiles() }
        try disk.withSession { session in
            _ = try session.writer.commitRoundSession(fixture.creationMutation)
            _ = try session.writer.commitRoundSession(fixture.activationMutation)
            let source = try fixture.source()
            _ = try session.adapter.persistRepetitiveCaptureProgressSource(source)
            let item = fixture.active.items[0], visit = try fixture.mutation(from: fixture.active, itemID: fixture.active.items[0].itemID, transition: .visitItem)
            let entry = try fixture.progressCheckpoint(fixture.step(source: source, expected: fixture.active, itemID: item.itemID, action: .enter, mutation: visit))
            _ = try session.adapter.persistRepetitiveCaptureProgressStep(entry)
            let receipt = try session.writer.commitRoundSession(visit)
            let repeatEntry = try fixture.progressCheckpoint(fixture.step(source: source, prior: entry, priorReceipt: receipt,
                expected: visit.session, itemID: item.itemID, action: .enter, mutation: nil))
            let before = try session.writer.currentRevision()
            XCTAssertThrowsError(try session.adapter.persistRepetitiveCaptureProgressStep(repeatEntry))
            let replay = try session.adapter.persistRepetitiveCaptureProgressStep(entry)
            XCTAssertEqual(replay.nodes.count, 1)
            XCTAssertEqual(replay.nodes.first?.roundReceipt, receipt)
            XCTAssertEqual(try session.writer.currentRevision(), before)
        }
    }

    func testMixedLaunchUsesRoundOrderAndPreservesEveryDispositionCount() throws {
        let fixture = try ProgressFixture(count: 6)
        var round = fixture.active
        let transitions: [(Int, RoundSessionTransitionV1)] = [
            (0, .visitItem), (0, .completeItem), (1, .deferItem),
            (2, .markInaccessible), (3, .skipItem), (4, .visitItem)
        ]
        for (index, transition) in transitions {
            round = try fixture.mutation(from: round, itemID: round.items[index].itemID, transition: transition).session
        }
        let source = try fixture.source(round: round)
        let launch = try RepetitiveCaptureProgressDraftCodecV2.source(source)
        XCTAssertEqual(launch.round.items.map(\.disposition), [.completed, .deferred, .inaccessible, .skipped, .visited, .pending])
        XCTAssertEqual(launch.firstIncompleteItemID, round.items[4].itemID)
        XCTAssertEqual(launch.round.counts.completed, 1)
        XCTAssertEqual(launch.round.counts.deferred, 1)
        XCTAssertEqual(launch.round.counts.inaccessible, 1)
        XCTAssertEqual(launch.round.counts.skipped, 1)
        XCTAssertEqual(launch.round.counts.undispositioned, 2)
        let advance = try fixture.step(source: source, expected: round, itemID: round.items[4].itemID,
            action: .keepOpenAndNext, mutation: nil)
        XCTAssertEqual(advance.navigationItemID, round.items[5].itemID)
        XCTAssertEqual(advance.resultingRound, round)
    }

    @MainActor
    func testGenericCheckpointCorpusOverOnePassBoundIsRejectedWithoutEffects() throws {
        let fixture = try ProgressFixture(count: 1), disk = try ProgressDisk(workspaceID: fixture.workspace)
        defer { disk.removeClosedFiles() }
        try disk.withSession { session in
            _ = try session.writer.commitRoundSession(fixture.creationMutation)
            _ = try session.writer.commitRoundSession(fixture.activationMutation)
            let source = try fixture.source()
            _ = try session.adapter.persistRepetitiveCaptureProgressSource(source)
            let item = fixture.active.items[0], visit = try fixture.mutation(from: fixture.active, itemID: fixture.active.items[0].itemID, transition: .visitItem)
            let step = try fixture.step(source: source, expected: fixture.active, itemID: item.itemID, action: .enter, mutation: visit)
            for _ in 0...2 {
                let checkpoint = try fixture.progressCheckpoint(step)
                _ = try session.adapter.compareAndSwap(checkpoint: checkpoint, expectedDraftRevision: 0, expectedBaseRevision: 0)
            }
            let before = try session.writer.currentRevision()
            XCTAssertThrowsError(try session.adapter.reviewedRepetitiveCaptureProgress(workspaceID: fixture.workspace, sourceDraftID: source.draftID)) {
                XCTAssertEqual($0 as? FieldDraftFailureV1, .limitExceeded)
            }
            XCTAssertEqual(try session.writer.currentRevision(), before)
        }
    }

    @MainActor
    func testRoundEffectBeforeProgressCheckpointCannotBeResealedAsValidNavigation() throws {
        let fixture = try ProgressFixture(count: 1), disk = try ProgressDisk(workspaceID: fixture.workspace)
        defer { disk.removeClosedFiles() }
        try disk.withSession { session in
            _ = try session.writer.commitRoundSession(fixture.creationMutation)
            _ = try session.writer.commitRoundSession(fixture.activationMutation)
            let source = try fixture.source()
            _ = try session.adapter.persistRepetitiveCaptureProgressSource(source)
            let visit = try fixture.mutation(from: fixture.active, itemID: fixture.active.items[0].itemID, transition: .visitItem)
            let entry = try fixture.progressCheckpoint(fixture.step(source: source, expected: fixture.active,
                itemID: fixture.active.items[0].itemID, action: .enter, mutation: visit))
            _ = try session.writer.commitRoundSession(visit)
            _ = try session.adapter.compareAndSwap(checkpoint: entry, expectedDraftRevision: 0, expectedBaseRevision: 0)
            let before = try session.writer.currentRevision()
            XCTAssertThrowsError(try session.adapter.reviewedRepetitiveCaptureProgress(workspaceID: fixture.workspace, sourceDraftID: source.draftID))
            XCTAssertEqual(try session.writer.currentRevision(), before)
        }
    }

    @MainActor
    func testCommittedCompetingCheckpointCannotBecomeASecondChainTip() throws {
        let fixture = try ProgressFixture(count: 1), disk = try ProgressDisk(workspaceID: fixture.workspace)
        defer { disk.removeClosedFiles() }
        try disk.withSession { session in
            _ = try session.writer.commitRoundSession(fixture.creationMutation)
            _ = try session.writer.commitRoundSession(fixture.activationMutation)
            let source = try fixture.source()
            _ = try session.adapter.persistRepetitiveCaptureProgressSource(source)
            let first = fixture.active.items[0], visit = try fixture.mutation(from: fixture.active, itemID: fixture.active.items[0].itemID, transition: .visitItem)
            let step = try fixture.step(source: source, expected: fixture.active, itemID: first.itemID, action: .enter, mutation: visit)
            let entry = try fixture.progressCheckpoint(step), competing = try fixture.progressCheckpoint(step)
            _ = try session.adapter.persistRepetitiveCaptureProgressStep(entry)
            // A canonical C36 write outside this producer must still fail
            // closed when read as a purported second continuation.
            _ = try session.adapter.compareAndSwap(checkpoint: competing, expectedDraftRevision: 0, expectedBaseRevision: 0)
            let before = try session.writer.currentRevision()
            XCTAssertThrowsError(try session.adapter.reviewedRepetitiveCaptureProgress(workspaceID: fixture.workspace, sourceDraftID: source.draftID))
            XCTAssertEqual(try session.writer.currentRevision(), before)
        }
    }
}

private struct ProgressFixture {
    static let date = Date(timeIntervalSince1970: 1_788_134_400)
    let workspace: WorkspaceID
    let planID = UUID()
    let draft: RoundSessionV1
    let active: RoundSessionV1
    let manifest: OfflineReadinessManifestV1

    init(count: Int) throws {
        workspace = WorkspaceID(rawValue: UUID())
        let package = try Self.package()
        let items = try (0..<count).map { index in
            try RoundItemV1(itemID: UUID(), order: index,
                selection: .init(assetID: UUID(), siteID: UUID(), labelAtSelection: "Asset \(index)"),
                requirement: .init(packageRelease: package, requiredContent: []))
        }
        let actor = try Self.actor(workspace)
        draft = try .init(workspaceID: workspace, sessionID: UUID(), predecessor: nil, revision: 1,
            mutationID: .init(rawValue: UUID()), state: .draft, transition: .create, items: items,
            recordedBy: actor, recordedAt: Self.date)
        active = try .init(workspaceID: workspace, sessionID: draft.sessionID, predecessor: draft, revision: 2,
            mutationID: .init(rawValue: UUID()), state: .active, transition: .start, items: items,
            recordedBy: actor, recordedAt: Self.date)
        manifest = try Self.manifest(round: active, checkedAt: Self.date)
    }
    var creationMutation: RoundSessionMutationV1 { get throws { try .init(workspaceID: workspace, expectedRevision: 0, mutationID: draft.mutationID, session: draft) } }
    var activationMutation: RoundSessionMutationV1 { get throws { try .init(workspaceID: workspace, expectedRevision: 1, mutationID: active.mutationID, session: active) } }
    func makeManifest(round: RoundSessionV1, checkedAt: Date) throws -> OfflineReadinessManifestV1 { try Self.manifest(round: round, checkedAt: checkedAt) }
    func source(round: RoundSessionV1? = nil, anchorOverride: DraftResumeAnchorV1? = nil) throws -> FieldDraftCheckpointV1 {
        let selected = round ?? active
        let readiness = try round.map { try Self.manifest(round: $0, checkedAt: Self.date) } ?? manifest
        let launch = try RepetitiveCaptureLaunchSourceV2(planID: planID, round: selected,
            readiness: selected.items.map { try .init(manifest: readiness, assetID: $0.selection.assetID) })
        return try checkpoint(.source(launch), anchor: anchorOverride ?? .init(sectionID: "facts", selectedStableID:
            selected.items.first { !$0.disposition.isTerminal }?.selection.assetID.uuidString.lowercased()))
    }
    func step(source: FieldDraftCheckpointV1, prior: FieldDraftCheckpointV1? = nil,
              priorReceipt: RoundSessionMutationReceiptV1? = nil, expected: RoundSessionV1, itemID: UUID,
              action: RepetitiveCaptureProgressActionV2, mutation: RoundSessionMutationV1?) throws -> RepetitiveCaptureProgressStepV2 {
        let index = try XCTUnwrap(expected.items.firstIndex { $0.itemID == itemID })
        let result = mutation?.session ?? expected
        let next = action == .enter ? itemID : result.items.dropFirst(index + 1).first { !$0.disposition.isTerminal }?.itemID
        let asset = result.items.first { $0.itemID == next }?.selection.assetID
        return try .init(source: .init(source: source), prior: prior.map { try .init(source: $0) },
            priorRoundReceipt: priorReceipt, expectedRound: expected, itemID: itemID, action: action,
            roundMutation: mutation, requirementFocus: .facts,
            resumeAnchor: .init(sectionID: "facts", selectedStableID: asset?.uuidString.lowercased()))
    }
    func progressCheckpoint(_ step: RepetitiveCaptureProgressStepV2) throws -> FieldDraftCheckpointV1 { try checkpoint(.progress(step), anchor: step.resumeAnchor) }
    private func checkpoint(_ payload: RepetitiveCaptureProgressDraftPayloadV2, anchor: DraftResumeAnchorV1) throws -> FieldDraftCheckpointV1 {
        try .init(draftID: UUID(), workspaceID: workspace,
            scope: RepetitiveCaptureDraftCodecV1.scope(planID: planID, round: active.reference), purpose: .repetitiveCapture,
            codec: RepetitiveCaptureProgressDraftCodecV2.release(), baseCanonicalRevision: 0, draftRevision: 1,
            payloadData: RepetitiveCaptureProgressDraftCodecV2.encode(payload), stageIDs: [], resumeAnchor: anchor,
            state: .active, updatedAt: Self.date, mutationID: .init(rawValue: UUID()))
    }
    func mutation(from prior: RoundSessionV1, itemID: UUID, transition: RoundSessionTransitionV1) throws -> RoundSessionMutationV1 {
        let index = try XCTUnwrap(prior.items.firstIndex { $0.itemID == itemID }), old = prior.items[index]
        let actor = try Self.actor(workspace)
        var items = prior.items
        let disposition: RoundItemDispositionV1
        let visit: RoundItemVisitV1?
        let reason: RoundItemReasonV1?
        let completion: RoundItemCompletionReferenceV1?
        switch transition {
        case .visitItem: disposition = .visited; visit = try .init(visitedAt: Self.date, recordedBy: actor); reason = nil; completion = nil
        case .deferItem: disposition = .deferred; visit = old.visit; reason = .userDeferred; completion = nil
        case .markInaccessible: disposition = .inaccessible; visit = old.visit; reason = .physicalAccessUnavailable; completion = nil
        case .skipItem: disposition = .skipped; visit = old.visit; reason = .explicitlyOutOfScope; completion = nil
        case .completeItem: disposition = .completed; visit = old.visit; reason = nil; completion = try .init(completionID: UUID(), revision: 1, completionSHA256: String(repeating: "c", count: 64))
        default: throw ScanToWorkFailureV1.invalidValue
        }
        items[index] = try .init(itemID: old.itemID, order: old.order, selection: old.selection,
            requirement: old.requirement, disposition: disposition, visit: visit, reason: reason, completion: completion)
        let successor = try RoundSessionV1(workspaceID: workspace, sessionID: prior.sessionID, predecessor: prior,
            revision: prior.revision + 1, mutationID: .init(rawValue: UUID()), state: .active,
            transition: transition, transitionItemID: itemID, items: items, recordedBy: actor, recordedAt: Self.date)
        return try .init(workspaceID: workspace, expectedRevision: prior.revision, mutationID: successor.mutationID, session: successor)
    }
    private static func package() throws -> RoundPackageReleaseReferenceV1 {
        try .init(packageReleaseID: String(repeating: "a", count: 64), packageID: "c36-progress", packageContentVersion: 1,
            packageSHA256: String(repeating: "a", count: 64), workflowSHA256: String(repeating: "b", count: 64))
    }
    private static func actor(_ workspace: WorkspaceID) throws -> ActorSnapshotV1 {
        let actor = try LocalActorReferenceV1(actorReferenceID: UUID(), workspaceID: workspace, displayName: "C36")
        return try .init(snapshotID: UUID(), workspaceID: workspace, actor: actor, responsibility: .recordedBy,
            displayNameAtTime: "C36", capturedAt: date)
    }
    private static func manifest(round: RoundSessionV1, checkedAt: Date) throws -> OfflineReadinessManifestV1 {
        try OfflineReadinessManifestBuilderV1.build(snapshot: .init(session: round.reference,
            expectedPackage: package(), observedPackage: package(),
            selectedAssets: round.items.map(\.selection).sorted { $0.assetID.uuidString < $1.assetID.uuidString },
            observedAssetIDs: Set(round.items.map { $0.selection.assetID }), guidanceReferenceIDs: [], availableGuidanceReferenceIDs: [],
            contentRequirements: [], contentObservations: [], expectedFieldReferences: [], fieldReferenceReadiness: [],
            storage: .init(capacityState: .checked, availableBytes: 100_000), access: .init(protectedDataAvailable: true),
            checkedAt: checkedAt, timeZoneIdentifier: "America/New_York", clockState: .checked))
    }
}

private enum ProgressFenceProbeFailure: Error { case unavailableEpoch }

@MainActor
private final class ProgressFenceProbe {
    var reads = 0
    var failOnRead: Int?
    func read(_ epoch: GenerationEpochV1) throws -> GenerationEpochV1 {
        reads += 1
        if reads == failOnRead { throw ProgressFenceProbeFailure.unavailableEpoch }
        return epoch
    }
}

@MainActor
private final class ProgressDisk {
    let root: URL
    private let identity: WorkspaceReplicaIdentityV1
    private let generationID: UUID
    private let fence: StaleWriterFenceV1
    private let registry: GenerationLeaseRegistryV1
    let fenceProbe = ProgressFenceProbe()
    private var bootstrap = true
    init(workspaceID: WorkspaceID) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("V23-progress-v2-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        identity = try .init(workspaceID: workspaceID, replicaID: .init(rawValue: UUID())); generationID = UUID()
        let epoch = try GenerationEpochV1(generationID: generationID, generationManifestSHA256: String(repeating: "a", count: 64))
        registry = try GenerationLeaseRegistryV1(applicationSupportURL: root)
        let lease = try registry.acquire(epoch: epoch, role: .writer)
        let probe = fenceProbe
        fence = try StaleWriterFenceV1(expectedGenerationEpoch: epoch, writerLeaseToken: lease,
            registry: registry, currentGenerationEpoch: { try probe.read(epoch) })
    }
    struct Session {
        let context: ModelContext
        let writer: WorkspaceWriterV1
        let journal: MutationJournalStoreV1
        let adapter: FieldDraftLifecycleAdapterV1
    }
    func withSession<T>(_ body: (Session) throws -> T) throws -> T {
        try autoreleasepool {
            let schema = Schema(PersistentSchemaV53.models, version: PersistentSchemaV53.versionIdentifier)
            let container = try ModelContainer(for: schema, migrationPlan: nil, configurations: [
                ModelConfiguration("ProgressV2", schema: schema, url: root.appendingPathComponent("progress.store"),
                                   allowsSave: true, cloudKitDatabase: .none)
            ])
            let context = ModelContext(container); context.autosaveEnabled = false
            let journal = try MutationJournalStoreV1(modelContext: context, identity: identity, generationID: generationID,
                allowStateBootstrap: bootstrap, staleWriterFence: fence)
            bootstrap = false
            let instance = UUID()
            let writer = try WorkspaceWriterV1(identity: identity, generationID: generationID,
                initialRevision: journal.currentRevision(writerInstanceID: instance), clock: ProgressClock(),
                idSource: ProgressIDs(instance: instance), fileAuthority: ProgressFiles(),
                adapter: WorkspaceWriterAdapterV1(modelContext: context), journalStore: journal)
            defer { writer.invalidate() }
            return try body(.init(context: context, writer: writer, journal: journal,
                adapter: .init(writer: writer, journal: journal, modelContext: context)))
        }
    }
    func removeClosedFiles() { try? FileManager.default.removeItem(at: root) }
}
private struct ProgressClock: ApplicationClock { func now() -> Date { ProgressFixture.date } }
private struct ProgressIDs: ApplicationIDSource { let instance: UUID; func makeID() -> UUID { instance } }
private struct ProgressFiles: ApplicationFileAuthorityV1 {
    func temporaryRelativePath(mutationID: MutationIDV1, component: String) throws -> String {
        "repetitive-progress/\(mutationID.rawValue.uuidString.lowercased())/\(component)"
    }
}

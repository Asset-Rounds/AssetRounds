import Foundation
import SwiftData
import XCTest

@testable import FieldEvidenceApp

final class V23RepetitiveCaptureDestinationResolutionTests: XCTestCase {
    @MainActor
    func testContinueUsesActualWriterReceiptAndPreservesRoundSourceAndReplay() throws {
        let source = try RepetitiveCaptureSourcePackageFixture(sourceOnly: true)
        defer { source.removePackages() }
        for mode in [BackupRestoreMode.fork, .replaceExisting] {
            let fixture = try RepetitiveResolutionFixture(source: source, mode: mode)
            defer { try? fixture.close() }
            let lineage = try fixture.lineage()
            let rounds = try fixture.rounds()
            let expected: [RoundSessionV1]
            if mode == .fork {
                expected = try C05RoundSessionRestoreIdentityBoundaryV1.rebinding(source.rounds, identity: fixture.identity)
            } else {
                let original = try ReferenceOwnerReplacementSourceV1.source(workspaceID: source.workspaceID,
                                                                           history: source.history)
                expected = try RoundSessionReplacementCommandProjectionV1.project(source: original,
                    identity: fixture.identity).commands.map { $0.mutation.session }
            }
            XCTAssertEqual(try RepetitiveCaptureDestinationResolutionV1.restoredRoundPrefix(from: lineage), expected)
            XCTAssertEqual(rounds, expected)
            let resolution = try fixture.propose(.continueEditing, mutationSeed: 1)
            let mutation = try resolutionMutation(resolution)
            let request = try fixture.request(mutation)
            XCTAssertEqual(Set(try mutation.concurrencyIdentities), Set([
                try WorkspaceEntityIdentityV1(kind: .fieldDraftCheckpoint, id: fixture.initialCheckpoint.draftID),
                try WorkspaceEntityIdentityV1(kind: .roundSession, id: XCTUnwrap(rounds.last).sessionID)
            ]))
            let before = try fixture.target.rawState()
            let outcome = try fixture.target.writer.execute(request)
            let original = try XCTUnwrap(fixture.target.writer.fieldDraftEvidence(mutationID: mutation.mutationID))
            let evidence = try ReviewedFieldDraftResolutionEvidenceV1(original: original)
            XCTAssertEqual(evidence.resolution, resolution)
            XCTAssertEqual(original.envelope.expectedRevision.workspaceID, request.expectedRevision.workspaceID)
            XCTAssertEqual(original.envelope.expectedRevision.generationID, request.expectedRevision.generationID)
            XCTAssertEqual(original.envelope.expectedRevision.workspaceRevision, request.expectedRevision.workspaceRevision)
            XCTAssertEqual(original.envelope.expectedRevision.entityRevisions,
                           request.expectedRevision.entityRevisions.sorted { $0.identity.stableKey < $1.identity.stableKey })
            XCTAssertEqual(outcome.effect.affectedEntities,
                           [try WorkspaceEntityIdentityV1(kind: .fieldDraftCheckpoint, id: fixture.initialCheckpoint.draftID)])
            XCTAssertEqual(try fixture.currentCheckpoint(), resolution.successorCheckpoint)
            XCTAssertEqual(try fixture.rounds(), rounds)
            XCTAssertEqual(try fixture.target.rawState().canonicalCounts, before.canonicalCounts)
            try fixture.assertOriginalsRetained()
            let after = try fixture.target.rawState()
            let replay = try fixture.target.writer.execute(request)
            XCTAssertEqual(replay.mutationID, outcome.mutationID)
            XCTAssertEqual(replay.commandDigest, outcome.commandDigest)
            XCTAssertEqual(replay.occurredAt, original.receipt.committedAt)
            XCTAssertEqual(try WorkspaceMutationCanonicalV1.data(replay.occurredAt),
                           try WorkspaceMutationCanonicalV1.data(outcome.occurredAt))
            XCTAssertEqual(replay.after, outcome.after)
            XCTAssertEqual(replay.effect, outcome.effect)
            // Durable replay reconstructs its basis from the saved envelope.
            let expectedRevision = original.envelope.expectedRevision
            XCTAssertEqual(replay.before.workspaceID, expectedRevision.workspaceID)
            XCTAssertEqual(replay.before.generationID, expectedRevision.generationID)
            XCTAssertEqual(replay.before.writerInstanceID, outcome.before.writerInstanceID)
            XCTAssertEqual(replay.before.revision, expectedRevision.workspaceRevision)
            XCTAssertEqual(replay.before.entityRevisions, expectedRevision.entityRevisions)
            XCTAssertEqual(try fixture.target.rawState(), after)
            let resolved = try fixture.lineage()
            XCTAssertEqual(resolved.selectedReview.prefix.count, 2)
            XCTAssertEqual(resolved.selectedReview.checkpoint, resolution.successorCheckpoint)
            XCTAssertEqual(resolved.selectedReview.payload, lineage.selectedReview.payload)
            XCTAssertEqual(resolution.successorCheckpoint.state, .active)
            XCTAssertEqual(resolution.successorCheckpoint.codec, fixture.initialCheckpoint.codec)
            XCTAssertNil(resolution.successorCheckpoint.lastDurableMutationID)
            // There is still one review checkpoint and no operational V2
            // continuation, Round effect, saga, reservation or stage.
            XCTAssertEqual(try fixture.target.context.fetchCount(FetchDescriptor<DraftCommitSagaRow>()), 0)
            XCTAssertEqual(try fixture.target.context.fetchCount(FetchDescriptor<AttachmentStagingItemRow>()), 0)
            XCTAssertEqual(try fixture.target.context.fetchCount(FetchDescriptor<DraftContentReservationRow>()), 0)
        }
    }

    @MainActor
    func testRebaseRequiresAnAdvancedMappedRoundAndGrantsNoReadinessOrRoundEffect() throws {
        let source = try RepetitiveCaptureSourcePackageFixture(sourceOnly: true)
        defer { source.removePackages() }
        let fixture = try RepetitiveResolutionFixture(source: source)
        defer { try? fixture.close() }
        XCTAssertThrowsError(try fixture.propose(.reviewAndRebase, mutationSeed: 10))
        try fixture.advance(.pause, state: .paused, mutationSeed: 11)
        XCTAssertThrowsError(try fixture.propose(.continueEditing, mutationSeed: 12))
        let pausedReview = try fixture.propose(.reviewAndRebase, mutationSeed: 13)
        XCTAssertEqual(pausedReview.successorCheckpoint.state, .active)
        XCTAssertEqual(try fixture.rounds().last?.state, .paused)
        try fixture.advance(.resume, state: .active, mutationSeed: 14)
        XCTAssertThrowsError(try fixture.propose(.continueEditing, mutationSeed: 15))
        let rounds = try fixture.rounds()
        let resolution = try fixture.propose(.reviewAndRebase, mutationSeed: 16)
        XCTAssertEqual(resolution.successorCheckpoint.baseCanonicalRevision, try XCTUnwrap(rounds.last).revision)
        XCTAssertGreaterThan(resolution.successorCheckpoint.baseCanonicalRevision, fixture.initialCheckpoint.baseCanonicalRevision)
        let request = try fixture.request(resolutionMutation(resolution))
        _ = try fixture.target.writer.execute(request)
        let evidence = try XCTUnwrap(fixture.target.writer.fieldDraftEvidence(mutationID: request.mutationID))
        XCTAssertEqual(try ReviewedFieldDraftResolutionEvidenceV1(original: evidence).resolution, resolution)
        XCTAssertEqual(try fixture.currentCheckpoint(), resolution.successorCheckpoint)
        XCTAssertEqual(try fixture.rounds(), rounds)
        XCTAssertEqual(try fixture.lineage().selectedReview.checkpoint, resolution.successorCheckpoint)
        try fixture.assertOriginalsRetained()
    }

    @MainActor
    func testDiscardBindsAbsentAndArchivedTargetsWithoutLosingHistoryOrRevivingWork() throws {
        let source = try RepetitiveCaptureSourcePackageFixture(sourceOnly: true)
        defer { source.removePackages() }
        for absent in [true, false] {
            let fixture = try RepetitiveResolutionFixture(source: source, materializeRound: !absent)
            defer { try? fixture.close() }
            if !absent { try fixture.archiveRound() }
            let before = try fixture.target.rawState()
            let rounds = try fixture.rounds()
            XCTAssertThrowsError(try fixture.propose(.continueEditing, mutationSeed: 30))
            if absent { XCTAssertThrowsError(try fixture.propose(.reviewAndRebase, mutationSeed: 31)) }
            else {
                XCTAssertEqual(try fixture.propose(.reviewAndRebase, mutationSeed: 31).successorCheckpoint.state, .active)
                XCTAssertEqual(rounds.last?.state, .archived)
            }
            XCTAssertThrowsError(try fixture.propose(.commitAsCopy, mutationSeed: 32))
            XCTAssertEqual(try fixture.target.rawState(), before)
            let resolution = try fixture.propose(.discard, mutationSeed: 33)
            let mutation = try resolutionMutation(resolution)
            XCTAssertEqual(try mutation.concurrencyIdentities.count, 1)
            XCTAssertNil(resolution.reviewedTargetBasis.existingIdentity)
            let request = try fixture.request(mutation)
            _ = try fixture.target.writer.execute(request)
            let original = try XCTUnwrap(fixture.target.writer.fieldDraftEvidence(mutationID: request.mutationID))
            XCTAssertEqual(try ReviewedFieldDraftResolutionEvidenceV1(original: original).resolution, resolution)
            XCTAssertEqual(try fixture.currentCheckpoint().state, .discardPending)
            XCTAssertEqual(try fixture.currentCheckpoint().payloadData, fixture.initialCheckpoint.payloadData)
            XCTAssertEqual(try fixture.rounds(), rounds)
            XCTAssertEqual(try fixture.target.rawState().canonicalCounts, before.canonicalCounts)
            try fixture.assertOriginalsRetained()
            // This receipt is the reviewed pending disposition. The existing
            // confirmation and terminal discard bundle are separate work.
            XCTAssertEqual(try fixture.target.context.fetchCount(FetchDescriptor<DraftDiscardReceiptRow>()), 0)
        }
    }
    @MainActor
    func testClosedTargetContractRejectsUnboundClaimsAndWrongRoundDigestWithoutEffects() throws {
        let source = try RepetitiveCaptureSourcePackageFixture(sourceOnly: true)
        defer { source.removePackages() }
        let fixture = try RepetitiveResolutionFixture(source: source)
        defer { try? fixture.close() }
        let resolution = try fixture.propose(.continueEditing, mutationSeed: 201)
        let bytes = try FieldDraftCanonicalCodecV1.encode(resolution.reviewedTargetBasis)
        XCTAssertEqual(try FieldDraftCanonicalCodecV1.decode(ReviewedDraftTargetBasisV1.self, from: bytes),
                       resolution.reviewedTargetBasis)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        let target = try XCTUnwrap(object["repetitiveCapture"] as? [String: Any])
        var variants: [[String: Any]] = []
        var extra = target; extra["ready"] = true
        variants.append(["repetitiveCapture": extra])
        var version = target; version["schemaVersion"] = 2
        variants.append(["repetitiveCapture": version])
        var tag = target; tag["tag"] = "REPETITIVE_CAPTURE_REVIEW_ONLY"
        variants.append(["repetitiveCapture": tag])
        var missing = target; missing.removeValue(forKey: "round")
        variants.append(["repetitiveCapture": missing])
        variants.append(["repetitiveCapture": target, "existing": [:]])
        for variant in variants {
            let data = try JSONSerialization.data(withJSONObject: variant, options: [.sortedKeys])
            XCTAssertThrowsError(try FieldDraftCanonicalCodecV1.decode(ReviewedDraftTargetBasisV1.self, from: data))
        }
        let tip = try XCTUnwrap(fixture.rounds().last)
        let basis = try ReviewedRepetitiveCaptureTargetBasisV1(workspaceID: tip.workspaceID,
            sessionID: tip.sessionID, expectedWorkspaceRevision: fixture.target.writer.currentRevision().revision,
            round: .init(workspaceID: tip.workspaceID, sessionID: tip.sessionID,
                         revision: tip.revision, sessionSHA256: String(repeating: "f", count: 64)))
        let forged = try ReviewedDraftConflictResolutionV1(plan: .continueEditing,
            expectedCheckpoint: resolution.expectedCheckpoint, repetitiveCaptureTargetBasis: basis,
            successorCheckpoint: resolution.successorCheckpoint)
        let before = try fixture.target.rawState()
        XCTAssertThrowsError(try fixture.target.writer.execute(fixture.request(resolutionMutation(forged))))
        XCTAssertEqual(try fixture.target.rawState(), before)
        XCTAssertEqual(try fixture.currentCheckpoint(), fixture.initialCheckpoint)
        let lineage = try fixture.lineage()
        XCTAssertThrowsError(try RepetitiveCaptureDestinationResolutionV1.propose(plan: .continueEditing,
            from: lineage, currentRoundHistory: [], expectedWorkspaceRevision: basis.expectedWorkspaceRevision,
            mutationID: .init(rawValue: resolutionID(202)), reviewedAt: resolution.successorCheckpoint.updatedAt))
        XCTAssertThrowsError(try RepetitiveCaptureDestinationResolutionV1.propose(plan: .continueEditing,
            from: lineage, currentRoundHistory: fixture.rounds(), expectedWorkspaceRevision: basis.expectedWorkspaceRevision,
            mutationID: XCTUnwrap(lineage.retainedSource.requiredHistory.first).envelope.mutationID,
            reviewedAt: resolution.successorCheckpoint.updatedAt))
        let discard = try fixture.propose(.discard, mutationSeed: 203)
        guard case let .repetitiveCapture(reviewOnly) = discard.reviewedTargetBasis else { return XCTFail("Expected C36 basis") }
        XCTAssertEqual(reviewOnly.tag, "REPETITIVE_CAPTURE_REVIEW_ONLY")
        XCTAssertThrowsError(try ReviewedDraftConflictResolutionV1(plan: .continueEditing,
            expectedCheckpoint: resolution.expectedCheckpoint, repetitiveCaptureTargetBasis: reviewOnly,
            successorCheckpoint: resolution.successorCheckpoint))
        XCTAssertThrowsError(try ReviewedDraftConflictResolutionV1(plan: .commitAsCopy,
            expectedCheckpoint: resolution.expectedCheckpoint, repetitiveCaptureTargetBasis: basis,
            successorCheckpoint: resolution.successorCheckpoint))
        XCTAssertEqual(try fixture.target.rawState(), before)
    }

    @MainActor
    func testPreparedProofRejectsContextCommandAndLateRoundChangesAndCannotBeReused() throws {
        let source = try RepetitiveCaptureSourcePackageFixture(sourceOnly: true)
        defer { source.removePackages() }
        let fixture = try RepetitiveResolutionFixture(source: source)
        defer { try? fixture.close() }
        let mutation = try resolutionMutation(fixture.propose(.continueEditing, mutationSeed: 211))
        let changed = try resolutionMutation(fixture.propose(.discard, mutationSeed: 212))
        let before = try fixture.target.rawState()
        let valid = try fixture.proof(mutation)
        try valid.validateForApply(mutation, in: fixture.target.context)
        XCTAssertThrowsError(try valid.validateForApply(mutation, in: fixture.target.context))
        let wrongCommand = try fixture.proof(mutation)
        XCTAssertThrowsError(try wrongCommand.validateForApply(changed, in: fixture.target.context))
        XCTAssertThrowsError(try wrongCommand.validateForApply(mutation, in: fixture.target.context))
        let wrongContext = try fixture.proof(mutation)
        let other = ModelContext(fixture.target.context.container)
        other.autosaveEnabled = false
        XCTAssertThrowsError(try wrongContext.validateForApply(mutation, in: other))
        XCTAssertThrowsError(try wrongContext.validateForApply(mutation, in: fixture.target.context))
        XCTAssertThrowsError(try WorkspaceWriterAdapterV1(modelContext: fixture.target.context).apply(
            .applyFieldDraft(mutation), occurredAt: fixture.initialCheckpoint.updatedAt,
            temporaryRelativePath: "c36-generic-resolution-denial"))
        XCTAssertEqual(try fixture.target.rawState(), before)
        let staleRequest = try fixture.request(mutation)
        let late = try fixture.proof(mutation)
        try fixture.advance(.pause, state: .paused, mutationSeed: 213)
        let advanced = try fixture.target.rawState()
        XCTAssertThrowsError(try late.validateForApply(mutation, in: fixture.target.context))
        XCTAssertThrowsError(try fixture.target.writer.execute(staleRequest))
        XCTAssertThrowsError(try fixture.proof(mutation))
        XCTAssertEqual(try fixture.target.rawState(), advanced)
        XCTAssertEqual(try fixture.currentCheckpoint(), fixture.initialCheckpoint)
        XCTAssertEqual(try fixture.rounds().last?.state, .paused)
    }

    @MainActor
    func testResolutionRechecksDirtyCorruptMissingQuarantinedAndRetiredSourceWithoutEffects() throws {
        let source = try RepetitiveCaptureSourcePackageFixture(sourceOnly: true)
        defer { source.removePackages() }
        let fixture = try RepetitiveResolutionFixture(source: source)
        defer { try? fixture.close() }
        let mutation = try resolutionMutation(fixture.propose(.discard, mutationSeed: 221))
        let original = try XCTUnwrap(fixture.lineage().retainedSource.requiredHistory.first)
        let row = try XCTUnwrap(fixture.target.context.fetch(FetchDescriptor<MutationReceiptRow>()).first {
            $0.workspaceMutationKey == MutationWorkspaceKeyV1.value(
                workspaceID: original.envelope.workspaceID, mutationID: original.envelope.mutationID)
        })
        let digest = row.receiptSHA256
        let before = try fixture.target.rawState()
        let late = try fixture.proof(mutation)
        row.receiptSHA256 = String(repeating: "f", count: 64)
        let dirty = try fixture.target.rawState()
        XCTAssertThrowsError(try fixture.proof(mutation))
        XCTAssertThrowsError(try late.validateForApply(mutation, in: fixture.target.context))
        XCTAssertEqual(try fixture.target.rawState(), dirty)
        fixture.target.context.rollback()
        XCTAssertEqual(try fixture.target.rawState(), before)
        row.receiptSHA256 = String(repeating: "f", count: 64)
        try fixture.target.context.save()
        let corrupt = try fixture.target.rawState()
        XCTAssertThrowsError(try fixture.proof(mutation))
        XCTAssertEqual(try fixture.target.rawState(), corrupt)
        row.receiptSHA256 = digest
        try fixture.target.context.save()
        let quarantine = MutationQuarantineRow(workspaceID: original.envelope.workspaceID,
            mutationID: original.envelope.mutationID, identityDomain: .mutationEnvelope,
            acceptedIdentitySHA256: original.receipt.envelopeSHA256,
            conflictingIdentitySHA256: String(repeating: "b", count: 64),
            detectedAt: fixture.initialCheckpoint.updatedAt)
        fixture.target.context.insert(quarantine)
        try fixture.target.context.save()
        let quarantined = try fixture.target.rawState()
        XCTAssertThrowsError(try fixture.proof(mutation))
        XCTAssertEqual(try fixture.target.rawState(), quarantined)
        fixture.target.context.delete(quarantine)
        try fixture.target.context.save()
        fixture.target.context.delete(row)
        try fixture.target.context.save()
        let missing = try fixture.target.rawState()
        XCTAssertThrowsError(try fixture.proof(mutation))
        XCTAssertEqual(try fixture.target.rawState(), missing)
        try fixture.target.insert(original.original)
        try fixture.target.context.save()
        XCTAssertEqual(try fixture.target.rawState(), before)
        let retiring = try fixture.proof(mutation)
        try fixture.target.closeJournalLease()
        XCTAssertThrowsError(try fixture.proof(mutation))
        XCTAssertThrowsError(try retiring.validateForApply(mutation, in: fixture.target.context))
        fixture.target.writer.invalidate()
        XCTAssertThrowsError(try fixture.target.writer.execute(fixture.request(mutation)))
        XCTAssertEqual(try fixture.target.rawState(), before)
        XCTAssertEqual(try fixture.currentCheckpoint(), fixture.initialCheckpoint)
    }

    @MainActor
    func testReplacementThenForkRetainsOriginalNamespaceAndRequiresFreshReviewReceipt() throws {
        let source = try RepetitiveCaptureSourcePackageFixture(sourceOnly: true)
        defer { source.removePackages() }
        let first = try RepetitiveResolutionFixture(source: source, mode: .replaceExisting)
        defer { try? first.close() }
        let resolution = try first.propose(.continueEditing, mutationSeed: 231)
        _ = try first.target.writer.execute(first.request(resolutionMutation(resolution)))
        let prior = try first.lineage()
        let second = try RepetitiveResolutionFixture(source: source,
            inherited: (prior, first.target.journal.exportSnapshot()))
        defer { try? second.close() }
        XCTAssertEqual(second.initialCheckpoint.state, .recoveryRequired)
        XCTAssertNotEqual(second.initialCheckpoint.draftID, first.initialCheckpoint.draftID)
        XCTAssertNotEqual(second.initialCheckpoint.mutationID, resolution.successorCheckpoint.mutationID)
        let lineage = try second.lineage()
        XCTAssertEqual(lineage.reviews.count, 2)
        XCTAssertEqual(lineage.reviews.first?.checkpoint, resolution.successorCheckpoint)
        let firstRounds = try first.rounds()
        let rounds = try second.rounds()
        XCTAssertEqual(rounds.map(\.mutationID), firstRounds.map(\.mutationID))
        XCTAssertNotEqual(rounds.map(\.mutationID), source.rounds.map(\.mutationID))
        XCTAssertEqual(rounds, try RepetitiveCaptureDestinationResolutionV1.restoredRoundPrefix(from: lineage))
        let next = try second.propose(.continueEditing, mutationSeed: 232)
        _ = try second.target.writer.execute(second.request(resolutionMutation(next)))
        XCTAssertEqual(try second.lineage().selectedReview.checkpoint, next.successorCheckpoint)
        XCTAssertEqual(try second.rounds(), rounds)
        try second.assertOriginalsRetained()
    }
}

private func resolutionID(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "8a000000-0000-0000-0000-%012d", value))!
}

private func resolutionMutation(_ value: ReviewedDraftConflictResolutionV1) throws -> FieldDraftMutationV1 {
    try .init(workspaceID: value.expectedCheckpoint.workspaceID,
        expectedRevision: value.expectedCheckpoint.draftRevision,
        expectedBaseCanonicalRevision: value.expectedCheckpoint.baseCanonicalRevision,
        mutationID: value.successorCheckpoint.mutationID, postImage: .resolveConflict(value))
}

/// A real writer fixture with retained foreign originals and explicit canonical
/// command writes. It does not claim that restore publication or registration ran.
@MainActor
final class RepetitiveResolutionFixture {
    let root: URL
    let target: RetainedSourceHistoryTargetV2
    let identity: RestoreIdentityV1
    let initialCheckpoint: FieldDraftCheckpointV1
    let sourceOriginals: [MutationHistoryReceiptRecordV1]

    init(source: RepetitiveCaptureSourcePackageFixture, mode: BackupRestoreMode = .fork,
         materializeRound: Bool = true,
         inherited: (lineage: RepetitiveCaptureReviewLineageV1, snapshot: MutationHistorySnapshotV1)? = nil) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("c36-resolution-\(UUID().uuidString)")
        sourceOriginals = inherited?.snapshot.receipts ?? source.history.receipts
        target = try RetainedSourceHistoryTargetV2(root: root, records: sourceOriginals)
        let sourceWorkspaceID = inherited?.lineage.selectedReview.checkpoint.workspaceID ?? source.workspaceID
        let workspace = target.session.workspaceIdentity.workspaceID.rawValue
        identity = try RestoreIdentityDecisionV1.decide(.init(mode: mode,
            source: .init(workspaceID: sourceWorkspaceID.rawValue, replicaID: resolutionID(10_001)),
            oldPointer: .init(generationID: resolutionID(10_002),
                generationManifestSHA256: String(repeating: "a", count: 64),
                workspaceID: mode == .replaceExisting ? workspace : resolutionID(10_003),
                replicaID: resolutionID(10_004)),
            targetGenerationID: target.session.generationID,
            targetGenerationManifestSHA256: String(repeating: "b", count: 64),
            allocatedWorkspaceID: mode == .fork ? workspace : nil,
            allocatedReplicaID: target.session.workspaceIdentity.replicaID.rawValue))
        if let inherited {
            initialCheckpoint = try RepetitiveCaptureDestinationReviewV1.prepareInherited(
                from: inherited.lineage, identity: identity,
                reviewedAt: RepetitiveCaptureSourcePackageFixture.date.addingTimeInterval(1_000)).checkpoint
        } else {
            let reviewed = try RepetitiveCaptureSourceGraphReviewV2.review(sourcePackage: source.validatedPackage())
            initialCheckpoint = try RepetitiveCaptureDestinationReviewV1.prepareFirst(from: reviewed,
                sourceDraftID: XCTUnwrap(reviewed.graphs.first).chain.sourceCheckpoint.draftID,
                identity: identity, reviewedAt: RepetitiveCaptureSourcePackageFixture.date.addingTimeInterval(1_000)).checkpoint
        }
        do {
            let create = try FieldDraftMutationV1(workspaceID: initialCheckpoint.workspaceID, expectedRevision: 0,
                expectedBaseCanonicalRevision: initialCheckpoint.baseCanonicalRevision,
                mutationID: initialCheckpoint.mutationID, postImage: .createCheckpoint(initialCheckpoint))
            _ = try target.writer.execute(.applyFieldDraft(create), mutationID: create.mutationID)
            if materializeRound { try materializeRestoredRound() }
        } catch {
            try? target.close()
            try? FileManager.default.removeItem(at: root)
            throw error
        }
    }

    func lineage() throws -> RepetitiveCaptureReviewLineageV1 {
        let checkpoint = try currentCheckpoint()
        return try target.writer.repetitiveCaptureDestinationReviewLineage(
            workspaceID: checkpoint.workspaceID, mutationID: checkpoint.mutationID)
    }

    func currentCheckpoint() throws -> FieldDraftCheckpointV1 {
        let rows = try target.context.fetch(FetchDescriptor<FieldDraftCheckpointRow>())
        return try XCTUnwrap(rows.first { $0.draftID == initialCheckpoint.draftID }).value()
    }

    func rounds() throws -> [RoundSessionV1] {
        try target.context.fetch(FetchDescriptor<RoundSessionRevisionRowV1>()).map { try $0.value() }
            .sorted { $0.revision < $1.revision }
    }

    func materializeRestoredRound() throws {
        let values = try RepetitiveCaptureDestinationResolutionV1.restoredRoundPrefix(from: lineage())
        for round in values { try append(round) }
    }

    func append(_ round: RoundSessionV1) throws {
        let mutation = try RoundSessionMutationV1(workspaceID: round.workspaceID,
            expectedRevision: round.revision - 1, mutationID: round.mutationID, session: round)
        _ = try target.writer.execute(.applyRoundSession(mutation), mutationID: mutation.mutationID)
    }

    func advance(_ transition: RoundSessionTransitionV1, state: RoundSessionStateV1, mutationSeed: Int) throws {
        let previous = try XCTUnwrap(rounds().last)
        let value = try RoundSessionV1(workspaceID: previous.workspaceID, sessionID: previous.sessionID,
            predecessor: previous, revision: previous.revision + 1,
            mutationID: .init(rawValue: resolutionID(mutationSeed)), state: state, transition: transition,
            items: previous.items, recordedBy: previous.recordedBy, recordedAt: previous.recordedAt.addingTimeInterval(1))
        try append(value)
    }

    func archiveRound() throws {
        for index in 0..<2 {
            let previous = try XCTUnwrap(rounds().last)
            var items = previous.items
            let item = items[index]
            items[index] = try RoundItemV1(itemID: item.itemID, order: item.order, selection: item.selection,
                requirement: item.requirement, disposition: .skipped, visit: item.visit, reason: .notRequired)
            let value = try RoundSessionV1(workspaceID: previous.workspaceID, sessionID: previous.sessionID,
                predecessor: previous, revision: previous.revision + 1,
                mutationID: .init(rawValue: resolutionID(100 + index)), state: .active, transition: .skipItem,
                transitionItemID: item.itemID, items: items, recordedBy: previous.recordedBy,
                recordedAt: previous.recordedAt.addingTimeInterval(1))
            try append(value)
        }
        try advance(.close, state: .completed, mutationSeed: 103)
        try advance(.archive, state: .archived, mutationSeed: 104)
    }

    func propose(_ plan: DraftConflictResolutionPlanV1, mutationSeed: Int) throws -> ReviewedDraftConflictResolutionV1 {
        try RepetitiveCaptureDestinationResolutionV1.propose(plan: plan, from: lineage(),
            currentRoundHistory: plan == .discard ? [] : rounds(), expectedWorkspaceRevision: target.writer.currentRevision().revision,
            mutationID: MutationIDV1(rawValue: resolutionID(mutationSeed)),
            reviewedAt: initialCheckpoint.updatedAt.addingTimeInterval(1))
    }

    func request(_ mutation: FieldDraftMutationV1) throws -> WorkspaceMutationRequestV1 {
        let current = try target.writer.currentRevision()
        return try .init(mutationID: mutation.mutationID,
            expectedRevision: .init(workspaceID: current.workspaceID, generationID: current.generationID,
                writerInstanceID: current.writerInstanceID, workspaceRevision: current.revision,
                entityRevisions: mutation.concurrencyIdentities.map {
                    .init(identity: $0, revision: try mutation.expectedRevision(for: $0))
                }), command: .applyFieldDraft(mutation))
    }

    func proof(_ mutation: FieldDraftMutationV1) throws -> PreparedReviewedFieldDraftApplyProofV1 {
        try XCTUnwrap(target.journal.validatePendingReviewedFieldDraftResolution(mutation,
            expectedWorkspaceRevision: target.writer.currentRevision().revision))
    }

    func assertOriginalsRetained(file: StaticString = #filePath, line: UInt = #line) throws {
        let stored = try target.journal.exportSnapshot().receipts
        for original in sourceOriginals {
            XCTAssertEqual(stored.filter { $0 == original }.count, 1, file: file, line: line)
        }
    }

    func close() throws {
        try target.close()
        try FileManager.default.removeItem(at: root)
    }
}

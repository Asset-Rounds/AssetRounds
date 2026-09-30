import Foundation
import SwiftData
import XCTest

@testable import FieldEvidenceApp

final class V23RepetitiveCaptureDestinationDiscardTests: XCTestCase {
    @MainActor
    func testConfirmedTerminalUsesActualAtomicReceiptForAbsentAndArchivedTargetsAndExactReplay() throws {
        let source = try RepetitiveCaptureSourcePackageFixture(sourceOnly: true)
        defer { source.removePackages() }
        for mode in [BackupRestoreMode.fork, .replaceExisting] {
            for materializeRound in [false, true] {
                let fixture = try RepetitiveResolutionFixture(source: source, mode: mode, materializeRound: materializeRound)
                defer { try? fixture.close() }
                if materializeRound { try fixture.archiveRound() }
                let pending = try recordDiscard(in: fixture)
                let proposal = try discardProposal(in: fixture)
                let mutation = try proposal.mutation
                let request = try fixture.request(mutation)
                let rounds = try fixture.rounds()
                let before = try fixture.target.rawState()
                let outcome = try fixture.target.writer.execute(request)
                let evidence = try discardEvidence(in: fixture)
                XCTAssertEqual(evidence.resolution.resolution.successorCheckpoint, pending)
                XCTAssertEqual(evidence.bundle, proposal.terminalBundle)
                XCTAssertEqual(evidence.plan, proposal.plan)
                XCTAssertEqual(evidence.terminal, try fixture.target.writer.fieldDraftEvidence(mutationID: mutation.mutationID))
                XCTAssertEqual(evidence.terminal.envelope.expectedRevision.workspaceID, request.expectedRevision.workspaceID)
                XCTAssertEqual(evidence.terminal.envelope.expectedRevision.generationID, request.expectedRevision.generationID)
                XCTAssertEqual(evidence.terminal.envelope.expectedRevision.workspaceRevision, request.expectedRevision.workspaceRevision)
                XCTAssertEqual(evidence.terminal.envelope.expectedRevision.entityRevisions,
                               request.expectedRevision.entityRevisions.sorted { $0.identity.stableKey < $1.identity.stableKey })
                XCTAssertEqual(outcome.effect.affectedEntities, try mutation.affectedIdentities)
                XCTAssertEqual(try fixture.currentCheckpoint(), proposal.terminalBundle.discardedCheckpoint)
                XCTAssertEqual(try fixture.currentCheckpoint().payloadData, fixture.initialCheckpoint.payloadData)
                XCTAssertEqual(try fixture.target.context.fetch(FetchDescriptor<DraftDiscardReceiptRow>()).map { try $0.value() },
                               [proposal.terminalBundle.receipt])
                XCTAssertEqual(try fixture.target.rawState().canonicalCounts, before.canonicalCounts)
                XCTAssertEqual(try fixture.rounds(), rounds)
                try fixture.assertOriginalsRetained()
                let after = try fixture.target.rawState()
                let replay = try fixture.target.writer.execute(request)
                XCTAssertEqual(replay.mutationID, outcome.mutationID)
                XCTAssertEqual(replay.commandDigest, outcome.commandDigest)
                // Replay returns the stored receipt instant; authenticate the
                // initial clock value at the canonical wire precision.
                XCTAssertEqual(replay.occurredAt, evidence.terminal.receipt.committedAt)
                XCTAssertEqual(try WorkspaceMutationCanonicalV1.data(replay.occurredAt),
                               try WorkspaceMutationCanonicalV1.data(outcome.occurredAt))
                XCTAssertEqual(replay.after, outcome.after)
                XCTAssertEqual(replay.effect, outcome.effect)
                // Durable replay includes explicit zero revisions for absent
                // entities; the initial process-local snapshot can omit them.
                let expected = evidence.terminal.envelope.expectedRevision
                XCTAssertEqual(replay.before.workspaceID, expected.workspaceID)
                XCTAssertEqual(replay.before.generationID, expected.generationID)
                XCTAssertEqual(replay.before.writerInstanceID, outcome.before.writerInstanceID)
                XCTAssertEqual(replay.before.revision, expected.workspaceRevision)
                XCTAssertEqual(replay.before.entityRevisions, expected.entityRevisions)
                XCTAssertEqual(try discardEvidence(in: fixture), evidence)
                XCTAssertEqual(try fixture.target.rawState(), after)
                XCTAssertThrowsError(try discardProposal(in: fixture, seed: 50))
            }
        }
    }

    @MainActor
    func testTerminalRecoveryAfterReopenReadsStoredOriginalWithoutAllocatingAnotherAttempt() throws {
        let source = try RepetitiveCaptureSourcePackageFixture(sourceOnly: true)
        defer { source.removePackages() }
        let fixture = try RepetitiveResolutionFixture(source: source, materializeRound: false)
        defer { try? fixture.close() }
        _ = try recordDiscard(in: fixture)
        let proposal = try discardProposal(in: fixture)
        let mutation = try proposal.mutation
        // Deliberately drop the successful caller result. Recovery uses only
        // stored originals, not a persisted in-memory proposal or reply.
        _ = try fixture.target.writer.execute(fixture.request(mutation))
        let expected = try discardEvidence(in: fixture)
        let receiptBytes = try fixture.target.rawState().receipts
        try fixture.target.close()
        let reopened = try fixture.target.factory.openOrBootstrapCurrent()
        let coordinator = try StoreSessionCoordinator(validatingSession: reopened,
            lifecycleProfileRegistry: WorkspacePackageLifecycleCompatibilityV1.shippingRegistry())
        defer { try? coordinator.invalidateAndReleaseWriter() }
        let recovered = try coordinator.workspaceWriter.repetitiveCaptureDestinationDiscardEvidence(
            workspaceID: fixture.initialCheckpoint.workspaceID, draftID: fixture.initialCheckpoint.draftID)
        XCTAssertEqual(recovered, expected)
        XCTAssertEqual(reopened.generationID, fixture.target.session.generationID)
        XCTAssertEqual(try reopened.modelContext.fetchCount(FetchDescriptor<DraftDiscardReceiptRow>()), 1)
        XCTAssertEqual(try reopened.modelContext.fetchCount(FetchDescriptor<MutationReceiptRow>()), receiptBytes.count)
        XCTAssertFalse(reopened.modelContext.hasChanges)
        let terminalRow = try XCTUnwrap(reopened.modelContext.fetch(FetchDescriptor<DraftDiscardReceiptRow>()).first)
        reopened.modelContext.delete(terminalRow)
        try reopened.modelContext.save()
        XCTAssertThrowsError(try coordinator.workspaceWriter.repetitiveCaptureDestinationDiscardEvidence(
            workspaceID: fixture.initialCheckpoint.workspaceID, draftID: fixture.initialCheckpoint.draftID))
        XCTAssertFalse(reopened.modelContext.hasChanges)
        reopened.modelContext.insert(try DraftDiscardReceiptRow(expected.bundle.receipt))
        try reopened.modelContext.save()
        XCTAssertEqual(try coordinator.workspaceWriter.repetitiveCaptureDestinationDiscardEvidence(
            workspaceID: fixture.initialCheckpoint.workspaceID, draftID: fixture.initialCheckpoint.draftID), expected)
    }

    @MainActor
    func testTerminalRequiresExplicitPendingDiscardAndRejectsWrongPlanTimePayloadAndKnownIDs() throws {
        let source = try RepetitiveCaptureSourcePackageFixture(sourceOnly: true)
        defer { source.removePackages() }
        let fixture = try RepetitiveResolutionFixture(source: source)
        defer { try? fixture.close() }
        let initial = try fixture.target.rawState()
        XCTAssertThrowsError(try discardProposal(in: fixture))
        XCTAssertThrowsError(try discardEvidence(in: fixture))
        XCTAssertEqual(try fixture.target.rawState(), initial)
        let pending = try recordDiscard(in: fixture)
        let lineage = try fixture.lineage()
        let proposal = try discardProposal(in: fixture)
        let before = try fixture.target.rawState()
        for id in [pending.draftID, pending.mutationID.rawValue,
                   try XCTUnwrap(lineage.requiredHistory.first).envelope.mutationID.rawValue,
                   try XCTUnwrap(lineage.selectedReview.payload.provenance.ultimateToDestinationPairs.first).sourceID] {
            XCTAssertThrowsError(try RepetitiveCaptureDestinationDiscardV1.propose(from: lineage,
                receiptID: id, mutationID: .init(rawValue: discardID(90)), discardedAt: pending.updatedAt))
        }
        XCTAssertThrowsError(try RepetitiveCaptureDestinationDiscardV1.propose(from: lineage,
            receiptID: discardID(91), mutationID: .init(rawValue: discardID(91)), discardedAt: pending.updatedAt))
        XCTAssertThrowsError(try RepetitiveCaptureDestinationDiscardV1.propose(from: lineage,
            receiptID: discardID(92), mutationID: .init(rawValue: discardID(93)),
            discardedAt: pending.updatedAt.addingTimeInterval(-1)))
        let other = try RepetitiveResolutionFixture(source: source)
        defer { try? other.close() }
        let wrongPlan = try changedTerminal(proposal, planSHA256: String(repeating: "a", count: 64))
        let wrongTime = try changedTerminal(proposal, discardedAt: pending.updatedAt.addingTimeInterval(-1))
        let wrongPayload = try changedTerminal(proposal, payload: other.initialCheckpoint.payloadData)
        for mutation in [wrongPlan, wrongTime, wrongPayload] {
            XCTAssertThrowsError(try RepetitiveCaptureDestinationDiscardV1.validate(mutation, against: lineage))
            XCTAssertThrowsError(try fixture.target.writer.execute(fixture.request(mutation)))
            XCTAssertEqual(try fixture.target.rawState(), before)
            XCTAssertEqual(try fixture.currentCheckpoint(), pending)
        }
        let continuing = try other.propose(.continueEditing, mutationSeed: 990)
        let continueMutation = try FieldDraftMutationV1(workspaceID: continuing.expectedCheckpoint.workspaceID,
            expectedRevision: continuing.expectedCheckpoint.draftRevision,
            expectedBaseCanonicalRevision: continuing.expectedCheckpoint.baseCanonicalRevision,
            mutationID: continuing.successorCheckpoint.mutationID, postImage: .resolveConflict(continuing))
        _ = try other.target.writer.execute(other.request(continueMutation))
        XCTAssertThrowsError(try discardProposal(in: other))
        XCTAssertEqual(try other.currentCheckpoint().state, .active)
    }

    @MainActor
    func testPreparedTerminalProofIsSingleUseContextBoundAndRechecksCompetingWrites() throws {
        let source = try RepetitiveCaptureSourcePackageFixture(sourceOnly: true)
        defer { source.removePackages() }
        let fixture = try RepetitiveResolutionFixture(source: source)
        defer { try? fixture.close() }
        let pending = try recordDiscard(in: fixture)
        let mutation = try discardProposal(in: fixture).mutation
        let changed = try discardProposal(in: fixture, seed: 100).mutation
        let before = try fixture.target.rawState()
        let valid = try discardProof(mutation, in: fixture)
        try valid.validateForApply(mutation, in: fixture.target.context)
        XCTAssertThrowsError(try valid.validateForApply(mutation, in: fixture.target.context))
        let wrongCommand = try discardProof(mutation, in: fixture)
        XCTAssertThrowsError(try wrongCommand.validateForApply(changed, in: fixture.target.context))
        XCTAssertThrowsError(try wrongCommand.validateForApply(mutation, in: fixture.target.context))
        let wrongContext = try discardProof(mutation, in: fixture)
        let other = ModelContext(fixture.target.context.container)
        other.autosaveEnabled = false
        XCTAssertThrowsError(try wrongContext.validateForApply(mutation, in: other))
        XCTAssertThrowsError(try wrongContext.validateForApply(mutation, in: fixture.target.context))
        XCTAssertThrowsError(try WorkspaceWriterAdapterV1(modelContext: fixture.target.context).apply(
            .applyFieldDraft(mutation), occurredAt: pending.updatedAt, temporaryRelativePath: "c36-discard-generic-denial"))
        XCTAssertEqual(try fixture.target.rawState(), before)
        let staleRequest = try fixture.request(mutation)
        let late = try discardProof(mutation, in: fixture)
        try fixture.advance(.pause, state: .paused, mutationSeed: 901)
        let advanced = try fixture.target.rawState()
        XCTAssertThrowsError(try late.validateForApply(mutation, in: fixture.target.context))
        XCTAssertThrowsError(try fixture.target.writer.execute(staleRequest))
        XCTAssertEqual(try fixture.target.rawState(), advanced)
        // A changed workspace requires fresh admission; Round readiness remains
        // irrelevant to discarding this pending review.
        let request = try fixture.request(mutation)
        let competing = try fixture.request(changed)
        _ = try fixture.target.writer.execute(request)
        let terminalState = try fixture.target.rawState()
        XCTAssertThrowsError(try fixture.target.writer.execute(competing))
        XCTAssertThrowsError(try discardProof(changed, in: fixture))
        XCTAssertEqual(try fixture.target.rawState(), terminalState)
        XCTAssertEqual(try discardEvidence(in: fixture).terminal.mutation, mutation)
    }

    @MainActor
    func testOwnedContentAndUnboundStageWritesDenyDiscardBeforeAnyEffect() throws {
        let source = try RepetitiveCaptureSourcePackageFixture(sourceOnly: true)
        defer { source.removePackages() }
        let fixture = try RepetitiveResolutionFixture(source: source, materializeRound: false)
        defer { try? fixture.close() }
        let pending = try recordDiscard(in: fixture)
        let mutation = try discardProposal(in: fixture).mutation
        let stage = try AttachmentStagingItemV1(stageID: discardID(200), draftID: pending.draftID,
            workspaceID: pending.workspaceID, attachmentKind: .photo, scratchLeaseID: discardID(201),
            expectedByteCount: 0, retryClass: .none, state: .capturing, protectionState: .available,
            revision: 1, mutationID: .init(rawValue: discardID(202)))
        let late = try discardProof(mutation, in: fixture)
        let stageRow = try AttachmentStagingItemRow(stage)
        fixture.target.context.insert(stageRow)
        try fixture.target.context.save()
        let withStage = try fixture.target.rawState()
        XCTAssertThrowsError(try discardProof(mutation, in: fixture))
        XCTAssertThrowsError(try late.validateForApply(mutation, in: fixture.target.context))
        XCTAssertEqual(try fixture.target.rawState(), withStage)
        XCTAssertEqual(try fixture.currentCheckpoint(), pending)
        fixture.target.context.delete(stageRow)
        try fixture.target.context.save()
        XCTAssertNoThrow(try discardProof(mutation, in: fixture))
        @MainActor
        func rejectOwnedRow<Model: PersistentModel>(_ row: Model) throws {
            fixture.target.context.insert(row)
            try fixture.target.context.save()
            let stored = try fixture.target.rawState()
            XCTAssertThrowsError(try discardProof(mutation, in: fixture))
            XCTAssertEqual(try fixture.target.rawState(), stored)
            XCTAssertEqual(try fixture.currentCheckpoint(), pending)
            fixture.target.context.delete(row)
            try fixture.target.context.save()
            XCTAssertNoThrow(try discardProof(mutation, in: fixture))
        }
        let plan = try DraftCommitPlanV1(planID: discardID(210), workspaceID: pending.workspaceID,
            draftID: pending.draftID, draftRevision: pending.draftRevision,
            baseCanonicalRevision: pending.baseCanonicalRevision, payloadSHA256: pending.payloadSHA256,
            stageDigests: [], targetCommandKind: .applyMyDay, expectedTargetRevision: 0,
            mutationID: .init(rawValue: discardID(211)), outputKeys: ["MY_DAY_PLAN|\(discardID(212).uuidString.lowercased())"])
        let saga = try DraftCommitSagaV1(sagaID: discardID(213), workspaceID: pending.workspaceID,
            draftID: pending.draftID, plan: plan, state: .prepared, revision: 1,
            mutationID: .init(rawValue: discardID(214)), updatedAt: pending.updatedAt)
        try rejectOwnedRow(DraftCommitSagaRow(saga))
        let commit = try DraftCommitReceiptV1(receiptID: discardID(215), workspaceID: pending.workspaceID,
            draftID: pending.draftID, sagaID: saga.sagaID, commitPlanSHA256: plan.planSHA256,
            sagaEventSHA256Chain: [saga.sagaSHA256], targetMutationID: plan.mutationID,
            targetReceiptSHA256: String(repeating: "a", count: 64), consumedStageToContentID: [:],
            committedAt: pending.updatedAt, mutationID: .init(rawValue: discardID(216)))
        try rejectOwnedRow(DraftCommitReceiptRow(commit))
        let digest = try ContentDigestV1(algorithm: .sha256, hexadecimalValue: String(repeating: "a", count: 64))
        let locator = try ContentLocatorV1(locatorID: "review-orphan-locator",
            workspaceID: pending.workspaceID.rawValue.uuidString.lowercased(), contentID: "review-orphan-content",
            locatorRevision: 0, contentDigest: digest, expectedByteLength: 1)
        let reservation = try DraftContentReservationV1(reservationID: discardID(217), workspaceID: pending.workspaceID,
            draftID: pending.draftID, stageID: stage.stageID, commitPlanSHA256: plan.planSHA256,
            mutationID: .init(rawValue: discardID(218)), contentDigest: digest, locator: locator,
            createdAt: pending.updatedAt, reviewAfter: pending.updatedAt.addingTimeInterval(1),
            reconciliationState: .reserved, revision: 1)
        try rejectOwnedRow(DraftContentReservationRow(reservation))
        try rejectOwnedRow(DraftDiscardReceiptRow(discardProposal(in: fixture).terminalBundle.receipt))
        let append = try FieldDraftMutationV1(workspaceID: pending.workspaceID, expectedRevision: 0,
            expectedBaseCanonicalRevision: pending.baseCanonicalRevision, mutationID: stage.mutationID,
            postImage: .appendStagingItem(stage))
        let beforeAppend = try fixture.target.rawState()
        // The existing adapter cannot attach an unbound stage to this review.
        // Rejecting the attempt leaves the pending discard available to confirm.
        XCTAssertThrowsError(try fixture.target.writer.execute(.applyFieldDraft(append), mutationID: append.mutationID)) { error in
            XCTAssertEqual(error as? WorkspaceMutationFailureV1, .invalidCommand)
        }
        XCTAssertEqual(try fixture.target.rawState(), beforeAppend)
        XCTAssertEqual(try fixture.currentCheckpoint(), pending)
        XCTAssertEqual(try fixture.target.context.fetchCount(FetchDescriptor<AttachmentStagingItemRow>()), 0)
        XCTAssertEqual(try fixture.target.context.fetchCount(FetchDescriptor<DraftDiscardReceiptRow>()), 0)
        XCTAssertNoThrow(try discardProof(mutation, in: fixture))
        try fixture.assertOriginalsRetained()
    }

    @MainActor
    func testTerminalAdmissionRejectsDirtyCorruptMissingQuarantinedAndRetiredHistoryWithoutEffects() throws {
        let source = try RepetitiveCaptureSourcePackageFixture(sourceOnly: true)
        defer { source.removePackages() }
        let fixture = try RepetitiveResolutionFixture(source: source)
        defer { try? fixture.close() }
        let pending = try recordDiscard(in: fixture)
        let mutation = try discardProposal(in: fixture).mutation
        let original = try XCTUnwrap(fixture.lineage().retainedSource.requiredHistory.first)
        let row = try XCTUnwrap(fixture.target.context.fetch(FetchDescriptor<MutationReceiptRow>()).first {
            $0.workspaceMutationKey == MutationWorkspaceKeyV1.value(
                workspaceID: original.envelope.workspaceID, mutationID: original.envelope.mutationID)
        })
        let digest = row.receiptSHA256
        let before = try fixture.target.rawState()
        let late = try discardProof(mutation, in: fixture)
        row.receiptSHA256 = String(repeating: "f", count: 64)
        let dirty = try fixture.target.rawState()
        XCTAssertThrowsError(try discardProof(mutation, in: fixture))
        XCTAssertThrowsError(try late.validateForApply(mutation, in: fixture.target.context))
        XCTAssertEqual(try fixture.target.rawState(), dirty)
        fixture.target.context.rollback()
        row.receiptSHA256 = String(repeating: "f", count: 64)
        try fixture.target.context.save()
        let corrupt = try fixture.target.rawState()
        XCTAssertThrowsError(try discardProof(mutation, in: fixture))
        XCTAssertEqual(try fixture.target.rawState(), corrupt)
        row.receiptSHA256 = digest
        try fixture.target.context.save()
        let quarantine = MutationQuarantineRow(workspaceID: original.envelope.workspaceID,
            mutationID: original.envelope.mutationID, identityDomain: .mutationEnvelope,
            acceptedIdentitySHA256: original.receipt.envelopeSHA256,
            conflictingIdentitySHA256: String(repeating: "b", count: 64), detectedAt: pending.updatedAt)
        fixture.target.context.insert(quarantine)
        try fixture.target.context.save()
        let quarantined = try fixture.target.rawState()
        XCTAssertThrowsError(try discardProof(mutation, in: fixture))
        XCTAssertEqual(try fixture.target.rawState(), quarantined)
        fixture.target.context.delete(quarantine)
        try fixture.target.context.save()
        fixture.target.context.delete(row)
        try fixture.target.context.save()
        let missing = try fixture.target.rawState()
        XCTAssertThrowsError(try discardProof(mutation, in: fixture))
        XCTAssertEqual(try fixture.target.rawState(), missing)
        try fixture.target.insert(original.original)
        try fixture.target.context.save()
        XCTAssertEqual(try fixture.target.rawState(), before)
        let retiring = try discardProof(mutation, in: fixture)
        try fixture.target.closeJournalLease()
        XCTAssertThrowsError(try discardProof(mutation, in: fixture))
        XCTAssertThrowsError(try retiring.validateForApply(mutation, in: fixture.target.context))
        fixture.target.writer.invalidate()
        XCTAssertThrowsError(try fixture.target.writer.execute(fixture.request(mutation)))
        XCTAssertThrowsError(try discardEvidence(in: fixture))
        XCTAssertEqual(try fixture.target.rawState(), before)
        XCTAssertEqual(try fixture.currentCheckpoint(), pending)
    }

    @MainActor
    func testOriginalWriterInterruptionBoundariesRollbackOrRecoverExactlyOneTerminal() throws {
        let source = try RepetitiveCaptureSourcePackageFixture(sourceOnly: true)
        defer { source.removePackages() }
        for boundary in MutationJournalFaultBoundaryV1.allCases {
            let fixture = try RepetitiveResolutionFixture(source: source, materializeRound: false)
            defer { try? fixture.close() }
            let pending = try recordDiscard(in: fixture)
            let proposal = try discardProposal(in: fixture)
            let mutation = try proposal.mutation
            let before = try fixture.target.rawState()
            try fixture.target.close()
            let session = fixture.target.session
            let registry = try fixture.target.factory.makeGenerationLeaseRegistry()
            let epoch = try XCTUnwrap(session.generationEpoch)
            let lease = try registry.acquireHandle(epoch: epoch, role: .writer)
            defer { try? lease.close() }
            let journal = try MutationJournalStoreV1(modelContext: session.modelContext,
                identity: session.workspaceIdentity, generationID: session.generationID,
                failureInjection: .init(failOnceAt: boundary), allowStateBootstrap: false,
                staleWriterFence: fixture.target.factory.makeWriterFence(
                    expectedGenerationEpoch: epoch, writerLeaseToken: lease.token, registry: registry))
            let writer = try WorkspaceWriterV1(identity: session.workspaceIdentity, generationID: session.generationID,
                initialRevision: journal.currentRevision(writerInstanceID: discardID(500)),
                clock: SystemApplicationClock(), idSource: SystemApplicationIDSource(),
                fileAuthority: SystemApplicationFileAuthorityV1(),
                adapter: WorkspaceWriterAdapterV1(modelContext: session.modelContext), journalStore: journal)
            defer { writer.invalidate() }
            let current = try writer.currentRevision()
            let request = try WorkspaceMutationRequestV1(mutationID: mutation.mutationID,
                expectedRevision: .init(workspaceID: current.workspaceID, generationID: current.generationID,
                    writerInstanceID: current.writerInstanceID, workspaceRevision: current.revision,
                    entityRevisions: mutation.concurrencyIdentities.map {
                        .init(identity: $0, revision: try mutation.expectedRevision(for: $0))
                    }), command: .applyFieldDraft(mutation))
            XCTAssertThrowsError(try writer.execute(request)) { error in
                XCTAssertEqual(error as? MutationJournalFailureV1, .injected(boundary))
            }
            if boundary == .afterSaveBeforeReturn {
                let recovered = try writer.repetitiveCaptureDestinationDiscardEvidence(
                    workspaceID: pending.workspaceID, draftID: pending.draftID)
                XCTAssertEqual(recovered.bundle, proposal.terminalBundle)
                XCTAssertEqual(recovered.terminal.envelope.expectedRevision.workspaceID, request.expectedRevision.workspaceID)
                XCTAssertEqual(recovered.terminal.envelope.expectedRevision.generationID, request.expectedRevision.generationID)
                XCTAssertEqual(recovered.terminal.envelope.expectedRevision.workspaceRevision, request.expectedRevision.workspaceRevision)
                XCTAssertEqual(recovered.terminal.envelope.expectedRevision.entityRevisions,
                               request.expectedRevision.entityRevisions.sorted { $0.identity.stableKey < $1.identity.stableKey })
            } else {
                XCTAssertEqual(try fixture.target.rawState(), before)
                XCTAssertEqual(try fixture.currentCheckpoint(), pending)
                XCTAssertThrowsError(try writer.repetitiveCaptureDestinationDiscardEvidence(
                    workspaceID: pending.workspaceID, draftID: pending.draftID))
            }
            _ = try writer.execute(request)
            let after = try fixture.target.rawState()
            let recovered = try writer.repetitiveCaptureDestinationDiscardEvidence(
                workspaceID: pending.workspaceID, draftID: pending.draftID)
            XCTAssertEqual(recovered.bundle, proposal.terminalBundle)
            _ = try writer.execute(request)
            XCTAssertEqual(try fixture.target.rawState(), after)
            XCTAssertEqual(try session.modelContext.fetchCount(FetchDescriptor<DraftDiscardReceiptRow>()), 1)
            let snapshot = try journal.exportSnapshot()
            for original in fixture.sourceOriginals { XCTAssertEqual(snapshot.receipts.filter { $0 == original }.count, 1) }
        }
    }
}

@MainActor
private func recordDiscard(in fixture: RepetitiveResolutionFixture) throws -> FieldDraftCheckpointV1 {
    let resolution = try fixture.propose(.discard, mutationSeed: 950)
    let prior = resolution.expectedCheckpoint
    let mutation = try FieldDraftMutationV1(workspaceID: prior.workspaceID, expectedRevision: prior.draftRevision,
        expectedBaseCanonicalRevision: prior.baseCanonicalRevision,
        mutationID: resolution.successorCheckpoint.mutationID, postImage: .resolveConflict(resolution))
    _ = try fixture.target.writer.execute(fixture.request(mutation))
    return resolution.successorCheckpoint
}

@MainActor
private func discardProposal(in fixture: RepetitiveResolutionFixture, seed: Int = 1) throws
    -> RepetitiveCaptureDestinationDiscardProposalV1 {
    try RepetitiveCaptureDestinationDiscardV1.propose(from: fixture.lineage(), receiptID: discardID(seed),
        mutationID: .init(rawValue: discardID(seed + 1)),
        discardedAt: fixture.initialCheckpoint.updatedAt.addingTimeInterval(2))
}

@MainActor
private func discardEvidence(in fixture: RepetitiveResolutionFixture) throws -> RepetitiveCaptureDestinationDiscardEvidenceV1 {
    try fixture.target.writer.repetitiveCaptureDestinationDiscardEvidence(
        workspaceID: fixture.initialCheckpoint.workspaceID, draftID: fixture.initialCheckpoint.draftID)
}

@MainActor
private func discardProof(_ mutation: FieldDraftMutationV1, in fixture: RepetitiveResolutionFixture) throws
    -> PreparedReviewedFieldDraftApplyProofV1 {
    try fixture.target.journal.validatePendingRepetitiveCaptureDestinationDiscard(mutation,
        expectedWorkspaceRevision: fixture.target.writer.currentRevision().revision)
}

private func changedTerminal(_ proposal: RepetitiveCaptureDestinationDiscardProposalV1,
                             planSHA256: String? = nil, discardedAt: Date? = nil, payload: Data? = nil) throws -> FieldDraftMutationV1 {
    let old = proposal.terminalBundle.receipt, value = proposal.terminalBundle.discardedCheckpoint
    let receipt = try DraftDiscardReceiptV1(receiptID: old.receiptID, workspaceID: old.workspaceID,
        draftID: old.draftID, planSHA256: planSHA256 ?? old.planSHA256, disposedStageIDs: [],
        quarantinedReservationIDs: [], discardedAt: discardedAt ?? old.discardedAt, mutationID: old.mutationID)
    let checkpoint = try FieldDraftCheckpointV1(draftID: value.draftID, workspaceID: value.workspaceID,
        scope: value.scope, purpose: value.purpose, codec: value.codec, baseCanonicalRevision: value.baseCanonicalRevision,
        draftRevision: value.draftRevision, payloadData: payload ?? value.payloadData, stageIDs: [],
        resumeAnchor: value.resumeAnchor, state: .discarded, lastDurableMutationID: value.mutationID,
        lastReceiptSHA256: receipt.receiptSHA256, updatedAt: discardedAt ?? value.updatedAt, mutationID: value.mutationID)
    return try .init(workspaceID: value.workspaceID, expectedRevision: proposal.expectedCheckpoint.draftRevision,
        expectedBaseCanonicalRevision: proposal.expectedCheckpoint.baseCanonicalRevision,
        mutationID: value.mutationID, postImage: .applyDiscardTerminal(.init(discardedCheckpoint: checkpoint, receipt: receipt)))
}

private func discardID(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "dbc00000-0000-4000-8000-%012x", value))!
}

import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

final class V23RepetitiveCaptureDestinationContinuationTests: XCTestCase {
    @MainActor
    func testSeparateContinuationBindsActualResolutionAndPreservesOneSourceAcrossRereview() throws {
        let source = try RepetitiveCaptureSourcePackageFixture(sourceOnly: true)
        defer { source.removePackages() }
        for mode in [BackupRestoreMode.fork, .replaceExisting] {
            for plan in [DraftConflictResolutionPlanV1.continueEditing, .reviewAndRebase] {
                let fixture = try RepetitiveResolutionFixture(source: source, mode: mode)
                defer { try? fixture.close() }
                XCTAssertThrowsError(try continuationProposal(in: fixture))
                if plan == .reviewAndRebase {
                    try fixture.advance(.pause, state: .paused, mutationSeed: 510)
                    try fixture.advance(.resume, state: .active, mutationSeed: 511)
                }
                let resolution = try continueResolution(in: fixture, plan: plan)
                let proposal = try continuationProposal(in: fixture)
                let request = try fixture.request(proposal.mutation)
                let before = try fixture.target.journal.exportSnapshot().receipts
                let rounds = try fixture.rounds()
                XCTAssertEqual(try proposal.mutation.concurrencyIdentities.count, 3)
                let result = try fixture.target.writer.execute(request)
                let original = try continuationEvidence(in: fixture)
                XCTAssertEqual(original.original.mutation, proposal.mutation)
                XCTAssertEqual(original.resolution.resolution, resolution)
                XCTAssertEqual(original.sourceCheckpoint, proposal.checkpoint)
                XCTAssertEqual(original.binding.review.draftID, fixture.initialCheckpoint.draftID)
                XCTAssertNotEqual(original.sourceCheckpoint.draftID, fixture.initialCheckpoint.draftID)
                XCTAssertEqual(try RepetitiveCaptureProgressDraftCodecV2.source(proposal.checkpoint).round, rounds.last)
                XCTAssertEqual(result.effect.affectedEntities,
                    [try WorkspaceEntityIdentityV1(kind: .fieldDraftCheckpoint, id: proposal.checkpoint.draftID)])
                XCTAssertEqual(try fixture.currentCheckpoint(), resolution.successorCheckpoint)
                XCTAssertEqual(try fixture.rounds(), rounds)
                let after = try fixture.target.rawState()
                _ = try fixture.target.writer.execute(request)
                XCTAssertEqual(try fixture.target.rawState(), after)
                XCTAssertEqual(try continuationEvidence(in: fixture), original)
                let retained = try fixture.target.journal.exportSnapshot().receipts
                XCTAssertTrue(before.allSatisfy { retained.contains($0) })

                // A later explicit review cannot allocate a second source or
                // rewrite which original resolution authorized the first one.
                let current = try fixture.currentCheckpoint()
                let conflicted = try continuationCheckpoint(current, state: .conflicted, seed: 701)
                let revise = try FieldDraftMutationV1(workspaceID: current.workspaceID,
                    expectedRevision: current.draftRevision, expectedBaseCanonicalRevision: current.baseCanonicalRevision,
                    mutationID: conflicted.mutationID, postImage: .reviseCheckpoint(conflicted))
                _ = try fixture.target.writer.execute(fixture.request(revise))
                _ = try continueResolution(in: fixture, plan: plan, seed: 702)
                let second = try continuationProposal(in: fixture, offset: 3_100)
                XCTAssertEqual(second.checkpoint.draftID, proposal.checkpoint.draftID)
                XCTAssertEqual(second.mutation.mutationID, proposal.mutation.mutationID)
                XCTAssertNotEqual(second.mutation.continuationBinding, proposal.mutation.continuationBinding)
                let rereviewed = try fixture.target.rawState()
                XCTAssertThrowsError(try fixture.target.writer.execute(fixture.request(second.mutation)))
                XCTAssertEqual(try fixture.target.rawState(), rereviewed)
                XCTAssertEqual(try continuationEvidence(in: fixture), original)
                XCTAssertEqual(try fixture.target.context.fetch(FetchDescriptor<FieldDraftCheckpointRow>())
                    .filter { $0.draftID == proposal.checkpoint.draftID }.count, 1)
                try fixture.assertOriginalsRetained()
            }
        }
    }

    @MainActor
    func testLegacyCommandBytesStayExactAndClosedBindingTamperingHasNoEffect() throws {
        let source = try RepetitiveCaptureSourcePackageFixture(sourceOnly: true)
        defer { source.removePackages() }
        let fixture = try RepetitiveResolutionFixture(source: source)
        defer { try? fixture.close() }
        _ = try continueResolution(in: fixture)
        let proposal = try continuationProposal(in: fixture)
        let value = proposal.mutation
        let legacy = try FieldDraftMutationV1(workspaceID: value.workspaceID, expectedRevision: value.expectedRevision,
            expectedBaseCanonicalRevision: value.expectedBaseCanonicalRevision, mutationID: value.mutationID,
            postImage: value.postImage)
        struct LegacyCommand: Encodable {
            let schemaVersion: Int
            let workspaceID: WorkspaceID
            let expectedRevision: UInt64
            let expectedBaseCanonicalRevision: UInt64
            let mutationID: MutationIDV1
            let postImage: FieldDraftMutationPayloadV1
        }
        let mirror = LegacyCommand(schemaVersion: legacy.schemaVersion, workspaceID: legacy.workspaceID,
            expectedRevision: legacy.expectedRevision, expectedBaseCanonicalRevision: legacy.expectedBaseCanonicalRevision,
            mutationID: legacy.mutationID, postImage: legacy.postImage)
        XCTAssertEqual(try WorkspaceMutationCanonicalV1.data(legacy), try WorkspaceMutationCanonicalV1.data(mirror))
        let legacyObject = try XCTUnwrap(JSONSerialization.jsonObject(with: WorkspaceMutationCanonicalV1.data(legacy)) as? [String: Any])
        XCTAssertNil(legacyObject["continuationBinding"])
        XCTAssertEqual(proposal.checkpoint.codec, try RepetitiveCaptureProgressDraftCodecV2.release())
        let bytes = try WorkspaceMutationCanonicalV1.data(value)
        let originalObject = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        let binding = try XCTUnwrap(originalObject["continuationBinding"] as? [String: Any])
        let before = try fixture.target.rawState()
        for key in ["reviewEnvelopeSHA256", "reviewReceiptSHA256", "resolutionEnvelopeSHA256", "resolutionReceiptSHA256"] {
            var changedBinding = binding
            changedBinding[key] = String(repeating: "f", count: 64)
            var object = originalObject
            object["continuationBinding"] = changedBinding
            let changed = try continuationDecode(object)
            try changed.validate()
            XCTAssertThrowsError(try continuationProof(changed, in: fixture), key)
            XCTAssertThrowsError(try fixture.target.writer.execute(fixture.request(changed)), key)
            XCTAssertEqual(try fixture.target.rawState(), before, key)
        }
        for (key, replacement) in [("unexpected", "value"), ("schemaVersion", "2")] {
            var changedBinding = binding
            changedBinding[key] = replacement
            var object = originalObject
            object["continuationBinding"] = changedBinding
            XCTAssertThrowsError(try continuationDecode(object))
        }
        let wrongTime = try continuationProposal(in: fixture, offset: 3_001)
        XCTAssertEqual(wrongTime.mutation.mutationID, value.mutationID)
        XCTAssertNotEqual(wrongTime.mutation, value)
        XCTAssertThrowsError(try continuationProposal(in: fixture, offset: 999))
        XCTAssertEqual(try fixture.target.rawState(), before)
    }

    @MainActor
    func testPreparedContinuationIsSingleUseContextBoundAndRechecksCurrentRoundAndReview() throws {
        let source = try RepetitiveCaptureSourcePackageFixture(sourceOnly: true)
        defer { source.removePackages() }
        let fixture = try RepetitiveResolutionFixture(source: source)
        defer { try? fixture.close() }
        _ = try continueResolution(in: fixture)
        let proposal = try continuationProposal(in: fixture)
        let changed = try continuationProposal(in: fixture, offset: 3_001)
        let before = try fixture.target.rawState()
        let used = try continuationProof(proposal.mutation, in: fixture)
        try used.validateForApply(proposal.mutation, in: fixture.target.context)
        XCTAssertThrowsError(try used.validateForApply(proposal.mutation, in: fixture.target.context))
        let wrong = try continuationProof(proposal.mutation, in: fixture)
        XCTAssertThrowsError(try wrong.validateForApply(changed.mutation, in: fixture.target.context))
        XCTAssertThrowsError(try wrong.validateForApply(proposal.mutation, in: fixture.target.context))
        let otherContext = ModelContext(fixture.target.context.container)
        otherContext.autosaveEnabled = false
        let wrongContext = try continuationProof(proposal.mutation, in: fixture)
        XCTAssertThrowsError(try wrongContext.validateForApply(proposal.mutation, in: otherContext))
        XCTAssertThrowsError(try wrongContext.validateForApply(proposal.mutation, in: fixture.target.context))
        XCTAssertThrowsError(try WorkspaceWriterAdapterV1(modelContext: fixture.target.context).apply(
            .applyFieldDraft(proposal.mutation), occurredAt: proposal.checkpoint.updatedAt,
            temporaryRelativePath: "c36-continuation-generic-denial"))
        XCTAssertEqual(try fixture.target.rawState(), before)
        let request = try fixture.request(proposal.mutation)
        let stale = try continuationProof(proposal.mutation, in: fixture)
        try fixture.advance(.pause, state: .paused, mutationSeed: 710)
        let advanced = try fixture.target.rawState()
        XCTAssertThrowsError(try stale.validateForApply(proposal.mutation, in: fixture.target.context))
        XCTAssertThrowsError(try fixture.target.writer.execute(request))
        XCTAssertThrowsError(try continuationProof(proposal.mutation, in: fixture))
        XCTAssertThrowsError(try continuationProposal(in: fixture))
        XCTAssertEqual(try fixture.target.rawState(), advanced)
        try fixture.assertOriginalsRetained()
    }

    @MainActor
    func testColdOriginalRecoverySurvivesArchivedRoundAndRejectsMissingSourceReceipt() throws {
        let source = try RepetitiveCaptureSourcePackageFixture(sourceOnly: true)
        defer { source.removePackages() }
        let fixture = try RepetitiveResolutionFixture(source: source)
        defer { try? fixture.close() }
        _ = try continueResolution(in: fixture)
        let proposal = try continuationProposal(in: fixture)
        _ = try fixture.target.writer.execute(fixture.request(proposal.mutation))
        let expected = try continuationEvidence(in: fixture)
        try fixture.archiveRound()
        XCTAssertEqual(try continuationEvidence(in: fixture), expected)
        let receiptCount = try fixture.target.rawState().receipts.count
        try fixture.target.close()
        let reopened = try fixture.target.factory.openOrBootstrapCurrent()
        let coordinator = try StoreSessionCoordinator(validatingSession: reopened,
            lifecycleProfileRegistry: WorkspacePackageLifecycleCompatibilityV1.shippingRegistry())
        defer { try? coordinator.invalidateAndReleaseWriter() }
        let recovered = try coordinator.workspaceWriter.repetitiveCaptureDestinationContinuationEvidence(
            workspaceID: fixture.initialCheckpoint.workspaceID, reviewDraftID: fixture.initialCheckpoint.draftID)
        XCTAssertEqual(recovered, expected)
        XCTAssertEqual(try reopened.modelContext.fetchCount(FetchDescriptor<MutationReceiptRow>()), receiptCount)
        XCTAssertEqual(try reopened.modelContext.fetch(FetchDescriptor<FieldDraftCheckpointRow>())
            .filter { $0.draftID == proposal.checkpoint.draftID }.count, 1)
        let row = try XCTUnwrap(reopened.modelContext.fetch(FetchDescriptor<MutationReceiptRow>()).first {
            $0.workspaceMutationKey == MutationWorkspaceKeyV1.value(workspaceID: expected.binding.workspaceID,
                mutationID: expected.original.mutation.mutationID)
        })
        reopened.modelContext.delete(row)
        try reopened.modelContext.save()
        XCTAssertThrowsError(try coordinator.workspaceWriter.repetitiveCaptureDestinationContinuationEvidence(
            workspaceID: fixture.initialCheckpoint.workspaceID, reviewDraftID: fixture.initialCheckpoint.draftID))
        reopened.modelContext.insert(try MutationReceiptRow(envelope: expected.original.envelope,
            receipt: expected.original.receipt))
        try reopened.modelContext.save()
        XCTAssertEqual(try coordinator.workspaceWriter.repetitiveCaptureDestinationContinuationEvidence(
            workspaceID: fixture.initialCheckpoint.workspaceID, reviewDraftID: fixture.initialCheckpoint.draftID), expected)
        XCTAssertFalse(reopened.modelContext.hasChanges)
    }

    @MainActor
    func testDirtyCorruptQuarantinedAndPreemptedSourceStateDeniesWithoutEffects() throws {
        let source = try RepetitiveCaptureSourcePackageFixture(sourceOnly: true)
        defer { source.removePackages() }
        let fixture = try RepetitiveResolutionFixture(source: source)
        defer { try? fixture.close() }
        _ = try continueResolution(in: fixture)
        let proposal = try continuationProposal(in: fixture)
        let original = try XCTUnwrap(fixture.lineage().retainedSource.requiredHistory.first)
        let row = try XCTUnwrap(fixture.target.context.fetch(FetchDescriptor<MutationReceiptRow>()).first {
            $0.workspaceMutationKey == MutationWorkspaceKeyV1.value(
                workspaceID: original.envelope.workspaceID, mutationID: original.envelope.mutationID)
        })
        let digest = row.receiptSHA256
        let before = try fixture.target.rawState()
        let prepared = try continuationProof(proposal.mutation, in: fixture)
        row.receiptSHA256 = String(repeating: "f", count: 64)
        let dirty = try fixture.target.rawState()
        XCTAssertThrowsError(try continuationProof(proposal.mutation, in: fixture))
        XCTAssertThrowsError(try prepared.validateForApply(proposal.mutation, in: fixture.target.context))
        XCTAssertEqual(try fixture.target.rawState(), dirty)
        fixture.target.context.rollback()
        row.receiptSHA256 = String(repeating: "f", count: 64)
        try fixture.target.context.save()
        let corrupt = try fixture.target.rawState()
        XCTAssertThrowsError(try continuationProof(proposal.mutation, in: fixture))
        XCTAssertEqual(try fixture.target.rawState(), corrupt)
        row.receiptSHA256 = digest
        try fixture.target.context.save()
        let quarantine = MutationQuarantineRow(workspaceID: original.envelope.workspaceID,
            mutationID: original.envelope.mutationID, identityDomain: .mutationEnvelope,
            acceptedIdentitySHA256: original.receipt.envelopeSHA256,
            conflictingIdentitySHA256: String(repeating: "b", count: 64), detectedAt: proposal.checkpoint.updatedAt)
        fixture.target.context.insert(quarantine)
        try fixture.target.context.save()
        let quarantined = try fixture.target.rawState()
        XCTAssertThrowsError(try continuationProof(proposal.mutation, in: fixture))
        XCTAssertEqual(try fixture.target.rawState(), quarantined)
        fixture.target.context.delete(quarantine)
        try fixture.target.context.save()
        XCTAssertEqual(try fixture.target.rawState(), before)
        // An unbound pre-existing checkpoint cannot be relabelled as a
        // continuation, repaired by stamping a receipt, or bypassed with new IDs.
        let preempted = try FieldDraftMutationV1(workspaceID: proposal.mutation.workspaceID,
            expectedRevision: 0, expectedBaseCanonicalRevision: proposal.mutation.expectedBaseCanonicalRevision,
            mutationID: proposal.mutation.mutationID, postImage: proposal.mutation.postImage)
        _ = try fixture.target.writer.execute(fixture.request(preempted))
        let occupied = try fixture.target.rawState()
        XCTAssertThrowsError(try continuationEvidence(in: fixture))
        XCTAssertThrowsError(try fixture.target.writer.execute(fixture.request(proposal.mutation)))
        XCTAssertEqual(try fixture.target.rawState(), occupied)
        try fixture.assertOriginalsRetained()
    }

    @MainActor
    func testRealWriterFaultBoundariesRollbackOrRecoverExactlyOneContinuation() throws {
        let source = try RepetitiveCaptureSourcePackageFixture(sourceOnly: true)
        defer { source.removePackages() }
        for boundary in MutationJournalFaultBoundaryV1.allCases {
            let fixture = try RepetitiveResolutionFixture(source: source)
            defer { try? fixture.close() }
            _ = try continueResolution(in: fixture)
            let proposal = try continuationProposal(in: fixture)
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
                initialRevision: journal.currentRevision(writerInstanceID: continuationID(900)),
                clock: SystemApplicationClock(), idSource: SystemApplicationIDSource(),
                fileAuthority: SystemApplicationFileAuthorityV1(),
                adapter: WorkspaceWriterAdapterV1(modelContext: session.modelContext), journalStore: journal)
            defer { writer.invalidate() }
            let current = try writer.currentRevision()
            let request = try WorkspaceMutationRequestV1(mutationID: proposal.mutation.mutationID,
                expectedRevision: .init(workspaceID: current.workspaceID, generationID: current.generationID,
                    writerInstanceID: current.writerInstanceID, workspaceRevision: current.revision,
                    entityRevisions: proposal.mutation.concurrencyIdentities.map {
                        .init(identity: $0, revision: try proposal.mutation.expectedRevision(for: $0))
                    }), command: .applyFieldDraft(proposal.mutation))
            XCTAssertThrowsError(try writer.execute(request)) { error in
                XCTAssertEqual(error as? MutationJournalFailureV1, .injected(boundary))
            }
            if boundary == .afterSaveBeforeReturn {
                let original = try XCTUnwrap(writer.repetitiveCaptureDestinationContinuationEvidence(
                    workspaceID: fixture.initialCheckpoint.workspaceID, reviewDraftID: fixture.initialCheckpoint.draftID))
                XCTAssertEqual(original.sourceCheckpoint, proposal.checkpoint)
            } else {
                XCTAssertEqual(try fixture.target.rawState(), before)
                XCTAssertNil(try writer.repetitiveCaptureDestinationContinuationEvidence(
                    workspaceID: fixture.initialCheckpoint.workspaceID, reviewDraftID: fixture.initialCheckpoint.draftID))
            }
            _ = try writer.execute(request)
            let after = try fixture.target.rawState()
            _ = try writer.execute(request)
            XCTAssertEqual(try fixture.target.rawState(), after)
            XCTAssertEqual(try writer.repetitiveCaptureDestinationContinuationEvidence(
                workspaceID: fixture.initialCheckpoint.workspaceID, reviewDraftID: fixture.initialCheckpoint.draftID)?.sourceCheckpoint,
                proposal.checkpoint)
            XCTAssertEqual(try fixture.target.context.fetch(FetchDescriptor<FieldDraftCheckpointRow>())
                .filter { $0.draftID == proposal.checkpoint.draftID }.count, 1)
            let retained = try journal.exportSnapshot().receipts
            XCTAssertTrue(fixture.sourceOriginals.allSatisfy { retained.contains($0) })
        }
    }

    @MainActor
    func testProductionServiceRecoversBeforePreparationAndRejectsForeignOrRetiredOwners() throws {
        let source = try RepetitiveCaptureSourcePackageFixture(sourceOnly: true)
        defer { source.removePackages() }
        let fixture = try RepetitiveResolutionFixture(source: source)
        defer { try? fixture.close() }
        _ = try continueResolution(in: fixture)
        let clock = ContinuationClock(value: RepetitiveCaptureSourcePackageFixture.date.addingTimeInterval(3_000))
        let ids = ContinuationIDs()
        let gate = AppAccessGateV1(setting: .absentDisabled, authentication: ContinuationAuthentication(),
            clock: clock, identifiers: ids)
        let transitions = try ProductionRoundSessionTransitionServiceV1(session: fixture.target.coordinator,
            accessGate: gate, clock: clock, idSource: ids)
        let service = try ProductionRepetitiveCaptureProgressServiceV2(session: fixture.target.coordinator,
            transitions: transitions, clock: clock, idSource: ids)
        let other = try ProductionRepetitiveCaptureProgressServiceV2(session: fixture.target.coordinator,
            transitions: transitions, clock: clock, idSource: ids)
        let round = try XCTUnwrap(fixture.rounds().last)
        let prepared = try service.prepareDestinationContinuation(reviewDraftID: fixture.initialCheckpoint.draftID,
            round: round, manifest: continuationManifest(round))
        XCTAssertEqual(prepared.attemptState, .notAttempted)
        let before = try fixture.target.rawState()
        XCTAssertThrowsError(try other.committedDestinationContinuation(prepared))
        XCTAssertThrowsError(try other.persistDestinationContinuation(prepared))
        XCTAssertEqual(try fixture.target.rawState(), before)
        let original = try service.persistDestinationContinuation(prepared)
        XCTAssertEqual(prepared.attemptState, .checkpointWriteAttempted)
        try service.validateForPublication(original)
        XCTAssertEqual(try service.committedDestinationContinuation(prepared)?.evidence, original.evidence)
        XCTAssertThrowsError(try service.prepareDestinationContinuation(reviewDraftID: fixture.initialCheckpoint.draftID,
            round: round, manifest: continuationManifest(round)))
        try fixture.advance(.pause, state: .paused, mutationSeed: 800)
        XCTAssertThrowsError(try service.validateForPublication(original))
        XCTAssertEqual(try service.destinationContinuation(reviewDraftID: fixture.initialCheckpoint.draftID)?.evidence,
            original.evidence)
        XCTAssertEqual(ids.count, 0)
        let stored = try fixture.target.rawState()
        try fixture.target.coordinator.invalidateAndReleaseWriter()
        XCTAssertThrowsError(try service.destinationContinuation(reviewDraftID: fixture.initialCheckpoint.draftID))
        XCTAssertThrowsError(try service.persistDestinationContinuation(prepared))
        XCTAssertEqual(try fixture.target.rawState(), stored)
    }
}

private func continuationID(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "bc360000-0000-0000-0000-%012d", value))!
}

@MainActor
private func continueResolution(in fixture: RepetitiveResolutionFixture,
                                plan: DraftConflictResolutionPlanV1 = .continueEditing,
                                seed: Int = 600) throws -> ReviewedDraftConflictResolutionV1 {
    let lineage = try fixture.lineage()
    let value = try RepetitiveCaptureDestinationResolutionV1.propose(plan: plan, from: lineage,
        currentRoundHistory: fixture.rounds(), expectedWorkspaceRevision: fixture.target.writer.currentRevision().revision,
        mutationID: MutationIDV1(rawValue: continuationID(seed)),
        reviewedAt: lineage.selectedReview.checkpoint.updatedAt.addingTimeInterval(1))
    let mutation = try FieldDraftMutationV1(workspaceID: value.expectedCheckpoint.workspaceID,
        expectedRevision: value.expectedCheckpoint.draftRevision,
        expectedBaseCanonicalRevision: value.expectedCheckpoint.baseCanonicalRevision,
        mutationID: value.successorCheckpoint.mutationID, postImage: .resolveConflict(value))
    _ = try fixture.target.writer.execute(fixture.request(mutation))
    return value
}

@MainActor
private func continuationProposal(in fixture: RepetitiveResolutionFixture, offset: TimeInterval = 3_000) throws
    -> RepetitiveCaptureDestinationContinuationProposalV1 {
    let round = try XCTUnwrap(fixture.rounds().last)
    return try RepetitiveCaptureDestinationContinuationV1.propose(from: fixture.lineage(),
        currentRoundHistory: fixture.rounds(), manifest: continuationManifest(round),
        preparedAt: RepetitiveCaptureSourcePackageFixture.date.addingTimeInterval(offset))
}

@MainActor
private func continuationProof(_ mutation: FieldDraftMutationV1, in fixture: RepetitiveResolutionFixture) throws
    -> PreparedReviewedFieldDraftApplyProofV1 {
    try fixture.target.journal.validatePendingRepetitiveCaptureDestinationContinuation(
        mutation, expectedWorkspaceRevision: fixture.target.writer.currentRevision().revision)
}

@MainActor
private func continuationEvidence(in fixture: RepetitiveResolutionFixture) throws
    -> RepetitiveCaptureDestinationContinuationEvidenceV1 {
    try XCTUnwrap(fixture.target.writer.repetitiveCaptureDestinationContinuationEvidence(
        workspaceID: fixture.initialCheckpoint.workspaceID, reviewDraftID: fixture.initialCheckpoint.draftID))
}

private func continuationManifest(_ round: RoundSessionV1) throws -> OfflineReadinessManifestV1 {
    let package = try RoundPackageReleaseReferenceV1(packageReleaseID: String(repeating: "a", count: 64),
        packageID: "c36-continuation", packageContentVersion: 1, packageSHA256: String(repeating: "a", count: 64),
        workflowSHA256: String(repeating: "b", count: 64))
    return try OfflineReadinessManifestBuilderV1.build(snapshot: .init(session: round.reference,
        expectedPackage: package, observedPackage: package,
        selectedAssets: round.items.map(\.selection).sorted { $0.assetID.uuidString < $1.assetID.uuidString },
        observedAssetIDs: Set(round.items.map { $0.selection.assetID }), guidanceReferenceIDs: [],
        availableGuidanceReferenceIDs: [], contentRequirements: [], contentObservations: [],
        expectedFieldReferences: [], fieldReferenceReadiness: [],
        storage: .init(capacityState: .checked, availableBytes: 100_000),
        access: .init(protectedDataAvailable: true),
        checkedAt: RepetitiveCaptureSourcePackageFixture.date.addingTimeInterval(2_000),
        timeZoneIdentifier: "America/New_York", clockState: .checked))
}

private func continuationCheckpoint(_ prior: FieldDraftCheckpointV1, state: FieldDraftStateV1, seed: Int) throws
    -> FieldDraftCheckpointV1 {
    try .init(draftID: prior.draftID, workspaceID: prior.workspaceID, scope: prior.scope, purpose: prior.purpose,
        codec: prior.codec, baseCanonicalRevision: prior.baseCanonicalRevision, draftRevision: prior.draftRevision + 1,
        payloadData: prior.payloadData, stageIDs: prior.stageIDs, resumeAnchor: prior.resumeAnchor, state: state,
        lastDurableMutationID: prior.lastDurableMutationID, lastReceiptSHA256: prior.lastReceiptSHA256,
        updatedAt: prior.updatedAt.addingTimeInterval(1), mutationID: MutationIDV1(rawValue: continuationID(seed)))
}

private func continuationDecode(_ object: [String: Any]) throws -> FieldDraftMutationV1 {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .millisecondsSince1970
    return try decoder.decode(FieldDraftMutationV1.self, from: JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
}

private struct ContinuationClock: ApplicationClock {
    let value: Date
    func now() -> Date { value }
}

private final class ContinuationIDs: ApplicationIDSource, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return calls }
    func makeID() -> UUID { lock.lock(); defer { lock.unlock() }; calls += 1; return UUID() }
}

private actor ContinuationAuthentication: LocalAuthenticationClient {
    func availability() -> LocalAuthenticationAvailabilityV1 { .systemValue(status: .available, biometry: .faceID) }
    func authenticate(_ attempt: LocalAuthenticationAttemptV1) -> LocalAuthenticationOutcomeV1 { .authenticated }
    func cancel(attemptID: UUID) {}
}

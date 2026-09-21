import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

@MainActor
final class V23RepetitiveCaptureRestoreReviewTests: XCTestCase {
    func testPhysicalForkCreatesReviewReceiptAndSecondHopSurvivesOriginalPackageRemoval() async throws {
        let timing = RestoreReviewTimingV1(enabled: true)
        timing.mark("source-fixture.begin")
        let source = try RepetitiveCaptureSourcePackageFixture(sourceOnly: true)
        timing.mark("source-fixture.end")
        defer { source.removePackages() }
        let harness = try RestoreReviewHarness(timing: timing)
        defer { harness.remove() }
        timing.mark("first-package.begin")
        let firstPackage = try source.package(named: "first")
        timing.mark("first-package.end")
        let first = try await harness.restore(firstPackage, mode: .fork)
        timing.mark("first-review.begin")
        let firstReview = try harness.onlyReview(in: first)
        let firstHistory = try harness.history(in: first)
        try assertOriginals(source.history, retainedIn: firstHistory)
        XCTAssertEqual(firstHistory.receipts.count, source.history.receipts.count + 1)
        XCTAssertEqual(firstReview.state, .recoveryRequired)
        XCTAssertEqual(firstReview.draftRevision, 1)
        XCTAssertTrue(firstReview.stageIDs.isEmpty)
        XCTAssertFalse(source.checkpoints.contains { $0.draftID == firstReview.draftID })
        XCTAssertNil(try RepetitiveCaptureDestinationReviewCodecV1.decode(firstReview.payloadData)
            .provenance.immediatePredecessor)
        timing.mark("first-review.end")
        timing.mark("first-export.begin")
        let exported = try harness.export(first)
        timing.mark("first-export.end")
        source.removePackages()
        timing.mark("source-packages.removed")

        let second = try await harness.restore(exported, mode: .fork)
        timing.mark("second-review.begin")
        let secondReview = try harness.onlyReview(in: second)
        let secondHistory = try harness.history(in: second)
        try assertOriginals(firstHistory, retainedIn: secondHistory)
        XCTAssertEqual(secondHistory.receipts.count, firstHistory.receipts.count + 1)
        XCTAssertNotEqual(firstReview.workspaceID, secondReview.workspaceID)
        XCTAssertNotEqual(firstReview.draftID, secondReview.draftID)
        timing.mark("second-review.end")
        timing.mark("reopen.begin")
        let reopened = try harness.factory.openOrBootstrapCurrent()
        timing.mark("reopen.end")
        XCTAssertEqual(reopened.generationID, second.generationID)
        try harness.assertCurrentAuxiliaryReadback(in: reopened)
        timing.mark("coordinator.begin")
        let coordinator = try StoreSessionCoordinator(validatingSession: reopened)
        timing.mark("coordinator.end")
        defer { try? coordinator.invalidateAndReleaseWriter() }
        timing.mark("lineage.begin")
        let lineage = try RepetitiveCaptureReviewLineageReaderV1.read(
            workspaceID: secondReview.workspaceID, mutationID: secondReview.mutationID,
            in: harness.history(in: reopened))
        XCTAssertEqual(lineage.reviews.count, 2)
        XCTAssertEqual(lineage.reviews.first?.initialCheckpoint, firstReview)
        XCTAssertEqual(lineage.selectedReview.initialCheckpoint, secondReview)
        XCTAssertEqual(try reopened.modelContext.fetchCount(FetchDescriptor<FieldDraftCheckpointRow>()), 1)
        XCTAssertEqual(try harness.history(in: reopened), secondHistory)
        timing.mark("journey.complete")
    }

    func testPopulatedCrossWorkspaceReplacementCreatesOnlyReviewAndRetainsOriginalHistory() async throws {
        let source = try RepetitiveCaptureSourcePackageFixture(sourceOnly: true)
        defer { source.removePackages() }
        let harness = try RestoreReviewHarness(timing: RestoreReviewTimingV1(enabled: true))
        defer { harness.remove() }
        let incumbent = try harness.populate()
        let incumbentIdentity = incumbent.workspaceIdentity
        let incumbentHistory = try harness.history(in: incumbent)
        let restored = try await harness.restore(try source.package(named: "replace"), mode: .replaceExisting)
        XCTAssertEqual(restored.workspaceIdentity, incumbentIdentity)
        let review = try harness.onlyReview(in: restored)
        XCTAssertEqual(review.workspaceID, incumbentIdentity.workspaceID)
        let history = try harness.history(in: restored)
        XCTAssertGreaterThan(incumbentHistory.lastLocalSequence, 0)
        XCTAssertEqual(history.lastLocalSequence, incumbentHistory.lastLocalSequence + 1)
        XCTAssertGreaterThan(history.workspaceRevision, incumbentHistory.workspaceRevision)
        let activeReceipts = try history.receipts.map {
            try MutationReceiptV1.decodeCanonical(from: $0.receiptData)
        }.filter {
            $0.identity.workspaceID == incumbentIdentity.workspaceID
                && $0.identity.replicaID == incumbentIdentity.replicaID
        }
        XCTAssertEqual(activeReceipts.map(\.identity.localSequence).max(), history.lastLocalSequence)
        try assertOriginals(source.history, retainedIn: history)
        try assertOriginals(incumbentHistory, retainedIn: history)
        try assertProjectedRoundRows(source.rounds, in: restored, history: history)
        XCTAssertEqual(try RepetitiveCaptureDestinationReviewCodecV1.decode(review.payloadData)
            .provenance.mode, .crossWorkspaceReplace)
        XCTAssertEqual(try restored.modelContext.fetchCount(FetchDescriptor<FieldDraftCheckpointRow>()), 1)
        XCTAssertEqual(try restored.modelContext.fetchCount(FetchDescriptor<DraftCommitSagaRow>()), 0)
        XCTAssertEqual(try restored.modelContext.fetchCount(FetchDescriptor<DraftContentReservationRow>()), 0)
        let cold = try harness.factory.openOrBootstrapCurrent()
        XCTAssertEqual(cold.generationID, restored.generationID)
        try harness.assertCurrentAuxiliaryReadback(in: cold)
        XCTAssertEqual(try harness.history(in: cold), history)
        try assertProjectedRoundRows(source.rounds, in: cold, history: history)
    }

    func testSameWorkspaceReplacementPreservesCheckpointAndOriginalReceiptBytes() async throws {
        let source = try RepetitiveCaptureSourcePackageFixture(sourceOnly: true)
        defer { source.removePackages() }
        let harness = try RestoreReviewHarness(timing: RestoreReviewTimingV1(enabled: true))
        defer { harness.remove() }
        try harness.assertAuxiliaryReadbackContracts()
        let first = try await harness.restore(try source.package(named: "install"), mode: .emptyInstall)
        let firstRows = try first.modelContext.fetch(FetchDescriptor<FieldDraftCheckpointRow>()).map { try $0.value() }
        let firstHistory = try harness.history(in: first)
        XCTAssertEqual(firstRows, source.checkpoints)
        XCTAssertTrue(firstRows.contains { $0.draftRevision > 0 })
        // Imported validation must still reject an incomplete revision frontier,
        // and the restore-only initializer must not leave its bootstrap state.
        let schema = Schema(PersistentSchemaV53.models, version: PersistentSchemaV53.versionIdentifier)
        let container = try ModelContainer(for: schema, migrationPlan: nil, configurations: [
            ModelConfiguration("RejectedRestoreHistory", schema: schema, isStoredInMemoryOnly: true,
                               allowsSave: true, cloudKitDatabase: .none)
        ])
        let rejectedContext = ModelContext(container)
        rejectedContext.autosaveEnabled = false
        let missingRevision = try XCTUnwrap(source.history.entityRevisions.first {
            $0.identity.kind == .fieldDraftCheckpoint
        })
        let incomplete = MutationHistorySnapshotV1(
            workspaceRevision: source.history.workspaceRevision,
            lastLocalSequence: source.history.lastLocalSequence,
            receipts: source.history.receipts,
            quarantines: source.history.quarantines,
            entityRevisions: source.history.entityRevisions.filter { $0.identity != missingRevision.identity }
        )
        XCTAssertThrowsError(try MutationJournalStoreV1(
            modelContext: rejectedContext, identity: first.workspaceIdentity, generationID: UUID(),
            importingHistory: incomplete, identityDisposition: .preserve
        )) { error in
            XCTAssertEqual(error as? WorkspaceMutationFailureV1, .receiptHistoryCorrupt)
        }
        XCTAssertEqual(try rejectedContext.fetchCount(FetchDescriptor<WorkspaceMutationStateRow>()), 0)
        XCTAssertEqual(try rejectedContext.fetchCount(FetchDescriptor<MutationReceiptRow>()), 0)
        XCTAssertEqual(try rejectedContext.fetchCount(FetchDescriptor<EntityMutationRevisionRow>()), 0)
        let restored = try await harness.restore(try source.package(named: "same-workspace"), mode: .replaceExisting)
        let rows = try restored.modelContext.fetch(FetchDescriptor<FieldDraftCheckpointRow>()).map { try $0.value() }
        XCTAssertEqual(rows, firstRows)
        XCTAssertEqual(try harness.history(in: restored).receipts, firstHistory.receipts)
        let restoredHistory = try harness.history(in: restored)
        XCTAssertEqual(restoredHistory, firstHistory)
        XCTAssertTrue(firstHistory.entityRevisions.contains { $0.externalProjectionSHA256 == nil })
        let coldFactory = StoreGenerationFactory(applicationSupportURL: harness.support)
        let cold = try coldFactory.openOrBootstrapCurrent()
        XCTAssertEqual(try harness.history(in: cold), firstHistory)
        let reviewRelease = try RepetitiveCaptureDestinationReviewCodecV1.release()
        XCTAssertTrue(rows.allSatisfy { $0.codec != reviewRelease })
        try assertDeletionHistoryPlanningUsesFinalLedgerWithoutInventingReceipts()
        try await assertSameWorkspaceDeletionWinsIncomingLiveAssetAndPreservesOriginalHistory()
    }

    private func assertDeletionHistoryPlanningUsesFinalLedgerWithoutInventingReceipts() throws {
        // A deliberately minimal projected-history fixture tests the pure plan;
        // the physical deletion case below separately exercises the real store.
        let workspace = try WorkspaceReplicaIdentityV1(
            workspaceID: WorkspaceID(rawValue: UUID()), replicaID: ReplicaID(rawValue: UUID()))
        let deletedID = UUID()
        let deletionIdentity = try DeletionIdentityV2(kind: .asset, id: deletedID)
        let late = try DeletionLedgerEntryV2(identity: deletionIdentity,
            deletedAt: RepetitiveCaptureSourcePackageFixture.date)
        let early = try DeletionLedgerEntryV2(identity: deletionIdentity,
            deletedAt: RepetitiveCaptureSourcePackageFixture.date.addingTimeInterval(-60))
        let terminalIdentity = try WorkspaceEntityIdentityV1(kind: .deletionLedgerEntry, id: deletedID)
        struct LedgerBasis: Codable {
            let identity: WorkspaceEntityIdentityV1
            let revision: UInt64
            let value: DeletionLedgerEntryV2
        }
        let oldDigest = try WorkspaceMutationCanonicalV1.sha256(
            LedgerBasis(identity: terminalIdentity, revision: 7, value: late))
        let expectedDigest = try WorkspaceMutationCanonicalV1.sha256(
            LedgerBasis(identity: terminalIdentity, revision: 7, value: early))
        XCTAssertNotEqual(oldDigest, expectedDigest)
        let history = MutationHistorySnapshotV1(workspaceRevision: 0, lastLocalSequence: 0,
            receipts: [], quarantines: [], entityRevisions: [
                .init(identity: terminalIdentity, revision: 7, externalProjectionSHA256: oldDigest)
            ])
        try MutationJournalStoreV1.validateImportedSnapshot(history)
        let emptyHistory = MutationHistorySnapshotV1(workspaceRevision: 0, lastLocalSequence: 0,
            receipts: [], quarantines: [], entityRevisions: [])
        func records(_ entries: [DeletionLedgerEntryV2], _ history: MutationHistorySnapshotV1) throws -> V4BackupRecordsV1 {
            V4BackupRecordsV1(assets: [], deletionLedger: try DeletionLedgerV2(entries:
                entries.sorted { $0.identity < $1.identity }), evidenceFiles: [], issues: [],
                mutationHistory: history, packets: [], recordsSchemaVersion: 3,
                reports: [], sites: [], workflowRecords: [])
        }
        let current = try records([late], history)
        let incoming = try records([early], emptyHistory)
        let result = try ReplacementRestoreRule.makeDeletionWinningPlan(.init(
            currentRecords: current, currentIdentity: workspace,
            incomingRecords: incoming, incomingIdentity: workspace,
            mode: .replaceExisting, replacementAt: late.deletedAt.addingTimeInterval(60)))
        let planned = try XCTUnwrap(result.recordsAfter.mutationHistory)
        XCTAssertEqual(result.deletionLedger.entries, [early])
        XCTAssertEqual(planned.entityRevisions, [
            .init(identity: terminalIdentity, revision: 7, externalProjectionSHA256: expectedDigest)
        ])
        XCTAssertEqual(planned.receipts, history.receipts)
        XCTAssertEqual(planned.quarantines, history.quarantines)
        XCTAssertEqual(planned.workspaceRevision, history.workspaceRevision)
        XCTAssertEqual(planned.lastLocalSequence, history.lastLocalSequence)
        try MutationJournalStoreV1.validateImportedSnapshot(planned)
        // No new terminal is invented for a newly introduced ledger row.
        let extra = try DeletionLedgerEntryV2(identity: DeletionIdentityV2(kind: .asset, id: UUID()),
            deletedAt: early.deletedAt)
        let expanded = try ReplacementRestoreRule.makeDeletionWinningPlan(.init(
            currentRecords: current, currentIdentity: workspace,
            incomingRecords: records([early, extra], emptyHistory), incomingIdentity: workspace,
            mode: .replaceExisting, replacementAt: late.deletedAt.addingTimeInterval(60)))
        XCTAssertEqual(expanded.recordsAfter.mutationHistory?.entityRevisions, planned.entityRevisions)
        // Typed deletion identities sharing a UUID cannot choose one live
        // journal image by array order.
        let collision = try DeletionLedgerEntryV2(identity: DeletionIdentityV2(kind: .site, id: deletedID),
            deletedAt: early.deletedAt)
        XCTAssertThrowsError(try ReplacementRestoreRule.makeDeletionWinningPlan(.init(
            currentRecords: current, currentIdentity: workspace,
            incomingRecords: records([early, collision], emptyHistory), incomingIdentity: workspace,
            mode: .replaceExisting, replacementAt: late.deletedAt.addingTimeInterval(60))))
        // Existing identity-less callers retain their released plan semantics.
        let legacy = try ReplacementRestoreRule.makeDeletionWinningPlan(.init(
            currentRecords: current, incomingRecords: incoming,
            mode: .replaceExisting, replacementAt: late.deletedAt.addingTimeInterval(60)))
        XCTAssertEqual(legacy.recordsAfter.mutationHistory, history)
    }

    private func assertSameWorkspaceDeletionWinsIncomingLiveAssetAndPreservesOriginalHistory() async throws {
        let harness = try RestoreReviewHarness(timing: RestoreReviewTimingV1(enabled: true))
        defer { harness.remove() }
        let current = try harness.populate()
        let asset = try XCTUnwrap(current.modelContext.fetch(FetchDescriptor<Asset>()).first)
        let assetID = asset.id
        let original = try harness.history(in: current)
        let incoming = try harness.export(current)
        let deletedAt = RepetitiveCaptureSourcePackageFixture.date.addingTimeInterval(60)
        _ = try await WholeSignDeletionService(
            modelContext: current.modelContext, generationRootURL: current.generationRootURL,
            now: { deletedAt }
        ).delete(assetID: assetID)
        let deletedHistory = try harness.history(in: current)
        let ledgerBefore = try DeletionLedgerStore(context: current.modelContext).snapshot()
        XCTAssertEqual(try current.modelContext.fetchCount(FetchDescriptor<Asset>()), 0)
        XCTAssertTrue(ledgerBefore.entries.contains { $0.identity.kind == .asset && $0.identity.id == assetID })
        let restored = try await harness.restore(incoming, mode: .replaceExisting)
        let history = try harness.history(in: restored)
        try assertOriginals(original, retainedIn: history)
        try assertOriginals(deletedHistory, retainedIn: history)
        XCTAssertEqual(try restored.modelContext.fetchCount(FetchDescriptor<Asset>()), 0)
        XCTAssertEqual(try DeletionLedgerStore(context: restored.modelContext).snapshot(), ledgerBefore)
        let identity = try WorkspaceEntityIdentityV1(kind: .asset, id: assetID)
        let originalTerminal = try XCTUnwrap(original.entityRevisions.first { $0.identity == identity })
        let terminal = try XCTUnwrap(history.entityRevisions.first { $0.identity == identity })
        XCTAssertEqual(terminal.revision, originalTerminal.revision)
        struct AbsentBasis: Codable {
            let identity: WorkspaceEntityIdentityV1
            let revision: UInt64
            let disposition: String
        }
        XCTAssertEqual(terminal.externalProjectionSHA256,
            try WorkspaceMutationCanonicalV1.sha256(AbsentBasis(identity: identity,
                revision: originalTerminal.revision, disposition: "ABSENT_AFTER_MUTATION")))
        let coldFactory = StoreGenerationFactory(applicationSupportURL: harness.support)
        let cold = try coldFactory.openOrBootstrapCurrent()
        XCTAssertEqual(try harness.history(in: cold), history)
        XCTAssertEqual(try cold.modelContext.fetchCount(FetchDescriptor<Asset>()), 0)
    }

    func testPrepublicationInterruptionReconcilesToUnchangedPopulatedGeneration() async throws {
        for point in [BackupRestoreFailurePoint.beforePreparedWrite, .afterPreparedWrite] {
        let source = try RepetitiveCaptureSourcePackageFixture(sourceOnly: true)
        defer { source.removePackages() }
        let harness = try RestoreReviewHarness(timing: RestoreReviewTimingV1(enabled: true))
        defer { harness.remove() }
        let current = try harness.populate()
        let before = try harness.history(in: current)
        let originalID = current.generationID
        let sourcePackage = try source.package(named: "failure")
        do {
            _ = try await harness.restore(sourcePackage, mode: .replaceExisting,
                failure: BackupRestoreFailureInjection(failOnceAt: point))
            XCTFail("The injected prepublication failure must be reported")
        } catch {
            XCTAssertEqual(error as? BackupRestoreServiceError, .injectedFailure)
            let authority = try harness.factory.makeRestoreGenerationAuthority()
            let stagedNames = try authority.restoreGenerationNames()
            XCTAssertEqual(stagedNames.count, 1)
            let stagedID = try XCTUnwrap(stagedNames.first.flatMap(UUID.init(uuidString:)))
            let staged = try harness.factory.openRestoreStagingGeneration(id: stagedID,
                identity: current.workspaceIdentity, authority: authority)
            _ = try harness.onlyReview(in: staged)
            try assertOriginals(source.history, retainedIn: harness.history(in: staged))
            try assertProjectedRoundRows(source.rounds, in: staged, history: harness.history(in: staged))
            let recoveryService = try BackupRestoreService(applicationSupportURL: harness.support)
            let oldRecords = try recoveryService.c55CurrentRecordsForTesting(in: current.modelContext)
            let targetRecords = try recoveryService.c55CurrentRecordsForTesting(in: staged.modelContext)
            let ordinary = try ReplacementRestoreRule.makeDeletionWinningPlan(.init(
                currentRecords: oldRecords, currentIdentity: current.workspaceIdentity,
                incomingRecords: targetRecords, incomingIdentity: staged.workspaceIdentity,
                mode: .replaceExisting, replacementAt: RepetitiveCaptureSourcePackageFixture.date.addingTimeInterval(3_600)))
            let recoveredPlan = try recoveryService.c36RecoveryPlanForTesting(
                current: oldRecords, currentIdentity: current.workspaceIdentity,
                target: staged, replacementAt: RepetitiveCaptureSourcePackageFixture.date.addingTimeInterval(3_600))
            XCTAssertNotEqual(ordinary.recordsAfter.mutationHistory, targetRecords.mutationHistory)
            XCTAssertEqual(recoveredPlan.recordsAfter, targetRecords)
            try assertOriginals(before, retainedIn: XCTUnwrap(recoveredPlan.recordsAfter.mutationHistory))
            XCTAssertEqual(try harness.factory.currentGenerationID(), originalID)
            let reopened = try harness.factory.openOrBootstrapCurrent()
            XCTAssertEqual(try harness.history(in: reopened), before)
            XCTAssertEqual(try reopened.modelContext.fetchCount(FetchDescriptor<FieldDraftCheckpointRow>()), 0)
            XCTAssertEqual(try reopened.modelContext.fetchCount(FetchDescriptor<Asset>()), 1)
            XCTAssertTrue(FileManager.default.fileExists(atPath: sourcePackage.path))
            XCTAssertEqual(try RestoreIntentStore(applicationSupportURL: harness.support).load() != nil,
                           point == .afterPreparedWrite)
        }
        var recoveryPhase = "create-recovery-service"
        var recoveryDifferences: [String] = []
        let recovered: StoreGenerationSession?
        let recovery: BackupRestoreService
        do {
            recovery = try BackupRestoreService(applicationSupportURL: harness.support)
#if DEBUG
            recovery.restorePhaseDiagnosticForTesting = { value in
                recoveryPhase = value
                if value.contains(".history."), recoveryDifferences.count < 32 {
                    recoveryDifferences.append(value)
                }
            }
#endif
            recoveryPhase = "invoke-cold-recovery"
            recovered = try await recovery.reconcileRestoreAndPrivateSystemDiscoveryAtStartup()
        } catch {
            print("RestoreReviewColdRecovery.failure phase=\(recoveryPhase) type=\(String(reflecting: type(of: error)))")
            print("RestoreReviewColdRecovery.historyDifferences=\(recoveryDifferences.joined(separator: ","))")
            throw error
        }
        XCTAssertNil(recovered)
        XCTAssertEqual(try harness.factory.currentGenerationID(), originalID)
        let coldFactory = StoreGenerationFactory(applicationSupportURL: harness.support)
        let cold = try coldFactory.openOrBootstrapCurrent()
        XCTAssertEqual(try harness.history(in: cold), before)
        XCTAssertEqual(try cold.modelContext.fetchCount(FetchDescriptor<Asset>()), 1)
        XCTAssertEqual(try cold.modelContext.fetchCount(FetchDescriptor<FieldDraftCheckpointRow>()), 0)
        XCTAssertNil(try RestoreIntentStore(applicationSupportURL: harness.support).load())
        let repeated = try await recovery.reconcileRestoreAndPrivateSystemDiscoveryAtStartup()
        XCTAssertNil(repeated)
        XCTAssertEqual(try harness.history(in: cold), before)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourcePackage.path))
        let unmodified = try recovery.c55CurrentRecordsForTesting(in: cold.modelContext)
        let terminalRows = try cold.modelContext.fetch(FetchDescriptor<EntityMutationRevisionRow>())
        let terminalRow = try XCTUnwrap(terminalRows.first)
        let originalProjection = terminalRow.externalProjectionSHA256
        terminalRow.externalProjectionSHA256 = String(repeating: "e", count: 64)
        try cold.modelContext.save()
        XCTAssertThrowsError(try recovery.c36RecoveryPlanForTesting(current: unmodified,
            currentIdentity: cold.workspaceIdentity, target: cold,
            replacementAt: RepetitiveCaptureSourcePackageFixture.date.addingTimeInterval(3_600)))
        terminalRow.externalProjectionSHA256 = originalProjection
        try cold.modelContext.save()
        XCTAssertEqual(try recovery.c55CurrentRecordsForTesting(in: cold.modelContext), unmodified)
        }
    }

    func testPhysicalForkKeepsTerminalHistoryAndUnrelatedDraftOwners() async throws {
        // Separate authentic packages: terminal C36 ownership and unrelated
        // semantic-reversal originals are independent retained obligations.
        for discarded in [true, false] {
            let source = try RepetitiveCaptureSourcePackageFixture(
                discardSource: discarded, includeUnrelatedHistory: !discarded)
            defer { source.removePackages() }
            let physical = try source.validatedPackage()
            let sourceRelease = try RepetitiveCaptureProgressDraftCodecV2.release()
            let originalRows = try physical.records.fieldDrafts.filter { $0.kind == .checkpoint }
                .map { try FieldDraftCanonicalCodecV1.decode(FieldDraftCheckpointV1.self, from: $0.canonicalData) }
            let unrelated = originalRows.filter { $0.codec != sourceRelease }
            if discarded {
                XCTAssertTrue(originalRows.contains { $0.state == .discarded })
                XCTAssertTrue(physical.records.fieldDrafts.contains { $0.kind == .discardReceipt })
            } else {
                XCTAssertEqual(unrelated.count, 2)
            }
            let harness = try RestoreReviewHarness(timing: RestoreReviewTimingV1(enabled: true))
            defer { harness.remove() }
            let restored = try await harness.restore(try source.package(named: "owned-rows"), mode: .fork)
            let review = try harness.onlyReview(in: restored)
            let rows = try restored.modelContext.fetch(FetchDescriptor<FieldDraftCheckpointRow>())
                .map { try $0.value() }
            XCTAssertFalse(rows.contains { $0.codec == sourceRelease })
            func mapped(_ value: UUID, namespace: String) throws -> UUID {
                try XCTUnwrap(RestoreIdentityV1.destinationFieldDraftID(for: value,
                    namespace: namespace, mode: .fork,
                    destinationWorkspaceID: restored.workspaceID.rawValue))
            }
            let expectedIDs = try unrelated.map { try mapped($0.draftID, namespace: "draft") }
            XCTAssertEqual(Set(rows.map(\.draftID)), Set(expectedIDs + [review.draftID]))
            let restoredHistory = try harness.history(in: restored)
            for original in unrelated {
                let expectedID = try mapped(original.draftID, namespace: "draft")
                let rebound = try XCTUnwrap(rows.first { $0.draftID == expectedID })
                XCTAssertEqual(rebound.workspaceID, restored.workspaceID)
                XCTAssertEqual(rebound.mutationID.rawValue,
                               try mapped(original.mutationID.rawValue, namespace: "mutation.checkpoint"))
                XCTAssertEqual(rebound.scope.scopeKind, original.scope.scopeKind)
                let expectedComponents = try original.scope.stableComponentIDs.map { component in
                    guard let id = UUID(uuidString: component) else { return component }
                    return try mapped(id, namespace: "scope").uuidString.lowercased()
                }
                XCTAssertEqual(rebound.scope.stableComponentIDs, expectedComponents)
                XCTAssertEqual(rebound.purpose, original.purpose)
                XCTAssertEqual(rebound.codec, original.codec)
                XCTAssertEqual(rebound.payloadData, original.payloadData)
                XCTAssertEqual(rebound.state, .recoveryRequired)
                XCTAssertNil(rebound.lastDurableMutationID)
                XCTAssertNil(rebound.lastReceiptSHA256)
                XCTAssertEqual(rebound.draftRevision, original.draftRevision)
                XCTAssertEqual(rebound.baseCanonicalRevision, original.baseCanonicalRevision)
                XCTAssertEqual(rebound.updatedAt, original.updatedAt)
                XCTAssertEqual(rebound.resumeAnchor, original.resumeAnchor)
                XCTAssertEqual(rebound.stageIDs, [])
                let mappedIdentity = try WorkspaceEntityIdentityV1(kind: .fieldDraftCheckpoint, id: expectedID)
                let mappedTerminal = try XCTUnwrap(restoredHistory.entityRevisions.first {
                    $0.identity == mappedIdentity
                })
                XCTAssertEqual(mappedTerminal.revision, original.draftRevision)
                XCTAssertEqual(mappedTerminal.externalProjectionSHA256, rebound.checkpointSHA256)
                let originalIdentity = try WorkspaceEntityIdentityV1(kind: .fieldDraftCheckpoint, id: original.draftID)
                let originalTerminal = try XCTUnwrap(restoredHistory.entityRevisions.first {
                    $0.identity == originalIdentity
                })
                XCTAssertEqual(originalTerminal.revision, original.draftRevision)
                // Independent wire basis; do not derive expectations from the
                // journal helper whose restore behavior this test exercises.
                struct AbsentBasis: Codable {
                    let identity: WorkspaceEntityIdentityV1
                    let revision: UInt64
                    let disposition: String
                }
                XCTAssertEqual(originalTerminal.externalProjectionSHA256,
                    try WorkspaceMutationCanonicalV1.sha256(AbsentBasis(
                        identity: originalIdentity, revision: original.draftRevision,
                        disposition: "ABSENT_AFTER_MUTATION")))
            }
            try assertOriginals(source.history, retainedIn: harness.history(in: restored))
            let coldFactory = StoreGenerationFactory(applicationSupportURL: harness.support)
            let cold = try coldFactory.openOrBootstrapCurrent()
            XCTAssertEqual(try harness.history(in: cold), restoredHistory)
            let nextPackage = try harness.export(cold)
            let secondHarness = try RestoreReviewHarness(timing: RestoreReviewTimingV1(enabled: true))
            defer { secondHarness.remove() }
            let second = try await secondHarness.restore(nextPackage, mode: .fork)
            let secondHistory = try secondHarness.history(in: second)
            try assertOriginals(restoredHistory, retainedIn: secondHistory)
            let payload = try RepetitiveCaptureDestinationReviewCodecV1.decode(review.payloadData)
            XCTAssertEqual(payload.source.value.checkpoints.contains(where: { $0.current.state == .discarded }), discarded)
            XCTAssertEqual(try restored.modelContext.fetchCount(FetchDescriptor<DraftDiscardReceiptRow>()), 0)
        }
    }

    func testReviewPlanRejectsMissingOrChangedOwnedRowsWithoutConsumingUnrelatedDrafts() throws {
        let source = try RepetitiveCaptureSourcePackageFixture(sourceOnly: true)
        defer { source.removePackages() }
        let package = try source.validatedPackage()
        let identity = try RestoreIdentityDecisionV1.decide(.init(
            mode: .fork,
            source: .init(workspaceID: package.source.workspaceID, replicaID: package.source.replicaID),
            oldPointer: .init(generationID: UUID(), generationManifestSHA256: String(repeating: "a", count: 64),
                workspaceID: UUID(), replicaID: UUID()),
            targetGenerationID: UUID(), targetGenerationManifestSHA256: String(repeating: "0", count: 64),
            allocatedWorkspaceID: UUID(), allocatedReplicaID: UUID()))
        let prepared = try RepetitiveCaptureRestoreReviewPlanV1.prepare(sourcePackage: package,
            identity: identity, restoreID: UUID(), reviewedAt: RepetitiveCaptureSourcePackageFixture.date)
        let plan = try XCTUnwrap(prepared)
        XCTAssertEqual(try plan.retainingUnownedRows(package.records.fieldDrafts), [])
        XCTAssertThrowsError(try plan.retainingUnownedRows([]))
        let unrelated = try C36FieldDraftTestSupportV1.makeFixture().activeCheckpoint
        let row = V16BackupFieldDraftRecordV1(kind: .checkpoint, id: unrelated.draftID,
            workspaceID: unrelated.workspaceID.rawValue, revision: unrelated.draftRevision,
            canonicalData: try FieldDraftCanonicalCodecV1.encode(unrelated))
        XCTAssertEqual(try plan.retainingUnownedRows(package.records.fieldDrafts + [row]), [row])
        let first = try XCTUnwrap(package.records.fieldDrafts.first)
        let changed = V16BackupFieldDraftRecordV1(kind: first.kind, id: first.id,
            workspaceID: first.workspaceID, revision: first.revision + 1, canonicalData: first.canonicalData)
        XCTAssertThrowsError(try plan.retainingUnownedRows([changed]))

        // Exercise the real normalization boundary before a writer or recovery
        // can mask an unnecessary rewrite of an authenticated original.
        let harness = try RestoreReviewHarness()
        defer { harness.remove() }
        let service = try BackupRestoreService(applicationSupportURL: harness.support)
        let normalized = try service.c55RecordsForMaterializationForTesting(
            package.records, members: package.validatedPackage.members,
            identityDecision: identity, legacyWorkspaceID: identity.oldPointer.workspaceID,
            partsStockOperationID: plan.restoreID)
        let originalHistory = try XCTUnwrap(package.records.mutationHistory)
        let normalizedHistory = try XCTUnwrap(normalized.mutationHistory)
        XCTAssertEqual(normalizedHistory.receipts, originalHistory.receipts)
        XCTAssertEqual(normalizedHistory.quarantines, originalHistory.quarantines)
        try MutationJournalStoreV1.validateImportedSnapshot(normalizedHistory)
        let sourceCheckpoint = try XCTUnwrap(package.records.fieldDrafts.first { $0.kind == .checkpoint })
        let sourceIdentity = try WorkspaceEntityIdentityV1(kind: .fieldDraftCheckpoint, id: sourceCheckpoint.id)
        let sourceTerminal = try XCTUnwrap(originalHistory.entityRevisions.first { $0.identity == sourceIdentity })
        let targetID = try XCTUnwrap(identity.destinationFieldDraftID(for: sourceCheckpoint.id, namespace: "draft"))
        let targetIdentity = try WorkspaceEntityIdentityV1(kind: .fieldDraftCheckpoint, id: targetID)
        let targetTerminal = try XCTUnwrap(normalizedHistory.entityRevisions.first { $0.identity == targetIdentity })
        let before = try harness.factory.openOrBootstrapCurrent()
        let beforeHistory = try harness.history(in: before)
        let beforePointer = try harness.factory.currentGenerationPointerV3(expectedGenerationID: before.generationID)

        // Each hostile input reaches the real records-for-materialization
        // entry. An equal-value target collision is still a collision; it
        // must never be silently merged into the original history.
        for failure in ["missing-source", "wrong-revision", "wrong-digest", "target-collision"] {
            var terminals = originalHistory.entityRevisions.filter { $0.identity != sourceIdentity }
            switch failure {
            case "missing-source": break
            case "wrong-revision":
                terminals.append(.init(identity: sourceIdentity, revision: sourceTerminal.revision + 1,
                    externalProjectionSHA256: sourceTerminal.externalProjectionSHA256))
            case "wrong-digest":
                terminals.append(.init(identity: sourceIdentity, revision: sourceTerminal.revision,
                    externalProjectionSHA256: String(repeating: "e", count: 64)))
            default:
                terminals.append(sourceTerminal)
                terminals.append(targetTerminal)
            }
            let hostileHistory = MutationHistorySnapshotV1(
                workspaceRevision: originalHistory.workspaceRevision,
                lastLocalSequence: originalHistory.lastLocalSequence,
                receipts: originalHistory.receipts, quarantines: originalHistory.quarantines,
                entityRevisions: terminals.sorted { $0.identity.stableKey < $1.identity.stableKey })
            var object = try XCTUnwrap(JSONSerialization.jsonObject(
                with: JSONEncoder().encode(package.records)) as? [String: Any])
            object["mutationHistory"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(hostileHistory))
            let hostileRecords = try JSONDecoder().decode(V4BackupRecordsV1.self,
                from: JSONSerialization.data(withJSONObject: object))
            XCTAssertThrowsError(try service.c55RecordsForMaterializationForTesting(
                hostileRecords, members: package.validatedPackage.members,
                identityDecision: identity, legacyWorkspaceID: identity.oldPointer.workspaceID,
                partsStockOperationID: plan.restoreID), failure)
            XCTAssertEqual(try harness.factory.currentGenerationPointerV3(
                expectedGenerationID: before.generationID), beforePointer, failure)
            XCTAssertEqual(try harness.history(in: before), beforeHistory, failure)
            let authority = try harness.factory.makeRestoreGenerationAuthority()
            XCTAssertEqual(try authority.restoreGenerationNames(), [], failure)
            XCTAssertFalse(before.modelContext.hasChanges, failure)
        }
    }

    private func assertProjectedRoundRows(_ originals: [RoundSessionV1],
                                         in session: StoreGenerationSession,
                                         history: MutationHistorySnapshotV1,
                                         file: StaticString = #filePath, line: UInt = #line) throws {
        let rows = try session.modelContext.fetch(FetchDescriptor<RoundSessionRevisionRowV1>()).map {
            try $0.value()
        }
        XCTAssertEqual(rows.count, originals.count, file: file, line: line)
        let values = try ReplacementHistoryCommandEmissionV1.decoded(history).filter {
            $0.envelope.workspaceID == session.workspaceIdentity.workspaceID
                && $0.envelope.command.kind == .applyRoundSession
        }
        XCTAssertEqual(values.count, rows.count, file: file, line: line)
        for original in originals {
            let row = try XCTUnwrap(rows.first {
                $0.sessionID == original.sessionID && $0.revision == original.revision
            }, file: file, line: line)
            XCTAssertEqual(row.workspaceID, session.workspaceIdentity.workspaceID, file: file, line: line)
            XCTAssertNotEqual(row.mutationID, original.mutationID, file: file, line: line)
            XCTAssertEqual(row.state, original.state, file: file, line: line)
            XCTAssertEqual(row.recordedAt, original.recordedAt, file: file, line: line)
            XCTAssertEqual(row.items.map(\.selection), original.items.map(\.selection), file: file, line: line)
            let value = try XCTUnwrap(values.first { $0.envelope.mutationID == row.mutationID },
                                      file: file, line: line)
            guard case let .applyRoundSession(mutation) = value.envelope.command else {
                return XCTFail("Expected the destination Round command", file: file, line: line)
            }
            XCTAssertEqual(mutation.session, row, file: file, line: line)
            _ = try RoundSessionMutationReceiptV1(mutation: mutation, mutationReceipt: value.receipt)
        }
    }

    private func assertOriginals(_ before: MutationHistorySnapshotV1,
                                retainedIn after: MutationHistorySnapshotV1,
                                file: StaticString = #filePath, line: UInt = #line) throws {
        let afterByKey = try Dictionary(uniqueKeysWithValues: after.receipts.map { original in
            let envelope = try MutationEnvelopeV1.decodeCanonical(from: original.envelopeData)
            return (MutationWorkspaceKeyV1.value(workspaceID: envelope.workspaceID,
                mutationID: envelope.mutationID), original)
        })
        for original in before.receipts {
            let envelope = try MutationEnvelopeV1.decodeCanonical(from: original.envelopeData)
            XCTAssertEqual(afterByKey[MutationWorkspaceKeyV1.value(workspaceID: envelope.workspaceID,
                mutationID: envelope.mutationID)], original, file: file, line: line)
        }
    }
}

/// Test-only, fixed-label progress for one reviewed interrupted journey.
/// Disabled unless the existing diagnostic test explicitly opts in. It has
/// no timeout, assertion, persistence or production behavior of its own.
@MainActor
final class RestoreReviewTimingV1 {
    private let enabled: Bool
    private let startedAt: UInt64

    init(enabled: Bool = false) {
        self.enabled = enabled
        startedAt = DispatchTime.now().uptimeNanoseconds
    }

    var isEnabled: Bool { enabled }

    func mark(_ phase: String) {
        guard enabled else { return }
        let elapsedMilliseconds = (DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000
        let line = "RestoreReviewTimingV1 phase=\(phase) elapsedMs=\(elapsedMilliseconds)\n"
        FileHandle.standardError.write(Data(line.utf8))
    }
}

@MainActor
final class RestoreReviewHarness {
    let root: URL
    let support: URL
    let factory: StoreGenerationFactory
    private let timing: RestoreReviewTimingV1?

    init(timing: RestoreReviewTimingV1? = nil) throws {
        self.timing = timing
        timing?.mark("harness.begin")
        root = FileManager.default.temporaryDirectory.appendingPathComponent("c36-real-restore-\(UUID())")
        support = root.appendingPathComponent("Application Support", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        var bootstrapFactory = StoreGenerationFactory(applicationSupportURL: support)
#if DEBUG
        bootstrapFactory.coldOpenDiagnosticForTesting = timing?.isEnabled == true
#endif
        timing?.mark("harness.bootstrap.begin")
        do {
            _ = try bootstrapFactory.openOrBootstrapCurrent()
        } catch {
            timing?.mark("harness.bootstrap.failure.type=\(String(reflecting: type(of: error)))")
            throw error
        }
#if DEBUG
        bootstrapFactory.coldOpenDiagnosticForTesting = false
#endif
        factory = bootstrapFactory
        timing?.mark("harness.end")
    }

    func remove() { try? FileManager.default.removeItem(at: root) }

    func populate() throws -> StoreGenerationSession {
        let session = try factory.openOrBootstrapCurrent()
        let coordinator = try StoreSessionCoordinator(validatingSession: session)
        defer { try? coordinator.invalidateAndReleaseWriter() }
        let pack = SignPack.illuminatedSignV1
        let siteID = UUID(), mutationID = try MutationIDV1(rawValue: UUID())
        _ = try coordinator.workspaceWriter.execute(.createFirstSign(.init(
            siteID: siteID,
            newSite: .init(id: siteID, label: "Retained incumbent", address: nil, timeZoneID: "America/New_York"),
            assetID: UUID(), assetLabel: "Retained sign", packID: pack.packID,
            packSchemaVersion: pack.schemaVersion, packContentVersion: pack.contentVersion,
            createdAt: RepetitiveCaptureSourcePackageFixture.date,
            initialPlacementMutationID: mutationID, initialPlacementEventID: UUID(),
            initialPhysicalEpisodeID: PhysicalPlacementEpisodeIDV1(rawValue: UUID()))), mutationID: mutationID)
        return session
    }

    func restore(_ package: URL, mode: BackupRestoreMode,
                 failure: BackupRestoreFailureInjection? = nil) async throws -> StoreGenerationSession {
        var phase = "open-current"
        var firstRecoveryOrigin: String?
        do {
            timing?.mark(phase)
            let current = try factory.openOrBootstrapCurrent()
            let incumbentPointer = try factory.currentGenerationPointerV3(
                expectedGenerationID: current.generationID)
            XCTAssertEqual(incumbentPointer.storeSchemaVersion,
                PersistentSchemaReleaseRegistryV1.activeVersionIdentifier.major)
            phase = "import-package"
            timing?.mark(phase)
            let imported = try BackupImportService(generationRootURL: current.generationRootURL,
                scopedAccess: .alreadyAuthorized).stageAndValidate(selectedPackageURL: package)
            if imported.records.recordsSchemaVersion == LightingNightWorkflowBackupEnrollmentV1.recordsSchemaVersion {
                // The real current-format export remains admissible; future
                // envelopes must still fail this same production boundary.
                XCTAssertNoThrow(try C08ImportBulkBackupImportBoundaryV1.validate(imported.records))
                let encoded = try JSONEncoder().encode(imported.records)
                var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
                object["recordsSchemaVersion"] = LightingNightWorkflowBackupEnrollmentV1.recordsSchemaVersion + 1
                let future = try JSONDecoder().decode(V4BackupRecordsV1.self,
                    from: JSONSerialization.data(withJSONObject: object))
                XCTAssertThrowsError(try C08ImportBulkBackupImportBoundaryV1.validate(future)) { error in
                    XCTAssertEqual(error as? BackupCanonicalDecodingErrorV1, .invalidRecords)
                }
            }
            phase = "create-restore-service"
            timing?.mark(phase)
            let service = try BackupRestoreService(applicationSupportURL: support,
                now: { RepetitiveCaptureSourcePackageFixture.date.addingTimeInterval(3_600) },
                failureInjection: failure)
#if DEBUG
            service.restorePhaseDiagnosticForTesting = { [timing] value in
                if value == "restore-error.recovery.begin", firstRecoveryOrigin == nil {
                    firstRecoveryOrigin = phase
                }
                phase = value
                timing?.mark("restore." + value)
            }
#endif
            phase = "invoke-restore"
            timing?.mark(phase)
            let restored = try await service.restore(validatedPackage: imported,
                currentModelContext: current.modelContext, currentGenerationID: current.generationID,
                currentGenerationRootURL: current.generationRootURL, mode: mode)
            timing?.mark("restore.returned")
            let publishedPointer = try factory.currentGenerationPointerV3(
                expectedGenerationID: restored.generationID)
            XCTAssertEqual(publishedPointer.storeSchemaVersion, incumbentPointer.storeSchemaVersion)
            XCTAssertEqual(try publishedPointer.identity(), restored.workspaceIdentity)
            try assertCurrentAuxiliaryReadback(in: restored)
            return restored
        } catch {
            let originalError = error
            let failureType = String(reflecting: type(of: originalError))
            let failureDomain = (originalError as NSError).domain
            let failureCode = (originalError as NSError).code
            let failureRecord = "RestoreReviewHarness.caught phase=\(phase) type=\(failureType) domain=\(failureDomain) code=\(failureCode)"
            XCTContext.runActivity(named: "Retained original failure before cleanup") { activity in
                let attachment = XCTAttachment(string: failureRecord)
                attachment.lifetime = .keepAlways
                activity.add(attachment)
            }
            // Immutable scalar evidence is retained before XCTest serializes Error.
            print(failureRecord)
            if let firstRecoveryOrigin {
                print("RestoreReviewHarness.firstRecoveryOrigin=\(firstRecoveryOrigin)")
            }
            if let generationFailure = error as? StoreGenerationFailure {
                switch generationFailure {
                case .dataPointerInvalid: print("RestoreReviewHarness.generationFailure.dataPointerInvalid")
                case .dataGenerationMissing: print("RestoreReviewHarness.generationFailure.dataGenerationMissing")
                }
            }
            throw originalError
        }
    }

    func history(in session: StoreGenerationSession) throws -> MutationHistorySnapshotV1 {
        try MutationJournalStoreV1(modelContext: session.modelContext,
            identity: session.workspaceIdentity, generationID: session.generationID,
            allowStateBootstrap: false).exportSnapshot()
    }

    func assertCurrentAuxiliaryReadback(in session: StoreGenerationSession) throws {
        let service = try BackupRestoreService(applicationSupportURL: support)
        let records = try service.c55CurrentRecordsForTesting(in: session.modelContext)
        XCTAssertEqual(records.recordsSchemaVersion, LightingNightWorkflowBackupEnrollmentV1.recordsSchemaVersion)
        XCTAssertNotNil(records.evidenceQuality)
        XCTAssertNotNil(records.fastSurveyInbox)
        XCTAssertNotNil(records.reinspectionExceptionQueue)
        let identity = try XCTUnwrap(records.entityIdentityResolution)
        XCTAssertEqual(identity.workspaceID, session.workspaceIdentity.workspaceID)
        if identity.mutationReceipts.isEmpty {
            XCTAssertEqual(identity.generationID, session.generationID)
        }
        try service.c36ValidateRowsForTesting(session.modelContext, expected: records)
    }

    /// Exercise the production reader and validator, including hostile physical
    /// rows. Archive-format metadata never supplies a stored payload.
    func assertAuxiliaryReadbackContracts() throws {
        timing?.mark("auxiliary.begin")
        let schema = Schema(PersistentSchemaV53.models, version: PersistentSchemaV53.versionIdentifier)
        let container = try ModelContainer(for: schema, migrationPlan: nil, configurations: [
            ModelConfiguration("RestoreAuxiliaryReadback", schema: schema, isStoredInMemoryOnly: true,
                               allowsSave: true, cloudKitDatabase: .none)
        ])
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let workspaceID = WorkspaceID(rawValue: UUID())
        let generationID = UUID()
        let state = WorkspaceMutationStateRow(workspaceID: workspaceID.rawValue,
            generationID: generationID, activeReplicaID: UUID())
        context.insert(state)
        try context.save()
        let service = try BackupRestoreService(applicationSupportURL: support)
        let current = try service.c55CurrentRecordsForTesting(in: context)
        XCTAssertEqual(current.recordsSchemaVersion, 52)
        XCTAssertEqual(current.entityIdentityResolution?.generationID, generationID)
        XCTAssertNotNil(current.evidenceQuality)
        XCTAssertNotNil(current.fastSurveyInbox)
        XCTAssertNotNil(current.reinspectionExceptionQueue)
        let history = try XCTUnwrap(current.mutationHistory)
        XCTAssertEqual(service.c36ReplacingMutationHistoryForTesting(in: current, with: history), current)

        let data = try JSONEncoder().encode(current)
        var legacyObject = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacyObject["recordsSchemaVersion"] = C05RoundSessionBackupEnrollmentV1.recordsSchemaVersion
        for key in ["evidenceQuality", "fastSurveyInbox", "reinspectionExceptionQueue", "entityIdentityResolution"] {
            legacyObject.removeValue(forKey: key)
        }
        let legacy = try JSONDecoder().decode(V4BackupRecordsV1.self,
            from: JSONSerialization.data(withJSONObject: legacyObject))
        XCTAssertNoThrow(try service.c36ValidateRowsForTesting(context, expected: legacy))

        var wrongGeneration = current
        wrongGeneration.entityIdentityResolution = try EntityIdentityResolutionBackupSnapshotV1(
            workspaceID: workspaceID, generationID: UUID(), aliasLinks: [],
            consolidationReceipts: [], mutationReceipts: [])
        XCTAssertThrowsError(try service.c36ValidateRowsForTesting(context, expected: wrongGeneration))

        let budget = try ImportStreamingBudgetV1(maximumSourceBytes: 1_024, maximumRows: 1,
            maximumColumns: 2, maximumCellBytes: 128, maximumScalarsPerCell: 128)
        let release = try ImportSchemaReleaseV1(releaseID: "restore_readback_schema", release: 1,
            entityKind: .asset, externalKeyColumn: "asset_key", columns: [
                try .init(key: "asset_key", scalar: .identifier, required: true,
                    editableOnExactUpdate: false, maximumCellBytes: 128, maximumScalars: 128)
            ], budget: budget)
        let profile = try ImportMappingProfileV1(profileID: UUID(), workspaceID: workspaceID,
            profileName: "Restore readback", schemaRelease: release,
            mappings: [try .init(sourceColumn: "external_key", targetColumn: "asset_key")])
        let row = try ImportMappingProfileRowV1(profile)
        context.insert(row)
        try context.save()
        XCTAssertEqual(try service.c55CurrentRecordsForTesting(in: context).importMappingProfiles, [profile])
        XCTAssertThrowsError(try service.c36ValidateRowsForTesting(context, expected: legacy))
        XCTAssertThrowsError(try service.c36ValidateRowsForTesting(context, expected: current))
        context.delete(row)
        try context.save()
        XCTAssertEqual(try service.c55CurrentRecordsForTesting(in: context), current)

        let foreignProfile = try ImportMappingProfileV1(profileID: UUID(),
            workspaceID: WorkspaceID(rawValue: UUID()), profileName: "Foreign readback",
            schemaRelease: release, mappings: profile.mappings)
        let foreign = try ImportMappingProfileRowV1(foreignProfile)
        context.insert(foreign)
        try context.save()
        XCTAssertThrowsError(try service.c55CurrentRecordsForTesting(in: context))
        context.delete(foreign)
        try context.save()

        state.generationID = UUID()
        try context.save()
        let rebound = try service.c55CurrentRecordsForTesting(in: context)
        XCTAssertEqual(rebound.entityIdentityResolution?.generationID, state.generationID)
        XCTAssertNotEqual(rebound.entityIdentityResolution, current.entityIdentityResolution)
        XCTAssertThrowsError(try service.c36ValidateRowsForTesting(context, expected: current))
        XCTAssertNoThrow(try service.c36ValidateRowsForTesting(context, expected: legacy))
        // A post-review history copy must retain the newly normalized target
        // generation instead of restoring an original archive's empty identity.
        XCTAssertEqual(service.c36ReplacingMutationHistoryForTesting(in: rebound,
            with: try XCTUnwrap(rebound.mutationHistory)), rebound)

        context.delete(state)
        context.insert(try ImportMappingProfileRowV1(profile))
        try context.save()
        XCTAssertThrowsError(try service.c55CurrentRecordsForTesting(in: context))
        timing?.mark("auxiliary.hostile-owner.end")
        try assertPopulatedAuxiliaryCopyAndDuplicateRejection(service: service)
        timing?.mark("auxiliary.end")
    }

    private func assertPopulatedAuxiliaryCopyAndDuplicateRejection(service: BackupRestoreService) throws {
        timing?.mark("auxiliary.c10.init.begin")
        let fixture = try C10ProductionFixture(useActiveSchema: true)
        timing?.mark("auxiliary.c10.init.end")
        let populated = try service.c55CurrentRecordsForTesting(in: fixture.context)
        timing?.mark("auxiliary.c10.readback.end")
        let quality = try C10ProductionFixture.physicalBackupSnapshot(
            in: fixture.context, workspaceID: fixture.workspaceID)
        XCTAssertFalse(quality.ruleSets.isEmpty)
        XCTAssertFalse(quality.receipts.isEmpty)
        XCTAssertEqual(populated.evidenceQuality, quality)
        let history = try XCTUnwrap(populated.mutationHistory)
        XCTAssertEqual(service.c36ReplacingMutationHistoryForTesting(in: populated, with: history), populated)
        var omitted = populated
        omitted.evidenceQuality = nil
        XCTAssertThrowsError(try service.c36ValidateRowsForTesting(fixture.context, expected: omitted))

        // A typed copy-only probe covers nonnil optional practice provenance;
        // this does not claim that the physical REAL fixture is a practice store.
        let template = try StarterWorkspaceTemplateReleaseV1(templateID: UUID(), release: 1,
            titleKey: "workspace.starter.practice.title", packageReleaseIDs: ["shipping.illuminated-sign.v1"],
            practiceWatermark: "PRACTICE — NOT FOR FIELD USE")
        let plan = try StarterWorkspaceInstallPlanV1(planID: UUID(), workspaceID: fixture.workspaceID,
            template: template, mutationID: MutationIDV1(rawValue: UUID()), requestedAt: fixture.date,
            explicitUserRequest: true, destinationWasEmpty: true)
        let receipt = try StarterWorkspaceInstallReceiptV1(receiptID: UUID(), plan: plan,
            resultingWorkspaceRevision: 1, installedAt: fixture.date.addingTimeInterval(1), disposition: .committed)
        var withPractice = populated
        withPractice.practiceWorkspaceProvenance = try PracticeWorkspaceBackupSnapshotV1(provenance:
            PracticeWorkspaceProvenanceV1(provenanceID: UUID(), plan: plan, receipt: receipt, revision: 1))
        XCTAssertEqual(service.c36ReplacingMutationHistoryForTesting(in: withPractice, with: history), withPractice)

        // Deliberately hostile persisted history: two individually valid rows
        // have distinct revision keys but the same logical ruleSetID. The real
        // reader must throw before constructing a unique-key Dictionary.
        timing?.mark("auxiliary.c10.copy.end")
        let original = fixture.ruleSet
        let predecessor = try EvidenceQualityRuleSetV1(ruleSetID: UUID(), workspaceID: fixture.workspaceID,
            policyVersion: original.policyVersion, orderedRules: original.orderedRules, revision: 1,
            mutationID: MutationIDV1(rawValue: UUID()), recordedAt: fixture.date)
        let duplicate = try EvidenceQualityRuleSetV1(ruleSetID: original.ruleSetID,
            workspaceID: fixture.workspaceID, policyVersion: original.policyVersion,
            orderedRules: original.orderedRules, predecessor: predecessor, revision: 2,
            mutationID: MutationIDV1(rawValue: UUID()), recordedAt: fixture.date.addingTimeInterval(1))
        let revision = try fixture.writer.currentRevision()
        let expected = try WorkspaceExpectedRevisionV1(workspaceID: revision.workspaceID,
            generationID: revision.generationID, writerInstanceID: revision.writerInstanceID,
            workspaceRevision: revision.revision, entityRevisions: revision.entityRevisions)
        let command = try EvidenceQualityMutationCommandV1(commandID: UUID(), workspaceID: fixture.workspaceID,
            expectedRevision: expected, mutationID: duplicate.mutationID, payload: .putRuleSet(duplicate),
            submittedAt: fixture.date.addingTimeInterval(1))
        let row = try EvidenceQualityRuleSetRowV1(duplicate, command: command,
            resultingWorkspaceRevision: revision.revision + 1)
        XCTAssertEqual(try row.value(), duplicate)
        let originalRow = try XCTUnwrap(fixture.context.fetch(FetchDescriptor<EvidenceQualityRuleSetRowV1>()).first)
        XCTAssertEqual(try originalRow.value(), original)
        XCTAssertNotEqual(row.rowID, originalRow.rowID)
        timing?.mark("auxiliary.c10.duplicate.insert")
        fixture.context.insert(row)
        try fixture.context.save()
        timing?.mark("auxiliary.c10.duplicate.readback")
        XCTAssertThrowsError(try service.c55CurrentRecordsForTesting(in: fixture.context)) { error in
            XCTAssertEqual(error as? BackupRestoreServiceError, .invalidRestoreAuthority)
        }
    }

    func onlyReview(in session: StoreGenerationSession) throws -> FieldDraftCheckpointV1 {
        let release = try RepetitiveCaptureDestinationReviewCodecV1.release()
        let rows = try session.modelContext.fetch(FetchDescriptor<FieldDraftCheckpointRow>()).map { try $0.value() }
        let reviews = rows.filter { $0.codec == release }
        XCTAssertEqual(reviews.count, 1)
        return try XCTUnwrap(reviews.first)
    }

    func export(_ session: StoreGenerationSession) throws -> URL {
        let destination = root.appendingPathComponent("export-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let service = BackupExportService(modelContext: session.modelContext,
            generationRootURL: session.generationRootURL)
        let preview = try service.prepare()
        return try service.export(previewID: preview.id, to: destination)
    }
}

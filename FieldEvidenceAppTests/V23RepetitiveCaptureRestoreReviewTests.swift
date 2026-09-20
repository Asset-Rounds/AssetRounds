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
        XCTAssertEqual(try harness.history(in: cold), history)
        try assertProjectedRoundRows(source.rounds, in: cold, history: history)
    }

    func testSameWorkspaceReplacementPreservesCheckpointAndOriginalReceiptBytes() async throws {
        let source = try RepetitiveCaptureSourcePackageFixture(sourceOnly: true)
        defer { source.removePackages() }
        let harness = try RestoreReviewHarness(timing: RestoreReviewTimingV1(enabled: true))
        defer { harness.remove() }
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
        let reviewRelease = try RepetitiveCaptureDestinationReviewCodecV1.release()
        XCTAssertTrue(rows.allSatisfy { $0.codec != reviewRelease })
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
            XCTAssertEqual(try harness.factory.currentGenerationID(), originalID)
            let reopened = try harness.factory.openOrBootstrapCurrent()
            XCTAssertEqual(try harness.history(in: reopened), before)
            XCTAssertEqual(try reopened.modelContext.fetchCount(FetchDescriptor<FieldDraftCheckpointRow>()), 0)
            XCTAssertEqual(try reopened.modelContext.fetchCount(FetchDescriptor<Asset>()), 1)
            XCTAssertTrue(FileManager.default.fileExists(atPath: sourcePackage.path))
            XCTAssertEqual(try RestoreIntentStore(applicationSupportURL: harness.support).load() != nil,
                           point == .afterPreparedWrite)
        }
        let recovery = try BackupRestoreService(applicationSupportURL: harness.support)
        let recovered = try await recovery.reconcileRestoreAndPrivateSystemDiscoveryAtStartup()
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
            }
            try assertOriginals(source.history, retainedIn: harness.history(in: restored))
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
        factory = StoreGenerationFactory(applicationSupportURL: support)
        _ = try factory.openOrBootstrapCurrent()
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
            return restored
        } catch {
            // Fixed phase and error type only: no paths, identifiers or error payload.
            print("RestoreReviewHarness.failure phase=\(phase) type=\(String(reflecting: type(of: error)))")
            if let generationFailure = error as? StoreGenerationFailure {
                switch generationFailure {
                case .dataPointerInvalid: print("RestoreReviewHarness.generationFailure.dataPointerInvalid")
                case .dataGenerationMissing: print("RestoreReviewHarness.generationFailure.dataGenerationMissing")
                }
            }
            throw error
        }
    }

    func history(in session: StoreGenerationSession) throws -> MutationHistorySnapshotV1 {
        try MutationJournalStoreV1(modelContext: session.modelContext,
            identity: session.workspaceIdentity, generationID: session.generationID,
            allowStateBootstrap: false).exportSnapshot()
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

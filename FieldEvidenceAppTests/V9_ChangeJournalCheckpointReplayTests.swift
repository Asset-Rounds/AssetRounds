import CryptoKit
import Foundation
import XCTest
@testable import FieldEvidenceApp

@MainActor
final class V9_ChangeJournalCheckpointReplayTests: XCTestCase {
    func testV23P03C40CanonicalReplayRetainsPredecessorConcurrencyIdentity() throws {
        let workspaceID = WorkspaceID(rawValue: UUID(uuidString: "00000000-0000-4000-8000-000000004001")!)
        let mutationID = try MutationIDV1(rawValue: UUID(uuidString: "00000000-0000-4000-8000-000000004002")!)
        let predecessorID = UUID(uuidString: "00000000-0000-4000-8000-000000004003")!
        let value = try AuthoritySourceReleaseV1(
            releaseID: UUID(uuidString: "00000000-0000-4000-8000-000000004004")!,
            workspaceID: workspaceID,
            sourceID: UUID(uuidString: "00000000-0000-4000-8000-000000004005")!,
            sourceType: .guidance, designation: "Replay guidance", editionOrRevision: "2",
            retrievedAt: Date(timeIntervalSince1970: 1_735_689_600),
            licenseStorageDisposition: .notStored, supersedesReleaseID: predecessorID,
            recordedAt: Date(timeIntervalSince1970: 1_735_689_600), revision: 2,
            mutationID: mutationID
        )
        let mutation = try AuthorityCriterionMutationV1(
            workspaceID: workspaceID, expectedRevision: 1, mutationID: mutationID,
            postImage: .supersedeAuthoritySource(value)
        )
        let replayed = try AuthorityCriterionMutationV1.decodeCanonical(from: mutation.canonicalData())
        XCTAssertEqual(replayed, mutation)
        XCTAssertEqual(
            try replayed.concurrencyIdentity,
            WorkspaceEntityIdentityV1(kind: .authoritySourceRelease, id: predecessorID)
        )
        XCTAssertEqual(try replayed.postImage.mutationPostImage.concurrencyIdentity, try replayed.concurrencyIdentity)
        XCTAssertEqual(try replayed.postImage.mutationPostImage.identity, try replayed.affectedIdentity)
    }

    func testV23P03C39JournalReplayRetainsExactLifecycleKinds() throws {
        let kinds = AssetLifecycleEventKindV1.allCases
        let bytes = try AssetSemanticCanonicalCodecV1.encode(kinds)
        XCTAssertEqual(
            try AssetSemanticCanonicalCodecV1.decode([AssetLifecycleEventKindV1].self, from: bytes),
            kinds
        )
        XCTAssertEqual(kinds.last, .classificationChangedRecorded)
    }

    func testV9_ChangeJournalCheckpointReplayG01CheckpointThenPostRIsSemanticallyExact() throws {
        let corpus = try loadCorpus()
        assertProductionSeamsCompile()
        XCTAssertEqual(corpus.schema, "V21P03C11ChangeJournalCheckpointReplayCorpusV1")
        XCTAssertEqual(corpus.schemaVersion, 1)
        XCTAssertTrue(corpus.checkpoint.complete)
        XCTAssertTrue(corpus.checkpoint.verified)
        XCTAssertEqual(corpus.checkpoint.revision, corpus.checkpoint.cursorSequence)
        XCTAssertEqual(corpus.postCheckpointChanges.map(\.sequence), Array(41...46))
        XCTAssertEqual(corpus.pages.flatMap(\.sequences), Array(41...46))
        XCTAssertEqual(corpus.pages.first?.afterSequence, corpus.checkpoint.cursorSequence)
        XCTAssertEqual(corpus.pages.last?.throughSequence, 46)
        XCTAssertEqual(corpus.pages.last?.isTerminal, true)

        let contracts = try makeProductionContracts(corpus)
        try contracts.frontier.validate(limits: contracts.limits)
        try contracts.manifest.validate(limits: contracts.limits)
        XCTAssertEqual(contracts.manifest.frontier, contracts.frontier)
        XCTAssertEqual(contracts.manifest.workspaceID, contracts.workspaceID)
        try contracts.cursor.validate(
            workspaceID: contracts.workspaceID,
            consumerReplicaID: contracts.destinationReplicaID,
            checkpointID: corpus.checkpoint.checkpointID,
            frontierSHA256: try contracts.frontier.canonicalSHA256()
        )
        let emptyBoundaryBatch = try ChangeBatchV1(
            workspaceID: contracts.workspaceID,
            sourceReplicaID: contracts.sourceReplicaID,
            checkpointID: corpus.checkpoint.checkpointID,
            beforeCursor: contracts.cursor,
            changes: [],
            limits: contracts.limits
        )
        XCTAssertEqual(emptyBoundaryBatch.beforeCursor, emptyBoundaryBatch.afterCursor)
        XCTAssertEqual(emptyBoundaryBatch.afterCursor.nextOrdinal, 0)
        let preparation = try WorkspaceCheckpointPreparationV1(
            preparationID: corpus.checkpoint.generationID,
            manifest: contracts.manifest,
            entries: [
                try CheckpointArchiveEntryDigestV1(
                    relativePath: "content/manifest.json",
                    byteCount: 1,
                    sha256: corpus.checkpoint.contentManifestSHA256
                ),
                try CheckpointArchiveEntryDigestV1(
                    relativePath: "records/canonical.json",
                    byteCount: 1,
                    sha256: corpus.checkpoint.normalizedSnapshotSHA256
                ),
            ],
            limits: contracts.limits
        )
        let exported = try WorkspaceCheckpointExportV1(
            preparation: preparation,
            packageRelativePath: "checkpoints/revision-40.fecp",
            packageByteCount: 2,
            packageSHA256: corpus.checkpoint.packageReleaseSHA256,
            limits: contracts.limits
        )
        XCTAssertEqual(exported.checkpointID, contracts.manifest.checkpointID)
        try exported.validate()

        let golden = try XCTUnwrap(
            corpus.replaySchedules.first { $0.id == "golden-checkpoint-then-post-r" }
        )
        XCTAssertEqual(
            golden.deliveries,
            ["checkpoint", "page-41-43", "page-44-46"]
        )
        XCTAssertEqual(golden.expectedDisposition, "APPLIED_TO_46")
        XCTAssertNotEqual(
            golden.expectedSemanticSHA256,
            corpus.checkpoint.normalizedSnapshotSHA256
        )
        try assertSHA256(golden.expectedSemanticSHA256)
    }

    func testV9_ChangeJournalCheckpointReplayA01BoundedSchedulesContentResumeAndScale() throws {
        let corpus = try loadCorpus()
        XCTAssertEqual(corpus.bounds.maximumPageItems, 3)
        XCTAssertTrue(corpus.pages.allSatisfy {
            $0.sequences.count <= corpus.bounds.maximumPageItems
        })
        XCTAssertEqual(Set(corpus.replaySchedules.map(\.id)).count, corpus.replaySchedules.count)
        XCTAssertEqual(
            corpus.replaySchedules.first { $0.id == "duplicate-and-reordered" }?
                .expectedDisposition,
            "GAP_BUFFERED_THEN_APPLIED_DUPLICATES_IGNORED"
        )
        XCTAssertEqual(
            corpus.replaySchedules.first { $0.id == "bounded-gap-resume" }?
                .expectedDisposition,
            "DURABLE_GAP_RESUMED_TO_46"
        )
        XCTAssertEqual(
            corpus.replaySchedules.first { $0.id == "gap-overflow" }?
                .expectedDisposition,
            "REJECTED_GAP_BOUND_EXCEEDED_NO_EFFECT"
        )

        let missing = try XCTUnwrap(
            corpus.contentCases.first { $0.id == "content-missing-then-resumed" }
        )
        let corrupt = try XCTUnwrap(
            corpus.contentCases.first { $0.id == "content-corrupt-then-resumed" }
        )
        XCTAssertNil(missing.observedSHA256)
        XCTAssertEqual(missing.expectedDisposition, "DEFERRED_THEN_APPLIED")
        XCTAssertNotEqual(corrupt.observedSHA256, corrupt.resumeSHA256)
        XCTAssertEqual(
            corrupt.expectedDisposition,
            "QUARANTINED_THEN_APPLIED_FROM_VERIFIED_BYTES"
        )
        try assertSHA256(try XCTUnwrap(missing.resumeSHA256))
        try assertSHA256(try XCTUnwrap(corrupt.observedSHA256))

        let deferred = try MutationReplayDispositionV1(
            mutationID: MutationIDV1(rawValue: corpus.postCheckpointChanges[1].mutationID),
            disposition: .deferredContent,
            missingContentIDs: ["content_42"],
            reasonCode: "CONTENT_MISSING"
        )
        XCTAssertEqual(deferred.disposition, .deferredContent)
        XCTAssertThrowsError(
            try MutationReplayDispositionV1(
                mutationID: deferred.mutationID,
                disposition: .deferredContent
            )
        ) { error in
            XCTAssertEqual(error as? ChangeJournalFailureV1, .invalidValue)
        }

        XCTAssertEqual(corpus.scale.assetCount, 10_000)
        XCTAssertEqual(corpus.scale.assetCount, corpus.bounds.scaleAssetCount)
        XCTAssertEqual(corpus.scale.pageItemLimit, 128)
        XCTAssertEqual(corpus.scale.expectedPageCount, 79)
        XCTAssertEqual(
            (corpus.scale.assetCount + corpus.scale.pageItemLimit - 1)
                / corpus.scale.pageItemLimit,
            corpus.scale.expectedPageCount
        )
        XCTAssertLessThanOrEqual(
            corpus.scale.maximumResidentBytes,
            corpus.bounds.scaleMaximumResidentBytes
        )
        let normalizedMetadata = Data(
            (0..<corpus.scale.assetCount)
                .map { String(format: "asset:%05d|Asset-%05d\n", $0, $0) }
                .joined()
                .utf8
        )
        XCTAssertEqual(corpus.scale.generationRule, "INDEX_ASCENDING_UTF8_LINE")
        XCTAssertEqual(normalizedMetadata.count, 240_000)
        XCTAssertLessThan(normalizedMetadata.count, corpus.scale.maximumResidentBytes)
        XCTAssertEqual(sha256(normalizedMetadata), corpus.scale.expectedNormalizedMetadataSHA256)
        try assertSHA256(corpus.scale.expectedNormalizedMetadataSHA256)
    }

    func testV9_ChangeJournalCheckpointReplayH01HostileContentConflictsAndReleaseAbsence() throws {
        let corpus = try loadCorpus()
        let dispositions = Dictionary(
            uniqueKeysWithValues: corpus.conflictCases.map { ($0.id, $0.expectedDisposition) }
        )
        XCTAssertEqual(dispositions["old-backup-tombstone"], "TOMBSTONED_NO_RESURRECTION")
        XCTAssertEqual(dispositions["same-field-manual"], "UNRESOLVED_STABLE_CONFLICT_ID")
        XCTAssertEqual(dispositions["delete-versus-update"], "DELETE_WINS_NO_RESURRECTION")
        XCTAssertEqual(
            dispositions["resolution-before-competitors"],
            "CAUSALLY_DEFERRED_THEN_RESOLVED"
        )
        XCTAssertEqual(
            dispositions["late-third-competitor"],
            "EARLIER_BASIS_REMAINS_RESOLVED_SUCCESSOR_CONFLICT_CREATED"
        )
        XCTAssertTrue(
            corpus.conflictCases.filter { $0.policy == "DELETE_WINS" }
                .allSatisfy { $0.expectedDisposition.contains("NO_RESURRECTION") }
        )

        let contracts = try makeProductionContracts(corpus)
        var encodedCursor = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(contracts.cursor))
                as? [String: Any]
        )
        encodedCursor["unrecognizedReplayAuthority"] = true
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                ChangeCursorV1.self,
                from: JSONSerialization.data(withJSONObject: encodedCursor, options: [.sortedKeys])
            )
        )
        encodedCursor.removeValue(forKey: "unrecognizedReplayAuthority")
        encodedCursor["schemaVersion"] = 2
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                ChangeCursorV1.self,
                from: JSONSerialization.data(withJSONObject: encodedCursor, options: [.sortedKeys])
            )
        ) { error in
            XCTAssertEqual(error as? ChangeJournalFailureV1, .incompatibleVersion)
        }
        let otherWorkspace = WorkspaceID(
            rawValue: UUID(uuidString: "99999999-9999-4999-8999-999999999999")!
        )
        XCTAssertThrowsError(
            try contracts.cursor.validate(
                workspaceID: otherWorkspace,
                consumerReplicaID: contracts.destinationReplicaID,
                checkpointID: corpus.checkpoint.checkpointID,
                frontierSHA256: try contracts.frontier.canonicalSHA256()
            )
        ) { error in
            XCTAssertEqual(error as? ChangeJournalFailureV1, .wrongWorkspace)
        }
        XCTAssertThrowsError(
            try contracts.cursor.validate(
                workspaceID: contracts.workspaceID,
                consumerReplicaID: contracts.destinationReplicaID,
                checkpointID: corpus.checkpoint.checkpointID,
                frontierSHA256: corpus.checkpoint.normalizedSnapshotSHA256
            )
        ) { error in
            XCTAssertEqual(error as? ChangeJournalFailureV1, .staleCursor)
        }
        XCTAssertThrowsError(
            try CheckpointActivationReceiptV1(
                workspaceID: otherWorkspace,
                destinationReplicaID: contracts.destinationReplicaID,
                destinationGenerationID: corpus.checkpoint.generationID,
                manifest: contracts.manifest,
                activatedFrontier: contracts.frontier,
                semanticProjectionSHA256: corpus.checkpoint.normalizedSnapshotSHA256,
                contentDispositionSHA256: corpus.checkpoint.contentManifestSHA256,
                limits: contracts.limits
            )
        ) { error in
            XCTAssertEqual(error as? ChangeJournalFailureV1, .wrongWorkspace)
        }

        let productionRoot = sourceRoot().appendingPathComponent(
            "FieldEvidenceApp",
            isDirectory: true
        )
        let productionSwift = try swiftSources(under: productionRoot)
        let productionText = try productionSwift
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
        for symbol in corpus.releaseAbsence.forbiddenProductionSymbols {
            XCTAssertFalse(
                productionText.contains(symbol),
                "Test-only symbol leaked to production: \(symbol)"
            )
        }
        for signature in [
            "func sourceMutationHistorySnapshot() throws -> MutationHistorySnapshotV1",
            "func executeImported(_ change: JournalChangeV1) throws -> WorkspaceMutationOutcomeV1",
            "func canonicalCheckpointBasis() throws -> BackupCanonicalCheckpointBasisV1",
            "contentEntryResolver: @escaping LocalChangeJournalV1.ContentEntryResolver",
            "try ContentIntegrityV1.verify(",
        ] {
            XCTAssertTrue(
                productionText.contains(signature),
                "Required production seam missing: \(signature)"
            )
        }
        XCTAssertFalse(
            productionText.contains("contentVerifier:"),
            "Journal construction must require observed content entries, not injected verification"
        )
        for path in corpus.releaseAbsence.forbiddenProductionPaths {
            XCTAssertFalse(fileManager.fileExists(atPath: sourceRoot().appendingPathComponent(path).path))
        }
    }

    func testV9_ChangeJournalCheckpointReplayI01CrashMatrixIsRestartSafeAtEveryBoundary() throws {
        let corpus = try loadCorpus()
        XCTAssertEqual(Set(corpus.crashMatrix.map(\.boundary)).count, 9)
        XCTAssertEqual(
            Set(corpus.crashMatrix.map(\.boundary)),
            Set([
                "CHECKPOINT_PREPARED", "CHECKPOINT_COMMITTED",
                "PAGE_PREPARED", "PAGE_COMMITTED",
                "REPLAY_AFTER_EFFECT_BEFORE_CURSOR",
                "ACTIVATION_PRE_POINTER", "ACTIVATION_POST_POINTER",
                "COMPACTION_PRE_REPLACEMENT", "COMPACTION_POST_REPLACEMENT",
            ])
        )
        XCTAssertEqual(
            corpus.crashMatrix.first { $0.boundary == "REPLAY_AFTER_EFFECT_BEFORE_CURSOR" }?
                .expected,
            "EFFECT_REPROVED_CURSOR_ADVANCED_ONCE"
        )
        XCTAssertEqual(
            corpus.crashMatrix.first { $0.boundary == "ACTIVATION_PRE_POINTER" }?.expected,
            "SOURCE_REMAINS_ACTIVE"
        )
        XCTAssertEqual(
            corpus.crashMatrix.first { $0.boundary == "ACTIVATION_POST_POINTER" }?.expected,
            "DESTINATION_ACTIVE_ON_RELAUNCH"
        )
        XCTAssertEqual(
            corpus.crashMatrix.first { $0.boundary == "COMPACTION_POST_REPLACEMENT" }?
                .expected,
            "COMPACTED_JOURNAL_VERIFIED"
        )

        let contracts = try makeProductionContracts(corpus)
        let receipt = try ChangeReplayReceiptV1(
            workspaceID: contracts.workspaceID,
            destinationReplicaID: contracts.destinationReplicaID,
            destinationGenerationID: corpus.checkpoint.generationID,
            batchSHA256: try XCTUnwrap(corpus.pages.last?.pageSHA256),
            resultingFrontier: contracts.frontier,
            dispositions: [],
            semanticProjectionSHA256: try XCTUnwrap(
                corpus.replaySchedules.first?.expectedSemanticSHA256
            ),
            limits: contracts.limits
        )
        let restartedReceipt = try JSONDecoder().decode(
            ChangeReplayReceiptV1.self,
            from: JSONEncoder().encode(receipt)
        )
        XCTAssertEqual(restartedReceipt, receipt)
        try restartedReceipt.validate(limits: contracts.limits)

        let activation = try CheckpointActivationReceiptV1(
            workspaceID: contracts.workspaceID,
            destinationReplicaID: contracts.destinationReplicaID,
            destinationGenerationID: corpus.checkpoint.generationID,
            manifest: contracts.manifest,
            activatedFrontier: contracts.frontier,
            semanticProjectionSHA256: receipt.semanticProjectionSHA256,
            contentDispositionSHA256: corpus.checkpoint.contentManifestSHA256,
            limits: contracts.limits
        )
        let compaction = try ChangeJournalCompactionReceiptV1(
            workspaceID: contracts.workspaceID,
            sourceReplicaID: contracts.sourceReplicaID,
            manifest: contracts.manifest,
            compactedThrough: contracts.frontier,
            preservedReceiptSetSHA256: activation.receiptSHA256,
            preservedReversalBasisSetSHA256: corpus.checkpoint.packageReleaseSHA256,
            removedChangeCount: corpus.checkpoint.cursorSequence,
            limits: contracts.limits
        )
        XCTAssertFalse(compaction.canonicalHistoryDeleted)
        XCTAssertEqual(compaction.checkpointID, contracts.manifest.checkpointID)
        try compaction.validate(limits: contracts.limits)
    }

    func testV9_ChangeJournalCheckpointReplayR01ReplicaConvergenceReversalRollbackAndCompaction() throws {
        let corpus = try loadCorpus()
        let schedules = corpus.replicaSchedules.map {
            ReplicaDeliveryScheduleV1(
                id: $0.id,
                replicas: $0.replicas,
                deliveries: $0.deliveries,
                expectedQuiescenceRounds: $0.expectedQuiescenceRounds
            )
        }
        let scenario = ReplicaConvergenceScenarioV1(
            workspaceID: corpus.workspaceID,
            fixedSeed: corpus.fixedSeed,
            schedules: schedules
        )
        XCTAssertEqual(scenario.schedules.map(\.replicas.count), [2, 3])
        XCTAssertTrue(scenario.schedules.allSatisfy { !$0.deliveries.isEmpty })
        let receipts = zip(scenario.schedules, corpus.replicaSchedules).map { schedule, source in
            ReplicaConvergenceReceiptV1(
                scheduleID: schedule.id,
                semanticSHA256: source.expectedSemanticSHA256,
                quiescenceRounds: schedule.expectedQuiescenceRounds
            )
        }
        XCTAssertEqual(receipts.map(\.quiescenceRounds), [3, 5])
        try receipts.forEach { try assertSHA256($0.semanticSHA256) }

        let contracts = try makeProductionContracts(corpus)
        let productionReceipts = try zip(corpus.replicaSchedules, corpus.destinationReplicaIDs)
            .map { schedule, destinationID in
                try ChangeReplayReceiptV1(
                    workspaceID: contracts.workspaceID,
                    destinationReplicaID: ReplicaID(rawValue: destinationID),
                    destinationGenerationID: corpus.checkpoint.generationID,
                    batchSHA256: try XCTUnwrap(corpus.pages.last?.pageSHA256),
                    resultingFrontier: contracts.frontier,
                    dispositions: [],
                    semanticProjectionSHA256: schedule.expectedSemanticSHA256,
                    limits: contracts.limits
                )
            }
        XCTAssertEqual(productionReceipts.count, 2)
        XCTAssertEqual(
            productionReceipts.map(\.semanticProjectionSHA256),
            corpus.replicaSchedules.map(\.expectedSemanticSHA256)
        )
        let observedMutationIDs = try corpus.postCheckpointChanges
            .map { try MutationIDV1(rawValue: $0.mutationID) }
            .sorted { $0.rawValue.uuidString.lowercased() < $1.rawValue.uuidString.lowercased() }
        let projection = try SemanticConvergenceProjectionV1(
            workspaceID: contracts.workspaceID,
            canonicalSnapshotSHA256: corpus.replaySchedules[0].expectedSemanticSHA256,
            tombstoneIdentities: [],
            unresolvedConflictIdentities: [],
            contentDispositionSHA256: corpus.checkpoint.contentManifestSHA256,
            observedMutationIDs: observedMutationIDs,
            limits: contracts.limits
        )
        let duplicateRunProjection = try SemanticConvergenceProjectionV1(
            workspaceID: contracts.workspaceID,
            canonicalSnapshotSHA256: corpus.replaySchedules[0].expectedSemanticSHA256,
            tombstoneIdentities: [],
            unresolvedConflictIdentities: [],
            contentDispositionSHA256: corpus.checkpoint.contentManifestSHA256,
            observedMutationIDs: observedMutationIDs,
            limits: contracts.limits
        )
        XCTAssertEqual(projection, duplicateRunProjection)

        XCTAssertEqual(
            corpus.reversal.reversalMutationID,
            corpus.postCheckpointChanges.first { $0.kind == "SEMANTIC_REVERSAL" }?
                .mutationID
        )
        XCTAssertEqual(
            corpus.reversal.targetMutationID,
            corpus.postCheckpointChanges.first { $0.kind == "SEMANTIC_REVERSAL" }?
                .reversesMutationID
        )
        XCTAssertEqual(
            corpus.reversal.expectedCompactionDisposition,
            "BASIS_AND_BOTH_RECEIPT_IDENTITIES_RETAINED"
        )
        XCTAssertEqual(corpus.rollback.policy, "CONTENT_ROLLBACK_ONLY")
        XCTAssertTrue(corpus.rollback.incompleteDerivedCheckpointsDiscardable)
        XCTAssertTrue(corpus.rollback.acceptedReceiptsImmutable)
        XCTAssertFalse(corpus.rollback.releasedSchemaDowngradeAllowed)
        XCTAssertFalse(corpus.rollback.providerStateCreated)
    }

    private let fileManager = FileManager.default

    private struct ProductionContracts {
        let workspaceID: WorkspaceID
        let sourceReplicaID: ReplicaID
        let destinationReplicaID: ReplicaID
        let limits: ChangeJournalLimitsV1
        let frontier: ChangeJournalFrontierV1
        let manifest: WorkspaceSnapshotManifestV1
        let cursor: ChangeCursorV1
    }

    private func makeProductionContracts(
        _ corpus: ChangeJournalCorpusV1
    ) throws -> ProductionContracts {
        let workspaceID = WorkspaceID(rawValue: corpus.workspaceID)
        let sourceReplicaID = ReplicaID(rawValue: corpus.sourceReplicaID)
        let destinationReplicaID = ReplicaID(rawValue: corpus.destinationReplicaIDs[0])
        let limits = try ChangeJournalLimitsV1(
            maximumChangesPerBatch: corpus.bounds.scalePageItems,
            maximumBatchBytes: corpus.bounds.maximumPageBytes,
            maximumEntitiesPerCheckpoint: corpus.bounds.scaleAssetCount,
            maximumContentEntriesPerCheckpoint: corpus.bounds.scaleAssetCount,
            maximumReplicaFrontiers: corpus.destinationReplicaIDs.count + 1,
            maximumConflicts: 64
        )
        let replicas = try ([corpus.sourceReplicaID] + corpus.destinationReplicaIDs)
            .sorted { $0.uuidString.lowercased() < $1.uuidString.lowercased() }
            .map {
                try ReplicaRevisionFrontierV1(
                    replicaID: ReplicaID(rawValue: $0),
                    localSequence: $0 == corpus.sourceReplicaID
                        ? UInt64(corpus.checkpoint.cursorSequence)
                        : 0
                )
            }
        let frontier = try ChangeJournalFrontierV1(
            workspaceRevision: UInt64(corpus.checkpoint.revision),
            replicas: replicas,
            entityRevisionSHA256: corpus.checkpoint.normalizedSnapshotSHA256,
            observedMutationSetSHA256: corpus.checkpoint.packageReleaseSHA256,
            limits: limits
        )
        let package = try CheckpointPackageDigestV1(
            packageID: corpus.checkpoint.packageID,
            packageSchemaVersion: corpus.checkpoint.packageSchemaVersion,
            contentVersion: corpus.checkpoint.packageContentVersion,
            packageSHA256: corpus.checkpoint.packageReleaseSHA256
        )
        let manifest = try WorkspaceSnapshotManifestV1(
            workspaceID: workspaceID,
            sourceReplicaID: sourceReplicaID,
            sourceGenerationID: corpus.checkpoint.generationID,
            persistentSchemaVersion: 4,
            persistentSchemaSHA256: corpus.checkpoint.packageReleaseSHA256,
            recordSchemaVersion: 1,
            recordSchemaSHA256: corpus.checkpoint.normalizedSnapshotSHA256,
            packages: [package],
            frontier: frontier,
            normalizedRecordsSHA256: corpus.checkpoint.normalizedSnapshotSHA256,
            tombstonesSHA256: corpus.checkpoint.contentManifestSHA256,
            contentManifestSHA256: corpus.checkpoint.contentManifestSHA256,
            reversalEligibilitySHA256: corpus.checkpoint.packageReleaseSHA256,
            limits: limits
        )
        let cursor = try ChangeCursorV1(
            workspaceID: workspaceID,
            consumerReplicaID: destinationReplicaID,
            checkpointID: corpus.checkpoint.checkpointID,
            frontierSHA256: try frontier.canonicalSHA256(),
            nextOrdinal: 0,
            previousBatchSHA256: nil
        )
        return ProductionContracts(
            workspaceID: workspaceID,
            sourceReplicaID: sourceReplicaID,
            destinationReplicaID: destinationReplicaID,
            limits: limits,
            frontier: frontier,
            manifest: manifest,
            cursor: cursor
        )
    }

    private func loadCorpus() throws -> ChangeJournalCorpusV1 {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(
            bundle.url(
                forResource: "V21P03C11ChangeJournalCheckpointReplayCorpusV1",
                withExtension: "json",
                subdirectory: "Fixtures/V21/ChangeJournal"
            ) ?? bundle.url(
                forResource: "V21P03C11ChangeJournalCheckpointReplayCorpusV1",
                withExtension: "json"
            )
        )
        let decoder = JSONDecoder()
        return try decoder.decode(ChangeJournalCorpusV1.self, from: Data(contentsOf: url))
    }

    /// These closures are intentionally not executed: constructing a complete
    /// SwiftData/backup stack here would obscure the deterministic corpus. They
    /// still compile every production journal boundary used by this contract,
    /// so a label, argument, or result-type drift breaks this test target.
    private func assertProductionSeamsCompile() {
        let writerHistory = { (writer: WorkspaceWriterV1) throws -> MutationHistorySnapshotV1 in
            try writer.sourceMutationHistorySnapshot()
        }
        let writerImport = {
            (writer: WorkspaceWriterV1, change: JournalChangeV1) throws
                -> WorkspaceMutationOutcomeV1 in
            try writer.executeImported(change)
        }
        let backupBasis = {
            (backup: BackupExportService) throws -> BackupCanonicalCheckpointBasisV1 in
            try backup.canonicalCheckpointBasis()
        }
        let prepare = {
            (journal: LocalChangeJournalV1, supplement: LocalChangeJournalV1.CheckpointSupplementV1)
                throws -> WorkspaceCheckpointPreparationV1 in
            try journal.prepareCheckpoint(supplement: supplement)
        }
        let export = {
            (journal: LocalChangeJournalV1, preparation: WorkspaceCheckpointPreparationV1)
                throws -> (export: WorkspaceCheckpointExportV1, packageData: Data) in
            try journal.exportPreparedCheckpoint(
                preparation,
                packageRelativePath: "compile-contract/checkpoint.fecp"
            )
        }
        let activate = {
            (journal: LocalChangeJournalV1, preparation: WorkspaceCheckpointPreparationV1)
                throws -> CheckpointActivationReceiptV1 in
            try journal.activatePreparedCheckpoint(preparation)
        }
        let install = {
            (journal: LocalChangeJournalV1, export: WorkspaceCheckpointExportV1, data: Data)
                throws -> CheckpointActivationReceiptV1 in
            try journal.installImportedCheckpoint(export: export, packageData: data)
        }
        let preparations = {
            (journal: LocalChangeJournalV1) throws -> [WorkspaceCheckpointPreparationV1] in
            try journal.resumableCheckpointPreparations()
        }
        let rollback = { (journal: LocalChangeJournalV1, preparationID: UUID) throws in
            try journal.rollbackPreparedCheckpoint(preparationID)
        }
        let initialCursor = {
            (journal: LocalChangeJournalV1, replicaID: ReplicaID, checkpointID: String?)
                throws -> ChangeCursorV1 in
            try journal.initialCursor(
                consumerReplicaID: replicaID,
                checkpointID: checkpointID
            )
        }
        let page = {
            (journal: LocalChangeJournalV1, cursor: ChangeCursorV1) throws -> ChangeBatchV1 in
            try journal.page(after: cursor)
        }
        let replay = {
            (journal: LocalChangeJournalV1, batch: ChangeBatchV1)
                throws -> ChangeReplayReceiptV1 in
            try journal.replay(batch)
        }
        let replayResult = {
            (journal: LocalChangeJournalV1, batch: ChangeBatchV1)
                throws -> LocalChangeJournalV1.ReplayResultV1 in
            try journal.replayResult(batch)
        }
        let resume = {
            (journal: LocalChangeJournalV1) throws -> [LocalChangeJournalV1.ReplayResultV1] in
            try journal.resumeStagedBatches()
        }
        let resolve = {
            (journal: LocalChangeJournalV1, basis: ConflictResolutionBasisV1) throws in
            try journal.installConflictResolution(basis)
        }
        let compact = {
            (journal: LocalChangeJournalV1, checkpointID: String)
                throws -> ChangeJournalCompactionReceiptV1 in
            try journal.compact(through: checkpointID)
        }
        let projection = {
            (journal: LocalChangeJournalV1, conflicts: [ConflictIdentityV1]?)
                throws -> SemanticConvergenceProjectionV1 in
            try journal.semanticProjection(unresolvedConflicts: conflicts)
        }
        let recover = { (journal: LocalChangeJournalV1) throws in
            try journal.recoverInterruptedWork()
        }
        _ = [
            writerHistory as Any, writerImport as Any, backupBasis as Any,
            prepare as Any, export as Any, activate as Any, install as Any,
            preparations as Any, rollback as Any, initialCursor as Any,
            page as Any, replay as Any, replayResult as Any, resume as Any,
            resolve as Any, compact as Any, projection as Any, recover as Any,
        ]
    }

    private func assertSHA256(
        _ value: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(value.count, 64, file: file, line: line)
        XCTAssertTrue(
            value.utf8.allSatisfy {
                (48...57).contains($0) || (97...102).contains($0)
            },
            file: file,
            line: line
        )
    }

    func testV23P03C38JournalBoundaryCarriesMutationIDsAndFrozenSnapshotBytes() throws {
        let root = sourceRoot()
        let fixtureURL = root.appendingPathComponent(
            "FieldEvidenceAppTests/Fixtures/V21/Accountability/V21P03C38PartyAccountabilityCorpusV1.json"
        )
        let fixture = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as? [String: Any]
        )
        let persistence = try XCTUnwrap(fixture["persistence"] as? [String: Any])
        XCTAssertEqual(persistence["schemaRelease"] as? String, "PERSISTENT_SCHEMA_V9_PARTY_ACCOUNTABILITY")
        XCTAssertEqual(persistence["searchRebuild"] as? String, "ALLOWLISTED_PARTY_ROLE_SIGNOFF_DISPLAY_FIELDS_ONLY")
        XCTAssertEqual(persistence["deleteDisposition"] as? String, "EXPLICIT_ERASE_OR_TOMBSTONE_WITH_HISTORY_PRESERVED")
        XCTAssertEqual(persistence["exportDisposition"] as? String, "CANONICAL_DOMAIN_BYTES_AND_FROZEN_SNAPSHOTS")

        let adapterSource = try String(
            contentsOf: root.appendingPathComponent(
                "FieldEvidenceApp/Infrastructure/Persistence/WorkspaceWriterAdapterV1.swift"
            ),
            encoding: .utf8
        )
        let journalSource = try String(
            contentsOf: root.appendingPathComponent(
                "FieldEvidenceApp/Infrastructure/Persistence/MutationJournal/MutationJournalStoreV1.swift"
            ),
            encoding: .utf8
        )
        let rowsSource = try String(
            contentsOf: root.appendingPathComponent(
                "FieldEvidenceApp/Domain/Models/PartyAccountabilityPersistenceModelsV1.swift"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(adapterSource.contains("applyPartyAccountability"))
        XCTAssertTrue(adapterSource.contains("MutationIDV1"))
        XCTAssertTrue(journalSource.contains("ServicePartyRow"))
        XCTAssertTrue(journalSource.contains("SignoffSnapshotRow"))
        XCTAssertTrue(rowsSource.contains("canonicalData"))
        XCTAssertTrue(rowsSource.contains("snapshotSHA256"))
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func sourceRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func swiftSources(under root: URL) throws -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }
}

private struct ReplicaConvergenceScenarioV1: Equatable, Sendable {
    let workspaceID: UUID
    let fixedSeed: String
    let schedules: [ReplicaDeliveryScheduleV1]
}

private struct ReplicaDeliveryScheduleV1: Equatable, Sendable {
    let id: String
    let replicas: [String]
    let deliveries: [String]
    let expectedQuiescenceRounds: Int
}

private struct ReplicaConvergenceReceiptV1: Equatable, Sendable {
    let scheduleID: String
    let semanticSHA256: String
    let quiescenceRounds: Int
}

private struct ChangeJournalCorpusV1: Decodable {
    struct Bounds: Decodable {
        let maximumPageItems: Int
        let maximumPageBytes: Int
        let maximumGapPages: Int
        let maximumReplayAttempts: Int
        let scaleAssetCount: Int
        let scalePageItems: Int
        let scaleExpectedPageCount: Int
        let scaleMaximumResidentBytes: Int
    }
    struct Checkpoint: Decodable {
        let checkpointID: String
        let revision: Int
        let cursorSequence: Int
        let schemaRelease: String
        let packageID: String
        let packageSchemaVersion: Int
        let packageContentVersion: Int
        let generationID: UUID
        let packageReleaseSHA256: String
        let normalizedSnapshotSHA256: String
        let contentManifestSHA256: String
        let complete: Bool
        let verified: Bool
    }
    struct Change: Decodable {
        let sequence: Int
        let mutationID: UUID
        let kind: String
        let entity: String
        let canonicalInputSHA256: String
        let contentSHA256: String?
        let reversesMutationID: UUID?
    }
    struct Page: Decodable {
        let pageID: String
        let afterSequence: Int
        let throughSequence: Int
        let sequences: [Int]
        let isTerminal: Bool
        let pageSHA256: String
    }
    struct ReplaySchedule: Decodable {
        let id: String
        let deliveries: [String]
        let expectedDisposition: String
        let expectedSemanticSHA256: String
    }
    struct ContentCase: Decodable {
        let id: String
        let sequence: Int
        let observedSHA256: String?
        let resumeSHA256: String?
        let expectedDisposition: String
    }
    struct ConflictCase: Decodable {
        let id: String
        let competitors: [String]
        let policy: String
        let expectedDisposition: String
    }
    struct Reversal: Decodable {
        let targetMutationID: UUID
        let reversalMutationID: UUID
        let targetReceiptStableKey: String
        let reversalReceiptStableKey: String
        let expectedCompactionDisposition: String
    }
    struct Crash: Decodable {
        let boundary: String
        let expected: String
    }
    struct ReplicaSchedule: Decodable {
        let id: String
        let replicas: [String]
        let deliveries: [String]
        let expectedQuiescenceRounds: Int
        let expectedSemanticSHA256: String
    }
    struct Scale: Decodable {
        let assetCount: Int
        let seed: Int
        let generationRule: String
        let labelRule: String
        let pageItemLimit: Int
        let expectedPageCount: Int
        let expectedFinalRevision: Int
        let expectedNormalizedMetadataSHA256: String
        let maximumResidentBytes: Int
    }
    struct Rollback: Decodable {
        let policy: String
        let incompleteDerivedCheckpointsDiscardable: Bool
        let acceptedReceiptsImmutable: Bool
        let releasedSchemaDowngradeAllowed: Bool
        let providerStateCreated: Bool
    }
    struct ReleaseAbsence: Decodable {
        let forbiddenProductionSymbols: [String]
        let forbiddenProductionPaths: [String]
    }

    let schema: String
    let schemaVersion: Int
    let fixedSeed: String
    let workspaceID: UUID
    let sourceReplicaID: UUID
    let destinationReplicaIDs: [UUID]
    let bounds: Bounds
    let checkpoint: Checkpoint
    let postCheckpointChanges: [Change]
    let pages: [Page]
    let replaySchedules: [ReplaySchedule]
    let contentCases: [ContentCase]
    let conflictCases: [ConflictCase]
    let reversal: Reversal
    let crashMatrix: [Crash]
    let replicaSchedules: [ReplicaSchedule]
    let scale: Scale
    let rollback: Rollback
    let releaseAbsence: ReleaseAbsence
}

extension V9_ChangeJournalCheckpointReplayTests {
    func testV23P03C41CheckpointReplayProducesDeterministicProjections() throws {
        let fixture = try C41FunctionalRelationshipTestSupportV1.makeFixture(seed: 41_090)

        let ended = try FunctionalRelationshipProjectionBuilderV1.rebuild(
            workspaceID: fixture.workspaceID,
            events: [fixture.added, fixture.ended],
            descriptors: [fixture.descriptor]
        )
        let superseded = try FunctionalRelationshipProjectionBuilderV1.rebuild(
            workspaceID: fixture.workspaceID,
            events: [fixture.added, fixture.superseded],
            descriptors: [fixture.descriptor]
        )

        XCTAssertTrue(ended.currentRelationships.isEmpty)
        XCTAssertEqual(superseded.currentRelationships.count, 1)
        XCTAssertEqual(superseded.currentRelationships.first?.revision, 2)
        XCTAssertNotEqual(ended.sourceEventsSHA256, superseded.sourceEventsSHA256)
        XCTAssertEqual(superseded.currentRelationships.first?.predecessorEventID, fixture.added.eventID)
        try fixture.ended.validateSuccessor(of: fixture.added)
        try fixture.superseded.validateSuccessor(of: fixture.added)
    }
}

extension V9_ChangeJournalCheckpointReplayTests {
    func testV23P03C13JournalReplayPreservesManifestAttestationCanonicalHistory() throws {
        let fixture = try C13EvidenceAssuranceTestSupportV1.makeFixture(seed: 51_090)
        let manifestData = try EvidenceAssuranceCanonicalCodecV1.encode(fixture.customerManifest)
        let attestationData = try EvidenceAssuranceCanonicalCodecV1.encode(fixture.customerAttestation)
        let replayedManifest = try EvidenceAssuranceCanonicalCodecV1.decode(
            AssuranceManifestV1.self, from: manifestData
        )
        let replayedAttestation = try EvidenceAssuranceCanonicalCodecV1.decode(
            AttestationV1.self, from: attestationData
        )

        XCTAssertEqual(replayedManifest, fixture.customerManifest)
        XCTAssertEqual(replayedAttestation, fixture.customerAttestation)
        XCTAssertEqual(try EvidenceAssuranceCanonicalCodecV1.encode(replayedManifest), manifestData)
        XCTAssertEqual(try EvidenceAssuranceCanonicalCodecV1.encode(replayedAttestation), attestationData)
        XCTAssertEqual(replayedAttestation.manifestSHA256, replayedManifest.manifestSHA256)
        try replayedAttestation.validate(manifest: replayedManifest)
    }
}

extension V9_ChangeJournalCheckpointReplayTests {
    func testV23P03C14JournalReplayRoundTripsResolvedChangeRequestBytes() throws {
        let fixture = try C14InspectionReviewTestSupportV1.makeFixture(seed: 145_104)
        let bytes = try InspectionReviewCanonicalCodecV1.encode(fixture.resolvedChangeRequest)
        let replayed = try InspectionReviewCanonicalCodecV1.decode(
            ChangeRequestV1.self, from: bytes
        )
        XCTAssertEqual(replayed, fixture.resolvedChangeRequest)
        XCTAssertEqual(try InspectionReviewCanonicalCodecV1.encode(replayed), bytes)
        XCTAssertEqual(replayed.state, .resolved)
        XCTAssertEqual(replayed.supersedesRequestRevisionID, fixture.changeRequest.requestRevisionID)
    }
}

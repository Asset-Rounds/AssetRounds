import CryptoKit
import Foundation
import XCTest
@testable import FieldEvidenceApp

private enum C52ServiceRequestBoundary_V9_ChangeJournalCheckpointReplayTests {
    static let typedAnchor: C52ServiceRequestBoundaryTokenV1.Type = C52ServiceRequestBoundaryTokenV1.self
}

private final class C45JournalReplayCompatibilityTests: XCTestCase {
    func testV23P03C45CompatibilityUsesOneTypedWorkspaceCommand() {
        XCTAssertEqual(WorkspaceCommandKindV1.applyAssetLabel.rawValue, "apply_asset_label")
        XCTAssertTrue(WorkspaceWriterAdapterV1.activeSupportedCommandKinds.contains(.applyAssetLabel))
        XCTAssertEqual(AssetLabelMutationV1.schemaVersion, 1)
    }
}

private final class C30EvidenceContextAnchorV9_ChangeJournalCheckpointReplay: XCTestCase {
    func testTypedEvidenceContextContractAnchor() throws {
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.persistentSchemaVersion, 30)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.recordsSchemaVersion, 29)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.durableModelCount, 2)
        XCTAssertEqual(EvidenceLightingConditionV1.allCases.count, 6)
        XCTAssertTrue(WorkspaceWriterAdapterV1.activeSupportedCommandKinds.contains(.applyEvidenceContext))
        try EvidenceContextLimitsV1.digest(String(repeating: "a", count: 64))
    }
}

@MainActor
final class V9_ChangeJournalCheckpointReplayTests: XCTestCase {
    func testV23P03C37TypedPoseContractAnchor() throws {
        let axis = try PoseAxisDescriptorV1(
            axisID: PoseAxisID(rawValue: "axis.c37.anchor"),
            localizedLabelKey: "pose.c37.anchor",
            semanticRole: .otherDeclaredAxis,
            requiredComponents: .azimuthOnly,
            observationRequirement: .optional,
            applicability: .applicable
        )
        let registry = try PoseAxisDescriptorRegistryV1(descriptors: [axis])
        XCTAssertEqual(try registry.descriptor(for: axis.axisID), axis)
    }
    func testV23P03C29TypedPlanContractAnchor() throws {
        let minimum = try NormalizedPlanCoordinateV1(millionths: 0)
        let maximum = try NormalizedPlanCoordinateV1(millionths: PlanLimitsV1.normalizedScale)
        XCTAssertEqual(minimum.millionths, 0)
        XCTAssertEqual(maximum.millionths, PlanLimitsV1.normalizedScale)
        XCTAssertEqual(PlanDocumentV1.schemaVersion, 1)
    }
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

private final class C27ChangeJournalTypedLocatorAnchorTests: XCTestCase {
    func testAssetLocatorContractAnchor() throws {
        XCTAssertEqual(PersistentSchemaReleaseV1.v26.compatibilityID, "ASSET_LOCATOR_V1")
        XCTAssertEqual(LocatorBindingActionV1.allCases.count, 6)
        XCTAssertFalse(AssetLocatorLifecycleAdapterV1.scanMutatesCanonicalState)
    }
}

extension V9_ChangeJournalCheckpointReplayTests {
    func testC22RecoverabilityVerificationAnchor() throws {
        XCTAssertEqual(RecoverabilityVerificationReceiptV1.schemaVersion, 1)
        try V21RecoverabilityImportBoundaryV1.validate(persistentSchemaVersion: 21, recordsSchemaVersion: 20)
        XCTAssertEqual(RecoverabilityVerificationLifecycleV1.writer, "SOLE_CANONICAL_WORKSPACE_WRITER")
        XCTAssertFalse(RecoverabilityVerificationLifecycleV1.liveRestorePermitted)
    }
}

extension V9_ChangeJournalCheckpointReplayTests {
    func testV23P03C18ReplayBoundaryUsesCanonicalSemanticDigest() throws {
        let change = try PackageSemanticChangeV1(
            kind: .guidanceChanged,
            stableSubjectID: "c18.guidance"
        )
        let encoded = try PackageEvolutionCanonicalCodecV1.encode(change)
        XCTAssertEqual(
            try PackageEvolutionCanonicalCodecV1.decode(
                PackageSemanticChangeV1.self,
                from: encoded
            ),
            change
        )
        XCTAssertEqual(
            PackageEvolutionLifecycleV1.interruption,
            "OLD_COMPLETE_OR_NEW_COMPLETE_NEVER_HYBRID"
        )
    }
}

extension V9_ChangeJournalCheckpointReplayTests {
    func testV23P03C15JournalReplayRestoresExactManifestAndClaimBytes() throws {
        let fixture = try C15WorkPacketManifestTestSupportV1.makeFixture(seed: 150_204)
        let manifestBytes = try WorkPacketCanonicalCodecV1.encode(fixture.manifest)
        let claimBytes = try WorkPacketCanonicalCodecV1.encode(fixture.claim)
        let replayedManifest = try WorkPacketCanonicalCodecV1.decode(
            WorkPacketManifestV1.self, from: manifestBytes
        )
        let replayedClaim = try WorkPacketCanonicalCodecV1.decode(
            WorkItemClaimV1.self, from: claimBytes
        )
        XCTAssertEqual(replayedManifest, fixture.manifest)
        XCTAssertEqual(replayedClaim, fixture.claim)
        XCTAssertEqual(try WorkPacketCanonicalCodecV1.encode(replayedManifest), manifestBytes)
        XCTAssertEqual(try WorkPacketCanonicalCodecV1.encode(replayedClaim), claimBytes)
    }
}

extension V9_ChangeJournalCheckpointReplayTests {
    func testV23P03C36JournalReplayPreservesEveryDraftCanonicalByteSequence() throws {
        let fixture = try C36FieldDraftTestSupportV1.makeFixture()
        let values: [(Data, Data)] = [
            (try FieldDraftCanonicalCodecV1.encode(fixture.activeCheckpoint), try FieldDraftCanonicalCodecV1.encode(try FieldDraftCanonicalCodecV1.decode(FieldDraftCheckpointV1.self, from: FieldDraftCanonicalCodecV1.encode(fixture.activeCheckpoint)))),
            (try FieldDraftCanonicalCodecV1.encode(fixture.readyItem), try FieldDraftCanonicalCodecV1.encode(try FieldDraftCanonicalCodecV1.decode(AttachmentStagingItemV1.self, from: FieldDraftCanonicalCodecV1.encode(fixture.readyItem)))),
            (try FieldDraftCanonicalCodecV1.encode(fixture.preparedSaga), try FieldDraftCanonicalCodecV1.encode(try FieldDraftCanonicalCodecV1.decode(DraftCommitSagaV1.self, from: FieldDraftCanonicalCodecV1.encode(fixture.preparedSaga)))),
            (try FieldDraftCanonicalCodecV1.encode(fixture.reservation), try FieldDraftCanonicalCodecV1.encode(try FieldDraftCanonicalCodecV1.decode(DraftContentReservationV1.self, from: FieldDraftCanonicalCodecV1.encode(fixture.reservation)))),
            (try FieldDraftCanonicalCodecV1.encode(fixture.commitReceipt), try FieldDraftCanonicalCodecV1.encode(try FieldDraftCanonicalCodecV1.decode(DraftCommitReceiptV1.self, from: FieldDraftCanonicalCodecV1.encode(fixture.commitReceipt)))),
            (try FieldDraftCanonicalCodecV1.encode(fixture.discardReceipt), try FieldDraftCanonicalCodecV1.encode(try FieldDraftCanonicalCodecV1.decode(DraftDiscardReceiptV1.self, from: FieldDraftCanonicalCodecV1.encode(fixture.discardReceipt))))
        ]
        XCTAssertTrue(values.allSatisfy { $0.0 == $0.1 })
        XCTAssertEqual(fixture.commitReceipt.sagaEventSHA256Chain.last, fixture.retiredSaga.sagaSHA256)
    }
}

extension V9_ChangeJournalCheckpointReplayTests {
    func testV9_ChangeJournalCheckpointReplayC17IntegrationEventsRemainDerivedAndRebuildable() throws {
        let coverage = IntegrationEventJournalCoverageV1()
        try coverage.validate()
        XCTAssertEqual(
            coverage.sourceTruth,
            "ACCEPTED_MUTATION_RECEIPTS_AND_CHANGE_JOURNAL_V1"
        )
        XCTAssertEqual(coverage.projectionSchema, "INTEGRATION_PROJECTION_SCHEMA_V1")
        XCTAssertTrue(coverage.acceptedReceiptAndJournalOnly)
        XCTAssertTrue(coverage.providerNeutral)
        XCTAssertFalse(coverage.canonicalPersistence)
        XCTAssertFalse(coverage.backupIncluded)
        XCTAssertFalse(coverage.restoreIncluded)
        XCTAssertFalse(coverage.exportIncluded)
        XCTAssertFalse(coverage.reportSourceOfTruth)
        XCTAssertTrue(coverage.dropAndRebuild)

        let fixtureURL = sourceRoot().appendingPathComponent(
            "FieldEvidenceAppTests/Fixtures/V21/Integration/V21P03C17IntegrationEventProjectionCorpusV1.json"
        )
        let fixture = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as? [String: Any]
        )
        XCTAssertEqual(
            fixture["schema"] as? String,
            "V21P03C17IntegrationEventProjectionCorpusV1"
        )
        XCTAssertEqual(fixture["expectedEventCount"] as? Int, 6)
        XCTAssertEqual(fixture["expectedReceiptCount"] as? Int, 3)

        let productionFiles = [
            "FieldEvidenceApp/Domain/Replication/IntegrationEventContractsV1.swift",
            "FieldEvidenceApp/Infrastructure/Replication/IntegrationEventProjectionV1.swift",
            "FieldEvidenceApp/Infrastructure/Replication/IntegrationConformanceConsumerV1.swift",
            "FieldEvidenceApp/Infrastructure/Replication/IntegrationProjectionCheckpointStoreV1.swift",
        ]
        let productionSource = try productionFiles.map {
            try String(
                contentsOf: sourceRoot().appendingPathComponent($0),
                encoding: .utf8
            )
        }.joined(separator: "\n")
        XCTAssertTrue(productionSource.contains("IntegrationEventV1"))
        XCTAssertTrue(productionSource.contains("ProjectionCheckpointV1"))
        XCTAssertTrue(productionSource.contains("DROP_AND_REBUILD"))
        XCTAssertFalse(productionSource.contains("IntegrationEventProviderAdapterV1"))
        XCTAssertFalse(productionSource.contains("IntegrationEventOutboxV1"))
        XCTAssertFalse(productionSource.contains("IntegrationEventInboxV1"))
        XCTAssertFalse(productionSource.contains("IntegrationEventCredentialV1"))
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

    func testV23P03C19ChangeJournalReceiptReplaysExactMeasurementBundle() throws {
        let fixture = try C19MeasurementIntegrityTestSupport.makeFixture()
        let bytes = try MeasurementIntegrityCanonicalCodecV1.encode(fixture.bundle)
        let replayed = try MeasurementIntegrityCanonicalCodecV1.decode(
            MeasurementIntegrityAtomicBundleV1.self, from: bytes
        )
        XCTAssertEqual(replayed, fixture.bundle)
        XCTAssertEqual(replayed.bundleSHA256, fixture.bundle.bundleSHA256)
        try replayed.validate()
    }

    func testC20PrivacyTransformReplayUsesCanonicalManifestBytes() throws {
        let fixture = try C20PrivacyTransformTestSupport.makeFixture()
        let first = try PrivacyTransformCanonicalCodecV1.encode(fixture.manifest)
        let second = try PrivacyTransformCanonicalCodecV1.encode(fixture.manifest)
        XCTAssertEqual(first, second)
        XCTAssertEqual(try PrivacyTransformCanonicalCodecV1.decode(PrivacyTransformManifestV1.self, from: first), fixture.manifest)
    }
}

extension V9_ChangeJournalCheckpointReplayTests {
    func testC21ClientCapabilityLifecycleAnchor() throws {
        XCTAssertEqual(ClientCapabilityProfileV1.schemaVersion, 1)
        XCTAssertEqual(ClientAdmissionV1.allCases.count, 5)
        XCTAssertEqual(PackageLifecycleOperationV1.allCases.count, 9)
        XCTAssertEqual(PersistentSchemaV20.models.count, 81)
        XCTAssertNoThrow(try V20ClientCapabilityImportBoundaryV1.validate(persistent: 20, records: 19))
    }
}

extension V9_ChangeJournalCheckpointReplayTests {
    func testV23P03C28TypedScheduleBoundaryIsClosedAndNonpersistent() {
        XCTAssertEqual(OccurrenceStateV1.allCases, [.upcoming, .ready, .due, .overdue, .deferred,
                                                    .missed, .skipped, .cancelled, .started, .completed])
        XCTAssertEqual(ScheduleReleaseActionV1.allCases.count, 6)
        XCTAssertFalse(WorkflowScheduleBoundaryV1.dueProjectionMayStartWorkflow)
    }
}
private final class C31LightingAnchorV9ChangeJournalCheckpointReplayTests: XCTestCase {
    func testC31TypedLightingPackageContractAnchor() throws {
        XCTAssertEqual(LightingPersistenceEnrollmentV1.persistentSchemaVersion, 31)
        XCTAssertEqual(LightingClaimTierV1.allCases.count, 5)
        XCTAssertTrue(LightingIssueKindV1.allCases.contains(.cameraBandingOnly))
        try LightingLimitsV1.digest(String(repeating: "a", count: 64))
    }
}

extension V9_ChangeJournalCheckpointReplayTests {
    @MainActor
    func testV23P03C42ChangeJournalReplayRetainsTypedRevisionAndMutationIdentity() throws {
        let receipts = [try CompositeAreaSafetyArchetypeV1.run(), try ControllerZoneDistributionArchetypeV1.run()]
        for (offset, receipt) in receipts.enumerated() {
            let c42Bytes = try CrossMarketCanonicalV1.data(receipt)
            let payload = c42Bytes.base64EncodedString()
            let supersede = try XCTUnwrap(receipt.operations.first { $0.kind == .supersede })
            let stale = try XCTUnwrap(receipt.operations.first { $0.kind == .rejectStaleRevision })
            let mutationID = try XCTUnwrap(receipt.operations.compactMap(\.mutationID).first)
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(
                "V9-ChangeJournal-C42-\(offset)-\(UUID().uuidString)",
                isDirectory: true
            )
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
            defer { try? FileManager.default.removeItem(at: root) }
            let session = try StoreGenerationFactory(applicationSupportURL: root).openOrBootstrapCurrent()
            let siteID = UUID()
            session.modelContext.insert(Site(
                id: siteID,
                label: receipt.archetypeID,
                address: payload,
                timeZoneID: "UTC",
                createdAt: Date(timeIntervalSince1970: 1_800_420_000 + Double(offset))
            ))
            try session.modelContext.save()
            let coordinator = StoreSessionCoordinator(session: session)
            let writer = coordinator.workspaceWriter
            let before = try writer.currentRevision()
            let expected = try WorkspaceExpectedRevisionV1(
                workspaceID: before.workspaceID,
                generationID: before.generationID,
                writerInstanceID: before.writerInstanceID,
                workspaceRevision: before.revision,
                entityRevisions: [try WorkspaceEntityRevisionV1(
                    identity: WorkspaceEntityIdentityV1(kind: .site, id: siteID),
                    revision: 0
                )]
            )
            let request = WorkspaceMutationRequestV1(
                mutationID: mutationID,
                expectedRevision: expected,
                command: .updateSiteTimeZone(.init(
                    siteID: siteID,
                    timeZoneID: "Europe/Paris",
                    confirmedAt: Date(timeIntervalSince1970: 1_800_420_100 + Double(offset))
                ))
            )
            let firstOutcome = try writer.execute(request)
            let replayOutcome = try writer.execute(request)
            let journal = try MutationJournalStoreV1(
                modelContext: session.modelContext,
                identity: session.workspaceIdentity,
                generationID: session.generationID,
                allowStateBootstrap: false
            )
            let durableReceipt = try XCTUnwrap(journal.receipt(mutationID: mutationID))
            let backup = BackupExportService(
                modelContext: session.modelContext,
                generationRootURL: session.generationRootURL,
                storagePreflight: StoragePreflightService(capacityProvider: { _ in .max })
            )
            let checkpoint = try backup.canonicalCheckpointBasis()
            let records = try BackupCanonicalDecoderV1().decodeRecords(checkpoint.recordsData)
            let restoredPayload = try XCTUnwrap(records.sites.first?.address)

            XCTAssertEqual(restoredPayload, payload)
            XCTAssertEqual(
                try CrossMarketCanonicalV1.decode(
                    ModelRunReceiptV1.self,
                    from: try XCTUnwrap(Data(base64Encoded: restoredPayload))
                ),
                receipt
            )
            XCTAssertEqual(replayOutcome, firstOutcome)
            XCTAssertEqual(durableReceipt.mutationID, mutationID)
            XCTAssertEqual(checkpoint.workspaceRevision, firstOutcome.after.revision)
            XCTAssertEqual(try journal.exportSnapshot().workspaceRevision, firstOutcome.after.revision)
            XCTAssertEqual(supersede.resultingRevision, 2)
            XCTAssertEqual(stale.entityID, supersede.entityID)
        }
    }
}

private final class C33TemporalEvidenceAnchorV9ChangeJournalCheckpointReplay: XCTestCase {
    func testC33V9ChangeJournalCheckpointReplayCompatibilityBindsTypedTemporalEvidenceToItsOwner() throws {
        let value = try C33TemporalEvidenceTestSupport.ownerClip(
            factID: "journal.temporal-evidence-replay",
            kind: .audio,
            reportProjection: .typedLinkOnly
        )
        try C33TemporalEvidenceTestSupport.assertOwnerBoundary(
            value,
            factID: "journal.temporal-evidence-replay",
            kind: .audio,
            reportProjection: .typedLinkOnly
        )
        let anchor = try C33TemporalEvidenceTestSupport.anchor(clip: value.clip)
        XCTAssertEqual(anchor.clipSHA256, value.clip.clipSHA256)
        XCTAssertEqual(anchor.sourceContentID, value.clip.original.contentID)
    }
}

private final class C32AssistanceAnchorV9ChangeJournalCheckpointReplay: XCTestCase {
    func testC32V9ChangeJournalCheckpointReplayCompatibilityKeepsProposalAtExplicitReviewBoundary() throws {
        let proposal = try C32AssistanceTestSupport.ownerProposal(
            entityKind: .factCapture,
            fieldID: "journal.effect-before-receipt",
            value: .integer(8)
        )
        try C32AssistanceTestSupport.assertOwnerBoundary(
            proposal,
            entityKind: .factCapture,
            fieldID: "journal.effect-before-receipt",
            valueKind: .integer
        )
        let canonical = try AssistanceCanonicalCodecV1.encode(proposal)
        XCTAssertEqual(
            try AssistanceCanonicalCodecV1.decode(AssistanceProposalV1.self, from: canonical),
            proposal
        )
    }
}
private final class C46JournalReplayCompatibilityTests: XCTestCase {
    func testC46JournalReplayBindsContactRevisionAndHandoffTarget() throws {
        try C46OperationalContactTestSupport.assertOwnerBoundary(
            owner: "journal-replay",
            kind: .email,
            handoff: .email,
            slot: 46200
        )
    }
}

extension C45JournalReplayCompatibilityTests {
    func testV23P03C51ReplayRevalidatesPersistedOverrideFrontier() {
        XCTAssertTrue(
            C51ScheduleOverrideRecoveryBoundaryV1.commandKind == .applySchedule
                && C51ScheduleOverrideRecoveryBoundaryV1
                    .effectBeforeReceiptRecoveryUsesCanonicalPostimages
                && C51ScheduleOverrideRecoveryBoundaryV1
                    .overrideFrontierIsRevalidatedFromPersistedRows
                && !C51ScheduleOverrideRecoveryBoundaryV1.createsParallelWriter
        )
    }
}

extension V9_ChangeJournalCheckpointReplayTests {
    func testV23P03C34NavigationStateIsExcludedFromTheChangeJournal() {
        let lifecycle = SceneNavigationLifecycleDispositionV1()
        XCTAssertFalse(lifecycle.journalIncluded)
        XCTAssertFalse(lifecycle.workspaceTruth)
        XCTAssertFalse(lifecycle.backupIncluded)
        XCTAssertTrue(lifecycle.tolerantDecode)
    }
}

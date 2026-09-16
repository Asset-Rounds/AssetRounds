import XCTest
import SwiftData
@testable import FieldEvidenceApp

@MainActor
final class V23FieldDraftReadyStagePublicationTests: XCTestCase {
    func testBundleCanonicalRoundTripAndPluralMutationMappingsPreserveIncumbentCase() throws {
        let fixture = try ReadyStageFixture()
        let bundleData = try FieldDraftCanonicalCodecV1.encode(fixture.bundle)
        let decoded = try JSONDecoder.fieldDraft.decode(
            FieldDraftStagePublicationBundleV1.self, from: bundleData
        )
        try decoded.validate()
        XCTAssertEqual(decoded, fixture.bundle)
        XCTAssertEqual(try FieldDraftCanonicalCodecV1.encode(decoded), bundleData)

        let mutation = try fixture.publicationMutation()
        let stageIdentity = try WorkspaceEntityIdentityV1(
            kind: .attachmentStagingItem, id: fixture.ready.stageID
        )
        let checkpointIdentity = try WorkspaceEntityIdentityV1(
            kind: .fieldDraftCheckpoint, id: fixture.expected.draftID
        )
        XCTAssertEqual(try mutation.affectedIdentities,
                       [stageIdentity, checkpointIdentity].sorted { $0.stableKey < $1.stableKey })
        XCTAssertEqual(try mutation.concurrencyIdentities,
                       [stageIdentity, checkpointIdentity].sorted { $0.stableKey < $1.stableKey })
        XCTAssertEqual(try mutation.expectedRevision(for: stageIdentity), 0)
        XCTAssertEqual(try mutation.expectedRevision(for: checkpointIdentity), 1)
        XCTAssertThrowsError(try mutation.affectedIdentity)
        XCTAssertThrowsError(try mutation.concurrencyIdentity)
        XCTAssertThrowsError(try mutation.expectedRevision(for:
            .init(kind: .site, id: ReadyStageFixture.id(90))))
        XCTAssertEqual(try mutation.postImage.mutationPostImages.map(\.revision).sorted(), [1, 2])

        let incumbent = try FieldDraftMutationV1(
            workspaceID: fixture.workspaceID, expectedRevision: 0,
            expectedBaseCanonicalRevision: fixture.expected.baseCanonicalRevision,
            mutationID: fixture.expected.mutationID, postImage: .createCheckpoint(fixture.expected)
        )
        let incumbentData = try WorkspaceMutationCanonicalV1.data(incumbent)
        XCTAssertEqual(try JSONDecoder.fieldDraft.decode(FieldDraftMutationV1.self,
                                                         from: incumbentData), incumbent)

        let unknownCase = String(data: try WorkspaceMutationCanonicalV1.data(mutation),
                                 encoding: .utf8)!
            .replacingOccurrences(of: "publishReadyStage", with: "futureReadyStage")
        XCTAssertThrowsError(try JSONDecoder.fieldDraft.decode(
            FieldDraftMutationV1.self, from: Data(unknownCase.utf8)
        ))
    }

    func testBundleRejectsUnknownSchemaAndMalformedAtomicPairs() throws {
        let fixture = try ReadyStageFixture()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(
            with: FieldDraftCanonicalCodecV1.encode(fixture.bundle)) as? [String: Any])
        object["schemaVersion"] = 2
        let future = try JSONDecoder.fieldDraft.decode(FieldDraftStagePublicationBundleV1.self,
            from: JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
        XCTAssertThrowsError(try future.validate())

        let missingUnion = try fixture.successor(stageIDs: [], mutationID: fixture.publicationID)
        XCTAssertThrowsError(try FieldDraftStagePublicationBundleV1(
            expectedCheckpoint: fixture.expected, readyItem: fixture.ready,
            successorCheckpoint: missingUnion
        ))
        let foreignMutation = try fixture.readyItem(mutationID: .init(rawValue: Self.id(91)))
        XCTAssertThrowsError(try FieldDraftStagePublicationBundleV1(
            expectedCheckpoint: fixture.expected, readyItem: foreignMutation,
            successorCheckpoint: fixture.successor
        ))
        let wrongRevision = try fixture.readyItem(revision: 2, state: .readyLocal,
                                                   mutationID: fixture.publicationID)
        XCTAssertThrowsError(try FieldDraftStagePublicationBundleV1(
            expectedCheckpoint: fixture.expected, readyItem: wrongRevision,
            successorCheckpoint: fixture.successor
        ))
        let wrongState = try fixture.readyItem(state: .processing,
                                               mutationID: fixture.publicationID)
        XCTAssertThrowsError(try FieldDraftStagePublicationBundleV1(
            expectedCheckpoint: fixture.expected, readyItem: wrongState,
            successorCheckpoint: fixture.successor
        ))
    }

    func testRealCoordinatorPublishesOnePairAndReplaysAfterSuccessorHotAndCold() throws {
        let fixture = try ReadyStageFixture()
        let node = try ReadyStageStoreNode(workspaceID: fixture.workspaceID)
        defer { node.removeClosedFiles() }
        let first: MutationReceiptV1 = try node.withSession { session in
            let coordinator = try fixture.coordinator(writer: session.lifecycle)
            _ = try coordinator.checkpoint(fixture.expected, expectedDraftRevision: 0,
                                           expectedBaseRevision: fixture.expected.baseCanonicalRevision)
            XCTAssertNil(try session.lifecycle.readyStagePublicationEvidence(for: fixture.bundle))
            let receipt = try coordinator.publish(readyStage: fixture.bundle)
            try assertExactPublication(receipt, mutation: fixture.publicationMutation(), fixture: fixture)
            XCTAssertEqual(try session.lifecycle.currentCheckpoint(workspaceID: fixture.workspaceID,
                                                                   draftID: fixture.expected.draftID),
                           fixture.successor)
            XCTAssertEqual(try session.context.fetch(FetchDescriptor<AttachmentStagingItemRow>())
                .map { try $0.value() }, [fixture.ready])
            let evidence = try XCTUnwrap(session.lifecycle.readyStagePublicationEvidence(
                for: fixture.bundle))
            XCTAssertEqual(evidence.receipt, receipt)
            XCTAssertEqual(evidence.mutation, try fixture.publicationMutation())
            XCTAssertEqual(try coordinator.publish(readyStage: fixture.bundle), receipt)
            XCTAssertFalse(session.context.hasChanges)
            try session.journal.validateAll()
            return receipt
        }
        try node.withSession { session in
            let coordinator = try fixture.coordinator(writer: session.lifecycle)
            XCTAssertEqual(try coordinator.publish(readyStage: fixture.bundle), first)
            XCTAssertEqual(try XCTUnwrap(session.lifecycle.readyStagePublicationEvidence(
                for: fixture.bundle)).receipt, first)
            XCTAssertEqual(try session.context.fetchCount(FetchDescriptor<FieldDraftCheckpointRow>()), 1)
            XCTAssertEqual(try session.context.fetchCount(FetchDescriptor<AttachmentStagingItemRow>()), 1)
            XCTAssertEqual(try session.context.fetchCount(FetchDescriptor<MutationReceiptRow>()), 2)
            try session.journal.validateAll()
        }
    }

    func testPublicationReceiptRejectsExtraExpectedAndResultIdentity() throws {
        let fixture = try ReadyStageFixture()
        let node = try ReadyStageStoreNode(workspaceID: fixture.workspaceID)
        defer { node.removeClosedFiles() }
        let unrelated = try FieldDraftCheckpointV1(draftID: Self.id(92),
            workspaceID: fixture.workspaceID, scope: fixture.expected.scope,
            purpose: fixture.expected.purpose, codec: fixture.expected.codec,
            baseCanonicalRevision: fixture.expected.baseCanonicalRevision,
            draftRevision: 1, payloadData: Data("unrelated durable checkpoint".utf8),
            stageIDs: [], resumeAnchor: fixture.expected.resumeAnchor, state: .active,
            updatedAt: ReadyStageFixture.date, mutationID: .init(rawValue: Self.id(93)))
        let unrelatedIdentity = try WorkspaceEntityIdentityV1(
            kind: .fieldDraftCheckpoint, id: unrelated.draftID)
        let original = try readyStageObserved("publication receipt hot session") { try node.withSession { session in
            _ = try session.lifecycle.compareAndSwap(checkpoint: unrelated,
                expectedDraftRevision: 0, expectedBaseRevision: unrelated.baseCanonicalRevision)
            _ = try session.lifecycle.compareAndSwap(checkpoint: fixture.expected,
                expectedDraftRevision: 0, expectedBaseRevision: fixture.expected.baseCanonicalRevision)
            let receipt = try session.lifecycle.publish(readyStage: fixture.bundle)
            let mutation = try fixture.publicationMutation()
            let typed = try FieldDraftMutationReceiptV1(mutation: mutation, mutationReceipt: receipt)
            XCTAssertEqual(Set(receipt.resultingRevision.entityRevisions.map(\.identity)),
                           Set(typed.affectedIdentities + [unrelatedIdentity]))
            XCTAssertEqual(receipt.resultingRevision.entityRevisions.first {
                $0.identity == unrelatedIdentity
            }?.revision, unrelated.draftRevision)
            XCTAssertEqual(try session.lifecycle.currentCheckpoint(workspaceID: fixture.workspaceID,
                draftID: unrelated.draftID), unrelated)
            XCTAssertEqual(receipt.postImages, try mutation.postImage.mutationPostImages)
            XCTAssertFalse(typed.affectedIdentities.contains(unrelatedIdentity))
            let extraExpected = try readyStageObserved("construct extra expected identity receipt") {
                try receiptWithExtraIdentity(receipt, mutation: mutation,
                                             inExpected: true, inResult: false)
            }
            try extraExpected.validate()
            XCTAssertThrowsError(try FieldDraftMutationReceiptV1(
                mutation: mutation, mutationReceipt: extraExpected
            )) { XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .invalidReceipt) }
            let extraResult = try readyStageObserved("construct extra result identity receipt") {
                try receiptWithExtraIdentity(receipt, mutation: mutation,
                                             inExpected: false, inResult: true)
            }
            try extraResult.validate()
            // A standalone wrapper cannot authenticate unrelated workspace state.
            // The retained journal must reject a replacement for its original receipt.
            let row = try XCTUnwrap(session.context.fetch(FetchDescriptor<MutationReceiptRow>())
                .first { $0.mutationID == receipt.mutationID.rawValue })
            let originalBytes = row.receiptData
            row.receiptData = try extraResult.canonicalData()
            try session.context.save()
            XCTAssertThrowsError(try session.journal.validateAll())
            XCTAssertThrowsError(try session.lifecycle.readyStagePublicationEvidence(for: fixture.bundle))
            XCTAssertEqual(row.receiptData, try extraResult.canonicalData())
            row.receiptData = originalBytes
            try session.context.save()
            try session.journal.validateAll()
            try readyStageObserved("affected result receipt guards") {
                try assertPublicationAffectedResultGuards(receipt, mutation: mutation)
            }
            XCTAssertEqual(try XCTUnwrap(session.lifecycle.readyStagePublicationEvidence(
                for: fixture.bundle)).receipt, receipt)
            return receipt
        } }
        try readyStageObserved("publication receipt cold session") { try node.withSession { session in
            let receipt = try session.lifecycle.publish(readyStage: fixture.bundle)
            XCTAssertEqual(receipt, original)
            XCTAssertEqual(try session.lifecycle.currentCheckpoint(workspaceID: fixture.workspaceID,
                draftID: unrelated.draftID), unrelated)
            _ = try FieldDraftMutationReceiptV1(mutation: fixture.publicationMutation(),
                                                mutationReceipt: receipt)
            try session.journal.validateAll()
        } }
    }

    func testOccupiedStageStalePredecessorAndDivergentRetryPreserveCommittedPair() throws {
        let fixture = try ReadyStageFixture()
        let node = try ReadyStageStoreNode(workspaceID: fixture.workspaceID)
        defer { node.removeClosedFiles() }
        try node.withSession { session in
            _ = try session.lifecycle.compareAndSwap(checkpoint: fixture.expected,
                expectedDraftRevision: 0, expectedBaseRevision: fixture.expected.baseCanonicalRevision)
            session.context.insert(try AttachmentStagingItemRow(fixture.ready))
            try session.context.save()
            XCTAssertThrowsError(try session.lifecycle.publish(readyStage: fixture.bundle))
            XCTAssertEqual(try session.lifecycle.currentCheckpoint(workspaceID: fixture.workspaceID,
                                                                   draftID: fixture.expected.draftID),
                           fixture.expected)
            XCTAssertEqual(try session.context.fetchCount(FetchDescriptor<AttachmentStagingItemRow>()), 1)
        }

        let stale = try ReadyStageStoreNode(workspaceID: fixture.workspaceID)
        defer { stale.removeClosedFiles() }
        try stale.withSession { session in
            _ = try session.lifecycle.compareAndSwap(checkpoint: fixture.expected,
                expectedDraftRevision: 0, expectedBaseRevision: fixture.expected.baseCanonicalRevision)
            let intervening = try fixture.successor(stageIDs: [],
                mutationID: .init(rawValue: Self.id(97)), payload: Data("intervening".utf8))
            _ = try session.lifecycle.compareAndSwap(checkpoint: intervening,
                expectedDraftRevision: 1, expectedBaseRevision: fixture.expected.baseCanonicalRevision)
            XCTAssertThrowsError(try session.lifecycle.publish(readyStage: fixture.bundle)) {
                XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .staleWorkspaceRevision)
            }
            XCTAssertEqual(try session.lifecycle.currentCheckpoint(workspaceID: fixture.workspaceID,
                                                                   draftID: fixture.expected.draftID),
                           intervening)
            XCTAssertEqual(try session.context.fetchCount(FetchDescriptor<AttachmentStagingItemRow>()), 0)
            XCTAssertNil(try session.writer.durableReceipt(mutationID: fixture.publicationID))
        }

        let clean = try ReadyStageStoreNode(workspaceID: fixture.workspaceID)
        defer { clean.removeClosedFiles() }
        try clean.withSession { session in
            _ = try session.lifecycle.compareAndSwap(checkpoint: fixture.expected,
                expectedDraftRevision: 0, expectedBaseRevision: fixture.expected.baseCanonicalRevision)
            let original = try session.lifecycle.publish(readyStage: fixture.bundle)
            let divergent = try fixture.divergentBundle()
            XCTAssertThrowsError(try session.lifecycle.publish(readyStage: divergent)) {
                XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
            }
            XCTAssertEqual(try session.lifecycle.currentCheckpoint(workspaceID: fixture.workspaceID,
                                                                   draftID: fixture.expected.draftID),
                           fixture.successor)
            XCTAssertEqual(try session.context.fetch(FetchDescriptor<AttachmentStagingItemRow>())
                .map { try $0.value() }, [fixture.ready])
            XCTAssertEqual(try session.context.fetchCount(FetchDescriptor<MutationReceiptRow>()), 2)
            XCTAssertEqual(try session.context.fetchCount(FetchDescriptor<MutationQuarantineRow>()), 1)
            XCTAssertEqual(original.mutationID, fixture.publicationID)
        }
    }

    #if DEBUG
    func testInjectedFailureAfterStageInsertRollsBackBothRowsAndReceipt() throws {
        let fixture = try ReadyStageFixture()
        let node = try ReadyStageStoreNode(workspaceID: fixture.workspaceID)
        defer { node.removeClosedFiles() }
        try node.withSession { session in
            _ = try session.lifecycle.compareAndSwap(checkpoint: fixture.expected,
                expectedDraftRevision: 0, expectedBaseRevision: fixture.expected.baseCanonicalRevision)
            session.adapter.afterReadyStageInsertForTesting = { throw InjectedFailure() }
            XCTAssertThrowsError(try session.lifecycle.publish(readyStage: fixture.bundle))
            XCTAssertEqual(try session.lifecycle.currentCheckpoint(workspaceID: fixture.workspaceID,
                                                                   draftID: fixture.expected.draftID),
                           fixture.expected)
            XCTAssertEqual(try session.context.fetchCount(FetchDescriptor<AttachmentStagingItemRow>()), 0)
            XCTAssertNil(try session.writer.durableReceipt(mutationID: fixture.publicationID))
            XCTAssertEqual(try session.context.fetchCount(FetchDescriptor<MutationReceiptRow>()), 1)
            XCTAssertFalse(session.context.hasChanges)
        }
    }
    #endif

    func testReadbackRejectsDirtyContextAndInvalidatedWriter() throws {
        let fixture = try ReadyStageFixture()
        let node = try ReadyStageStoreNode(workspaceID: fixture.workspaceID)
        defer { node.removeClosedFiles() }
        try node.withSession(invalidateAtEnd: false) { session in
            _ = try session.lifecycle.compareAndSwap(checkpoint: fixture.expected,
                expectedDraftRevision: 0, expectedBaseRevision: fixture.expected.baseCanonicalRevision)
            _ = try session.lifecycle.publish(readyStage: fixture.bundle)
            let otherContext = ModelContext(session.container)
            otherContext.autosaveEnabled = false
            let mismatched = FieldDraftLifecycleAdapterV1(writer: session.writer,
                journal: session.journal, modelContext: otherContext)
            XCTAssertThrowsError(try mismatched.readyStagePublicationEvidence(for: fixture.bundle))
            session.context.insert(try AttachmentStagingItemRow(
                fixture.readyItem(stageID: Self.id(92), mutationID: .init(rawValue: Self.id(93)))
            ))
            XCTAssertThrowsError(try session.lifecycle.readyStagePublicationEvidence(for: fixture.bundle))
            session.context.rollback()
            session.writer.invalidate()
            XCTAssertThrowsError(try session.lifecycle.readyStagePublicationEvidence(for: fixture.bundle)) {
                XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .writerInvalidated)
            }
        }
    }

    func testReadbackRejectsSavedMissingHalfAndUnreceiptedPairWithoutWrites() throws {
        let fixture = try ReadyStageFixture()
        for damage in ["missing-stage", "missing-checkpoint", "unreceipted-pair"] {
            let node = try ReadyStageStoreNode(workspaceID: fixture.workspaceID)
            defer { node.removeClosedFiles() }
            try node.withSession { session in
                _ = try session.lifecycle.compareAndSwap(checkpoint: fixture.expected,
                    expectedDraftRevision: 0,
                    expectedBaseRevision: fixture.expected.baseCanonicalRevision)
                if damage == "unreceipted-pair" {
                    let checkpoint = try XCTUnwrap(session.context.fetch(
                        FetchDescriptor<FieldDraftCheckpointRow>()).first)
                    try checkpoint.replace(with: fixture.successor, expectedRevision: 1)
                    session.context.insert(try AttachmentStagingItemRow(fixture.ready))
                } else {
                    _ = try session.lifecycle.publish(readyStage: fixture.bundle)
                    if damage == "missing-stage" {
                        session.context.delete(try XCTUnwrap(session.context.fetch(
                            FetchDescriptor<AttachmentStagingItemRow>()).first))
                    } else {
                        session.context.delete(try XCTUnwrap(session.context.fetch(
                            FetchDescriptor<FieldDraftCheckpointRow>()).first))
                    }
                }
                try session.context.save()
                func retainedBytes() throws -> [[Data]] {
                    let checkpoints = try session.context.fetch(FetchDescriptor<FieldDraftCheckpointRow>())
                        .map(\.canonicalData)
                    let stages = try session.context.fetch(FetchDescriptor<AttachmentStagingItemRow>())
                        .map(\.canonicalData)
                    let history = try session.context.fetch(FetchDescriptor<MutationReceiptRow>())
                        .sorted { $0.workspaceMutationKey < $1.workspaceMutationKey }
                        .flatMap { [$0.envelopeData, $0.receiptData,
                                    $0.reversalBasisData ?? Data(), $0.semanticReversalData ?? Data()] }
                    return [checkpoints, stages, history]
                }
                let prior = try retainedBytes()
                let priorQuarantines = try session.context.fetchCount(FetchDescriptor<MutationQuarantineRow>())
                XCTAssertThrowsError(try session.lifecycle.readyStagePublicationEvidence(for: fixture.bundle))
                XCTAssertEqual(try retainedBytes(), prior)
                XCTAssertEqual(try session.context.fetchCount(FetchDescriptor<MutationQuarantineRow>()),
                               priorQuarantines)
                XCTAssertFalse(session.context.hasChanges)
            }
        }
    }

    func testAtomicPublicationBackupValidatesRejectsMissingHalvesAndRestoresSameWorkspaceCold()
        async throws {
        var step = "create source harness"
        var finished = false
        defer { if !finished { XCTFail("Atomic publication stopped at: \(step)") } }
        let source = try BackupHarness(name: "source")
        defer { source.removeFiles() }
        step = "create atomic backup"
        let package = try await makeAtomicBackup(in: source)
        XCTAssertTrue(source.sessionsAreReleased)
        step = "validate exported package"
        let validated = try BackupPackageValidatorV1().validate(stagedPackageURL: package.directory)
        XCTAssertEqual(validated.records.fieldDrafts.count, 2)
        XCTAssertEqual(validated.members[package.memberPath], package.bytes)
        step = "decode archived checkpoint"
        let archivedCheckpoint = try FieldDraftCanonicalCodecV1.decode(
            FieldDraftCheckpointV1.self,
            from: XCTUnwrap(validated.records.fieldDrafts.first { $0.kind == .checkpoint })
                .canonicalData)
        step = "decode archived staging item"
        let archivedStage = try FieldDraftCanonicalCodecV1.decode(
            AttachmentStagingItemV1.self,
            from: XCTUnwrap(validated.records.fieldDrafts.first { $0.kind == .stagingItem })
                .canonicalData)
        XCTAssertEqual(archivedCheckpoint, package.bundle.successorCheckpoint)
        XCTAssertEqual(archivedStage, package.bundle.readyItem)
        step = "authenticate original publication history"
        let history = try XCTUnwrap(validated.records.mutationHistory).receipts.filter {
            try MutationReceiptV1.decodeCanonical(from: $0.receiptData).mutationID
                == package.bundle.mutationID
        }
        XCTAssertEqual(history, [package.historyRecord])
        try assertOriginalPublicationHistory(try XCTUnwrap(history.first), package: package)

        for removedKind in [V16BackupFieldDraftRecordV1.Kind.stagingItem, .checkpoint] {
            step = "prepare missing-\(removedKind.rawValue) negative package"
            let missingRow = source.root.appendingPathComponent(
                "missing-\(removedKind.rawValue)-row", isDirectory: true)
            try FileManager.default.copyItem(at: package.directory, to: missingRow)
            step = "rewrite missing-\(removedKind.rawValue) negative package"
            let rewritten = try removeFieldDraftRowAndRehashPackage(at: missingRow, kind: removedKind)
            step = "decode missing-\(removedKind.rawValue) records"
            let decodable = try readyStageObserved("decode missing-\(removedKind.rawValue) records") {
                try BackupCanonicalDecoderV1().decodeRecords(rewritten)
            }
            XCTAssertEqual(decodable.fieldDrafts.count, 1)
            XCTAssertEqual(decodable.fieldDrafts.first?.kind,
                           removedKind == .stagingItem ? .checkpoint : .stagingItem)
            XCTAssertThrowsError(try BackupPackageValidatorV1().validate(stagedPackageURL: missingRow)) {
                XCTAssertEqual($0 as? BackupPackageValidationErrorV1, .invalidPackage)
            }
        }
        step = "prepare missing-stage-bytes negative package"
        let missingBytes = source.root.appendingPathComponent("missing-stage-bytes", isDirectory: true)
        try FileManager.default.copyItem(at: package.directory, to: missingBytes)
        try FileManager.default.removeItem(at: missingBytes.appendingPathComponent(package.memberPath))
        XCTAssertThrowsError(try BackupPackageValidatorV1().validate(stagedPackageURL: missingBytes)) {
            XCTAssertEqual($0 as? BackupPackageValidationErrorV1, .invalidPackage)
        }

        step = "create restore target"
        let target = try BackupHarness(name: "target", identity: package.identity)
        defer { target.removeFiles() }
        step = "restore and assert hot atomic pair"
        try await restoreAndAssertHotAtomicPair(package, in: target)
        XCTAssertTrue(target.sessionsAreReleased)
        step = "reopen and assert cold atomic pair"
        try await assertColdAtomicPair(package, in: target)
        XCTAssertTrue(target.sessionsAreReleased)
        finished = true
    }

    private func restoreAndAssertHotAtomicPair(_ package: AtomicBackupPackage,
                                               in target: BackupHarness) async throws {
        var step = "open target session"
        var finished = false
        defer { if !finished { XCTFail("Hot atomic restore stopped at: \(step)") } }
        let current = try target.openSession()
        step = "stage and validate archive"
        let imported = try BackupImportService(generationRootURL: current.generationRootURL,
            scopedAccess: .alreadyAuthorized).stageAndValidate(selectedPackageURL: package.archive)
        step = "restore validated archive"
        let restored = try await BackupRestoreService(applicationSupportURL: target.support,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in .max }))
            .restore(validatedPackage: imported, currentModelContext: current.modelContext,
                currentGenerationID: current.generationID,
                currentGenerationRootURL: current.generationRootURL)
        target.observeRestoredSession(restored)
        XCTAssertEqual(restored.workspaceIdentity, package.identity)
        step = "read restored pair and original history"
        try assertRestoredAtomicPair(restored.modelContext, package: package)
        try assertOriginalPublicationHistory(
            publicationHistory(in: restored.modelContext, mutationID: package.bundle.mutationID),
            package: package)
        step = "read restored staging bytes"
        let restoredBytes = try await DraftAttachmentStagingAdapterV1(
            applicationSupportURL: target.support, workspaceID: restored.workspaceID)
            .data(stageID: package.bundle.readyItem.stageID)
        XCTAssertEqual(restoredBytes, package.bytes)
        finished = true
    }

    private func assertColdAtomicPair(_ package: AtomicBackupPackage,
                                      in target: BackupHarness) async throws {
        var step = "open cold target session"
        var finished = false
        defer { if !finished { XCTFail("Cold atomic restore stopped at: \(step)") } }
        XCTAssertTrue(target.sessionsAreReleased)
        let cold = try target.openSession()
        XCTAssertEqual(cold.workspaceIdentity, package.identity)
        step = "read cold pair and original history"
        try assertRestoredAtomicPair(cold.modelContext, package: package)
        try assertOriginalPublicationHistory(
            publicationHistory(in: cold.modelContext, mutationID: package.bundle.mutationID),
            package: package)
        step = "read cold staging bytes"
        let coldBytes = try await DraftAttachmentStagingAdapterV1(
            applicationSupportURL: target.support, workspaceID: cold.workspaceID)
            .data(stageID: package.bundle.readyItem.stageID)
        XCTAssertEqual(coldBytes, package.bytes)
        finished = true
    }

    private func publicationHistory(in context: ModelContext, mutationID: MutationIDV1) throws
        -> MutationHistoryReceiptRecordV1 {
        let rows = try context.fetch(FetchDescriptor<MutationReceiptRow>())
            .filter { $0.mutationID == mutationID.rawValue }
        XCTAssertEqual(rows.count, 1)
        let row = try XCTUnwrap(rows.first)
        XCTAssertNil(row.reversalBasisSHA256)
        return .init(envelopeData: row.envelopeData, receiptData: row.receiptData,
                     reversalBasisData: row.reversalBasisData,
                     semanticReversalData: row.semanticReversalData)
    }

    private func assertOriginalPublicationHistory(_ value: MutationHistoryReceiptRecordV1,
                                                   package: AtomicBackupPackage) throws {
        XCTAssertEqual(value, package.historyRecord)
        XCTAssertNil(value.reversalBasisData)
        XCTAssertNil(value.semanticReversalData)
        let envelope = try MutationEnvelopeV1.decodeCanonical(from: value.envelopeData)
        let receipt = try MutationReceiptV1.decodeCanonical(from: value.receiptData)
        XCTAssertEqual(receipt, package.receipt)
        XCTAssertEqual(envelope.mutationID, package.bundle.mutationID)
        XCTAssertEqual(envelope.workspaceID, package.identity.workspaceID)
        XCTAssertEqual(envelope.command, .applyFieldDraft(try .init(
            workspaceID: package.bundle.workspaceID,
            expectedRevision: package.bundle.expectedCheckpoint.draftRevision,
            expectedBaseCanonicalRevision: package.bundle.expectedCheckpoint.baseCanonicalRevision,
            mutationID: package.bundle.mutationID, postImage: .publishReadyStage(package.bundle))))
        XCTAssertNil(receipt.reversesMutationID)
        XCTAssertNil(envelope.reversalPlanDigest)
        XCTAssertNil(envelope.semanticReversalReplayIdentitySHA256)
        XCTAssertNil(envelope.semanticReversalExecution)
    }

    func testEveryIncumbentFieldDraftPayloadCaseStillCanonicalRoundTrips() throws {
        var step = "construct C36 fixture"
        var finished = false
        defer { if !finished { XCTFail("Incumbent payload roundtrip stopped at: \(step)") } }
        let value = try C36FieldDraftTestSupportV1.makeFixture(seed: 936_000)
        step = "construct incumbent conflict payload"
        let conflict = try incumbentConflictPayload()
        let payloads: [(String, FieldDraftMutationPayloadV1)] = [
            ("createCheckpoint", .createCheckpoint(value.activeCheckpoint)),
            ("reviseCheckpoint", .reviseCheckpoint(value.committingCheckpoint)),
            ("appendStagingItem", .appendStagingItem(value.readyItem)),
            ("reviseStagingItem", .reviseStagingItem(value.committedItem)),
            ("appendCommitSaga", .appendCommitSaga(value.preparedSaga)),
            ("advanceCommitSaga", .advanceCommitSaga(value.promotedSaga)),
            ("appendContentReservation", .appendContentReservation(value.reservation)),
            ("reviseContentReservation", .reviseContentReservation(value.quarantinedReservation)),
            ("applyCommitTerminal", .applyCommitTerminal(value.commitTerminalBundle, expectedSagaRevision: 4)),
            ("applyDiscardTerminal", .applyDiscardTerminal(value.discardTerminalBundle)),
            ("resolveConflict", .resolveConflict(conflict))
        ]
        XCTAssertEqual(payloads.count, 11)
        for (name, payload) in payloads {
            step = "\(name): validate original"
            try payload.validate()
            step = "\(name): canonical encode"
            let data = try WorkspaceMutationCanonicalV1.data(payload)
            step = "\(name): decode"
            let decoded = try JSONDecoder.fieldDraft.decode(FieldDraftMutationPayloadV1.self, from: data)
            step = "\(name): validate decoded"
            try decoded.validate()
            XCTAssertEqual(decoded, payload, name)
            step = "\(name): canonical re-encode"
            XCTAssertEqual(try WorkspaceMutationCanonicalV1.data(decoded), data, name)
        }
        finished = true
    }

    private func assertExactPublication(_ receipt: MutationReceiptV1,
                                        mutation: FieldDraftMutationV1,
                                        fixture: ReadyStageFixture) throws {
        let typed = try FieldDraftMutationReceiptV1(mutation: mutation, mutationReceipt: receipt)
        XCTAssertEqual(Set(receipt.expectedRevision.entityRevisions.map(\.identity)),
                       Set(typed.concurrencyIdentities))
        XCTAssertEqual(Set(receipt.resultingRevision.entityRevisions.map(\.identity)),
                       Set(typed.affectedIdentities))
        XCTAssertEqual(receipt.postImages, try mutation.postImage.mutationPostImages)
        XCTAssertNil(receipt.reversesMutationID)
        XCTAssertEqual(receipt.mutationID, fixture.publicationID)
    }

    private func receiptWithExtraIdentity(_ receipt: MutationReceiptV1,
                                          mutation: FieldDraftMutationV1,
                                          inExpected: Bool, inResult: Bool) throws -> MutationReceiptV1 {
        let extra = try WorkspaceEntityIdentityV1(kind: .site, id: Self.id(94))
        var expectedRows = receipt.expectedRevision.entityRevisions
        var resultRows = receipt.resultingRevision.entityRevisions
        if inExpected { expectedRows.append(.init(identity: extra, revision: 0)) }
        if inResult { resultRows.append(.init(identity: extra, revision: 1)) }
        return try publicationReceipt(receipt, mutation: mutation,
            expectedRows: expectedRows, resultRows: resultRows)
    }

    private func publicationReceipt(_ receipt: MutationReceiptV1,
                                     mutation: FieldDraftMutationV1,
                                     expectedRows: [WorkspaceEntityRevisionV1]? = nil,
                                     resultRows: [WorkspaceEntityRevisionV1]? = nil,
                                     images: [MutationPostImageV1]? = nil) throws -> MutationReceiptV1 {
        let writerID = Self.id(95)
        let expected = try WorkspaceExpectedRevisionV1(
            workspaceID: receipt.expectedRevision.workspaceID,
            generationID: receipt.expectedRevision.generationID, writerInstanceID: writerID,
            workspaceRevision: receipt.expectedRevision.workspaceRevision,
            entityRevisions: expectedRows ?? receipt.expectedRevision.entityRevisions
        )
        let envelope = try MutationEnvelopeV1(request: .init(
            mutationID: mutation.mutationID, expectedRevision: expected,
            command: .applyFieldDraft(mutation)
        ), identity: .init(workspaceID: receipt.identity.workspaceID,
                           replicaID: receipt.identity.replicaID))
        let resulting = try MutationPortableExpectedRevisionV1(.init(
            workspaceID: receipt.resultingRevision.workspaceID,
            generationID: receipt.resultingRevision.generationID, writerInstanceID: writerID,
            workspaceRevision: receipt.resultingRevision.workspaceRevision,
            entityRevisions: resultRows ?? receipt.resultingRevision.entityRevisions
        ))
        return try MutationReceiptV1(identity: receipt.identity, envelope: envelope,
            resultingRevision: resulting, postImages: images ?? receipt.postImages,
            committedAt: receipt.committedAt)
    }

    private func assertPublicationAffectedResultGuards(_ receipt: MutationReceiptV1,
                                                       mutation: FieldDraftMutationV1) throws {
        for image in receipt.postImages {
            let identity = try image.identity
            let missing = receipt.resultingRevision.entityRevisions.filter { $0.identity != identity }
            XCTAssertThrowsError(try publicationReceipt(receipt, mutation: mutation,
                resultRows: missing), "Missing affected identity: \(identity.stableKey)")
            let wrong = receipt.resultingRevision.entityRevisions.map {
                $0.identity == identity
                    ? WorkspaceEntityRevisionV1(identity: identity, revision: $0.revision + 1) : $0
            }
            XCTAssertThrowsError(try publicationReceipt(receipt, mutation: mutation,
                resultRows: wrong), "Wrong affected revision: \(identity.stableKey)")
        }
        let changedImages: [MutationPostImageV1] = receipt.postImages.map { image in
            if case let .attachmentStagingItem(id, concurrency, revision, _) = image {
                return .attachmentStagingItem(id: id, concurrencyIdentity: concurrency,
                    revision: revision, semanticSHA256: ReadyStageFixture.digest("e"))
            }
            return image
        }
        let changed = try publicationReceipt(receipt, mutation: mutation, images: changedImages)
        try changed.validate()
        XCTAssertThrowsError(try FieldDraftMutationReceiptV1(mutation: mutation,
                                                            mutationReceipt: changed))
        let extraIdentity = try WorkspaceEntityIdentityV1(kind: .site, id: Self.id(94))
        let extraImage = MutationPostImageV1.site(id: extraIdentity.id, revision: 1,
                                                 semanticSHA256: ReadyStageFixture.digest("e"))
        let extra = try publicationReceipt(receipt, mutation: mutation,
            expectedRows: receipt.expectedRevision.entityRevisions + [.init(identity: extraIdentity, revision: 0)],
            resultRows: receipt.resultingRevision.entityRevisions + [.init(identity: extraIdentity, revision: 1)],
            images: receipt.postImages + [extraImage])
        try extra.validate()
        XCTAssertThrowsError(try FieldDraftMutationReceiptV1(mutation: mutation, mutationReceipt: extra))

        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: receipt.canonicalData())
            as? [String: Any])
        let wrongMutationID = try JSONSerialization.jsonObject(with:
            WorkspaceMutationCanonicalV1.data(MutationIDV1(rawValue: Self.id(98))))
        for (key, value) in [("commandBodySHA256", ReadyStageFixture.digest("f") as Any),
                             ("mutationID", wrongMutationID)] {
            var object = original
            object[key] = value
            let altered = try JSONDecoder.fieldDraft.decode(MutationReceiptV1.self,
                from: JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
            try altered.validate()
            XCTAssertThrowsError(try FieldDraftMutationReceiptV1(mutation: mutation,
                mutationReceipt: altered), key)
        }
        var foreignObject = original
        var foreignIdentity = try XCTUnwrap(foreignObject["identity"] as? [String: Any])
        foreignIdentity["workspaceID"] = try JSONSerialization.jsonObject(with:
            WorkspaceMutationCanonicalV1.data(WorkspaceID(rawValue: Self.id(99))))
        foreignObject["identity"] = foreignIdentity
        let foreign = try JSONDecoder.fieldDraft.decode(MutationReceiptV1.self,
            from: JSONSerialization.data(withJSONObject: foreignObject, options: [.sortedKeys]))
        XCTAssertThrowsError(try FieldDraftMutationReceiptV1(mutation: mutation,
                                                            mutationReceipt: foreign))
    }

    private func makeAtomicBackup(in harness: BackupHarness) async throws -> AtomicBackupPackage {
        var step = "open source session"
        var finished = false
        defer { if !finished { XCTFail("Atomic backup creation stopped at: \(step)") } }
        let session = try harness.openSession()
        step = "create source coordinator"
        let coordinator = try StoreSessionCoordinator(validatingSession: session)
        defer {
            do { try coordinator.invalidateAndReleaseWriter() }
            catch { XCTFail("Atomic backup writer release failed: \(error)") }
        }
        let workspace = coordinator.workspaceID
        let bytes = Data("atomic ready-stage owned bytes".utf8)
        let draftID = Self.id(110)
        step = "create staging adapter"
        let staging = try DraftAttachmentStagingAdapterV1(applicationSupportURL: harness.support,
            workspaceID: workspace, clock: { ReadyStageFixture.date })
        step = "write raw staging bytes"
        let item = try await staging.stage(data: bytes, draftID: draftID,
            workspaceID: workspace, attachmentKind: .photo)
        step = "construct base C36 fixture"
        let base = try C36FieldDraftTestSupportV1.makeFixture(seed: 936_100)
        step = "construct expected checkpoint"
        let expected = try FieldDraftCheckpointV1(draftID: draftID, workspaceID: workspace,
            scope: base.activeCheckpoint.scope, purpose: base.activeCheckpoint.purpose,
            codec: base.activeCheckpoint.codec, baseCanonicalRevision: 0, draftRevision: 1,
            payloadData: base.activeCheckpoint.payloadData, stageIDs: [],
            resumeAnchor: base.activeCheckpoint.resumeAnchor, state: .active,
            updatedAt: ReadyStageFixture.date, mutationID: .init(rawValue: Self.id(111)))
        step = "commit expected checkpoint"
        _ = try coordinator.workspaceWriter.commitFieldDraft(.init(workspaceID: workspace,
            expectedRevision: 0, expectedBaseCanonicalRevision: 0,
            mutationID: expected.mutationID, postImage: .createCheckpoint(expected)))
        step = "construct publication bundle"
        let successor = try FieldDraftCheckpointV1(draftID: draftID, workspaceID: workspace,
            scope: expected.scope, purpose: expected.purpose, codec: expected.codec,
            baseCanonicalRevision: 0, draftRevision: 2, payloadData: expected.payloadData,
            stageIDs: [item.stageID], resumeAnchor: expected.resumeAnchor, state: .active,
            updatedAt: ReadyStageFixture.date.addingTimeInterval(1), mutationID: item.mutationID)
        let bundle = try FieldDraftStagePublicationBundleV1(expectedCheckpoint: expected,
            readyItem: item, successorCheckpoint: successor)
        let mutation = try FieldDraftMutationV1(workspaceID: workspace, expectedRevision: 1,
            expectedBaseCanonicalRevision: 0, mutationID: item.mutationID,
            postImage: .publishReadyStage(bundle))
        step = "commit atomic publication"
        let receipt = try coordinator.workspaceWriter.commitFieldDraft(mutation)
        step = "create export directory"
        let exportRoot = harness.root.appendingPathComponent("export", isDirectory: true)
        try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: true)
        let exporter = BackupExportService(modelContext: session.modelContext,
            generationRootURL: session.generationRootURL,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in .max }),
            now: { ReadyStageFixture.date.addingTimeInterval(60) })
        step = "prepare backup export"
        let preview = try exporter.prepare()
        step = "export archive"
        let archive = try exporter.export(previewID: preview.id, to: exportRoot)
        let directory = harness.root.appendingPathComponent("decoded.fieldrecordbackup", isDirectory: true)
        step = "extract exported archive"
        _ = try StreamingArchiveService().extract(archive, to: directory)
        let memberPath = "draft-staging/\(draftID.uuidString.lowercased())/"
            + "\(item.stageID.uuidString.lowercased()).bin"
        step = "capture original publication history"
        let result = AtomicBackupPackage(archive: archive, directory: directory, bytes: bytes,
                     memberPath: memberPath, bundle: bundle, receipt: receipt,
                     identity: session.workspaceIdentity,
                     historyRecord: try publicationHistory(in: session.modelContext,
                                                           mutationID: bundle.mutationID))
        finished = true
        return result
    }

    private func removeFieldDraftRowAndRehashPackage(at package: URL,
                                                     kind: V16BackupFieldDraftRecordV1.Kind) throws -> Data {
        let recordsURL = package.appendingPathComponent("records.json")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: recordsURL))
            as? [String: Any])
        var rows = try XCTUnwrap(object["fieldDrafts"] as? [[String: Any]])
        let index = try XCTUnwrap(rows.firstIndex { ($0["kind"] as? String) == kind.rawValue })
        rows.remove(at: index)
        object["fieldDrafts"] = rows
        let recordsData = try RepetitiveCaptureSourcePackageFixture.canonicalJSONData(object)
        try recordsData.write(to: recordsURL, options: .atomic)

        let manifestURL = package.appendingPathComponent("manifest.json")
        let manifest = try BackupCanonicalDecoderV1().decodeManifest(Data(contentsOf: manifestURL))
        let entries = manifest.entries.map { entry in
            entry.path == "records.json"
                ? V4BackupEntryV1(byteCount: recordsData.count, mimeType: entry.mimeType,
                                  path: entry.path, sha256: CanonicalJSONV1.sha256(recordsData))
                : entry
        }
        let rewritten = V4BackupManifestV1(backupSchemaVersion: manifest.backupSchemaVersion,
            consumedEvaluationRootIDs: manifest.consumedEvaluationRootIDs,
            declaredPayloadByteCount: entries.reduce(0) { $0 + $1.byteCount },
            entries: entries, exportedAt: manifest.exportedAt, packs: manifest.packs,
            source: manifest.source)
        try BackupCanonicalEncoderV1().encodeManifest(rewritten).data
            .write(to: manifestURL, options: .atomic)
        return recordsData
    }

    private func assertRestoredAtomicPair(_ context: ModelContext,
                                          package: AtomicBackupPackage) throws {
        let checkpoints = try context.fetch(FetchDescriptor<FieldDraftCheckpointRow>())
        let stages = try context.fetch(FetchDescriptor<AttachmentStagingItemRow>())
        XCTAssertEqual(try checkpoints.map { try $0.value() }, [package.bundle.successorCheckpoint])
        XCTAssertEqual(try stages.map { try $0.value() }, [package.bundle.readyItem])
        XCTAssertEqual(try XCTUnwrap(checkpoints.first).value().stageIDs,
                       [try XCTUnwrap(stages.first).value().stageID])
    }

    private func incumbentConflictPayload() throws -> ReviewedDraftConflictResolutionV1 {
        let workspace = WorkspaceID(rawValue: Self.id(120))
        let key = try readyStageObserved("construct conflict MyDay key") {
            try MyDayKeyV1(workspaceID: workspace,
                civilDate: .init(year: 2026, month: 9, day: 14), ianaTimeZoneIdentifier: "UTC")
        }
        let actor = try LocalActorReferenceV1(actorReferenceID: Self.id(121),
            workspaceID: workspace, displayName: "Reviewer")
        let snapshot = try ActorSnapshotV1(snapshotID: Self.id(122), workspaceID: workspace,
            actor: actor, responsibility: .recordedBy, displayNameAtTime: "Reviewer",
            capturedAt: ReadyStageFixture.date)
        let context = try MyDayPlanningConfirmedContextV1(key: key, recordedBy: snapshot,
            keyWasExplicitlyConfirmed: true, recordedByWasExplicitlySelectedOrCaptured: true)
        let payload = try readyStageObserved("construct conflict editing payload") {
            try MyDayPlanningDraftPayloadV1(editing: context,
                intent: .plan(draft: .init(key: key, items: [], eligibleReferences: []), predecessor: nil))
        }
        func checkpoint(revision: UInt64, state: FieldDraftStateV1,
                        mutationID: MutationIDV1, at: Date) throws -> FieldDraftCheckpointV1 {
            try .init(draftID: Self.id(123), workspaceID: workspace,
                scope: MyDayPlanningDraftCodecV1.scope(for: key), purpose: .myDayPlanning,
                codec: MyDayPlanningDraftCodecV1.release(), baseCanonicalRevision: 0,
                draftRevision: revision, payloadData: MyDayPlanningDraftCodecV1.encode(payload),
                stageIDs: [], resumeAnchor: .init(sectionID: "review"), state: state,
                updatedAt: at, mutationID: mutationID)
        }
        let expected = try checkpoint(revision: 1, state: .conflicted,
            mutationID: .init(rawValue: Self.id(124)), at: ReadyStageFixture.date)
        let successor = try checkpoint(revision: 2, state: .active,
            mutationID: .init(rawValue: Self.id(125)),
            at: ReadyStageFixture.date.addingTimeInterval(1))
        return try readyStageObserved("construct reviewed conflict resolution") {
            try .init(plan: .reviewAndRebase, expectedCheckpoint: expected,
                reviewedTargetBasis: .absent(key: key, expectedWorkspaceRevision: 0),
                successorCheckpoint: successor)
        }
    }

    private static func id(_ slot: Int) -> UUID { ReadyStageFixture.id(slot) }
    private struct InjectedFailure: Error {}
}

@MainActor
private func readyStageObserved<Value>(
    _ phase: String, file: StaticString = #filePath, line: UInt = #line,
    _ operation: () throws -> Value
) rethrows -> Value {
    do { return try operation() }
    catch {
        let value = error as NSError
        XCTFail("Ready-stage failure phase=\(phase) type=\(String(reflecting: type(of: error)))"
            + " value=\(String(reflecting: error)) domain=\(value.domain) code=\(value.code)",
            file: file, line: line)
        throw error
    }
}

private extension JSONDecoder {
    static var fieldDraft: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}

private struct ReadyStageFixture {
    let workspaceID = WorkspaceID(rawValue: id(1))
    let draftID = id(2)
    let stageID = id(3)
    let publicationID: MutationIDV1
    let codec: DraftPayloadCodecReleaseV1
    let definition: DraftPurposeDefinitionV1
    let expected: FieldDraftCheckpointV1
    let ready: AttachmentStagingItemV1
    let successor: FieldDraftCheckpointV1
    let bundle: FieldDraftStagePublicationBundleV1

    init() throws {
        publicationID = try MutationIDV1(rawValue: Self.id(4))
        codec = try .init(codecID: "atomic-ready-stage.fixture", codecVersion: 1,
                          releaseSHA256: Self.digest("a"))
        definition = try .init(purpose: .inspectionReview, codec: codec,
            maximumPayloadBytes: 1_024, maximumStageItems: 8,
            targetCommandKind: .applyMyDay, retention: .explicitDiscardOnly,
            attachmentKinds: [.photo], privacyClass: .restrictedEvidence)
        expected = try .init(draftID: draftID, workspaceID: workspaceID,
            scope: .init(scopeKind: "INSPECTION_REVIEW_PHOTO", stableComponentIDs: ["asset-1"]),
            purpose: .inspectionReview, codec: codec, baseCanonicalRevision: 7,
            draftRevision: 1, payloadData: Data("payload".utf8), stageIDs: [],
            resumeAnchor: .init(sectionID: "wide_context", fieldID: "asset-1"),
            state: .active, updatedAt: Self.date,
            mutationID: .init(rawValue: Self.id(5)))
        ready = try Self.makeReady(workspaceID: workspaceID, draftID: draftID,
            stageID: stageID, mutationID: publicationID)
        successor = try .init(draftID: draftID, workspaceID: workspaceID,
            scope: expected.scope, purpose: expected.purpose, codec: expected.codec,
            baseCanonicalRevision: expected.baseCanonicalRevision, draftRevision: 2,
            payloadData: expected.payloadData, stageIDs: [stageID],
            resumeAnchor: expected.resumeAnchor, state: .active,
            lastDurableMutationID: expected.lastDurableMutationID,
            lastReceiptSHA256: expected.lastReceiptSHA256,
            updatedAt: Self.date.addingTimeInterval(1), mutationID: publicationID)
        bundle = try .init(expectedCheckpoint: expected, readyItem: ready,
                           successorCheckpoint: successor)
    }

    func publicationMutation() throws -> FieldDraftMutationV1 {
        try .init(workspaceID: workspaceID, expectedRevision: expected.draftRevision,
                  expectedBaseCanonicalRevision: expected.baseCanonicalRevision,
                  mutationID: publicationID, postImage: .publishReadyStage(bundle))
    }

    func successor(stageIDs: [UUID], mutationID: MutationIDV1,
                   payload: Data? = nil) throws -> FieldDraftCheckpointV1 {
        try .init(draftID: draftID, workspaceID: workspaceID, scope: expected.scope,
            purpose: expected.purpose, codec: expected.codec,
            baseCanonicalRevision: expected.baseCanonicalRevision, draftRevision: 2,
            payloadData: payload ?? expected.payloadData, stageIDs: stageIDs,
            resumeAnchor: expected.resumeAnchor, state: .active,
            lastDurableMutationID: expected.lastDurableMutationID,
            lastReceiptSHA256: expected.lastReceiptSHA256,
            updatedAt: Self.date.addingTimeInterval(1), mutationID: mutationID)
    }

    func readyItem(stageID: UUID? = nil, revision: UInt64 = 1,
                   state: AttachmentStagingStateV1 = .readyLocal,
                   mutationID: MutationIDV1) throws -> AttachmentStagingItemV1 {
        try Self.makeReady(workspaceID: workspaceID, draftID: draftID,
                           stageID: stageID ?? self.stageID, revision: revision,
                           state: state, mutationID: mutationID)
    }

    func divergentBundle() throws -> FieldDraftStagePublicationBundleV1 {
        let otherID = Self.id(96)
        let item = try readyItem(stageID: otherID, mutationID: publicationID)
        return try .init(expectedCheckpoint: expected, readyItem: item,
                         successorCheckpoint: successor(stageIDs: [otherID],
                                                        mutationID: publicationID))
    }

    @MainActor
    func coordinator(writer: FieldDraftLifecycleAdapterV1) throws -> FieldDraftCoordinatorV1 {
        FieldDraftCoordinatorV1(purposeAuthority: ReadyStagePurposeAuthority(definition: definition),
            writer: writer, content: ReadyStageContentPort(), target: ReadyStageTargetPort())
    }

    private static func makeReady(workspaceID: WorkspaceID, draftID: UUID, stageID: UUID,
                                  revision: UInt64 = 1,
                                  state: AttachmentStagingStateV1 = .readyLocal,
                                  mutationID: MutationIDV1) throws -> AttachmentStagingItemV1 {
        try .init(stageID: stageID, draftID: draftID, workspaceID: workspaceID,
            attachmentKind: .photo, scratchLeaseID: id(6), expectedByteCount: 4,
            actualByteCount: state == .readyLocal ? 4 : nil,
            contentDigest: state == .readyLocal ? try .init(algorithm: .sha256,
                                                            hexadecimalValue: digest("b")) : nil,
            retryClass: .none, state: state, protectionState: .available,
            revision: revision, mutationID: mutationID)
    }

    static let date = Date(timeIntervalSince1970: 1_788_134_520)
    static func id(_ slot: Int) -> UUID {
        UUID(uuidString: String(format: "b3600000-0000-4000-8000-%012x", slot))!
    }
    static func digest(_ character: Character) -> String {
        String(repeating: String(character), count: 64)
    }
}

private struct ReadyStagePurposeAuthority: DraftPurposeDefinitionResolvingV1 {
    let definition: DraftPurposeDefinitionV1
    func require(_ purpose: DraftPurposeV1,
                 codec: DraftPayloadCodecReleaseV1) throws -> DraftPurposeDefinitionV1 {
        guard purpose == definition.purpose, codec == definition.codec else {
            throw FieldDraftFailureV1.unknownCodec
        }
        return definition
    }
}

private struct ReadyStageContentPort: DraftContentPromotionPortV1 {
    func promote(plan: DraftCommitPlanV1, items: [AttachmentStagingItemV1],
                 reservationMutationIDs: [UUID: MutationIDV1]) async throws
        -> [DraftContentReservationV1] { throw FieldDraftFailureV1.invalidValue }
    func quarantine(reservations: [DraftContentReservationV1],
                    for plan: DraftDiscardPlanV1) async throws {}
}

@MainActor
private final class ReadyStageTargetPort: DraftCanonicalCommitPortV1 {
    func commit(plan: DraftCommitPlanV1,
                reservations: [DraftContentReservationV1]) throws -> MutationReceiptV1 {
        throw FieldDraftFailureV1.invalidValue
    }
    func readBackMatches(plan: DraftCommitPlanV1,
                         receipt: MutationReceiptV1) throws -> Bool { false }
}

@MainActor
private final class ReadyStageStoreNode {
    struct Session {
        let container: ModelContainer
        let context: ModelContext
        let journal: MutationJournalStoreV1
        let adapter: WorkspaceWriterAdapterV1
        let writer: WorkspaceWriterV1
        let lifecycle: FieldDraftLifecycleAdapterV1
    }
    let root: URL
    let identity: WorkspaceReplicaIdentityV1
    let generationID: UUID
    let registry: GenerationLeaseRegistryV1
    let fence: StaleWriterFenceV1
    private var bootstrap = true

    init(workspaceID: WorkspaceID) throws {
        let openedRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("V23-ready-stage-\(UUID().uuidString)", isDirectory: true)
        root = openedRoot
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        identity = try .init(workspaceID: workspaceID, replicaID: .init(rawValue: UUID()))
        generationID = UUID()
        let epoch = try GenerationEpochV1(generationID: generationID,
            generationManifestSHA256: String(repeating: "c", count: 64))
        let openedRegistry = try readyStageObserved("create ready-stage lease registry") {
            try GenerationLeaseRegistryV1(applicationSupportURL: openedRoot)
        }
        registry = openedRegistry
        let lease = try readyStageObserved("acquire ready-stage writer lease") {
            try openedRegistry.acquire(epoch: epoch, role: .writer)
        }
        fence = try readyStageObserved("create ready-stage writer fence") {
            try StaleWriterFenceV1(expectedGenerationEpoch: epoch,
                writerLeaseToken: lease, registry: openedRegistry, currentGenerationEpoch: { epoch })
        }
    }

    func withSession<T>(invalidateAtEnd: Bool = true,
                        _ body: (Session) throws -> T) throws -> T {
        try autoreleasepool {
            let schema = Schema(PersistentSchemaV53.models,
                                version: PersistentSchemaV53.versionIdentifier)
            let container = try readyStageObserved("open ready-stage model container") {
                try ModelContainer(for: schema, migrationPlan: nil,
                    configurations: [ModelConfiguration("ReadyStage", schema: schema,
                        url: root.appendingPathComponent("ready-stage.store"),
                        allowsSave: true, cloudKitDatabase: .none)])
            }
            let context = ModelContext(container)
            context.autosaveEnabled = false
            let journal = try readyStageObserved("open ready-stage journal") {
                try MutationJournalStoreV1(modelContext: context, identity: identity,
                    generationID: generationID, allowStateBootstrap: bootstrap,
                    staleWriterFence: fence)
            }
            bootstrap = false
            let writerID = UUID()
            let adapter = WorkspaceWriterAdapterV1(modelContext: context)
            let writer = try readyStageObserved("open ready-stage writer") {
                try WorkspaceWriterV1(identity: identity, generationID: generationID,
                    initialRevision: journal.currentRevision(writerInstanceID: writerID),
                    clock: ReadyStageClock(), idSource: ReadyStageIDs(value: writerID),
                    fileAuthority: ReadyStageFiles(), adapter: adapter, journalStore: journal)
            }
            defer { if invalidateAtEnd { writer.invalidate() } }
            return try readyStageObserved("execute ready-stage fixture body") {
                try body(.init(container: container, context: context, journal: journal, adapter: adapter,
                    writer: writer, lifecycle: .init(writer: writer, journal: journal,
                                                     modelContext: context)))
            }
        }
    }

    func removeClosedFiles() {
        do {
            try registry.release(fence.writerLeaseToken)
            try FileManager.default.removeItem(at: root)
        } catch { XCTFail("Atomic writer fixture cleanup failed: \(error)") }
    }
}

private struct ReadyStageClock: ApplicationClock {
    func now() -> Date { ReadyStageFixture.date.addingTimeInterval(10) }
}
private struct ReadyStageIDs: ApplicationIDSource {
    let value: UUID
    func makeID() -> UUID { value }
}
private struct ReadyStageFiles: ApplicationFileAuthorityV1 {
    func temporaryRelativePath(mutationID: MutationIDV1, component: String) throws -> String {
        "ready-stage/\(mutationID.rawValue.uuidString.lowercased())/\(component)"
    }
}

private struct AtomicBackupPackage {
    let archive: URL
    let directory: URL
    let bytes: Data
    let memberPath: String
    let bundle: FieldDraftStagePublicationBundleV1
    let receipt: MutationReceiptV1
    let identity: WorkspaceReplicaIdentityV1
    let historyRecord: MutationHistoryReceiptRecordV1
}

@MainActor
private final class BackupHarness {
    let root: URL
    let support: URL
    private var factory: StoreGenerationFactory?
    private weak var openedSession: StoreGenerationSession?
    private weak var restoredSession: StoreGenerationSession?
    var sessionsAreReleased: Bool { openedSession == nil && restoredSession == nil }

    init(name: String, identity: WorkspaceReplicaIdentityV1? = nil) throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("V23-ready-stage-backup-\(name)-\(UUID().uuidString)",
                                    isDirectory: true)
        support = root.appendingPathComponent("Application Support", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        factory = StoreGenerationFactory(applicationSupportURL: support,
                                         pointerEnrichmentIdentity: identity)
    }

    func openSession() throws -> StoreGenerationSession {
        XCTAssertTrue(sessionsAreReleased, "Cold open requires all previous store graphs released")
        let session = try XCTUnwrap(factory, "Backup harness has already been closed")
            .openOrBootstrapCurrent()
        openedSession = session
        return session
    }

    func observeRestoredSession(_ session: StoreGenerationSession) { restoredSession = session }

    func removeFiles() {
        guard sessionsAreReleased else {
            XCTFail("Atomic backup cleanup requires every store session graph to be released")
            return
        }
        factory = nil
        do { try FileManager.default.removeItem(at: root) }
        catch { XCTFail("Atomic backup cleanup failed: \(error)") }
    }
}

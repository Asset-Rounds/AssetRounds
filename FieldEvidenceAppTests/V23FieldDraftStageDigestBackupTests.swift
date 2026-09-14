import AVFoundation
import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

@MainActor
final class V23FieldDraftStageDigestBackupTests: XCTestCase {
    func testPublicPackageValidatorAcceptsNonemptyProducerStageSHA256Commit() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await makePackage(at: root, mode: .valid)
        try assertInternallyConsistentPackage(fixture)

        XCTAssertEqual(fixture.plan.stageDigests, [fixture.storedStage.stageSHA256])
        XCTAssertNotEqual(fixture.storedStage.stageSHA256,
                          fixture.storedStage.contentDigest?.hexadecimalValue)
        let validated = try BackupPackageValidatorV1().validate(stagedPackageURL: fixture.package)
        XCTAssertEqual(validated.records, fixture.records)
        XCTAssertEqual(validated.members[fixture.draftMember], fixture.bytes)
        XCTAssertEqual(validated.members[try TemporalEvidenceBackupMemberV1.original(for: fixture.clip)],
                       fixture.bytes)
        XCTAssertEqual(fixture.receipt.targetReceiptSHA256, fixture.targetReceipt.resultSHA256)
        XCTAssertEqual(fixture.receipt.consumedStageToContentID,
                       [fixture.storedStage.stageID.uuidString: fixture.clip.original.contentID])
    }

    func testContentDigestSubstitutionIsFullyRehashedButRejectedByBothProducersAndPackage() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await makePackage(at: root, mode: .contentDigestInPlan)
        try assertInternallyConsistentPackage(fixture)

        XCTAssertEqual(fixture.plan.stageDigests,
                       [try XCTUnwrap(fixture.storedStage.contentDigest).hexadecimalValue])
        XCTAssertNotEqual(fixture.plan.stageDigests, [fixture.storedStage.stageSHA256])
        XCTAssertTrue(fixture.coordinatorRejectedWrongDomain)
        XCTAssertTrue(fixture.stagingRejectedWrongDomain)
        XCTAssertThrowsError(try BackupPackageValidatorV1().validate(stagedPackageURL: fixture.package)) {
            XCTAssertEqual($0 as? BackupPackageValidationErrorV1, .invalidPackage)
        }
    }

    func testSameOriginalBytesWithDifferentCanonicalStageMetadataCannotSatisfyPlan() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await makePackage(at: root, mode: .differentStageMetadata)
        try assertInternallyConsistentPackage(fixture)

        XCTAssertEqual(fixture.storedStage.contentDigest, fixture.producerStage.contentDigest)
        XCTAssertEqual(fixture.storedStage.actualByteCount, fixture.producerStage.actualByteCount)
        XCTAssertEqual(fixture.storedStage.stageID, fixture.producerStage.stageID)
        XCTAssertNotEqual(fixture.storedStage.scratchLeaseID, fixture.producerStage.scratchLeaseID)
        XCTAssertNotEqual(fixture.storedStage.stageSHA256, fixture.producerStage.stageSHA256)
        XCTAssertEqual(fixture.plan.stageDigests, [fixture.producerStage.stageSHA256])
        XCTAssertThrowsError(try BackupPackageValidatorV1().validate(stagedPackageURL: fixture.package)) {
            XCTAssertEqual($0 as? BackupPackageValidationErrorV1, .invalidPackage)
        }
    }
}

private extension V23FieldDraftStageDigestBackupTests {
    enum Mode: Equatable { case valid, contentDigestInPlan, differentStageMetadata }

    struct PackageFixture {
        let package: URL
        let manifest: V4BackupManifestV1
        let records: V4BackupRecordsV1
        let bytes: Data
        let producerStage: AttachmentStagingItemV1
        let storedStage: AttachmentStagingItemV1
        let plan: DraftCommitPlanV1
        let receipt: DraftCommitReceiptV1
        let targetReceipt: MutationReceiptV1
        let clip: TemporalEvidenceClipV1
        let coordinatorRejectedWrongDomain: Bool
        let stagingRejectedWrongDomain: Bool

        var draftMember: String {
            "draft-staging/\(storedStage.draftID.uuidString.lowercased())/\(storedStage.stageID.uuidString.lowercased()).bin"
        }
    }

    func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("V23-field-draft-stage-digest-\(UUID().uuidString)", isDirectory: true)
    }

    func makePackage(at root: URL, mode: Mode) async throws -> PackageFixture {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let support = root.appendingPathComponent("source", isDirectory: true)
        let session = try StoreGenerationFactory(applicationSupportURL: support).openOrBootstrapCurrent()
        let now = C33TemporalEvidenceTestSupport.fixedDate
        let store = try StoreSessionCoordinator(validatingSession: session,
            clock: StageDigestClock(value: now.addingTimeInterval(5)))
        defer { XCTAssertNoThrow(try store.invalidateAndReleaseWriter()) }
        let journal = try MutationJournalStoreV1(modelContext: session.modelContext,
            identity: session.workspaceIdentity, generationID: session.generationID)
        let writer = FieldDraftLifecycleAdapterV1(writer: store.workspaceWriter, journal: journal,
            modelContext: session.modelContext)
        let submission = try StageDigestTemporalSubmission(workspaceID: session.workspaceID)
        let bytes = pcmWave()
        let wav = root.appendingPathComponent("source.wav")
        try bytes.write(to: wav)
        // The attachment is a decodable PCM WAV, not an empty or arbitrary byte sentinel.
        let audio = try AVAudioFile(forReading: wav)
        XCTAssertEqual(audio.length, 800)
        XCTAssertEqual(audio.processingFormat.sampleRate, 8_000)
        let samples = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: 800))
        try audio.read(into: samples)
        XCTAssertEqual(samples.frameLength, 800)

        let staging = try DraftAttachmentStagingAdapterV1(applicationSupportURL: support,
            workspaceID: session.workspaceID,
            immutableContentWriter: EvidenceBundleStore(generationRootURL: session.generationRootURL),
            clock: { now })
        let draftID = UUID()
        let stage = try await staging.stage(data: bytes, draftID: draftID,
            workspaceID: session.workspaceID, attachmentKind: .audio, mediaType: "audio/wav")
        XCTAssertEqual(stage.state, .readyLocal)
        let stagedBytes = try await staging.data(stageID: stage.stageID)
        XCTAssertEqual(stagedBytes, bytes)
        let storedStage: AttachmentStagingItemV1
        if mode == .differentStageMetadata { storedStage = try alteredStage(stage) }
        else { storedStage = stage }
        let purpose = try StageDigestPurposeAuthority()
        let target = StageDigestTemporalTarget(submission: submission, writer: store.workspaceWriter,
            journal: journal, context: session.modelContext)
        let coordinator = FieldDraftCoordinatorV1(purposeAuthority: purpose, writer: writer,
            content: staging, target: target)
        let active = try FieldDraftCheckpointV1(draftID: draftID, workspaceID: session.workspaceID,
            scope: .init(scopeKind: "temporal-evidence", stableComponentIDs: [submission.clipID.uuidString]),
            purpose: .evidenceCuration, codec: purpose.definition.codec, baseCanonicalRevision: 0,
            draftRevision: 1, payloadData: FieldDraftCanonicalCodecV1.encode(submission),
            stageIDs: [stage.stageID], resumeAnchor: .init(sectionID: "review"), state: .active,
            updatedAt: now, mutationID: MutationIDV1(rawValue: UUID()))
        _ = try coordinator.checkpoint(active, expectedDraftRevision: 0, expectedBaseRevision: 0)
        // The metadata-hostile corpus records its actual changed preimage in the journal.
        // It never reconstructs an earlier READY_LOCAL value from a current committed tip.
        _ = try coordinator.append(storedStage, checkpoint: active, expectedRevision: 0)
        let committing = try FieldDraftCheckpointV1(draftID: active.draftID,
            workspaceID: active.workspaceID, scope: active.scope, purpose: active.purpose,
            codec: active.codec, baseCanonicalRevision: active.baseCanonicalRevision,
            draftRevision: 2, payloadData: active.payloadData, stageIDs: active.stageIDs,
            resumeAnchor: active.resumeAnchor, state: .committing, updatedAt: now,
            mutationID: MutationIDV1(rawValue: UUID()))
        _ = try coordinator.checkpoint(committing, expectedDraftRevision: 1, expectedBaseRevision: 0)
        let correctPlan = try DraftCommitPlanV1(planID: UUID(), workspaceID: session.workspaceID,
            draftID: draftID, draftRevision: committing.draftRevision, baseCanonicalRevision: 0,
            payloadSHA256: committing.payloadSHA256, stageDigests: [stage.stageSHA256],
            targetCommandKind: .applyTemporalEvidence, expectedTargetRevision: 0,
            mutationID: MutationIDV1(rawValue: UUID()), outputKeys: [submission.clipID.uuidString])
        let plan: DraftCommitPlanV1
        if mode == .contentDigestInPlan {
            plan = try replacingDigests(correctPlan, with: [XCTUnwrap(stage.contentDigest).hexadecimalValue])
        } else {
            plan = correctPlan
        }
        let chain = try sagaChain(plan, at: now)
        let rowIDs = try DraftCommitRowMutationIDsV1(
            reservationByStageID: [stage.stageID: MutationIDV1(rawValue: UUID())],
            terminalBundleMutationID: chain[4].mutationID)
        let receiptID = UUID()
        var coordinatorRejected = false
        var stagingRejected = false
        let receipt: DraftCommitReceiptV1
        if mode == .contentDigestInPlan {
            let before = try store.workspaceWriter.currentRevision()
            do {
                _ = try await commit(coordinator, plan: plan, checkpoint: committing,
                    stage: stage, chain: chain, rowIDs: rowIDs, receiptID: receiptID, at: now)
                XCTFail("The coordinator must reject a content digest before writing a saga")
            } catch {
                XCTAssertEqual(error as? FieldDraftFailureV1, .conflictRequired)
                coordinatorRejected = (error as? FieldDraftFailureV1) == .conflictRequired
            }
            do {
                _ = try await staging.promote(plan: plan, items: [stage],
                    reservationMutationIDs: rowIDs.reservationByStageID)
                XCTFail("The real staging adapter must reject the wrong digest domain")
            } catch {
                XCTAssertEqual(error as? DraftAttachmentStagingFailureV1, .reservationMismatch)
                stagingRejected = (error as? DraftAttachmentStagingFailureV1) == .reservationMismatch
            }
            XCTAssertEqual(try store.workspaceWriter.currentRevision(), before)
            XCTAssertFalse(session.modelContext.hasChanges)
            XCTAssertNil(target.committedClip)
            let unchangedStage = try await staging.verify(stageID: stage.stageID)
            XCTAssertEqual(unchangedStage, stage)

            // Deliberately author a hostile but fully rehashed graph through the lower
            // canonical writer. The real promotion still uses its correct producer plan;
            // only the hostile reservation/plan binding is substituted afterwards. Every
            // field mutation and the real temporal target receive actual writer receipts.
            _ = try writer.append(saga: chain[0], expectedRevision: 0)
            let promoted = try await staging.promote(plan: correctPlan, items: [stage],
                reservationMutationIDs: rowIDs.reservationByStageID)
            let reservations = try promoted.map { try replacingPlan($0, with: plan.planSHA256) }
            for reservation in reservations { _ = try writer.append(reservation: reservation, expectedRevision: 0) }
            _ = try writer.append(saga: chain[1], expectedRevision: 1)
            let actualTarget = try target.commit(plan: plan, reservations: reservations)
            XCTAssertTrue(try target.readBackMatches(plan: plan, receipt: actualTarget))
            _ = try writer.append(saga: chain[2], expectedRevision: 2)
            _ = try writer.append(saga: chain[3], expectedRevision: 3)
            receipt = try terminalReceipt(plan: plan, chain: chain, reservations: reservations,
                target: actualTarget, receiptID: receiptID)
            let terminal = try terminalCheckpoint(committing, receipt: receipt, at: now.addingTimeInterval(8))
            _ = try writer.apply(commitTerminalBundle: .init(retiredSaga: chain[4],
                committedCheckpoint: terminal, receipt: receipt), expectedDraftRevision: 2, expectedSagaRevision: 4)
        } else {
            receipt = try await commit(coordinator, plan: plan, checkpoint: committing,
                stage: stage, chain: chain, rowIDs: rowIDs, receiptID: receiptID, at: now)
        }
        let clip = try XCTUnwrap(target.committedClip)
        let actualTarget = try XCTUnwrap(journal.receipt(mutationID: plan.mutationID))
        XCTAssertEqual(receipt.targetReceiptSHA256, actualTarget.resultSHA256)
        XCTAssertEqual(try XCTUnwrap(writer.currentCheckpoint(workspaceID: session.workspaceID,
            draftID: draftID)).lastReceiptSHA256, receipt.receiptSHA256)
        XCTAssertFalse(session.modelContext.hasChanges)

        let exportRoot = root.appendingPathComponent("export", isDirectory: true)
        try fm.createDirectory(at: exportRoot, withIntermediateDirectories: true)
        let exporter = BackupExportService(modelContext: session.modelContext,
            generationRootURL: session.generationRootURL,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in .max }),
            now: { now.addingTimeInterval(120) })
        let preview = try exporter.prepare()
        let archive = try exporter.export(previewID: preview.id, to: exportRoot)
        let package = root.appendingPathComponent("decoded.fieldrecordbackup", isDirectory: true)
        _ = try StreamingArchiveService().extract(archive, to: package)
        let manifest = try BackupCanonicalDecoderV1().decodeManifest(
            Data(contentsOf: package.appendingPathComponent("manifest.json")))
        let records = try BackupCanonicalDecoderV1().decodeRecords(
            Data(contentsOf: package.appendingPathComponent("records.json")))
        return PackageFixture(package: package, manifest: manifest, records: records, bytes: bytes,
            producerStage: stage, storedStage: storedStage, plan: plan, receipt: receipt,
            targetReceipt: actualTarget, clip: clip, coordinatorRejectedWrongDomain: coordinatorRejected,
            stagingRejectedWrongDomain: stagingRejected)
    }

    func commit(_ coordinator: FieldDraftCoordinatorV1, plan: DraftCommitPlanV1,
                checkpoint: FieldDraftCheckpointV1, stage: AttachmentStagingItemV1,
                chain: [DraftCommitSagaV1], rowIDs: DraftCommitRowMutationIDsV1,
                receiptID: UUID, at now: Date) async throws -> DraftCommitReceiptV1 {
        try await coordinator.commit(plan: plan, checkpoint: checkpoint, items: [stage],
            prepared: chain[0], contentPromoted: chain[1], targetCommitted: chain[2],
            retirePending: chain[3], retired: chain[4], commitReceiptID: receiptID,
            terminalCheckpointUpdatedAt: now.addingTimeInterval(8), rowMutationIDs: rowIDs)
    }

    func sagaChain(_ plan: DraftCommitPlanV1, at now: Date) throws -> [DraftCommitSagaV1] {
        let states: [DraftCommitSagaStateV1] = [.prepared, .contentPromotedUnbound,
            .targetCommitted, .draftRetirePending, .draftRetired]
        var result: [DraftCommitSagaV1] = []
        let offsets: [TimeInterval] = [0, 1, 6, 7, 8]
        for (index, state) in states.enumerated() {
            result.append(try DraftCommitSagaV1(sagaID: UUID(), workspaceID: plan.workspaceID,
                draftID: plan.draftID, plan: plan, state: state, predecessorSagaID: result.last?.sagaID,
                revision: UInt64(index + 1), mutationID: MutationIDV1(rawValue: UUID()),
                updatedAt: now.addingTimeInterval(offsets[index])))
        }
        return result
    }

    func replacingDigests(_ plan: DraftCommitPlanV1, with digests: [String]) throws -> DraftCommitPlanV1 {
        try .init(planID: plan.planID, workspaceID: plan.workspaceID, draftID: plan.draftID,
            draftRevision: plan.draftRevision, baseCanonicalRevision: plan.baseCanonicalRevision,
            payloadSHA256: plan.payloadSHA256, stageDigests: digests, targetCommandKind: plan.targetCommandKind,
            expectedTargetRevision: plan.expectedTargetRevision, mutationID: plan.mutationID, outputKeys: plan.outputKeys)
    }

    func alteredStage(_ item: AttachmentStagingItemV1) throws -> AttachmentStagingItemV1 {
        try .init(stageID: item.stageID, draftID: item.draftID, workspaceID: item.workspaceID,
            attachmentKind: item.attachmentKind, scratchLeaseID: UUID(), expectedByteCount: item.expectedByteCount,
            actualByteCount: item.actualByteCount, contentDigest: item.contentDigest,
            contentReference: item.contentReference, processingJobID: item.processingJobID,
            retryClass: item.retryClass, state: item.state, protectionState: item.protectionState,
            revision: item.revision, mutationID: item.mutationID)
    }

    func replacingPlan(_ value: DraftContentReservationV1, with digest: String) throws -> DraftContentReservationV1 {
        try .init(reservationID: value.reservationID, workspaceID: value.workspaceID, draftID: value.draftID,
            stageID: value.stageID, commitPlanSHA256: digest, mutationID: value.mutationID,
            contentDigest: value.contentDigest, locator: value.locator, createdAt: value.createdAt,
            reviewAfter: value.reviewAfter, reconciliationState: value.reconciliationState, revision: value.revision)
    }

    func terminalReceipt(plan: DraftCommitPlanV1, chain: [DraftCommitSagaV1],
                         reservations: [DraftContentReservationV1], target: MutationReceiptV1,
                         receiptID: UUID) throws -> DraftCommitReceiptV1 {
        let retired = try XCTUnwrap(chain.last)
        return try .init(receiptID: receiptID, workspaceID: plan.workspaceID, draftID: plan.draftID,
            sagaID: retired.sagaID, commitPlanSHA256: plan.planSHA256, sagaEventSHA256Chain: chain.map(\.sagaSHA256),
            targetMutationID: plan.mutationID, targetReceiptSHA256: target.resultSHA256,
            consumedStageToContentID: Dictionary(uniqueKeysWithValues: reservations.map {
                ($0.stageID.uuidString, $0.locator.contentID)
            }), committedAt: target.committedAt, mutationID: retired.mutationID)
    }

    func terminalCheckpoint(_ prior: FieldDraftCheckpointV1, receipt: DraftCommitReceiptV1,
                            at now: Date) throws -> FieldDraftCheckpointV1 {
        try .init(draftID: prior.draftID, workspaceID: prior.workspaceID, scope: prior.scope,
            purpose: prior.purpose, codec: prior.codec, baseCanonicalRevision: prior.baseCanonicalRevision,
            draftRevision: prior.draftRevision + 1, payloadData: prior.payloadData, stageIDs: prior.stageIDs,
            resumeAnchor: prior.resumeAnchor, state: .committed, lastDurableMutationID: receipt.mutationID,
            lastReceiptSHA256: receipt.receiptSHA256, updatedAt: now, mutationID: receipt.mutationID)
    }

    func assertInternallyConsistentPackage(_ fixture: PackageFixture) throws {
        let encoder = BackupCanonicalEncoderV1()
        XCTAssertEqual(try encoder.encodeManifest(fixture.manifest).data,
                       try Data(contentsOf: fixture.package.appendingPathComponent("manifest.json")))
        XCTAssertEqual(try encoder.encodeRecords(fixture.records).data,
                       try Data(contentsOf: fixture.package.appendingPathComponent("records.json")))
        XCTAssertEqual(fixture.manifest.declaredPayloadByteCount,
                       fixture.manifest.entries.reduce(0) { $0 + $1.byteCount })
        for entry in fixture.manifest.entries {
            let data = try Data(contentsOf: fixture.package.appendingPathComponent(entry.path))
            XCTAssertEqual(data.count, entry.byteCount)
            XCTAssertEqual(CanonicalJSONV1.sha256(data), entry.sha256)
        }
        XCTAssertEqual(try Data(contentsOf: fixture.package.appendingPathComponent(fixture.draftMember)), fixture.bytes)
        XCTAssertEqual(try Data(contentsOf: fixture.package.appendingPathComponent(
            TemporalEvidenceBackupMemberV1.original(for: fixture.clip))), fixture.bytes)
        let history = try XCTUnwrap(fixture.records.mutationHistory)
        try MutationJournalStoreV1.validateImportedSnapshot(history,
            sourcePersistentSchemaVersion: fixture.manifest.source.persistentSchemaVersion)
        let targetReceipts = try history.receipts.map { try MutationReceiptV1.decodeCanonical(from: $0.receiptData) }
            .filter { $0.mutationID == fixture.plan.mutationID }
        XCTAssertEqual(targetReceipts, [fixture.targetReceipt])

        let rows = fixture.records.fieldDrafts
        let checkpoint = try FieldDraftCanonicalCodecV1.decode(FieldDraftCheckpointV1.self,
            from: XCTUnwrap(rows.first { $0.kind == .checkpoint }).canonicalData)
        let stage = try FieldDraftCanonicalCodecV1.decode(AttachmentStagingItemV1.self,
            from: XCTUnwrap(rows.first { $0.kind == .stagingItem }).canonicalData)
        let receipt = try FieldDraftCanonicalCodecV1.decode(DraftCommitReceiptV1.self,
            from: XCTUnwrap(rows.first { $0.kind == .commitReceipt }).canonicalData)
        let reservation = try FieldDraftCanonicalCodecV1.decode(DraftContentReservationV1.self,
            from: XCTUnwrap(rows.first { $0.kind == .contentReservation }).canonicalData)
        let chain = try rows.filter { $0.kind == .commitSaga }.map {
            try FieldDraftCanonicalCodecV1.decode(DraftCommitSagaV1.self, from: $0.canonicalData)
        }.sorted { $0.revision < $1.revision }
        XCTAssertEqual(rows.count, 9)
        XCTAssertEqual(stage, fixture.storedStage)
        XCTAssertEqual(stage.state, .readyLocal)
        XCTAssertEqual(stage.contentDigest?.hexadecimalValue, CanonicalJSONV1.sha256(fixture.bytes))
        XCTAssertEqual(checkpoint.stageIDs, [stage.stageID])
        XCTAssertEqual(checkpoint.state, .committed)
        XCTAssertEqual(checkpoint.lastDurableMutationID, receipt.mutationID)
        XCTAssertEqual(checkpoint.lastReceiptSHA256, receipt.receiptSHA256)
        XCTAssertEqual(receipt, fixture.receipt)
        XCTAssertEqual(receipt.targetReceiptSHA256, fixture.targetReceipt.resultSHA256)
        XCTAssertEqual(chain.map(\.state), [.prepared, .contentPromotedUnbound,
            .targetCommitted, .draftRetirePending, .draftRetired])
        XCTAssertEqual(chain.map(\.revision), [1, 2, 3, 4, 5])
        XCTAssertEqual(chain.map(\.sagaSHA256), receipt.sagaEventSHA256Chain)
        XCTAssertTrue(chain.allSatisfy { $0.plan == fixture.plan })
        for (prior, next) in zip(chain, chain.dropFirst()) { try next.validateSuccessor(of: prior) }
        XCTAssertEqual(reservation.commitPlanSHA256, fixture.plan.planSHA256)
        XCTAssertEqual(reservation.contentDigest, stage.contentDigest)
        XCTAssertEqual(reservation.locator.contentID, fixture.clip.original.contentID)
        XCTAssertEqual(receipt.consumedStageToContentID,
                       [stage.stageID.uuidString: reservation.locator.contentID])
        var journalStages: [AttachmentStagingItemV1] = []
        var journalSagas: [DraftCommitSagaV1] = []
        var journalReservations: [DraftContentReservationV1] = []
        var journalTerminals: [DraftCommitTerminalBundleV1] = []
        for record in history.receipts {
            let envelope = try MutationEnvelopeV1.decodeCanonical(from: record.envelopeData)
            guard case let .applyFieldDraft(mutation) = envelope.command else { continue }
            switch mutation.postImage {
            case let .appendStagingItem(value): journalStages.append(value)
            case let .appendCommitSaga(value), let .advanceCommitSaga(value): journalSagas.append(value)
            case let .appendContentReservation(value): journalReservations.append(value)
            case let .applyCommitTerminal(value, _):
                journalTerminals.append(value)
                journalSagas.append(value.retiredSaga)
            default: break
            }
        }
        XCTAssertEqual(journalStages, [stage])
        XCTAssertEqual(journalSagas.sorted { $0.revision < $1.revision }, chain)
        XCTAssertEqual(journalReservations, [reservation])
        XCTAssertEqual(journalTerminals.count, 1)
        XCTAssertEqual(journalTerminals.first?.committedCheckpoint, checkpoint)
        XCTAssertEqual(journalTerminals.first?.receipt, receipt)
    }

    // 100ms of 8kHz mono, signed 16-bit PCM; RIFF sizes describe all 800 samples.
    func pcmWave() -> Data {
        var data = Data("RIFF".utf8)
        func append16(_ value: UInt16) { data.append(UInt8(value & 255)); data.append(UInt8(value >> 8)) }
        func append32(_ value: UInt32) {
            for shift in stride(from: 0, through: 24, by: 8) { data.append(UInt8((value >> shift) & 255)) }
        }
        append32(36 + 1_600)
        data.append(Data("WAVEfmt ".utf8))
        append32(16); append16(1); append16(1); append32(8_000); append32(16_000)
        append16(2); append16(16)
        data.append(Data("data".utf8)); append32(1_600)
        for sample in 0..<800 { append16(UInt16(bitPattern: sample % 16 < 8 ? 1_000 : -1_000)) }
        return data
    }
}

private struct StageDigestClock: ApplicationClock {
    let value: Date
    func now() -> Date { value }
}

private struct StageDigestPurposeAuthority: DraftPurposeDefinitionResolvingV1 {
    let definition: DraftPurposeDefinitionV1

    init() throws {
        let codec = try DraftPayloadCodecReleaseV1(codecID: "test.stage-digest.temporal-submission",
            codecVersion: 1, releaseSHA256: CanonicalJSONV1.sha256(Data("stage-digest-temporal-v1".utf8)))
        definition = try .init(purpose: .evidenceCuration, codec: codec,
            maximumPayloadBytes: FieldDraftLimitsV1.maximumPayloadBytes, maximumStageItems: 1,
            targetCommandKind: .applyTemporalEvidence, retention: .retireAfterCommit,
            attachmentKinds: [.audio], privacyClass: .restrictedEvidence)
    }

    func require(_ purpose: DraftPurposeV1, codec: DraftPayloadCodecReleaseV1) throws -> DraftPurposeDefinitionV1 {
        guard purpose == definition.purpose, codec == definition.codec else { throw FieldDraftFailureV1.unknownPurpose }
        return definition
    }
}

/// Test submission metadata freezes no content locator before real promotion.
private struct StageDigestTemporalSubmission: Codable {
    let clipID: UUID
    let workspaceID: WorkspaceID
    let target: TemporalEvidenceTargetV1
    let facts: TemporalEvidenceMediaFactsV1
    let profile: TemporalEvidenceLimitProfileV1
    let recordedBy: ActorSnapshotV1

    init(workspaceID: WorkspaceID) throws {
        self.workspaceID = workspaceID
        clipID = UUID()
        let base = try C33TemporalEvidenceTestSupport.profile(workspaceID: workspaceID,
            reportProjection: .typedLinkOnly, requiresTranscript: false)
        let wav = try TemporalEvidenceCodecV1(container: "wav", codec: "pcm-s16le", mediaType: "audio/wav")
        profile = try .init(profileID: base.profileID, revision: base.revision,
            packageRelease: base.packageRelease, definitionRelease: base.definitionRelease,
            audio: .init(kind: .audio, maximumDurationMilliseconds: 1_000, maximumByteCount: 8_192,
                         acceptedCodecs: [wav]), video: base.video,
            maximumClipsPerRequirement: base.maximumClipsPerRequirement,
            maximumClipsPerSession: base.maximumClipsPerSession, minimumFreeByteCount: base.minimumFreeByteCount,
            reportProjection: .typedLinkOnly, requiresAccessibleDescription: true, requiresManualTranscript: false)
        target = try C33TemporalEvidenceTestSupport.target(workspaceID: workspaceID, profile: profile)
        facts = try .init(kind: .audio, durationMilliseconds: 100, byteCount: 1_644, codec: wav)
        recordedBy = try C26SurveySessionTestSupport.actor(workspaceID: workspaceID, slot: 36_001,
            responsibility: .recordedBy)
    }
}

/// This test adapter issues the actual incumbent temporal command and reads its
/// persisted clip and journal receipt. It never manufactures a successful receipt.
@MainActor
private final class StageDigestTemporalTarget: DraftCanonicalCommitPortV1 {
    let submission: StageDigestTemporalSubmission
    let writer: WorkspaceWriterV1
    let journal: MutationJournalStoreV1
    let context: ModelContext
    private(set) var committedClip: TemporalEvidenceClipV1?

    init(submission: StageDigestTemporalSubmission, writer: WorkspaceWriterV1,
         journal: MutationJournalStoreV1, context: ModelContext) {
        self.submission = submission; self.writer = writer; self.journal = journal; self.context = context
    }

    func commit(plan: DraftCommitPlanV1, reservations: [DraftContentReservationV1]) throws -> MutationReceiptV1 {
        guard plan.workspaceID == submission.workspaceID, plan.targetCommandKind == .applyTemporalEvidence,
              plan.expectedTargetRevision == 0, plan.outputKeys == [submission.clipID.uuidString],
              plan.payloadSHA256 == FieldDraftCanonicalCodecV1.sha256(
                try FieldDraftCanonicalCodecV1.encode(submission)), reservations.count == 1,
              let reservation = reservations.first, reservation.commitPlanSHA256 == plan.planSHA256,
              reservation.workspaceID == plan.workspaceID, reservation.draftID == plan.draftID else {
            throw FieldDraftFailureV1.conflictRequired
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let original = try ContentReferenceV1(workspaceID: plan.workspaceID.rawValue.uuidString.lowercased(),
            contentID: reservation.locator.contentID, byteLength: Int64(submission.facts.byteCount),
            mediaType: submission.facts.codec.mediaType, digests: .init([reservation.contentDigest]),
            byteRole: .immutableOriginal, createdAt: formatter.string(from: reservation.createdAt))
        let clip = try TemporalEvidenceClipV1(clipID: submission.clipID, workspaceID: submission.workspaceID,
            target: submission.target, original: original,
            originalProvenance: .init(provenanceID: "stage-digest-import",
                workspaceID: original.workspaceID, contentID: original.contentID,
                contentDigest: reservation.contentDigest, origin: .localImport, recordedAt: original.createdAt),
            locator: reservation.locator, facts: submission.facts, profile: submission.profile,
            accessibleDescription: "A reviewed 100ms PCM tone used by the stage digest fixture.",
            manualTranscript: nil, recordedBy: submission.recordedBy,
            capturedAt: C33TemporalEvidenceTestSupport.fixedDate,
            acceptedAt: C33TemporalEvidenceTestSupport.fixedDate.addingTimeInterval(5),
            revision: 1, mutationID: plan.mutationID)
        let current = try writer.currentRevision()
        let expected = try C33TemporalEvidenceTestSupport.expectedRevision(for: clip,
            generationID: current.generationID, writerInstanceID: current.writerInstanceID,
            workspaceRevision: current.revision)
        _ = try writer.commitTemporalEvidence(.init(workspaceID: plan.workspaceID, expectedRevision: expected,
            mutationID: plan.mutationID, payload: .acceptClip(clip,
                review: C33TemporalEvidenceTestSupport.review(for: clip), predecessor: nil)))
        committedClip = clip
        return try XCTUnwrap(journal.receipt(mutationID: plan.mutationID))
    }

    func readBackMatches(plan: DraftCommitPlanV1, receipt: MutationReceiptV1) throws -> Bool {
        guard let clip = committedClip, clip.mutationID == plan.mutationID,
              try journal.receipt(mutationID: plan.mutationID) == receipt else { return false }
        let clips = try context.fetch(FetchDescriptor<TemporalEvidenceClipRow>()).map { try $0.value() }
        return clips.filter { $0.clipID == clip.clipID } == [clip]
    }
}

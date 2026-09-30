import Foundation
import SwiftData
import XCTest

@testable import FieldEvidenceApp

final class V23StartupMediaOwnershipReadTests: XCTestCase {
    @MainActor
    func testGenuinePhotoPhasesUseFreshCompleteOwnershipAndRejectChangedHistory() async throws {
        try await withAsyncFrozenBeginFixture("fixed-media-read", entry: .check,
            storedTimeZoneID: "America/Chicago", appDirectoryLayout: true) { h in
            let writer = h.coordinator.workspaceWriter
            let context = h.session.modelContext
            let zero = try self.assertParity(h, photoCount: 0)
            XCTAssertTrue(zero.authorities.isEmpty)
            let wide = try await FrozenProductionPhotoV1.make(h, publishRaw: false)
            _ = try self.assertParity(h, photoCount: 1)
            let input = h.root.appendingPathComponent("fixed-media-wide.png")
            try WorkCanonicalIntegrationTestSupportV1.makePNG(seed: 183).write(to: input)
            _ = try await wide.service.publishRawPhoto(parentDraftID: wide.parentID,
                childDraftID: wide.childID, sourceURL: input)
            _ = try self.assertParity(h, photoCount: 1)
            let pair = try await wide.service.preparePhotoPair(parentDraftID: wide.parentID,
                childDraftID: wide.childID)
            _ = try self.assertParity(h, photoCount: 1)
            _ = try wide.service.preparePhotoCommit(parentDraftID: wide.parentID,
                childDraftID: wide.childID, expectedCheckpointSHA256: pair.checkpointSHA256,
                proposal: wide.attempt(pairCheckpoint: pair))
            _ = try self.assertParity(h, photoCount: 1)
            _ = try await wide.service.resumePhotoCommit(parentDraftID: wide.parentID, childDraftID: wide.childID)
            XCTAssertEqual(try self.assertParity(h, photoCount: 1).photos.map(\.targetCommitted), [true])

            // A committed wide photo coexists with each pending close phase;
            // the close readers must retain their exact preceding-wide joins.
            let close = try await FrozenProductionPhotoV1.make(h, parentID: wide.parentID,
                step: .close, publishRaw: false)
            let mixed = try self.assertParity(h, photoCount: 2)
            XCTAssertEqual(mixed.photos.filter(\.targetCommitted).count, 1)
            let closeInput = h.root.appendingPathComponent("fixed-media-close.png")
            try WorkCanonicalIntegrationTestSupportV1.makePNG(seed: 184).write(to: closeInput)
            _ = try await close.service.publishRawPhoto(parentDraftID: close.parentID,
                childDraftID: close.childID, sourceURL: closeInput)
            _ = try self.assertParity(h, photoCount: 2)
            let closePair = try await close.service.preparePhotoPair(parentDraftID: close.parentID,
                childDraftID: close.childID)
            _ = try self.assertParity(h, photoCount: 2)
            _ = try close.service.preparePhotoCommit(parentDraftID: close.parentID,
                childDraftID: close.childID, expectedCheckpointSHA256: closePair.checkpointSHA256,
                proposal: close.attempt(pairCheckpoint: closePair))
            _ = try self.assertParity(h, photoCount: 2)
            _ = try await close.service.resumePhotoCommit(parentDraftID: close.parentID, childDraftID: close.childID)
            let finished = try self.assertParity(h, photoCount: 2)
            XCTAssertEqual(finished.photos.filter(\.targetCommitted).count, 2)
            let original = try writer.sourceMutationHistorySnapshot()
            let revision = try writer.currentRevision()

            // Corrupt an unrelated package/actor/Round original, not a selected
            // photo receipt. A previous successful observation cannot hide it.
            let unrelated = try XCTUnwrap(context.fetch(FetchDescriptor<MutationReceiptRow>()).first { row in
                let envelope = try MutationEnvelopeV1.decodeCanonical(from: row.envelopeData)
                if case .applyPackagePromotion = envelope.command { return true }
                return false
            })
            let originalSHA = unrelated.envelopeSHA256
            unrelated.envelopeSHA256 = String(repeating: "0", count: 64)
            try context.save()
            var incumbentError: WorkspaceMutationFailureV1?
            XCTAssertThrowsError(try writer.sourceMutationHistorySnapshot()) {
                incumbentError = $0 as? WorkspaceMutationFailureV1
            }
            XCTAssertNotNil(incumbentError)
            XCTAssertThrowsError(try writer.startupMediaOwnershipInReadScope(
                workspaceID: h.workspaceID, modelContext: context)) {
                XCTAssertEqual($0 as? WorkspaceMutationFailureV1, incumbentError)
            }
            XCTAssertEqual(unrelated.envelopeSHA256, String(repeating: "0", count: 64))
            XCTAssertFalse(context.hasChanges)
            unrelated.envelopeSHA256 = originalSHA
            try context.save()
            XCTAssertEqual(try self.assertParity(h, photoCount: 2), finished)

            let selected = try close.checkpoint()
            let selectedID = selected.mutationID.rawValue
            let receiptRow = try XCTUnwrap(context.fetch(FetchDescriptor<MutationReceiptRow>(
                predicate: #Predicate { $0.mutationID == selectedID })).first)
            let quarantine = MutationQuarantineRow(workspaceID: h.workspaceID,
                mutationID: selected.mutationID, identityDomain: .mutationEnvelope,
                acceptedIdentitySHA256: receiptRow.envelopeSHA256,
                conflictingIdentitySHA256: String(repeating: "0", count: 64), detectedAt: h.clock.now())
            context.insert(quarantine)
            try context.save()
            XCTAssertThrowsError(try writer.startupMediaOwnershipInReadScope(
                workspaceID: h.workspaceID, modelContext: context))
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<MutationQuarantineRow>()), 1)
            XCTAssertFalse(context.hasChanges)
            context.delete(quarantine)
            try context.save()
            XCTAssertEqual(try self.assertParity(h, photoCount: 2), finished)

            // A missing current terminal cannot be accepted from cached originals.
            let childID = close.childID
            let childRow = try XCTUnwrap(context.fetch(FetchDescriptor<FieldDraftCheckpointRow>(
                predicate: #Predicate { $0.draftID == childID })).first)
            context.delete(childRow)
            try context.save()
            XCTAssertThrowsError(try writer.startupMediaOwnershipInReadScope(
                workspaceID: h.workspaceID, modelContext: context))
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<FieldDraftCheckpointRow>(
                predicate: #Predicate { $0.draftID == childID })), 0)
            context.insert(try FieldDraftCheckpointRow(selected))
            try context.save()
            XCTAssertEqual(try self.assertParity(h, photoCount: 2), finished)

            // Saved ownership changes need not advance a writer revision. Fresh
            // observations still authenticate all rows instead of trusting it.
            let evidenceID = wide.intent.evidenceID
            let evidence = try XCTUnwrap(context.fetch(FetchDescriptor<EvidenceFile>(
                predicate: #Predicate { $0.id == evidenceID })).first)
            let purpose = evidence.purposeKey
            evidence.purposeKey = "hostile_changed_ownership"
            try context.save()
            XCTAssertEqual(try writer.currentRevision(), revision)
            XCTAssertThrowsError(try writer.startupMediaOwnershipInReadScope(
                workspaceID: h.workspaceID, modelContext: context))
            XCTAssertEqual(evidence.purposeKey, "hostile_changed_ownership")
            evidence.purposeKey = purpose
            try context.save()
            XCTAssertEqual(try self.assertParity(h, photoCount: 2), finished)
            XCTAssertEqual(try writer.sourceMutationHistorySnapshot(), original)
            XCTAssertFalse(context.hasChanges)
        }
    }

    @MainActor
    func testZeroPhotoReadRequiresExactContextFreshFenceAndPoisonsFailedProof() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("V23-media-read-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // All local contexts/registry/lease owners leave this synchronous scope
        // before its inert path is removed. No global FD-lifetime claim.
        defer { try? FileManager.default.removeItem(at: root) }
        try autoreleasepool {
            let identity = try WorkspaceReplicaIdentityV1(workspaceID: .init(rawValue: UUID()),
                replicaID: .init(rawValue: UUID()))
            let generationID = UUID(), instance = UUID()
            let epoch = try GenerationEpochV1(generationID: generationID,
                generationManifestSHA256: String(repeating: "a", count: 64))
            let registry = try GenerationLeaseRegistryV1(applicationSupportURL: root)
            let lease = try registry.acquire(epoch: epoch, role: .writer)
            defer { XCTAssertNoThrow(try registry.release(lease)) }
            let probe = StartupMediaReadFenceProbe()
            let fence = try StaleWriterFenceV1(expectedGenerationEpoch: epoch, writerLeaseToken: lease,
                registry: registry, currentGenerationEpoch: { try probe.read(epoch) })
            let schema = Schema(PersistentSchemaV53.models, version: PersistentSchemaV53.versionIdentifier)
            let container = try ModelContainer(for: schema, configurations: [
                ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
            let context = ModelContext(container)
            context.autosaveEnabled = false
            let journal = try MutationJournalStoreV1(modelContext: context, identity: identity,
                generationID: generationID, allowStateBootstrap: true, staleWriterFence: fence)
            let writer = try WorkspaceWriterV1(identity: identity, generationID: generationID,
                initialRevision: journal.currentRevision(writerInstanceID: instance),
                clock: StartupMediaReadClock(), idSource: StartupMediaReadIDs(instance: instance),
                fileAuthority: StartupMediaReadFiles(), adapter: WorkspaceWriterAdapterV1(modelContext: context),
                journalStore: journal)
            defer { writer.invalidate() }
            @MainActor func read(_ supplied: ModelContext? = nil) throws -> StartupMediaOwnershipSnapshotV1 {
                try writer.startupMediaOwnershipInReadScope(workspaceID: identity.workspaceID,
                    modelContext: supplied ?? context)
            }
            let start = try self.passCount(writer)
            let zero = try read()
            XCTAssertTrue(zero.photos.isEmpty)
            XCTAssertTrue(zero.authorities.isEmpty)
            XCTAssertEqual(try self.passCount(writer) - start, 1)
            XCTAssertEqual(try read(), zero)
            XCTAssertEqual(try self.passCount(writer) - start, 2)
            let history = try writer.sourceMutationHistorySnapshot()
            let wrongContext = ModelContext(container)
            try writer.withProvenLease {
                XCTAssertThrowsError(try read(wrongContext)) {
                    XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .persistenceFailed)
                }
                let afterBodyFailure = probe.reads
                XCTAssertEqual(try writer.currentRevision(), zero.revision)
                XCTAssertGreaterThan(probe.reads, afterBodyFailure)
                probe.failOnRead = probe.reads + 1
                defer { probe.failOnRead = nil }
                XCTAssertThrowsError(try writer.currentRevision()) {
                    XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .persistenceFailed)
                }
            }
            try writer.withProvenLease {
                let before = probe.reads
                XCTAssertEqual(try read(), zero)
                let boundaries = probe.reads - before
                XCTAssertGreaterThanOrEqual(boundaries, 2)
                probe.failOnRead = probe.reads + boundaries
                XCTAssertThrowsError(try read()) {
                    XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .persistenceFailed)
                }
                probe.failOnRead = probe.reads + 1
                defer { probe.failOnRead = nil }
                XCTAssertThrowsError(try writer.currentRevision()) {
                    XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .persistenceFailed)
                }
            }
            XCTAssertThrowsError(try writer.startupMediaOwnershipInReadScope(
                workspaceID: .init(rawValue: UUID()), modelContext: context)) {
                XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .wrongWorkspace)
            }
            context.insert(Site(label: "Unsaved hostile", timeZoneID: "America/Chicago"))
            XCTAssertThrowsError(try read()) {
                XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .receiptHistoryCorrupt)
            }
            XCTAssertTrue(context.hasChanges)
            context.rollback()
            XCTAssertEqual(try read(), zero)
            XCTAssertEqual(try writer.sourceMutationHistorySnapshot(), history)
            probe.staleEpoch = try GenerationEpochV1(generationID: UUID(),
                generationManifestSHA256: String(repeating: "b", count: 64))
            XCTAssertThrowsError(try read())
            probe.staleEpoch = nil
            XCTAssertEqual(try read(), zero)
            writer.invalidate()
            XCTAssertThrowsError(try read()) {
                XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .writerInvalidated)
            }
        }
    }

    @MainActor
    private func passCount(_ writer: WorkspaceWriterV1) throws -> UInt64 {
#if DEBUG
        return try XCTUnwrap(writer.fullJournalValidationPassCountForTesting)
#else
        throw StartupMediaReadTestFailure.diagnosticUnavailable
#endif
    }

    @MainActor
    private func assertParity(_ h: FrozenBeginFixture, photoCount: Int,
        file: StaticString = #filePath, line: UInt = #line) throws -> StartupMediaOwnershipSnapshotV1 {
        let writer = h.coordinator.workspaceWriter
        let before = try writer.sourceMutationHistorySnapshot()
        let expected = try incumbentOwnership(h)
        let passes = try passCount(writer)
        let actual = try writer.startupMediaOwnershipInReadScope(workspaceID: h.workspaceID,
            modelContext: h.session.modelContext)
        XCTAssertEqual(try passCount(writer) - passes, 1, file: file, line: line)
        XCTAssertEqual(actual, expected, file: file, line: line)
        XCTAssertEqual(actual.photos.count, photoCount, file: file, line: line)
        XCTAssertEqual(try writer.sourceMutationHistorySnapshot(), before, file: file, line: line)
        XCTAssertFalse(h.session.modelContext.hasChanges, file: file, line: line)
        return actual
    }

    /// Independent parity oracle: the incumbent per-photo public readers and
    /// complete physical census, before changing the application to a fixed read.
    @MainActor
    private func incumbentOwnership(_ h: FrozenBeginFixture) throws -> StartupMediaOwnershipSnapshotV1 {
        let context = h.session.modelContext, writer = h.coordinator.workspaceWriter
        let revision = try writer.currentRevision()
        let authorities = try context.fetch(FetchDescriptor<EvidenceFile>()).map {
            EvidenceBundleAuthority(schemaVersion: $0.schemaVersion, id: $0.id, recordID: $0.recordID,
                purposeKey: $0.purposeKey, relativePath: $0.relativePath, mimeType: $0.mimeType,
                byteCount: $0.byteCount, sha256: $0.sha256, thumbnailRelativePath: $0.thumbnailRelativePath,
                thumbnailByteCount: $0.thumbnailByteCount, thumbnailSHA256: $0.thumbnailSHA256)
        }.sorted { $0.id.uuidString < $1.id.uuidString }
        let checkpoints = try context.fetch(FetchDescriptor<FieldDraftCheckpointRow>()).map { try $0.value() }
            .filter { $0.codec.codecID == CheckRunnerPhotoDraftCodecV1.codecID }
            .sorted { $0.draftID.uuidString < $1.draftID.uuidString }
        let photos: [StartupMediaPhotoOwnershipV1] = try checkpoints.map { checkpoint in
            let payload = try CheckRunnerPhotoDraftCodecV1.validateCheckpoint(checkpoint)
            let committed: Bool
            if checkpoint.state == .committed {
                let value = try XCTUnwrap(writer.checkRunnerPhotoCurrentTargetEvidence(workspaceID: h.workspaceID,
                    parentDraftID: payload.parentDraftID, childDraftID: checkpoint.draftID))
                guard case let .applyCommitTerminal(bundle, _) = value.parent.child.terminal.mutation.postImage,
                      bundle.committedCheckpoint == checkpoint else { throw StartupMediaReadTestFailure.invalidFixture }
                committed = true
            } else {
                switch payload.phase {
                case .awaitingRawStage, .rawReady:
                    let value = try XCTUnwrap(writer.checkRunnerPhotoRawStageEvidence(workspaceID: h.workspaceID,
                        parentDraftID: payload.parentDraftID, childDraftID: checkpoint.draftID))
                    XCTAssertEqual(value.currentCheckpoint, checkpoint)
                    committed = false
                case .pairReady, .preparedCommit:
                    let value = try XCTUnwrap(writer.checkRunnerPhotoContinuationEvidence(workspaceID: h.workspaceID,
                        parentDraftID: payload.parentDraftID, childDraftID: checkpoint.draftID))
                    XCTAssertEqual(value.checkpoint, checkpoint)
                    committed = value.target != nil
                }
            }
            return .init(checkpoint: checkpoint, payload: payload, targetCommitted: committed)
        }
        XCTAssertEqual(try writer.currentRevision(), revision)
        return .init(revision: revision, authorities: authorities, photos: photos)
    }
}

private enum StartupMediaReadTestFailure: Error { case diagnosticUnavailable, invalidFixture, unavailableEpoch }
@MainActor private final class StartupMediaReadFenceProbe {
    var reads = 0
    var failOnRead: Int?
    var staleEpoch: GenerationEpochV1?
    func read(_ epoch: GenerationEpochV1) throws -> GenerationEpochV1 {
        reads += 1
        if reads == failOnRead { throw StartupMediaReadTestFailure.unavailableEpoch }
        return staleEpoch ?? epoch
    }
}
private struct StartupMediaReadClock: ApplicationClock {
    func now() -> Date { Date(timeIntervalSince1970: 1_800_000_000) }
}
private struct StartupMediaReadIDs: ApplicationIDSource { let instance: UUID; func makeID() -> UUID { instance } }
private struct StartupMediaReadFiles: ApplicationFileAuthorityV1 {
    func temporaryRelativePath(mutationID: MutationIDV1, component: String) throws -> String {
        "startup-media-test/\(mutationID.rawValue.uuidString.lowercased())/\(component)"
    }
}

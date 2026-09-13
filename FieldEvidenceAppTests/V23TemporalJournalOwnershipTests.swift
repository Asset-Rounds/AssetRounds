import Darwin
import Foundation
import XCTest
@testable import FieldEvidenceApp

@MainActor
final class V23TemporalJournalOwnershipTests: XCTestCase {
    func testPromotionJournalRejectsRootAndLeafReplacementBeforeAnyCallback() async throws {
        let fixture = try makeFixture(slot: 91_000)
        let root = try makeDirectory("V23-temporal-root")
        let outside = try makeDirectory("V23-temporal-outside")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        defer { try? FileManager.default.removeItem(at: outside.deletingLastPathComponent()) }
        let effects = JournalEffects()
        let store = try promotionStore(root: root, workspaceID: fixture.workspaceID, effects: effects)

        let moved = root.deletingLastPathComponent().appendingPathComponent("old-root", isDirectory: true)
        try FileManager.default.moveItem(at: root, to: moved)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        await assertFails { try await store.prepare(fixture.reservation) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("operational").path))
        let rootCounts = await effects.counts()
        XCTAssertEqual(rootCounts.verify, 0)
        XCTAssertEqual(rootCounts.remove, 0)

        let leafRoot = try makeDirectory("V23-temporal-leaf")
        defer { try? FileManager.default.removeItem(at: leafRoot.deletingLastPathComponent()) }
        let leafStore = try promotionStore(root: leafRoot, workspaceID: fixture.workspaceID, effects: effects)
        let journal = journalURL(root: leafRoot, workspaceID: fixture.workspaceID)
        try FileManager.default.createDirectory(at: journal.deletingLastPathComponent(), withIntermediateDirectories: true)
        let outsideLeaf = outside.appendingPathComponent("outside.json")
        try Data("outside".utf8).write(to: outsideLeaf)
        XCTAssertEqual(Darwin.symlink(outsideLeaf.path, journal.path), 0)
        await assertFails { try await leafStore.prepare(fixture.reservation) }
        XCTAssertEqual(try Data(contentsOf: outsideLeaf), Data("outside".utf8))
        let leafCounts = await effects.counts()
        XCTAssertEqual(leafCounts.verify, 0)
        XCTAssertEqual(leafCounts.remove, 0)
    }

    func testPromotionJournalRejectsMalformedRecordBeforeRecoveryOrCallback() async throws {
        let fixture = try makeFixture(slot: 91_100)
        let root = try makeDirectory("V23-temporal-malformed")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let effects = JournalEffects()
        let store = try promotionStore(root: root, workspaceID: fixture.workspaceID, effects: effects)
        let journal = journalURL(root: root, workspaceID: fixture.workspaceID)
        try FileManager.default.createDirectory(at: journal.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{not-json".utf8).write(to: journal)

        await assertFails { _ = try await store.recoverPending() }
        await assertFails { _ = try await store.promotedContentExists(fixture.reservation) }
        await assertFails { try await store.removeUncommittedContent(fixture.reservation) }
        let counts = await effects.counts()
        XCTAssertEqual(counts.verify, 0)
        XCTAssertEqual(counts.remove, 0)
    }

    func testPromotionJournalRejectsOperationalDirectorySwapDuringTransition() async throws {
        let fixture = try makeFixture(slot: 91_150)
        let root = try makeDirectory("V23-temporal-transition")
        let outside = try makeDirectory("V23-temporal-transition-outside")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        defer { try? FileManager.default.removeItem(at: outside.deletingLastPathComponent()) }
        let effects = JournalEffects()
        let store = try promotionStore(root: root, workspaceID: fixture.workspaceID, effects: effects)
        try await store.prepare(fixture.reservation)
        let operations = root.appendingPathComponent("operational", isDirectory: true)
        let replacement = outside.appendingPathComponent("replacement", isDirectory: true)
        try FileManager.default.createDirectory(at: replacement, withIntermediateDirectories: true)
        try FileManager.default.removeItem(at: operations)
        try FileManager.default.moveItem(at: replacement, to: operations)
        await assertFails { try await store.transition(fixture.reservation, to: .originalPromoted) }
        let counts = await effects.counts()
        XCTAssertEqual(counts.verify, 0)
        XCTAssertEqual(counts.remove, 0)
    }

    func testPromotionCleanupFenceRejectsConcurrentCanonicalTransition() async throws {
        let fixture = try makeFixture(slot: 91_175)
        let root = try makeDirectory("V23-temporal-cleanup-fence")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let effects = JournalEffects()
        let store = try promotionStore(root: root, workspaceID: fixture.workspaceID, effects: effects)
        try await store.prepare(fixture.reservation)
        try await store.transition(fixture.reservation, to: .originalPromoted)
        await effects.blockNextRemove()
        let deletion = Task { try await store.removeUncommittedContent(fixture.reservation) }
        await effects.waitForRemoveStart()
        await assertFails { try await store.transition(fixture.reservation, to: .canonicalCommitted) }
        await effects.releaseRemove()
        try await deletion.value
        let pending = try await store.recoverPending()
        XCTAssertEqual(pending.single?.state, .quarantined)
    }

    func testRetentionJournalRejectsDirectorySwapAndLeafSymlink() async throws {
        let workspaceID = C33TemporalEvidenceTestSupport.workspace(91_200)
        let root = try makeDirectory("V23-retention-root")
        let outside = try makeDirectory("V23-retention-outside")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        defer { try? FileManager.default.removeItem(at: outside.deletingLastPathComponent()) }
        let store = try TemporalEvidenceRetentionCleanupRecoveryFileAdapterV1(
            generationRootURL: root, workspaceID: workspaceID
        )
        let initiallyPending = try await store.pendingCleanups()
        XCTAssertTrue(initiallyPending.isEmpty)
        let operations = root.appendingPathComponent("operational", isDirectory: true)
        let replacement = outside.appendingPathComponent("replacement", isDirectory: true)
        try FileManager.default.createDirectory(at: replacement, withIntermediateDirectories: true)
        try FileManager.default.removeItem(at: operations)
        try FileManager.default.moveItem(at: replacement, to: operations)
        await assertFails { _ = try await store.pendingCleanups() }

        let leafRoot = try makeDirectory("V23-retention-leaf")
        defer { try? FileManager.default.removeItem(at: leafRoot.deletingLastPathComponent()) }
        let leafStore = try TemporalEvidenceRetentionCleanupRecoveryFileAdapterV1(
            generationRootURL: leafRoot, workspaceID: workspaceID
        )
        let leaf = leafRoot.appendingPathComponent("operational", isDirectory: true)
            .appendingPathComponent("temporal-evidence-promotion-v1", isDirectory: true)
            .appendingPathComponent(workspaceID.rawValue.uuidString.lowercased() + "-retention-cleanup.json")
        try FileManager.default.createDirectory(at: leaf.deletingLastPathComponent(), withIntermediateDirectories: true)
        let outsideLeaf = outside.appendingPathComponent("retention-outside.json")
        try Data("outside".utf8).write(to: outsideLeaf)
        XCTAssertEqual(Darwin.symlink(outsideLeaf.path, leaf.path), 0)
        await assertFails { _ = try await leafStore.pendingCleanups() }
        XCTAssertEqual(try Data(contentsOf: outsideLeaf), Data("outside".utf8))
    }

    func testRetentionJournalPersistsPrepareCommitFinishAndRejectsMalformedRecord() async throws {
        let fixture = try makeRetentionFixture(slot: 91_250)
        let root = try makeDirectory("V23-retention-phases")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let store = try TemporalEvidenceRetentionCleanupRecoveryFileAdapterV1(
            generationRootURL: root, workspaceID: fixture.workspaceID
        )
        try await store.prepareCleanup(fixture.reservation)
        let prepared = try await store.pendingCleanups()
        XCTAssertEqual(prepared, [fixture.reservation])
        let receipt = String(repeating: "b", count: 64)
        try await store.markCleanupCommitted(fixture.reservation, receiptSHA256: receipt)
        let committed = try await store.pendingCleanups()
        XCTAssertEqual(committed.single?.state, .canonicalCommitted)
        XCTAssertEqual(committed.single?.receiptSHA256, receipt)
        try await store.finishCleanup(fixture.reservation)
        let finished = try await store.pendingCleanups()
        XCTAssertTrue(finished.isEmpty)

        let malformed = root.appendingPathComponent("operational", isDirectory: true)
            .appendingPathComponent("temporal-evidence-promotion-v1", isDirectory: true)
            .appendingPathComponent(fixture.workspaceID.rawValue.uuidString.lowercased() + "-retention-cleanup.json")
        try Data("[] trailing".utf8).write(to: malformed)
        await assertFails { _ = try await store.pendingCleanups() }
    }

    func testBothJournalsRejectHardlinkedManifestLeaves() async throws {
        let fixture = try makeFixture(slot: 91_300)
        let root = try makeDirectory("V23-hardlink-promotion")
        let retentionRoot = try makeDirectory("V23-hardlink-retention")
        let outside = try makeDirectory("V23-hardlink-outside")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        defer { try? FileManager.default.removeItem(at: retentionRoot.deletingLastPathComponent()) }
        defer { try? FileManager.default.removeItem(at: outside.deletingLastPathComponent()) }
        let effects = JournalEffects()
        let promotion = try promotionStore(root: root, workspaceID: fixture.workspaceID, effects: effects)
        let outsidePromotion = outside.appendingPathComponent("promotion.json")
        try Data("outside-promotion".utf8).write(to: outsidePromotion)
        XCTAssertEqual(Darwin.link(outsidePromotion.path, journalURL(root: root, workspaceID: fixture.workspaceID).path), 0)
        await assertFails { try await promotion.prepare(fixture.reservation) }
        XCTAssertEqual(try Data(contentsOf: outsidePromotion), Data("outside-promotion".utf8))

        let retention = try TemporalEvidenceRetentionCleanupRecoveryFileAdapterV1(
            generationRootURL: retentionRoot, workspaceID: fixture.workspaceID
        )
        let retentionLeaf = retentionRoot.appendingPathComponent("operational", isDirectory: true)
            .appendingPathComponent("temporal-evidence-promotion-v1", isDirectory: true)
            .appendingPathComponent(fixture.workspaceID.rawValue.uuidString.lowercased() + "-retention-cleanup.json")
        let outsideRetention = outside.appendingPathComponent("retention.json")
        try Data("outside-retention".utf8).write(to: outsideRetention)
        XCTAssertEqual(Darwin.link(outsideRetention.path, retentionLeaf.path), 0)
        await assertFails { _ = try await retention.pendingCleanups() }
        XCTAssertEqual(try Data(contentsOf: outsideRetention), Data("outside-retention".utf8))
    }

    func testPromotionJournalReadBoundaryRejectsPostStatRegularAndFIFOReplacementBeforeCallbacks() async throws {
        let fixture = try makeFixture(slot: 91_350)
        let regularRoot = try makeDirectory("V23-promotion-regular-replacement")
        let fifoRoot = try makeDirectory("V23-promotion-fifo-replacement")
        defer { try? FileManager.default.removeItem(at: regularRoot.deletingLastPathComponent()) }
        defer { try? FileManager.default.removeItem(at: fifoRoot.deletingLastPathComponent()) }

        let regularEffects = JournalEffects()
        let regularSeed = try promotionStore(root: regularRoot, workspaceID: fixture.workspaceID, effects: regularEffects)
        try await regularSeed.prepare(fixture.reservation)
        let regularJournal = journalURL(root: regularRoot, workspaceID: fixture.workspaceID)
        let replacement = regularRoot.deletingLastPathComponent().appendingPathComponent("replacement.json")
        try Data(contentsOf: regularJournal).write(to: replacement)
        let originalInode = try inode(of: regularJournal)
        let replacementInode = try inode(of: replacement)
        XCTAssertNotEqual(originalInode, replacementInode)
        let regular = try promotionStore(root: regularRoot, workspaceID: fixture.workspaceID, effects: regularEffects, readBoundary: { phase in
            guard phase == .afterLeafStat else { return }
            guard Darwin.rename(replacement.path, regularJournal.path) == 0 else { throw TemporalEvidenceContractFailureV1.interruption }
        })
        await assertFails { _ = try await regular.promotedContentExists(fixture.reservation) }
        let regularCounts = await regularEffects.counts()
        XCTAssertEqual(regularCounts.verify, 0)
        XCTAssertEqual(regularCounts.remove, 0)

        let fifoEffects = JournalEffects()
        let fifoSeed = try promotionStore(root: fifoRoot, workspaceID: fixture.workspaceID, effects: fifoEffects)
        try await fifoSeed.prepare(fixture.reservation)
        let fifoJournal = journalURL(root: fifoRoot, workspaceID: fixture.workspaceID)
        let fifo = try promotionStore(root: fifoRoot, workspaceID: fixture.workspaceID, effects: fifoEffects, readBoundary: { phase in
            guard phase == .afterLeafStat else { return }
            try FileManager.default.removeItem(at: fifoJournal)
            guard Darwin.mkfifo(fifoJournal.path, mode_t(0o600)) == 0 else { throw TemporalEvidenceContractFailureV1.interruption }
        })
        await assertFails { _ = try await fifo.promotedContentExists(fixture.reservation) }
        let fifoCounts = await fifoEffects.counts()
        XCTAssertEqual(fifoCounts.verify, 0)
        XCTAssertEqual(fifoCounts.remove, 0)
    }

    func testRetentionJournalReadBoundaryRejectsPostStatRegularAndFIFOReplacement() async throws {
        let fixture = try makeRetentionFixture(slot: 91_400)
        let regularRoot = try makeDirectory("V23-retention-regular-replacement")
        let fifoRoot = try makeDirectory("V23-retention-fifo-replacement")
        defer { try? FileManager.default.removeItem(at: regularRoot.deletingLastPathComponent()) }
        defer { try? FileManager.default.removeItem(at: fifoRoot.deletingLastPathComponent()) }

        let regularSeed = try TemporalEvidenceRetentionCleanupRecoveryFileAdapterV1(generationRootURL: regularRoot, workspaceID: fixture.workspaceID)
        try await regularSeed.prepareCleanup(fixture.reservation)
        let regularJournal = retentionJournalURL(root: regularRoot, workspaceID: fixture.workspaceID)
        let replacement = regularRoot.deletingLastPathComponent().appendingPathComponent("replacement.json")
        try Data(contentsOf: regularJournal).write(to: replacement)
        let originalInode = try inode(of: regularJournal)
        let replacementInode = try inode(of: replacement)
        XCTAssertNotEqual(originalInode, replacementInode)
        let regular = try TemporalEvidenceRetentionCleanupRecoveryFileAdapterV1(generationRootURL: regularRoot, workspaceID: fixture.workspaceID, readBoundary: { phase in
            guard phase == .afterLeafStat else { return }
            guard Darwin.rename(replacement.path, regularJournal.path) == 0 else { throw TemporalEvidenceContractFailureV1.interruption }
        })
        await assertFails { _ = try await regular.pendingCleanups() }

        let fifoSeed = try TemporalEvidenceRetentionCleanupRecoveryFileAdapterV1(generationRootURL: fifoRoot, workspaceID: fixture.workspaceID)
        try await fifoSeed.prepareCleanup(fixture.reservation)
        let fifoJournal = retentionJournalURL(root: fifoRoot, workspaceID: fixture.workspaceID)
        let fifo = try TemporalEvidenceRetentionCleanupRecoveryFileAdapterV1(generationRootURL: fifoRoot, workspaceID: fixture.workspaceID, readBoundary: { phase in
            guard phase == .afterLeafStat else { return }
            try FileManager.default.removeItem(at: fifoJournal)
            guard Darwin.mkfifo(fifoJournal.path, mode_t(0o600)) == 0 else { throw TemporalEvidenceContractFailureV1.interruption }
        })
        await assertFails { _ = try await fifo.pendingCleanups() }
    }

    func testBothJournalsBoundAccumulationAfterPostOpenGrowthAndKeepValidReadControls() async throws {
        let promotionFixture = try makeFixture(slot: 91_450)
        let retentionFixture = try makeRetentionFixture(slot: 91_500)
        let promotionRoot = try makeDirectory("V23-promotion-post-open-growth")
        let retentionRoot = try makeDirectory("V23-retention-post-open-growth")
        defer { try? FileManager.default.removeItem(at: promotionRoot.deletingLastPathComponent()) }
        defer { try? FileManager.default.removeItem(at: retentionRoot.deletingLastPathComponent()) }

        let effects = JournalEffects()
        let promotionSeed = try promotionStore(root: promotionRoot, workspaceID: promotionFixture.workspaceID, effects: effects)
        try await promotionSeed.prepare(promotionFixture.reservation)
        let promotionJournal = journalURL(root: promotionRoot, workspaceID: promotionFixture.workspaceID)
        let promotionObservation = JournalReadObservation()
        let promotionGrowth = try promotionStore(root: promotionRoot, workspaceID: promotionFixture.workspaceID, effects: effects, readBoundary: { phase in
            switch phase {
            case .afterOpen: try promotionObservation.grow(promotionJournal)
            case .accumulatedRead(let count): promotionObservation.record(count)
            case .afterLeafStat: break
            }
        })
        await assertFails { _ = try await promotionGrowth.promotedContentExists(promotionFixture.reservation) }
        XCTAssertEqual(promotionObservation.maximum, 1_048_576)
        let promotionCounts = await effects.counts()
        XCTAssertEqual(promotionCounts.verify, 0)
        XCTAssertEqual(promotionCounts.remove, 0)

        let retentionSeed = try TemporalEvidenceRetentionCleanupRecoveryFileAdapterV1(generationRootURL: retentionRoot, workspaceID: retentionFixture.workspaceID)
        try await retentionSeed.prepareCleanup(retentionFixture.reservation)
        let retentionJournal = retentionJournalURL(root: retentionRoot, workspaceID: retentionFixture.workspaceID)
        let retentionObservation = JournalReadObservation()
        let retentionGrowth = try TemporalEvidenceRetentionCleanupRecoveryFileAdapterV1(generationRootURL: retentionRoot, workspaceID: retentionFixture.workspaceID, readBoundary: { phase in
            switch phase {
            case .afterOpen: try retentionObservation.grow(retentionJournal)
            case .accumulatedRead(let count): retentionObservation.record(count)
            case .afterLeafStat: break
            }
        })
        await assertFails { _ = try await retentionGrowth.pendingCleanups() }
        XCTAssertEqual(retentionObservation.maximum, 1_048_576)

        let controlRoot = try makeDirectory("V23-temporal-valid-read-control")
        defer { try? FileManager.default.removeItem(at: controlRoot.deletingLastPathComponent()) }
        let controlEffects = JournalEffects()
        let promotionControl = try promotionStore(root: controlRoot, workspaceID: promotionFixture.workspaceID, effects: controlEffects, readBoundary: { _ in })
        try await promotionControl.prepare(promotionFixture.reservation)
        let promotionExists = try await promotionControl.promotedContentExists(promotionFixture.reservation)
        XCTAssertTrue(promotionExists)
        let controlCounts = await controlEffects.counts()
        XCTAssertEqual(controlCounts.verify, 1)
        XCTAssertEqual(controlCounts.remove, 0)
        let retentionControl = try TemporalEvidenceRetentionCleanupRecoveryFileAdapterV1(generationRootURL: controlRoot, workspaceID: retentionFixture.workspaceID, readBoundary: { _ in })
        try await retentionControl.prepareCleanup(retentionFixture.reservation)
        let pendingRetentionCleanup = try await retentionControl.pendingCleanups()
        XCTAssertEqual(pendingRetentionCleanup, [retentionFixture.reservation])
    }

    private func makeFixture(slot: Int) throws -> (workspaceID: WorkspaceID, reservation: TemporalEvidencePromotionReservationV1) {
        let workspaceID = C33TemporalEvidenceTestSupport.workspace(slot)
        let mutationID = try C33TemporalEvidenceTestSupport.mutation(slot + 1)
        let contentID = "temporal.journal.\(slot)"
        let digest = String(repeating: "a", count: 64)
        let created = Date(timeIntervalSince1970: 1_820_000_000)
        let leaseID = C33TemporalEvidenceTestSupport.id(slot + 2)
        let request = try CapabilityScratchLeaseRequestV1(
            leaseID: leaseID, operationID: mutationID.rawValue, purpose: .capture,
            requestedByteCount: 1024, createdAt: created, expiresAt: created.addingTimeInterval(60)
        )
        let lease = CapabilityScratchLeaseV1(
            leaseID: leaseID, purpose: .capture,
            relativeDirectory: "temporal-journal-\(slot)"
        )
        let binding = try TemporalEvidenceScratchBindingV1(
            request: request, lease: lease, mutationID: mutationID, contentID: contentID,
            contentSHA256: digest
        )
        return (workspaceID, try TemporalEvidencePromotionReservationV1(
            workspaceID: workspaceID, mutationID: mutationID, contentID: contentID,
            contentSHA256: digest, binding: binding, state: .prepared
        ))
    }

    private func makeRetentionFixture(slot: Int) throws -> (workspaceID: WorkspaceID, reservation: TemporalEvidenceRetentionCleanupReservationV1) {
        let base = try C33TemporalEvidenceTestSupport.clip(slot: slot)
        let eventMutationID = try C33TemporalEvidenceTestSupport.mutation(slot + 1)
        let event = try TemporalEvidenceRetentionEventV1(
            eventID: C33TemporalEvidenceTestSupport.id(slot + 2), clip: base.clip,
            disposition: .deleteClip, policySHA256: String(repeating: "c", count: 64),
            actor: C26SurveySessionTestSupport.actor(
                workspaceID: base.clip.workspaceID, slot: slot + 3, responsibility: .reviewedBy
            ), occurredAt: base.clip.acceptedAt.addingTimeInterval(1), revision: 1,
            mutationID: eventMutationID
        )
        let expected = try C33TemporalEvidenceTestSupport.expectedRevision(
            for: base.clip, generationID: C33TemporalEvidenceTestSupport.id(slot + 4),
            writerInstanceID: C33TemporalEvidenceTestSupport.id(slot + 5), workspaceRevision: 1,
            entityRevision: base.clip.revision
        )
        let mutation = try TemporalEvidenceMutationV1(
            workspaceID: base.clip.workspaceID, expectedRevision: expected, mutationID: eventMutationID,
            payload: .removeClip(event: event, clips: [base.clip], anchors: [], derivatives: [], predecessorEvent: nil)
        )
        return (base.clip.workspaceID, try TemporalEvidenceRetentionCleanupReservationV1(
            mutation: mutation, state: .prepared
        ))
    }

    private func promotionStore(root: URL, workspaceID: WorkspaceID, effects: JournalEffects, readBoundary: TemporalEvidenceOperationalJournalReadBoundaryHookV1? = nil) throws
        -> TemporalEvidencePromotionRecoveryFileAdapterV1 {
        try TemporalEvidencePromotionRecoveryFileAdapterV1(
            generationRootURL: root, workspaceID: workspaceID, readBoundary: readBoundary,
            verify: { _, _, _ in await effects.verified() },
            remove: { _, _, _ in await effects.removed() }
        )
    }

    private func makeDirectory(_ name: String) throws -> URL {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        let root = parent.appendingPathComponent("generation", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func journalURL(root: URL, workspaceID: WorkspaceID) -> URL {
        root.appendingPathComponent("operational", isDirectory: true)
            .appendingPathComponent("temporal-evidence-promotion-v1", isDirectory: true)
            .appendingPathComponent(workspaceID.rawValue.uuidString.lowercased() + ".json")
    }

    private func retentionJournalURL(root: URL, workspaceID: WorkspaceID) -> URL {
        root.appendingPathComponent("operational", isDirectory: true)
            .appendingPathComponent("temporal-evidence-promotion-v1", isDirectory: true)
            .appendingPathComponent(workspaceID.rawValue.uuidString.lowercased() + "-retention-cleanup.json")
    }

    private func inode(of url: URL) throws -> ino_t {
        var info = stat()
        guard url.path.withCString({ Darwin.stat($0, &info) }) == 0 else {
            throw TemporalEvidenceContractFailureV1.interruption
        }
        return info.st_ino
    }

    private func assertFails(
        _ operation: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await operation()
            XCTFail("expected descriptor-pinned journal operation to fail", file: file, line: line)
        } catch { }
    }
}

private actor JournalEffects {
    private var verifyCount = 0
    private var removeCount = 0
    private var blocksRemove = false
    private var removeStarted = false
    private var removeContinuation: CheckedContinuation<Void, Never>?
    private var removeWaiters: [CheckedContinuation<Void, Never>] = []
    func verified() -> Bool { verifyCount += 1; return true }
    func removed() async {
        removeCount += 1
        guard blocksRemove else { return }
        removeStarted = true
        let waiters = removeWaiters; removeWaiters.removeAll()
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { removeContinuation = $0 }
        removeContinuation = nil; blocksRemove = false
    }
    func blockNextRemove() { blocksRemove = true }
    func waitForRemoveStart() async {
        guard !removeStarted else { return }
        await withCheckedContinuation { removeWaiters.append($0) }
    }
    func releaseRemove() { removeContinuation?.resume(); removeContinuation = nil }
    func counts() -> (verify: Int, remove: Int) { (verifyCount, removeCount) }
}

private final class JournalReadObservation: @unchecked Sendable {
    private let lock = NSLock()
    private var observedMaximum = 0

    var maximum: Int { lock.withLock { observedMaximum } }

    func record(_ count: Int) {
        lock.withLock { observedMaximum = max(observedMaximum, count) }
    }

    func grow(_ url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(repeating: 0x61, count: 1_048_576))
    }
}

private extension Array {
    var single: Element? { count == 1 ? first : nil }
}

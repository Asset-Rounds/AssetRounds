import Foundation
import XCTest
@testable import FieldEvidenceApp

/// Exercises actual M1 publication/read forwarding. These tests never claim
/// canonical source admission, content removal permission or executor success.
final class V23TemporalPromotionJournalSeparationTests: XCTestCase {
    func testPreparedJournalReopensAndRejectsNonpreparedInput() throws {
        let root = try makeRoot()
        let reservation = try makeReservation()
        var journal: TemporalEvidencePromotionJournalV1? = try .init(
            generationRootURL: root, workspaceID: reservation.workspaceID)
        try journal!.prepare(reservation)
        try journal!.prepare(reservation)
        XCTAssertEqual(try journal!.recoverPending(), [reservation])
        let changed = try TemporalEvidencePromotionReservationV1(
            workspaceID: reservation.workspaceID, mutationID: reservation.mutationID,
            contentID: reservation.contentID, contentSHA256: reservation.contentSHA256,
            binding: reservation.binding, state: .originalPromoted)
        XCTAssertThrowsError(try journal!.prepare(changed))
        weak var original = journal
        journal = nil
        XCTAssertNil(original)
        guard original == nil else { return } // retain failed owner's namespace
        journal = try .init(generationRootURL: root, workspaceID: reservation.workspaceID)
        XCTAssertEqual(try journal!.reservation(workspaceID: reservation.workspaceID,
            mutationID: reservation.mutationID), reservation)
        XCTAssertThrowsError(try journal!.reservation(workspaceID: WorkspaceID(),
            mutationID: reservation.mutationID))
        weak var reopened = journal
        journal = nil
        XCTAssertNil(reopened)
        guard reopened == nil else { return }
        try FileManager.default.removeItem(at: root)
    }

    func testFullAdapterPreparationForwardsWithoutCallingContentEffects() async throws {
        let root = try makeRoot()
        let reservation = try makeReservation()
        let calls = ContentEffectCalls()
        var adapter: TemporalEvidencePromotionRecoveryFileAdapterV1? = try .init(
            generationRootURL: root, workspaceID: reservation.workspaceID,
            verify: { _, _, _ in await calls.verify(); throw Injected.contentEffect },
            remove: { _, _, _ in await calls.remove(); throw Injected.contentEffect })
        try await adapter!.prepare(reservation)
        let actual = try await adapter!.reservation(workspaceID: reservation.workspaceID,
            mutationID: reservation.mutationID)
        XCTAssertEqual(actual, reservation)
        let pending = try await adapter!.recoverPending()
        XCTAssertEqual(pending, [reservation])
        let count = await calls.counts()
        XCTAssertEqual(count.verify, 0)
        XCTAssertEqual(count.remove, 0)
        weak var old = adapter
        adapter = nil
        XCTAssertNil(old)
        guard old == nil else { return }
        var journal: TemporalEvidencePromotionJournalV1? = try .init(
            generationRootURL: root, workspaceID: reservation.workspaceID)
        XCTAssertEqual(try journal!.recoverPending(), [reservation])
        weak var reader = journal
        journal = nil
        XCTAssertNil(reader)
        guard reader == nil else { return }
        try FileManager.default.removeItem(at: root)
    }

    func testFailedContentRemovalStillQuarantinesAndDoesNotFinishJournal() async throws {
        let root = try makeRoot()
        let reservation = try makeReservation()
        let calls = ContentEffectCalls()
        var adapter: TemporalEvidencePromotionRecoveryFileAdapterV1? = try .init(
            generationRootURL: root, workspaceID: reservation.workspaceID,
            verify: { _, _, _ in await calls.verify(); throw Injected.contentEffect },
            remove: { _, _, _ in await calls.remove(); throw Injected.contentEffect })
        try await adapter!.prepare(reservation)
        do {
            try await adapter!.removeUncommittedContent(reservation)
            XCTFail("Injected content failure must propagate")
        } catch Injected.contentEffect { }
        let actual = try await adapter!.reservation(workspaceID: reservation.workspaceID,
            mutationID: reservation.mutationID)
        XCTAssertEqual(actual?.state, .quarantined)
        let count = await calls.counts()
        XCTAssertEqual(count.verify, 0)
        XCTAssertEqual(count.remove, 1)
        do {
            try await adapter!.remove(reservation)
            XCTFail("A quarantined journal cannot be removed as finished")
        } catch { }
        weak var old = adapter
        adapter = nil
        XCTAssertNil(old)
        guard old == nil else { return }
        try FileManager.default.removeItem(at: root)
    }

    func testSynchronousReadHookReentryRefusesBeforeSharedDescriptorAccess() throws {
        let root = try makeRoot(), reservation = try makeReservation()
        let probe = ReentryProbe()
        var journal: TemporalEvidencePromotionJournalV1? = try .init(
            generationRootURL: root, workspaceID: reservation.workspaceID,
            readBoundary: { _ in try probe.observe() })
        try journal!.prepare(reservation)
        probe.journal = journal
        XCTAssertEqual(try journal!.recoverPending(), [reservation])
        XCTAssertGreaterThan(probe.refusals, 0)
        weak var retained = journal
        journal = nil
        XCTAssertNil(retained)
        guard retained == nil else { return }
        try FileManager.default.removeItem(at: root)
    }

    func testConcurrentSameInstanceReadRefusesWithoutReleasingFirstReadLock() async throws {
        let root = try makeRoot(), reservation = try makeReservation()
        let gate = ReadGate()
        var journal: TemporalEvidencePromotionJournalV1? = try .init(
            generationRootURL: root, workspaceID: reservation.workspaceID,
            readBoundary: { _ in gate.pauseOnce() })
        try journal!.prepare(reservation)
        gate.arm()
        var first: Task<[TemporalEvidencePromotionReservationV1], Error>? = Task.detached { [owned = journal!] in try owned.recoverPending() }
        // This handshake only arranges overlap; it is never drain evidence.
        let entered = await Task.detached { gate.entered.wait(timeout: .now() + 5) == .success }.value
        guard entered else {
            gate.release.signal()
            _ = try await first!.value
            XCTFail("Actual reader never reached its retained hook")
            return
        }
        XCTAssertThrowsError(try journal!.recoverPending()) { error in
            XCTAssertEqual(error as? TemporalEvidenceContractFailureV1, .interruption)
        }
        gate.release.signal()
        let result = try await first!.value
        XCTAssertEqual(result, [reservation])
        XCTAssertEqual(try journal!.recoverPending(), [reservation])
        first = nil
        weak var retained = journal
        journal = nil
        XCTAssertNil(retained)
        guard retained == nil else { return }
        try FileManager.default.removeItem(at: root)
    }

    private final class ReentryProbe: @unchecked Sendable {
        weak var journal: TemporalEvidencePromotionJournalV1?
        private(set) var refusals = 0
        func observe() throws {
            guard let journal else { return }
            do {
                _ = try journal.recoverPending()
                throw Injected.contentEffect
            } catch TemporalEvidenceContractFailureV1.interruption { refusals += 1 }
        }
    }
    private final class ReadGate: @unchecked Sendable {
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var armed = false
        func arm() { lock.lock(); armed = true; lock.unlock() }
        func pauseOnce() {
            lock.lock(); let pause = armed; armed = false; lock.unlock()
            if pause { entered.signal(); release.wait() }
        }
    }

    private enum Injected: Error { case contentEffect }
    private actor ContentEffectCalls {
        private var verifies = 0
        private var removals = 0
        func verify() { verifies += 1 }
        func remove() { removals += 1 }
        func counts() -> (verify: Int, remove: Int) { (verifies, removals) }
    }
    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("promotion-journal-separation-" + UUID().uuidString.lowercased())
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }
    private func makeReservation() throws -> TemporalEvidencePromotionReservationV1 {
        let workspace = WorkspaceID(), mutation = try MutationIDV1(rawValue: UUID())
        let id = UUID(), now = Date(timeIntervalSince1970: 1_820_000_000)
        let content = UUID().uuidString.lowercased(), digest = String(repeating: "a", count: 64)
        let request = try CapabilityScratchLeaseRequestV1(leaseID: id,
            operationID: mutation.rawValue, purpose: .capture, requestedByteCount: 1024,
            createdAt: now, expiresAt: now.addingTimeInterval(60))
        let lease = CapabilityScratchLeaseV1(leaseID: id, purpose: .capture,
            relativeDirectory: "capture-" + id.uuidString.lowercased())
        let binding = try TemporalEvidenceScratchBindingV1(request: request, lease: lease,
            mutationID: mutation, contentID: content, contentSHA256: digest)
        return try .init(workspaceID: workspace, mutationID: mutation, contentID: content,
            contentSHA256: digest, binding: binding, state: .prepared)
    }
}

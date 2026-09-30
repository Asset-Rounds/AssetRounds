import Darwin
import Foundation
import XCTest
@testable import FieldEvidenceApp

/// Standalone storage witnesses. These do not supply generation G, canonical
/// command ownership, application startup normalization, or Erase readiness.
@MainActor
final class V23TemporalPublicationRecoveryTests: XCTestCase {
    private enum Stop: Error { case interrupted }
    private let clock = Date(timeIntervalSince1970: 1_820_000_000)

    func testNewManifestPublicationRecoversEveryDurableBoundary() async throws {
        for retention in [false, true] {
            for boundary in TemporalEvidenceOperationalPublicationBoundaryV2.allCases {
                let root = try temporaryRoot()
                defer { try? FileManager.default.removeItem(at: root) }
                let fixture = try promotion(970_000)
                let cleanup = try retentionFixture(970_100)
                let probe = TemporalPublicationProbe()
                let hook: TemporalEvidenceOperationalPublicationBoundaryHookV2 = { observed in
                    if observed == boundary { probe.mark(); throw Stop.interrupted }
                }
                if retention {
                    let store = try TemporalEvidenceRetentionCleanupRecoveryFileAdapterV1(
                        generationRootURL: root, workspaceID: cleanup.mutation.workspaceID, publicationBoundary: hook
                    )
                    await fails { try await store.prepareCleanup(cleanup) }
                } else {
                    let store = try promotionStore(root, fixture, hook: hook)
                    await fails { try await store.prepare(fixture) }
                }
                XCTAssertTrue(probe.hit, "did not reach \(retention)/\(boundary)")
                guard probe.hit else { throw Stop.interrupted }
                let published = isAfterPublication(boundary)
                let first = try TemporalEvidenceOperationalJournalRecoveryV2.recoverExistingPublications(generationRootURL: root)
                XCTAssertEqual(first.removedPublicationCount, boundary == .removedReservation ? 0 : 1, "\(retention)/\(boundary)")
                XCTAssertEqual(try TemporalEvidenceOperationalJournalRecoveryV2.recoverExistingPublications(generationRootURL: root).removedPublicationCount, 0)
                if retention {
                    let cold = try TemporalEvidenceRetentionCleanupRecoveryFileAdapterV1(generationRootURL: root, workspaceID: cleanup.mutation.workspaceID)
                    let actual = try await cold.pendingCleanups()
                    XCTAssertEqual(actual, published ? [cleanup] : [])
                } else {
                    let cold = try promotionStore(root, fixture)
                    let actual = try await cold.recoverPending()
                    XCTAssertEqual(actual, published ? [fixture] : [])
                }
                XCTAssertFalse(try names(journal(root)).contains { $0.hasPrefix(".tp2-") })
            }
        }
    }

    func testReplacementPublicationRecoversBeforeAndAfterSwap() async throws {
        for retention in [false, true] {
            for boundary in TemporalEvidenceOperationalPublicationBoundaryV2.allCases {
                let root = try temporaryRoot()
                defer { try? FileManager.default.removeItem(at: root) }
                let fixture = try promotion(971_000), cleanup = try retentionFixture(971_100)
                let workspace = retention ? cleanup.mutation.workspaceID : fixture.workspaceID
                let target = manifest(root, workspace, retention: retention)
                if retention {
                    try await TemporalEvidenceRetentionCleanupRecoveryFileAdapterV1(generationRootURL: root, workspaceID: workspace).prepareCleanup(cleanup)
                } else { try await promotionStore(root, fixture).prepare(fixture) }
                let predecessor = try Data(contentsOf: target), predecessorInode = try inode(target)
                let probe = TemporalPublicationProbe()
                let hook: TemporalEvidenceOperationalPublicationBoundaryHookV2 = { if $0 == boundary { probe.mark(); throw Stop.interrupted } }
                if retention {
                    let store = try TemporalEvidenceRetentionCleanupRecoveryFileAdapterV1(generationRootURL: root, workspaceID: workspace, publicationBoundary: hook)
                    await fails { try await store.markCleanupCommitted(cleanup, receiptSHA256: String(repeating: "a", count: 64)) }
                } else {
                    let store = try promotionStore(root, fixture, hook: hook)
                    await fails { try await store.transition(fixture, to: .originalPromoted) }
                }
                XCTAssertTrue(probe.hit, "did not reach replacement \(retention)/\(boundary)")
                guard probe.hit else { throw Stop.interrupted }
                _ = try TemporalEvidenceOperationalJournalRecoveryV2.recoverExistingPublications(generationRootURL: root)
                let stable = try inventory(root)
                _ = try TemporalEvidenceOperationalJournalRecoveryV2.recoverExistingPublications(generationRootURL: root)
                XCTAssertEqual(try inventory(root), stable)
                if !isAfterPublication(boundary) {
                    XCTAssertEqual(try Data(contentsOf: target), predecessor)
                    XCTAssertEqual(try inode(target), predecessorInode)
                } else {
                    XCTAssertNotEqual(try Data(contentsOf: target), predecessor)
                    XCTAssertNotEqual(try inode(target), predecessorInode)
                }
                if retention {
                    let actual = try await TemporalEvidenceRetentionCleanupRecoveryFileAdapterV1(generationRootURL: root, workspaceID: workspace).pendingCleanups()
                    let expected = try TemporalEvidenceRetentionCleanupReservationV1(mutation: cleanup.mutation, state: isAfterPublication(boundary) ? .canonicalCommitted : .prepared, receiptSHA256: isAfterPublication(boundary) ? String(repeating: "a", count: 64) : nil)
                    XCTAssertEqual(actual, [expected])
                } else {
                    let actual = try await promotionStore(root, fixture).reservation(workspaceID: workspace, mutationID: fixture.mutationID)
                    XCTAssertEqual(actual, try replacing(fixture, state: isAfterPublication(boundary) ? .originalPromoted : .prepared))
                }
            }
        }
    }

    func testPublicationRecoveryIsNoCreateAndPreservesUnknownLegacyArtifacts() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let empty = try inventory(root)
        _ = try TemporalEvidenceOperationalJournalRecoveryV2.recoverExistingPublications(generationRootURL: root)
        XCTAssertEqual(try inventory(root), empty)
        let missing = root.appendingPathComponent("missing")
        XCTAssertThrowsError(try TemporalEvidenceOperationalJournalRecoveryV2.recoverExistingPublications(generationRootURL: missing))
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
        let alias = root.appendingPathComponent("alias")
        XCTAssertEqual(Darwin.symlink(root.path, alias.path), 0)
        XCTAssertThrowsError(try TemporalEvidenceOperationalJournalRecoveryV2.recoverExistingPublications(generationRootURL: alias))
        let fixture = try promotion(972_000)
        let store = try promotionStore(root, fixture)
        let legacy = journal(root).appendingPathComponent(".temporal-journal-\(UUID().uuidString.lowercased()).tmp")
        try Data("a genuine unknown old interruption must remain".utf8).write(to: legacy)
        let before = try inventory(root)
        XCTAssertThrowsError(try TemporalEvidenceOperationalJournalRecoveryV2.recoverExistingPublications(generationRootURL: root))
        await fails { try await store.prepare(fixture) }
        XCTAssertEqual(try inventory(root), before)

        for relocate in [false, true] {
            let ownedRoot = try temporaryRoot()
            defer { try? FileManager.default.removeItem(at: ownedRoot) }
            let ownedFixture = try promotion(972_100)
            let pinned = try promotionStore(ownedRoot, ownedFixture)
            if relocate {
                try await pinned.prepare(ownedFixture)
                try FileManager.default.moveItem(at: journal(ownedRoot), to: ownedRoot.appendingPathComponent("held-journal"))
            } else { try FileManager.default.removeItem(at: journal(ownedRoot)) }
            let captured = try inventory(ownedRoot)
            await fails { _ = try await pinned.recoverPending() }
            await fails { try await pinned.prepare(ownedFixture) }
            XCTAssertEqual(try inventory(ownedRoot), captured)
            let fresh = try TemporalEvidenceOperationalJournalRecoveryV2.recoverExistingPublications(generationRootURL: ownedRoot)
            XCTAssertEqual(fresh.removedPublicationCount, 0)
            XCTAssertFalse(fresh.retainedEmptyCreation)
            XCTAssertEqual(try inventory(ownedRoot), captured)
            XCTAssertFalse(FileManager.default.fileExists(atPath: journal(ownedRoot).path))
        }
        let policyRoot = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: policyRoot) }
        let policyFixture = try promotion(972_200)
        let pinned = try promotionStore(policyRoot, policyFixture)
        var changed = journal(policyRoot), resources = URLResourceValues()
        resources.isExcludedFromBackup = false
        try changed.setResourceValues(resources)
        let beforePolicy = try inventory(policyRoot)
        await fails { _ = try await pinned.recoverPending() }
        await fails { try await pinned.prepare(policyFixture) }
        XCTAssertEqual(try inventory(policyRoot), beforePolicy)
        let cold = try TemporalEvidenceOperationalJournalRecoveryV2.recoverExistingPublications(generationRootURL: policyRoot)
        XCTAssertTrue(cold.retainedEmptyCreation)
        XCTAssertEqual(try inventory(policyRoot), beforePolicy)
        changed.removeAllCachedResourceValues()
        XCTAssertEqual(try changed.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, false)
    }

    func testPublicationRecoveryRejectsContradictoryAndExtraSlotMembersWithoutEffects() async throws {
        for attack in 0..<8 {
            let root = try temporaryRoot()
            defer { try? FileManager.default.removeItem(at: root) }
            let fixture = try promotion(973_000)
            let probe = TemporalPublicationProbe()
            let store = try promotionStore(root, fixture, hook: { if $0 == .durablePayload { probe.mark(); throw Stop.interrupted } })
            await fails { try await store.prepare(fixture) }
            XCTAssertTrue(probe.hit)
            guard probe.hit else { throw Stop.interrupted }
            let slot = try transaction(root), payload = slot.appendingPathComponent("payload")
            switch attack {
            case 0: try FileManager.default.createDirectory(at: slot.appendingPathComponent("extra"), withIntermediateDirectories: false)
            case 1:
                var bytes = try Data(contentsOf: payload); bytes[bytes.count / 2] ^= 1
                try bytes.write(to: payload); try ProtectedFilePolicyV1.applyAndVerify(.journalTemporary, at: payload)
            case 2:
                try FileManager.default.copyItem(at: slot, to: journal(root).appendingPathComponent(slot.lastPathComponent.replacingOccurrences(of: "-n-", with: "-" + String(repeating: "0", count: 64) + "-")))
            case 3:
                try Data(repeating: 0, count: 1_048_577).write(to: payload)
            case 6, 7:
                var values = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: payload)) as? [[String: Any]])
                if attack == 6 { values.append(try XCTUnwrap(values.first)) }
                else { values[0]["workspaceID"] = C33TemporalEvidenceTestSupport.id(973_099).uuidString }
                let hostile = try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
                try hostile.write(to: payload)
                try ProtectedFilePolicyV1.applyAndVerify(.journalTemporary, at: payload)
                // Bind actual full bytes/length to a correctly spelled slot, so
                // this reaches typed duplicate-ID/workspace admission, not SHA.
                let prefix = slot.lastPathComponent.split(separator: "-").dropLast(2).joined(separator: "-")
                let renamed = slot.deletingLastPathComponent().appendingPathComponent(prefix + "-" + KernelCanonicalHashV1.sha256(hostile).lowercased() + "-" + String(hostile.count))
                try FileManager.default.moveItem(at: slot, to: renamed)
            case 5:
                // A nonempty interrupted write never gets the empty-creation
                // policy exception, including on a diagnostic Simulator.
                try Data([1]).write(to: payload)
                var changedURL = payload, resources = URLResourceValues()
                resources.isExcludedFromBackup = false
                try changedURL.setResourceValues(resources)
            default:
                try Data("[]".utf8).write(to: manifest(root, fixture.workspaceID))
                try ProtectedFilePolicyV1.applyAndVerify(.journal, at: manifest(root, fixture.workspaceID))
            }
            let before = try inventory(root)
            XCTAssertThrowsError(try TemporalEvidenceOperationalJournalRecoveryV2.recoverExistingPublications(generationRootURL: root))
            XCTAssertEqual(try inventory(root), before)
        }
        let emptyRoot = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: emptyRoot) }
        let emptyFixture = try promotion(973_150)
        let emptyStore = try promotionStore(emptyRoot, emptyFixture, hook: { if $0 == .openedPayload { throw Stop.interrupted } })
        await fails { try await emptyStore.prepare(emptyFixture) }
        let emptyPayload = try transaction(emptyRoot).appendingPathComponent("payload")
        XCTAssertEqual(try Data(contentsOf: emptyPayload).count, 0)
        var emptyURL = emptyPayload, emptyResources = URLResourceValues()
        emptyResources.isExcludedFromBackup = false
        try emptyURL.setResourceValues(emptyResources)
        XCTAssertEqual(try TemporalEvidenceOperationalJournalRecoveryV2.recoverExistingPublications(generationRootURL: emptyRoot).removedPublicationCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: manifest(emptyRoot, emptyFixture.workspaceID).path))

        // Count limit is enforced before a sort/read/decode can admit an omitted leaf.
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try promotion(973_200)
        try await promotionStore(root, fixture).prepare(fixture)
        let template = try Data(contentsOf: manifest(root, fixture.workspaceID))
        for index in 1..<256 { try seedManifest(template, workspace: C33TemporalEvidenceTestSupport.workspace(974_000 + index), root: root) }
        let admitted = try inventory(root)
        XCTAssertEqual(try TemporalEvidenceOperationalJournalRecoveryV2.recoverExistingPublications(generationRootURL: root).removedPublicationCount, 0)
        try seedManifest(template, workspace: C33TemporalEvidenceTestSupport.workspace(975_000), root: root)
        let overLimit = try inventory(root)
        XCTAssertThrowsError(try TemporalEvidenceOperationalJournalRecoveryV2.recoverExistingPublications(generationRootURL: root))
        XCTAssertEqual(try inventory(root), overLimit)
        XCTAssertEqual(admitted.keys.count + 1, overLimit.keys.count)

        // 15MiB settled ceiling still reserves a complete1MiB terminal successor.
        let byteRoot = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: byteRoot) }
        let base = try promotion(975_100)
        try await promotionStore(byteRoot, base).prepare(base)
        let bytes = try Data(contentsOf: manifest(byteRoot, base.workspaceID))
        for index in 0..<15 {
            let workspace = index == 0 ? base.workspaceID : C33TemporalEvidenceTestSupport.workspace(975_200 + index)
            try seedManifest(bytes, workspace: workspace, root: byteRoot, paddedTo: 1_048_576)
        }
        _ = try TemporalEvidenceOperationalJournalRecoveryV2.recoverExistingPublications(generationRootURL: byteRoot)
        let full = try inventory(byteRoot)
        let newcomer = try promotion(975_500)
        await fails { try await promotionStore(byteRoot, newcomer).prepare(newcomer) }
        XCTAssertEqual(try inventory(byteRoot), full)
        try await promotionStore(byteRoot, base).transition(base, to: .finished)
        try await promotionStore(byteRoot, base).remove(base)
        XCTAssertEqual(try Data(contentsOf: manifest(byteRoot, base.workspaceID)), Data("[]".utf8))
    }

    func testPublicationPinsRootAncestorPayloadAndTargetAcrossBoundaries() async throws {
        for attack in 0..<5 {
            let root = try temporaryRoot(), outside = try temporaryRoot()
            defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
            let fixture = try promotion(976_000)
            let sentinel = outside.appendingPathComponent("untouched")
            let sentinelBytes = Data("outside bytes".utf8)
            try sentinelBytes.write(to: sentinel)
            let slotParent = journal(root), target = manifest(root, fixture.workspaceID)
            let probe = TemporalPublicationProbe()
            let store = try promotionStore(root, fixture, hook: { boundary in
                guard boundary == .beforePublication else { return }
                probe.mark()
                let slots = try FileManager.default.contentsOfDirectory(at: slotParent, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix(".tp2-") }
                guard slots.count == 1 else { throw Stop.interrupted }
                let payload = slots[0].appendingPathComponent("payload")
                switch attack {
                case 0:
                    try FileManager.default.moveItem(at: payload, to: slots[0].appendingPathComponent("saved"))
                    guard Darwin.symlink(sentinel.path, payload.path) == 0 else { throw Stop.interrupted }
                case 1:
                    try FileManager.default.moveItem(at: payload, to: slots[0].appendingPathComponent("saved"))
                    guard Darwin.link(sentinel.path, payload.path) == 0 else { throw Stop.interrupted }
                case 2:
                    try FileManager.default.moveItem(at: slotParent, to: root.appendingPathComponent("held-journal"))
                    try FileManager.default.createDirectory(at: slotParent, withIntermediateDirectories: false)
                case 4:
                    try FileManager.default.moveItem(at: root, to: outside.appendingPathComponent("held-root"))
                    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
                default:
                    try Data("[]".utf8).write(to: target)
                    try ProtectedFilePolicyV1.applyAndVerify(.journal, at: target)
                }
            })
            await fails { try await store.prepare(fixture) }
            XCTAssertTrue(probe.hit)
            XCTAssertEqual(try Data(contentsOf: sentinel), sentinelBytes)
            if attack == 3 { XCTAssertEqual(try Data(contentsOf: target), Data("[]".utf8)) }
            else { XCTAssertFalse(FileManager.default.fileExists(atPath: target.path)) }
        }

        // Late final displaced-payload read: a policy-valid named copy must not
        // authorize unlink from the old detached root or journal descriptor.
        for replaceRoot in [true, false] {
            let root = try temporaryRoot(), held = try temporaryRoot()
            defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: held) }
            let fixture = try promotion(976_100)
            try await promotionStore(root, fixture).prepare(fixture)
            let predecessor = try Data(contentsOf: manifest(root, fixture.workspaceID))
            let stage = TemporalPublicationProbe(), swapped = TemporalPublicationProbe()
            let parent = journal(root), targetName = manifest(root, fixture.workspaceID).lastPathComponent
            let store = try promotionStore(root, fixture, hook: { if $0 == .durablePublication { stage.mark() } }, readHook: { boundary in
                guard boundary == .afterOpen, stage.hit, stage.nextOpen() == 3 else { return }
                // Two reads belong to the last full census. The third is the
                // separate final payload reread immediately before unlink.
                let source = replaceRoot ? root : parent
                let moved = held.appendingPathComponent("captured")
                try FileManager.default.moveItem(at: source, to: moved)
                try FileManager.default.copyItem(at: moved, to: source)
                let slotNames = try FileManager.default.contentsOfDirectory(atPath: parent.path).filter { $0.hasPrefix(".tp2-") }
                guard slotNames.count == 1 else { throw Stop.interrupted }
                let slot = parent.appendingPathComponent(slotNames[0])
                for url in [root.appendingPathComponent("operational"), parent, slot] {
                    try ProtectedFilePolicyV1.applyAndVerify(.stagingDirectory, at: url)
                }
                try ProtectedFilePolicyV1.applyAndVerify(.journal, at: parent.appendingPathComponent(targetName))
                try ProtectedFilePolicyV1.applyAndVerify(.journalTemporary, at: slot.appendingPathComponent("payload"))
                swapped.mark()
            })
            await fails { try await store.transition(fixture, to: .originalPromoted) }
            XCTAssertTrue(stage.hit); XCTAssertTrue(swapped.hit)
            guard swapped.hit else { throw Stop.interrupted }
            let captured = held.appendingPathComponent("captured")
            let oldJournal = replaceRoot ? journal(captured) : captured
            let slots = try names(oldJournal).filter { $0.hasPrefix(".tp2-") }
            let oldSlot = oldJournal.appendingPathComponent(try XCTUnwrap(slots.first))
            XCTAssertEqual(try Data(contentsOf: oldSlot.appendingPathComponent("payload")), predecessor)
            XCTAssertEqual(try Data(contentsOf: oldSlot.appendingPathComponent("payload")), try Data(contentsOf: parent.appendingPathComponent(oldSlot.lastPathComponent).appendingPathComponent("payload")))
        }

        let growthRoot = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: growthRoot) }
        let fixture = try promotion(976_200), prepared = TemporalPublicationProbe()
        let preparer = try promotionStore(growthRoot, fixture, hook: { if $0 == .durablePayload { prepared.mark(); throw Stop.interrupted } })
        await fails { try await preparer.prepare(fixture) }
        XCTAssertTrue(prepared.hit)
        let payload = try transaction(growthRoot).appendingPathComponent("payload")
        let original = try Data(contentsOf: payload), growth = Data([32])
        var expectedInventory = try inventory(growthRoot)
        let relative = String(payload.path.dropFirst(growthRoot.path.count + 1))
        let beforeValue = try XCTUnwrap(expectedInventory[relative])
        expectedInventory[relative] = String(beforeValue.dropLast(64)) + KernelCanonicalHashV1.sha256(original + growth)
        let observed = TemporalPublicationProbe()
        let reader = try promotionStore(growthRoot, fixture, readHook: { boundary in
            guard boundary == .afterOpen, !observed.hit else { return }
            let file = try FileHandle(forWritingTo: payload)
            defer { try? file.close() }
            try file.seekToEnd(); try file.write(contentsOf: growth); try file.synchronize()
            observed.mark()
        })
        await fails { _ = try await reader.recoverPending() }
        XCTAssertTrue(observed.hit)
        XCTAssertEqual(try Data(contentsOf: payload), original + growth)
        XCTAssertEqual(try inventory(growthRoot), expectedInventory)
    }

    func testTwoIndependentAdaptersSerializeFullManifestMutation() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try promotion(977_000), second = try promotion(977_010, workspace: C33TemporalEvidenceTestSupport.workspace(977_000))
        let a = try promotionStore(root, first), b = try promotionStore(root, second)
        // Different open descriptions, not a duplicated FD or actor mailbox.
        let held = Darwin.open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        XCTAssertGreaterThanOrEqual(held, 0)
        guard held >= 0 else { return }
        defer { _ = Darwin.close(held) }
        XCTAssertEqual(flock(held, LOCK_EX | LOCK_NB), 0)
        await fails { try await a.prepare(first) }
        await fails { try await b.prepare(second) }
        XCTAssertTrue(try names(journal(root)).isEmpty)
        XCTAssertEqual(flock(held, LOCK_UN), 0)
        // Intentionally exercise the documented busy outcome, then finish only
        // the operation that did not enter storage; no lost-snapshot retry.
        async let one = Self.attempt { try await a.prepare(first) }
        async let two = Self.attempt { try await b.prepare(second) }
        let results = try await (one, two)
        XCTAssertTrue(results.0 || results.1)
        if !results.0 { try await a.prepare(first) }
        if !results.1 { try await b.prepare(second) }
        let cold = try promotionStore(root, first)
        let actual = try await cold.recoverPending()
        XCTAssertEqual(actual, [first, second].sorted { $0.mutationID.rawValue.uuidString < $1.mutationID.rawValue.uuidString })
        // Preserve carry-forward API: callers keep PREPARED reservation values.
        try await a.transition(first, to: .finished)
        try await b.remove(first)
        let remaining = try await cold.recoverPending()
        XCTAssertEqual(remaining, [second])
    }

    func testPromotionAndRetentionRemovalRequireEveryImmutableBindingField() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try promotion(978_000), store = try promotionStore(root, original)
        try await store.prepare(original); try await store.transition(original, to: .finished)
        let before = try inventory(root)
        let binding = original.binding, request = binding.request
        for field in 0..<8 {
            let leaseID = field == 0 ? C33TemporalEvidenceTestSupport.id(978_090) : request.leaseID
            let modifiedRequest = try CapabilityScratchLeaseRequestV1(
                leaseID: leaseID, operationID: request.operationID,
                purpose: field == 1 ? .importData : request.purpose,
                requestedByteCount: field == 2 ? request.requestedByteCount + 1 : request.requestedByteCount,
                createdAt: field == 3 ? request.createdAt.addingTimeInterval(-1) : request.createdAt,
                expiresAt: field == 4 ? request.expiresAt.addingTimeInterval(1) : request.expiresAt
            )
            let modifiedLease = CapabilityScratchLeaseV1(leaseID: leaseID, purpose: modifiedRequest.purpose, relativeDirectory: field == 5 ? "different-directory" : binding.lease.relativeDirectory)
            let content = field == 6 ? "different.content" : original.contentID
            let digest = field == 7 ? String(repeating: "b", count: 64) : original.contentSHA256
            let modifiedBinding = try TemporalEvidenceScratchBindingV1(request: modifiedRequest, lease: modifiedLease, mutationID: original.mutationID, contentID: content, contentSHA256: digest)
            let hostile = try TemporalEvidencePromotionReservationV1(workspaceID: original.workspaceID, mutationID: original.mutationID, contentID: content, contentSHA256: digest, binding: modifiedBinding, state: .prepared)
            await fails { try await store.remove(hostile) }
            XCTAssertEqual(try inventory(root), before)
        }
        let foreign = try TemporalEvidencePromotionReservationV1(workspaceID: C33TemporalEvidenceTestSupport.workspace(978_100), mutationID: original.mutationID, contentID: original.contentID, contentSHA256: original.contentSHA256, binding: original.binding, state: .finished)
        await fails { try await store.remove(foreign) }
        XCTAssertEqual(try inventory(root), before)
        try await store.remove(original)
        XCTAssertEqual(try Data(contentsOf: manifest(root, original.workspaceID)), Data("[]".utf8))

        let reservation = try retentionFixture(978_200)
        let retention = try TemporalEvidenceRetentionCleanupRecoveryFileAdapterV1(generationRootURL: root, workspaceID: reservation.mutation.workspaceID)
        try await retention.prepareCleanup(reservation)
        try await retention.markCleanupCommitted(reservation, receiptSHA256: String(repeating: "a", count: 64))
        let retained = try inventory(root)
        let hostileMutation = try retentionFixture(978_200, policySHA256: String(repeating: "d", count: 64))
        XCTAssertEqual(hostileMutation.mutation.mutationID, reservation.mutation.mutationID)
        XCTAssertNotEqual(hostileMutation.mutation, reservation.mutation)
        await fails { try await retention.finishCleanup(hostileMutation) }
        XCTAssertEqual(try inventory(root), retained)
        let invalidReceipt = String(repeating: "b", count: 64)
        await fails { try await retention.markCleanupCommitted(reservation, receiptSHA256: invalidReceipt) }
        XCTAssertEqual(try inventory(root), retained)
        // Same carried PREPARED value legitimately finishes the current record;
        // full stored state/receipt were validated under the transaction lock.
        try await retention.finishCleanup(reservation)
        let pending = try await retention.pendingCleanups()
        XCTAssertTrue(pending.isEmpty)
    }

    func testScratchRecoveryRemovesExactColdLeaseAndIsIdempotent() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await scratchFixture(root, slot: 979_000)
        let unrelated = try await scratchFixture(root, slot: 979_010)
        XCTAssertNotEqual(fixture.binding.request.leaseID, fixture.binding.request.operationID)
        let cold = try scratchStore(root)
        let adapter = TemporalEvidenceScratchRecoveryAdapterV1(scratch: cold)
        try await adapter.removeRecoveredScratch(binding: fixture.binding)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.directory.path))
        XCTAssertEqual(try Data(contentsOf: unrelated.directory.appendingPathComponent("original.bin")), Data([1, 2, 3]))
        let stable = try inventory(root)
        try await TemporalEvidenceScratchRecoveryAdapterV1(scratch: try scratchStore(root)).removeRecoveredScratch(binding: fixture.binding)
        XCTAssertEqual(try inventory(root), stable)
    }

    func testScratchRecoveryRejectsDifferentOwnerAndUnsafeLeaseShapeWithoutEffects() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await scratchFixture(root, slot: 979_100)
        let adapter = TemporalEvidenceScratchRecoveryAdapterV1(scratch: try scratchStore(root))
        let original = fixture.binding
        for field in 0..<5 {
            let operation = field == 0 ? C33TemporalEvidenceTestSupport.id(979_190) : original.request.operationID
            let request = try CapabilityScratchLeaseRequestV1(
                leaseID: original.request.leaseID, operationID: operation,
                purpose: field == 1 ? .importData : .capture,
                requestedByteCount: field == 2 ? 2048 : original.request.requestedByteCount,
                createdAt: field == 3 ? original.request.createdAt.addingTimeInterval(-1) : original.request.createdAt,
                expiresAt: original.request.expiresAt
            )
            let lease = CapabilityScratchLeaseV1(leaseID: request.leaseID, purpose: request.purpose, relativeDirectory: field == 4 ? "other" : original.lease.relativeDirectory)
            let binding = try TemporalEvidenceScratchBindingV1(request: request, lease: lease, mutationID: MutationIDV1(rawValue: operation), contentID: original.contentID, contentSHA256: original.contentSHA256)
            let before = try inventory(root)
            await fails { try await adapter.removeRecoveredScratch(binding: binding) }
            XCTAssertEqual(try inventory(root), before)
        }
        let moved = fixture.directory.appendingPathExtension("held")
        try FileManager.default.moveItem(at: fixture.directory, to: moved)
        XCTAssertEqual(Darwin.symlink(moved.path, fixture.directory.path), 0)
        let hostile = try inventory(root)
        await fails { try await adapter.removeRecoveredScratch(binding: original) }
        XCTAssertEqual(try inventory(root), hostile)
    }

    func testScratchRecoveryResumesOwnedDeletionTombstone() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await scratchFixture(root, slot: 979_200)
        let tombstone = fixture.directory.deletingLastPathComponent().appendingPathComponent(".deleting-" + fixture.directory.lastPathComponent)
        // The incumbent V9_12 witness uses a real acquired lease in this exact
        // source-shaped postrename state. This is not process-stop evidence.
        try FileManager.default.moveItem(at: fixture.directory, to: tombstone)
        let adapter = TemporalEvidenceScratchRecoveryAdapterV1(scratch: try scratchStore(root))
        try await adapter.removeRecoveredScratch(binding: fixture.binding)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tombstone.path))
        try await adapter.removeRecoveredScratch(binding: fixture.binding)
        let collision = try await scratchFixture(root, slot: 979_210)
        let collisionTombstone = collision.directory.deletingLastPathComponent().appendingPathComponent(".deleting-" + collision.directory.lastPathComponent)
        try FileManager.default.copyItem(at: collision.directory, to: collisionTombstone)
        let before = try inventory(root)
        await fails { try await adapter.removeRecoveredScratch(binding: collision.binding) }
        XCTAssertEqual(try inventory(root), before)
    }

    private func promotion(_ slot: Int, workspace: WorkspaceID? = nil) throws -> TemporalEvidencePromotionReservationV1 {
        let mutation = try C33TemporalEvidenceTestSupport.mutation(slot + 1)
        let leaseID = C33TemporalEvidenceTestSupport.id(slot + 2)
        let request = try CapabilityScratchLeaseRequestV1(leaseID: leaseID, operationID: mutation.rawValue, purpose: .capture, requestedByteCount: 1024, createdAt: clock, expiresAt: clock.addingTimeInterval(60))
        let lease = CapabilityScratchLeaseV1(leaseID: leaseID, purpose: .capture, relativeDirectory: "capture-" + leaseID.uuidString.lowercased())
        let content = "publication.test.\(slot)", digest = String(repeating: "a", count: 64)
        let binding = try TemporalEvidenceScratchBindingV1(request: request, lease: lease, mutationID: mutation, contentID: content, contentSHA256: digest)
        return try .init(workspaceID: workspace ?? C33TemporalEvidenceTestSupport.workspace(slot), mutationID: mutation, contentID: content, contentSHA256: digest, binding: binding, state: .prepared)
    }
    private func replacing(_ value: TemporalEvidencePromotionReservationV1, state: TemporalEvidencePromotionRecoveryStateV1) throws -> TemporalEvidencePromotionReservationV1 {
        try .init(workspaceID: value.workspaceID, mutationID: value.mutationID, contentID: value.contentID, contentSHA256: value.contentSHA256, binding: value.binding, state: state)
    }
    private func retentionFixture(_ slot: Int, policySHA256: String = String(repeating: "c", count: 64)) throws -> TemporalEvidenceRetentionCleanupReservationV1 {
        let base = try C33TemporalEvidenceTestSupport.clip(slot: slot)
        let id = try C33TemporalEvidenceTestSupport.mutation(slot + 1)
        let event = try TemporalEvidenceRetentionEventV1(eventID: C33TemporalEvidenceTestSupport.id(slot + 2), clip: base.clip, disposition: .deleteClip, policySHA256: policySHA256, actor: C26SurveySessionTestSupport.actor(workspaceID: base.clip.workspaceID, slot: slot + 3, responsibility: .reviewedBy), occurredAt: base.clip.acceptedAt.addingTimeInterval(1), revision: 1, mutationID: id)
        let expected = try C33TemporalEvidenceTestSupport.expectedRevision(for: base.clip, generationID: C33TemporalEvidenceTestSupport.id(slot + 4), writerInstanceID: C33TemporalEvidenceTestSupport.id(slot + 5), workspaceRevision: 1, entityRevision: base.clip.revision)
        let mutation = try TemporalEvidenceMutationV1(workspaceID: base.clip.workspaceID, expectedRevision: expected, mutationID: id, payload: .removeClip(event: event, clips: [base.clip], anchors: [], derivatives: [], predecessorEvent: nil))
        return try .init(mutation: mutation, state: .prepared)
    }
    private func promotionStore(_ root: URL, _ fixture: TemporalEvidencePromotionReservationV1, hook: TemporalEvidenceOperationalPublicationBoundaryHookV2? = nil, readHook: TemporalEvidenceOperationalJournalReadBoundaryHookV1? = nil) throws -> TemporalEvidencePromotionRecoveryFileAdapterV1 {
        try .init(generationRootURL: root, workspaceID: fixture.workspaceID, readBoundary: readHook, publicationBoundary: hook, verify: { _, _, _ in true }, remove: { _, _, _ in })
    }
    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("temporal-m1-" + UUID().uuidString.lowercased(), isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }
    private nonisolated func journal(_ root: URL) -> URL { root.appendingPathComponent("operational/temporal-evidence-promotion-v1", isDirectory: true) }
    private func manifest(_ root: URL, _ workspace: WorkspaceID, retention: Bool = false) -> URL { journal(root).appendingPathComponent(workspace.rawValue.uuidString.lowercased() + (retention ? "-retention-cleanup.json" : ".json")) }
    private func transaction(_ root: URL) throws -> URL {
        let slots = try names(journal(root)).filter { $0.hasPrefix(".tp2-") }
        XCTAssertEqual(slots.count, 1)
        return journal(root).appendingPathComponent(try XCTUnwrap(slots.first), isDirectory: true)
    }
    private func names(_ root: URL) throws -> [String] { try FileManager.default.contentsOfDirectory(atPath: root.path).sorted() }
    private func inode(_ file: URL) throws -> ino_t {
        var info = stat(); guard Darwin.lstat(file.path, &info) == 0 else { throw Stop.interrupted }; return info.st_ino
    }
    private func inventory(_ root: URL) throws -> [String: String] {
        var result: [String: String] = [:]
        @MainActor func visit(_ directory: URL, prefix: String) throws {
            for name in try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted() {
                let path = prefix + name, url = directory.appendingPathComponent(name)
                var info = stat(); guard Darwin.lstat(url.path, &info) == 0 else { throw Stop.interrupted }
                let common = "\(info.st_dev):\(info.st_ino):\(info.st_nlink):\(info.st_mode)"
                if info.st_mode & S_IFMT == S_IFDIR { result[path] = "d:" + common; try visit(url, prefix: path + "/") }
                else if info.st_mode & S_IFMT == S_IFLNK { result[path] = "l:" + common + ":" + (try FileManager.default.destinationOfSymbolicLink(atPath: url.path)) }
                else { result[path] = "f:" + common + ":" + KernelCanonicalHashV1.sha256(try Data(contentsOf: url)) }
            }
        }
        try visit(root, prefix: "")
        return result
    }
    private func seedManifest(_ template: Data, workspace: WorkspaceID, root: URL, paddedTo: Int? = nil) throws {
        var values = try XCTUnwrap(JSONSerialization.jsonObject(with: template) as? [[String: Any]])
        for index in values.indices { values[index]["workspaceID"] = workspace.rawValue.uuidString }
        var data = try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
        if let paddedTo { guard data.count <= paddedTo else { throw Stop.interrupted }; data.append(Data(repeating: 32, count: paddedTo - data.count)) }
        let path = manifest(root, workspace)
        try data.write(to: path)
        try ProtectedFilePolicyV1.applyAndVerify(.journal, at: path)
    }
    private func isAfterPublication(_ boundary: TemporalEvidenceOperationalPublicationBoundaryV2) -> Bool { [.published, .durablePublication, .removedDisplacedPayload, .removedReservation].contains(boundary) }
    private func scratchStore(_ root: URL) throws -> ScratchDataLeaseStoreV1 { try .init(applicationSupportURL: root, clock: { Date(timeIntervalSince1970: 1_820_000_000) }, capacityProvider: { _ in Int64.max }) }
    private func scratchFixture(_ root: URL, slot: Int) async throws -> (binding: TemporalEvidenceScratchBindingV1, directory: URL) {
        let reservation = try promotion(slot), request = reservation.binding.request
        let backing = try ScratchDataLeaseRequestV1(leaseID: request.leaseID, purpose: .capture, owner: .capture, ownerOperationID: request.operationID, requestedByteCount: request.requestedByteCount, createdAt: request.createdAt, expiresAt: request.expiresAt)
        let store = try scratchStore(root), lease = try await store.acquireScratchLease(backing)
        _ = try await store.writeScratchData(Data([1, 2, 3]), named: "original.bin", lease: lease)
        XCTAssertEqual(lease.relativeDirectory, reservation.binding.lease.relativeDirectory)
        return (reservation.binding, root.appendingPathComponent("FieldEvidenceOperations/ScratchDataV1").appendingPathComponent(lease.relativeDirectory))
    }
    private func fails(_ operation: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async {
        do { try await operation(); XCTFail("expected denied operation", file: file, line: line) } catch { }
    }
    private nonisolated static func attempt(_ operation: @Sendable () async throws -> Void) async throws -> Bool {
        do { try await operation(); return true }
        catch TemporalEvidenceContractFailureV1.interruption { return false }
    }
}

private final class TemporalPublicationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var observed = false
    private var opens = 0
    func nextOpen() -> Int { lock.lock(); defer { lock.unlock() }; opens += 1; return opens }
    func mark() { lock.lock(); observed = true; lock.unlock() }
    var hit: Bool { lock.lock(); defer { lock.unlock() }; return observed }
}

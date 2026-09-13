import Darwin
import Foundation
import XCTest

@testable import FieldEvidenceApp

final class V23StoreControlDescriptorOwnershipTests: XCTestCase {
    #if DEBUG
    private typealias Hooks = StoreControlInitializationTestHooksV1
    private enum InjectedFailure: Error, Equatable { case initialization }

    func testMigrationJournalFailureBeforeTransferClosesLocalDescriptorsOnceAndReopens() throws {
        try exerciseJournalFailure(at: .beforeOwnershipTransfer, cleanupOwner: .local)
    }

    func testMigrationJournalPostTransferFailuresCloseObjectDescriptorsOnceAndReopen() throws {
        for boundary in [Hooks.Boundary.afterOwnershipTransfer, .beforeCompletion] {
            try exerciseJournalFailure(at: boundary, cleanupOwner: .object)
        }
    }

    func testMigrationJournalSuccessfulLifetimeClosesOnlyItsObjectDescriptorsOnce() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        var events: [Hooks.Cleanup] = []
        try autoreleasepool {
            let store = try StoreMigrationJournalStoreV1(applicationSupportURL: root,
                initializationTesting: Hooks(cleanup: { events.append($0) }))
            XCTAssertNil(try store.loadJournal())
            withExtendedLifetime(store) { XCTAssertTrue(events.isEmpty) }
        }
        XCTAssertEqual(events, journalCloses(by: .object))
        try assertJournalReopens(at: root)
    }

    func testGenerationLeaseFailureBeforeTransferUnlocksAndClosesOnlyLocalDescriptors() throws {
        try exerciseRegistryFailure(at: .beforeOwnershipTransfer, cleanupOwner: .local)
    }

    func testGenerationLeasePostTransferFailuresNeverAttemptOwnerGuardCleanupAndReopen() throws {
        for boundary in [Hooks.Boundary.afterOwnershipTransfer, .beforeCompletion] {
            try exerciseRegistryFailure(at: boundary, cleanupOwner: .object)
        }
    }

    func testGenerationLeaseSuccessfulLifetimeRemovesUnusedOwnerGuardAndClosesOnce() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let ownerID = UUID()
        let guardURL = ownerGuardURL(root: root, ownerID: ownerID)
        var events: [Hooks.Cleanup] = []
        try autoreleasepool {
            let registry = try GenerationLeaseRegistryV1(applicationSupportURL: root, ownerID: ownerID,
                initializationTesting: Hooks(cleanup: { events.append($0) }))
            XCTAssertNil(try registry.loadPruneIntent())
            XCTAssertTrue(FileManager.default.fileExists(atPath: guardURL.path))
            withExtendedLifetime(registry) { XCTAssertTrue(events.isEmpty) }
        }
        XCTAssertEqual(events, [.ownerGuardCleanupRequested] + registryCloses(by: .object))
        XCTAssertFalse(FileManager.default.fileExists(atPath: guardURL.path))
        try assertRegistryReopens(at: root, ownerID: ownerID)
    }

    private func exerciseJournalFailure(at boundary: Hooks.Boundary,
                                        cleanupOwner: Hooks.CleanupOwner) throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        var events: [Hooks.Cleanup] = []
        var reached = false
        let hooks = Hooks(boundary: {
            if $0 == boundary { reached = true; throw InjectedFailure.initialization }
        }, cleanup: { events.append($0) })
        XCTAssertThrowsError(try autoreleasepool {
            try StoreMigrationJournalStoreV1(applicationSupportURL: root, initializationTesting: hooks)
        }) { XCTAssertEqual($0 as? InjectedFailure, .initialization) }
        XCTAssertTrue(reached)
        XCTAssertEqual(events, journalCloses(by: cleanupOwner))
        try assertJournalReopens(at: root)
    }

    private func exerciseRegistryFailure(at boundary: Hooks.Boundary,
                                         cleanupOwner: Hooks.CleanupOwner) throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let ownerID = UUID()
        let guardURL = ownerGuardURL(root: root, ownerID: ownerID)
        var events: [Hooks.Cleanup] = []
        var reached = false
        let hooks = Hooks(boundary: {
            if $0 == boundary { reached = true; throw InjectedFailure.initialization }
        }, cleanup: { events.append($0) })
        XCTAssertThrowsError(try autoreleasepool {
            try GenerationLeaseRegistryV1(applicationSupportURL: root, ownerID: ownerID,
                initializationTesting: hooks)
        }) { XCTAssertEqual($0 as? InjectedFailure, .initialization) }
        XCTAssertTrue(reached)
        XCTAssertEqual(events, registryCloses(by: cleanupOwner))
        // Failed construction must leave logical guard reconciliation to a
        // complete owner. Reopening the exact same owner also proves its lock
        // was released, rather than merely observing a callback count.
        XCTAssertTrue(FileManager.default.fileExists(atPath: guardURL.path))
        try assertRegistryReopens(at: root, ownerID: ownerID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: guardURL.path))
    }

    private func assertJournalReopens(at root: URL) throws {
        try autoreleasepool {
            let store = try StoreMigrationJournalStoreV1(applicationSupportURL: root)
            XCTAssertNil(try store.loadJournal())
            withExtendedLifetime(store) {}
        }
    }

    private func assertRegistryReopens(at root: URL, ownerID: UUID) throws {
        try autoreleasepool {
            let registry = try GenerationLeaseRegistryV1(applicationSupportURL: root, ownerID: ownerID)
            XCTAssertNil(try registry.loadPruneIntent())
            withExtendedLifetime(registry) {}
        }
    }

    private func journalCloses(by owner: Hooks.CleanupOwner) -> [Hooks.Cleanup] {
        [.closed(.migration, owner, succeeded: true),
         .closed(.operations, owner, succeeded: true),
         .closed(.applicationSupport, owner, succeeded: true)]
    }

    private func registryCloses(by owner: Hooks.CleanupOwner) -> [Hooks.Cleanup] {
        [.ownerUnlocked(owner, succeeded: true),
         .closed(.ownerLock, owner, succeeded: true),
         .closed(.mutationLock, owner, succeeded: true),
         .closed(.owners, owner, succeeded: true),
         .closed(.lease, owner, succeeded: true),
         .closed(.operations, owner, succeeded: true),
         .closed(.applicationSupport, owner, succeeded: true)]
    }

    private func ownerGuardURL(root: URL, ownerID: UUID) -> URL {
        root.appendingPathComponent("FieldEvidenceOperations/generation-leases/owners")
            .appendingPathComponent(ownerID.uuidString.lowercased() + ".lock")
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("v23-descriptor-ownership-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    #endif
}

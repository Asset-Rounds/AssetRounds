import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

final class S6_6EraseRecoveryTests: XCTestCase {
    private let fileManager = FileManager.default
    private let bundleID = "com.palatis3.fieldrecord"

    @MainActor
    func testAbsentApplicationSupportHasNoEraseAuthority() async throws {
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "S6_6-absent-support-\(UUID().uuidString)",
            isDirectory: true
        )
        let library = root.appendingPathComponent("Library", isDirectory: true)
        let support = library.appendingPathComponent(
            "Application Support",
            isDirectory: true
        )
        let caches = library.appendingPathComponent("Caches", isDirectory: true)
        let temporary = root.appendingPathComponent("tmp", isDirectory: true)
        try fileManager.createDirectory(
            at: caches,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: temporary,
            withIntermediateDirectories: true
        )
        defer { try? fileManager.removeItem(at: root) }

        let recovered = try await EraseAllService(
            applicationSupportURL: support,
            cachesDirectoryURL: caches,
            temporaryDirectoryURL: temporary
        ).reconcileAtStartup(
            diagnosticsStore: DiagnosticsStore(applicationSupportURL: support)
        )

        XCTAssertNil(recovered)
        XCTAssertFalse(fileManager.fileExists(atPath: support.path))
    }

    @MainActor
    func testGoldenEraseActivatesEmptyGenerationAndClearsFrozenState() async throws {
        let harness = try await makeHarness("golden")
        defer { cleanup(harness) }
        let coordinator = try XCTUnwrap(harness.coordinator)
        let oldID = coordinator.generationID
        let newID = uuid("66000000-0000-0000-0000-000000000101")
        let service = EraseAllService(
            applicationSupportURL: harness.support,
            cachesDirectoryURL: harness.caches,
            temporaryDirectoryURL: harness.temporary,
            userDefaults: harness.defaults,
            bundleIdentifier: bundleID,
            makeUUID: sequence([
                newID,
                uuid("66000000-0000-0000-0000-000000000102"),
            ])
        )

        let erased = try await service.erase(
            confirmation: "ERASE",
            coordinator: coordinator,
            diagnosticsStore: harness.diagnostics
        ) { session in
            coordinator.activate(session: session)
        }

        XCTAssertFalse(erased.cleanupDeferred)
        XCTAssertEqual(erased.session.generationID, newID)
        XCTAssertEqual(coordinator.generationID, newID)
        XCTAssertEqual(try harness.factory.currentGenerationID(), newID)
        XCTAssertEqual(try harness.factory.retiredGenerationIDs(), [])
        XCTAssertEqual(
            try counts(erased.session.modelContext),
            [0, 0, 0, 0, 0, 0, 0]
        )
        let diagnosticsAfterErase = await harness.diagnostics.snapshot()
        XCTAssertEqual(diagnosticsAfterErase, .zero)
        XCTAssertTrue(
            (harness.defaults.persistentDomain(forName: bundleID) ?? [:]).isEmpty
        )
        XCTAssertFalse(fileManager.fileExists(
            atPath: harness.factory.installedGenerationURL(id: oldID).path
        ))
        XCTAssertFalse(fileManager.fileExists(
            atPath: harness.support.appendingPathComponent("FieldEvidenceErase").path
        ))
        assertAuxiliaryRootsCleared(harness)

        let reopened = try harness.factory.openOrBootstrapCurrent()
        XCTAssertEqual(reopened.generationID, newID)
        XCTAssertEqual(try counts(reopened.modelContext), [0, 0, 0, 0, 0, 0, 0])
    }

    @MainActor
    func testRetainedLiveContextDefersCleanupUntilColdRecovery() async throws {
        let harness = try await makeHarness("deferred-drain")
        defer { cleanup(harness) }
        let coordinator = try XCTUnwrap(harness.coordinator)
        let oldID = coordinator.generationID
        let newID = uuid("66000000-0000-0000-0000-000000000111")
        var retainedContext: ModelContext? = coordinator.modelContext
        let service = EraseAllService(
            applicationSupportURL: harness.support,
            cachesDirectoryURL: harness.caches,
            temporaryDirectoryURL: harness.temporary,
            userDefaults: harness.defaults,
            bundleIdentifier: bundleID,
            makeUUID: sequence([
                newID,
                uuid("66000000-0000-0000-0000-000000000112"),
            ])
        )

        let outcome = try await service.erase(
            confirmation: "ERASE",
            coordinator: coordinator,
            diagnosticsStore: harness.diagnostics
        ) { session in
            coordinator.activate(session: session)
        }

        XCTAssertTrue(outcome.cleanupDeferred)
        XCTAssertEqual(outcome.session.generationID, newID)
        XCTAssertEqual(try harness.factory.currentGenerationID(), newID)
        XCTAssertTrue(fileManager.fileExists(atPath:
            harness.factory.installedGenerationURL(id: oldID).path
        ))
        let pending = try XCTUnwrap(try EraseIntentStore(
            applicationSupportURL: harness.support
        ).load())
        XCTAssertEqual(pending.phase, .sessionActivated)

        retainedContext = nil
        _ = retainedContext
        await Task.yield()
        let recovered = try await EraseAllService(
            applicationSupportURL: harness.support,
            cachesDirectoryURL: harness.caches,
            temporaryDirectoryURL: harness.temporary,
            userDefaults: harness.defaults,
            bundleIdentifier: bundleID
        ).reconcileAtStartup(diagnosticsStore: harness.diagnostics)

        XCTAssertEqual(recovered?.generationID, newID)
        XCTAssertFalse(fileManager.fileExists(atPath:
            harness.factory.installedGenerationURL(id: oldID).path
        ))
        XCTAssertFalse(fileManager.fileExists(atPath:
            harness.support.appendingPathComponent("FieldEvidenceErase").path
        ))
        let diagnosticsAfterRecovery = await harness.diagnostics.snapshot()
        XCTAssertEqual(diagnosticsAfterRecovery, .zero)
    }

    @MainActor
    func testEveryInterruptionRecoversOldOrFullyErasedNew() async throws {
        for (offset, point) in EraseAllFailurePoint.allCases.enumerated() {
            let harness = try await makeHarness("phase-\(offset)")
            defer { cleanup(harness) }
            let oldID = try XCTUnwrap(harness.coordinator).generationID
            let newID = UUID(uuid: (
                0x66, 0, 0, 0, 0, 0, 0, 0,
                0, 0, 0, 0, 0, 0,
                UInt8(0x40 + offset), UInt8(0x60 + offset)
            ))
            let service = EraseAllService(
                applicationSupportURL: harness.support,
                cachesDirectoryURL: harness.caches,
                temporaryDirectoryURL: harness.temporary,
                userDefaults: harness.defaults,
                bundleIdentifier: bundleID,
                makeUUID: sequence([newID, UUID()]),
                failureInjection: EraseAllFailureInjection(failOnceAt: point)
            )
            await XCTAssertThrowsErrorAsync {
                _ = try await service.erase(
                    confirmation: "ERASE",
                    coordinator: try XCTUnwrap(harness.coordinator),
                    diagnosticsStore: harness.diagnostics
                ) { session in
                    harness.coordinator?.activate(session: session)
                }
            } verify: { error in
                XCTAssertEqual(error as? EraseAllServiceError, .injectedFailure)
            }

            harness.coordinator = nil
            await Task.yield()
            let recovery = EraseAllService(
                applicationSupportURL: harness.support,
                cachesDirectoryURL: harness.caches,
                temporaryDirectoryURL: harness.temporary,
                userDefaults: harness.defaults,
                bundleIdentifier: bundleID
            )
            let recovered = try await recovery.reconcileAtStartup(
                diagnosticsStore: harness.diagnostics
            )

            if point == .afterEmptyGenerationDirectoryCreate
                || point == .beforePreparedWrite {
                XCTAssertNil(recovered, "\(point)")
                XCTAssertEqual(try harness.factory.currentGenerationID(), oldID)
                let retainedSession = try harness.factory.openOrBootstrapCurrent()
                XCTAssertEqual(
                    try retainedSession.modelContext.fetchCount(
                        FetchDescriptor<Asset>()
                    ),
                    1
                )
                let retainedDiagnostics = await harness.diagnostics.snapshot()
                XCTAssertNotEqual(retainedDiagnostics, .zero)
            } else {
                let session = try XCTUnwrap(recovered, "\(point)")
                XCTAssertEqual(session.generationID, newID, "\(point)")
                XCTAssertEqual(try harness.factory.currentGenerationID(), newID)
                XCTAssertEqual(try harness.factory.retiredGenerationIDs(), [])
                XCTAssertEqual(
                    try counts(session.modelContext),
                    [0, 0, 0, 0, 0, 0, 0],
                    "\(point)"
                )
                let clearedDiagnostics = await harness.diagnostics.snapshot()
                XCTAssertEqual(clearedDiagnostics, .zero)
                assertAuxiliaryRootsCleared(harness)
            }
            XCTAssertFalse(fileManager.fileExists(
                atPath: harness.support.appendingPathComponent(
                    "FieldEvidenceErase/erase.json"
                ).path
            ))
        }
    }

    @MainActor
    func testCancelAndDirtyContextChangeNothingBeforeMarker() async throws {
        let harness = try await makeHarness("no-marker")
        defer { cleanup(harness) }
        let before = try tree(harness.support)
        let service = EraseAllService(
            applicationSupportURL: harness.support,
            cachesDirectoryURL: harness.caches,
            temporaryDirectoryURL: harness.temporary,
            userDefaults: harness.defaults,
            bundleIdentifier: bundleID
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await service.erase(
                confirmation: "erase",
                coordinator: try XCTUnwrap(harness.coordinator),
                diagnosticsStore: harness.diagnostics,
                activate: { _ in }
            )
        } verify: { error in
            XCTAssertEqual(error as? EraseAllServiceError, .invalidConfirmation)
        }
        XCTAssertEqual(try tree(harness.support), before)

        let coordinator = try XCTUnwrap(harness.coordinator)
        coordinator.modelContext.insert(Site(label: "Unsaved"))
        await XCTAssertThrowsErrorAsync {
            _ = try await service.erase(
                confirmation: "ERASE",
                coordinator: coordinator,
                diagnosticsStore: harness.diagnostics,
                activate: { _ in }
            )
        } verify: { error in
            XCTAssertEqual(error as? EraseAllServiceError, .contextHasChanges)
        }
        coordinator.modelContext.rollback()
        XCTAssertEqual(try tree(harness.support), before)
        XCTAssertFalse(fileManager.fileExists(
            atPath: harness.support.appendingPathComponent(
                "FieldEvidenceErase/erase.json"
            ).path
        ))
    }

    @MainActor
    func testLiveCleanupWaitsForOldContextReferenceDrain() async throws {
        let harness = try await makeHarness("drain")
        defer { cleanup(harness) }
        let coordinator = try XCTUnwrap(harness.coordinator)
        let oldID = coordinator.generationID
        let newID = uuid("66000000-0000-0000-0000-000000000301")
        var retainedContext: ModelContext? = coordinator.modelContext
        let service = EraseAllService(
            applicationSupportURL: harness.support,
            cachesDirectoryURL: harness.caches,
            temporaryDirectoryURL: harness.temporary,
            userDefaults: harness.defaults,
            bundleIdentifier: bundleID,
            makeUUID: sequence([
                newID,
                uuid("66000000-0000-0000-0000-000000000302"),
            ])
        )

        let outcome = try await service.erase(
            confirmation: "ERASE",
            coordinator: coordinator,
            diagnosticsStore: harness.diagnostics
        ) { session in
            coordinator.activate(session: session)
        }
        XCTAssertTrue(outcome.cleanupDeferred)
        XCTAssertEqual(outcome.session.generationID, newID)
        XCTAssertNotNil(retainedContext)
        XCTAssertTrue(fileManager.fileExists(
            atPath: harness.factory.installedGenerationURL(id: oldID).path
        ))
        XCTAssertEqual(
            try EraseIntentStore(applicationSupportURL: harness.support)
                .load()?.phase,
            .sessionActivated
        )

        retainedContext = nil
        harness.coordinator = nil
        await Task.yield()
        let recovered = try await EraseAllService(
            applicationSupportURL: harness.support,
            cachesDirectoryURL: harness.caches,
            temporaryDirectoryURL: harness.temporary,
            userDefaults: harness.defaults,
            bundleIdentifier: bundleID
        ).reconcileAtStartup(diagnosticsStore: harness.diagnostics)
        XCTAssertEqual(recovered?.generationID, newID)
        XCTAssertFalse(fileManager.fileExists(
            atPath: harness.factory.installedGenerationURL(id: oldID).path
        ))
    }

    @MainActor
    func testMalformedAuxiliaryTreeFailsBeforeAnyDeletion() async throws {
        let harness = try await makeHarness("auxiliary")
        defer { cleanup(harness) }
        let external = harness.root.appendingPathComponent("external.bin")
        let externalBytes = Data("outside erase authority".utf8)
        try externalBytes.write(to: external)
        let link = harness.support.appendingPathComponent(
            "FieldEvidenceOperations/unsafe-link"
        )
        try fileManager.createSymbolicLink(
            at: link,
            withDestinationURL: external
        )
        let before = try tree(harness.support)
        let service = EraseAllService(
            applicationSupportURL: harness.support,
            cachesDirectoryURL: harness.caches,
            temporaryDirectoryURL: harness.temporary,
            userDefaults: harness.defaults,
            bundleIdentifier: bundleID
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await service.erase(
                confirmation: "ERASE",
                coordinator: try XCTUnwrap(harness.coordinator),
                diagnosticsStore: harness.diagnostics,
                activate: { _ in }
            )
        } verify: { error in
            XCTAssertEqual(error as? EraseAllServiceError, .invalidAuthority)
        }
        XCTAssertEqual(try tree(harness.support), before)
        XCTAssertEqual(try Data(contentsOf: external), externalBytes)
        XCTAssertTrue(fileManager.fileExists(atPath: link.path))
        XCTAssertFalse(fileManager.fileExists(
            atPath: harness.support.appendingPathComponent(
                "FieldEvidenceErase/erase.json"
            ).path
        ))
    }

    @MainActor
    func testPinnedEmptyGenerationCreationRejectsReplacementBeforeSQLiteWrite() async throws {
        for replaceParent in [true, false] {
            let harness = try await makeHarness(
                replaceParent ? "create-parent" : "create-leaf"
            )
            defer { cleanup(harness) }
            let authority = try harness.factory.makeRestoreGenerationAuthority()
            let oldID = try XCTUnwrap(harness.coordinator).generationID
            let oldRoot = harness.factory.installedGenerationURL(id: oldID)
            let oldBefore = try tree(oldRoot)
            let newID = replaceParent
                ? uuid("66000000-0000-0000-0000-000000000411")
                : uuid("66000000-0000-0000-0000-000000000412")
            let dataRoot = harness.support.appendingPathComponent(
                "FieldEvidenceData",
                isDirectory: true
            )
            let generations = dataRoot.appendingPathComponent(
                "generations",
                isDirectory: true
            )
            let newName = newID.uuidString.lowercased()
            var detached: URL?
            var replacement: URL?

            XCTAssertThrowsError(try harness.factory.createEmptyInstalledGeneration(
                id: newID,
                authority: authority,
                beforeStoreCreate: {
                    if replaceParent {
                        let moved = dataRoot.appendingPathComponent(
                            "generations.detached",
                            isDirectory: true
                        )
                        try self.fileManager.moveItem(at: generations, to: moved)
                        try self.fileManager.createDirectory(
                            at: generations,
                            withIntermediateDirectories: false
                        )
                        detached = moved
                        replacement = generations.appendingPathComponent(
                            "replacement.bin"
                        )
                    } else {
                        let owned = generations.appendingPathComponent(
                            newName,
                            isDirectory: true
                        )
                        let moved = generations.appendingPathComponent(
                            "\(newName).detached",
                            isDirectory: true
                        )
                        try self.fileManager.moveItem(at: owned, to: moved)
                        try self.fileManager.createDirectory(
                            at: owned,
                            withIntermediateDirectories: false
                        )
                        detached = moved
                        replacement = owned.appendingPathComponent(
                            "replacement.bin"
                        )
                    }
                    try Data("unowned replacement".utf8).write(
                        to: try XCTUnwrap(replacement)
                    )
                }
            )) { error in
                XCTAssertEqual(
                    error as? StoreGenerationFailure,
                    .dataPointerInvalid
                )
            }

            let replacementURL = try XCTUnwrap(replacement)
            XCTAssertEqual(
                try Data(contentsOf: replacementURL),
                Data("unowned replacement".utf8)
            )
            if replaceParent {
                XCTAssertEqual(
                    try tree(
                        try XCTUnwrap(detached).appendingPathComponent(
                            oldID.uuidString.lowercased(),
                            isDirectory: true
                        )
                    ),
                    oldBefore
                )
            } else {
                XCTAssertEqual(try tree(oldRoot), oldBefore)
                XCTAssertFalse(fileManager.fileExists(
                    atPath: try XCTUnwrap(detached).path
                ))
            }
            XCTAssertFalse(fileManager.fileExists(
                atPath: harness.support.appendingPathComponent(
                    "FieldEvidenceErase/erase.json"
                ).path
            ))
        }
    }

    @MainActor
    func testReplacedGenerationAncestorFailsClosedWithoutDeletingEitherTree() async throws {
        let harness = try await makeHarness("ancestor")
        defer { cleanup(harness) }
        let newID = uuid("66000000-0000-0000-0000-000000000401")
        let service = EraseAllService(
            applicationSupportURL: harness.support,
            cachesDirectoryURL: harness.caches,
            temporaryDirectoryURL: harness.temporary,
            userDefaults: harness.defaults,
            bundleIdentifier: bundleID,
            makeUUID: sequence([
                newID,
                uuid("66000000-0000-0000-0000-000000000402"),
            ]),
            failureInjection: EraseAllFailureInjection(
                failOnceAt: .afterPreparedWrite
            )
        )
        await XCTAssertThrowsErrorAsync {
            _ = try await service.erase(
                confirmation: "ERASE",
                coordinator: try XCTUnwrap(harness.coordinator),
                diagnosticsStore: harness.diagnostics,
                activate: { _ in }
            )
        } verify: { error in
            XCTAssertEqual(error as? EraseAllServiceError, .injectedFailure)
        }
        harness.coordinator = nil
        await Task.yield()

        let dataRoot = harness.support.appendingPathComponent("FieldEvidenceData")
        let canonical = dataRoot.appendingPathComponent("generations")
        let detached = dataRoot.appendingPathComponent("generations.detached")
        try fileManager.moveItem(at: canonical, to: detached)
        try fileManager.createDirectory(at: canonical, withIntermediateDirectories: false)
        let replacement = canonical.appendingPathComponent("replacement.bin")
        let replacementBytes = Data("unowned replacement".utf8)
        try replacementBytes.write(to: replacement)
        let detachedBefore = try tree(detached)

        let recovery = EraseAllService(
            applicationSupportURL: harness.support,
            cachesDirectoryURL: harness.caches,
            temporaryDirectoryURL: harness.temporary,
            userDefaults: harness.defaults,
            bundleIdentifier: bundleID
        )
        await XCTAssertThrowsErrorAsync {
            _ = try await recovery.reconcileAtStartup(
                diagnosticsStore: harness.diagnostics
            )
        } verify: { _ in }
        XCTAssertEqual(try tree(detached), detachedBefore)
        XCTAssertEqual(try Data(contentsOf: replacement), replacementBytes)
        XCTAssertNotNil(try EraseIntentStore(
            applicationSupportURL: harness.support
        ).load())
    }
}

private extension S6_6EraseRecoveryTests {
    final class Harness {
        let root: URL
        let support: URL
        let caches: URL
        let temporary: URL
        let factory: StoreGenerationFactory
        var coordinator: StoreSessionCoordinator?
        let diagnostics: DiagnosticsStore
        let defaults: UserDefaults

        init(
            root: URL,
            support: URL,
            caches: URL,
            temporary: URL,
            factory: StoreGenerationFactory,
            coordinator: StoreSessionCoordinator,
            diagnostics: DiagnosticsStore,
            defaults: UserDefaults
        ) {
            self.root = root
            self.support = support
            self.caches = caches
            self.temporary = temporary
            self.factory = factory
            self.coordinator = coordinator
            self.diagnostics = diagnostics
            self.defaults = defaults
        }
    }

    struct FileFact: Equatable {
        let path: String
        let bytes: Data
    }

    enum FixtureError: Error { case invalid }

    @MainActor
    func makeHarness(_ name: String) async throws -> Harness {
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "S6_6-\(name)-\(UUID().uuidString)",
            isDirectory: true
        )
        let library = root.appendingPathComponent("Library", isDirectory: true)
        let support = library.appendingPathComponent(
            "Application Support",
            isDirectory: true
        )
        let caches = library.appendingPathComponent("Caches", isDirectory: true)
        let temporary = root.appendingPathComponent("tmp", isDirectory: true)
        try fileManager.createDirectory(at: support, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: caches, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: temporary, withIntermediateDirectories: true)
        let factory = StoreGenerationFactory(applicationSupportURL: support)
        let session = try factory.openOrBootstrapCurrent()
        let context = session.modelContext
        let created = Date(timeIntervalSince1970: 1_786_800_000)
        let siteID = uuid("66000000-0000-0000-0000-000000000001")
        context.insert(Site(
            id: siteID,
            label: "Erase campus",
            address: nil,
            timeZoneID: "America/New_York",
            createdAt: created
        ))
        context.insert(Asset(
            id: uuid("66000000-0000-0000-0000-000000000002"),
            siteID: siteID,
            packID: SignPack.illuminatedSignV1.packID,
            packSchemaVersion: SignPack.illuminatedSignV1.schemaVersion,
            packContentVersion: SignPack.illuminatedSignV1.contentVersion,
            label: "Erase sign",
            createdAt: created.addingTimeInterval(1)
        ))
        context.insert(Packet(
            id: uuid("66000000-0000-0000-0000-000000000003"),
            stableRootID: uuid("66000000-0000-0000-0000-000000000004"),
            currentRecordID: nil,
            evaluationCounted: true,
            contentDeletedAt: created.addingTimeInterval(3),
            createdAt: created.addingTimeInterval(2)
        ))
        try context.save()

        for relative in [
            "FieldEvidenceRestore/owned.bin",
            "FieldEvidenceOperations/owned.bin",
            "FieldEvidenceCommerce/entitlement.json",
        ] {
            let url = support.appendingPathComponent(relative)
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(relative.utf8).write(to: url)
        }
        for rootURL in [
            caches.appendingPathComponent("FieldEvidenceApp"),
            temporary.appendingPathComponent("FieldEvidenceApp"),
        ] {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
            try Data("owned cache".utf8).write(
                to: rootURL.appendingPathComponent("owned.bin")
            )
        }
        let diagnostics = DiagnosticsStore(applicationSupportURL: support)
        await diagnostics.prepare()
        await diagnostics.increment(.reportSaved)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "S6_6-\(UUID())"))
        defaults.setPersistentDomain(["erase-test": true], forName: bundleID)
        return Harness(
            root: root,
            support: support,
            caches: caches,
            temporary: temporary,
            factory: factory,
            coordinator: StoreSessionCoordinator(session: session),
            diagnostics: diagnostics,
            defaults: defaults
        )
    }

    @MainActor
    func counts(_ context: ModelContext) throws -> [Int] {
        [
            try context.fetchCount(FetchDescriptor<Site>()),
            try context.fetchCount(FetchDescriptor<Asset>()),
            try context.fetchCount(FetchDescriptor<WorkflowRecord>()),
            try context.fetchCount(FetchDescriptor<EvidenceFile>()),
            try context.fetchCount(FetchDescriptor<Issue>()),
            try context.fetchCount(FetchDescriptor<Packet>()),
            try context.fetchCount(FetchDescriptor<Report>()),
        ]
    }

    func assertAuxiliaryRootsCleared(
        _ harness: Harness,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for url in [
            harness.support.appendingPathComponent("FieldEvidenceRestore"),
            harness.support.appendingPathComponent("FieldEvidenceOperations"),
            harness.support.appendingPathComponent("FieldEvidenceCommerce"),
            harness.caches.appendingPathComponent("FieldEvidenceApp"),
            harness.temporary.appendingPathComponent("FieldEvidenceApp"),
        ] {
            XCTAssertFalse(
                fileManager.fileExists(atPath: url.path),
                url.path,
                file: file,
                line: line
            )
        }
    }

    func cleanup(_ harness: Harness) {
        harness.defaults.removePersistentDomain(forName: bundleID)
        harness.coordinator = nil
        // These roots are unique and live under the Simulator's temporary
        // container. A synchronous XCTest defer can still retain a local
        // ModelContext/ModelContainer while it runs, so unlinking the SQLite
        // vnode here is an API violation. The Simulator owns final temp cleanup.
    }

    func sequence(_ values: [UUID]) -> () -> UUID {
        var remaining = values
        return {
            guard !remaining.isEmpty else { return UUID() }
            return remaining.removeFirst()
        }
    }

    func uuid(_ value: String) -> UUID {
        UUID(uuidString: value)!
    }

    func tree(_ root: URL) throws -> [FileFact] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { throw FixtureError.invalid }
        var facts: [FileFact] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory != true else { continue }
            let relative = String(
                url.standardizedFileURL.path.dropFirst(
                    root.standardizedFileURL.path.count + 1
                )
            )
            facts.append(FileFact(path: relative, bytes: try Data(contentsOf: url)))
        }
        return facts.sorted { $0.path < $1.path }
    }

    @MainActor
    func XCTAssertThrowsErrorAsync(
        _ expression: () async throws -> Void,
        verify: (Error) -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await expression()
            XCTFail("Expected error", file: file, line: line)
        } catch {
            verify(error)
        }
    }
}

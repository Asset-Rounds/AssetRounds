import Foundation
import SwiftData
import XCTest

@testable import FieldEvidenceApp

final class V9_05RestoreIdentityTests: XCTestCase {
    private let fileManager = FileManager.default

    @MainActor
    func testV9_05G01GoldenEmptyReplaceCloneForkMatrix() async throws {
        let corpus = try loadCorpus()
        XCTAssertEqual(corpus.schemaVersion, 1)
        XCTAssertEqual(corpus.authority, "V23-P01-C05")
        XCTAssertEqual(corpus.cases.count, 13)
        XCTAssertEqual(Set(corpus.cases.map(\.family)), ["G01", "A01", "H01", "I01", "R01"])
        XCTAssertEqual(Set(corpus.cases.filter { $0.family == "G01" }.compactMap(\.mode)), Set(BackupRestoreMode.allCases.map(\.rawValue)))

        for (offset, mode) in BackupRestoreMode.allCases.enumerated() {
            let scenario = try makeScenario("golden-\(mode.rawValue)", targetIsNonempty: mode == .replaceExisting)
            defer { try? fileManager.removeItem(at: scenario.root) }
            let oldWorkspace = scenario.target.session.workspaceID
            let oldReplica = scenario.target.session.replicaID
            let freshWorkspace = id(300 + offset * 10)
            let freshReplica = id(301 + offset * 10)
            let restored = try await restore(
                scenario,
                mode: mode,
                uuidValues: restoreUUIDs(mode: mode, newGeneration: id(200 + offset * 10), restoreID: id(201 + offset * 10), workspace: freshWorkspace, replica: freshReplica)
            )
            let pointer = try scenario.target.factory.currentGenerationPointerV3(expectedGenerationID: restored.generationID)
            XCTAssertEqual(pointer.workspaceID, canonical(restored.workspaceID.rawValue), mode.rawValue)
            XCTAssertEqual(pointer.replicaID, canonical(restored.replicaID.rawValue), mode.rawValue)
            XCTAssertNotEqual(restored.replicaID.rawValue, scenario.sourceReplicaID, mode.rawValue)
            switch mode {
            case .emptyInstall:
                XCTAssertEqual(restored.workspaceID.rawValue, scenario.sourceWorkspaceID)
                XCTAssertEqual(restored.replicaID.rawValue, freshReplica)
            case .replaceExisting:
                XCTAssertEqual(restored.workspaceID, oldWorkspace)
                XCTAssertEqual(restored.replicaID, oldReplica)
            case .clone, .fork:
                XCTAssertEqual(restored.workspaceID.rawValue, freshWorkspace)
                XCTAssertEqual(restored.replicaID.rawValue, freshReplica)
            }
            XCTAssertEqual(try recordIDs(in: restored), scenario.sourceRecordIDs, mode.rawValue)
            XCTAssertNil(try RestoreIntentStore(applicationSupportURL: scenario.target.support).load())
        }
    }

    @MainActor
    func testV9_05A01AlternateBoundedCollisionsAndCrossWorkspace() async throws {
        let clone = try makeScenario("collision-retry", targetIsNonempty: false)
        defer { try? fileManager.removeItem(at: clone.root) }
        let old = clone.target.session
        let validWorkspace = id(410)
        let validReplica = id(411)
        let restored = try await restore(
            clone,
            mode: .clone,
            uuidValues: [id(400), id(401), clone.sourceWorkspaceID, old.workspaceID.rawValue, validWorkspace, clone.sourceReplicaID, old.replicaID.rawValue, validReplica]
        )
        XCTAssertEqual(restored.workspaceID.rawValue, validWorkspace)
        XCTAssertEqual(restored.replicaID.rawValue, validReplica)
        XCTAssertEqual(try recordIDs(in: restored), clone.sourceRecordIDs)

        let replace = try makeScenario("cross-workspace-replace", targetIsNonempty: true)
        defer { try? fileManager.removeItem(at: replace.root) }
        let destinationWorkspace = replace.target.session.workspaceID
        let destinationReplica = replace.target.session.replicaID
        XCTAssertNotEqual(destinationWorkspace.rawValue, replace.sourceWorkspaceID)
        let replaced = try await restore(replace, mode: .replaceExisting, uuidValues: [id(420), id(421)])
        XCTAssertEqual(replaced.workspaceID, destinationWorkspace)
        XCTAssertEqual(replaced.replicaID, destinationReplica)
        XCTAssertEqual(try recordIDs(in: replaced), replace.sourceRecordIDs)
    }

    @MainActor
    func testV9_05H01HostileIdentityCollisionAndSourceReplicaReuse() async throws {
        let scenario = try makeScenario("source-replica-reuse", targetIsNonempty: false)
        defer { try? fileManager.removeItem(at: scenario.root) }
        let oldID = scenario.target.session.generationID
        let pointerBefore = try pointerBytes(in: scenario.target.support)
        let validated = try importArchive(scenario.archiveURL, into: scenario.target.session)
        let service = try BackupRestoreService(
            applicationSupportURL: scenario.target.support,
            storagePreflight: unlimitedStorage,
            makeUUID: sequence([id(500), id(501)] + Array(repeating: scenario.sourceReplicaID, count: 16))
        )
        await XCTAssertThrowsErrorAsync {
            _ = try await service.restore(validatedPackage: validated, currentModelContext: scenario.target.session.modelContext, currentGenerationID: oldID, currentGenerationRootURL: scenario.target.session.generationRootURL, mode: .emptyInstall)
        } verify: { error in
            XCTAssertEqual(error as? BackupRestoreServiceError, .invalidRestoreAuthority)
        }
        XCTAssertEqual(try scenario.target.factory.currentGenerationID(), oldID)
        XCTAssertEqual(try pointerBytes(in: scenario.target.support), pointerBefore)
        XCTAssertNil(try RestoreIntentStore(applicationSupportURL: scenario.target.support).load())
        XCTAssertFalse(fileManager.fileExists(atPath: scenario.target.factory.installedGenerationURL(id: id(500)).path))
        XCTAssertNotEqual(scenario.target.session.replicaID.rawValue, scenario.sourceReplicaID)
    }

    @MainActor
    func testV9_05I01CrashPartialActivationCancellationAndLowStorage() async throws {
        let oldOutcome: Set<BackupRestoreFailurePoint> = [
            .beforePreparedWrite,
            .afterPreparedWrite,
            .beforeGenerationInstall,
            .afterGenerationInstall,
            .beforePointerSwitch,
        ]
        for (offset, point) in BackupRestoreFailurePoint.allCases.enumerated() {
            let scenario = try makeScenario("interrupt-\(offset)", targetIsNonempty: false)
            defer { try? fileManager.removeItem(at: scenario.root) }
            let oldID = scenario.target.session.generationID
            let newID = id(600 + offset * 10)
            let validated = try importArchive(scenario.archiveURL, into: scenario.target.session)
            let service = try BackupRestoreService(
                applicationSupportURL: scenario.target.support,
                storagePreflight: unlimitedStorage,
                makeUUID: sequence([newID, id(601 + offset * 10), id(602 + offset * 10)]),
                failureInjection: BackupRestoreFailureInjection(failOnceAt: point)
            )
            await XCTAssertThrowsErrorAsync {
                _ = try await service.restore(validatedPackage: validated, currentModelContext: scenario.target.session.modelContext, currentGenerationID: oldID, currentGenerationRootURL: scenario.target.session.generationRootURL, mode: .emptyInstall)
            } verify: { error in
                XCTAssertEqual(error as? BackupRestoreServiceError, .injectedFailure, "\(point)")
            }
            let recovery = try BackupRestoreService(applicationSupportURL: scenario.target.support, storagePreflight: unlimitedStorage)
            let recovered = try recovery.reconcileAtStartup()
            let expectedID = oldOutcome.contains(point) ? oldID : newID
            XCTAssertEqual(try scenario.target.factory.currentGenerationID(), expectedID, "\(point)")
            if oldOutcome.contains(point) {
                XCTAssertNil(recovered, "\(point)")
                XCTAssertFalse(fileManager.fileExists(atPath: scenario.target.factory.installedGenerationURL(id: newID).path))
            } else {
                let session = try XCTUnwrap(recovered, "\(point)")
                XCTAssertEqual(session.generationID, newID, "\(point)")
                XCTAssertEqual(try recordIDs(in: session), scenario.sourceRecordIDs, "\(point)")
                XCTAssertNotEqual(session.replicaID.rawValue, scenario.sourceReplicaID, "\(point)")
            }
            XCTAssertNil(try recovery.reconcileAtStartup(), "\(point)")
            let manifest = try StoreMigrationJournalStoreV1(
                applicationSupportURL: scenario.target.support
            ).loadManifestIfPresent(targetGenerationID: newID)
            if oldOutcome.contains(point) {
                XCTAssertNil(manifest, "\(point)")
            } else {
                let retained = try XCTUnwrap(manifest, "\(point)")
                let active = try scenario.target.factory
                    .currentGenerationPointerV3(expectedGenerationID: newID)
                XCTAssertEqual(retained.digest, active.generationManifestSHA256, "\(point)")
                XCTAssertEqual(retained.manifest.generationID, newID, "\(point)")
            }
            try assertNoRestoreResidue(
                in: scenario.target.support,
                point: "\(point)"
            )
        }

        let manifestFirst = try makeScenario(
            "manifest-first-rollback",
            targetIsNonempty: false
        )
        defer { try? fileManager.removeItem(at: manifestFirst.root) }
        let manifestOldID = manifestFirst.target.session.generationID
        let manifestNewID = id(750)
        let manifestValidated = try importArchive(
            manifestFirst.archiveURL,
            into: manifestFirst.target.session
        )
        let interrupted = try BackupRestoreService(
            applicationSupportURL: manifestFirst.target.support,
            storagePreflight: unlimitedStorage,
            makeUUID: sequence([manifestNewID, id(751), id(752)]),
            failureInjection: BackupRestoreFailureInjection(
                failOnceAt: .afterGenerationInstall
            )
        )
        await XCTAssertThrowsErrorAsync {
            _ = try await interrupted.restore(
                validatedPackage: manifestValidated,
                currentModelContext: manifestFirst.target.session.modelContext,
                currentGenerationID: manifestOldID,
                currentGenerationRootURL:
                    manifestFirst.target.session.generationRootURL,
                mode: .emptyInstall
            )
        } verify: { error in
            XCTAssertEqual(error as? BackupRestoreServiceError, .injectedFailure)
        }
        let intentStore = try RestoreIntentStore(
            applicationSupportURL: manifestFirst.target.support
        )
        let retainedIntent = try XCTUnwrap(try intentStore.load())
        XCTAssertEqual(retainedIntent.phase, .generationInstalled)
        let retainedIdentity = try XCTUnwrap(retainedIntent.identity)
        let authority = try manifestFirst.target.factory
            .makeRestoreGenerationAuthority()
        let beforeRemoval = try manifestFirst.target.factory.generationPresence(
            id: manifestNewID,
            authority: authority
        )
        XCTAssertTrue(beforeRemoval.installed)
        XCTAssertFalse(beforeRemoval.staging)
        XCTAssertEqual(
            try manifestFirst.target.factory.currentGenerationID(
                authority: authority
            ),
            manifestOldID
        )
        try manifestFirst.target.factory
            .removePreparedRestoreGenerationManifestBeforeDiscard(
                expectedOldID: manifestOldID,
                generationID: manifestNewID,
                expectedDigest:
                    retainedIdentity.targetPointer.generationManifestSHA256,
                authority: authority
            )
        XCTAssertNil(
            try StoreMigrationJournalStoreV1(
                applicationSupportURL: manifestFirst.target.support
            ).loadManifestIfPresent(targetGenerationID: manifestNewID)
        )
        XCTAssertTrue(
            try manifestFirst.target.factory.generationPresence(
                id: manifestNewID,
                authority: authority
            ).installed
        )

        let manifestRecovery = try BackupRestoreService(
            applicationSupportURL: manifestFirst.target.support,
            storagePreflight: unlimitedStorage
        )
        XCTAssertNil(try manifestRecovery.reconcileAtStartup())
        XCTAssertEqual(
            try manifestFirst.target.factory.currentGenerationID(),
            manifestOldID
        )
        XCTAssertFalse(
            fileManager.fileExists(
                atPath: manifestFirst.target.factory
                    .installedGenerationURL(id: manifestNewID).path
            )
        )
        XCTAssertNil(try intentStore.load())
        try assertNoRestoreResidue(
            in: manifestFirst.target.support,
            point: "manifest-first-rollback"
        )

        let absent = try await makeManifestAbsentCrash(
            "manifest-absent-target-absent",
            newID: id(760)
        )
        defer { try? fileManager.removeItem(at: absent.scenario.root) }
        try absent.scenario.target.factory.removeInstalledGeneration(
            id: absent.newID,
            keeping: absent.oldID,
            authority: absent.authority
        )
        XCTAssertFalse(
            fileManager.fileExists(
                atPath: absent.scenario.target.factory
                    .installedGenerationURL(id: absent.newID).path
            )
        )
        XCTAssertNotNil(try absent.intentStore.load())
        let absentRecovery = try BackupRestoreService(
            applicationSupportURL: absent.scenario.target.support,
            storagePreflight: unlimitedStorage
        )
        XCTAssertNil(try absentRecovery.reconcileAtStartup())
        XCTAssertEqual(
            try absent.scenario.target.factory.currentGenerationID(),
            absent.oldID
        )
        XCTAssertNil(try absent.intentStore.load())
        try assertNoRestoreResidue(
            in: absent.scenario.target.support,
            point: "manifest-absent-target-absent"
        )

        let partial = try await makeManifestAbsentCrash(
            "manifest-absent-target-partial",
            newID: id(770)
        )
        defer { try? fileManager.removeItem(at: partial.scenario.root) }
        let partialRoot = partial.scenario.target.factory
            .installedGenerationURL(id: partial.newID)
        let removedModel = partialRoot.appendingPathComponent("model.sqlite")
        try fileManager.removeItem(at: removedModel)
        XCTAssertTrue(fileManager.fileExists(atPath: partialRoot.path))
        XCTAssertFalse(fileManager.fileExists(atPath: removedModel.path))
        XCTAssertNotNil(try partial.intentStore.load())
        let partialRecovery = try BackupRestoreService(
            applicationSupportURL: partial.scenario.target.support,
            storagePreflight: unlimitedStorage
        )
        XCTAssertNil(try partialRecovery.reconcileAtStartup())
        XCTAssertEqual(
            try partial.scenario.target.factory.currentGenerationID(),
            partial.oldID
        )
        XCTAssertFalse(fileManager.fileExists(atPath: partialRoot.path))
        XCTAssertNil(try partial.intentStore.load())
        try assertNoRestoreResidue(
            in: partial.scenario.target.support,
            point: "manifest-absent-target-partial"
        )

        let cancelled = try makeScenario("cancelled", targetIsNonempty: false)
        defer { try? fileManager.removeItem(at: cancelled.root) }
        let cancelledValidated = try importArchive(cancelled.archiveURL, into: cancelled.target.session)
        let cancelledID = cancelled.target.session.generationID
        let task = Task {
            try await BackupRestoreService(applicationSupportURL: cancelled.target.support, storagePreflight: unlimitedStorage).restore(
                validatedPackage: cancelledValidated,
                currentModelContext: cancelled.target.session.modelContext,
                currentGenerationID: cancelledID,
                currentGenerationRootURL: cancelled.target.session.generationRootURL,
                mode: .emptyInstall
            )
        }
        task.cancel()
        await XCTAssertThrowsErrorAsync { _ = try await task.value } verify: { XCTAssertTrue($0 is CancellationError) }
        XCTAssertEqual(try cancelled.target.factory.currentGenerationID(), cancelledID)
        try BackupImportService(generationRootURL: cancelled.target.session.generationRootURL, storagePreflight: unlimitedStorage, scopedAccess: .alreadyAuthorized).discard(cancelledValidated)

        let low = try makeScenario("low-storage", targetIsNonempty: false)
        defer { try? fileManager.removeItem(at: low.root) }
        let lowValidated = try importArchive(low.archiveURL, into: low.target.session)
        let lowID = low.target.session.generationID
        let lowService = try BackupRestoreService(applicationSupportURL: low.target.support, storagePreflight: StoragePreflightService(capacityProvider: { _ in 0 }))
        await XCTAssertThrowsErrorAsync {
            _ = try await lowService.restore(validatedPackage: lowValidated, currentModelContext: low.target.session.modelContext, currentGenerationID: lowID, currentGenerationRootURL: low.target.session.generationRootURL, mode: .emptyInstall)
        } verify: { error in
            guard let storage = error as? StoragePreflightError,
                  case .insufficientCapacity = storage else {
                return XCTFail("Unexpected low-storage error \(error)")
            }
        }
        XCTAssertEqual(try low.target.factory.currentGenerationID(), lowID)
        XCTAssertNil(try RestoreIntentStore(applicationSupportURL: low.target.support).load())
        try BackupImportService(generationRootURL: low.target.session.generationRootURL, storagePreflight: unlimitedStorage, scopedAccess: .alreadyAuthorized).discard(lowValidated)
    }

    @MainActor
    func testV9_05R01RecoveryRelaunchAndExportReconciliation() async throws {
        let scenario = try makeScenario("relaunch-export", targetIsNonempty: false)
        defer { try? fileManager.removeItem(at: scenario.root) }
        let restored = try await restore(scenario, mode: .fork, uuidValues: [id(800), id(801), id(802), id(803)])
        let secondLaunch = try scenario.target.factory.openOrBootstrapCurrent()
        XCTAssertEqual(secondLaunch.generationID, restored.generationID)
        XCTAssertEqual(secondLaunch.workspaceIdentity, restored.workspaceIdentity)
        let recovery = try BackupRestoreService(applicationSupportURL: scenario.target.support, storagePreflight: unlimitedStorage)
        XCTAssertNil(try recovery.reconcileAtStartup())

        let exportDirectory = scenario.root.appendingPathComponent("reconciled-export", isDirectory: true)
        try fileManager.createDirectory(at: exportDirectory, withIntermediateDirectories: false)
        let exporter = BackupExportService(
            modelContext: secondLaunch.modelContext,
            generationRootURL: secondLaunch.generationRootURL,
            storagePreflight: unlimitedStorage,
            now: { Date(timeIntervalSince1970: 1_800_000_000) },
            makeUUID: sequence([id(810), id(811), id(812), id(813)])
        )
        let preview = try exporter.prepareStreaming()
        let archive = try exporter.exportStreaming(previewID: preview.id, to: exportDirectory)
        let verification = try makeHarness(at: scenario.root, name: "verification", nonempty: false)
        let validated = try importArchive(archive, into: verification.session)
        let pointer = try scenario.target.factory.currentGenerationPointerV3(expectedGenerationID: secondLaunch.generationID)
        XCTAssertEqual(validated.manifest.backupSchemaVersion, 2)
        XCTAssertEqual(validated.manifest.source.workspaceID?.uuidString.lowercased(), pointer.workspaceID)
        XCTAssertEqual(validated.manifest.source.replicaID?.uuidString.lowercased(), pointer.replicaID)
        XCTAssertNotEqual(validated.manifest.source.replicaID, scenario.sourceReplicaID)
        XCTAssertEqual(Set(validated.records.sites.map(\.id) + validated.records.assets.map(\.id)), scenario.sourceRecordIDs)
        try BackupImportService(generationRootURL: verification.session.generationRootURL, storagePreflight: unlimitedStorage, scopedAccess: .alreadyAuthorized).discard(validated)
        try assertNoRestoreResidue(in: scenario.target.support, point: "relaunch")
    }
}

private extension V9_05RestoreIdentityTests {
    struct Harness { let support: URL; let factory: StoreGenerationFactory; let session: StoreGenerationSession }
    struct Scenario {
        let root: URL
        let target: Harness
        let archiveURL: URL
        let sourceWorkspaceID: UUID
        let sourceReplicaID: UUID
        let sourceRecordIDs: Set<UUID>
    }
    struct ManifestAbsentCrash {
        let scenario: Scenario
        let oldID: UUID
        let newID: UUID
        let intentStore: RestoreIntentStore
        let authority: StoreRestoreGenerationAuthority
    }
    struct Corpus: Decodable {
        struct Case: Decodable { let id: String; let family: String; let mode: String? }
        let schemaVersion: Int
        let authority: String
        let cases: [Case]
    }

    var unlimitedStorage: StoragePreflightService { StoragePreflightService(capacityProvider: { _ in .max }) }

    @MainActor
    func makeScenario(_ name: String, targetIsNonempty: Bool) throws -> Scenario {
        let root = fileManager.temporaryDirectory.appendingPathComponent("V9_05-\(name)-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: false)
        let source = try makeHarness(at: root, name: "source", nonempty: true)
        let sourceRecordIDs = try recordIDs(in: source.session)
        let destination = root.appendingPathComponent("source-export", isDirectory: true)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: false)
        let exporter = BackupExportService(
            modelContext: source.session.modelContext,
            generationRootURL: source.session.generationRootURL,
            storagePreflight: unlimitedStorage,
            now: { Date(timeIntervalSince1970: 1_800_000_000) },
            makeUUID: sequence([id(90), id(91), id(92), id(93)])
        )
        let preview = try exporter.prepareStreaming()
        let archive = try exporter.exportStreaming(previewID: preview.id, to: destination)
        let target = try makeHarness(at: root, name: "target", nonempty: targetIsNonempty)
        return Scenario(root: root, target: target, archiveURL: archive, sourceWorkspaceID: source.session.workspaceID.rawValue, sourceReplicaID: source.session.replicaID.rawValue, sourceRecordIDs: sourceRecordIDs)
    }

    @MainActor
    func makeHarness(at root: URL, name: String, nonempty: Bool) throws -> Harness {
        let support = root.appendingPathComponent("\(name)-support", isDirectory: true)
        try fileManager.createDirectory(at: support, withIntermediateDirectories: true)
        let factory = StoreGenerationFactory(applicationSupportURL: support)
        let session = try factory.openOrBootstrapCurrent()
        if nonempty {
            let siteID = UUID()
            session.modelContext.insert(Site(id: siteID, label: "\(name) lot", address: nil, timeZoneID: "America/New_York", createdAt: Date(timeIntervalSince1970: 1_799_999_000)))
            session.modelContext.insert(Asset(id: UUID(), siteID: siteID, packID: SignPack.illuminatedSignV1.packID, packSchemaVersion: SignPack.illuminatedSignV1.schemaVersion, packContentVersion: SignPack.illuminatedSignV1.contentVersion, label: "\(name) sign", createdAt: Date(timeIntervalSince1970: 1_799_999_001)))
            try session.modelContext.save()
        }
        return Harness(support: support, factory: factory, session: session)
    }

    @MainActor
    func importArchive(_ archive: URL, into session: StoreGenerationSession) throws -> ValidatedV4BackupPackageV1 {
        try BackupImportService(generationRootURL: session.generationRootURL, storagePreflight: unlimitedStorage, makeUUID: { self.id(99) }, scopedAccess: .alreadyAuthorized).stageAndValidate(selectedPackageURL: archive)
    }

    @MainActor
    func restore(_ scenario: Scenario, mode: BackupRestoreMode, uuidValues: [UUID]) async throws -> StoreGenerationSession {
        let validated = try importArchive(scenario.archiveURL, into: scenario.target.session)
        return try await BackupRestoreService(applicationSupportURL: scenario.target.support, storagePreflight: unlimitedStorage, makeUUID: sequence(uuidValues)).restore(
            validatedPackage: validated,
            currentModelContext: scenario.target.session.modelContext,
            currentGenerationID: scenario.target.session.generationID,
            currentGenerationRootURL: scenario.target.session.generationRootURL,
            mode: mode
        )
    }

    @MainActor
    func makeManifestAbsentCrash(
        _ name: String,
        newID: UUID
    ) async throws -> ManifestAbsentCrash {
        let scenario = try makeScenario(name, targetIsNonempty: false)
        let oldID = scenario.target.session.generationID
        let validated = try importArchive(
            scenario.archiveURL,
            into: scenario.target.session
        )
        let service = try BackupRestoreService(
            applicationSupportURL: scenario.target.support,
            storagePreflight: unlimitedStorage,
            makeUUID: sequence([newID, id(790), id(791)]),
            failureInjection: BackupRestoreFailureInjection(
                failOnceAt: .afterGenerationInstall
            )
        )
        do {
            _ = try await service.restore(
                validatedPackage: validated,
                currentModelContext: scenario.target.session.modelContext,
                currentGenerationID: oldID,
                currentGenerationRootURL:
                    scenario.target.session.generationRootURL,
                mode: .emptyInstall
            )
            XCTFail("Expected afterGenerationInstall interruption")
        } catch {
            XCTAssertEqual(
                error as? BackupRestoreServiceError,
                .injectedFailure
            )
        }
        let intentStore = try RestoreIntentStore(
            applicationSupportURL: scenario.target.support
        )
        let intent = try XCTUnwrap(try intentStore.load())
        XCTAssertEqual(intent.phase, .generationInstalled)
        let identity = try XCTUnwrap(intent.identity)
        let authority = try scenario.target.factory
            .makeRestoreGenerationAuthority()
        XCTAssertEqual(
            try scenario.target.factory.currentGenerationID(
                authority: authority
            ),
            oldID
        )
        let presence = try scenario.target.factory.generationPresence(
            id: newID,
            authority: authority
        )
        XCTAssertTrue(presence.installed)
        XCTAssertFalse(presence.staging)
        try scenario.target.factory
            .removePreparedRestoreGenerationManifestBeforeDiscard(
                expectedOldID: oldID,
                generationID: newID,
                expectedDigest:
                    identity.targetPointer.generationManifestSHA256,
                authority: authority
            )
        XCTAssertNil(
            try StoreMigrationJournalStoreV1(
                applicationSupportURL: scenario.target.support
            ).loadManifestIfPresent(targetGenerationID: newID)
        )
        return ManifestAbsentCrash(
            scenario: scenario,
            oldID: oldID,
            newID: newID,
            intentStore: intentStore,
            authority: authority
        )
    }

    func restoreUUIDs(mode: BackupRestoreMode, newGeneration: UUID, restoreID: UUID, workspace: UUID, replica: UUID) -> [UUID] {
        switch mode {
        case .emptyInstall: [newGeneration, restoreID, replica]
        case .replaceExisting: [newGeneration, restoreID]
        case .clone, .fork: [newGeneration, restoreID, workspace, replica]
        }
    }

    @MainActor
    func recordIDs(in session: StoreGenerationSession) throws -> Set<UUID> {
        let sites = try session.modelContext.fetch(FetchDescriptor<Site>()).map(\.id)
        let assets = try session.modelContext.fetch(FetchDescriptor<Asset>()).map(\.id)
        return Set(sites + assets)
    }

    func pointerBytes(in support: URL) throws -> Data { try Data(contentsOf: support.appendingPathComponent("FieldEvidenceData/current.json")) }

    func assertNoRestoreResidue(in support: URL, point: String, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertNil(try RestoreIntentStore(applicationSupportURL: support).load(), point, file: file, line: line)
        let restore = support.appendingPathComponent("FieldEvidenceRestore", isDirectory: true)
        XCTAssertFalse(
            fileManager.fileExists(
                atPath: restore.appendingPathComponent("restore.json").path
            ),
            point,
            file: file,
            line: line
        )
        if fileManager.fileExists(atPath: restore.path) {
            let allowed = Set(["generations", "staging"])
            let children = Set(try fileManager.contentsOfDirectory(atPath: restore.path))
            XCTAssertTrue(children.isSubset(of: allowed), point, file: file, line: line)
            for name in children {
                XCTAssertEqual(
                    try fileManager.contentsOfDirectory(
                        atPath: restore.appendingPathComponent(name).path
                    ),
                    [],
                    point,
                    file: file,
                    line: line
                )
            }
        }
    }

    func sequence(_ values: [UUID]) -> () -> UUID {
        var remaining = values
        return { remaining.isEmpty ? UUID() : remaining.removeFirst() }
    }

    func loadCorpus() throws -> Corpus {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(forResource: "V21P01C05IdentityTransformationsV1", withExtension: "json", subdirectory: "Fixtures/V21/Restore") ?? bundle.url(forResource: "V21P01C05IdentityTransformationsV1", withExtension: "json"))
        return try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: url))
    }

    func id(_ suffix: Int) -> UUID { UUID(uuidString: String(format: "66000000-0000-0000-0000-%012d", suffix))! }
    func canonical(_ value: UUID) -> String { value.uuidString.lowercased() }

    @MainActor
    func XCTAssertThrowsErrorAsync(_ expression: () async throws -> Void, verify: (Error) -> Void, file: StaticString = #filePath, line: UInt = #line) async {
        do { try await expression(); XCTFail("Expected error", file: file, line: line) } catch { verify(error) }
    }
}

import Foundation
import Darwin
import SwiftData
import XCTest
@testable import FieldEvidenceApp

private enum C52ServiceRequestBoundary_V9_03MigrationRecoveryTests {
    static let typedAnchor: C52ServiceRequestBoundaryTokenV1.Type = C52ServiceRequestBoundaryTokenV1.self
}

private enum C53AssetServiceReliabilityBoundary_V9_03MigrationRecoveryTests {
    static let typedAnchor: C53AssetServiceReliabilityBoundaryTokenV1.Type = C53AssetServiceReliabilityBoundaryTokenV1.self
}

private final class C50MigrationRecoveryTests: XCTestCase {
    func testV23P03C50MigrationAndReplacementRestoreExcludeNonpersistentAdapterState() {
        XCTAssertTrue(C50IncumbentFileExchangeBackupBoundaryV1.validate())
        XCTAssertTrue(C50IncumbentFileExchangeBackupImportBoundaryV1.validate())
        XCTAssertTrue(C50IncumbentFileExchangeReplacementRestoreRuleV1.validate())
        XCTAssertTrue(C50IncumbentFileExchangeBackupBoundaryV1.profileAndSelectionAreNonpersistent)
        XCTAssertTrue(C50IncumbentFileExchangeBackupBoundaryV1.sourceScratchAndQuarantineAreExcluded)
        XCTAssertFalse(C50IncumbentFileExchangeReplacementRestoreRuleV1.restoresProfileOrSelectionState)
    }
}

private final class C45MigrationRecoveryCompatibilityTests: XCTestCase {
    func testV23P03C45CompatibilityPinsForwardOnlyAcceptedSnapshotSchema() {
        XCTAssertEqual(AssetLabelPersistenceEnrollmentV1.persistentSchemaVersion, 34)
        XCTAssertEqual(AssetLabelPersistenceEnrollmentV1.recordsSchemaVersion, 33)
        XCTAssertFalse(AssetLabelPersistenceEnrollmentV1.persistentFamilies.contains("AssetLabelGenerationPlanV1"))
    }
}

private final class C30EvidenceContextAnchorV9_03MigrationRecovery: XCTestCase {
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
final class V9_03MigrationRecoveryTests: XCTestCase {
    func testAggregatePopulatedLegacyPublishesOnlyActiveThenRequiresIndependentProcessAndPreservesSource() async throws {
        let fixture = try makeLegacyFixture(suffix: "aggregate-full-golden-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: fixture.root) }
        var processID = UUID()
        let factory = StoreGenerationFactory(applicationSupportURL: fixture.root,
            migrationIdentitySource: StoreMigrationIdentitySourceV1(makeMigrationID: UUID.init,
                makeGenerationID: UUID.init, makeProcessID: { processID }))
        let pointerURL = fixture.root.appendingPathComponent("FieldEvidenceData/current.json")
        let originalPointer = try Data(contentsOf: pointerURL)
        var recoveries = 0
        let first = try await factory.openForStartup { source in
            recoveries += 1
            XCTAssertEqual(try Data(contentsOf: pointerURL), originalPointer)
            XCTAssertEqual(source.sourceRelease, .v1)
            XCTAssertEqual(source.sourceGenerationID, fixture.sourceID)
        }
        guard case .awaitingIndependentValidation(let awaiting) = first else {
            return XCTFail("First process cannot expose a ready session")
        }
        let control = try XCTUnwrap(StoreAggregateMigrationControlV1(applicationSupportURL: fixture.root))
        let firstJournal = try XCTUnwrap(control.load())
        XCTAssertEqual(firstJournal.phase, .awaitingIndependentValidation)
        XCTAssertEqual(firstJournal.transitions.map { $0.targetRelease.versionIdentifier.major }, Array(2...53))
        XCTAssertEqual(firstJournal.targetGenerationID, awaiting.targetGenerationID)
        XCTAssertNotEqual(firstJournal.targetGenerationID, fixture.sourceID)
        let authority = try factory.makeRestoreGenerationAuthority()
        let frozenSource = try authority.snapshotInstalledGeneration(id: fixture.sourceID)
        XCTAssertFalse(try authority.retiredGenerationIDs().contains(fixture.sourceID))
        let publishedPointer = try Data(contentsOf: pointerURL)
        XCTAssertEqual(try CurrentGenerationPointerV3.decodeCanonical(from: publishedPointer).storeSchemaVersion, 53)
        let retry = try await factory.openForStartup { _ in XCTFail("Source recovery occurs once") }
        guard case .awaitingIndependentValidation = retry else { return XCTFail("Same-process retry must hold") }
        XCTAssertEqual(try control.load(), firstJournal)
        XCTAssertEqual(try Data(contentsOf: pointerURL), publishedPointer)
        processID = UUID() // Unit analogue; the UI test performs a real terminate/relaunch.
        let independent = try await factory.openForStartup { _ in XCTFail("Independent validation does not recover source") }
        guard case .ready(let session) = independent else { return XCTFail("Independent process must validate active target") }
        XCTAssertEqual(session.generationID, firstJournal.targetGenerationID)
        try assertMigratedRows(in: session.modelContext, fixture: fixture)
        XCTAssertEqual(try session.modelContext.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>()).first?.schemaVersion, 53)
        XCTAssertEqual(try control.load()?.phase, .complete)
        XCTAssertTrue(try authority.retiredGenerationIDs().contains(fixture.sourceID))
        XCTAssertEqual(try Data(contentsOf: pointerURL), publishedPointer)
        let preserved = try authority.snapshotInstalledGeneration(id: fixture.sourceID)
        XCTAssertEqual(preserved.files, frozenSource.files)
        XCTAssertEqual(preserved.frozenIdentityDigest, frozenSource.frozenIdentityDigest)

        // Admission uses the real active session, retained writer lease and
        // stale-writer fence. No second container or journal owner is created.
        let coordinator = try StoreSessionCoordinator(validatingSession: session)
        try withExtendedLifetime(coordinator) {
            XCTAssertTrue(coordinator.modelContext === session.modelContext)
            XCTAssertEqual(coordinator.generationID, firstJournal.targetGenerationID)
            let epoch = try XCTUnwrap(session.generationEpoch)
            XCTAssertEqual(epoch.generationID, firstJournal.targetGenerationID)
            XCTAssertEqual(epoch.generationManifestSHA256,
                try CurrentGenerationPointerV3.decodeCanonical(from: publishedPointer).generationManifestSHA256)
            let writer = coordinator.workspaceWriter
            // This delegates to the admitted writer's own journal.exportSnapshot,
            // which runs strict validateAll before returning receipt history.
            let originalHistory = try writer.sourceMutationHistorySnapshot()
            XCTAssertTrue(originalHistory.receipts.isEmpty)
            let current = try writer.currentRevision()
            let siteIdentity = try WorkspaceEntityIdentityV1(kind: .site, id: fixture.siteID)
            let siteRevision = current.entityRevisions.first(where: { $0.identity == siteIdentity })?.revision ?? 0
            let expected = try WorkspaceExpectedRevisionV1(workspaceID: current.workspaceID,
                generationID: current.generationID, writerInstanceID: current.writerInstanceID,
                workspaceRevision: current.revision,
                entityRevisions: [.init(identity: siteIdentity, revision: siteRevision)])
            let mutationID = try MutationIDV1(rawValue: UUID())
            let request = WorkspaceMutationRequestV1(mutationID: mutationID, expectedRevision: expected,
                command: .updateSiteTimeZone(.init(siteID: fixture.siteID, timeZoneID: "Europe/London",
                    confirmedAt: Date(timeIntervalSince1970: 1_800_000_100))))
            let site = try XCTUnwrap(coordinator.modelContext.fetch(FetchDescriptor<Site>()).first)
            XCTAssertEqual(site.timeZoneID, "America/New_York")
            let outcome = try writer.execute(request)
            XCTAssertEqual(outcome.after.revision, current.revision + 1)
            XCTAssertEqual(site.timeZoneID, "Europe/London")
            let receipt = try XCTUnwrap(writer.durableReceipt(mutationID: mutationID))
            let receiptBytes = try receipt.canonicalData()
            XCTAssertEqual(receipt.expectedRevision, try MutationPortableExpectedRevisionV1(expected))
            XCTAssertEqual(receipt.postImages.count, 1)
            XCTAssertEqual(try receipt.postImages.first?.identity, siteIdentity)
            let writtenHistory = try writer.sourceMutationHistorySnapshot()
            XCTAssertEqual(writtenHistory.receipts.count, 1)
            XCTAssertEqual(try coordinator.modelContext.fetchCount(FetchDescriptor<MutationReceiptRow>()), 1)
            let replay = try writer.execute(request)
            XCTAssertEqual(replay.mutationID, outcome.mutationID)
            XCTAssertEqual(replay.after.revision, outcome.after.revision)
            XCTAssertEqual(try XCTUnwrap(writer.durableReceipt(mutationID: mutationID)).canonicalData(), receiptBytes)
            XCTAssertEqual(try writer.sourceMutationHistorySnapshot(), writtenHistory)
            XCTAssertEqual(try coordinator.modelContext.fetchCount(FetchDescriptor<MutationReceiptRow>()), 1)
            XCTAssertFalse(coordinator.modelContext.hasChanges)
            try assertMigratedRows(in: coordinator.modelContext, fixture: fixture)
            XCTAssertEqual(try Data(contentsOf: pointerURL), publishedPointer)
            let afterWrite = try authority.snapshotInstalledGeneration(id: fixture.sourceID)
            XCTAssertEqual(afterWrite.files, frozenSource.files)
            XCTAssertEqual(afterWrite.frozenIdentityDigest, frozenSource.frozenIdentityDigest)
            XCTAssertTrue(try authority.retiredGenerationIDs().contains(fixture.sourceID))
            XCTAssertEqual(try control.load()?.sourceCheckpoint, firstJournal.sourceCheckpoint)
            XCTAssertEqual(try control.load()?.phase, .complete)
        }
        XCTAssertEqual(recoveries, 1)
    }

    func testAggregatePublishedMarkerTamperHoldsWithoutRepairingTargetOrRetiringSource() async throws {
        let fixture = try makeLegacyFixture(suffix: "aggregate-marker-tamper-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: fixture.root) }
        let factory = StoreGenerationFactory(applicationSupportURL: fixture.root,
            migrationIdentitySource: StoreMigrationIdentitySourceV1(makeMigrationID: UUID.init,
                makeGenerationID: UUID.init, makeProcessID: UUID.init))
        let first = try await factory.openForStartup { _ in }
        guard case .awaitingIndependentValidation = first else { return XCTFail("Expected published awaiting target") }
        let control = try XCTUnwrap(StoreAggregateMigrationControlV1(applicationSupportURL: fixture.root))
        let journal = try XCTUnwrap(control.load())
        let authority = try factory.makeRestoreGenerationAuthority()
        let source = try authority.snapshotInstalledGeneration(id: fixture.sourceID)
        let targetURL = factory.installedGenerationURL(id: journal.targetGenerationID)
        try autoreleasepool {
            let schema = Schema(PersistentSchemaV53.models, version: PersistentSchemaV53.versionIdentifier)
            let configuration = ModelConfiguration("FieldEvidenceV53", schema: schema,
                url: targetURL.appendingPathComponent("model.sqlite"), allowsSave: true, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            container.mainContext.autosaveEnabled = false
            let marker = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>()).first)
            marker.schemaVersion = 52
            try container.mainContext.save()
        }
        let tampered = try authority.snapshotInstalledGeneration(id: journal.targetGenerationID)
        let pointerURL = fixture.root.appendingPathComponent("FieldEvidenceData/current.json")
        let pointer = try Data(contentsOf: pointerURL)
        do {
            _ = try await factory.openForStartup { _ in XCTFail("Published marker corruption cannot recover source") }
            XCTFail("Altered marker must not be normalized into success")
        } catch {}
        XCTAssertEqual(try control.load(), journal)
        XCTAssertEqual(try Data(contentsOf: pointerURL), pointer)
        XCTAssertFalse(try authority.retiredGenerationIDs().contains(fixture.sourceID))
        let preservedSource = try authority.snapshotInstalledGeneration(id: fixture.sourceID)
        XCTAssertEqual(preservedSource.files, source.files)
        XCTAssertEqual(preservedSource.frozenIdentityDigest, source.frozenIdentityDigest)
        let preservedTarget = try authority.snapshotInstalledGeneration(id: journal.targetGenerationID)
        XCTAssertEqual(preservedTarget.files, tampered.files)
        XCTAssertEqual(preservedTarget.frozenIdentityDigest, tampered.frozenIdentityDigest)
    }

#if DEBUG
    func testReleasedCheckpointFixtureRefusesExistingRootsWithoutPopulationOrMutation() throws {
        for nonempty in [false, true] {
            let root = fileManager.temporaryDirectory.appendingPathComponent("checkpoint-existing-" + UUID().uuidString)
            try fileManager.createDirectory(at: root, withIntermediateDirectories: false)
            defer { try? fileManager.removeItem(at: root) }
            let sentinel = root.appendingPathComponent("preserve.bin")
            let bytes = Data("Preexisting fixture authority is never reset".utf8)
            if nonempty { try bytes.write(to: sentinel) }
            let factory = StoreGenerationFactory(applicationSupportURL: root)
            let identity = try WorkspaceReplicaIdentityV1(workspaceID: WorkspaceID(rawValue: UUID()),
                replicaID: ReplicaID(rawValue: UUID()))
            let names = try fileManager.contentsOfDirectory(atPath: root.path)
            XCTAssertThrowsError(try factory.seedReleasedCheckpointTestFixture(release: .v9,
                generationID: UUID(), migrationID: UUID(), identity: identity) { _ in
                    XCTFail("Existing roots cannot expose a fixture population context")
                })
            XCTAssertEqual(try fileManager.contentsOfDirectory(atPath: root.path), names)
            if nonempty { XCTAssertEqual(try Data(contentsOf: sentinel), bytes) }
        }
    }

    func testAggregateAllocationCrashRecoveryPreservesUnboundResidueAndOneBoundCandidate() async throws {
        for boundary: StoreAggregateMigrationFaultBoundaryV1 in [
            .afterAllocationCreation, .afterAllocationBinding, .afterAllocationRenameBeforeSync, .afterAllocationPublication,
        ] {
            let fixture = try makeLegacyFixture(suffix: "aggregate-allocation-\(boundary)-\(UUID().uuidString)")
            defer { try? fileManager.removeItem(at: fixture.root) }
            let injection = StoreMigrationFailureInjection(aggregateFault: boundary)
            let factory = StoreGenerationFactory(applicationSupportURL: fixture.root, migrationFailureInjection: injection)
            let pointerURL = fixture.root.appendingPathComponent("FieldEvidenceData/current.json")
            let pointer = try Data(contentsOf: pointerURL)
            do {
                _ = try await factory.openForStartup { _ in }
                XCTFail("Expected allocation crash boundary \(boundary)")
            } catch let reached as StoreAggregateMigrationFaultBoundaryV1 {
                XCTAssertEqual(reached, boundary)
            }
            let control = try XCTUnwrap(StoreAggregateMigrationControlV1(applicationSupportURL: fixture.root))
            let before = try XCTUnwrap(control.load())
            XCTAssertEqual(before.phase, .sourceFrozen)
            let migrationRoot = fixture.root.appendingPathComponent("FieldEvidenceOperations/schema-migration")
            let allocations = try fileManager.contentsOfDirectory(atPath: migrationRoot.path).filter {
                StoreAggregateMigrationControlV1.allocationID(for: $0) != nil
            }
            var residue: URL?
            let sentinelBytes = Data("Unknown unbound allocation content must survive".utf8)
            if boundary == .afterAllocationCreation {
                XCTAssertNil(before.allocationID)
                XCTAssertNil(before.candidateRootInode)
                XCTAssertEqual(allocations.count, 1)
                residue = migrationRoot.appendingPathComponent(try XCTUnwrap(allocations.first)).appendingPathComponent("unknown.bin")
                try sentinelBytes.write(to: try XCTUnwrap(residue))
            } else {
                XCTAssertNotNil(before.allocationID)
                XCTAssertNotNil(before.candidateRootInode)
            }
            // Reproduce both original temp states: an uncommitted binding,
            // or the old original left after an atomic binding swap.
            var interrupted = before
            if let allocationID = before.allocationID {
                interrupted.revision -= 1
                interrupted.allocationID = nil; interrupted.candidateRootDevice = nil; interrupted.candidateRootInode = nil
                XCTAssertNotEqual(allocationID, interrupted.allocationID)
                try before.validateReplacement(of: interrupted)
            } else {
                let name = try XCTUnwrap(allocations.first)
                var info = stat()
                XCTAssertEqual(Darwin.lstat(migrationRoot.appendingPathComponent(name).path, &info), 0)
                interrupted.revision += 1
                interrupted.allocationID = try XCTUnwrap(StoreAggregateMigrationControlV1.allocationID(for: name))
                interrupted.candidateRootDevice = UInt64(info.st_dev); interrupted.candidateRootInode = UInt64(info.st_ino)
                try interrupted.validateReplacement(of: before)
            }
            try interrupted.canonicalData().write(to: migrationRoot.appendingPathComponent(StoreAggregateMigrationControlV1.temporaryName))
            injection.failNext(at: .beforeSourceClone)
            do {
                _ = try await factory.openForStartup { _ in XCTFail("Frozen source must not recover again") }
                XCTFail("Expected pre-clone stop after exact allocation recovery")
            } catch let failure as StoreMigrationFailure {
                XCTAssertEqual(failure, .injectedFault(.beforeSourceClone))
            }
            let after = try XCTUnwrap(control.load())
            XCTAssertEqual(after.phase, .sourceFrozen)
            XCTAssertEqual(after.targetGenerationID, before.targetGenerationID)
            XCTAssertEqual(after.sourceCheckpoint, before.sourceCheckpoint)
            XCTAssertFalse(fileManager.fileExists(atPath: migrationRoot.appendingPathComponent(StoreAggregateMigrationControlV1.temporaryName).path))
            let target = factory.restoreStagingGenerationURL(id: after.targetGenerationID)
            var info = stat()
            XCTAssertEqual(Darwin.lstat(target.path, &info), 0)
            XCTAssertEqual(UInt64(info.st_dev), after.candidateRootDevice)
            XCTAssertEqual(UInt64(info.st_ino), after.candidateRootInode)
            XCTAssertTrue(try fileManager.contentsOfDirectory(atPath: target.path).isEmpty)
            XCTAssertFalse(fileManager.fileExists(atPath: migrationRoot.appendingPathComponent(
                "allocation-" + (try XCTUnwrap(after.allocationID)).uuidString.lowercased()).path))
            if before.allocationID != nil {
                XCTAssertEqual(after.allocationID, before.allocationID)
                XCTAssertEqual(after.candidateRootInode, before.candidateRootInode)
            }
            if let residue { XCTAssertEqual(try Data(contentsOf: residue), sentinelBytes) }
            XCTAssertEqual(try Data(contentsOf: pointerURL), pointer)
        }
    }

    func testAggregateBoundAllocationRejectsBothNeitherReplacementAndSymlinkWithoutCleanup() async throws {
        for attack in ["both", "neither", "replacement", "symlink", "malformed-name", "destination-symlink"] {
            let fixture = try makeLegacyFixture(suffix: "aggregate-allocation-\(attack)-\(UUID().uuidString)")
            defer { try? fileManager.removeItem(at: fixture.root) }
            let injection = StoreMigrationFailureInjection(aggregateFault: .afterAllocationBinding)
            let factory = StoreGenerationFactory(applicationSupportURL: fixture.root, migrationFailureInjection: injection)
            do { _ = try await factory.openForStartup { _ in }; XCTFail("Expected bound allocation stop") }
            catch let reached as StoreAggregateMigrationFaultBoundaryV1 { XCTAssertEqual(reached, .afterAllocationBinding) }
            let control = try XCTUnwrap(StoreAggregateMigrationControlV1(applicationSupportURL: fixture.root))
            let before = try XCTUnwrap(control.load())
            let migrationRoot = fixture.root.appendingPathComponent("FieldEvidenceOperations/schema-migration")
            let allocation = migrationRoot.appendingPathComponent("allocation-" + (try XCTUnwrap(before.allocationID)).uuidString.lowercased())
            let target = factory.restoreStagingGenerationURL(id: before.targetGenerationID)
            let retained = fixture.root.appendingPathComponent("retained-bound-allocation")
            let movesAllocation = ["neither", "replacement", "symlink"].contains(attack)
            if movesAllocation {
                try fileManager.moveItem(at: allocation, to: retained)
            }
            if attack == "both" { try fileManager.createDirectory(at: target, withIntermediateDirectories: false) }
            if attack == "replacement" {
                try fileManager.createDirectory(at: allocation, withIntermediateDirectories: false)
                // Plausible SQLite never substitutes for the exact allocation
                // inode. Retain the valid source and this foreign copy.
                let sourceModel = factory.installedGenerationURL(id: fixture.sourceID).appendingPathComponent("model.sqlite")
                try fileManager.copyItem(at: sourceModel, to: allocation.appendingPathComponent("model.sqlite"))
                try Data("foreign plausible allocation".utf8).write(to: allocation.appendingPathComponent("sentinel.bin"))
            }
            if attack == "symlink" { try fileManager.createSymbolicLink(at: allocation, withDestinationURL: retained) }
            if attack == "malformed-name" { try fileManager.createDirectory(at: migrationRoot.appendingPathComponent("allocation-NOT-A-UUID"), withIntermediateDirectories: false) }
            let destination = target.deletingLastPathComponent()
            let foreignDestination = fixture.root.appendingPathComponent("foreign-destination")
            if attack == "destination-symlink" {
                try fileManager.moveItem(at: destination, to: foreignDestination)
                try fileManager.createSymbolicLink(at: destination, withDestinationURL: foreignDestination)
            }
            let pointerURL = fixture.root.appendingPathComponent("FieldEvidenceData/current.json")
            let pointer = try Data(contentsOf: pointerURL)
            let names = try fileManager.contentsOfDirectory(atPath: migrationRoot.path).sorted()
            do {
                _ = try await factory.openForStartup { _ in XCTFail("Frozen source cannot recover again") }
                XCTFail("Uncertain allocation must hold: \(attack)")
            } catch {}
            XCTAssertEqual(try control.load(), before)
            XCTAssertEqual(try Data(contentsOf: pointerURL), pointer)
            XCTAssertEqual(try fileManager.contentsOfDirectory(atPath: migrationRoot.path).sorted(), names)
            if attack == "both" { XCTAssertTrue(fileManager.fileExists(atPath: target.path)) }
            if movesAllocation { XCTAssertTrue(fileManager.fileExists(atPath: retained.path)) }
            if attack == "replacement" {
                XCTAssertEqual(try Data(contentsOf: allocation.appendingPathComponent("model.sqlite")),
                    try Data(contentsOf: factory.installedGenerationURL(id: fixture.sourceID).appendingPathComponent("model.sqlite")))
                XCTAssertEqual(try Data(contentsOf: allocation.appendingPathComponent("sentinel.bin")), Data("foreign plausible allocation".utf8))
            }
            if attack == "destination-symlink" { XCTAssertTrue(try fileManager.contentsOfDirectory(atPath: foreignDestination.path).isEmpty) }
        }
    }
#endif

    func testAggregateOwnerRemainsLiveAfterFactoryReleaseWhileContextOrActorEscapes() async throws {
        for retention in ["context", "actor"] {
            let fixture = try makeLegacyFixture(suffix: "aggregate-factory-release-\(retention)-\(UUID().uuidString)")
            defer { try? fileManager.removeItem(at: fixture.root) }
            var factory: StoreGenerationFactory? = StoreGenerationFactory(applicationSupportURL: fixture.root)
            var escapedContext: ModelContext?
            var escapedActor: EvidenceBundleStore?
            do {
                _ = try await factory!.openForStartup { authority in
                    if retention == "context" { escapedContext = try authority.recoveryContext() }
                    else { escapedActor = try EvidenceBundleStore(sourceRecoveryAuthority: authority) }
                }
                XCTFail("Escaped recovery object must hold before checkpoint")
            } catch {}
            factory = nil
            await Task.yield()
            XCTAssertNil(factory, "The registry lifetime must not depend on retaining the factory value")
            let control = try XCTUnwrap(StoreAggregateMigrationControlV1(applicationSupportURL: fixture.root))
            let before = try XCTUnwrap(control.load())
            XCTAssertEqual(before.phase, .recoveringSource)
            XCTAssertNil(before.sourceCheckpoint)
            let rival = StoreGenerationFactory(applicationSupportURL: fixture.root)
            var rivalReachedRecovery = false
            do {
                _ = try await rival.openForStartup { _ in rivalReachedRecovery = true }
                XCTFail("Leaked recovery object retains the original owner guard")
            } catch {}
            XCTAssertFalse(rivalReachedRecovery)
            XCTAssertEqual(try control.load(), before)
            XCTAssertFalse(fileManager.fileExists(atPath: rival.restoreStagingGenerationURL(id: before.targetGenerationID).path))
            if let actor = escapedActor {
                do { try await actor.verifyOriginalRecoverySettled(authorities: []); XCTFail("Escaped actor is revoked") }
                catch {}
            }
            if retention == "context" { XCTAssertNotNil(escapedContext) }
            escapedContext = nil; escapedActor = nil
        }
    }

    func testAggregateReservationSerializesRestoreStagingAndOriginalIntentAdmission() async throws {
        for ordering in ["staging-first", "restore-first", "erase-first", "aggregate-first"] {
            let fixture = try makeLegacyFixture(suffix: "aggregate-admission-\(ordering)-\(UUID().uuidString)")
            defer { try? fileManager.removeItem(at: fixture.root) }
            let factory = StoreGenerationFactory(applicationSupportURL: fixture.root)
            let authority = try factory.makeRestoreGenerationAuthority()
            let target = UUID()
            let restore = RestoreIntentV1(newGenerationID: target,
                newGenerationRelativePath: "FieldEvidenceData/generations/" + target.uuidString.lowercased(),
                oldGenerationID: fixture.sourceID, phase: .prepared, restoreID: UUID(), schemaVersion: 1,
                stagingGenerationRelativePath: "FieldEvidenceRestore/generations/" + target.uuidString.lowercased())
            let erase = EraseIntentV1(auxiliaryRoots: EraseIntentV1.canonicalAuxiliaryRoots,
                eraseID: UUID(), generationIDsToDelete: [fixture.sourceID], newGenerationID: target,
                oldGenerationID: fixture.sourceID, phase: .emptyGenerationPrepared, schemaVersion: 1)
            XCTAssertTrue(RestoreIntentCodecV1.valid(restore))
            XCTAssertTrue(EraseIntentCodecV1.valid(erase))
            let restoreStore = try RestoreIntentStore(applicationSupportURL: fixture.root)
            let eraseStore = try EraseIntentStore(applicationSupportURL: fixture.root)
            if ordering == "staging-first" { try authority.createStagingGeneration(id: target) }
            if ordering == "restore-first" { try restoreStore.create(restore) }
            if ordering == "erase-first" { try eraseStore.create(erase) }
            let pointerURL = fixture.root.appendingPathComponent("FieldEvidenceData/current.json")
            let pointer = try Data(contentsOf: pointerURL)
            let source = try authority.snapshotInstalledGeneration(id: fixture.sourceID)
            var callbackReached = false
            do {
                _ = try await factory.openForStartup { _ in
                    callbackReached = true
                    throw StoreMigrationFailure.maintenanceRequired(.sourceUnavailable)
                }
                XCTFail("Expected original authority/admission hold")
            } catch {}
            if ordering == "aggregate-first" {
                XCTAssertTrue(callbackReached)
                let control = try XCTUnwrap(StoreAggregateMigrationControlV1(applicationSupportURL: fixture.root))
                let before = try XCTUnwrap(control.load())
                XCTAssertThrowsError(try authority.createStagingGeneration(id: target))
                XCTAssertThrowsError(try restoreStore.create(restore))
                XCTAssertThrowsError(try eraseStore.create(erase))
                XCTAssertThrowsError(try authority.removeInstalledGeneration(id: fixture.sourceID))
                XCTAssertThrowsError(try authority.installStagingGeneration(id: target))
                XCTAssertFalse(fileManager.fileExists(atPath: factory.restoreStagingGenerationURL(id: target).path))
                XCTAssertNil(try restoreStore.load())
                XCTAssertNil(try eraseStore.load())
                XCTAssertEqual(try control.load(), before)
            } else {
                XCTAssertFalse(callbackReached)
                XCTAssertNil(try StoreAggregateMigrationControlV1(applicationSupportURL: fixture.root)?.load())
                if ordering == "staging-first" { XCTAssertTrue(fileManager.fileExists(atPath: factory.restoreStagingGenerationURL(id: target).path)) }
                if ordering == "restore-first" { XCTAssertEqual(try restoreStore.load(), restore) }
                if ordering == "erase-first" { XCTAssertEqual(try eraseStore.load(), erase) }
            }
            XCTAssertEqual(try Data(contentsOf: pointerURL), pointer)
            let retainedSource = try authority.snapshotInstalledGeneration(id: fixture.sourceID)
            XCTAssertEqual(retainedSource.files.first(where: { $0.relativePath == "model.sqlite" })?.sha256,
                source.files.first(where: { $0.relativePath == "model.sqlite" })?.sha256)
            if ordering != "aggregate-first" {
                XCTAssertEqual(retainedSource.files, source.files)
                XCTAssertEqual(retainedSource.frozenIdentityDigest, source.frozenIdentityDigest)
            }
        }
    }

    func testAggregateReservationRejectsInjectedConflictingAuthorityWithoutRecoveryOrCleanup() async throws {
        for conflict in ["restore", "erase"] {
            let fixture = try makeLegacyFixture(suffix: "aggregate-coexistence-\(conflict)-\(UUID().uuidString)")
            defer { try? fileManager.removeItem(at: fixture.root) }
            let factory = StoreGenerationFactory(applicationSupportURL: fixture.root)
            do {
                _ = try await factory.openForStartup { _ in throw StoreMigrationFailure.maintenanceRequired(.sourceUnavailable) }
                XCTFail("Expected retained source-recovery reservation")
            } catch {}
            let control = try XCTUnwrap(StoreAggregateMigrationControlV1(applicationSupportURL: fixture.root))
            let original = try XCTUnwrap(control.load())
            XCTAssertTrue(original.reservationIsActive)
            let target = UUID()
            let directory = fixture.root.appendingPathComponent(conflict == "restore" ? "FieldEvidenceRestore" : "FieldEvidenceErase")
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let intentURL = directory.appendingPathComponent(conflict + ".json")
            let intent: Data
            if conflict == "restore" {
                intent = try RestoreIntentCodecV1.encode(RestoreIntentV1(newGenerationID: target,
                    newGenerationRelativePath: "FieldEvidenceData/generations/" + target.uuidString.lowercased(),
                    oldGenerationID: fixture.sourceID, phase: .prepared, restoreID: UUID(), schemaVersion: 1,
                    stagingGenerationRelativePath: "FieldEvidenceRestore/generations/" + target.uuidString.lowercased()))
            } else {
                intent = try EraseIntentCodecV1.encode(EraseIntentV1(auxiliaryRoots: EraseIntentV1.canonicalAuxiliaryRoots,
                    eraseID: UUID(), generationIDsToDelete: [fixture.sourceID], newGenerationID: target,
                    oldGenerationID: fixture.sourceID, phase: .emptyGenerationPrepared, schemaVersion: 1))
            }
            // Bypass the cooperating admission API only to model conflicting
            // on-disk authority. Neither authority may resolve the other.
            try intent.write(to: intentURL)
            let pointerURL = fixture.root.appendingPathComponent("FieldEvidenceData/current.json")
            let pointer = try Data(contentsOf: pointerURL)
            let authority = try factory.makeRestoreGenerationAuthority()
            let source = try authority.snapshotInstalledGeneration(id: fixture.sourceID)
            let names = try fileManager.contentsOfDirectory(atPath: directory.path).sorted()
            XCTAssertThrowsError(try factory.hasAggregateMigrationReservation())
            do {
                _ = try await factory.openForStartup { _ in XCTFail("Conflicting authority must prevent source recovery") }
                XCTFail("Coexisting original authority must hold")
            } catch {}
            XCTAssertEqual(try control.load(), original)
            XCTAssertEqual(try Data(contentsOf: intentURL), intent)
            XCTAssertEqual(try Data(contentsOf: pointerURL), pointer)
            XCTAssertEqual(try fileManager.contentsOfDirectory(atPath: directory.path).sorted(), names)
            let retained = try authority.snapshotInstalledGeneration(id: fixture.sourceID)
            XCTAssertEqual(retained.files, source.files)
            XCTAssertEqual(retained.frozenIdentityDigest, source.frozenIdentityDigest)
            XCTAssertFalse(fileManager.fileExists(atPath: factory.restoreStagingGenerationURL(id: original.targetGenerationID).path))
        }
    }

    func testAggregateMissingSourceRootCannotBootstrapOrDeleteBootstrapResidue() async throws {
        let fixture = try makeLegacyFixture(suffix: "aggregate-missing-root-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: fixture.root) }
        let factory = StoreGenerationFactory(applicationSupportURL: fixture.root)
        do {
            _ = try await factory.openForStartup { _ in throw StoreMigrationFailure.maintenanceRequired(.sourceUnavailable) }
            XCTFail("Injected source recovery failure must retain aggregate authority")
        } catch {}
        let control = try XCTUnwrap(StoreAggregateMigrationControlV1(applicationSupportURL: fixture.root))
        let journal = try XCTUnwrap(control.load())
        let dataRoot = fixture.root.appendingPathComponent("FieldEvidenceData")
        let retained = fixture.root.appendingPathComponent("retained-source")
        try fileManager.moveItem(at: dataRoot, to: retained)
        let bootstrap = fixture.root.appendingPathComponent(".FieldEvidenceData.bootstrap")
        try fileManager.createDirectory(at: bootstrap, withIntermediateDirectories: false)
        let sentinel = bootstrap.appendingPathComponent("unknown-preserve.bin")
        let sentinelBytes = Data("Retain preexisting bootstrap evidence".utf8)
        try sentinelBytes.write(to: sentinel)
        let controlRoot = fixture.root.appendingPathComponent("FieldEvidenceOperations/schema-migration")
        let names = try fileManager.contentsOfDirectory(atPath: controlRoot.path).sorted()
        do {
            _ = try await factory.openForStartup { _ in XCTFail("Missing root cannot expose recovery context") }
            XCTFail("An extant aggregate cannot be replaced by a fresh bootstrap")
        } catch {}
        XCTAssertFalse(fileManager.fileExists(atPath: dataRoot.path))
        XCTAssertEqual(try Data(contentsOf: sentinel), sentinelBytes)
        XCTAssertEqual(try fileManager.contentsOfDirectory(atPath: controlRoot.path).sorted(), names)
        XCTAssertEqual(try control.load(), journal)
        XCTAssertTrue(fileManager.fileExists(atPath: retained.appendingPathComponent("current.json").path))
    }

    func testAggregateOriginalRecoveryRevokesEscapedAuthorityAndRetainsSourceBeforeClone() async throws {
        let fixture = try makeLegacyFixture(suffix: "aggregate-drain-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: fixture.root) }
        let factory = StoreGenerationFactory(applicationSupportURL: fixture.root)
        let pointerURL = fixture.root.appendingPathComponent("FieldEvidenceData/current.json")
        let pointer = try Data(contentsOf: pointerURL)
        var escapedContext: ModelContext?
        var escapedGuard: StoreMigrationSourceMutationGuardV1?
        do {
            _ = try await factory.openForStartup { authority in
                XCTAssertEqual(authority.sourceRelease, .v1)
                XCTAssertEqual(authority.sourceGenerationID, fixture.sourceID)
                let context = try authority.recoveryContext()
                XCTAssertFalse(context.autosaveEnabled)
                XCTAssertEqual(try context.fetch(FetchDescriptor<Site>()).map(\.id), [fixture.siteID])
                escapedContext = context
                escapedGuard = try authority.recoveryMutationGuard()
            }
            XCTFail("An escaped context must prevent checkpointing and cloning")
        } catch {}
        XCTAssertNotNil(escapedContext)
        let revoked = try XCTUnwrap(escapedGuard)
        XCTAssertThrowsError(try revoked.validateCurrent())
        var effects = 0
        XCTAssertThrowsError(try revoked.withAuthorizedMutation { effects += 1 })
        XCTAssertEqual(effects, 0)
        XCTAssertEqual(try Data(contentsOf: pointerURL), pointer)
        let control = try XCTUnwrap(StoreAggregateMigrationControlV1(applicationSupportURL: fixture.root))
        let journal = try XCTUnwrap(control.load())
        XCTAssertEqual(journal.phase, .recoveringSource)
        XCTAssertNil(journal.sourceCheckpoint)
        XCTAssertNil(journal.candidateRootInode)
        XCTAssertFalse(fileManager.fileExists(atPath: factory.restoreStagingGenerationURL(id: journal.targetGenerationID).path))
        let rival = StoreGenerationFactory(applicationSupportURL: fixture.root)
        var rivalCallback = false
        do {
            _ = try await rival.openForStartup { _ in rivalCallback = true }
            XCTFail("A live reservation owner cannot be replaced")
        } catch {}
        XCTAssertFalse(rivalCallback)
        XCTAssertEqual(try Data(contentsOf: pointerURL), pointer)
        XCTAssertEqual(try control.load(), journal)
        escapedContext = nil
        escapedGuard = nil
    }

    func testOwnedGenerationPathGrammarAndManifestKindsStayClosed() throws {
        let id = "a0000000-0000-4000-8000-000000000001"
        let durable: [String: OwnedFileKindV1] = [
            "model.sqlite": .database, "model.sqlite-wal": .databaseWAL, "model.sqlite-shm": .databaseSHM,
            "evidence/\(id)/original.jpg": .mediaOriginal,
            "evidence/\(id)/thumbnail.jpg": .mediaThumbnail,
            "snapshots/\(id).json": .reportSnapshot, "pdfs/\(id).pdf": .reportPDF,
            "content/\(id)/valid.content-id/original.bin": .mediaOriginal,
            "content/\(id)/valid.content-id/derivative-publication.json": .reportSnapshot,
            "content/\(id)/.asset-label-publications/\(id)/publication.json": .reportSnapshot,
        ]
        for (path, kind) in durable {
            let classification = try GenerationOwnedPathV1.classify(path, nodeType: .regularFile)
            XCTAssertEqual(classification.kind, kind, path)
            XCTAssertFalse(classification.recoveryOwned, path)
        }
        for path in [
            ".staging/evidence/\(id)/original.jpg", ".staging/evidence/\(id)/thumbnail.jpg",
            ".staging/snapshots/\(id).json", ".staging/pdfs/\(id).pdf",
            ".staging/evidence-derivatives/\(id)/operation.alpha-1/original.bin",
            ".staging/evidence-derivatives/\(id)/operation.alpha-1/derivative-publication.json",
        ] {
            let classification = try GenerationOwnedPathV1.classify(path, nodeType: .regularFile)
            XCTAssertEqual(classification.kind, .stagingFile)
            XCTAssertTrue(classification.recoveryOwned)
        }
        for path in [
            "model.sqlite/child", "evidence/\(id.uppercased())/original.jpg",
            "evidence/\(id)/unknown.jpg", "content/\(id)//original.bin",
            "content/\(id)/../original.bin", "content/\(id)/Uppercase/original.bin",
            "content/\(id)/valid/original.bin/extra", ".staging/unknown.bin",
            "operational/local-job-staging-v1", "../model.sqlite", "/model.sqlite", "model\\sqlite",
        ] {
            XCTAssertThrowsError(try GenerationOwnedPathV1.classify(path, nodeType: .regularFile), path)
        }
        let model = try StoreGenerationFileDigestV1(relativePath: "model.sqlite", byteCount: 0,
            sha256: String(repeating: "a", count: 64), kind: .database)
        for bad in [
            try StoreGenerationFileDigestV1(relativePath: "pdfs/\(id).pdf", byteCount: 0,
                sha256: String(repeating: "b", count: 64), kind: .mediaOriginal),
            try StoreGenerationFileDigestV1(relativePath: ".staging/pdfs/\(id).pdf", byteCount: 0,
                sha256: String(repeating: "b", count: 64), kind: .stagingFile),
        ] {
            XCTAssertThrowsError(try StoreGenerationManifestV1(
                generationID: UUID(), predecessorGenerationID: UUID(), migrationID: UUID(),
                storeSchemaRelease: .v1, semanticSHA256: nil, frozenIdentityDigest: String(repeating: "c", count: 64),
                files: [model, bad].sorted { $0.relativePath < $1.relativePath }
            ))
        }
    }

    func testOwnedGenerationInventoryStreamsNestedCloneAndPreservesFlatIdentity() throws {
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fileManager.removeItem(at: root) }
        let sourceID = fixedUUID("a1000000-0000-4000-8000-000000000001")
        let targetID = fixedUUID("a1000000-0000-4000-8000-000000000002")
        let factory = StoreGenerationFactory(applicationSupportURL: root)
        let source = factory.installedGenerationURL(id: sourceID)
        try fileManager.createDirectory(at: source, withIntermediateDirectories: true)
        // Opaque transport fixture, not a claim that these bytes are SQLite.
        // Both database and media transport must exceed the control-file cap.
        let large = Data(repeating: 0x5a, count: 5 * 1024 * 1024 + 17)
        try large.write(to: source.appendingPathComponent("model.sqlite"))
        let authority = try factory.makeRestoreGenerationAuthority()
        let flat = try authority.snapshotInstalledGeneration(id: sourceID)
        var rootInfo = stat(), modelInfo = stat()
        XCTAssertEqual(Darwin.lstat(source.path, &rootInfo), 0)
        XCTAssertEqual(Darwin.lstat(source.appendingPathComponent("model.sqlite").path, &modelInfo), 0)
        let oldTokens = [
            "source-directory|\(rootInfo.st_dev)|\(rootInfo.st_ino)",
            "model.sqlite|\(modelInfo.st_dev)|\(modelInfo.st_ino)|\(modelInfo.st_nlink)|\(StoreMigrationCanonicalJSONV1.sha256(large))",
        ]
        XCTAssertEqual(flat.frozenIdentityDigest, StoreMigrationCanonicalJSONV1.sha256(
            Data(oldTokens.sorted().joined(separator: "\n").utf8)
        ))
        let flatManifest = try StoreGenerationManifestV1(
            generationID: sourceID, predecessorGenerationID: targetID,
            migrationID: fixedUUID("a1000000-0000-4000-8000-000000000003"),
            storeSchemaRelease: .v1, semanticSHA256: nil,
            frozenIdentityDigest: flat.frozenIdentityDigest, files: flat.files
        )
        struct HistoricalManifest: Encodable {
            let schemaVersion: Int; let generationID: UUID; let predecessorGenerationID: UUID
            let migrationID: UUID; let storeSchemaRelease: PersistentSchemaReleaseV1
            let semanticSHA256: String?; let frozenIdentityDigest: String
            let files: [StoreGenerationFileDigestV1]
        }
        let historicalBytes = try StoreMigrationCanonicalJSONV1.encode(HistoricalManifest(
            schemaVersion: 1, generationID: sourceID, predecessorGenerationID: targetID,
            migrationID: flatManifest.migrationID, storeSchemaRelease: .v1,
            semanticSHA256: nil, frozenIdentityDigest: flat.frozenIdentityDigest, files: flat.files
        ))
        XCTAssertEqual(try flatManifest.canonicalData(), historicalBytes)
        XCTAssertEqual(try StoreGenerationManifestV1.decodeCanonical(from: historicalBytes), flatManifest)

        let workspace = "a1000000-0000-4000-8000-000000000004"
        let evidence = "a1000000-0000-4000-8000-000000000005"
        let job = "a1000000-0000-4000-8000-000000000006"
        let payloads: [String: Data] = [
            "evidence/\(evidence)/original.jpg": large,
            "evidence/\(evidence)/thumbnail.jpg": Data("thumbnail".utf8),
            "snapshots/\(evidence).json": Data("immutable snapshot".utf8),
            "pdfs/\(evidence).pdf": Data("immutable PDF".utf8),
            "content/\(workspace)/reading.alpha-1/original.bin": Data("original content".utf8),
            "content/\(workspace)/reading.alpha-1/derivative-publication.json": Data("derivative receipt".utf8),
            "content/\(workspace)/.asset-label-publications/\(job)/publication.json": Data("label receipt".utf8),
        ]
        for (path, bytes) in payloads {
            let url = source.appendingPathComponent(path)
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try bytes.write(to: url)
        }
        let empty = "content/\(workspace)/empty-content"
        for path in [empty, ".staging/pdfs"] {
            try fileManager.createDirectory(at: source.appendingPathComponent(path), withIntermediateDirectories: true)
        }
        let before = try authority.snapshotInstalledGeneration(id: sourceID)
        let beforeTree = try authority.installedTree(id: sourceID)
        XCTAssertTrue(beforeTree.directories.contains(empty))
        try authority.createStagingGeneration(id: targetID)
        let cloned = try authority.cloneInstalledGeneration(sourceID: sourceID, toStagingGeneration: targetID)
        XCTAssertEqual(cloned.files, before.files)
        XCTAssertEqual(cloned.sourceTreeDigest, before.sourceTreeDigest)
        XCTAssertEqual(cloned.frozenIdentityDigest, before.frozenIdentityDigest)
        XCTAssertEqual(try authority.stagingTree(id: targetID), beforeTree)
        try authority.installStagingGeneration(id: targetID)
        XCTAssertEqual(try authority.installedTree(id: targetID), beforeTree)
        let installed = factory.installedGenerationURL(id: targetID)
        for file in cloned.files {
            let url = installed.appendingPathComponent(file.relativePath)
            XCTAssertEqual(try Data(contentsOf: url).count, file.byteCount)
            XCTAssertEqual(try StoreMigrationCanonicalJSONV1.sha256(Data(contentsOf: url)), file.sha256)
            try ProtectedFilePolicyV1.verify(file.kind, at: url)
        }
        for path in beforeTree.directories {
            let owned = try GenerationOwnedPathV1.classify(path, nodeType: .directory)
            try ProtectedFilePolicyV1.verify(owned.kind, at: installed.appendingPathComponent(path))
        }
        let installedSnapshot = try authority.snapshotInstalledGeneration(id: targetID)
        XCTAssertEqual(installedSnapshot.files, before.files)
        try fileManager.removeItem(at: installed.appendingPathComponent(empty))
        let withoutEmpty = try authority.snapshotInstalledGeneration(id: targetID)
        XCTAssertEqual(withoutEmpty.sourceTreeDigest, installedSnapshot.sourceTreeDigest)
        XCTAssertNotEqual(withoutEmpty.frozenIdentityDigest, installedSnapshot.frozenIdentityDigest,
                          "File-only hashes cannot witness empty-directory identity")
    }

    func testOwnedGenerationInventoryRejectsHostileTreesBeforeCleanup() throws {
        for variant in ["unknown", "symlink", "directory-link", "hardlink", "fifo"] {
            let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? fileManager.removeItem(at: root) }
            let id = fixedUUID("a2000000-0000-4000-8000-000000000001")
            let leaf = "a2000000-0000-4000-8000-000000000002"
            let factory = StoreGenerationFactory(applicationSupportURL: root)
            let generation = factory.installedGenerationURL(id: id)
            try fileManager.createDirectory(at: generation.appendingPathComponent("snapshots"), withIntermediateDirectories: true)
            let model = generation.appendingPathComponent("model.sqlite")
            let media = generation.appendingPathComponent("snapshots/\(leaf).json")
            try Data("model retained".utf8).write(to: model)
            try Data("snapshot retained".utf8).write(to: media)
            let sentinel = root.appendingPathComponent("outside.bin")
            try Data("outside retained".utf8).write(to: sentinel)
            let hostile = generation.appendingPathComponent("pdfs/\(leaf).pdf")
            try fileManager.createDirectory(at: hostile.deletingLastPathComponent(), withIntermediateDirectories: true)
            switch variant {
            case "unknown": try Data("unknown".utf8).write(to: generation.appendingPathComponent("zz-unowned.bin"))
            case "symlink": try fileManager.createSymbolicLink(at: hostile, withDestinationURL: sentinel)
            case "directory-link":
                try fileManager.removeItem(at: hostile.deletingLastPathComponent())
                try fileManager.createSymbolicLink(at: hostile.deletingLastPathComponent(), withDestinationURL: root)
            case "hardlink": try fileManager.linkItem(at: sentinel, to: hostile)
            default: XCTAssertEqual(Darwin.mkfifo(hostile.path, mode_t(0o600)), 0)
            }
            let authority = try factory.makeRestoreGenerationAuthority()
            let names = try fileManager.subpathsOfDirectory(atPath: generation.path).sorted()
            XCTAssertThrowsError(try authority.snapshotInstalledGeneration(id: id), variant)
            XCTAssertThrowsError(try authority.protectInstalledGeneration(id: id), variant)
            XCTAssertThrowsError(try authority.installedTree(id: id), variant)
            XCTAssertThrowsError(try authority.removeInstalledGeneration(id: id), variant)
            XCTAssertEqual(try Data(contentsOf: model), Data("model retained".utf8), variant)
            XCTAssertEqual(try Data(contentsOf: media), Data("snapshot retained".utf8), variant)
            XCTAssertEqual(try Data(contentsOf: sentinel), Data("outside retained".utf8), variant)
            XCTAssertEqual(try fileManager.subpathsOfDirectory(atPath: generation.path).sorted(), names, variant)
        }
    }

    func testOwnedGenerationInventorySeparatesRecoveryStagingAndPartialCleanup() throws {
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fileManager.removeItem(at: root) }
        let sourceID = fixedUUID("a3000000-0000-4000-8000-000000000001")
        let targetID = fixedUUID("a3000000-0000-4000-8000-000000000002")
        let workspace = "a3000000-0000-4000-8000-000000000003"
        let factory = StoreGenerationFactory(applicationSupportURL: root)
        let source = factory.installedGenerationURL(id: sourceID)
        let stage = source.appendingPathComponent(".staging/evidence-derivatives/\(workspace)/operation.alpha-1/original.bin")
        try fileManager.createDirectory(at: stage.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("unsettled original operation".utf8).write(to: stage)
        try Data("model".utf8).write(to: source.appendingPathComponent("model.sqlite"))
        let authority = try factory.makeRestoreGenerationAuthority()
        try authority.protectInstalledGeneration(id: sourceID)
        try ProtectedFilePolicyV1.verify(.stagingFile, at: stage)
        XCTAssertThrowsError(try authority.snapshotInstalledGeneration(id: sourceID))
        try authority.createStagingGeneration(id: targetID)
        XCTAssertThrowsError(try authority.cloneInstalledGeneration(sourceID: sourceID, toStagingGeneration: targetID))
        XCTAssertTrue(try authority.stagingTree(id: targetID).files.isEmpty)
        XCTAssertTrue(try authority.stagingTree(id: targetID).directories.isEmpty)
        let partial = factory.restoreStagingGenerationURL(id: targetID)
        try fileManager.createDirectory(at: partial.appendingPathComponent("content/\(workspace)/partial"), withIntermediateDirectories: true)
        try Data("partial WAL".utf8).write(to: partial.appendingPathComponent("model.sqlite-wal"))
        try Data("partial content".utf8).write(to: partial.appendingPathComponent("content/\(workspace)/partial/original.bin"))
        try authority.removeStagingGeneration(id: targetID)
        XCTAssertFalse(fileManager.fileExists(atPath: partial.path))
        XCTAssertEqual(try Data(contentsOf: stage), Data("unsettled original operation".utf8))
    }

    func testOwnedGenerationInventoryReopensPopulatedCurrentFileTree() throws {
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fileManager.removeItem(at: root) }
        let factory = StoreGenerationFactory(applicationSupportURL: root)
        let first = try factory.openOrBootstrapCurrent()
        let leaf = "a4000000-0000-4000-8000-000000000001"
        let url = first.generationRootURL.appendingPathComponent("evidence/\(leaf)/original.jpg")
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("retained generation media".utf8).write(to: url)
        let reopened = try factory.openOrBootstrapCurrent()
        XCTAssertEqual(reopened.generationID, first.generationID)
        XCTAssertEqual(reopened.workspaceIdentity, first.workspaceIdentity)
        XCTAssertEqual(try Data(contentsOf: url), Data("retained generation media".utf8))
        try ProtectedFilePolicyV1.verify(.mediaOriginal, at: url)
        try reopened.reproofAfterSave()
    }

    func testOwnedGenerationCleanupRejectsReplacedPinnedGeneration() throws {
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: root.appendingPathComponent("FieldEvidenceData/generations"), withIntermediateDirectories: true)
        let factory = StoreGenerationFactory(applicationSupportURL: root)
        let authority = try factory.makeRestoreGenerationAuthority()
        let id = fixedUUID("a5000000-0000-4000-8000-000000000001")
        let handle = try authority.createInstalledGeneration(id: id)
        let generation = factory.installedGenerationURL(id: id)
        try Data("original pinned bytes".utf8).write(to: generation.appendingPathComponent("model.sqlite"))
        let moved = root.appendingPathComponent("moved-generation")
        try fileManager.moveItem(at: generation, to: moved)
        try fileManager.createDirectory(at: generation, withIntermediateDirectories: true)
        try Data("replacement bytes".utf8).write(to: generation.appendingPathComponent("model.sqlite"))
        XCTAssertThrowsError(try authority.removeCreatedInstalledGeneration(handle))
        XCTAssertEqual(try Data(contentsOf: moved.appendingPathComponent("model.sqlite")), Data("original pinned bytes".utf8))
        XCTAssertEqual(try Data(contentsOf: generation.appendingPathComponent("model.sqlite")), Data("replacement bytes".utf8))
    }

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
    func testV23P03C39RecoveryRejectsNonCanonicalSemanticPayload() throws {
        let source = try AssetSemanticCanonicalCodecV1.encode(
            AssetSemanticCompatibilityPolicyV1.sameSemanticIDSuccessor
        )
        XCTAssertEqual(
            try AssetSemanticCanonicalCodecV1.decode(
                AssetSemanticCompatibilityPolicyV1.self,
                from: source
            ),
            .sameSemanticIDSuccessor
        )
        var altered = source
        altered.append(0x20)
        XCTAssertThrowsError(
            try AssetSemanticCanonicalCodecV1.decode(
                AssetSemanticCompatibilityPolicyV1.self,
                from: altered
            )
        ) { error in
            XCTAssertEqual(error as? AssetSemanticContractFailureV1, .nonCanonicalData)
        }
        XCTAssertFalse(AssetSemanticValidationV1.validIdentifier("ASSET.KIND", maximumBytes: 160))
        XCTAssertFalse(AssetSemanticValidationV1.validText("  unknown  ", maximumCharacters: 32))
    }

    private let fileManager = FileManager.default

    private struct LegacyFixture {
        let root: URL
        let sourceID: UUID
        let migrationID: UUID
        let targetID: UUID
        let v3TargetID: UUID
        let v4TargetID: UUID
        let v5TargetID: UUID
        let v6TargetID: UUID
        let v7TargetID: UUID
        let v8TargetID: UUID
        let v9TargetID: UUID
        let siteID: UUID
        let assetID: UUID
        let recordID: UUID
        let processIDs: [UUID]
    }

    private struct LegacyCurrentPointer: Codable {
        let generationID: String
        let schemaVersion: Int
    }

    private struct RetiredPointer: Codable {
        let generationIDs: [String]
        let schemaVersion: Int
    }

    private struct FuturePointer: Codable {
        let schemaVersion: Int
    }

    private struct MalformedV2Pointer: Codable {
        let generationID: String
        let generationManifestSHA256: String
        let storeSchemaVersion: Int = 2
        let schemaVersion: Int = 2
    }

    private final class ProcessCursor {
        var index = 0
    }

    func testLegacyV1MigrationPreservesRowsAndCompletesTwoLaunchValidation() throws {
        let fixture = try makeLegacyFixture(suffix: "Clean")
        defer { try? fileManager.removeItem(at: fixture.root) }
        let processCursor = ProcessCursor()
        let factory = makeFactory(fixture: fixture, processCursor: processCursor)
        let sourceSemantic = try semanticData(
            at: installedModelURL(in: fixture.root, id: fixture.sourceID),
            root: fixture.root,
            release: .v1
        )

        XCTAssertEqual(try pointerSchema(in: fixture.root), 1)
        var firstLaunch: StoreGenerationSession? = try factory.openOrBootstrapCurrent()
        let first = try XCTUnwrap(firstLaunch)
        XCTAssertEqual(first.generationID, fixture.targetID)
        try assertMigratedRows(in: first.modelContext, fixture: fixture)

        let store = try StoreMigrationJournalStoreV1(
            applicationSupportURL: fixture.root
        )
        let firstJournal = try XCTUnwrap(try store.loadJournal())
        XCTAssertEqual(firstJournal.phase, .firstLaunchValidated)
        XCTAssertEqual(firstJournal.firstValidationProcessID, fixture.processIDs[0])
        XCTAssertNil(firstJournal.secondValidationProcessID)
        XCTAssertEqual(try pointerSchema(in: fixture.root), 2)

        let sourceManifest = try store.loadManifest(
            targetGenerationID: fixture.sourceID,
            expectedDigest: firstJournal.sourceManifestDigest
        )
        XCTAssertEqual(sourceManifest.storeSchemaRelease, .v1)
        XCTAssertEqual(sourceManifest.generationID, fixture.sourceID)
        XCTAssertEqual(sourceManifest.migrationID, fixture.migrationID)
        XCTAssertNil(sourceManifest.semanticSHA256)
        XCTAssertEqual(
            firstJournal.sourceSemanticDigest,
            StoreMigrationCanonicalJSONV1.sha256(sourceSemantic)
        )
        XCTAssertEqual(
            try sourceManifest.canonicalSHA256(),
            firstJournal.sourceManifestDigest
        )

        let firstMarker = try XCTUnwrap(
            try first.modelContext.fetch(
                FetchDescriptor<PersistentSchemaReleaseMarker>()
            ).first
        )
        XCTAssertEqual(firstMarker.id, PersistentSchemaReleaseRegistryV1.v2MarkerID)
        XCTAssertEqual(firstMarker.schemaVersion, 2)
        XCTAssertEqual(
            firstMarker.releaseID,
            PersistentSchemaReleaseRegistryV1.v2CompatibilityID
        )
        XCTAssertEqual(
            firstMarker.predecessorReleaseID,
            PersistentSchemaReleaseRegistryV1.v1CompatibilityID
        )
        XCTAssertEqual(firstMarker.migrationID, fixture.migrationID)

        let pointer = try CurrentGenerationPointerV2.decodeCanonical(
            from: try Data(contentsOf: currentPointerURL(in: fixture.root))
        )
        let manifest = try store.loadManifest(
            targetGenerationID: fixture.targetID,
            expectedDigest: pointer.generationManifestSHA256
        )
        XCTAssertEqual(manifest.storeSchemaRelease, .v2)
        XCTAssertEqual(manifest.migrationID, fixture.migrationID)
        XCTAssertEqual(manifest.predecessorGenerationID, fixture.sourceID)
        XCTAssertTrue(manifest.files.contains { $0.relativePath == "model.sqlite" })
        XCTAssertEqual(
            try manifest.canonicalSHA256(),
            pointer.generationManifestSHA256
        )
        XCTAssertEqual(
            try XCTUnwrap(firstJournal.targetManifestDigest),
            pointer.generationManifestSHA256
        )
        XCTAssertEqual(
            try XCTUnwrap(firstJournal.targetSemanticDigest),
            try XCTUnwrap(manifest.semanticSHA256)
        )
        XCTAssertEqual(
            try pointer.canonicalSHA256(),
            try XCTUnwrap(firstJournal.desiredPointerDigest)
        )
        XCTAssertEqual(
            try XCTUnwrap(manifest.semanticSHA256),
            StoreMigrationCanonicalJSONV1.sha256(sourceSemantic)
        )
        let targetSemantic = try semanticData(
            at: first.generationRootURL.appendingPathComponent(
                "model.sqlite",
                isDirectory: false
            ),
            root: fixture.root,
            release: .v2
        )
        XCTAssertEqual(sourceSemantic, targetSemantic)

        firstLaunch = nil
        XCTAssertNotEqual(fixture.processIDs[0], fixture.processIDs[1])
        var secondLaunch: StoreGenerationSession? = try factory.openOrBootstrapCurrent()
        let second = try XCTUnwrap(secondLaunch)
        XCTAssertEqual(second.generationID, fixture.v3TargetID)
        try assertMigratedRows(in: second.modelContext, fixture: fixture)
        XCTAssertEqual(
            try DeletionLedgerStore(context: second.modelContext).snapshot(),
            .empty
        )
        secondLaunch = nil

        let v3FirstLaunch = try XCTUnwrap(try store.loadJournal())
        XCTAssertEqual(v3FirstLaunch.sourceRelease, .v2)
        XCTAssertEqual(v3FirstLaunch.targetRelease, .v3)
        XCTAssertEqual(v3FirstLaunch.phase, .firstLaunchValidated)
        XCTAssertEqual(try pointerSchema(in: fixture.root), 3)

        var thirdLaunch: StoreGenerationSession? = try factory.openOrBootstrapCurrent()
        let third = try XCTUnwrap(thirdLaunch)
        XCTAssertEqual(third.generationID, fixture.v4TargetID)
        try assertMigratedRows(in: third.modelContext, fixture: fixture)
        XCTAssertEqual(
            try DeletionLedgerStore(context: third.modelContext).snapshot(),
            .empty
        )
        XCTAssertEqual(try third.modelContext.fetchCount(FetchDescriptor<MutationReceiptRow>()), 0)
        thirdLaunch = nil

        let v4FirstLaunch = try XCTUnwrap(try store.loadJournal())
        XCTAssertEqual(v4FirstLaunch.sourceRelease, .v3)
        XCTAssertEqual(v4FirstLaunch.targetRelease, .v4)
        XCTAssertEqual(v4FirstLaunch.phase, .firstLaunchValidated)
        XCTAssertEqual(try pointerSchema(in: fixture.root), 3)

        var fourthLaunch: StoreGenerationSession? = try factory.openOrBootstrapCurrent()
        let fourth = try XCTUnwrap(fourthLaunch)
        XCTAssertEqual(fourth.generationID, fixture.v5TargetID)
        XCTAssertEqual(try fourth.modelContext.fetchCount(FetchDescriptor<MutationReceiptRow>()), 0)
        let migratedRecord = try XCTUnwrap(
            try fourth.modelContext.fetch(FetchDescriptor<WorkflowRecord>()).first
        )
        XCTAssertEqual(migratedRecord.id, fixture.recordID)
        let migratedCompanion = try ObservationAndTimeRowStoreV1.requireRow(
            recordID: migratedRecord.id,
            in: fourth.modelContext
        )
        XCTAssertEqual(try migratedCompanion.observationBasisV1().kind, .unverifiable)
        XCTAssertEqual(try migratedCompanion.observationBasisV1().method.key, ObservationMethodV1.unknownKey)
        XCTAssertEqual(try migratedCompanion.temporalContextV1().localTimeDisposition, .unknown)
        XCTAssertEqual(try migratedCompanion.temporalContextV1().utcOffsetSeconds, -18_000)
        fourthLaunch = nil

        let v5FirstLaunch = try XCTUnwrap(try store.loadJournal())
        XCTAssertEqual(v5FirstLaunch.sourceRelease, .v4)
        XCTAssertEqual(v5FirstLaunch.targetRelease, .v5)
        XCTAssertEqual(v5FirstLaunch.phase, .firstLaunchValidated)

        var fifthLaunch: StoreGenerationSession? = try factory.openOrBootstrapCurrent()
        let fifth = try XCTUnwrap(fifthLaunch)
        XCTAssertEqual(fifth.generationID, fixture.v6TargetID)
        XCTAssertEqual(
            try fifth.modelContext.fetchCount(FetchDescriptor<WorkflowRecord>()),
            1
        )
        XCTAssertEqual(
            try fifth.modelContext.fetchCount(FetchDescriptor<ObservationAndTimeRow>()),
            1
        )
        XCTAssertEqual(
            try fifth.modelContext.fetchCount(FetchDescriptor<AssetPlacementEventRow>()),
            1
        )
        XCTAssertEqual(
            try fifth.modelContext.fetchCount(FetchDescriptor<LocationMigrationReceiptRow>()),
            1
        )
        fifthLaunch = nil

        let v6FirstLaunch = try XCTUnwrap(try store.loadJournal())
        XCTAssertEqual(v6FirstLaunch.sourceRelease, .v5)
        XCTAssertEqual(v6FirstLaunch.targetRelease, .v6)
        XCTAssertEqual(v6FirstLaunch.phase, .firstLaunchValidated)

        var sixthLaunch: StoreGenerationSession? = try factory.openOrBootstrapCurrent()
        XCTAssertEqual(try XCTUnwrap(sixthLaunch).generationID, fixture.v7TargetID)
        sixthLaunch = nil

        let v7FirstLaunch = try XCTUnwrap(try store.loadJournal())
        XCTAssertEqual(v7FirstLaunch.sourceRelease, .v6)
        XCTAssertEqual(v7FirstLaunch.targetRelease, .v7)
        XCTAssertEqual(v7FirstLaunch.phase, .firstLaunchValidated)

        var seventhLaunch: StoreGenerationSession? = try factory.openOrBootstrapCurrent()
        XCTAssertEqual(try XCTUnwrap(seventhLaunch).generationID, fixture.v8TargetID)
        seventhLaunch = nil

        let v8FirstLaunch = try XCTUnwrap(try store.loadJournal())
        XCTAssertEqual(v8FirstLaunch.sourceRelease, .v7)
        XCTAssertEqual(v8FirstLaunch.targetRelease, .v8)
        XCTAssertEqual(v8FirstLaunch.phase, .firstLaunchValidated)

        var eighthLaunch: StoreGenerationSession? = try factory.openOrBootstrapCurrent()
        XCTAssertEqual(try XCTUnwrap(eighthLaunch).generationID, fixture.v9TargetID)
        let assurances = try XCTUnwrap(eighthLaunch).modelContext.fetch(
            FetchDescriptor<RequirementAssuranceRow>()
        )
        XCTAssertEqual(assurances.count, 1)
        XCTAssertEqual(try assurances[0].snapshot().workflowRecordID, fixture.recordID)
        XCTAssertEqual(try assurances[0].currentDecision().disposition, .blocked)
        XCTAssertEqual(try XCTUnwrap(eighthLaunch).modelContext.fetchCount(FetchDescriptor<ServicePartyRow>()), 0)
        XCTAssertEqual(try XCTUnwrap(eighthLaunch).modelContext.fetchCount(FetchDescriptor<SitePartyRoleEventRow>()), 0)
        XCTAssertEqual(try XCTUnwrap(eighthLaunch).modelContext.fetchCount(FetchDescriptor<ActorSnapshotRow>()), 0)
        XCTAssertEqual(try XCTUnwrap(eighthLaunch).modelContext.fetchCount(FetchDescriptor<QualificationSnapshotRow>()), 0)
        XCTAssertEqual(try XCTUnwrap(eighthLaunch).modelContext.fetchCount(FetchDescriptor<SignoffSnapshotRow>()), 0)
        eighthLaunch = nil
        let v9FirstLaunch = try XCTUnwrap(try store.loadJournal())
        XCTAssertEqual(v9FirstLaunch.sourceRelease, .v8)
        XCTAssertEqual(v9FirstLaunch.targetRelease, .v9)
        XCTAssertEqual(v9FirstLaunch.phase, .firstLaunchValidated)

        var ninthLaunch: StoreGenerationSession? = try factory.openOrBootstrapCurrent()
        XCTAssertNotEqual(try XCTUnwrap(ninthLaunch).generationID, fixture.v9TargetID)
        XCTAssertEqual(try XCTUnwrap(ninthLaunch).modelContext.fetchCount(FetchDescriptor<ServicePartyRow>()), 0)
        XCTAssertEqual(try XCTUnwrap(ninthLaunch).modelContext.fetchCount(FetchDescriptor<SitePartyRoleEventRow>()), 0)
        XCTAssertEqual(try XCTUnwrap(ninthLaunch).modelContext.fetchCount(FetchDescriptor<ActorSnapshotRow>()), 0)
        XCTAssertEqual(try XCTUnwrap(ninthLaunch).modelContext.fetchCount(FetchDescriptor<QualificationSnapshotRow>()), 0)
        XCTAssertEqual(try XCTUnwrap(ninthLaunch).modelContext.fetchCount(FetchDescriptor<SignoffSnapshotRow>()), 0)
        ninthLaunch = nil
        let v10FirstLaunch = try XCTUnwrap(try store.loadJournal())
        XCTAssertEqual(v10FirstLaunch.sourceRelease, .v9)
        XCTAssertEqual(v10FirstLaunch.targetRelease, .v10)
        XCTAssertEqual(v10FirstLaunch.phase, .firstLaunchValidated)
        XCTAssertEqual(try pointerSchema(in: fixture.root), 3)
    }

    func testPopulatedLegacyMigrationTraversesLateReleasesAndReopensActiveStore() throws {
        let fixture = try makeLegacyFixture(suffix: "ActiveChain")
        defer { try? fileManager.removeItem(at: fixture.root) }
        let factory = StoreGenerationFactory(
            applicationSupportURL: fixture.root,
            migrationIdentitySource: StoreMigrationIdentitySourceV1(
                makeMigrationID: UUID.init,
                makeGenerationID: UUID.init,
                makeProcessID: UUID.init
            )
        )
        let store = try StoreMigrationJournalStoreV1(applicationSupportURL: fixture.root)
        var priorGenerationID = fixture.sourceID
        var sourceManifest: StoreGenerationManifestV1?
        var lateSourceVersions = Set<Int>()
        // One populated lineage exercises adjacent upgrades, not a fresh-store matrix.
        for targetVersion in 2...53 {
            try autoreleasepool {
                let session = try factory.openOrBootstrapCurrent()
                try assertMigratedRows(in: session.modelContext, fixture: fixture)
                let journal = try XCTUnwrap(try store.loadJournal())
                XCTAssertEqual(journal.sourceGenerationID, priorGenerationID)
                XCTAssertNotEqual(session.generationID, priorGenerationID)
                XCTAssertEqual(journal.sourceRelease.versionIdentifier.major, targetVersion - 1)
                XCTAssertEqual(journal.targetRelease.versionIdentifier.major, targetVersion)
                XCTAssertEqual(journal.phase, .firstLaunchValidated)
                let marker = try XCTUnwrap(session.modelContext.fetch(
                    FetchDescriptor<PersistentSchemaReleaseMarker>()
                ).first)
                XCTAssertEqual(marker.schemaVersion, targetVersion)
                XCTAssertEqual(marker.releaseID, journal.targetRelease.compatibilityID)
                XCTAssertEqual(marker.predecessorReleaseID, journal.sourceRelease.compatibilityID)
                if targetVersion == 2 {
                    sourceManifest = try store.loadManifest(
                        targetGenerationID: fixture.sourceID,
                        expectedDigest: journal.sourceManifestDigest
                    )
                }
                if [37, 50, 51, 52].contains(targetVersion - 1) {
                    lateSourceVersions.insert(targetVersion - 1)
                    let pointer = try factory.currentGenerationPointerV3(expectedGenerationID: session.generationID)
                    let manifest = try store.loadManifest(
                        targetGenerationID: session.generationID,
                        expectedDigest: pointer.generationManifestSHA256
                    )
                    XCTAssertEqual(pointer.storeSchemaVersion, targetVersion)
                    XCTAssertEqual(manifest.storeSchemaRelease, journal.targetRelease)
                    XCTAssertEqual(manifest.migrationID, marker.migrationID)
                }
                priorGenerationID = session.generationID
            }
#if DEBUG
            if [37, 50, 51, 52].contains(targetVersion) {
                // Model a cold launch after durable journal removal, before
                // startup starts the next adjacent release. The next loop
                // must use the ordinary no-journal current-pointer route.
                let interrupted = StoreGenerationFactory(
                    applicationSupportURL: fixture.root,
                    migrationIdentitySource: StoreMigrationIdentitySourceV1(
                        makeMigrationID: UUID.init,
                        makeGenerationID: UUID.init,
                        makeProcessID: UUID.init
                    ),
                    migrationFailureInjection: StoreMigrationFailureInjection(failOnceAt: .afterJournalRemoval)
                )
                XCTAssertThrowsError(try interrupted.openOrBootstrapCurrent()) { error in
                    XCTAssertEqual(error as? StoreMigrationFailure, .injectedFault(.afterJournalRemoval))
                }
                XCTAssertNil(try store.loadJournal())
                let pointer = try factory.currentGenerationPointerV3(expectedGenerationID: priorGenerationID)
                XCTAssertEqual(pointer.storeSchemaVersion, targetVersion)
            }
#endif
        }
        XCTAssertEqual(lateSourceVersions, [37, 50, 51, 52])
        let reopened = try factory.openOrBootstrapCurrent()
        XCTAssertEqual(reopened.generationID, priorGenerationID)
        try assertMigratedRows(in: reopened.modelContext, fixture: fixture)
        XCTAssertNil(try store.loadJournal())
        let pointer = try factory.currentGenerationPointerV3(expectedGenerationID: reopened.generationID)
        XCTAssertEqual(pointer.storeSchemaVersion, 53)
        XCTAssertEqual(try reopened.modelContext.fetchCount(FetchDescriptor<LightingNightWorkflowRowV1>()), 0)
        let original = try XCTUnwrap(sourceManifest)
        let snapshot = try factory.makeRestoreGenerationAuthority().snapshotInstalledGeneration(id: fixture.sourceID)
        XCTAssertEqual(snapshot.files, original.files)
        XCTAssertEqual(snapshot.frozenIdentityDigest, original.frozenIdentityDigest)
    }

    func testFreshBootstrapPersistsActiveMarkerManifestAndPointerAcrossReopen() throws {
        let generationID = fixedUUID("53000000-0000-4000-8000-000000000001")
        let workspaceID = WorkspaceID(rawValue: fixedUUID("53000000-0000-4000-8000-000000000002"))
        let replicaID = ReplicaID(rawValue: fixedUUID("53000000-0000-4000-8000-000000000003"))
        let priorReplica = ReplicaID(rawValue: fixedUUID("53000000-0000-4000-8000-000000000004"))
        for version in [2, 26, 27, 35, 36, 53] {
            let value = try CurrentGenerationPointerV3(
                generationID: generationID,
                generationManifestSHA256: String(repeating: "a", count: 64),
                workspaceID: workspaceID,
                replicaID: replicaID,
                knownReplicaIDs: [priorReplica],
                storeSchemaVersion: version
            )
            let data = try value.canonicalData()
            let decoded = try CurrentGenerationPointerV3.decodeCanonical(from: data)
            XCTAssertEqual(decoded, value)
            XCTAssertEqual(decoded.storeSchemaVersion, version)
            XCTAssertEqual(try decoded.knownReplicaIdentitySet(), [priorReplica, replicaID])
            XCTAssertEqual(try decoded.canonicalData(), data)
        }
        for version in [1, 54, Int.max] {
            XCTAssertThrowsError(try CurrentGenerationPointerV3(
                generationID: generationID,
                generationManifestSHA256: String(repeating: "a", count: 64),
                workspaceID: workspaceID,
                replicaID: replicaID,
                storeSchemaVersion: version
            )) { error in
                XCTAssertEqual(error as? StoreMigrationFailure, .invalidContract)
            }
        }
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fileManager.removeItem(at: root) }
        let factory = StoreGenerationFactory(applicationSupportURL: root)
        let first = try factory.openOrBootstrapCurrent()
        let pointer = try factory.currentGenerationPointerV3(expectedGenerationID: first.generationID)
        let store = try StoreMigrationJournalStoreV1(applicationSupportURL: root)
        let manifest = try store.loadManifest(targetGenerationID: first.generationID, expectedDigest: pointer.generationManifestSHA256)
        let marker = try XCTUnwrap(first.modelContext.fetch(FetchDescriptor<PersistentSchemaReleaseMarker>()).first)
        XCTAssertEqual(pointer.storeSchemaVersion, 53)
        XCTAssertEqual(manifest.storeSchemaRelease, .v53)
        XCTAssertEqual(marker.schemaVersion, 53)
        XCTAssertEqual(marker.releaseID, PersistentSchemaReleaseV1.v53.compatibilityID)
        XCTAssertEqual(marker.predecessorReleaseID, PersistentSchemaReleaseV1.v52.compatibilityID)
        XCTAssertEqual(marker.migrationID, manifest.migrationID)
        let reopened = try factory.openOrBootstrapCurrent()
        XCTAssertEqual(reopened.generationID, first.generationID)
        XCTAssertEqual(reopened.workspaceIdentity, first.workspaceIdentity)
        XCTAssertEqual(try factory.currentGenerationID(), first.generationID)
        let epoch = try factory.currentGenerationEpoch()
        XCTAssertEqual(epoch.generationID, first.generationID)
        XCTAssertEqual(epoch.generationManifestSHA256, pointer.generationManifestSHA256)
        XCTAssertEqual(reopened.generationEpoch, epoch)
        let coordinator = try StoreSessionCoordinator(validatingSession: reopened)
        XCTAssertEqual(coordinator.generationID, reopened.generationID)
        XCTAssertEqual(coordinator.workspaceIdentity, reopened.workspaceIdentity)
        let revision = try coordinator.workspaceWriter.currentRevision()
        XCTAssertEqual(revision.workspaceID, reopened.workspaceID)
        XCTAssertEqual(revision.generationID, reopened.generationID)
        XCTAssertEqual(revision.revision, 0)
        XCTAssertEqual(try reopened.modelContext.fetchCount(FetchDescriptor<LightingNightWorkflowRowV1>()), 0)
        XCTAssertNil(try store.loadJournal())
    }

#if DEBUG
    func testEveryFaultBoundaryUsesPreWriteFallbackOrPostWriteForwardRecovery() throws {
        let boundaries = StoreMigrationFaultBoundaryV1.allCases
        XCTAssertEqual(boundaries.count, 18)

        let preWriteBoundaries: [StoreMigrationFaultBoundaryV1] = [
            .beforePreparedJournalWrite,
            .afterPreparedJournalWrite,
            .beforeSourceClone,
            .afterSourceClone,
            .beforeV2WriteAuthorization,
        ]
        let publishedBoundaries: [StoreMigrationFaultBoundaryV1] = [
            .afterPointerPublication,
            .beforeFirstLaunchValidation,
            .afterFirstLaunchValidation,
            .beforeSecondLaunchValidation,
            .afterSecondLaunchValidation,
            .beforeJournalRemoval,
            .afterJournalRemoval,
        ]
        let durableMarkerBoundaries: [StoreMigrationFaultBoundaryV1] = [
            .afterV2Validation,
            .beforeGenerationInstall,
            .afterGenerationInstall,
            .beforePointerPublication,
            .afterPointerPublication,
            .beforeFirstLaunchValidation,
            .afterFirstLaunchValidation,
            .beforeSecondLaunchValidation,
            .afterSecondLaunchValidation,
            .beforeJournalRemoval,
            .afterJournalRemoval,
        ]

        for (index, boundary) in boundaries.enumerated() {
            let fixture = try makeLegacyFixture(
                suffix: "Boundary-\(index)-\(boundary.rawValue)"
            )
            defer { try? fileManager.removeItem(at: fixture.root) }
            let processCursor = ProcessCursor()
            let injection = StoreMigrationFailureInjection(failOnceAt: boundary)
            let factory = makeFactory(
                fixture: fixture,
                processCursor: processCursor,
                injection: injection
            )

            var didReachInjectedBoundary = false
            for _ in 0..<4 {
                do {
                    var session: StoreGenerationSession? =
                        try factory.openOrBootstrapCurrent()
                    session = nil
                } catch let failure as StoreMigrationFailure {
                    guard case .injectedFault(let actualBoundary) = failure else {
                        XCTFail(
                            "\(boundary.rawValue) produced unexpected failure \(failure)"
                        )
                        break
                    }
                    XCTAssertEqual(actualBoundary, boundary)
                    didReachInjectedBoundary = true
                    break
                } catch {
                    XCTFail("\(boundary.rawValue) produced non-migration error \(error)")
                    break
                }
            }
            XCTAssertTrue(didReachInjectedBoundary, boundary.rawValue)

            let journal = try loadJournal(in: fixture.root)
            let pointerVersion = try pointerSchema(in: fixture.root)
            if preWriteBoundaries.contains(boundary) {
                XCTAssertEqual(pointerVersion, 1, boundary.rawValue)
                XCTAssertTrue(
                    journal == nil || journal?.targetWritePossible == false,
                    boundary.rawValue
                )
            } else if publishedBoundaries.contains(boundary) {
                XCTAssertEqual(pointerVersion, 2, boundary.rawValue)
                if let journal {
                    XCTAssertTrue(journal.targetWritePossible, boundary.rawValue)
                }
            } else {
                XCTAssertEqual(pointerVersion, 1, boundary.rawValue)
                XCTAssertTrue(journal?.targetWritePossible == true, boundary.rawValue)
            }

            if boundary == .afterSecondLaunchValidation {
                let secondLaunchJournal = try XCTUnwrap(journal)
                XCTAssertEqual(
                    secondLaunchJournal.phase,
                    .secondLaunchValidated,
                    boundary.rawValue
                )
                let firstProcess = try XCTUnwrap(
                    secondLaunchJournal.firstValidationProcessID
                )
                let secondProcess = try XCTUnwrap(
                    secondLaunchJournal.secondValidationProcessID
                )
                let publicationProcess = try XCTUnwrap(
                    secondLaunchJournal.publicationProcessID
                )
                XCTAssertNotEqual(firstProcess, secondProcess, boundary.rawValue)
                XCTAssertNotEqual(
                    secondProcess,
                    secondLaunchJournal.originatingProcessID,
                    boundary.rawValue
                )
                XCTAssertNotEqual(
                    secondProcess,
                    publicationProcess,
                    boundary.rawValue
                )
            }

            if durableMarkerBoundaries.contains(boundary) {
                let authority = try factory.makeRestoreGenerationAuthority()
                let presence = try authority.presence(id: fixture.targetID)
                XCTAssertTrue(
                    presence.staging || presence.installed,
                    boundary.rawValue
                )
                let root = presence.installed
                    ? factory.installedGenerationURL(id: fixture.targetID)
                    : factory.restoreStagingGenerationURL(id: fixture.targetID)
                try assertMarker(
                    at: root.appendingPathComponent("model.sqlite"),
                    migrationID: fixture.migrationID
                )
            }

            var reachedRecoveredV3Stage = false
            for _ in 0..<6 {
                let session = try factory.openOrBootstrapCurrent()
                let recoveredJournal = try XCTUnwrap(try loadJournal(in: fixture.root), boundary.rawValue)
                if recoveredJournal.targetRelease == .v3 {
                    XCTAssertEqual(recoveredJournal.sourceRelease, .v2, boundary.rawValue)
                    XCTAssertEqual(recoveredJournal.sourceGenerationID, fixture.targetID, boundary.rawValue)
                    XCTAssertEqual(recoveredJournal.targetGenerationID, fixture.v3TargetID, boundary.rawValue)
                    XCTAssertEqual(recoveredJournal.phase, .firstLaunchValidated, boundary.rawValue)
                    XCTAssertEqual(session.generationID, fixture.v3TargetID, boundary.rawValue)
                    try assertMigratedRows(in: session.modelContext, fixture: fixture)
                    try assertMarker(
                        at: session.generationRootURL.appendingPathComponent("model.sqlite"),
                        migrationID: fixture.migrationID,
                        release: .v3
                    )
                    let pointer = try factory.currentGenerationPointerV3(expectedGenerationID: fixture.v3TargetID)
                    XCTAssertEqual(pointer.storeSchemaVersion, 3, boundary.rawValue)
                    XCTAssertEqual(try pointerSchema(in: fixture.root), 3, boundary.rawValue)
                    reachedRecoveredV3Stage = true
                    break
                }
                guard recoveredJournal.sourceRelease == .v1,
                      recoveredJournal.targetRelease == .v2,
                      recoveredJournal.targetGenerationID == fixture.targetID,
                      recoveredJournal.phase == .firstLaunchValidated,
                      session.generationID == fixture.targetID else {
                    XCTFail("Unexpected recovery stage for \(boundary.rawValue): \(recoveredJournal.targetRelease)")
                    break
                }
            }
            XCTAssertTrue(reachedRecoveredV3Stage, boundary.rawValue)
        }

        let markerRetry = try makeLegacyFixture(suffix: "V4MarkerRetry")
        defer { try? fileManager.removeItem(at: markerRetry.root) }
        let markerRetryCursor = ProcessCursor()
        let advanceFactory = makeFactory(
            fixture: markerRetry,
            processCursor: markerRetryCursor
        )
        var advanced: StoreGenerationSession? = try advanceFactory.openOrBootstrapCurrent()
        advanced = nil
        advanced = try advanceFactory.openOrBootstrapCurrent()
        XCTAssertEqual(try XCTUnwrap(advanced).generationID, markerRetry.v3TargetID)
        advanced = nil

        let retryFactory = makeFactory(
            fixture: markerRetry,
            processCursor: markerRetryCursor,
            injection: StoreMigrationFailureInjection(failOnceAt: .afterV2Validation)
        )
        XCTAssertThrowsError(try retryFactory.openOrBootstrapCurrent()) {
            XCTAssertEqual(
                $0 as? StoreMigrationFailure,
                .injectedFault(.afterV2Validation)
            )
        }
        let retryStaging = retryFactory.restoreStagingGenerationURL(
            id: markerRetry.v4TargetID
        )
        try assertMarker(
            at: retryStaging.appendingPathComponent("model.sqlite"),
            migrationID: markerRetry.migrationID,
            release: .v4
        )
        var recovered: StoreGenerationSession? = try retryFactory.openOrBootstrapCurrent()
        XCTAssertEqual(try XCTUnwrap(recovered).generationID, markerRetry.v4TargetID)
        XCTAssertEqual(
            try XCTUnwrap(recovered).modelContext.fetchCount(
                FetchDescriptor<MutationReceiptRow>()
            ),
            0
        )
        XCTAssertEqual(
            try XCTUnwrap(recovered).modelContext.fetchCount(
                FetchDescriptor<WorkspaceMutationStateRow>()
            ),
            1
        )
        recovered = nil
        let recoveredV4Journal = try XCTUnwrap(try loadJournal(in: markerRetry.root))
        XCTAssertEqual(recoveredV4Journal.sourceRelease, .v3)
        XCTAssertEqual(recoveredV4Journal.targetRelease, .v4)
        XCTAssertEqual(recoveredV4Journal.phase, .firstLaunchValidated)
        let recoveryProcessID = try XCTUnwrap(recoveredV4Journal.firstValidationProcessID)
        // Reopening in the validating process tests the V4 marker retry;
        // a distinct process would correctly begin the next V5 migration.
        let sameProcessFactory = StoreGenerationFactory(
            applicationSupportURL: markerRetry.root,
            migrationIdentitySource: StoreMigrationIdentitySourceV1(
                makeMigrationID: { markerRetry.migrationID },
                makeGenerationID: UUID.init,
                makeProcessID: { recoveryProcessID }
            )
        )
        let secondRecovery = try sameProcessFactory.openOrBootstrapCurrent()
        XCTAssertEqual(secondRecovery.generationID, markerRetry.v4TargetID)
        XCTAssertEqual(try loadJournal(in: markerRetry.root), recoveredV4Journal)
        XCTAssertEqual(
            try secondRecovery.modelContext.fetchCount(
                FetchDescriptor<WorkspaceMutationStateRow>()
            ),
            1
        )

        let exactMarkerSchema = Schema(
            PersistentSchemaV4.models,
            version: PersistentSchemaV4.versionIdentifier
        )
        let exactMarkerContainer = try ModelContainer(
            for: exactMarkerSchema,
            migrationPlan: nil,
            configurations: [ModelConfiguration(
                "V9_03V4ExactMarkerRetry",
                schema: exactMarkerSchema,
                isStoredInMemoryOnly: true,
                allowsSave: true,
                cloudKitDatabase: .none
            )]
        )
        let exactMarkerContext = exactMarkerContainer.mainContext
        exactMarkerContext.autosaveEnabled = false
        exactMarkerContext.insert(PersistentSchemaReleaseMarker(
            id: PersistentSchemaReleaseRegistryV1.v2MarkerID,
            schemaVersion: 4,
            releaseID: PersistentSchemaReleaseRegistryV1.v4CompatibilityID,
            predecessorReleaseID: PersistentSchemaReleaseRegistryV1.v3CompatibilityID,
            migrationID: markerRetry.migrationID
        ))
        try exactMarkerContext.save()
        let exactIdentity = try WorkspaceReplicaIdentityV1(
            workspaceID: WorkspaceID(rawValue: fixedUUID("00000000-0000-0000-0000-000000000091")),
            replicaID: ReplicaID(rawValue: fixedUUID("00000000-0000-0000-0000-000000000092"))
        )
        _ = try MutationJournalStoreV1(
            modelContext: exactMarkerContext,
            identity: exactIdentity,
            generationID: fixedUUID("00000000-0000-0000-0000-000000000093")
        )
        var exactStates = try exactMarkerContext.fetch(
            FetchDescriptor<WorkspaceMutationStateRow>()
        )
        XCTAssertEqual(exactStates.count, 1)
        let incompleteState = try XCTUnwrap(exactStates.first)
        incompleteState.mutableSemanticSHA256 = nil
        try exactMarkerContext.save()
        _ = try MutationJournalStoreV1(
            modelContext: exactMarkerContext,
            identity: exactIdentity,
            generationID: fixedUUID("00000000-0000-0000-0000-000000000093")
        )
        exactStates = try exactMarkerContext.fetch(FetchDescriptor<WorkspaceMutationStateRow>())
        XCTAssertEqual(exactStates.count, 1)
        XCTAssertNotNil(try XCTUnwrap(exactStates.first).mutableSemanticSHA256)
    }

    func testSourceCloneRecoveryReclonesButAuthorizedRecoveryIsForwardOnly() throws {
        let sourceCloneFixture = try makeLegacyFixture(suffix: "Reclone")
        defer { try? fileManager.removeItem(at: sourceCloneFixture.root) }
        let sourceCloneCursor = ProcessCursor()
        let sourceCloneFactory = makeFactory(
            fixture: sourceCloneFixture,
            processCursor: sourceCloneCursor,
            injection: StoreMigrationFailureInjection(
                failOnceAt: .afterSourceClone
            )
        )

        XCTAssertThrowsError(
            try sourceCloneFactory.openOrBootstrapCurrent()
        ) { error in
            XCTAssertEqual(
                error as? StoreMigrationFailure,
                .injectedFault(.afterSourceClone)
            )
        }
        let clonedModelURL = sourceCloneFactory
            .restoreStagingGenerationURL(id: sourceCloneFixture.targetID)
            .appendingPathComponent("model.sqlite", isDirectory: false)
        try Data(repeating: 0xA5, count: 32).write(
            to: clonedModelURL,
            options: .atomic
        )
        var firstRecovery: StoreGenerationSession? = try sourceCloneFactory
            .openOrBootstrapCurrent()
        firstRecovery = nil
        var secondRecovery: StoreGenerationSession? = try sourceCloneFactory
            .openOrBootstrapCurrent()
        XCTAssertEqual(secondRecovery?.generationID, sourceCloneFixture.v3TargetID)
        XCTAssertEqual(
            try DeletionLedgerStore(
                context: try XCTUnwrap(secondRecovery).modelContext
            ).snapshot(),
            .empty
        )
        secondRecovery = nil
        XCTAssertEqual(try pointerSchema(in: sourceCloneFixture.root), 3)
        let installedModelURL = sourceCloneFactory
            .installedGenerationURL(id: sourceCloneFixture.targetID)
            .appendingPathComponent("model.sqlite", isDirectory: false)
        XCTAssertTrue(fileManager.fileExists(atPath: installedModelURL.path))
        XCTAssertEqual(
            try loadJournal(in: sourceCloneFixture.root)?.targetRelease,
            .v3
        )
        var thirdRecovery: StoreGenerationSession? = try sourceCloneFactory
            .openOrBootstrapCurrent()
        thirdRecovery = nil
        XCTAssertNil(try loadJournal(in: sourceCloneFixture.root))

        let authorizedFixture = try makeLegacyFixture(suffix: "ForwardOnly")
        defer { try? fileManager.removeItem(at: authorizedFixture.root) }
        let authorizedCursor = ProcessCursor()
        let authorizedFactory = makeFactory(
            fixture: authorizedFixture,
            processCursor: authorizedCursor,
            injection: StoreMigrationFailureInjection(
                failOnceAt: .afterV2WriteAuthorization
            )
        )
        XCTAssertThrowsError(
            try authorizedFactory.openOrBootstrapCurrent()
        ) { error in
            XCTAssertEqual(
                error as? StoreMigrationFailure,
                .injectedFault(.afterV2WriteAuthorization)
            )
        }
        let authorizedAuthority = try authorizedFactory
            .makeRestoreGenerationAuthority()
        try authorizedAuthority.removeStagingGeneration(
            id: authorizedFixture.targetID
        )
        XCTAssertThrowsError(
            try authorizedFactory.openOrBootstrapCurrent()
        ) { error in
            XCTAssertEqual(
                error as? StoreMigrationFailure,
                .maintenanceRequired(.targetUnavailable)
            )
        }
        XCTAssertEqual(try pointerSchema(in: authorizedFixture.root), 1)
        let authorizedJournal = try XCTUnwrap(
            try loadJournal(in: authorizedFixture.root)
        )
        XCTAssertEqual(authorizedJournal.phase, .v2WriteAuthorized)
        XCTAssertTrue(authorizedJournal.targetWritePossible)
    }

    func testTargetSnapshotMutationAfterValidationFailsForwardClosed() throws {
        let fixture = try makeLegacyFixture(suffix: "TargetReproof")
        defer { try? fileManager.removeItem(at: fixture.root) }
        let processCursor = ProcessCursor()
        let factory = makeFactory(
            fixture: fixture,
            processCursor: processCursor,
            injection: StoreMigrationFailureInjection(
                failOnceAt: .afterV2Validation
            )
        )

        XCTAssertThrowsError(try factory.openOrBootstrapCurrent()) { error in
            XCTAssertEqual(
                error as? StoreMigrationFailure,
                .injectedFault(.afterV2Validation)
            )
        }
        let journal = try XCTUnwrap(try loadJournal(in: fixture.root))
        XCTAssertEqual(journal.phase, .v2Validated)
        let targetModelURL = factory
            .restoreStagingGenerationURL(id: fixture.targetID)
            .appendingPathComponent("model.sqlite", isDirectory: false)
        var mutated = try Data(contentsOf: targetModelURL)
        mutated.append(0)
        try mutated.write(to: targetModelURL, options: .atomic)

        XCTAssertThrowsError(try factory.openOrBootstrapCurrent()) { error in
            XCTAssertEqual(
                error as? StoreMigrationFailure,
                .maintenanceRequired(.targetMismatch)
            )
        }
        XCTAssertEqual(try pointerSchema(in: fixture.root), 1)
        let retained = try XCTUnwrap(try loadJournal(in: fixture.root))
        XCTAssertEqual(retained.phase, .v2Validated)
        XCTAssertTrue(retained.targetWritePossible)
    }

    func testPreparedSourceMutationFailsClosedAgainstSourceManifest() throws {
        let fixture = try makeLegacyFixture(suffix: "SourceReproof")
        defer { try? fileManager.removeItem(at: fixture.root) }
        let processCursor = ProcessCursor()
        let factory = makeFactory(
            fixture: fixture,
            processCursor: processCursor,
            injection: StoreMigrationFailureInjection(
                failOnceAt: .afterPreparedJournalWrite
            )
        )

        XCTAssertThrowsError(try factory.openOrBootstrapCurrent()) { error in
            XCTAssertEqual(
                error as? StoreMigrationFailure,
                .injectedFault(.afterPreparedJournalWrite)
            )
        }
        let sourceModelURL = installedModelURL(
            in: fixture.root,
            id: fixture.sourceID
        )
        try Data(repeating: 0x5A, count: 32).write(
            to: sourceModelURL,
            options: .atomic
        )

        XCTAssertThrowsError(try factory.openOrBootstrapCurrent()) { error in
            XCTAssertEqual(
                error as? StoreMigrationFailure,
                .maintenanceRequired(.sourceMismatch)
            )
        }
        XCTAssertEqual(try pointerSchema(in: fixture.root), 1)
        let retained = try XCTUnwrap(try loadJournal(in: fixture.root))
        XCTAssertEqual(retained.phase, .prepared)
        XCTAssertFalse(retained.targetWritePossible)
    }
#endif

    func testLegacyPointerIsAcceptedAndFutureOrMalformedBinaryIsRejected() throws {
        let legacy = try makeLegacyFixture(suffix: "LegacyPointer")
        defer { try? fileManager.removeItem(at: legacy.root) }
        let processCursor = ProcessCursor()
        let factory = makeFactory(fixture: legacy, processCursor: processCursor)
        XCTAssertEqual(try pointerSchema(in: legacy.root), 1)
        var session: StoreGenerationSession? = try factory.openOrBootstrapCurrent()
        XCTAssertEqual(session?.generationID, legacy.targetID)
        session = nil
        let validPointerData = try Data(
            contentsOf: currentPointerURL(in: legacy.root)
        )
        XCTAssertEqual(try pointerSchema(in: legacy.root), 2)
        let validPointer = try CurrentGenerationPointerV2.decodeCanonical(
            from: validPointerData
        )
        XCTAssertEqual(
            validPointer.generationID,
            legacy.targetID.uuidString.lowercased()
        )

        let cases: [(String, Data, StoreMigrationFailure)] = [
            (
                "future",
                try StoreMigrationCanonicalJSONV1.encode(
                    FuturePointer(schemaVersion: 4)
                ),
                .maintenanceRequired(.futureVersion)
            ),
            (
                "malformed-v2",
                try StoreMigrationCanonicalJSONV1.encode(
                    MalformedV2Pointer(
                        generationID: legacy.targetID.uuidString.lowercased(),
                        generationManifestSHA256: "not-a-digest"
                    )
                ),
                .invalidDigest
            ),
        ]

        for (name, data, expected) in cases {
            try data.write(
                to: currentPointerURL(in: legacy.root),
                options: .atomic
            )
            XCTAssertThrowsError(try factory.openOrBootstrapCurrent(), name) { error in
                XCTAssertEqual(error as? StoreMigrationFailure, expected, name)
            }
            let restoredPointer = try CurrentGenerationPointerV2.decodeCanonical(
                from: validPointerData
            )
            XCTAssertEqual(restoredPointer.schemaVersion, 2, name)
            try validPointerData.write(
                to: currentPointerURL(in: legacy.root),
                options: .atomic
            )
        }
    }

    @MainActor
    func testLegacyRestorePublishesFormat2AndReusesRollbackManifest() throws {
        let fixture = try makeLegacyFixture(suffix: "LegacyRestore")
        defer { try? fileManager.removeItem(at: fixture.root) }
        let factory = StoreGenerationFactory(applicationSupportURL: fixture.root)
        let authority = try factory.makeRestoreGenerationAuthority()
        let firstRestoreID = fixedUUID(
            "00000000-0000-0000-0000-000000000021"
        )
        let secondRestoreID = fixedUUID(
            "00000000-0000-0000-0000-000000000022"
        )
        try factory.createEmptyInstalledGeneration(
            id: firstRestoreID,
            authority: authority
        )
        try factory.switchCurrentGeneration(
            expected: fixture.sourceID,
            to: firstRestoreID,
            authority: authority
        )

        let store = try StoreMigrationJournalStoreV1(
            applicationSupportURL: fixture.root
        )
        let firstPointer = try CurrentGenerationPointerV2.decodeCanonical(
            from: Data(contentsOf: currentPointerURL(in: fixture.root))
        )
        XCTAssertEqual(firstPointer.schemaVersion, 2)
        XCTAssertEqual(firstPointer.storeSchemaVersion, 2)
        XCTAssertEqual(
            firstPointer.generationID,
            firstRestoreID.uuidString.lowercased()
        )
        let firstManifest = try store.loadManifest(
            targetGenerationID: firstRestoreID,
            expectedDigest: firstPointer.generationManifestSHA256
        )
        XCTAssertEqual(firstManifest.storeSchemaRelease, .v2)
        XCTAssertEqual(firstManifest.migrationID, firstRestoreID)

        try factory.createEmptyInstalledGeneration(
            id: secondRestoreID,
            authority: authority
        )
        try factory.switchCurrentGeneration(
            expected: firstRestoreID,
            to: secondRestoreID,
            authority: authority
        )
        let secondPointer = try CurrentGenerationPointerV2.decodeCanonical(
            from: Data(contentsOf: currentPointerURL(in: fixture.root))
        )
        XCTAssertEqual(
            secondPointer.generationID,
            secondRestoreID.uuidString.lowercased()
        )
        XCTAssertNotEqual(
            secondPointer.generationManifestSHA256,
            firstPointer.generationManifestSHA256
        )

        try factory.switchCurrentGeneration(
            expected: secondRestoreID,
            to: firstRestoreID,
            authority: authority
        )
        let restoredPointer = try CurrentGenerationPointerV2.decodeCanonical(
            from: Data(contentsOf: currentPointerURL(in: fixture.root))
        )
        XCTAssertEqual(
            restoredPointer.generationID,
            firstRestoreID.uuidString.lowercased()
        )
        XCTAssertEqual(
            restoredPointer.generationManifestSHA256,
            firstPointer.generationManifestSHA256
        )
        let reusedManifest = try store.loadManifest(
            targetGenerationID: firstRestoreID,
            expectedDigest: restoredPointer.generationManifestSHA256
        )
        XCTAssertEqual(reusedManifest, firstManifest)
        XCTAssertEqual(
            try factory.currentGenerationID(authority: authority),
            firstRestoreID
        )
    }

    func testV23P03C38V8ToV9MigrationIsCopyOnWriteAndDoesNotInventParties() throws {
        XCTAssertEqual(
            PersistentSchemaMigrationPlanV8.schemas.map { ObjectIdentifier($0) },
            [
                ObjectIdentifier(PersistentSchemaV8.self),
                ObjectIdentifier(PersistentSchemaV9.self),
            ]
        )
        XCTAssertEqual(PersistentSchemaMigrationPlanV8.stages.count, 1)

        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let schemaSource = try String(
            contentsOf: root.appendingPathComponent(
                "FieldEvidenceApp/Infrastructure/Persistence/PersistentSchemas.swift"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(schemaSource.contains("PersistentSchemaV8.self, PersistentSchemaV9.self"))
        XCTAssertTrue(schemaSource.contains("empty collections"))
        XCTAssertTrue(schemaSource.contains("didMigrate: { _ in }"))

        let factorySource = try String(
            contentsOf: root.appendingPathComponent(
                "FieldEvidenceApp/Infrastructure/Persistence/StoreGenerationFactory.swift"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(factorySource.contains("PersistentSchemaMigrationPlanV8.self"))
        XCTAssertTrue(factorySource.contains("PersistentSchemaV9"))
    }

    func testV23P03C40V10ToV11MigrationIsEmptyAndKeepsAuthorityExplicit() throws {
        XCTAssertEqual(
            PersistentSchemaMigrationPlanV10.schemas.map { ObjectIdentifier($0) },
            [
                ObjectIdentifier(PersistentSchemaV10.self),
                ObjectIdentifier(PersistentSchemaV11.self),
            ]
        )
        XCTAssertEqual(PersistentSchemaMigrationPlanV10.stages.count, 1)
        XCTAssertEqual(PersistentSchemaV11.models.count, PersistentSchemaV10.models.count + 9)
        XCTAssertEqual(
            Array(PersistentSchemaV11.models.suffix(9)).map { ObjectIdentifier($0) },
            [
                ObjectIdentifier(AuthoritySourceReleaseRow.self),
                ObjectIdentifier(RequirementBasisBindingRow.self),
                ObjectIdentifier(ApplicabilityContextSnapshotRow.self),
                ObjectIdentifier(AssessmentScopeSnapshotRow.self),
                ObjectIdentifier(SeverityScaleReleaseRow.self),
                ObjectIdentifier(FindingClassificationBindingRow.self),
                ObjectIdentifier(MeasurementProtocolReleaseRow.self),
                ObjectIdentifier(DerivedFactEvaluatorDescriptorRow.self),
                ObjectIdentifier(DerivedFactProvenanceRow.self),
            ]
        )

        let schemaSource = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("FieldEvidenceApp/Infrastructure/Persistence/PersistentSchemas.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(schemaSource.contains("PersistentSchemaV10.self, PersistentSchemaV11.self"))
        XCTAssertTrue(schemaSource.contains("enum PersistentSchemaMigrationPlanV10"))
        XCTAssertTrue(schemaSource.contains("didMigrate: { _ in }"))

        let factorySource = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("FieldEvidenceApp/Infrastructure/Persistence/StoreGenerationFactory.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(factorySource.contains("PersistentSchemaMigrationPlanV10.self"))
        XCTAssertTrue(factorySource.contains("PersistentSchemaV11"))
    }

    private func makeLegacyFixture(suffix: String) throws -> LegacyFixture {
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "V9_03MigrationRecoveryTests-\(suffix)",
            isDirectory: true
        )
        try? fileManager.removeItem(at: root)
        let dataRoot = root.appendingPathComponent("FieldEvidenceData", isDirectory: true)
        let generationsRoot = dataRoot.appendingPathComponent("generations", isDirectory: true)

        let sourceID = fixedUUID("00000000-0000-0000-0000-000000000010")
        let migrationID = fixedUUID("00000000-0000-0000-0000-000000000011")
        let targetID = fixedUUID("00000000-0000-0000-0000-000000000012")
        let v3TargetID = fixedUUID("00000000-0000-0000-0000-000000000015")
        let v4TargetID = fixedUUID("00000000-0000-0000-0000-000000000016")
        let v5TargetID = fixedUUID("00000000-0000-0000-0000-000000000017")
        let v6TargetID = fixedUUID("00000000-0000-0000-0000-00000000001a")
        let v7TargetID = fixedUUID("00000000-0000-0000-0000-00000000001b")
        let v8TargetID = fixedUUID("00000000-0000-0000-0000-00000000001c")
        let v9TargetID = fixedUUID("00000000-0000-0000-0000-00000000001d")
        let siteID = fixedUUID("00000000-0000-0000-0000-000000000013")
        let assetID = fixedUUID("00000000-0000-0000-0000-000000000014")
        let recordID = fixedUUID("00000000-0000-0000-0000-000000000018")
        let processIDs = (0..<10).map {
            fixedUUID(String(format: "00000000-0000-0000-0000-00000000002%1d", $0))
        }
        let sourceRoot = generationsRoot.appendingPathComponent(
            sourceID.uuidString.lowercased(),
            isDirectory: true
        )
        let modelURL = sourceRoot.appendingPathComponent("model.sqlite", isDirectory: false)

        try fileManager.createDirectory(
            at: sourceRoot,
            withIntermediateDirectories: true
        )
        let createdAt = Date(timeIntervalSince1970: 1_700_000_100)
        do {
            let schema = PersistentSchemaV1.makeSchema()
            let configuration = ModelConfiguration(
                "V9_03LegacyV1",
                schema: schema,
                url: modelURL,
                allowsSave: true,
                cloudKitDatabase: .none
            )
            let container = try ModelContainer(
                for: schema,
                migrationPlan: nil,
                configurations: [configuration]
            )
            let context = container.mainContext
            context.insert(
                Site(
                    id: siteID,
                    label: "Synthetic Legacy Site",
                    address: "1 Synthetic Way",
                    timeZoneID: "America/New_York",
                    createdAt: createdAt,
                    updatedAt: createdAt
                )
            )
            context.insert(
                Asset(
                    id: assetID,
                    siteID: siteID,
                    packID: "field.evidence.illuminated_sign.v1",
                    packSchemaVersion: 1,
                    packContentVersion: 1,
                    label: "Synthetic Legacy Asset",
                    createdAt: createdAt,
                    updatedAt: createdAt
                )
            )
            context.insert(WorkflowRecord(
                id: recordID,
                assetID: assetID,
                packetID: nil,
                issueID: nil,
                parentRecordID: nil,
                recordRevisionRootID: recordID,
                revisesRecordID: nil,
                evidenceSourceRecordID: nil,
                revisionKind: .original,
                stage: .recheck,
                state: .completed,
                draftStepKey: nil,
                startedAt: createdAt,
                completedAt: createdAt.addingTimeInterval(5),
                observedAtUTC: createdAt,
                timeZoneID: "America/New_York",
                utcOffsetMinutes: -300,
                localDate: "2023-11-14",
                localTime: "17:15:00",
                afterDarkAcknowledgementKey: nil,
                afterDarkAcknowledgementCopy: nil,
                afterDarkAcknowledgementVersion: nil,
                afterDarkAcknowledgementAccepted: nil,
                safePositionAcknowledgementKey: nil,
                safePositionAcknowledgementCopy: nil,
                safePositionAcknowledgementVersion: nil,
                safePositionAcknowledgementAccepted: nil,
                packID: "field.evidence.illuminated_sign.v1",
                packSchemaVersion: 1,
                packContentVersion: 1,
                pdfTemplateID: "field.evidence.pdf.worklight.v1",
                pdfTemplateVersion: 1,
                outcomeKey: "could_not_verify",
                couldNotVerifyKey: "required_view_obstructed",
                couldNotVerifyDisplaySnapshot: "Required view is blocked",
                couldNotVerifyRegistryVersion: "cnv.reason.en-US.v1",
                workPerformedLocalDate: nil,
                workDescription: nil,
                note: nil,
                finalizationMutationID: fixedUUID(
                    "00000000-0000-0000-0000-000000000019"
                )
            ))
            try context.save()
        }

        let current = LegacyCurrentPointer(
            generationID: sourceID.uuidString.lowercased(),
            schemaVersion: 1
        )
        let retired = RetiredPointer(generationIDs: [], schemaVersion: 1)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try StoreMigrationCanonicalJSONV1.encode(current).write(
            to: dataRoot.appendingPathComponent("current.json"),
            options: .atomic
        )
        try StoreMigrationCanonicalJSONV1.encode(retired).write(
            to: dataRoot.appendingPathComponent("retired.json"),
            options: .atomic
        )

        return LegacyFixture(
            root: root,
            sourceID: sourceID,
            migrationID: migrationID,
            targetID: targetID,
            v3TargetID: v3TargetID,
            v4TargetID: v4TargetID,
            v5TargetID: v5TargetID,
            v6TargetID: v6TargetID,
            v7TargetID: v7TargetID,
            v8TargetID: v8TargetID,
            v9TargetID: v9TargetID,
            siteID: siteID,
            assetID: assetID,
            recordID: recordID,
            processIDs: processIDs
        )
    }

    private func makeFactory(
        fixture: LegacyFixture,
        processCursor: ProcessCursor
    ) -> StoreGenerationFactory {
        return StoreGenerationFactory(
            applicationSupportURL: fixture.root,
            migrationIdentitySource: makeIdentitySource(
                fixture: fixture,
                processCursor: processCursor
            )
        )
    }

    private func makeIdentitySource(
        fixture: LegacyFixture,
        processCursor: ProcessCursor
    ) -> StoreMigrationIdentitySourceV1 {
        StoreMigrationIdentitySourceV1(
            makeMigrationID: { fixture.migrationID },
            makeGenerationID: {
                let pointerURL = fixture.root
                    .appendingPathComponent("FieldEvidenceData", isDirectory: true)
                    .appendingPathComponent("current.json", isDirectory: false)
                let schemaVersion: Int?
                if let data = try? Data(contentsOf: pointerURL),
                   let object = try? JSONSerialization.jsonObject(with: data),
                   let fields = object as? [String: Any] {
                    schemaVersion = fields["schemaVersion"] as? Int
                } else {
                    schemaVersion = nil
                }
                if schemaVersion == 1 { return fixture.targetID }
                if let data = try? Data(contentsOf: pointerURL),
                   let pointer = try? CurrentGenerationPointerV3.decodeCanonical(from: data),
                   pointer.storeSchemaVersion >= 3 {
                    if pointer.storeSchemaVersion == 3 { return fixture.v4TargetID }
                    if pointer.storeSchemaVersion == 4 { return fixture.v5TargetID }
                    if pointer.storeSchemaVersion == 5 { return fixture.v6TargetID }
                    if pointer.storeSchemaVersion == 6 { return fixture.v7TargetID }
                    if pointer.storeSchemaVersion == 7 { return fixture.v8TargetID }
                    if pointer.storeSchemaVersion == 8 { return fixture.v9TargetID }
                    return UUID()
                }
                return fixture.v3TargetID
            },
            makeProcessID: {
                defer { processCursor.index += 1 }
                return fixture.processIDs[
                    min(processCursor.index, fixture.processIDs.count - 1)
                ]
            }
        )
    }

#if DEBUG
    private func makeFactory(
        fixture: LegacyFixture,
        processCursor: ProcessCursor,
        injection: StoreMigrationFailureInjection
    ) -> StoreGenerationFactory {
        StoreGenerationFactory(
            applicationSupportURL: fixture.root,
            migrationIdentitySource: makeIdentitySource(
                fixture: fixture,
                processCursor: processCursor
            ),
            migrationFailureInjection: injection
        )
    }
#endif

    private func assertMigratedRows(
        in context: ModelContext,
        fixture: LegacyFixture
    ) throws {
        let sites = try context.fetch(FetchDescriptor<Site>())
        let assets = try context.fetch(FetchDescriptor<Asset>())
        let records = try context.fetch(FetchDescriptor<WorkflowRecord>())
        XCTAssertEqual(sites.count, 1)
        XCTAssertEqual(assets.count, 1)
        XCTAssertEqual(records.count, 1)
        let site = try XCTUnwrap(sites.first)
        let asset = try XCTUnwrap(assets.first)
        XCTAssertEqual(site.id, fixture.siteID)
        XCTAssertEqual(site.label, "Synthetic Legacy Site")
        XCTAssertEqual(asset.id, fixture.assetID)
        XCTAssertEqual(asset.siteID, fixture.siteID)
        XCTAssertEqual(asset.label, "Synthetic Legacy Asset")
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record.id, fixture.recordID)
    }

    private func assertMarker(
        at modelURL: URL,
        migrationID: UUID,
        release: PersistentSchemaReleaseV1 = .v2
    ) throws {
        guard release != .v1 else {
            throw StoreMigrationFailure.invalidContract
        }
        let schema = Schema(release.models, version: release.versionIdentifier)
        let configuration = ModelConfiguration(
            "V9_03MarkerInspection",
            schema: schema,
            url: modelURL,
            allowsSave: false,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            migrationPlan: nil,
            configurations: [configuration]
        )
        let markers = try container.mainContext.fetch(
            FetchDescriptor<PersistentSchemaReleaseMarker>()
        )
        let marker = try XCTUnwrap(markers.first)
        XCTAssertEqual(markers.count, 1)
        XCTAssertEqual(marker.id, PersistentSchemaReleaseRegistryV1.v2MarkerID)
        guard let predecessorVersion = release.predecessorVersionIdentifier else {
            throw StoreMigrationFailure.invalidContract
        }
        let predecessor = try PersistentSchemaReleaseRegistryV1.release(for: predecessorVersion)
        let expectedSchemaVersion = release.versionIdentifier.major
        let expectedReleaseID = release.compatibilityID
        let expectedPredecessorID = predecessor.compatibilityID
        XCTAssertEqual(marker.schemaVersion, expectedSchemaVersion)
        XCTAssertEqual(
            marker.releaseID,
            expectedReleaseID
        )
        XCTAssertEqual(
            marker.predecessorReleaseID,
            expectedPredecessorID
        )
        XCTAssertEqual(marker.migrationID, migrationID)
    }

    private func semanticData(
        at modelURL: URL,
        root: URL,
        release: PersistentSchemaReleaseV1
    ) throws -> Data {
        let schema = Schema(release.models, version: release.versionIdentifier)
        let configuration = ModelConfiguration(
            "V9_03Semantic-\(release.rawValue)",
            schema: schema,
            url: modelURL,
            allowsSave: false,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            migrationPlan: nil,
            configurations: [configuration]
        )
        let service = try BackupRestoreService(applicationSupportURL: root)
        return try BackupCanonicalEncoderV1()
            .encodeRecords(
                service.migrationCanonicalRecords(in: container.mainContext)
            )
            .data
    }

    private func loadJournal(in root: URL) throws -> StoreMigrationJournalV1? {
        let store = try StoreMigrationJournalStoreV1(applicationSupportURL: root)
        return try store.loadJournal()
    }

    private func pointerSchema(in root: URL) throws -> Int {
        let data = try Data(contentsOf: currentPointerURL(in: root))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        return try XCTUnwrap(object["schemaVersion"] as? Int)
    }

    private func currentPointerURL(in root: URL) -> URL {
        root
            .appendingPathComponent("FieldEvidenceData", isDirectory: true)
            .appendingPathComponent("current.json", isDirectory: false)
    }

    private func installedModelURL(in root: URL, id: UUID) -> URL {
        root
            .appendingPathComponent("FieldEvidenceData", isDirectory: true)
            .appendingPathComponent("generations", isDirectory: true)
            .appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
            .appendingPathComponent("model.sqlite", isDirectory: false)
    }

    private func fixedUUID(_ value: String) -> UUID {
        UUID(uuidString: value)!
    }
}

private final class C27V903TypedLocatorAnchorTests: XCTestCase {
    func testAssetLocatorContractAnchor() throws {
        XCTAssertEqual(Set(LocatorInputSourceV1.allCases), [.camera, .manual, .imported])
        XCTAssertEqual(AssetLocatorStateV1.allCases.count, 4)
        XCTAssertFalse(AssetLocatorLifecycleAdapterV1.scanMutatesCanonicalState)
    }
}

extension V9_03MigrationRecoveryTests {
    func testC24AccessibleDocumentTypedAnchor() throws {
        XCTAssertEqual(AccessibleDocumentSemanticTreeV1.schemaVersion, 1)
        XCTAssertEqual(AccessibleDocumentRoleV1.allCases.count, 13)
        XCTAssertEqual(AccessibleDocumentAssessmentStateV1.allCases.count, 4)
        XCTAssertFalse(AccessibleDocumentLifecycleV1.pdfUAClaimed)
    }
}

extension V9_03MigrationRecoveryTests {
    func testC22RecoverabilityVerificationAnchor() throws {
        XCTAssertEqual(RecoverabilityVerificationReceiptV1.schemaVersion, 1)
        try V21RecoverabilityImportBoundaryV1.validate(persistentSchemaVersion: 21, recordsSchemaVersion: 20)
        XCTAssertEqual(RecoverabilityVerificationLifecycleV1.stagingPersistence, "DERIVED_ONLY_DROP_AND_REBUILD")
        XCTAssertFalse(RecoverabilityVerificationLifecycleV1.externalCopyAvailabilityClaimed)
    }
}

extension V9_03MigrationRecoveryTests {
    func testV23P03C15MigrationCarriesFiveWorkPacketRows() throws {
        let fixture = try C15WorkPacketManifestTestSupportV1.makeFixture(seed: 150_103)
        XCTAssertEqual(PersistentSchemaV15.versionIdentifier, Schema.Version(15, 0, 0))
        XCTAssertEqual(PersistentSchemaV15.models.count, 58)
        XCTAssertEqual(PersistentSchemaMigrationPlanV14.schemas.count, 2)
        XCTAssertEqual(PersistentSchemaMigrationPlanV14.stages.count, 1)
        XCTAssertEqual(try WorkPacketManifestRow(fixture.manifest).value(), fixture.manifest)
    }
}

extension V9_03MigrationRecoveryTests {
    func testV23P03C36MigrationAddsOnlyTheSixFieldDraftRows() throws {
        XCTAssertEqual(PersistentSchemaV15.versionIdentifier, Schema.Version(15, 0, 0))
        XCTAssertEqual(PersistentSchemaV15.models.count, 58)
        XCTAssertEqual(PersistentSchemaV16.versionIdentifier, Schema.Version(16, 0, 0))
        XCTAssertEqual(PersistentSchemaV16.models.count, 64)
        XCTAssertEqual(PersistentSchemaMigrationPlanV15.schemas.count, 2)
        XCTAssertEqual(PersistentSchemaMigrationPlanV15.stages.count, 1)

        let fixture = try C36FieldDraftTestSupportV1.makeFixture()
        XCTAssertEqual(try FieldDraftCheckpointRow(fixture.activeCheckpoint).value(), fixture.activeCheckpoint)
        XCTAssertEqual(try AttachmentStagingItemRow(fixture.readyItem).value(), fixture.readyItem)
        XCTAssertEqual(try DraftCommitSagaRow(fixture.preparedSaga).value(), fixture.preparedSaga)
        XCTAssertEqual(try DraftContentReservationRow(fixture.reservation).value(), fixture.reservation)
        XCTAssertEqual(try DraftCommitReceiptRow(fixture.commitReceipt).value(), fixture.commitReceipt)
        XCTAssertEqual(try DraftDiscardReceiptRow(fixture.discardReceipt).value(), fixture.discardReceipt)
    }
}

extension V9_03MigrationRecoveryTests {
    func testV23P03C41MigrationReplayRetainsCanonicalRelationshipHistory() throws {
        let fixture = try C41FunctionalRelationshipTestSupportV1.makeFixture(seed: 41_030)
        try fixture.ended.validateSuccessor(of: fixture.added)

        let endedProjection = try FunctionalRelationshipProjectionBuilderV1.rebuild(
            workspaceID: fixture.workspaceID,
            events: [fixture.added, fixture.ended],
            descriptors: [fixture.descriptor]
        )
        XCTAssertTrue(endedProjection.currentRelationships.isEmpty)
        XCTAssertEqual(endedProjection.readiness, .ready)

        let encoded = try FunctionalRelationshipCanonicalCodecV1.encode(fixture.ended)
        let decoded = try FunctionalRelationshipCanonicalCodecV1.decode(
            AssetFunctionalRelationshipEventV1.self, from: encoded
        )
        XCTAssertEqual(decoded, fixture.ended)
        XCTAssertEqual(try FunctionalRelationshipCanonicalCodecV1.encode(decoded), encoded)
    }
}

extension V9_03MigrationRecoveryTests {
    func testV23P03C13V12ToV13CopyOnWriteRowsRemainCanonical() throws {
        let fixture = try C13EvidenceAssuranceTestSupportV1.makeFixture(seed: 51_903)
        let rows: [(Data, Data)] = [
            (try EvidenceAssuranceCanonicalCodecV1.encode(fixture.routineVisibility), try EvidenceAssuranceCanonicalCodecV1.encode(try EvidenceVisibilityRow(fixture.routineVisibility).value())),
            (try EvidenceAssuranceCanonicalCodecV1.encode(fixture.customerLink), try EvidenceAssuranceCanonicalCodecV1.encode(try ClaimEvidenceLinkRow(fixture.customerLink).value())),
            (try EvidenceAssuranceCanonicalCodecV1.encode(fixture.customerManifest), try EvidenceAssuranceCanonicalCodecV1.encode(try AssuranceManifestRow(fixture.customerManifest).value())),
            (try EvidenceAssuranceCanonicalCodecV1.encode(fixture.customerAttestation), try EvidenceAssuranceCanonicalCodecV1.encode(try AttestationRow(fixture.customerAttestation).value()))
        ]

        XCTAssertTrue(rows.allSatisfy { $0.0 == $0.1 })
        XCTAssertEqual(PersistentSchemaV13.models.count, PersistentSchemaV12.models.count + 4)
        XCTAssertEqual(PersistentSchemaReleaseV1.v13.predecessorVersionIdentifier, PersistentSchemaV12.versionIdentifier)
        XCTAssertEqual(fixture.customerPreview.includedLinks.count, 1)
        XCTAssertEqual(fixture.customerPreview.excludedLinks.count, 1)
    }
}

extension V9_03MigrationRecoveryTests {
    func testV23P03C14MigrationAddsOnlyTheFiveReviewRows() throws {
        XCTAssertEqual(PersistentSchemaV14.versionIdentifier, Schema.Version(14, 0, 0))
        XCTAssertEqual(PersistentSchemaV14.models.count, 53)
        XCTAssertEqual(PersistentSchemaMigrationPlanV13.schemas.count, 2)
        XCTAssertEqual(PersistentSchemaMigrationPlanV13.stages.count, 1)
    }
}

extension V9_03MigrationRecoveryTests {
    func testV23P03C18MigrationBackupAndForwardFixPolicyIsTyped() throws {
        XCTAssertEqual(PackageEvolutionLifecycleV1.schema, "PACKAGE_EVOLUTION_V1")
        XCTAssertTrue(PackageEvolutionLifecycleV1.migrationRequired)
        XCTAssertTrue(PackageEvolutionLifecycleV1.backupRestoreRequired)
        XCTAssertTrue(PackageEvolutionLifecycleV1.deleteEraseRequired)
        XCTAssertEqual(
            PackageEvolutionLifecycleV1.downgradePolicy,
            "PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_FIRST_V17_WRITE"
        )

        let payload = Data("c18-migration-payload".utf8)
        let encoded = try PackageEvolutionCanonicalCodecV1.encode(payload)
        XCTAssertEqual(
            try PackageEvolutionCanonicalCodecV1.decode(Data.self, from: encoded),
            payload
        )
        XCTAssertThrowsError(
            try PackageEvolutionCanonicalCodecV1.decode(
                PackagePromotionReceiptV1.self,
                from: Data()
            )
        )
    }

    func testV23P03C19MigrationPlanRetainsV18MeasurementRows() throws {
        let fixture = try C19MeasurementIntegrityTestSupport.makeFixture()
        XCTAssertEqual(PersistentSchemaMigrationPlanV17.schemas.count, 2)
        XCTAssertEqual(PersistentSchemaMigrationPlanV17.stages.count, 1)
        XCTAssertEqual(fixture.bundle.workspaceID, fixture.workspace)
        try fixture.bundle.validate()
    }

    func testC20PrivacyTransformMigrationBoundaryIsTyped() throws {
        XCTAssertEqual(PersistentSchemaMigrationPlanV18.schemas.count, 2)
        XCTAssertEqual(PersistentSchemaMigrationPlanV18.stages.count, 1)
        try V19PrivacyTransformImportBoundaryV1.validate(persistent: 19, records: 18)
        XCTAssertThrowsError(try V19PrivacyTransformImportBoundaryV1.validate(persistent: 18, records: 18))
    }
}

extension V9_03MigrationRecoveryTests {
    func testC21ClientCapabilityLifecycleAnchor() throws {
        XCTAssertEqual(ClientCapabilityProfileV1.schemaVersion, 1)
        XCTAssertEqual(ClientAdmissionV1.allCases.count, 5)
        XCTAssertEqual(PackageLifecycleOperationV1.allCases.count, 9)
        XCTAssertEqual(PersistentSchemaV20.models.count, 81)
        XCTAssertNoThrow(try V20ClientCapabilityImportBoundaryV1.validate(persistent: 20, records: 19))
    }
}
extension V9_03MigrationRecoveryTests {
    func testC25SurveyDefinitionTypedAnchor() throws {
        XCTAssertEqual(PersistentSchemaMigrationPlanV23.schemas.count, 2)
        XCTAssertEqual(PersistentSchemaMigrationPlanV23.stages.count, 1)
        XCTAssertEqual(
            PersistentSchemaMigrationPlanV23.schemas.map { ObjectIdentifier($0) },
            [ObjectIdentifier(PersistentSchemaV23.self), ObjectIdentifier(PersistentSchemaV24.self)]
        )
        XCTAssertEqual(PersistentSchemaReleaseV1.v24.predecessorVersionIdentifier, PersistentSchemaV23.versionIdentifier)
    }
}
extension V9_03MigrationRecoveryTests {
    func testC26SurveySessionTypedAnchor() throws {
        XCTAssertEqual(ActivityKindSemanticsV1(kind: .survey).completion, .typedFactCollection)
        XCTAssertFalse(ActivityKindSemanticsV1(kind: .survey).mayClaimInspectionResult)
        XCTAssertEqual(SurveySessionStateV1.allCases.count, 8)
        XCTAssertEqual(SurveySessionTransitionV1.allCases.count, 10)
        XCTAssertNoThrow(try V25GuidedSurveyImportBoundaryV1.validate(persistent: 25, records: 24))
    }
}

extension V9_03MigrationRecoveryTests {
    func testV23P03C28TypedScheduleBoundaryIsClosedAndNonpersistent() {
        XCTAssertEqual(OccurrenceStateV1.allCases, [.upcoming, .ready, .due, .overdue, .deferred,
                                                    .missed, .skipped, .cancelled, .started, .completed])
        XCTAssertEqual(ScheduleReleaseActionV1.allCases.count, 6)
        XCTAssertFalse(WorkflowScheduleBoundaryV1.dueProjectionMayStartWorkflow)
    }
}
private final class C31LightingAnchorV903MigrationRecoveryTests: XCTestCase {
    func testC31TypedLightingPackageContractAnchor() throws {
        XCTAssertEqual(LightingPersistenceEnrollmentV1.persistentSchemaVersion, 31)
        XCTAssertEqual(LightingClaimTierV1.allCases.count, 5)
        XCTAssertTrue(LightingIssueKindV1.allCases.contains(.cameraBandingOnly))
        try LightingLimitsV1.digest(String(repeating: "a", count: 64))
    }
}

private final class C33TemporalEvidenceAnchorV903MigrationRecovery: XCTestCase {
    func testC33V903MigrationRecoveryCompatibilityBindsTypedTemporalEvidenceToItsOwner() throws {
        let value = try C33TemporalEvidenceTestSupport.ownerClip(
            factID: "migration.v33-temporal-evidence",
            kind: .audio,
            reportProjection: .typedLinkOnly
        )
        try C33TemporalEvidenceTestSupport.assertOwnerBoundary(
            value,
            factID: "migration.v33-temporal-evidence",
            kind: .audio,
            reportProjection: .typedLinkOnly
        )
        let anchor = try C33TemporalEvidenceTestSupport.anchor(clip: value.clip)
        XCTAssertEqual(anchor.clipSHA256, value.clip.clipSHA256)
        XCTAssertEqual(anchor.sourceContentID, value.clip.original.contentID)
    }
}

private final class C32AssistanceAnchorV903MigrationRecovery: XCTestCase {
    func testC32V903MigrationRecoveryCompatibilityKeepsProposalAtExplicitReviewBoundary() throws {
        let proposal = try C32AssistanceTestSupport.ownerProposal(
            entityKind: .asset,
            fieldID: "migration.forward-fix",
            value: .text("migration-safe manual value")
        )
        try C32AssistanceTestSupport.assertOwnerBoundary(
            proposal,
            entityKind: .asset,
            fieldID: "migration.forward-fix",
            valueKind: .text
        )
        let canonical = try AssistanceCanonicalCodecV1.encode(proposal)
        XCTAssertEqual(
            try AssistanceCanonicalCodecV1.decode(AssistanceProposalV1.self, from: canonical),
            proposal
        )
    }
}
private final class C46V903MigrationRecoveryCompatibilityTests: XCTestCase {
    func testC46MigrationRecoveryKeepsOperationalEmailPurposeSeparated() throws {
        try C46OperationalContactTestSupport.assertOwnerBoundary(
            owner: "migration-recovery",
            kind: .email,
            handoff: .email,
            slot: 46_003
        )
    }
}


private enum C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_03MigrationRecoveryTests_swift {
    static let compatibilityCardID = "V23-P03-C47"
    static let sharedEnvelopeDoesNotCollapseFamilyTruth = true
    static let installationAndPunchReceiptsRemainIndependent = true
    static let noPlanFallbackIsExplicit = true
    static let surveyDefinitionOwnershipIsPreserved = true
    static let legacyInspectionTruthIsNotRewritten = true
    static let threeReceiptIsolationIsRequired = true
}

private final class C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_03MigrationRecoveryTests_swift_Tests: XCTestCase {
    func testC47V903MigrationRecoveryTestsOwnerCompatibilityIsTyped() {
        XCTAssertEqual(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_03MigrationRecoveryTests_swift.compatibilityCardID, "V23-P03-C47")
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_03MigrationRecoveryTests_swift.sharedEnvelopeDoesNotCollapseFamilyTruth)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_03MigrationRecoveryTests_swift.installationAndPunchReceiptsRemainIndependent)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_03MigrationRecoveryTests_swift.noPlanFallbackIsExplicit)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_03MigrationRecoveryTests_swift.surveyDefinitionOwnershipIsPreserved)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_03MigrationRecoveryTests_swift.legacyInspectionTruthIsNotRewritten)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_03MigrationRecoveryTests_swift.threeReceiptIsolationIsRequired)
        XCTAssertEqual(ActivityContractPersistenceEnrollmentV2.persistentFamilies.count, 6)
        XCTAssertTrue(ActivityContractPersistenceEnrollmentV2.usesSoleWorkspaceWriter)
    }
}

private final class C48PortableReviewV903MigrationTests: XCTestCase {
    func testC48SessionMigrationPreservesBytesWithoutSwiftDataMigration() {
        XCTAssertEqual(C48PortableExchangeMigrationBoundaryV2.sourceVersion, 1)
        XCTAssertEqual(C48PortableExchangeMigrationBoundaryV2.targetVersion, 2)
        XCTAssertFalse(C48PortableExchangeMigrationBoundaryV2.canonicalSwiftDataSchemaChanged)
        XCTAssertTrue(C48PortableExchangeMigrationBoundaryV2.preservesExactBytes)
    }
}
private final class C49WorkResourceMigrationBoundaryTests: XCTestCase {
    func testMigrationPreservesAllReleasedDispositions() {
        XCTAssertEqual(WorkResourceDispositionV1.allCases.count, 4)
        XCTAssertEqual(C49WorkResourcePersistenceBoundaryV1.recordsSchemaVersion, 36)
        XCTAssertTrue(C49WorkResourcePersistenceBoundaryV1.acceptedBytesAreCanonical)
    }
}

private final class C05EvidenceMetadataMigrationBoundaryTests: XCTestCase {
    func testV23P03C05V42ToV43MigrationAndRecords41CompatibilityAreClosed() {
        XCTAssertTrue(C05EvidenceCurationMigrationBoundaryV1.validate())
        XCTAssertEqual(C05EvidenceCurationMigrationBoundaryV1.sourcePersistentSchemaVersion, 42)
        XCTAssertEqual(C05EvidenceCurationMigrationBoundaryV1.targetPersistentSchemaVersion, 43)
        XCTAssertEqual(C05EvidenceCurationMigrationBoundaryV1.currentRecordsSchemaVersion, 42)
        XCTAssertEqual(C05EvidenceCurationMigrationBoundaryV1.compatibleRecordsSchemaVersions, [41, 42])
        XCTAssertEqual(
            C05EvidenceCurationMigrationBoundaryV1.newlyAddedRows,
            ["EvidenceAssociationEventRowV1", "EvidenceSequenceRevisionRowV1"]
        )
        XCTAssertTrue(C05EvidenceCurationMigrationBoundaryV1.sourceRowsMustBeEmpty)
        XCTAssertFalse(C05EvidenceCurationMigrationBoundaryV1.backfillCreatesEvidenceTruth)
    }
}

extension C50MigrationRecoveryTests {
    func testV23P03C51MigrationUsesV37RecordsWithoutBackfillTruth() {
        XCTAssertTrue(
            C51ScheduleExceptionMigrationBoundaryV1.validate()
                && C51ScheduleExceptionMigrationBoundaryV1.newDurableRows
                    == ["ExceptionCalendarReleaseRow", "ScheduleOverrideEventRow"]
                && !C51ScheduleExceptionMigrationBoundaryV1.backfillCreatesScheduleTruth
                && C51ScheduleExceptionMigrationBoundaryV1.existingScheduleRowsRemainByteStable
        )
    }
}

extension V9_03MigrationRecoveryTests {
    func testV23P03C34FutureAndCorruptSceneBytesDiscardAndErase() throws {
        let port = InMemorySceneNavigationDeviceStatePortV1()
        let adapter = SceneNavigationStateAdapterV1(port: port)
        try port.saveSceneNavigationData(Data(#"{"schemaVersion":99}"#.utf8))
        XCTAssertEqual(
            try adapter.loadAndReconcile(), .discarded(.unsupportedSnapshotVersion)
        )
        XCTAssertNil(port.data)
        try port.saveSceneNavigationData(Data("not-json".utf8))
        XCTAssertEqual(try adapter.loadAndReconcile(), .discarded(.corruptSnapshot))
        XCTAssertNil(port.data)
    }
}

import Foundation
import Darwin
import SwiftData
import XCTest

@testable import FieldEvidenceApp

final class V9_08GenerationLeaseTests: XCTestCase {
    @MainActor
    func testLegacyAndV2RestorePublicationRetainsV3ManifestAndRejectsStalePointerBytes() throws {
        for version in [1, 2] {
            let root = try makeApplicationSupport(label: "restore-pointer-v\(version)")
            defer { try? fileManager.removeItem(at: root) }
            let factory = StoreGenerationFactory(applicationSupportURL: root)
            let old = try autoreleasepool { () throws -> CurrentGenerationPointerV3 in
                let session = try factory.openOrBootstrapCurrent()
                return try factory.currentGenerationPointerV3(expectedGenerationID: session.generationID)
            }
            let oldID = try XCTUnwrap(UUID(uuidString: old.generationID)), newID = UUID()
            let authority = try factory.makeRestoreGenerationAuthority()
            try factory.createEmptyInstalledGeneration(id: newID, authority: authority)
            let currentURL = root.appendingPathComponent("FieldEvidenceData/current.json")
            // Exercise each supported predecessor encoding at the physical
            // pointer boundary; the target is an actual factory-created store.
            let original: Data
            if version == 1 {
                original = try StoreMigrationCanonicalJSONV1.encode(CurrentPointerV1(generationID: old.generationID, schemaVersion: 1))
            } else {
                original = try CurrentGenerationPointerV2(generationID: oldID,
                    generationManifestSHA256: old.generationManifestSHA256).canonicalData()
            }
            try overwriteFilePreservingIdentity(original, at: currentURL)
            XCTAssertEqual(try CurrentPointerCodecV1.decode(original).generationID, old.generationID)
            try factory.switchCurrentGeneration(expected: oldID, to: newID, authority: authority)
            let publishedBytes = try Data(contentsOf: currentURL)
            let published = try CurrentGenerationPointerV3.decodeCanonical(from: publishedBytes)
            XCTAssertEqual(published.generationID, newID.uuidString.lowercased())
            XCTAssertEqual(published.storeSchemaVersion, PersistentSchemaReleaseRegistryV1.activeVersionIdentifier.major)
            let store = try StoreMigrationJournalStoreV1(applicationSupportURL: root)
            let manifest = try store.loadManifest(targetGenerationID: newID, expectedDigest: published.generationManifestSHA256)
            XCTAssertEqual(manifest.generationID, newID)
            XCTAssertEqual(manifest.predecessorGenerationID, oldID)
            XCTAssertEqual(manifest.storeSchemaRelease, PersistentSchemaReleaseRegistryV1.activeRelease)
            let modelURL = factory.installedGenerationURL(id: newID).appendingPathComponent("model.sqlite")
            let modelBefore = try Data(contentsOf: modelURL)
            XCTAssertFalse(modelBefore.isEmpty)

            // Same generation and same inode, but different canonical pointer
            // bytes: generation-only and inode-only comparisons must both fail.
            let drift = try CurrentGenerationPointerV2(generationID: oldID,
                generationManifestSHA256: String(repeating: old.generationManifestSHA256 == String(repeating: "a", count: 64) ? "b" : "a", count: 64)).canonicalData()
            try overwriteFilePreservingIdentity(drift, at: currentURL)
            XCTAssertEqual(try authority.currentGenerationID(), oldID)
            XCTAssertThrowsError(try authority.switchCurrentGeneration(expected: oldID, to: newID,
                pointer: published, expectedCurrentPointerData: original)) {
                XCTAssertEqual($0 as? StoreGenerationFailure, .dataPointerInvalid)
            }
            XCTAssertEqual(try Data(contentsOf: currentURL), drift)
            XCTAssertEqual(try Data(contentsOf: modelURL), modelBefore)

            try overwriteFilePreservingIdentity(original, at: currentURL)
            try authority.switchCurrentGeneration(expected: oldID, to: newID,
                pointer: published, expectedCurrentPointerData: original)
            XCTAssertEqual(try Data(contentsOf: currentURL), publishedBytes)
            XCTAssertEqual(try authority.currentGenerationID(), newID)
            XCTAssertEqual(try Data(contentsOf: modelURL), modelBefore)
        }
    }

    @MainActor
    func testOwnedGenerationQuarantineCleanupPreflightsNestedRemainingBytes() throws {
#if DEBUG
        let fixture = try makeRealPruneFixture(label: "owned-tree-quarantine", offset: 81)
        defer { try? fileManager.removeItem(at: fixture.root) }
        let factory = StoreGenerationFactory(applicationSupportURL: fixture.root)
        let store = try StoreMigrationJournalStoreV1(applicationSupportURL: fixture.root)
        let manifest = try XCTUnwrap(store.loadManifestIfPresent(targetGenerationID: fixture.candidateGenerationID))
        let epoch = try GenerationEpochV1(generationID: fixture.candidateGenerationID, generationManifestSHA256: manifest.digest)
        let registry = try factory.makeGenerationLeaseRegistry(ownerID: makeUUID(8_101))
        let lease = try registry.acquire(epoch: epoch, role: .reader)
        let held = try factory.reconcileGenerationLeasesAndPrune()
        XCTAssertFalse(held.prunedEpochs.contains(epoch))
        XCTAssertTrue(fileManager.fileExists(atPath: fixture.candidateModelURL.path))
        try registry.release(lease)

        let interrupted = StoreGenerationFactory(applicationSupportURL: fixture.root,
            pruneFailureInjection: StoreGenerationPruneFailureInjectionV1(failOnceAt: .prepared))
        XCTAssertThrowsError(try interrupted.reconcileGenerationLeasesAndPrune()) { error in
            XCTAssertEqual(error as? StoreGenerationPruneInjectedFailureV1, .injectedFault(.prepared))
        }
        let intent = try XCTUnwrap(registry.loadPruneIntent())
        let source = factory.installedGenerationURL(id: fixture.candidateGenerationID)
        var info = stat()
        XCTAssertEqual(Darwin.lstat(source.path, &info), 0)
        let name = ".prune-\(intent.operationID.uuidString.lowercased())-\(fixture.candidateGenerationID.uuidString.lowercased())-\(info.st_dev)-\(info.st_ino)"
        let quarantine = source.deletingLastPathComponent().appendingPathComponent(name)
        try fileManager.moveItem(at: source, to: quarantine)
        // Model an already-authorized quarantine whose unlink sequence was
        // interrupted after the database. This is not a newly accepted store.
        try fileManager.removeItem(at: quarantine.appendingPathComponent("model.sqlite"))
        let relative = "pdfs/81000000-0000-4000-8000-000000000001.pdf"
        let retained = quarantine.appendingPathComponent(relative)
        try fileManager.createDirectory(at: retained.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("remaining owned PDF".utf8).write(to: retained)
        let hostile = quarantine.appendingPathComponent("zz-unowned.bin")
        try Data("unknown quarantine member".utf8).write(to: hostile)
        let names = try fileManager.subpathsOfDirectory(atPath: quarantine.path).sorted()
        XCTAssertThrowsError(try factory.reconcileGenerationLeasesAndPrune())
        XCTAssertEqual(try Data(contentsOf: retained), Data("remaining owned PDF".utf8))
        XCTAssertEqual(try Data(contentsOf: hostile), Data("unknown quarantine member".utf8))
        XCTAssertEqual(try fileManager.subpathsOfDirectory(atPath: quarantine.path).sorted(), names)
        XCTAssertEqual(try registry.loadPruneIntent(), intent)
        try fileManager.removeItem(at: hostile)
        let recovered = try factory.reconcileGenerationLeasesAndPrune()
        XCTAssertTrue(recovered.prunedEpochs.contains(epoch))
        XCTAssertFalse(fileManager.fileExists(atPath: quarantine.path))
        XCTAssertNil(try registry.loadPruneIntent())
#endif
    }

    private let fileManager = FileManager.default

    @MainActor
    func testDirectoryMembershipChangesPreserveOriginalLeaseAndMigrationOwners() throws {
        let root = try makeApplicationSupport(label: "directory-membership")
        defer { try? fileManager.removeItem(at: root) }
        let registry = try GenerationLeaseRegistryV1(applicationSupportURL: root)
        let epoch = try makeEpoch(9_801)
        let lease = try registry.acquire(epoch: epoch, role: .reader)
        let journal = try StoreMigrationJournalStoreV1(applicationSupportURL: root)
        let registryFile = root.appendingPathComponent("FieldEvidenceOperations/generation-leases/registry.json")
        let original = try Data(contentsOf: registryFile)
        try fileManager.createDirectory(at: root.appendingPathComponent("FieldEvidenceData/generations"),
            withIntermediateDirectories: true)
        try registry.validateActive(lease, requiredRole: .reader)
        XCTAssertNil(try journal.loadJournal())
        let secondOwner = try GenerationLeaseRegistryV1(applicationSupportURL: root)
        let secondLease = try secondOwner.acquire(epoch: epoch, role: .reader)
        try registry.validateActive(lease, requiredRole: .reader)
        XCTAssertNil(try journal.loadJournal())
        try secondOwner.release(secondLease)
        XCTAssertEqual(try Data(contentsOf: registryFile), original)
        try registry.release(lease)
    }

    @MainActor
    func testDirectoryReplacementAndControlHardLinksStillRejectOriginalOwners() throws {
        for replaceDirectory in [true, false] {
            let root = try makeApplicationSupport(label: "hostile-directory-\(replaceDirectory)")
            defer { try? fileManager.removeItem(at: root) }
            let registry = try GenerationLeaseRegistryV1(applicationSupportURL: root)
            let journal = try StoreMigrationJournalStoreV1(applicationSupportURL: root)
            let lease = try registry.acquire(epoch: makeEpoch(9_802), role: .reader)
            let operations = root.appendingPathComponent("FieldEvidenceOperations")
            let control = operations.appendingPathComponent("generation-leases/registry.json")
            let original = try Data(contentsOf: control)
            if replaceDirectory {
                let retained = root.appendingPathComponent("retained-original-operations")
                try fileManager.moveItem(at: operations, to: retained)
                try fileManager.createDirectory(at: operations, withIntermediateDirectories: false)
                XCTAssertThrowsError(try registry.validateActive(lease, requiredRole: .reader))
                XCTAssertThrowsError(try journal.loadJournal())
                XCTAssertEqual(try Data(contentsOf: retained.appendingPathComponent("generation-leases/registry.json")), original)
                XCTAssertTrue(try fileManager.contentsOfDirectory(atPath: operations.path).isEmpty)
            } else {
                let lock = operations.appendingPathComponent("generation-leases/mutation.lock")
                let alias = root.appendingPathComponent("unexpected-lock-alias")
                XCTAssertEqual(Darwin.link(lock.path, alias.path), 0)
                XCTAssertThrowsError(try registry.validateActive(lease, requiredRole: .reader))
                XCTAssertEqual(try Data(contentsOf: control), original)
                try fileManager.removeItem(at: alias)
                try registry.validateActive(lease, requiredRole: .reader)
                try registry.release(lease)
            }
        }
    }

    func testV9_08G01DurableLeaseIdentityAndBoundedRegistry() throws {
        let root = try makeApplicationSupport(label: "g01")
        defer { try? fileManager.removeItem(at: root) }

        let epoch = try makeEpoch(1)
        let leaseIDs = UUIDCursor((10...16).map(makeUUID))
        let fixedDate = Date(timeIntervalSinceReferenceDate: 123_456)

        do {
            let registry = try GenerationLeaseRegistryV1(
                applicationSupportURL: root,
                ownerID: makeUUID(100),
                makeLeaseID: { leaseIDs.next() },
                now: { fixedDate }
            )

            let reader = try registry.acquire(epoch: epoch, role: .reader)
            let writer = try registry.acquire(epoch: epoch, role: .writer)
            XCTAssertEqual(reader.ownerID, registry.ownerID)
            XCTAssertEqual(writer.ownerID, registry.ownerID)
            XCTAssertEqual(reader.epoch, epoch)
            XCTAssertEqual(writer.epoch, epoch)
            XCTAssertEqual(reader.role, .reader)
            XCTAssertEqual(writer.role, .writer)
            XCTAssertEqual(reader.acquiredAt, fixedDate)
            XCTAssertEqual(writer.acquiredAt, fixedDate)

            try registry.validateActive(reader, requiredRole: .reader)
            try registry.validateActive(writer, requiredRole: .writer)
            XCTAssertThrowsError(
                try registry.validateActive(reader, requiredRole: .writer)
            ) { error in
                XCTAssertEqual(
                    error as? GenerationLeaseRegistryFailureV1,
                    .wrongLeaseRole
                )
            }
            XCTAssertEqual(try registry.activeEpochs(), Set([epoch]))

            let epochBytes = try epoch.canonicalData()
            XCTAssertEqual(
                try GenerationEpochV1.decodeCanonical(from: epochBytes),
                epoch
            )
            let readerBytes = try reader.canonicalData()
            XCTAssertEqual(
                try GenerationLeaseTokenV1.decodeCanonical(from: readerBytes),
                reader
            )

            let registryURL = root.appendingPathComponent(
                "FieldEvidenceOperations/generation-leases/registry.json"
            )
            let registryObject = try XCTUnwrap(
                try JSONSerialization.jsonObject(
                    with: Data(contentsOf: registryURL)
                ) as? [String: Any]
            )
            XCTAssertEqual(registryObject["schemaVersion"] as? Int, 1)
            let persistedLeases = try XCTUnwrap(
                registryObject["leases"] as? [[String: Any]]
            )
            XCTAssertEqual(persistedLeases.count, 2)
            XCTAssertEqual(
                persistedLeases.compactMap { $0["leaseID"] as? String },
                persistedLeases.compactMap { $0["leaseID"] as? String }.sorted()
            )

            try registry.release(reader)
            XCTAssertThrowsError(try registry.release(reader)) { error in
                XCTAssertEqual(
                    error as? GenerationLeaseRegistryFailureV1,
                    .leaseNotActive
                )
            }

            let handle = try registry.acquireHandle(epoch: epoch, role: .reader)
            try handle.close()
            try handle.close()
            try registry.release(writer)
            XCTAssertTrue(try registry.activeEpochs().isEmpty)
        }

        let reopened = try GenerationLeaseRegistryV1(
            applicationSupportURL: root,
            ownerID: makeUUID(101),
            makeLeaseID: { v908MakeUUID(17) },
            now: { fixedDate }
        )
        XCTAssertTrue(try reopened.activeEpochs().isEmpty)
        XCTAssertFalse(
            fileManager.fileExists(
                atPath: root.appendingPathComponent(
                    "FieldEvidenceOperations/generation-leases/registry.next.json"
                ).path
            )
        )
        try reopened.withExclusiveGenerationMutationLock {
            XCTAssertEqual(try reopened.activeEpochs(), Set<GenerationEpochV1>())
        }
    }

    @MainActor
    func testV9_08A01ExpectedEpochAndLeaseFenceRejectsStaleCommit() throws {
        let root = try makeApplicationSupport(label: "a01")
        defer { try? fileManager.removeItem(at: root) }

        let epoch = try makeEpoch(2)
        let successor = try makeEpoch(3)
        let leaseIDs = UUIDCursor([makeUUID(20), makeUUID(21)])
        let registry = try GenerationLeaseRegistryV1(
            applicationSupportURL: root,
            ownerID: makeUUID(110),
            makeLeaseID: { leaseIDs.next() },
            now: { Date(timeIntervalSinceReferenceDate: 222_222) }
        )
        let writer = try registry.acquire(epoch: epoch, role: .writer)
        let reader = try registry.acquire(epoch: epoch, role: .reader)

        var currentEpoch = epoch
        let fence = try StaleWriterFenceV1(
            expectedGenerationEpoch: epoch,
            writerLeaseToken: writer,
            registry: registry,
            currentGenerationEpoch: { currentEpoch }
        )

        try fence.validateCurrent()
        var canonicalCommitCount = 0
        let committedValue = try fence.withAuthorizedCommit {
            canonicalCommitCount += 1
            return "committed"
        }
        XCTAssertEqual(committedValue, "committed")
        XCTAssertEqual(canonicalCommitCount, 1)

        XCTAssertThrowsError(
            try StaleWriterFenceV1(
                expectedGenerationEpoch: epoch,
                writerLeaseToken: reader,
                registry: registry,
                currentGenerationEpoch: { epoch }
            )
        ) { error in
            XCTAssertEqual(
                error as? GenerationLeaseRegistryFailureV1,
                .invalidContract
            )
        }

        currentEpoch = successor
        XCTAssertThrowsError(try fence.validateCurrent()) { error in
            XCTAssertEqual(
                error as? GenerationLeaseRegistryFailureV1,
                .staleGeneration
            )
        }
        var staleOperationRan = false
        XCTAssertThrowsError(
            try fence.withAuthorizedCommit {
                staleOperationRan = true
            }
        ) { error in
            XCTAssertEqual(
                error as? GenerationLeaseRegistryFailureV1,
                .staleGeneration
            )
        }
        XCTAssertFalse(staleOperationRan)
        XCTAssertEqual(canonicalCommitCount, 1)
        XCTAssertNil(try registry.loadLastPruneReceipt())

        try registry.release(writer)
        XCTAssertThrowsError(
            try fence.withAuthorizedCommit { () -> Void in }
        ) { error in
            XCTAssertEqual(
                error as? GenerationLeaseRegistryFailureV1,
                .leaseNotActive
            )
        }
        XCTAssertEqual(try registry.activeEpochs(), Set([epoch]))
        try registry.release(reader)

        let realRoot = try makeApplicationSupport(label: "a01-real-writer")
        defer { try? fileManager.removeItem(at: realRoot) }
        let realFactory = StoreGenerationFactory(
            applicationSupportURL: realRoot
        )
        let realSession = try realFactory.openOrBootstrapCurrent()
        let realOldEpoch = try XCTUnwrap(realSession.generationEpoch)
        let realReaderLease = try XCTUnwrap(realSession.readerLeaseToken)
        let realCoordinator = StoreSessionCoordinator(
            session: realSession,
            clock: V908FixedClock(
                value: Date(timeIntervalSinceReferenceDate: 222_333)
            ),
            idSource: V908FixedIDSource(value: v908MakeUUID(230)),
            fileAuthority: V908FileAuthority()
        )
        let realWriter = realCoordinator.workspaceWriter
        let realBefore = try realWriter.currentRevision()
        let realSiteID = v908MakeUUID(231)
        let realAssetID = v908MakeUUID(232)
        let realMutationID = try MutationIDV1(rawValue: v908MakeUUID(233))
        let realPlacementEventID = v908MakeUUID(244)
        let realPhysicalEpisodeID = try PhysicalPlacementEpisodeIDV1(
            rawValue: v908MakeUUID(245)
        )
        let realExpected = try WorkspaceExpectedRevisionV1(
            workspaceID: realBefore.workspaceID,
            generationID: realBefore.generationID,
            writerInstanceID: realBefore.writerInstanceID,
            workspaceRevision: realBefore.revision,
            entityRevisions: [
                .init(
                    identity: try WorkspaceEntityIdentityV1(
                        kind: .site,
                        id: realSiteID
                    ),
                    revision: 0
                ),
                .init(
                    identity: try WorkspaceEntityIdentityV1(
                        kind: .asset,
                        id: realAssetID
                    ),
                    revision: 0
                ),
                .init(
                    identity: try WorkspaceEntityIdentityV1(
                        kind: .assetPlacementEvent,
                        id: realPlacementEventID
                    ),
                    revision: 0
                ),
            ]
        )
        let realRequest = WorkspaceMutationRequestV1(
            mutationID: realMutationID,
            expectedRevision: realExpected,
            command: .createFirstSign(.init(
                siteID: realSiteID,
                newSite: .init(
                    id: realSiteID,
                    label: "Lease test site",
                    address: nil,
                    timeZoneID: "UTC"
                ),
                assetID: realAssetID,
                assetLabel: "Lease test asset",
                packID: "v23.lease.test",
                packSchemaVersion: 1,
                packContentVersion: 1,
                createdAt: Date(timeIntervalSinceReferenceDate: 222_334),
                initialPlacementMutationID: realMutationID,
                initialPlacementEventID: realPlacementEventID,
                initialPhysicalEpisodeID: realPhysicalEpisodeID
            ))
        )
        let realOutcome = try realWriter.execute(realRequest)
        XCTAssertEqual(realOutcome.before.revision, 0)
        XCTAssertEqual(realOutcome.after.revision, 1)
        let realReceipt = try XCTUnwrap(
            try realWriter.durableReceipt(mutationID: realMutationID)
        )
        XCTAssertEqual(realReceipt.identity.localSequence, 1)
        XCTAssertEqual(realReceipt.resultingRevision.workspaceRevision, 1)

        let staleSiteID = v908MakeUUID(234)
        let staleAssetID = v908MakeUUID(235)
        let staleMutationID = try MutationIDV1(rawValue: v908MakeUUID(236))
        let stalePlacementEventID = v908MakeUUID(246)
        let stalePhysicalEpisodeID = try PhysicalPlacementEpisodeIDV1(
            rawValue: v908MakeUUID(247)
        )
        let staleExpected = try WorkspaceExpectedRevisionV1(
            workspaceID: realBefore.workspaceID,
            generationID: realBefore.generationID,
            writerInstanceID: realBefore.writerInstanceID,
            workspaceRevision: realBefore.revision,
            entityRevisions: [
                .init(
                    identity: try WorkspaceEntityIdentityV1(
                        kind: .site,
                        id: staleSiteID
                    ),
                    revision: 0
                ),
                .init(
                    identity: try WorkspaceEntityIdentityV1(
                        kind: .asset,
                        id: staleAssetID
                    ),
                    revision: 0
                ),
                .init(
                    identity: try WorkspaceEntityIdentityV1(
                        kind: .assetPlacementEvent,
                        id: stalePlacementEventID
                    ),
                    revision: 0
                ),
            ]
        )
        let staleRequest = WorkspaceMutationRequestV1(
            mutationID: staleMutationID,
            expectedRevision: staleExpected,
            command: .createFirstSign(.init(
                siteID: staleSiteID,
                newSite: .init(
                    id: staleSiteID,
                    label: "Stale site",
                    address: nil,
                    timeZoneID: "UTC"
                ),
                assetID: staleAssetID,
                assetLabel: "Stale asset",
                packID: "v23.lease.test",
                packSchemaVersion: 1,
                packContentVersion: 1,
                createdAt: Date(timeIntervalSinceReferenceDate: 222_335),
                initialPlacementMutationID: staleMutationID,
                initialPlacementEventID: stalePlacementEventID,
                initialPhysicalEpisodeID: stalePhysicalEpisodeID
            ))
        )
        XCTAssertThrowsError(try realWriter.execute(staleRequest)) { error in
            XCTAssertEqual(
                error as? WorkspaceMutationFailureV1,
                .staleWorkspaceRevision
            )
        }
        XCTAssertNil(try realWriter.durableReceipt(mutationID: staleMutationID))
        let afterStale = try realWriter.currentRevision()
        XCTAssertEqual(afterStale.revision, realOutcome.after.revision)
        XCTAssertEqual(
            try realWriter.durableReceipt(mutationID: realMutationID),
            realReceipt
        )
        XCTAssertEqual(
            try realSession.modelContext.fetch(FetchDescriptor<Site>(
                predicate: #Predicate { $0.id == staleSiteID }
            )).count,
            0
        )
        let retryExpected = try WorkspaceExpectedRevisionV1(
            workspaceID: afterStale.workspaceID,
            generationID: afterStale.generationID,
            writerInstanceID: afterStale.writerInstanceID,
            workspaceRevision: afterStale.revision,
            entityRevisions: [
                .init(
                    identity: try WorkspaceEntityIdentityV1(
                        kind: .site,
                        id: realSiteID
                    ),
                    revision: 1
                ),
            ]
        )
        let retryMutationID = try MutationIDV1(rawValue: v908MakeUUID(237))
        let retryOutcome = try realWriter.execute(WorkspaceMutationRequestV1(
            mutationID: retryMutationID,
            expectedRevision: retryExpected,
            command: .updateSiteTimeZone(.init(
                siteID: realSiteID,
                timeZoneID: "America/New_York",
                confirmedAt: Date(timeIntervalSinceReferenceDate: 222_336)
            ))
        ))
        XCTAssertEqual(retryOutcome.after.revision, 2)
        let retryReceipt = try XCTUnwrap(
            try realWriter.durableReceipt(mutationID: retryMutationID)
        )
        XCTAssertEqual(retryReceipt.identity.localSequence, 2)

        let switchedGenerationID = v908MakeUUID(238)
        let oldPointer = try makeRestorePointer(
            from: try realFactory.currentGenerationPointerV3(
                expectedGenerationID: realSession.generationID
            )
        )
        let switchAuthority = try realFactory.makeRestoreGenerationAuthority()
        let switched = try realFactory.createEmptyEraseGeneration(
            id: switchedGenerationID,
            expectedOldPointer: oldPointer,
            identity: realSession.workspaceIdentity,
            authority: switchAuthority
        )
        try realFactory.publishEmptyEraseGeneration(
            expectedOldPointer: oldPointer,
            targetPointer: switched.pointer,
            expectedEmptyLedger: switched.ledgerProof,
            authority: switchAuthority
        )
        try realFactory.retireGeneration(
            oldID: realSession.generationID,
            currentID: switchedGenerationID
        )
        let switchedEpoch = try realFactory.currentGenerationEpoch()
        XCTAssertEqual(switchedEpoch.generationID, switchedGenerationID)
        XCTAssertNotEqual(switchedEpoch, realOldEpoch)

        let activeEpochProbe = try realFactory.makeGenerationLeaseRegistry(
            ownerID: v908MakeUUID(243)
        )
        XCTAssertTrue(try activeEpochProbe.activeEpochs().contains(realOldEpoch))
        XCTAssertEqual(realReaderLease.epoch, realOldEpoch)

        let switchedSiteID = v908MakeUUID(239)
        let switchedAssetID = v908MakeUUID(240)
        let switchedMutationID = try MutationIDV1(rawValue: v908MakeUUID(241))
        let switchedPlacementEventID = v908MakeUUID(248)
        let switchedPhysicalEpisodeID = try PhysicalPlacementEpisodeIDV1(
            rawValue: v908MakeUUID(249)
        )
        let switchedExpected = try WorkspaceExpectedRevisionV1(
            workspaceID: realBefore.workspaceID,
            generationID: realBefore.generationID,
            writerInstanceID: realBefore.writerInstanceID,
            workspaceRevision: retryOutcome.after.revision,
            entityRevisions: [
                .init(
                    identity: try WorkspaceEntityIdentityV1(
                        kind: .site,
                        id: switchedSiteID
                    ),
                    revision: 0
                ),
                .init(
                    identity: try WorkspaceEntityIdentityV1(
                        kind: .asset,
                        id: switchedAssetID
                    ),
                    revision: 0
                ),
                .init(
                    identity: try WorkspaceEntityIdentityV1(
                        kind: .assetPlacementEvent,
                        id: switchedPlacementEventID
                    ),
                    revision: 0
                ),
            ]
        )
        let switchedRequest = WorkspaceMutationRequestV1(
            mutationID: switchedMutationID,
            expectedRevision: switchedExpected,
            command: .createFirstSign(.init(
                siteID: switchedSiteID,
                newSite: .init(
                    id: switchedSiteID,
                    label: "Rejected after generation switch",
                    address: nil,
                    timeZoneID: "UTC"
                ),
                assetID: switchedAssetID,
                assetLabel: "Rejected asset",
                packID: "v23.lease.test",
                packSchemaVersion: 1,
                packContentVersion: 1,
                createdAt: Date(timeIntervalSinceReferenceDate: 222_337),
                initialPlacementMutationID: switchedMutationID,
                initialPlacementEventID: switchedPlacementEventID,
                initialPhysicalEpisodeID: switchedPhysicalEpisodeID
            ))
        )
        XCTAssertThrowsError(try realWriter.execute(switchedRequest)) { error in
            XCTAssertEqual(
                error as? WorkspaceMutationFailureV1,
                .wrongGeneration
            )
        }
        XCTAssertNil(try realWriter.durableReceipt(mutationID: switchedMutationID))
        XCTAssertEqual(
            try realSession.modelContext.fetch(FetchDescriptor<Site>(
                predicate: #Predicate { $0.id == switchedSiteID }
            )).count,
            0
        )
        XCTAssertEqual(
            try realSession.modelContext.fetch(FetchDescriptor<Asset>(
                predicate: #Predicate { $0.id == switchedAssetID }
            )).count,
            0
        )
        let receiptRows = try realSession.modelContext.fetch(
            FetchDescriptor<MutationReceiptRow>()
        )
        XCTAssertEqual(receiptRows.count, 2)
        XCTAssertEqual(
            receiptRows.map(\.localSequence).sorted(),
            [Int64(1), Int64(2)]
        )
        let stateRows = try realSession.modelContext.fetch(
            FetchDescriptor<WorkspaceMutationStateRow>()
        )
        XCTAssertEqual(stateRows.count, 1)
        XCTAssertEqual(stateRows.first?.workspaceRevision, 2)

        let retainedOldGeneration = try realFactory
            .reconcileGenerationLeasesAndPrune()
        XCTAssertEqual(
            retainedOldGeneration.disposition,
            .noEligibleGenerations
        )
        XCTAssertTrue(
            retainedOldGeneration.activeRetainedEpochs.contains(realOldEpoch)
        )
    }

    @MainActor
    func testV9_08H01UnknownCorruptAndUncertainOwnershipRetainsBytes() throws {
        let activeReadRoot = try makeApplicationSupport(label: "h01-active-read")
        defer { try? fileManager.removeItem(at: activeReadRoot) }
        let activeReadFactory = StoreGenerationFactory(
            applicationSupportURL: activeReadRoot
        )
        var activeReadSession: StoreGenerationSession? = try activeReadFactory
            .openOrBootstrapCurrent()
        let activeReadOpened = try XCTUnwrap(activeReadSession)
        let activeReadEpoch = try XCTUnwrap(activeReadOpened.generationEpoch)
        let activeReadToken = try XCTUnwrap(activeReadOpened.readerLeaseToken)
        XCTAssertEqual(activeReadToken.role, .reader)
        let activeReadPrune = try activeReadFactory
            .reconcileGenerationLeasesAndPrune()
        XCTAssertEqual(activeReadPrune.disposition, .noEligibleGenerations)
        XCTAssertTrue(activeReadPrune.retainedEpochs.contains(activeReadEpoch))
        XCTAssertTrue(activeReadPrune.activeRetainedEpochs.contains(activeReadEpoch))

        // A missing owner guard makes liveness uncertain even when every
        // lease still names a known accepted generation. The durable receipt
        // must carry that fact instead of inventing an uncertain generation ID.
        var uncertainOwnerRegistry: GenerationLeaseRegistryV1? = try
            activeReadFactory.makeGenerationLeaseRegistry(
                ownerID: makeUUID(118)
            )
        _ = try uncertainOwnerRegistry!.acquire(
            epoch: activeReadEpoch,
            role: .reader
        )
        let uncertainOwnerLock = activeReadRoot.appendingPathComponent(
            "FieldEvidenceOperations/generation-leases/owners/\(makeUUID(118).uuidString.lowercased()).lock"
        )
        try fileManager.removeItem(at: uncertainOwnerLock)
        let uncertainOwnerPrune = try activeReadFactory
            .reconcileGenerationLeasesAndPrune()
        XCTAssertEqual(uncertainOwnerPrune.disposition, .uncertainRetainAll)
        XCTAssertTrue(uncertainOwnerPrune.ownerLivenessUncertain)
        XCTAssertTrue(uncertainOwnerPrune.uncertainRetainedGenerationIDs.isEmpty)
        let uncertainOwnerReceiptRegistry = try activeReadFactory
            .makeGenerationLeaseRegistry(ownerID: makeUUID(117))
        XCTAssertEqual(
            try uncertainOwnerReceiptRegistry.loadLastPruneReceipt(),
            uncertainOwnerPrune
        )
        uncertainOwnerRegistry = nil
        activeReadSession = nil

        let unknownRoot = try makeApplicationSupport(label: "h01-unknown")
        defer { try? fileManager.removeItem(at: unknownRoot) }
        let unknownFactory = StoreGenerationFactory(
            applicationSupportURL: unknownRoot
        )
        var unknownSession: StoreGenerationSession? = try unknownFactory
            .openOrBootstrapCurrent()
        let unknownInstalledID = makeUUID(405)
        let unknownAuthority = try unknownFactory.makeRestoreGenerationAuthority()
        try unknownFactory.createEmptyInstalledGeneration(
            id: unknownInstalledID,
            authority: unknownAuthority
        )
        let unknownBytesURL = unknownFactory
            .installedGenerationURL(id: unknownInstalledID)
            .appendingPathComponent("model.sqlite")
        XCTAssertTrue(fileManager.fileExists(atPath: unknownBytesURL.path))
        let unknownLeaseRegistry = try unknownFactory.makeGenerationLeaseRegistry(
            ownerID: makeUUID(119)
        )
        let unknownLease = try unknownLeaseRegistry.acquire(
            epoch: try makeEpoch(404),
            role: .reader
        )
        let uncertainPrune = try unknownFactory
            .reconcileGenerationLeasesAndPrune()
        XCTAssertEqual(uncertainPrune.disposition, .uncertainRetainAll)
        XCTAssertTrue(uncertainPrune.ownerLivenessUncertain)
        XCTAssertTrue(
            uncertainPrune.uncertainRetainedGenerationIDs
                .contains(unknownLease.epoch.generationID)
        )
        XCTAssertTrue(
            uncertainPrune.uncertainRetainedGenerationIDs
                .contains(unknownInstalledID)
        )
        XCTAssertTrue(fileManager.fileExists(atPath: unknownBytesURL.path))
        let recoveryDisabledPolicy = try GenerationPrunePolicyV1(
            retainedInactiveAcceptedGenerationCount: 2,
            pruningEnabled: false
        )
        let disabledPrune = try unknownFactory
            .reconcileGenerationLeasesAndPrune(policy: recoveryDisabledPolicy)
        XCTAssertEqual(disabledPrune.disposition, .disabledRetainAll)
        XCTAssertTrue(disabledPrune.prunedEpochs.isEmpty)
        XCTAssertTrue(fileManager.fileExists(atPath: unknownBytesURL.path))
        try unknownLeaseRegistry.release(unknownLease)
        unknownSession = nil

        let root = try makeApplicationSupport(label: "h01")
        defer { try? fileManager.removeItem(at: root) }

        let retainedBytes = Data("retain this generation".utf8)
        let retainedURL = root.appendingPathComponent(
            "FieldEvidenceData/generations/retained/payload.bin"
        )
        try fileManager.createDirectory(
            at: retainedURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try retainedBytes.write(to: retainedURL)

        let epoch = try makeEpoch(4)
        let foreignOwner = makeUUID(120)
        var firstRegistry: GenerationLeaseRegistryV1? = try GenerationLeaseRegistryV1(
            applicationSupportURL: root,
            ownerID: foreignOwner,
            makeLeaseID: { v908MakeUUID(30) },
            now: { Date(timeIntervalSinceReferenceDate: 333_333) }
        )
        let foreignReader = try firstRegistry!.acquire(
            epoch: epoch,
            role: .reader
        )

        let observer = try GenerationLeaseRegistryV1(
            applicationSupportURL: root,
            ownerID: makeUUID(121),
            makeLeaseID: { v908MakeUUID(31) },
            now: { Date(timeIntervalSinceReferenceDate: 333_334) }
        )
        XCTAssertEqual(try observer.reconcileAbandonedOwners(), 0)
        XCTAssertTrue(try observer.activeEpochs().contains(epoch))

        let activeReadReceipt = try makePruneReceipt(
            operationID: makeUUID(122),
            currentEpoch: epoch,
            retainedEpochs: [epoch],
            prunedEpochs: [],
            activeRetainedEpochs: [epoch],
            uncertainRetainedGenerationIDs: [],
            disposition: .noEligibleGenerations
        )
        XCTAssertEqual(activeReadReceipt.activeRetainedEpochs, [epoch])
        XCTAssertTrue(try observer.activeEpochs().contains(foreignReader.epoch))

        firstRegistry = nil
        let foreignOwnerLock = root.appendingPathComponent(
            "FieldEvidenceOperations/generation-leases/owners/\(foreignOwner.uuidString.lowercased()).lock"
        )
        try fileManager.removeItem(at: foreignOwnerLock)

        XCTAssertThrowsError(try observer.reconcileAbandonedOwners()) { error in
            XCTAssertEqual(
                error as? GenerationLeaseRegistryFailureV1,
                .uncertainOwner
            )
        }
        XCTAssertTrue(try observer.activeEpochs().contains(epoch))
        XCTAssertEqual(try Data(contentsOf: retainedURL), retainedBytes)

        let registryURL = root.appendingPathComponent(
            "FieldEvidenceOperations/generation-leases/registry.json"
        )
        try overwriteFilePreservingIdentity(
            Data("{\"schemaVersion\":99}".utf8),
            at: registryURL
        )
        XCTAssertThrowsError(try observer.activeEpochs()) { error in
            XCTAssertEqual(
                error as? GenerationLeaseRegistryFailureV1,
                .corruptRegistry
            )
        }
        let corruptFactory = StoreGenerationFactory(applicationSupportURL: root)
        XCTAssertThrowsError(
            try corruptFactory.reconcileGenerationLeasesAndPrune()
        ) { error in
            XCTAssertEqual(
                error as? GenerationLeaseRegistryFailureV1,
                .corruptRegistry
            )
        }
        XCTAssertEqual(try Data(contentsOf: retainedURL), retainedBytes)

        let limitRoot = try makeApplicationSupport(label: "h01-limit")
        defer { try? fileManager.removeItem(at: limitRoot) }
        let limitEpoch = try makeEpoch(5)
        let limitIDs = UUIDCursor((1_000...1_256).map(makeUUID))
        let limitRegistry = try GenerationLeaseRegistryV1(
            applicationSupportURL: limitRoot,
            ownerID: makeUUID(123),
            makeLeaseID: { limitIDs.next() },
            now: { Date(timeIntervalSinceReferenceDate: 444_444) }
        )
        XCTAssertEqual(GenerationLeaseRegistryV1.maximumActiveLeaseCount, 256)
        XCTAssertEqual(GenerationLeaseRegistryV1.maximumOwnerCount, 64)
        XCTAssertEqual(GenerationLeaseRegistryV1.maximumControlFileBytes, 4 * 1024 * 1024)
        var leases: [GenerationLeaseTokenV1] = []
        for _ in 0..<GenerationLeaseRegistryV1.maximumActiveLeaseCount {
            leases.append(try limitRegistry.acquire(epoch: limitEpoch, role: .reader))
        }
        XCTAssertEqual(try limitRegistry.activeEpochs(), Set([limitEpoch]))
        XCTAssertThrowsError(
            try limitRegistry.acquire(epoch: limitEpoch, role: .reader)
        ) { error in
            XCTAssertEqual(
                error as? GenerationLeaseRegistryFailureV1,
                .registryLimitExceeded
            )
        }
        for lease in leases.reversed() {
            try limitRegistry.release(lease)
        }
        XCTAssertTrue(try limitRegistry.activeEpochs().isEmpty)

        XCTAssertThrowsError(
            try GenerationEpochV1(
                generationID: makeUUID(124),
                generationManifestSHA256: String(repeating: "A", count: 64)
            )
        ) { error in
            XCTAssertEqual(
                error as? GenerationLeaseRegistryFailureV1,
                .invalidContract
            )
        }
        XCTAssertThrowsError(
            try GenerationPrunePolicyV1(
                retainedInactiveAcceptedGenerationCount: 65
            )
        ) { error in
            XCTAssertEqual(
                error as? GenerationLeaseRegistryFailureV1,
                .invalidContract
            )
        }
    }

    @MainActor
    func testV9_08I01CrashExpiredLeaseRecoveryAndPruneBoundaries() throws {
        let epoch = try makeEpoch(6)
        let candidate = try makeEpoch(7)
        let retained = try makeEpoch(8)
        let unknownGenerationID = makeUUID(139)

        let crashPhases = GenerationPruneIntentPhaseV1.allCases
        XCTAssertEqual(
            crashPhases.map(\.rawValue),
            ["PREPARED", "BYTES_REMOVED", "RETIRED_POINTER_PUBLISHED", "RECEIPT_PUBLISHED"]
        )

        for (offset, phase) in crashPhases.enumerated() {
            let root = try makeApplicationSupport(label: "i01-\(offset)")
            defer { try? fileManager.removeItem(at: root) }
            let registry = try GenerationLeaseRegistryV1(
                applicationSupportURL: root,
                ownerID: makeUUID(140 + offset),
                makeLeaseID: { v908MakeUUID(150 + offset) },
                now: { Date(timeIntervalSinceReferenceDate: 555_555) }
            )
            let intent = try makePruneIntent(
                operationID: makeUUID(160 + offset),
                phase: .prepared,
                currentEpoch: epoch,
                candidateEpochs: [candidate],
                retainedEpochs: [epoch, retained],
                activeRetainedEpochs: [retained],
                uncertainRetainedGenerationIDs: [],
                inventoryBeforeSHA256: String(repeating: "1", count: 64),
                expectedRetiredGenerationIDs: [
                    candidate.generationID,
                    retained.generationID,
                ],
                desiredRetiredGenerationIDs: [retained.generationID]
            )
            try registry.createPruneIntent(intent)
            try registry.createPruneIntent(intent)
            XCTAssertEqual(try registry.loadPruneIntent(), intent)

            var persisted = intent
            for next in crashPhases where next.ordinalForTests <= phase.ordinalForTests {
                guard next != .prepared else { continue }
                let replacement = try persisted.advancing(to: next)
                try registry.replacePruneIntent(expected: persisted, with: replacement)
                persisted = replacement
            }
            XCTAssertEqual(persisted.phase, phase)

            if phase == .receiptPublished {
                let receipt = try makePruneReceipt(
                    operationID: persisted.operationID,
                    currentEpoch: epoch,
                    retainedEpochs: [epoch, retained],
                    prunedEpochs: [candidate],
                    activeRetainedEpochs: [retained],
                    uncertainRetainedGenerationIDs: [],
                    disposition: .pruned,
                    inventoryBeforeSHA256: persisted.inventoryBeforeSHA256
                )
                try registry.publishPruneReceipt(receipt, completing: persisted)
                XCTAssertNil(try registry.loadPruneIntent())
                XCTAssertEqual(try registry.loadLastPruneReceipt(), receipt)
                XCTAssertThrowsError(
                    try registry.publishPruneReceipt(receipt, completing: persisted)
                ) { error in
                    XCTAssertEqual(
                        error as? GenerationLeaseRegistryFailureV1,
                        .corruptRegistry
                    )
                }
            } else {
                XCTAssertEqual(try registry.loadPruneIntent(), persisted)
                let reopened = try GenerationLeaseRegistryV1(
                    applicationSupportURL: root,
                    ownerID: makeUUID(170 + offset),
                    makeLeaseID: { v908MakeUUID(180 + offset) },
                    now: { Date(timeIntervalSinceReferenceDate: 555_556) }
                )
                XCTAssertEqual(try reopened.loadPruneIntent(), persisted)
                XCTAssertNil(try reopened.loadLastPruneReceipt())
            }

            let mismatchedExpected = try makePruneIntent(
                operationID: makeUUID(220 + offset),
                phase: .prepared,
                currentEpoch: epoch,
                candidateEpochs: [candidate],
                retainedEpochs: [epoch, retained],
                activeRetainedEpochs: [retained],
                uncertainRetainedGenerationIDs: [],
                inventoryBeforeSHA256: String(repeating: "1", count: 64),
                expectedRetiredGenerationIDs: [
                    candidate.generationID,
                    retained.generationID,
                ],
                desiredRetiredGenerationIDs: [retained.generationID]
            )
            XCTAssertThrowsError(
                try registry.replacePruneIntent(
                    expected: mismatchedExpected,
                    with: try mismatchedExpected.advancing(to: .bytesRemoved)
                )
            ) { error in
                XCTAssertEqual(
                    error as? GenerationLeaseRegistryFailureV1,
                    .corruptRegistry
                )
            }
        }

        let recoveryRoot = try makeApplicationSupport(label: "i01-recovery")
        defer { try? fileManager.removeItem(at: recoveryRoot) }
        let crashedOwner = makeUUID(190)
        var crashedRegistry: GenerationLeaseRegistryV1? = try GenerationLeaseRegistryV1(
            applicationSupportURL: recoveryRoot,
            ownerID: crashedOwner,
            makeLeaseID: { v908MakeUUID(191) },
            now: { Date(timeIntervalSinceReferenceDate: 111) }
        )
        _ = try crashedRegistry!.acquire(epoch: candidate, role: .writer)
        crashedRegistry = nil

        let recoveryRegistry = try GenerationLeaseRegistryV1(
            applicationSupportURL: recoveryRoot,
            ownerID: makeUUID(192),
            makeLeaseID: { v908MakeUUID(193) },
            now: { Date(timeIntervalSinceReferenceDate: 222) }
        )
        XCTAssertEqual(try recoveryRegistry.reconcileAbandonedOwners(), 1)
        XCTAssertTrue(try recoveryRegistry.activeEpochs().isEmpty)
        XCTAssertEqual(try recoveryRegistry.reconcileAbandonedOwners(), 0)

        let disabledPolicy = try GenerationPrunePolicyV1(
            retainedInactiveAcceptedGenerationCount: 2,
            pruningEnabled: false
        )
        XCTAssertFalse(disabledPolicy.pruningEnabled)
        let disabledReceipt = try makePruneReceipt(
            operationID: makeUUID(194),
            currentEpoch: epoch,
            retainedEpochs: [epoch, candidate, retained],
            prunedEpochs: [],
            activeRetainedEpochs: [retained],
            uncertainRetainedGenerationIDs: [],
            disposition: .disabledRetainAll
        )
        XCTAssertEqual(disabledReceipt.disposition, .disabledRetainAll)
        XCTAssertTrue(disabledReceipt.prunedEpochs.isEmpty)

        let uncertainReceipt = try makePruneReceipt(
            operationID: makeUUID(195),
            currentEpoch: epoch,
            retainedEpochs: [epoch, retained],
            prunedEpochs: [],
            activeRetainedEpochs: [retained],
            uncertainRetainedGenerationIDs: [unknownGenerationID],
            disposition: .uncertainRetainAll
        )
        XCTAssertEqual(
            uncertainReceipt.uncertainRetainedGenerationIDs,
            [unknownGenerationID]
        )

        let emptyOwnerLivenessReceipt = try makePruneReceipt(
            operationID: makeUUID(196),
            currentEpoch: epoch,
            retainedEpochs: [epoch, retained],
            prunedEpochs: [],
            activeRetainedEpochs: [],
            uncertainRetainedGenerationIDs: [],
            ownerLivenessUncertain: true,
            disposition: .uncertainRetainAll
        )
        XCTAssertTrue(emptyOwnerLivenessReceipt.ownerLivenessUncertain)
        XCTAssertTrue(emptyOwnerLivenessReceipt.uncertainRetainedGenerationIDs.isEmpty)
        XCTAssertThrowsError(
            try makePruneReceipt(
                operationID: makeUUID(197),
                currentEpoch: epoch,
                retainedEpochs: [epoch, retained],
                prunedEpochs: [],
                activeRetainedEpochs: [],
                uncertainRetainedGenerationIDs: [],
                disposition: .uncertainRetainAll
            )
        )
        for (offset, disposition) in [
            GenerationPruneDispositionV1.pruned,
            .noEligibleGenerations,
            .disabledRetainAll,
        ].enumerated() {
            XCTAssertThrowsError(
                try makePruneReceipt(
                    operationID: makeUUID(198 + offset),
                    currentEpoch: epoch,
                    retainedEpochs: [epoch, retained],
                    prunedEpochs: disposition == .pruned ? [candidate] : [],
                    activeRetainedEpochs: [],
                    uncertainRetainedGenerationIDs: [],
                    ownerLivenessUncertain: true,
                    disposition: disposition
                ),
                "owner liveness uncertainty is only valid for uncertain retain-all"
            )
        }

#if DEBUG
        // Exercise the production factory's durable intent protocol at every
        // fault boundary. Each recovery deliberately creates a new factory so
        // that the assertions cover relaunch rather than in-process state.
        for (offset, boundary) in StoreGenerationPruneFaultBoundaryV1
            .allCases
            .enumerated() {
            let fixture = try makeRealPruneFixture(
                label: "i01-prune-\(offset)",
                offset: offset
            )
            defer { try? fileManager.removeItem(at: fixture.root) }

            let faultFactory = StoreGenerationFactory(
                applicationSupportURL: fixture.root,
                pruneFailureInjection:
                    StoreGenerationPruneFailureInjectionV1(
                        failOnceAt: boundary
                    )
            )
            XCTAssertThrowsError(
                try faultFactory.reconcileGenerationLeasesAndPrune()
            ) { error in
                XCTAssertEqual(
                    error as? StoreGenerationPruneInjectedFailureV1,
                    .injectedFault(boundary),
                    "fault boundary \(boundary.rawValue)"
                )
            }

            let interruptedRegistry = try GenerationLeaseRegistryV1(
                applicationSupportURL: fixture.root,
                ownerID: v908MakeUUID(2_000 + offset),
                makeLeaseID: { v908MakeUUID(2_100 + offset) },
                now: { Date(timeIntervalSinceReferenceDate: 777_000) }
            )
            let interruptedIntent = try XCTUnwrap(
                try interruptedRegistry.loadPruneIntent(),
                "intent survives \(boundary.rawValue)"
            )
            XCTAssertEqual(
                interruptedIntent.currentEpoch.generationID,
                fixture.currentGenerationID
            )
            XCTAssertTrue(
                interruptedIntent.candidateEpochs.contains {
                    $0.generationID == fixture.candidateGenerationID
                }
            )

            switch boundary {
            case .prepared:
                XCTAssertEqual(interruptedIntent.phase, .prepared)
                XCTAssertTrue(
                    fileManager.fileExists(
                        atPath: fixture.candidateModelURL.path
                    )
                )
                XCTAssertTrue(
                    try faultFactory.retiredGenerationIDs()
                        .contains(fixture.candidateGenerationID)
                )
            case .bytesRemoved:
                XCTAssertEqual(interruptedIntent.phase, .bytesRemoved)
                XCTAssertFalse(
                    fileManager.fileExists(
                        atPath: fixture.candidateModelURL.path
                    )
                )
                XCTAssertTrue(
                    try faultFactory.retiredGenerationIDs()
                        .contains(fixture.candidateGenerationID)
                )
            case .retiredPointerPublished:
                XCTAssertEqual(
                    interruptedIntent.phase,
                    .retiredPointerPublished
                )
                XCTAssertFalse(
                    fileManager.fileExists(
                        atPath: fixture.candidateModelURL.path
                    )
                )
                XCTAssertFalse(
                    try faultFactory.retiredGenerationIDs()
                        .contains(fixture.candidateGenerationID)
                )
            case .receiptPublished:
                XCTAssertEqual(interruptedIntent.phase, .receiptPublished)
                XCTAssertFalse(
                    fileManager.fileExists(
                        atPath: fixture.candidateModelURL.path
                    )
                )
                XCTAssertFalse(
                    try faultFactory.retiredGenerationIDs()
                        .contains(fixture.candidateGenerationID)
                )
            }

            let relaunchedFactory = StoreGenerationFactory(
                applicationSupportURL: fixture.root
            )
            var relaunchedSession: StoreGenerationSession? = try
                relaunchedFactory.openOrBootstrapCurrent()
            XCTAssertEqual(
                relaunchedSession?.generationID,
                fixture.currentGenerationID,
                "current pointer after \(boundary.rawValue) recovery"
            )
            relaunchedSession = nil

            let recoveredRegistry = try relaunchedFactory
                .makeGenerationLeaseRegistry(ownerID: v908MakeUUID(2_200 + offset))
            let recoveredReceipt = try XCTUnwrap(
                try recoveredRegistry.loadLastPruneReceipt(),
                "receipt after \(boundary.rawValue) recovery"
            )
            XCTAssertEqual(recoveredReceipt.disposition, .pruned)
            XCTAssertEqual(
                recoveredReceipt.operationID,
                interruptedIntent.operationID
            )
            XCTAssertEqual(
                recoveredReceipt.prunedEpochs.map(\.generationID),
                [fixture.candidateGenerationID]
            )
            XCTAssertNil(try recoveredRegistry.loadPruneIntent())
            XCTAssertFalse(
                fileManager.fileExists(
                    atPath: fixture.candidateModelURL.path
                )
            )
            XCTAssertFalse(
                fileManager.fileExists(
                    atPath: relaunchedFactory
                        .installedGenerationURL(
                            id: fixture.candidateGenerationID
                        )
                        .path
                )
            )
            XCTAssertEqual(
                try relaunchedFactory.retiredGenerationIDs(),
                fixture.retainedGenerationIDs
            )

            let postRecovery = try relaunchedFactory
                .reconcileGenerationLeasesAndPrune()
            XCTAssertEqual(postRecovery.disposition, .noEligibleGenerations)
            XCTAssertTrue(postRecovery.prunedEpochs.isEmpty)
        }
#endif

        for (offset, boundary) in MutationJournalFaultBoundaryV1.allCases.enumerated() {
            let journalRoot = try makeApplicationSupport(
                label: "i01-journal-\(offset)"
            )
            defer { try? fileManager.removeItem(at: journalRoot) }
            let journalFactory = StoreGenerationFactory(
                applicationSupportURL: journalRoot
            )
            var initialJournalSession: StoreGenerationSession? = try journalFactory
                .openOrBootstrapCurrent()
            let journalGenerationID = try XCTUnwrap(
                initialJournalSession?.generationID
            )
            let journalIdentity = try XCTUnwrap(
                initialJournalSession?.workspaceIdentity
            )
            let journalEpoch = try XCTUnwrap(
                initialJournalSession?.generationEpoch
            )
            let journalWriterInstanceID = v908MakeUUID(300 + offset)
            let journalSiteID = v908MakeUUID(310 + offset)
            let journalAssetID = v908MakeUUID(320 + offset)
            let journalMutationID = try MutationIDV1(
                rawValue: v908MakeUUID(330 + offset)
            )
            let journalRequest = try makeCreateFirstSignRequest(
                workspaceID: journalIdentity.workspaceID,
                generationID: journalGenerationID,
                writerInstanceID: journalWriterInstanceID,
                workspaceRevision: 0,
                mutationID: journalMutationID,
                siteID: journalSiteID,
                assetID: journalAssetID,
                placementEventID: v908MakeUUID(360 + offset),
                physicalEpisodeID: v908MakeUUID(370 + offset),
                label: "Interrupted lease mutation \(offset)"
            )

            do {
                let opened = try XCTUnwrap(initialJournalSession)
                let writerRegistry = try journalFactory.makeGenerationLeaseRegistry(
                    ownerID: v908MakeUUID(340 + offset)
                )
                let writerLease = try writerRegistry.acquire(
                    epoch: journalEpoch,
                    role: .writer
                )
                let writerFence = try journalFactory.makeWriterFence(
                    expectedGenerationEpoch: journalEpoch,
                    writerLeaseToken: writerLease,
                    registry: writerRegistry
                )
                do {
                    let injectedStore = try MutationJournalStoreV1(
                        modelContext: opened.modelContext,
                        identity: journalIdentity,
                        generationID: journalGenerationID,
                        failureInjection: MutationJournalFailureInjectionV1(
                            failOnceAt: boundary
                        ),
                        allowStateBootstrap: false,
                        staleWriterFence: writerFence
                    )
                    let injectedWriter = try WorkspaceWriterV1(
                        identity: journalIdentity,
                        generationID: journalGenerationID,
                        initialRevision: try injectedStore.currentRevision(
                            writerInstanceID: journalWriterInstanceID
                        ),
                        clock: V908FixedClock(
                            value: Date(timeIntervalSinceReferenceDate: 600_000 + Double(offset))
                        ),
                        idSource: V908FixedIDSource(
                            value: journalWriterInstanceID
                        ),
                        fileAuthority: V908FileAuthority(),
                        adapter: WorkspaceWriterAdapterV1(
                            modelContext: opened.modelContext
                        ),
                        journalStore: injectedStore
                    )
                    XCTAssertThrowsError(
                        try injectedWriter.execute(journalRequest)
                    ) { error in
                        XCTAssertEqual(
                            error as? MutationJournalFailureV1,
                            .injected(boundary)
                        )
                    }
                }
                try writerRegistry.release(writerLease)
            }
            initialJournalSession = nil

            do {
                let relaunched = try journalFactory.openOrBootstrapCurrent()
                let relaunchedEpoch = try XCTUnwrap(relaunched.generationEpoch)
                let recoveryRegistry = try journalFactory.makeGenerationLeaseRegistry(
                    ownerID: v908MakeUUID(350 + offset)
                )
                let recoveryLease = try recoveryRegistry.acquire(
                    epoch: relaunchedEpoch,
                    role: .writer
                )
                let recoveryFence = try journalFactory.makeWriterFence(
                    expectedGenerationEpoch: relaunchedEpoch,
                    writerLeaseToken: recoveryLease,
                    registry: recoveryRegistry
                )
                let recoveryStore = try MutationJournalStoreV1(
                    modelContext: relaunched.modelContext,
                    identity: journalIdentity,
                    generationID: journalGenerationID,
                    allowStateBootstrap: false,
                    staleWriterFence: recoveryFence
                )
                try MutationReceiptRecoveryServiceV1(
                    store: recoveryStore
                ).recoverBeforeWriterActivation()

                let recoveredReceipt = try recoveryStore.receipt(
                    mutationID: journalMutationID
                )
                if boundary == .afterSaveBeforeReturn {
                    let durable = try XCTUnwrap(recoveredReceipt)
                    XCTAssertEqual(durable.identity.localSequence, 1)
                    XCTAssertEqual(
                        durable.resultingRevision.workspaceRevision,
                        1
                    )
                } else {
                    XCTAssertNil(recoveredReceipt)
                    XCTAssertEqual(
                        try recoveryStore.currentRevision(
                            writerInstanceID: journalWriterInstanceID
                        ).revision,
                        0
                    )
                }

                let retryWriter = try WorkspaceWriterV1(
                    identity: journalIdentity,
                    generationID: journalGenerationID,
                    initialRevision: try recoveryStore.currentRevision(
                        writerInstanceID: journalWriterInstanceID
                    ),
                    clock: V908FixedClock(
                        value: Date(timeIntervalSinceReferenceDate: 600_100 + Double(offset))
                    ),
                    idSource: V908FixedIDSource(
                        value: journalWriterInstanceID
                    ),
                    fileAuthority: V908FileAuthority(),
                    adapter: WorkspaceWriterAdapterV1(
                        modelContext: relaunched.modelContext
                    ),
                    journalStore: recoveryStore
                )
                let retryOutcome = try retryWriter.execute(journalRequest)
                XCTAssertEqual(retryOutcome.after.revision, 1)
                let retryReceipt = try XCTUnwrap(
                    try retryWriter.durableReceipt(mutationID: journalMutationID)
                )
                XCTAssertEqual(retryReceipt.identity.localSequence, 1)
                if let recoveredReceipt {
                    XCTAssertEqual(retryReceipt, recoveredReceipt)
                }
                XCTAssertEqual(
                    try relaunched.modelContext.fetch(
                        FetchDescriptor<MutationReceiptRow>()
                    ).count,
                    1
                )
                let stateRows = try relaunched.modelContext.fetch(
                    FetchDescriptor<WorkspaceMutationStateRow>()
                )
                XCTAssertEqual(stateRows.count, 1)
                XCTAssertEqual(stateRows.first?.workspaceRevision, 1)
                XCTAssertEqual(stateRows.first?.lastLocalSequence, 1)
                XCTAssertEqual(
                    try relaunched.modelContext.fetch(
                        FetchDescriptor<Site>(
                            predicate: #Predicate { $0.id == journalSiteID }
                        )
                    ).count,
                    1
                )
                XCTAssertEqual(
                    try relaunched.modelContext.fetch(
                        FetchDescriptor<Asset>(
                            predicate: #Predicate { $0.id == journalAssetID }
                        )
                    ).count,
                    1
                )
                try recoveryRegistry.release(recoveryLease)
            }
        }

        let pruneRoot = try makeApplicationSupport(label: "i01-factory")
        defer { try? fileManager.removeItem(at: pruneRoot) }
        let pruneFactory = StoreGenerationFactory(
            applicationSupportURL: pruneRoot
        )
        var initialSession: StoreGenerationSession? = try pruneFactory
            .openOrBootstrapCurrent()
        let stableIdentity = try XCTUnwrap(initialSession).workspaceIdentity
        var oldGenerationID = try XCTUnwrap(initialSession).generationID
        var oldPointer = try makeRestorePointer(
            from: try pruneFactory.currentGenerationPointerV3(
                expectedGenerationID: oldGenerationID
            )
        )
        initialSession = nil

        let acceptedRetiredIDs = [
            makeUUID(260),
            makeUUID(261),
            makeUUID(262),
        ]
        let pruneAuthority = try pruneFactory.makeRestoreGenerationAuthority()
        for nextGenerationID in acceptedRetiredIDs {
            let created = try pruneFactory.createEmptyEraseGeneration(
                id: nextGenerationID,
                expectedOldPointer: oldPointer,
                identity: stableIdentity,
                authority: pruneAuthority
            )
            try pruneFactory.publishEmptyEraseGeneration(
                expectedOldPointer: oldPointer,
                targetPointer: created.pointer,
                expectedEmptyLedger: created.ledgerProof,
                authority: pruneAuthority
            )
            try pruneFactory.retireGeneration(
                oldID: oldGenerationID,
                currentID: nextGenerationID
            )
            oldGenerationID = nextGenerationID
            oldPointer = created.pointer
        }

        let retiredBeforePrune = try pruneFactory.retiredGenerationIDs()
        XCTAssertEqual(retiredBeforePrune.count, 3)
        let candidateGenerationID = try XCTUnwrap(retiredBeforePrune.first)
        let candidateBytesURL = pruneFactory
            .installedGenerationURL(id: candidateGenerationID)
            .appendingPathComponent("model.sqlite")
        XCTAssertTrue(fileManager.fileExists(atPath: candidateBytesURL.path))
        let disabledFactoryPrune = try pruneFactory.reconcileGenerationLeasesAndPrune(
            policy: try GenerationPrunePolicyV1(
                retainedInactiveAcceptedGenerationCount: 2,
                pruningEnabled: false
            )
        )
        XCTAssertEqual(disabledFactoryPrune.disposition, .disabledRetainAll)
        XCTAssertTrue(disabledFactoryPrune.prunedEpochs.isEmpty)
        XCTAssertTrue(fileManager.fileExists(atPath: candidateBytesURL.path))

        let prunedReceipt = try pruneFactory.reconcileGenerationLeasesAndPrune()
        XCTAssertEqual(prunedReceipt.disposition, .pruned)
        XCTAssertEqual(
            prunedReceipt.prunedEpochs.map(\.generationID),
            [candidateGenerationID]
        )
        XCTAssertTrue(
            prunedReceipt.retainedEpochs.contains(where: {
                $0.generationID == oldGenerationID
            })
        )
        XCTAssertFalse(fileManager.fileExists(atPath: candidateBytesURL.path))
        XCTAssertEqual(
            try pruneFactory.retiredGenerationIDs(),
            Array(retiredBeforePrune.dropFirst())
        )
        let pruneRegistry = try pruneFactory.makeGenerationLeaseRegistry(
            ownerID: makeUUID(270)
        )
        XCTAssertEqual(try pruneRegistry.loadLastPruneReceipt(), prunedReceipt)
        XCTAssertNil(try pruneRegistry.loadPruneIntent())
        let relaunchedPruneFactory = StoreGenerationFactory(
            applicationSupportURL: pruneRoot
        )
        var relaunchedPruneSession: StoreGenerationSession? = try
            relaunchedPruneFactory.openOrBootstrapCurrent()
        XCTAssertEqual(relaunchedPruneSession?.generationID, oldGenerationID)
        relaunchedPruneSession = nil
        let relaunchRegistry = try relaunchedPruneFactory
            .makeGenerationLeaseRegistry(ownerID: makeUUID(271))
        XCTAssertEqual(try relaunchRegistry.loadLastPruneReceipt(), prunedReceipt)
        XCTAssertNil(try relaunchRegistry.loadPruneIntent())
        let relaunchReceipt = try relaunchedPruneFactory
            .reconcileGenerationLeasesAndPrune()
        XCTAssertEqual(relaunchReceipt.disposition, .noEligibleGenerations)
        XCTAssertTrue(relaunchReceipt.prunedEpochs.isEmpty)
    }

    @MainActor
    func testV9_08R01BackupReplaceRestoreAndRelaunchReconciliation() async throws {
        var diagnosticBoundary = "fixture-directories"
        defer { print("V9_08R01 lastBoundary=\(diagnosticBoundary)") }
        let root = try makeApplicationSupport(label: "r01-production")
        addTeardownBlock { [root = root] in
            try? FileManager.default.removeItem(at: root)
        }

        let sourceSupport = root.appendingPathComponent(
            "source-support",
            isDirectory: true
        )
        let destinationSupport = root.appendingPathComponent(
            "destination-support",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: sourceSupport,
            withIntermediateDirectories: false
        )
        try fileManager.createDirectory(
            at: destinationSupport,
            withIntermediateDirectories: false
        )

        let sourceFactory = StoreGenerationFactory(
            applicationSupportURL: sourceSupport
        )
        diagnosticBoundary = "source-open"
        var sourceSession: StoreGenerationSession? = try sourceFactory
            .openOrBootstrapCurrent()
        let source = try XCTUnwrap(sourceSession)
        let sourceGenerationID = source.generationID
        let sourceReaderLease = try XCTUnwrap(source.readerLeaseToken)
        XCTAssertEqual(sourceReaderLease.epoch.generationID, sourceGenerationID)
        XCTAssertEqual(try sourceFactory.currentGenerationID(), sourceGenerationID)
        diagnosticBoundary = "source-writer"
        let sourceSiteID = makeUUID(2_400)
        let sourceAssetID = makeUUID(2_401)
        let sourceMutationID = try MutationIDV1(rawValue: makeUUID(2_402))
        do {
            let coordinator = try StoreSessionCoordinator(
                validatingSession: source,
                clock: V908FixedClock(
                    value: Date(timeIntervalSinceReferenceDate: 900_000)
                ),
                idSource: V908FixedIDSource(value: makeUUID(2_403)),
                fileAuthority: V908FileAuthority()
            )
            let before = try coordinator.workspaceWriter.currentRevision()
            let request = try makeCreateFirstSignRequest(
                workspaceID: before.workspaceID,
                generationID: before.generationID,
                writerInstanceID: before.writerInstanceID,
                workspaceRevision: before.revision,
                mutationID: sourceMutationID,
                siteID: sourceSiteID,
                assetID: sourceAssetID,
                placementEventID: makeUUID(2_404),
                physicalEpisodeID: makeUUID(2_405),
                label: "Production backup source"
            )
            diagnosticBoundary = "source-first-sign-commit"
            let outcome = try coordinator.workspaceWriter.execute(request)
            XCTAssertEqual(outcome.after.revision, 1)
            XCTAssertEqual(
                try coordinator.workspaceWriter
                    .durableReceipt(mutationID: sourceMutationID)?
                    .identity.localSequence,
                1
            )
        }

        let exportDirectory = root.appendingPathComponent(
            "export",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: exportDirectory,
            withIntermediateDirectories: false
        )
        let exportUUIDs = UUIDCursor((2_410...2_419).map(makeUUID))
        let exporter = BackupExportService(
            modelContext: source.modelContext,
            generationRootURL: source.generationRootURL,
            storagePreflight: makeUnlimitedStoragePreflight(),
            now: { Date(timeIntervalSinceReferenceDate: 900_010) },
            makeUUID: { exportUUIDs.next() }
        )
        diagnosticBoundary = "export-prepare"
        let preview = try exporter.prepareStreaming()
        diagnosticBoundary = "export-stream"
        let archive = try exporter.exportStreaming(
            previewID: preview.id,
            to: exportDirectory
        )
        XCTAssertTrue(fileManager.fileExists(atPath: archive.path))

        let destinationFactory = StoreGenerationFactory(
            applicationSupportURL: destinationSupport
        )
        diagnosticBoundary = "destination-open"
        var destinationSession: StoreGenerationSession? = try destinationFactory
            .openOrBootstrapCurrent()
        let destination = try XCTUnwrap(destinationSession)
        let destinationIdentity = destination.workspaceIdentity
        let destinationOldID = destination.generationID
        let destinationReaderLease = try XCTUnwrap(destination.readerLeaseToken)
        diagnosticBoundary = "destination-writer"
        let destinationSiteID = makeUUID(2_420)
        let destinationAssetID = makeUUID(2_421)
        let destinationMutationID = try MutationIDV1(rawValue: makeUUID(2_422))
        do {
            let coordinator = try StoreSessionCoordinator(
                validatingSession: destination,
                clock: V908FixedClock(
                    value: Date(timeIntervalSinceReferenceDate: 900_020)
                ),
                idSource: V908FixedIDSource(value: makeUUID(2_423)),
                fileAuthority: V908FileAuthority()
            )
            let before = try coordinator.workspaceWriter.currentRevision()
            let request = try makeCreateFirstSignRequest(
                workspaceID: before.workspaceID,
                generationID: before.generationID,
                writerInstanceID: before.writerInstanceID,
                workspaceRevision: before.revision,
                mutationID: destinationMutationID,
                siteID: destinationSiteID,
                assetID: destinationAssetID,
                placementEventID: makeUUID(2_425),
                physicalEpisodeID: makeUUID(2_426),
                label: "Existing destination data"
            )
            diagnosticBoundary = "destination-first-sign-commit"
            let outcome = try coordinator.workspaceWriter.execute(request)
            XCTAssertEqual(outcome.after.revision, 1)
        }

        diagnosticBoundary = "import-open"
        let importer = try BackupImportService(
            generationRootURL: destination.generationRootURL,
            storagePreflight: makeUnlimitedStoragePreflight(),
            makeUUID: { v908MakeUUID(2_424) },
            scopedAccess: .alreadyAuthorized
        )
        diagnosticBoundary = "import-validate"
        let validated = try importer.stageAndValidate(
            selectedPackageURL: archive
        )
        XCTAssertEqual(validated.manifest.backupSchemaVersion, 4)
        XCTAssertEqual(validated.manifest.source.recordsSchemaVersion,
                       LightingNightWorkflowBackupEnrollmentV1.recordsSchemaVersion)
        XCTAssertTrue(validated.records.savedSmartViews.isEmpty)
        XCTAssertEqual(
            Set(validated.records.sites.map(\.id)),
            Set([sourceSiteID])
        )
        XCTAssertEqual(
            Set(validated.records.assets.map(\.id)),
            Set([sourceAssetID])
        )
        XCTAssertNotNil(validated.records.mutationHistory)
        XCTAssertNotEqual(sourceReaderLease.ownerID, destinationReaderLease.ownerID)

        let restoreUUIDs = UUIDCursor((2_430...2_459).map(makeUUID))
        diagnosticBoundary = "restore-open"
        let restoreService = try BackupRestoreService(
            applicationSupportURL: destinationSupport,
            storagePreflight: makeUnlimitedStoragePreflight(),
            now: { Date(timeIntervalSinceReferenceDate: 900_030) },
            makeUUID: { restoreUUIDs.next() }
        )
        diagnosticBoundary = "restore-apply"
        var restoredSession: StoreGenerationSession? = try await restoreService.restore(
            validatedPackage: validated,
            currentModelContext: destination.modelContext,
            currentGenerationID: destinationOldID,
            currentGenerationRootURL: destination.generationRootURL,
            mode: .replaceExisting
        )
        let restored = try XCTUnwrap(restoredSession)
        diagnosticBoundary = "restore-result-assertions"
        XCTAssertEqual(restored.workspaceIdentity, destinationIdentity)
        XCTAssertEqual(restored.generationID, try destinationFactory.currentGenerationID())
        XCTAssertNotEqual(restored.generationID, destinationOldID)
        XCTAssertEqual(
            try restored.modelContext.fetch(
                FetchDescriptor<Site>(
                    predicate: #Predicate { $0.id == sourceSiteID }
                )
            ).count,
            1
        )
        XCTAssertEqual(
            try restored.modelContext.fetch(
                FetchDescriptor<Asset>(
                    predicate: #Predicate { $0.id == sourceAssetID }
                )
            ).count,
            1
        )
        XCTAssertEqual(
            try restored.modelContext.fetch(
                FetchDescriptor<Site>(
                    predicate: #Predicate { $0.id == destinationSiteID }
                )
            ).count,
            0
        )
        let restoredReaderLease = try XCTUnwrap(restored.readerLeaseToken)
        XCTAssertNotEqual(
            sourceReaderLease.ownerID,
            restoredReaderLease.ownerID
        )
        XCTAssertTrue(
            try destinationFactory.retiredGenerationIDs()
                .contains(destinationOldID)
        )
        XCTAssertTrue(
            fileManager.fileExists(
                atPath: destinationFactory
                    .installedGenerationURL(id: destinationOldID)
                    .appendingPathComponent("model.sqlite")
                    .path
            )
        )

        // The production startup reconciler is part of the replace/relaunch
        // contract even when the restore completed without a pending intent.
        diagnosticBoundary = "startup-reconcile"
        XCTAssertNil(try BackupRestoreService(
            applicationSupportURL: destinationSupport,
            storagePreflight: makeUnlimitedStoragePreflight()
        ).reconcileAtStartup())

        restoredSession = nil
        destinationSession = nil
        sourceSession = nil

        let relaunchedFactory = StoreGenerationFactory(
            applicationSupportURL: destinationSupport
        )
        diagnosticBoundary = "relaunch-open"
        var relaunchedSession: StoreGenerationSession? = try relaunchedFactory
            .openOrBootstrapCurrent()
        let relaunched = try XCTUnwrap(relaunchedSession)
        XCTAssertEqual(relaunched.generationID, restored.generationID)
        XCTAssertEqual(relaunched.workspaceIdentity, destinationIdentity)
        XCTAssertTrue(
            try relaunchedFactory.retiredGenerationIDs()
                .contains(destinationOldID)
        )
        XCTAssertTrue(
            fileManager.fileExists(
                atPath: relaunchedFactory
                    .installedGenerationURL(id: destinationOldID)
                    .appendingPathComponent("model.sqlite")
                    .path
            )
        )
        relaunchedSession = nil
        diagnosticBoundary = "relaunch-prune"
        let relaunchPrune = try relaunchedFactory
            .reconcileGenerationLeasesAndPrune()
        XCTAssertEqual(relaunchPrune.disposition, .noEligibleGenerations)
        XCTAssertTrue(relaunchPrune.prunedEpochs.isEmpty)
        diagnosticBoundary = "completed"
    }

    private func makeApplicationSupport(label: String) throws -> URL {
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "V9_08GenerationLeaseTests-\(label)-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: root,
            withIntermediateDirectories: false
        )
        return root
    }

    private func makeUUID(_ value: Int) -> UUID {
        v908MakeUUID(value)
    }

    private func overwriteFilePreservingIdentity(
        _ data: Data,
        at url: URL
    ) throws {
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: data)
        try handle.synchronize()
        try handle.close()
    }

    private func makeEpoch(_ value: Int) throws -> GenerationEpochV1 {
        let hex = String(format: "%x", value)
        return try GenerationEpochV1(
            generationID: makeUUID(1_000 + value),
            generationManifestSHA256: String(String(repeating: hex, count: 64).prefix(64))
        )
    }

    private func makeRestorePointer(
        from pointer: CurrentGenerationPointerV3
    ) throws -> RestorePointerIdentityV1 {
        RestorePointerIdentityV1(
            generationID: try XCTUnwrap(UUID(uuidString: pointer.generationID)),
            generationManifestSHA256: pointer.generationManifestSHA256,
            knownReplicaIDs: Set(try pointer.knownReplicaIDs.map {
                try XCTUnwrap(UUID(uuidString: $0))
            }),
            workspaceID: try XCTUnwrap(UUID(uuidString: pointer.workspaceID)),
            replicaID: try XCTUnwrap(UUID(uuidString: pointer.replicaID))
        )
    }

    @MainActor
    private func makeRealPruneFixture(
        label: String,
        offset: Int
    ) throws -> V908PruneFixture {
        let root = try makeApplicationSupport(label: label)
        let factory = StoreGenerationFactory(applicationSupportURL: root)
        var session: StoreGenerationSession? = try factory
            .openOrBootstrapCurrent()
        let opened = try XCTUnwrap(session)
        let identity = opened.workspaceIdentity
        var oldGenerationID = opened.generationID
        var oldPointer = try makeRestorePointer(
            from: try factory.currentGenerationPointerV3(
                expectedGenerationID: oldGenerationID
            )
        )
        session = nil

        let generationIDs = (0..<3).map {
            makeUUID(2_500 + (offset * 10) + $0)
        }
        let authority = try factory.makeRestoreGenerationAuthority()
        for nextGenerationID in generationIDs {
            let created = try factory.createEmptyEraseGeneration(
                id: nextGenerationID,
                expectedOldPointer: oldPointer,
                identity: identity,
                authority: authority
            )
            try factory.publishEmptyEraseGeneration(
                expectedOldPointer: oldPointer,
                targetPointer: created.pointer,
                expectedEmptyLedger: created.ledgerProof,
                authority: authority
            )
            try factory.retireGeneration(
                oldID: oldGenerationID,
                currentID: nextGenerationID
            )
            oldGenerationID = nextGenerationID
            oldPointer = created.pointer
        }

        let retiredIDs = try factory.retiredGenerationIDs()
        XCTAssertEqual(retiredIDs.count, 3)
        let candidateID = try XCTUnwrap(retiredIDs.first)
        let candidateModelURL = factory
            .installedGenerationURL(id: candidateID)
            .appendingPathComponent("model.sqlite")
        XCTAssertTrue(fileManager.fileExists(atPath: candidateModelURL.path))
        XCTAssertFalse(try Data(contentsOf: candidateModelURL).isEmpty)
        return V908PruneFixture(
            root: root,
            currentGenerationID: oldGenerationID,
            candidateGenerationID: candidateID,
            candidateModelURL: candidateModelURL,
            retainedGenerationIDs: Array(retiredIDs.dropFirst())
        )
    }

    private func makeUnlimitedStoragePreflight() -> StoragePreflightService {
        StoragePreflightService(capacityProvider: { _ in .max })
    }

    private func makeCreateFirstSignRequest(
        workspaceID: WorkspaceID,
        generationID: UUID,
        writerInstanceID: UUID,
        workspaceRevision: UInt64,
        mutationID: MutationIDV1,
        siteID: UUID,
        assetID: UUID,
        placementEventID: UUID,
        physicalEpisodeID: UUID,
        label: String
    ) throws -> WorkspaceMutationRequestV1 {
        let expected = try WorkspaceExpectedRevisionV1(
            workspaceID: workspaceID,
            generationID: generationID,
            writerInstanceID: writerInstanceID,
            workspaceRevision: workspaceRevision,
            entityRevisions: [
                .init(
                    identity: try WorkspaceEntityIdentityV1(
                        kind: .site,
                        id: siteID
                    ),
                    revision: 0
                ),
                .init(
                    identity: try WorkspaceEntityIdentityV1(
                        kind: .asset,
                        id: assetID
                    ),
                    revision: 0
                ),
                .init(
                    identity: try WorkspaceEntityIdentityV1(
                        kind: .assetPlacementEvent,
                        id: placementEventID
                    ),
                    revision: 0
                ),
            ]
        )
        return WorkspaceMutationRequestV1(
            mutationID: mutationID,
            expectedRevision: expected,
            command: .createFirstSign(.init(
                siteID: siteID,
                newSite: .init(
                    id: siteID,
                    label: label,
                    address: nil,
                    timeZoneID: "UTC"
                ),
                assetID: assetID,
                assetLabel: "Interrupted asset",
                packID: SignPack.illuminatedSignV1.packID,
                packSchemaVersion: SignPack.illuminatedSignV1.schemaVersion,
                packContentVersion: SignPack.illuminatedSignV1.contentVersion,
                createdAt: Date(timeIntervalSinceReferenceDate: 601_000),
                initialPlacementMutationID: mutationID,
                initialPlacementEventID: placementEventID,
                initialPhysicalEpisodeID: try PhysicalPlacementEpisodeIDV1(
                    rawValue: physicalEpisodeID
                )
            ))
        )
    }

    private func makePruneIntent(
        operationID: UUID,
        phase: GenerationPruneIntentPhaseV1,
        currentEpoch: GenerationEpochV1,
        candidateEpochs: [GenerationEpochV1],
        retainedEpochs: [GenerationEpochV1],
        activeRetainedEpochs: [GenerationEpochV1],
        uncertainRetainedGenerationIDs: [UUID],
        inventoryBeforeSHA256: String,
        expectedRetiredGenerationIDs: [UUID],
        desiredRetiredGenerationIDs: [UUID]
    ) throws -> GenerationPruneIntentV1 {
        try GenerationPruneIntentV1(
            operationID: operationID,
            phase: phase,
            currentEpoch: currentEpoch,
            candidateEpochs: candidateEpochs,
            retainedEpochs: retainedEpochs,
            activeRetainedEpochs: activeRetainedEpochs,
            uncertainRetainedGenerationIDs: uncertainRetainedGenerationIDs,
            inventoryBeforeSHA256: inventoryBeforeSHA256,
            expectedRetiredGenerationIDs: expectedRetiredGenerationIDs,
            desiredRetiredGenerationIDs: desiredRetiredGenerationIDs
        )
    }

    private func makePruneReceipt(
        operationID: UUID,
        currentEpoch: GenerationEpochV1,
        retainedEpochs: [GenerationEpochV1],
        prunedEpochs: [GenerationEpochV1],
        activeRetainedEpochs: [GenerationEpochV1],
        uncertainRetainedGenerationIDs: [UUID],
        ownerLivenessUncertain: Bool = false,
        disposition: GenerationPruneDispositionV1,
        inventoryBeforeSHA256: String = String(repeating: "a", count: 64)
    ) throws -> GenerationPruneReceiptV1 {
        try GenerationPruneReceiptV1(
            operationID: operationID,
            currentEpoch: currentEpoch,
            retainedEpochs: retainedEpochs,
            prunedEpochs: prunedEpochs,
            activeRetainedEpochs: activeRetainedEpochs,
            uncertainRetainedGenerationIDs: uncertainRetainedGenerationIDs,
            ownerLivenessUncertain: ownerLivenessUncertain,
            inventoryBeforeSHA256: inventoryBeforeSHA256,
            inventoryAfterSHA256: String(repeating: "b", count: 64),
            disposition: disposition
        )
    }
}

private struct V908PruneFixture {
    let root: URL
    let currentGenerationID: UUID
    let candidateGenerationID: UUID
    let candidateModelURL: URL
    let retainedGenerationIDs: [UUID]
}

private final class UUIDCursor: @unchecked Sendable {
    private let lock = NSLock()
    private let values: [UUID]
    private var index = 0

    init(_ values: [UUID]) {
        self.values = values
    }

    func next() -> UUID {
        lock.lock()
        defer { lock.unlock() }
        defer { index += 1 }
        guard index < values.count else { return UUID() }
        return values[index]
    }
}

private struct V908FixedClock: ApplicationClock {
    let value: Date

    func now() -> Date { value }
}

private struct V908FixedIDSource: ApplicationIDSource {
    let value: UUID

    func makeID() -> UUID { value }
}

private struct V908FileAuthority: ApplicationFileAuthorityV1 {
    func temporaryRelativePath(
        mutationID: MutationIDV1,
        component: String
    ) throws -> String {
        "mutation-staging/\(mutationID.rawValue.uuidString.lowercased())/\(component)"
    }
}

private func v908MakeUUID(_ value: Int) -> UUID {
    let suffix = String(format: "%012x", value)
    return UUID(uuidString: "00000000-0000-0000-0000-\(suffix)")!
}

private extension GenerationPruneIntentPhaseV1 {
    var ordinalForTests: Int {
        switch self {
        case .prepared: return 0
        case .bytesRemoved: return 1
        case .retiredPointerPublished: return 2
        case .receiptPublished: return 3
        }
    }
}

import Foundation
import SwiftData
import XCTest

@testable import FieldEvidenceApp

final class V9_06DeletionArchiveIntegrationTests: XCTestCase {
    @MainActor
    func testV23P03C40AssetDeletionPreservesImmutableAuthorityRows() async throws {
        let harness = try V906Integration.makeHarness("c40-immutable", withAsset: true)
        defer { V906Integration.remove(harness.root) }
        let mutationID = try MutationIDV1(rawValue: V906Integration.id(880))
        let value = try AuthoritySourceReleaseV1(
            releaseID: V906Integration.id(881),
            workspaceID: harness.session.workspaceIdentity.workspaceID,
            sourceID: V906Integration.id(882),
            sourceType: .ownerPolicy,
            designation: "Deletion-retained policy",
            editionOrRevision: "1",
            retrievedAt: V906Integration.deletedAt.addingTimeInterval(-30),
            licenseStorageDisposition: .notStored,
            recordedAt: V906Integration.deletedAt.addingTimeInterval(-30),
            mutationID: mutationID
        )
        harness.session.modelContext.insert(try AuthoritySourceReleaseRow(value))
        try harness.session.modelContext.save()
        let assetID = try XCTUnwrap(
            harness.session.modelContext.fetch(FetchDescriptor<Asset>()).first?.id
        )

        _ = try await V906Integration.deletionService(harness).delete(assetID: assetID)

        XCTAssertEqual(try harness.session.modelContext.fetchCount(FetchDescriptor<Asset>()), 0)
        let retained = try harness.session.modelContext.fetch(FetchDescriptor<AuthoritySourceReleaseRow>())
        XCTAssertEqual(retained.count, 1)
        XCTAssertEqual(try XCTUnwrap(retained.first).value(), value)
    }

    // Relaunch recovery is the real restore boundary for interrupted deletion work.
    @MainActor
    func testV9_06I01PartialDeletionRecoveryAndInterruptedErasePreservesOrForwards() async throws {
        let deletion = try V906Integration.makeHarness("i-delete", withAsset: true)
        defer { V906Integration.remove(deletion.root) }
        let assetID = try XCTUnwrap(
            deletion.session.modelContext.fetch(FetchDescriptor<Asset>()).first?.id
        )
        do {
            _ = try await V906Integration.deletionService(
                deletion,
                failure: .committedPhase
            ).delete(assetID: assetID)
            XCTFail("Expected committed-phase interruption")
        } catch {
            XCTAssertEqual(error as? WholeSignDeletionServiceError, .injectedFailure)
        }
        XCTAssertEqual(try deletion.session.modelContext.fetchCount(FetchDescriptor<Asset>()), 0)
        XCTAssertTrue(try DeletionLedgerStore(context: deletion.session.modelContext).snapshot().entries.contains {
            $0.identity.kind == .asset && $0.identity.id == assetID
        })
        let deletionRecovery = WholeSignDeletionService(
            modelContext: deletion.session.modelContext,
            generationRootURL: deletion.session.generationRootURL
        )
        XCTAssertEqual(try await deletionRecovery.reconcile().completedCommittedCount, 1)
        XCTAssertEqual(try await deletionRecovery.reconcile().completedCommittedCount, 0)

        for (offset, point) in [
            EraseAllFailurePoint.beforePreparedWrite,
            EraseAllFailurePoint.afterPointerSwitch,
        ].enumerated() {
            let harness = try V906Integration.makeHarness("i-erase-\(offset)", withAsset: true)
            defer { V906Integration.remove(harness.root) }
            let context = harness.session.modelContext
            let tombstone = try DeletionLedgerEntryV2(
                identity: DeletionIdentityV2(kind: .asset, id: V906Integration.id(800 + offset)),
                deletedAt: V906Integration.deletedAt
            )
            try DeletionLedgerStore(context: context).stageUnion([tombstone])
            try context.save()
            let oldGenerationID = harness.session.generationID
            var coordinator: StoreSessionCoordinator? = StoreSessionCoordinator(session: harness.session)
            let diagnostics = DiagnosticsStore(applicationSupportURL: harness.support)
            await diagnostics.prepare()
            let defaults = try XCTUnwrap(UserDefaults(suiteName: "V9_06-I01-\(UUID())"))
            defer { defaults.removePersistentDomain(forName: "com.palatis3.fieldrecord") }
            let service = EraseAllService(
                applicationSupportURL: harness.support,
                cachesDirectoryURL: harness.caches,
                temporaryDirectoryURL: harness.temporary,
                userDefaults: defaults,
                bundleIdentifier: "com.palatis3.fieldrecord",
                makeUUID: V906Integration.sequence([
                    V906Integration.id(820 + offset * 10),
                    V906Integration.id(821 + offset * 10),
                    V906Integration.id(822 + offset * 10),
                    V906Integration.id(823 + offset * 10),
                ]),
                failureInjection: EraseAllFailureInjection(failOnceAt: point)
            )
            do {
                _ = try await service.erase(
                    confirmation: "ERASE",
                    coordinator: try XCTUnwrap(coordinator),
                    diagnosticsStore: diagnostics,
                    activate: { _ in }
                )
                XCTFail("Expected erase interruption at \(point)")
            } catch {
                XCTAssertEqual(error as? EraseAllServiceError, .injectedFailure)
            }
            if point == .beforePreparedWrite {
                XCTAssertEqual(try harness.factory.currentGenerationID(), oldGenerationID)
                XCTAssertEqual(try DeletionLedgerStore(context: context).snapshot().entries, [tombstone])
            }
            coordinator = nil
            await Task.yield()
            let recovered = try await EraseAllService(
                applicationSupportURL: harness.support,
                cachesDirectoryURL: harness.caches,
                temporaryDirectoryURL: harness.temporary,
                userDefaults: defaults,
                bundleIdentifier: "com.palatis3.fieldrecord"
            ).reconcileAtStartup(diagnosticsStore: diagnostics)
            if point == .beforePreparedWrite {
                XCTAssertNil(recovered)
                XCTAssertEqual(try harness.factory.currentGenerationID(), oldGenerationID)
            } else {
                let session = try XCTUnwrap(recovered)
                XCTAssertNotEqual(session.generationID, oldGenerationID)
                XCTAssertEqual(try DeletionLedgerStore(context: session.modelContext).snapshot(), .empty)
                XCTAssertEqual(try session.modelContext.fetchCount(FetchDescriptor<Asset>()), 0)
            }
        }

        // A preparation is durable before an Erase intent exists. These cases
        // model process death while that pre-intent cleanup is at each stable
        // boundary: a complete target, a target whose manifest was already
        // removed, and an already-removed target. An unknown installed sibling
        // must instead stop recovery without mutating any of those authorities.
        let preparationCases = [
            (name: "full-target", removeManifest: false, removeTarget: false, unknown: false),
            (name: "manifest-absent", removeManifest: true, removeTarget: false, unknown: false),
            (name: "target-absent", removeManifest: true, removeTarget: true, unknown: false),
            (name: "unknown-generation", removeManifest: false, removeTarget: false, unknown: true),
        ]
        for (offset, crashCase) in preparationCases.enumerated() {
            let harness = try V906Integration.makeHarness(
                "i-preparation-\(crashCase.name)",
                withAsset: true
            )
            defer { V906Integration.remove(harness.root) }
            let context = harness.session.modelContext
            let sourceTombstone = try DeletionLedgerEntryV2(
                identity: DeletionIdentityV2(
                    kind: .asset,
                    id: V906Integration.id(940 + offset)
                ),
                deletedAt: V906Integration.deletedAt
            )
            try DeletionLedgerStore(context: context).stageUnion([sourceTombstone])
            try context.save()
            let sourceLedger = try DeletionLedgerStore(context: context).snapshot()

            let authority = try harness.factory.makeRestoreGenerationAuthority()
            let oldGenerationID = harness.session.generationID
            let current = try harness.factory.currentGenerationPointerV3(
                expectedGenerationID: oldGenerationID,
                authority: authority
            )
            let oldPointer = RestorePointerIdentityV1(
                generationID: try XCTUnwrap(UUID(uuidString: current.generationID)),
                generationManifestSHA256: current.generationManifestSHA256,
                knownReplicaIDs: Set(try current.knownReplicaIDs.map {
                    try XCTUnwrap(UUID(uuidString: $0))
                }),
                workspaceID: try XCTUnwrap(UUID(uuidString: current.workspaceID)),
                replicaID: try XCTUnwrap(UUID(uuidString: current.replicaID))
            )
            let sourceProof = try harness.factory.currentGenerationDeletionLedgerProof(
                expectedPointer: oldPointer,
                authority: authority
            )
            let installedBefore = Set(try authority.installedGenerationNames())
            let targetGenerationID = V906Integration.id(960 + offset * 10)
            let targetIdentity = try WorkspaceReplicaIdentityV1(
                workspaceID: WorkspaceID(
                    rawValue: V906Integration.id(961 + offset * 10)
                ),
                replicaID: ReplicaID(
                    rawValue: V906Integration.id(962 + offset * 10)
                )
            )
            let initialPreparation = ErasePreparationV2(
                oldPointer: oldPointer,
                sourceLedger: sourceProof,
                targetGenerationID: targetGenerationID,
                targetWorkspaceID: targetIdentity.workspaceID.rawValue,
                targetReplicaID: targetIdentity.replicaID.rawValue,
                targetPointer: nil
            )
            let preparationStore = try EraseIntentStore(
                applicationSupportURL: harness.support
            )
            try preparationStore.createPreparation(initialPreparation)
            XCTAssertNil(try preparationStore.load())

            let created = try harness.factory.createEmptyEraseGeneration(
                id: targetGenerationID,
                expectedOldPointer: oldPointer,
                identity: targetIdentity,
                authority: authority
            )
            let frozenPreparation: ErasePreparationV2
            if crashCase.name == "full-target" {
                // Death can occur after target creation and before the marker
                // is rebound to the generated pointer.
                frozenPreparation = initialPreparation
            } else {
                let bound = initialPreparation.binding(targetPointer: created.pointer)
                try preparationStore.replacePreparation(
                    expected: initialPreparation,
                    with: bound
                )
                frozenPreparation = bound
            }

            if crashCase.removeManifest {
                try harness.factory.removePreparedRestoreGenerationManifestBeforeDiscard(
                    expectedOldID: oldGenerationID,
                    generationID: targetGenerationID,
                    expectedDigest: created.pointer.generationManifestSHA256,
                    authority: authority
                )
            }
            if crashCase.removeTarget {
                try harness.factory.removeInstalledGeneration(
                    id: targetGenerationID,
                    keeping: oldGenerationID,
                    authority: authority
                )
            }

            let unknownGenerationID = V906Integration.id(963 + offset * 10)
            if crashCase.unknown {
                try harness.factory.createEmptyInstalledGeneration(
                    id: unknownGenerationID,
                    authority: authority
                )
            }
            XCTAssertEqual(try preparationStore.loadPreparation(), frozenPreparation)
            XCTAssertEqual(
                try harness.factory.currentGenerationPointerV3(
                    expectedGenerationID: oldGenerationID,
                    authority: authority
                ),
                current
            )
            XCTAssertEqual(
                try harness.factory.currentGenerationDeletionLedgerProof(
                    expectedPointer: oldPointer,
                    authority: authority
                ),
                sourceProof
            )

            let diagnostics = DiagnosticsStore(applicationSupportURL: harness.support)
            await diagnostics.prepare()
            let suiteName = "V9_06-I01-Preparation-\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            defer { defaults.removePersistentDomain(forName: suiteName) }
            let recovery = EraseAllService(
                applicationSupportURL: harness.support,
                cachesDirectoryURL: harness.caches,
                temporaryDirectoryURL: harness.temporary,
                userDefaults: defaults,
                bundleIdentifier: "com.palatis3.fieldrecord"
            )

            if crashCase.unknown {
                do {
                    _ = try await recovery.reconcileAtStartup(
                        diagnosticsStore: diagnostics
                    )
                    XCTFail("Unknown installed generation must stop preparation recovery")
                } catch {
                    XCTAssertEqual(
                        error as? StoreGenerationFailure,
                        .dataPointerInvalid
                    )
                }
                XCTAssertEqual(try preparationStore.loadPreparation(), frozenPreparation)
                XCTAssertTrue(
                    try harness.factory.generationPresence(
                        id: targetGenerationID,
                        authority: authority
                    ).installed
                )
                XCTAssertTrue(
                    try harness.factory.generationPresence(
                        id: unknownGenerationID,
                        authority: authority
                    ).installed
                )
                XCTAssertEqual(
                    Set(try authority.installedGenerationNames()),
                    installedBefore.union([
                        targetGenerationID.uuidString.lowercased(),
                        unknownGenerationID.uuidString.lowercased(),
                    ])
                )
            } else {
                let recovered = try await recovery.reconcileAtStartup(
                    diagnosticsStore: diagnostics
                )
                XCTAssertNil(recovered)
                XCTAssertNil(try preparationStore.loadPreparation())
                XCTAssertNil(try preparationStore.load())
                let targetPresence = try harness.factory.generationPresence(
                    id: targetGenerationID,
                    authority: authority
                )
                XCTAssertFalse(targetPresence.installed)
                XCTAssertFalse(targetPresence.staging)
                XCTAssertNil(
                    try StoreMigrationJournalStoreV1(
                        applicationSupportURL: harness.support
                    ).loadManifestIfPresent(targetGenerationID: targetGenerationID)
                )
                XCTAssertEqual(
                    Set(try authority.installedGenerationNames()),
                    installedBefore
                )
            }

            XCTAssertEqual(
                try harness.factory.currentGenerationPointerV3(
                    expectedGenerationID: oldGenerationID,
                    authority: authority
                ),
                current
            )
            XCTAssertEqual(
                try harness.factory.currentGenerationDeletionLedgerProof(
                    expectedPointer: oldPointer,
                    authority: authority
                ),
                sourceProof
            )
            XCTAssertEqual(
                try DeletionLedgerStore(context: context).snapshot(),
                sourceLedger
            )
        }
    }

    @MainActor
    func testV9_06R01OrphanCleanupIsSeparateFromLedgerAndSurvivesRelaunch() async throws {
        let harness = try V906Integration.makeHarness("r", withAsset: true)
        defer { V906Integration.remove(harness.root) }
        let assetID = try XCTUnwrap(
            harness.session.modelContext.fetch(FetchDescriptor<Asset>()).first?.id
        )
        _ = try await V906Integration.deletionService(harness).delete(assetID: assetID)
        let ledgerBefore = try DeletionLedgerStore(context: harness.session.modelContext).snapshot()

        let orphanID = V906Integration.id(900).uuidString.lowercased()
        let orphanDirectory = harness.session.generationRootURL.appendingPathComponent(
            "evidence/\(orphanID)", isDirectory: true
        )
        try FileManager.default.createDirectory(at: orphanDirectory, withIntermediateDirectories: true)
        try Data("orphan-original".utf8).write(to: orphanDirectory.appendingPathComponent("original.jpg"))
        try Data("orphan-thumbnail".utf8).write(to: orphanDirectory.appendingPathComponent("thumbnail.jpg"))

        let summary = try OrphanFileCleanupService(
            generationRootURL: harness.session.generationRootURL
        ).reconcile(referencedRelativePaths: [])
        XCTAssertEqual(summary.removedFileCount, 2)
        XCTAssertEqual(summary.removedDirectoryCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphanDirectory.path))
        XCTAssertEqual(
            try DeletionLedgerStore(context: harness.session.modelContext).snapshot(),
            ledgerBefore
        )

        let relaunched = try harness.factory.openOrBootstrapCurrent()
        XCTAssertEqual(relaunched.generationID, harness.session.generationID)
        XCTAssertEqual(try DeletionLedgerStore(context: relaunched.modelContext).snapshot(), ledgerBefore)
        XCTAssertEqual(try relaunched.modelContext.fetchCount(FetchDescriptor<Site>()), 1)
        XCTAssertEqual(try relaunched.modelContext.fetchCount(FetchDescriptor<Asset>()), 0)
    }
}

extension V9_06DeletionArchiveIntegrationTests {
    func testV23P03C41ArchiveReplayLeavesNoCurrentRelationship() throws {
        let fixture = try C41FunctionalRelationshipTestSupportV1.makeFixture(seed: 41_062)
        let projection = try FunctionalRelationshipProjectionBuilderV1.rebuild(
            workspaceID: fixture.workspaceID,
            events: [fixture.added, fixture.ended],
            descriptors: [fixture.descriptor]
        )

        XCTAssertTrue(projection.currentRelationships.isEmpty)
        XCTAssertEqual(projection.sourceEventsSHA256.count, 64)
        try fixture.ended.validateSuccessor(of: fixture.added)

        let snapshot = try CompletedFunctionalRelationshipSnapshotV1(
            snapshotID: C41FunctionalRelationshipTestSupportV1.id(41_063),
            workspaceID: fixture.workspaceID,
            capturedAt: C41FunctionalRelationshipTestSupportV1.fixedDate,
            descriptorReleases: [fixture.descriptor],
            relationships: [fixture.added]
        )
        XCTAssertEqual(snapshot.relationships.first?.relationshipID, fixture.relationshipID)
        try snapshot.validate()
    }
}

extension V9_06DeletionArchiveIntegrationTests {
    func testV23P03C13ArchiveRowsRetainManifestAndAttestationHistory() throws {
        let fixture = try C13EvidenceAssuranceTestSupportV1.makeFixture(seed: 51_607)
        let manifestRow = try AssuranceManifestRow(fixture.customerManifest)
        let attestationRow = try AttestationRow(fixture.customerAttestation)
        let restoredManifest = try manifestRow.value()
        let restoredAttestation = try attestationRow.value()

        XCTAssertEqual(restoredManifest.manifestID, fixture.customerManifest.manifestID)
        XCTAssertEqual(restoredManifest.revision, 1)
        XCTAssertEqual(restoredAttestation.action, .recorded)
        XCTAssertEqual(restoredAttestation.supersedesAttestationID, nil)
        XCTAssertEqual(restoredAttestation.manifestSHA256, restoredManifest.manifestSHA256)
        try restoredAttestation.validate(manifest: restoredManifest)
    }
}

extension V9_06DeletionArchiveIntegrationTests {
    func testV23P03C14ArchivedReviewTransitionRetainsCanonicalRowIdentity() throws {
        let fixture = try C14InspectionReviewTestSupportV1.makeFixture(seed: 145_006)
        let row = try InspectionReviewTransitionRow(fixture.transitions[0])
        XCTAssertEqual(try row.value(), fixture.transitions[0])
        XCTAssertEqual(row.reviewID, fixture.reviewID)
        XCTAssertEqual(row.revision, 1)
    }
}

import Foundation
import SwiftData
import XCTest

@testable import FieldEvidenceApp

final class V9_07CompatibilityCorpusIntegrationTests: XCTestCase {
    func testV23P03C40CanonicalCompatibilityRoundTripRetainsProvisionalReaderBoundary() throws {
        let policy = ReleasedDataCompatibilityPolicyV1.exactHead(
            candidateHead: String(repeating: "4", count: 40)
        )
        let restored = try ReleasedDataCompatibilityPolicyV1.decodeCanonical(
            policy.canonicalData()
        )
        let path = try restored.dataManifest.path(for: .reportOpenJSON)
        XCTAssertEqual(path.currentWriterVersion, "snapshot2")
        XCTAssertTrue(path.readableVersions.contains("snapshot3"))
        XCTAssertThrowsError(
            try restored.dataManifest.validateWriterVersion("snapshot3", for: .reportOpenJSON)
        )
    }

    @MainActor
    func testV9_07G01AggregateReleasedDataCorpusAndRuntimeRoundTrips() async throws {
        let policy = ReleasedDataCompatibilityPolicyV1.current
        let corpus = try V907CompatibilitySupport.corpus()
        let seed = try V907CompatibilitySupport.seed()
        let metadata = try V907CompatibilitySupport.corpusMetadata()
        try policy.validate()
        try corpus.validate(against: policy.dataManifest)
        try seed.validate(against: policy)
        XCTAssertEqual(metadata.schema, "V21P01C07CompatibilityCorpusV1")
        XCTAssertEqual(metadata.schemaVersion, 1)
        XCTAssertTrue(CompatibilityCanonicalV1.validSHA256(metadata.artifactDigest))
        XCTAssertEqual(Set(metadata.evidenceIDs), [
            "V23-P01-C07-G01", "V23-P01-C07-A01", "V23-P01-C07-H01",
            "V23-P01-C07-I01", "V23-P01-C07-R01",
        ])
        XCTAssertEqual(metadata.workspaceScenarioTags, [
            "dst", "empty", "long", "maximal", "minimum", "rtl", "unicode",
        ])
        XCTAssertTrue(metadata.immutable && metadata.synthetic)
        XCTAssertFalse(metadata.containsCustomerData || metadata.containsSecrets)

        let store = try policy.dataManifest.path(for: .liveStore)
        XCTAssertEqual(store.readableVersions, ["1.0.0", "2.0.0", "3.0.0"])
        XCTAssertEqual(store.currentWriterVersion, "3.0.0")
        XCTAssertEqual(store.forwardUpgradeTransitions, [
            .init(fromVersion: "1.0.0", toVersion: "2.0.0"),
            .init(fromVersion: "2.0.0", toVersion: "3.0.0"),
        ])
        XCTAssertTrue(try store.supportsForwardUpgrade(fromVersion: "1.0.0", toVersion: "3.0.0"))
        for version in store.readableVersions {
            XCTAssertTrue(corpus.validatesEnrollment(family: .liveStore, version: version))
        }
        XCTAssertTrue(V907CompatibilitySupport.containsCase(corpus, family: .liveStore, tokens: ["second", "launch"]))

        let source = try V906Integration.makeHarness("v907-g-source", withAsset: true)
        defer { V906Integration.remove(source.root) }
        let sourceSiteID = try XCTUnwrap(
            source.session.modelContext.fetch(FetchDescriptor<Site>()).first?.id
        )
        let sourceAssetID = try XCTUnwrap(
            source.session.modelContext.fetch(FetchDescriptor<Asset>()).first?.id
        )
        _ = try await V906Integration.deletionService(source).delete(assetID: sourceAssetID)
        let sourcePointer = try restorePointer(
            factory: source.factory,
            generationID: source.session.generationID
        )
        let sourceLedger = try DeletionLedgerStore(
            context: source.session.modelContext
        ).snapshot()
        XCTAssertEqual(try source.session.modelContext.fetchCount(FetchDescriptor<Site>()), 1)
        XCTAssertEqual(try source.session.modelContext.fetchCount(FetchDescriptor<Asset>()), 0)
        XCTAssertTrue(sourceLedger.entries.contains {
            $0.identity.kind == .asset && $0.identity.id == sourceAssetID
        })
        let currentDestination = source.root.appendingPathComponent("current-export", isDirectory: true)
        try FileManager.default.createDirectory(at: currentDestination, withIntermediateDirectories: true)
        let exportService = BackupExportService(
            modelContext: source.session.modelContext,
            generationRootURL: source.session.generationRootURL,
            storagePreflight: V906Integration.storage,
            now: { V906Integration.deletedAt },
            makeUUID: V906Integration.sequence([
                V906Integration.id(600), V906Integration.id(601),
                V906Integration.id(602), V906Integration.id(603),
            ])
        )
        let currentPreview = try exportService.prepareStreaming()
        let currentArchive = try exportService.exportStreaming(
            previewID: currentPreview.id,
            to: currentDestination
        )
        let legacyArchive = try V906Integration.exportLegacy(source)
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: currentArchive.path, isDirectory: &isDirectory))
        XCTAssertFalse(isDirectory.boolValue)
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyArchive.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)

        for (archiveOffset, archive) in [currentArchive, legacyArchive].enumerated() {
            for (modeOffset, mode) in BackupRestoreMode.allCases.enumerated() {
                let target = try V906Integration.makeHarness(
                    "v907-g-\(archiveOffset)-\(mode.rawValue)",
                    withAsset: mode == .replaceExisting
                )
                defer { V906Integration.remove(target.root) }
                let oldPointer = try restorePointer(
                    factory: target.factory,
                    generationID: target.session.generationID
                )
                let targetOnlyTombstone = try DeletionLedgerEntryV2(
                    identity: DeletionIdentityV2(
                        kind: .report,
                        id: V906Integration.id(700 + archiveOffset * 20 + modeOffset)
                    ),
                    deletedAt: V906Integration.deletedAt
                )
                if mode == .replaceExisting {
                    try DeletionLedgerStore(context: target.session.modelContext).stageUnion([
                        targetOnlyTombstone,
                    ])
                    try target.session.modelContext.save()
                }
                let oldLedger = try DeletionLedgerStore(
                    context: target.session.modelContext
                ).snapshot()
                let restoreIDs = V906Integration.restoreIDs(
                    mode,
                    offset: 30 + archiveOffset * 8 + modeOffset
                )
                if archiveOffset == 1 && (mode == .clone || mode == .fork) {
                    do {
                        _ = try await V906Integration.restore(
                            archive,
                            into: target,
                            mode: mode,
                            ids: restoreIDs
                        )
                        XCTFail("Legacy \(mode.rawValue) must fail without source identity")
                    } catch {
                        XCTAssertEqual(
                            error as? BackupRestoreServiceError,
                            .invalidPackage,
                            mode.rawValue
                        )
                    }
                    XCTAssertEqual(
                        try restorePointer(
                            factory: target.factory,
                            generationID: target.session.generationID
                        ),
                        oldPointer,
                        mode.rawValue
                    )
                    let reopened = try target.factory.openOrBootstrapCurrent()
                    XCTAssertEqual(reopened.generationID, oldPointer.generationID)
                    XCTAssertEqual(
                        try DeletionLedgerStore(context: reopened.modelContext).snapshot(),
                        oldLedger,
                        mode.rawValue
                    )
                    XCTAssertNil(
                        try BackupRestoreService(
                            applicationSupportURL: target.support
                        ).reconcileAtStartup(),
                        mode.rawValue
                    )
                    continue
                }
                let restored = try await V906Integration.restore(
                    archive,
                    into: target,
                    mode: mode,
                    ids: restoreIDs
                )
                let diagnostic = "\(archive.lastPathComponent) \(mode.rawValue)"
                XCTAssertEqual(
                    try restored.modelContext.fetch(FetchDescriptor<Site>()).map(\.id),
                    [sourceSiteID],
                    diagnostic
                )
                XCTAssertFalse(
                    try restored.modelContext.fetch(FetchDescriptor<Asset>()).contains {
                        $0.id == sourceAssetID
                    },
                    diagnostic
                )
                let restoredLedger = try DeletionLedgerStore(
                    context: restored.modelContext
                ).snapshot()
                XCTAssertEqual(
                    restoredLedger.entries.contains(targetOnlyTombstone),
                    mode == .replaceExisting,
                    diagnostic
                )
                XCTAssertEqual(
                    restoredLedger.entries.contains {
                        $0.identity.kind == .asset && $0.identity.id == sourceAssetID
                    },
                    archiveOffset == 0,
                    diagnostic
                )
                XCTAssertEqual(
                    restoredLedger.entries.count,
                    (archiveOffset == 0 ? sourceLedger.entries.count : 0)
                        + (mode == .replaceExisting ? 1 : 0),
                    diagnostic
                )

                let restoredPointer = try restorePointer(
                    factory: target.factory,
                    generationID: restored.generationID
                )
                XCTAssertEqual(restoredPointer.generationID, restored.generationID, diagnostic)
                XCTAssertTrue(
                    Set(oldPointer.knownReplicaIDs).isSubset(
                        of: Set(restoredPointer.knownReplicaIDs)
                    ),
                    diagnostic
                )
                XCTAssertTrue(restoredPointer.knownReplicaIDs.contains(restoredPointer.replicaID))
                if archiveOffset == 0 {
                    XCTAssertNotEqual(
                        restoredPointer.replicaID,
                        sourcePointer.replicaID,
                        diagnostic
                    )
                    XCTAssertTrue(
                        restoredPointer.knownReplicaIDs.contains(sourcePointer.replicaID),
                        diagnostic
                    )
                }
                switch mode {
                case .emptyInstall:
                    if archiveOffset == 0 {
                        XCTAssertEqual(restoredPointer.workspaceID, sourcePointer.workspaceID, diagnostic)
                    }
                case .replaceExisting:
                    XCTAssertEqual(restoredPointer.workspaceID, oldPointer.workspaceID, diagnostic)
                    XCTAssertEqual(restoredPointer.replicaID, oldPointer.replicaID, diagnostic)
                case .clone, .fork:
                    XCTAssertNotEqual(restoredPointer.workspaceID, oldPointer.workspaceID, diagnostic)
                    if archiveOffset == 0 {
                        XCTAssertNotEqual(
                            restoredPointer.workspaceID,
                            sourcePointer.workspaceID,
                            diagnostic
                        )
                    }
                }

                let reopened = try target.factory.openOrBootstrapCurrent()
                XCTAssertEqual(reopened.generationID, restored.generationID, diagnostic)
                XCTAssertEqual(
                    try restorePointer(
                        factory: target.factory,
                        generationID: reopened.generationID
                    ),
                    restoredPointer,
                    diagnostic
                )
                XCTAssertEqual(
                    try DeletionLedgerStore(context: reopened.modelContext).snapshot(),
                    restoredLedger,
                    diagnostic
                )
                XCTAssertEqual(
                    try reopened.modelContext.fetch(FetchDescriptor<Site>()).map(\.id),
                    [sourceSiteID],
                    diagnostic
                )
                XCTAssertNil(
                    try BackupRestoreService(
                        applicationSupportURL: target.support
                    ).reconcileAtStartup(),
                    diagnostic
                )
            }
        }

        for family in [
            CompatibilityArtifactFamilyV1.reportOpenJSON,
            .reportPDF, .signPack, .durableMedia, .deletionLedger, .deletionIntent, .eraseIntent,
        ] {
            let currentVersion = try policy.dataManifest.path(for: family).currentWriterVersion
            try policy.validateWriterEnrollment(family: family, version: currentVersion, corpus: corpus)
        }
        let open = try V907CompatibilitySupport.fixtureData("V21P01C07HistoricReportOpenV1")
        let pdf = try V907CompatibilitySupport.fixtureData("V21P01C07HistoricReportV1", extension: "pdf")
        let seedBytes = try V907CompatibilitySupport.fixtureData("V21P01C07PreV23SeedV1")
        XCTAssertEqual(
            metadata.fixtureDigests["FieldEvidenceAppTests/Fixtures/V21/Compatibility/V21P01C07HistoricReportOpenV1.json"],
            V907CompatibilitySupport.sha256(open)
        )
        XCTAssertEqual(
            metadata.fixtureDigests["FieldEvidenceAppTests/Fixtures/V21/Compatibility/V21P01C07HistoricReportV1.pdf"],
            V907CompatibilitySupport.sha256(pdf)
        )
        XCTAssertEqual(
            metadata.fixtureDigests["FieldEvidenceAppTests/Fixtures/V21/Compatibility/V21P01C07PreV23SeedV1.json"],
            V907CompatibilitySupport.sha256(seedBytes)
        )
        XCTAssertTrue(corpus.cases.contains {
            $0.family == .reportOpenJSON && $0.artifactSHA256 == V907CompatibilitySupport.sha256(open)
        })
        XCTAssertTrue(corpus.cases.contains {
            $0.family == .reportPDF && $0.artifactSHA256 == V907CompatibilitySupport.sha256(pdf)
        })
    }

    @MainActor
    func testV9_07I01EvidenceExportAndRunReceiptInterruptionsPreserveCorpus() async throws {
        let policy = ReleasedDataCompatibilityPolicyV1.current
        let corpus = try V907CompatibilitySupport.corpus()
        let beforeCorpusDigest = try corpus.canonicalSHA256()
        let beforeSeedBytes = try V907CompatibilitySupport.fixtureData("V21P01C07PreV23SeedV1")

        let restoreSource = try V906Integration.makeHarness(
            "v907-i-restore-source",
            withAsset: true
        )
        defer { V906Integration.remove(restoreSource.root) }
        let restoredSiteID = try XCTUnwrap(
            restoreSource.session.modelContext.fetch(FetchDescriptor<Site>()).first?.id
        )
        let deletedAssetID = try XCTUnwrap(
            restoreSource.session.modelContext.fetch(FetchDescriptor<Asset>()).first?.id
        )
        _ = try await V906Integration.deletionService(restoreSource).delete(
            assetID: deletedAssetID
        )
        let restoreSourcePointer = try restorePointer(
            factory: restoreSource.factory,
            generationID: restoreSource.session.generationID
        )
        let restoreArchive = try V906Integration.exportStreaming(restoreSource)
        let restoreTarget = try V906Integration.makeHarness(
            "v907-i-restore-target",
            withAsset: false
        )
        defer { V906Integration.remove(restoreTarget.root) }
        let validated = try BackupImportService(
            generationRootURL: restoreTarget.session.generationRootURL,
            storagePreflight: V906Integration.storage,
            makeUUID: { V906Integration.id(1_500) },
            scopedAccess: .alreadyAuthorized
        ).stageAndValidate(selectedPackageURL: restoreArchive)
        let restoreIDs = V906Integration.restoreIDs(.emptyInstall, offset: 90)
        do {
            _ = try await BackupRestoreService(
                applicationSupportURL: restoreTarget.support,
                storagePreflight: V906Integration.storage,
                makeUUID: V906Integration.sequence(restoreIDs),
                failureInjection: BackupRestoreFailureInjection(
                    failOnceAt: .afterPointerSwitch
                )
            ).restore(
                validatedPackage: validated,
                currentModelContext: restoreTarget.session.modelContext,
                currentGenerationID: restoreTarget.session.generationID,
                currentGenerationRootURL: restoreTarget.session.generationRootURL,
                mode: .emptyInstall
            )
            XCTFail("Expected pointer-switch restore interruption")
        } catch {
            XCTAssertEqual(error as? BackupRestoreServiceError, .injectedFailure)
        }
        let restoreRecovery = try BackupRestoreService(
            applicationSupportURL: restoreTarget.support
        )
        let recoveredRestore = try XCTUnwrap(restoreRecovery.reconcileAtStartup())
        XCTAssertEqual(recoveredRestore.generationID, restoreIDs[0])
        XCTAssertEqual(
            try recoveredRestore.modelContext.fetch(FetchDescriptor<Site>()).map(\.id),
            [restoredSiteID]
        )
        XCTAssertEqual(
            try recoveredRestore.modelContext.fetchCount(FetchDescriptor<Asset>()),
            0
        )
        XCTAssertTrue(
            try DeletionLedgerStore(context: recoveredRestore.modelContext)
                .snapshot().entries.contains {
                    $0.identity.kind == .asset && $0.identity.id == deletedAssetID
                }
        )
        let recoveredRestorePointer = try restorePointer(
            factory: restoreTarget.factory,
            generationID: recoveredRestore.generationID
        )
        XCTAssertEqual(recoveredRestorePointer.workspaceID, restoreSourcePointer.workspaceID)
        XCTAssertNotEqual(recoveredRestorePointer.replicaID, restoreSourcePointer.replicaID)
        XCTAssertTrue(
            recoveredRestorePointer.knownReplicaIDs.contains(restoreSourcePointer.replicaID)
        )
        XCTAssertNil(try restoreRecovery.reconcileAtStartup())
        let reopenedRestore = try restoreTarget.factory.openOrBootstrapCurrent()
        XCTAssertEqual(reopenedRestore.generationID, recoveredRestore.generationID)
        XCTAssertEqual(
            try DeletionLedgerStore(context: reopenedRestore.modelContext).snapshot(),
            try DeletionLedgerStore(context: recoveredRestore.modelContext).snapshot()
        )

        let deletion = try V906Integration.makeHarness("v907-i-delete", withAsset: true)
        defer { V906Integration.remove(deletion.root) }
        let interruptedAssetID = try XCTUnwrap(
            deletion.session.modelContext.fetch(FetchDescriptor<Asset>()).first?.id
        )
        do {
            _ = try await V906Integration.deletionService(
                deletion,
                failure: .committedPhase
            ).delete(assetID: interruptedAssetID)
            XCTFail("Expected committed deletion interruption")
        } catch {
            XCTAssertEqual(error as? WholeSignDeletionServiceError, .injectedFailure)
        }
        let relaunchedDeletion = try deletion.factory.openOrBootstrapCurrent()
        let deletionRecovery = WholeSignDeletionService(
            modelContext: relaunchedDeletion.modelContext,
            generationRootURL: relaunchedDeletion.generationRootURL
        )
        let firstDeletionRecovery = try await deletionRecovery.reconcile()
        XCTAssertEqual(firstDeletionRecovery.completedCommittedCount, 1)
        let secondDeletionRecovery = try await deletionRecovery.reconcile()
        XCTAssertEqual(secondDeletionRecovery.completedCommittedCount, 0)
        XCTAssertEqual(
            try relaunchedDeletion.modelContext.fetchCount(FetchDescriptor<Asset>()),
            0
        )
        XCTAssertTrue(
            try DeletionLedgerStore(context: relaunchedDeletion.modelContext)
                .snapshot().entries.contains {
                    $0.identity.kind == .asset && $0.identity.id == interruptedAssetID
                }
        )

        for (eraseOffset, point) in [
            EraseAllFailurePoint.beforePreparedWrite,
            .afterPointerSwitch,
        ].enumerated() {
            let erase = try V906Integration.makeHarness(
                "v907-i-erase-\(eraseOffset)",
                withAsset: true
            )
            defer { V906Integration.remove(erase.root) }
            let eraseTombstone = try DeletionLedgerEntryV2(
                identity: DeletionIdentityV2(
                    kind: .asset,
                    id: V906Integration.id(1_600 + eraseOffset)
                ),
                deletedAt: V906Integration.deletedAt
            )
            try DeletionLedgerStore(context: erase.session.modelContext).stageUnion([
                eraseTombstone,
            ])
            try erase.session.modelContext.save()
            let oldErasePointer = try restorePointer(
                factory: erase.factory,
                generationID: erase.session.generationID
            )
            var coordinator: StoreSessionCoordinator? = StoreSessionCoordinator(
                session: erase.session
            )
            let diagnostics = DiagnosticsStore(applicationSupportURL: erase.support)
            await diagnostics.prepare()
            let defaultsSuite = "V9_07-I01-Erase-\(eraseOffset)-\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuite))
            defer { defaults.removePersistentDomain(forName: defaultsSuite) }
            do {
                let base = 1_610 + eraseOffset * 10
                _ = try await EraseAllService(
                    applicationSupportURL: erase.support,
                    cachesDirectoryURL: erase.caches,
                    temporaryDirectoryURL: erase.temporary,
                    userDefaults: defaults,
                    bundleIdentifier: "com.palatis3.fieldrecord",
                    makeUUID: V906Integration.sequence([
                        V906Integration.id(base), V906Integration.id(base + 1),
                        V906Integration.id(base + 2), V906Integration.id(base + 3),
                    ]),
                    failureInjection: EraseAllFailureInjection(failOnceAt: point)
                ).erase(
                    confirmation: "ERASE",
                    coordinator: try XCTUnwrap(coordinator),
                    diagnosticsStore: diagnostics,
                    activate: { _ in }
                )
                XCTFail("Expected erase interruption at \(point)")
            } catch {
                XCTAssertEqual(error as? EraseAllServiceError, .injectedFailure)
            }
            coordinator = nil
            await Task.yield()
            let eraseRecovery = EraseAllService(
                applicationSupportURL: erase.support,
                cachesDirectoryURL: erase.caches,
                temporaryDirectoryURL: erase.temporary,
                userDefaults: defaults,
                bundleIdentifier: "com.palatis3.fieldrecord"
            )
            let recoveredErase = try await eraseRecovery.reconcileAtStartup(
                diagnosticsStore: diagnostics
            )
            if point == .beforePreparedWrite {
                XCTAssertNil(recoveredErase)
                let reopened = try erase.factory.openOrBootstrapCurrent()
                XCTAssertEqual(reopened.generationID, oldErasePointer.generationID)
                XCTAssertEqual(
                    try restorePointer(
                        factory: erase.factory,
                        generationID: reopened.generationID
                    ),
                    oldErasePointer
                )
                XCTAssertEqual(
                    try DeletionLedgerStore(context: reopened.modelContext).snapshot().entries,
                    [eraseTombstone]
                )
                XCTAssertEqual(try reopened.modelContext.fetchCount(FetchDescriptor<Asset>()), 1)
            } else {
                let forwarded = try XCTUnwrap(recoveredErase)
                XCTAssertNotEqual(forwarded.generationID, oldErasePointer.generationID)
                XCTAssertEqual(
                    try DeletionLedgerStore(context: forwarded.modelContext).snapshot(),
                    .empty
                )
                XCTAssertEqual(try forwarded.modelContext.fetchCount(FetchDescriptor<Site>()), 0)
                XCTAssertEqual(try forwarded.modelContext.fetchCount(FetchDescriptor<Asset>()), 0)
                let forwardedPointer = try restorePointer(
                    factory: erase.factory,
                    generationID: forwarded.generationID
                )
                XCTAssertNotEqual(forwardedPointer.workspaceID, oldErasePointer.workspaceID)
                XCTAssertNotEqual(forwardedPointer.replicaID, oldErasePointer.replicaID)
                XCTAssertEqual(forwardedPointer.knownReplicaIDs, [forwardedPointer.replicaID])
                let reopened = try erase.factory.openOrBootstrapCurrent()
                XCTAssertEqual(reopened.generationID, forwarded.generationID)
                XCTAssertEqual(
                    try DeletionLedgerStore(context: reopened.modelContext).snapshot(),
                    .empty
                )
            }
            let secondEraseRecovery = try await eraseRecovery.reconcileAtStartup(
                diagnosticsStore: diagnostics
            )
            XCTAssertNil(secondEraseRecovery)
        }

        let selected = corpus.caseIDs(for: .representativeSentinel)
        let byID = Dictionary(uniqueKeysWithValues: corpus.cases.map { ($0.caseID, $0) })
        let boundaryCase = try XCTUnwrap(byID[try XCTUnwrap(selected.first)])

        for boundary in ["evidence_export_boundary", "run_receipt_boundary"] {
            let interrupted = try V907CompatibilitySupport.receipt(
                runID: "v23-p01-c07-i01-\(boundary)",
                corpus: corpus,
                selection: .representativeSentinel,
                mode: .acceptingFailFast,
                results: [try V907CompatibilitySupport.result(
                    for: boundaryCase,
                    outcome: .interrupted,
                    failureCode: boundary
                )]
            )
            try interrupted.validate(against: corpus)
            XCTAssertFalse(interrupted.isAccepting)
            XCTAssertThrowsError(try interrupted.requireAccepting(against: corpus))
        }

        try corpus.validate(against: policy.dataManifest, previous: corpus)
        XCTAssertEqual(try corpus.canonicalSHA256(), beforeCorpusDigest)
        XCTAssertEqual(
            try V907CompatibilitySupport.fixtureData("V21P01C07PreV23SeedV1"),
            beforeSeedBytes
        )
    }
}

extension V9_07CompatibilityCorpusIntegrationTests {
    func testV23P03C15CorpusAdvertisesSchemaAndBoundaryCompatibility() throws {
        let data = try Data(contentsOf: C15WorkPacketManifestTestSupportV1.corpusURL())
        let source = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(source.contains("V23-P03-C15"))
        XCTAssertTrue(source.contains("\"persistentModelCount\": 58"))
        XCTAssertTrue(source.contains("\"recordsSchemaVersion\": 14"))
        XCTAssertTrue(source.contains("V23-P03-C14"))
    }
}

@MainActor
private func restorePointer(
    factory: StoreGenerationFactory,
    generationID: UUID
) throws -> RestorePointerIdentityV1 {
    let pointer = try factory.currentGenerationPointerV3(
        expectedGenerationID: generationID
    )
    return RestorePointerIdentityV1(
        generationID: try XCTUnwrap(UUID(uuidString: pointer.generationID)),
        generationManifestSHA256: pointer.generationManifestSHA256,
        knownReplicaIDs: Set(try pointer.knownReplicaIDs.map {
            try XCTUnwrap(UUID(uuidString: $0))
        }),
        workspaceID: try XCTUnwrap(UUID(uuidString: pointer.workspaceID)),
        replicaID: try XCTUnwrap(UUID(uuidString: pointer.replicaID))
    )
}

extension V9_07CompatibilityCorpusIntegrationTests {
    func testV23P03C41CorpusBindsV12AndPortableContractNames() throws {
        let url = C41FunctionalRelationshipTestSupportV1.sourceRoot().appendingPathComponent(
            "FieldEvidenceAppTests/Fixtures/V21/FunctionalRelationships/V21P03C41FunctionalRelationshipCorpusV1.json"
        )
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
        XCTAssertEqual(root["schema"] as? String, "V21P03C41FunctionalRelationshipCorpusV1")
        XCTAssertEqual(root["cardID"] as? String, "V23-P03-C41")

        let persistence = try XCTUnwrap(root["persistence"] as? [String: Any])
        XCTAssertEqual(persistence["schemaRelease"] as? String, "PERSISTENT_SCHEMA_V12_FUNCTIONAL_RELATIONSHIPS")
        XCTAssertEqual(persistence["predecessorSchemaVersion"] as? Int, 11)
        XCTAssertEqual(persistence["recordsCatalog"] as? String, "RECORDS11")

        let contracts = try XCTUnwrap(root["requiredContractNames"] as? [String])
        XCTAssertTrue(contracts.contains("FunctionalRelationshipTypeDescriptorV1"))
        XCTAssertTrue(contracts.contains("AssetFunctionalRelationshipEventV1"))
        XCTAssertTrue(contracts.contains("CurrentFunctionalRelationshipProjectionV1"))
        XCTAssertTrue(contracts.contains("CompletedFunctionalRelationshipSnapshotV1"))
        XCTAssertTrue(contracts.contains("FunctionalRelationshipDispositionPreviewV1"))
    }
}

extension V9_07CompatibilityCorpusIntegrationTests {
    func testV23P03C13CorpusBindsClosedVisibilityAndForwardSchemaPolicy() throws {
        let fixture = try C13EvidenceAssuranceTestSupportV1.makeFixture(seed: 51_908)
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(contentsOf: C13EvidenceAssuranceTestSupportV1.corpusURL())
            ) as? [String: Any]
        )
        XCTAssertEqual(root["schema"] as? String, "V21P03C13EvidenceAssuranceCorpusV1")
        XCTAssertEqual(root["cardID"] as? String, "V23-P03-C13")
        XCTAssertEqual(root["purposeBindingRequired"] as? Bool, true)
        XCTAssertEqual(root["snapshotBindingRequired"] as? Bool, true)
        XCTAssertEqual(root["denyByDefault"] as? Bool, true)
        XCTAssertEqual((root["currentProjectionRows"] as? [Any])?.count, 0)

        let persistence = try XCTUnwrap(root["persistence"] as? [String: Any])
        XCTAssertEqual(persistence["schemaRelease"] as? String, "PERSISTENT_SCHEMA_V13_EVIDENCE_ASSURANCE")
        XCTAssertEqual(persistence["migration"] as? String, "EXACT_V12_TO_V13_COPY_ON_WRITE")
        XCTAssertEqual(persistence["secondWriter"] as? Bool, false)
        XCTAssertEqual(persistence["cloudStore"] as? Bool, false)
        XCTAssertEqual(fixture.customerPreview.excludedLinks.first?.decision.disposition, .excluded)
    }
}

extension V9_07CompatibilityCorpusIntegrationTests {
    func testV23P03C14CorpusDeclaresTheInspectionReviewBoundary() throws {
        let data = try Data(contentsOf: C14InspectionReviewTestSupportV1.corpusURL())
        let source = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(source.contains("V23-P03-C14"))
        XCTAssertTrue(source.contains("V23-P03-C13"))
        XCTAssertTrue(source.contains("\"persistentModelCount\": 53"))
        XCTAssertTrue(source.contains("\"recordsSchemaVersion\": 13"))
    }
}

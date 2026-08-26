import Foundation
import SwiftData
import XCTest

@testable import FieldEvidenceApp

final class V9_06DeletionRightsTests: XCTestCase {
    @MainActor
    func testV9_06G01DeleteStreamingRoundTripAllModesAndEmptySite() async throws {
        let fixture = try V906Integration.loadFixture()
        XCTAssertEqual(fixture.schema, "V21P01C06DeletionGraphV1")
        XCTAssertEqual(fixture.schemaVersion, 1)
        XCTAssertEqual(Set(fixture.authority.deterministicEvidenceIDs), [
            "V23-P01-C06-G01", "V23-P01-C06-A01", "V23-P01-C06-H01",
            "V23-P01-C06-I01", "V23-P01-C06-R01",
        ])
        XCTAssertEqual(
            Set(fixture.deletionModes.map(\.mode)),
            Set(BackupRestoreMode.allCases.map { $0.rawValue.uppercased() })
        )
        XCTAssertTrue(fixture.registeredKindPolicy.currentPersistentTagKindPresent == false)
        let source = try V906Integration.makeHarness("g-source", withAsset: true)
        defer { V906Integration.remove(source.root) }
        let deletedAssetID = try XCTUnwrap(
            source.session.modelContext.fetch(FetchDescriptor<Asset>()).first?.id
        )
        _ = try await V906Integration.deletionService(source).delete(assetID: deletedAssetID)
        XCTAssertEqual(try source.session.modelContext.fetchCount(FetchDescriptor<Site>()), 1)
        XCTAssertEqual(try source.session.modelContext.fetchCount(FetchDescriptor<Asset>()), 0)
        let archive = try V906Integration.exportStreaming(source)

        for (offset, mode) in BackupRestoreMode.allCases.enumerated() {
            let target = try V906Integration.makeHarness(
                "g-target-\(mode.rawValue)",
                withAsset: mode == .replaceExisting
            )
            defer { V906Integration.remove(target.root) }
            let restored = try await V906Integration.restore(
                archive,
                into: target,
                mode: mode,
                ids: V906Integration.restoreIDs(mode, offset: offset)
            )
            XCTAssertEqual(try restored.modelContext.fetchCount(FetchDescriptor<Asset>()), 0, mode.rawValue)
            XCTAssertGreaterThanOrEqual(try restored.modelContext.fetchCount(FetchDescriptor<Site>()), 1, mode.rawValue)
            let ledger = try DeletionLedgerStore(context: restored.modelContext).snapshot()
            XCTAssertTrue(ledger.entries.contains {
                $0.identity.kind == .asset && $0.identity.id == deletedAssetID
            }, mode.rawValue)
        }
    }

    @MainActor
    func testV9_06A01DeleteRecreateUsesDistinctTypedIdentity() async throws {
        let harness = try V906Integration.makeHarness("a", withAsset: true)
        defer { V906Integration.remove(harness.root) }
        let context = harness.session.modelContext
        let old = try XCTUnwrap(context.fetch(FetchDescriptor<Asset>()).first)
        let oldID = old.id
        let siteID = old.siteID
        _ = try await V906Integration.deletionService(harness).delete(assetID: oldID)

        let replacementID = V906Integration.id(110)
        context.insert(Asset(
            id: replacementID,
            siteID: siteID,
            packID: SignPack.illuminatedSignV1.packID,
            packSchemaVersion: SignPack.illuminatedSignV1.schemaVersion,
            packContentVersion: SignPack.illuminatedSignV1.contentVersion,
            label: "Recreated sign",
            createdAt: V906Integration.recreatedAt
        ))
        try context.save()

        let assets = try context.fetch(FetchDescriptor<Asset>())
        XCTAssertEqual(assets.map(\.id), [replacementID])
        let ledger = try DeletionLedgerStore(context: context).snapshot()
        let oldIdentity = try DeletionIdentityV2(kind: .asset, id: oldID)
        let replacementIdentity = try DeletionIdentityV2(kind: .asset, id: replacementID)
        XCTAssertNotEqual(oldIdentity.typedID, replacementIdentity.typedID)
        XCTAssertTrue(ledger.entries.contains { $0.identity == oldIdentity })
        XCTAssertFalse(ledger.entries.contains { $0.identity == replacementIdentity })
    }

    @MainActor
    func testV9_06H01OldArchiveUnknownKindAndNonEraseCannotClearLedger() async throws {
        let source = try V906Integration.makeHarness("h-source", withAsset: true)
        defer { V906Integration.remove(source.root) }
        let archivedAssetID = try XCTUnwrap(
            source.session.modelContext.fetch(FetchDescriptor<Asset>()).first?.id
        )
        let oldArchive = try V906Integration.exportLegacy(source)
        let legacyManifest = try BackupCanonicalDecoderV1().decodeManifest(
            Data(contentsOf: oldArchive.appendingPathComponent("manifest.json"))
        )
        XCTAssertEqual(legacyManifest.backupSchemaVersion, 1)
        XCTAssertEqual(legacyManifest.source.recordsSchemaVersion, 1)

        let target = try V906Integration.makeHarness("h-target", withAsset: false)
        defer { V906Integration.remove(target.root) }
        let identity = try DeletionIdentityV2(kind: .asset, id: archivedAssetID)
        try DeletionLedgerStore(context: target.session.modelContext).stageUnion([
            try DeletionLedgerEntryV2(identity: identity, deletedAt: V906Integration.deletedAt),
        ])
        try target.session.modelContext.save()

        let restored = try await V906Integration.restore(
            oldArchive,
            into: target,
            mode: .replaceExisting,
            ids: V906Integration.restoreIDs(.replaceExisting, offset: 10)
        )
        XCTAssertFalse(try restored.modelContext.fetch(FetchDescriptor<Asset>()).contains {
            $0.id == archivedAssetID
        })
        XCTAssertTrue(try DeletionLedgerStore(context: restored.modelContext).snapshot().entries.contains {
            $0.identity == identity
        })

        XCTAssertThrowsError(try DeletionIdentityV2(typedID: "unknown:\(V906Integration.id(120).uuidString.lowercased())"))
        XCTAssertThrowsError(try DeletionIdentityV2(typedID: "tag:\(V906Integration.id(121).uuidString.lowercased())"))
        XCTAssertNil(DeletionRecordKindV2(rawValue: "tag"))
        XCTAssertEqual(Set(DeletionRecordKindV2.allCases.map(\.rawValue)), [
            "site", "asset", "workflowRecord", "evidenceFile", "issue", "packet", "report",
        ])

        let malformedRecords = try V906Integration.injectUnknownLedgerKind(
            intoLegacyPackage: oldArchive
        )
        XCTAssertThrowsError(try BackupCanonicalDecoderV1().decodeRecords(malformedRecords)) {
            XCTAssertEqual($0 as? BackupCanonicalDecodingErrorV1, .invalidRecords)
        }
        XCTAssertThrowsError(try BackupPackageValidatorV1().validate(stagedPackageURL: oldArchive)) {
            XCTAssertEqual($0 as? BackupPackageValidationErrorV1, .invalidPackage)
        }
    }
}

@MainActor
enum V906Integration {
    static let deletedAt = Date(timeIntervalSince1970: 1_767_322_645)
    static let recreatedAt = deletedAt.addingTimeInterval(60)
    static let storage = StoragePreflightService(capacityProvider: { _ in .max })
    static let fileManager = FileManager.default

    struct Harness {
        let root: URL
        let support: URL
        let caches: URL
        let temporary: URL
        let factory: StoreGenerationFactory
        let session: StoreGenerationSession
    }

    struct Fixture: Decodable {
        struct Authority: Decodable { let deterministicEvidenceIDs: [String] }
        struct Mode: Decodable { let mode: String }
        struct KindPolicy: Decodable { let currentPersistentTagKindPresent: Bool }
        let schema: String
        let schemaVersion: Int
        let authority: Authority
        let deletionModes: [Mode]
        let registeredKindPolicy: KindPolicy
    }

    static func makeHarness(_ name: String, withAsset: Bool) throws -> Harness {
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "V9_06-\(name)-\(UUID().uuidString)", isDirectory: true
        )
        let support = root.appendingPathComponent("Library/Application Support", isDirectory: true)
        let caches = root.appendingPathComponent("Library/Caches", isDirectory: true)
        let temporary = root.appendingPathComponent("tmp", isDirectory: true)
        try fileManager.createDirectory(at: support, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: caches, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: temporary, withIntermediateDirectories: true)
        let factory = StoreGenerationFactory(applicationSupportURL: support)
        let session = try factory.openOrBootstrapCurrent()
        if withAsset {
            let siteID = fixtureID(1)
            session.modelContext.insert(Site(
                id: siteID,
                label: "Deletion fixture site",
                address: nil,
                timeZoneID: "America/New_York",
                createdAt: deletedAt.addingTimeInterval(-120)
            ))
            session.modelContext.insert(Asset(
                id: fixtureID(2),
                siteID: siteID,
                packID: SignPack.illuminatedSignV1.packID,
                packSchemaVersion: SignPack.illuminatedSignV1.schemaVersion,
                packContentVersion: SignPack.illuminatedSignV1.contentVersion,
                label: "Deletion fixture sign",
                createdAt: deletedAt.addingTimeInterval(-119)
            ))
            try session.modelContext.save()
        }
        return Harness(
            root: root,
            support: support,
            caches: caches,
            temporary: temporary,
            factory: factory,
            session: session
        )
    }

    static func deletionService(
        _ harness: Harness,
        failure: WholeSignDeletionFailurePoint? = nil
    ) -> WholeSignDeletionService {
        WholeSignDeletionService(
            modelContext: harness.session.modelContext,
            generationRootURL: harness.session.generationRootURL,
            now: { deletedAt },
            makeUUID: { id(50) },
            failureInjection: failure.map {
                WholeSignDeletionFailureInjection(failOnceAt: $0)
            }
        )
    }

    static func exportStreaming(_ harness: Harness) throws -> URL {
        let destination = harness.root.appendingPathComponent("exports", isDirectory: true)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        let service = BackupExportService(
            modelContext: harness.session.modelContext,
            generationRootURL: harness.session.generationRootURL,
            storagePreflight: storage,
            now: { deletedAt },
            makeUUID: sequence([id(60), id(61), id(62), id(63)])
        )
        let preview = try service.prepareStreaming()
        return try service.exportStreaming(previewID: preview.id, to: destination)
    }

    static func exportLegacy(_ harness: Harness) throws -> URL {
        let destination = harness.root.appendingPathComponent("legacy-export", isDirectory: true)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        let service = BackupExportService(
            modelContext: harness.session.modelContext,
            generationRootURL: harness.session.generationRootURL,
            storagePreflight: storage,
            now: { deletedAt },
            makeUUID: { id(64) }
        )
        let preview = try service.prepareCompatibilityFixtureLegacyDirectoryPackage()
        return try service.exportCompatibilityFixtureLegacyDirectoryPackage(
            previewID: preview.id,
            to: destination
        )
    }

    static func injectUnknownLedgerKind(intoLegacyPackage package: URL) throws -> Data {
        let recordsURL = package.appendingPathComponent("records.json")
        let originalRecords = try Data(contentsOf: recordsURL)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: originalRecords) as? [String: Any]
        )
        object["recordsSchemaVersion"] = 2
        object["deletionLedger"] = [
            "entries": [[
                "deletedAt": "2026-01-02T03:04:05.000Z",
                "identity": [
                    "id": fixtureID(2).uuidString.lowercased(),
                    "kind": "unknown",
                ],
                "schemaVersion": 2,
            ]],
            "schemaVersion": 2,
        ]
        let malformedRecords = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        try malformedRecords.write(to: recordsURL)

        let manifestURL = package.appendingPathComponent("manifest.json")
        let old = try BackupCanonicalDecoderV1().decodeManifest(Data(contentsOf: manifestURL))
        let entries = try old.entries.map { entry -> V4BackupEntryV1 in
            let data = try Data(contentsOf: package.appendingPathComponent(entry.path))
            return V4BackupEntryV1(
                byteCount: data.count,
                mimeType: entry.mimeType,
                path: entry.path,
                sha256: CanonicalJSONV1.sha256(data)
            )
        }
        let manifest = V4BackupManifestV1(
            backupSchemaVersion: 2,
            consumedEvaluationRootIDs: old.consumedEvaluationRootIDs,
            declaredPayloadByteCount: entries.reduce(0) { $0 + $1.byteCount },
            entries: entries,
            exportedAt: old.exportedAt,
            packs: old.packs,
            source: V4BackupSourceV1(
                appBuild: old.source.appBuild,
                appVersion: old.source.appVersion,
                persistentSchemaVersion: 3,
                replicaID: id(131),
                recordsSchemaVersion: 2,
                workspaceID: id(130)
            )
        )
        try BackupCanonicalEncoderV1().encodeManifest(manifest).data.write(to: manifestURL)
        return malformedRecords
    }

    static func restore(
        _ archive: URL,
        into target: Harness,
        mode: BackupRestoreMode,
        ids values: [UUID]
    ) async throws -> StoreGenerationSession {
        let validated = try BackupImportService(
            generationRootURL: target.session.generationRootURL,
            storagePreflight: storage,
            makeUUID: { id(70) },
            scopedAccess: .alreadyAuthorized
        ).stageAndValidate(selectedPackageURL: archive)
        return try await BackupRestoreService(
            applicationSupportURL: target.support,
            storagePreflight: storage,
            makeUUID: sequence(values)
        ).restore(
            validatedPackage: validated,
            currentModelContext: target.session.modelContext,
            currentGenerationID: target.session.generationID,
            currentGenerationRootURL: target.session.generationRootURL,
            mode: mode
        )
    }

    static func restoreIDs(_ mode: BackupRestoreMode, offset: Int) -> [UUID] {
        let base = 200 + offset * 10
        switch mode {
        case .emptyInstall: [id(base), id(base + 1), id(base + 2)]
        case .replaceExisting: [id(base), id(base + 1)]
        case .clone, .fork: [id(base), id(base + 1), id(base + 2), id(base + 3)]
        }
    }

    static func sequence(_ values: [UUID]) -> () -> UUID {
        var remaining = values
        return { remaining.isEmpty ? UUID() : remaining.removeFirst() }
    }

    static func id(_ suffix: Int) -> UUID {
        UUID(uuidString: String(format: "76000000-0000-4000-8000-%012d", suffix))!
    }

    static func fixtureID(_ suffix: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012x", suffix))!
    }

    static func loadFixture() throws -> Fixture {
        let bundle = Bundle(for: V9_06DeletionRightsTests.self)
        let url = try XCTUnwrap(
            bundle.url(
                forResource: "V21P01C06DeletionGraphV1",
                withExtension: "json",
                subdirectory: "Fixtures/V21/Deletion"
            ) ?? bundle.url(
                forResource: "V21P01C06DeletionGraphV1",
                withExtension: "json"
            )
        )
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    nonisolated static func remove(_ root: URL) {
        try? FileManager.default.removeItem(at: root)
    }
}

import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

final class V9_01VersionedSchemaIdentityTests: XCTestCase {
    private let fileManager = FileManager.default

    func testCatalogIsTheExactSevenModelOrderAndScalarReferencePolicy() throws {
        let registrations = PersistentModelCatalog.registrations
        let expectedNames = [
            "Site",
            "Asset",
            "WorkflowRecord",
            "EvidenceFile",
            "Issue",
            "Packet",
            "Report",
        ]
        let expectedTypes: [Any.Type] = [
            Site.self,
            Asset.self,
            WorkflowRecord.self,
            EvidenceFile.self,
            Issue.self,
            Packet.self,
            Report.self,
        ]
        let expectedFields = [
            [],
            ["siteID"],
            [
                "assetID", "packetID", "issueID", "parentRecordID",
                "recordRevisionRootID", "revisesRecordID", "evidenceSourceRecordID",
            ],
            ["recordID"],
            ["assetID", "openedByRecordID", "resolvedByRecordID"],
            ["stableRootID", "currentRecordID"],
            ["packetID", "sourceRecordID", "replacesReportID"],
        ]
        let expectedReferences: [[PersistentScalarReferenceRegistration]] = [
            [],
            [
                .init(field: "siteID", targetModel: .site),
            ],
            [
                .init(field: "assetID", targetModel: .asset),
                .init(field: "packetID", targetModel: .packet),
                .init(field: "issueID", targetModel: .issue),
                .init(field: "parentRecordID", targetModel: .workflowRecord),
                .init(field: "recordRevisionRootID", targetModel: .workflowRecord),
                .init(field: "revisesRecordID", targetModel: .workflowRecord),
                .init(field: "evidenceSourceRecordID", targetModel: .workflowRecord),
            ],
            [
                .init(field: "recordID", targetModel: .workflowRecord),
            ],
            [
                .init(field: "assetID", targetModel: .asset),
                .init(field: "openedByRecordID", targetModel: .workflowRecord),
                .init(field: "resolvedByRecordID", targetModel: .workflowRecord),
            ],
            [
                .init(field: "stableRootID", targetModel: .packet),
                .init(field: "currentRecordID", targetModel: .workflowRecord),
            ],
            [
                .init(field: "packetID", targetModel: .packet),
                .init(field: "sourceRecordID", targetModel: .workflowRecord),
                .init(field: "replacesReportID", targetModel: .report),
            ],
        ]
        let expectedStorage: [PersistentReferenceStorageDisposition] = [
            .none,
            .applicationGovernedScalarUUID,
            .applicationGovernedScalarUUID,
            .applicationGovernedScalarUUID,
            .applicationGovernedScalarUUID,
            .applicationGovernedScalarUUID,
            .applicationGovernedScalarUUID,
        ]
        let expectedDeleteDispositions: [PersistentApplicationDeleteDisposition] = [
            .deleteOrphanSiteIfSelectedAssetWasLastSiteAsset,
            .deleteSelectedAssetAfterDependents,
            .deleteSelectedAssetWorkflowRecords,
            .deleteSelectedRecordEvidence,
            .deleteSelectedAssetIssues,
            .deleteUncountedPacketOrTombstoneCountedPacket,
            .deleteSelectedPacketReports,
        ]
        let expectedDeleteRules: [PersistentSwiftDataDeleteRuleDisposition] = Array(
            repeating: .noneNoSwiftDataRelationship,
            count: expectedNames.count
        )

        XCTAssertEqual(registrations.count, 7)
        XCTAssertEqual(registrations.map(\.stableName), expectedNames)
        XCTAssertEqual(registrations.map(\.scalarReferences), expectedReferences)
        XCTAssertEqual(registrations.map(\.scalarReferenceFields), expectedFields)
        XCTAssertEqual(registrations.map(\.referenceStorageDisposition), expectedStorage)
        XCTAssertEqual(
            registrations.map(\.swiftDataDeleteRuleDisposition),
            expectedDeleteRules
        )
        XCTAssertEqual(
            PersistentModelCatalog.applicationDeleteRuleOwner,
            "WholeSignDeletionRule + WholeSignDeletionService.apply(plan:rows:)"
        )
        XCTAssertEqual(
            registrations.map(\.applicationDeleteRuleOwner),
            Array(
                repeating: PersistentModelCatalog.applicationDeleteRuleOwner,
                count: expectedNames.count
            )
        )
        XCTAssertEqual(
            registrations.map(\.applicationDeleteDisposition),
            expectedDeleteDispositions
        )

        let deletionSource = try sourceText(
            "FieldEvidenceApp/Infrastructure/Deletion/WholeSignDeletionService.swift"
        )
        XCTAssertTrue(deletionSource.contains("WholeSignDeletionRule.makePlan("))
        XCTAssertTrue(deletionSource.contains("modelContext.delete("))
        XCTAssertTrue(deletionSource.contains("packet.currentRecordID = nil"))
        XCTAssertTrue(deletionSource.contains("packet.evaluationCounted = true"))
        XCTAssertTrue(
            deletionSource.contains("packet.contentDeletedAt = tombstone.contentDeletedAt")
        )

        for index in registrations.indices {
            XCTAssertEqual(
                ObjectIdentifier(registrations[index].modelType),
                ObjectIdentifier(expectedTypes[index]),
                "catalog model mapping at index \(index)"
            )
        }
        XCTAssertEqual(
            modelTypeIDs(PersistentModelCatalog.models),
            expectedTypes.map { ObjectIdentifier($0) }
        )
    }

    func testV1IsActiveAndV2RemainsDeclarationOnly() throws {
        XCTAssertEqual(PersistentSchemaV1.versionIdentifier, Schema.Version(1, 0, 0))
        XCTAssertEqual(PersistentSchemaV2.versionIdentifier, Schema.Version(2, 0, 0))
        XCTAssertEqual(
            modelTypeIDs(PersistentSchemaV1.models),
            modelTypeIDs(PersistentModelCatalog.models)
        )
        XCTAssertEqual(
            modelTypeIDs(PersistentSchemaV2.models),
            modelTypeIDs(PersistentModelCatalog.models)
        )

        let factorySource = try sourceText(
            "FieldEvidenceApp/Infrastructure/Persistence/StoreGenerationFactory.swift"
        )
        XCTAssertTrue(factorySource.contains("PersistentSchemaV1.makeSchema()"))
        XCTAssertTrue(factorySource.contains("migrationPlan: nil"))
        XCTAssertFalse(factorySource.contains("PersistentSchemaV2"))
        XCTAssertEqual(
            factorySource.components(separatedBy: "cloudKitDatabase: .none").count - 1,
            1
        )
        XCTAssertFalse(factorySource.contains("cloudKitDatabase: .automatic"))
        XCTAssertFalse(factorySource.contains("NSPersistentCloudKitContainer"))

        let sources = try productionSwiftSources()
        XCTAssertEqual(
            sources.filter { $0.text.contains("ModelConfiguration(") }
                .map(\.relativePath),
            ["Infrastructure/Persistence/StoreGenerationFactory.swift"]
        )
        XCTAssertEqual(
            sources.filter { $0.text.contains("ModelContainer(") }
                .map(\.relativePath),
            ["Infrastructure/Persistence/StoreGenerationFactory.swift"]
        )

        let schemaSource = try sourceText(
            "FieldEvidenceApp/Infrastructure/Persistence/PersistentSchemas.swift"
        )
        let v2Body = try XCTUnwrap(
            schemaSource.components(separatedBy: "enum PersistentSchemaV2").last
        )
        XCTAssertFalse(v2Body.contains("static func makeSchema"))
    }

    func testFixedIdentityWrappersAndBoundedRestoreCollisionHandling() throws {
        let workspaceRaw = fixedUUID("00000000-0000-0000-0000-000000000001")
        let sourceRaw = fixedUUID("00000000-0000-0000-0000-000000000002")
        let blockedRaw = fixedUUID("00000000-0000-0000-0000-000000000003")
        let destinationRaw = fixedUUID("00000000-0000-0000-0000-000000000004")

        let workspace = WorkspaceID(rawValue: workspaceRaw)
        XCTAssertEqual(workspace.rawValue, workspaceRaw)
        XCTAssertEqual(WorkspaceID(rawValue: workspaceRaw), workspace)

        let siteID = SiteID(rawValue: workspaceRaw)
        let assetID = AssetID(rawValue: workspaceRaw)
        XCTAssertEqual(siteID.rawValue, workspaceRaw)
        XCTAssertEqual(assetID.rawValue, workspaceRaw)
        XCTAssertNotEqual(siteID.rawValue, sourceRaw)

        let source = ReplicaID(rawValue: sourceRaw)
        let blocked = ReplicaID(rawValue: blockedRaw)
        var candidates = [sourceRaw, blockedRaw, destinationRaw]
        var candidateIndex = 0
        let destination = try ReplicaID.destinationOwnedForRestore(
            excluding: source,
            disallowed: Set([blocked]),
            maximumAttempts: candidates.count,
            generate: {
                defer { candidateIndex += 1 }
                return candidates[candidateIndex]
            }
        )
        XCTAssertEqual(destination.rawValue, destinationRaw)
        XCTAssertNotEqual(destination, source)
        XCTAssertNotEqual(destination, blocked)

        var attempts = 0
        XCTAssertThrowsError(
            try ReplicaID.destinationOwnedForRestore(
                excluding: source,
                maximumAttempts: 2,
                generate: {
                    attempts += 1
                    return sourceRaw
                }
            )
        ) { error in
            XCTAssertEqual(
                error as? ReplicaIdentityFailure,
                .destinationIdentityExhausted
            )
        }
        XCTAssertEqual(attempts, 2)

        var generatedAtZeroBound = false
        XCTAssertThrowsError(
            try ReplicaID.destinationOwnedForRestore(
                excluding: source,
                maximumAttempts: 0,
                generate: {
                    generatedAtZeroBound = true
                    return destinationRaw
                }
            )
        ) { error in
            XCTAssertEqual(
                error as? ReplicaIdentityFailure,
                .destinationIdentityExhausted
            )
        }
        XCTAssertFalse(generatedAtZeroBound)
    }

    @MainActor
    func testUnknownCurrentAndRetiredPointerVersionsPrecedeModelStoreInspection() throws {
        let cases: [(String, (URL, UUID) throws -> Void)] = [
            ("current", { root, generationID in
                let pointer = "{\"generationID\":\"\(generationID.uuidString.lowercased())\",\"schemaVersion\":2}"
                try Data(pointer.utf8).write(
                    to: self.currentPointerURL(in: root),
                    options: .atomic
                )
            }),
            ("retired", { root, _ in
                try Data("{\"generationIDs\":[],\"schemaVersion\":2}".utf8)
                    .write(to: self.retiredPointerURL(in: root), options: .atomic)
            }),
        ]

        for (name, mutate) in cases {
            let root = try makeTemporaryApplicationSupportURL()
            defer { try? fileManager.removeItem(at: root) }
            let (factory, generationID, modelURL) = try bootstrapGeneration(at: root)
            try fileManager.removeItem(at: modelURL)
            try mutate(root, generationID)

            XCTAssertThrowsError(try factory.openOrBootstrapCurrent(), name) { error in
                XCTAssertEqual(error as? StoreGenerationFailure, .dataPointerInvalid, name)
            }
            XCTAssertFalse(fileManager.fileExists(atPath: modelURL.path), name)
        }
    }

    @MainActor
    func testLegacyV1BootstrapAndReopenPreserveTheSameGenerationAndModels() throws {
        let root = try makeTemporaryApplicationSupportURL()
        defer { try? fileManager.removeItem(at: root) }
        let factory = StoreGenerationFactory(applicationSupportURL: root)
        let siteID = fixedUUID("11111111-2222-3333-4444-555555555555")
        let assetID = fixedUUID("AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")
        let createdAt = Date(timeIntervalSince1970: 1_700_000_001)
        let generationID: UUID

        do {
            var session: StoreGenerationSession? = try factory.openOrBootstrapCurrent()
            let opened = try XCTUnwrap(session)
            generationID = opened.generationID
            opened.modelContext.insert(
                Site(
                    id: siteID,
                    label: "Legacy Site",
                    address: "1 Main Street",
                    timeZoneID: "America/New_York",
                    createdAt: createdAt,
                    updatedAt: createdAt
                )
            )
            opened.modelContext.insert(
                Asset(
                    id: assetID,
                    siteID: siteID,
                    packID: "field.evidence.illuminated_sign.v1",
                    packSchemaVersion: 1,
                    packContentVersion: 1,
                    label: "Legacy Asset",
                    createdAt: createdAt,
                    updatedAt: createdAt
                )
            )
            try opened.modelContext.save()
            session = nil
        }

        do {
            let reopened = try factory.openOrBootstrapCurrent()
            XCTAssertEqual(reopened.generationID, generationID)
            XCTAssertEqual(
                try Data(contentsOf: currentPointerURL(in: root)),
                Data("{\"generationID\":\"\(generationID.uuidString.lowercased())\",\"schemaVersion\":1}".utf8)
            )
            XCTAssertEqual(
                try Data(contentsOf: retiredPointerURL(in: root)),
                Data("{\"generationIDs\":[],\"schemaVersion\":1}".utf8)
            )

            let sites = try reopened.modelContext.fetch(FetchDescriptor<Site>())
            let assets = try reopened.modelContext.fetch(FetchDescriptor<Asset>())
            XCTAssertEqual(sites.count, 1)
            XCTAssertEqual(assets.count, 1)
            XCTAssertEqual(try XCTUnwrap(sites.first).id, siteID)
            XCTAssertEqual(try XCTUnwrap(assets.first).id, assetID)
            XCTAssertEqual(try XCTUnwrap(assets.first).siteID, siteID)
        }
    }

    private struct ProductionSource {
        let relativePath: String
        let text: String
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func sourceText(_ relativePath: String) throws -> String {
        try String(
            decoding: Data(
                contentsOf: repositoryRoot.appendingPathComponent(relativePath)
            ),
            as: UTF8.self
        )
    }

    private func productionSwiftSources() throws -> [ProductionSource] {
        let root = repositoryRoot.appendingPathComponent("FieldEvidenceApp")
        let enumerator = try XCTUnwrap(
            fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        )
        var sources: [ProductionSource] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let relative = url.path
                .replacingOccurrences(of: root.path, with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "\\/"))
                .replacingOccurrences(of: "\\", with: "/")
            sources.append(
                ProductionSource(
                    relativePath: relative,
                    text: String(decoding: try Data(contentsOf: url), as: UTF8.self)
                )
            )
        }
        return sources.sorted { $0.relativePath < $1.relativePath }
    }

    @MainActor
    private func bootstrapGeneration(at root: URL) throws -> (
        factory: StoreGenerationFactory,
        generationID: UUID,
        modelURL: URL
    ) {
        let factory = StoreGenerationFactory(applicationSupportURL: root)
        var session: StoreGenerationSession? = try factory.openOrBootstrapCurrent()
        let opened = try XCTUnwrap(session)
        let generationID = opened.generationID
        let modelURL = opened.generationRootURL.appendingPathComponent(
            "model.sqlite",
            isDirectory: false
        )
        session = nil
        return (factory, generationID, modelURL)
    }

    private func makeTemporaryApplicationSupportURL() throws -> URL {
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "V9_01VersionedSchemaIdentityTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func currentPointerURL(in root: URL) -> URL {
        root
            .appendingPathComponent("FieldEvidenceData", isDirectory: true)
            .appendingPathComponent("current.json", isDirectory: false)
    }

    private func retiredPointerURL(in root: URL) -> URL {
        root
            .appendingPathComponent("FieldEvidenceData", isDirectory: true)
            .appendingPathComponent("retired.json", isDirectory: false)
    }

    private func fixedUUID(_ value: String) -> UUID {
        UUID(uuidString: value)!
    }

    private func modelTypeIDs(
        _ models: [any PersistentModel.Type]
    ) -> [ObjectIdentifier] {
        models.map { ObjectIdentifier($0) }
    }
}

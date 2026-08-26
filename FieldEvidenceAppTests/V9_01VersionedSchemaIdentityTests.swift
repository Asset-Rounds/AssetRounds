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

    func testV1AndV2RegistryKeepDistinctOrderedSchemas() throws {
        XCTAssertEqual(PersistentSchemaV1.versionIdentifier, Schema.Version(1, 0, 0))
        XCTAssertEqual(PersistentSchemaV2.versionIdentifier, Schema.Version(2, 0, 0))
        XCTAssertEqual(
            modelTypeIDs(PersistentSchemaV1.models),
            modelTypeIDs(PersistentModelCatalog.models)
        )
        XCTAssertEqual(PersistentSchemaV1.models.count, 7)
        XCTAssertEqual(PersistentSchemaV2.models.count, 8)
        XCTAssertEqual(
            modelTypeIDs(Array(PersistentSchemaV2.models.dropLast())),
            modelTypeIDs(PersistentModelCatalog.models)
        )
        XCTAssertEqual(
            modelTypeIDs(PersistentSchemaV2.models).last,
            ObjectIdentifier(PersistentSchemaReleaseMarker.self)
        )
        XCTAssertNotEqual(
            modelTypeIDs(PersistentSchemaV1.models),
            modelTypeIDs(PersistentSchemaV2.models)
        )
        XCTAssertEqual(PersistentSchemaReleaseRegistryV1.releases, [.v1, .v2])
        XCTAssertEqual(PersistentSchemaReleaseRegistryV1.activeRelease, .v2)
        XCTAssertEqual(
            PersistentSchemaReleaseRegistryV1.activeVersionIdentifier,
            PersistentSchemaV2.versionIdentifier
        )
        XCTAssertEqual(
            PersistentSchemaReleaseRegistryV1.activeCompatibilityID,
            PersistentSchemaReleaseRegistryV1.v2CompatibilityID
        )
        XCTAssertNoThrow(try PersistentSchemaReleaseRegistryV1.validate())
        XCTAssertEqual(
            PersistentSchemaMigrationPlanV1.schemas.map {
                ObjectIdentifier($0)
            },
            [
                ObjectIdentifier(PersistentSchemaV1.self),
                ObjectIdentifier(PersistentSchemaV2.self),
            ]
        )
        XCTAssertEqual(PersistentSchemaMigrationPlanV1.stages.count, 1)

        let factorySource = try sourceText(
            "FieldEvidenceApp/Infrastructure/Persistence/StoreGenerationFactory.swift"
        )
        XCTAssertTrue(factorySource.contains("PersistentSchemaV1.makeSchema()"))
        XCTAssertTrue(factorySource.contains("migrationPlan: nil"))
        XCTAssertTrue(factorySource.contains("PersistentSchemaV2"))
        XCTAssertTrue(factorySource.contains("PersistentSchemaReleaseMarker"))
        XCTAssertTrue(factorySource.contains("migrationPlan: PersistentSchemaMigrationPlanV1.self"))
        XCTAssertEqual(
            factorySource.components(separatedBy: "cloudKitDatabase: .none").count - 1,
            2
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
    func testFutureAndMalformedV2PointersFailBeforeModelStoreInspection() throws {
        let cases: [(String, (UUID) throws -> Data, StoreMigrationFailure)] = [
            (
                "future",
                { generationID in
                    try StoreMigrationCanonicalJSONV1.encode(
                        FuturePointer(schemaVersion: 4)
                    )
                },
                StoreMigrationFailure.maintenanceRequired(.futureVersion)
            ),
            (
                "malformed-v2",
                { generationID in
                    try StoreMigrationCanonicalJSONV1.encode(
                        MalformedV2Pointer(
                            generationID: generationID.uuidString.lowercased(),
                            generationManifestSHA256: "not-a-digest"
                        )
                    )
                },
                StoreMigrationFailure.invalidDigest
            ),
        ]

        for (name, makePointer, expectedError) in cases {
            let root = try makeTemporaryApplicationSupportURL(
                suffix: "Pointer-\(name)"
            )
            defer { try? fileManager.removeItem(at: root) }
            let (factory, generationID, modelURL) = try bootstrapGeneration(at: root)
            try fileManager.removeItem(at: modelURL)
            try makePointer(generationID).write(
                to: currentPointerURL(in: root),
                options: .atomic
            )

            XCTAssertThrowsError(try factory.openOrBootstrapCurrent(), name) { error in
                XCTAssertEqual(error as? StoreMigrationFailure, expectedError, name)
            }
            XCTAssertFalse(fileManager.fileExists(atPath: modelURL.path), name)
        }
    }

    @MainActor
    func testFutureRetiredPointerFailsBeforeModelStoreInspection() throws {
        let root = try makeTemporaryApplicationSupportURL(
            suffix: "RetiredPointer-future"
        )
        defer { try? fileManager.removeItem(at: root) }
        let (factory, _, modelURL) = try bootstrapGeneration(at: root)
        try fileManager.removeItem(at: modelURL)
        try StoreMigrationCanonicalJSONV1.encode(
            FutureRetiredPointer(generationIDs: [], schemaVersion: 4)
        ).write(to: retiredPointerURL(in: root), options: .atomic)

        XCTAssertThrowsError(try factory.openOrBootstrapCurrent()) { error in
            XCTAssertEqual(error as? StoreGenerationFailure, .dataPointerInvalid)
        }
        XCTAssertFalse(fileManager.fileExists(atPath: modelURL.path))
    }

    @MainActor
    func testV3BootstrapAndReopenPersistV2ManifestAndMarker() throws {
        let root = try makeTemporaryApplicationSupportURL(suffix: "V2Bootstrap")
        defer { try? fileManager.removeItem(at: root) }
        let factory = StoreGenerationFactory(applicationSupportURL: root)
        var opened: StoreGenerationSession? = try factory.openOrBootstrapCurrent()
        let generationID = try XCTUnwrap(opened).generationID
        let workspaceID = try XCTUnwrap(opened).workspaceID
        let replicaID = try XCTUnwrap(opened).replicaID
        let pointerData = try Data(contentsOf: currentPointerURL(in: root))
        let pointer = try CurrentGenerationPointerV3.decodeCanonical(from: pointerData)
        XCTAssertEqual(pointer.generationID, generationID.uuidString.lowercased())
        XCTAssertEqual(pointer.schemaVersion, 3)
        XCTAssertEqual(pointer.storeSchemaVersion, 2)
        XCTAssertEqual(
            pointer.workspaceID,
            workspaceID.rawValue.uuidString.lowercased()
        )
        XCTAssertEqual(
            pointer.replicaID,
            replicaID.rawValue.uuidString.lowercased()
        )

        let migrationStore = try StoreMigrationJournalStoreV1(
            applicationSupportURL: root
        )
        let manifest = try migrationStore.loadManifest(
            targetGenerationID: generationID,
            expectedDigest: pointer.generationManifestSHA256
        )
        XCTAssertEqual(manifest.storeSchemaRelease, .v2)
        XCTAssertEqual(manifest.generationID, generationID)
        XCTAssertTrue(manifest.files.contains { $0.relativePath == "model.sqlite" })

        let markers = try XCTUnwrap(opened).modelContext.fetch(
            FetchDescriptor<PersistentSchemaReleaseMarker>()
        )
        let marker = try XCTUnwrap(markers.first)
        XCTAssertEqual(markers.count, 1)
        XCTAssertEqual(marker.id, PersistentSchemaReleaseRegistryV1.v2MarkerID)
        XCTAssertEqual(marker.schemaVersion, 2)
        XCTAssertEqual(
            marker.releaseID,
            PersistentSchemaReleaseRegistryV1.v2CompatibilityID
        )
        XCTAssertEqual(
            marker.predecessorReleaseID,
            PersistentSchemaReleaseRegistryV1.v1CompatibilityID
        )
        XCTAssertNotNil(marker.migrationID)
        let markerMigrationID = marker.migrationID
        opened = nil

        let reopened = try factory.openOrBootstrapCurrent()
        XCTAssertEqual(reopened.generationID, generationID)
        XCTAssertEqual(reopened.workspaceID, workspaceID)
        XCTAssertEqual(reopened.replicaID, replicaID)
        let reopenedMarkers = try reopened.modelContext.fetch(
            FetchDescriptor<PersistentSchemaReleaseMarker>()
        )
        XCTAssertEqual(reopenedMarkers.count, 1)
        XCTAssertEqual(
            try XCTUnwrap(reopenedMarkers.first).migrationID,
            markerMigrationID
        )
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

    private struct FuturePointer: Codable {
        let schemaVersion: Int
    }

    private struct MalformedV2Pointer: Codable {
        let generationID: String
        let generationManifestSHA256: String
        let storeSchemaVersion: Int = 2
        let schemaVersion: Int = 2
    }

    private struct FutureRetiredPointer: Codable {
        let generationIDs: [String]
        let schemaVersion: Int
    }

    private func makeTemporaryApplicationSupportURL(
        suffix: String = UUID().uuidString
    ) throws -> URL {
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "V9_01VersionedSchemaIdentityTests-\(suffix)",
            isDirectory: true
        )
        try? fileManager.removeItem(at: root)
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

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
            .preserveEmptySiteUnlessExplicitlyDeleted,
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

    func testV1ThroughV7RegistryKeepDistinctOrderedSchemas() throws {
        XCTAssertEqual(PersistentSchemaV1.versionIdentifier, Schema.Version(1, 0, 0))
        XCTAssertEqual(PersistentSchemaV2.versionIdentifier, Schema.Version(2, 0, 0))
        XCTAssertEqual(PersistentSchemaV3.versionIdentifier, Schema.Version(3, 0, 0))
        XCTAssertEqual(PersistentSchemaV4.versionIdentifier, Schema.Version(4, 0, 0))
        XCTAssertEqual(PersistentSchemaV5.versionIdentifier, Schema.Version(5, 0, 0))
        XCTAssertEqual(PersistentSchemaV6.versionIdentifier, Schema.Version(6, 0, 0))
        XCTAssertEqual(PersistentSchemaV7.versionIdentifier, Schema.Version(7, 0, 0))
        XCTAssertEqual(
            modelTypeIDs(PersistentSchemaV1.models),
            modelTypeIDs(PersistentModelCatalog.models)
        )
        XCTAssertEqual(PersistentSchemaV1.models.count, 7)
        XCTAssertEqual(PersistentSchemaV2.models.count, 8)
        XCTAssertEqual(PersistentSchemaV3.models.count, 9)
        XCTAssertEqual(PersistentSchemaV4.models.count, 13)
        XCTAssertEqual(PersistentSchemaV5.models.count, 14)
        XCTAssertEqual(PersistentSchemaV6.models.count, 20)
        XCTAssertEqual(PersistentSchemaV7.models.count, 21)
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
        XCTAssertEqual(
            modelTypeIDs(Array(PersistentSchemaV3.models.dropLast())),
            modelTypeIDs(PersistentSchemaV2.models)
        )
        XCTAssertEqual(
            modelTypeIDs(PersistentSchemaV3.models).last,
            ObjectIdentifier(DeletionLedgerRow.self)
        )
        XCTAssertEqual(
            modelTypeIDs(Array(PersistentSchemaV4.models.dropLast(4))),
            modelTypeIDs(PersistentSchemaV3.models)
        )
        XCTAssertEqual(
            modelTypeIDs(Array(PersistentSchemaV4.models.suffix(4))),
            [
                ObjectIdentifier(MutationReceiptRow.self),
                ObjectIdentifier(MutationQuarantineRow.self),
                ObjectIdentifier(WorkspaceMutationStateRow.self),
                ObjectIdentifier(EntityMutationRevisionRow.self),
            ]
        )
        XCTAssertEqual(
            modelTypeIDs(Array(PersistentSchemaV5.models.dropLast())),
            modelTypeIDs(PersistentSchemaV4.models)
        )
        XCTAssertEqual(
            modelTypeIDs(PersistentSchemaV5.models).last,
            ObjectIdentifier(ObservationAndTimeRow.self)
        )
        XCTAssertNotEqual(
            modelTypeIDs(PersistentSchemaV5.models),
            modelTypeIDs(PersistentSchemaV4.models)
        )
        XCTAssertEqual(
            modelTypeIDs(Array(PersistentSchemaV6.models.dropLast(6))),
            modelTypeIDs(PersistentSchemaV5.models)
        )
        XCTAssertEqual(
            modelTypeIDs(Array(PersistentSchemaV6.models.suffix(6))),
            [
                ObjectIdentifier(LocationNodeRow.self),
                ObjectIdentifier(LocationHierarchyEventRow.self),
                ObjectIdentifier(AssetPlacementEventRow.self),
                ObjectIdentifier(AssetCompositionEdgeRow.self),
                ObjectIdentifier(AssetCompositionEventRow.self),
                ObjectIdentifier(LocationMigrationReceiptRow.self),
            ]
        )
        XCTAssertEqual(
            modelTypeIDs(Array(PersistentSchemaV7.models.dropLast())),
            modelTypeIDs(PersistentSchemaV6.models)
        )
        XCTAssertEqual(
            modelTypeIDs(PersistentSchemaV7.models).last,
            ObjectIdentifier(SavedSmartViewRowV1.self)
        )
        XCTAssertEqual(
            PersistentSchemaReleaseRegistryV1.releases,
            [.v1, .v2, .v3, .v4, .v5, .v6, .v7]
        )
        XCTAssertEqual(PersistentSchemaReleaseRegistryV1.activeRelease, .v7)
        XCTAssertEqual(
            PersistentSchemaReleaseRegistryV1.activeVersionIdentifier,
            PersistentSchemaV7.versionIdentifier
        )
        XCTAssertEqual(
            PersistentSchemaReleaseRegistryV1.activeCompatibilityID,
            PersistentSchemaReleaseRegistryV1.v7CompatibilityID
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
        XCTAssertEqual(
            PersistentSchemaMigrationPlanV2.schemas.map { ObjectIdentifier($0) },
            [
                ObjectIdentifier(PersistentSchemaV2.self),
                ObjectIdentifier(PersistentSchemaV3.self),
            ]
        )
        XCTAssertEqual(PersistentSchemaMigrationPlanV2.stages.count, 1)
        XCTAssertEqual(
            PersistentSchemaMigrationPlanV3.schemas.map { ObjectIdentifier($0) },
            [
                ObjectIdentifier(PersistentSchemaV3.self),
                ObjectIdentifier(PersistentSchemaV4.self),
            ]
        )
        XCTAssertEqual(PersistentSchemaMigrationPlanV3.stages.count, 1)
        XCTAssertEqual(
            PersistentSchemaMigrationPlanV4.schemas.map { ObjectIdentifier($0) },
            [
                ObjectIdentifier(PersistentSchemaV4.self),
                ObjectIdentifier(PersistentSchemaV5.self),
            ]
        )
        XCTAssertEqual(PersistentSchemaMigrationPlanV4.stages.count, 1)
        XCTAssertEqual(
            PersistentSchemaMigrationPlanV5.schemas.map { ObjectIdentifier($0) },
            [
                ObjectIdentifier(PersistentSchemaV5.self),
                ObjectIdentifier(PersistentSchemaV6.self),
            ]
        )
        XCTAssertEqual(PersistentSchemaMigrationPlanV5.stages.count, 1)
        XCTAssertEqual(
            PersistentSchemaMigrationPlanV6.schemas.map { ObjectIdentifier($0) },
            [
                ObjectIdentifier(PersistentSchemaV6.self),
                ObjectIdentifier(PersistentSchemaV7.self),
            ]
        )
        XCTAssertEqual(PersistentSchemaMigrationPlanV6.stages.count, 1)
        XCTAssertEqual(PersistentSchemaReleaseV1.v4.migrationStage, .lightweight)
        XCTAssertEqual(PersistentSchemaReleaseV1.v5.migrationStage, .custom)
        XCTAssertEqual(PersistentSchemaReleaseV1.v6.migrationStage, .custom)
        XCTAssertEqual(PersistentSchemaReleaseV1.v7.migrationStage, .custom)

        let factorySource = try sourceText(
            "FieldEvidenceApp/Infrastructure/Persistence/StoreGenerationFactory.swift"
        )
        XCTAssertTrue(factorySource.contains("PersistentSchemaV1.makeSchema()"))
        XCTAssertTrue(factorySource.contains("migrationPlan: nil"))
        XCTAssertTrue(factorySource.contains("PersistentSchemaV2"))
        XCTAssertTrue(factorySource.contains("PersistentSchemaV3"))
        XCTAssertTrue(factorySource.contains("PersistentSchemaV4"))
        XCTAssertTrue(factorySource.contains("PersistentSchemaV5"))
        XCTAssertTrue(factorySource.contains("PersistentSchemaV6"))
        XCTAssertTrue(factorySource.contains("PersistentSchemaV7"))
        XCTAssertTrue(factorySource.contains("PersistentSchemaReleaseMarker"))
        XCTAssertTrue(factorySource.contains("migrationPlan: PersistentSchemaMigrationPlanV1.self"))
        XCTAssertTrue(factorySource.contains("migrationPlan: PersistentSchemaMigrationPlanV4.self"))
        XCTAssertTrue(factorySource.contains("migrationPlan: PersistentSchemaMigrationPlanV5.self"))
        XCTAssertTrue(factorySource.contains("migrationPlan: PersistentSchemaMigrationPlanV6.self"))
        XCTAssertEqual(
            factorySource.components(separatedBy: "cloudKitDatabase: .none").count - 1,
            7
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

    func testDeletionLedgerV2IsClosedSortedTypedAndAppendOnlyByUnion() throws {
        XCTAssertEqual(
            DeletionRecordKindV2.allCases,
            [.site, .asset, .workflowRecord, .evidenceFile, .issue, .packet, .report]
        )
        XCTAssertEqual(DeletionLedgerV2.maximumEntryCount, 100_000)
        XCTAssertNil(DeletionRecordKindV2(rawValue: "tag"))

        let id = fixedUUID("00000000-0000-0000-0000-000000000101")
        let identity = try DeletionIdentityV2(kind: .packet, id: id)
        XCTAssertEqual(identity.typedID, "packet:00000000-0000-0000-0000-000000000101")
        XCTAssertEqual(try DeletionIdentityV2(typedID: identity.typedID), identity)

        let later = try DeletionLedgerEntryV2(
            identity: identity,
            deletedAt: Date(timeIntervalSince1970: 20)
        )
        let earlier = try DeletionLedgerEntryV2(
            identity: identity,
            deletedAt: Date(timeIntervalSince1970: 10)
        )
        let union = try DeletionLedgerV2(entries: [later]).union(
            DeletionLedgerV2(entries: [earlier])
        )
        XCTAssertEqual(union.entries, [earlier])
        XCTAssertEqual(try union.canonicalData(), try union.canonicalData())
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
    func testV4BootstrapAndReopenPersistV4ManifestAndMarker() throws {
        let root = try makeTemporaryApplicationSupportURL(suffix: "V5Bootstrap")
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
        XCTAssertEqual(pointer.storeSchemaVersion, 6)
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
        XCTAssertEqual(manifest.storeSchemaRelease, .v7)
        XCTAssertEqual(manifest.generationID, generationID)
        XCTAssertTrue(manifest.files.contains { $0.relativePath == "model.sqlite" })

        let markers = try XCTUnwrap(opened).modelContext.fetch(
            FetchDescriptor<PersistentSchemaReleaseMarker>()
        )
        let marker = try XCTUnwrap(markers.first)
        XCTAssertEqual(markers.count, 1)
        XCTAssertEqual(marker.id, PersistentSchemaReleaseRegistryV1.v2MarkerID)
        XCTAssertEqual(marker.schemaVersion, 7)
        XCTAssertEqual(
            marker.releaseID,
            PersistentSchemaReleaseRegistryV1.v7CompatibilityID
        )
        XCTAssertEqual(
            marker.predecessorReleaseID,
            PersistentSchemaReleaseRegistryV1.v6CompatibilityID
        )
        XCTAssertNotNil(marker.migrationID)
        let markerMigrationID = marker.migrationID
        let siteID = fixedUUID("00000000-0000-0000-0000-000000000491")
        let assetID = fixedUUID("00000000-0000-0000-0000-000000000492")
        let mutationID = try MutationIDV1(
            rawValue: fixedUUID("00000000-0000-0000-0000-000000000493")
        )
        let placementEventID = fixedUUID("00000000-0000-0000-0000-000000000494")
        let physicalEpisodeID = try PhysicalPlacementEpisodeIDV1(
            rawValue: fixedUUID("00000000-0000-0000-0000-000000000495")
        )
        var coordinator: StoreSessionCoordinator? = StoreSessionCoordinator(
            session: try XCTUnwrap(opened)
        )
        let revision = try XCTUnwrap(coordinator).workspaceWriter.currentRevision()
        let expected = try WorkspaceExpectedRevisionV1(
            workspaceID: revision.workspaceID,
            generationID: revision.generationID,
            writerInstanceID: revision.writerInstanceID,
            workspaceRevision: revision.revision,
            entityRevisions: [
                .init(
                    identity: try WorkspaceEntityIdentityV1(kind: .site, id: siteID),
                    revision: 0
                ),
                .init(
                    identity: try WorkspaceEntityIdentityV1(kind: .asset, id: assetID),
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
        _ = try XCTUnwrap(coordinator).workspaceWriter.execute(.init(
            mutationID: mutationID,
            expectedRevision: expected,
            command: .createFirstSign(.init(
                siteID: siteID,
                newSite: .init(id: siteID, label: "V5 relaunch", address: nil, timeZoneID: "UTC"),
                assetID: assetID,
                assetLabel: "V5 asset",
                packID: "v5.test.pack",
                packSchemaVersion: 1,
                packContentVersion: 1,
                createdAt: Date(timeIntervalSince1970: 1_800_004_900),
                initialPlacementMutationID: mutationID,
                initialPlacementEventID: placementEventID,
                initialPhysicalEpisodeID: physicalEpisodeID
            ))
        ))
        XCTAssertNotNil(
            try XCTUnwrap(coordinator).workspaceWriter.durableReceipt(mutationID: mutationID)
        )
        coordinator = nil
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
        let reopenedJournal = try MutationJournalStoreV1(
            modelContext: reopened.modelContext,
            identity: .init(workspaceID: workspaceID, replicaID: replicaID),
            generationID: generationID,
            allowStateBootstrap: false
        )
        XCTAssertNotNil(try reopenedJournal.receipt(mutationID: mutationID))
        XCTAssertNoThrow(
            try MutationReceiptRecoveryServiceV1(store: reopenedJournal)
                .recoverBeforeWriterActivation()
        )

        let persistedSite = try XCTUnwrap(reopened.modelContext.fetch(
            FetchDescriptor<Site>(predicate: #Predicate { $0.id == siteID })
        ).first)
        persistedSite.label = "Semantically corrupted after receipt"
        try reopened.modelContext.save()
        XCTAssertThrowsError(
            try MutationReceiptRecoveryServiceV1(store: reopenedJournal)
                .recoverBeforeWriterActivation()
        ) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .receiptHistoryCorrupt)
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

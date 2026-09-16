import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

@MainActor
final class V23StoreSemanticValidationTests: XCTestCase {
    func testCurrentV53ValidationTraversesEveryLayerWithoutRetainingPredecessorBytesAndColdReopens() throws {
        let root = temporaryRoot("Traversal")
        let support = applicationSupport(in: root)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let lighting = try SemanticValidationLighting.makeFixture(slot: 53)
        let pointerURL = currentPointerURL(in: support)
        let facts = try autoreleasepool { () throws -> SemanticValidationStoreFacts in
            let factory = StoreGenerationFactory(
                applicationSupportURL: support,
                pointerEnrichmentIdentity: try workspaceIdentity(lighting.night.workspaceID)
            )
            let active = try semanticObserved("traversal open current store") {
                try factory.openOrBootstrapCurrent()
            }
            let persisted = try semanticObserved("traversal populate current store") {
                try populateCurrentStore(active, lighting: lighting)
            }
            let modelURL = active.generationRootURL.appendingPathComponent("model.sqlite")
            let pointerBefore = try Data(contentsOf: pointerURL)
            let storeBefore = try Data(contentsOf: modelURL)
            let locationBefore = persisted.location.canonicalData
            let nightBefore = persisted.night.canonicalData
            let receiptsBefore = try receiptBytes(in: active.modelContext)
            XCTAssertGreaterThan(receiptsBefore.count, 0)
            XCTAssertTrue(receiptsBefore.allSatisfy {
                $0.workspaceID == active.workspaceIdentity.workspaceID.rawValue &&
                $0.replicaID == active.workspaceIdentity.replicaID.rawValue &&
                $0.localSequence > 0 && !$0.envelope.isEmpty && !$0.receipt.isEmpty
            })
            var traversal: [Data] = []
            try semanticObserved("validate current semantic traversal") {
                try factory.validateSemanticRowsForTesting(
                    in: active.modelContext, through: PersistentSchemaReleaseRegistryV1.activeRelease
                ) { traversal.append($0) }
            }
            try assertValidationTraversal(traversal, location: locationBefore, night: lighting.night)
            XCTAssertFalse(active.modelContext.hasChanges)
            XCTAssertEqual(persisted.location.canonicalData, locationBefore)
            XCTAssertEqual(persisted.night.canonicalData, nightBefore)
            XCTAssertEqual(try receiptBytes(in: active.modelContext), receiptsBefore)
            XCTAssertEqual(try Data(contentsOf: pointerURL), pointerBefore)
            XCTAssertEqual(try Data(contentsOf: modelURL), storeBefore)
            return SemanticValidationStoreFacts(generationID: active.generationID,
                generationRoot: active.generationRootURL, pointer: pointerBefore,
                location: locationBefore, night: nightBefore, receipts: receiptsBefore,
                traversalCount: traversal.count)
        }
        try autoreleasepool { () throws -> Void in
            let factory = StoreGenerationFactory(applicationSupportURL: support)
            let cold = try semanticObserved("traversal cold open") { try factory.openOrBootstrapCurrent() }
            XCTAssertEqual(cold.generationID, facts.generationID)
            XCTAssertEqual(cold.storeSchemaRelease, .v53)
            let modelURL = facts.generationRoot.appendingPathComponent("model.sqlite")
            let storeBefore = try Data(contentsOf: modelURL)
            var traversal: [Data] = []
            try factory.validateSemanticRowsForTesting(in: cold.modelContext, through: .v53) {
                traversal.append($0)
            }
            try assertValidationTraversal(traversal, location: facts.location, night: lighting.night)
            XCTAssertEqual(traversal.count, facts.traversalCount)
            XCTAssertEqual(try XCTUnwrap(cold.modelContext.fetch(FetchDescriptor<LocationNodeRow>()).first).canonicalData, facts.location)
            XCTAssertEqual(try XCTUnwrap(cold.modelContext.fetch(FetchDescriptor<LightingNightWorkflowRowV1>()).first).canonicalData, facts.night)
            XCTAssertEqual(try receiptBytes(in: cold.modelContext), facts.receipts)
            XCTAssertEqual(try Data(contentsOf: pointerURL), facts.pointer)
            XCTAssertEqual(try Data(contentsOf: modelURL), storeBefore)
            XCTAssertFalse(cold.modelContext.hasChanges)
            let laterLocation = try LocationNodeV1(
                id: semanticID(702),
                workspaceID: lighting.night.workspaceID,
                siteID: lighting.system.siteID,
                parentNodeID: nil,
                kind: .building,
                label: "Unadopted semantic validation building",
                shortCode: "UV",
                siblingOrder: 1,
                state: .active,
                revision: 1,
                provenance: .init(
                    mutationID: try MutationIDV1(rawValue: semanticID(703)),
                    occurredAt: lighting.night.recordedAt.addingTimeInterval(200)
                )
            )
            cold.modelContext.insert(try LocationNodeRow(laterLocation))
            try cold.modelContext.save()
            XCTAssertThrowsError(try cold.reproofAfterSave()) {
                XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .receiptHistoryCorrupt)
            }
            XCTAssertEqual(try receiptBytes(in: cold.modelContext), facts.receipts)
            XCTAssertFalse(cold.modelContext.hasChanges)
        }
        try FileManager.default.removeItem(at: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testEarlyAndLatestCanonicalRowCorruptionKeepTypedFailureAndColdOpenTargetMismatchWithoutRepair() throws {
        try assertCorruptionFailsClosed(.location)
        try assertCorruptionFailsClosed(.nightWorkflow)
    }

    func testLowReleaseCanonicalProjectionsRetainExactNestedPredecessorBytes() throws {
        let schema = try PersistentSchemaReleaseRegistryV1.activeSchema()
        let container = try ModelContainer(
            for: schema,
            migrationPlan: nil,
            configurations: [ModelConfiguration(
                "V23SemanticLowReleaseFacts",
                schema: schema,
                isStoredInMemoryOnly: true,
                allowsSave: true,
                cloudKitDatabase: .none
            )]
        )
        let context = container.mainContext
        let factory = StoreGenerationFactory(applicationSupportURL: temporaryRoot("LowRelease"))

        let fixture = try SemanticValidationLighting.makeFixture(slot: 70)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let siteID = semanticID(810)
        context.insert(Site(id: siteID, label: "Frozen low-release site", address: nil,
                            timeZoneID: "UTC", createdAt: date, updatedAt: date))
        let deletion = try DeletionLedgerEntryV2(
            identity: .init(kind: .asset, id: semanticID(811)), deletedAt: date)
        try DeletionLedgerStore(context: context).stageUnion([deletion])
        let location = try LocationNodeV1(id: semanticID(812), workspaceID: fixture.night.workspaceID,
            siteID: siteID, parentNodeID: nil, kind: .building, label: "Frozen low-release building",
            shortCode: "LOW", siblingOrder: 0, state: .active, revision: 1,
            provenance: .init(mutationID: .init(rawValue: semanticID(813)), occurredAt: date))
        context.insert(try LocationNodeRow(location))
        try context.save()
        let locationBytes = try LocationPersistenceCodecV1.encode(location)
        let frozenRecords = V4BackupRecordsV1(
            assets: [], evidenceFiles: [], issues: [], packets: [],
            recordsSchemaVersion: 1, reports: [], sites: [V4BackupSiteDTO(
                id: siteID, schemaVersion: 1, label: "Frozen low-release site", address: nil,
                timeZoneID: "UTC", createdAt: date, updatedAt: date)], workflowRecords: []
        )
        let records = try BackupCanonicalEncoderV1().encodeRecords(frozenRecords).data
        let ledger = try DeletionLedgerV2(entries: [deletion]).canonicalData()
        let expectedV3 = try StoreMigrationCanonicalJSONV1.encode(
            ExpectedSemanticEnvelopeV3(records: records, deletionLedger: ledger)
        )
        let expectedV4 = try StoreMigrationCanonicalJSONV1.encode(
            ExpectedSemanticEnvelopeV4(
                base: expectedV3, receipts: [], quarantines: [], states: [], entityRevisions: []
            )
        )
        let expectedV5 = try StoreMigrationCanonicalJSONV1.encode(
            ExpectedSemanticEnvelopeV5(base: expectedV4, observationAndTime: [])
        )
        let expectedV6 = try StoreMigrationCanonicalJSONV1.encode(
            ExpectedSemanticEnvelopeV6(
                base: expectedV5, locationNodes: [locationBytes], hierarchyEvents: [],
                placementEvents: [], compositionEdges: [], compositionEvents: [],
                migrationReceipts: []
            )
        )

        let actualV3 = try factory.canonicalSemanticProjectionForTesting(in: context, release: .v3)
        let actualV4 = try factory.canonicalSemanticProjectionForTesting(in: context, release: .v4)
        let actualV5 = try factory.canonicalSemanticProjectionForTesting(in: context, release: .v5)
        let actualV6 = try factory.canonicalSemanticProjectionForTesting(in: context, release: .v6)
        XCTAssertEqual(actualV3, expectedV3)
        XCTAssertEqual(actualV4, expectedV4)
        XCTAssertEqual(actualV5, expectedV5)
        XCTAssertEqual(actualV6, expectedV6)
        XCTAssertEqual(try decodedBase(actualV4), actualV3)
        XCTAssertEqual(try decodedBase(actualV5), actualV4)
        XCTAssertEqual(try decodedBase(actualV6), actualV5)
        let v6 = try JSONDecoder().decode(ObservedSemanticLocationEnvelope.self, from: actualV6)
        XCTAssertEqual(v6.locationNodes, [locationBytes])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Site>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<LocationNodeRow>()), 1)

        let v3Object = try jsonObject(actualV3)
        XCTAssertEqual(Set(v3Object.keys), ["records", "deletionLedger"])
        XCTAssertEqual(try decodedData(v3Object, key: "records"), records)
        XCTAssertEqual(try decodedData(v3Object, key: "deletionLedger"), ledger)
        XCTAssertFalse(context.hasChanges)
    }

    private enum CorruptionKind: String {
        case location
        case nightWorkflow
    }

    private func assertCorruptionFailsClosed(
        _ kind: CorruptionKind,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let root = temporaryRoot("Corrupt-\(kind.rawValue)")
        let support = applicationSupport(in: root)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let lighting = try SemanticValidationLighting.makeFixture(slot: kind == .location ? 61 : 62)
        defer { try? FileManager.default.removeItem(at: root) }
        let pointerURL = currentPointerURL(in: support)
        let corrupt = try autoreleasepool { () throws -> SemanticValidationCorruptFacts in
            let factory = StoreGenerationFactory(
                applicationSupportURL: support,
                pointerEnrichmentIdentity: try workspaceIdentity(lighting.night.workspaceID)
            )
            let active = try semanticObserved("\(kind.rawValue) open corruption fixture") {
                try factory.openOrBootstrapCurrent()
            }
            let persisted = try semanticObserved("\(kind.rawValue) populate corruption fixture") {
                try populateCurrentStore(active, lighting: lighting)
            }
            let pointerBefore = try Data(contentsOf: pointerURL)
            let receiptsBefore = try receiptBytes(in: active.modelContext)
            XCTAssertGreaterThan(receiptsBefore.count, 0, file: file, line: line)
            let originalBytes: Data
            switch kind {
            case .location:
                originalBytes = persisted.location.canonicalData
                let original = try persisted.location.value()
                let divergent = try LocationNodeV1(
                    id: original.id,
                    workspaceID: original.workspaceID,
                    siteID: original.siteID,
                    parentNodeID: original.parentNodeID,
                    kind: original.kind,
                    label: "Divergent canonical location",
                    shortCode: original.shortCode,
                    siblingOrder: original.siblingOrder,
                    state: original.state,
                    revision: original.revision,
                    provenance: original.provenance
                )
                persisted.location.canonicalData = try LocationPersistenceCodecV1.encode(divergent)
                try active.modelContext.save()
                XCTAssertThrowsError(try persisted.location.value(), file: file, line: line) {
                    XCTAssertEqual($0 as? LocationContractFailureV1, .digestMismatch, file: file, line: line)
                }
            case .nightWorkflow:
                originalBytes = persisted.night.canonicalData
                let original = lighting.night
                let divergent = try LightingNightWorkflowV1(
                    recordID: semanticID(900),
                    workflowID: original.workflowID,
                    workspaceID: original.workspaceID,
                    system: lighting.system,
                    dayWorkflow: lighting.plannedDay,
                    safety: original.safety,
                    deltas: original.deltas,
                    repairPolicy: original.repairPolicy,
                    repairs: original.repairs,
                    rechecks: original.rechecks,
                    reopens: original.reopens,
                    rootCauseGroups: original.rootCauseGroups,
                    patrol: original.patrol,
                    claims: original.claims,
                    state: original.state,
                    revision: original.revision,
                    mutationID: original.mutationID,
                    recordedBy: original.recordedBy,
                    recordedAt: original.recordedAt
                )
                persisted.night.canonicalData = try LightingCanonicalCodecV1.encode(divergent)
                try active.modelContext.save()
                XCTAssertThrowsError(try persisted.night.value(), file: file, line: line) {
                    guard let failure = $0 as? LightingPersistenceFailureV1 else {
                        return XCTFail("Expected LightingPersistenceFailureV1.corruptRow, got \($0)", file: file, line: line)
                    }
                    switch failure {
                    case .corruptRow: break
                    }
                }
            }
            XCTAssertThrowsError(try factory.validateSemanticRowsForTesting(
                in: active.modelContext, through: .v53, didEncode: { _ in }
            ), file: file, line: line) { error in
                switch kind {
                case .location:
                    XCTAssertEqual(error as? LocationContractFailureV1, .digestMismatch, file: file, line: line)
                case .nightWorkflow:
                    guard let failure = error as? LightingPersistenceFailureV1 else {
                        return XCTFail("Expected traversal LightingPersistenceFailureV1.corruptRow, got \(error)", file: file, line: line)
                    }
                    switch failure { case .corruptRow: break }
                }
            }
            XCTAssertFalse(active.modelContext.hasChanges)
            XCTAssertEqual(try receiptBytes(in: active.modelContext), receiptsBefore, file: file, line: line)
            XCTAssertEqual(try Data(contentsOf: pointerURL), pointerBefore, file: file, line: line)
            return SemanticValidationCorruptFacts(generationRoot: active.generationRootURL,
                pointer: pointerBefore, original: originalBytes,
                corrupted: kind == .location ? persisted.location.canonicalData : persisted.night.canonicalData,
                location: kind == .location ? originalBytes : persisted.location.canonicalData,
                night: kind == .nightWorkflow ? originalBytes : persisted.night.canonicalData,
                receipts: receiptsBefore)
        }
        try autoreleasepool { () throws -> Void in
            let factory = StoreGenerationFactory(applicationSupportURL: support)
            XCTAssertThrowsError(try factory.openOrBootstrapCurrent(), file: file, line: line) {
                XCTAssertEqual($0 as? StoreMigrationFailure, .maintenanceRequired(.targetMismatch),
                               file: file, line: line)
            }
        }
        XCTAssertEqual(try Data(contentsOf: pointerURL), corrupt.pointer, file: file, line: line)
        try autoreleasepool { () throws -> Void in
            let repairContainer = try currentContainer(at: corrupt.generationRoot)
            let repairContext = repairContainer.mainContext
            XCTAssertFalse(repairContext.hasChanges, file: file, line: line)
            XCTAssertEqual(try receiptBytes(in: repairContext), corrupt.receipts, file: file, line: line)
            switch kind {
            case .location:
                let row = try XCTUnwrap(repairContext.fetch(FetchDescriptor<LocationNodeRow>()).first,
                                        file: file, line: line)
                XCTAssertEqual(row.canonicalData, corrupt.corrupted, file: file, line: line)
                XCTAssertNotEqual(row.canonicalData, corrupt.original, file: file, line: line)
                row.canonicalData = corrupt.original
            case .nightWorkflow:
                let row = try XCTUnwrap(repairContext.fetch(FetchDescriptor<LightingNightWorkflowRowV1>()).first,
                                        file: file, line: line)
                XCTAssertEqual(row.canonicalData, corrupt.corrupted, file: file, line: line)
                XCTAssertNotEqual(row.canonicalData, corrupt.original, file: file, line: line)
                row.canonicalData = corrupt.original
            }
            try repairContext.save()
        }
        try autoreleasepool { () throws -> Void in
            let factory = StoreGenerationFactory(applicationSupportURL: support)
            let cold = try semanticObserved("\(kind.rawValue) cold reopen repaired original") {
                try factory.openOrBootstrapCurrent()
            }
            var traversal: [Data] = []
            try factory.validateSemanticRowsForTesting(in: cold.modelContext, through: .v53) {
                traversal.append($0)
            }
            try assertValidationTraversal(traversal, location: corrupt.location, night: lighting.night,
                                          file: file, line: line)
            XCTAssertEqual(try XCTUnwrap(cold.modelContext.fetch(FetchDescriptor<LocationNodeRow>()).first).canonicalData,
                           corrupt.location, file: file, line: line)
            XCTAssertEqual(try XCTUnwrap(cold.modelContext.fetch(FetchDescriptor<LightingNightWorkflowRowV1>()).first).canonicalData,
                           corrupt.night, file: file, line: line)
            XCTAssertEqual(try receiptBytes(in: cold.modelContext), corrupt.receipts, file: file, line: line)
            XCTAssertEqual(try Data(contentsOf: pointerURL), corrupt.pointer, file: file, line: line)
            XCTAssertFalse(cold.modelContext.hasChanges, file: file, line: line)
        }
        try FileManager.default.removeItem(at: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path), file: file, line: line)
    }

    private func populateCurrentStore(
        _ session: StoreGenerationSession,
        lighting: SemanticValidationLighting.Fixture
    ) throws -> (location: LocationNodeRow, night: LightingNightWorkflowRowV1) {
        let context = session.modelContext
        let assetID = try XCTUnwrap(lighting.night.deltas.first).assetID
        let locationValue = try LocationNodeV1(
            id: semanticID(700),
            workspaceID: lighting.night.workspaceID,
            siteID: lighting.system.siteID,
            parentNodeID: nil,
            kind: .building,
            label: "Semantic validation building",
            shortCode: "SV",
            siblingOrder: 0,
            state: .active,
            revision: 1,
            provenance: .init(
                mutationID: try MutationIDV1(rawValue: semanticID(701)),
                occurredAt: lighting.night.recordedAt.addingTimeInterval(-200)
            )
        )
        let location = try LocationNodeRow(locationValue)
        let night = try LightingNightWorkflowRowV1(lighting.night)
        context.insert(location)
        context.insert(night)
        try semanticObserved("adopt semantic fixture deletion baseline") {
            try V906Integration.adoptSeededDeletionBaseline(session)
        }
        do {
            let coordinator = try semanticObserved("activate semantic fixture writer") {
                try StoreSessionCoordinator(validatingSession: session)
            }
            do {
                let mutation = try MutationIDV1(rawValue: semanticID(690))
                _ = try coordinator.workspaceWriter.execute(.createFirstSign(.init(
                    siteID: lighting.system.siteID,
                    newSite: .init(id: lighting.system.siteID, label: "Semantic validation site",
                                   address: nil, timeZoneID: "UTC"),
                    assetID: assetID, assetLabel: "Semantic validation asset",
                    packID: SignPack.illuminatedSignV1.packID,
                    packSchemaVersion: SignPack.illuminatedSignV1.schemaVersion,
                    packContentVersion: SignPack.illuminatedSignV1.contentVersion,
                    createdAt: lighting.night.recordedAt.addingTimeInterval(-300),
                    initialPlacementMutationID: mutation, initialPlacementEventID: semanticID(691),
                    initialPhysicalEpisodeID: .init(rawValue: semanticID(692))
                )), mutationID: mutation)
            } catch {
                semanticReportFailure("create semantic fixture sign", error: error)
                do { try coordinator.invalidateAndReleaseWriter() }
                catch { XCTFail("Semantic fixture writer release failed: \(error)") }
                throw error
            }
            try semanticObserved("release semantic fixture writer") {
                try coordinator.invalidateAndReleaseWriter()
            }
        }
        try semanticObserved("reprove semantic fixture session") { try session.reproofAfterSave() }
        XCTAssertEqual(session.storeSchemaRelease, .v53)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Site>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Asset>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<LocationNodeRow>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<LightingNightWorkflowRowV1>()), 1)
        return (location, night)
    }

    private func assertValidationTraversal(
        _ observations: [Data],
        location: Data,
        night: LightingNightWorkflowV1,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(observations.count, 51, file: file, line: line)
        guard observations.count == 51 else { return }
        let v6 = try JSONDecoder().decode(ObservedSemanticLocationEnvelope.self, from: observations[3])
        XCTAssertEqual(v6.locationNodes, [location], file: file, line: line)
        let v53 = try JSONDecoder().decode(ObservedSemanticNightEnvelope.self, from: observations[50])
        XCTAssertEqual(v53.rows.count, 1, file: file, line: line)
        XCTAssertEqual(try LightingCanonicalCodecV1.encode(v53.rows),
                       try LightingCanonicalCodecV1.encode([night]), file: file, line: line)
        let v3 = try jsonObject(observations[0])
        XCTAssertNil(v3["base"], file: file, line: line)
        XCTAssertEqual(Set(v3.keys), ["records", "deletionLedger"], file: file, line: line)
        for (offset, bytes) in observations.dropFirst().enumerated() {
            let object = try jsonObject(bytes)
            XCTAssertEqual(
                try decodedData(object, key: "base"),
                Data(),
                "V\(offset + 4) retained predecessor bytes",
                file: file,
                line: line
            )
        }
    }

    private func receiptBytes(in context: ModelContext) throws -> [SemanticValidationReceiptBytes] {
        try context.fetch(FetchDescriptor<MutationReceiptRow>())
            .map {
                SemanticValidationReceiptBytes(
                    identity: $0.receiptIdentity, mutationID: $0.mutationID,
                    workspaceMutationKey: $0.workspaceMutationKey, workspaceID: $0.workspaceID,
                    replicaID: $0.replicaID, localSequence: $0.localSequence, commandKind: $0.commandKind,
                    envelope: $0.envelopeData, envelopeSHA256: $0.envelopeSHA256,
                    receipt: $0.receiptData, receiptSHA256: $0.receiptSHA256,
                    reversalBasis: $0.reversalBasisData, reversalBasisSHA256: $0.reversalBasisSHA256,
                    semanticReversal: $0.semanticReversalData
                )
            }
            .sorted { $0.identity < $1.identity }
    }

    private func decodedBase(_ data: Data) throws -> Data {
        try decodedData(jsonObject(data), key: "base")
    }

    private func decodedData(_ object: [String: Any], key: String) throws -> Data {
        let encoded = try XCTUnwrap(object[key] as? String)
        return try XCTUnwrap(Data(base64Encoded: encoded))
    }

    private func jsonObject(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func currentContainer(at generationRoot: URL) throws -> ModelContainer {
        let schema = try PersistentSchemaReleaseRegistryV1.activeSchema()
        return try ModelContainer(
            for: schema,
            migrationPlan: nil,
            configurations: [ModelConfiguration(
                "V23SemanticRepair",
                schema: schema,
                url: generationRoot.appendingPathComponent("model.sqlite", isDirectory: false),
                allowsSave: true,
                cloudKitDatabase: .none
            )]
        )
    }

    private func workspaceIdentity(_ workspaceID: WorkspaceID) throws -> WorkspaceReplicaIdentityV1 {
        try WorkspaceReplicaIdentityV1(
            workspaceID: workspaceID,
            replicaID: ReplicaID(rawValue: semanticID(50))
        )
    }

    private func temporaryRoot(_ suffix: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "V23StoreSemanticValidation-\(suffix)-\(UUID().uuidString)",
            isDirectory: true
        )
    }

    private func applicationSupport(in root: URL) -> URL {
        root.appendingPathComponent("Library/Application Support", isDirectory: true)
    }

    private func currentPointerURL(in support: URL) -> URL {
        support.appendingPathComponent("FieldEvidenceData/current.json", isDirectory: false)
    }

    private func semanticID(_ suffix: Int) -> UUID {
        UUID(uuidString: String(format: "53530000-0000-4000-8000-%012x", suffix))!
    }
}

@MainActor
private func semanticObserved<Value>(
    _ phase: String, file: StaticString = #filePath, line: UInt = #line,
    _ operation: () throws -> Value
) rethrows -> Value {
    do { return try operation() }
    catch {
        semanticReportFailure(phase, error: error, file: file, line: line)
        throw error
    }
}

@MainActor
private func semanticReportFailure(
    _ phase: String, error: Error, file: StaticString = #filePath, line: UInt = #line
) {
    let value = error as NSError
    XCTFail("Semantic fixture failure phase=\(phase) type=\(String(reflecting: type(of: error)))"
        + " value=\(String(reflecting: error)) domain=\(value.domain) code=\(value.code)",
        file: file, line: line)
}

private struct SemanticValidationStoreFacts {
    let generationID: UUID
    let generationRoot: URL
    let pointer: Data
    let location: Data
    let night: Data
    let receipts: [SemanticValidationReceiptBytes]
    let traversalCount: Int
}

private struct SemanticValidationCorruptFacts {
    let generationRoot: URL
    let pointer: Data
    let original: Data
    let corrupted: Data
    let location: Data
    let night: Data
    let receipts: [SemanticValidationReceiptBytes]
}

private struct ObservedSemanticLocationEnvelope: Decodable {
    let base: Data
    let locationNodes: [Data]
}

private struct ObservedSemanticNightEnvelope: Decodable {
    let base: Data
    let rows: [LightingNightWorkflowV1]
}

private struct ExpectedSemanticEnvelopeV3: Encodable {
    let records: Data
    let deletionLedger: Data
}

private struct SemanticValidationReceiptBytes: Equatable {
    let identity: String
    let mutationID: UUID
    let workspaceMutationKey: String
    let workspaceID: UUID
    let replicaID: UUID
    let localSequence: Int64
    let commandKind: String
    let envelope: Data
    let envelopeSHA256: String
    let receipt: Data
    let receiptSHA256: String
    let reversalBasis: Data?
    let reversalBasisSHA256: String?
    let semanticReversal: Data?
}

private struct ExpectedSemanticEnvelopeV4: Encodable {
    let base: Data
    let receipts: [String]
    let quarantines: [String]
    let states: [String]
    let entityRevisions: [String]
}

private struct ExpectedSemanticEnvelopeV5: Encodable {
    let base: Data
    let observationAndTime: [String]
}

private struct ExpectedSemanticEnvelopeV6: Encodable {
    let base: Data
    let locationNodes: [Data]
    let hierarchyEvents: [String]
    let placementEvents: [String]
    let compositionEdges: [String]
    let compositionEvents: [String]
    let migrationReceipts: [String]
}

private enum SemanticValidationLighting {
    struct Fixture {
        let system: LightingSystemV1
        let dayObservation: LightingObservationV1
        let nightObservation: LightingObservationV1
        let day: LightingDayInventoryWorkflowV1
        let plannedDay: LightingDayInventoryWorkflowV1
        let night: LightingNightWorkflowV1
        let dayAdmission: LightingDayInventoryAdmissionClosureV1
        let nightAdmission: LightingNightWorkflowAdmissionClosureV1
    }

    static func makeFixture(slot: Int) throws -> Fixture {
        let packetFixture = try C15WorkPacketManifestTestSupportV1.makeFixture(seed: 290_000 + slot)
        let workspace = packetFixture.workspaceID
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let actor = try C26SurveySessionTestSupport.actor(workspaceID: workspace)
        let package = try C26SurveySessionTestSupport.packageRelease(workflowID: "c17.report.workflow")
        let packageIdentity = try PackageReleaseIdentityV1(packageID: package.packageID, schemaVersion: 1,
                                                          contentVersion: package.packageContentVersion)
        let assetID = id(202), zoneID = id(203), groupID = id(204), luminaireID = id(205)
        let binding = try WorkSubjectSemanticBindingSnapshotV1(assetID: assetID,
            kindBindingEventID: id(206), kindBindingRevision: 1,
            catalogRelease: .init(releaseID: id(207), packageRelease: packageIdentity, catalogSHA256: digest("a")),
            semanticID: "luminaire.exterior", workflowPackageReleases: [packageIdentity])
        let zone = LightingZoneV1(zoneID: zoneID, displayName: "Day inventory",
            workSubject: .init(kind: .locationNode, subjectID: zoneID, revision: 1, ownerAssetID: nil),
            declaredActivityClass: "PARKING", declaredSecurityClass: "GENERAL")
        let group = ControlGroupV1(controlGroupID: groupID, semanticID: "lighting.primary",
            expectation: try .init(controlGroupID: groupID.uuidString.lowercased(), expectedState: .noExpectation,
                policyID: "C17_LOCAL_POLICY", policyVersion: 1, policySHA256: digest("b")))
        let luminaire = LuminaireAssetV1(luminaireID: luminaireID, assetID: assetID, assetRevision: 1,
            semanticBinding: binding, zoneIDs: [zoneID], controlGroupIDs: [groupID],
            maintenanceDisposition: .independentlyMaintained)
        let system = try LightingSystemV1(recordID: id(208), systemID: id(209), workspaceID: workspace,
            siteID: id(210), packageRelease: .init(package), zones: [zone], controlGroups: [group],
            luminaires: [luminaire], revision: 1, mutationID: .init(rawValue: id(211)),
            recordedBy: actor, recordedAt: date)
        let temporal = try TemporalContextV1(occurredAtUTC: date, recordedAtUTC: date,
            localDate: "2027-01-15", localTime: "08:00:00", utcOffsetSeconds: 0,
            ianaTimeZoneIdentifier: "UTC", localTimeDisposition: .unambiguous)
        let context = try EvidenceContextV1(contextID: id(212), workspaceID: workspace,
            evidenceID: "c17-original", evidenceSHA256: digest("c"), evidenceRevision: 1,
            assetID: assetID, assetRevision: 1, temporalContext: temporal,
            userObserved: .init(condition: .daylight, observationNoteCode: "DAY_NOT_NIGHT_TEST"),
            derivedSolar: nil, controlExpectation: nil, predecessor: nil, revision: 1,
            mutationID: .init(rawValue: id(213)), recordedBy: actor, recordedAt: date)
        let observation = try LightingObservationV1(recordID: id(214), observationID: id(215),
            workspaceID: workspace, system: system, luminaireID: luminaireID, zoneID: zoneID,
            controlGroupID: groupID, evidenceContext: context,
            observationBasis: .init(kind: .directlyObserved, method: .init(key: "c17.manual"),
                source: .init(kind: .observer), limitations: []), issueKinds: [], revision: 1,
            mutationID: .init(rawValue: id(216)), recordedBy: actor, recordedAt: date)
        let path = try LocationPathSnapshotV1(siteID: system.siteID, siteDisplay: "Fixture site", nodes: [])
        let safety = try LightingSafetyIntakeV1(intakeID: id(217), workspaceID: workspace,
            systemID: system.systemID, systemRevision: system.revision, systemSHA256: system.systemSHA256,
            area: zone.workSubject, route: path, timeContext: temporal, siteAuthority: .confirmed,
            requiredPPE: [], confirmedPPE: [], emergencyReadiness: .confirmed,
            trafficSafety: .noTrafficExposure, observerSafety: .authorizedAccessibleVantage,
            recordedBy: actor, recordedAt: date)
        let condition = try LightingDayConditionSnapshotV1(luminaireID: luminaireID, assetID: assetID,
            assetRevision: 1, zoneID: zoneID, controlGroupID: groupID, observation: .init(observation),
            poseDisposition: .notDeclared, poseEvent: nil,
            facts: [.init(aspect: .lens, state: .notObserved, issueKind: nil)], contextualMedia: [])
        let day = try LightingDayInventoryWorkflowV1(recordID: id(223), workflowID: id(224),
            workspaceID: workspace, system: system, safetyIntake: safety, conditionSnapshots: [condition],
            state: .dayInventoryRecorded, revision: 1, mutationID: .init(rawValue: id(225)),
            recordedBy: actor, recordedAt: date)
        let dayAdmission = LightingDayInventoryAdmissionClosureV1(system: system, observations: [observation],
            poseEvents: [], occurrence: nil, workPacket: nil, readiness: nil)
        try dayAdmission.validate(day)

        let nightDate = Date(timeIntervalSince1970: 1_800_046_800)
        let definition = try C26SurveySessionTestSupport.release(workspaceID: workspace)
        let timeBasis = try FrozenScheduleTimeBasisV1(
            ianaTimeZoneIdentifier: "UTC", timeZoneRuleSetVersion: "test-frozen-v1",
            timeZoneRuleSetSHA256: digest("a"), ambiguousTimePolicy: .earlierOffset,
            nonexistentTimePolicy: .shiftForwardByGap, calendarBasisSHA256: digest("b")
        )
        let anchor = ScheduleLocalAnchorV1(
            year: nil, month: nil, day: nil, weekday: nil, weekdayOrdinal: nil,
            hour: 21, minute: 0, second: 0
        )
        let schedule = try ScheduleDefinitionReleaseV1(
            scheduleDefinitionID: id(8_101), releaseID: id(8_102), workspaceID: workspace,
            occurrenceIdentityNamespaceID: id(8_103), action: .create, lifecycleState: .active,
            recurrence: .fixedCalendar(.init(cadence: .daily, interval: 1, anchor: anchor)),
            timeBasis: timeBasis, startsAtUTC: nightDate, generationHorizonDays: 30,
            maximumGeneratedOccurrences: 8, readyLeadSeconds: 0, overdueGraceSeconds: 0,
            subject: WorkSubjectReferenceV1(kind: .asset, subjectID: id(8_104),
                                            revision: 1, ownerAssetID: nil),
            workDefinition: ScheduledWorkDefinitionReferenceV1(
                kind: .workPacket, definition: definition, packageRelease: package
            ),
            revision: 1, mutationID: MutationIDV1(rawValue: id(8_105)),
            authoredBy: actor, authoredAt: nightDate
        )
        let basis = ResolvedOccurrenceBasisV1(
            nominalLocalDate: "2027-01-15", nominalLocalTime: "21:00:00",
            resolvedAtUTC: nightDate, utcOffsetSeconds: 0, disposition: .unambiguous,
            timeBasisSHA256: try timeBasis.canonicalSHA256(), adjustmentProvenanceSHA256: nil
        )
        let occurrenceID = try OccurrenceIDV1(
            scheduleDefinitionID: schedule.scheduleDefinitionID,
            identityNamespaceID: schedule.occurrenceIdentityNamespaceID, nominalKey: basis.nominalKey
        )
        let event = try OccurrenceHistoryEventV1(
            eventID: id(8_106), workspaceID: workspace, occurrenceID: occurrenceID,
            scheduleRelease: ScheduleDefinitionReleaseReferenceV1(schedule),
            action: .generated, nominalBasis: basis, effectiveBasis: basis,
            predecessor: nil, revision: 1, mutationID: MutationIDV1(rawValue: id(8_107)),
            recordedBy: actor, recordedAt: nightDate
        )
        let plan = try LightingNightFollowupPlanV1(planID: id(310), workspaceID: workspace,
            sourceSystemID: system.systemID, sourceSystemRevision: system.revision,
            sourceSystemSHA256: system.systemSHA256, sourceDayInventoryContentSHA256: day.dayInventoryContentSHA256,
            selectedLuminaireIDs: [luminaireID], occurrence: .init(event),
            workPacket: .init(packetFixture.manifest), offlineReadinessSourceSHA256: digest("e"),
            offlineReadinessManifestSHA256: digest("f"), readinessCheckedAt: nightDate,
            createdBy: actor, createdAt: nightDate)
        let plannedDay = try LightingDayInventoryWorkflowV1(recordID: id(311), workflowID: id(312),
            workspaceID: workspace, system: system, safetyIntake: safety, conditionSnapshots: [condition],
            state: .nightFollowupPrepared, nightFollowupPlan: plan, revision: 1,
            mutationID: .init(rawValue: id(313)), recordedBy: actor, recordedAt: nightDate)
        let nightTime = try TemporalContextV1(occurredAtUTC: nightDate, recordedAtUTC: nightDate,
            localDate: "2027-01-15", localTime: "21:00:00", utcOffsetSeconds: 0,
            ianaTimeZoneIdentifier: "UTC", localTimeDisposition: .unambiguous)
        let nightContext = try EvidenceContextV1(contextID: id(314), workspaceID: workspace,
            evidenceID: "receipt-safety-night", evidenceSHA256: digest("8"), evidenceRevision: 1,
            assetID: assetID, assetRevision: 1, temporalContext: nightTime,
            userObserved: .init(condition: .night, observationNoteCode: "NIGHT_INVENTORY"),
            derivedSolar: nil, controlExpectation: nil, predecessor: nil, revision: 1,
            mutationID: .init(rawValue: id(315)), recordedBy: actor, recordedAt: nightDate)
        let nightObservation = try LightingObservationV1(recordID: id(316), observationID: id(317),
            workspaceID: workspace, system: system, luminaireID: luminaireID, zoneID: zoneID,
            controlGroupID: groupID, evidenceContext: nightContext,
            observationBasis: .init(kind: .directlyObserved, method: .init(key: "receipt.night.manual"),
                source: .init(kind: .observer), limitations: []), issueKinds: [], revision: 1,
            mutationID: .init(rawValue: id(318)), recordedBy: actor, recordedAt: nightDate)
        let nightSafety = try LightingSafetyIntakeV1(intakeID: id(319), workspaceID: workspace,
            systemID: system.systemID, systemRevision: system.revision, systemSHA256: system.systemSHA256,
            area: zone.workSubject, route: path, timeContext: nightTime, siteAuthority: .confirmed,
            requiredPPE: [], confirmedPPE: [], emergencyReadiness: .confirmed,
            trafficSafety: .noTrafficExposure, observerSafety: .authorizedAccessibleVantage,
            recordedBy: actor, recordedAt: nightDate)
        let comparableMedia = try ContentReferenceV1(
            workspaceID: workspace.rawValue.uuidString.lowercased(),
            contentID: nightContext.evidenceID, byteLength: 1, mediaType: "image/jpeg",
            digests: .init([.init(algorithm: .sha256,
                hexadecimalValue: nightContext.evidenceSHA256)]),
            byteRole: .immutableOriginal, createdAt: ISO8601DateFormatter().string(from: nightDate))
        let delta = try LightingNightDeltaV1(luminaireID: luminaireID, assetID: assetID, assetRevision: 1,
            zoneID: zoneID, controlGroupID: groupID, observation: .init(nightObservation),
            expectedControl: .noDeclaredExpectation, observedControl: .appearedOn,
            issueKinds: [], comparableMedia: [comparableMedia], temporaryLight: .notObserved,
            weatherContext: .notObserved, surfaceContext: .notObserved, measurement: nil,
            cameraBandingRecordedWithoutFlickerClaim: false)
        let night = try LightingNightWorkflowV1(recordID: id(320), workflowID: id(321),
            workspaceID: workspace, system: system, dayWorkflow: plannedDay,
            safety: .init(intake: nightSafety, nightPlan: plan), deltas: [delta], repairPolicy: .init(),
            state: .nightInventoryRecorded, revision: 1, mutationID: .init(rawValue: id(322)),
            recordedBy: actor, recordedAt: nightDate)
        let nightAdmission = LightingNightWorkflowAdmissionClosureV1(system: system,
            dayWorkflow: plannedDay, observations: [nightObservation], issues: [],
            admittedMeasurementSHA256s: [], patrolSessions: [])
        try nightAdmission.validate(night)
        return .init(system: system, dayObservation: observation, nightObservation: nightObservation,
            day: day, plannedDay: plannedDay, night: night, dayAdmission: dayAdmission,
            nightAdmission: nightAdmission)
    }

    private static func id(_ slot: Int) -> UUID {
        UUID(uuidString: String(format: "d1800000-0000-4000-8000-%012x", slot))!
    }
    private static func digest(_ character: Character) -> String {
        String(repeating: String(character), count: 64)
    }
}

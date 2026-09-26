import CryptoKit
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
            let manifestStore = try StoreMigrationJournalStoreV1(applicationSupportURL: support)
            let bootstrap = try XCTUnwrap(manifestStore.loadManifestIfPresent(targetGenerationID: active.generationID))
            XCTAssertEqual(bootstrap.manifest.schemaVersion, 2)
            XCTAssertEqual(bootstrap.manifest.semanticDigestAlgorithm, .framedLayersV1)
            XCTAssertEqual(bootstrap.manifest.semanticSHA256,
                try factory.manifestSemanticDigestForTesting(in: active.modelContext, manifest: bootstrap.manifest))
            let bootstrapBytes = try bootstrap.manifest.canonicalData()
            XCTAssertEqual(try manifestStore.loadManifest(targetGenerationID: active.generationID,
                expectedDigest: bootstrap.digest), bootstrap.manifest)
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
            let boundedDigest = try factory.framedSemanticDigestForTesting(in: active.modelContext)
            XCTAssertEqual(boundedDigest, expectedFramedDigest(traversal))
            try assertFramedLayerTamperAndBounds(traversal)
            XCTAssertFalse(active.modelContext.hasChanges)
            XCTAssertEqual(persisted.location.canonicalData, locationBefore)
            XCTAssertEqual(persisted.night.canonicalData, nightBefore)
            XCTAssertEqual(try receiptBytes(in: active.modelContext), receiptsBefore)
            XCTAssertEqual(try Data(contentsOf: pointerURL), pointerBefore)
            XCTAssertEqual(try Data(contentsOf: modelURL), storeBefore)
            return SemanticValidationStoreFacts(generationID: active.generationID,
                generationRoot: active.generationRootURL, pointer: pointerBefore,
                location: locationBefore, night: nightBefore, receipts: receiptsBefore,
                traversalCount: traversal.count, boundedDigest: boundedDigest, bootstrapManifest: bootstrapBytes)
        }
        try autoreleasepool { () throws -> Void in
            let factory = StoreGenerationFactory(applicationSupportURL: support)
            let cold = try semanticObserved("traversal cold open") { try factory.openOrBootstrapCurrent() }
            XCTAssertEqual(cold.generationID, facts.generationID)
            XCTAssertEqual(cold.storeSchemaRelease, .v53)
            let manifestStore = try StoreMigrationJournalStoreV1(applicationSupportURL: support)
            let bootstrap = try XCTUnwrap(manifestStore.loadManifestIfPresent(targetGenerationID: cold.generationID))
            XCTAssertEqual(try bootstrap.manifest.canonicalData(), facts.bootstrapManifest)
            // Activation proof stays immutable after legitimate production writes.
            XCTAssertEqual(bootstrap.manifest.schemaVersion, 2)
            XCTAssertEqual(bootstrap.manifest.semanticDigestAlgorithm, .framedLayersV1)
            let modelURL = facts.generationRoot.appendingPathComponent("model.sqlite")
            let storeBefore = try Data(contentsOf: modelURL)
            var traversal: [Data] = []
            try factory.validateSemanticRowsForTesting(in: cold.modelContext, through: .v53) {
                traversal.append($0)
            }
            try assertValidationTraversal(traversal, location: facts.location, night: lighting.night)
            XCTAssertEqual(traversal.count, facts.traversalCount)
            XCTAssertEqual(try factory.framedSemanticDigestForTesting(in: cold.modelContext), facts.boundedDigest)
            XCTAssertEqual(expectedFramedDigest(traversal), facts.boundedDigest)
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
            // Recorded expectation correction: reproofAfterSave() re-proves only the
            // closed generation file set and protection policy (its contract). Rows
            // saved outside WorkspaceWriter are detected by relaunch validation,
            // which verifies the persisted mutable semantic checkpoint
            // (V23P02C02MutationRecoveryMatrixV1.json persistedStateRecovery
            // relaunchValidation VERIFY_ACTUAL_STATE_TOMBSTONES_MUTABLE_SEMANTIC_AND_EXTERNAL_PROJECTIONS).
            let relaunchJournal = try MutationJournalStoreV1(
                modelContext: cold.modelContext, identity: cold.workspaceIdentity,
                generationID: cold.generationID, allowStateBootstrap: false)
            XCTAssertNoThrow(try relaunchJournal.validateAll())
            cold.modelContext.insert(try LocationNodeRow(laterLocation))
            try cold.modelContext.save()
            XCTAssertNoThrow(try cold.reproofAfterSave())
            XCTAssertThrowsError(try MutationJournalStoreV1(
                modelContext: cold.modelContext, identity: cold.workspaceIdentity,
                generationID: cold.generationID, allowStateBootstrap: false).validateAll()) {
                XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .receiptHistoryCorrupt)
            }
            XCTAssertEqual(try receiptBytes(in: cold.modelContext), facts.receipts)
            XCTAssertFalse(cold.modelContext.hasChanges)
        }
        try FileManager.default.removeItem(at: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    /// A released S10 (V1) store upgrades through every adjacent release and both
    /// launches with bounded framed digests: no nested canonical V3...V53 bytes.
    func testReleasedV1UpgradeCompletesBothLaunchesWithinBoundedTimeAndMemory() async throws {
        try await assertBoundedV1Upgrade(siteCount: 1, label: "OneSite")
        try await assertBoundedV1Upgrade(siteCount: 40, label: "FortySites")
    }

    /// A durable Parts Stock commit reports success under a live clock with
    /// sub-millisecond precision: the writer freezes the commit instant at the
    /// canonical millisecond before any effect, so the persisted generic receipt,
    /// the typed receipt and replay agree.
    func testPartsStockCommitUnderSubMillisecondClockReportsSuccess() throws {
        struct SubMillisecondClock: ApplicationClock {
            func now() -> Date { Date(timeIntervalSince1970: 1_800_000_000.123_456_7) }
        }
        let root = temporaryRoot("PartsStockClock")
        let support = applicationSupport(in: root)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspaceID = WorkspaceID(rawValue: semanticID(790))
        let factory = StoreGenerationFactory(applicationSupportURL: support,
            pointerEnrichmentIdentity: try workspaceIdentity(workspaceID))
        let session = try semanticObserved("parts clock open") { try factory.openOrBootstrapCurrent() }
        let coordinator = try semanticObserved("parts clock writer") {
            try StoreSessionCoordinator(validatingSession: session, clock: SubMillisecondClock())
        }
        let mutation = PartsStockMutationV1.upsertPart(try LocalPartDefinitionV1(
            partID: semanticID(791), workspaceID: workspaceID, displayName: "Clock part",
            canonicalUnit: .each, productIdentities: [try .init(kind: .sku, value: "SKU-CLOCK")],
            preferredMinimum: try .init(mantissa: 1, scale: 0, unit: .each), archived: false,
            revision: 1, mutationID: try MutationIDV1(rawValue: semanticID(792))))
        let receipt = try coordinator.workspaceWriter.commitPartsStock(mutation)
        XCTAssertNoThrow(try receipt.validate())
        XCTAssertEqual(receipt.committedAt, Date(timeIntervalSince1970: 1_800_000_000.123))
        XCTAssertEqual(try coordinator.workspaceWriter.commitPartsStock(mutation), receipt, "replay agrees")
        try coordinator.invalidateAndReleaseWriter()
        let journal = try MutationJournalStoreV1(modelContext: session.modelContext,
            identity: session.workspaceIdentity, generationID: session.generationID, allowStateBootstrap: false)
        XCTAssertEqual(try journal.receipt(mutationID: mutation.mutationID)?.committedAt, receipt.committedAt)
        XCTAssertEqual(try session.modelContext.fetch(FetchDescriptor<LocalPartDefinitionRowV1>()).count, 1)
        XCTAssertNoThrow(try journal.validateAll())
    }

    /// Coverage guard: every journaled kind is either enumerated by the v1
    /// identity basis, counted by the v2 row inventory, or hashed directly
    /// (virtual balance stream, deletion ledger). A new kind fails here until
    /// it is placed in exactly one group.
    func testMutableSemanticCheckpointCoversEveryJournaledKind() {
        let v1 = MutationJournalStoreV1.mutableSemanticV1IdentityKinds
        let inventory = MutationJournalStoreV1.mutableSemanticInventoryModelsV2
        let v2 = Set(inventory.map(\.kind))
        let direct = MutationJournalStoreV1.mutableSemanticNonInventoryKinds
        XCTAssertEqual(WorkspaceEntityKindV1.allCases.count, 148)
        XCTAssertEqual(v2.count, inventory.count, "one inventory model per kind")
        XCTAssertEqual(Set(inventory.map(\.model)).count, inventory.count)
        XCTAssertTrue(v1.isDisjoint(with: v2))
        XCTAssertTrue(v1.isDisjoint(with: direct))
        XCTAssertTrue(v2.isDisjoint(with: direct))
        XCTAssertEqual(v1.union(v2).union(direct), Set(WorkspaceEntityKindV1.allCases))
        XCTAssertEqual(inventory.map(\.model), inventory.map(\.model).sorted(), "digest order is stable")
    }

    /// Test-only tamper matrix for out-of-writer changes made in the writer's
    /// context and checked by the relaunch validator (validateAll). Source
    /// analysis: validateTerminalRows re-proves the current post-image of every
    /// revision-journaled identity for all WorkspaceEntityKindV1 cases, so
    /// modify/delete of receipt-backed rows is kind-generic; an insert without a
    /// receipt is only seen through the mutable semantic checkpoint identity set
    /// (parity validators are receipt-driven). The recorded gap set pins today's
    /// behavior so a versioned checkpoint must update it deliberately.
    func testOutOfWriterTamperMatrixRecordsDetectionMechanism() throws {
        let root = temporaryRoot("TamperMatrix")
        let support = applicationSupport(in: root)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let lighting = try SemanticValidationLighting.makeFixture(slot: 61)
        let factory = StoreGenerationFactory(applicationSupportURL: support,
            pointerEnrichmentIdentity: try workspaceIdentity(lighting.night.workspaceID))
        let session = try semanticObserved("tamper matrix open") { try factory.openOrBootstrapCurrent() }
        let persisted = try semanticObserved("tamper matrix populate") { try populateCurrentStore(session, lighting: lighting) }
        let context = session.modelContext
        let journal = try MutationJournalStoreV1(modelContext: context, identity: session.workspaceIdentity,
            generationID: session.generationID, allowStateBootstrap: false)
        XCTAssertNoThrow(try journal.validateAll())
        let date = lighting.night.recordedAt.addingTimeInterval(500)
        // Writer-committed rows of two v2-only kinds for count-neutral and
        // canonical-byte tamper probes.
        let committedActorID = semanticID(770), committedPartID = semanticID(772)
        try semanticObserved("tamper matrix writer seeds") {
            let seeding = try StoreSessionCoordinator(validatingSession: session)
            let actor = try LocalActorReferenceV1(actorReferenceID: semanticID(771),
                workspaceID: lighting.night.workspaceID, displayName: "Committed matrix actor")
            _ = try seeding.workspaceWriter.execute(.applyPartyAccountability(.appendActorSnapshot(
                try ActorSnapshotV1(snapshotID: committedActorID, workspaceID: lighting.night.workspaceID,
                    actor: actor, responsibility: .recordedBy, displayNameAtTime: actor.displayName,
                    capturedAt: date))), mutationID: MutationIDV1(rawValue: semanticID(773)))
            let partReceipt = try seeding.workspaceWriter.commitPartsStock(.upsertPart(try LocalPartDefinitionV1(
                partID: committedPartID, workspaceID: lighting.night.workspaceID, displayName: "Committed part",
                canonicalUnit: .each, productIdentities: [try .init(kind: .sku, value: "SKU-COMMITTED")],
                preferredMinimum: try .init(mantissa: 1, scale: 0, unit: .each), archived: false,
                revision: 1, mutationID: try MutationIDV1(rawValue: semanticID(774)))))
            XCTAssertNoThrow(try partReceipt.validate())
            try seeding.invalidateAndReleaseWriter()
        }
        XCTAssertEqual(try context.fetch(FetchDescriptor<LocalPartDefinitionRowV1>()).filter {
            $0.partID == committedPartID }.count, 1)
        XCTAssertNoThrow(try journal.validateAll())
        func probe(_ name: String, _ tamper: () throws -> Void) rethrows -> Bool {
            try tamper()
            defer { context.rollback() }
            do { try journal.validateAll(); return false } catch { return true }
        }
        var detected: [String: Bool] = [:]
        detected["locationNode.insert(checkpoint)"] = try probe("insert location") {
            context.insert(try LocationNodeRow(try LocationNodeV1(
                id: semanticID(760), workspaceID: lighting.night.workspaceID, siteID: lighting.system.siteID,
                parentNodeID: nil, kind: .building, label: "Tamper matrix building", shortCode: "TM",
                siblingOrder: 7, state: .active, revision: 1,
                provenance: .init(mutationID: try MutationIDV1(rawValue: semanticID(761)), occurredAt: date))))
        }
        detected["locationNode.modify(terminal+checkpoint)"] = try probe("modify location") {
            let old = try persisted.location.value()
            let changed = try LocationNodeV1(id: old.id, workspaceID: old.workspaceID, siteID: old.siteID,
                parentNodeID: old.parentNodeID, kind: old.kind, label: "Consistently tampered label",
                shortCode: old.shortCode, siblingOrder: old.siblingOrder, state: old.state,
                revision: old.revision, provenance: old.provenance)
            persisted.location.label = changed.label
            persisted.location.canonicalData = try LocationPersistenceCodecV1.encode(changed)
        }
        detected["locationNode.delete(terminal+checkpoint)"] = try probe("delete location") {
            context.delete(persisted.location)
        }
        detected["lightingNightWorkflow.delete(terminal+checkpoint)"] = try probe("delete night") {
            context.delete(persisted.night)
        }
        detected["actorSnapshot.insert(v2 inventory)"] = try probe("insert actor") {
            let actor = try LocalActorReferenceV1(actorReferenceID: semanticID(764),
                workspaceID: lighting.night.workspaceID, displayName: "Tamper matrix actor")
            context.insert(try ActorSnapshotRow(try ActorSnapshotV1(snapshotID: semanticID(765),
                workspaceID: lighting.night.workspaceID, actor: actor, responsibility: .recordedBy,
                displayNameAtTime: actor.displayName, capturedAt: date)))
        }
        detected["localPartDefinition.insert(v2 inventory)"] = try probe("insert part") {
            context.insert(try LocalPartDefinitionRowV1(try LocalPartDefinitionV1(
                partID: semanticID(766), workspaceID: lighting.night.workspaceID, displayName: "Tamper part",
                canonicalUnit: .each, productIdentities: [try .init(kind: .sku, value: "SKU-TAMPER")],
                preferredMinimum: try .init(mantissa: 1, scale: 0, unit: .each), archived: false,
                revision: 1, mutationID: try MutationIDV1(rawValue: semanticID(767)))))
        }
        detected["actorSnapshot.insertAndDelete(count-neutral)"] = try probe("count-neutral actor") {
            let actor = try LocalActorReferenceV1(actorReferenceID: semanticID(775),
                workspaceID: lighting.night.workspaceID, displayName: "Forged matrix actor")
            context.insert(try ActorSnapshotRow(try ActorSnapshotV1(snapshotID: semanticID(776),
                workspaceID: lighting.night.workspaceID, actor: actor, responsibility: .recordedBy,
                displayNameAtTime: actor.displayName, capturedAt: date)))
            let committed = try context.fetch(FetchDescriptor<ActorSnapshotRow>(
                predicate: #Predicate { $0.snapshotID == committedActorID }))
            XCTAssertEqual(committed.count, 1)
            committed.forEach(context.delete)
        }
        detected["localPartDefinition.modifyCanonicalBytes(v2-only kind)"] = try probe("modify part bytes") {
            let row = try XCTUnwrap(context.fetch(FetchDescriptor<LocalPartDefinitionRowV1>()).first {
                $0.partID == committedPartID })
            let old = try row.value()
            let forged = try LocalPartDefinitionV1(partID: old.partID, workspaceID: old.workspaceID,
                displayName: "Forged part name", canonicalUnit: old.canonicalUnit,
                productIdentities: old.productIdentities, preferredMinimum: old.preferredMinimum,
                archived: old.archived, revision: old.revision, mutationID: old.mutationID)
            row.displayName = forged.displayName
            row.canonicalData = try PartsStockPersistenceCodecV1.encode(forged)
        }
        detected["assetLocator.insert(v2 inventory)"] = try probe("insert locator") {
            context.insert(try AssetLocatorRow(try AssetLocatorV1(
                locatorID: semanticID(762), workspaceID: lighting.night.workspaceID,
                assetID: try XCTUnwrap(lighting.night.deltas.first).assetID,
                representation: .externalKey(try ExternalKeyV1(namespaceID: "asset",
                    normalization: .asciiCaseInsensitive, suppliedValue: "tamper-matrix")),
                state: .active, revision: 1, mutationID: try MutationIDV1(rawValue: semanticID(763)),
                recordedAt: date)))
        }
        for (key, value) in detected.sorted(by: { $0.key < $1.key }) {
            print("V23TamperMatrix probe=\(key) detected=\(value)")
        }
        XCTAssertFalse(context.hasChanges)
        XCTAssertNoThrow(try journal.validateAll())
        // Recorded expectation change (checkpoint v2): no exercised out-of-writer
        // insert, modify or delete remains undetected.
        XCTAssertEqual(Set(detected.filter { !$0.value }.keys), [])

        // Implicit version dispatch and one-time re-stage.
        let versions = try journal.checkpointVersionsForTesting()
        XCTAssertNotEqual(versions.v1, versions.v2)
        XCTAssertEqual(versions.stored, versions.v2)
        XCTAssertEqual(versions.validated, 2)
        let state = try XCTUnwrap(context.fetch(FetchDescriptor<WorkspaceMutationStateRow>()).first)
        state.mutableSemanticSHA256 = versions.v1
        try context.save()
        XCTAssertNoThrow(try journal.validateAll())
        XCTAssertEqual(try journal.checkpointVersionsForTesting().validated, 1)
        try journal.restageValidatedLegacyCheckpointIfNeeded()
        XCTAssertEqual(state.mutableSemanticSHA256, versions.v1, "maintenance access never re-stages")
        state.mutableSemanticSHA256 = String(repeating: "0", count: 64)
        XCTAssertThrowsError(try journal.validateAll())
        context.rollback()
        let coordinator = try semanticObserved("tamper matrix writer re-stage") {
            try StoreSessionCoordinator(validatingSession: session)
        }
        try coordinator.invalidateAndReleaseWriter()
        XCTAssertEqual(try XCTUnwrap(context.fetch(FetchDescriptor<WorkspaceMutationStateRow>()).first)
            .mutableSemanticSHA256, versions.v2, "first writer session re-stages an exact v1 checkpoint as v2")
        XCTAssertNoThrow(try journal.validateAll())
        XCTAssertEqual(try journal.checkpointVersionsForTesting().validated, 2)

        // Timing on a populated context (unsaved, rolled back): v2 adds only
        // row-count queries to the v1 computation.
        for index in 0..<600 {
            context.insert(Site(id: semanticID(20_000 + index), label: "Timing site \(index)", address: nil,
                                timeZoneID: "UTC", createdAt: date, updatedAt: date))
        }
        var v1Seconds: [Double] = [], v2Seconds: [Double] = []
        for _ in 0..<5 {
            var start = Date(); _ = try journal.checkpointV1ForTesting(); v1Seconds.append(Date().timeIntervalSince(start))
            start = Date(); _ = try journal.checkpointV2ForTesting(); v2Seconds.append(Date().timeIntervalSince(start))
        }
        context.rollback()
        let v1Median = v1Seconds.sorted()[2], v2Median = v2Seconds.sorted()[2]
        print("V23CheckpointTiming rows=600+fixture v1MedianMs=\(Int(v1Median * 1000)) v2MedianMs=\(Int(v2Median * 1000))")
        XCTAssertLessThan(v2Median, 2.0)
    }

    func testEarlyAndLatestCanonicalRowCorruptionKeepTypedFailureAndColdOpenTargetMismatchWithoutRepair() throws {
        try assertCorruptionFailsClosed(.location)
        try assertCorruptionFailsClosed(.nightWorkflow)
    }

    func testLowReleaseCanonicalProjectionsRetainExactNestedPredecessorBytes() throws {
        try assertManifestDigestFormatsAndFrozenFrameVector()
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
        let manifestHash = String(repeating: "1", count: 64)
        let file = try StoreGenerationFileDigestV1(relativePath: "model.sqlite", byteCount: 1,
                                                  sha256: manifestHash, kind: .database)
        let oldManifest = try StoreGenerationManifestV1(generationID: semanticID(820),
            predecessorGenerationID: semanticID(821), migrationID: semanticID(822), storeSchemaRelease: .v3,
            semanticSHA256: StoreMigrationCanonicalJSONV1.sha256(expectedV3),
            frozenIdentityDigest: manifestHash, files: [file])
        XCTAssertEqual(try factory.manifestSemanticDigestForTesting(in: context, manifest: oldManifest),
                       StoreMigrationCanonicalJSONV1.sha256(expectedV3))
        var currentLayers: [Data] = []
        try factory.validateSemanticRowsForTesting(in: context, through: .v53) { currentLayers.append($0) }
        let expectedModern = expectedFramedDigest(currentLayers)
        // Aggregate candidates hash the same local envelopes, truncated at their release.
        for release in [PersistentSchemaReleaseV1.v3, .v4, .v6, .v44, .v52] {
            let major = release.versionIdentifier.major
            XCTAssertEqual(try factory.framedSemanticDigestForTesting(in: context, release: release),
                           expectedFramedDigest(Array(currentLayers.prefix(major - 2)), release: UInt64(major)))
        }
        XCTAssertThrowsError(try factory.framedSemanticDigestForTesting(in: context, release: .v2))
        let newManifest = try StoreGenerationManifestV1(schemaVersion: 2, generationID: semanticID(823),
            predecessorGenerationID: semanticID(824), migrationID: semanticID(825), storeSchemaRelease: .v53,
            semanticSHA256: expectedModern, semanticDigestAlgorithm: .framedLayersV1,
            frozenIdentityDigest: manifestHash, files: [file])
        XCTAssertEqual(try factory.manifestSemanticDigestForTesting(in: context, manifest: newManifest), expectedModern)
        XCTAssertNotEqual(expectedModern, oldManifest.semanticSHA256)
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

    // Independent whole-frame oracle used only for small test fixtures.
    // Production hashes incrementally and never keeps this aggregate buffer.
    private func expectedFramedDigest(_ layers: [Data], release: UInt64 = 53) -> String {
        func integer(_ value: UInt64) -> [UInt8] {
            (0..<8).reversed().map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }
        }
        var frame = Array("AssetRounds.StoreSemanticDigest.framed-layers.v1\0".utf8)
        frame += integer(release)
        for (offset, layer) in layers.enumerated() {
            frame += integer(UInt64(offset + 3))
            frame += integer(UInt64(layer.count))
            frame += layer
        }
        frame += integer(UInt64(layers.count))
        return SHA256.hash(data: Data(frame)).map { String(format: "%02x", $0) }.joined()
    }

    private func digestLayers(_ layers: [Data], release: PersistentSchemaReleaseV1 = .v53) throws -> String {
        var digest = try StoreSemanticLayerDigestV1(release: release)
        for layer in layers { try digest.append(layer) }
        return try digest.finalize()
    }

    private func assertFramedLayerTamperAndBounds(_ layers: [Data]) throws {
        XCTAssertEqual(layers.count, 51)
        guard layers.count == 51 else { return }
        let expected = expectedFramedDigest(layers)
        XCTAssertEqual(try digestLayers(layers), expected)
        // Covers base records/ledger, receipt history, locations and latest rows.
        for index in [0, 1, 3, 50] {
            var changed = layers
            changed[index].append(0x20)
            XCTAssertNotEqual(try digestLayers(changed), expected)
        }
        var reordered = layers
        reordered.swapAt(0, 50)
        XCTAssertNotEqual(try digestLayers(reordered), expected)
        XCTAssertThrowsError(try digestLayers(Array(layers.dropLast())))
        XCTAssertThrowsError(try digestLayers(layers + [Data()]))
        // Recorded expectation change (aggregate journal schema 2): V3...V52 are
        // valid framed releases with exactly n-2 layers; flat V1/V2 never frame.
        XCTAssertThrowsError(try StoreSemanticLayerDigestV1(release: .v1))
        XCTAssertThrowsError(try StoreSemanticLayerDigestV1(release: .v2))
        XCTAssertThrowsError(try digestLayers(layers, release: .v52))
        XCTAssertThrowsError(try digestLayers(Array(layers.dropLast(2)), release: .v52))
        XCTAssertNotEqual(try digestLayers(Array(layers.dropLast()), release: .v52), expected)
    }

    private func assertManifestDigestFormatsAndFrozenFrameVector() throws {
        let vector = (3...53).map { Data("layer-\($0)".utf8) }
        // Frozen independently with Python hashlib and >Q framing.
        let golden = "8dc72f3178421dc3f690025e5aab119da2f556d658bf84ac9553896cd63835a3"
        XCTAssertEqual(expectedFramedDigest(vector), golden)
        XCTAssertEqual(try digestLayers(vector), golden)
        try assertFramedLayerTamperAndBounds(vector)
        // Frozen independently with Python hashlib (same framing, release n, n-2 layers).
        let releaseGoldens: [(PersistentSchemaReleaseV1, String)] = [
            (.v3, "0dfc060b4518873e37ace624f18e3e88ce0ea9817e7c21d1718e5a6758960691"),
            (.v4, "abfb5566dcb667b7e567503c27782a7ed39a9a0bcb4517457762e323741276eb"),
            (.v44, "6f54c88c8bcf68ff98bb2d8f6129a7658fbf59870cc306d147a57831f68b3976"),
            (.v52, "2cf093c0f468f2f8b44102cbc55e61a95a0fe357db06ff2f9828b987d7d0e3af")
        ]
        for (release, expected) in releaseGoldens {
            let major = release.versionIdentifier.major
            let layers = (3...major).map { Data("layer-\($0)".utf8) }
            XCTAssertEqual(expectedFramedDigest(layers, release: UInt64(major)), expected)
            XCTAssertEqual(try digestLayers(layers, release: release), expected)
            XCTAssertThrowsError(try digestLayers(Array(layers.dropLast()), release: release))
            XCTAssertThrowsError(try digestLayers(layers + [Data()], release: release))
            var changed = layers; changed[layers.count - 1].append(0x20)
            XCTAssertNotEqual(try digestLayers(changed, release: release), expected)
        }

        let generation = try XCTUnwrap(UUID(uuidString: "10000000-0000-4000-8000-000000000001"))
        let predecessor = try XCTUnwrap(UUID(uuidString: "10000000-0000-4000-8000-000000000002"))
        let migration = try XCTUnwrap(UUID(uuidString: "10000000-0000-4000-8000-000000000003"))
        let hash = String(repeating: "1", count: 64)
        let file = try StoreGenerationFileDigestV1(relativePath: "model.sqlite", byteCount: 1,
                                                  sha256: hash, kind: .database)
        let legacy = try StoreGenerationManifestV1(generationID: generation,
            predecessorGenerationID: predecessor, migrationID: migration, storeSchemaRelease: .v53,
            semanticSHA256: hash, frozenIdentityDigest: hash, files: [file])
        let legacyBytes = try legacy.canonicalData()
        // Independent legacy shape: the new optional field must not alter old bytes.
        let expectedLegacy: [String: Any] = [
            "schemaVersion": 1, "generationID": generation.uuidString,
            "predecessorGenerationID": predecessor.uuidString, "migrationID": migration.uuidString,
            "storeSchemaRelease": "V53", "semanticSHA256": hash, "frozenIdentityDigest": hash,
            "files": [["relativePath": "model.sqlite", "byteCount": 1, "sha256": hash, "kind": "database"]]
        ]
        let jsonOptions: JSONSerialization.WritingOptions = [.sortedKeys, .withoutEscapingSlashes]
        XCTAssertEqual(legacyBytes, try JSONSerialization.data(withJSONObject: expectedLegacy, options: jsonOptions))
        XCTAssertEqual(try StoreGenerationManifestV1.decodeCanonical(from: legacyBytes), legacy)
        XCTAssertNil(legacy.semanticDigestAlgorithm)
        let modern = try StoreGenerationManifestV1(schemaVersion: 2, generationID: generation,
            predecessorGenerationID: predecessor, migrationID: migration, storeSchemaRelease: .v53,
            semanticSHA256: golden, semanticDigestAlgorithm: .framedLayersV1,
            frozenIdentityDigest: hash, files: [file])
        let modernBytes = try modern.canonicalData()
        XCTAssertEqual(try StoreGenerationManifestV1.decodeCanonical(from: modernBytes), modern)
        XCTAssertNotEqual(try modern.canonicalSHA256(), try legacy.canonicalSHA256())
        let modernObject = try jsonObject(modernBytes)
        var invalidObjects: [[String: Any]] = []
        for version in [0, 1, 3] {
            var changed = modernObject; changed["schemaVersion"] = version; invalidObjects.append(changed)
        }
        for algorithm in ["unknown", "canonicalNestedV1"] {
            var changed = modernObject; changed["semanticDigestAlgorithm"] = algorithm; invalidObjects.append(changed)
        }
        var missing = modernObject; missing.removeValue(forKey: "semanticDigestAlgorithm"); invalidObjects.append(missing)
        var wrongRelease = modernObject; wrongRelease["storeSchemaRelease"] = "V52"; invalidObjects.append(wrongRelease)
        var nullLegacy = expectedLegacy; nullLegacy["semanticDigestAlgorithm"] = NSNull(); invalidObjects.append(nullLegacy)
        for value in invalidObjects {
            let bytes = try JSONSerialization.data(withJSONObject: value, options: jsonOptions)
            XCTAssertThrowsError(try StoreGenerationManifestV1.decodeCanonical(from: bytes))
        }
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
            XCTAssertThrowsError(try factory.framedSemanticDigestForTesting(in: active.modelContext),
                                 file: file, line: line)
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
        context.insert(location)
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
                // Night rows and everything they admit against enter only
                // through the canonical writer, after the journal exists.
                let journal = try MutationJournalStoreV1(modelContext: context,
                    identity: session.workspaceIdentity, generationID: session.generationID)
                let promotionActor = try C26SurveySessionTestSupport.actor(
                    workspaceID: lighting.night.workspaceID, slot: 8_004)
                let writer = coordinator.workspaceWriter
                // Runs inside this open's autorelease scope; the sandbox step is async.
                try semanticRunBlocking {
                    try await CanonicalWriterSeedingV1.seedLightingNightPrerequisites(lighting,
                        promotionActor: promotionActor, writer: writer, journal: journal, context: context)
                }
                _ = try coordinator.workspaceWriter.commitLightingNightWorkflow(.appendWorkflow(
                    value: lighting.night, predecessor: nil, admission: lighting.nightAdmission))
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
        let night = try XCTUnwrap(context.fetch(FetchDescriptor<LightingNightWorkflowRowV1>()).first)
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

    private func openStartup(support: URL, identity: WorkspaceReplicaIdentityV1,
                             processID: UUID) async throws -> StoreStartupOpenResultV1 {
        let factory = StoreGenerationFactory(applicationSupportURL: support,
            migrationIdentitySource: StoreMigrationIdentitySourceV1(makeMigrationID: UUID.init,
                makeGenerationID: UUID.init, makeProcessID: { processID }),
            pointerEnrichmentIdentity: identity)
        return try await factory.openForStartup { _ in }
    }

    private func assertBoundedV1Upgrade(siteCount: Int, label: String) async throws {
        // Measured on a heavily loaded iOS 26.5 Simulator host: 11-14 s for both
        // launches, <10 MB footprint growth (nested exports: >300 s and >2 GB).
        let wallBudgetSeconds = 60.0
        let footprintBudgetBytes: UInt64 = 256 * 1_048_576
        let root = temporaryRoot("Upgrade\(label)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Library", isDirectory: true),
                                                withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let support = applicationSupport(in: root)
        let identity = try WorkspaceReplicaIdentityV1(workspaceID: WorkspaceID(rawValue: semanticID(900)),
                                                      replicaID: ReplicaID(rawValue: semanticID(901)))
        let sourceGenerationID = semanticID(902)
        let date = Date(timeIntervalSince1970: 1_700_060_000)
        try semanticObserved("seed released V1 \(label)") {
            try autoreleasepool {
                _ = try StoreGenerationFactory(applicationSupportURL: support, pointerEnrichmentIdentity: identity)
                    .seedReleasedCheckpointTestFixture(release: .v1, generationID: sourceGenerationID,
                        migrationID: semanticID(903), identity: identity) { context in
                        for index in 0..<siteCount {
                            context.insert(Site(id: semanticID(1_000 + index), label: "Upgrade site \(index)",
                                address: "\(index) Main Street, Springfield", timeZoneID: "UTC",
                                createdAt: date, updatedAt: date))
                        }
                    }
            }
        }
        let sampler = SemanticFootprintSampler()
        let started = Date()
        guard case .awaitingIndependentValidation(let pending) = try await openStartup(
            support: support, identity: identity, processID: semanticID(904)) else {
            _ = sampler.stop()
            return XCTFail("\(label): first launch must migrate and await independent validation")
        }
        let firstLaunchSeconds = Date().timeIntervalSince(started)
        let control = try XCTUnwrap(StoreAggregateMigrationControlV1(applicationSupportURL: support))
        let awaiting = try XCTUnwrap(control.load())
        XCTAssertEqual(awaiting.schemaVersion, StoreAggregateMigrationJournalV1.currentSchemaVersion)
        XCTAssertEqual(awaiting.phase, .awaitingIndependentValidation)
        XCTAssertEqual(awaiting.transitions.map { $0.targetRelease.versionIdentifier.major }, Array(2...53))
        XCTAssertEqual(awaiting.targetGenerationID, pending.targetGenerationID)
        let manifestStore = try StoreMigrationJournalStoreV1(applicationSupportURL: support)
        let manifest = try manifestStore.loadManifest(targetGenerationID: awaiting.targetGenerationID,
            expectedDigest: try XCTUnwrap(awaiting.targetManifestSHA256))
        XCTAssertEqual(manifest.schemaVersion, 2)
        XCTAssertEqual(manifest.semanticDigestAlgorithm, .framedLayersV1)
        XCTAssertEqual(manifest.storeSchemaRelease, .v53)
        XCTAssertEqual(manifest.semanticSHA256, awaiting.transitions.last?.targetSemanticSHA256)

        // An unfinished journal carrying the retired nested format fails closed by name.
        let awaitingBytes = try awaiting.canonicalData()
        var nested = try jsonObject(awaitingBytes); nested["schemaVersion"] = 1
        let nestedBytes = try JSONSerialization.data(withJSONObject: nested, options: [.sortedKeys, .withoutEscapingSlashes])
        XCTAssertThrowsError(try StoreAggregateMigrationJournalV1.decodeCanonical(from: nestedBytes)) { error in
            XCTAssertEqual(error as? StoreMigrationFailure,
                           StoreAggregateMigrationJournalV1.nestedDigestJournalRequiresForwardFix)
            XCTAssertEqual(error as? StoreMigrationFailure, .maintenanceRequired(.forwardFixRequired))
        }
        var future = try jsonObject(awaitingBytes); future["schemaVersion"] = 3
        XCTAssertThrowsError(try StoreAggregateMigrationJournalV1.decodeCanonical(
            from: JSONSerialization.data(withJSONObject: future, options: [.sortedKeys, .withoutEscapingSlashes])))

        let secondStarted = Date()
        guard case .ready(let session) = try await openStartup(
            support: support, identity: identity, processID: semanticID(905)) else {
            _ = sampler.stop()
            return XCTFail("\(label): independent second launch must validate and admit the target")
        }
        let secondLaunchSeconds = Date().timeIntervalSince(secondStarted)
        let peak = sampler.stop()
        let growth = peak > sampler.baseline ? peak - sampler.baseline : 0
        print("V23AggregateUpgradeBudget label=\(label) sites=\(siteCount) firstLaunch=\(String(format: "%.2f", firstLaunchSeconds))s secondLaunch=\(String(format: "%.2f", secondLaunchSeconds))s peakFootprintMB=\(peak / 1_048_576) growthMB=\(growth / 1_048_576)")
        XCTAssertEqual(session.generationID, pending.targetGenerationID)
        XCTAssertEqual(session.storeSchemaRelease, .v53)
        XCTAssertEqual(try session.modelContext.fetchCount(FetchDescriptor<Site>()), siteCount)
        XCTAssertEqual(try StoreGenerationFactory(applicationSupportURL: support)
            .framedSemanticDigestForTesting(in: session.modelContext), manifest.semanticSHA256)
        let complete = try XCTUnwrap(control.load())
        XCTAssertEqual(complete.phase, .complete)
        // Completed schema-1 history stays readable; it is never re-hashed.
        var history = complete; history.schemaVersion = 1
        XCTAssertNoThrow(try history.validate())
        XCTAssertLessThan(firstLaunchSeconds + secondLaunchSeconds, wallBudgetSeconds, label)
        XCTAssertLessThan(growth, footprintBudgetBytes, label)
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

/// Samples this process's physical footprint off the main actor.
private final class SemanticFootprintSampler: @unchecked Sendable {
    let baseline: UInt64
    private let lock = NSLock()
    private var peak: UInt64
    private let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInitiated))

    init() {
        baseline = Self.footprint()
        peak = baseline
        timer.schedule(deadline: .now(), repeating: .milliseconds(20))
        timer.setEventHandler { [weak self] in self?.sample() }
        timer.resume()
    }

    private func sample() {
        let value = Self.footprint()
        lock.lock(); peak = max(peak, value); lock.unlock()
    }

    func stop() -> UInt64 {
        timer.cancel()
        sample()
        lock.lock(); defer { lock.unlock() }
        return peak
    }

    static func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }
}

@MainActor
private func semanticRunBlocking(_ operation: @escaping @MainActor () async throws -> Void) throws {
    var outcome: Result<Void, Error>?
    let done = XCTestExpectation(description: "semantic fixture seeding")
    Task { @MainActor in
        do { try await operation(); outcome = .success(()) } catch { outcome = .failure(error) }
        done.fulfill()
    }
    guard XCTWaiter().wait(for: [done], timeout: 120) == .completed, let outcome else {
        throw CancellationError()
    }
    try outcome.get()
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
    let boundedDigest: String
    let bootstrapManifest: Data
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

private typealias SemanticValidationLighting = CanonicalLightingFixtureV1

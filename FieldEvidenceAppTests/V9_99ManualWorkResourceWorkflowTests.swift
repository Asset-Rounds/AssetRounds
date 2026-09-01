import Foundation
import SwiftData
import XCTest

@testable import FieldEvidenceApp

private struct C36Corpus: Decodable {
    let schema: String
    let schemaVersion: Int
    let cardID: String
    let testOnly: Bool
    let synthetic: Bool
    let containsCustomerData: Bool
    let containsProductionSecrets: Bool
    let evidenceIDs: [String]
    let consumedPersistence: Persistence
    let selectors: Selectors

    struct Persistence: Decodable {
        let manualWorkResource: Version
        let partsStock: Version
        let addsRecordFamily: Bool
    }
    struct Version: Decodable { let schemaVersion: Int; let recordInventoryVersion: Int }
    struct Selectors: Decodable {
        let manualEntryAvailable: Bool
        let stockOptional: Bool
        let stockUseRequiresExplicitSelection: Bool
        let automaticStockMovement: Bool
        let catalogLookup: Bool
        let liveBalanceClaim: Bool
        let accountingClaim: Bool
        let invoiceClaim: Bool
        let availabilityClaim: Bool
        let approvalClaim: Bool
        let usesBinaryFloatingPoint: Bool
        let requiresNetwork: Bool
        let requiresAccount: Bool
        let requiresEntitlement: Bool
    }
}

private enum C36Support {
    static let date = Date(timeIntervalSince1970: 1_810_000_000)
    static func id(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "C3600000-0000-4000-8000-%012x", value))!
    }
    static func mutation(_ value: Int) throws -> MutationIDV1 { try MutationIDV1(rawValue: id(value)) }
    static func digest(_ value: Character) -> String { String(repeating: String(value), count: 64) }

    static func fixture() throws -> C36Corpus {
        let bundle = Bundle(for: V9_99ManualWorkResourceWorkflowTests.self)
        let url = bundle.url(
            forResource: "V23P04C36ManualWorkResourceWorkflowCorpusV1",
            withExtension: "json",
            subdirectory: "Fixtures/V23/WorkResources"
        ) ?? bundle.url(forResource: "V23P04C36ManualWorkResourceWorkflowCorpusV1", withExtension: "json")
        guard let url else { throw ManualWorkResourceWorkflowFailureV1.invalidContext }
        return try JSONDecoder().decode(C36Corpus.self, from: Data(contentsOf: url))
    }

    static func actor(_ workspaceID: WorkspaceID) throws -> ActorSnapshotV1 {
        let local = try LocalActorReferenceV1(
            actorReferenceID: id(10), workspaceID: workspaceID, displayName: "C36 recorder"
        )
        return try ActorSnapshotV1(
            snapshotID: id(11), workspaceID: workspaceID, actor: local,
            responsibility: .recordedBy, displayNameAtTime: "C36 recorder", capturedAt: date
        )
    }

    static func subject(_ workspaceID: WorkspaceID) throws -> WorkResourceSubjectV1 {
        try WorkResourceSubjectV1(
            workspaceID: workspaceID, kind: .workPacket, subjectID: id(20).uuidString,
            subjectRevision: 1, subjectSHA256: digest("s")
        )
    }

    static func material(
        lineID: UUID = id(30), part: LocalPartReferenceSnapshotV1? = nil,
        mantissa: Int64 = 4, scale: Int = 0, unit: String = StockUnitV1.each.rawValue
    ) throws -> ManualMaterialLineV1 {
        try ManualMaterialLineV1(
            lineID: lineID, description: "M8 stainless bolt",
            quantity: ExactDecimalQuantityV1(mantissa: mantissa, scale: scale),
            unit: unit, localPartReference: part
        )
    }

    static func entry(
        workspaceID: WorkspaceID, actor: ActorSnapshotV1, subject: WorkResourceSubjectV1,
        mutation: Int, materials: [ManualMaterialLineV1], predecessor: WorkResourceEntryV1? = nil
    ) throws -> WorkResourceEntryV1 {
        try WorkResourceEntryV1(
            entryID: id(100 + mutation), workspaceID: workspaceID, subject: subject, actor: actor,
            duration: try ManualDurationV1(minutes: 95), materials: materials,
            directCost: try DirectCostEntryV1(
                amount: ExactMoneyAmountV1(mantissa: 1_234, currencyCode: "USD", minorUnitScale: 2),
                note: "Manual field purchase"
            ), recordedAt: date,
            expectedRevision: predecessor?.revision ?? 0, revision: (predecessor?.revision ?? 0) + 1,
            supersedesEntryID: predecessor?.entryID,
            supersedesEntrySHA256: predecessor?.entrySHA256,
            mutationID: C36Support.mutation(mutation)
        )
    }
}

private struct C36Clock: ApplicationClock { func now() -> Date { C36Support.date } }
private final class C36IDSource: ApplicationIDSource {
    private var next = 900
    func makeID() -> UUID { defer { next += 1 }; return C36Support.id(next) }
}
private struct C36FileAuthority: ApplicationFileAuthorityV1 {
    func temporaryRelativePath(mutationID: MutationIDV1, component: String) throws -> String {
        "c36-tests/\(mutationID.rawValue.uuidString.lowercased())/\(component)"
    }
}

@MainActor
private final class C36Harness {
    let workspaceID = WorkspaceID(rawValue: C36Support.id(1))
    let container: ModelContainer
    let context: ModelContext
    let writer: WorkspaceWriterV1
    let actor: ActorSnapshotV1
    let subject: WorkResourceSubjectV1

    init(failure: MutationJournalFailureInjectionV1? = nil, name: String) throws {
        let schema = Schema(PersistentSchemaV41.models, version: PersistentSchemaV41.versionIdentifier)
        container = try ModelContainer(for: schema, migrationPlan: nil, configurations: [
            ModelConfiguration(name, schema: schema, isStoredInMemoryOnly: true, allowsSave: true, cloudKitDatabase: .none)
        ])
        context = container.mainContext
        context.autosaveEnabled = false
        actor = try C36Support.actor(workspaceID)
        context.insert(try ActorSnapshotRow(actor))
        let item = try WorkPacketItemV1(
            itemID: "C36-WORK", kind: .inspection, expectedRevision: 1,
            itemSHA256: C36Support.digest("i")
        )
        let manifest = try WorkPacketManifestV1(
            manifestID: C36Support.id(20), packetID: C36Support.id(21), packetVersion: 1,
            workspaceID: workspaceID, items: [item], packageReleases: [],
            creationBasis: .explicitLocalSelection, creator: actor, createdAt: C36Support.date,
            mutationID: C36Support.mutation(22)
        )
        subject = try WorkResourceSubjectV1(
            workspaceID: workspaceID, kind: .workPacket,
            subjectID: manifest.manifestID.uuidString,
            subjectRevision: manifest.revision, subjectSHA256: manifest.manifestSHA256
        )
        context.insert(try WorkPacketManifestRow(manifest))
        try context.save()
        let identity = try WorkspaceReplicaIdentityV1(
            workspaceID: workspaceID, replicaID: ReplicaID(rawValue: C36Support.id(970))
        )
        let generationID = C36Support.id(971)
        let writerID = C36Support.id(972)
        let journal = try MutationJournalStoreV1(
            modelContext: context, identity: identity, generationID: generationID,
            failureInjection: failure
        )
        writer = try WorkspaceWriterV1(
            identity: identity, generationID: generationID,
            initialRevision: journal.currentRevision(writerInstanceID: writerID),
            clock: C36Clock(), idSource: C36IDSource(), fileAuthority: C36FileAuthority(),
            adapter: WorkspaceWriterAdapterV1(modelContext: context), journalStore: journal
        )
    }

    func coordinator(stock: ManualWorkResourceStockCapabilityV1) throws -> ManualWorkResourceWorkflowCoordinatorV1 {
        let work = WorkResourceCoordinatorV1(writer: writer)
        if stock == .available {
            return try ManualWorkResourceWorkflowCoordinatorV1(
                workResources: work, stock: PartsStockCoordinatorV1(writer: writer), stockCapability: stock
            )
        }
        return try ManualWorkResourceWorkflowCoordinatorV1(workResources: work, stockCapability: stock)
    }

    func coordinator(
        stock: ManualWorkResourceStockCapabilityV1,
        failure: MutationJournalFailureInjectionV1
    ) throws -> ManualWorkResourceWorkflowCoordinatorV1 {
        let identity = try WorkspaceReplicaIdentityV1(
            workspaceID: workspaceID, replicaID: ReplicaID(rawValue: C36Support.id(970))
        )
        let generationID = C36Support.id(971)
        let writerID = C36Support.id(972)
        let journal = try MutationJournalStoreV1(
            modelContext: context, identity: identity, generationID: generationID,
            failureInjection: failure
        )
        let recoveringWriter = try WorkspaceWriterV1(
            identity: identity, generationID: generationID,
            initialRevision: journal.currentRevision(writerInstanceID: writerID),
            clock: C36Clock(), idSource: C36IDSource(), fileAuthority: C36FileAuthority(),
            adapter: WorkspaceWriterAdapterV1(modelContext: context), journalStore: journal
        )
        return try ManualWorkResourceWorkflowCoordinatorV1(
            workResources: WorkResourceCoordinatorV1(writer: recoveringWriter),
            stock: PartsStockCoordinatorV1(writer: recoveringWriter), stockCapability: stock
        )
    }

    func workflowContext(materials: [ManualMaterialLineV1], predecessor: WorkResourceEntryV1? = nil) throws -> ManualWorkResourceWorkflowContextV1 {
        try ManualWorkResourceWorkflowContextV1(
            workspaceID: workspaceID, subject: subject, actor: actor,
            draftDuration: try ManualDurationV1(minutes: 95), draftMaterials: materials,
            draftDirectCost: try DirectCostEntryV1(
                amount: ExactMoneyAmountV1(mantissa: 1_234, currencyCode: "USD", minorUnitScale: 2),
                note: "Manual field purchase"
            ), predecessor: predecessor
        )
    }

    func stockFacts() throws -> (LocalPartDefinitionV1, StockStorageLocationV1, StockBalanceProjectionV1) {
        let part = try LocalPartDefinitionV1(
            partID: C36Support.id(40), workspaceID: workspaceID, displayName: "M8 stainless bolt",
            canonicalUnit: .each, productIdentities: [], revision: 1, mutationID: C36Support.mutation(41)
        )
        let location = try StockStorageLocationV1(
            locationID: C36Support.id(42), workspaceID: workspaceID, kind: .shop,
            label: "Main shop", binLabel: "A1", revision: 1
        )
        _ = try writer.commitPartsStock(.upsertPart(part))
        _ = try writer.commitPartsStock(.upsertLocation(location, mutationID: C36Support.mutation(43)))
        let quantity = try StockQuantityV1(mantissa: 10, scale: 0, unit: .each)
        let movement = try StockMovementEventV1(
            movementID: C36Support.id(44), workspaceID: workspaceID, part: part.frozenReference(),
            locationID: location.locationID, kind: .openingCount, quantity: quantity, unit: .each,
            preBalance: .unknown, postBalance: quantity, actor: actor, occurredAt: C36Support.date,
            recordedAt: C36Support.date, expectedLocationRevision: 0, mutationID: C36Support.mutation(45)
        )
        _ = try writer.commitPartsStock(.appendMovement(movement))
        let balance = StockBalanceProjectionV1(
            workspaceID: workspaceID, partID: part.partID, locationID: location.locationID,
            unit: .each, balance: .known(quantity), locationRevision: movement.locationRevision,
            lastMovementID: movement.movementID
        )
        try balance.validate()
        return (part, location, balance)
    }
}

final class V9_99ManualWorkResourceWorkflowTests: XCTestCase {
    @MainActor
    func testV23P04C36G01ManualValuesAndExplicitStockUseCommitDeterministically() async throws {
        let fixture = try C36Support.fixture()
        XCTAssertEqual(fixture.evidenceIDs.count, 5)
        XCTAssertEqual(fixture.consumedPersistence.manualWorkResource.schemaVersion, 37)
        XCTAssertEqual(fixture.consumedPersistence.manualWorkResource.recordInventoryVersion, 36)
        XCTAssertEqual(fixture.consumedPersistence.partsStock.schemaVersion, 41)
        XCTAssertEqual(fixture.consumedPersistence.partsStock.recordInventoryVersion, 40)
        XCTAssertFalse(fixture.consumedPersistence.addsRecordFamily)
        XCTAssertTrue(fixture.selectors.manualEntryAvailable)
        XCTAssertTrue(fixture.selectors.stockOptional)
        XCTAssertTrue(fixture.selectors.stockUseRequiresExplicitSelection)
        XCTAssertFalse(fixture.selectors.automaticStockMovement)
        XCTAssertFalse(fixture.selectors.catalogLookup)
        XCTAssertFalse(fixture.selectors.liveBalanceClaim)
        XCTAssertFalse(fixture.selectors.accountingClaim)
        XCTAssertFalse(fixture.selectors.invoiceClaim)
        XCTAssertFalse(fixture.selectors.availabilityClaim)
        XCTAssertFalse(fixture.selectors.approvalClaim)
        XCTAssertFalse(fixture.selectors.usesBinaryFloatingPoint)
        XCTAssertFalse(fixture.selectors.requiresNetwork)
        XCTAssertFalse(fixture.selectors.requiresAccount)
        XCTAssertFalse(fixture.selectors.requiresEntitlement)

        let harness = try C36Harness(name: "C36-G")
        let coordinator = try harness.coordinator(stock: .available)
        let (part, location, balance) = try harness.stockFacts()
        let line = try C36Support.material(part: part.frozenReference())
        let context = try harness.workflowContext(materials: [line])
        let projection = coordinator.projection(context: context)
        XCTAssertTrue(projection.canSaveManualEntry)
        XCTAssertFalse(projection.editingChangesStock)
        XCTAssertFalse(projection.accountingClaimed)
        XCTAssertFalse(projection.invoiceClaimed)
        XCTAssertFalse(projection.availabilityClaimed)
        XCTAssertFalse(projection.approvalOrDeliveryClaimed)

        let successor = try ManualWorkResourceSuccessorDraftV1(
            entryID: C36Support.id(50), workspaceID: harness.workspaceID, subject: harness.subject,
            actor: harness.actor, duration: projection.duration, materials: projection.materials,
            directCost: projection.directCost, recordedAt: C36Support.date
        )
        let outcome = try coordinator.execute(.useFromStock(ManualWorkResourceUseStockCommandV1(
            mutationID: C36Support.mutation(53),
            receiptID: C36Support.id(51), movementID: C36Support.id(52),
            frozenMaterialLineID: line.lineID, part: part, source: location,
            quantity: StockQuantityV1(mantissa: 4, scale: 0, unit: .each), sourceBalance: balance,
            actor: harness.actor, occurredAt: C36Support.date, recordedAt: C36Support.date,
            workResourceSuccessor: successor
        )), context: context)
        guard case let .stockUsed(use, receipt) = outcome else { return XCTFail("Expected atomic stock use") }
        XCTAssertEqual(use.mutationID, receipt.mutationID)
        XCTAssertEqual(use.workResourceSuccessor.mutationID, use.mutationID)
        XCTAssertEqual(use.movement.kind, .useOnWork)
        XCTAssertEqual(try harness.context.fetch(FetchDescriptor<StockUseReceiptRowV1>()).count, 1)
        XCTAssertEqual(try harness.context.fetch(FetchDescriptor<ManualWorkResourceRecordRow>()).count, 1)
    }

    @MainActor
    func testV23P04C36A01ManualOnlyAndDisabledStockRemainFullyFunctional() async throws {
        for capability in [ManualWorkResourceStockCapabilityV1.manualOnly, .disabled, .unavailable] {
            let harness = try C36Harness(name: "C36-A-\(capability.rawValue)")
            let coordinator = try harness.coordinator(stock: capability)
            let line = try C36Support.material()
            let context = try harness.workflowContext(materials: [line])
            XCTAssertTrue(coordinator.projection(context: context).canSaveManualEntry)
            let entry = try C36Support.entry(
                workspaceID: harness.workspaceID, actor: harness.actor, subject: harness.subject,
                mutation: 100 + capability.rawValue.count, materials: [line]
            )
            guard case .manualSaved = try coordinator.execute(.saveManual(entry), context: context) else {
                return XCTFail("Manual save must remain available")
            }
            XCTAssertEqual(try harness.context.fetch(FetchDescriptor<ManualWorkResourceRecordRow>()).count, 1)
            XCTAssertEqual(try harness.context.fetch(FetchDescriptor<StockMovementEventRowV1>()).count, 0)
        }
    }

    @MainActor
    func testV23P04C36H01InvalidDraftsFrontiersAndOverreturnFailWithoutEffects() async throws {
        XCTAssertThrowsError(try ExactDecimalQuantityV1(mantissa: 0, scale: 0))
        XCTAssertThrowsError(try ExactDecimalQuantityV1(mantissa: 1, scale: 4))
        XCTAssertThrowsError(try ExactMoneyAmountV1(mantissa: 1, currencyCode: "usd", minorUnitScale: 2))
        XCTAssertThrowsError(try ExactMoneyAmountV1(mantissa: 1, currencyCode: "USD", minorUnitScale: 3))

        let harness = try C36Harness(name: "C36-H")
        let coordinator = try harness.coordinator(stock: .available)
        let (part, location, balance) = try harness.stockFacts()
        let baselineMovements = try harness.context.fetch(FetchDescriptor<StockMovementEventRowV1>()).count
        let baselineWork = try harness.context.fetch(FetchDescriptor<ManualWorkResourceRecordRow>()).count
        let line = try C36Support.material(part: part.frozenReference())
        let context = try harness.workflowContext(materials: [line])
        _ = coordinator.projection(context: context)
        _ = coordinator.projection(context: try harness.workflowContext(materials: [try C36Support.material(mantissa: 2)]))
        XCTAssertEqual(try harness.context.fetch(FetchDescriptor<StockMovementEventRowV1>()).count, baselineMovements)
        XCTAssertEqual(try harness.context.fetch(FetchDescriptor<ManualWorkResourceRecordRow>()).count, baselineWork)

        let stale = try WorkResourceEntryV1(
            entryID: C36Support.id(64), workspaceID: harness.workspaceID,
            subject: harness.subject, actor: harness.actor,
            duration: context.draftDuration, materials: context.draftMaterials,
            directCost: context.draftDirectCost, recordedAt: C36Support.date,
            expectedRevision: 1, revision: 2, mutationID: C36Support.mutation(65)
        )
        XCTAssertThrowsError(try coordinator.execute(.saveManual(stale), context: context))
        XCTAssertEqual(try harness.context.fetch(FetchDescriptor<StockMovementEventRowV1>()).count, baselineMovements)
        XCTAssertEqual(try harness.context.fetch(FetchDescriptor<ManualWorkResourceRecordRow>()).count, baselineWork)

        let successor = try ManualWorkResourceSuccessorDraftV1(
            workspaceID: harness.workspaceID, subject: harness.subject, actor: harness.actor,
            materials: [line], recordedAt: C36Support.date
        )
        for invalidQuantity in [
            try StockQuantityV1(mantissa: 0, scale: 0, unit: .each),
            try StockQuantityV1(mantissa: 4, scale: 0, unit: .meter)
        ] {
            XCTAssertThrowsError(try coordinator.execute(.useFromStock(
                ManualWorkResourceUseStockCommandV1(
                    mutationID: C36Support.mutation(97 + invalidQuantity.scale),
                    receiptID: C36Support.id(90 + invalidQuantity.scale),
                    movementID: C36Support.id(92 + invalidQuantity.scale),
                    frozenMaterialLineID: line.lineID, part: part, source: location,
                    quantity: invalidQuantity, sourceBalance: balance, actor: harness.actor,
                    occurredAt: C36Support.date, recordedAt: C36Support.date,
                    workResourceSuccessor: successor
                )), context: context))
        }
        let otherSubject = try WorkResourceSubjectV1(
            workspaceID: harness.workspaceID, kind: .workPacket,
            subjectID: C36Support.id(94).uuidString, subjectRevision: 1,
            subjectSHA256: C36Support.digest("x")
        )
        let wrongLineage = try ManualWorkResourceSuccessorDraftV1(
            workspaceID: harness.workspaceID, subject: otherSubject, actor: harness.actor,
            materials: [line], recordedAt: C36Support.date
        )
        XCTAssertThrowsError(try coordinator.execute(.useFromStock(
            ManualWorkResourceUseStockCommandV1(
                mutationID: C36Support.mutation(98),
                receiptID: C36Support.id(95), movementID: C36Support.id(96),
                frozenMaterialLineID: line.lineID, part: part, source: location,
                quantity: StockQuantityV1(mantissa: 4, scale: 0, unit: .each),
                sourceBalance: balance, actor: harness.actor,
                occurredAt: C36Support.date, recordedAt: C36Support.date,
                workResourceSuccessor: wrongLineage
            )), context: context))
        XCTAssertEqual(try harness.context.fetch(FetchDescriptor<StockMovementEventRowV1>()).count, baselineMovements)
        XCTAssertEqual(try harness.context.fetch(FetchDescriptor<ManualWorkResourceRecordRow>()).count, baselineWork)
        guard case let .stockUsed(use, _) = try coordinator.execute(.useFromStock(
            ManualWorkResourceUseStockCommandV1(
                mutationID: C36Support.mutation(99),
                receiptID: C36Support.id(66), movementID: C36Support.id(67),
                frozenMaterialLineID: line.lineID, part: part, source: location,
                quantity: StockQuantityV1(mantissa: 4, scale: 0, unit: .each),
                sourceBalance: balance, actor: harness.actor, occurredAt: C36Support.date,
                recordedAt: C36Support.date, workResourceSuccessor: successor
            )), context: context) else { return XCTFail("Expected hostile-test setup use") }
        let afterSetupMovements = try harness.context.fetch(FetchDescriptor<StockMovementEventRowV1>()).count
        let afterSetupWork = try harness.context.fetch(FetchDescriptor<ManualWorkResourceRecordRow>()).count
        let postUse = StockBalanceProjectionV1(
            workspaceID: harness.workspaceID, partID: part.partID, locationID: location.locationID,
            unit: .each, balance: .known(try StockQuantityV1(mantissa: 6, scale: 0, unit: .each)),
            locationRevision: use.movement.locationRevision, lastMovementID: use.movement.movementID
        )
        let returnDraft = try ManualWorkResourceSuccessorDraftV1(
            workspaceID: harness.workspaceID, subject: harness.subject, actor: harness.actor,
            materials: [line], recordedAt: C36Support.date, predecessor: use.workResourceSuccessor
        )
        let returnContext = try harness.workflowContext(materials: [line], predecessor: use.workResourceSuccessor)
        XCTAssertThrowsError(try coordinator.execute(.returnToStock(
            ManualWorkResourceReturnStockCommandV1(
                mutationID: C36Support.mutation(100),
                receiptID: C36Support.id(68), movementID: C36Support.id(69), sourceUse: use,
                predecessorFrontier: nil, workResourcePredecessor: use.workResourceSuccessor,
                destination: location, quantity: StockQuantityV1(mantissa: 5, scale: 0, unit: .each),
                destinationBalance: postUse, actor: harness.actor, occurredAt: C36Support.date,
                recordedAt: C36Support.date, workResourceSuccessor: returnDraft
            )), context: returnContext))
        XCTAssertEqual(try harness.context.fetch(FetchDescriptor<StockMovementEventRowV1>()).count, afterSetupMovements)
        XCTAssertEqual(try harness.context.fetch(FetchDescriptor<ManualWorkResourceRecordRow>()).count, afterSetupWork)

        let wrongPart = try LocalPartDefinitionV1(
            partID: C36Support.id(60), workspaceID: harness.workspaceID, displayName: "Wrong part",
            canonicalUnit: .each, revision: 1, mutationID: C36Support.mutation(61)
        )
        XCTAssertThrowsError(try coordinator.execute(.useFromStock(ManualWorkResourceUseStockCommandV1(
            mutationID: C36Support.mutation(101),
            receiptID: C36Support.id(62), movementID: C36Support.id(63), frozenMaterialLineID: line.lineID,
            part: wrongPart, source: location, quantity: StockQuantityV1(mantissa: 4, scale: 0, unit: .each),
            sourceBalance: balance, actor: harness.actor, occurredAt: C36Support.date,
            recordedAt: C36Support.date, workResourceSuccessor: successor
        )), context: context))
        XCTAssertEqual(try harness.context.fetch(FetchDescriptor<StockMovementEventRowV1>()).count, afterSetupMovements)
        XCTAssertEqual(try harness.context.fetch(FetchDescriptor<ManualWorkResourceRecordRow>()).count, afterSetupWork)
    }

    @MainActor
    func testV23P04C36I01EffectBeforeReceiptRecoveryIsZeroOrOneAtomicComposite() async throws {
        let injection = MutationJournalFailureInjectionV1(failOnceAt: .afterEffectBeforeReceipt)
        let harness = try C36Harness(failure: injection, name: "C36-I")
        let coordinator = try harness.coordinator(stock: .manualOnly)
        let line = try C36Support.material()
        let context = try harness.workflowContext(materials: [line])
        let entry = try C36Support.entry(
            workspaceID: harness.workspaceID, actor: harness.actor, subject: harness.subject,
            mutation: 70, materials: [line]
        )
        XCTAssertThrowsError(try coordinator.execute(.saveManual(entry), context: context))
        let afterInterruption = try harness.context.fetch(FetchDescriptor<ManualWorkResourceRecordRow>()).count
        XCTAssertTrue([0, 1].contains(afterInterruption))
        guard case .manualSaved = try coordinator.execute(.saveManual(entry), context: context) else {
            return XCTFail("Retry must recover the exact manual mutation")
        }
        XCTAssertEqual(try harness.context.fetch(FetchDescriptor<ManualWorkResourceRecordRow>()).count, 1)

        let stockHarness = try C36Harness(name: "C36-I-Stock")
        let (part, location, balance) = try stockHarness.stockFacts()
        let stockCoordinator = try stockHarness.coordinator(
            stock: .available,
            failure: MutationJournalFailureInjectionV1(failOnceAt: .afterEffectBeforeReceipt)
        )
        let stockLine = try C36Support.material(part: part.frozenReference())
        let stockContext = try stockHarness.workflowContext(materials: [stockLine])
        let stockSuccessor = try ManualWorkResourceSuccessorDraftV1(
            workspaceID: stockHarness.workspaceID, subject: stockHarness.subject,
            actor: stockHarness.actor, materials: [stockLine], recordedAt: C36Support.date
        )
        let interruptedUse = ManualWorkResourceUseStockCommandV1(
                mutationID: try C36Support.mutation(75),
                receiptID: C36Support.id(73), movementID: C36Support.id(74),
                frozenMaterialLineID: stockLine.lineID, part: part, source: location,
                quantity: StockQuantityV1(mantissa: 4, scale: 0, unit: .each),
                sourceBalance: balance, actor: stockHarness.actor,
                occurredAt: C36Support.date, recordedAt: C36Support.date,
                workResourceSuccessor: stockSuccessor
            )
        XCTAssertThrowsError(try stockCoordinator.execute(.useFromStock(interruptedUse), context: stockContext))
        let stockUseCount = try stockHarness.context.fetch(FetchDescriptor<StockUseReceiptRowV1>()).count
        let stockWorkCount = try stockHarness.context.fetch(FetchDescriptor<ManualWorkResourceRecordRow>()).count
        XCTAssertEqual(stockUseCount, stockWorkCount, "C55 composite cannot tear stock from frozen work")
        XCTAssertTrue([0, 1].contains(stockUseCount))
        guard case let .stockUsed(recoveredUse, recoveredReceipt) = try stockCoordinator.execute(
            .useFromStock(interruptedUse), context: stockContext
        ) else { return XCTFail("Exact stock retry must recover") }
        XCTAssertEqual(recoveredUse.mutationID, interruptedUse.mutationID)
        XCTAssertEqual(recoveredReceipt.mutationID, interruptedUse.mutationID)
        XCTAssertEqual(try stockHarness.context.fetch(FetchDescriptor<StockUseReceiptRowV1>()).count, 1)
        XCTAssertEqual(try stockHarness.context.fetch(FetchDescriptor<ManualWorkResourceRecordRow>()).count, 1)
        guard case let .stockUsed(replayedUse, replayedUseReceipt) = try stockCoordinator.execute(
            .useFromStock(interruptedUse), context: stockContext
        ) else { return XCTFail("Recovered use must replay exactly") }
        XCTAssertEqual(replayedUse, recoveredUse)
        XCTAssertEqual(replayedUseReceipt, recoveredReceipt)

        let returnCoordinator = try stockHarness.coordinator(
            stock: .available,
            failure: MutationJournalFailureInjectionV1(failOnceAt: .afterEffectBeforeReceipt)
        )
        let postUseBalance = StockBalanceProjectionV1(
            workspaceID: stockHarness.workspaceID, partID: part.partID,
            locationID: location.locationID, unit: .each,
            balance: .known(try StockQuantityV1(mantissa: 6, scale: 0, unit: .each)),
            locationRevision: recoveredUse.movement.locationRevision,
            lastMovementID: recoveredUse.movement.movementID
        )
        let remainingLine = try C36Support.material(
            lineID: stockLine.lineID, part: part.frozenReference(), mantissa: 2
        )
        let returnSuccessor = try ManualWorkResourceSuccessorDraftV1(
            workspaceID: stockHarness.workspaceID, subject: stockHarness.subject,
            actor: stockHarness.actor, materials: [remainingLine], recordedAt: C36Support.date,
            predecessor: recoveredUse.workResourceSuccessor
        )
        let returnContext = try stockHarness.workflowContext(
            materials: [remainingLine], predecessor: recoveredUse.workResourceSuccessor
        )
        let interruptedReturn = ManualWorkResourceReturnStockCommandV1(
            mutationID: try C36Support.mutation(76), receiptID: C36Support.id(77),
            movementID: C36Support.id(78), sourceUse: recoveredUse, predecessorFrontier: nil,
            workResourcePredecessor: recoveredUse.workResourceSuccessor, destination: location,
            quantity: try StockQuantityV1(mantissa: 2, scale: 0, unit: .each),
            destinationBalance: postUseBalance, actor: stockHarness.actor,
            occurredAt: C36Support.date, recordedAt: C36Support.date,
            workResourceSuccessor: returnSuccessor
        )
        XCTAssertThrowsError(try returnCoordinator.execute(
            .returnToStock(interruptedReturn), context: returnContext
        ))
        XCTAssertEqual(
            try stockHarness.context.fetch(FetchDescriptor<StockReturnReceiptRowV1>()).count,
            try stockHarness.context.fetch(FetchDescriptor<ManualWorkResourceRecordRow>()).count - 1
        )
        guard case let .stockReturned(recoveredReturn, recoveredReturnReceipt) = try returnCoordinator.execute(
            .returnToStock(interruptedReturn), context: returnContext
        ) else { return XCTFail("Exact return retry must recover") }
        guard case let .stockReturned(replayedReturn, replayedReturnReceipt) = try returnCoordinator.execute(
            .returnToStock(interruptedReturn), context: returnContext
        ) else { return XCTFail("Recovered return must replay exactly") }
        XCTAssertEqual(replayedReturn, recoveredReturn)
        XCTAssertEqual(replayedReturnReceipt, recoveredReturnReceipt)
        XCTAssertEqual(try stockHarness.context.fetch(FetchDescriptor<StockReturnReceiptRowV1>()).count, 1)
        XCTAssertEqual(try stockHarness.context.fetch(FetchDescriptor<ManualWorkResourceRecordRow>()).count, 2)
    }

    @MainActor
    func testV23P04C36R01IdempotentUseAndExactReturnPreserveLineage() async throws {
        let manualHarness = try C36Harness(name: "C36-R-Manual")
        let manualCoordinator = try manualHarness.coordinator(stock: .manualOnly)
        let manualLine = try C36Support.material()
        let manualContext = try manualHarness.workflowContext(materials: [manualLine])
        let manualEntry = try C36Support.entry(
            workspaceID: manualHarness.workspaceID, actor: manualHarness.actor,
            subject: manualHarness.subject, mutation: 86, materials: [manualLine]
        )
        guard case let .manualSaved(firstManual) = try manualCoordinator.execute(
            .saveManual(manualEntry), context: manualContext
        ), case let .manualSaved(replayedManual) = try manualCoordinator.execute(
            .saveManual(manualEntry), context: manualContext
        ) else { return XCTFail("Expected exact manual replay") }
        XCTAssertEqual(replayedManual, firstManual)
        let divergentManual = try WorkResourceEntryV1(
            entryID: C36Support.id(87), workspaceID: manualHarness.workspaceID,
            subject: manualHarness.subject, actor: manualHarness.actor,
            duration: manualEntry.duration, materials: manualEntry.materials,
            directCost: manualEntry.directCost, recordedAt: manualEntry.recordedAt,
            expectedRevision: manualEntry.expectedRevision, revision: manualEntry.revision,
            mutationID: manualEntry.mutationID
        )
        XCTAssertThrowsError(try manualCoordinator.execute(.saveManual(divergentManual), context: manualContext))
        XCTAssertEqual(
            try manualHarness.context.fetch(FetchDescriptor<ManualWorkResourceRecordRow>()).count, 1
        )

        let harness = try C36Harness(name: "C36-R")
        let coordinator = try harness.coordinator(stock: .available)
        let (part, location, balance) = try harness.stockFacts()
        let line = try C36Support.material(part: part.frozenReference())
        let context = try harness.workflowContext(materials: [line])
        let successorDraft = try ManualWorkResourceSuccessorDraftV1(
            entryID: C36Support.id(80), workspaceID: harness.workspaceID, subject: harness.subject,
            actor: harness.actor, materials: [line], recordedAt: C36Support.date
        )
        let command = ManualWorkResourceUseStockCommandV1(
            mutationID: try C36Support.mutation(102),
            receiptID: C36Support.id(81), movementID: C36Support.id(82), frozenMaterialLineID: line.lineID,
            part: part, source: location, quantity: StockQuantityV1(mantissa: 4, scale: 0, unit: .each),
            sourceBalance: balance, actor: harness.actor, occurredAt: C36Support.date,
            recordedAt: C36Support.date, workResourceSuccessor: successorDraft
        )
        guard case let .stockUsed(use, firstReceipt) = try coordinator.execute(.useFromStock(command), context: context) else {
            return XCTFail("Expected use")
        }
        guard case let .stockUsed(replayedUse, replayedUseReceipt) = try coordinator.execute(
            .useFromStock(command), context: context
        ) else { return XCTFail("Expected exact use replay") }
        XCTAssertEqual(replayedUse, use)
        XCTAssertEqual(replayedUseReceipt, firstReceipt)
        let postUse = StockBalanceProjectionV1(
            workspaceID: harness.workspaceID, partID: part.partID, locationID: location.locationID,
            unit: .each, balance: .known(try StockQuantityV1(mantissa: 6, scale: 0, unit: .each)),
            locationRevision: use.movement.locationRevision, lastMovementID: use.movement.movementID
        )
        let returnedLine = try C36Support.material(
            lineID: line.lineID, part: part.frozenReference(), mantissa: 2
        )
        let returnDraft = try ManualWorkResourceSuccessorDraftV1(
            entryID: C36Support.id(83), workspaceID: harness.workspaceID, subject: harness.subject,
            actor: harness.actor, materials: [returnedLine], recordedAt: C36Support.date,
            predecessor: use.workResourceSuccessor
        )
        let returnContext = try harness.workflowContext(materials: [returnedLine], predecessor: use.workResourceSuccessor)
        let returnCommand = ManualWorkResourceReturnStockCommandV1(
                mutationID: try C36Support.mutation(103),
                receiptID: C36Support.id(84), movementID: C36Support.id(85), sourceUse: use,
                predecessorFrontier: nil, workResourcePredecessor: use.workResourceSuccessor,
                destination: location, quantity: StockQuantityV1(mantissa: 2, scale: 0, unit: .each),
                destinationBalance: postUse, actor: harness.actor, occurredAt: C36Support.date,
                recordedAt: C36Support.date, workResourceSuccessor: returnDraft
            )
        guard case let .stockReturned(returned, returnReceipt) = try coordinator.execute(
            .returnToStock(returnCommand), context: returnContext
        ) else { return XCTFail("Expected return") }
        guard case let .stockReturned(replayedReturn, replayedReturnReceipt) = try coordinator.execute(
            .returnToStock(returnCommand), context: returnContext
        ) else { return XCTFail("Expected exact return replay") }
        XCTAssertEqual(replayedReturn, returned)
        XCTAssertEqual(replayedReturnReceipt, returnReceipt)
        XCTAssertEqual(returned.returnMovement.relatedMovementID, use.movement.movementID)
        XCTAssertEqual(returned.returnMovement.postBalance.mantissa, 8)
        XCTAssertEqual(returned.mutationID, returnReceipt.mutationID)
        XCTAssertNotEqual(firstReceipt.mutationID, returnReceipt.mutationID)
        let beforeRejectedReturn = try harness.context.fetch(FetchDescriptor<StockReturnReceiptRowV1>()).count
        XCTAssertThrowsError(try coordinator.execute(.returnToStock(
            ManualWorkResourceReturnStockCommandV1(
                mutationID: returnCommand.mutationID,
                receiptID: C36Support.id(88), movementID: C36Support.id(89), sourceUse: use,
                predecessorFrontier: nil, workResourcePredecessor: use.workResourceSuccessor,
                destination: location, quantity: StockQuantityV1(mantissa: 2, scale: 0, unit: .each),
                destinationBalance: postUse, actor: harness.actor, occurredAt: C36Support.date,
                recordedAt: C36Support.date, workResourceSuccessor: returnDraft
            )), context: returnContext))
        XCTAssertEqual(
            try harness.context.fetch(FetchDescriptor<StockReturnReceiptRowV1>()).count,
            beforeRejectedReturn
        )
        XCTAssertEqual(try harness.context.fetch(FetchDescriptor<StockUseReceiptRowV1>()).count, 1)
        XCTAssertEqual(try harness.context.fetch(FetchDescriptor<StockReturnReceiptRowV1>()).count, 1)
        XCTAssertEqual(try harness.context.fetch(FetchDescriptor<ManualWorkResourceRecordRow>()).count, 2)
        XCTAssertEqual(try harness.context.fetch(FetchDescriptor<StockMovementEventRowV1>()).count, 3)
    }
}

import Foundation
import SwiftData
import XCTest

@testable import FieldEvidenceApp

private struct C55PartsStockCorpusFixture: Decodable {
    let schema: String
    let schemaVersion: Int
    let cardID: String
    let corpusID: String
    let corpusVersion: String
    let testOnly: Bool
    let synthetic: Bool
    let immutable: Bool
    let containsCustomerData: Bool
    let containsProductionSecrets: Bool
    let deterministicSeed: String
    let contracts: [String]
    let persistenceRows: [String]
    let evidenceIDs: [String]
    let units: [String]
    let storageKinds: [String]
    let movementKinds: [String]
    let golden: Scenario
    let alternate: Scenario
    let hostileVectors: HostileVectors
    let claims: Claims
    let hostileCases: [String]
    let recoveryCases: [String]
    let forbiddenCapabilities: [String]

    struct Quantity: Decodable {
        let mantissa: Int64
        let scale: Int
    }

    struct Scenario: Decodable {
        let displayName: String
        let canonicalUnit: String
        let sku: String
        let manufacturerCode: String
        let storageKind: String
        let storageLabel: String
        let binLabel: String
        let preferredMinimum: Quantity
        let opening: Quantity
        let physicalCount: Quantity
        let destinationOpening: Quantity
        let adjustmentIncrease: Quantity
        let transfer: Quantity
        let use: Quantity
        let `return`: Quantity
    }

    struct HostileVectors: Decodable {
        let negativeMantissa: Int64
        let zeroMagnitude: Int64
        let invalidScale: Int
        let overflowExpectedReturnedMantissa: Int64
        let underflowExpectedReturnedMantissa: Int64
    }

    struct Claims: Decodable {
        let unknownNeverZero: Bool
        let openingOrCountEstablishesKnown: Bool
        let adjustmentRequiresKnown: Bool
        let useRequiresSufficientKnown: Bool
        let transferRequiresKnownBothSides: Bool
        let transferIsAtomic: Bool
        let returnIsProvenanceBound: Bool
        let returnUsesCASFrontier: Bool
        let ordinaryRetirementRequiresKnownZero: Bool
        let revisionCannotArchive: Bool
        let appendOnly: Bool
        let noNegativeKnown: Bool
        let abandonmentPreservesUnknown: Bool
        let reportExcludesBalancesAndStorage: Bool
        let cloneCopiesDefinitionsOnly: Bool
        let forkRequiresRecount: Bool
        let retryIsIdempotent: Bool
        let featureDisablePreservesReadExportRecovery: Bool
    }
}

private enum C55PartsStockFixtureFailure: Error {
    case invalidFixture
}

private enum C55PartsStockTestSupport {
    static let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)

    static func fixture() throws -> C55PartsStockCorpusFixture {
        let bundle = Bundle(for: V9_63PartsStockTests.self)
        let url = bundle.url(
            forResource: "V22P03C55PartsStockCorpusV1",
            withExtension: "json",
            subdirectory: "Fixtures/V22/PartsStock"
        ) ?? bundle.url(forResource: "V22P03C55PartsStockCorpusV1", withExtension: "json")
        guard let url else { throw C55PartsStockFixtureFailure.invalidFixture }
        return try JSONDecoder().decode(C55PartsStockCorpusFixture.self, from: Data(contentsOf: url))
    }

    static func id(_ slot: Int) -> UUID {
        UUID(uuidString: String(format: "C5500000-0000-4000-8000-%012x", slot))!
    }

    static func workspace(_ slot: Int = 1) -> WorkspaceID {
        WorkspaceID(rawValue: id(slot))
    }

    static func mutation(_ slot: Int) throws -> MutationIDV1 {
        try MutationIDV1(rawValue: id(slot))
    }

    static func date(_ offset: TimeInterval = 0) -> Date {
        fixedDate.addingTimeInterval(offset)
    }

    static func digest(_ character: Character) -> String {
        String(repeating: String(character), count: 64)
    }

    static func unit(_ rawValue: String) throws -> StockUnitV1 {
        guard let value = StockUnitV1(rawValue: rawValue) else {
            throw C55PartsStockFixtureFailure.invalidFixture
        }
        return value
    }

    static func storageKind(_ rawValue: String) throws -> StockStorageKindV1 {
        guard let value = StockStorageKindV1(rawValue: rawValue) else {
            throw C55PartsStockFixtureFailure.invalidFixture
        }
        return value
    }

    static func movementKind(_ rawValue: String) throws -> StockMovementKindV1 {
        guard let value = StockMovementKindV1(rawValue: rawValue) else {
            throw C55PartsStockFixtureFailure.invalidFixture
        }
        return value
    }

    static func exact(_ quantity: C55PartsStockCorpusFixture.Quantity) throws -> ExactDecimalQuantityV1 {
        try ExactDecimalQuantityV1(mantissa: quantity.mantissa, scale: quantity.scale)
    }

    static func exact(_ quantity: StockQuantityV1) throws -> ExactDecimalQuantityV1 {
        try ExactDecimalQuantityV1(mantissa: quantity.mantissa, scale: quantity.scale)
    }

    static func stock(
        _ quantity: C55PartsStockCorpusFixture.Quantity,
        unit: StockUnitV1
    ) throws -> StockQuantityV1 {
        try StockQuantityV1(mantissa: quantity.mantissa, scale: quantity.scale, unit: unit)
    }

    static func actor(
        workspaceID: WorkspaceID,
        slot: Int = 10,
        displayName: String = "C55 deterministic actor"
    ) throws -> ActorSnapshotV1 {
        let local = try LocalActorReferenceV1(
            actorReferenceID: id(slot),
            workspaceID: workspaceID,
            displayName: displayName
        )
        return try ActorSnapshotV1(
            snapshotID: id(slot + 1),
            workspaceID: workspaceID,
            actor: local,
            responsibility: .recordedBy,
            displayNameAtTime: displayName,
            capturedAt: fixedDate
        )
    }

    static func part(
        _ scenario: C55PartsStockCorpusFixture.Scenario,
        workspaceID: WorkspaceID,
        slot: Int = 20
    ) throws -> LocalPartDefinitionV1 {
        let unit = try unit(scenario.canonicalUnit)
        let identities = try [
            StockProductIdentityV1(kind: .manufacturer, value: scenario.manufacturerCode),
            StockProductIdentityV1(kind: .sku, value: scenario.sku)
        ]
        return try LocalPartDefinitionV1(
            partID: id(slot),
            workspaceID: workspaceID,
            displayName: scenario.displayName,
            canonicalUnit: unit,
            productIdentities: identities,
            preferredMinimum: try stock(scenario.preferredMinimum, unit: unit),
            revision: 1,
            mutationID: try mutation(slot + 1)
        )
    }

    static func location(
        _ scenario: C55PartsStockCorpusFixture.Scenario,
        workspaceID: WorkspaceID,
        slot: Int = 40,
        revision: UInt64 = 1
    ) throws -> StockStorageLocationV1 {
        try StockStorageLocationV1(
            locationID: id(slot),
            workspaceID: workspaceID,
            kind: storageKind(scenario.storageKind),
            label: scenario.storageLabel,
            binLabel: scenario.binLabel,
            revision: revision
        )
    }

    static func projection(
        workspaceID: WorkspaceID,
        partID: UUID,
        locationID: UUID,
        unit: StockUnitV1,
        balance: StockBalanceV1,
        locationRevision: UInt64,
        lastMovementID: UUID?
    ) throws -> StockBalanceProjectionV1 {
        let value = StockBalanceProjectionV1(
            workspaceID: workspaceID,
            partID: partID,
            locationID: locationID,
            unit: unit,
            balance: balance,
            locationRevision: locationRevision,
            lastMovementID: lastMovementID
        )
        try value.validate()
        return value
    }

    static func movement(
        movementID: UUID,
        workspaceID: WorkspaceID,
        part: LocalPartReferenceSnapshotV1,
        locationID: UUID,
        kind: StockMovementKindV1,
        quantity: StockQuantityV1,
        unit: StockUnitV1,
        preBalance: StockBalanceV1,
        postBalance: StockQuantityV1,
        relatedMovementID: UUID? = nil,
        reason: String? = nil,
        actor: ActorSnapshotV1,
        expectedLocationRevision: UInt64,
        mutationSlot: Int,
        occurredOffset: TimeInterval = 0
    ) throws -> StockMovementEventV1 {
        try StockMovementEventV1(
            movementID: movementID,
            workspaceID: workspaceID,
            part: part,
            locationID: locationID,
            kind: kind,
            quantity: quantity,
            unit: unit,
            preBalance: preBalance,
            postBalance: postBalance,
            relatedMovementID: relatedMovementID,
            reason: reason,
            actor: actor,
            occurredAt: date(occurredOffset),
            recordedAt: date(occurredOffset + 1),
            expectedLocationRevision: expectedLocationRevision,
            mutationID: try mutation(mutationSlot)
        )
    }

    static func workEntry(
        workspaceID: WorkspaceID,
        part: LocalPartReferenceSnapshotV1,
        quantity: ExactDecimalQuantityV1,
        lineID: UUID,
        mutationID: MutationIDV1,
        slot: Int = 500,
        subject: WorkResourceSubjectV1? = nil,
        entryActor: ActorSnapshotV1? = nil,
        materialUnit: String? = nil
    ) throws -> WorkResourceEntryV1 {
        let entrySubject: WorkResourceSubjectV1
        if let subject {
            entrySubject = subject
        } else {
            entrySubject = try WorkResourceSubjectV1(
                workspaceID: workspaceID,
                kind: .workPacket,
                subjectID: id(slot).uuidString,
                subjectRevision: 1,
                subjectSHA256: digest("w")
            )
        }
        let material = try ManualMaterialLineV1(
            lineID: lineID,
            description: part.displayName,
            quantity: quantity,
            unit: materialUnit ?? StockUnitV1.each.rawValue,
            localPartReference: part
        )
        let resolvedActor: ActorSnapshotV1
        if let entryActor {
            resolvedActor = entryActor
        } else {
            resolvedActor = try actor(workspaceID: workspaceID, slot: slot + 2)
        }
        return try WorkResourceEntryV1(
            entryID: id(slot + 1),
            workspaceID: workspaceID,
            subject: entrySubject,
            actor: resolvedActor,
            materials: [material],
            recordedAt: date(100 + TimeInterval(slot)),
            expectedRevision: 0,
            revision: 1,
            mutationID: mutationID
        )
    }

    static func workSuccessor(
        of predecessor: WorkResourceEntryV1,
        part: LocalPartReferenceSnapshotV1,
        quantity: StockQuantityV1?,
        lineID: UUID,
        mutationID: MutationIDV1,
        disposition: WorkResourceDispositionV1 = .active,
        materialUnit: String? = nil,
        slot: Int
    ) throws -> WorkResourceEntryV1 {
        let materials: [ManualMaterialLineV1]
        if let quantity {
            let prior = predecessor.materials.first { $0.lineID == lineID }
            materials = [try ManualMaterialLineV1(
                lineID: lineID,
                description: prior?.description ?? part.displayName,
                quantity: try exact(quantity),
                unit: materialUnit ?? prior?.unit ?? StockUnitV1.each.rawValue,
                localPartReference: part
            )]
        } else {
            materials = []
        }
        return try WorkResourceEntryV1(
            entryID: id(slot),
            workspaceID: predecessor.workspaceID,
            subject: predecessor.subject,
            actor: predecessor.actor,
            duration: quantity == nil ? try ManualDurationV1(minutes: 1) : nil,
            materials: materials,
            directCost: nil,
            visibility: predecessor.visibility,
            disposition: disposition,
            recordedAt: date(200 + TimeInterval(slot)),
            expectedRevision: predecessor.revision,
            revision: predecessor.revision + 1,
            supersedesEntryID: predecessor.entryID,
            supersedesEntrySHA256: predecessor.entrySHA256,
            mutationID: mutationID
        )
    }

    static func useReceipt(
        workspaceID: WorkspaceID,
        part: LocalPartDefinitionV1,
        location: StockStorageLocationV1,
        quantity: StockQuantityV1,
        preBalance: StockQuantityV1,
        postBalance: StockQuantityV1,
        expectedLocationRevision: UInt64 = 1,
        slot: Int = 600,
        workResourceSubject: WorkResourceSubjectV1? = nil,
        workResourceActor: ActorSnapshotV1? = nil,
        workResourceMaterialUnit: String? = nil
    ) throws -> StockUseOnWorkReceiptV1 {
        let lineID = id(slot)
        let movement = try movement(
            movementID: id(slot + 1),
            workspaceID: workspaceID,
            part: try part.frozenReference(),
            locationID: location.locationID,
            kind: .useOnWork,
            quantity: quantity,
            unit: part.canonicalUnit,
            preBalance: .known(preBalance),
            postBalance: postBalance,
            actor: try actor(workspaceID: workspaceID, slot: slot + 2),
            expectedLocationRevision: expectedLocationRevision,
            mutationSlot: slot + 3
        )
        return try StockUseOnWorkReceiptV1(
            receiptID: id(slot + 4),
            movement: movement,
            workResourceSuccessor: try workEntry(
                workspaceID: workspaceID,
                part: movement.part,
                quantity: try exact(quantity),
                lineID: lineID,
                mutationID: movement.mutationID,
                slot: slot + 10,
                subject: workResourceSubject,
                entryActor: workResourceActor,
                materialUnit: workResourceMaterialUnit
            ),
            frozenMaterialLineID: lineID,
            mutationID: movement.mutationID
        )
    }

    static func returnReceipt(
        sourceUse: StockUseOnWorkReceiptV1,
        destination: StockStorageLocationV1,
        destinationPreBalance: StockQuantityV1,
        quantity: StockQuantityV1,
        predecessorFrontier: StockReturnFrontierSnapshotV1?,
        workResourcePredecessor: WorkResourceEntryV1,
        workResourceSuccessor: WorkResourceEntryV1,
        expectedLocationRevision: UInt64 = 2,
        movementSlot: Int,
        receiptSlot: Int
    ) throws -> StockReturnAgainstUseReceiptV1 {
        let (postMantissa, overflow) = destinationPreBalance.mantissa.addingReportingOverflow(quantity.mantissa)
        guard !overflow else { throw C55PartsStockFixtureFailure.invalidFixture }
        let movement = try movement(
            movementID: id(movementSlot),
            workspaceID: sourceUse.workspaceID,
            part: sourceUse.movement.part,
            locationID: destination.locationID,
            kind: .returnAgainstUse,
            quantity: quantity,
            unit: sourceUse.movement.unit,
            preBalance: .known(destinationPreBalance),
            postBalance: try StockQuantityV1(mantissa: postMantissa, scale: destinationPreBalance.scale, unit: sourceUse.movement.unit),
            relatedMovementID: sourceUse.movement.movementID,
            actor: try actor(workspaceID: sourceUse.workspaceID, slot: movementSlot + 1),
            expectedLocationRevision: expectedLocationRevision,
            mutationSlot: movementSlot + 2
        )
        return try StockReturnAgainstUseReceiptV1(
            receiptID: id(receiptSlot),
            sourceUse: sourceUse,
            predecessorFrontier: predecessorFrontier,
            returnMovement: movement,
            workResourcePredecessor: workResourcePredecessor,
            workResourceSuccessor: workResourceSuccessor,
            mutationID: movement.mutationID
        )
    }

    static func reversalReceipt(
        sourceUse: StockUseOnWorkReceiptV1,
        destination: StockStorageLocationV1,
        destinationPreBalance: StockQuantityV1,
        reason: String,
        expectedLocationRevision: UInt64 = 1,
        slot: Int
    ) throws -> StockUseReversalReceiptV1 {
        let (postMantissa, overflow) = destinationPreBalance.mantissa.addingReportingOverflow(sourceUse.movement.quantity.mantissa)
        guard !overflow else { throw C55PartsStockFixtureFailure.invalidFixture }
        let movement = try movement(
            movementID: id(slot),
            workspaceID: sourceUse.workspaceID,
            part: sourceUse.movement.part,
            locationID: destination.locationID,
            kind: .reverseUse,
            quantity: sourceUse.movement.quantity,
            unit: sourceUse.movement.unit,
            preBalance: .known(destinationPreBalance),
            postBalance: try StockQuantityV1(mantissa: postMantissa, scale: destinationPreBalance.scale, unit: sourceUse.movement.unit),
            relatedMovementID: sourceUse.movement.movementID,
            reason: reason,
            actor: try actor(workspaceID: sourceUse.workspaceID, slot: slot + 1),
            expectedLocationRevision: expectedLocationRevision,
            mutationSlot: slot + 2
        )
        let successor = try workSuccessor(
            of: sourceUse.workResourceSuccessor,
            part: sourceUse.movement.part,
            quantity: nil,
            lineID: sourceUse.frozenMaterialLineID,
            mutationID: movement.mutationID,
            disposition: .reversed,
            slot: slot + 3
        )
        return try StockUseReversalReceiptV1(
            receiptID: id(slot + 4),
            sourceUse: sourceUse,
            reversalMovement: movement,
            workResourceSuccessor: successor,
            reason: reason,
            mutationID: movement.mutationID
        )
    }
}

@MainActor
private final class C55InMemoryWriter: PartsStockCanonicalWriterPortV1 {
    private var nextMutationSlot = 900
    private var committed: [MutationIDV1: (mutation: PartsStockMutationV1, receipt: PartsStockMutationReceiptV1)] = [:]
    private(set) var mutations: [PartsStockMutationV1] = []
    private(set) var makeMutationIDCalls = 0
    private(set) var commitCalls = 0

    func makeMutationID() throws -> MutationIDV1 {
        makeMutationIDCalls += 1
        defer { nextMutationSlot += 1 }
        return try C55PartsStockTestSupport.mutation(nextMutationSlot)
    }

    func commitPartsStock(_ mutation: PartsStockMutationV1) throws -> PartsStockMutationReceiptV1 {
        commitCalls += 1
        try mutation.validate()
        if let prior = committed[mutation.mutationID] {
            guard prior.mutation == mutation else { throw PartsStockFailureV1.duplicateMutation }
            return prior.receipt
        }
        let receipt = try PartsStockMutationReceiptV1(
            workspaceID: mutation.workspaceID,
            mutationID: mutation.mutationID,
            mutationSHA256: try PartsStockCanonicalCodecV1.sha256(mutation),
            committedAt: C55PartsStockTestSupport.fixedDate
        )
        committed[mutation.mutationID] = (mutation, receipt)
        mutations.append(mutation)
        return receipt
    }
}

@MainActor
private final class C55PartsStockLifecycleSpy: PartsStockLifecyclePortV1 {
    let restoreEffectSHA256: String
    private(set) var restoreCalls = 0
    private(set) var deleteCalls = 0
    private(set) var eraseCalls = 0
    private(set) var rebuildCalls = 0

    init(restoreEffectSHA256: String) {
        self.restoreEffectSHA256 = restoreEffectSHA256
    }

    func restorePartsStock(
        _ snapshot: PartsStockBackupSnapshotV1,
        targetWorkspaceID: WorkspaceID,
        operationID: UUID,
        disposition: PartsStockRestoreDispositionV1
    ) async throws -> PartsStockLifecycleReceiptV1 {
        restoreCalls += 1
        return try PartsStockLifecycleReceiptV1(
            operationID: operationID,
            sourceWorkspaceID: snapshot.workspaceID,
            targetWorkspaceID: targetWorkspaceID,
            disposition: disposition,
            snapshotSHA256: snapshot.snapshotSHA256,
            effectSHA256: restoreEffectSHA256,
            completedAt: C55PartsStockTestSupport.fixedDate
        )
    }

    func deletePartsStock(workspaceID: WorkspaceID) async throws {
        deleteCalls += 1
    }

    func erasePartsStock(workspaceID: WorkspaceID) async throws {
        eraseCalls += 1
    }

    func rebuildPartsStockSearch(workspaceID: WorkspaceID) async throws {
        rebuildCalls += 1
    }
}

private struct C55ProductionWriterClock: ApplicationClock {
    func now() -> Date { C55PartsStockTestSupport.fixedDate }
}

private struct C55ProductionWriterIDSource: ApplicationIDSource {
    let value: UUID
    func makeID() -> UUID { value }
}

private struct C55ProductionWriterFileAuthority: ApplicationFileAuthorityV1 {
    func temporaryRelativePath(mutationID: MutationIDV1, component: String) throws -> String {
        "c55-production-writer/\(mutationID.rawValue.uuidString.lowercased())/\(component)"
    }
}

@MainActor
private final class C55ProductionWriterHarness {
    let container: ModelContainer
    let context: ModelContext
    let journal: MutationJournalStoreV1
    let writer: WorkspaceWriterV1

    init(workspaceID: WorkspaceID, configurationName: String = "C55-Production-Writer") throws {
        let schema = Schema(
            PersistentSchemaV41.models,
            version: PersistentSchemaV41.versionIdentifier
        )
        let installedContainer = try ModelContainer(
            for: schema,
            migrationPlan: nil,
            configurations: [ModelConfiguration(
                configurationName, schema: schema, isStoredInMemoryOnly: true,
                allowsSave: true, cloudKitDatabase: .none
            )]
        )
        let installedContext = installedContainer.mainContext
        installedContext.autosaveEnabled = false
        let identity = try WorkspaceReplicaIdentityV1(
            workspaceID: workspaceID,
            replicaID: ReplicaID(rawValue: C55PartsStockTestSupport.id(971))
        )
        let generationID = C55PartsStockTestSupport.id(970)
        let writerInstanceID = C55PartsStockTestSupport.id(972)
        let installedJournal = try MutationJournalStoreV1(
            modelContext: installedContext,
            identity: identity,
            generationID: generationID
        )
        container = installedContainer
        context = installedContext
        journal = installedJournal
        writer = try WorkspaceWriterV1(
            identity: identity,
            generationID: generationID,
            initialRevision: installedJournal.currentRevision(writerInstanceID: writerInstanceID),
            clock: C55ProductionWriterClock(),
            idSource: C55ProductionWriterIDSource(value: writerInstanceID),
            fileAuthority: C55ProductionWriterFileAuthority(),
            adapter: WorkspaceWriterAdapterV1(modelContext: installedContext),
            journalStore: installedJournal
        )
    }
}

final class V9_63PartsStockTests: XCTestCase {
    func testV23P03C55G01CanonicalUnitsLabelsAndUnknownToKnownProjection() throws {
        let fixture = try Self.fixture()
        XCTAssertEqual(fixture.schema, "V22P03C55PartsStockCorpusV1")
        XCTAssertEqual(fixture.schemaVersion, 1)
        XCTAssertEqual(fixture.corpusVersion, "V22")
        XCTAssertEqual(fixture.cardID, "V23-P03-C55")
        XCTAssertEqual(fixture.corpusID, "v22-p03-c55-parts-stock-corpus-v1")
        XCTAssertTrue(fixture.testOnly)
        XCTAssertTrue(fixture.synthetic)
        XCTAssertTrue(fixture.immutable)
        XCTAssertFalse(fixture.containsCustomerData)
        XCTAssertFalse(fixture.containsProductionSecrets)
        XCTAssertEqual(fixture.deterministicSeed, "C55-V22-FIXED-0001")
        XCTAssertEqual(
            Set(fixture.contracts),
            Set([
                "LocalPartDefinitionV1", "StockStorageLocationV1", "StockMovementEventV1", "StockBalanceProjectionV1",
                "StockTransferReceiptV1", "StockUseOnWorkReceiptV1", "StockUseReversalReceiptV1",
                "StockReturnAgainstUseReceiptV1", "AbandonUnverifiedStockDispositionV1",
                "StockAbandonmentReceiptV1", "StockPartRetirementReceiptV1", "PartsStockMutationV1",
                "PartsStockBackupSnapshotV1"
            ])
        )
        XCTAssertEqual(fixture.contracts.count, 13)
        XCTAssertEqual(
            fixture.persistenceRows,
            [
                "LocalPartDefinitionRowV1", "StockStorageLocationRowV1", "StockMovementEventRowV1",
                "StockUseReceiptRowV1", "StockUseReversalReceiptRowV1", "StockReturnReceiptRowV1",
                "AbandonUnverifiedStockRowV1"
            ]
        )
        XCTAssertEqual(fixture.persistenceRows.count, 7)
        XCTAssertEqual(
            fixture.evidenceIDs,
            [
                "V23-P03-C55-G01", "V23-P03-C55-A01", "V23-P03-C55-H01",
                "V23-P03-C55-I01", "V23-P03-C55-R01"
            ]
        )
        XCTAssertEqual(Set(fixture.units), Set(StockUnitV1.allCases.map(\.rawValue)))
        XCTAssertEqual(Set(fixture.storageKinds), Set(StockStorageKindV1.allCases.map(\.rawValue)))
        XCTAssertEqual(Set(fixture.movementKinds), Set(StockMovementKindV1.allCases.map(\.rawValue)))

        XCTAssertTrue(fixture.claims.unknownNeverZero)
        XCTAssertTrue(fixture.claims.openingOrCountEstablishesKnown)
        XCTAssertTrue(fixture.claims.appendOnly)
        XCTAssertTrue(fixture.claims.noNegativeKnown)
        XCTAssertEqual(
            Set(fixture.forbiddenCapabilities),
            Set([
                "VENDORS", "PROCUREMENT", "PURCHASING", "PURCHASE_ORDERS", "VALUATION", "TAX",
                "INVOICING", "PAYROLL", "SERIALIZED_LOTS", "RESERVATIONS", "CLOUD_SYNC",
                "REPLENISHMENT_AUTOMATION"
            ])
        )

        let workspaceID = C55PartsStockTestSupport.workspace()
        let part = try C55PartsStockTestSupport.part(fixture.golden, workspaceID: workspaceID)
        let location = try C55PartsStockTestSupport.location(fixture.golden, workspaceID: workspaceID)
        let unit = part.canonicalUnit
        XCTAssertEqual(part.displayName, fixture.golden.displayName)
        XCTAssertEqual(part.canonicalUnit.rawValue, fixture.golden.canonicalUnit)
        XCTAssertEqual(part.productIdentities.map(\.value), [fixture.golden.sku, fixture.golden.manufacturerCode].sorted())
        XCTAssertEqual(part.preferredMinimum?.mantissa, fixture.golden.preferredMinimum.mantissa)
        XCTAssertEqual(location.kind.rawValue, fixture.golden.storageKind)
        XCTAssertEqual(location.label, fixture.golden.storageLabel)
        XCTAssertEqual(location.binLabel, fixture.golden.binLabel)

        let unknown = try C55PartsStockTestSupport.projection(
            workspaceID: workspaceID,
            partID: part.partID,
            locationID: location.locationID,
            unit: unit,
            balance: .unknown,
            locationRevision: 0,
            lastMovementID: nil
        )
        if case .known = unknown.balance { XCTFail("a new location must remain UNKNOWN") }

        let opening = try C55PartsStockTestSupport.stock(fixture.golden.opening, unit: unit)
        let openingMovement = try C55PartsStockTestSupport.movement(
            movementID: C55PartsStockTestSupport.id(60),
            workspaceID: workspaceID,
            part: try part.frozenReference(),
            locationID: location.locationID,
            kind: .openingCount,
            quantity: try C55PartsStockTestSupport.stock(fixture.golden.opening, unit: unit),
            unit: unit,
            preBalance: unknown.balance,
            postBalance: opening,
            actor: try C55PartsStockTestSupport.actor(workspaceID: workspaceID),
            expectedLocationRevision: unknown.locationRevision,
            mutationSlot: 61
        )
        XCTAssertEqual(openingMovement.preBalance, .unknown)
        XCTAssertEqual(openingMovement.postBalance, opening)
        XCTAssertEqual(openingMovement.locationRevision, 1)

        let afterOpening = try C55PartsStockTestSupport.projection(
            workspaceID: workspaceID,
            partID: part.partID,
            locationID: location.locationID,
            unit: unit,
            balance: .known(opening),
            locationRevision: openingMovement.locationRevision,
            lastMovementID: openingMovement.movementID
        )
        let counted = try C55PartsStockTestSupport.stock(fixture.golden.physicalCount, unit: unit)
        let countMovement = try C55PartsStockTestSupport.movement(
            movementID: C55PartsStockTestSupport.id(62),
            workspaceID: workspaceID,
            part: try part.frozenReference(),
            locationID: location.locationID,
            kind: .physicalCount,
            quantity: try C55PartsStockTestSupport.stock(fixture.golden.physicalCount, unit: unit),
            unit: unit,
            preBalance: afterOpening.balance,
            postBalance: counted,
            actor: try C55PartsStockTestSupport.actor(workspaceID: workspaceID, slot: 12),
            expectedLocationRevision: afterOpening.locationRevision,
            mutationSlot: 63,
            occurredOffset: 2
        )
        XCTAssertEqual(countMovement.preBalance, .known(opening))
        XCTAssertEqual(countMovement.postBalance, counted)
        XCTAssertEqual(countMovement.locationRevision, 2)

        let alternateUnit = try C55PartsStockTestSupport.unit(fixture.alternate.canonicalUnit)
        let alternatePart = try C55PartsStockTestSupport.part(fixture.alternate, workspaceID: workspaceID, slot: 70)
        XCTAssertEqual(alternateUnit.family, .length)
        XCTAssertEqual(alternatePart.preferredMinimum?.scale, fixture.alternate.preferredMinimum.scale)
        XCTAssertThrowsError(
            try StockStorageLocationV1(
                locationID: C55PartsStockTestSupport.id(71),
                workspaceID: workspaceID,
                kind: .shop,
                label: String(repeating: "x", count: PartsStockLimitsV1.maximumStorageLabelBytes + 1),
                revision: 1
            )
        )
        XCTAssertThrowsError(
            try StockStorageLocationV1(
                locationID: C55PartsStockTestSupport.id(72),
                workspaceID: workspaceID,
                kind: .shop,
                label: fixture.golden.storageLabel,
                binLabel: String(repeating: "b", count: PartsStockLimitsV1.maximumBinLabelBytes + 1),
                revision: 1
            )
        )
    }

    @MainActor
    func testV23P03C55A01KnownOnlyAdjustTransferUseAndAtomicReceipts() throws {
        let fixture = try Self.fixture()
        XCTAssertTrue(fixture.hostileCases.contains("UNIT_CHANGE_AFTER_MOVEMENT"))
        let workspaceID = C55PartsStockTestSupport.workspace()
        let unit = try C55PartsStockTestSupport.unit(fixture.golden.canonicalUnit)
        let writer = C55InMemoryWriter()
        let coordinator = PartsStockCoordinatorV1(writer: writer)
        let identities = try [
            StockProductIdentityV1(kind: .manufacturer, value: fixture.golden.manufacturerCode),
            StockProductIdentityV1(kind: .sku, value: fixture.golden.sku)
        ]
        let minimum = try C55PartsStockTestSupport.stock(fixture.golden.preferredMinimum, unit: unit)
        let (part, createReceipt) = try coordinator.createPart(
            partID: C55PartsStockTestSupport.id(100),
            workspaceID: workspaceID,
            displayName: fixture.golden.displayName,
            canonicalUnit: unit,
            productIdentities: identities,
            preferredMinimum: minimum
        )
        XCTAssertEqual(createReceipt.workspaceID, workspaceID)
        XCTAssertEqual(part.partSHA256.count, 64)
        let source = try C55PartsStockTestSupport.location(fixture.golden, workspaceID: workspaceID, slot: 101)
        let destination = try StockStorageLocationV1(
            locationID: C55PartsStockTestSupport.id(102),
            workspaceID: workspaceID,
            kind: .vehicle,
            label: "Service Van",
            binLabel: "Cabinet 2",
            revision: 1
        )
        _ = try coordinator.saveLocation(source)
        _ = try coordinator.saveLocation(destination)

        let unknownSource = try C55PartsStockTestSupport.projection(
            workspaceID: workspaceID, partID: part.partID, locationID: source.locationID,
            unit: unit, balance: .unknown, locationRevision: 0, lastMovementID: nil
        )
        let opening = try C55PartsStockTestSupport.stock(fixture.golden.opening, unit: unit)
        let (openingMovement, _) = try coordinator.count(
            movementID: C55PartsStockTestSupport.id(103),
            part: part,
            location: source,
            observed: opening,
            current: unknownSource,
            opening: true,
            actor: try C55PartsStockTestSupport.actor(workspaceID: workspaceID, slot: 104),
            occurredAt: C55PartsStockTestSupport.date(),
            recordedAt: C55PartsStockTestSupport.date(1)
        )
        let afterOpening = try C55PartsStockTestSupport.projection(
            workspaceID: workspaceID, partID: part.partID, locationID: source.locationID,
            unit: unit, balance: .known(opening), locationRevision: openingMovement.locationRevision,
            lastMovementID: openingMovement.movementID
        )
        let counted = try C55PartsStockTestSupport.stock(fixture.golden.physicalCount, unit: unit)
        let (countMovement, _) = try coordinator.count(
            movementID: C55PartsStockTestSupport.id(105),
            part: part,
            location: source,
            observed: counted,
            current: afterOpening,
            opening: false,
            actor: try C55PartsStockTestSupport.actor(workspaceID: workspaceID, slot: 106),
            occurredAt: C55PartsStockTestSupport.date(2),
            recordedAt: C55PartsStockTestSupport.date(3)
        )
        let afterCount = try C55PartsStockTestSupport.projection(
            workspaceID: workspaceID, partID: part.partID, locationID: source.locationID,
            unit: unit, balance: .known(counted), locationRevision: countMovement.locationRevision,
            lastMovementID: countMovement.movementID
        )
        let adjustment = try C55PartsStockTestSupport.stock(fixture.golden.adjustmentIncrease, unit: unit)
        let (adjusted, _) = try coordinator.adjust(
            movementID: C55PartsStockTestSupport.id(107),
            part: part,
            location: source,
            magnitude: adjustment,
            increase: true,
            reason: "C55 deterministic receiving correction",
            current: afterCount,
            actor: try C55PartsStockTestSupport.actor(workspaceID: workspaceID, slot: 108),
            occurredAt: C55PartsStockTestSupport.date(4),
            recordedAt: C55PartsStockTestSupport.date(5)
        )
        XCTAssertEqual(adjusted.kind, .adjustmentIncrease)
        XCTAssertEqual(adjusted.postBalance.mantissa, counted.mantissa + adjustment.mantissa)

        let unknownDestination = try C55PartsStockTestSupport.projection(
            workspaceID: workspaceID, partID: part.partID, locationID: destination.locationID,
            unit: unit, balance: .unknown, locationRevision: 0, lastMovementID: nil
        )
        let destinationOpening = try C55PartsStockTestSupport.stock(fixture.golden.destinationOpening, unit: unit)
        let (destinationOpeningMovement, _) = try coordinator.count(
            movementID: C55PartsStockTestSupport.id(109),
            part: part,
            location: destination,
            observed: destinationOpening,
            current: unknownDestination,
            opening: true,
            actor: try C55PartsStockTestSupport.actor(workspaceID: workspaceID, slot: 110),
            occurredAt: C55PartsStockTestSupport.date(6),
            recordedAt: C55PartsStockTestSupport.date(7)
        )
        let afterDestinationOpening = try C55PartsStockTestSupport.projection(
            workspaceID: workspaceID, partID: part.partID, locationID: destination.locationID,
            unit: unit, balance: .known(destinationOpening),
            locationRevision: destinationOpeningMovement.locationRevision,
            lastMovementID: destinationOpeningMovement.movementID
        )

        let transferQuantity = try C55PartsStockTestSupport.stock(fixture.golden.transfer, unit: unit)
        let sourceAfterAdjustment = try C55PartsStockTestSupport.projection(
            workspaceID: workspaceID, partID: part.partID, locationID: source.locationID,
            unit: unit, balance: .known(adjusted.postBalance), locationRevision: adjusted.locationRevision,
            lastMovementID: adjusted.movementID
        )
        let (transfer, _) = try coordinator.transfer(
            outboundID: C55PartsStockTestSupport.id(111),
            inboundID: C55PartsStockTestSupport.id(112),
            part: part,
            source: source,
            destination: destination,
            quantity: transferQuantity,
            sourceBalance: sourceAfterAdjustment,
            destinationBalance: afterDestinationOpening,
            actor: try C55PartsStockTestSupport.actor(workspaceID: workspaceID, slot: 113),
            occurredAt: C55PartsStockTestSupport.date(8),
            recordedAt: C55PartsStockTestSupport.date(9)
        )
        try transfer.validate()
        XCTAssertEqual(transfer.outbound.relatedMovementID, transfer.inbound.movementID)
        XCTAssertEqual(transfer.inbound.relatedMovementID, transfer.outbound.movementID)
        XCTAssertEqual(transfer.outbound.quantity, transfer.inbound.quantity)
        XCTAssertEqual(transfer.outbound.postBalance.mantissa, adjusted.postBalance.mantissa - transferQuantity.mantissa)
        XCTAssertEqual(transfer.inbound.postBalance.mantissa, destinationOpening.mantissa + transferQuantity.mantissa)

        let useQuantity = try C55PartsStockTestSupport.stock(fixture.golden.use, unit: unit)
        let afterTransferSource = try C55PartsStockTestSupport.projection(
            workspaceID: workspaceID, partID: part.partID, locationID: source.locationID,
            unit: unit, balance: .known(transfer.outbound.postBalance),
            locationRevision: transfer.outbound.locationRevision,
            lastMovementID: transfer.outbound.movementID
        )
        let (useReceipt, _) = try coordinator.use(
            receiptID: C55PartsStockTestSupport.id(114),
            movementID: C55PartsStockTestSupport.id(115),
            frozenMaterialLineID: C55PartsStockTestSupport.id(116),
            part: part,
            source: source,
            quantity: useQuantity,
            sourceBalance: afterTransferSource,
            actor: try C55PartsStockTestSupport.actor(workspaceID: workspaceID, slot: 117),
            occurredAt: C55PartsStockTestSupport.date(10),
            recordedAt: C55PartsStockTestSupport.date(11),
            workResourceSuccessor: { mutationID in
                try C55PartsStockTestSupport.workEntry(
                    workspaceID: workspaceID,
                    part: try part.frozenReference(),
                    quantity: try C55PartsStockTestSupport.exact(fixture.golden.use),
                    lineID: C55PartsStockTestSupport.id(116),
                    mutationID: mutationID,
                    slot: 520
                )
            }
        )
        try useReceipt.validate()
        XCTAssertEqual(useReceipt.movement.kind, .useOnWork)
        XCTAssertEqual(useReceipt.movement.postBalance.mantissa, transfer.outbound.postBalance.mantissa - useQuantity.mantissa)
        XCTAssertEqual(useReceipt.workResourceSuccessor.mutationID, useReceipt.mutationID)
        XCTAssertEqual(useReceipt.workResourceSuccessor.materials.first?.localPartReference, useReceipt.movement.part)
        let zero = try StockQuantityV1(mantissa: 0, scale: 0, unit: unit)
        let zeroSource = try C55PartsStockTestSupport.projection(
            workspaceID: workspaceID, partID: part.partID, locationID: source.locationID,
            unit: unit, balance: .known(zero),
            locationRevision: useReceipt.movement.locationRevision, lastMovementID: useReceipt.movement.movementID
        )
        let zeroDestination = try C55PartsStockTestSupport.projection(
            workspaceID: workspaceID, partID: part.partID, locationID: destination.locationID,
            unit: unit, balance: .known(zero),
            locationRevision: transfer.inbound.locationRevision, lastMovementID: transfer.inbound.movementID
        )
        XCTAssertThrowsError(
            try coordinator.revisePart(
                predecessor: part,
                displayName: "Unit change after movement is forbidden",
                canonicalUnit: .meter,
                productIdentities: part.productIdentities,
                preferredMinimum: part.preferredMinimum,
                hasMovementHistory: true
            )
        )
        let (revised, _) = try coordinator.revisePart(
            predecessor: part,
            displayName: "M8 stainless bolt revised",
            canonicalUnit: unit,
            productIdentities: part.productIdentities,
            preferredMinimum: part.preferredMinimum,
            hasMovementHistory: true
        )
        XCTAssertFalse(revised.archived)
        XCTAssertEqual(revised.revision, part.revision + 1)
        let (retirement, _) = try coordinator.retirePart(
            predecessor: revised,
            completeBalances: [zeroSource, zeroDestination]
        )
        try retirement.validate()
        XCTAssertTrue(retirement.archivedPartSuccessor.archived)
        XCTAssertEqual(retirement.verifiedBalances.map(\.balance), [.known(zero), .known(zero)])
        XCTAssertTrue(fixture.claims.ordinaryRetirementRequiresKnownZero)
        XCTAssertTrue(fixture.claims.revisionCannotArchive)
        let unknownRetirementBalance = try C55PartsStockTestSupport.projection(
            workspaceID: workspaceID, partID: part.partID, locationID: source.locationID,
            unit: unit, balance: .unknown, locationRevision: useReceipt.movement.locationRevision,
            lastMovementID: useReceipt.movement.movementID
        )
        XCTAssertThrowsError(
            try StockPartRetirementReceiptV1(
                archivedPartSuccessor: retirement.archivedPartSuccessor,
                predecessor: revised,
                verifiedBalances: [unknownRetirementBalance, zeroDestination]
            )
        )
        let positiveRetirementBalance = try C55PartsStockTestSupport.projection(
            workspaceID: workspaceID, partID: part.partID, locationID: source.locationID,
            unit: unit, balance: .known(opening), locationRevision: useReceipt.movement.locationRevision,
            lastMovementID: useReceipt.movement.movementID
        )
        XCTAssertThrowsError(
            try StockPartRetirementReceiptV1(
                archivedPartSuccessor: retirement.archivedPartSuccessor,
                predecessor: revised,
                verifiedBalances: [positiveRetirementBalance, zeroDestination]
            )
        )
        XCTAssertThrowsError(
            try StockPartRetirementReceiptV1(
                archivedPartSuccessor: retirement.archivedPartSuccessor,
                predecessor: revised,
                verifiedBalances: []
            )
        )
        XCTAssertThrowsError(
            try coordinator.revisePart(
                predecessor: retirement.archivedPartSuccessor,
                displayName: "Revision after archive is forbidden",
                canonicalUnit: retirement.archivedPartSuccessor.canonicalUnit,
                productIdentities: retirement.archivedPartSuccessor.productIdentities,
                preferredMinimum: retirement.archivedPartSuccessor.preferredMinimum,
                hasMovementHistory: true
            )
        )

        // The disabled policy is a hard precondition on every write route:
        // no mutation ID may be allocated and no writer effect may occur.
        let disabledWriter = C55InMemoryWriter()
        let disabledCoordinator = PartsStockCoordinatorV1(
            writer: disabledWriter,
            featurePolicy: .readExportRecoveryOnly
        )
        func assertWritesDisabled(_ operation: () throws -> Void) {
            XCTAssertThrowsError(try operation()) { error in
                XCTAssertEqual(error as? PartsStockFailureV1, .writesDisabled)
            }
        }
        assertWritesDisabled {
            _ = try disabledCoordinator.createPart(
                partID: C55PartsStockTestSupport.id(118), workspaceID: workspaceID,
                displayName: fixture.golden.displayName, canonicalUnit: unit,
                productIdentities: identities, preferredMinimum: minimum
            )
        }
        assertWritesDisabled {
            _ = try disabledCoordinator.revisePart(
                predecessor: part, displayName: part.displayName,
                canonicalUnit: part.canonicalUnit,
                productIdentities: part.productIdentities,
                preferredMinimum: part.preferredMinimum, hasMovementHistory: false
            )
        }
        assertWritesDisabled {
            _ = try disabledCoordinator.retirePart(
                predecessor: revised, completeBalances: [zeroSource, zeroDestination]
            )
        }
        assertWritesDisabled { _ = try disabledCoordinator.saveLocation(source) }
        assertWritesDisabled {
            _ = try disabledCoordinator.count(
                movementID: C55PartsStockTestSupport.id(119), part: part,
                location: source, observed: opening, current: unknownSource,
                opening: true,
                actor: try C55PartsStockTestSupport.actor(workspaceID: workspaceID),
                occurredAt: C55PartsStockTestSupport.date(),
                recordedAt: C55PartsStockTestSupport.date(1)
            )
        }
        assertWritesDisabled {
            _ = try disabledCoordinator.adjust(
                movementID: C55PartsStockTestSupport.id(120), part: part,
                location: source, magnitude: adjustment, increase: true,
                reason: "disabled", current: afterCount,
                actor: try C55PartsStockTestSupport.actor(workspaceID: workspaceID),
                occurredAt: C55PartsStockTestSupport.date(),
                recordedAt: C55PartsStockTestSupport.date(1)
            )
        }
        assertWritesDisabled {
            _ = try disabledCoordinator.transfer(
                outboundID: C55PartsStockTestSupport.id(121),
                inboundID: C55PartsStockTestSupport.id(122), part: part,
                source: source, destination: destination, quantity: transferQuantity,
                sourceBalance: sourceAfterAdjustment,
                destinationBalance: afterDestinationOpening,
                actor: try C55PartsStockTestSupport.actor(workspaceID: workspaceID),
                occurredAt: C55PartsStockTestSupport.date(),
                recordedAt: C55PartsStockTestSupport.date(1)
            )
        }
        assertWritesDisabled {
            _ = try disabledCoordinator.use(
                receiptID: C55PartsStockTestSupport.id(123),
                movementID: C55PartsStockTestSupport.id(124),
                frozenMaterialLineID: C55PartsStockTestSupport.id(125), part: part,
                source: source, quantity: useQuantity,
                sourceBalance: afterTransferSource,
                actor: try C55PartsStockTestSupport.actor(workspaceID: workspaceID),
                occurredAt: C55PartsStockTestSupport.date(),
                recordedAt: C55PartsStockTestSupport.date(1),
                workResourceSuccessor: { _ in
                    try C55PartsStockTestSupport.workEntry(
                        workspaceID: workspaceID, part: try part.frozenReference(),
                        quantity: try C55PartsStockTestSupport.exact(useQuantity),
                        lineID: C55PartsStockTestSupport.id(125),
                        mutationID: try C55PartsStockTestSupport.mutation(126)
                    )
                }
            )
        }
        assertWritesDisabled {
            _ = try disabledCoordinator.reverseUse(
                receiptID: C55PartsStockTestSupport.id(127),
                movementID: C55PartsStockTestSupport.id(128), sourceUse: useReceipt,
                destination: destination, destinationBalance: zeroDestination,
                actor: try C55PartsStockTestSupport.actor(workspaceID: workspaceID),
                reason: "disabled", occurredAt: C55PartsStockTestSupport.date(),
                recordedAt: C55PartsStockTestSupport.date(1),
                workResourceSuccessor: { _ in useReceipt.workResourceSuccessor }
            )
        }
        assertWritesDisabled {
            _ = try disabledCoordinator.returnAgainstUse(
                receiptID: C55PartsStockTestSupport.id(129),
                movementID: C55PartsStockTestSupport.id(130), sourceUse: useReceipt,
                predecessorFrontier: nil,
                workResourcePredecessor: useReceipt.workResourceSuccessor,
                destination: destination, quantity: useQuantity,
                destinationBalance: zeroDestination,
                actor: try C55PartsStockTestSupport.actor(workspaceID: workspaceID),
                occurredAt: C55PartsStockTestSupport.date(),
                recordedAt: C55PartsStockTestSupport.date(1),
                workResourceSuccessor: { _ in useReceipt.workResourceSuccessor }
            )
        }
        assertWritesDisabled {
            _ = try disabledCoordinator.abandonUnknown(
                part: part,
                affected: [(location: source, current: unknownSource)],
                actor: try C55PartsStockTestSupport.actor(workspaceID: workspaceID),
                reason: "disabled", recordedAt: C55PartsStockTestSupport.date()
            )
        }
        XCTAssertEqual(disabledWriter.makeMutationIDCalls, 0)
        XCTAssertEqual(disabledWriter.commitCalls, 0)
        XCTAssertTrue(disabledWriter.mutations.isEmpty)
        XCTAssertEqual(
            C55PartsStockLifecycleBoundaryV1.disabledFeaturePolicy,
            .readExportRecoveryOnly
        )
        XCTAssertTrue(C55PartsStockLifecycleBoundaryV1.offlineOperationIsDeviceLocal)
        XCTAssertEqual(
            C55PartsStockLifecycleBoundaryV1.foundationAccessibility,
            .notApplicable
        )
        XCTAssertTrue(C55PartsStockLifecycleBoundaryV1.featureDisablePreservesReadExportRecovery)
        XCTAssertTrue(C55PartsStockLifecycleBoundaryV1.searchRebuildDelegatesToIncumbentLifecyclePort)
        XCTAssertTrue(C55PartsStockLifecycleBoundaryV1.workspaceEraseDelegatesToIncumbentLifecyclePort)
        XCTAssertEqual(writer.mutations.count, 11)
        XCTAssertTrue(fixture.claims.adjustmentRequiresKnown)
        XCTAssertTrue(fixture.claims.useRequiresSufficientKnown)
        XCTAssertTrue(fixture.claims.transferRequiresKnownBothSides)
        XCTAssertTrue(fixture.claims.transferIsAtomic)
    }

    @MainActor
    func testV23P03C55H01HostileBoundsMismatchesFrontierAndIdempotencyFailClosed() throws {
        let fixture = try Self.fixture()
        for value in ["PRODUCTION_WRITER_REPLAY_FENCE", "SEQUENTIAL_RESULTING_HISTORY_MAP"] {
            XCTAssertTrue(fixture.recoveryCases.contains(value), "fixture missing \(value)")
        }
        XCTAssertTrue(fixture.claims.returnIsProvenanceBound)
        XCTAssertTrue(fixture.claims.returnUsesCASFrontier)
        let requiredHostiles = [
            "NEGATIVE_QUANTITY", "ZERO_MOVEMENT_MAGNITUDE", "NAN_DATE", "SCALE_FOUR",
            "OVERFLOW_RETURN_FRONTIER", "UNDERFLOW_RETURN_FRONTIER",
            "UNKNOWN_ADJUSTMENT", "CROSS_WORKSPACE", "KIND_MISMATCH", "UNIT_MISMATCH",
            "DUPLICATE_PRODUCT_IDENTITY", "DIVERGENT_SAME_MUTATION", "MALFORMED_UNKNOWN_BALANCE",
            "OVERSIZED_STORAGE_LABEL", "INSUFFICIENT_KNOWN_USE", "STOCK_WORK_UNIT_MISMATCH",
            "OMITTED_TRANSFER_HALF", "OMITTED_USE_RECEIPT", "OMITTED_REVERSAL_RECEIPT",
            "OMITTED_RETURN_RECEIPT", "FABRICATED_FROZEN_PART_REFERENCE", "STALE_RETURN_FRONTIER",
            "STALE_FROZEN_PART_REFERENCE", "FORKED_RETURN_PREDECESSOR", "NONLATEST_RETURN_FRONTIER", "CORRUPT_PERSISTENCE_ROW",
            "DECODED_ARCHIVE_CATALOG_MUTATION", "UNIT_CHANGE_AFTER_MOVEMENT", "INVALID_NONCOUNT_GENESIS",
            "DUPLICATE_MOVEMENT_REVISION", "GAP_MOVEMENT_REVISION", "FORK_MOVEMENT_REVISION",
            "TAMPERED_COMMAND_BODY_DIGEST", "TAMPERED_POSTIMAGE_DIGEST",
            "TAMPERED_EXPECTED_REVISION", "TAMPERED_RESULTING_REVISION",
            "MISSING_SNAPSHOT_EFFECT", "EXTRA_SNAPSHOT_EFFECT", "DIVERGENT_PRODUCTION_REPLAY",
            "FRACTIONAL_NSNUMBER_CANONICAL", "EXTRA_EXPECTED_REVISION_IDENTITY",
            "EXTRA_RESULTING_REVISION_IDENTITY", "EXTRA_ENTITY_REVISION_IDENTITY",
            "ARCHIVE_PREDECESSOR_REVISION_GAP_FORK"
        ]
        for value in requiredHostiles { XCTAssertTrue(fixture.hostileCases.contains(value), "fixture missing \(value)") }
        XCTAssertEqual(fixture.hostileVectors.negativeMantissa, -1)
        XCTAssertEqual(fixture.hostileVectors.zeroMagnitude, 0)
        XCTAssertEqual(fixture.hostileVectors.invalidScale, 4)
        XCTAssertEqual(fixture.hostileVectors.overflowExpectedReturnedMantissa, Int64.max)
        XCTAssertEqual(fixture.hostileVectors.underflowExpectedReturnedMantissa, 3)
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let backupEncoderSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalEncoderV1.swift"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(backupEncoderSource.contains("NSNumber"))
        XCTAssertTrue(backupEncoderSource.contains("CFGetTypeID(value) != CFBooleanGetTypeID()"))
        XCTAssertTrue(backupEncoderSource.contains("!representation.contains(\".\")"))
        XCTAssertTrue(backupEncoderSource.contains("!representation.contains(\"e\")"))
        XCTAssertTrue(backupEncoderSource.contains("!representation.contains(\"E\")"))

        let workspaceID = C55PartsStockTestSupport.workspace()
        let otherWorkspace = C55PartsStockTestSupport.workspace(2)
        let unit = try C55PartsStockTestSupport.unit(fixture.golden.canonicalUnit)
        let part = try C55PartsStockTestSupport.part(fixture.golden, workspaceID: workspaceID, slot: 200)
        let location = try C55PartsStockTestSupport.location(fixture.golden, workspaceID: workspaceID, slot: 201)
        let partReference = try part.frozenReference()

        XCTAssertThrowsError(try StockQuantityV1(mantissa: fixture.hostileVectors.negativeMantissa, scale: 0, unit: unit))
        XCTAssertThrowsError(try ExactDecimalQuantityV1(mantissa: fixture.hostileVectors.negativeMantissa, scale: 0))
        XCTAssertThrowsError(try ExactDecimalQuantityV1(mantissa: 1, scale: fixture.hostileVectors.invalidScale))
        XCTAssertThrowsError(try StockQuantityV1(mantissa: 1, scale: 1, unit: .each))
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                StockBalanceV1.self,
                from: Data(#"{"state":"UNKNOWN","quantity":{"mantissa":1,"scale":0}}"#.utf8)
            )
        )

        let known = try C55PartsStockTestSupport.stock(fixture.golden.opening, unit: unit)
        let magnitude = try C55PartsStockTestSupport.stock(fixture.golden.adjustmentIncrease, unit: unit)

        func assertDirectReplayRejects(
            _ name: String,
            movements: [StockMovementEventV1]
        ) throws {
            let schema = Schema([StockMovementEventRowV1.self])
            let container = try ModelContainer(
                for: schema,
                migrationPlan: nil,
                configurations: [ModelConfiguration(
                    "C55-H01-" + name,
                    schema: schema,
                    isStoredInMemoryOnly: true,
                    allowsSave: true,
                    cloudKitDatabase: .none
                )]
            )
            let context = container.mainContext
            context.autosaveEnabled = false
            for movement in movements {
                context.insert(try StockMovementEventRowV1(movement))
            }
            try context.save()
            XCTAssertThrowsError(
                try PartsStockLifecycleAdapterV1(modelContext: context)
                    .replay(workspaceID: workspaceID)
            )
        }

        let knownFirstMovement = try C55PartsStockTestSupport.movement(
            movementID: C55PartsStockTestSupport.id(198),
            workspaceID: workspaceID,
            part: partReference,
            locationID: location.locationID,
            kind: .physicalCount,
            quantity: known,
            unit: unit,
            preBalance: .known(known),
            postBalance: known,
            actor: try C55PartsStockTestSupport.actor(workspaceID: workspaceID, slot: 199),
            expectedLocationRevision: 0,
            mutationSlot: 196
        )
        try assertDirectReplayRejects(
            "first-known-prebalance",
            movements: [knownFirstMovement]
        )

        let validOpeningMovement = try C55PartsStockTestSupport.movement(
            movementID: C55PartsStockTestSupport.id(197),
            workspaceID: workspaceID,
            part: partReference,
            locationID: location.locationID,
            kind: .openingCount,
            quantity: known,
            unit: unit,
            preBalance: .unknown,
            postBalance: known,
            actor: try C55PartsStockTestSupport.actor(workspaceID: workspaceID, slot: 195),
            expectedLocationRevision: 0,
            mutationSlot: 194
        )
        let laterOpeningCount = try C55PartsStockTestSupport.movement(
            movementID: C55PartsStockTestSupport.id(196),
            workspaceID: workspaceID,
            part: partReference,
            locationID: location.locationID,
            kind: .openingCount,
            quantity: known,
            unit: unit,
            preBalance: .known(known),
            postBalance: known,
            actor: try C55PartsStockTestSupport.actor(workspaceID: workspaceID, slot: 193),
            expectedLocationRevision: validOpeningMovement.locationRevision,
            mutationSlot: 192
        )
        try assertDirectReplayRejects(
            "later-opening-count",
            movements: [validOpeningMovement, laterOpeningCount]
        )

        XCTAssertThrowsError(
            try C55PartsStockTestSupport.movement(
                movementID: C55PartsStockTestSupport.id(202), workspaceID: workspaceID, part: partReference,
                locationID: location.locationID, kind: .adjustmentIncrease, quantity: magnitude, unit: unit,
                preBalance: .unknown, postBalance: known, actor: try C55PartsStockTestSupport.actor(workspaceID: workspaceID),
                expectedLocationRevision: 0, mutationSlot: 203
            )
        )
        XCTAssertThrowsError(
            try C55PartsStockTestSupport.movement(
                movementID: C55PartsStockTestSupport.id(204), workspaceID: workspaceID, part: partReference,
                locationID: location.locationID, kind: .adjustmentIncrease, quantity: magnitude, unit: unit,
                preBalance: .known(known), postBalance: known, actor: try C55PartsStockTestSupport.actor(workspaceID: workspaceID),
                expectedLocationRevision: 0, mutationSlot: 205
            )
        )
        let zeroMagnitude = try StockQuantityV1(mantissa: fixture.hostileVectors.zeroMagnitude, scale: 0, unit: unit)
        XCTAssertThrowsError(
            try C55PartsStockTestSupport.movement(
                movementID: C55PartsStockTestSupport.id(208), workspaceID: workspaceID, part: partReference,
                locationID: location.locationID, kind: .adjustmentIncrease, quantity: zeroMagnitude, unit: unit,
                preBalance: .known(known), postBalance: known, reason: "Zero movement is not a fact",
                actor: try C55PartsStockTestSupport.actor(workspaceID: workspaceID),
                expectedLocationRevision: 0, mutationSlot: 209
            )
        )
        XCTAssertThrowsError(
            try C55PartsStockTestSupport.movement(
                movementID: C55PartsStockTestSupport.id(206), workspaceID: workspaceID, part: partReference,
                locationID: location.locationID, kind: .useOnWork, quantity: magnitude, unit: unit,
                preBalance: .known(known), postBalance: known,
                actor: try C55PartsStockTestSupport.actor(workspaceID: workspaceID),
                expectedLocationRevision: 0, mutationSlot: 207,
                occurredOffset: .nan
            )
        )

        let useQuantity = try C55PartsStockTestSupport.stock(fixture.golden.use, unit: unit)
        let usePost = try StockQuantityV1(mantissa: known.mantissa - useQuantity.mantissa, scale: known.scale, unit: unit)
        XCTAssertThrowsError(
            try C55PartsStockTestSupport.movement(
                movementID: C55PartsStockTestSupport.id(209), workspaceID: workspaceID, part: partReference,
                locationID: location.locationID, kind: .useOnWork, quantity: useQuantity, unit: unit,
                preBalance: .known(try StockQuantityV1(mantissa: 1, scale: 0, unit: unit)),
                postBalance: try StockQuantityV1(mantissa: 0, scale: 0, unit: unit),
                actor: try C55PartsStockTestSupport.actor(workspaceID: workspaceID),
                expectedLocationRevision: 0, mutationSlot: 211
            )
        )
        let sourceUse = try C55PartsStockTestSupport.useReceipt(
            workspaceID: workspaceID,
            part: part,
            location: location,
            quantity: useQuantity,
            preBalance: known,
            postBalance: usePost,
            slot: 210
        )
        let mismatchedWorkSuccessor = try C55PartsStockTestSupport.workSuccessor(
            of: sourceUse.workResourceSuccessor,
            part: sourceUse.movement.part,
            quantity: useQuantity,
            lineID: sourceUse.frozenMaterialLineID,
            mutationID: sourceUse.mutationID,
            materialUnit: StockUnitV1.meter.rawValue,
            slot: 545
        )
        XCTAssertThrowsError(
            try StockUseOnWorkReceiptV1(
                receiptID: C55PartsStockTestSupport.id(245),
                movement: sourceUse.movement,
                workResourceSuccessor: mismatchedWorkSuccessor,
                frozenMaterialLineID: sourceUse.frozenMaterialLineID,
                mutationID: sourceUse.mutationID
            )
        )
        let returnQuantity = try C55PartsStockTestSupport.stock(fixture.golden.return, unit: unit)
        let validReturnWork = try C55PartsStockTestSupport.workSuccessor(
            of: sourceUse.workResourceSuccessor,
            part: sourceUse.movement.part,
            quantity: returnQuantity,
            lineID: sourceUse.frozenMaterialLineID,
            mutationID: try C55PartsStockTestSupport.mutation(222),
            slot: 530
        )
        let validReturn = try C55PartsStockTestSupport.returnReceipt(
            sourceUse: sourceUse,
            destination: location,
            destinationPreBalance: try StockQuantityV1(mantissa: 1, scale: 0, unit: unit),
            quantity: returnQuantity,
            predecessorFrontier: nil,
            workResourcePredecessor: sourceUse.workResourceSuccessor,
            workResourceSuccessor: validReturnWork,
            movementSlot: 220,
            receiptSlot: 224
        )
        XCTAssertNoThrow(
            try validReturn.validate()
        )
        XCTAssertThrowsError(
            try StockReturnFrontierSnapshotV1(
                returnReceiptID: C55PartsStockTestSupport.id(223),
                returnReceiptSHA256: C55PartsStockTestSupport.digest("n"),
                sourceUseReceiptID: sourceUse.receiptID,
                resultingReturnedMantissa: fixture.hostileVectors.negativeMantissa,
                workResourceSuccessor: sourceUse.workResourceSuccessor
            )
        )
        let wrongWorkPredecessor = try C55PartsStockTestSupport.workEntry(
            workspaceID: workspaceID,
            part: sourceUse.movement.part,
            quantity: try C55PartsStockTestSupport.exact(useQuantity),
            lineID: sourceUse.frozenMaterialLineID,
            mutationID: sourceUse.mutationID,
            slot: 540
        )
        let wrongWorkSuccessor = try C55PartsStockTestSupport.workSuccessor(
            of: wrongWorkPredecessor,
            part: sourceUse.movement.part,
            quantity: returnQuantity,
            lineID: sourceUse.frozenMaterialLineID,
            mutationID: validReturn.mutationID,
            slot: 541
        )
        XCTAssertThrowsError(
            try StockReturnAgainstUseReceiptV1(
                receiptID: C55PartsStockTestSupport.id(224), sourceUse: sourceUse,
                predecessorFrontier: nil,
                returnMovement: validReturn.returnMovement,
                workResourcePredecessor: wrongWorkPredecessor,
                workResourceSuccessor: wrongWorkSuccessor, mutationID: validReturn.mutationID
            )
        )
        let reversal = try C55PartsStockTestSupport.reversalReceipt(
            sourceUse: sourceUse,
            destination: location,
            destinationPreBalance: try StockQuantityV1(mantissa: 1, scale: 0, unit: unit),
            reason: "C55 correction reverses the use",
            slot: 250
        )
        try reversal.validate()
        XCTAssertEqual(reversal.reversalMovement.kind, .reverseUse)
        let retainedMaterialSuccessor = try C55PartsStockTestSupport.workSuccessor(
            of: sourceUse.workResourceSuccessor,
            part: sourceUse.movement.part,
            quantity: useQuantity,
            lineID: sourceUse.frozenMaterialLineID,
            mutationID: reversal.mutationID,
            slot: 542
        )
        XCTAssertThrowsError(
            try StockUseReversalReceiptV1(
                receiptID: C55PartsStockTestSupport.id(261), sourceUse: sourceUse,
                reversalMovement: reversal.reversalMovement,
                workResourceSuccessor: retainedMaterialSuccessor,
                reason: reversal.reason, mutationID: reversal.mutationID
            )
        )
        XCTAssertThrowsError(
            try StockReturnAgainstUseReceiptV1(
                receiptID: C55PartsStockTestSupport.id(225), sourceUse: sourceUse,
                predecessorFrontier: try StockReturnFrontierSnapshotV1(
                    returnReceiptID: C55PartsStockTestSupport.id(225),
                    returnReceiptSHA256: C55PartsStockTestSupport.digest("u"),
                    sourceUseReceiptID: sourceUse.receiptID,
                    resultingReturnedMantissa: fixture.hostileVectors.underflowExpectedReturnedMantissa,
                    workResourceSuccessor: sourceUse.workResourceSuccessor
                ),
                returnMovement: validReturn.returnMovement,
                workResourcePredecessor: sourceUse.workResourceSuccessor,
                workResourceSuccessor: validReturnWork, mutationID: validReturn.mutationID
            )
        )
        XCTAssertThrowsError(
            try StockReturnAgainstUseReceiptV1(
                receiptID: C55PartsStockTestSupport.id(227), sourceUse: sourceUse,
                predecessorFrontier: try StockReturnFrontierSnapshotV1(
                    returnReceiptID: C55PartsStockTestSupport.id(228),
                    returnReceiptSHA256: C55PartsStockTestSupport.digest("o"),
                    sourceUseReceiptID: sourceUse.receiptID,
                    resultingReturnedMantissa: fixture.hostileVectors.overflowExpectedReturnedMantissa,
                    workResourceSuccessor: sourceUse.workResourceSuccessor
                ),
                returnMovement: validReturn.returnMovement,
                workResourcePredecessor: sourceUse.workResourceSuccessor,
                workResourceSuccessor: validReturnWork, mutationID: validReturn.mutationID
            )
        )

        let wrongUnitMovement = try C55PartsStockTestSupport.movement(
            movementID: C55PartsStockTestSupport.id(228), workspaceID: workspaceID, part: sourceUse.movement.part,
            locationID: location.locationID, kind: .returnAgainstUse, quantity: returnQuantity, unit: .meter,
            preBalance: .known(try StockQuantityV1(mantissa: 1, scale: 0, unit: .meter)),
            postBalance: try StockQuantityV1(mantissa: 2, scale: 0, unit: .meter),
            relatedMovementID: sourceUse.movement.movementID, actor: try C55PartsStockTestSupport.actor(workspaceID: workspaceID, slot: 229),
            expectedLocationRevision: 2, mutationSlot: 230
        )
        let wrongUnitWorkSuccessor = try C55PartsStockTestSupport.workSuccessor(
            of: sourceUse.workResourceSuccessor,
            part: sourceUse.movement.part,
            quantity: returnQuantity,
            lineID: sourceUse.frozenMaterialLineID,
            mutationID: wrongUnitMovement.mutationID,
            slot: 548
        )
        XCTAssertThrowsError(
            try StockReturnAgainstUseReceiptV1(
                receiptID: C55PartsStockTestSupport.id(231), sourceUse: sourceUse,
                predecessorFrontier: nil, returnMovement: wrongUnitMovement,
                workResourcePredecessor: sourceUse.workResourceSuccessor,
                workResourceSuccessor: wrongUnitWorkSuccessor, mutationID: wrongUnitMovement.mutationID
            )
        )
        let foreignMovement = try C55PartsStockTestSupport.movement(
            movementID: C55PartsStockTestSupport.id(232), workspaceID: otherWorkspace, part: sourceUse.movement.part,
            locationID: location.locationID, kind: .returnAgainstUse, quantity: returnQuantity, unit: unit,
            preBalance: .known(try StockQuantityV1(mantissa: 1, scale: 0, unit: unit)),
            postBalance: try StockQuantityV1(mantissa: 2, scale: 0, unit: unit),
            relatedMovementID: sourceUse.movement.movementID, actor: try C55PartsStockTestSupport.actor(workspaceID: otherWorkspace, slot: 233),
            expectedLocationRevision: 2, mutationSlot: 234
        )
        XCTAssertThrowsError(
            try StockReturnAgainstUseReceiptV1(
                receiptID: C55PartsStockTestSupport.id(235), sourceUse: sourceUse,
                predecessorFrontier: nil, returnMovement: foreignMovement,
                workResourcePredecessor: sourceUse.workResourceSuccessor,
                workResourceSuccessor: validReturnWork, mutationID: foreignMovement.mutationID
            )
        )

        let destination = try C55PartsStockTestSupport.location(fixture.golden, workspaceID: workspaceID, slot: 236)
        let otherPart = try C55PartsStockTestSupport.part(fixture.alternate, workspaceID: workspaceID, slot: 237)
        let inbound = try C55PartsStockTestSupport.movement(
            movementID: C55PartsStockTestSupport.id(238), workspaceID: workspaceID, part: try otherPart.frozenReference(),
            locationID: destination.locationID, kind: .transferIn, quantity: magnitude, unit: unit,
            preBalance: .known(known), postBalance: try StockQuantityV1(mantissa: known.mantissa + magnitude.mantissa, scale: known.scale, unit: unit),
            relatedMovementID: C55PartsStockTestSupport.id(239), actor: try C55PartsStockTestSupport.actor(workspaceID: workspaceID, slot: 240),
            expectedLocationRevision: 0, mutationSlot: 241
        )
        let outbound = try C55PartsStockTestSupport.movement(
            movementID: C55PartsStockTestSupport.id(239), workspaceID: workspaceID, part: partReference,
            locationID: location.locationID, kind: .transferOut, quantity: magnitude, unit: unit,
            preBalance: .known(known), postBalance: try StockQuantityV1(mantissa: known.mantissa - magnitude.mantissa, scale: known.scale, unit: unit),
            relatedMovementID: inbound.movementID, actor: try C55PartsStockTestSupport.actor(workspaceID: workspaceID, slot: 240),
            expectedLocationRevision: 0, mutationSlot: 242
        )
        XCTAssertThrowsError(
            try StockTransferReceiptV1(
                workspaceID: workspaceID, outbound: outbound, inbound: inbound,
                mutationID: outbound.mutationID
            ).validate()
        )
        XCTAssertThrowsError(
            try StockTransferReceiptV1(
                workspaceID: workspaceID, outbound: inbound, inbound: outbound,
                mutationID: outbound.mutationID
            ).validate()
        )
        let transferMutationID = try C55PartsStockTestSupport.mutation(260)
        let validTransferOutbound = try C55PartsStockTestSupport.movement(
            movementID: C55PartsStockTestSupport.id(261), workspaceID: workspaceID, part: partReference,
            locationID: location.locationID, kind: .transferOut, quantity: magnitude, unit: unit,
            preBalance: .known(known), postBalance: try StockQuantityV1(mantissa: known.mantissa - magnitude.mantissa, scale: known.scale, unit: unit),
            relatedMovementID: C55PartsStockTestSupport.id(262), actor: try C55PartsStockTestSupport.actor(workspaceID: workspaceID, slot: 263),
            expectedLocationRevision: 0, mutationSlot: 260
        )
        let validTransferInbound = try C55PartsStockTestSupport.movement(
            movementID: C55PartsStockTestSupport.id(262), workspaceID: workspaceID, part: partReference,
            locationID: destination.locationID, kind: .transferIn, quantity: magnitude, unit: unit,
            preBalance: .known(known), postBalance: try StockQuantityV1(mantissa: known.mantissa + magnitude.mantissa, scale: known.scale, unit: unit),
            relatedMovementID: C55PartsStockTestSupport.id(261), actor: try C55PartsStockTestSupport.actor(workspaceID: workspaceID, slot: 264),
            expectedLocationRevision: 0, mutationSlot: 260
        )
        XCTAssertEqual(validTransferOutbound.mutationID, transferMutationID)
        XCTAssertEqual(validTransferInbound.mutationID, transferMutationID)
        let validTransfer = StockTransferReceiptV1(
            workspaceID: workspaceID, outbound: validTransferOutbound,
            inbound: validTransferInbound, mutationID: transferMutationID
        )
        XCTAssertNoThrow(try validTransfer.validate())
        func snapshot(
            movements: [StockMovementEventV1],
            uses: [StockUseOnWorkReceiptV1] = [],
            reversals: [StockUseReversalReceiptV1] = [],
            returns: [StockReturnAgainstUseReceiptV1] = [],
            locations: [StockStorageLocationV1] = [location, destination]
        ) throws -> PartsStockBackupSnapshotV1 {
            try PartsStockBackupSnapshotV1(
                workspaceID: workspaceID,
                parts: [part], locations: locations, movements: movements,
                uses: uses, reversals: reversals, returns: returns, abandonments: []
            )
        }
        let streamOpening = try C55PartsStockTestSupport.movement(
            movementID: C55PartsStockTestSupport.id(280), workspaceID: workspaceID,
            part: partReference, locationID: location.locationID, kind: .openingCount,
            quantity: known, unit: unit, preBalance: .unknown, postBalance: known,
            actor: try C55PartsStockTestSupport.actor(workspaceID: workspaceID, slot: 281),
            expectedLocationRevision: 0, mutationSlot: 282
        )
        let streamAdjustmentPost = try StockQuantityV1(
            mantissa: known.mantissa + magnitude.mantissa, scale: known.scale, unit: unit
        )
        let streamAdjustment = try C55PartsStockTestSupport.movement(
            movementID: C55PartsStockTestSupport.id(283), workspaceID: workspaceID,
            part: partReference, locationID: location.locationID, kind: .adjustmentIncrease,
            quantity: magnitude, unit: unit, preBalance: .known(streamOpening.postBalance),
            postBalance: streamAdjustmentPost, reason: "Contiguous stream adjustment",
            actor: try C55PartsStockTestSupport.actor(workspaceID: workspaceID, slot: 284),
            expectedLocationRevision: streamOpening.locationRevision, mutationSlot: 285
        )
        let destinationGenesis = try C55PartsStockTestSupport.movement(
            movementID: C55PartsStockTestSupport.id(286), workspaceID: workspaceID,
            part: partReference, locationID: destination.locationID, kind: .physicalCount,
            quantity: try C55PartsStockTestSupport.stock(fixture.golden.destinationOpening, unit: unit),
            unit: unit, preBalance: .unknown,
            postBalance: try C55PartsStockTestSupport.stock(fixture.golden.destinationOpening, unit: unit),
            actor: try C55PartsStockTestSupport.actor(workspaceID: workspaceID, slot: 287),
            expectedLocationRevision: 0, mutationSlot: 288
        )
        let duplicateReversal = try C55PartsStockTestSupport.reversalReceipt(
            sourceUse: sourceUse,
            destination: destination,
            destinationPreBalance: destinationGenesis.postBalance,
            reason: "Duplicate reversal is forbidden",
            expectedLocationRevision: destinationGenesis.locationRevision,
            slot: 298
        )
        let duplicateReversalSuccessor = try C55PartsStockTestSupport.reversalReceipt(
            sourceUse: sourceUse,
            destination: destination,
            destinationPreBalance: duplicateReversal.reversalMovement.postBalance,
            reason: "Second reversal is forbidden",
            expectedLocationRevision: duplicateReversal.reversalMovement.locationRevision,
            slot: 304
        )
        XCTAssertThrowsError(
            try snapshot(
                movements: [
                    streamOpening, sourceUse.movement, destinationGenesis,
                    duplicateReversal.reversalMovement,
                    duplicateReversalSuccessor.reversalMovement
                ],
                uses: [sourceUse],
                reversals: [duplicateReversal, duplicateReversalSuccessor]
            )
        )
        XCTAssertThrowsError(
            try snapshot(
                movements: [
                    streamOpening, sourceUse.movement, destinationGenesis,
                    duplicateReversal.reversalMovement, validReturn.returnMovement
                ],
                uses: [sourceUse],
                reversals: [duplicateReversal],
                returns: [validReturn]
            )
        )
        let contiguous = try snapshot(
            movements: [streamAdjustment, destinationGenesis, streamOpening]
        )
        try contiguous.validate()
        XCTAssertEqual(streamOpening.locationRevision, 1)
        XCTAssertEqual(streamAdjustment.expectedLocationRevision, streamOpening.locationRevision)
        XCTAssertEqual(streamAdjustment.locationRevision, 2)
        XCTAssertEqual(streamAdjustment.preBalance, .known(streamOpening.postBalance))
        XCTAssertEqual(destinationGenesis.locationRevision, 1)
        XCTAssertEqual(
            contiguous.movements.filter { $0.locationID == location.locationID }
                .map(\.locationRevision),
            [1, 2]
        )
        XCTAssertEqual(
            contiguous.movements.filter { $0.locationID == destination.locationID }
                .map(\.locationRevision),
            [1]
        )

        let invalidNonCountGenesis = try C55PartsStockTestSupport.movement(
            movementID: C55PartsStockTestSupport.id(289), workspaceID: workspaceID,
            part: partReference, locationID: location.locationID, kind: .adjustmentIncrease,
            quantity: magnitude, unit: unit, preBalance: .known(known),
            postBalance: streamAdjustmentPost, reason: "Non-count genesis is forbidden",
            actor: try C55PartsStockTestSupport.actor(workspaceID: workspaceID, slot: 290),
            expectedLocationRevision: 0, mutationSlot: 291
        )
        XCTAssertThrowsError(try snapshot(movements: [invalidNonCountGenesis]))
        XCTAssertThrowsError(try snapshot(movements: [streamOpening, streamOpening]))
        let gapMovement = try C55PartsStockTestSupport.movement(
            movementID: C55PartsStockTestSupport.id(292), workspaceID: workspaceID,
            part: partReference, locationID: location.locationID, kind: .adjustmentIncrease,
            quantity: magnitude, unit: unit, preBalance: .known(streamAdjustmentPost),
            postBalance: try StockQuantityV1(
                mantissa: streamAdjustmentPost.mantissa + magnitude.mantissa,
                scale: unit == .each ? 0 : streamAdjustmentPost.scale, unit: unit
            ), reason: "Gap in stream revision",
            actor: try C55PartsStockTestSupport.actor(workspaceID: workspaceID, slot: 293),
            expectedLocationRevision: 2, mutationSlot: 294
        )
        XCTAssertThrowsError(try snapshot(movements: [streamOpening, gapMovement]))
        let forkMovement = try C55PartsStockTestSupport.movement(
            movementID: C55PartsStockTestSupport.id(295), workspaceID: workspaceID,
            part: partReference, locationID: location.locationID, kind: .adjustmentIncrease,
            quantity: magnitude, unit: unit, preBalance: .known(streamOpening.postBalance),
            postBalance: streamAdjustmentPost, reason: "Fork in stream revision",
            actor: try C55PartsStockTestSupport.actor(workspaceID: workspaceID, slot: 296),
            expectedLocationRevision: streamOpening.locationRevision, mutationSlot: 297
        )
        XCTAssertThrowsError(try snapshot(movements: [streamOpening, streamAdjustment, forkMovement]))
        XCTAssertThrowsError(
            try snapshot(movements: [validTransferOutbound])
        )
        XCTAssertThrowsError(
            try snapshot(movements: [sourceUse.movement])
        )
        XCTAssertThrowsError(
            try snapshot(
                movements: [sourceUse.movement, reversal.reversalMovement], uses: [sourceUse]
            )
        )
        XCTAssertThrowsError(
            try snapshot(
                movements: [sourceUse.movement, validReturn.returnMovement], uses: [sourceUse]
            )
        )
        let fabricatedReference = try LocalPartReferenceSnapshotV1(
            partID: part.partID, partRevision: part.revision,
            partSHA256: C55PartsStockTestSupport.digest("f"), displayName: part.displayName
        )
        let fabricatedMovement = try C55PartsStockTestSupport.movement(
            movementID: C55PartsStockTestSupport.id(265), workspaceID: workspaceID,
            part: fabricatedReference, locationID: location.locationID, kind: .openingCount,
            quantity: known, unit: unit, preBalance: .unknown, postBalance: known,
            actor: try C55PartsStockTestSupport.actor(workspaceID: workspaceID, slot: 266),
            expectedLocationRevision: 0, mutationSlot: 267
        )
        XCTAssertThrowsError(
            try snapshot(movements: [fabricatedMovement])
        )
        let staleReference = try LocalPartReferenceSnapshotV1(
            partID: part.partID, partRevision: part.revision + 1,
            partSHA256: part.partSHA256, displayName: part.displayName
        )
        let staleMovement = try C55PartsStockTestSupport.movement(
            movementID: C55PartsStockTestSupport.id(268), workspaceID: workspaceID,
            part: staleReference, locationID: location.locationID, kind: .openingCount,
            quantity: known, unit: unit, preBalance: .unknown, postBalance: known,
            actor: try C55PartsStockTestSupport.actor(workspaceID: workspaceID, slot: 269),
            expectedLocationRevision: 0, mutationSlot: 270
        )
        XCTAssertThrowsError(
            try snapshot(movements: [staleMovement])
        )
        XCTAssertThrowsError(
            try LocalPartDefinitionV1(
                partID: C55PartsStockTestSupport.id(243), workspaceID: workspaceID,
                displayName: "Duplicate code", canonicalUnit: unit,
                productIdentities: [
                    StockProductIdentityV1(kind: .sku, value: fixture.golden.sku),
                    StockProductIdentityV1(kind: .sku, value: fixture.golden.sku)
                ], revision: 1, mutationID: try C55PartsStockTestSupport.mutation(244)
            )
        )

        let reversedIdentities = try [
            StockProductIdentityV1(kind: .sku, value: fixture.golden.sku),
            StockProductIdentityV1(kind: .manufacturer, value: fixture.golden.manufacturerCode)
        ]
        let reordered = try LocalPartDefinitionV1(
            partID: part.partID, workspaceID: workspaceID, displayName: part.displayName,
            canonicalUnit: part.canonicalUnit, productIdentities: reversedIdentities,
            preferredMinimum: part.preferredMinimum, revision: part.revision, mutationID: part.mutationID
        )
        XCTAssertEqual(reordered, part)

        let writer = C55InMemoryWriter()
        let mutation = PartsStockMutationV1.upsertPart(part)
        let first = try writer.commitPartsStock(mutation)
        let replay = try writer.commitPartsStock(mutation)
        XCTAssertEqual(first, replay)
        let divergentPart = try LocalPartDefinitionV1(
            partID: part.partID, workspaceID: workspaceID, displayName: "Divergent same mutation",
            canonicalUnit: part.canonicalUnit, productIdentities: part.productIdentities,
            preferredMinimum: part.preferredMinimum, revision: part.revision, mutationID: part.mutationID
        )
        XCTAssertThrowsError(try writer.commitPartsStock(.upsertPart(divergentPart)))
        let reversalFirst = try writer.commitPartsStock(.reverseUse(reversal))
        let reversalReplay = try writer.commitPartsStock(.reverseUse(reversal))
        XCTAssertEqual(reversalFirst, reversalReplay)

        let productionHarness = try C55ProductionWriterHarness(workspaceID: workspaceID)
        let productionPart = try C55PartsStockTestSupport.part(
            fixture.alternate, workspaceID: workspaceID, slot: 270
        )
        let productionMutation = PartsStockMutationV1.upsertPart(productionPart)
        let productionFirst = try productionHarness.writer.commitPartsStock(productionMutation)
        let productionReplay = try productionHarness.writer.commitPartsStock(productionMutation)
        XCTAssertEqual(productionFirst, productionReplay)
        let productionDivergentPart = try LocalPartDefinitionV1(
            partID: productionPart.partID,
            workspaceID: workspaceID,
            displayName: "Production writer divergent replay",
            canonicalUnit: productionPart.canonicalUnit,
            productIdentities: productionPart.productIdentities,
            preferredMinimum: productionPart.preferredMinimum,
            revision: productionPart.revision,
            mutationID: productionPart.mutationID
        )
        XCTAssertThrowsError(
            try productionHarness.writer.commitPartsStock(
                .upsertPart(productionDivergentPart)
            )
        )
        let productionArchiveLocation = try C55PartsStockTestSupport.location(
            fixture.alternate, workspaceID: workspaceID, slot: 880
        )
        _ = try productionHarness.writer.commitPartsStock(
            .upsertLocation(
                productionArchiveLocation,
                mutationID: try C55PartsStockTestSupport.mutation(881)
            )
        )
        let productionZero = try StockQuantityV1(
            mantissa: 0, scale: 0, unit: productionPart.canonicalUnit
        )
        let productionArchiveGenesis = try C55PartsStockTestSupport.movement(
            movementID: C55PartsStockTestSupport.id(882),
            workspaceID: workspaceID,
            part: try productionPart.frozenReference(),
            locationID: productionArchiveLocation.locationID,
            kind: .physicalCount,
            quantity: productionZero,
            unit: productionPart.canonicalUnit,
            preBalance: .unknown,
            postBalance: productionZero,
            actor: try C55PartsStockTestSupport.actor(workspaceID: workspaceID, slot: 883),
            expectedLocationRevision: 0,
            mutationSlot: 884
        )
        _ = try productionHarness.writer.commitPartsStock(
            .appendMovement(productionArchiveGenesis)
        )
        let productionArchiveBalance = try C55PartsStockTestSupport.projection(
            workspaceID: workspaceID,
            partID: productionPart.partID,
            locationID: productionArchiveLocation.locationID,
            unit: productionPart.canonicalUnit,
            balance: .known(productionZero),
            locationRevision: productionArchiveGenesis.locationRevision,
            lastMovementID: productionArchiveGenesis.movementID
        )
        let productionGapSuccessor = try LocalPartDefinitionV1(
            partID: productionPart.partID,
            workspaceID: workspaceID,
            displayName: productionPart.displayName,
            canonicalUnit: productionPart.canonicalUnit,
            productIdentities: productionPart.productIdentities,
            preferredMinimum: productionPart.preferredMinimum,
            archived: true,
            revision: productionPart.revision + 2,
            mutationID: try C55PartsStockTestSupport.mutation(885)
        )
        XCTAssertThrowsError(
            try StockPartRetirementReceiptV1(
                archivedPartSuccessor: productionGapSuccessor,
                predecessor: productionPart,
                verifiedBalances: [productionArchiveBalance]
            )
        )
        let productionGapLocation = try C55PartsStockTestSupport.location(
            fixture.alternate,
            workspaceID: workspaceID,
            slot: 880,
            revision: 3
        )
        XCTAssertThrowsError(
            try productionHarness.writer.commitPartsStock(
                .upsertLocation(
                    productionGapLocation,
                    mutationID: try C55PartsStockTestSupport.mutation(886)
                )
            )
        )
        let productionForkLocation = try StockStorageLocationV1(
            locationID: productionArchiveLocation.locationID,
            workspaceID: workspaceID,
            kind: productionArchiveLocation.kind,
            label: "Forked archive location",
            binLabel: productionArchiveLocation.binLabel,
            revision: productionArchiveLocation.revision
        )
        XCTAssertThrowsError(
            try productionHarness.writer.commitPartsStock(
                .upsertLocation(
                    productionForkLocation,
                    mutationID: try C55PartsStockTestSupport.mutation(887)
                )
            )
        )
        let productionForkPredecessor = try LocalPartDefinitionV1(
            partID: productionPart.partID,
            workspaceID: workspaceID,
            displayName: "Forked archive predecessor",
            canonicalUnit: productionPart.canonicalUnit,
            productIdentities: productionPart.productIdentities,
            preferredMinimum: productionPart.preferredMinimum,
            revision: productionPart.revision,
            mutationID: productionPart.mutationID
        )
        let productionForkSuccessor = try LocalPartDefinitionV1(
            partID: productionPart.partID,
            workspaceID: workspaceID,
            displayName: productionForkPredecessor.displayName,
            canonicalUnit: productionForkPredecessor.canonicalUnit,
            productIdentities: productionForkPredecessor.productIdentities,
            preferredMinimum: productionForkPredecessor.preferredMinimum,
            archived: true,
            revision: productionForkPredecessor.revision + 1,
            mutationID: try C55PartsStockTestSupport.mutation(888)
        )
        let productionForkRetirement = try StockPartRetirementReceiptV1(
            archivedPartSuccessor: productionForkSuccessor,
            predecessor: productionForkPredecessor,
            verifiedBalances: [productionArchiveBalance]
        )
        XCTAssertThrowsError(
            try productionHarness.writer.commitPartsStock(
                .retirePart(productionForkRetirement)
            )
        )

        // Exercise the real sole writer through the C55 `.applyPartsStock`
        // path.  The work-resource subject and actor are seeded through their
        // existing canonical rows so this is the production contract, not a
        // test-only stand-in.
        let applyHarness = try C55ProductionWriterHarness(
            workspaceID: workspaceID,
            configurationName: "C55-Production-Writer-Apply"
        )
        let workActor = try C55PartsStockTestSupport.actor(workspaceID: workspaceID, slot: 800)
        let workItem = try WorkPacketItemV1(
            itemID: "C55-MATERIAL",
            kind: .inspection,
            expectedRevision: 1,
            itemSHA256: C55PartsStockTestSupport.digest("i")
        )
        let manifest = try WorkPacketManifestV1(
            manifestID: C55PartsStockTestSupport.id(830),
            packetID: C55PartsStockTestSupport.id(831),
            packetVersion: 1,
            workspaceID: workspaceID,
            items: [workItem],
            packageReleases: [],
            creationBasis: .explicitLocalSelection,
            creator: workActor,
            createdAt: C55PartsStockTestSupport.date(),
            mutationID: try C55PartsStockTestSupport.mutation(832)
        )
        applyHarness.context.insert(try ActorSnapshotRow(workActor))
        applyHarness.context.insert(try WorkPacketManifestRow(manifest))
        try applyHarness.context.save()
        let workSubject = try WorkResourceSubjectV1(
            workspaceID: workspaceID,
            kind: .workPacket,
            subjectID: manifest.manifestID.uuidString,
            subjectRevision: manifest.revision,
            subjectSHA256: manifest.manifestSHA256
        )
        let applyOpening = try C55PartsStockTestSupport.movement(
            movementID: C55PartsStockTestSupport.id(840),
            workspaceID: workspaceID,
            part: try part.frozenReference(),
            locationID: location.locationID,
            kind: .openingCount,
            quantity: known,
            unit: unit,
            preBalance: .unknown,
            postBalance: known,
            actor: try C55PartsStockTestSupport.actor(workspaceID: workspaceID, slot: 841),
            expectedLocationRevision: 0,
            mutationSlot: 842
        )
        let applyUseQuantity = try C55PartsStockTestSupport.stock(fixture.golden.use, unit: unit)
        let applyUsePostBalance = try StockQuantityV1(
            mantissa: known.mantissa - applyUseQuantity.mantissa,
            scale: known.scale,
            unit: unit
        )
        let applyUse = try C55PartsStockTestSupport.useReceipt(
            workspaceID: workspaceID,
            part: part,
            location: location,
            quantity: applyUseQuantity,
            preBalance: known,
            postBalance: applyUsePostBalance,
            expectedLocationRevision: applyOpening.locationRevision,
            slot: 850,
            workResourceSubject: workSubject,
            workResourceActor: workActor
        )
        _ = try applyHarness.writer.commitPartsStock(.upsertPart(part))
        _ = try applyHarness.writer.commitPartsStock(
            .upsertLocation(
                location,
                mutationID: try C55PartsStockTestSupport.mutation(843)
            )
        )
        _ = try applyHarness.writer.commitPartsStock(.appendMovement(applyOpening))
        let applyUseReceipt = try applyHarness.writer.commitPartsStock(.use(applyUse))
        XCTAssertEqual(applyUseReceipt.mutationID, applyUse.mutationID)
        XCTAssertEqual(applyUseReceipt.workspaceID, workspaceID)
        XCTAssertEqual(
            try applyHarness.writer.commitPartsStock(.use(applyUse)),
            applyUseReceipt
        )
        let divergentApplyUse = try C55PartsStockTestSupport.useReceipt(
            workspaceID: workspaceID,
            part: part,
            location: location,
            quantity: applyUseQuantity,
            preBalance: known,
            postBalance: applyUsePostBalance,
            expectedLocationRevision: applyOpening.locationRevision,
            slot: 850,
            workResourceSubject: workSubject,
            workResourceActor: try C55PartsStockTestSupport.actor(workspaceID: workspaceID, slot: 870)
        )
        XCTAssertNotEqual(divergentApplyUse.workResourceSuccessor, applyUse.workResourceSuccessor)
        XCTAssertThrowsError(
            try applyHarness.writer.commitPartsStock(.use(divergentApplyUse))
        )
        XCTAssertEqual(
            try applyHarness.context.fetch(FetchDescriptor<StockMovementEventRowV1>()).count,
            2
        )
        XCTAssertEqual(
            try applyHarness.context.fetch(FetchDescriptor<StockUseReceiptRowV1>()).count,
            1
        )
        XCTAssertEqual(
            try applyHarness.context.fetch(FetchDescriptor<ManualWorkResourceRecordRow>()).count,
            1
        )
        XCTAssertEqual(
            [
                try applyHarness.context.fetch(FetchDescriptor<LocalPartDefinitionRowV1>()).count,
                try applyHarness.context.fetch(FetchDescriptor<StockStorageLocationRowV1>()).count,
                try applyHarness.context.fetch(FetchDescriptor<StockMovementEventRowV1>()).count,
                try applyHarness.context.fetch(FetchDescriptor<StockUseReceiptRowV1>()).count,
                try applyHarness.context.fetch(FetchDescriptor<StockUseReversalReceiptRowV1>()).count,
                try applyHarness.context.fetch(FetchDescriptor<StockReturnReceiptRowV1>()).count,
                try applyHarness.context.fetch(FetchDescriptor<AbandonUnverifiedStockRowV1>()).count
            ],
            [1, 1, 2, 1, 0, 0, 0]
        )
        let applySnapshot = try PartsStockLifecycleAdapterV1(
            modelContext: applyHarness.context
        ).snapshotForBackup(workspaceID: workspaceID)
        try applySnapshot.validate()
        XCTAssertEqual(applySnapshot.parts, [part])
        XCTAssertEqual(applySnapshot.locations, [location])
        XCTAssertEqual(applySnapshot.movements, [applyOpening, applyUse.movement])
        XCTAssertEqual(applySnapshot.uses, [applyUse])

        let applyHistory = try applyHarness.writer.sourceMutationHistorySnapshot()
        let applyHistoryReceipts = try applyHistory.receipts.map {
            try MutationReceiptV1.decodeCanonical(from: $0.receiptData)
        }
        XCTAssertEqual(applyHistoryReceipts.count, 4)
        XCTAssertEqual(
            applyHistoryReceipts.map { $0.expectedRevision.workspaceRevision },
            [0, 1, 2, 3]
        )
        XCTAssertEqual(
            applyHistoryReceipts.map { $0.resultingRevision.workspaceRevision },
            [1, 2, 3, 4]
        )
        XCTAssertEqual(applyHistory.workspaceRevision, 4)
        XCTAssertEqual(
            applyHistory.lastLocalSequence,
            applyHistoryReceipts.map { $0.identity.localSequence }.max() ?? 0
        )
        let applyMutationSequence: [PartsStockMutationV1] = [
            .upsertPart(part),
            .upsertLocation(
                location,
                mutationID: try C55PartsStockTestSupport.mutation(843)
            ),
            .appendMovement(applyOpening),
            .use(applyUse)
        ]
        var expectedResultingMap: [WorkspaceEntityIdentityV1: UInt64] = [:]
        for (receipt, mutation) in zip(applyHistoryReceipts, applyMutationSequence) {
            let expectedMap = Dictionary(
                uniqueKeysWithValues: receipt.expectedRevision.entityRevisions.map {
                    ($0.identity, $0.revision)
                }
            )
            let targets = try mutation.concurrencyIdentities
            XCTAssertEqual(Set(expectedMap.keys), Set(targets))
            XCTAssertEqual(expectedMap.count, targets.count)
            for target in targets {
                XCTAssertEqual(expectedMap[target], try mutation.expectedRevision(for: target))
            }
            for image in try mutation.mutationPostImages {
                if case let .partsStock(id, kind, concurrency, revision, _) = image {
                    let physical = try WorkspaceEntityIdentityV1(kind: kind, id: id)
                    expectedResultingMap[physical] = revision
                    expectedResultingMap[concurrency] = revision
                } else {
                    let identity = try image.identity
                    expectedResultingMap[identity] = image.revision
                }
            }
            let resultingMap = Dictionary(
                uniqueKeysWithValues: receipt.resultingRevision.entityRevisions.map {
                    ($0.identity, $0.revision)
                }
            )
            XCTAssertEqual(resultingMap, expectedResultingMap)
        }
        let finalHistoryMap = Dictionary(
            uniqueKeysWithValues: applyHistory.entityRevisions.map {
                ($0.identity, $0.revision)
            }
        )
        let finalWriterMap = Dictionary(
            uniqueKeysWithValues: (try applyHarness.writer.currentRevision()).entityRevisions.map {
                ($0.identity, $0.revision)
            }
        )
        XCTAssertEqual(finalHistoryMap, finalWriterMap)
        XCTAssertEqual(finalHistoryMap, expectedResultingMap)
        let workResourceRecord = try V37BackupWorkResourceRecordV1(
            applyUse.workResourceSuccessor
        )
        let partyRecord = V9BackupPartyAccountabilityRecordV1(
            kind: .actorSnapshot,
            id: workActor.snapshotID,
            workspaceID: workspaceID.rawValue,
            revision: nil,
            canonicalData: try PartyAccountabilitySnapshotCodecV1.encode(workActor)
        )
        let packetRecord = V15BackupWorkPacketRecordV1(
            kind: .manifest,
            id: manifest.manifestID,
            workspaceID: workspaceID.rawValue,
            revision: manifest.revision,
            canonicalData: try WorkPacketCanonicalCodecV1.encode(manifest)
        )
        let backupRecords = V4BackupRecordsV1(
            assets: [],
            evidenceFiles: [],
            issues: [],
            mutationHistory: applyHistory,
            packets: [],
            partyAccountability: [partyRecord],
            recordsSchemaVersion: C55PartsStockBackupEnrollmentV1.recordsSchemaVersion,
            reports: [],
            sites: [],
            workflowRecords: [],
            workPackets: [packetRecord],
            workResources: [workResourceRecord],
            partsStockSnapshot: applySnapshot
        )
        XCTAssertNoThrow(try C49WorkResourceBackupImportBoundaryV1.validate(backupRecords))
        XCTAssertNoThrow(
            try C55PartsStockBackupImportBoundaryV1.validate(
                backupRecords,
                workspaceID: workspaceID
            )
        )
        XCTAssertEqual(MutationJournalStoreV1.maximumC55TerminalRevisionRowCount, 200_000)
        XCTAssertGreaterThan(MutationJournalStoreV1.maximumImportedEntityRevisionValidationCount, 1_024)

        // A later physical count is a real journal successor. Removing its
        // receipt, event, and stream while keeping the terminal workspace
        // frontier must fail closed; deleting an earlier catalog receipt must
        // fail for the same reason.
        let countHarness = try C55ProductionWriterHarness(
            workspaceID: workspaceID,
            configurationName: "C55-I01-Count-Erasure"
        )
        _ = try countHarness.writer.commitPartsStock(.upsertPart(part))
        _ = try countHarness.writer.commitPartsStock(
            .upsertLocation(
                location,
                mutationID: try C55PartsStockTestSupport.mutation(315)
            )
        )
        _ = try countHarness.writer.commitPartsStock(.appendMovement(openingMovement))
        _ = try countHarness.writer.commitPartsStock(.appendMovement(countMovement))
        let countSnapshot = try PartsStockLifecycleAdapterV1(
            modelContext: countHarness.context
        ).snapshotForBackup(workspaceID: workspaceID)
        let countHistory = try countHarness.writer.sourceMutationHistorySnapshot()
        let countRecords = V4BackupRecordsV1(
            assets: [], evidenceFiles: [], issues: [], mutationHistory: countHistory,
            packets: [], partyAccountability: [],
            recordsSchemaVersion: C55PartsStockBackupEnrollmentV1.recordsSchemaVersion,
            reports: [], sites: [], workflowRecords: [], workPackets: [],
            workResources: [], partsStockSnapshot: countSnapshot
        )
        XCTAssertNoThrow(
            try C55PartsStockBackupImportBoundaryV1.validate(
                countRecords,
                workspaceID: workspaceID
            )
        )
        func tamperedRecords(
            _ base: V4BackupRecordsV1,
            _ mutate: (inout [String: Any]) throws -> Void
        ) throws -> V4BackupRecordsV1 {
            var object = try XCTUnwrap(
                JSONSerialization.jsonObject(
                    with: JSONEncoder().encode(base)
                ) as? [String: Any]
            )
            try mutate(&object)
            return try JSONDecoder().decode(
                V4BackupRecordsV1.self,
                from: JSONSerialization.data(
                    withJSONObject: object,
                    options: [.sortedKeys]
                )
            )
        }
        // Reproduce the former projected-first-count erasure attack with a
        // canonically valid baseline and receipt. The forged package rebuilds
        // a correct definitions-only snapshot and removes its event/stream,
        // but retains the terminal workspace revision.
        let projectedReplica = ReplicaID(rawValue: C55PartsStockTestSupport.id(320))
        let projectedGenerationID = C55PartsStockTestSupport.id(321)
        let projectedCount = try C55PartsStockTestSupport.movement(
            movementID: C55PartsStockTestSupport.id(322),
            workspaceID: workspaceID,
            part: try part.frozenReference(),
            locationID: location.locationID,
            kind: .physicalCount,
            quantity: opening,
            unit: unit,
            preBalance: .unknown,
            postBalance: opening,
            actor: try C55PartsStockTestSupport.actor(workspaceID: workspaceID, slot: 323),
            expectedLocationRevision: 0,
            mutationSlot: 324
        )
        let projectedMutation = PartsStockMutationV1.appendMovement(projectedCount)
        let projectedStreamIdentity = try StockBalanceStreamIdentityV1.entity(
            partID: part.partID,
            locationID: location.locationID
        )
        let projectedExpected = try WorkspaceExpectedRevisionV1(
            workspaceID: workspaceID,
            generationID: projectedGenerationID,
            writerInstanceID: projectedReplica.rawValue,
            workspaceRevision: 0,
            entityRevisions: [
                WorkspaceEntityRevisionV1(identity: projectedStreamIdentity, revision: 0)
            ]
        )
        let projectedEnvelope = try MutationEnvelopeV1(
            request: try projectedMutation.canonicalWorkspaceMutationRequest(
                expectedRevision: projectedExpected
            ),
            identity: try WorkspaceReplicaIdentityV1(
                workspaceID: workspaceID,
                replicaID: projectedReplica
            ),
            sourceKind: .localUser
        )
        let projectedPartIdentity = try WorkspaceEntityIdentityV1(
            kind: .localPartDefinition,
            id: part.partID
        )
        let projectedLocationIdentity = try WorkspaceEntityIdentityV1(
            kind: .stockStorageLocation,
            id: location.locationID
        )
        let projectedMovementIdentity = try WorkspaceEntityIdentityV1(
            kind: .stockMovementEvent,
            id: projectedCount.movementID
        )
        let projectedResulting = try MutationPortableExpectedRevisionV1(
            WorkspaceExpectedRevisionV1(
                workspaceID: workspaceID,
                generationID: projectedGenerationID,
                writerInstanceID: projectedReplica.rawValue,
                workspaceRevision: 1,
                entityRevisions: [
                    WorkspaceEntityRevisionV1(identity: projectedPartIdentity, revision: 1),
                    WorkspaceEntityRevisionV1(identity: projectedLocationIdentity, revision: 1),
                    WorkspaceEntityRevisionV1(identity: projectedMovementIdentity, revision: 1),
                    WorkspaceEntityRevisionV1(identity: projectedStreamIdentity, revision: 1)
                ]
            )
        )
        let projectedReceipt = try MutationReceiptV1(
            identity: MutationReceiptIdentityV1(
                workspaceID: workspaceID,
                replicaID: projectedReplica,
                localSequence: 1
            ),
            envelope: projectedEnvelope,
            resultingRevision: projectedResulting,
            postImages: try projectedMutation.mutationPostImages,
            committedAt: C55PartsStockTestSupport.fixedDate
        )
        let projectedHistory = MutationHistorySnapshotV1(
            workspaceRevision: 1,
            lastLocalSequence: 1,
            receipts: [
                MutationHistoryReceiptRecordV1(
                    envelopeData: try projectedEnvelope.canonicalData(),
                    receiptData: try projectedReceipt.canonicalData(),
                    reversalBasisData: nil,
                    semanticReversalData: nil
                )
            ],
            quarantines: [],
            entityRevisions: [
                MutationHistoryEntityRevisionV1(
                    identity: projectedPartIdentity,
                    revision: 1,
                    externalProjectionSHA256: part.partSHA256
                ),
                MutationHistoryEntityRevisionV1(
                    identity: projectedLocationIdentity,
                    revision: 1,
                    externalProjectionSHA256: try PartsStockCanonicalCodecV1.sha256(location)
                ),
                MutationHistoryEntityRevisionV1(
                    identity: projectedMovementIdentity,
                    revision: 1
                ),
                MutationHistoryEntityRevisionV1(
                    identity: projectedStreamIdentity,
                    revision: 1
                )
            ]
        )
        let projectedSnapshot = try PartsStockBackupSnapshotV1(
            workspaceID: workspaceID,
            parts: [part], locations: [location], movements: [projectedCount],
            uses: [], reversals: [], returns: [], abandonments: []
        )
        let projectedRecords = V4BackupRecordsV1(
            assets: [], evidenceFiles: [], issues: [], mutationHistory: projectedHistory,
            packets: [], partyAccountability: [],
            recordsSchemaVersion: C55PartsStockBackupEnrollmentV1.recordsSchemaVersion,
            reports: [], sites: [], workflowRecords: [], workPackets: [],
            workResources: [], partsStockSnapshot: projectedSnapshot
        )
        XCTAssertNoThrow(try MutationJournalStoreV1.validateImportedSnapshot(projectedHistory))
        XCTAssertNoThrow(
            try C55PartsStockBackupImportBoundaryV1.validate(
                projectedRecords,
                workspaceID: workspaceID
            )
        )
        let projectedDefinitionsOnly = try PartsStockBackupSnapshotV1(
            workspaceID: workspaceID,
            parts: [part], locations: [location], movements: [],
            uses: [], reversals: [], returns: [], abandonments: []
        )
        let countErasure = try tamperedRecords(projectedRecords) { object in
            var history = try XCTUnwrap(object["mutationHistory"] as? [String: Any])
            history["receipts"] = []
            var revisions = try XCTUnwrap(
                history["entityRevisions"] as? [[String: Any]]
            )
            revisions.removeAll { row in
                guard let identity = row["identity"] as? [String: Any],
                      let kind = identity["kind"] as? String else { return false }
                return kind == WorkspaceEntityKindV1.stockMovementEvent.rawValue
                    || kind == WorkspaceEntityKindV1.stockBalanceStream.rawValue
            }
            history["entityRevisions"] = revisions
            object["mutationHistory"] = history
            object["partsStockSnapshot"] = try XCTUnwrap(
                JSONSerialization.jsonObject(
                    with: JSONEncoder().encode(projectedDefinitionsOnly)
                ) as? [String: Any]
            )
        }
        XCTAssertThrowsError(
            try C55PartsStockBackupImportBoundaryV1.validate(
                countErasure,
                workspaceID: workspaceID
            )
        )
        let missingMiddleCatalogReceipt = try tamperedRecords(countRecords) { object in
            var history = try XCTUnwrap(object["mutationHistory"] as? [String: Any])
            var receipts = try XCTUnwrap(history["receipts"] as? [[String: Any]])
            XCTAssertEqual(receipts.count, 4)
            receipts.remove(at: 1)
            history["receipts"] = receipts
            object["mutationHistory"] = history
        }
        XCTAssertThrowsError(
            try C55PartsStockBackupImportBoundaryV1.validate(
                missingMiddleCatalogReceipt,
                workspaceID: workspaceID
            )
        )

        let largeParts = try (0..<1_025).map { offset in
            try C55PartsStockTestSupport.part(
                fixture.golden,
                workspaceID: workspaceID,
                slot: 5_000 + offset
            )
        }
        let largeLocation = try C55PartsStockTestSupport.location(
            fixture.golden,
            workspaceID: workspaceID,
            slot: 6_100
        )
        let largeSnapshot = try PartsStockBackupSnapshotV1(
            workspaceID: workspaceID,
            parts: largeParts,
            locations: [largeLocation],
            movements: [], uses: [], reversals: [], returns: [], abandonments: []
        )
        let largeTerminalRows = try largeParts.map {
            MutationHistoryEntityRevisionV1(
                identity: try WorkspaceEntityIdentityV1(
                    kind: .localPartDefinition,
                    id: $0.partID
                ),
                revision: 1,
                externalProjectionSHA256: $0.partSHA256
            )
        } + [
            MutationHistoryEntityRevisionV1(
                identity: try WorkspaceEntityIdentityV1(
                    kind: .stockStorageLocation,
                    id: largeLocation.locationID
                ),
                revision: 1,
                externalProjectionSHA256: try PartsStockCanonicalCodecV1.sha256(largeLocation)
            )
        ]
        let largeHistory = MutationHistorySnapshotV1(
            workspaceRevision: 0,
            lastLocalSequence: 0,
            receipts: [],
            quarantines: [],
            entityRevisions: largeTerminalRows
        )
        XCTAssertEqual(largeTerminalRows.count, 1_026)
        XCTAssertNoThrow(try MutationJournalStoreV1.validateImportedSnapshot(largeHistory))
        let largeRecords = V4BackupRecordsV1(
            assets: [], evidenceFiles: [], issues: [], mutationHistory: largeHistory,
            packets: [], partyAccountability: [],
            recordsSchemaVersion: C55PartsStockBackupEnrollmentV1.recordsSchemaVersion,
            reports: [], sites: [], workflowRecords: [], workPackets: [],
            workResources: [], partsStockSnapshot: largeSnapshot
        )
        XCTAssertNoThrow(
            try C55PartsStockBackupImportBoundaryV1.validate(
                largeRecords,
                workspaceID: workspaceID
            )
        )

        // The per-receipt postimage limit is not a history-size limit: a
        // bounded 1,024-step physical-count stream must retain exact
        // pre/post and location-revision continuity.
        let longStreamPart = try C55PartsStockTestSupport.part(
            fixture.golden,
            workspaceID: workspaceID,
            slot: 7_000
        )
        let longStreamLocation = try C55PartsStockTestSupport.location(
            fixture.golden,
            workspaceID: workspaceID,
            slot: 7_001
        )
        let longStreamQuantity = try C55PartsStockTestSupport.stock(
            fixture.golden.opening,
            unit: unit
        )
        let longStreamOpening = try C55PartsStockTestSupport.movement(
            movementID: C55PartsStockTestSupport.id(7_002),
            workspaceID: workspaceID,
            part: try longStreamPart.frozenReference(),
            locationID: longStreamLocation.locationID,
            kind: .openingCount,
            quantity: longStreamQuantity,
            unit: unit,
            preBalance: .unknown,
            postBalance: longStreamQuantity,
            actor: try C55PartsStockTestSupport.actor(workspaceID: workspaceID, slot: 7_003),
            expectedLocationRevision: 0,
            mutationSlot: 7_004
        )
        var longStreamMovements = [longStreamOpening]
        var priorLongStreamMovement = longStreamOpening
        for offset in 1...1_024 {
            let movement = try C55PartsStockTestSupport.movement(
                movementID: C55PartsStockTestSupport.id(7_010 + offset * 3),
                workspaceID: workspaceID,
                part: try longStreamPart.frozenReference(),
                locationID: longStreamLocation.locationID,
                kind: .physicalCount,
                quantity: longStreamQuantity,
                unit: unit,
                preBalance: .known(longStreamQuantity),
                postBalance: longStreamQuantity,
                actor: try C55PartsStockTestSupport.actor(
                    workspaceID: workspaceID,
                    slot: 7_011 + offset * 3
                ),
                expectedLocationRevision: priorLongStreamMovement.locationRevision,
                mutationSlot: 7_012 + offset * 3,
                occurredOffset: TimeInterval(offset * 2)
            )
            longStreamMovements.append(movement)
            priorLongStreamMovement = movement
        }
        let longStreamSnapshot = try PartsStockBackupSnapshotV1(
            workspaceID: workspaceID,
            parts: [longStreamPart],
            locations: [longStreamLocation],
            movements: longStreamMovements,
            uses: [], reversals: [], returns: [], abandonments: []
        )
        try longStreamSnapshot.validate()
        XCTAssertEqual(longStreamSnapshot.movements.count, 1_025)
        XCTAssertEqual(longStreamSnapshot.movements.first?.kind, .openingCount)
        XCTAssertEqual(
            longStreamSnapshot.movements.dropFirst().map(\.locationRevision),
            Array(2...1_025).map(UInt64.init)
        )
        XCTAssertEqual(longStreamSnapshot.movements.last?.preBalance, .known(longStreamQuantity))
        XCTAssertEqual(longStreamSnapshot.movements.last?.postBalance, longStreamQuantity)
        XCTAssertEqual(MutationReceiptV1.maximumPostImageCount, 1_024)
        XCTAssertEqual(C49WorkResourceBackupImportBoundaryV1.recordsSchemaVersion, 36)
        XCTAssertEqual(C55PartsStockBackupImportBoundaryV1.persistentSchemaVersion, 41)
        let preC55Records = V4BackupRecordsV1(
            assets: [], evidenceFiles: [], issues: [], mutationHistory: nil,
            packets: [], partyAccountability: [], recordsSchemaVersion: 39,
            reports: [], sites: [], workflowRecords: [], partsStockSnapshot: nil
        )
        XCTAssertNoThrow(try C55PartsStockBackupEnrollmentV1.validate(preC55Records, workspaceID: workspaceID))
        XCTAssertThrowsError(
            try C55PartsStockBackupImportBoundaryV1.validate(
                preC55Records,
                workspaceID: workspaceID
            )
        )
        let missingSnapshotRecords = V4BackupRecordsV1(
            assets: [],
            evidenceFiles: [],
            issues: [],
            mutationHistory: applyHistory,
            packets: [],
            partyAccountability: [partyRecord],
            recordsSchemaVersion: C55PartsStockBackupEnrollmentV1.recordsSchemaVersion,
            reports: [],
            sites: [],
            workflowRecords: [],
            workPackets: [packetRecord],
            workResources: [workResourceRecord],
            partsStockSnapshot: nil
        )
        XCTAssertThrowsError(
            try C55PartsStockBackupImportBoundaryV1.validate(
                missingSnapshotRecords,
                workspaceID: workspaceID
            )
        )
        let extraPart = try C55PartsStockTestSupport.part(
            fixture.alternate,
            workspaceID: workspaceID,
            slot: 900
        )
        let extraSnapshot = try PartsStockBackupSnapshotV1(
            workspaceID: workspaceID,
            parts: [part, extraPart],
            locations: [location],
            movements: applySnapshot.movements,
            uses: applySnapshot.uses,
            reversals: [],
            returns: [],
            abandonments: []
        )
        let extraSnapshotRecords = V4BackupRecordsV1(
            assets: [],
            evidenceFiles: [],
            issues: [],
            mutationHistory: applyHistory,
            packets: [],
            partyAccountability: [partyRecord],
            recordsSchemaVersion: C55PartsStockBackupEnrollmentV1.recordsSchemaVersion,
            reports: [],
            sites: [],
            workflowRecords: [],
            workPackets: [packetRecord],
            workResources: [workResourceRecord],
            partsStockSnapshot: extraSnapshot
        )
        XCTAssertThrowsError(
            try C55PartsStockBackupImportBoundaryV1.validate(
                extraSnapshotRecords,
                workspaceID: workspaceID
            )
        )

        let applyRows = try applyHarness.context.fetch(FetchDescriptor<MutationReceiptRow>())
        let applyRow = try XCTUnwrap(
            applyRows.first(where: { $0.mutationID == applyUse.mutationID.rawValue })
        )
        func rejectEnvelopeTamper(_ mutate: ([String: Any]) -> [String: Any]) throws {
            let originalData = applyRow.envelopeData
            let originalSHA256 = applyRow.envelopeSHA256
            defer {
                applyRow.envelopeData = originalData
                applyRow.envelopeSHA256 = originalSHA256
                try? applyHarness.context.save()
            }
            var object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: originalData) as? [String: Any]
            )
            object = mutate(object)
            let tamperedData = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            applyRow.envelopeData = tamperedData
            applyRow.envelopeSHA256 = KernelCanonicalHashV1.sha256(tamperedData)
            try applyHarness.context.save()
            XCTAssertThrowsError(try applyHarness.journal.validateAll())
        }
        try rejectEnvelopeTamper { object in
            var value = object
            value["commandBodySHA256"] = C55PartsStockTestSupport.digest("x")
            return value
        }

        func rejectReceiptTamper(_ mutate: ([String: Any]) -> [String: Any]) throws {
            let originalData = applyRow.receiptData
            let originalSHA256 = applyRow.receiptSHA256
            defer {
                applyRow.receiptData = originalData
                applyRow.receiptSHA256 = originalSHA256
                try? applyHarness.context.save()
            }
            var object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: originalData) as? [String: Any]
            )
            object = mutate(object)
            let tamperedData = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            applyRow.receiptData = tamperedData
            applyRow.receiptSHA256 = KernelCanonicalHashV1.sha256(tamperedData)
            try applyHarness.context.save()
            XCTAssertThrowsError(try applyHarness.journal.validateAll())
        }
        try rejectReceiptTamper { object in
            var value = object
            value["commandBodySHA256"] = C55PartsStockTestSupport.digest("q")
            return value
        }
        try rejectReceiptTamper { object in
            var value = object
            var images = value["postImages"] as? [[String: Any]] ?? []
            if !images.isEmpty {
                var image = images[0]
                image["semanticSHA256"] = C55PartsStockTestSupport.digest("p")
                images[0] = image
            }
            value["postImages"] = images
            return value
        }
        try rejectReceiptTamper { object in
            var value = object
            var expected = value["expectedRevision"] as? [String: Any] ?? [:]
            expected["workspaceRevision"] = 999
            value["expectedRevision"] = expected
            return value
        }
        try rejectReceiptTamper { object in
            var value = object
            var resulting = value["resultingRevision"] as? [String: Any] ?? [:]
            resulting["workspaceRevision"] = 999
            value["resultingRevision"] = resulting
            return value
        }
        func extraRevisionEntry(
            _ object: [String: Any], key: String
        ) -> [String: Any] {
            var value = object
            var revision = value[key] as? [String: Any] ?? [:]
            var entries = revision["entityRevisions"] as? [[String: Any]] ?? []
            if var extra = entries.first,
               var identity = extra["identity"] as? [String: Any] {
                identity["id"] = C55PartsStockTestSupport.id(999).uuidString
                extra["identity"] = identity
                extra["revision"] = 0
                entries.append(extra)
                entries.sort { lhs, rhs in
                    let leftIdentity = lhs["identity"] as? [String: Any] ?? [:]
                    let rightIdentity = rhs["identity"] as? [String: Any] ?? [:]
                    let leftKey = "\((leftIdentity["kind"] as? String) ?? ""):\(((leftIdentity["id"] as? String) ?? "").lowercased())"
                    let rightKey = "\((rightIdentity["kind"] as? String) ?? ""):\(((rightIdentity["id"] as? String) ?? "").lowercased())"
                    return leftKey < rightKey
                }
            }
            revision["entityRevisions"] = entries
            value[key] = revision
            return value
        }
        try rejectReceiptTamper { object in
            extraRevisionEntry(object, key: "expectedRevision")
        }
        try rejectReceiptTamper { object in
            extraRevisionEntry(object, key: "resultingRevision")
        }
        try rejectReceiptTamper { object in
            var value = object
            var images = value["postImages"] as? [[String: Any]] ?? []
            if let first = images.first { images.append(first) }
            value["postImages"] = images
            return value
        }
        try rejectReceiptTamper { object in
            var value = object
            var images = value["postImages"] as? [[String: Any]] ?? []
            if !images.isEmpty {
                var image = images[0]
                var concurrency = image["concurrencyIdentity"] as? [String: Any] ?? [:]
                concurrency["kind"] = WorkspaceEntityKindV1.stockUseReceipt.rawValue
                image["concurrencyIdentity"] = concurrency
                images[0] = image
            }
            value["postImages"] = images
            return value
        }

        // C55 workspace revisions are a contiguous journal stream, including
        // the first receipt and the terminal state frontier.  Keep the
        // altered envelope/receipt pair internally valid so this exercises
        // journal continuity rather than canonical decoding or row hashing.
        func rejectC55WorkspaceRevisionTamper(
            mutationID: UUID,
            expectedWorkspaceRevision: UInt64,
            resultingWorkspaceRevision: UInt64
        ) throws {
            let row = try XCTUnwrap(
                applyRows.first(where: { $0.mutationID == mutationID })
            )
            let originalEnvelopeData = row.envelopeData
            let originalEnvelopeSHA256 = row.envelopeSHA256
            let originalReceiptData = row.receiptData
            let originalReceiptSHA256 = row.receiptSHA256
            defer {
                row.envelopeData = originalEnvelopeData
                row.envelopeSHA256 = originalEnvelopeSHA256
                row.receiptData = originalReceiptData
                row.receiptSHA256 = originalReceiptSHA256
                try? applyHarness.context.save()
            }

            let sourceEnvelope = try MutationEnvelopeV1.decodeCanonical(
                from: originalEnvelopeData
            )
            let sourceReceipt = try MutationReceiptV1.decodeCanonical(
                from: originalReceiptData
            )
            let expectedRevision = try WorkspaceExpectedRevisionV1(
                workspaceID: sourceEnvelope.expectedRevision.workspaceID,
                generationID: sourceEnvelope.expectedRevision.generationID,
                writerInstanceID: sourceEnvelope.replicaID.rawValue,
                workspaceRevision: expectedWorkspaceRevision,
                entityRevisions: sourceEnvelope.expectedRevision.entityRevisions
            )
            let alteredEnvelope = try MutationEnvelopeV1(
                request: WorkspaceMutationRequestV1(
                    mutationID: sourceEnvelope.mutationID,
                    expectedRevision: expectedRevision,
                    command: sourceEnvelope.command
                ),
                identity: try WorkspaceReplicaIdentityV1(
                    workspaceID: sourceEnvelope.workspaceID,
                    replicaID: sourceEnvelope.replicaID
                ),
                sourceKind: sourceEnvelope.sourceKind,
                contentDependencyIDs: sourceEnvelope.contentDependencyIDs,
                causationMutationID: sourceEnvelope.causationMutationID,
                correlationID: sourceEnvelope.correlationID,
                reversalPlanDigest: sourceEnvelope.reversalPlanDigest,
                semanticReversalReplayIdentitySHA256:
                    sourceEnvelope.semanticReversalReplayIdentitySHA256,
                semanticReversalExecution: sourceEnvelope.semanticReversalExecution
            )
            let resultingRevision = try MutationPortableExpectedRevisionV1(
                WorkspaceExpectedRevisionV1(
                    workspaceID: sourceReceipt.resultingRevision.workspaceID,
                    generationID: sourceReceipt.resultingRevision.generationID,
                    writerInstanceID: sourceEnvelope.replicaID.rawValue,
                    workspaceRevision: resultingWorkspaceRevision,
                    entityRevisions: sourceReceipt.resultingRevision.entityRevisions
                )
            )
            let alteredReceipt = try MutationReceiptV1(
                identity: sourceReceipt.identity,
                envelope: alteredEnvelope,
                resultingRevision: resultingRevision,
                postImages: sourceReceipt.postImages,
                reversesMutationID: sourceReceipt.reversesMutationID,
                committedAt: sourceReceipt.committedAt
            )
            row.envelopeData = try alteredEnvelope.canonicalData()
            row.envelopeSHA256 = try alteredEnvelope.canonicalSHA256()
            row.receiptData = try alteredReceipt.canonicalData()
            row.receiptSHA256 = try alteredReceipt.canonicalSHA256()
            try applyHarness.context.save()
            XCTAssertThrowsError(try applyHarness.journal.validateAll())
        }

        let firstApplyMutationID = try MutationEnvelopeV1.decodeCanonical(
            from: applyHistory.receipts[0].envelopeData
        ).mutationID.rawValue
        try rejectC55WorkspaceRevisionTamper(
            mutationID: firstApplyMutationID,
            expectedWorkspaceRevision: 1,
            resultingWorkspaceRevision: 2
        )
        let terminalApplyMutationID = try MutationEnvelopeV1.decodeCanonical(
            from: applyHistory.receipts[3].envelopeData
        ).mutationID.rawValue
        try rejectC55WorkspaceRevisionTamper(
            mutationID: terminalApplyMutationID,
            expectedWorkspaceRevision: 2,
            resultingWorkspaceRevision: 3
        )
        let stateRow = try XCTUnwrap(
            applyHarness.context.fetch(FetchDescriptor<WorkspaceMutationStateRow>()).first
        )
        let originalTerminalWorkspaceRevision = stateRow.workspaceRevision
        defer {
            stateRow.workspaceRevision = originalTerminalWorkspaceRevision
            try? applyHarness.context.save()
        }
        stateRow.workspaceRevision = originalTerminalWorkspaceRevision - 1
        try applyHarness.context.save()
        XCTAssertThrowsError(try applyHarness.journal.validateAll())
    }

    @MainActor
    func testV23P03C55I01PersistenceReplaySearchReportAndBackupClosure() async throws {
        let fixture = try Self.fixture()
        for value in ["SNAPSHOT_RECEIPT_COMPLETENESS", "CORRUPT_ROW_FAIL_CLOSED", "C49_RECORDS40_PERSISTENT41_ADMISSION", "APPLY_PARTS_STOCK_WORK_RESOURCE_JOURNAL_BYTES", "STREAM_CONTINUITY_PRE_POST"] {
            XCTAssertTrue(fixture.recoveryCases.contains(value), "fixture missing \(value)")
        }
        for value in ["TAMPERED_COMMAND_BODY_DIGEST", "TAMPERED_POSTIMAGE_DIGEST", "TAMPERED_EXPECTED_REVISION", "TAMPERED_RESULTING_REVISION", "MISSING_SNAPSHOT_EFFECT", "EXTRA_SNAPSHOT_EFFECT", "DIVERGENT_PRODUCTION_REPLAY", "MAX_REVISION_CORRUPTION_FAIL_CLOSED"] {
            XCTAssertTrue(fixture.hostileCases.contains(value), "fixture missing \(value)")
        }
        let workspaceID = C55PartsStockTestSupport.workspace()
        let unit = try C55PartsStockTestSupport.unit(fixture.golden.canonicalUnit)
        let part = try C55PartsStockTestSupport.part(fixture.golden, workspaceID: workspaceID, slot: 300)
        let location = try C55PartsStockTestSupport.location(fixture.golden, workspaceID: workspaceID, slot: 301)
        let opening = try C55PartsStockTestSupport.stock(fixture.golden.opening, unit: unit)
        let counted = try C55PartsStockTestSupport.stock(fixture.golden.physicalCount, unit: unit)
        let openingMovement = try C55PartsStockTestSupport.movement(
            movementID: C55PartsStockTestSupport.id(302), workspaceID: workspaceID,
            part: try part.frozenReference(), locationID: location.locationID, kind: .openingCount,
            quantity: try C55PartsStockTestSupport.stock(fixture.golden.opening, unit: unit), unit: unit,
            preBalance: .unknown, postBalance: opening, actor: try C55PartsStockTestSupport.actor(workspaceID: workspaceID, slot: 303),
            expectedLocationRevision: 0, mutationSlot: 304
        )
        let countMovement = try C55PartsStockTestSupport.movement(
            movementID: C55PartsStockTestSupport.id(305), workspaceID: workspaceID,
            part: try part.frozenReference(), locationID: location.locationID, kind: .physicalCount,
            quantity: try C55PartsStockTestSupport.stock(fixture.golden.physicalCount, unit: unit), unit: unit,
            preBalance: .known(opening), postBalance: counted, actor: try C55PartsStockTestSupport.actor(workspaceID: workspaceID, slot: 306),
            expectedLocationRevision: 1, mutationSlot: 307, occurredOffset: 2
        )
        let schema = Schema([
            LocalPartDefinitionRowV1.self,
            StockStorageLocationRowV1.self,
            StockMovementEventRowV1.self,
            StockUseReceiptRowV1.self,
            StockUseReversalReceiptRowV1.self,
            StockReturnReceiptRowV1.self,
            AbandonUnverifiedStockRowV1.self
        ])
        let container = try ModelContainer(
            for: schema,
            migrationPlan: nil,
            configurations: [ModelConfiguration(
                "C55-I01", schema: schema, isStoredInMemoryOnly: true,
                allowsSave: true, cloudKitDatabase: .none
            )]
        )
        let context = container.mainContext
        context.autosaveEnabled = false
        let partRow = try LocalPartDefinitionRowV1(part)
        let locationRow = try StockStorageLocationRowV1(location)
        let openingRow = try StockMovementEventRowV1(openingMovement)
        let countRow = try StockMovementEventRowV1(countMovement)
        context.insert(partRow)
        context.insert(locationRow)
        context.insert(openingRow)
        context.insert(countRow)
        try context.save()

        let adapter = PartsStockLifecycleAdapterV1(modelContext: context)
        let projections = try adapter.replay(workspaceID: workspaceID)
        let projection = try XCTUnwrap(projections.first)
        XCTAssertEqual(projection.balance, .known(counted))
        XCTAssertEqual(projection.locationRevision, 2)
        XCTAssertEqual(projection.lastMovementID, countMovement.movementID)
        XCTAssertEqual(try adapter.projection(workspaceID: workspaceID, partID: part.partID, locationID: location.locationID, unit: unit), projection)

        let searchByName = try adapter.search(workspaceID: workspaceID, query: fixture.golden.displayName)
        let searchBySKU = try adapter.search(workspaceID: workspaceID, query: fixture.golden.sku.lowercased())
        XCTAssertEqual(searchByName, [part])
        XCTAssertEqual(searchBySKU, [part])
        XCTAssertEqual(try adapter.search(workspaceID: workspaceID, query: ""), [part])
        let report = try adapter.report(workspaceID: workspaceID, reviewedPartIDs: [part.partID])
        XCTAssertEqual(report.workspaceID, workspaceID)
        XCTAssertEqual(report.parts, [try part.frozenReference()])
        XCTAssertTrue(fixture.claims.reportExcludesBalancesAndStorage)

        let backup = try adapter.snapshotForBackup(workspaceID: workspaceID)
        try backup.validate()
        XCTAssertEqual(backup.parts, [part])
        XCTAssertEqual(backup.locations, [location])
        XCTAssertEqual(backup.movements, [openingMovement, countMovement].sorted { ($0.recordedAt, $0.movementID.uuidString) < ($1.recordedAt, $1.movementID.uuidString) })

        // Materialization is an all-seven-family, single-save operation. A
        // second/collision attempt must leave the staged truth untouched.
        let stagingContainer = try ModelContainer(
            for: schema,
            migrationPlan: nil,
            configurations: [ModelConfiguration(
                "C55-I01-Staging", schema: schema, isStoredInMemoryOnly: true,
                allowsSave: true, cloudKitDatabase: .none
            )]
        )
        let stagingContext = stagingContainer.mainContext
        stagingContext.autosaveEnabled = false
        let stagingAdapter = PartsStockLifecycleAdapterV1(modelContext: stagingContext)
        let stagingReceipt = try stagingAdapter.materializeRestoreStaging(
            backup,
            targetWorkspaceID: workspaceID,
            operationID: C55PartsStockTestSupport.id(309),
            disposition: .replace,
            completedAt: C55PartsStockTestSupport.fixedDate
        )
        XCTAssertEqual(stagingReceipt.snapshotSHA256, backup.snapshotSHA256)
        XCTAssertEqual(stagingReceipt.effectSHA256, backup.snapshotSHA256)
        let stagedTruth = try stagingAdapter.snapshotForBackup(workspaceID: workspaceID)
        XCTAssertEqual(stagedTruth, backup)
        XCTAssertEqual(
            [
                try stagingContext.fetch(FetchDescriptor<LocalPartDefinitionRowV1>()).count,
                try stagingContext.fetch(FetchDescriptor<StockStorageLocationRowV1>()).count,
                try stagingContext.fetch(FetchDescriptor<StockMovementEventRowV1>()).count,
                try stagingContext.fetch(FetchDescriptor<StockUseReceiptRowV1>()).count,
                try stagingContext.fetch(FetchDescriptor<StockUseReversalReceiptRowV1>()).count,
                try stagingContext.fetch(FetchDescriptor<StockReturnReceiptRowV1>()).count,
                try stagingContext.fetch(FetchDescriptor<AbandonUnverifiedStockRowV1>()).count
            ],
            [1, 1, 2, 0, 0, 0, 0]
        )
        XCTAssertThrowsError(
            try stagingAdapter.materializeRestoreStaging(
                backup,
                targetWorkspaceID: workspaceID,
                operationID: C55PartsStockTestSupport.id(310),
                disposition: .replace,
                completedAt: C55PartsStockTestSupport.fixedDate
            )
        )
        XCTAssertEqual(try stagingAdapter.snapshotForBackup(workspaceID: workspaceID), stagedTruth)

        let lifecycleSpy = C55PartsStockLifecycleSpy(
            restoreEffectSHA256: backup.snapshotSHA256
        )
        let delegatedAdapter = PartsStockLifecycleAdapterV1(
            modelContext: context,
            lifecycle: lifecycleSpy
        )
        let delegatedReceipt = try await delegatedAdapter.restore(
            backup,
            targetWorkspaceID: workspaceID,
            operationID: C55PartsStockTestSupport.id(311),
            disposition: .replace
        )
        XCTAssertEqual(delegatedReceipt.effectSHA256, backup.snapshotSHA256)
        try await delegatedAdapter.rebuildSearch(workspaceID: workspaceID)
        try await delegatedAdapter.erase(workspaceID: workspaceID)
        try await delegatedAdapter.delete(workspaceID: workspaceID)
        XCTAssertEqual(lifecycleSpy.restoreCalls, 1)
        XCTAssertEqual(lifecycleSpy.rebuildCalls, 1)
        XCTAssertEqual(lifecycleSpy.eraseCalls, 1)
        XCTAssertEqual(lifecycleSpy.deleteCalls, 1)
        let wrongEffectSpy = C55PartsStockLifecycleSpy(
            restoreEffectSHA256: C55PartsStockTestSupport.digest("q")
        )
        let wrongEffectAdapter = PartsStockLifecycleAdapterV1(
            modelContext: context,
            lifecycle: wrongEffectSpy
        )
        do {
            try await wrongEffectAdapter.restore(
                backup,
                targetWorkspaceID: workspaceID,
                operationID: C55PartsStockTestSupport.id(312),
                disposition: .replace
            )
            XCTFail("restore must reject a mismatched prepared effect digest")
        } catch {
            XCTAssertEqual(error as? PartsStockFailureV1, .invalidDigest)
        }
        let encoded = try PartsStockCanonicalCodecV1.encode(backup)
        let decoded = try PartsStockCanonicalCodecV1.decode(PartsStockBackupSnapshotV1.self, from: encoded)
        XCTAssertEqual(decoded, backup)
        XCTAssertEqual(try PartsStockPersistenceCodecV1.decode(LocalPartDefinitionV1.self, from: partRow.canonicalData), part)
        let corruptMirrorRow = try LocalPartDefinitionRowV1(part)
        corruptMirrorRow.displayName = "Corrupt indexed mirror"
        XCTAssertThrowsError(try corruptMirrorRow.value())
        let corruptCanonicalRow = try StockStorageLocationRowV1(location)
        corruptCanonicalRow.canonicalData = Data("not canonical C55 data".utf8)
        XCTAssertThrowsError(try corruptCanonicalRow.value())
        let corruptMaxPartRow = try LocalPartDefinitionRowV1(part)
        corruptMaxPartRow.revision = UInt64.max
        XCTAssertThrowsError(try corruptMaxPartRow.value())
        let corruptMaxLocationRow = try StockStorageLocationRowV1(location)
        corruptMaxLocationRow.revision = UInt64.max
        XCTAssertThrowsError(try corruptMaxLocationRow.value())
        XCTAssertTrue(C55PartsStockPersistenceBoundaryV1.usesExistingWorkspaceWriter)
        XCTAssertFalse(C55PartsStockPersistenceBoundaryV1.parallelPersistenceAuthority)
        XCTAssertEqual(C55PartsStockPersistenceBoundaryV1.persistentTypes.count, 7)
        XCTAssertEqual(C55PartsStockPersistenceBoundaryV1.persistentTypes.count, fixture.persistenceRows.count)

        do {
            try await adapter.rebuildSearch(workspaceID: workspaceID)
            XCTFail("search rebuild requires the incumbent lifecycle port")
        } catch {
            XCTAssertEqual(error as? PartsStockFailureV1, .unavailable)
        }

        // A C55 stock receipt may share a backup with an unrelated retained
        // C49 receipt. Clone/fork must strip only the stock authority and its
        // stock-owned work row, while rebinding the unrelated row atomically.
        XCTAssertTrue(
            fixture.recoveryCases.contains("BACKUP_RESTORE_MIXED_HISTORY_CLONE_FORK")
        )
        let mixedHarness = try C55ProductionWriterHarness(
            workspaceID: workspaceID,
            configurationName: "C55-I01-Mixed-History"
        )
        let mixedActor = try C55PartsStockTestSupport.actor(
            workspaceID: workspaceID,
            slot: 1200
        )
        let mixedItem = try WorkPacketItemV1(
            itemID: "C55-MIXED-MATERIAL",
            kind: .inspection,
            expectedRevision: 1,
            itemSHA256: C55PartsStockTestSupport.digest("i")
        )
        let mixedManifest = try WorkPacketManifestV1(
            manifestID: C55PartsStockTestSupport.id(1202),
            packetID: C55PartsStockTestSupport.id(1203),
            packetVersion: 1,
            workspaceID: workspaceID,
            items: [mixedItem],
            packageReleases: [],
            creationBasis: .explicitLocalSelection,
            creator: mixedActor,
            createdAt: C55PartsStockTestSupport.fixedDate,
            mutationID: try C55PartsStockTestSupport.mutation(1204)
        )
        mixedHarness.context.insert(try ActorSnapshotRow(mixedActor))
        mixedHarness.context.insert(try WorkPacketManifestRow(mixedManifest))
        try mixedHarness.context.save()
        let mixedSubject = try WorkResourceSubjectV1(
            workspaceID: workspaceID,
            kind: .workPacket,
            subjectID: mixedManifest.manifestID.uuidString,
            subjectRevision: mixedManifest.revision,
            subjectSHA256: mixedManifest.manifestSHA256
        )
        let mixedPart = try C55PartsStockTestSupport.part(
            fixture.golden,
            workspaceID: workspaceID,
            slot: 1210
        )
        let mixedLocation = try C55PartsStockTestSupport.location(
            fixture.golden,
            workspaceID: workspaceID,
            slot: 1212
        )
        let mixedOpeningQuantity = try C55PartsStockTestSupport.stock(
            fixture.golden.opening,
            unit: unit
        )
        let mixedOpening = try C55PartsStockTestSupport.movement(
            movementID: C55PartsStockTestSupport.id(1214),
            workspaceID: workspaceID,
            part: try mixedPart.frozenReference(),
            locationID: mixedLocation.locationID,
            kind: .openingCount,
            quantity: mixedOpeningQuantity,
            unit: unit,
            preBalance: .unknown,
            postBalance: mixedOpeningQuantity,
            actor: try C55PartsStockTestSupport.actor(
                workspaceID: workspaceID,
                slot: 1217
            ),
            expectedLocationRevision: 0,
            mutationSlot: 1218
        )
        let mixedUseQuantity = try C55PartsStockTestSupport.stock(
            fixture.golden.use,
            unit: unit
        )
        let mixedUsePostBalance = try StockQuantityV1(
            mantissa: mixedOpeningQuantity.mantissa - mixedUseQuantity.mantissa,
            scale: mixedOpeningQuantity.scale,
            unit: unit
        )
        let mixedUse = try C55PartsStockTestSupport.useReceipt(
            workspaceID: workspaceID,
            part: mixedPart,
            location: mixedLocation,
            quantity: mixedUseQuantity,
            preBalance: mixedOpeningQuantity,
            postBalance: mixedUsePostBalance,
            expectedLocationRevision: mixedOpening.locationRevision,
            slot: 1220,
            workResourceSubject: mixedSubject,
            workResourceActor: mixedActor
        )
        _ = try mixedHarness.writer.commitPartsStock(.upsertPart(mixedPart))
        _ = try mixedHarness.writer.commitPartsStock(
            .upsertLocation(
                mixedLocation,
                mutationID: try C55PartsStockTestSupport.mutation(1213)
            )
        )
        _ = try mixedHarness.writer.commitPartsStock(.appendMovement(mixedOpening))
        _ = try mixedHarness.writer.commitPartsStock(.use(mixedUse))

        let unrelatedEntry = try C55PartsStockTestSupport.workEntry(
            workspaceID: workspaceID,
            part: try mixedPart.frozenReference(),
            quantity: try C55PartsStockTestSupport.exact(mixedUseQuantity),
            lineID: C55PartsStockTestSupport.id(1240),
            mutationID: try C55PartsStockTestSupport.mutation(1241),
            slot: 1242,
            subject: mixedSubject,
            entryActor: mixedActor
        )
        let unrelatedMutation = try WorkResourceMutationV1(
            workspaceID: workspaceID,
            mutationID: unrelatedEntry.mutationID,
            postImage: unrelatedEntry
        )
        let mixedCurrentRevision = try mixedHarness.writer.currentRevision()
        let unrelatedConcurrency = try unrelatedMutation.concurrencyIdentity
        let unrelatedExpected = try WorkspaceExpectedRevisionV1(
            workspaceID: workspaceID,
            generationID: mixedCurrentRevision.generationID,
            writerInstanceID: mixedCurrentRevision.writerInstanceID,
            workspaceRevision: mixedCurrentRevision.revision,
            entityRevisions: [
                WorkspaceEntityRevisionV1(
                    identity: unrelatedConcurrency,
                    revision: try unrelatedMutation.expectedRevision(
                        for: unrelatedConcurrency
                    )
                )
            ]
        )
        let unrelatedCommit = try mixedHarness.writer.commitWorkResource(
            unrelatedMutation,
            expectedRevision: unrelatedExpected
        )
        XCTAssertEqual(unrelatedCommit.mutationReceipt.mutationID, unrelatedEntry.mutationID)

        let mixedSnapshot = try PartsStockLifecycleAdapterV1(
            modelContext: mixedHarness.context
        ).snapshotForBackup(workspaceID: workspaceID)
        try mixedSnapshot.validate()
        let mixedHistory = try mixedHarness.writer.sourceMutationHistorySnapshot()
        let mixedWorkRows = try [mixedUse.workResourceSuccessor, unrelatedEntry]
            .map(V37BackupWorkResourceRecordV1.init)
            .sorted {
                ($0.workspaceID.uuidString.lowercased(), $0.entryID.uuidString.lowercased())
                    < ($1.workspaceID.uuidString.lowercased(), $1.entryID.uuidString.lowercased())
            }
        let sourceActorRecord = V9BackupPartyAccountabilityRecordV1(
            kind: .actorSnapshot,
            id: mixedActor.snapshotID,
            workspaceID: workspaceID.rawValue,
            revision: nil,
            canonicalData: try PartyAccountabilitySnapshotCodecV1.encode(mixedActor)
        )
        let sourcePacketRecord = V15BackupWorkPacketRecordV1(
            kind: .manifest,
            id: mixedManifest.manifestID,
            workspaceID: workspaceID.rawValue,
            revision: mixedManifest.revision,
            canonicalData: try WorkPacketCanonicalCodecV1.encode(mixedManifest)
        )
        func mixedRecords(
            actorRecord: V9BackupPartyAccountabilityRecordV1,
            packetRecord: V15BackupWorkPacketRecordV1
        ) -> V4BackupRecordsV1 {
            V4BackupRecordsV1(
                assets: [],
                deletionLedger: .empty,
                evidenceFiles: [],
                issues: [],
                mutationHistory: mixedHistory,
                packets: [],
                partyAccountability: [actorRecord],
                recordsSchemaVersion: C55PartsStockBackupEnrollmentV1.recordsSchemaVersion,
                reports: [],
                sites: [],
                workflowRecords: [],
                workPackets: [packetRecord],
                workResources: mixedWorkRows,
                partsStockSnapshot: mixedSnapshot
            )
        }
        let sourceRecords = mixedRecords(
            actorRecord: sourceActorRecord,
            packetRecord: sourcePacketRecord
        )
        let sourceEntries = [mixedUse.workResourceSuccessor, unrelatedEntry].sorted {
            ($0.workspaceID.rawValue.uuidString.lowercased(), $0.entryID.uuidString.lowercased())
                < ($1.workspaceID.rawValue.uuidString.lowercased(), $1.entryID.uuidString.lowercased())
        }
        XCTAssertEqual(try sourceRecords.validateC49WorkResources(), sourceEntries)
        XCTAssertNoThrow(
            try C55PartsStockBackupImportBoundaryV1.validate(
                sourceRecords,
                workspaceID: workspaceID
            )
        )
        let sourceEnvelopes = try mixedHistory.receipts.map {
            try MutationEnvelopeV1.decodeCanonical(from: $0.envelopeData)
        }
        XCTAssertEqual(sourceEnvelopes.count, 5)
        XCTAssertTrue(sourceEnvelopes.dropLast().allSatisfy { envelope in
            if case .applyPartsStock = envelope.command { return true }
            return false
        })
        let sourceLastEnvelope = try XCTUnwrap(sourceEnvelopes.last)
        guard case let .applyWorkResource(sourceUnrelatedMutation) = sourceLastEnvelope.command else {
            XCTFail("mixed history must retain an unrelated applyWorkResource receipt")
            return
        }
        XCTAssertEqual(sourceUnrelatedMutation.postImage, unrelatedEntry)
        func reencodedRecords(
            _ base: V4BackupRecordsV1,
            _ mutate: (inout [String: Any]) throws -> Void
        ) throws -> V4BackupRecordsV1 {
            var object = try XCTUnwrap(
                JSONSerialization.jsonObject(
                    with: JSONEncoder().encode(base)
                ) as? [String: Any]
            )
            try mutate(&object)
            return try JSONDecoder().decode(
                V4BackupRecordsV1.self,
                from: JSONSerialization.data(
                    withJSONObject: object,
                    options: [.sortedKeys]
                )
            )
        }

        let mixedServiceRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "C55-I01-Mixed-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: mixedServiceRoot,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: mixedServiceRoot) }
        let restoreService = try BackupRestoreService(
            applicationSupportURL: mixedServiceRoot
        )
        let mixedMembers = ValidatedV4BackupMembersV1(
            rootURL: mixedServiceRoot,
            rootIdentity: try BackupPackageAnchoredFile.rootIdentity(
                at: mixedServiceRoot
            ),
            descriptors: [:],
            maximumMemberByteCount: 0
        )

        func mixedIdentity(
            _ mode: BackupRestoreMode,
            targetWorkspaceID: WorkspaceID,
            targetGenerationID: UUID,
            targetReplicaID: UUID
        ) throws -> RestoreIdentityV1 {
            let sourceReplicaID = C55PartsStockTestSupport.id(1260)
            let oldWorkspaceID = mode == .replaceExisting
                ? workspaceID.rawValue
                : C55PartsStockTestSupport.id(1261)
            let oldPointer = RestorePointerIdentityV1(
                generationID: C55PartsStockTestSupport.id(1262),
                generationManifestSHA256: C55PartsStockTestSupport.digest("a"),
                knownReplicaIDs: [],
                workspaceID: oldWorkspaceID,
                replicaID: C55PartsStockTestSupport.id(1263)
            )
            return try RestoreIdentityDecisionV1.decide(
                RestoreIdentityDecisionInputV1(
                    mode: mode,
                    source: RestoreSourceIdentityV1(
                        workspaceID: workspaceID.rawValue,
                        replicaID: sourceReplicaID
                    ),
                    oldPointer: oldPointer,
                    targetGenerationID: targetGenerationID,
                    targetGenerationManifestSHA256: C55PartsStockTestSupport.digest("b"),
                    allocatedWorkspaceID: mode == .replaceExisting
                        ? nil
                        : targetWorkspaceID.rawValue,
                    allocatedReplicaID: targetReplicaID
                )
            )
        }

        for (index, mode) in [BackupRestoreMode.clone, .fork].enumerated() {
            let targetWorkspaceID = C55PartsStockTestSupport.workspace(1270 + index)
            let targetActorReference = try LocalActorReferenceV1(
                actorReferenceID: mixedActor.actor.actorReferenceID,
                workspaceID: targetWorkspaceID,
                partyID: mixedActor.actor.partyID,
                displayName: mixedActor.actor.displayName
            )
            let targetActor = try ActorSnapshotV1(
                snapshotID: mixedActor.snapshotID,
                workspaceID: targetWorkspaceID,
                actor: targetActorReference,
                responsibility: mixedActor.responsibility,
                displayNameAtTime: mixedActor.displayNameAtTime,
                capturedAt: mixedActor.capturedAt
            )
            let targetManifest = try mixedManifest.rebound(to: targetWorkspaceID)
            let destinationRecords = mixedRecords(
                actorRecord: V9BackupPartyAccountabilityRecordV1(
                    kind: .actorSnapshot,
                    id: targetActor.snapshotID,
                    workspaceID: targetWorkspaceID.rawValue,
                    revision: nil,
                    canonicalData: try PartyAccountabilitySnapshotCodecV1.encode(targetActor)
                ),
                packetRecord: V15BackupWorkPacketRecordV1(
                    kind: .manifest,
                    id: targetManifest.manifestID,
                    workspaceID: targetWorkspaceID.rawValue,
                    revision: targetManifest.revision,
                    canonicalData: try WorkPacketCanonicalCodecV1.encode(targetManifest)
                )
            )
            let identity = try mixedIdentity(
                mode,
                targetWorkspaceID: targetWorkspaceID,
                targetGenerationID: C55PartsStockTestSupport.id(1280 + index),
                targetReplicaID: C55PartsStockTestSupport.id(1282 + index)
            )
            let projected = try restoreService.c55RebindingWorkResourcesForTesting(
                in: destinationRecords,
                sourceRecords: sourceRecords,
                identity: identity,
                partsStockOperationID: C55PartsStockTestSupport.id(1290 + index)
            )
            let projectedSnapshot = try XCTUnwrap(projected.partsStockSnapshot)
            try C55PartsStockBackupImportBoundaryV1.validate(
                projected,
                workspaceID: targetWorkspaceID
            )
            XCTAssertEqual(projectedSnapshot.workspaceID, targetWorkspaceID)
            let expectedProjectedParts = mixedSnapshot.parts.filter { !$0.archived }
            let expectedProjectedLocations = mixedSnapshot.locations.filter { !$0.archived }
            XCTAssertEqual(projectedSnapshot.parts.map(\.partID), expectedProjectedParts.map(\.partID))
            XCTAssertEqual(projectedSnapshot.parts.map(\.displayName), expectedProjectedParts.map(\.displayName))
            XCTAssertEqual(projectedSnapshot.parts.map(\.canonicalUnit), expectedProjectedParts.map(\.canonicalUnit))
            XCTAssertEqual(projectedSnapshot.locations.map(\.locationID), expectedProjectedLocations.map(\.locationID))
            XCTAssertEqual(projectedSnapshot.locations.map(\.label), expectedProjectedLocations.map(\.label))
            XCTAssertTrue(projectedSnapshot.parts.allSatisfy { !$0.archived && $0.revision == 1 })
            XCTAssertTrue(projectedSnapshot.locations.allSatisfy { !$0.archived && $0.revision == 1 })
            XCTAssertTrue(projectedSnapshot.movements.isEmpty)
            XCTAssertTrue(projectedSnapshot.uses.isEmpty)
            XCTAssertTrue(projectedSnapshot.reversals.isEmpty)
            XCTAssertTrue(projectedSnapshot.returns.isEmpty)
            XCTAssertTrue(projectedSnapshot.abandonments.isEmpty)
            XCTAssertTrue(projectedSnapshot.parts.allSatisfy { $0.workspaceID == targetWorkspaceID })
            XCTAssertTrue(projectedSnapshot.locations.allSatisfy { $0.workspaceID == targetWorkspaceID })

            let projectedEntries = try projected.validateC49WorkResources()
            let projectedEntry = try XCTUnwrap(projectedEntries.first)
            XCTAssertEqual(projectedEntries.count, 1)
            XCTAssertEqual(projectedEntry.entryID, unrelatedEntry.entryID)
            XCTAssertEqual(projectedEntry.workspaceID, targetWorkspaceID)
            XCTAssertEqual(projectedEntry.subject.workspaceID, targetWorkspaceID)
            XCTAssertEqual(projectedEntry.subject.subjectSHA256, targetManifest.manifestSHA256)
            XCTAssertNotEqual(projectedEntry.entryID, mixedUse.workResourceSuccessor.entryID)
            XCTAssertEqual(projected.workResources.count, 1)

            let projectedHistory = try XCTUnwrap(projected.mutationHistory)
            let projectedBaselineRows = projectedHistory.entityRevisions.filter { row in
                row.identity.kind == .localPartDefinition
                    || row.identity.kind == .stockStorageLocation
            }
            XCTAssertEqual(
                projectedBaselineRows.count,
                projectedSnapshot.parts.count + projectedSnapshot.locations.count
            )
            for value in projectedSnapshot.parts {
                let identity = try WorkspaceEntityIdentityV1(
                    kind: .localPartDefinition,
                    id: value.partID
                )
                let baseline = try XCTUnwrap(
                    projectedBaselineRows.first { $0.identity == identity }
                )
                XCTAssertEqual(baseline.revision, 1)
                XCTAssertEqual(baseline.externalProjectionSHA256, value.partSHA256)
            }
            for value in projectedSnapshot.locations {
                let identity = try WorkspaceEntityIdentityV1(
                    kind: .stockStorageLocation,
                    id: value.locationID
                )
                let baseline = try XCTUnwrap(
                    projectedBaselineRows.first { $0.identity == identity }
                )
                XCTAssertEqual(baseline.revision, 1)
                XCTAssertEqual(
                    baseline.externalProjectionSHA256,
                    try PartsStockCanonicalCodecV1.sha256(value)
                )
            }
            XCTAssertTrue(projectedHistory.entityRevisions.allSatisfy { row in
                switch row.identity.kind {
                case .localPartDefinition, .stockStorageLocation, .workResourceEntry:
                    return true
                case .stockBalanceStream, .stockMovementEvent, .stockUseReceipt,
                     .stockUseReversalReceipt, .stockReturnReceipt, .stockAbandonment:
                    return false
                default:
                    return true
                }
            })
            let projectedEnvelope = try XCTUnwrap(
                projectedHistory.receipts.map {
                    try MutationEnvelopeV1.decodeCanonical(from: $0.envelopeData)
                }.first
            )
            let projectedReceipt = try XCTUnwrap(
                projectedHistory.receipts.map {
                    try MutationReceiptV1.decodeCanonical(from: $0.receiptData)
                }.first
            )
            guard case let .applyWorkResource(projectedMutation) = projectedEnvelope.command else {
                XCTFail("clone/fork must retain the unrelated work-resource receipt")
                continue
            }
            XCTAssertEqual(projectedMutation.postImage, projectedEntry)
            XCTAssertEqual(projectedMutation.workspaceID, targetWorkspaceID)
            XCTAssertNil(projectedEnvelope.causationMutationID)
            XCTAssertNil(projectedReceipt.reversesMutationID)
            XCTAssertTrue(projectedHistory.receipts.allSatisfy { record in
                let envelope = try? MutationEnvelopeV1.decodeCanonical(from: record.envelopeData)
                let receipt = try? MutationReceiptV1.decodeCanonical(from: record.receiptData)
                return (envelope.map {
                    if case .applyPartsStock = $0.command { return false }
                    return true
                } ?? false)
                    && receipt?.reversesMutationID == nil
                    && record.reversalBasisData == nil
                    && record.semanticReversalData == nil
            })
            let resultingMap = Dictionary(
                uniqueKeysWithValues: projectedReceipt.resultingRevision.entityRevisions.map {
                    ($0.identity, $0.revision)
                }
            )
            let projectedHistoryMap = Dictionary(
                uniqueKeysWithValues: projectedHistory.entityRevisions.map {
                    ($0.identity, $0.revision)
                }
            )
            let projectedNonStockHistoryMap = Dictionary(
                uniqueKeysWithValues: projectedHistory.entityRevisions.filter { row in
                    switch row.identity.kind {
                    case .localPartDefinition, .stockStorageLocation, .stockBalanceStream,
                         .stockMovementEvent, .stockUseReceipt, .stockUseReversalReceipt,
                         .stockReturnReceipt, .stockAbandonment:
                        return false
                    default:
                        return true
                    }
                }.map { ($0.identity, $0.revision) }
            )
            let projectedNonStockResultMap = Dictionary(
                uniqueKeysWithValues: resultingMap.filter { pair in
                    switch pair.key.kind {
                    case .localPartDefinition, .stockStorageLocation, .stockBalanceStream,
                         .stockMovementEvent, .stockUseReceipt, .stockUseReversalReceipt,
                         .stockReturnReceipt, .stockAbandonment:
                        return false
                    default:
                        return true
                    }
                }.map { ($0.key, $0.value) }
            )
            XCTAssertEqual(projectedNonStockHistoryMap, projectedNonStockResultMap)
            for baseline in projectedBaselineRows {
                XCTAssertEqual(projectedHistoryMap[baseline.identity], baseline.revision)
                XCTAssertNil(resultingMap[baseline.identity])
            }
            func recordsWithJSONMutation(
                _ base: V4BackupRecordsV1,
                _ mutate: (inout [String: Any]) throws -> Void
            ) throws -> V4BackupRecordsV1 {
                let encoded = try JSONEncoder().encode(base)
                var object = try XCTUnwrap(
                    JSONSerialization.jsonObject(with: encoded) as? [String: Any]
                )
                try mutate(&object)
                let tampered = try JSONSerialization.data(
                    withJSONObject: object,
                    options: [.sortedKeys]
                )
                return try JSONDecoder().decode(
                    V4BackupRecordsV1.self,
                    from: tampered
                )
            }
            func recordsWithHistoryMutation(
                _ mutate: (inout [[String: Any]]) -> Void
            ) throws -> V4BackupRecordsV1 {
                try recordsWithJSONMutation(projected) { object in
                    var history = try XCTUnwrap(
                        object["mutationHistory"] as? [String: Any]
                    )
                    var revisions = try XCTUnwrap(
                        history["entityRevisions"] as? [[String: Any]]
                    )
                    mutate(&revisions)
                    history["entityRevisions"] = revisions
                    object["mutationHistory"] = history
                }
            }
            func recordsWithHistoryReceiptMutation(
                _ base: V4BackupRecordsV1,
                _ mutate: (inout [[String: Any]]) -> Void
            ) throws -> V4BackupRecordsV1 {
                try recordsWithJSONMutation(base) { object in
                var history = try XCTUnwrap(
                    object["mutationHistory"] as? [String: Any]
                )
                var receipts = try XCTUnwrap(
                    history["receipts"] as? [[String: Any]]
                )
                mutate(&receipts)
                history["receipts"] = receipts
                object["mutationHistory"] = history
                }
            }
            func historyRowKind(_ row: [String: Any]) -> String? {
                (row["identity"] as? [String: Any])?["kind"] as? String
            }
            let missingBaseline = try recordsWithHistoryMutation { revisions in
                if let index = revisions.firstIndex(where: {
                    historyRowKind($0) == WorkspaceEntityKindV1.localPartDefinition.rawValue
                }) {
                    revisions.remove(at: index)
                }
            }
            XCTAssertThrowsError(
                try C55PartsStockBackupImportBoundaryV1.validate(
                    missingBaseline,
                    workspaceID: targetWorkspaceID
                )
            )
            let tamperedBaseline = try recordsWithHistoryMutation { revisions in
                guard let index = revisions.firstIndex(where: {
                    historyRowKind($0) == WorkspaceEntityKindV1.localPartDefinition.rawValue
                }) else { return }
                var row = revisions[index]
                row["externalProjectionSHA256"] = C55PartsStockTestSupport.digest("z")
                revisions[index] = row
            }
            XCTAssertThrowsError(
                try C55PartsStockBackupImportBoundaryV1.validate(
                    tamperedBaseline,
                    workspaceID: targetWorkspaceID
                )
            )
            let extraBaselineIdentity = try WorkspaceEntityIdentityV1(
                kind: .localPartDefinition,
                id: C55PartsStockTestSupport.id(1390 + index)
            )
            let extraBaselineRow = MutationHistoryEntityRevisionV1(
                identity: extraBaselineIdentity,
                revision: 1,
                externalProjectionSHA256: C55PartsStockTestSupport.digest("e")
            )
            let extraBaselineObject = try XCTUnwrap(
                JSONSerialization.jsonObject(
                    with: try JSONEncoder().encode(extraBaselineRow)
                ) as? [String: Any]
            )
            let extraBaseline = try recordsWithHistoryMutation { revisions in
                revisions.append(extraBaselineObject)
            }
            XCTAssertThrowsError(
                try C55PartsStockBackupImportBoundaryV1.validate(
                    extraBaseline,
                    workspaceID: targetWorkspaceID
                )
            )
            let foreignReceiptRecordObject = try XCTUnwrap(
                JSONSerialization.jsonObject(
                    with: JSONEncoder().encode(mixedHistory.receipts.last!)
                ) as? [String: Any]
            )
            let foreignReceiptRecords = try recordsWithJSONMutation(projected) { object in
                var history = try XCTUnwrap(
                    object["mutationHistory"] as? [String: Any]
                )
                var receipts = try XCTUnwrap(
                    history["receipts"] as? [[String: Any]]
                )
                receipts.append(foreignReceiptRecordObject)
                history["receipts"] = receipts
                object["mutationHistory"] = history
            }
            XCTAssertThrowsError(
                try C55PartsStockBackupImportBoundaryV1.validate(
                    foreignReceiptRecords,
                    workspaceID: targetWorkspaceID
                )
            )
            let foreignQuarantine = MutationHistoryQuarantineRecordV1(
                workspaceID: workspaceID,
                mutationID: C55PartsStockTestSupport.id(1410),
                identityDomain: .mutationEnvelope,
                acceptedIdentitySHA256: C55PartsStockTestSupport.digest("a"),
                conflictingIdentitySHA256: C55PartsStockTestSupport.digest("b"),
                detectedAt: C55PartsStockTestSupport.fixedDate
            )
            let foreignQuarantineObject = try XCTUnwrap(
                JSONSerialization.jsonObject(
                    with: JSONEncoder().encode(foreignQuarantine)
                ) as? [String: Any]
            )
            let foreignQuarantineRecords = try recordsWithJSONMutation(projected) { object in
                var history = try XCTUnwrap(
                    object["mutationHistory"] as? [String: Any]
                )
                var quarantines = try XCTUnwrap(
                    history["quarantines"] as? [[String: Any]]
                )
                quarantines.append(foreignQuarantineObject)
                history["quarantines"] = quarantines
                object["mutationHistory"] = history
            }
            XCTAssertThrowsError(
                try C55PartsStockBackupImportBoundaryV1.validate(
                    foreignQuarantineRecords,
                    workspaceID: targetWorkspaceID
                )
            )
            XCTAssertEqual(
                resultingMap[try WorkspaceEntityIdentityV1(
                    kind: .workResourceEntry,
                    id: unrelatedEntry.entryID
                )],
                unrelatedEntry.revision
            )
        }

        // A second replica cannot replay the same mutation after the
        // imported-history cutoff, and a different replica cannot skip a
        // workspace revision. Keep both records canonically encoded so the
        // boundary, rather than JSON decoding, owns the rejection.
        let duplicateReplica = ReplicaID(rawValue: C55PartsStockTestSupport.id(1400))
        let duplicateSourceRecord = mixedHistory.receipts[0]
        let duplicateSourceEnvelope = try MutationEnvelopeV1.decodeCanonical(
            from: duplicateSourceRecord.envelopeData
        )
        let duplicateSourceReceipt = try MutationReceiptV1.decodeCanonical(
            from: duplicateSourceRecord.receiptData
        )
        let duplicateExpectedRevision = try WorkspaceExpectedRevisionV1(
            workspaceID: duplicateSourceEnvelope.expectedRevision.workspaceID,
            generationID: duplicateSourceEnvelope.expectedRevision.generationID,
            writerInstanceID: duplicateReplica.rawValue,
            workspaceRevision: duplicateSourceEnvelope.expectedRevision.workspaceRevision,
            entityRevisions: duplicateSourceEnvelope.expectedRevision.entityRevisions
        )
        let duplicateEnvelope = try MutationEnvelopeV1(
            request: WorkspaceMutationRequestV1(
                mutationID: duplicateSourceEnvelope.mutationID,
                expectedRevision: duplicateExpectedRevision,
                command: duplicateSourceEnvelope.command
            ),
            identity: try WorkspaceReplicaIdentityV1(
                workspaceID: workspaceID,
                replicaID: duplicateReplica
            ),
            sourceKind: duplicateSourceEnvelope.sourceKind,
            contentDependencyIDs: duplicateSourceEnvelope.contentDependencyIDs,
            causationMutationID: duplicateSourceEnvelope.causationMutationID,
            correlationID: duplicateSourceEnvelope.correlationID,
            reversalPlanDigest: duplicateSourceEnvelope.reversalPlanDigest,
            semanticReversalReplayIdentitySHA256:
                duplicateSourceEnvelope.semanticReversalReplayIdentitySHA256,
            semanticReversalExecution: duplicateSourceEnvelope.semanticReversalExecution
        )
        let duplicateReceipt = try MutationReceiptV1(
            identity: MutationReceiptIdentityV1(
                workspaceID: workspaceID,
                replicaID: duplicateReplica,
                localSequence: duplicateSourceReceipt.identity.localSequence
            ),
            envelope: duplicateEnvelope,
            resultingRevision: duplicateSourceReceipt.resultingRevision,
            postImages: duplicateSourceReceipt.postImages,
            reversesMutationID: duplicateSourceReceipt.reversesMutationID,
            committedAt: duplicateSourceReceipt.committedAt
        )
        let duplicateRecord = MutationHistoryReceiptRecordV1(
            envelopeData: try duplicateEnvelope.canonicalData(),
            receiptData: try duplicateReceipt.canonicalData(),
            reversalBasisData: duplicateSourceRecord.reversalBasisData,
            semanticReversalData: duplicateSourceRecord.semanticReversalData
        )
        let duplicateRecordObject = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(duplicateRecord)
            ) as? [String: Any]
        )
        let duplicateReplicaRecords = try reencodedRecords(sourceRecords) { object in
            var history = try XCTUnwrap(object["mutationHistory"] as? [String: Any])
            var receipts = try XCTUnwrap(history["receipts"] as? [[String: Any]])
            receipts.append(duplicateRecordObject)
            history["receipts"] = receipts
            object["mutationHistory"] = history
        }
        XCTAssertThrowsError(
            try C55PartsStockBackupImportBoundaryV1.validate(
                duplicateReplicaRecords,
                workspaceID: workspaceID
            )
        )

        let gappedReplica = ReplicaID(rawValue: C55PartsStockTestSupport.id(1401))
        let gappedEntry = try C55PartsStockTestSupport.workEntry(
            workspaceID: workspaceID,
            part: try mixedPart.frozenReference(),
            quantity: try C55PartsStockTestSupport.exact(mixedUseQuantity),
            lineID: C55PartsStockTestSupport.id(1402),
            mutationID: try C55PartsStockTestSupport.mutation(1403),
            slot: 1404,
            subject: mixedSubject,
            entryActor: mixedActor
        )
        let gappedMutation = try WorkResourceMutationV1(
            workspaceID: workspaceID,
            mutationID: gappedEntry.mutationID,
            postImage: gappedEntry
        )
        let gappedExpectedRevision = try WorkspaceExpectedRevisionV1(
            workspaceID: workspaceID,
            generationID: sourceLastEnvelope.generationID,
            writerInstanceID: gappedReplica.rawValue,
            workspaceRevision: mixedHistory.workspaceRevision + 1,
            entityRevisions: [
                WorkspaceEntityRevisionV1(
                    identity: try gappedMutation.concurrencyIdentity,
                    revision: try gappedMutation.expectedRevision(
                        for: gappedMutation.concurrencyIdentity
                    )
                )
            ]
        )
        let gappedRequest = try gappedMutation.canonicalWorkspaceMutationRequest(
            expectedRevision: gappedExpectedRevision
        )
        let gappedEnvelope = try MutationEnvelopeV1(
            request: gappedRequest,
            identity: try WorkspaceReplicaIdentityV1(
                workspaceID: workspaceID,
                replicaID: gappedReplica
            )
        )
        let gappedResultingRevision = try MutationPortableExpectedRevisionV1(
            WorkspaceExpectedRevisionV1(
                workspaceID: workspaceID,
                generationID: gappedExpectedRevision.generationID,
                writerInstanceID: gappedReplica.rawValue,
                workspaceRevision: mixedHistory.workspaceRevision + 2,
                entityRevisions: [
                    WorkspaceEntityRevisionV1(
                        identity: try gappedMutation.affectedIdentity,
                        revision: gappedEntry.revision
                    )
                ]
            )
        )
        let gappedReceipt = try MutationReceiptV1(
            identity: MutationReceiptIdentityV1(
                workspaceID: workspaceID,
                replicaID: gappedReplica,
                localSequence: 1
            ),
            envelope: gappedEnvelope,
            resultingRevision: gappedResultingRevision,
            postImages: try gappedMutation.mutationPostImages,
            committedAt: C55PartsStockTestSupport.fixedDate
        )
        let gappedRecord = MutationHistoryReceiptRecordV1(
            envelopeData: try gappedEnvelope.canonicalData(),
            receiptData: try gappedReceipt.canonicalData(),
            reversalBasisData: nil,
            semanticReversalData: nil
        )
        let gappedRecordObject = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(gappedRecord)
            ) as? [String: Any]
        )
        let gappedReplicaRecords = try reencodedRecords(sourceRecords) { object in
            var history = try XCTUnwrap(object["mutationHistory"] as? [String: Any])
            var receipts = try XCTUnwrap(history["receipts"] as? [[String: Any]])
            receipts.append(gappedRecordObject)
            history["receipts"] = receipts
            history["workspaceRevision"] = mixedHistory.workspaceRevision + 2
            var revisions = try XCTUnwrap(
                history["entityRevisions"] as? [[String: Any]]
            )
            revisions.append(
                try XCTUnwrap(
                    JSONSerialization.jsonObject(
                        with: JSONEncoder().encode(
                            MutationHistoryEntityRevisionV1(
                                identity: try gappedMutation.affectedIdentity,
                                revision: gappedEntry.revision
                            )
                        )
                    ) as? [String: Any]
                )
            )
            history["entityRevisions"] = revisions
            object["mutationHistory"] = history
        }
        XCTAssertThrowsError(
            try C55PartsStockBackupImportBoundaryV1.validate(
                gappedReplicaRecords,
                workspaceID: workspaceID
            )
        )

        let replacementIdentity = try mixedIdentity(
            .replaceExisting,
            targetWorkspaceID: workspaceID,
            targetGenerationID: C55PartsStockTestSupport.id(1295),
            targetReplicaID: C55PartsStockTestSupport.id(1296)
        )
        let replacement = try restoreService.c55RecordsForMaterializationForTesting(
            sourceRecords,
            members: mixedMembers,
            identityDecision: replacementIdentity,
            legacyWorkspaceID: workspaceID.rawValue,
            partsStockOperationID: C55PartsStockTestSupport.id(1297)
        )
        try C55PartsStockBackupImportBoundaryV1.validate(
            replacement,
            workspaceID: workspaceID
        )
        XCTAssertEqual(replacement, sourceRecords)
        XCTAssertEqual(replacement.partsStockSnapshot, mixedSnapshot)
        XCTAssertEqual(replacement.workResources, sourceRecords.workResources)
        XCTAssertEqual(replacement.mutationHistory, sourceRecords.mutationHistory)
    }

    @MainActor
    func testV23P03C55R01UnknownAbandonmentFrozenHistoryAndLifecycleRecovery() async throws {
        let fixture = try Self.fixture()
        for value in ["REPLAY_APPEND_ONLY_MOVEMENTS", "BACKUP_CANONICAL_ROUND_TRIP", "RETURN_FRONTIER_CHAIN", "STREAM_CONTINUITY_PRE_POST", "SNAPSHOT_RECEIPT_COMPLETENESS", "DECODED_ARCHIVE_IMMUTABILITY", "ABANDON_UNKNOWN_AUDIT", "ABANDONMENT_EXACT_UNKNOWN_FRONTIER", "RETIREMENT_COMPLETE_ZERO_COVERAGE", "RETIREMENT_REPLAY_LOCATION_REVISION_ORDER", "CLONE_DEFINITIONS_ONLY", "CLONE_FORK_STOCK_HISTORY_QUARANTINE", "FORK_REQUIRES_RECOUNT", "ERASE_DELEGATED"] {
            XCTAssertTrue(fixture.recoveryCases.contains(value), "fixture missing \(value)")
        }
        XCTAssertTrue(fixture.claims.abandonmentPreservesUnknown)
        XCTAssertTrue(fixture.claims.cloneCopiesDefinitionsOnly)
        XCTAssertTrue(fixture.claims.forkRequiresRecount)
        XCTAssertTrue(fixture.claims.retryIsIdempotent)
        XCTAssertTrue(fixture.claims.featureDisablePreservesReadExportRecovery)

        let workspaceID = C55PartsStockTestSupport.workspace()
        let unit = try C55PartsStockTestSupport.unit(fixture.golden.canonicalUnit)
        let part = try C55PartsStockTestSupport.part(fixture.golden, workspaceID: workspaceID, slot: 400)
        let abandonmentPart = try C55PartsStockTestSupport.part(fixture.golden, workspaceID: workspaceID, slot: 405)
        let abandonmentMutationID = try C55PartsStockTestSupport.mutation(404)
        let archivedPart = try LocalPartDefinitionV1(
            partID: abandonmentPart.partID, workspaceID: workspaceID, displayName: abandonmentPart.displayName,
            canonicalUnit: abandonmentPart.canonicalUnit, productIdentities: abandonmentPart.productIdentities,
            preferredMinimum: abandonmentPart.preferredMinimum, archived: true, revision: 2,
            mutationID: abandonmentMutationID
        )
        let retiredPart = try LocalPartDefinitionV1(
            partID: part.partID, workspaceID: workspaceID, displayName: part.displayName,
            canonicalUnit: part.canonicalUnit, productIdentities: part.productIdentities,
            preferredMinimum: part.preferredMinimum, archived: true, revision: 2,
            mutationID: try C55PartsStockTestSupport.mutation(406)
        )
        let location = try C55PartsStockTestSupport.location(fixture.golden, workspaceID: workspaceID, slot: 401)
        let reversalLocation = try C55PartsStockTestSupport.location(fixture.golden, workspaceID: workspaceID, slot: 460)
        let unknown = try C55PartsStockTestSupport.projection(
            workspaceID: workspaceID, partID: abandonmentPart.partID, locationID: location.locationID,
            unit: unit, balance: .unknown, locationRevision: 0, lastMovementID: nil
        )
        let useQuantity = try C55PartsStockTestSupport.stock(fixture.golden.use, unit: unit)
        let opening = try C55PartsStockTestSupport.stock(fixture.golden.opening, unit: unit)
        let openingMovement = try C55PartsStockTestSupport.movement(
            movementID: C55PartsStockTestSupport.id(407), workspaceID: workspaceID,
            part: try part.frozenReference(), locationID: location.locationID, kind: .openingCount,
            quantity: opening, unit: unit, preBalance: .unknown, postBalance: opening,
            actor: try C55PartsStockTestSupport.actor(workspaceID: workspaceID, slot: 408),
            expectedLocationRevision: 0, mutationSlot: 409
        )
        let sourceUse = try C55PartsStockTestSupport.useReceipt(
            workspaceID: workspaceID,
            part: part,
            location: location,
            quantity: useQuantity,
            preBalance: opening,
            postBalance: try StockQuantityV1(mantissa: fixture.golden.opening.mantissa - useQuantity.mantissa, scale: 0, unit: unit),
            expectedLocationRevision: openingMovement.locationRevision,
            slot: 410
        )
        let reversalOpening = try C55PartsStockTestSupport.movement(
            movementID: C55PartsStockTestSupport.id(416), workspaceID: workspaceID,
            part: try part.frozenReference(), locationID: reversalLocation.locationID, kind: .openingCount,
            quantity: try StockQuantityV1(mantissa: 1, scale: 0, unit: unit), unit: unit,
            preBalance: .unknown, postBalance: try StockQuantityV1(mantissa: 1, scale: 0, unit: unit),
            actor: try C55PartsStockTestSupport.actor(workspaceID: workspaceID, slot: 417),
            expectedLocationRevision: 0, mutationSlot: 418
        )
        let reversal = try C55PartsStockTestSupport.reversalReceipt(
            sourceUse: sourceUse,
            destination: reversalLocation,
            destinationPreBalance: try StockQuantityV1(mantissa: 1, scale: 0, unit: unit),
            reason: "C55 recovery reversal",
            expectedLocationRevision: reversalOpening.locationRevision,
            slot: 420
        )
        let returnQuantity = try C55PartsStockTestSupport.stock(fixture.golden.return, unit: unit)
        let returnSuccessor = try C55PartsStockTestSupport.workSuccessor(
            of: sourceUse.workResourceSuccessor,
            part: sourceUse.movement.part,
            quantity: returnQuantity,
            lineID: sourceUse.frozenMaterialLineID,
            mutationID: try C55PartsStockTestSupport.mutation(432),
            slot: 550
        )
        let firstReturn = try C55PartsStockTestSupport.returnReceipt(
            sourceUse: sourceUse,
            destination: location,
            destinationPreBalance: sourceUse.movement.postBalance,
            quantity: returnQuantity,
            predecessorFrontier: nil,
            workResourcePredecessor: sourceUse.workResourceSuccessor,
            workResourceSuccessor: returnSuccessor,
            expectedLocationRevision: sourceUse.movement.locationRevision,
            movementSlot: 430,
            receiptSlot: 434
        )
        try firstReturn.validate()
        let finalReturnSuccessor = try C55PartsStockTestSupport.workSuccessor(
            of: returnSuccessor,
            part: sourceUse.movement.part,
            quantity: nil,
            lineID: sourceUse.frozenMaterialLineID,
            mutationID: try C55PartsStockTestSupport.mutation(437),
            disposition: .reversed,
            slot: 552
        )
        let finalReturn = try C55PartsStockTestSupport.returnReceipt(
            sourceUse: sourceUse,
            destination: location,
            destinationPreBalance: firstReturn.returnMovement.postBalance,
            quantity: returnQuantity,
            predecessorFrontier: try firstReturn.frontierSnapshot(),
            workResourcePredecessor: returnSuccessor,
            workResourceSuccessor: finalReturnSuccessor,
            expectedLocationRevision: firstReturn.returnMovement.locationRevision,
            movementSlot: 435,
            receiptSlot: 439
        )
        try finalReturn.validate()
        XCTAssertEqual(finalReturn.resultingReturnedMantissa, 2)
        let firstFrontier = try firstReturn.frontierSnapshot()
        let staleFrontier = try StockReturnFrontierSnapshotV1(
            returnReceiptID: firstReturn.receiptID,
            returnReceiptSHA256: C55PartsStockTestSupport.digest("s"),
            sourceUseReceiptID: sourceUse.receiptID,
            resultingReturnedMantissa: firstReturn.resultingReturnedMantissa,
            workResourceSuccessor: returnSuccessor
        )
        let staleReturnSuccessor = try C55PartsStockTestSupport.workSuccessor(
            of: returnSuccessor,
            part: sourceUse.movement.part,
            quantity: nil,
            lineID: sourceUse.frozenMaterialLineID,
            mutationID: try C55PartsStockTestSupport.mutation(442),
            disposition: .reversed,
            slot: 553
        )
        let staleReturn = try C55PartsStockTestSupport.returnReceipt(
            sourceUse: sourceUse,
            destination: location,
            destinationPreBalance: firstReturn.returnMovement.postBalance,
            quantity: returnQuantity,
            predecessorFrontier: staleFrontier,
            workResourcePredecessor: returnSuccessor,
            workResourceSuccessor: staleReturnSuccessor,
            expectedLocationRevision: firstReturn.returnMovement.locationRevision,
            movementSlot: 440,
            receiptSlot: 444
        )
        XCTAssertNoThrow(try staleReturn.validate())
        XCTAssertThrowsError(
            try PartsStockBackupSnapshotV1(
                workspaceID: workspaceID,
                parts: [part, archivedPart], locations: [location, reversalLocation],
                movements: [openingMovement, sourceUse.movement, firstReturn.returnMovement, staleReturn.returnMovement],
                uses: [sourceUse], reversals: [], returns: [firstReturn, staleReturn], abandonments: []
            )
        )
        let forkedPredecessor = try C55PartsStockTestSupport.workSuccessor(
            of: sourceUse.workResourceSuccessor,
            part: sourceUse.movement.part,
            quantity: returnQuantity,
            lineID: sourceUse.frozenMaterialLineID,
            mutationID: try C55PartsStockTestSupport.mutation(446),
            slot: 555
        )
        let forkedSuccessor = try C55PartsStockTestSupport.workSuccessor(
            of: forkedPredecessor,
            part: sourceUse.movement.part,
            quantity: nil,
            lineID: sourceUse.frozenMaterialLineID,
            mutationID: try C55PartsStockTestSupport.mutation(447),
            disposition: .reversed,
            slot: 556
        )
        XCTAssertThrowsError(
            try C55PartsStockTestSupport.returnReceipt(
                sourceUse: sourceUse,
                destination: location,
                destinationPreBalance: firstReturn.returnMovement.postBalance,
                quantity: returnQuantity,
                predecessorFrontier: firstFrontier,
                workResourcePredecessor: forkedPredecessor,
                workResourceSuccessor: forkedSuccessor,
                expectedLocationRevision: firstReturn.returnMovement.locationRevision,
                movementSlot: 445,
                receiptSlot: 449
            )
        )
        let nonLatestSuccessor = try C55PartsStockTestSupport.workSuccessor(
            of: returnSuccessor,
            part: sourceUse.movement.part,
            quantity: nil,
            lineID: sourceUse.frozenMaterialLineID,
            mutationID: try C55PartsStockTestSupport.mutation(452),
            disposition: .reversed,
            slot: 560
        )
        let nonLatestReturn = try C55PartsStockTestSupport.returnReceipt(
            sourceUse: sourceUse,
            destination: location,
            destinationPreBalance: firstReturn.returnMovement.postBalance,
            quantity: returnQuantity,
            predecessorFrontier: firstFrontier,
            workResourcePredecessor: returnSuccessor,
            workResourceSuccessor: nonLatestSuccessor,
            expectedLocationRevision: firstReturn.returnMovement.locationRevision,
            movementSlot: 450,
            receiptSlot: 454
        )
        XCTAssertNoThrow(try nonLatestReturn.validate())
        XCTAssertThrowsError(
            try PartsStockBackupSnapshotV1(
                workspaceID: workspaceID,
                parts: [part, archivedPart], locations: [location, reversalLocation],
                movements: [openingMovement, sourceUse.movement, firstReturn.returnMovement, finalReturn.returnMovement, nonLatestReturn.returnMovement],
                uses: [sourceUse], reversals: [], returns: [firstReturn, finalReturn, nonLatestReturn], abandonments: []
            )
        )
        XCTAssertEqual(try StockUseReceiptRowV1(sourceUse).value(), sourceUse)
        XCTAssertEqual(try StockUseReversalReceiptRowV1(reversal).value(), reversal)
        XCTAssertEqual(try StockReturnReceiptRowV1(firstReturn).value(), firstReturn)
        XCTAssertEqual(try StockReturnReceiptRowV1(finalReturn).value(), finalReturn)
        let disposition = try AbandonUnverifiedStockDispositionV1(
            dispositionID: C55PartsStockTestSupport.id(402), workspaceID: workspaceID,
            partID: abandonmentPart.partID, locationID: location.locationID,
            actor: try C55PartsStockTestSupport.actor(workspaceID: workspaceID, slot: 403),
            reason: "Physical quantity was not verifiable at close",
            lastMovementID: unknown.lastMovementID,
            lastLocationRevision: unknown.locationRevision,
            recordedAt: C55PartsStockTestSupport.date(),
            mutationID: abandonmentMutationID,
            currentBalance: unknown.balance
        )
        try disposition.validate()
        XCTAssertTrue(disposition.quantityRemainsUnknown)
        let unknownReversal = try C55PartsStockTestSupport.projection(
            workspaceID: workspaceID, partID: abandonmentPart.partID, locationID: reversalLocation.locationID,
            unit: unit, balance: .unknown, locationRevision: 0, lastMovementID: nil
        )
        let secondDisposition = try AbandonUnverifiedStockDispositionV1(
            dispositionID: C55PartsStockTestSupport.id(462), workspaceID: workspaceID,
            partID: abandonmentPart.partID, locationID: reversalLocation.locationID,
            actor: try C55PartsStockTestSupport.actor(workspaceID: workspaceID, slot: 463),
            reason: "Second location was not verifiable at close",
            lastMovementID: unknownReversal.lastMovementID,
            lastLocationRevision: unknownReversal.locationRevision,
            recordedAt: C55PartsStockTestSupport.date(),
            mutationID: abandonmentMutationID,
            currentBalance: unknownReversal.balance
        )
        try secondDisposition.validate()
        let abandonment = try StockAbandonmentReceiptV1(
            dispositions: [disposition, secondDisposition], archivedPartSuccessor: archivedPart, predecessor: abandonmentPart
        )
        try abandonment.validate()
        XCTAssertEqual(abandonment.dispositions, [disposition, secondDisposition])
        XCTAssertTrue(abandonment.archivedPartSuccessor.archived)
        XCTAssertEqual(
            Set(abandonment.dispositions.map(\.locationID)),
            Set([location.locationID, reversalLocation.locationID])
        )
        XCTAssertTrue(abandonment.dispositions.allSatisfy {
            $0.quantityRemainsUnknown
                && $0.currentBalance == .unknown
                && $0.lastMovementID == nil
                && $0.lastLocationRevision == 0
        })
        let mismatchedAbandonmentFrontier = try AbandonUnverifiedStockDispositionV1(
            dispositionID: C55PartsStockTestSupport.id(464),
            workspaceID: workspaceID,
            partID: abandonmentPart.partID,
            locationID: location.locationID,
            actor: try C55PartsStockTestSupport.actor(workspaceID: workspaceID, slot: 465),
            reason: "Stale unknown frontier",
            lastMovementID: nil,
            lastLocationRevision: 1,
            recordedAt: C55PartsStockTestSupport.date(),
            mutationID: abandonmentMutationID,
            currentBalance: .unknown
        )
        XCTAssertThrowsError(
            try PartsStockBackupSnapshotV1(
                workspaceID: workspaceID,
                parts: [part, archivedPart],
                locations: [location, reversalLocation],
                movements: [openingMovement, sourceUse.movement],
                uses: [sourceUse], reversals: [], returns: [],
                abandonments: [mismatchedAbandonmentFrontier, secondDisposition]
            )
        )
        let zeroBalance = try C55PartsStockTestSupport.projection(
            workspaceID: workspaceID, partID: part.partID, locationID: location.locationID,
            unit: unit, balance: .known(try StockQuantityV1(mantissa: 0, scale: 0, unit: unit)),
            locationRevision: 0, lastMovementID: nil
        )
        let secondZeroBalance = try C55PartsStockTestSupport.projection(
            workspaceID: workspaceID, partID: part.partID, locationID: reversalLocation.locationID,
            unit: unit, balance: .known(try StockQuantityV1(mantissa: 0, scale: 0, unit: unit)),
            locationRevision: 0, lastMovementID: nil
        )
        let retirement = try StockPartRetirementReceiptV1(
            archivedPartSuccessor: retiredPart,
            predecessor: part,
            verifiedBalances: [zeroBalance, secondZeroBalance]
        )
        try retirement.validate()
        XCTAssertEqual(
            Set(retirement.verifiedBalances.map(\.locationID)),
            Set([location.locationID, reversalLocation.locationID])
        )
        XCTAssertTrue(retirement.verifiedBalances.allSatisfy {
            guard case let .known(value) = $0.balance else { return false }
            return value.mantissa == 0
        })
        let zeroRetirementPart = try C55PartsStockTestSupport.part(
            fixture.golden,
            workspaceID: workspaceID,
            slot: 470
        )
        let zeroRetirementSuccessor = try LocalPartDefinitionV1(
            partID: zeroRetirementPart.partID,
            workspaceID: workspaceID,
            displayName: zeroRetirementPart.displayName,
            canonicalUnit: zeroRetirementPart.canonicalUnit,
            productIdentities: zeroRetirementPart.productIdentities,
            preferredMinimum: zeroRetirementPart.preferredMinimum,
            archived: true,
            revision: zeroRetirementPart.revision + 1,
            mutationID: try C55PartsStockTestSupport.mutation(472)
        )
        let zeroQuantity = try StockQuantityV1(mantissa: 0, scale: 0, unit: unit)
        let zeroOpeningSource = try C55PartsStockTestSupport.movement(
            movementID: C55PartsStockTestSupport.id(473),
            workspaceID: workspaceID,
            part: try zeroRetirementPart.frozenReference(),
            locationID: location.locationID,
            kind: .physicalCount,
            quantity: zeroQuantity,
            unit: unit,
            preBalance: .unknown,
            postBalance: zeroQuantity,
            actor: try C55PartsStockTestSupport.actor(workspaceID: workspaceID, slot: 474),
            expectedLocationRevision: 0,
            mutationSlot: 475
        )
        let zeroOpeningDestination = try C55PartsStockTestSupport.movement(
            movementID: C55PartsStockTestSupport.id(476),
            workspaceID: workspaceID,
            part: try zeroRetirementPart.frozenReference(),
            locationID: reversalLocation.locationID,
            kind: .physicalCount,
            quantity: zeroQuantity,
            unit: unit,
            preBalance: .unknown,
            postBalance: zeroQuantity,
            actor: try C55PartsStockTestSupport.actor(workspaceID: workspaceID, slot: 477),
            expectedLocationRevision: 0,
            mutationSlot: 478
        )
        let zeroRetirementSnapshot = try PartsStockBackupSnapshotV1(
            workspaceID: workspaceID,
            parts: [zeroRetirementSuccessor],
            locations: [location, reversalLocation],
            movements: [zeroOpeningSource, zeroOpeningDestination],
            uses: [],
            reversals: [],
            returns: [],
            abandonments: []
        )
        try zeroRetirementSnapshot.validate()
        let zeroRetirement = try StockPartRetirementReceiptV1(
            archivedPartSuccessor: zeroRetirementSuccessor,
            predecessor: zeroRetirementPart,
            verifiedBalances: [
                try C55PartsStockTestSupport.projection(
                    workspaceID: workspaceID,
                    partID: zeroRetirementPart.partID,
                    locationID: location.locationID,
                    unit: unit,
                    balance: .known(zeroQuantity),
                    locationRevision: zeroOpeningSource.locationRevision,
                    lastMovementID: zeroOpeningSource.movementID
                ),
                try C55PartsStockTestSupport.projection(
                    workspaceID: workspaceID,
                    partID: zeroRetirementPart.partID,
                    locationID: reversalLocation.locationID,
                    unit: unit,
                    balance: .known(zeroQuantity),
                    locationRevision: zeroOpeningDestination.locationRevision,
                    lastMovementID: zeroOpeningDestination.movementID
                )
            ]
        )
        try zeroRetirement.validate()
        XCTAssertEqual(
            try PartsStockCanonicalCodecV1.decode(
                StockPartRetirementReceiptV1.self,
                from: PartsStockCanonicalCodecV1.encode(retirement)
            ),
            retirement
        )
        var retirementJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: PartsStockCanonicalCodecV1.encode(retirement)
            ) as? [String: Any]
        )
        var retirementSuccessorJSON = try XCTUnwrap(
            retirementJSON["archivedPartSuccessor"] as? [String: Any]
        )
        retirementSuccessorJSON["displayName"] = "Decoded retirement catalog mutation"
        retirementJSON["archivedPartSuccessor"] = retirementSuccessorJSON
        let tamperedRetirement = try JSONSerialization.data(
            withJSONObject: retirementJSON, options: [.sortedKeys]
        )
        XCTAssertThrowsError(
            try PartsStockCanonicalCodecV1.decode(
                StockPartRetirementReceiptV1.self, from: tamperedRetirement
            )
        )
        XCTAssertEqual(
            try PartsStockCanonicalCodecV1.decode(
                StockAbandonmentReceiptV1.self,
                from: PartsStockCanonicalCodecV1.encode(abandonment)
            ),
            abandonment
        )
        var abandonmentJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: PartsStockCanonicalCodecV1.encode(abandonment)
            ) as? [String: Any]
        )
        var abandonmentSuccessorJSON = try XCTUnwrap(
            abandonmentJSON["archivedPartSuccessor"] as? [String: Any]
        )
        abandonmentSuccessorJSON["canonicalUnit"] = StockUnitV1.meter.rawValue
        abandonmentJSON["archivedPartSuccessor"] = abandonmentSuccessorJSON
        let tamperedAbandonment = try JSONSerialization.data(
            withJSONObject: abandonmentJSON, options: [.sortedKeys]
        )
        XCTAssertThrowsError(
            try PartsStockCanonicalCodecV1.decode(
                StockAbandonmentReceiptV1.self, from: tamperedAbandonment
            )
        )
        let abandonmentWriter = C55InMemoryWriter()
        let abandonmentCommit = try abandonmentWriter.commitPartsStock(.abandon(abandonment))
        XCTAssertEqual(abandonmentCommit.mutationID, abandonment.archivedPartSuccessor.mutationID)
        XCTAssertEqual(
            try abandonmentWriter.commitPartsStock(.abandon(abandonment)),
            abandonmentCommit
        )
        XCTAssertThrowsError(
            try AbandonUnverifiedStockDispositionV1(
                dispositionID: C55PartsStockTestSupport.id(405), workspaceID: workspaceID,
                partID: part.partID, locationID: location.locationID,
                actor: try C55PartsStockTestSupport.actor(workspaceID: workspaceID, slot: 406),
                reason: "Cannot abandon a known balance",
                lastMovementID: nil, lastLocationRevision: 1,
                recordedAt: C55PartsStockTestSupport.date(),
                mutationID: try C55PartsStockTestSupport.mutation(407),
                currentBalance: .known(try C55PartsStockTestSupport.stock(fixture.golden.opening, unit: unit))
            )
        )

        let frozen = try part.frozenReference()
        let renamed = try LocalPartDefinitionV1(
            partID: part.partID, workspaceID: workspaceID, displayName: "M8 bolt renamed",
            canonicalUnit: part.canonicalUnit, productIdentities: part.productIdentities,
            preferredMinimum: part.preferredMinimum, revision: 2, mutationID: try C55PartsStockTestSupport.mutation(408)
        )
        XCTAssertNotEqual(renamed.displayName, frozen.displayName)
        XCTAssertEqual(frozen.partID, renamed.partID)
        XCTAssertEqual(frozen.partSHA256, part.partSHA256)

        for value in ["DUPLICATE_RETURN_RECEIPT", "REORDER_RETURN_CHAIN"] {
            XCTAssertTrue(fixture.hostileCases.contains(value), "fixture missing \(value)")
        }
        XCTAssertThrowsError(
            try PartsStockBackupSnapshotV1(
                workspaceID: workspaceID,
                parts: [part, archivedPart], locations: [location, reversalLocation],
                movements: [openingMovement, sourceUse.movement, firstReturn.returnMovement],
                uses: [sourceUse], reversals: [], returns: [firstReturn, firstReturn], abandonments: [disposition, secondDisposition]
            )
        )
        XCTAssertThrowsError(
            try PartsStockBackupSnapshotV1(
                workspaceID: workspaceID,
                parts: [part, archivedPart],
                locations: [location, reversalLocation],
                movements: [
                    openingMovement, sourceUse.movement, reversalOpening,
                    reversal.reversalMovement, firstReturn.returnMovement,
                    finalReturn.returnMovement
                ],
                uses: [sourceUse],
                reversals: [reversal],
                returns: [firstReturn, finalReturn],
                abandonments: [disposition]
            )
        )
        let backup = try PartsStockBackupSnapshotV1(
            workspaceID: workspaceID,
            parts: [part, archivedPart],
            locations: [location, reversalLocation],
            movements: [openingMovement, sourceUse.movement, firstReturn.returnMovement, finalReturn.returnMovement],
            uses: [sourceUse],
            reversals: [],
            returns: [firstReturn, finalReturn],
            abandonments: [disposition, secondDisposition]
        )
        try backup.validate()
        let backupRetry = try PartsStockBackupSnapshotV1(
            workspaceID: workspaceID,
            parts: [part, archivedPart],
            locations: [reversalLocation, location],
            movements: [finalReturn.returnMovement, sourceUse.movement, openingMovement, firstReturn.returnMovement],
            uses: [sourceUse],
            reversals: [],
            returns: [finalReturn, firstReturn],
            abandonments: [secondDisposition, disposition]
        )
        XCTAssertEqual(backupRetry, backup)
        XCTAssertEqual(try PartsStockCanonicalCodecV1.decode(PartsStockBackupSnapshotV1.self, from: PartsStockCanonicalCodecV1.encode(backup)), backup)
        let retirementReplayPart = try C55PartsStockTestSupport.part(
            fixture.golden,
            workspaceID: workspaceID,
            slot: 620
        )
        let retirementReplaySuccessor = try LocalPartDefinitionV1(
            partID: retirementReplayPart.partID,
            workspaceID: workspaceID,
            displayName: retirementReplayPart.displayName,
            canonicalUnit: retirementReplayPart.canonicalUnit,
            productIdentities: retirementReplayPart.productIdentities,
            preferredMinimum: retirementReplayPart.preferredMinimum,
            archived: true,
            revision: retirementReplayPart.revision + 1,
            mutationID: try C55PartsStockTestSupport.mutation(622)
        )
        let retirementReplayLocation = try C55PartsStockTestSupport.location(
            fixture.golden,
            workspaceID: workspaceID,
            slot: 623
        )
        let retirementReplayZero = try StockQuantityV1(
            mantissa: 0,
            scale: 0,
            unit: unit
        )
        let retirementReplayOpening = try C55PartsStockTestSupport.movement(
            movementID: C55PartsStockTestSupport.id(624),
            workspaceID: workspaceID,
            part: try retirementReplayPart.frozenReference(),
            locationID: retirementReplayLocation.locationID,
            kind: .physicalCount,
            quantity: retirementReplayZero,
            unit: unit,
            preBalance: .unknown,
            postBalance: retirementReplayZero,
            actor: try C55PartsStockTestSupport.actor(workspaceID: workspaceID, slot: 626),
            expectedLocationRevision: 0,
            mutationSlot: 628,
            occurredOffset: 100
        )
        let retirementReplayCount = try C55PartsStockTestSupport.movement(
            movementID: C55PartsStockTestSupport.id(625),
            workspaceID: workspaceID,
            part: try retirementReplayPart.frozenReference(),
            locationID: retirementReplayLocation.locationID,
            kind: .physicalCount,
            quantity: retirementReplayZero,
            unit: unit,
            preBalance: .known(retirementReplayZero),
            postBalance: retirementReplayZero,
            actor: try C55PartsStockTestSupport.actor(workspaceID: workspaceID, slot: 627),
            expectedLocationRevision: retirementReplayOpening.locationRevision,
            mutationSlot: 629,
            occurredOffset: -100
        )
        XCTAssertLessThan(
            retirementReplayCount.recordedAt,
            retirementReplayOpening.recordedAt
        )
        let retirementReplaySnapshot = try PartsStockBackupSnapshotV1(
            workspaceID: workspaceID,
            parts: [retirementReplaySuccessor],
            locations: [retirementReplayLocation],
            movements: [retirementReplayOpening, retirementReplayCount],
            uses: [],
            reversals: [],
            returns: [],
            abandonments: []
        )
        try retirementReplaySnapshot.validate()
        XCTAssertEqual(
            retirementReplaySnapshot.movements.first?.movementID,
            retirementReplayCount.movementID
        )
        let retirementReplay = try StockPartRetirementReceiptV1(
            archivedPartSuccessor: retirementReplaySuccessor,
            predecessor: retirementReplayPart,
            verifiedBalances: [
                try C55PartsStockTestSupport.projection(
                    workspaceID: workspaceID,
                    partID: retirementReplayPart.partID,
                    locationID: retirementReplayLocation.locationID,
                    unit: unit,
                    balance: .known(retirementReplayZero),
                    locationRevision: retirementReplayCount.locationRevision,
                    lastMovementID: retirementReplayCount.movementID
                )
            ]
        )
        try retirementReplay.validate()

        let schema = Schema([
            LocalPartDefinitionRowV1.self,
            StockStorageLocationRowV1.self,
            StockMovementEventRowV1.self,
            StockUseReceiptRowV1.self,
            StockUseReversalReceiptRowV1.self,
            StockReturnReceiptRowV1.self,
            AbandonUnverifiedStockRowV1.self
        ])
        let container = try ModelContainer(
            for: schema,
            migrationPlan: nil,
            configurations: [ModelConfiguration(
                "C55-R01", schema: schema, isStoredInMemoryOnly: true,
                allowsSave: true, cloudKitDatabase: .none
            )]
        )
        let context = container.mainContext
        context.autosaveEnabled = false
        context.insert(try LocalPartDefinitionRowV1(part))
        context.insert(try LocalPartDefinitionRowV1(archivedPart))
        context.insert(try LocalPartDefinitionRowV1(retirementReplaySuccessor))
        context.insert(try StockStorageLocationRowV1(location))
        context.insert(try StockStorageLocationRowV1(reversalLocation))
        context.insert(try StockStorageLocationRowV1(retirementReplayLocation))
        context.insert(try StockMovementEventRowV1(openingMovement))
        context.insert(try StockMovementEventRowV1(sourceUse.movement))
        context.insert(try StockMovementEventRowV1(reversalOpening))
        context.insert(try StockMovementEventRowV1(reversal.reversalMovement))
        context.insert(try StockMovementEventRowV1(firstReturn.returnMovement))
        context.insert(try StockMovementEventRowV1(finalReturn.returnMovement))
        context.insert(try StockMovementEventRowV1(retirementReplayOpening))
        context.insert(try StockMovementEventRowV1(retirementReplayCount))
        context.insert(try StockUseReceiptRowV1(sourceUse))
        context.insert(try StockUseReversalReceiptRowV1(reversal))
        context.insert(try StockReturnReceiptRowV1(firstReturn))
        context.insert(try StockReturnReceiptRowV1(finalReturn))
        context.insert(try AbandonUnverifiedStockRowV1(disposition))
        context.insert(try AbandonUnverifiedStockRowV1(secondDisposition))
        try context.save()
        let adapter = PartsStockLifecycleAdapterV1(modelContext: context)
        let replayed = try adapter.replay(workspaceID: workspaceID)
        XCTAssertEqual(replayed.count, 3)
        let sourceProjection = try XCTUnwrap(
            replayed.first { $0.partID == part.partID && $0.locationID == location.locationID }
        )
        XCTAssertEqual(sourceProjection.locationRevision, finalReturn.returnMovement.locationRevision)
        XCTAssertEqual(sourceProjection.lastMovementID, finalReturn.returnMovement.movementID)
        let reversalProjection = try XCTUnwrap(
            replayed.first { $0.partID == part.partID && $0.locationID == reversalLocation.locationID }
        )
        XCTAssertEqual(reversalProjection.locationRevision, reversal.reversalMovement.locationRevision)
        XCTAssertEqual(reversalProjection.lastMovementID, reversal.reversalMovement.movementID)
        let retirementReplayProjection = try XCTUnwrap(
            replayed.first {
                $0.partID == retirementReplayPart.partID
                    && $0.locationID == retirementReplayLocation.locationID
            }
        )
        XCTAssertEqual(
            retirementReplayProjection.locationRevision,
            retirementReplayCount.locationRevision
        )
        XCTAssertEqual(
            retirementReplayProjection.lastMovementID,
            retirementReplayCount.movementID
        )
        XCTAssertEqual(retirementReplayProjection.balance, .known(retirementReplayZero))
        let definitionsOnlySource = try PartsStockBackupSnapshotV1(
            workspaceID: workspaceID,
            parts: [part],
            locations: [location],
            movements: [],
            uses: [],
            reversals: [],
            returns: [],
            abandonments: []
        )
        let cloneWorkspaceID = C55PartsStockTestSupport.workspace(2)
        let cloned = try adapter.preparedRestoreSnapshot(
            definitionsOnlySource,
            targetWorkspaceID: cloneWorkspaceID,
            operationID: C55PartsStockTestSupport.id(610),
            disposition: .cloneDefinitions
        )
        XCTAssertEqual(cloned.workspaceID, cloneWorkspaceID)
        XCTAssertEqual(cloned.parts.count, 1)
        XCTAssertEqual(cloned.locations.count, 1)
        XCTAssertTrue(cloned.movements.isEmpty)
        XCTAssertTrue(cloned.uses.isEmpty)
        XCTAssertEqual(cloned.parts.first?.workspaceID, cloneWorkspaceID)
        let forked = try adapter.preparedRestoreSnapshot(
            definitionsOnlySource,
            targetWorkspaceID: cloneWorkspaceID,
            operationID: C55PartsStockTestSupport.id(611),
            disposition: .forkRequiresRecount
        )
        XCTAssertEqual(forked.workspaceID, cloneWorkspaceID)
        XCTAssertTrue(forked.movements.isEmpty)
        XCTAssertTrue(forked.uses.isEmpty)
        let historySource = try PartsStockBackupSnapshotV1(
            workspaceID: workspaceID,
            parts: [part],
            locations: [location, reversalLocation],
            movements: [
                openingMovement,
                sourceUse.movement,
                firstReturn.returnMovement,
                finalReturn.returnMovement
            ],
            uses: [sourceUse],
            reversals: [],
            returns: [firstReturn, finalReturn],
            abandonments: []
        )
        try historySource.validate()
        XCTAssertFalse(historySource.movements.isEmpty)
        XCTAssertFalse(historySource.uses.isEmpty)
        XCTAssertFalse(historySource.returns.isEmpty)
        let historyClone = try adapter.preparedRestoreSnapshot(
            historySource,
            targetWorkspaceID: cloneWorkspaceID,
            operationID: C55PartsStockTestSupport.id(613),
            disposition: .cloneDefinitions
        )
        XCTAssertEqual(historyClone.parts.count, 1)
        XCTAssertEqual(historyClone.locations.count, 2)
        XCTAssertTrue(historyClone.movements.isEmpty)
        XCTAssertTrue(historyClone.uses.isEmpty)
        XCTAssertTrue(historyClone.reversals.isEmpty)
        XCTAssertTrue(historyClone.returns.isEmpty)
        XCTAssertTrue(historyClone.abandonments.isEmpty)
        let historyFork = try adapter.preparedRestoreSnapshot(
            historySource,
            targetWorkspaceID: cloneWorkspaceID,
            operationID: C55PartsStockTestSupport.id(614),
            disposition: .forkRequiresRecount
        )
        XCTAssertEqual(historyFork.parts.count, 1)
        XCTAssertEqual(historyFork.locations.count, 2)
        XCTAssertTrue(historyFork.movements.isEmpty)
        XCTAssertTrue(historyFork.uses.isEmpty)
        XCTAssertTrue(historyFork.reversals.isEmpty)
        XCTAssertTrue(historyFork.returns.isEmpty)
        XCTAssertTrue(historyFork.abandonments.isEmpty)
        let replacedHistory = try adapter.preparedRestoreSnapshot(
            historySource,
            targetWorkspaceID: workspaceID,
            operationID: C55PartsStockTestSupport.id(615),
            disposition: .replace
        )
        XCTAssertEqual(replacedHistory, historySource)
        XCTAssertThrowsError(
            try adapter.preparedRestoreSnapshot(
                definitionsOnlySource,
                targetWorkspaceID: workspaceID,
                operationID: C55PartsStockTestSupport.id(612),
                disposition: .cloneDefinitions
            )
        )
        do {
            try await adapter.restore(backup, targetWorkspaceID: workspaceID, operationID: C55PartsStockTestSupport.id(409), disposition: .replace)
            XCTFail("restore requires the incumbent lifecycle port")
        } catch {
            XCTAssertEqual(error as? PartsStockFailureV1, .unavailable)
        }
        do {
            try await adapter.erase(workspaceID: workspaceID)
            XCTFail("erase requires the incumbent lifecycle port")
        } catch {
            XCTAssertEqual(error as? PartsStockFailureV1, .unavailable)
        }
        do {
            try await adapter.delete(workspaceID: workspaceID)
            XCTFail("delete requires the incumbent lifecycle port")
        } catch {
            XCTAssertEqual(error as? PartsStockFailureV1, .unavailable)
        }
        XCTAssertTrue(C55PartsStockLifecycleBoundaryV1.journalIsAppendOnly)
        XCTAssertTrue(C55PartsStockLifecycleBoundaryV1.cloneCopiesDefinitionsOnly)
        XCTAssertTrue(C55PartsStockLifecycleBoundaryV1.forkBalancesRequireRecount)
        XCTAssertTrue(C55PartsStockLifecycleBoundaryV1.replacePreservesExactTruth)
        XCTAssertTrue(C55PartsStockLifecycleBoundaryV1.featureDisablePreservesReadExportRecovery)
        XCTAssertFalse(C55PartsStockLifecycleBoundaryV1.hostedOrParallelWriter)
    }

    private static func fixture() throws -> C55PartsStockCorpusFixture {
        try C55PartsStockTestSupport.fixture()
    }
}

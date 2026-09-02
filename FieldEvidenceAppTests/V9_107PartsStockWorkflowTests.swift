import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

private enum C44 {
    static let now = Date(timeIntervalSince1970: 1_788_364_800)
    static func id(_ value: Int) -> UUID { UUID(uuidString: String(format: "C4400000-0000-4000-8000-%012x", value))! }
    static func mutation(_ value: Int) throws -> MutationIDV1 { try .init(rawValue: id(value)) }
}
private struct C44Clock: ApplicationClock { func now() -> Date { C44.now } }
private final class C44IDs: ApplicationIDSource, @unchecked Sendable {
    private let lock = NSLock()
    private var next = 900

    func makeID() -> UUID {
        lock.lock()
        defer { lock.unlock() }
        defer { next += 1 }
        return C44.id(next)
    }
}
private struct C44Files: ApplicationFileAuthorityV1 { func temporaryRelativePath(mutationID: MutationIDV1, component: String) throws -> String { "c44/\(mutationID.rawValue.uuidString)/\(component)" } }

@MainActor private final class C44Harness {
    let workspaceID = WorkspaceID(rawValue: C44.id(1))
    let container: ModelContainer
    let context: ModelContext
    let writer: WorkspaceWriterV1
    let actor: ActorSnapshotV1
    let subject: WorkResourceSubjectV1
    let lifecycle: PartsStockLifecycleAdapterV1

    init(_ name: String, failure: MutationJournalFailureInjectionV1? = nil) throws {
        let schema = Schema(PersistentSchemaV41.models, version: PersistentSchemaV41.versionIdentifier)
        container = try ModelContainer(for: schema, migrationPlan: nil, configurations: [ModelConfiguration(name, schema: schema, isStoredInMemoryOnly: true, allowsSave: true, cloudKitDatabase: .none)])
        context = container.mainContext; context.autosaveEnabled = false
        let reference = try LocalActorReferenceV1(actorReferenceID: C44.id(2), workspaceID: workspaceID, displayName: "C44 recorder")
        actor = try ActorSnapshotV1(snapshotID: C44.id(3), workspaceID: workspaceID, actor: reference, responsibility: .recordedBy, displayNameAtTime: "C44 recorder", capturedAt: C44.now)
        context.insert(try ActorSnapshotRow(actor))
        let item = try WorkPacketItemV1(itemID: "C44-WORK", kind: .inspection, expectedRevision: 1, itemSHA256: String(repeating: "a", count: 64))
        let manifest = try WorkPacketManifestV1(manifestID: C44.id(7), packetID: C44.id(8), packetVersion: 1, workspaceID: workspaceID, items: [item], packageReleases: [], creationBasis: .explicitLocalSelection, creator: actor, createdAt: C44.now, mutationID: C44.mutation(9))
        subject = try WorkResourceSubjectV1(workspaceID: workspaceID, kind: .workPacket, subjectID: manifest.manifestID.uuidString, subjectRevision: manifest.revision, subjectSHA256: manifest.manifestSHA256)
        context.insert(try WorkPacketManifestRow(manifest)); try context.save()
        let identity = try WorkspaceReplicaIdentityV1(workspaceID: workspaceID, replicaID: ReplicaID(rawValue: C44.id(4)))
        let journal = try MutationJournalStoreV1(modelContext: context, identity: identity, generationID: C44.id(5), failureInjection: failure)
        writer = try WorkspaceWriterV1(identity: identity, generationID: C44.id(5), initialRevision: journal.currentRevision(writerInstanceID: C44.id(6)), clock: C44Clock(), idSource: C44IDs(), fileAuthority: C44Files(), adapter: WorkspaceWriterAdapterV1(modelContext: context), journalStore: journal)
        lifecycle = PartsStockLifecycleAdapterV1(modelContext: context)
    }

    func part(_ slot: Int = 10, sku: String = "STOCK:M8-SS", name: String = "M8 stainless bolt") throws -> LocalPartDefinitionV1 {
        let identity = try StockProductIdentityV1(kind: .sku, value: sku)
        let minimum = try StockQuantityV1(mantissa: 4, scale: 0, unit: .each)
        return try .init(partID: C44.id(slot), workspaceID: workspaceID, displayName: name, canonicalUnit: .each, productIdentities: [identity], preferredMinimum: minimum, revision: 1, mutationID: C44.mutation(slot + 1))
    }
    func location(_ slot: Int = 20) throws -> StockStorageLocationV1 { try .init(locationID: C44.id(slot), workspaceID: workspaceID, kind: .shop, label: "Main shop", binLabel: "A1", revision: 1) }
    func workflow(policy: LocalStockFeaturePolicyV1 = .enabled) throws -> PartsStockWorkflowCoordinatorV1 {
        let stock = PartsStockCoordinatorV1(writer: writer, featurePolicy: policy.partsStockPolicy)
        let work = try ManualWorkResourceWorkflowCoordinatorV1(workResources: WorkResourceCoordinatorV1(writer: writer), stock: stock, stockCapability: policy.allowsWrites ? .available : .disabled)
        return PartsStockWorkflowCoordinatorV1(stock: stock, workResources: work, lifecycle: lifecycle, featurePolicy: policy)
    }
    func seed(_ part: LocalPartDefinitionV1, _ location: StockStorageLocationV1, quantity: Int64 = 10, slot: Int = 30) throws -> StockBalanceProjectionV1 {
        _ = try writer.commitPartsStock(.upsertPart(part)); _ = try writer.commitPartsStock(.upsertLocation(location, mutationID: C44.mutation(slot)))
        let q = try StockQuantityV1(mantissa: quantity, scale: 0, unit: .each)
        let movement = try StockMovementEventV1(movementID: C44.id(slot + 1), workspaceID: workspaceID, part: part.frozenReference(), locationID: location.locationID, kind: .openingCount, quantity: q, unit: .each, preBalance: .unknown, postBalance: q, actor: actor, occurredAt: C44.now, recordedAt: C44.now, expectedLocationRevision: 0, mutationID: C44.mutation(slot + 2))
        _ = try writer.commitPartsStock(.appendMovement(movement))
        return try .init(workspaceID: workspaceID, partID: part.partID, locationID: location.locationID, unit: .each, balance: .known(q), locationRevision: movement.locationRevision, lastMovementID: movement.movementID)
    }
    func material(_ part: LocalPartReferenceSnapshotV1, lineID: UUID = C44.id(50), quantity: Int64 = 2) throws -> ManualMaterialLineV1 {
        let exact = try ExactDecimalQuantityV1(mantissa: quantity, scale: 0)
        return try .init(lineID: lineID, description: part.displayName, quantity: exact, unit: StockUnitV1.each.rawValue, localPartReference: part)
    }
    func workflowContext(_ materials: [ManualMaterialLineV1], predecessor: WorkResourceEntryV1? = nil) throws -> ManualWorkResourceWorkflowContextV1 {
        let duration = try ManualDurationV1(minutes: 30)
        return try .init(workspaceID: workspaceID, subject: subject, actor: actor, draftDuration: duration, draftMaterials: materials, predecessor: predecessor)
    }
}

final class V9_107PartsStockWorkflowTests: XCTestCase {
    private func corpus() throws -> [String: Any] {
        let name = "V23P04C44PartsStockWorkflowCorpusV1"; let bundled = Bundle(for: Self.self).url(forResource: name, withExtension: "json", subdirectory: "Fixtures/V23/PartsStock")
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/V23/PartsStock/\(name).json")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: bundled ?? source)) as? [String: Any])
    }

    @MainActor func testV23P04C44G01CatalogLookupDetailCountAdjustTransferLowStockAndArchive() throws {
        let fixture = try corpus(); XCTAssertEqual(fixture["catalogID"] as? String, PartsStockWorkflowCatalogV1.identifier)
        let h = try C44Harness("c44-g"), part = try h.part(), source = try h.location(), destination = try h.location(21), flow = try h.workflow()
        let balance = try h.seed(part, source); _ = try h.writer.commitPartsStock(.upsertLocation(destination, mutationID: C44.mutation(33)))
        XCTAssertEqual(try flow.lookup(workspaceID: h.workspaceID, request: .manualText("bolt")).map(\.partID), [part.partID])
        let scan = try StockProductIdentityV1(kind: .sku, value: "STOCK:M8-SS")
        XCTAssertEqual(try flow.lookup(workspaceID: h.workspaceID, request: .scannedIdentity(scan)).count, 1)
        XCTAssertEqual(try flow.detail(workspaceID: h.workspaceID, partID: part.partID).catalogID, "LOCAL_PART_CATALOG_V1")
        let adjustment = try StockQuantityV1(mantissa: 7, scale: 0, unit: .each)
        let adjusted = try flow.adjust(movementID: C44.id(34), part: part, location: source, magnitude: adjustment, increase: false, reason: "count correction", current: balance, actor: h.actor, occurredAt: C44.now, recordedAt: C44.now).0
        let current = try StockBalanceProjectionV1(workspaceID: h.workspaceID, partID: part.partID, locationID: source.locationID, unit: .each, balance: .known(adjusted.postBalance), locationRevision: adjusted.locationRevision, lastMovementID: adjusted.movementID)
        let destinationBalance = try StockBalanceProjectionV1(workspaceID: h.workspaceID, partID: part.partID, locationID: destination.locationID, unit: .each, balance: .unknown, locationRevision: 0, lastMovementID: nil)
        let one = try StockQuantityV1(mantissa: 1, scale: 0, unit: .each)
        XCTAssertThrowsError(try flow.transfer(part: part, source: source, destination: destination, quantity: one, sourceBalance: current, destinationBalance: destinationBalance, actor: h.actor, occurredAt: C44.now, recordedAt: C44.now))
        let countedDestination = try flow.count(movementID: C44.id(35), part: part, location: destination, observed: try StockQuantityV1(mantissa: 0, scale: 0, unit: .each), current: destinationBalance, opening: true, actor: h.actor, occurredAt: C44.now, recordedAt: C44.now).0
        let knownDestination = try StockBalanceProjectionV1(workspaceID: h.workspaceID, partID: part.partID, locationID: destination.locationID, unit: .each, balance: .known(countedDestination.postBalance), locationRevision: countedDestination.locationRevision, lastMovementID: countedDestination.movementID)
        let transfer = try flow.transfer(outboundID: C44.id(36), inboundID: C44.id(37), part: part, source: source, destination: destination, quantity: one, sourceBalance: current, destinationBalance: knownDestination, actor: h.actor, occurredAt: C44.now, recordedAt: C44.now).0
        XCTAssertEqual(transfer.outbound.postBalance.mantissa, 2); XCTAssertEqual(transfer.inbound.postBalance.mantissa, 1)
        let postTransfer = try StockBalanceProjectionV1(workspaceID: h.workspaceID, partID: part.partID, locationID: source.locationID, unit: .each, balance: .known(transfer.outbound.postBalance), locationRevision: transfer.outbound.locationRevision, lastMovementID: transfer.outbound.movementID)
        let uncounted = try h.location(22); _ = try h.writer.commitPartsStock(.upsertLocation(uncounted, mutationID: C44.mutation(38)))
        let attention = try flow.lowStock(workspaceID: h.workspaceID, locations: [source, destination, uncounted])
        XCTAssertEqual(attention.first { $0.locationID == uncounted.locationID }?.balance, .unknown)
        XCTAssertEqual(attention.first { $0.locationID == uncounted.locationID }?.isBelowPreferred, false)
        let line = try h.material(part.frozenReference())
        let useDraft = try ManualWorkResourceSuccessorDraftV1(workspaceID: h.workspaceID, subject: h.subject, actor: h.actor, materials: [line], recordedAt: C44.now)
        let useInput = ManualWorkResourceUseStockCommandV1(mutationID: try C44.mutation(40), receiptID: C44.id(41), movementID: C44.id(42), frozenMaterialLineID: line.lineID, part: part, source: source, quantity: try StockQuantityV1(mantissa: 2, scale: 0, unit: .each), sourceBalance: postTransfer, actor: h.actor, occurredAt: C44.now, recordedAt: C44.now, workResourceSuccessor: useDraft)
        let used = try flow.use(useInput, context: h.workflowContext([line])).0
        XCTAssertEqual(try h.context.fetchCount(FetchDescriptor<StockUseReceiptRowV1>()), 1)
        XCTAssertEqual(try h.context.fetchCount(FetchDescriptor<ManualWorkResourceRecordRow>()), 1)
        let postUse = try StockBalanceProjectionV1(workspaceID: h.workspaceID, partID: part.partID, locationID: source.locationID, unit: .each, balance: .known(used.movement.postBalance), locationRevision: used.movement.locationRevision, lastMovementID: used.movement.movementID)
        let remaining = try h.material(part.frozenReference(), lineID: line.lineID, quantity: 1)
        let returnDraft = try ManualWorkResourceSuccessorDraftV1(workspaceID: h.workspaceID, subject: h.subject, actor: h.actor, materials: [remaining], recordedAt: C44.now, predecessor: used.workResourceSuccessor)
        let returnInput = ManualWorkResourceReturnStockCommandV1(mutationID: try C44.mutation(43), receiptID: C44.id(44), movementID: C44.id(45), sourceUse: used, predecessorFrontier: nil, workResourcePredecessor: used.workResourceSuccessor, destination: source, quantity: one, destinationBalance: postUse, actor: h.actor, occurredAt: C44.now, recordedAt: C44.now, workResourceSuccessor: returnDraft)
        let returned = try flow.`return`(returnInput, context: h.workflowContext([remaining], predecessor: used.workResourceSuccessor)).0
        XCTAssertEqual(returned.resultingReturnedMantissa, 1)
        XCTAssertEqual(try h.context.fetchCount(FetchDescriptor<StockReturnReceiptRowV1>()), 1)
        let currentReturnBalance = try StockBalanceProjectionV1(workspaceID: h.workspaceID, partID: part.partID, locationID: source.locationID, unit: .each, balance: .known(returned.returnMovement.postBalance), locationRevision: returned.returnMovement.locationRevision, lastMovementID: returned.returnMovement.movementID)
        let excessDraft = try ManualWorkResourceSuccessorDraftV1(workspaceID: h.workspaceID, subject: h.subject, actor: h.actor, materials: [], recordedAt: C44.now, predecessor: returned.workResourceSuccessor)
        let excess = ManualWorkResourceReturnStockCommandV1(mutationID: try C44.mutation(46), receiptID: C44.id(47), movementID: C44.id(48), sourceUse: used, predecessorFrontier: try returned.frontierSnapshot(), workResourcePredecessor: returned.workResourceSuccessor, destination: source, quantity: try StockQuantityV1(mantissa: 2, scale: 0, unit: .each), destinationBalance: currentReturnBalance, actor: h.actor, occurredAt: C44.now, recordedAt: C44.now, workResourceSuccessor: excessDraft)
        XCTAssertThrowsError(try flow.`return`(excess, context: h.workflowContext([], predecessor: returned.workResourceSuccessor)))
        XCTAssertEqual(try h.context.fetchCount(FetchDescriptor<StockReturnReceiptRowV1>()), 1)
        let zeroPart = try h.part(60, sku: "STOCK:ZERO-ONLY", name: "Zero-only fastener"), zeroLocation = try h.location(61), zero = try h.seed(zeroPart, zeroLocation, quantity: 0, slot: 60)
        let archived = try flow.archive(predecessor: zeroPart, completeBalances: [zero]).0
        XCTAssertTrue(archived.archivedPartSuccessor.archived)
    }

    @MainActor func testV23P04C44A01LookupCSVImportAndDisabledPreservation() throws {
        let h = try C44Harness("c44-a"), part = try h.part(), location = try h.location(), flow = try h.workflow(); _ = try h.seed(part, location)
        let before = try h.context.fetchCount(FetchDescriptor<StockMovementEventRowV1>())
        let scan = try StockProductIdentityV1(kind: .sku, value: "STOCK:M8-SS")
        _ = try flow.lookup(workspaceID: h.workspaceID, request: .manualText("M8")); _ = try flow.lookup(workspaceID: h.workspaceID, request: .scannedIdentity(scan))
        XCTAssertEqual(try h.context.fetchCount(FetchDescriptor<StockMovementEventRowV1>()), before)
        let bytes = try flow.exportCSV(workspaceID: h.workspaceID); let plan = try flow.previewCSVImport(workspaceID: h.workspaceID, csvBytes: bytes)
        XCTAssertEqual(plan.rows.count, 1); XCTAssertEqual(try flow.previewCSVImport(workspaceID: h.workspaceID, csvBytes: bytes).rows.map(\.mutationID), plan.rows.map(\.mutationID))
        let empty = try PartsStockWorkflowCSVCodecV1.export([])
        XCTAssertEqual(String(data: empty, encoding: .utf8), PartsStockWorkflowCSVCodecV1.header)
        let emptyPlan = try flow.previewCSVImport(workspaceID: h.workspaceID, csvBytes: empty)
        XCTAssertTrue(emptyPlan.rows.isEmpty)
        let emptyResult = try flow.importCSV(emptyPlan)
        XCTAssertEqual(emptyResult.disposition, .complete); XCTAssertTrue(emptyResult.committedReceipts.isEmpty)
        let fresh = try C44Harness("c44-a-import"), freshFlow = try fresh.workflow()
        let cancelled = try freshFlow.importCSV(plan, cancellingAfter: 0); XCTAssertEqual(cancelled.disposition, .cancelled); XCTAssertTrue(cancelled.committedReceipts.isEmpty)
        let disabled = try h.workflow(policy: .readExportRecoveryOnly); XCTAssertNoThrow(try disabled.exportCSV(workspaceID: h.workspaceID)); XCTAssertThrowsError(try disabled.importCSV(plan))
    }

    @MainActor func testV23P04C44H01RejectsMalformedCSVUnknownStockAndStandaloneReturnClaims() throws {
        let h = try C44Harness("c44-h"), flow = try h.workflow(), part = try h.part(), location = try h.location()
        XCTAssertThrowsError(try flow.previewCSVImport(workspaceID: h.workspaceID, csvBytes: Data("wrong".utf8)))
        XCTAssertThrowsError(try flow.previewCSVImport(workspaceID: h.workspaceID, csvBytes: Data("catalog_id,row_index,part_id,display_name\n\"unterminated".utf8)))
        let unknown = try StockBalanceProjectionV1(workspaceID: h.workspaceID, partID: part.partID, locationID: location.locationID, unit: .each, balance: .unknown, locationRevision: 0, lastMovementID: nil)
        let one = try StockQuantityV1(mantissa: 1, scale: 0, unit: .each)
        XCTAssertThrowsError(try flow.adjust(part: part, location: location, magnitude: one, increase: true, reason: "no count", current: unknown, actor: h.actor, occurredAt: C44.now, recordedAt: C44.now))
        XCTAssertTrue(C44PartsStockWorkflowBoundaryV1.returnsRequireEligibleUseAndOrderedFrontier)
        XCTAssertTrue(C44PartsStockWorkflowBoundaryV1.onlyExplicitUseMutatesStock)
    }

    @MainActor func testV23P04C44I01AndR01CSVReceiptFirstReplayAndReportRedaction() throws {
        let h = try C44Harness("c44-r"), flow = try h.workflow(), part = try h.part()
        let bytes = try PartsStockWorkflowCSVCodecV1.export([part]); let plan = try flow.previewCSVImport(workspaceID: h.workspaceID, csvBytes: bytes)
        let first = try flow.importCSV(plan); let replay = try flow.importCSV(plan)
        XCTAssertEqual(first, replay); XCTAssertEqual(first.disposition, .complete); XCTAssertEqual(first.committedReceipts.count, 1)
        let report = try flow.report(workspaceID: h.workspaceID, reviewedPartIDs: [part.partID]); XCTAssertEqual(report.parts.count, 1)
        let encoded = try JSONEncoder().encode(report); let text = try XCTUnwrap(String(data: encoded, encoding: .utf8)); XCTAssertFalse(text.localizedCaseInsensitiveContains("balance")); XCTAssertFalse(text.localizedCaseInsensitiveContains("bin"))
        var divergent = try h.part(11); divergent = try LocalPartDefinitionV1(partID: part.partID, workspaceID: h.workspaceID, displayName: "Different", canonicalUnit: .each, revision: 1, mutationID: plan.rows[0].mutationID)
        XCTAssertNotEqual(divergent, part)
    }

    @MainActor func testV23P04C44I01ImportedRowEffectBeforeReceiptRecoversExactlyOnce() throws {
        let interrupted = try C44Harness("c44-i", failure: .init(failOnceAt: .afterEffectBeforeReceipt))
        let sourcePart = try interrupted.part(); let bytes = try PartsStockWorkflowCSVCodecV1.export([sourcePart])
        let flow = try interrupted.workflow(); let plan = try flow.previewCSVImport(workspaceID: interrupted.workspaceID, csvBytes: bytes)
        let incomplete = try flow.importCSV(plan)
        XCTAssertEqual(incomplete.disposition, .incomplete); XCTAssertEqual(incomplete.incompleteAtRowIndex, 0)
        XCTAssertTrue(incomplete.committedReceipts.isEmpty)
        let recovered = try flow.importCSV(plan); let replay = try flow.importCSV(plan)
        XCTAssertEqual(recovered, replay); XCTAssertEqual(recovered.disposition, .complete)
        XCTAssertEqual(try interrupted.context.fetchCount(FetchDescriptor<LocalPartDefinitionRowV1>()), 1)
    }
}

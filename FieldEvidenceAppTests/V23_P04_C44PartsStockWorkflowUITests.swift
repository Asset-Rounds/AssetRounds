import Foundation
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import FieldEvidenceApp

final class V23_P04_C44PartsStockWorkflowUITests: V23ProductionFourRootShellTestSupport {
    @MainActor
    func testV23P04C44StaticAccessibilityJourneyIsClosed() {
        let journey = [
            PartsStockWorkflowView.screenAccessibilityIdentifier,
            PartsStockWorkflowView.catalogAccessibilityIdentifier,
            PartsStockWorkflowView.lookupAccessibilityIdentifier,
            PartsStockWorkflowView.detailAccessibilityIdentifier,
            PartsStockWorkflowView.countAccessibilityIdentifier,
            PartsStockWorkflowView.useAccessibilityIdentifier,
            PartsStockWorkflowView.returnAccessibilityIdentifier,
            PartsStockWorkflowView.statusAccessibilityIdentifier
        ]
        XCTAssertEqual(Set(journey).count, journey.count)
        XCTAssertEqual(journey, ["v23.p04.c44.parts-stock-workflow.screen", "v23.p04.c44.parts-stock-workflow.catalog", "v23.p04.c44.parts-stock-workflow.lookup", "v23.p04.c44.parts-stock-workflow.detail", "v23.p04.c44.parts-stock-workflow.count", "v23.p04.c44.parts-stock-workflow.use", "v23.p04.c44.parts-stock-workflow.return", "v23.p04.c44.parts-stock-workflow.status"])
    }

    // Full live adoption remains PENDING, separately from these Phase 1 tests:
    // testV23P04C44VisibleWorkCatalogLookupDetailCountAndHistoryJourney
    // testV23P04C44VisibleExplicitUseEligibleBoundReturnAndHistoryJourney
    // testV23P04C44LiveDisablePreservesStockDraftExportAndRecoveryJourney
    // They still require the real Work entry, explicit canonical mutations,
    // receipt-bound Return/history, stock-draft lifecycle, accessibility and
    // qualified owner-reviewed UI evidence. Direct hosting is not adoption.
    @MainActor
    func testV23P04C44PhaseOneWorkDoesNotOfferLiveStockJourney() async throws {
        #if DEBUG
        let fixture = try await makeFixture("c44-phase-one-stock-boundary")
        defer { fixture.cleanUp() }
        let writer = fixture.coordinator.workspaceWriter
        let seed = try C954StockSeedV1.make(writer: writer,
            context: fixture.coordinator.modelContext,
            workspaceID: fixture.coordinator.workspaceID)
        let before = try seed.snapshot(writer: writer)
        XCTAssertEqual(before.stock.parts, [seed.part])
        XCTAssertEqual(before.stock.uses, [seed.used])
        XCTAssertEqual(before.drafts, [seed.checkpoint])
        XCTAssertFalse(before.receipts.isEmpty)

        try selectWorkBeforeLaunch(fixture)
        var composedScene: AppShellSceneStateV1?
        let shipping = try mountCompletedWorkShell(store: fixture.coordinator,
            presentation: fixture.presentation, diagnostics: fixture.diagnostics,
            router: fixture.router) { scene in
                if composedScene == nil { composedScene = scene }
            }
        defer { shipping.unmount() }
        let workMounted = await waitForMountedScreen(
            ProductionWorkRootViewV1.screenAccessibilityIdentifier, from: shipping.host)
        XCTAssertTrue(workMounted, "The actual Work source must finish loading")
        let completedMounted = await waitForMountedScreen(
            SignoffEnrollmentView.workRootAccessibilityIdentifier, from: shipping.host)
        XCTAssertTrue(completedMounted, "The real Phase 1 Work content is composed")
        let scene = try XCTUnwrap(composedScene)
        XCTAssertEqual(scene.snapshot?.selectedRoot, .work)

        let featureWitnesses = c954FeatureWitnesses(seed: seed)
        for identifier in featureWitnesses {
            XCTAssertFalse(nativeScreenObservation(identifier, from: shipping.host).found,
                "Loaded shipping Work must not offer the live stock node: \(identifier)")
        }
        XCTAssertEqual(try seed.snapshot(writer: writer), before)
        XCTAssertFalse(seed.context.hasChanges)
        shipping.unmount()

        // The same actual rendered nodes must be observable on the real
        // contained view. `.allFeatures` cannot wire this unwired feature.
        let projection = try seed.containedProjection(writer: writer)
        XCTAssertEqual(projection.selectedItem?.detail.part, seed.part)
        XCTAssertEqual(projection.eligibleReturns.map(\.sourceUse), [seed.used])
        XCTAssertEqual(projection.draft?.draftID, seed.checkpoint.draftID)
        XCTAssertEqual(projection.draft?.revision, seed.checkpoint.draftRevision)
        var commands: [PartsStockWorkflowCommandV1] = []
        let contained = try mountC954ContainedView(projection: projection) { commands.append($0) }
        defer { contained.unmount() }
        for identifier in featureWitnesses {
            let mounted = await waitForMountedScreen(identifier, from: contained.host)
            XCTAssertTrue(mounted, "The same actual C44 node must be observed: \(identifier)")
        }
        XCTAssertTrue(commands.isEmpty, "Mounting/read-only preservation requests no command")
        XCTAssertEqual(try seed.snapshot(writer: writer), before)
        XCTAssertFalse(seed.context.hasChanges)
        #else
        XCTFail("The required native Phase 1 boundary uses the pinned DEBUG host route")
        #endif
    }

    @MainActor
    func testV23P04C44ReadOnlyPolicyPreservesIncumbentDraftExportAndRecoveryAndRejectsStockWrites() throws {
        #if DEBUG
        let harness = try C954WriterHarnessV1()
        defer { harness.writer.invalidate() }
        let seed = try C954StockSeedV1.make(writer: harness.writer,
            context: harness.context, workspaceID: harness.identity.workspaceID)
        let enabled = try seed.workflow(writer: harness.writer, policy: .enabled)
        let beforeExport = try enabled.exportCSV(workspaceID: seed.workspaceID)
        let before = try seed.snapshot(writer: harness.writer)
        XCTAssertEqual(before.stock.parts, [seed.part])
        XCTAssertEqual(before.stock.uses, [seed.used])
        XCTAssertEqual(before.workResources, [seed.used.workResourceSuccessor])
        XCTAssertEqual(before.drafts, [seed.checkpoint])
        XCTAssertEqual(before.draftEvidence.receipt, seed.draftReceipt)
        XCTAssertEqual(try harness.writer.durableReceipt(mutationID: seed.checkpoint.mutationID),
            seed.draftReceipt)
        XCTAssertEqual(seed.checkpoint.payloadData, C954StockBoundaryV1.draftPayload)
        XCTAssertFalse(before.receipts.isEmpty)
        XCTAssertFalse(beforeExport.isEmpty)
        XCTAssertFalse(harness.context.hasChanges)

        let disabled = try seed.workflow(writer: harness.writer, policy: .readExportRecoveryOnly)
        XCTAssertEqual(try disabled.catalog(workspaceID: seed.workspaceID), [seed.part])
        XCTAssertEqual(try disabled.lookup(workspaceID: seed.workspaceID,
            request: .manualText("C954 bolt")), [seed.part])
        XCTAssertEqual(try disabled.detail(workspaceID: seed.workspaceID,
            partID: seed.part.partID).part, seed.part)
        XCTAssertEqual(try disabled.exportCSV(workspaceID: seed.workspaceID), beforeExport)
        let attention = try disabled.lowStock(workspaceID: seed.workspaceID,
            locations: [seed.source, seed.destination, seed.uncounted])
        let unknown = try XCTUnwrap(attention.first { $0.locationID == seed.uncounted.locationID })
        XCTAssertEqual(unknown.balance, .unknown)
        XCTAssertFalse(unknown.isBelowPreferred, "Never-counted stock is not zero")
        XCTAssertEqual(try seed.snapshot(writer: harness.writer), before)

        let importedPart = try seed.importCandidate()
        let importBytes = try PartsStockWorkflowCSVCodecV1.export([importedPart])
        let importPlan = try disabled.previewCSVImport(workspaceID: seed.workspaceID,
            csvBytes: importBytes)
        XCTAssertEqual(importPlan.rows.count, 1)
        XCTAssertEqual(importPlan.rows.first?.row.partID, importedPart.partID)
        XCTAssertEqual(try seed.snapshot(writer: harness.writer), before)

        let current = try seed.lifecycle.projection(workspaceID: seed.workspaceID,
            partID: seed.part.partID, locationID: seed.source.locationID, unit: .each)
        let destinationBalance = try seed.lifecycle.projection(workspaceID: seed.workspaceID,
            partID: seed.part.partID, locationID: seed.destination.locationID, unit: .each)
        XCTAssertEqual(current.balance, .known(try C954StockBoundaryV1.quantity(8)))
        XCTAssertEqual(destinationBalance.balance, .known(try C954StockBoundaryV1.quantity(0)))
        let one = try C954StockBoundaryV1.quantity(1)
        let newUseLine = try ManualMaterialLineV1(lineID: C954StockBoundaryV1.id(213),
            description: seed.part.displayName, quantity: .init(mantissa: 1, scale: 0),
            unit: StockUnitV1.each.rawValue, localPartReference: seed.part.frozenReference())
        let nextMaterials = seed.used.workResourceSuccessor.materials + [newUseLine]
        let useSuccessor = try ManualWorkResourceSuccessorDraftV1(workspaceID: seed.workspaceID,
            subject: seed.subject, actor: seed.actor, materials: nextMaterials,
            recordedAt: C954StockBoundaryV1.now, predecessor: seed.used.workResourceSuccessor)
        let useInput = ManualWorkResourceUseStockCommandV1(
            mutationID: try C954StockBoundaryV1.mutation(210),
            receiptID: C954StockBoundaryV1.id(211), movementID: C954StockBoundaryV1.id(212),
            frozenMaterialLineID: newUseLine.lineID, part: seed.part, source: seed.source,
            quantity: one, sourceBalance: current, actor: seed.actor,
            occurredAt: C954StockBoundaryV1.now, recordedAt: C954StockBoundaryV1.now,
            workResourceSuccessor: useSuccessor)
        let returnedMaterials = [try seed.material(quantity: 1)]
        let returnSuccessor = try ManualWorkResourceSuccessorDraftV1(workspaceID: seed.workspaceID,
            subject: seed.subject, actor: seed.actor, materials: returnedMaterials,
            recordedAt: C954StockBoundaryV1.now, predecessor: seed.used.workResourceSuccessor)
        let returnInput = ManualWorkResourceReturnStockCommandV1(
            mutationID: try C954StockBoundaryV1.mutation(220),
            receiptID: C954StockBoundaryV1.id(221), movementID: C954StockBoundaryV1.id(222),
            sourceUse: seed.used, predecessorFrontier: nil,
            workResourcePredecessor: seed.used.workResourceSuccessor,
            destination: seed.source, quantity: one, destinationBalance: current,
            actor: seed.actor, occurredAt: C954StockBoundaryV1.now,
            recordedAt: C954StockBoundaryV1.now, workResourceSuccessor: returnSuccessor)
        let useContext = try seed.workflowContext(nextMaterials,
            predecessor: seed.used.workResourceSuccessor)
        let returnContext = try seed.workflowContext(returnedMaterials,
            predecessor: seed.used.workResourceSuccessor)
        let allocationsBefore = harness.ids.allocationCount

        func rejectWrite(_ name: String, _ operation: () throws -> Void) throws {
            XCTAssertThrowsError(try operation(), name) { error in
                XCTAssertEqual(error as? PartsStockFailureV1, .writesDisabled, name)
            }
            XCTAssertEqual(harness.ids.allocationCount, allocationsBefore,
                "Disabled \(name) must not allocate a writer MutationID")
            XCTAssertEqual(try seed.snapshot(writer: harness.writer), before, name)
            XCTAssertFalse(harness.context.hasChanges, name)
        }
        try rejectWrite("Count") {
            _ = try disabled.count(movementID: C954StockBoundaryV1.id(200),
                part: seed.part, location: seed.source, observed: one, current: current,
                opening: false, actor: seed.actor, occurredAt: C954StockBoundaryV1.now,
                recordedAt: C954StockBoundaryV1.now)
        }
        try rejectWrite("Adjust") {
            _ = try disabled.adjust(movementID: C954StockBoundaryV1.id(201),
                part: seed.part, location: seed.source, magnitude: one, increase: false,
                reason: "Explicit correction", current: current, actor: seed.actor,
                occurredAt: C954StockBoundaryV1.now, recordedAt: C954StockBoundaryV1.now)
        }
        try rejectWrite("Transfer") {
            _ = try disabled.transfer(outboundID: C954StockBoundaryV1.id(202),
                inboundID: C954StockBoundaryV1.id(203), part: seed.part,
                source: seed.source, destination: seed.destination, quantity: one,
                sourceBalance: current, destinationBalance: destinationBalance,
                actor: seed.actor, occurredAt: C954StockBoundaryV1.now,
                recordedAt: C954StockBoundaryV1.now)
        }
        try rejectWrite("Use") { _ = try disabled.use(useInput, context: useContext) }
        try rejectWrite("Return") { _ = try disabled.`return`(returnInput, context: returnContext) }
        try rejectWrite("Archive") {
            // Nonzero stock is deliberately retained. This asserts policy
            // precedence, not eligibility to retire that stock definition.
            _ = try disabled.archive(predecessor: seed.part, completeBalances: [current, destinationBalance])
        }
        try rejectWrite("CSV import") { _ = try disabled.importCSV(importPlan) }

        // A healthy canonical journal may still be revalidated and replayed
        // while the stock facade is read-only. This is not interruption,
        // disk-reopen, replace/clone/fork or integrated stock-draft recovery.
        let oldWriterInstance = try harness.writer.currentRevision().writerInstanceID
        try harness.reactivateAfterHealthyRecovery()
        XCTAssertNotEqual(try harness.writer.currentRevision().writerInstanceID, oldWriterInstance)
        let recovered = try seed.workflow(writer: harness.writer, policy: .readExportRecoveryOnly)
        XCTAssertEqual(try seed.snapshot(writer: harness.writer), before)
        XCTAssertEqual(try recovered.exportCSV(workspaceID: seed.workspaceID), beforeExport)
        XCTAssertEqual(try harness.writer.durableReceipt(mutationID: seed.checkpoint.mutationID),
            seed.draftReceipt)
        XCTAssertEqual(try harness.writer.fieldDraftEvidence(mutationID: seed.checkpoint.mutationID),
            before.draftEvidence)
        let recoveredAllocations = harness.ids.allocationCount
        XCTAssertThrowsError(try recovered.count(movementID: C954StockBoundaryV1.id(230),
            part: seed.part, location: seed.source, observed: one, current: current,
            opening: false, actor: seed.actor, occurredAt: C954StockBoundaryV1.now,
            recordedAt: C954StockBoundaryV1.now)) { error in
            XCTAssertEqual(error as? PartsStockFailureV1, .writesDisabled)
        }
        XCTAssertEqual(harness.ids.allocationCount, recoveredAllocations)
        XCTAssertEqual(try seed.snapshot(writer: harness.writer), before)
        XCTAssertFalse(harness.context.hasChanges)
        #else
        XCTFail("The isolated real-journal fixture requires the pinned DEBUG host route")
        #endif
    }
}

#if DEBUG
private enum C954StockBoundaryV1 {
    static let now = Date(timeIntervalSince1970: 1_788_364_800)
    static let draftPayload = Data("C954 incumbent Work draft: preserve this material note".utf8)
    static func id(_ slot: Int) -> UUID {
        UUID(uuidString: String(format: "C9540000-0000-4000-8000-%012x", slot))!
    }
    static func mutation(_ slot: Int) throws -> MutationIDV1 { try .init(rawValue: id(slot)) }
    static func quantity(_ value: Int64) throws -> StockQuantityV1 {
        try .init(mantissa: value, scale: 0, unit: .each)
    }
}

private struct C954ClockV1: ApplicationClock {
    func now() -> Date { C954StockBoundaryV1.now }
}

private final class C954IDsV1: ApplicationIDSource, @unchecked Sendable {
    private let lock = NSLock()
    private var next = 1_000
    var allocationCount: Int {
        lock.lock(); defer { lock.unlock() }
        return next - 1_000
    }
    func makeID() -> UUID {
        lock.lock(); defer { lock.unlock() }
        defer { next += 1 }
        return C954StockBoundaryV1.id(next)
    }
}

private struct C954FilesV1: ApplicationFileAuthorityV1 {
    func temporaryRelativePath(mutationID: MutationIDV1, component: String) throws -> String {
        "c954/\(mutationID.rawValue.uuidString.lowercased())/\(component)"
    }
}

@MainActor
private final class C954WriterHarnessV1 {
    let container: ModelContainer
    let context: ModelContext
    let identity: WorkspaceReplicaIdentityV1
    let journal: MutationJournalStoreV1
    let ids: C954IDsV1
    private(set) var writer: WorkspaceWriterV1

    init() throws {
        let schema = Schema(PersistentSchemaV53.models, version: PersistentSchemaV53.versionIdentifier)
        container = try ModelContainer(for: schema, migrationPlan: nil,
            configurations: [ModelConfiguration("C954-read-only-stock", schema: schema,
                isStoredInMemoryOnly: true, allowsSave: true, cloudKitDatabase: .none)])
        context = container.mainContext
        context.autosaveEnabled = false
        identity = try WorkspaceReplicaIdentityV1(
            workspaceID: WorkspaceID(rawValue: C954StockBoundaryV1.id(1)),
            replicaID: ReplicaID(rawValue: C954StockBoundaryV1.id(4)))
        journal = try MutationJournalStoreV1(modelContext: context, identity: identity,
            generationID: C954StockBoundaryV1.id(5))
        let installedIDs = C954IDsV1()
        ids = installedIDs
        writer = try WorkspaceWriterV1(identity: identity, generationID: C954StockBoundaryV1.id(5),
            initialRevision: journal.currentRevision(writerInstanceID: C954StockBoundaryV1.id(6)),
            clock: C954ClockV1(), idSource: installedIDs, fileAuthority: C954FilesV1(),
            adapter: WorkspaceWriterAdapterV1(modelContext: context), journalStore: journal)
    }

    func reactivateAfterHealthyRecovery() throws {
        writer.invalidate()
        try MutationReceiptRecoveryServiceV1(store: journal).recoverBeforeWriterActivation()
        writer = try WorkspaceWriterV1(identity: identity, generationID: C954StockBoundaryV1.id(5),
            initialRevision: journal.currentRevision(writerInstanceID: C954StockBoundaryV1.id(7)),
            clock: C954ClockV1(), idSource: ids, fileAuthority: C954FilesV1(),
            adapter: WorkspaceWriterAdapterV1(modelContext: context), journalStore: journal)
    }
}

/// Equality deliberately excludes the noncanonical writer-instance identity;
/// receipt values, workspace/entity revisions and all seeded effects stay exact.
private struct C954CanonicalSnapshotV1: Equatable {
    let workspaceID: WorkspaceID
    let generationID: UUID
    let workspaceRevision: UInt64
    let entityRevisions: [WorkspaceEntityRevisionV1]
    let receipts: [MutationReceiptV1]
    let stock: PartsStockBackupSnapshotV1
    let balances: [StockBalanceProjectionV1]
    let workResources: [WorkResourceEntryV1]
    let drafts: [FieldDraftCheckpointV1]
    let draftEvidence: FieldDraftCommittedEvidenceV1
}

@MainActor
private struct C954StockSeedV1 {
    let context: ModelContext
    let workspaceID: WorkspaceID
    let actor: ActorSnapshotV1
    let subject: WorkResourceSubjectV1
    let part: LocalPartDefinitionV1
    let source: StockStorageLocationV1
    let destination: StockStorageLocationV1
    let uncounted: StockStorageLocationV1
    let used: StockUseOnWorkReceiptV1
    let checkpoint: FieldDraftCheckpointV1
    let draftReceipt: MutationReceiptV1
    let lifecycle: PartsStockLifecycleAdapterV1
    var materialLineID: UUID { C954StockBoundaryV1.id(50) }
    var returnCandidateID: UUID { C954StockBoundaryV1.id(80) }

    static func make(writer: WorkspaceWriterV1, context: ModelContext,
                     workspaceID: WorkspaceID) throws -> Self {
        let reference = try LocalActorReferenceV1(actorReferenceID: C954StockBoundaryV1.id(2),
            workspaceID: workspaceID, displayName: "C954 recorder")
        let actor = try ActorSnapshotV1(snapshotID: C954StockBoundaryV1.id(3),
            workspaceID: workspaceID, actor: reference, responsibility: .recordedBy,
            displayNameAtTime: "C954 recorder", capturedAt: C954StockBoundaryV1.now)
        _ = try writer.execute(.applyPartyAccountability(.appendActorSnapshot(actor)),
            mutationID: C954StockBoundaryV1.mutation(10_000))
        let item = try WorkPacketItemV1(itemID: "C954-WORK", kind: .inspection,
            expectedRevision: 1, itemSHA256: String(repeating: "a", count: 64))
        let manifest = try WorkPacketManifestV1(manifestID: C954StockBoundaryV1.id(8),
            packetID: C954StockBoundaryV1.id(9), packetVersion: 1, workspaceID: workspaceID,
            items: [item], packageReleases: [], creationBasis: .explicitLocalSelection,
            creator: actor, createdAt: C954StockBoundaryV1.now,
            mutationID: C954StockBoundaryV1.mutation(10))
        let packetMutation = try WorkPacketMutationV1(workspaceID: workspaceID,
            expectedRevision: 0, mutationID: manifest.mutationID, postImage: .appendManifest(manifest))
        _ = try writer.execute(.applyWorkPacket(packetMutation), mutationID: manifest.mutationID)
        let subject = try WorkResourceSubjectV1(workspaceID: workspaceID, kind: .workPacket,
            subjectID: manifest.manifestID.uuidString, subjectRevision: manifest.revision,
            subjectSHA256: manifest.manifestSHA256)
        let part = try LocalPartDefinitionV1(partID: C954StockBoundaryV1.id(20),
            workspaceID: workspaceID, displayName: "C954 bolt", canonicalUnit: .each,
            productIdentities: [.init(kind: .sku, value: "STOCK:C954-BOLT")],
            preferredMinimum: C954StockBoundaryV1.quantity(4), revision: 1,
            mutationID: C954StockBoundaryV1.mutation(21))
        _ = try writer.commitPartsStock(.upsertPart(part))
        func location(_ slot: Int, _ label: String) throws -> StockStorageLocationV1 {
            try .init(locationID: C954StockBoundaryV1.id(slot), workspaceID: workspaceID,
                kind: .shop, label: label, revision: 1)
        }
        let source = try location(30, "C954 source")
        let destination = try location(31, "C954 destination")
        let uncounted = try location(32, "C954 never counted")
        for (offset, value) in [source, destination, uncounted].enumerated() {
            _ = try writer.commitPartsStock(.upsertLocation(value,
                mutationID: C954StockBoundaryV1.mutation(40 + offset)))
        }
        let stock = PartsStockCoordinatorV1(writer: writer)
        let lifecycle = PartsStockLifecycleAdapterV1(modelContext: context)
        for (offset, pair) in [(source, Int64(10)), (destination, Int64(0))].enumerated() {
            let unknown = try lifecycle.projection(workspaceID: workspaceID,
                partID: part.partID, locationID: pair.0.locationID, unit: .each)
            _ = try stock.count(movementID: C954StockBoundaryV1.id(60 + offset), part: part,
                location: pair.0, observed: C954StockBoundaryV1.quantity(pair.1),
                current: unknown, opening: true, actor: actor,
                occurredAt: C954StockBoundaryV1.now, recordedAt: C954StockBoundaryV1.now)
        }
        let line = try ManualMaterialLineV1(lineID: C954StockBoundaryV1.id(50),
            description: part.displayName, quantity: .init(mantissa: 2, scale: 0),
            unit: StockUnitV1.each.rawValue, localPartReference: part.frozenReference())
        let draft = try ManualWorkResourceSuccessorDraftV1(workspaceID: workspaceID,
            subject: subject, actor: actor, materials: [line], recordedAt: C954StockBoundaryV1.now)
        let work = try ManualWorkResourceWorkflowCoordinatorV1(
            workResources: WorkResourceCoordinatorV1(writer: writer), stock: stock,
            stockCapability: .available)
        let enabled = PartsStockWorkflowCoordinatorV1(stock: stock, workResources: work,
            lifecycle: lifecycle)
        let use = ManualWorkResourceUseStockCommandV1(
            mutationID: try C954StockBoundaryV1.mutation(70),
            receiptID: C954StockBoundaryV1.id(71), movementID: C954StockBoundaryV1.id(72),
            frozenMaterialLineID: line.lineID, part: part, source: source,
            quantity: try C954StockBoundaryV1.quantity(2),
            sourceBalance: try lifecycle.projection(workspaceID: workspaceID,
                partID: part.partID, locationID: source.locationID, unit: .each),
            actor: actor, occurredAt: C954StockBoundaryV1.now,
            recordedAt: C954StockBoundaryV1.now, workResourceSuccessor: draft)
        let useContext = try ManualWorkResourceWorkflowContextV1(workspaceID: workspaceID,
            subject: subject, actor: actor, draftDuration: .init(minutes: 30), draftMaterials: [line])
        let used = try enabled.use(use, context: useContext).0

        // An incumbent registered test-contract Work draft is the sentinel.
        // No C44 draft codec or shipping stock-draft integration is invented.
        let checkpoint = try FieldDraftCheckpointV1(draftID: C954StockBoundaryV1.id(90),
            workspaceID: workspaceID,
            scope: .init(scopeKind: "c954-incumbent-work", stableComponentIDs: [subject.subjectID]),
            purpose: .workPacket, codec: C36FieldDraftTestSupportV1.codec(for: .workPacket),
            baseCanonicalRevision: manifest.revision, draftRevision: 1,
            payloadData: C954StockBoundaryV1.draftPayload, stageIDs: [],
            resumeAnchor: .init(sectionID: "materials"), state: .active,
            updatedAt: C954StockBoundaryV1.now,
            mutationID: C954StockBoundaryV1.mutation(91))
        try checkpoint.validate(registry: C36FieldDraftTestSupportV1.makeRegistry())
        let draftAdapter = try writer.makeFieldDraftLifecycleAdapter(modelContext: context)
        let draftReceipt = try draftAdapter.compareAndSwap(checkpoint: checkpoint,
            expectedDraftRevision: 0, expectedBaseRevision: checkpoint.baseCanonicalRevision)
        let actualCheckpoint = try XCTUnwrap(draftAdapter.currentCheckpoint(
            workspaceID: workspaceID, draftID: checkpoint.draftID))
        guard actualCheckpoint == checkpoint else { throw FieldDraftFailureV1.digestMismatch }
        let evidence = try XCTUnwrap(writer.fieldDraftEvidence(mutationID: checkpoint.mutationID))
        guard evidence.receipt == draftReceipt else { throw FieldDraftFailureV1.missingReceipt }
        return Self(context: context, workspaceID: workspaceID, actor: actor, subject: subject,
            part: part, source: source, destination: destination, uncounted: uncounted,
            used: used, checkpoint: actualCheckpoint, draftReceipt: draftReceipt, lifecycle: lifecycle)
    }

    func workflow(writer: WorkspaceWriterV1,
                  policy: LocalStockFeaturePolicyV1) throws -> PartsStockWorkflowCoordinatorV1 {
        let stock = PartsStockCoordinatorV1(writer: writer, featurePolicy: policy.partsStockPolicy)
        let work = try ManualWorkResourceWorkflowCoordinatorV1(
            workResources: WorkResourceCoordinatorV1(writer: writer), stock: stock,
            stockCapability: policy.allowsWrites ? .available : .disabled)
        return PartsStockWorkflowCoordinatorV1(stock: stock, workResources: work,
            lifecycle: lifecycle, featurePolicy: policy)
    }

    func material(quantity: Int64) throws -> ManualMaterialLineV1 {
        try .init(lineID: materialLineID, description: part.displayName,
            quantity: .init(mantissa: quantity, scale: 0), unit: StockUnitV1.each.rawValue,
            localPartReference: part.frozenReference())
    }

    func workflowContext(_ materials: [ManualMaterialLineV1],
                         predecessor: WorkResourceEntryV1) throws -> ManualWorkResourceWorkflowContextV1 {
        try .init(workspaceID: workspaceID, subject: subject, actor: actor,
            draftDuration: .init(minutes: 30), draftMaterials: materials, predecessor: predecessor)
    }

    func importCandidate() throws -> LocalPartDefinitionV1 {
        try .init(partID: C954StockBoundaryV1.id(95), workspaceID: workspaceID,
            displayName: "C954 new catalog part", canonicalUnit: .each,
            productIdentities: [.init(kind: .sku, value: "STOCK:C954-IMPORT")],
            revision: 1, mutationID: C954StockBoundaryV1.mutation(96))
    }

    func snapshot(writer: WorkspaceWriterV1) throws -> C954CanonicalSnapshotV1 {
        let revision = try writer.currentRevision()
        let receipts = try writer.acceptedReceiptsForProjection().sorted {
            $0.mutationID.rawValue.uuidString < $1.mutationID.rawValue.uuidString
        }
        let drafts = try context.fetch(FetchDescriptor<FieldDraftCheckpointRow>())
            .map { try $0.value() }.sorted { $0.draftID.uuidString < $1.draftID.uuidString }
        let resources = try context.fetch(FetchDescriptor<ManualWorkResourceRecordRow>())
            .map { try $0.value() }.sorted { $0.entryID.uuidString < $1.entryID.uuidString }
        let evidence = try XCTUnwrap(writer.fieldDraftEvidence(mutationID: checkpoint.mutationID))
        return C954CanonicalSnapshotV1(workspaceID: revision.workspaceID,
            generationID: revision.generationID, workspaceRevision: revision.revision,
            entityRevisions: revision.entityRevisions, receipts: receipts,
            stock: try lifecycle.snapshotForBackup(workspaceID: workspaceID),
            balances: try lifecycle.replay(workspaceID: workspaceID), workResources: resources,
            drafts: drafts, draftEvidence: evidence)
    }

    func containedProjection(writer: WorkspaceWriterV1) throws -> PartsStockWorkflowProjectionV1 {
        let disabled = try workflow(writer: writer, policy: .readExportRecoveryOnly)
        let persisted = try lifecycle.snapshotForBackup(workspaceID: workspaceID)
        let actualUse = try XCTUnwrap(persisted.uses.first { $0.receiptID == used.receiptID })
        let balance = try lifecycle.projection(workspaceID: workspaceID,
            partID: part.partID, locationID: source.locationID, unit: .each)
        let item = try PartsStockWorkflowCatalogItemV1(
            detail: disabled.detail(workspaceID: workspaceID, partID: part.partID),
            balances: [.init(projection: balance, location: source)])
        let candidate = try PartsStockWorkflowReturnPresentationV1(id: returnCandidateID,
            sourceUse: actualUse, destination: source, workLabel: "C954 accepted Use",
            outstandingQuantity: actualUse.movement.quantity)
        return .init(featurePolicy: .readExportRecoveryOnly, availability: .featureDisabled,
            catalog: [item], selectedPartID: item.id, returns: [candidate],
            draft: .init(draftID: checkpoint.draftID, revision: checkpoint.draftRevision,
                materialText: String(decoding: checkpoint.payloadData, as: UTF8.self),
                state: .checkpointed, canCheckpoint: false),
            csv: .init(importAvailable: false, exportAvailable: true),
            history: [.init(id: actualUse.receiptID, title: "Accepted Use receipt",
                detail: actualUse.receiptID.uuidString)])
    }
}

private extension V23_P04_C44PartsStockWorkflowUITests {
    @MainActor
    func c954FeatureWitnesses(seed: C954StockSeedV1) -> [String] {
        [PartsStockWorkflowView.screenAccessibilityIdentifier,
         PartsStockWorkflowView.catalogAccessibilityIdentifier,
         PartsStockWorkflowView.catalogItemAccessibilityIdentifierPrefix
            + seed.part.partID.uuidString.lowercased(),
         PartsStockWorkflowView.countAccessibilityIdentifier,
         PartsStockWorkflowView.useAccessibilityIdentifier + ".submit",
         PartsStockWorkflowView.eligibleReturnObservationIdentifier,
         PartsStockWorkflowView.draftAccessibilityIdentifier + ".material"]
    }

    @MainActor
    func mountC954ContainedView(projection: PartsStockWorkflowProjectionV1,
        onCommand: @escaping @MainActor (PartsStockWorkflowCommandV1) -> Void
    ) throws -> SIG1MountedShellV1 {
        let windowScene = try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = windowScene.windows.first { $0.isKeyWindow }
        let content = NavigationStack {
            PartsStockWorkflowView(model: projection, onCommand: onCommand)
        }
        let host = UIHostingController(rootView: AnyView(content))
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        return SIG1MountedShellV1(window: window, host: host, previousKeyWindow: previousKeyWindow)
    }
}
#endif

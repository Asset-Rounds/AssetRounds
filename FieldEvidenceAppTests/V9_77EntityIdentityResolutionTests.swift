import Foundation
import SwiftData
import XCTest

@testable import FieldEvidenceApp

@MainActor
final class V9_77EntityIdentityResolutionTests: XCTestCase {
    func testV23P04C13G01PreviewAliasAndConsolidationPlansPreserveCanonicalEvidenceAndHistory() throws {
        let f = try Fixture()
        let plans = try EntityIdentityResolutionActionV1.allCases.map { try f.plan(action: $0) }
        XCTAssertEqual(Set(plans.map(\.action)), Set(EntityIdentityResolutionActionV1.allCases))
        XCTAssertTrue(plans.allSatisfy { !$0.automaticMutation })
        XCTAssertTrue(plans.allSatisfy { $0.planSHA256.allSatisfy(\.isHexDigit) })
        let link = try f.alias(revision: 1)
        let receipt = try f.consolidation(revision: 1)
        XCTAssertEqual(link.alias.identity, f.source.identity)
        XCTAssertEqual(link.canonicalEntity.identity, f.survivor.identity)
        XCTAssertTrue(link.aliasSHA256.allSatisfy(\.isHexDigit))
        XCTAssertEqual(receipt.inventory.items.map(\.family), EntityConsolidationInventoryFamilyV1.allCases)
        XCTAssertTrue(receipt.inventory.items.first { $0.family == .relationship }!.relationshipIsEvidenceOnly)
        XCTAssertEqual(receipt.source, f.source)
        XCTAssertEqual(receipt.survivor, f.survivor)
        XCTAssertFalse(EntityIdentityResolutionLifecycleV1.plansAndPreviewsArePersistent)
        XCTAssertFalse(EntityIdentityResolutionLifecycleV1.automaticMutation)
    }

    func testV23P04C13A01ExplicitSingleWriterAliasAndSuccessorReversalReceiptsUseExactRevision() throws {
        let f = try Fixture()
        let h = try C13Harness(f)
        let first = try f.consolidation(revision: 1)
        let successor = try f.consolidation(revision: 2, predecessor: first, disposition: .reversedBySuccessor, mutation: 31)
        XCTAssertNotEqual(first.consolidationReceiptID, successor.consolidationReceiptID)
        XCTAssertEqual(successor.supersedesReceiptID, first.consolidationReceiptID)
        XCTAssertEqual(successor.predecessorSHA256, first.receiptSHA256)
        XCTAssertTrue(successor.reversal)
        XCTAssertEqual(EntityIdentityResolutionLifecycleV1.canonicalWriter, "WorkspaceWriterV1")
        XCTAssertEqual(EntityIdentityResolutionLifecycleV1.writersPerWorkspaceGeneration, 1)
        XCTAssertThrowsError(try f.consolidation(revision: 2, predecessor: first, disposition: .reversedBySuccessor), "receipt ID and mutation ID reuse fails")
        let firstAlias = try f.alias(revision: 1, mutation: 21)
        let successorAlias = try f.alias(revision: 2, predecessor: firstAlias, mutation: 22)
        XCTAssertNotEqual(firstAlias.linkEventID, successorAlias.linkEventID)
        XCTAssertEqual(successorAlias.supersedesLinkEventID, firstAlias.linkEventID)
        XCTAssertThrowsError(try f.alias(revision: 2, predecessor: firstAlias, mutation: 21), "alias event ID and mutation ID reuse fails")
        let rootCommand = try h.command(payload: .consolidation(first, nil))
        XCTAssertEqual(try h.writer.commitEntityIdentityResolution(rootCommand).resultingWorkspaceRevision, 1)
        let successorCommand = try h.command(payload: .consolidation(successor, first))
        XCTAssertEqual(try h.writer.commitEntityIdentityResolution(successorCommand).resultingWorkspaceRevision, 2)
        XCTAssertEqual(try h.writer.commitEntityIdentityResolution(successorCommand), try h.writer.commitEntityIdentityResolution(successorCommand))
        guard case let .consolidationHistory(history) = try h.writer.entityIdentityResolutionQuery(.init(workspaceID: f.workspaceID, target: .consolidationHistory(first.consolidationReceiptID))) else { return XCTFail("expected consolidation history") }
        XCTAssertEqual(history.map(\.consolidationReceiptID), [first.consolidationReceiptID, successor.consolidationReceiptID])
        XCTAssertEqual(try h.context.fetch(FetchDescriptor<EntityConsolidationReceiptRowV1>()).count, 2)
    }

    func testV23P04C13H01CrossWorkspaceReuseStalePlanHistoryRewriteAndAutomaticMutationFailClosed() throws {
        let f = try Fixture()
        let other = WorkspaceID(rawValue: f.id(90))
        let foreign = try EntityIdentitySnapshotV1(workspaceID: other, identity: f.source.identity, revision: 1, entitySHA256: f.hash(90))
        XCTAssertThrowsError(try EntityAliasLinkV1(linkEventID: f.id(91), workspaceID: f.workspaceID, alias: foreign,
            canonicalEntity: f.survivor, revision: 1, reason: .verifiedPriorAlias, policyVersion: 1,
            policySHA256: f.hash(91), recordedBy: f.actor, recordedAt: f.date, mutationID: try f.mutation(91)))
        let first = try f.alias(revision: 1)
        XCTAssertThrowsError(try EntityAliasLinkV1(linkEventID: f.id(92), workspaceID: f.workspaceID, alias: f.source,
            canonicalEntity: f.survivor, revision: 2, predecessor: first, reason: .verifiedPriorAlias, policyVersion: 1,
            policySHA256: f.hash(92), recordedBy: f.actor, recordedAt: f.date, mutationID: try f.mutation(92)))
        var mismatchedBases = try EntityConsolidationInventoryFamilyV1.allCases.map {
            try EntityConsolidationInventoryFamilyManifestBasisV1(workspaceID: f.workspaceID, source: f.source, survivor: f.survivor,
                family: $0, atoms: f.atomsByFamily[$0] ?? [])
        }
        mismatchedBases[1] = try EntityConsolidationInventoryFamilyManifestBasisV1(workspaceID: f.workspaceID, source: f.source, survivor: f.survivor,
            family: .evidence, atoms: [try .init(kind: "evidence", itemID: "forged-evidence", revision: 1, itemSHA256: f.hash(94), associationRole: "evidence-only")])
        XCTAssertThrowsError(try f.inventory.validate(against: mismatchedBases))
        XCTAssertFalse(EntityIdentityResolutionLifecycleV1.automaticMutation)
        XCTAssertFalse(EntityIdentityResolutionLifecycleV1.createsSecondStore)
    }

    func testV23P04C13I01InterruptedEffectBeforeReceiptRecoveryNeverDuplicatesIdentityConsolidation() throws {
        let f = try Fixture()
        let effect = try f.consolidation(revision: 1, mutation: 40)
        let command = try f.command(effect: effect, mutation: 40)
        let awaiting = try EntityIdentityResolutionMutationReceiptV1(receiptID: f.id(41), command: command,
            resultingWorkspaceRevision: 2, recoveryState: .effectCommittedAwaitingReceipt, committedAt: f.date)
        let committed = try EntityIdentityResolutionMutationReceiptV1(receiptID: f.id(42), command: command,
            resultingWorkspaceRevision: 2, recoveryState: .receiptCommitted, committedAt: f.date)
        XCTAssertEqual(awaiting.mutationID, effect.mutationID)
        XCTAssertEqual(committed.mutationID, effect.mutationID)
        XCTAssertEqual(awaiting.semanticSHA256s, [effect.receiptSHA256])
        XCTAssertEqual(committed.semanticSHA256s, [effect.receiptSHA256])
        XCTAssertEqual(awaiting.priorWorkspaceRevision, command.expectedRevision.workspaceRevision)
        let h = try C13Harness(f, failure: .afterEffectBeforeReceipt)
        let durableCommand = try h.command(payload: .consolidation(effect, nil))
        XCTAssertThrowsError(try h.writer.commitEntityIdentityResolution(durableCommand))
        try MutationReceiptRecoveryServiceV1(store: h.journal).recoverBeforeWriterActivation()
        let recovered = try h.writer.commitEntityIdentityResolution(durableCommand)
        let pairs = try h.journal.entityIdentityResolutionRecoveryPairs().filter { $0.command.mutationID == durableCommand.mutationID }
        XCTAssertEqual(pairs.count, 1); XCTAssertEqual(pairs.first?.receipt, recovered)
        XCTAssertEqual(try h.context.fetch(FetchDescriptor<EntityConsolidationReceiptRowV1>()).count, 1)
        XCTAssertEqual(try h.context.fetch(FetchDescriptor<EntityIdentityResolutionMutationReceiptRowV1>()).count, 1)
    }

    func testV23P04C13R01RestoreReplayRebuildsAliasesConsolidationReceiptsAndEvidenceOnlyRelationships() throws {
        let f = try Fixture()
        let h = try C13Harness(f)
        let alias = try f.alias(revision: 1, mutation: 50)
        let consolidation = try f.consolidation(revision: 1, mutation: 51)
        let backupAliasCommand = try f.command(effect: alias, mutation: 50)
        let backupConsolidationCommand = try f.command(effect: consolidation, mutation: 51)
        let snapshot = try EntityIdentityResolutionBackupSnapshotV1(workspaceID: f.workspaceID, generationID: f.generationID,
            aliasLinks: [alias], consolidationReceipts: [consolidation], mutationReceipts: [
                try .init(receiptID: f.id(52), command: backupAliasCommand, resultingWorkspaceRevision: 2, recoveryState: .receiptCommitted, committedAt: f.date),
                try .init(receiptID: f.id(53), command: backupConsolidationCommand, resultingWorkspaceRevision: 2, recoveryState: .receiptCommitted, committedAt: f.date)
            ])
        let data = try JSONEncoder().encode(snapshot)
        let replayed = try JSONDecoder().decode(EntityIdentityResolutionBackupSnapshotV1.self, from: data)
        XCTAssertEqual(replayed, snapshot)
        XCTAssertEqual(replayed.aliasLinks.count, 1)
        XCTAssertEqual(replayed.consolidationReceipts.count, 1)
        XCTAssertTrue(replayed.consolidationReceipts[0].inventory.items.first { $0.family == .relationship }!.relationshipIsEvidenceOnly)
        XCTAssertEqual(Set(replayed.mutationReceipts.map(\.mutationID)), Set([alias.mutationID, consolidation.mutationID]))
        let aliasCommand = try h.command(payload: .alias(alias, nil))
        _ = try h.writer.commitEntityIdentityResolution(aliasCommand)
        let consolidationCommand = try h.command(payload: .consolidation(consolidation, nil))
        _ = try h.writer.commitEntityIdentityResolution(consolidationCommand)
        let persisted = try h.lifecycle.backup()
        try h.lifecycle.replaceRestore(persisted, commands: [alias.mutationID: aliasCommand, consolidation.mutationID: consolidationCommand])
        XCTAssertEqual(try h.lifecycle.backup(), persisted)
        guard case let .aliases(rebuiltAliases) = try h.lifecycle.rebuild(.init(workspaceID: f.workspaceID, target: .aliases(f.source.identity))),
              case let .consolidationHistory(replayedHistory) = try h.lifecycle.query(.init(workspaceID: f.workspaceID, target: .consolidationHistory(consolidation.consolidationReceiptID)))
        else { return XCTFail("expected restored C13 query histories") }
        XCTAssertEqual(rebuiltAliases, [alias]); XCTAssertEqual(replayedHistory, [consolidation])
        XCTAssertEqual(try h.lifecycle.replay(consolidationCommand), try XCTUnwrap(h.writer.entityIdentityResolutionReceipt(for: consolidationCommand)))
    }
}

private struct Fixture {
    let workspaceID: WorkspaceID
    let generationID: UUID
    let date: Date
    let actor: ActorSnapshotV1
    let source: EntityIdentitySnapshotV1
    let survivor: EntityIdentitySnapshotV1
    let atomsByFamily: [EntityConsolidationInventoryFamilyV1: [EntityConsolidationInventoryAtomV1]]
    let inventory: EntityConsolidationInventoryV1

    init() throws {
        let workspace = WorkspaceID(rawValue: UUID(uuid: (1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1)))
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        let operatorSnapshot = try ActorSnapshotV1(snapshotID: Self.fixedID(3), workspaceID: workspace,
            actor: try LocalActorReferenceV1(actorReferenceID: Self.fixedID(4), workspaceID: workspace, displayName: "Operator"),
            responsibility: .recordedBy, displayNameAtTime: "Operator", capturedAt: now)
        let sourceSnapshot = try EntityIdentitySnapshotV1(workspaceID: workspace,
            identity: try .init(kind: .asset, id: Self.fixedID(5)), revision: 1, entitySHA256: Self.fixedHash(5))
        let survivorSnapshot = try EntityIdentitySnapshotV1(workspaceID: workspace,
            identity: try .init(kind: .asset, id: Self.fixedID(6)), revision: 1, entitySHA256: Self.fixedHash(6))
        let atoms = try Dictionary(uniqueKeysWithValues: EntityConsolidationInventoryFamilyV1.allCases.enumerated().map { offset, family in
            let values: [EntityConsolidationInventoryAtomV1]
            switch family {
            case .tombstone, .mutationReceipt: values = []
            default: values = [try .init(kind: family.rawValue.lowercased(), itemID: "item-\(offset)", revision: 1,
                itemSHA256: Self.fixedHash(offset + 10), associationRole: family == .relationship ? "evidence-only" : "preserve")]
            }
            return (family, values)
        })
        self.workspaceID = workspace
        generationID = UUID(uuid: (2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2))
        date = now
        actor = operatorSnapshot
        source = sourceSnapshot
        survivor = survivorSnapshot
        atomsByFamily = atoms
        inventory = try EntityConsolidationInventoryBuilderV1.inventory(workspaceID: workspace, source: sourceSnapshot, survivor: survivorSnapshot, atomsByFamily: atoms)
    }

    static func fixedID(_ n: UInt8) -> UUID { UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, n)) }
    static func fixedHash(_ n: Int) -> String { String(format: "%064x", n) }
    func id(_ n: UInt8) -> UUID { Self.fixedID(n) }
    func hash(_ n: Int) -> String { Self.fixedHash(n) }
    func mutation(_ n: UInt8) throws -> MutationIDV1 { try .init(rawValue: id(n)) }
    func alias(revision: UInt64, predecessor: EntityAliasLinkV1? = nil, mutation: UInt8 = 20) throws -> EntityAliasLinkV1 {
        try .init(linkEventID: id(mutation), workspaceID: workspaceID, alias: source, canonicalEntity: survivor, revision: revision,
            predecessor: predecessor, reason: .verifiedPriorAlias, policyVersion: 1, policySHA256: hash(Int(mutation)), recordedBy: actor, recordedAt: date, mutationID: try self.mutation(mutation))
    }
    func consolidation(revision: UInt64, predecessor: EntityConsolidationReceiptV1? = nil,
                       disposition: EntityConsolidationDispositionV1 = .consolidated, mutation: UInt8 = 30) throws -> EntityConsolidationReceiptV1 {
        try .init(consolidationReceiptID: id(mutation), workspaceID: workspaceID, source: source, survivor: survivor, inventory: inventory,
            disposition: disposition, revision: revision, predecessor: predecessor, policyVersion: 1, policySHA256: hash(Int(mutation)),
            recordedBy: actor, recordedAt: date, mutationID: try self.mutation(mutation))
    }
    func command(effect: EntityConsolidationReceiptV1, mutation: UInt8) throws -> EntityIdentityResolutionMutationCommandV1 {
        let revision = try WorkspaceRevisionV1(workspaceID: workspaceID, generationID: generationID, writerInstanceID: id(70), revision: 1, entityRevisions: [])
        return try .init(commandID: id(mutation + 60), workspaceID: workspaceID, expectedRevision: .init(snapshot: revision), mutationID: try self.mutation(mutation), payload: .consolidation(effect, nil), submittedAt: date)
    }
    func command(effect: EntityAliasLinkV1, mutation: UInt8) throws -> EntityIdentityResolutionMutationCommandV1 {
        let revision = try WorkspaceRevisionV1(workspaceID: workspaceID, generationID: generationID, writerInstanceID: id(70), revision: 1, entityRevisions: [])
        return try .init(commandID: id(mutation + 60), workspaceID: workspaceID, expectedRevision: .init(snapshot: revision), mutationID: try self.mutation(mutation), payload: .alias(effect, nil), submittedAt: date)
    }
    func plan(action: EntityIdentityResolutionActionV1) throws -> EntityIdentityResolutionPlanV1 {
        let candidates = try [
            EntityIdentityResolutionCandidateV1(snapshot: source, reasons: [.verifiedPriorAlias]),
            EntityIdentityResolutionCandidateV1(snapshot: survivor, reasons: [.verifiedSerialOrTag])
        ].sorted { $0.snapshot.stableKey < $1.snapshot.stableKey }
        let selected: EntityIdentitySnapshotV1? = (action == .linkAlias || action == .consolidate) ? candidates[0].snapshot : nil
        return try .init(planID: id(UInt8(80 + action.allCasesIndex)), workspaceID: workspaceID,
            source: .init(workspaceID: workspaceID, sourceBatchID: id(81), artifactID: id(82), artifactRevision: 1, artifactSHA256: hash(82)),
            expectedWorkspaceRevision: 1, policyVersion: 1, policySHA256: hash(83), candidates: candidates, action: action,
            selectedCandidate: selected, reasons: [.explicitOperatorDecision], createdBy: actor, createdAt: date, expiresAt: date.addingTimeInterval(60))
    }
}

private extension EntityIdentityResolutionActionV1 {
    var allCasesIndex: Int { EntityIdentityResolutionActionV1.allCases.firstIndex(of: self)! }
}

private struct C13Clock: ApplicationClock { func now() -> Date { Date(timeIntervalSinceReferenceDate: 1_000) } }
private struct C13IDs: ApplicationIDSource { func makeID() -> UUID { UUID() } }
private struct C13Files: ApplicationFileAuthorityV1 {
    func temporaryRelativePath(mutationID: MutationIDV1, component: String) throws -> String {
        "mutation-staging/\(mutationID.rawValue.uuidString.lowercased())/\(component)"
    }
}

private final class C13Authority: EntityIdentityResolutionCanonicalSourceResolvingV1 {
    let source: EntityIdentityResolutionCanonicalSourceV1
    let survivor: EntityIdentityResolutionCanonicalSourceV1
    let atomsByFamily: [EntityConsolidationInventoryFamilyV1: [EntityConsolidationInventoryAtomV1]]
    init(_ f: Fixture) throws {
        source = try .init(snapshot: f.source, inventory: f.inventory)
        survivor = try .init(snapshot: f.survivor, inventory: f.inventory)
        atomsByFamily = f.atomsByFamily
    }
    func resolveEntityIdentity(_ identity: WorkspaceEntityIdentityV1, workspaceID: WorkspaceID, revision: UInt64) throws -> EntityIdentitySnapshotV1 {
        try resolve(workspaceID: workspaceID, entityID: identity, expectedRevision: revision).snapshot
    }
    func aliasPath(from alias: WorkspaceEntityIdentityV1, workspaceID: WorkspaceID) throws -> [WorkspaceEntityIdentityV1] {
        guard workspaceID == source.snapshot.workspaceID else { throw EntityIdentityResolutionFailureV1.wrongWorkspace }
        return []
    }
    func canonicalConsolidationAtoms(source: EntityIdentitySnapshotV1, survivor: EntityIdentitySnapshotV1, family: EntityConsolidationInventoryFamilyV1) throws -> [EntityConsolidationInventoryAtomV1] {
        guard source == self.source.snapshot, survivor == self.survivor.snapshot else { throw EntityIdentityResolutionFailureV1.incompleteInventory }
        return atomsByFamily[family] ?? []
    }
    func resolve(workspaceID: WorkspaceID, entityID: WorkspaceEntityIdentityV1, expectedRevision: UInt64) throws -> EntityIdentityResolutionCanonicalSourceV1 {
        let value = entityID == source.snapshot.identity ? source : (entityID == survivor.snapshot.identity ? survivor : nil)
        guard let value, value.snapshot.workspaceID == workspaceID, value.snapshot.revision == expectedRevision else { throw EntityIdentityResolutionFailureV1.staleRevision }
        return value
    }
}

@MainActor
private final class C13Harness {
    let context: ModelContext
    let writer: WorkspaceWriterV1
    let journal: MutationJournalStoreV1
    let lifecycle: EntityIdentityResolutionLifecycleAdapterV1
    let fixture: Fixture
    init(_ fixture: Fixture, failure: MutationJournalFaultBoundaryV1? = nil) throws {
        let schema = Schema(PersistentSchemaV50.models, version: PersistentSchemaV50.versionIdentifier)
        let container = try ModelContainer(for: schema, migrationPlan: nil, configurations: [ModelConfiguration("C13", schema: schema, isStoredInMemoryOnly: true, allowsSave: true, cloudKitDatabase: .none)])
        let context = container.mainContext; context.autosaveEnabled = false
        let replica = try WorkspaceReplicaIdentityV1(workspaceID: fixture.workspaceID, replicaID: ReplicaID(rawValue: fixture.id(101)))
        let journal = try MutationJournalStoreV1(modelContext: context, identity: replica, generationID: fixture.generationID,
            failureInjection: failure.map { .init(failOnceAt: $0) })
        self.context = context; self.journal = journal; self.fixture = fixture
        let authority = try C13Authority(fixture)
        let canonicalWriter = try WorkspaceWriterV1(identity: replica, generationID: fixture.generationID,
            initialRevision: journal.currentRevision(writerInstanceID: fixture.id(102)), clock: C13Clock(), idSource: C13IDs(), fileAuthority: C13Files(),
            adapter: WorkspaceWriterAdapterV1(modelContext: context, entityIdentityCanonicalResolver: authority), journalStore: journal)
        writer = canonicalWriter
        lifecycle = EntityIdentityResolutionLifecycleAdapterV1(modelContext: context, workspaceID: fixture.workspaceID, resolver: authority, workspaceWriter: canonicalWriter)
    }
    func command(payload: EntityIdentityResolutionMutationPayloadV1) throws -> EntityIdentityResolutionMutationCommandV1 {
        let mutation = payload.mutationID
        return try .init(commandID: UUID(), workspaceID: fixture.workspaceID, expectedRevision: .init(snapshot: try writer.currentRevision()), mutationID: mutation, payload: payload, submittedAt: fixture.date)
    }
}

import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

@MainActor
final class V23OperationalContactImportAuthorityTests: XCTestCase {
    func testOrdinaryReceiptBackedPartyIsReadableWithoutProjectionOrMutation() async throws {
        let fixture = try ContactImportAuthorityFixture()
        let revisions = try fixture.context.fetch(FetchDescriptor<EntityMutationRevisionRow>())
        XCTAssertEqual(revisions.count, 1)
        XCTAssertNil(try XCTUnwrap(revisions.first).externalProjectionSHA256)
        let before = try fixture.writer.currentRevision()
        let receiptBytes = try fixture.context.fetch(FetchDescriptor<MutationReceiptRow>()).map(\.receiptData)

        let state = try await fixture.query.currentImportState(
            workspaceID: fixture.party.workspaceID, partyIDs: [fixture.party.partyID]
        )

        XCTAssertEqual(state.parties, [fixture.party])
        XCTAssertTrue(state.contacts.isEmpty)
        XCTAssertEqual(try fixture.writer.currentRevision(), before)
        XCTAssertEqual(try fixture.context.fetch(FetchDescriptor<MutationReceiptRow>()).map(\.receiptData), receiptBytes)
        XCTAssertFalse(fixture.context.hasChanges)
        try fixture.journal.validateAll()
    }

    func testMissingCommittedReceiptRefusesOtherwisePresentParty() async throws {
        let fixture = try ContactImportAuthorityFixture()
        let row = try XCTUnwrap(fixture.context.fetch(FetchDescriptor<MutationReceiptRow>()).first)
        fixture.context.delete(row)
        try fixture.context.save() // Deliberately corrupt this isolated in-memory store.
        XCTAssertEqual(try fixture.context.fetch(FetchDescriptor<ServicePartyRow>()).count, 1)
        try await assertRefuses(fixture)
        XCTAssertTrue(try fixture.context.fetch(FetchDescriptor<MutationReceiptRow>()).isEmpty)
        XCTAssertFalse(fixture.context.hasChanges)
    }

    func testAlteredReceiptDigestRefusesWithoutRepair() async throws {
        let fixture = try ContactImportAuthorityFixture()
        let row = try XCTUnwrap(fixture.context.fetch(FetchDescriptor<MutationReceiptRow>()).first)
        let hostile = String(repeating: "f", count: 64)
        XCTAssertNotEqual(row.receiptSHA256, hostile)
        row.receiptSHA256 = hostile
        try fixture.context.save()
        try await assertRefuses(fixture)
        XCTAssertEqual(row.receiptSHA256, hostile)
        XCTAssertFalse(fixture.context.hasChanges)
    }

    func testWrongExternalProjectionRefusesWithoutRepair() async throws {
        let fixture = try ContactImportAuthorityFixture()
        let row = try XCTUnwrap(fixture.context.fetch(FetchDescriptor<EntityMutationRevisionRow>()).first)
        XCTAssertNil(row.externalProjectionSHA256)
        let hostile = String(repeating: "e", count: 64)
        row.externalProjectionSHA256 = hostile
        try fixture.context.save()
        try await assertRefuses(fixture)
        XCTAssertEqual(row.externalProjectionSHA256, hostile)
        XCTAssertFalse(fixture.context.hasChanges)
    }

    func testDirtyContextRefusesWithoutSavingOrRollingBackCallerChanges() async throws {
        let fixture = try ContactImportAuthorityFixture()
        let row = try XCTUnwrap(fixture.context.fetch(FetchDescriptor<WorkspaceMutationStateRow>()).first)
        let previous = row.workspaceRevision
        row.workspaceRevision += 1
        XCTAssertTrue(fixture.context.hasChanges)
        try await assertRefuses(fixture)
        XCTAssertTrue(fixture.context.hasChanges)
        XCTAssertEqual(row.workspaceRevision, previous + 1)
    }

    func testMissingCheckpointRefusesWithoutBootstrappingIt() async throws {
        let fixture = try ContactImportAuthorityFixture()
        let row = try XCTUnwrap(fixture.context.fetch(FetchDescriptor<WorkspaceMutationStateRow>()).first)
        XCTAssertNotNil(row.mutableSemanticSHA256)
        row.mutableSemanticSHA256 = nil
        try fixture.context.save()
        try await assertRefuses(fixture)
        XCTAssertNil(row.mutableSemanticSHA256)
        XCTAssertFalse(fixture.context.hasChanges)
    }

    private func assertRefuses(
        _ fixture: ContactImportAuthorityFixture,
        file: StaticString = #filePath, line: UInt = #line
    ) async throws {
        do {
            _ = try await fixture.query.currentImportState(
                workspaceID: fixture.party.workspaceID, partyIDs: [fixture.party.partyID]
            )
            XCTFail("Unauthenticated current import state was accepted", file: file, line: line)
        } catch {
            // Refusal is the contract; neither a repair nor a new mutation is permitted.
        }
    }
}

@MainActor
private final class ContactImportAuthorityFixture {
    let container: ModelContainer
    let context: ModelContext
    let journal: MutationJournalStoreV1
    let writer: WorkspaceWriterV1
    let party: ServicePartyReferenceV1
    let query: OperationalContactRowQueryV1

    init() throws {
        let schema = Schema(PersistentSchemaV53.models, version: PersistentSchemaV53.versionIdentifier)
        container = try ModelContainer(for: schema, migrationPlan: nil, configurations: [
            ModelConfiguration("ContactImportAuthority", schema: schema,
                isStoredInMemoryOnly: true, allowsSave: true, cloudKitDatabase: .none)
        ])
        context = container.mainContext
        context.autosaveEnabled = false
        let workspaceID = C46OperationalContactTestSupport.workspace(460_001)
        let identity = try WorkspaceReplicaIdentityV1(
            workspaceID: workspaceID,
            replicaID: ReplicaID(rawValue: C46OperationalContactTestSupport.id(460_002))
        )
        let generationID = C46OperationalContactTestSupport.id(460_003)
        journal = try MutationJournalStoreV1(modelContext: context, identity: identity,
            generationID: generationID)
        writer = try WorkspaceWriterV1(identity: identity, generationID: generationID,
            initialRevision: journal.currentRevision(writerInstanceID: C46OperationalContactTestSupport.id(460_004)),
            clock: ContactImportAuthorityClock(), idSource: ContactImportAuthorityIDSource(),
            fileAuthority: ContactImportAuthorityFileAuthority(),
            adapter: WorkspaceWriterAdapterV1(modelContext: context), journalStore: journal)
        party = try C46OperationalContactTestSupport.party(slot: 460_010, workspaceID: workspaceID)
        _ = try writer.execute(.applyPartyAccountability(.recordParty(party)), mutationID: party.mutationID)
        try journal.validateAll()
        query = OperationalContactRowQueryV1(modelContext: context, workspaceID: workspaceID)
    }
}

private struct ContactImportAuthorityClock: ApplicationClock {
    func now() -> Date { C46OperationalContactTestSupport.date(460_020) }
}

private struct ContactImportAuthorityIDSource: ApplicationIDSource {
    func makeID() -> UUID { C46OperationalContactTestSupport.id(460_004) }
}

private struct ContactImportAuthorityFileAuthority: ApplicationFileAuthorityV1 {
    func temporaryRelativePath(mutationID: MutationIDV1, component: String) throws -> String {
        "contact-import-authority/\(mutationID.rawValue.uuidString.lowercased())/\(component)"
    }
}

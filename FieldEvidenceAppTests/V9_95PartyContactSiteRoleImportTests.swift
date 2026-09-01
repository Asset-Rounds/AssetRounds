import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

private struct C32Corpus: Decodable {
    struct Selector: Decodable { let id: String; let selector: String; let tier: String }
    struct Expected: Decodable {
        let atomicity: String
        let contactDefaultExportEnabled: Bool
        let fuzzyMatching: Bool
        let oneCanonicalWriter: Bool
        let previewWritesCanonicalState: Bool
        let scratchRetainedAfterTerminalState: Bool
        let sourceOrder: [String]
    }
    let cardID: String
    let expected: Expected
    let ordinal: Int
    let schema: String
    let schemaVersion: Int
    let selectors: [Selector]
}

private enum C32 {
    static let instant = Date(timeIntervalSince1970: 2_240_000_000)
    static let sourceDigest = String(repeating: "a", count: 64)
    static let revisionDigest = String(repeating: "b", count: 64)

    static func id(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "32000000-0000-4000-8000-%012x", value))!
    }

    static func mutation(_ value: Int) throws -> MutationIDV1 {
        try MutationIDV1(rawValue: id(value))
    }
}

private struct C32Clock: ApplicationClock { func now() -> Date { C32.instant } }
private struct C32IDSource: ApplicationIDSource { func makeID() -> UUID { C32.id(900) } }
private struct C32FileAuthority: ApplicationFileAuthorityV1 {
    func temporaryRelativePath(mutationID: MutationIDV1, component: String) throws -> String {
        "c32/\(mutationID.rawValue.uuidString.lowercased())/\(component)"
    }
}

private struct C32RejectingMaterializer: ImportWorkspaceCommandMaterializingV1 {
    func materialize(_ context: ImportCommandMaterializationContextV1) throws -> WorkspaceMutationRequestV1 {
        throw ImportBulkFailureV1.unsupportedSchema
    }
}

private final class C32ScratchRecorder: PartyContactSiteRoleImportScratchDiscardingV1, @unchecked Sendable {
    private(set) var discardedLeaseIDs: [UUID] = []
    func discard(leaseIDs: [UUID]) throws { discardedLeaseIDs = leaseIDs }
}

@MainActor private final class C32Store {
    let context: ModelContext
    let writer: WorkspaceWriterV1
    let lifecycle: ImportBulkLifecycleAdapterV1
    let journal: MutationJournalStoreV1
    let workspaceID: WorkspaceID
    let siteIDs: [UUID]

    init() throws {
        let models = PersistentSchemaV45.models + [
            ImportMappingProfileRowV1.self,
            BulkSessionRowV1.self,
            BulkCommitReceiptRowV1.self,
        ]
        let schema = Schema(models, version: PersistentSchemaV45.versionIdentifier)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: nil,
            configurations: [ModelConfiguration(
                "C32PartyContactSiteRoleImport",
                schema: schema,
                isStoredInMemoryOnly: true,
                allowsSave: true,
                cloudKitDatabase: .none
            )]
        )
        context = container.mainContext
        context.autosaveEnabled = false
        workspaceID = WorkspaceID(rawValue: C32.id(1))
        siteIDs = [C32.id(10), C32.id(11)]
        let generationID = C32.id(2)
        let identity = try WorkspaceReplicaIdentityV1(
            workspaceID: workspaceID,
            replicaID: ReplicaID(rawValue: C32.id(3))
        )
        journal = try MutationJournalStoreV1(
            modelContext: context,
            identity: identity,
            generationID: generationID
        )
        writer = try WorkspaceWriterV1(
            identity: identity,
            generationID: generationID,
            initialRevision: try journal.currentRevision(writerInstanceID: C32.id(4)),
            clock: C32Clock(),
            idSource: C32IDSource(),
            fileAuthority: C32FileAuthority(),
            adapter: WorkspaceWriterAdapterV1(modelContext: context),
            journalStore: journal
        )
        for (index, siteID) in siteIDs.enumerated() {
            let snapshot = try writer.currentRevision()
            _ = try writer.execute(WorkspaceMutationRequestV1(
                mutationID: try C32.mutation(20 + index),
                expectedRevision: .init(snapshot: snapshot),
                command: .createFirstSign(.init(
                    siteID: siteID,
                    newSite: .init(id: siteID, label: "C32 Site \(index + 1)", address: nil, timeZoneID: "UTC"),
                    assetID: C32.id(30 + index),
                    assetLabel: "C32 seed \(index + 1)",
                    packID: "c32.seed",
                    packSchemaVersion: 1,
                    packContentVersion: 1,
                    createdAt: C32.instant
                ))
            ))
        }
        lifecycle = try ImportBulkLifecycleAdapterV1(
            registrations: [try Self.registration()],
            modelContext: context
        )
    }

    func coordinator(
        prepared: PartyContactSiteRoleImportPreparedV1,
        scratch: any PartyContactSiteRoleImportScratchDiscardingV1
    ) throws -> PartyContactSiteRoleImportCoordinatorV1 {
        let registrations = try ImportCommandKindV1.allCases.map { kind in
            if kind == .applyAtomicWorkspaceBundle {
                return try PartyContactSiteRoleImportProductionRegistrationV1.make(prepared: prepared)
            }
            return try ImportBulkMaterializerRegistrationV1(
                kind: kind,
                materializer: C32RejectingMaterializer()
            )
        }
        return PartyContactSiteRoleImportCoordinatorV1(
            bulk: try ImportBulkCoordinatorV1(
                writer: writer,
                lifecycle: lifecycle,
                materializers: registrations
            ),
            scratch: scratch
        )
    }

    private static func registration() throws -> ImportAdapterRegistrationV1 {
        try ImportAdapterRegistrationV1(
            adapterID: "c32_party_contact_site_role",
            adapterVersion: 1,
            schemaReleaseID: "PARTY_CONTACT_SITE_ROLE_ATOMIC_V1",
            schemaRelease: 1,
            entityKinds: ImportEntityKindV1.allCases.sorted(),
            requiredSourceKeys: ["source_binding_sha256"],
            dependencyAdapterIDs: [],
            commandKinds: ImportCommandKindV1.allCases.sorted(),
            lifecycleDispositions: [
                .activeBulkSessionRecoverableOperationalState,
                .bulkCommitReceiptImmutableCanonicalAudit,
                .importedEntityUsesOrdinaryLifecycle,
            ],
            privacyClass: .localOperational,
            supportsDeterministicExport: true,
            fixtureSHA256s: [C32.sourceDigest]
        )
    }
}

@MainActor private func c32Prepared(_ store: C32Store) throws -> PartyContactSiteRoleImportPreparedV1 {
    let manifest = try PartyContactSiteRoleImportSourceManifestV1(
        workspaceID: store.workspaceID,
        files: [
            try .init(kind: .sitePartyRoles, fileName: "roles.csv", byteCount: 31, sha256: String(repeating: "c", count: 64), leaseID: C32.id(103)),
            try .init(kind: .parties, fileName: "parties.csv", byteCount: 29, sha256: C32.sourceDigest, leaseID: C32.id(101)),
            try .init(kind: .partyContacts, fileName: "contacts.csv", byteCount: 30, sha256: String(repeating: "d", count: 64), leaseID: C32.id(102)),
        ]
    )
    let snapshot = try store.writer.currentRevision()
    let partyIDs = [C32.id(200), C32.id(201)]
    let contactID = C32.id(210)
    let roleIDs = [C32.id(220), C32.id(221)]
    let pending = try [
        WorkspaceEntityRevisionV1(identity: .init(kind: .serviceParty, id: partyIDs[0]), revision: 0),
        WorkspaceEntityRevisionV1(identity: .init(kind: .serviceParty, id: partyIDs[1]), revision: 0),
        WorkspaceEntityRevisionV1(identity: .init(kind: .serviceContactPoint, id: contactID), revision: 0),
        WorkspaceEntityRevisionV1(identity: .init(kind: .sitePartyRoleEvent, id: roleIDs[0]), revision: 0),
        WorkspaceEntityRevisionV1(identity: .init(kind: .sitePartyRoleEvent, id: roleIDs[1]), revision: 0),
    ]
    let expected = try WorkspaceExpectedRevisionV1(
        workspaceID: snapshot.workspaceID,
        generationID: snapshot.generationID,
        writerInstanceID: snapshot.writerInstanceID,
        workspaceRevision: snapshot.revision,
        entityRevisions: snapshot.entityRevisions + pending
    )
    let partyRows = try partyIDs.enumerated().map { index, partyID in
        try PartyCSVRowV1(
            rowIndex: index + 1,
            partyID: partyID,
            kind: .organization,
            displayName: "Shared Party",
            profileDescriptor: "Operational import only",
            provenance: .importedExternalEvidence,
            state: .effective,
            effectiveAt: C32.instant,
            revision: 1
        )
    }
    let contactRows = [try PartyContactCSVRowV1(
        rowIndex: 1,
        contactPointID: contactID,
        partyID: partyIDs[0],
        kind: .email,
        label: .work,
        displayValue: "ops@example.test",
        preferred: true,
        effectiveAt: C32.instant,
        revision: 1
    )]
    let roleRows = try roleIDs.enumerated().map { index, roleID in
        try SitePartyRoleCSVRowV1(
            rowIndex: index + 1,
            eventID: roleID,
            siteID: store.siteIDs[index],
            partyID: partyIDs[0],
            role: .serviceProvider,
            effectiveFrom: C32.instant,
            source: .importedExternalEvidence,
            revision: 1,
            recordedAt: C32.instant
        )
    }
    let mutationID = try PartyContactSiteRoleImportPreparedV1.deterministicMutationID(
        sourceManifest: manifest,
        partyRows: partyRows,
        contactRows: contactRows,
        siteRoleRows: roleRows,
        expectedRevision: expected,
        workspaceRevisionSHA256: C32.revisionDigest,
        importedAt: C32.instant
    )
    let parties = try partyRows.map {
        try ServicePartyReferenceV1(
            partyID: $0.partyID, workspaceID: store.workspaceID, kind: $0.kind,
            displayName: $0.displayName, profileDescriptor: $0.profileDescriptor,
            provenance: $0.provenance, state: $0.state, effectiveAt: $0.effectiveAt,
            retiredAt: $0.retiredAt, revision: $0.revision, mutationID: mutationID
        )
    }
    let contacts = try contactRows.map { row in
        try ServiceContactPointV1(
            contactPointID: row.contactPointID, workspaceID: store.workspaceID,
            party: try XCTUnwrap(parties.first { $0.partyID == row.partyID }),
            kind: row.kind, label: row.label, displayValue: row.displayValue,
            preferred: row.preferred, provenance: .importedExternalEvidence,
            importSourceSetSHA256: try manifest.contactImportSourceSet().sourceSetSHA256,
            lifecycle: .effective, effectiveAt: row.effectiveAt, retiredAt: row.retiredAt,
            revision: row.revision, mutationID: mutationID
        )
    }
    let contactMutation = try OperationalContactMutationV1(
        workspaceID: store.workspaceID,
        mutationID: mutationID,
        expectedRevision: expected,
        successors: contacts,
        preferredScopes: [try .init(
            partyID: partyIDs[0], kind: .email, activeContactPointIDs: [contactID], preferredContactPointID: contactID
        )],
        importSourceSet: try manifest.contactImportSourceSet()
    )
    let roles = try roleRows.map {
        try SitePartyRoleEventV1(
            eventID: $0.eventID, workspaceID: store.workspaceID, siteID: $0.siteID,
            partyID: $0.partyID, role: $0.role, effectiveFrom: $0.effectiveFrom,
            effectiveUntil: $0.effectiveUntil, source: $0.source,
            supersedesEventID: $0.supersedesEventID, revision: $0.revision,
            mutationID: mutationID, recordedAt: $0.recordedAt
        )
    }
    let mutation = try PartyContactSiteRoleImportMutationV1(
        workspaceID: store.workspaceID,
        mutationID: mutationID,
        expectedRevision: expected,
        partyMutations: parties.map(PartyAccountabilityMutationV1.recordParty),
        operationalContactMutation: contactMutation,
        siteRoleMutations: roles.map(PartyAccountabilityMutationV1.appendSiteRole)
    )
    return try PartyContactSiteRoleImportPreparedV1(
        sourceManifest: manifest,
        partyRows: partyRows,
        contactRows: contactRows,
        siteRoleRows: roleRows,
        mutation: mutation,
        workspaceRevisionSHA256: C32.revisionDigest,
        importedAt: C32.instant
    )
}

@MainActor final class V9_95PartyContactSiteRoleImportTests: XCTestCase {
    func testV23P04C32G01PreviewFirstMultiFilePartyContactAndSiteRoleMigrationGolden() throws {
        let corpus = try loadCorpus(); check(corpus, "G01", "GOLDEN")
        let store = try C32Store(); let prepared = try c32Prepared(store)
        let scratch = C32ScratchRecorder(); let coordinator = try store.coordinator(prepared: prepared, scratch: scratch)
        XCTAssertEqual(prepared.sourceManifest.files.map(\.kind), [.parties, .partyContacts, .sitePartyRoles])
        XCTAssertEqual(prepared.preview.bulkPlan.atomicity, .allOrNothing)
        XCTAssertFalse(prepared.preview.importPlan.previewWritesCanonicalState)
        XCTAssertFalse(prepared.defaultContactExportEnabled)
        let before = try store.writer.currentRevision()
        XCTAssertEqual(try coordinator.preview(prepared, currentSourceSHA256: prepared.preview.importPlan.source.sourceSHA256, currentWorkspaceRevisionSHA256: C32.revisionDigest), prepared.preview)
        XCTAssertEqual(try store.writer.currentRevision(), before)
        XCTAssertEqual(prepared.dispositions.map(\.group), [.parties, .parties, .contacts, .siteRoles, .siteRoles])
    }

    func testV23P04C32A01ExplicitKeyBindingSharedRoleCorrectionAndReversalAlternate() throws {
        let corpus = try loadCorpus(); check(corpus, "A01", "ALTERNATE")
        let store = try C32Store(); let prepared = try c32Prepared(store)
        XCTAssertEqual(prepared.dispositions.filter { $0.group == .siteRoles }.count, 2)
        XCTAssertEqual(Set(prepared.dispositions.filter { $0.group == .siteRoles }.map(\.stableID)).count, 2)
        XCTAssertTrue(prepared.dispositions.allSatisfy { $0.reason == .exactStableKeyCreate })
        XCTAssertTrue(PartyContactsCSVContractV1.correctionFields.contains("displayValue"))
        XCTAssertTrue(SitePartyRolesCSVContractV1.correctionFields.contains("effectiveUntil"))
        XCTAssertFalse(PartyContactsCSVContractV1.defaultExportEnabled)
        XCTAssertThrowsError(try PartyContactSiteRoleImportPreparedV1(
            sourceManifest: prepared.sourceManifest,
            partyRows: [], contactRows: [], siteRoleRows: [], mutation: prepared.mutation,
            workspaceRevisionSHA256: C32.revisionDigest, importedAt: C32.instant
        ))
    }

    func testV23P04C32H01HostileIdentityUnicodeFormulaAndBudgetFailClosed() throws {
        let corpus = try loadCorpus(); check(corpus, "H01", "HOSTILE")
        let store = try C32Store(); let prepared = try c32Prepared(store)
        XCTAssertThrowsError(try PartyContactSiteRoleImportSourceManifestV1(
            workspaceID: store.workspaceID,
            files: [try .init(kind: .parties, fileName: "bad\u{202e}.csv", byteCount: 1, sha256: C32.sourceDigest, leaseID: C32.id(501))]
        ))
        XCTAssertThrowsError(try PartyCSVRowV1(rowIndex: 1, partyID: C32.id(502), kind: .person, displayName: "unsafe\u{202e}", provenance: .locallyRecorded, state: .effective, effectiveAt: C32.instant, revision: 1))
        XCTAssertThrowsError(try PartyCSVRowV1(rowIndex: 1, partyID: C32.id(505), kind: .person, displayName: "cafe\u{0301}", provenance: .locallyRecorded, state: .effective, effectiveAt: C32.instant, revision: 1))
        XCTAssertThrowsError(try PartyContactCSVRowV1(rowIndex: 1, contactPointID: C32.id(503), partyID: C32.id(504), kind: .email, label: .work, displayValue: "a\u{0000}@example.test", preferred: false, effectiveAt: C32.instant, revision: 1))
        let exportSchema = try ExportSchemaReleaseV1(
            releaseID: "c32_formula_safe", release: 1,
            importSchema: prepared.preview.importPlan.schemaRelease,
            expectedRevisionColumn: "expected_revision"
        )
        let formulaExport = try DeterministicCSVExportV1(
            exportID: C32.id(506), workspaceID: store.workspaceID, kind: .inventory,
            exportSchema: exportSchema, rowCount: 1,
            bytes: Data("source_binding_sha256,expected_revision\\n'=1+1,0\\n".utf8)
        )
        XCTAssertTrue(formulaExport.formulaAndControlPrefixesNeutralized)
        XCTAssertThrowsError(try PartyContactSiteRoleImportPreparedV1(
            sourceManifest: prepared.sourceManifest,
            partyRows: [], contactRows: [], siteRoleRows: [], mutation: prepared.mutation,
            workspaceRevisionSHA256: String(repeating: "f", count: 64), importedAt: C32.instant
        ))
        let coordinator = try store.coordinator(prepared: prepared, scratch: C32ScratchRecorder())
        XCTAssertThrowsError(try coordinator.preview(prepared, currentSourceSHA256: String(repeating: "f", count: 64), currentWorkspaceRevisionSHA256: C32.revisionDigest))
        XCTAssertThrowsError(try coordinator.preview(prepared, currentSourceSHA256: prepared.preview.importPlan.source.sourceSHA256, currentWorkspaceRevisionSHA256: String(repeating: "f", count: 64)))
    }

    func testV23P04C32I01CancellationChunkInterruptionAndRestoreNoPartialClaim() throws {
        let corpus = try loadCorpus(); check(corpus, "I01", "INTERRUPTION")
        let store = try C32Store(); let prepared = try c32Prepared(store); let scratch = C32ScratchRecorder()
        let coordinator = try store.coordinator(prepared: prepared, scratch: scratch)
        let begun = try coordinator.begin(sessionID: C32.id(600), prepared: prepared, currentSourceSHA256: prepared.preview.importPlan.source.sourceSHA256, currentWorkspaceRevisionSHA256: C32.revisionDigest)
        let cancelled = try coordinator.commitOrResume(session: begun, prepared: prepared, currentSourceSHA256: prepared.preview.importPlan.source.sourceSHA256, currentWorkspaceRevisionSHA256: C32.revisionDigest, cancellationRequested: true)
        XCTAssertEqual(cancelled.state, .cancelled)
        XCTAssertEqual(cancelled.chunkReceipts.count, 1)
        XCTAssertEqual(cancelled.chunkReceipts[0].disposition, .cancelledBeforeCommit)
        XCTAssertTrue(cancelled.chunkReceipts[0].committedMutationIDs.isEmpty)
        XCTAssertNil(try store.writer.durableReceipt(mutationID: prepared.mutation.mutationID))
        try coordinator.discardScratch(for: prepared)
        XCTAssertEqual(scratch.discardedLeaseIDs, prepared.sourceManifest.leaseIDs)
    }

    func testV23P04C32R01ReceiptReplayBackupRestoreJournalReplicationAndPrivacyRecovery() throws {
        let corpus = try loadCorpus(); check(corpus, "R01", "RECOVERY")
        let store = try C32Store(); let prepared = try c32Prepared(store); let coordinator = try store.coordinator(prepared: prepared, scratch: C32ScratchRecorder())
        let begun = try coordinator.begin(sessionID: C32.id(700), prepared: prepared, currentSourceSHA256: prepared.preview.importPlan.source.sourceSHA256, currentWorkspaceRevisionSHA256: C32.revisionDigest)
        let beforeCommit = try store.writer.currentRevision()
        let committed = try coordinator.commitOrResume(session: begun, prepared: prepared, currentSourceSHA256: prepared.preview.importPlan.source.sourceSHA256, currentWorkspaceRevisionSHA256: C32.revisionDigest, cancellationRequested: false)
        let afterCommit = try store.writer.currentRevision()
        XCTAssertEqual(afterCommit.revision, beforeCommit.revision + 1)
        let receipt = try XCTUnwrap(try store.writer.durableReceipt(mutationID: prepared.mutation.mutationID))
        let typedReceipt = try PartyContactSiteRoleImportMutationReceiptV1(mutation: prepared.mutation, mutationReceipt: receipt)
        XCTAssertEqual(typedReceipt.mutationReceipt, receipt)
        let committedHistory = try store.writer.sourceMutationHistorySnapshot()
        XCTAssertEqual(try c32ReceiptCount(committedHistory, mutationID: prepared.mutation.mutationID), 1)
        try MutationReceiptRecoveryServiceV1(store: store.journal)
            .recoverPartyContactSiteRoleImportEffectsBeforeWriterActivation()
        try PartyContactSiteRoleImportLocalChangeJournalPolicyV1.validate(
            try c32JournalChange(committedHistory, mutationID: prepared.mutation.mutationID)
        )
        let restoredStartingPoint = try BulkSessionV1(sessionID: begun.sessionID, workspaceID: begun.workspaceID, bulkPlan: prepared.preview.bulkPlan, sourceSHA256: begun.sourceSHA256, expectedWorkspaceRevisionSHA256: begun.expectedWorkspaceRevisionSHA256)
        try store.lifecycle.record(session: restoredStartingPoint, replacing: committed.sessionSHA256)
        let replayed = try coordinator.commitOrResume(session: restoredStartingPoint, prepared: prepared, currentSourceSHA256: prepared.preview.importPlan.source.sourceSHA256, currentWorkspaceRevisionSHA256: C32.revisionDigest, cancellationRequested: false)
        XCTAssertEqual(replayed.chunkReceipts, committed.chunkReceipts)
        XCTAssertEqual(try store.writer.durableReceipt(mutationID: prepared.mutation.mutationID), receipt)
        XCTAssertEqual(try store.writer.currentRevision(), afterCommit)
        XCTAssertEqual(
            try c32ReceiptCount(
                store.writer.sourceMutationHistorySnapshot(),
                mutationID: prepared.mutation.mutationID
            ),
            1
        )
        try store.journal.validateAll()
        XCTAssertFalse(PartyContactsCSVContractV1.defaultExportEnabled)
        XCTAssertFalse(OperationalContactPersistenceEnrollmentV1.importSourceBytesArePersistent)
    }

    private func loadCorpus() throws -> C32Corpus {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try JSONDecoder().decode(C32Corpus.self, from: Data(contentsOf: root.appendingPathComponent("FieldEvidenceAppTests/Fixtures/V23/ImportExport/V23P04C32PartyContactSiteRoleImportCorpusV1.json")))
    }

    private func check(_ corpus: C32Corpus, _ id: String, _ tier: String) {
        XCTAssertEqual(corpus.schema, "V23P04C32PartyContactSiteRoleImportCorpusV1")
        XCTAssertEqual(corpus.schemaVersion, 1); XCTAssertEqual(corpus.cardID, "V23-P04-C32"); XCTAssertEqual(corpus.ordinal, 117)
        XCTAssertEqual(corpus.selectors.map(\.id), ["G01", "A01", "H01", "I01", "R01"])
        XCTAssertEqual(corpus.selectors.first { $0.id == id }?.tier, tier)
        XCTAssertEqual(corpus.expected.atomicity, "ONE_ROOT_ALL_OR_NOTHING")
        XCTAssertEqual(corpus.expected.sourceOrder, ["PARTIES_V1", "PARTY_CONTACTS_V1", "SITE_PARTY_ROLES_V1"])
        XCTAssertTrue(corpus.expected.oneCanonicalWriter); XCTAssertFalse(corpus.expected.previewWritesCanonicalState)
        XCTAssertFalse(corpus.expected.fuzzyMatching); XCTAssertFalse(corpus.expected.contactDefaultExportEnabled)
        XCTAssertFalse(corpus.expected.scratchRetainedAfterTerminalState)
    }
}

@MainActor private func c32ReceiptCount(
    _ history: MutationHistorySnapshotV1,
    mutationID: MutationIDV1
) throws -> Int {
    try history.receipts.reduce(into: 0) { count, record in
        if try MutationEnvelopeV1.decodeCanonical(from: record.envelopeData).mutationID == mutationID {
            count += 1
        }
    }
}

@MainActor private func c32JournalChange(
    _ history: MutationHistorySnapshotV1,
    mutationID: MutationIDV1
) throws -> JournalChangeV1 {
    let record = try XCTUnwrap(history.receipts.first { record in
        guard let envelope = try? MutationEnvelopeV1.decodeCanonical(from: record.envelopeData) else {
            return false
        }
        return envelope.mutationID == mutationID
    })
    let envelope = try MutationEnvelopeV1.decodeCanonical(from: record.envelopeData)
    let receipt = try MutationReceiptV1.decodeCanonical(from: record.receiptData)
    let policy = try ConflictPolicyV1(
        policyID: "c32.import.exact-revision",
        rule: .exactRevisionManual
    )
    let entityChanges = try receipt.postImages.map {
        try EntityChangeV1(
            postImage: $0,
            conflictPolicy: policy,
            conflictIdentity: nil
        )
    }
    return try JournalChangeV1(
        envelope: envelope,
        receipt: receipt,
        entityChanges: entityChanges,
        reversalBasis: nil,
        portableReversalPlan: nil,
        semanticReversalReceipt: nil,
        contentReferences: []
    )
}

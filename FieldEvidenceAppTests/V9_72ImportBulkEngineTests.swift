import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

private struct C08Corpus: Decodable {
    struct Selector: Decodable { let id: String; let selector: String; let tier: String }
    struct Expected { let allOrNothing: String; let changedInput: String; let errorCodes: [String]; let previewWritesCanonicalState: Bool; let receipt: Receipt; let receiptDisposition: String; let sourceSHA256: String; let workspaceRevisionSHA256: String }
    struct Receipt { let chunkIndex: Int; let committedMutationCount: Int; let disposition: String }
    let schema: String; let schemaVersion: Int; let cardID: String; let ordinal: Int; let selectors: [Selector]; let expected: Expected; let synthetic: Bool
}
extension C08Corpus.Expected: Decodable {}
extension C08Corpus.Receipt: Decodable {}

private enum C08 {
    static let sourceSHA256 = String(repeating: "a", count: 64)
    static let workspaceRevisionSHA256 = String(repeating: "d", count: 64)
    static let time = Date(timeIntervalSince1970: 1_788_134_400)
    static func id(_ value: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", value))! }
    static func workspace() -> WorkspaceID { .init(rawValue: id(980_001)) }

    static func schema(release: UInt64 = 1) throws -> ImportSchemaReleaseV1 {
        let budget = try ImportStreamingBudgetV1(maximumSourceBytes: 1_024, maximumRows: 8, maximumColumns: 4, maximumCellBytes: 128, maximumScalarsPerCell: 128)
        return try ImportSchemaReleaseV1(releaseID: "c08_schema", release: release, entityKind: .asset, externalKeyColumn: "asset_key", columns: [
            try .init(key: "asset_key", scalar: .identifier, required: true, editableOnExactUpdate: false, maximumCellBytes: 128, maximumScalars: 128),
            try .init(key: "asset_name", scalar: .text, required: false, editableOnExactUpdate: true, maximumCellBytes: 128, maximumScalars: 128)
        ], budget: budget)
    }

    static func plan(workspaceID: WorkspaceID = workspace(), rowCount: Int = 1) throws -> (ImportPlanV1, BulkCommandPlanV1) {
        let schema = try schema()
        let source = try ImportSourceV1(sourceID: id(980_002), workspaceID: workspaceID, kind: .userSelectedFile, sourceSHA256: sourceSHA256, byteCount: 32, leaseID: id(980_003), importedAt: time)
        let rows = try (1...rowCount).map { ordinal -> ImportPlanRowV1 in
            let identity = try ImportRowIdentityV1(workspaceID: workspaceID, sourceSHA256: sourceSHA256, sourceOrdinal: UInt64(ordinal), canonicalRowSHA256: String(format: "%064x", ordinal), stableExternalKey: String(format: "asset_%03d", ordinal), schemaReleaseID: schema.releaseID, schemaRelease: schema.release)
            let mappedFields = [try ImportMappedFieldV1(key: "asset_key", value: String(format: "asset_%03d", ordinal))]
            let commandID = String(format: "create_asset_%03d", ordinal)
            let payloadSHA256 = try ImportProposedCommandV1.canonicalPayloadSHA256(commandID: commandID, kind: .createAsset, targetStableID: nil, expectedRevision: nil, dependencyCommandIDs: [], rowIdentity: identity, schemaRelease: schema, mappedFields: mappedFields)
            let command = try ImportProposedCommandV1(commandID: commandID, kind: .createAsset, targetStableID: nil, expectedRevision: nil, dependencyCommandIDs: [], payloadSHA256: payloadSHA256)
            return try ImportPlanRowV1(identity: identity, disposition: .create, reasons: [.exactStableKeyCreate], mappedFields: mappedFields, commands: [command], expectedTargetRevision: nil)
        }
        let planID = try ImportPlanV1.deterministicPlanID(workspaceID: workspaceID, source: source, schemaRelease: schema, mappingProfileSHA256: nil, workspaceRevisionSHA256: workspaceRevisionSHA256, rows: rows)
        let plan = try ImportPlanV1(planID: planID, workspaceID: workspaceID, source: source, schemaRelease: schema, mappingProfileSHA256: nil, workspaceRevisionSHA256: workspaceRevisionSHA256, rows: rows)
        let chunks = try rows.enumerated().map { index, row -> BulkChunkPlanV1 in
            let mutationID = try BulkCommandPlanV1.deterministicMutationID(importPlanID: plan.planID, chunkIndex: index, rowIdentitySHA256: row.identity.identitySHA256)
            return try BulkChunkPlanV1(chunkIndex: index, rowIdentitySHA256s: [row.identity.identitySHA256], mutationIDs: [mutationID])
        }
        let atomicity: BulkAtomicityV1 = rowCount == 1 ? .allOrNothing : .chunkedAtomic
        let bulkPlanID = try BulkCommandPlanV1.deterministicBulkPlanID(importPlan: plan, atomicity: atomicity, chunks: chunks)
        return (plan, try BulkCommandPlanV1(bulkPlanID: bulkPlanID, importPlan: plan, atomicity: atomicity, chunks: chunks))
    }
}

@MainActor private final class C08WriterAdapter: WorkspaceWriterAdapterPortV1 {
    private(set) var applyCount = 0
    func apply(_ command: WorkspaceCommandV1, occurredAt: Date, temporaryRelativePath: String) throws -> WorkspaceMutationEffectV1 {
        guard case let .createFirstSign(value) = command else { throw WorkspaceMutationFailureV1.unsupportedCommand }
        applyCount += 1
        var identities = [try WorkspaceEntityIdentityV1(kind: .asset, id: value.assetID)]
        if let site = value.newSite { identities.append(try WorkspaceEntityIdentityV1(kind: .site, id: site.id)) }
        return try WorkspaceMutationEffectV1(affectedEntities: identities, temporaryRelativePath: temporaryRelativePath)
    }
}

private struct C08Clock: ApplicationClock { func now() -> Date { C08.time } }
private struct C08IDSource: ApplicationIDSource { let value: UUID; func makeID() -> UUID { value } }
private struct C08FileAuthority: ApplicationFileAuthorityV1 {
    func temporaryRelativePath(mutationID: MutationIDV1, component: String) throws -> String {
        "c08/\(mutationID.rawValue.uuidString.lowercased())/\(component)"
    }
}

private struct C08RejectingMaterializer: ImportWorkspaceCommandMaterializingV1 {
    func materialize(_ context: ImportCommandMaterializationContextV1) throws -> WorkspaceMutationRequestV1 {
        throw ImportBulkFailureV1.unsupportedSchema
    }
}

private struct C08CreateAssetMaterializer: ImportWorkspaceCommandMaterializingV1 {
    func materialize(_ context: ImportCommandMaterializationContextV1) throws -> WorkspaceMutationRequestV1 {
        try WorkspaceMutationRequestV1(mutationID: context.mutationID, expectedRevision: context.expectedRevision, command: .createFirstSign(.init(siteID: C08.id(980_110), newSite: .init(id: C08.id(980_110), label: "C08 site", address: nil, timeZoneID: "UTC"), assetID: C08.id(980_111), assetLabel: "C08 imported asset", packID: "c08.pack", packSchemaVersion: 1, packContentVersion: 1, createdAt: C08.time)))
    }
}

@MainActor private final class C08Stack {
    let context: ModelContext
    let adapter: C08WriterAdapter
    let writer: WorkspaceWriterV1
    let lifecycle: ImportBulkLifecycleAdapterV1
    let coordinator: ImportBulkCoordinatorV1

    init() throws {
        let models = PersistentSchemaV45.models + [ImportMappingProfileRowV1.self, BulkSessionRowV1.self, BulkCommitReceiptRowV1.self]
        let schema = Schema(models, version: PersistentSchemaV45.versionIdentifier)
        let container = try ModelContainer(for: schema, migrationPlan: nil, configurations: [ModelConfiguration("C08ImportBulk", schema: schema, isStoredInMemoryOnly: true, allowsSave: true, cloudKitDatabase: .none)])
        context = container.mainContext
        context.autosaveEnabled = false
        let workspaceID = C08.workspace(), generationID = C08.id(980_090)
        let identity = try WorkspaceReplicaIdentityV1(workspaceID: workspaceID, replicaID: ReplicaID(rawValue: C08.id(980_091)))
        let journal = try MutationJournalStoreV1(modelContext: context, identity: identity, generationID: generationID)
        adapter = C08WriterAdapter()
        writer = try WorkspaceWriterV1(identity: identity, generationID: generationID, initialRevision: journal.currentRevision(writerInstanceID: C08.id(980_092)), clock: C08Clock(), idSource: C08IDSource(value: C08.id(980_092)), fileAuthority: C08FileAuthority(), adapter: adapter, journalStore: journal)
        let registration = try C08Stack.registration()
        lifecycle = try ImportBulkLifecycleAdapterV1(registrations: [registration], modelContext: context)
        let materializers = ImportCommandKindV1.allCases.map { ImportBulkMaterializerRegistrationV1(kind: $0, materializer: $0 == .createAsset ? C08CreateAssetMaterializer() : C08RejectingMaterializer()) }
        coordinator = try ImportBulkCoordinatorV1(writer: writer, lifecycle: lifecycle, materializers: materializers)
    }

    private static func registration() throws -> ImportAdapterRegistrationV1 {
        try ImportAdapterRegistrationV1(adapterID: "c08_all", adapterVersion: 1, schemaReleaseID: "c08_schema", schemaRelease: 1, entityKinds: ImportEntityKindV1.allCases.sorted(), requiredSourceKeys: ["asset_key"], dependencyAdapterIDs: [], commandKinds: ImportCommandKindV1.allCases.sorted(), lifecycleDispositions: [.activeBulkSessionRecoverableOperationalState, .bulkCommitReceiptImmutableCanonicalAudit, .importedEntityUsesOrdinaryLifecycle], privacyClass: .localOperational, supportsDeterministicExport: true, fixtureSHA256s: [C08.sourceSHA256])
    }
}

@MainActor private func c08Stack() throws -> C08Stack { try C08Stack() }

@MainActor final class V9_72ImportBulkEngineTests: XCTestCase {
    func testV23P04C08G01PreviewFirstImportBulkAndDeterministicExportGolden() throws {
        let corpus = try loadCorpus(); check(corpus, "G01", "GOLDEN")
        let (plan, bulk) = try C08.plan(); try plan.validate(); try bulk.validate(importPlan: plan)
        XCTAssertEqual(bulk.atomicity, .allOrNothing)
        let stack = try c08Stack(), coordinator = stack.coordinator
        let preview = try coordinator.preview(importPlan: plan, bulkPlan: bulk, currentSourceSHA256: plan.source.sourceSHA256, currentWorkspaceRevisionSHA256: plan.workspaceRevisionSHA256)
        XCTAssertEqual(preview.importPlan, plan); XCTAssertEqual(preview.bulkPlan, bulk)
        XCTAssertNil(try stack.lifecycle.durableSession(sessionID: C08.id(980_030)))
        XCTAssertNil(try stack.lifecycle.durableReceipt(workspaceID: plan.workspaceID, bulkPlan: bulk, chunkIndex: 0))
        let zeroWrites = stack.adapter.applyCount
        XCTAssertEqual(zeroWrites, 0)
        let begun = try coordinator.begin(sessionID: C08.id(980_030), preview: preview, currentSourceSHA256: plan.source.sourceSHA256, currentWorkspaceRevisionSHA256: plan.workspaceRevisionSHA256)
        XCTAssertEqual(try stack.lifecycle.durableSession(sessionID: begun.sessionID), begun)
        let context = try ImportCommandMaterializationContextV1(plan: plan, rowIdentity: plan.rows[0].identity, row: plan.rows[0], command: plan.rows[0].commands[0], chunkIndex: 0, mutationID: bulk.chunks[0].mutationIDs[0], expectedRevision: .init(snapshot: try stack.writer.currentRevision()))
        let request = try C08CreateAssetMaterializer().materializeValidated(context)
        XCTAssertEqual(request.mutationID, bulk.chunks[0].mutationIDs[0])
        let committed = try coordinator.commitFirstMissingChunk(session: begun, importPlan: plan, bulkPlan: bulk, currentSourceSHA256: plan.source.sourceSHA256, currentWorkspaceRevisionSHA256: plan.workspaceRevisionSHA256, cancellationRequested: false)
        XCTAssertEqual(committed.state, .completed); XCTAssertEqual(committed.chunkReceipts.count, 1)
        XCTAssertNotNil(try stack.writer.durableReceipt(mutationID: bulk.chunks[0].mutationIDs[0]))
        XCTAssertEqual(try stack.lifecycle.durableReceipt(workspaceID: plan.workspaceID, bulkPlan: bulk, chunkIndex: 0), committed.chunkReceipts[0])
        XCTAssertEqual(stack.adapter.applyCount, 1)
        XCTAssertFalse(plan.previewWritesCanonicalState)
        XCTAssertEqual(try ImportBulkCanonicalCodecV1.decode(ImportPlanV1.self, from: ImportBulkCanonicalCodecV1.encode(plan)), plan)
        XCTAssertEqual(try C08.plan().0.planSHA256, plan.planSHA256)
        let perturbed = try C08.plan(rowCount: 2).0
        let digest = try ImportBulkCanonicalCodecV1.sha256(plan)
        XCTAssertEqual(digest, try ImportBulkCanonicalCodecV1.sha256(C08.plan().0))
        XCTAssertNotEqual(digest, try ImportBulkCanonicalCodecV1.sha256(perturbed))
        let exportSchema = try ExportSchemaReleaseV1(releaseID: "c08_export", release: 1, importSchema: plan.schemaRelease, expectedRevisionColumn: "expected_revision")
        let CRLFBytes = Data("asset_key,asset_name\r\nasset_001,'=1+1\r\n".utf8)
        let lfBytes = Data("asset_key,asset_name\nasset_001,'=1+1\n".utf8)
        let first = try DeterministicCSVExportV1(exportID: C08.id(980_020), workspaceID: plan.workspaceID, kind: .inventory, exportSchema: exportSchema, rowCount: 1, bytes: CRLFBytes)
        let repeated = try DeterministicCSVExportV1(exportID: C08.id(980_020), workspaceID: plan.workspaceID, kind: .inventory, exportSchema: exportSchema, rowCount: 1, bytes: CRLFBytes)
        let lf = try DeterministicCSVExportV1(exportID: C08.id(980_021), workspaceID: plan.workspaceID, kind: .inventory, exportSchema: exportSchema, rowCount: 1, bytes: lfBytes)
        XCTAssertTrue(first.formulaAndControlPrefixesNeutralized); XCTAssertEqual(first.exportSHA256, repeated.exportSHA256); XCTAssertEqual(first.bytesSHA256, repeated.bytesSHA256)
        XCTAssertNotEqual(first.bytesSHA256, lf.bytesSHA256)
        let NFC = "caf\u{00e9}", nfd = "cafe\u{0301}"
        XCTAssertEqual(NFC, nfd.precomposedStringWithCanonicalMapping)
        XCTAssertThrowsError(try ImportMappedFieldV1(key: "asset_name", value: nfd))
    }

    func testV23P04C08A01CorrectionAndPoseRoundTripAlternate() throws {
        let corpus = try loadCorpus(); check(corpus, "A01", "ALTERNATE")
        let (plan, bulk) = try C08.plan()
        let receipt = try BulkCommitReceiptV1(receiptID: C08.id(980_010), workspaceID: plan.workspaceID, bulkPlan: bulk, chunkIndex: 0, expectedWorkspaceRevisionSHA256: plan.workspaceRevisionSHA256, disposition: .committed, committedMutationIDs: bulk.chunks[0].mutationIDs)
        let correction = try ImportCorrectionArtifactV1(rowIdentity: plan.rows[0].identity, errorCode: .staleExpectedRevision, offendingColumn: "expected_revision", boundedCorrectionHint: "refresh revision")
        let correctionRepeat = try ImportCorrectionArtifactV1(rowIdentity: plan.rows[0].identity, errorCode: .staleExpectedRevision, offendingColumn: "expected_revision", boundedCorrectionHint: "other hint")
        try correction.validate()
        XCTAssertEqual(try ImportBulkCanonicalCodecV1.decode(BulkCommitReceiptV1.self, from: ImportBulkCanonicalCodecV1.encode(receipt)), receipt)
        XCTAssertEqual(correction.retryIdentitySHA256, correctionRepeat.retryIdentitySHA256)
        XCTAssertNotEqual(correction.artifactSHA256, correctionRepeat.artifactSHA256)
        XCTAssertEqual(plan.schemaRelease.entityKind, .asset)
    }

    func testV23P04C08H01HostileBudgetIdentityAndFormulaSafety() throws {
        let corpus = try loadCorpus(); check(corpus, "H01", "HOSTILE")
        let (plan, bulk) = try C08.plan()
        let coordinator = try c08Stack().coordinator
        XCTAssertThrowsError(try coordinator.preview(importPlan: plan, bulkPlan: bulk, currentSourceSHA256: String(repeating: "f", count: 64), currentWorkspaceRevisionSHA256: plan.workspaceRevisionSHA256)) { error in
            XCTAssertEqual(error as? ImportBulkFailureV1, .changedInputQuarantined)
        }
        XCTAssertThrowsError(try ImportStreamingBudgetV1(maximumSourceBytes: 0, maximumRows: 1, maximumColumns: 1, maximumCellBytes: 1, maximumScalarsPerCell: 1))
        XCTAssertThrowsError(try ImportRowIdentityV1(workspaceID: plan.workspaceID, sourceSHA256: C08.sourceSHA256, sourceOrdinal: 0, canonicalRowSHA256: C08.sourceSHA256, stableExternalKey: "asset_001", schemaReleaseID: "c08_schema", schemaRelease: 1))
        XCTAssertThrowsError(try ImportRowIdentityV1(workspaceID: plan.workspaceID, sourceSHA256: C08.sourceSHA256, sourceOrdinal: 1, canonicalRowSHA256: C08.sourceSHA256, stableExternalKey: "asset\n001", schemaReleaseID: "c08_schema", schemaRelease: 1))
        XCTAssertThrowsError(try BulkChunkPlanV1(chunkIndex: 0, rowIdentitySHA256s: [], mutationIDs: []))
        let duplicate = try ImportPlanRowV1(identity: plan.rows[0].identity, disposition: .duplicateSource, reasons: [.duplicateExternalKey], mappedFields: [], commands: [], expectedTargetRevision: nil)
        let ambiguous = try ImportPlanRowV1(identity: plan.rows[0].identity, disposition: .ambiguousTarget, reasons: [.multipleExactTargets], mappedFields: [], commands: [], expectedTargetRevision: nil)
        XCTAssertEqual(duplicate.disposition, .duplicateSource); XCTAssertEqual(duplicate.reasons, [.duplicateExternalKey]); XCTAssertTrue(duplicate.commands.isEmpty)
        XCTAssertEqual(ambiguous.disposition, .ambiguousTarget); XCTAssertEqual(ambiguous.reasons, [.multipleExactTargets]); XCTAssertTrue(ambiguous.commands.isEmpty)
        XCTAssertThrowsError(try bulk.validate(importPlan: try ImportPlanV1(planID: plan.planID, workspaceID: plan.workspaceID, source: plan.source, schemaRelease: plan.schemaRelease, mappingProfileSHA256: nil, workspaceRevisionSHA256: String(repeating: "e", count: 64), rows: plan.rows)))
        let exportSchema = try ExportSchemaReleaseV1(releaseID: "c08_export", release: 1, importSchema: plan.schemaRelease, expectedRevisionColumn: "expected_revision")
        XCTAssertThrowsError(try DeterministicCSVExportV1(exportID: C08.id(980_021), workspaceID: plan.workspaceID, kind: .inventory, exportSchema: exportSchema, rowCount: 1, bytes: Data("a\u{0000}".utf8)))
    }

    func testV23P04C08I01ChunkBoundaryInterruptionAndResume() throws {
        let corpus = try loadCorpus(); check(corpus, "I01", "INTERRUPTION")
        let (plan, bulk) = try C08.plan(rowCount: 2)
        let stack = try c08Stack(), coordinator = stack.coordinator
        let preview = try coordinator.preview(importPlan: plan, bulkPlan: bulk, currentSourceSHA256: plan.source.sourceSHA256, currentWorkspaceRevisionSHA256: plan.workspaceRevisionSHA256)
        let begun = try coordinator.begin(sessionID: C08.id(980_031), preview: preview, currentSourceSHA256: plan.source.sourceSHA256, currentWorkspaceRevisionSHA256: plan.workspaceRevisionSHA256)
        let interruptionContext = try ImportCommandMaterializationContextV1(plan: plan, rowIdentity: plan.rows[0].identity, row: plan.rows[0], command: plan.rows[0].commands[0], chunkIndex: 0, mutationID: bulk.chunks[0].mutationIDs[0], expectedRevision: .init(snapshot: try stack.writer.currentRevision()))
        XCTAssertEqual(try C08CreateAssetMaterializer().materializeValidated(interruptionContext).mutationID, bulk.chunks[0].mutationIDs[0])
        let coordinatorCancelled = try coordinator.commitFirstMissingChunk(session: begun, importPlan: plan, bulkPlan: bulk, currentSourceSHA256: plan.source.sourceSHA256, currentWorkspaceRevisionSHA256: plan.workspaceRevisionSHA256, cancellationRequested: true)
        XCTAssertEqual(coordinatorCancelled.state, .cancelled)
        XCTAssertEqual(coordinatorCancelled.chunkReceipts.count, 1)
        XCTAssertEqual(coordinatorCancelled.chunkReceipts[0].disposition, .cancelledBeforeCommit)
        XCTAssertEqual(try stack.lifecycle.durableSession(sessionID: begun.sessionID), coordinatorCancelled)
        XCTAssertEqual(try stack.lifecycle.durableReceipt(workspaceID: plan.workspaceID, bulkPlan: bulk, chunkIndex: 0)?.disposition, .cancelledBeforeCommit)
        let firstReceipt = try BulkCommitReceiptV1(receiptID: C08.id(980_011), workspaceID: plan.workspaceID, bulkPlan: bulk, chunkIndex: 0, expectedWorkspaceRevisionSHA256: plan.workspaceRevisionSHA256, disposition: .committed, committedMutationIDs: bulk.chunks[0].mutationIDs)
        let interrupted = try BulkSessionV1(sessionID: C08.id(980_012), workspaceID: plan.workspaceID, bulkPlan: bulk, sourceSHA256: plan.source.sourceSHA256, expectedWorkspaceRevisionSHA256: plan.workspaceRevisionSHA256, state: .cancellationRequested, chunkReceipts: [firstReceipt])
        try interrupted.validate(); XCTAssertEqual(try interrupted.firstMissingReceiptChunkIndex(in: bulk), 1)
        XCTAssertThrowsError(try interrupted.validateResumption(bulkPlan: bulk, sourceSHA256: String(repeating: "f", count: 64), workspaceRevisionSHA256: plan.workspaceRevisionSHA256))
        let cancelled = try BulkCommitReceiptV1(receiptID: C08.id(980_013), workspaceID: plan.workspaceID, bulkPlan: bulk, chunkIndex: 1, expectedWorkspaceRevisionSHA256: plan.workspaceRevisionSHA256, disposition: .cancelledBeforeCommit, committedMutationIDs: [])
        let terminal = try BulkSessionV1(sessionID: C08.id(980_014), workspaceID: plan.workspaceID, bulkPlan: bulk, sourceSHA256: plan.source.sourceSHA256, expectedWorkspaceRevisionSHA256: plan.workspaceRevisionSHA256, state: .cancelled, chunkReceipts: [firstReceipt, cancelled])
        XCTAssertNil(try terminal.firstMissingReceiptChunkIndex(in: bulk))
    }

    func testV23P04C08R01IdempotentRetryCompensationAndLifecycleRecovery() throws {
        let corpus = try loadCorpus(); check(corpus, "R01", "RECOVERY")
        let (plan, bulk) = try C08.plan()
        let stack = try c08Stack(), coordinator = stack.coordinator
        let preview = try coordinator.preview(importPlan: plan, bulkPlan: bulk, currentSourceSHA256: plan.source.sourceSHA256, currentWorkspaceRevisionSHA256: plan.workspaceRevisionSHA256)
        let begun = try coordinator.begin(sessionID: C08.id(980_040), preview: preview, currentSourceSHA256: plan.source.sourceSHA256, currentWorkspaceRevisionSHA256: plan.workspaceRevisionSHA256)
        let recoveryContext = try ImportCommandMaterializationContextV1(plan: plan, rowIdentity: plan.rows[0].identity, row: plan.rows[0], command: plan.rows[0].commands[0], chunkIndex: 0, mutationID: bulk.chunks[0].mutationIDs[0], expectedRevision: .init(snapshot: try stack.writer.currentRevision()))
        XCTAssertEqual(try C08CreateAssetMaterializer().materializeValidated(recoveryContext).mutationID, bulk.chunks[0].mutationIDs[0])
        let committedByCoordinator = try coordinator.commitFirstMissingChunk(session: begun, importPlan: plan, bulkPlan: bulk, currentSourceSHA256: plan.source.sourceSHA256, currentWorkspaceRevisionSHA256: plan.workspaceRevisionSHA256, cancellationRequested: false)
        let recoveredStartingPoint = try BulkSessionV1(sessionID: begun.sessionID, workspaceID: plan.workspaceID, bulkPlan: bulk, sourceSHA256: plan.source.sourceSHA256, expectedWorkspaceRevisionSHA256: plan.workspaceRevisionSHA256)
        try stack.lifecycle.record(session: recoveredStartingPoint, replacing: committedByCoordinator.sessionSHA256)
        let recovered = try coordinator.commitFirstMissingChunk(session: recoveredStartingPoint, importPlan: plan, bulkPlan: bulk, currentSourceSHA256: plan.source.sourceSHA256, currentWorkspaceRevisionSHA256: plan.workspaceRevisionSHA256, cancellationRequested: false)
        XCTAssertEqual(recovered.chunkReceipts, committedByCoordinator.chunkReceipts)
        XCTAssertEqual(stack.adapter.applyCount, 1)
        let receipt = try BulkCommitReceiptV1(receiptID: C08.id(980_015), workspaceID: plan.workspaceID, bulkPlan: bulk, chunkIndex: 0, expectedWorkspaceRevisionSHA256: plan.workspaceRevisionSHA256, disposition: .committed, committedMutationIDs: bulk.chunks[0].mutationIDs)
        let completed = try BulkSessionV1(sessionID: C08.id(980_016), workspaceID: plan.workspaceID, bulkPlan: bulk, sourceSHA256: plan.source.sourceSHA256, expectedWorkspaceRevisionSHA256: plan.workspaceRevisionSHA256, state: .completed, chunkReceipts: [receipt])
        let receiptRow = try BulkCommitReceiptRowV1(receipt); XCTAssertEqual(try receiptRow.value(), receipt)
        let sessionRow = try BulkSessionRowV1(completed); XCTAssertEqual(try sessionRow.value(), completed)
        XCTAssertThrowsError(try sessionRow.replace(with: completed, expectedSessionSHA256: String(repeating: "e", count: 64)))
        XCTAssertThrowsError(try completed.validateResumption(bulkPlan: bulk, sourceSHA256: plan.source.sourceSHA256, workspaceRevisionSHA256: String(repeating: "e", count: 64)))
        let registration = try ImportAdapterRegistrationV1(adapterID: "c08_asset", adapterVersion: 1, schemaReleaseID: plan.schemaRelease.releaseID, schemaRelease: plan.schemaRelease.release, entityKinds: [.asset], requiredSourceKeys: ["asset_key"], dependencyAdapterIDs: [], commandKinds: [.createAsset], lifecycleDispositions: [.savedMappingWorkspaceConfiguration, .activeBulkSessionRecoverableOperationalState, .bulkCommitReceiptImmutableCanonicalAudit, .importedEntityUsesOrdinaryLifecycle], privacyClass: .localOperational, supportsDeterministicExport: true, fixtureSHA256s: [receipt.receiptSHA256])
        XCTAssertNoThrow(try ImportAdapterRegistryV1.validate([registration]))
        XCTAssertEqual(receipt.committedMutationIDs, bulk.chunks[0].mutationIDs)

        let targetWorkspaceID = WorkspaceID(rawValue: C08.id(980_050))
        let profile = try ImportMappingProfileV1(profileID: C08.id(980_051), workspaceID: plan.workspaceID, profileName: "C08 mapping", schemaRelease: plan.schemaRelease, mappings: [try .init(sourceColumn: "external_asset", targetColumn: "asset_name")])
        let reboundProfile = try ImportBulkWorkspaceRebindingFactoryV1.rebind(mappingProfile: profile, to: targetWorkspaceID, schemaRelease: plan.schemaRelease)
        guard case let .mappingProfile(rebound) = reboundProfile else { return XCTFail("exact schema binding must rebind mapping") }
        XCTAssertEqual(rebound.workspaceID, targetWorkspaceID)
        XCTAssertEqual(rebound.schemaSHA256, plan.schemaRelease.schemaSHA256)
        let sameWorkspaceProfile = try ImportBulkWorkspaceRebindingFactoryV1.rebind(mappingProfile: profile, to: plan.workspaceID, schemaRelease: plan.schemaRelease)
        guard case let .rejected(sameProfileRejection) = sameWorkspaceProfile else { return XCTFail("source target equality must reject") }
        XCTAssertEqual(sameProfileRejection.reason, .targetEqualsSource)
        let incompatibleSchemaProfile = try ImportBulkWorkspaceRebindingFactoryV1.rebind(mappingProfile: profile, to: targetWorkspaceID, schemaRelease: try C08.schema(release: 2))
        guard case let .rejected(schemaRejection) = incompatibleSchemaProfile else { return XCTFail("schema mismatch must reject") }
        XCTAssertEqual(schemaRejection.reason, .schemaBindingMismatch)

        let target = try C08.plan(workspaceID: targetWorkspaceID)
        let active = try BulkSessionV1(sessionID: C08.id(980_052), workspaceID: plan.workspaceID, bulkPlan: bulk, sourceSHA256: plan.source.sourceSHA256, expectedWorkspaceRevisionSHA256: plan.workspaceRevisionSHA256)
        let reboundSession = try ImportBulkWorkspaceRebindingFactoryV1.rebind(session: active, to: targetWorkspaceID, bulkPlan: target.1, sourceSHA256: target.0.source.sourceSHA256, expectedWorkspaceRevisionSHA256: target.0.workspaceRevisionSHA256)
        guard case let .bulkSession(reboundActive) = reboundSession else { return XCTFail("receipt-free active session must rebind") }
        XCTAssertEqual(reboundActive.workspaceID, targetWorkspaceID)
        XCTAssertTrue(reboundActive.chunkReceipts.isEmpty)
        let sameWorkspaceSession = try ImportBulkWorkspaceRebindingFactoryV1.rebind(session: active, to: plan.workspaceID, bulkPlan: bulk, sourceSHA256: plan.source.sourceSHA256, expectedWorkspaceRevisionSHA256: plan.workspaceRevisionSHA256)
        guard case let .rejected(sameSessionRejection) = sameWorkspaceSession else { return XCTFail("session target equality must reject") }
        XCTAssertEqual(sameSessionRejection.reason, .targetEqualsSource)
        let mismatchedTargetPlan = try ImportBulkWorkspaceRebindingFactoryV1.rebind(session: active, to: targetWorkspaceID, bulkPlan: bulk, sourceSHA256: plan.source.sourceSHA256, expectedWorkspaceRevisionSHA256: plan.workspaceRevisionSHA256)
        guard case let .rejected(planRejection) = mismatchedTargetPlan else { return XCTFail("foreign target plan must reject") }
        XCTAssertEqual(planRejection.reason, .targetPlanWorkspaceMismatch)
        let mismatchedSource = try ImportBulkWorkspaceRebindingFactoryV1.rebind(session: active, to: targetWorkspaceID, bulkPlan: target.1, sourceSHA256: String(repeating: "f", count: 64), expectedWorkspaceRevisionSHA256: target.0.workspaceRevisionSHA256)
        guard case let .rejected(sourceRejection) = mismatchedSource else { return XCTFail("source digest mismatch must reject") }
        XCTAssertEqual(sourceRejection.reason, .sourceDigestMismatch)
        let immutableReceipt = try ImportBulkWorkspaceRebindingFactoryV1.rebind(receipt: receipt, to: targetWorkspaceID)
        guard case let .rejected(receiptRejection) = immutableReceipt else { return XCTFail("immutable receipt must reject") }
        XCTAssertEqual(receiptRejection.reason, .immutableAuditReceiptCannotBeRebound)
        let rejectionJSON = String(data: try ImportBulkCanonicalCodecV1.encode(receiptRejection), encoding: .utf8)!
        XCTAssertFalse(rejectionJSON.contains(plan.workspaceID.rawValue.uuidString))
    }

    private func loadCorpus() throws -> C08Corpus {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try JSONDecoder().decode(C08Corpus.self, from: Data(contentsOf: root.appendingPathComponent("FieldEvidenceAppTests/Fixtures/V22/ImportExport/V22P04C08ImportBulkEngineCorpusV1.json")))
    }

    private func check(_ corpus: C08Corpus, _ id: String, _ tier: String) {
        XCTAssertEqual(corpus.schema, "V22P04C08ImportBulkEngineCorpusV1"); XCTAssertEqual(corpus.schemaVersion, 1); XCTAssertEqual(corpus.cardID, "V23-P04-C08"); XCTAssertEqual(corpus.ordinal, 96)
        XCTAssertEqual(corpus.selectors.map(\.id), ["G01", "A01", "H01", "I01", "R01"]); XCTAssertEqual(corpus.selectors.map(\.selector), ["V23-P04-C08-G01", "V23-P04-C08-A01", "V23-P04-C08-H01", "V23-P04-C08-I01", "V23-P04-C08-R01"]); XCTAssertEqual(corpus.selectors.first { $0.id == id }?.tier, tier)
        XCTAssertFalse(corpus.expected.previewWritesCanonicalState); XCTAssertEqual(corpus.expected.allOrNothing, "ALL_OR_NOTHING"); XCTAssertEqual(corpus.expected.changedInput, "QUARANTINED_CHANGED_INPUT"); XCTAssertEqual(corpus.expected.errorCodes, ["INVALID_VALUE", "STALE_EXPECTED_REVISION"]); XCTAssertEqual(corpus.expected.receipt.chunkIndex, 0); XCTAssertEqual(corpus.expected.receipt.committedMutationCount, 1); XCTAssertEqual(corpus.expected.receipt.disposition, "COMMITTED"); XCTAssertEqual(corpus.expected.receiptDisposition, "COMMITTED"); XCTAssertEqual(corpus.expected.sourceSHA256, C08.sourceSHA256); XCTAssertEqual(corpus.expected.workspaceRevisionSHA256, C08.workspaceRevisionSHA256); XCTAssertTrue(corpus.synthetic)
    }
}

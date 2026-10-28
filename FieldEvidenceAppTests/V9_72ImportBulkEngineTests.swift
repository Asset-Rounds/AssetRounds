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

    static func atomicPlan(workspaceID: WorkspaceID = workspace()) throws -> (ImportPlanV1, BulkCommandPlanV1) {
        let budget = try ImportStreamingBudgetV1(maximumSourceBytes: 1_024, maximumRows: 1, maximumColumns: 4, maximumCellBytes: 128, maximumScalarsPerCell: 128)
        let schema = try ImportSchemaReleaseV1(releaseID: "c08_atomic_bundle", release: 1, entityKind: .atomicWorkspaceBundle, externalKeyColumn: "bundle_key", columns: [
            try .init(key: "bundle_key", scalar: .identifier, required: true, editableOnExactUpdate: false, maximumCellBytes: 128, maximumScalars: 128)
        ], budget: budget)
        let source = try ImportSourceV1(sourceID: id(980_120), workspaceID: workspaceID, kind: .userSelectedFile, sourceSHA256: sourceSHA256, byteCount: 32, leaseID: id(980_121), importedAt: time)
        let identity = try ImportRowIdentityV1(workspaceID: workspaceID, sourceSHA256: sourceSHA256, sourceOrdinal: 1, canonicalRowSHA256: String(format: "%064x", 980_122), stableExternalKey: "atomic_bundle", schemaReleaseID: schema.releaseID, schemaRelease: schema.release)
        let mappedFields = [try ImportMappedFieldV1(key: "bundle_key", value: "atomic_bundle")]
        let payloadSHA256 = try ImportProposedCommandV1.canonicalPayloadSHA256(commandID: "apply_atomic_bundle", kind: .applyAtomicWorkspaceBundle, targetStableID: nil, expectedRevision: nil, dependencyCommandIDs: [], rowIdentity: identity, schemaRelease: schema, mappedFields: mappedFields)
        let command = try ImportProposedCommandV1(commandID: "apply_atomic_bundle", kind: .applyAtomicWorkspaceBundle, targetStableID: nil, expectedRevision: nil, dependencyCommandIDs: [], payloadSHA256: payloadSHA256)
        let row = try ImportPlanRowV1(identity: identity, disposition: .create, reasons: [.exactStableKeyCreate], mappedFields: mappedFields, commands: [command], expectedTargetRevision: nil)
        let planID = try ImportPlanV1.deterministicPlanID(workspaceID: workspaceID, source: source, schemaRelease: schema, mappingProfileSHA256: nil, workspaceRevisionSHA256: workspaceRevisionSHA256, rows: [row])
        let plan = try ImportPlanV1(planID: planID, workspaceID: workspaceID, source: source, schemaRelease: schema, mappingProfileSHA256: nil, workspaceRevisionSHA256: workspaceRevisionSHA256, rows: [row])
        let mutationID = try BulkCommandPlanV1.deterministicMutationID(importPlanID: plan.planID, chunkIndex: 0, rowIdentitySHA256: row.identity.identitySHA256)
        let chunk = try BulkChunkPlanV1(chunkIndex: 0, rowIdentitySHA256s: [row.identity.identitySHA256], mutationIDs: [mutationID])
        let bulkPlanID = try BulkCommandPlanV1.deterministicBulkPlanID(importPlan: plan, atomicity: .allOrNothing, chunks: [chunk])
        return (plan, try BulkCommandPlanV1(bulkPlanID: bulkPlanID, importPlan: plan, atomicity: .allOrNothing, chunks: [chunk]))
    }
}

@MainActor private final class C08WriterAdapter: WorkspaceWriterAdapterPortV1 {
    private(set) var applyCount = 0
    private let lifecycleAdapter: WorkspaceWriterAdapterV1

    init(modelContext: ModelContext) {
        lifecycleAdapter = WorkspaceWriterAdapterV1(modelContext: modelContext)
    }

    func apply(_ command: WorkspaceCommandV1, occurredAt: Date, temporaryRelativePath: String) throws -> WorkspaceMutationEffectV1 {
        if case .applyImportBulk = command {
            return try lifecycleAdapter.apply(command, occurredAt: occurredAt,
                temporaryRelativePath: temporaryRelativePath)
        }
        guard case let .createFirstSign(value) = command else { throw WorkspaceMutationFailureV1.unsupportedCommand }
        applyCount += 1
        var identities = [try WorkspaceEntityIdentityV1(kind: .asset, id: value.assetID)]
        if let site = value.newSite { identities.append(try WorkspaceEntityIdentityV1(kind: .site, id: site.id)) }
        return try WorkspaceMutationEffectV1(affectedEntities: identities, temporaryRelativePath: temporaryRelativePath)
    }

    func rollback() { lifecycleAdapter.rollback() }
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

private struct C08MismatchedCreateAssetMaterializer: ImportWorkspaceCommandMaterializingV1 {
    func materialize(_ context: ImportCommandMaterializationContextV1) throws -> WorkspaceMutationRequestV1 {
        try WorkspaceMutationRequestV1(mutationID: context.mutationID, expectedRevision: context.expectedRevision, command: .createFirstSign(.init(siteID: C08.id(980_110), newSite: .init(id: C08.id(980_110), label: "C08 site", address: nil, timeZoneID: "UTC"), assetID: C08.id(980_112), assetLabel: "C08 mismatched asset", packID: "c08.pack", packSchemaVersion: 1, packContentVersion: 1, createdAt: C08.time)))
    }
}

private final class C08FixedRequestMaterializer: ImportWorkspaceCommandMaterializingV1, @unchecked Sendable {
    private let request: WorkspaceMutationRequestV1
    private let lock = NSLock()
    private var invocations = 0
    init(_ request: WorkspaceMutationRequestV1) { self.request = request }
    var count: Int { lock.lock(); defer { lock.unlock() }; return invocations }
    func materialize(_ context: ImportCommandMaterializationContextV1) throws -> WorkspaceMutationRequestV1 {
        lock.lock(); defer { lock.unlock() }
        invocations += 1
        return request
    }
}

@MainActor private final class C08Stack {
    let container: ModelContainer
    let context: ModelContext
    let adapter: C08WriterAdapter
    let writer: WorkspaceWriterV1
    let lifecycle: ImportBulkLifecycleAdapterV1
    let coordinator: ImportBulkCoordinatorV1

    convenience init() throws {
        try self.init(
            atomicMaterializer: C08RejectingMaterializer(),
            atomicAllowedWorkspaceCommandKinds: [.applyAssetSemantics]
        )
    }

    init(
        atomicMaterializer: any ImportWorkspaceCommandMaterializingV1,
        atomicAllowedWorkspaceCommandKinds: Set<WorkspaceCommandKindV1>,
        createAssetMaterializer: any ImportWorkspaceCommandMaterializingV1 = C08CreateAssetMaterializer()
    ) throws {
        let models = PersistentSchemaV45.models + [ImportMappingProfileRowV1.self, BulkSessionRowV1.self, BulkCommitReceiptRowV1.self]
        let schema = Schema(models, version: PersistentSchemaV45.versionIdentifier)
        let container = try ModelContainer(for: schema, migrationPlan: nil, configurations: [ModelConfiguration("C08ImportBulk", schema: schema, isStoredInMemoryOnly: true, allowsSave: true, cloudKitDatabase: .none)])
        self.container = container
        context = container.mainContext
        context.autosaveEnabled = false
        let workspaceID = C08.workspace(), generationID = C08.id(980_090)
        let identity = try WorkspaceReplicaIdentityV1(workspaceID: workspaceID, replicaID: ReplicaID(rawValue: C08.id(980_091)))
        let journal = try MutationJournalStoreV1(modelContext: context, identity: identity, generationID: generationID)
        adapter = C08WriterAdapter(modelContext: context)
        writer = try WorkspaceWriterV1(identity: identity, generationID: generationID, initialRevision: journal.currentRevision(writerInstanceID: C08.id(980_092)), clock: C08Clock(), idSource: C08IDSource(value: C08.id(980_092)), fileAuthority: C08FileAuthority(), adapter: adapter, journalStore: journal)
        let registration = try C08Stack.registration()
        lifecycle = try ImportBulkLifecycleAdapterV1(registrations: [registration], modelContext: context)
        let materializers = try ImportCommandKindV1.allCases.map { kind in
            if kind == .applyAtomicWorkspaceBundle {
                return try ImportBulkMaterializerRegistrationV1(
                    kind: kind,
                    materializer: atomicMaterializer,
                    allowedWorkspaceCommandKinds: atomicAllowedWorkspaceCommandKinds
                )
            }
            return try ImportBulkMaterializerRegistrationV1(
                kind: kind,
                materializer: kind == .createAsset ? createAssetMaterializer : C08RejectingMaterializer()
            )
        }
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

    func testFreshCreatePreparationEnrollsOnlyAbsentTargetsAndPreservesCAS() throws {
        let (plan, bulk) = try C08.plan()
        let stack = try c08Stack()
        let preview = try stack.coordinator.preview(importPlan: plan, bulkPlan: bulk,
            currentSourceSHA256: plan.source.sourceSHA256,
            currentWorkspaceRevisionSHA256: plan.workspaceRevisionSHA256)
        let begun = try stack.coordinator.begin(sessionID: C08.id(980_130), preview: preview,
            currentSourceSHA256: plan.source.sourceSHA256,
            currentWorkspaceRevisionSHA256: plan.workspaceRevisionSHA256)
        let base = WorkspaceExpectedRevisionV1(snapshot: try stack.writer.currentRevision())
        func context(_ expected: WorkspaceExpectedRevisionV1) throws -> ImportCommandMaterializationContextV1 {
            try .init(plan: plan, rowIdentity: plan.rows[0].identity, row: plan.rows[0],
                command: plan.rows[0].commands[0], chunkIndex: 0,
                mutationID: bulk.chunks[0].mutationIDs[0], expectedRevision: expected)
        }
        func expected(_ rows: [WorkspaceEntityRevisionV1]) throws -> WorkspaceExpectedRevisionV1 {
            try .init(workspaceID: base.workspaceID, generationID: base.generationID,
                writerInstanceID: base.writerInstanceID, workspaceRevision: base.workspaceRevision,
                entityRevisions: rows)
        }
        let input = try context(base)
        let raw = try C08CreateAssetMaterializer().materializeValidated(input)
        let materializer = C08FixedRequestMaterializer(raw)
        let registration = try ImportBulkMaterializerRegistrationV1(kind: .createAsset, materializer: materializer)
        let prepared = try registration.prepareFreshRequest(input)
        XCTAssertEqual(materializer.count, 1)
        XCTAssertEqual(prepared.command, raw.command)
        XCTAssertEqual(prepared.mutationID, raw.mutationID)
        XCTAssertEqual(prepared.expectedRevision.workspaceID, base.workspaceID)
        XCTAssertEqual(prepared.expectedRevision.generationID, base.generationID)
        XCTAssertEqual(prepared.expectedRevision.writerInstanceID, base.writerInstanceID)
        XCTAssertEqual(prepared.expectedRevision.workspaceRevision, base.workspaceRevision)
        let asset = try WorkspaceEntityIdentityV1(kind: .asset, id: C08.id(980_111))
        let site = try WorkspaceEntityIdentityV1(kind: .site, id: C08.id(980_110))
        let session = try WorkspaceEntityIdentityV1(kind: .bulkSession, id: begun.sessionID)
        let rows = Dictionary(uniqueKeysWithValues: prepared.expectedRevision.entityRevisions.map { ($0.identity, $0.revision) })
        XCTAssertEqual(rows[asset], 0); XCTAssertEqual(rows[site], 0); XCTAssertEqual(rows[session], 1)
        XCTAssertEqual(Set(rows.keys), Set(base.entityRevisions.map(\.identity)).union([asset, site]))
        for row in base.entityRevisions { XCTAssertEqual(rows[row.identity], row.revision) }
        try context(prepared.expectedRevision).validate(materialized: prepared)
        let enrolled = C08FixedRequestMaterializer(prepared)
        XCTAssertEqual(try ImportBulkMaterializerRegistrationV1(kind: .createAsset, materializer: enrolled)
            .prepareFreshRequest(context(prepared.expectedRevision)), prepared)
        XCTAssertEqual(enrolled.count, 1)

        let incumbent = try expected(base.entityRevisions + [.init(identity: asset, revision: 7)])
        let incumbentContext = try context(incumbent)
        let incumbentRaw = try C08CreateAssetMaterializer().materializeValidated(incumbentContext)
        let incumbentPrepared = try ImportBulkMaterializerRegistrationV1(kind: .createAsset,
            materializer: C08FixedRequestMaterializer(incumbentRaw)).prepareFreshRequest(incumbentContext)
        XCTAssertEqual(incumbentPrepared.expectedRevision.entityRevisions.first { $0.identity == asset }?.revision, 7)
        XCTAssertEqual(incumbentPrepared.expectedRevision.entityRevisions.first { $0.identity == site }?.revision, 0)
        XCTAssertThrowsError(try stack.writer.execute(incumbentPrepared)) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .staleEntityRevision(asset))
        }

        guard case let .createFirstSign(value) = raw.command else { return XCTFail("Expected create fixture") }
        let placementID = C08.id(980_131)
        let placedCommand = WorkspaceCommandV1.createFirstSign(.init(siteID: value.siteID, newSite: value.newSite,
            assetID: value.assetID, assetLabel: value.assetLabel, packID: value.packID,
            packSchemaVersion: value.packSchemaVersion, packContentVersion: value.packContentVersion,
            createdAt: value.createdAt, initialPlacementMutationID: raw.mutationID,
            initialPlacementEventID: placementID,
            initialPhysicalEpisodeID: try .init(rawValue: C08.id(980_132))))
        let placed = try ImportBulkMaterializerRegistrationV1(kind: .createAsset,
            materializer: C08FixedRequestMaterializer(.init(mutationID: raw.mutationID,
                expectedRevision: base, command: placedCommand))).prepareFreshRequest(input)
        XCTAssertEqual(placed.command, placedCommand)
        XCTAssertEqual(placed.expectedRevision.entityRevisions,
            try expected(base.entityRevisions + [.init(identity: asset, revision: 0),
                .init(identity: site, revision: 0),
                .init(identity: WorkspaceEntityIdentityV1(kind: .assetPlacementEvent, id: placementID), revision: 0)]).entityRevisions)

        let arbitrary = try WorkspaceEntityIdentityV1(kind: .asset, id: C08.id(980_133))
        let hostileBases = try [
            expected(base.entityRevisions + [.init(identity: arbitrary, revision: 0)]),
            expected(base.entityRevisions + [.init(identity: asset, revision: 9)]),
            expected([]),
            expected(base.entityRevisions.map { .init(identity: $0.identity, revision: $0.revision + 1) }),
            WorkspaceExpectedRevisionV1(workspaceID: base.workspaceID, generationID: base.generationID,
                writerInstanceID: C08.id(980_136), workspaceRevision: base.workspaceRevision,
                entityRevisions: base.entityRevisions)
        ]
        for hostile in hostileBases {
            let hostileMaterializer = C08FixedRequestMaterializer(.init(mutationID: raw.mutationID,
                expectedRevision: hostile, command: raw.command))
            XCTAssertThrowsError(try ImportBulkMaterializerRegistrationV1(kind: .createAsset,
                materializer: hostileMaterializer).prepareFreshRequest(input)) {
                XCTAssertEqual($0 as? ImportBulkFailureV1, .invalidValue)
            }
            XCTAssertEqual(hostileMaterializer.count, 1)
        }
        XCTAssertThrowsError(try ImportBulkMaterializerRegistrationV1(kind: .createAsset,
            materializer: C08FixedRequestMaterializer(.init(mutationID: MutationIDV1(rawValue: C08.id(980_134)),
                expectedRevision: base, command: raw.command))).prepareFreshRequest(input)) {
            XCTAssertEqual($0 as? ImportBulkFailureV1, .invalidValue)
        }
        let wrongKind = C08FixedRequestMaterializer(raw)
        XCTAssertThrowsError(try ImportBulkMaterializerRegistrationV1(kind: .updateAssetExactKey,
            materializer: wrongKind).prepareFreshRequest(input)) {
            XCTAssertEqual($0 as? ImportBulkFailureV1, .unsupportedSchema)
        }
        XCTAssertEqual(wrongKind.count, 0)
        let unsupported = WorkspaceCommandV1.updateSiteTimeZone(.init(siteID: C08.id(980_110),
            timeZoneID: "UTC", confirmedAt: C08.time))
        XCTAssertThrowsError(try ImportBulkMaterializerRegistrationV1(kind: .createAsset,
            materializer: C08FixedRequestMaterializer(.init(mutationID: raw.mutationID,
                expectedRevision: base, command: unsupported))).prepareFreshRequest(input)) {
            XCTAssertEqual($0 as? ImportBulkFailureV1, .unsupportedSchema)
        }

        // A genuine intervening lifecycle write must invalidate the captured CAS;
        // preparation cannot refresh it or execute the counted create effect.
        _ = try stack.coordinator.begin(sessionID: C08.id(980_135), preview: preview,
            currentSourceSHA256: plan.source.sourceSHA256,
            currentWorkspaceRevisionSHA256: plan.workspaceRevisionSHA256)
        XCTAssertThrowsError(try stack.writer.execute(prepared)) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .staleWorkspaceRevision)
        }
        XCTAssertEqual(stack.adapter.applyCount, 0)
        XCTAssertNil(try stack.writer.durableReceipt(mutationID: raw.mutationID))
    }

    func testFreshPreparationLeavesAllowedNonCreateRequestUnchanged() throws {
        let (plan, bulk) = try C08.atomicPlan()
        let stack = try c08Stack()
        let base = WorkspaceExpectedRevisionV1(snapshot: try stack.writer.currentRevision())
        let input = try ImportCommandMaterializationContextV1(plan: plan,
            rowIdentity: plan.rows[0].identity, row: plan.rows[0], command: plan.rows[0].commands[0],
            chunkIndex: 0, mutationID: bulk.chunks[0].mutationIDs[0], expectedRevision: base)
        let command = WorkspaceCommandV1.applySavedSmartView(try .init(deletingID: C08.id(980_140),
            workspaceID: plan.workspaceID.rawValue, stableID: "c08_saved_view", expectedDescriptorRevision: 1,
            mutationID: input.mutationID.rawValue))
        let raw = WorkspaceMutationRequestV1(mutationID: input.mutationID, expectedRevision: base, command: command)
        let materializer = C08FixedRequestMaterializer(raw)
        let registration = try ImportBulkMaterializerRegistrationV1(kind: .applyAtomicWorkspaceBundle,
            materializer: materializer, allowedWorkspaceCommandKinds: [.applySavedSmartView])
        XCTAssertEqual(try registration.prepareFreshRequest(input), raw)
        XCTAssertEqual(materializer.count, 1)
        XCTAssertEqual(stack.adapter.applyCount, 0)
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

    func testV23P04C08AtomicBundleRegistrationIsExplicitAndFailClosed() throws {
        let rejecting = C08RejectingMaterializer()
        XCTAssertThrowsError(try ImportBulkMaterializerRegistrationV1(
            kind: .applyAtomicWorkspaceBundle,
            materializer: rejecting
        ))
        XCTAssertThrowsError(try ImportBulkMaterializerRegistrationV1(
            kind: .applyAtomicWorkspaceBundle,
            materializer: rejecting,
            allowedWorkspaceCommandKinds: []
        ))
        XCTAssertThrowsError(try ImportBulkMaterializerRegistrationV1(
            kind: .applyAtomicWorkspaceBundle,
            materializer: rejecting,
            allowedWorkspaceCommandKinds: [.applyAssetSemantics, .applyAssetPlacementChange]
        ))
        XCTAssertThrowsError(try ImportBulkMaterializerRegistrationV1(
            kind: .applyAtomicWorkspaceBundle,
            materializer: rejecting,
            allowedWorkspaceCommandKinds: [.eraseWorkspace]
        ))
        XCTAssertThrowsError(try ImportBulkMaterializerRegistrationV1(
            kind: .createAsset,
            materializer: rejecting,
            allowedWorkspaceCommandKinds: [.eraseWorkspace]
        ))

        let legacy = try ImportCommandKindV1.allCases.filter { !$0.createsAggregate }.map {
            try ImportBulkMaterializerRegistrationV1(kind: $0, materializer: rejecting)
        }
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: legacy.map { ($0.kind, $0.allowedWorkspaceCommandKinds) }), [
            .createLocationNode: [.applyLocationHierarchyChange],
            .createAsset: [.createFirstSign, .applyAssetSemantics],
            .placeAsset: [.applyAssetPlacementChange],
            .updateAssetExactKey: [.applyAssetSemantics],
            .appendPlacementPose: [.applyPlacementPose]
        ])

        let (plan, bulk) = try C08.atomicPlan()
        XCTAssertTrue(plan.rows[0].commands[0].kind.createsAggregate)
        XCTAssertNil(plan.rows[0].commands[0].expectedRevision)
        XCTAssertNil(plan.rows[0].commands[0].targetStableID)
        let stack = try C08Stack(
            atomicMaterializer: C08CreateAssetMaterializer(),
            atomicAllowedWorkspaceCommandKinds: [.applyAssetSemantics]
        )
        let preview = try stack.coordinator.preview(importPlan: plan, bulkPlan: bulk, currentSourceSHA256: plan.source.sourceSHA256, currentWorkspaceRevisionSHA256: plan.workspaceRevisionSHA256)
        let begun = try stack.coordinator.begin(sessionID: C08.id(980_123), preview: preview, currentSourceSHA256: plan.source.sourceSHA256, currentWorkspaceRevisionSHA256: plan.workspaceRevisionSHA256)
        XCTAssertThrowsError(try stack.coordinator.commitFirstMissingChunk(session: begun, importPlan: plan, bulkPlan: bulk, currentSourceSHA256: plan.source.sourceSHA256, currentWorkspaceRevisionSHA256: plan.workspaceRevisionSHA256, cancellationRequested: false)) { error in
            XCTAssertEqual(error as? ImportBulkFailureV1, .unsupportedSchema)
        }
        XCTAssertEqual(stack.adapter.applyCount, 0)
    }

    func testV23P04C08C32AggregateRegistrationDoesNotAlterAssetPlanDigest() throws {
        let (first, _) = try C08.plan()
        let (repeated, _) = try C08.plan()
        XCTAssertEqual(first.planSHA256, repeated.planSHA256)
        XCTAssertEqual(first.rows.map(\.identity), repeated.rows.map(\.identity))
        XCTAssertEqual(first.rows.flatMap(\.commands).map(\.kind), [.createAsset])
        XCTAssertTrue(ImportCommandKindV1.allCases.contains(.applyAtomicWorkspaceBundle))
        XCTAssertTrue(WorkspaceCommandKindV1.allCases.contains(.applyPartyContactSiteRoleImport))
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

        // Stable matching keys retain their exact accepted bytes; ordinary text may span lines.
        let acceptedKey = "Asset_Caf\u{00E9} 001\tB"
        let acceptedIdentity = try ImportRowIdentityV1(
            workspaceID: plan.workspaceID, sourceSHA256: C08.sourceSHA256, sourceOrdinal: 1,
            canonicalRowSHA256: C08.sourceSHA256, stableExternalKey: acceptedKey,
            schemaReleaseID: "c08_schema", schemaRelease: 1
        )
        let acceptedBytes = try ImportBulkCanonicalCodecV1.encode(acceptedIdentity)
        let acceptedRoundTrip = try ImportBulkCanonicalCodecV1.decode(ImportRowIdentityV1.self, from: acceptedBytes)
        try acceptedRoundTrip.validate()
        XCTAssertEqual(Array(acceptedIdentity.stableExternalKey.utf8), Array(acceptedKey.utf8))
        XCTAssertEqual(Array(acceptedRoundTrip.stableExternalKey.utf8), Array(acceptedKey.utf8))
        XCTAssertEqual(acceptedRoundTrip.identitySHA256, acceptedIdentity.identitySHA256)
        XCTAssertEqual(try ImportBulkCanonicalCodecV1.encode(acceptedRoundTrip), acceptedBytes)

        // Reconstruct a digest-valid identity permitted by the old multiline-key contract.
        struct LegacyIdentityBasis: Encodable {
            let schemaVersion: Int
            let workspaceID: WorkspaceID
            let sourceSHA256: String
            let sourceOrdinal: UInt64
            let canonicalRowSHA256: String
            let stableExternalKey: String
            let schemaReleaseID: String
            let schemaRelease: UInt64
        }
        let newlineSequences = ["\n", "\r", "\r\n", "\u{000B}", "\u{000C}", "\u{0085}", "\u{2028}", "\u{2029}"]
        for newline in newlineSequences {
            let multilineKey = "asset\(newline)001"
            XCTAssertThrowsError(try ImportRowIdentityV1(
                workspaceID: plan.workspaceID, sourceSHA256: C08.sourceSHA256, sourceOrdinal: 1,
                canonicalRowSHA256: C08.sourceSHA256, stableExternalKey: multilineKey,
                schemaReleaseID: "c08_schema", schemaRelease: 1
            )) { error in
                XCTAssertEqual(error as? ImportBulkFailureV1, .invalidValue)
            }
            let legacyBasis = LegacyIdentityBasis(
                schemaVersion: ImportRowIdentityV1.schemaVersion, workspaceID: plan.workspaceID,
                sourceSHA256: C08.sourceSHA256, sourceOrdinal: 1,
                canonicalRowSHA256: C08.sourceSHA256, stableExternalKey: multilineKey,
                schemaReleaseID: "c08_schema", schemaRelease: 1
            )
            let legacyDigest = try ImportBulkCanonicalCodecV1.sha256(legacyBasis)
            var legacyObject = try XCTUnwrap(JSONSerialization.jsonObject(with: acceptedBytes) as? [String: Any])
            legacyObject["stableExternalKey"] = multilineKey
            legacyObject["identitySHA256"] = legacyDigest
            let legacyTransportBytes = try JSONSerialization.data(withJSONObject: legacyObject, options: [.sortedKeys])
            let legacyIdentity = try JSONDecoder().decode(ImportRowIdentityV1.self, from: legacyTransportBytes)
            let replayedIdentity = try ImportBulkCanonicalCodecV1.decode(
                ImportRowIdentityV1.self, from: ImportBulkCanonicalCodecV1.encode(legacyIdentity)
            )
            XCTAssertEqual(Array(replayedIdentity.stableExternalKey.utf8), Array(multilineKey.utf8))
            XCTAssertEqual(replayedIdentity.identitySHA256, legacyDigest)
            XCTAssertThrowsError(try replayedIdentity.validate()) { error in
                XCTAssertEqual(error as? ImportBulkFailureV1, .invalidValue)
            }
            XCTAssertThrowsError(try ImportPlanRowV1(
                identity: replayedIdentity, disposition: .duplicateSource, reasons: [.duplicateExternalKey],
                mappedFields: [], commands: [], expectedTargetRevision: nil
            )) { error in
                XCTAssertEqual(error as? ImportBulkFailureV1, .invalidValue)
            }
            var replayedRow = try XCTUnwrap(
                JSONSerialization.jsonObject(with: ImportBulkCanonicalCodecV1.encode(plan.rows[0])) as? [String: Any]
            )
            replayedRow["identity"] = legacyObject
            XCTAssertThrowsError(try JSONDecoder().decode(
                ImportPlanRowV1.self, from: JSONSerialization.data(withJSONObject: replayedRow, options: [.sortedKeys])
            )) { error in
                XCTAssertEqual(error as? ImportBulkFailureV1, .invalidValue)
            }
            XCTAssertThrowsError(try ImportProposedCommandV1.canonicalPayloadSHA256(
                commandID: "create_asset_001", kind: .createAsset, targetStableID: nil,
                expectedRevision: nil, dependencyCommandIDs: [], rowIdentity: replayedIdentity,
                schemaRelease: plan.schemaRelease, mappedFields: []
            )) { error in
                XCTAssertEqual(error as? ImportBulkFailureV1, .invalidValue)
            }

            let multilineText = "First\(newline)second"
            XCTAssertNoThrow(try ImportBulkCanonicalCodecV1.requireText(multilineText))
            let mappedText = try ImportMappedFieldV1(key: "asset_name", value: multilineText)
            let mappedRoundTrip = try ImportBulkCanonicalCodecV1.decode(
                ImportMappedFieldV1.self, from: ImportBulkCanonicalCodecV1.encode(mappedText)
            )
            XCTAssertEqual(Array(mappedRoundTrip.value.utf8), Array(multilineText.utf8))
            let correction = try ImportCorrectionArtifactV1(
                rowIdentity: acceptedIdentity, errorCode: .staleExpectedRevision,
                offendingColumn: "asset_name", boundedCorrectionHint: multilineText
            )
            let correctionRoundTrip = try ImportBulkCanonicalCodecV1.decode(
                ImportCorrectionArtifactV1.self, from: ImportBulkCanonicalCodecV1.encode(correction)
            )
            try correctionRoundTrip.validate()
            XCTAssertEqual(Array(correctionRoundTrip.boundedCorrectionHint.utf8), Array(multilineText.utf8))
        }
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

        let effectStack = try c08Stack(), effectCoordinator = effectStack.coordinator
        let effectPreview = try effectCoordinator.preview(importPlan: plan, bulkPlan: bulk, currentSourceSHA256: plan.source.sourceSHA256, currentWorkspaceRevisionSHA256: plan.workspaceRevisionSHA256)
        let effectBegun = try effectCoordinator.begin(sessionID: C08.id(980_032), preview: effectPreview, currentSourceSHA256: plan.source.sourceSHA256, currentWorkspaceRevisionSHA256: plan.workspaceRevisionSHA256)
        let effectContext = try ImportCommandMaterializationContextV1(plan: plan, rowIdentity: plan.rows[0].identity, row: plan.rows[0], command: plan.rows[0].commands[0], chunkIndex: 0, mutationID: bulk.chunks[0].mutationIDs[0], expectedRevision: .init(snapshot: try effectStack.writer.currentRevision()))
        let effectRequest = try ImportBulkMaterializerRegistrationV1(kind: .createAsset,
            materializer: C08CreateAssetMaterializer()).prepareFreshRequest(effectContext)
        _ = try effectStack.writer.execute(effectRequest)
        XCTAssertNotNil(try effectStack.writer.durableReceipt(mutationID: bulk.chunks[0].mutationIDs[0]))
        XCTAssertNil(try effectStack.lifecycle.durableReceipt(workspaceID: plan.workspaceID, bulkPlan: bulk, chunkIndex: 0))
        let recoveredEffect = try effectCoordinator.commitFirstMissingChunk(session: effectBegun, importPlan: plan, bulkPlan: bulk, currentSourceSHA256: plan.source.sourceSHA256, currentWorkspaceRevisionSHA256: plan.workspaceRevisionSHA256, cancellationRequested: true)
        XCTAssertEqual(effectStack.adapter.applyCount, 1)
        XCTAssertEqual(recoveredEffect.state, .active)
        XCTAssertEqual(recoveredEffect.chunkReceipts.count, 1)
        XCTAssertEqual(recoveredEffect.chunkReceipts[0].disposition, .committed)
        XCTAssertEqual(recoveredEffect.chunkReceipts[0].committedMutationIDs, [bulk.chunks[0].mutationIDs[0]])
        XCTAssertEqual(try effectStack.lifecycle.durableSession(sessionID: effectBegun.sessionID), recoveredEffect)
        XCTAssertEqual(try effectStack.lifecycle.durableReceipt(workspaceID: plan.workspaceID, bulkPlan: bulk, chunkIndex: 0), recoveredEffect.chunkReceipts[0])

        let mismatchedStack = try c08Stack(), mismatchedCoordinator = mismatchedStack.coordinator
        let mismatchedPreview = try mismatchedCoordinator.preview(importPlan: plan, bulkPlan: bulk, currentSourceSHA256: plan.source.sourceSHA256, currentWorkspaceRevisionSHA256: plan.workspaceRevisionSHA256)
        let mismatchedBegun = try mismatchedCoordinator.begin(sessionID: C08.id(980_033), preview: mismatchedPreview, currentSourceSHA256: plan.source.sourceSHA256, currentWorkspaceRevisionSHA256: plan.workspaceRevisionSHA256)
        let mismatchedContext = try ImportCommandMaterializationContextV1(plan: plan, rowIdentity: plan.rows[0].identity, row: plan.rows[0], command: plan.rows[0].commands[0], chunkIndex: 0, mutationID: bulk.chunks[0].mutationIDs[0], expectedRevision: .init(snapshot: try mismatchedStack.writer.currentRevision()))
        _ = try mismatchedStack.writer.execute(ImportBulkMaterializerRegistrationV1(kind: .createAsset,
            materializer: C08MismatchedCreateAssetMaterializer()).prepareFreshRequest(mismatchedContext))
        XCTAssertThrowsError(try mismatchedCoordinator.commitFirstMissingChunk(session: mismatchedBegun, importPlan: plan, bulkPlan: bulk, currentSourceSHA256: plan.source.sourceSHA256, currentWorkspaceRevisionSHA256: plan.workspaceRevisionSHA256, cancellationRequested: true))
        XCTAssertEqual(mismatchedStack.adapter.applyCount, 1)
        XCTAssertEqual(try mismatchedStack.lifecycle.durableSession(sessionID: mismatchedBegun.sessionID), mismatchedBegun)
        XCTAssertNil(try mismatchedStack.lifecycle.durableReceipt(workspaceID: plan.workspaceID, bulkPlan: bulk, chunkIndex: 0))

        let rejectingStack = try C08Stack(atomicMaterializer: C08RejectingMaterializer(), atomicAllowedWorkspaceCommandKinds: [.applyAssetSemantics], createAssetMaterializer: C08RejectingMaterializer())
        let rejectingPreview = try rejectingStack.coordinator.preview(importPlan: plan, bulkPlan: bulk, currentSourceSHA256: plan.source.sourceSHA256, currentWorkspaceRevisionSHA256: plan.workspaceRevisionSHA256)
        let rejectingBegun = try rejectingStack.coordinator.begin(sessionID: C08.id(980_034), preview: rejectingPreview, currentSourceSHA256: plan.source.sourceSHA256, currentWorkspaceRevisionSHA256: plan.workspaceRevisionSHA256)
        let rejectingContext = try ImportCommandMaterializationContextV1(plan: plan, rowIdentity: plan.rows[0].identity, row: plan.rows[0], command: plan.rows[0].commands[0], chunkIndex: 0, mutationID: bulk.chunks[0].mutationIDs[0], expectedRevision: .init(snapshot: try rejectingStack.writer.currentRevision()))
        _ = try rejectingStack.writer.execute(ImportBulkMaterializerRegistrationV1(kind: .createAsset,
            materializer: C08CreateAssetMaterializer()).prepareFreshRequest(rejectingContext))
        XCTAssertThrowsError(try rejectingStack.coordinator.commitFirstMissingChunk(session: rejectingBegun, importPlan: plan, bulkPlan: bulk, currentSourceSHA256: plan.source.sourceSHA256, currentWorkspaceRevisionSHA256: plan.workspaceRevisionSHA256, cancellationRequested: true)) { error in
            XCTAssertEqual(error as? ImportBulkFailureV1, .unsupportedSchema)
        }
        XCTAssertEqual(rejectingStack.adapter.applyCount, 1)
        XCTAssertEqual(try rejectingStack.lifecycle.durableSession(sessionID: rejectingBegun.sessionID), rejectingBegun)
        XCTAssertNil(try rejectingStack.lifecycle.durableReceipt(workspaceID: plan.workspaceID, bulkPlan: bulk, chunkIndex: 0))
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
        // The real writer effect is durable while the authentic begun session
        // still lacks its C08 chunk receipt, matching I01's existing recovery edge.
        _ = try stack.writer.execute(ImportBulkMaterializerRegistrationV1(kind: .createAsset,
            materializer: C08CreateAssetMaterializer()).prepareFreshRequest(recoveryContext))
        XCTAssertNotNil(try stack.writer.durableReceipt(mutationID: bulk.chunks[0].mutationIDs[0]))
        XCTAssertNil(try stack.lifecycle.durableReceipt(workspaceID: plan.workspaceID, bulkPlan: bulk, chunkIndex: 0))
        XCTAssertEqual(try stack.lifecycle.durableSession(sessionID: begun.sessionID), begun)
        let recoveredStartingPoint = begun
        let committedByCoordinator = try coordinator.commitFirstMissingChunk(session: recoveredStartingPoint, importPlan: plan, bulkPlan: bulk, currentSourceSHA256: plan.source.sourceSHA256, currentWorkspaceRevisionSHA256: plan.workspaceRevisionSHA256, cancellationRequested: false)
        XCTAssertEqual(committedByCoordinator.state, .completed)
        let historyBeforeReplay = try stack.writer.sourceMutationHistorySnapshot()
        let recovered = try coordinator.commitFirstMissingChunk(session: committedByCoordinator, importPlan: plan, bulkPlan: bulk, currentSourceSHA256: plan.source.sourceSHA256, currentWorkspaceRevisionSHA256: plan.workspaceRevisionSHA256, cancellationRequested: false)
        XCTAssertEqual(recovered.chunkReceipts, committedByCoordinator.chunkReceipts)
        XCTAssertEqual(stack.adapter.applyCount, 1)
        XCTAssertEqual(try stack.writer.sourceMutationHistorySnapshot(), historyBeforeReplay)
        XCTAssertEqual(try stack.lifecycle.durableSession(sessionID: begun.sessionID), committedByCoordinator)
        // A completed receipt-bearing session can never be rewound to begun.
        XCTAssertThrowsError(try stack.lifecycle.record(session: begun, replacing: committedByCoordinator.sessionSHA256)) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .invalidCommand)
        }
        XCTAssertEqual(try stack.lifecycle.durableSession(sessionID: begun.sessionID), committedByCoordinator)
        XCTAssertEqual(try stack.lifecycle.durableReceipt(workspaceID: plan.workspaceID, bulkPlan: bulk, chunkIndex: 0), committedByCoordinator.chunkReceipts[0])
        XCTAssertEqual(try stack.writer.sourceMutationHistorySnapshot(), historyBeforeReplay)
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

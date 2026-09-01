import Foundation
import SwiftData
import XCTest

@testable import FieldEvidenceApp

private struct C37Corpus: Decodable {
    struct Production: Decodable {
        let status: String; let selectedProfileCount: Int; let fileActionCount: Int
        let canonicalWriteCount: Int; let providerName: String?; let providerSuccessClaim: Bool
    }
    struct SyntheticAuthority: Decodable {
        let selectedProfileCount: Int; let representation: String
        let shippedProductionSelectedProfileCount: Int
        let deterministicPreview: Bool; let deterministicExport: Bool
    }
    struct Claims: Decodable {
        let fileCreatedMeansSynced: Bool; let fileCreatedMeansDelivered: Bool
        let fileCreatedMeansProviderAccepted: Bool; let providerSDK: Bool
        let networkEndpoint: Bool; let credentials: Bool; let securityClaim: Bool
        let identityClaim: Bool; let legalClaim: Bool; let shippedProductionProfileSelected: Bool
        let previewWritesCanonicalData: Bool; let automaticImport: Bool
    }
    let schema: String; let schemaVersion: Int; let cardID: String
    let testOnly: Bool; let synthetic: Bool; let containsCustomerData: Bool; let containsSecrets: Bool
    let evidenceIDs: [String]; let production: Production
    let syntheticAuthority: SyntheticAuthority; let hostileCases: [String]
    let recoveryCases: [String]; let claims: Claims
}

private enum C37 {
    static let date = C50IncumbentFileAdapterTestSupport.fixedDate
    static func id(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "C3700000-0000-4000-8000-%012x", value))!
    }
    static func digest(_ value: Character) -> String { String(repeating: String(value), count: 64) }
    static func fixture() throws -> C37Corpus {
        let bundle = Bundle(for: V9_100IncumbentFileAdapterWorkflowTests.self)
        let url = bundle.url(
            forResource: "V23P04C37IncumbentFileAdapterWorkflowCorpusV1",
            withExtension: "json", subdirectory: "Fixtures/V23/IncumbentExchange"
        ) ?? bundle.url(forResource: "V23P04C37IncumbentFileAdapterWorkflowCorpusV1", withExtension: "json")
        guard let url else { throw IncumbentFileContractFailureV1.invalidValue }
        return try JSONDecoder().decode(C37Corpus.self, from: Data(contentsOf: url))
    }

    static func registry(
        release: IncumbentFileProfileReleaseV1? = nil
    ) throws -> ClosedIncumbentAdapterRegistryV1 {
        if let release {
            let selection = try C50IncumbentFileAdapterTestSupport.enabledSelection(for: release)
            return try ClosedIncumbentAdapterRegistryV1(
                currentProductionReleases: [release], selection: selection,
                selectionHistory: [selection],
                availabilityReceipt: C50IncumbentFileAdapterTestSupport.availability(
                    selected: true, release: release
                )
            )
        }
        let selection = try C50IncumbentFileAdapterTestSupport.disabledSelection()
        return try ClosedIncumbentAdapterRegistryV1(
            currentProductionReleases: [], selection: selection,
            selectionHistory: [selection],
            availabilityReceipt: C50IncumbentFileAdapterTestSupport.availability(selected: false)
        )
    }

    @MainActor
    static func workflow(
        release: IncumbentFileProfileReleaseV1? = nil,
        bulk: ImportBulkCoordinatorV1? = nil
    ) throws -> IncumbentFileAdapterWorkflowCoordinatorV1 {
        let registry = try registry(release: release)
        let adapters: [any IncumbentFileAdapterV1] = if let release {
            [try C50IncumbentFileAdapterTestSupport.adapter(for: release)]
        } else { [] }
        return IncumbentFileAdapterWorkflowCoordinatorV1(
            registry: registry,
            exchange: try IncumbentFileExchangeCoordinatorV1(registry: registry, adapters: adapters),
            importBulk: bulk
        )
    }

    static func inbound(
        workflow: IncumbentFileAdapterWorkflowCoordinatorV1,
        release: IncumbentFileProfileReleaseV1,
        operationSlot: Int = 30
    ) throws -> (IncumbentFileInputV1, IncumbentExchangeScopeV1, IncumbentFileAdapterInboundPreviewV1) {
        let input = try C50IncumbentFileAdapterTestSupport.input()
        let scope = try C50IncumbentFileAdapterTestSupport.scope(
            for: release, operationSlot: operationSlot
        )
        guard case let .inboundPreview(inbound) = try workflow.execute(
            .previewInbound(input: input, scope: scope, at: date)
        ) else { throw IncumbentFileContractFailureV1.invalidValue }
        return (input, scope, inbound)
    }

    static func bulkPlan(
        workspaceID: WorkspaceID,
        sourceSHA256: String,
        mappingProfileSHA256: String? = nil,
        rowKey: String = "asset_001"
    ) throws -> (ImportPlanV1, BulkCommandPlanV1) {
        let budget = try ImportStreamingBudgetV1(
            maximumSourceBytes: 4_096, maximumRows: 2, maximumColumns: 2,
            maximumCellBytes: 128, maximumScalarsPerCell: 128
        )
        let schema = try ImportSchemaReleaseV1(
            releaseID: "c37_c08_schema", release: 1, entityKind: .asset,
            externalKeyColumn: "asset_key", columns: [
                try .init(key: "asset_key", scalar: .identifier, required: true,
                          editableOnExactUpdate: false, maximumCellBytes: 128, maximumScalars: 128)
            ], budget: budget
        )
        let source = try ImportSourceV1(
            sourceID: id(100), workspaceID: workspaceID, kind: .userSelectedFile,
            sourceSHA256: sourceSHA256, byteCount: 64, leaseID: id(101), importedAt: date
        )
        let identity = try ImportRowIdentityV1(
            workspaceID: workspaceID, sourceSHA256: sourceSHA256, sourceOrdinal: 1,
            canonicalRowSHA256: digest("r"), stableExternalKey: rowKey,
            schemaReleaseID: schema.releaseID, schemaRelease: schema.release
        )
        let fields = [try ImportMappedFieldV1(key: "asset_key", value: rowKey)]
        let payload = try ImportProposedCommandV1.canonicalPayloadSHA256(
            commandID: "create_c37_asset", kind: .createAsset, targetStableID: nil,
            expectedRevision: nil, dependencyCommandIDs: [], rowIdentity: identity,
            schemaRelease: schema, mappedFields: fields
        )
        let command = try ImportProposedCommandV1(
            commandID: "create_c37_asset", kind: .createAsset, targetStableID: nil,
            expectedRevision: nil, dependencyCommandIDs: [], payloadSHA256: payload
        )
        let row = try ImportPlanRowV1(
            identity: identity, disposition: .create, reasons: [.exactStableKeyCreate],
            mappedFields: fields, commands: [command], expectedTargetRevision: nil
        )
        let revisionSHA = digest("w")
        let planID = try ImportPlanV1.deterministicPlanID(
            workspaceID: workspaceID, source: source, schemaRelease: schema,
            mappingProfileSHA256: mappingProfileSHA256, workspaceRevisionSHA256: revisionSHA, rows: [row]
        )
        let plan = try ImportPlanV1(
            planID: planID, workspaceID: workspaceID, source: source, schemaRelease: schema,
            mappingProfileSHA256: mappingProfileSHA256, workspaceRevisionSHA256: revisionSHA, rows: [row]
        )
        let mutation = try BulkCommandPlanV1.deterministicMutationID(
            importPlanID: plan.planID, chunkIndex: 0, rowIdentitySHA256: identity.identitySHA256
        )
        let chunk = try BulkChunkPlanV1(
            chunkIndex: 0, rowIdentitySHA256s: [identity.identitySHA256], mutationIDs: [mutation]
        )
        let bulkID = try BulkCommandPlanV1.deterministicBulkPlanID(
            importPlan: plan, atomicity: .allOrNothing, chunks: [chunk]
        )
        return (plan, try BulkCommandPlanV1(
            bulkPlanID: bulkID, importPlan: plan, atomicity: .allOrNothing, chunks: [chunk]
        ))
    }
}

@MainActor private final class C37WriterAdapter: WorkspaceWriterAdapterPortV1 {
    private(set) var applyCount = 0
    private var hasUncommittedApply = false
    func apply(
        _ command: WorkspaceCommandV1, occurredAt: Date, temporaryRelativePath: String
    ) throws -> WorkspaceMutationEffectV1 {
        guard case let .createFirstSign(value) = command else {
            throw WorkspaceMutationFailureV1.unsupportedCommand
        }
        applyCount += 1
        hasUncommittedApply = true
        return try WorkspaceMutationEffectV1(affectedEntities: [
            WorkspaceEntityIdentityV1(kind: .asset, id: value.assetID)
        ], temporaryRelativePath: temporaryRelativePath)
    }

    func rollback() {
        guard hasUncommittedApply else { return }
        applyCount -= 1
        hasUncommittedApply = false
    }
}
private struct C37Clock: ApplicationClock { func now() -> Date { C37.date } }
private struct C37IDs: ApplicationIDSource { func makeID() -> UUID { C37.id(180) } }
private struct C37Files: ApplicationFileAuthorityV1 {
    func temporaryRelativePath(mutationID: MutationIDV1, component: String) throws -> String {
        "c37/\(mutationID.rawValue.uuidString.lowercased())/\(component)"
    }
}
private struct C37Materializer: ImportWorkspaceCommandMaterializingV1 {
    func materialize(_ context: ImportCommandMaterializationContextV1) throws -> WorkspaceMutationRequestV1 {
        try WorkspaceMutationRequestV1(
            mutationID: context.mutationID, expectedRevision: context.expectedRevision,
            command: .createFirstSign(.init(
                siteID: C37.id(190), newSite: .init(
                    id: C37.id(190), label: "C37 synthetic site", address: nil, timeZoneID: "UTC"
                ), assetID: C37.id(191), assetLabel: "C37 synthetic imported asset",
                packID: "c37.synthetic", packSchemaVersion: 1, packContentVersion: 1,
                createdAt: C37.date
            ))
        )
    }
}
private struct C37RejectingMaterializer: ImportWorkspaceCommandMaterializingV1 {
    func materialize(_ context: ImportCommandMaterializationContextV1) throws -> WorkspaceMutationRequestV1 {
        throw ImportBulkFailureV1.unsupportedSchema
    }
}

@MainActor private final class C37BulkHarness {
    let context: ModelContext
    let adapter: C37WriterAdapter
    let writer: WorkspaceWriterV1
    let coordinator: ImportBulkCoordinatorV1
    let lifecycle: ImportBulkLifecycleAdapterV1

    init(workspaceID: WorkspaceID, failure: MutationJournalFailureInjectionV1? = nil) throws {
        let models = PersistentSchemaV45.models + [
            ImportMappingProfileRowV1.self, BulkSessionRowV1.self, BulkCommitReceiptRowV1.self
        ]
        let schema = Schema(models, version: PersistentSchemaV45.versionIdentifier)
        let container = try ModelContainer(for: schema, migrationPlan: nil, configurations: [
            ModelConfiguration("C37-C08", schema: schema, isStoredInMemoryOnly: true,
                               allowsSave: true, cloudKitDatabase: .none)
        ])
        context = container.mainContext
        context.autosaveEnabled = false
        let identity = try WorkspaceReplicaIdentityV1(
            workspaceID: workspaceID, replicaID: ReplicaID(rawValue: C37.id(170))
        )
        let generation = C37.id(171)
        let journal = try MutationJournalStoreV1(
            modelContext: context, identity: identity, generationID: generation,
            failureInjection: failure
        )
        adapter = C37WriterAdapter()
        writer = try WorkspaceWriterV1(
            identity: identity, generationID: generation,
            initialRevision: journal.currentRevision(writerInstanceID: C37.id(172)),
            clock: C37Clock(), idSource: C37IDs(), fileAuthority: C37Files(), adapter: adapter,
            journalStore: journal
        )
        let registration = try ImportAdapterRegistrationV1(
            adapterID: "c37_all", adapterVersion: 1, schemaReleaseID: "c37_c08_schema",
            schemaRelease: 1, entityKinds: ImportEntityKindV1.allCases.sorted(),
            requiredSourceKeys: ["asset_key"], dependencyAdapterIDs: [],
            commandKinds: ImportCommandKindV1.allCases.sorted(),
            lifecycleDispositions: [.activeBulkSessionRecoverableOperationalState,
                                    .bulkCommitReceiptImmutableCanonicalAudit,
                                    .importedEntityUsesOrdinaryLifecycle],
            privacyClass: .localOperational, supportsDeterministicExport: true,
            fixtureSHA256s: [C37.digest("f")]
        )
        lifecycle = try ImportBulkLifecycleAdapterV1(registrations: [registration], modelContext: context)
        let materializers = try ImportCommandKindV1.allCases.map { kind in
            try ImportBulkMaterializerRegistrationV1(
                kind: kind, materializer: kind == .createAsset ? C37Materializer() : C37RejectingMaterializer()
            )
        }
        coordinator = try ImportBulkCoordinatorV1(
            writer: writer, lifecycle: lifecycle, materializers: materializers
        )
    }
}

final class V9_100IncumbentFileAdapterWorkflowTests: XCTestCase {
    @MainActor
    func testV23P04C37G01DisabledNoSelectedProfileHasZeroActionsAndClaims() async throws {
        let fixture = try C37.fixture()
        let workflow = try C37.workflow()
        let projection = try workflow.projection(
            context: IncumbentFileAdapterWorkflowContextV1(evaluatedAt: C37.date)
        )
        XCTAssertEqual(projection.state.rawValue, fixture.production.status)
        XCTAssertEqual(fixture.production.selectedProfileCount, 0)
        XCTAssertEqual(IncumbentFileAdapterWorkflowClaimsV1.selectedProductionProfileCount, 0)
        XCTAssertNil(projection.selectedReleaseID)
        XCTAssertNil(projection.providerDisplayToken)
        XCTAssertFalse(projection.canDetectParseOrMap)
        XCTAssertFalse(projection.canPreviewCanonicalImport)
        XCTAssertFalse(projection.canCommitCanonicalImport)
        XCTAssertFalse(projection.canExport)
        XCTAssertEqual(fixture.production.fileActionCount, 0)
        XCTAssertEqual(fixture.production.canonicalWriteCount, 0)
        XCTAssertNil(fixture.production.providerName)
        XCTAssertFalse(fixture.production.providerSuccessClaim)
    }

    @MainActor
    func testV23P04C37A01SyntheticExactProfilePreviewAndExportAreDeterministic() async throws {
        let fixture = try C37.fixture()
        let release = try C50IncumbentFileAdapterTestSupport.profile()
        let workflow = try C37.workflow(release: release)
        let first = try C37.inbound(workflow: workflow, release: release)
        let second = try C37.inbound(workflow: workflow, release: release)
        XCTAssertEqual(first.2, second.2)
        XCTAssertTrue(first.2.isZeroWrite)
        let export = try C50IncumbentFileAdapterTestSupport.projectionAndScope(for: release)
        guard case let .exported(firstBytes, firstManifest) = try workflow.execute(
            .export(projections: [export.projection], scope: export.scope, at: C37.date)
        ), case let .exported(secondBytes, secondManifest) = try workflow.execute(
            .export(projections: [export.projection], scope: export.scope, at: C37.date)
        ) else { return XCTFail("Expected deterministic synthetic export") }
        XCTAssertEqual(firstBytes, secondBytes)
        XCTAssertEqual(firstManifest, secondManifest)
        XCTAssertEqual(fixture.syntheticAuthority.selectedProfileCount, 1)
        XCTAssertEqual(
            fixture.syntheticAuthority.representation,
            "IN_MEMORY_SELECTED_PROFILE_SIMULATION"
        )
        XCTAssertEqual(fixture.syntheticAuthority.shippedProductionSelectedProfileCount, 0)
        XCTAssertEqual(IncumbentFileAdapterWorkflowClaimsV1.selectedProductionProfileCount, 0)
        let shipped = try C37.workflow()
        XCTAssertEqual(
            try shipped.projection(context: .init(evaluatedAt: C37.date)).state,
            .disabledNoSelectedProfile
        )
        let projection = try workflow.projection(
            context: IncumbentFileAdapterWorkflowContextV1(evaluatedAt: C37.date)
        )
        XCTAssertFalse(projection.fileCreatedMeansSynced)
        XCTAssertFalse(projection.fileCreatedMeansDelivered)
        XCTAssertFalse(projection.fileCreatedMeansAccepted)
    }

    @MainActor
    func testV23P04C37H01HostileFilesAndMismatchedC08BindingsFailBeforeWrites() async throws {
        let release = try C50IncumbentFileAdapterTestSupport.profile()
        let bulkHarness = try C37BulkHarness(workspaceID: C50IncumbentFileAdapterTestSupport.workspace())
        let workflow = try C37.workflow(release: release, bulk: bulkHarness.coordinator)
        let valid = try C37.inbound(workflow: workflow, release: release)
        for bytes in [
            Data([0xff, 0xfe, 0x00]),
            Data("Version,Asset ID,Note\r\nc50-v2,1,unknown\r\n".utf8),
            Data("Version,Asset ID,Note\r\nc50-v1,=2+2,hostile\r\n".utf8),
            Data(repeating: 0x61, count: 4_097)
        ] {
            XCTAssertThrowsError(try workflow.execute(.previewInbound(
                input: C50IncumbentFileAdapterTestSupport.input(bytes: bytes),
                scope: valid.1, at: C37.date
            )))
        }
        let (wrongPlan, wrongBulk) = try C37.bulkPlan(
            workspaceID: valid.1.workspaceID, sourceSHA256: C37.digest("z")
        )
        XCTAssertThrowsError(try workflow.execute(.previewCanonicalImport(
            IncumbentFileAdapterC08PreviewCommandV1(
                inbound: valid.2, importPlan: wrongPlan, bulkPlan: wrongBulk,
                currentSourceSHA256: valid.0.byteSHA256,
                currentWorkspaceRevisionSHA256: wrongPlan.workspaceRevisionSHA256
            )
        )))
        XCTAssertEqual(bulkHarness.adapter.applyCount, 0)
        XCTAssertNil(try bulkHarness.lifecycle.durableSession(sessionID: C37.id(210)))

        let successor = try C50IncumbentFileAdapterTestSupport.successor(of: release)
        let staleSelection = try C50IncumbentFileAdapterTestSupport.enabledSelection(for: release)
        XCTAssertThrowsError(try ClosedIncumbentAdapterRegistryV1(
            currentProductionReleases: [successor], selection: staleSelection,
            selectionHistory: [staleSelection],
            availabilityReceipt: C50IncumbentFileAdapterTestSupport.availability(
                selected: true, release: successor
            )
        ))
        XCTAssertThrowsError(try ClosedIncumbentAdapterRegistryV1(
            currentProductionReleases: [release, successor], selection: staleSelection,
            selectionHistory: [staleSelection],
            availabilityReceipt: C50IncumbentFileAdapterTestSupport.availability(
                selected: true, release: release
            )
        ))
    }

    @MainActor
    func testV23P04C37I01CancellationAndEffectBeforeReceiptRetryCommitExactlyOnce() async throws {
        let release = try C50IncumbentFileAdapterTestSupport.profile()
        let bulkHarness = try C37BulkHarness(
            workspaceID: C50IncumbentFileAdapterTestSupport.workspace(),
            failure: MutationJournalFailureInjectionV1(failOnceAt: .afterEffectBeforeReceipt)
        )
        let workflow = try C37.workflow(release: release, bulk: bulkHarness.coordinator)
        let inbound = try C37.inbound(workflow: workflow, release: release).2
        let (plan, bulk) = try C37.bulkPlan(
            workspaceID: inbound.scope.workspaceID,
            sourceSHA256: inbound.mapping.inputSHA256,
            mappingProfileSHA256: inbound.mapping.mappingManifestSHA256
        )
        guard case let .canonicalPreview(reentry) = try workflow.execute(.previewCanonicalImport(
            .init(inbound: inbound, importPlan: plan, bulkPlan: bulk,
                  currentSourceSHA256: plan.source.sourceSHA256,
                  currentWorkspaceRevisionSHA256: plan.workspaceRevisionSHA256)
        )), case let .canonicalSession(session) = try workflow.execute(.beginCanonicalImport(
            .init(sessionID: C37.id(220), reentry: reentry,
                  currentSourceSHA256: plan.source.sourceSHA256,
                  currentWorkspaceRevisionSHA256: plan.workspaceRevisionSHA256)
        )) else { return XCTFail("Expected C08 preview and session") }
        let cancelled = try workflow.execute(.commitOrCancelCanonicalImport(.init(
            reentry: reentry, session: session,
            currentSourceSHA256: plan.source.sourceSHA256,
            currentWorkspaceRevisionSHA256: plan.workspaceRevisionSHA256,
            cancellationRequested: true
        )))
        guard case let .canonicalSession(cancelledSession) = cancelled else { return XCTFail() }
        XCTAssertEqual(cancelledSession.state, .cancelled)
        XCTAssertEqual(bulkHarness.adapter.applyCount, 0)

        guard case let .canonicalSession(restarted) = try workflow.execute(.beginCanonicalImport(
            .init(sessionID: C37.id(221), reentry: reentry,
                  currentSourceSHA256: plan.source.sourceSHA256,
                  currentWorkspaceRevisionSHA256: plan.workspaceRevisionSHA256)
        )) else { return XCTFail() }
        let commit = IncumbentFileAdapterC08CommitCommandV1(
            reentry: reentry, session: restarted,
            currentSourceSHA256: plan.source.sourceSHA256,
            currentWorkspaceRevisionSHA256: plan.workspaceRevisionSHA256,
            cancellationRequested: false
        )
        XCTAssertThrowsError(try workflow.execute(.commitOrCancelCanonicalImport(commit)))
        XCTAssertEqual(bulkHarness.adapter.applyCount, 0, "rollback must remove the interrupted effect")
        guard case let .canonicalSession(recovered) = try workflow.execute(
            .commitOrCancelCanonicalImport(commit)
        ) else { return XCTFail("Expected effect-before-receipt recovery") }
        XCTAssertEqual(recovered.state, .completed)
        XCTAssertEqual(recovered.chunkReceipts.count, 1)
        XCTAssertEqual(bulkHarness.adapter.applyCount, 1)
        let replayCommit = IncumbentFileAdapterC08CommitCommandV1(
            reentry: reentry, session: recovered,
            currentSourceSHA256: plan.source.sourceSHA256,
            currentWorkspaceRevisionSHA256: plan.workspaceRevisionSHA256,
            cancellationRequested: false
        )
        guard case let .canonicalSession(replayed) = try workflow.execute(
            .commitOrCancelCanonicalImport(replayCommit)
        ) else { return XCTFail("Expected exact C08 commit replay") }
        XCTAssertEqual(replayed, recovered)
        XCTAssertEqual(bulkHarness.adapter.applyCount, 1)
        XCTAssertEqual(
            try bulkHarness.lifecycle.durableReceipt(
                workspaceID: plan.workspaceID, bulkPlan: bulk, chunkIndex: 0
            ), recovered.chunkReceipts.first
        )
        let journalReceipt = try bulkHarness.writer.durableReceipt(
            mutationID: bulk.chunks[0].mutationIDs[0]
        )
        XCTAssertNotNil(journalReceipt)
        XCTAssertEqual(
            try bulkHarness.writer.durableReceipt(mutationID: bulk.chunks[0].mutationIDs[0]),
            journalReceipt
        )
    }

    @MainActor
    func testV23P04C37R01RetriesAreByteIdenticalAndDivergenceIsQuarantined() async throws {
        let release = try C50IncumbentFileAdapterTestSupport.profile()
        let workflow = try C37.workflow(release: release)
        let (input, scope, inbound) = try C37.inbound(workflow: workflow, release: release)
        let plan = try C50IncumbentFileAdapterTestSupport.recoveryPlan(
            input: input, scope: scope, release: release, preview: inbound.mapping
        )
        guard case let .recovered(first) = try workflow.execute(.recover(
            scope: scope, at: C37.date,
            plan: plan, observedSourceSHA256: input.byteSHA256,
            canonicalMutation: nil, cleanup: nil
        )), case let .recovered(replayed) = try workflow.execute(.recover(
            scope: scope, at: C37.date,
            plan: plan, observedSourceSHA256: input.byteSHA256,
            canonicalMutation: nil, cleanup: nil
        )), case let .recovered(divergent) = try workflow.execute(.recover(
            scope: scope, at: C37.date,
            plan: plan, observedSourceSHA256: C37.digest("q"),
            canonicalMutation: nil, cleanup: nil
        )) else { return XCTFail("Expected recovery outcomes") }
        XCTAssertEqual(first, replayed)
        XCTAssertEqual(
            try IncumbentFileCanonicalCodecV1.encode(first),
            try IncumbentFileCanonicalCodecV1.encode(replayed)
        )
        XCTAssertEqual(first.disposition, .beforeCanonicalEffect)
        XCTAssertEqual(divergent.disposition, .divergentQuarantined)
        XCTAssertFalse(first.canonicalReapplyOccurred)
        XCTAssertFalse(divergent.canonicalReapplyOccurred)
        let writerFixture = try C20PrivacyTransformTestSupport.makeFixture()
        let writerReceipt = try C20PrivacyTransformTestSupport.makeCanonicalMutationReceipt(
            for: writerFixture
        )
        let fields = C50IncumbentFileAdapterTestSupport.adapterFields(for: release)
        let baseApproval = try C50IncumbentFileAdapterTestSupport.privacyApproval(
            workspaceID: writerFixture.workspace, slot: 250
        )
        let adapterApproval = try C50IncumbentFileAdapterTestSupport.adapterApproval(
            privacyApproval: baseApproval, allowedCanonicalFields: fields, slot: 260
        )
        let boundScope = try IncumbentExchangeScopeV1(
            operationID: C37.id(270), workspaceID: writerFixture.workspace,
            workspaceRevision: 1, release: release, direction: release.direction,
            allowedCanonicalFields: fields, privacyApproval: adapterApproval
        )
        guard case let .inboundPreview(boundInbound) = try workflow.execute(.previewInbound(
            input: input, scope: boundScope, at: C37.date
        )) else { return XCTFail("Expected authority-bound preview") }
        let boundPlan = try C50IncumbentFileAdapterTestSupport.recoveryPlan(
            input: input, scope: boundScope, release: release, preview: boundInbound.mapping,
            expectedMutationID: writerReceipt.mutationID,
            expectedCommandBodySHA256: writerReceipt.commandBodySHA256
        )
        let canonical = try IncumbentCanonicalMutationReceiptReferenceV1(
            receipt: writerReceipt, plan: boundPlan
        )
        let cleanup = try IncumbentCleanupEvidenceV1(
            operationID: boundPlan.operationID, sourceSHA256: boundPlan.sourceSHA256,
            cleanupIdentitySHA256: boundPlan.cleanupIdentitySHA256, cleanedAt: C37.date
        )
        guard case let .recovered(cleaned) = try workflow.execute(.recover(
            scope: boundScope, at: C37.date, plan: boundPlan,
            observedSourceSHA256: input.byteSHA256,
            canonicalMutation: canonical, cleanup: cleanup
        )), case let .recovered(cleanedReplay) = try workflow.execute(.recover(
            scope: boundScope, at: C37.date, plan: boundPlan,
            observedSourceSHA256: input.byteSHA256,
            canonicalMutation: canonical, cleanup: cleanup
        )) else { return XCTFail("Expected deterministic cleanup recovery") }
        XCTAssertEqual(cleaned, cleanedReplay)
        XCTAssertEqual(cleaned.disposition, .cleanupOnly)
        XCTAssertFalse(cleaned.canonicalReapplyOccurred)
        let fixture = try C37.fixture()
        XCTAssertTrue(fixture.claims.allSatisfyFalse)
    }
}

private extension C37Corpus.Claims {
    var allSatisfyFalse: Bool {
        !fileCreatedMeansSynced && !fileCreatedMeansDelivered
            && !fileCreatedMeansProviderAccepted && !providerSDK && !networkEndpoint
            && !credentials && !securityClaim && !identityClaim && !legalClaim
            && !shippedProductionProfileSelected && !previewWritesCanonicalData && !automaticImport
    }
}

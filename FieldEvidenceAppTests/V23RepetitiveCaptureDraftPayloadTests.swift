import Foundation
import XCTest
import SwiftData

@testable import FieldEvidenceApp

final class V23RepetitiveCaptureDraftPayloadTests: XCTestCase {
    func testSourceCheckpointMaterializesExactPlanAndDistinctContinuationRoundTrips() throws {
        let fixture = try Fixture()
        let source = try fixture.sourceCheckpoint()
        let plan = try RepetitiveCaptureDraftCodecV1.materializePlan(from: source)
        XCTAssertEqual(plan.draftID, source.draftID)
        XCTAssertEqual(plan.draftRevision, source.draftRevision)
        XCTAssertEqual(plan.draftSHA256, source.checkpointSHA256)
        XCTAssertEqual(plan.round, try fixture.predecessor.reference)
        XCTAssertEqual(try RepetitiveCaptureDraftCodecV1.decode(source.payloadData), fixture.sourcePayload)
        XCTAssertNil(source.payloadData.range(of: Data(source.checkpointSHA256.utf8)))

        try RepetitiveCaptureDraftCodecV1.validateSelectedRoundItem(
            sourceCheckpoint: source, round: fixture.predecessor, selectedItem: fixture.predecessor.items[0]
        )
        let request = try fixture.request(plan: plan)
        let continuation = try fixture.continuationCheckpoint(source: source, request: request)
        XCTAssertNotEqual(continuation.draftID, source.draftID)
        XCTAssertEqual(
            try RepetitiveCaptureDraftCodecV1.validateContinuationCheckpoint(
                continuation, sourceCheckpoint: source
            ), request
        )
        XCTAssertEqual(try RepetitiveCaptureDraftCodecV1.decode(continuation.payloadData),
                       .continuation(source: try .init(source: source), request: request))
    }

    func testCodecRejectsClosedGrammarTamperingAndBounds() throws {
        let fixture = try Fixture()
        let source = try fixture.sourceCheckpoint()
        let bytes = try RepetitiveCaptureDraftCodecV1.encode(fixture.sourcePayload)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        object["future"] = true
        XCTAssertThrowsError(try RepetitiveCaptureDraftCodecV1.decode(
            JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        ))
        object.removeValue(forKey: "future")
        object["schemaVersion"] = 2
        XCTAssertThrowsError(try RepetitiveCaptureDraftCodecV1.decode(
            JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        ))
        object["schemaVersion"] = 1
        object["tag"] = "CONTINUATION"
        XCTAssertThrowsError(try RepetitiveCaptureDraftCodecV1.decode(
            JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        ))
        XCTAssertThrowsError(try RepetitiveCaptureDraftCodecV1.decode(Data("not-json".utf8)))
        XCTAssertThrowsError(try RepetitiveCaptureDraftCodecV1.decode(
            Data(repeating: 0, count: RepetitiveCaptureDraftCodecV1.maximumPayloadBytes + 1)
        ))
        XCTAssertThrowsError(try RepetitiveCaptureDraftCodecV1.validateSourceCheckpoint(
            try fixture.checkpoint(payload: .continuation(source: try .init(source: source), request: try fixture.request(plan: try RepetitiveCaptureDraftCodecV1.materializePlan(from: source))), draftID: source.draftID, anchor: try .init())
        ))
    }

    func testContinuationRejectsForeignSourceIdentityAndSameDraft() throws {
        let fixture = try Fixture()
        let source = try fixture.sourceCheckpoint()
        let plan = try RepetitiveCaptureDraftCodecV1.materializePlan(from: source)
        let request = try fixture.request(plan: plan)
        let continuation = try fixture.continuationCheckpoint(source: source, request: request)
        let foreign = try fixture.sourceCheckpoint(workspace: fixture.otherWorkspace)
        XCTAssertThrowsError(try RepetitiveCaptureDraftCodecV1.validateContinuationCheckpoint(
            continuation, sourceCheckpoint: foreign
        ))
        let sameDraft = try fixture.continuationCheckpoint(source: source, request: request, draftID: source.draftID)
        XCTAssertThrowsError(try RepetitiveCaptureDraftCodecV1.validateContinuationCheckpoint(
            sameDraft, sourceCheckpoint: source
        ))
        var wrongRound = fixture.predecessor
        // A canonical value from a different predecessor cannot be accepted as the selected round.
        wrongRound = try fixture.round(revision: 1, predecessor: nil, state: .draft, transition: .create,
                                       items: fixture.pendingItems)
        XCTAssertThrowsError(try RepetitiveCaptureDraftCodecV1.validateSelectedRoundItem(
            sourceCheckpoint: source, round: wrongRound, selectedItem: wrongRound.items[0]
        ))
    }


    @MainActor
    func testDurableSourceAndContinuationReplayAndFreshAuthorityReadbackWithoutRoundEffects() throws {
        let fixture = try Fixture(), harness = try RepetitiveDraftHarness(workspaceID: fixture.workspace)
        defer { harness.removeFiles() }
        let adapter = harness.adapter, source = try fixture.sourceCheckpoint()
        let saved = try adapter.persistRepetitiveCaptureSource(source, round: fixture.predecessor,
                                                               selectedItem: fixture.predecessor.items[0])
        XCTAssertEqual(saved.checkpoint, source)
        XCTAssertEqual(try adapter.persistRepetitiveCaptureSource(source, round: fixture.predecessor,
            selectedItem: fixture.predecessor.items[0]), saved)
        let request = try fixture.request(plan: saved.plan)
        let continuation = try durableCheckpoint(try fixture.continuationCheckpoint(source: source, request: request))
        let stored = try adapter.persistRepetitiveCaptureContinuation(continuation)
        XCTAssertEqual(stored.source, saved)
        XCTAssertEqual(stored.request, request)
        XCTAssertEqual(try adapter.persistRepetitiveCaptureContinuation(continuation), stored)
        let revision = try harness.writer.currentRevision()
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<FieldDraftCheckpointRow>()), 2)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<MutationReceiptRow>()), 2)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<RoundSessionRevisionRowV1>()), 0)
        let reopened = try harness.reopen()
        XCTAssertEqual(try reopened.adapter.reviewedRepetitiveCaptureSource(workspaceID: fixture.workspace, draftID: source.draftID), saved)
        XCTAssertEqual(try reopened.adapter.reviewedRepetitiveCaptureContinuation(workspaceID: fixture.workspace, draftID: continuation.draftID), stored)
        XCTAssertEqual(try harness.writer.currentRevision(), revision)
    }

    @MainActor
    func testDurableContinuationRejectsRevisedSourceWithoutNewEffects() throws {
        let fixture = try Fixture(), harness = try RepetitiveDraftHarness(workspaceID: fixture.workspace)
        defer { harness.removeFiles() }
        let source = try fixture.sourceCheckpoint(), adapter = harness.adapter
        let saved = try adapter.persistRepetitiveCaptureSource(source, round: fixture.predecessor,
                                                               selectedItem: fixture.predecessor.items[0])
        let continuation = try durableCheckpoint(try fixture.continuationCheckpoint(source: source, request: fixture.request(plan: saved.plan)))
        _ = try adapter.persistRepetitiveCaptureContinuation(continuation)
        let revised = try durableCheckpoint(source, revision: 2)
        _ = try adapter.compareAndSwap(checkpoint: revised, expectedDraftRevision: 1, expectedBaseRevision: source.baseCanonicalRevision)
        let revision = try harness.writer.currentRevision()
        XCTAssertThrowsError(try adapter.reviewedRepetitiveCaptureSource(workspaceID: fixture.workspace, draftID: source.draftID))
        XCTAssertThrowsError(try adapter.reviewedRepetitiveCaptureContinuation(workspaceID: fixture.workspace, draftID: continuation.draftID))
        XCTAssertThrowsError(try adapter.persistRepetitiveCaptureContinuation(continuation))
        let reopened = try harness.reopen()
        XCTAssertThrowsError(try reopened.adapter.reviewedRepetitiveCaptureContinuation(workspaceID: fixture.workspace, draftID: continuation.draftID))
        XCTAssertEqual(try harness.writer.currentRevision(), revision)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<MutationReceiptRow>()), 3)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<RoundSessionRevisionRowV1>()), 0)
    }

    @MainActor
    func testDurableReadbackRejectsUnauthenticatedPhysicalSource() throws {
        let fixture = try Fixture(), harness = try RepetitiveDraftHarness(workspaceID: fixture.workspace)
        defer { harness.removeFiles() }
        let source = try fixture.sourceCheckpoint()
        harness.context.insert(try FieldDraftCheckpointRow(source))
        try harness.context.save()
        XCTAssertThrowsError(try harness.adapter.reviewedRepetitiveCaptureSource(workspaceID: fixture.workspace, draftID: source.draftID))
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<MutationReceiptRow>()), 0)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<RoundSessionRevisionRowV1>()), 0)
    }

    @MainActor
    func testDurableContinuationRejectsForeignOrReusedIdentityAndInvalidatedWriter() throws {
        let fixture = try Fixture(), harness = try RepetitiveDraftHarness(workspaceID: fixture.workspace)
        defer { harness.removeFiles() }
        let source = try fixture.sourceCheckpoint(), adapter = harness.adapter
        let saved = try adapter.persistRepetitiveCaptureSource(source, round: fixture.predecessor,
                                                               selectedItem: fixture.predecessor.items[0])
        let request = try fixture.request(plan: saved.plan)
        let reused = try fixture.continuationCheckpoint(source: source, request: request)
        XCTAssertEqual(reused.mutationID, source.mutationID)
        XCTAssertThrowsError(try adapter.persistRepetitiveCaptureContinuation(reused))
        let roundIDReuse = try durableCheckpoint(reused, mutationID: request.roundMutation.mutationID)
        XCTAssertThrowsError(try adapter.persistRepetitiveCaptureContinuation(roundIDReuse))
        XCTAssertThrowsError(try adapter.reviewedRepetitiveCaptureSource(workspaceID: fixture.otherWorkspace, draftID: source.draftID))
        let changed = try durableCheckpoint(reused, workspaceID: fixture.otherWorkspace)
        XCTAssertThrowsError(try adapter.persistRepetitiveCaptureContinuation(changed))
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<MutationReceiptRow>()), 1)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<MutationQuarantineRow>()), 0)
        harness.writer.invalidate()
        XCTAssertThrowsError(try adapter.reviewedRepetitiveCaptureSource(workspaceID: fixture.workspace, draftID: source.draftID))
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<RoundSessionRevisionRowV1>()), 0)
    }

    private func durableCheckpoint(_ value: FieldDraftCheckpointV1, revision: UInt64 = 1,
                                   mutationID: MutationIDV1? = nil, workspaceID: WorkspaceID? = nil) throws -> FieldDraftCheckpointV1 {
        try .init(draftID: value.draftID, workspaceID: workspaceID ?? value.workspaceID, scope: value.scope,
            purpose: value.purpose, codec: value.codec, baseCanonicalRevision: value.baseCanonicalRevision,
            draftRevision: revision, payloadData: value.payloadData, stageIDs: [],
            resumeAnchor: value.resumeAnchor, state: .active, updatedAt: value.updatedAt,
            mutationID: mutationID ?? .init(rawValue: UUID()))
    }

    private struct Fixture {
        static let digest = String(repeating: "a", count: 64)
        static let alternate = String(repeating: "b", count: 64)
        static let date = Date(timeIntervalSince1970: 1_788_134_400)
        let workspace = WorkspaceID(rawValue: id(1))
        let otherWorkspace = WorkspaceID(rawValue: id(2))
        let first: RoundAssetSelectionV1
        let second: RoundAssetSelectionV1
        let selection: BatchScanSelectionV1
        let predecessor: RoundSessionV1
        let pendingItems: [RoundItemV1]
        let successor: RoundSessionV1
        let sourcePayload: RepetitiveCaptureDraftPayloadV1

        init() throws {
            first = try .init(assetID: Self.id(101), siteID: Self.id(201), labelAtSelection: "Asset A")
            second = try .init(assetID: Self.id(102), siteID: Self.id(202), labelAtSelection: "Asset B")
            let package = try Self.package()
            let draft = try Self.round(workspace: workspace, revision: 1, predecessor: nil, state: .draft,
                                       transition: .create, items: Self.items([first, second], workspace: workspace, package: package))
            predecessor = try Self.round(workspace: workspace, revision: 2, predecessor: draft, state: .active,
                                         transition: .start, items: draft.items)
            pendingItems = predecessor.items
            let visit = try RoundItemVisitV1(visitedAt: Self.date.addingTimeInterval(3), recordedBy: try Self.actor(workspace))
            var visited = predecessor.items
            visited[0] = try .init(itemID: visited[0].itemID, order: 0, selection: first,
                                   requirement: visited[0].requirement, disposition: .visited, visit: visit)
            successor = try Self.round(workspace: workspace, revision: 3, predecessor: predecessor, state: .active,
                                       transition: .visitItem, transitionItemID: visited[0].itemID, items: visited)
            selection = try Self.batch(workspace: workspace, first: first, second: second, session: try predecessor.reference)
            sourcePayload = .source(planID: Self.id(301), round: try predecessor.reference, selection: selection)
        }

        func sourceCheckpoint(workspace: WorkspaceID? = nil) throws -> FieldDraftCheckpointV1 {
            let selectedWorkspace = workspace ?? self.workspace
            let payload: RepetitiveCaptureDraftPayloadV1
            let round: RoundSessionReferenceV1
            let selected: BatchScanSelectionV1
            if selectedWorkspace == self.workspace { payload = sourcePayload; round = try predecessor.reference; selected = selection }
            else {
                round = try .init(workspaceID: selectedWorkspace, sessionID: Self.id(901), revision: 1, sessionSHA256: Self.digest)
                selected = try Self.batch(workspace: selectedWorkspace, first: first, second: second, session: round)
                payload = .source(planID: Self.id(301), round: round, selection: selected)
            }
            return try checkpoint(payload: payload, workspace: selectedWorkspace, scope: try RepetitiveCaptureDraftCodecV1.scope(planID: Self.id(301), round: round), draftID: Self.id(selectedWorkspace == self.workspace ? 401 : 402), anchor: .init(sectionID: "facts", selectedStableID: first.assetID.uuidString.lowercased()))
        }

        func request(plan: RepetitiveCapturePlanV1) throws -> RepetitiveCaptureCheckpointRequestV1 {
            try .init(plan: plan, assetID: first.assetID, disposition: .keepOpenAndNext, requirementFocus: .facts,
                      resumeAnchor: .init(sectionID: "facts", fieldID: "f-1", selectedStableID: second.assetID.uuidString.lowercased(), boundedPosition: 1),
                      roundMutation: .init(workspaceID: workspace, expectedRevision: predecessor.revision, mutationID: successor.mutationID, session: successor))
        }

        func continuationCheckpoint(source: FieldDraftCheckpointV1, request: RepetitiveCaptureCheckpointRequestV1, draftID: UUID? = nil) throws -> FieldDraftCheckpointV1 {
            guard let round = request.plan.round else { throw ScanToWorkFailureV1.authorityMismatch }
            return try checkpoint(payload: .continuation(source: try .init(source: source), request: request), workspace: source.workspaceID,
                                  scope: try RepetitiveCaptureDraftCodecV1.scope(planID: request.plan.planID, round: round),
                                  draftID: draftID ?? Self.id(501), anchor: request.resumeAnchor)
        }

        func checkpoint(payload: RepetitiveCaptureDraftPayloadV1, workspace: WorkspaceID? = nil, scope: DraftScopeKeyV1? = nil, draftID: UUID, anchor: DraftResumeAnchorV1) throws -> FieldDraftCheckpointV1 {
            let selectedWorkspace = workspace ?? self.workspace
            let resolvedScope = try scope ?? RepetitiveCaptureDraftCodecV1.scope(planID: Self.id(301), round: try predecessor.reference)
            return try .init(draftID: draftID, workspaceID: selectedWorkspace, scope: resolvedScope,
                             purpose: .repetitiveCapture, codec: RepetitiveCaptureDraftCodecV1.release(), baseCanonicalRevision: 0,
                             draftRevision: 1, payloadData: RepetitiveCaptureDraftCodecV1.encode(payload), stageIDs: [],
                             resumeAnchor: anchor, state: .active, updatedAt: Self.date, mutationID: try .init(rawValue: Self.id(601)))
        }

        func round(revision: UInt64, predecessor: RoundSessionV1?, state: RoundSessionStateV1, transition: RoundSessionTransitionV1, items: [RoundItemV1]) throws -> RoundSessionV1 {
            try Self.round(workspace: workspace, revision: revision, predecessor: predecessor, state: state, transition: transition, items: items)
        }

        private static func id(_ value: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", value))! }
        private static func package() throws -> RoundPackageReleaseReferenceV1 { try .init(packageReleaseID: digest, packageID: "c36", packageContentVersion: 1, packageSHA256: digest, workflowSHA256: alternate) }
        private static func actor(_ workspace: WorkspaceID) throws -> ActorSnapshotV1 { let local = try LocalActorReferenceV1(actorReferenceID: id(701), workspaceID: workspace, displayName: "C36"); return try .init(snapshotID: id(702), workspaceID: workspace, actor: local, responsibility: .recordedBy, displayNameAtTime: "C36", capturedAt: date) }
        private static func items(_ selections: [RoundAssetSelectionV1], workspace: WorkspaceID, package: RoundPackageReleaseReferenceV1) throws -> [RoundItemV1] { let requirement = try RoundPackageContentRequirementV1(packageRelease: package, requiredContent: []); return try selections.enumerated().map { try .init(itemID: id(800 + $0.offset), order: $0.offset, selection: $0.element, requirement: requirement) } }
        private static func round(workspace: WorkspaceID, revision: UInt64, predecessor: RoundSessionV1?, state: RoundSessionStateV1, transition: RoundSessionTransitionV1, transitionItemID: UUID? = nil, items: [RoundItemV1]) throws -> RoundSessionV1 { try .init(workspaceID: workspace, sessionID: id(900), predecessor: predecessor, revision: revision, mutationID: try .init(rawValue: id(900 + Int(revision))), state: state, transition: transition, transitionItemID: transitionItemID, items: items, recordedBy: try actor(workspace), recordedAt: date.addingTimeInterval(TimeInterval(revision))) }
        private static func batch(workspace: WorkspaceID, first: RoundAssetSelectionV1, second: RoundAssetSelectionV1, session: RoundSessionReferenceV1) throws -> BatchScanSelectionV1 {
            try session.validate()
            let manifest = try OfflineReadinessManifestBuilderV1.build(snapshot: .init(session: session, expectedPackage: try package(), observedPackage: try package(), selectedAssets: [first, second], observedAssetIDs: [first.assetID, second.assetID], guidanceReferenceIDs: [], availableGuidanceReferenceIDs: [], contentRequirements: [], contentObservations: [], expectedFieldReferences: [], fieldReferenceReadiness: [], storage: try .init(capacityState: .checked, availableBytes: 100_000), access: .init(protectedDataAvailable: true), checkedAt: date, timeZoneIdentifier: "America/New_York", clockState: .checked))
            func preview(_ selection: RoundAssetSelectionV1, _ n: Int) throws -> AssetPreviewStateV1 { let proof = try ScanToWorkOfflineReadinessProofV1(manifest: manifest, assetID: selection.assetID); let asset = try ScanToWorkAssetBindingV1(workspaceID: workspace, assetID: selection.assetID, siteID: selection.siteID, label: selection.labelAtSelection, assetRevision: 1, assetSHA256: digest, locator: .init(locatorID: id(1000+n), revision: 1, locatorSHA256: digest), readiness: proof, qualifiedPose: nil); return try .init(workspaceID: workspace, source: .manual, inputSHA256: KernelCanonicalHashV1.sha256(Data("c36-\(n)".utf8)), resolutionSHA256: alternate, outcome: .ready, asset: asset, candidateLocators: [], evaluatedAt: date) }
            return try .init(workspaceID: workspace, previews: try [preview(first, 1), preview(second, 2)].sorted { $0.inputSHA256 < $1.inputSHA256 })
        }
    }
}

@MainActor
private final class RepetitiveDraftHarness {
    let root: URL; let container: ModelContainer; let context: ModelContext
    let registry: GenerationLeaseRegistryV1; let fence: StaleWriterFenceV1
    let identity: WorkspaceReplicaIdentityV1; let generationID: UUID
    let store: MutationJournalStoreV1; let writer: WorkspaceWriterV1
    var adapter: FieldDraftLifecycleAdapterV1 { .init(writer: writer, journal: store, modelContext: context) }
    init(workspaceID: WorkspaceID) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("V23-repetitive-draft-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let schema = Schema(PersistentSchemaV53.models, version: PersistentSchemaV53.versionIdentifier)
        container = try ModelContainer(for: schema, migrationPlan: nil,
            configurations: [ModelConfiguration("RepetitiveDraft", schema: schema,
                isStoredInMemoryOnly: true, allowsSave: true, cloudKitDatabase: .none)])
        context = container.mainContext; context.autosaveEnabled = false
        identity = try .init(workspaceID: workspaceID, replicaID: .init(rawValue: UUID()))
        generationID = UUID()
        let epoch = try GenerationEpochV1(generationID: generationID, generationManifestSHA256: String(repeating: "a", count: 64))
        registry = try GenerationLeaseRegistryV1(applicationSupportURL: root)
        let lease = try registry.acquire(epoch: epoch, role: .writer)
        fence = try StaleWriterFenceV1(expectedGenerationEpoch: epoch, writerLeaseToken: lease,
                                      registry: registry, currentGenerationEpoch: { epoch })
        store = try MutationJournalStoreV1(modelContext: context, identity: identity, generationID: generationID, staleWriterFence: fence)
        let id = UUID()
        writer = try WorkspaceWriterV1(identity: identity, generationID: generationID,
            initialRevision: store.currentRevision(writerInstanceID: id), clock: RepetitiveDraftClock(),
            idSource: RepetitiveDraftIDs(value: id), fileAuthority: RepetitiveDraftFiles(),
            adapter: WorkspaceWriterAdapterV1(modelContext: context), journalStore: store)
    }
    func reopen() throws -> (writer: WorkspaceWriterV1, adapter: FieldDraftLifecycleAdapterV1) {
        let context = ModelContext(container); context.autosaveEnabled = false
        let store = try MutationJournalStoreV1(modelContext: context, identity: identity,
            generationID: generationID, allowStateBootstrap: false, staleWriterFence: fence)
        let id = UUID()
        let writer = try WorkspaceWriterV1(identity: identity, generationID: generationID,
            initialRevision: store.currentRevision(writerInstanceID: id), clock: RepetitiveDraftClock(),
            idSource: RepetitiveDraftIDs(value: id), fileAuthority: RepetitiveDraftFiles(),
            adapter: WorkspaceWriterAdapterV1(modelContext: context), journalStore: store)
        return (writer, .init(writer: writer, journal: store, modelContext: context))
    }
    func removeFiles() { try? FileManager.default.removeItem(at: root) }
}
private struct RepetitiveDraftClock: ApplicationClock { func now() -> Date { Date(timeIntervalSince1970: 1_788_134_520) } }
private struct RepetitiveDraftIDs: ApplicationIDSource { let value: UUID; func makeID() -> UUID { value } }
private struct RepetitiveDraftFiles: ApplicationFileAuthorityV1 {
    func temporaryRelativePath(mutationID: MutationIDV1, component: String) throws -> String {
        "repetitive-draft/\(mutationID.rawValue.uuidString.lowercased())/\(component)"
    }
}

import Foundation
import XCTest
@testable import FieldEvidenceApp

/// Draft composition tests. Actual journal adapters publish/read the M1 input;
/// canonical value fixtures use the incumbent codecs. These tests confer no
/// source/lifetime/EX/G authority and have not been compiled or run.
final class TemporalUncommittedOriginalClassifierTests: XCTestCase {
    typealias Classification = TemporalNormalizationUncommittedOriginalClassificationV1

    private func emptySource(workspace: WorkspaceID) throws -> TemporalNormalizationReferencePreflightV1 {
        let history = MutationHistorySnapshotV1(workspaceRevision: 0, lastLocalSequence: 0,
            receipts: [], quarantines: [], entityRevisions: [])
        let generation = UUID()
        let authored = V4BackupRecordsV1(assets: [], deletionLedger: .empty,
            evidenceFiles: [], issues: [], mutationHistory: history, packets: [],
            recordsSchemaVersion: LightingNightWorkflowBackupEnrollmentV1.recordsSchemaVersion,
            reports: [], sites: [], workflowRecords: [],
            partsStockSnapshot: try .init(workspaceID: workspace, parts: [], locations: [], movements: [],
                uses: [], reversals: [], returns: [], abandonments: []),
            evidenceQuality: try .init(ruleSets: [], assessments: [], waivers: [], receipts: [], effectProvenance: []),
            fastSurveyInbox: try .init(inboxItems: [], promotions: [], snippets: [], snippetInsertions: [],
                receipts: [], effectProvenance: []),
            reinspectionExceptionQueue: try .init(plans: [], attestations: [], acknowledgements: [],
                receipts: [], effectProvenance: []),
            entityIdentityResolution: try .init(workspaceID: workspace, generationID: generation,
                aliasLinks: [], consolidationReceipts: [], mutationReceipts: []))
        let encoder = BackupCanonicalEncoderV1()
        let records = try BackupCanonicalDecoderV1().decodeRecords(encoder.encodeRecords(authored).data)
        let identity = try WorkspaceReplicaIdentityV1(workspaceID: workspace, replicaID: ReplicaID(rawValue: UUID()))
        let source = V4BackupSourceV1(appBuild: "test", appVersion: "test",
            persistentSchemaVersion: LightingNightWorkflowBackupEnrollmentV1.persistentSchemaVersion,
            replicaID: identity.replicaID.rawValue, recordsSchemaVersion: records.recordsSchemaVersion,
            sourceGenerationID: generation, workspaceID: workspace.rawValue)
        let snapshot = try TemporalNormalizationCanonicalSnapshotV1(source: source, records: records,
            recordsData: encoder.encodeRecords(records).data, semanticRecordsData: encoder.encodeSemanticRecords(records).data,
            history: history, workspaceIdentity: identity, generationID: generation,
            revision: .init(workspaceID: workspace, generationID: generation, history: history))
        return try .observe(snapshot: snapshot, history: .init(history: history))
    }
    private func classify(_ reservation: TemporalEvidencePromotionReservationV1, root: URL) throws -> Classification {
        try .init(reservation: reservation,
            operational: .prepare(generationRootURL: root), sources: [emptySource(workspace: reservation.workspaceID)])
    }
    private func changing(_ value: TemporalEvidencePromotionReservationV1,
                          workspace: WorkspaceID? = nil, mutation: MutationIDV1? = nil,
                          digest: String? = nil) throws -> TemporalEvidencePromotionReservationV1 {
        let mutation = mutation ?? value.mutationID, digest = digest ?? value.contentSHA256
        let old = value.binding.request
        let request = try CapabilityScratchLeaseRequestV1(leaseID: old.leaseID, operationID: mutation.rawValue,
            purpose: old.purpose, requestedByteCount: old.requestedByteCount, createdAt: old.createdAt, expiresAt: old.expiresAt)
        let binding = try TemporalEvidenceScratchBindingV1(request: request, lease: value.binding.lease,
            mutationID: mutation, contentID: value.contentID, contentSHA256: digest)
        return try .init(workspaceID: workspace ?? value.workspaceID, mutationID: mutation,
            contentID: value.contentID, contentSHA256: digest, binding: binding, state: .prepared)
    }
    func testPublishedReservationWithExportShapedEmptySnapshotsHasExactBoundedNoReferenceResult() async throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let reservation = try observationReservation(), store = try observationStore(root, reservation)
        try await store.prepare(reservation)
        let before = try TemporalOperationalJournalObservationV1.prepare(generationRootURL: root)
        let result = try classify(reservation, root: root)
        guard case .noReferencedContentInSuppliedObservations = result.decision else { return XCTFail("unexpected blocker") }
        XCTAssertTrue(result.blockers.isEmpty)
        XCTAssertEqual(result.sources[0].canonical.map(\.field).count, 77)
        XCTAssertEqual(Set(result.sources[0].canonical.map { $0.field.rawValue }).count, 77)
        XCTAssertTrue(result.sources[0].commands.isEmpty)
        let optionalFields: Set<Classification.CanonicalField> = [.evidenceQuality, .fastSurveyInbox,
            .reinspectionExceptionQueue, .entityIdentityResolution, .partsStockSnapshot]
        let emptyBranches = result.sources[0].canonical.filter { optionalFields.contains($0.field) }
        XCTAssertEqual(emptyBranches.count, 5)
        XCTAssertTrue(emptyBranches.allSatisfy { $0.count == 0 })
        XCTAssertEqual(try TemporalOperationalJournalObservationV1.prepare(generationRootURL: root).published.map(\.canonicalData),
                       before.published.map(\.canonicalData))
        let noSources = try Classification(reservation: reservation, operational: before, sources: [])
        guard case .preserve = noSources.decision else { return XCTFail("missing source was treated as no owner") }
    }
    func testPopulatedOptionalSnapshotRemainsUnsupportedAndCounted() throws {
        let workspace = WorkspaceID(rawValue: UUID())
        let part = try LocalPartDefinitionV1(partID: UUID(), workspaceID: workspace,
            displayName: "Retained part", canonicalUnit: .each, revision: 1,
            mutationID: MutationIDV1(rawValue: UUID()))
        let stock = try PartsStockBackupSnapshotV1(workspaceID: workspace, parts: [part],
            locations: [], movements: [], uses: [], reversals: [], returns: [], abandonments: [])
        try stock.validate()
        let history = MutationHistorySnapshotV1(workspaceRevision: 0, lastLocalSequence: 0,
            receipts: [], quarantines: [], entityRevisions: [])
        let records = V4BackupRecordsV1(assets: [], deletionLedger: .empty,
            evidenceFiles: [], issues: [], mutationHistory: history, packets: [],
            recordsSchemaVersion: LightingNightWorkflowBackupEnrollmentV1.recordsSchemaVersion,
            reports: [], sites: [], workflowRecords: [], partsStockSnapshot: stock)
        // This isolates the census; no source admission or writer receipt is
        // fabricated for this constructed catalog row.
        let branch = try XCTUnwrap(Classification.canonicalBranches(records: records,
            history: .init(history: history)).first { $0.field == .partsStockSnapshot })
        XCTAssertEqual(branch.count, 1)
        guard case .unsupportedAffectedOwner = branch.disposition else {
            return XCTFail("populated unsupported family lost its refusal")
        }
    }
    func testFinishedMarkerCannotBeUncommittedEvenWithNoCanonicalReference() async throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let reservation = try observationReservation(), store = try observationStore(root, reservation)
        try await store.prepare(reservation); try await store.transition(reservation, to: .finished)
        let stored = try await store.reservation(workspaceID: reservation.workspaceID, mutationID: reservation.mutationID)
        let current = try XCTUnwrap(stored)
        let result = try classify(current, root: root)
        XCTAssertTrue(result.blockers.contains { if case .terminalReservation = $0 { return true }; return false })
    }
    func testSharedPromotionBlocksButSameContentIDInForeignWorkspaceDoesNotAlias() async throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let reservation = try observationReservation(), store = try observationStore(root, reservation)
        try await store.prepare(reservation)
        let foreign = try changing(reservation, workspace: .init(rawValue: UUID()), mutation: .init(rawValue: UUID()))
        let foreignStore = try observationStore(root, foreign); try await foreignStore.prepare(foreign)
        let separate = try classify(reservation, root: root)
        guard case .noReferencedContentInSuppliedObservations = separate.decision else { return XCTFail("foreign namespace aliased") }
        let shared = try changing(reservation, mutation: .init(rawValue: UUID()))
        try await store.prepare(shared)
        let result = try classify(reservation, root: root)
        XCTAssertTrue(result.blockers.contains { if case .sharedPromotion = $0 { return true }; return false })
    }
    func testWrongReservationDigestIsDivergentRatherThanUnreferenced() async throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let reservation = try observationReservation(), store = try observationStore(root, reservation)
        try await store.prepare(reservation)
        let result = try classify(changing(reservation, digest: String(repeating: "b", count: 64)), root: root)
        XCTAssertTrue(result.blockers.contains { if case .divergentReservation = $0 { return true }; return false })
    }
    func testRealM1InterruptedSuccessorBlocksBeforeAnyRemovalClassification() async throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let reservation = try observationReservation()
        let store = try observationStore(root, reservation, boundary: .durablePayload)
        do { try await store.prepare(reservation); XCTFail("missing actual fault") } catch ObservationStop.boundary { }
        let result = try classify(reservation, root: root)
        XCTAssertTrue(result.blockers.contains { if case .pendingPublication = $0 { return true }; return false })
    }
    func testReleasedMyDayPayloadRetainsSelectedAndEligibleOwnerOccurrences() throws {
        let workspace = WorkspaceID(rawValue: UUID()), now = Date(timeIntervalSince1970: 1_820_000_000)
        let key = try MyDayKeyV1(workspaceID: workspace, civilDate: .init("2026-09-10"), ianaTimeZoneIdentifier: "America/New_York")
        let actor = try LocalActorReferenceV1(actorReferenceID: UUID(), workspaceID: workspace, displayName: "Recorder")
        let recorder = try ActorSnapshotV1(snapshotID: UUID(), workspaceID: workspace, actor: actor,
            responsibility: .recordedBy, displayNameAtTime: actor.displayName, capturedAt: now)
        let reference = MyDayEligibleReferenceV1.roundSession(workspaceID: workspace, sessionID: UUID(),
            revision: 1, sessionSHA256: String(repeating: "a", count: 64))
        let draft = try MyDayPlanDraftV1(key: key,
            items: [.init(membershipID: UUID(), reference: reference)], eligibleReferences: [reference])
        let payload = try MyDayPlanningDraftPayloadV1(editing: .init(key: key, recordedBy: recorder,
            keyWasExplicitlyConfirmed: true, recordedByWasExplicitlySelectedOrCaptured: true),
            intent: .plan(draft: draft, predecessor: nil))
        let decoded = try MyDayPlanningDraftCodecV1.decode(MyDayPlanningDraftCodecV1.encode(payload))
        let descendants = try TemporalNormalizationKnownDraftPayloadReferencesV1.releasedPurposeDescendants(.myDay(decoded))
        XCTAssertEqual(descendants.count, 2)
        for binding in descendants {
            guard case let .myDayEligible(actual) = binding else { return XCTFail("typed owner lost") }
            XCTAssertEqual(actual, reference)
        }
    }
    private enum ObservationStop: Error { case boundary, unexpectedContentPort }

    private func observationReservation() throws -> TemporalEvidencePromotionReservationV1 {
        let now = Date(timeIntervalSince1970: 1_820_000_000)
        let mutation = try MutationIDV1(rawValue: UUID()), leaseID = UUID()
        let request = try CapabilityScratchLeaseRequestV1(leaseID: leaseID, operationID: mutation.rawValue,
            purpose: .capture, requestedByteCount: 1024, createdAt: now, expiresAt: now.addingTimeInterval(60))
        let lease = CapabilityScratchLeaseV1(leaseID: leaseID, purpose: .capture,
            relativeDirectory: "capture-" + leaseID.uuidString.lowercased())
        let digest = String(repeating: "a", count: 64)
        let binding = try TemporalEvidenceScratchBindingV1(request: request, lease: lease,
            mutationID: mutation, contentID: "observation-test", contentSHA256: digest)
        return try .init(workspaceID: WorkspaceID(rawValue: UUID()), mutationID: mutation,
            contentID: "observation-test", contentSHA256: digest, binding: binding, state: .prepared)
    }

    private func observationStore(_ root: URL, _ reservation: TemporalEvidencePromotionReservationV1,
                                  boundary: TemporalEvidenceOperationalPublicationBoundaryV2? = nil)
        throws -> TemporalEvidencePromotionRecoveryFileAdapterV1 {
        try .init(generationRootURL: root, workspaceID: reservation.workspaceID,
            publicationBoundary: { if $0 == boundary { throw ObservationStop.boundary } },
            verify: { _, _, _ in throw ObservationStop.unexpectedContentPort },
            remove: { _, _, _ in throw ObservationStop.unexpectedContentPort })
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "V23TemporalNormalizationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }

    private func makeProtocolEpoch() throws -> GenerationEpochV1 {
        try .init(generationID: UUID(), generationManifestSHA256: String(repeating: "a", count: 64))
    }
}

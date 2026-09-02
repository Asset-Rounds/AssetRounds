import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

private enum C43 {
    static let now = Date(timeIntervalSince1970: 1_788_278_400)
    static func id(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "43000000-0000-4000-8000-%012x", value))!
    }
    static func mutation(_ value: Int) throws -> MutationIDV1 { try .init(rawValue: id(value)) }
}

private struct C43Clock: ApplicationClock { func now() -> Date { C43.now } }
private struct C43IDSource: ApplicationIDSource {
    let value: UUID
    func makeID() -> UUID { value }
}

@MainActor private final class C43Store {
    let root: URL
    let session: StoreGenerationSession
    let writerID = C43.id(2)

    init(_ label: String) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("c43-\(label)-\(UUID().uuidString)")
        session = try StoreGenerationFactory(applicationSupportURL: root).openOrBootstrapCurrent()
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    func make(failure: MutationJournalFailureInjectionV1? = nil) throws
        -> (writer: WorkspaceWriterV1, coordinator: SignoffEnrollmentCoordinatorV1, party: PartyAccountabilityCoordinatorV1) {
        let journal = try MutationJournalStoreV1(modelContext: session.modelContext,
            identity: session.workspaceIdentity, generationID: session.generationID, failureInjection: failure)
        let writer = try WorkspaceWriterV1(identity: session.workspaceIdentity, generationID: session.generationID,
            initialRevision: journal.currentRevision(writerInstanceID: writerID), clock: C43Clock(),
            idSource: C43IDSource(value: writerID), fileAuthority: SystemApplicationFileAuthorityV1(),
            adapter: WorkspaceWriterAdapterV1(modelContext: session.modelContext), journalStore: journal)
        let party = PartyAccountabilityCoordinatorV1(writer: writer, idSource: C43IDSource(value: C43.id(3)))
        return (writer, SignoffEnrollmentCoordinatorV1(partyCoordinator: party,
            idSource: C43IDSource(value: C43.id(4))), party)
    }

    func expected(_ writer: WorkspaceWriterV1, kind: WorkspaceEntityKindV1? = nil,
                  id: UUID? = nil, revision: UInt64 = 0) throws -> WorkspaceExpectedRevisionV1 {
        let current = try writer.currentRevision()
        var entities = current.entityRevisions
        if let kind, let id {
            let identity = try WorkspaceEntityIdentityV1(kind: kind, id: id)
            entities.removeAll { $0.identity == identity }
            entities.append(.init(identity: identity, revision: revision))
        }
        return try .init(workspaceID: current.workspaceID, generationID: current.generationID,
            writerInstanceID: current.writerInstanceID, workspaceRevision: current.revision,
            entityRevisions: entities.sorted { $0.identity.stableKey < $1.identity.stableKey })
    }

    func actor(_ bundle: (writer: WorkspaceWriterV1, coordinator: SignoffEnrollmentCoordinatorV1,
                          party: PartyAccountabilityCoordinatorV1), id: Int = 10) throws -> ActorSnapshotV1 {
        let reference = try LocalActorReferenceV1(actorReferenceID: C43.id(id), workspaceID: session.workspaceID,
            displayName: "Jordan Local")
        let actor = try ActorSnapshotV1(snapshotID: C43.id(id + 1), workspaceID: session.workspaceID,
            actor: reference, responsibility: .acknowledgedBy, displayNameAtTime: "Jordan Local", capturedAt: C43.now)
        let plan = try bundle.party.preview(mutation: .appendActorSnapshot(actor),
            expectedRevision: expected(bundle.writer, kind: .actorSnapshot, id: actor.snapshotID),
            workspaceID: session.workspaceID)
        _ = try bundle.party.commit(plan)
        return actor
    }

    func request(_ bundle: (writer: WorkspaceWriterV1, coordinator: SignoffEnrollmentCoordinatorV1,
                            party: PartyAccountabilityCoordinatorV1), actor: ActorSnapshotV1,
                 mark: SignoffEnrollmentDrawnMarkV1? = nil, mutation: Int = 20,
                 expected: WorkspaceExpectedRevisionV1? = nil) throws -> SignoffEnrollmentRequestV1 {
        let resolvedExpected: WorkspaceExpectedRevisionV1
        if let expected {
            resolvedExpected = expected
        } else {
            resolvedExpected = try self.expected(bundle.writer)
        }
        try .init(workspaceID: session.workspaceID, subjectID: C43.id(99), subjectRevision: 1,
            expectedRevision: resolvedExpected, actorSnapshot: actor,
            typedName: "Jordan Local", claimedRole: "Local responder", disclosure: .init(), routeChain: .init(),
            occurredAt: C43.now, recordedAt: C43.now, drawnMark: mark, mutationID: C43.mutation(mutation))
    }
}

final class V9_106SignoffEnrollmentTests: XCTestCase {
    private func corpus() throws -> [String: Any] {
        let name = "V23P04C43SignoffEnrollmentCorpusV1"
        let bundled = Bundle(for: Self.self).url(forResource: name, withExtension: "json", subdirectory: "Fixtures/V23/Accountability")
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/V23/Accountability/\(name).json")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: bundled ?? source)) as? [String: Any])
    }

    @MainActor func testV23P04C43G01TypedLocalResponseUsesExistingWriterAndFixedDisclosure() throws {
        let fixture = try corpus(); XCTAssertEqual(fixture["manifest"] as? String, "WORK_DETAIL_COMPLETED_RESPONSE_V1")
        let store = try C43Store("golden"), bundle = try store.make(), actor = try store.actor(bundle)
        let plan = try bundle.coordinator.preview(store.request(bundle, actor: actor))
        XCTAssertEqual(plan.manifest, .workDetailCompletedResponseV1); XCTAssertEqual(plan.method, .typedLocalAssertion)
        XCTAssertEqual(plan.partyPlan.basis.mutationID, C43.mutation(20)); XCTAssertEqual(plan.routeChain.actionRoot, .work)
        XCTAssertEqual(C43SignoffEnrollmentBoundaryV1.actionTitle, "Record approval response")
        XCTAssertTrue(plan.routeChain.requiresVisibleWorkRoot)
        XCTAssertFalse(plan.routeChain.directDeepLinkOnlyIsEligible)
        let receipt = try bundle.coordinator.commit(plan); try receipt.validate()
        XCTAssertEqual(receipt.mutationID, C43.mutation(20))
        XCTAssertEqual(try store.session.modelContext.fetchCount(FetchDescriptor<SignoffSnapshotRow>()), 1)
        let flags = SignoffEnrollmentProhibitedClaimFlagsV1(); try flags.validate()
        XCTAssertTrue(flags.disclaimsVerifiedIdentity && flags.disclaimsVerifiedAuthority && flags.disclaimsLegalSignature)
        XCTAssertTrue(flags.disclaimsBehalfOfAnotherPerson && flags.disclaimsLegalEffect)
        XCTAssertTrue(flags.disclaimsNonrepudiation && flags.disclaimsFinalApproval && flags.disclaimsWorkflowTransition)
    }

    @MainActor func testV23P04C43A01OptionalMarkOnlyChangesMethodAndNeverDurablyStoresMarkMaterial() throws {
        let store = try C43Store("alternate"), bundle = try store.make(), actor = try store.actor(bundle)
        let plan = try bundle.coordinator.preview(try store.request(bundle, actor: actor, mark: .presentNonBiometric))
        XCTAssertEqual(plan.method, .explicitLocalAcknowledgement); XCTAssertTrue(C43SignoffEnrollmentBoundaryV1.drawnMarkIsNonDurable)
        let receipt = try bundle.coordinator.commit(plan); let encoded = try JSONEncoder().encode(receipt)
        let text = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("stroke")); XCTAssertFalse(text.localizedCaseInsensitiveContains("image")); XCTAssertFalse(text.localizedCaseInsensitiveContains("biometric"))
    }

    @MainActor func testV23P04C43H01ActorWorkspaceStalenessReceiptAndManifestHostilityReject() throws {
        let store = try C43Store("hostile"), bundle = try store.make(), actor = try store.actor(bundle)
        let missing = try ActorSnapshotV1(snapshotID: C43.id(31), workspaceID: store.session.workspaceID,
            actor: try .init(actorReferenceID: C43.id(30), workspaceID: store.session.workspaceID, displayName: "Jordan Local"),
            responsibility: .acknowledgedBy, displayNameAtTime: "Jordan Local", capturedAt: C43.now)
        XCTAssertThrowsError(try bundle.coordinator.commit(bundle.coordinator.preview(try store.request(bundle, actor: missing, mutation: 31))))
        let other = WorkspaceID(rawValue: C43.id(32))
        let cross = try ActorSnapshotV1(snapshotID: C43.id(33), workspaceID: other,
            actor: try .init(actorReferenceID: C43.id(34), workspaceID: other, displayName: "Jordan Local"),
            responsibility: .acknowledgedBy, displayNameAtTime: "Jordan Local", capturedAt: C43.now)
        XCTAssertThrowsError(try store.request(bundle, actor: cross, mutation: 32))
        var stale = try store.expected(bundle.writer); stale = try .init(workspaceID: stale.workspaceID, generationID: stale.generationID, writerInstanceID: stale.writerInstanceID, workspaceRevision: 0, entityRevisions: stale.entityRevisions)
        XCTAssertThrowsError(try bundle.coordinator.preview(try store.request(bundle, actor: actor, mutation: 33, expected: stale)))
        let plan = try bundle.coordinator.preview(try store.request(bundle, actor: actor, mutation: 34)); let receipt = try bundle.coordinator.commit(plan)
        let receiptData = try JSONEncoder().encode(receipt); var receiptText = try XCTUnwrap(String(data: receiptData, encoding: .utf8)); receiptText = receiptText.replacingOccurrences(of: receipt.receiptSHA256, with: String(repeating: "0", count: 64))
        XCTAssertThrowsError(try JSONDecoder().decode(SignoffEnrollmentReceiptV1.self, from: try XCTUnwrap(receiptText.data(using: .utf8))))
        let foreignDisclosure = try SignoffIntentDisclosureReleaseV1(
            releaseID: "foreign-local-response-v1", disclosureText: "Foreign local response.")
        let foreignAssertion = try SignoffRoleAssertionV1(claimedRole: "Local responder",
            actor: actor, disclosureRelease: foreignDisclosure)
        let collision = try SignoffSnapshotV1(snapshotID: C43.id(35), workspaceID: store.session.workspaceID,
            purpose: SignoffEnrollmentManifestV1.workDetailCompletedResponseV1.purpose,
            subjectID: C43.id(99), subjectRevision: 1, disposition: .recordedLocalAssertion,
            method: .typedLocalAssertion, roleAssertion: foreignAssertion, occurredAt: C43.now, recordedAt: C43.now,
            mutationID: C43.mutation(35))
        XCTAssertTrue(C43SignoffEnrollmentBoundaryV1.isEnrollmentSnapshot(collision))
        let genericPlan = try bundle.party.preview(mutation: .appendSignoff(collision),
            expectedRevision: store.expected(bundle.writer), workspaceID: store.session.workspaceID)
        XCTAssertThrowsError(try bundle.party.commit(genericPlan))
        XCTAssertEqual(SignoffEnrollmentManifestV1.workDetailCompletedResponseV1.purpose, "WORK_DETAIL_COMPLETED_RESPONSE_V1")
    }

    @MainActor func testV23P04C43I01AndR01ReplayReceiptFirstAndKeepAcknowledgementBytesUnmigrated() throws {
        let store = try C43Store("replay"), bundle = try store.make(), actor = try store.actor(bundle)
        let plan = try bundle.coordinator.preview(try store.request(bundle, actor: actor, mutation: 40))
        let first = try bundle.coordinator.commit(plan), replay = try bundle.coordinator.commit(plan)
        XCTAssertEqual(first, replay); XCTAssertEqual(try store.session.modelContext.fetchCount(FetchDescriptor<SignoffSnapshotRow>()), 1)
        let frozenPreC43Bytes = Data(
            "{\"accepted\":true,\"copy\":\"Local response only\",\"key\":\"local_response_only\",\"version\":\"v1\"}".utf8
        )
        let value = try JSONDecoder().decode(AcknowledgementSnapshotV1.self, from: frozenPreC43Bytes)
        XCTAssertTrue(value.accepted)
        XCTAssertEqual(value.copy, "Local response only")
        XCTAssertEqual(value.key, "local_response_only")
        XCTAssertEqual(value.version, "v1")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(value); let restored = try JSONDecoder().decode(AcknowledgementSnapshotV1.self, from: bytes)
        XCTAssertEqual(restored, value); XCTAssertEqual(bytes, frozenPreC43Bytes)
    }
}

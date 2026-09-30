import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

private enum C42 {
    static let now = Date(timeIntervalSince1970: 1_788_192_000)
    static func id(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "42000000-0000-4000-8000-%012x", value))!
    }
    static func mutation(_ value: Int) throws -> MutationIDV1 { try .init(rawValue: id(value)) }
}

private struct C42Clock: ApplicationClock { func now() -> Date { C42.now } }
private struct C42IDSource: ApplicationIDSource {
    let value: UUID
    func makeID() -> UUID { value }
}

@MainActor private final class C42NoSystemHandoff: SystemHandoffPortV1 {
    func handOff(_ request: SystemHandoffRequestV1) async -> SystemHandoffResultV1 {
        try! .init(intentID: request.intent.intentID, disposition: .systemUnavailable,
                   evaluatedAt: C42.now)
    }
}

@MainActor private final class C42Query: PartyContactSiteRoleWorkflowQueryingV1 {
    let context: ModelContext
    let workspaceID: WorkspaceID

    init(context: ModelContext, workspaceID: WorkspaceID) {
        self.context = context
        self.workspaceID = workspaceID
    }

    func currentParty(workspaceID: WorkspaceID, partyID: UUID) async throws
        -> ServicePartyReferenceV1? {
        guard workspaceID == self.workspaceID else { return nil }
        let raw = workspaceID.rawValue
        let rows = try context.fetch(FetchDescriptor<ServicePartyRow>(
            predicate: #Predicate { $0.workspaceID == raw && $0.partyID == partyID }
        ))
        guard rows.count <= 1 else { throw PartyContactSiteRoleWorkflowFailureV1.identityMismatch }
        return try rows.first?.value()
    }

    func currentContactPoints(workspaceID: WorkspaceID, partyID: UUID,
                              kind: ServiceContactKindV1) async throws
        -> [ServiceContactPointV1] {
        guard workspaceID == self.workspaceID else { return [] }
        let raw = workspaceID.rawValue
        return try context.fetch(FetchDescriptor<ServiceContactPointRow>(
            predicate: #Predicate { $0.workspaceID == raw && $0.partyID == partyID }
        )).map { try $0.value() }.filter { $0.kind == kind }
    }

    func siteRoleHistory(workspaceID: WorkspaceID, siteID: UUID, partyID: UUID?) async throws
        -> [SitePartyRoleEventV1] {
        guard workspaceID == self.workspaceID else { return [] }
        let raw = workspaceID.rawValue
        return try context.fetch(FetchDescriptor<SitePartyRoleEventRow>(
            predicate: #Predicate { $0.workspaceID == raw && $0.siteID == siteID }
        )).map { try $0.value() }.filter { partyID == nil || $0.partyID == partyID }
    }
}

@MainActor private final class C42Store {
    struct Bundle {
        let writer: WorkspaceWriterV1
        let workflow: PartyContactSiteRoleWorkflowCoordinatorV1
    }

    let root: URL
    let session: StoreGenerationSession
    let writerID = C42.id(2)
    let query: C42Query

    init(_ label: String) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("c42-\(label)-\(UUID().uuidString)")
        session = try StoreGenerationFactory(applicationSupportURL: root).openOrBootstrapCurrent()
        query = C42Query(context: session.modelContext, workspaceID: session.workspaceID)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    func make(failure: MutationJournalFailureInjectionV1? = nil) throws -> Bundle {
        let journal = try MutationJournalStoreV1(modelContext: session.modelContext,
            identity: session.workspaceIdentity, generationID: session.generationID,
            failureInjection: failure)
        let writer = try WorkspaceWriterV1(identity: session.workspaceIdentity,
            generationID: session.generationID,
            initialRevision: journal.currentRevision(writerInstanceID: writerID),
            clock: C42Clock(), idSource: C42IDSource(value: writerID),
            fileAuthority: SystemApplicationFileAuthorityV1(),
            adapter: WorkspaceWriterAdapterV1(modelContext: session.modelContext),
            journalStore: journal)
        let contactQuery = OperationalContactRowQueryV1(modelContext: session.modelContext,
                                                        workspaceID: session.workspaceID)
        let contact = OperationalContactCoordinatorV1(query: contactQuery, writer: writer,
            system: C42NoSystemHandoff(), clock: C42Clock(),
            idSource: C42IDSource(value: C42.id(3)), importQuery: contactQuery)
        let party = PartyAccountabilityCoordinatorV1(writer: writer,
            idSource: C42IDSource(value: C42.id(4)))
        return Bundle(writer: writer, workflow: .init(partyCoordinator: party,
            contactCoordinator: contact, query: query))
    }

    func expected(_ writer: WorkspaceWriterV1, kind: WorkspaceEntityKindV1,
                  id: UUID, revision: UInt64) throws -> WorkspaceExpectedRevisionV1 {
        let current = try writer.currentRevision()
        let identity = try WorkspaceEntityIdentityV1(kind: kind, id: id)
        var revisions = current.entityRevisions.filter { $0.identity != identity }
        revisions.append(WorkspaceEntityRevisionV1(identity: identity, revision: revision))
        return try .init(workspaceID: current.workspaceID, generationID: current.generationID,
            writerInstanceID: current.writerInstanceID, workspaceRevision: current.revision,
            entityRevisions: revisions.sorted { $0.identity.stableKey < $1.identity.stableKey })
    }

    func rows<Row: PersistentModel>(_ type: Row.Type) throws -> [Row] {
        try session.modelContext.fetch(FetchDescriptor<Row>())
    }
}

final class V9_105PartyContactSiteRoleWorkflowTests: XCTestCase {
    private func corpus() throws -> [String: Any] {
        let name = "V23P04C42PartyContactSiteRoleWorkflowCorpusV1"
        let bundled = Bundle(for: Self.self).url(forResource: name, withExtension: "json",
            subdirectory: "Fixtures/V23/Contacts")
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/V23/Contacts/\(name).json")
        return try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(contentsOf: bundled ?? source)) as? [String: Any])
    }

    @MainActor
    func testV23P04C42G01CreatePartyContactsPreferredRoleImpactAndHistory() async throws {
        let fixture = try corpus()
        XCTAssertEqual(fixture["cardID"] as? String, "V23-P04-C42")
        XCTAssertEqual(fixture["evidenceIDs"] as? [String], [
            "V23-P04-C42-G01", "V23-P04-C42-A01", "V23-P04-C42-H01",
            "V23-P04-C42-I01", "V23-P04-C42-R01"
        ])
        let store = try C42Store("golden")
        let bundle = try store.make()
        let partyID = C42.id(10), phoneID = C42.id(11), emailID = C42.id(12)
        let siteID = C42.id(13), roleID = C42.id(14)
        let partyPreview = try await bundle.workflow.previewCreateParty(
            workspaceID: store.session.workspaceID, partyID: partyID, kind: .organization,
            displayName: "Synthetic Service Co", profileDescriptor: "Operational contact",
            effectiveAt: C42.now,
            expectedRevision: store.expected(bundle.writer, kind: .serviceParty,
                                             id: partyID, revision: 0),
            mutationID: C42.mutation(20))
        XCTAssertTrue(partyPreview.zeroWrite)
        XCTAssertEqual(partyPreview.impact.cascadeCount, 0)
        guard case .party = try await bundle.workflow.execute(.commitParty(partyPreview)) else {
            return XCTFail("party")
        }
        let phone = try await bundle.workflow.previewCreateContact(
            workspaceID: store.session.workspaceID, contactPointID: phoneID, partyID: partyID,
            kind: .phone, label: .work, displayValue: "+12125550142", preferred: true,
            effectiveAt: C42.now,
            expectedRevision: store.expected(bundle.writer, kind: .serviceContactPoint,
                                             id: phoneID, revision: 0),
            mutationID: C42.mutation(21))
        guard case .contact = try await bundle.workflow.execute(.commitContact(phone)) else {
            return XCTFail("phone")
        }
        let email = try await bundle.workflow.previewCreateContact(
            workspaceID: store.session.workspaceID, contactPointID: emailID, partyID: partyID,
            kind: .email, label: .work, displayValue: "service@example.test", preferred: true,
            effectiveAt: C42.now,
            expectedRevision: store.expected(bundle.writer, kind: .serviceContactPoint,
                                             id: emailID, revision: 0),
            mutationID: C42.mutation(22))
        guard case .contact = try await bundle.workflow.execute(.commitContact(email)) else {
            return XCTFail("email")
        }
        let role = try await bundle.workflow.previewAppendSiteRole(
            workspaceID: store.session.workspaceID, eventID: roleID, siteID: siteID,
            partyID: partyID, role: .serviceProvider, effectiveFrom: C42.now,
            recordedAt: C42.now,
            expectedRevision: store.expected(bundle.writer, kind: .sitePartyRoleEvent,
                                             id: roleID, revision: 0),
            mutationID: C42.mutation(23))
        XCTAssertEqual(role.impact.affectedSiteRoleEventIDs, [roleID])
        XCTAssertEqual(role.impact.cascadeCount, 0)
        guard case .siteRole = try await bundle.workflow.execute(.commitSiteRole(role)) else {
            return XCTFail("role")
        }
        let queriedParty = try await store.query.currentParty(
            workspaceID: store.session.workspaceID, partyID: partyID)
        let party = try XCTUnwrap(queriedParty)
        let phones = try await store.query.currentContactPoints(
            workspaceID: store.session.workspaceID, partyID: partyID, kind: .phone)
        let emails = try await store.query.currentContactPoints(
            workspaceID: store.session.workspaceID, partyID: partyID, kind: .email)
        let contacts = phones + emails
        let roles = try await store.query.siteRoleHistory(workspaceID: store.session.workspaceID,
                                                          siteID: siteID, partyID: partyID)
        let history = try bundle.workflow.history(workspaceID: store.session.workspaceID,
            partyRevisions: [party], contactRevisions: contacts, siteRoleEvents: roles)
        XCTAssertEqual(history.contactRevisions.filter(\.preferred).count, 2)
        XCTAssertEqual(history.siteRoleEvents.count, 1)
        XCTAssertEqual(try store.rows(MutationReceiptRow.self).count, 4)
    }

    @MainActor
    func testV23P04C42A01EditsLifecyclePreferenceReversalAndPresentationLabels() async throws {
        let store = try C42Store("alternate")
        let bundle = try store.make()
        let partyID = C42.id(30), firstID = C42.id(31), secondID = C42.id(32)
        let siteID = C42.id(33), roleID = C42.id(34)
        let create = try await bundle.workflow.previewCreateParty(workspaceID: store.session.workspaceID,
            partyID: partyID, kind: .person, displayName: "Original Name", effectiveAt: C42.now,
            expectedRevision: store.expected(bundle.writer, kind: .serviceParty, id: partyID, revision: 0),
            mutationID: C42.mutation(40))
        _ = try await bundle.workflow.execute(.commitParty(create))
        let renamed = try await bundle.workflow.previewEditParty(workspaceID: store.session.workspaceID,
            partyID: partyID, displayName: "Renamed Party",
            expectedRevision: store.expected(bundle.writer, kind: .serviceParty, id: partyID, revision: 1),
            mutationID: C42.mutation(41))
        _ = try await bundle.workflow.execute(.commitParty(renamed))
        for (id, value, mutation) in [(firstID, "first@example.test", 42),
                                      (secondID, "second@example.test", 43)] {
            let preview = try await bundle.workflow.previewCreateContact(
                workspaceID: store.session.workspaceID, contactPointID: id, partyID: partyID,
                kind: .email, label: .work, displayValue: value, preferred: id == firstID,
                effectiveAt: C42.now,
                expectedRevision: store.expected(bundle.writer, kind: .serviceContactPoint,
                                                 id: id, revision: 0),
                mutationID: C42.mutation(mutation))
            _ = try await bundle.workflow.execute(.commitContact(preview))
        }
        let edited = try await bundle.workflow.previewEditContact(
            workspaceID: store.session.workspaceID, contactPointID: secondID,
            label: .other, displayValue: "edited@example.test", preferred: false,
            expectedRevision: store.expected(bundle.writer, kind: .serviceContactPoint,
                                             id: secondID, revision: 1),
            mutationID: C42.mutation(440))
        _ = try await bundle.workflow.execute(.commitContact(edited))
        let preferred = try await bundle.workflow.previewSetPreferredContact(
            workspaceID: store.session.workspaceID, contactPointID: secondID,
            expectedRevision: store.expected(bundle.writer, kind: .serviceContactPoint,
                                             id: secondID, revision: 2),
            mutationID: C42.mutation(44))
        XCTAssertEqual(preferred.mutation.successors.count, 2)
        _ = try await bundle.workflow.execute(.commitContact(preferred))
        let retired = try await bundle.workflow.previewRetireContact(
            workspaceID: store.session.workspaceID, contactPointID: firstID,
            retiredAt: C42.now.addingTimeInterval(60),
            expectedRevision: store.expected(bundle.writer, kind: .serviceContactPoint,
                                             id: firstID, revision: 2),
            mutationID: C42.mutation(45))
        _ = try await bundle.workflow.execute(.commitContact(retired))
        let reactivated = try await bundle.workflow.previewReactivateContact(
            workspaceID: store.session.workspaceID, contactPointID: firstID, preferred: false,
            expectedRevision: store.expected(bundle.writer, kind: .serviceContactPoint,
                                             id: firstID, revision: 3),
            mutationID: C42.mutation(46))
        _ = try await bundle.workflow.execute(.commitContact(reactivated))
        let role = try await bundle.workflow.previewAppendSiteRole(workspaceID: store.session.workspaceID,
            eventID: roleID, siteID: siteID, partyID: partyID, role: .client,
            effectiveFrom: C42.now, recordedAt: C42.now,
            expectedRevision: store.expected(bundle.writer, kind: .sitePartyRoleEvent,
                                             id: roleID, revision: 0),
            mutationID: C42.mutation(47))
        _ = try await bundle.workflow.execute(.commitSiteRole(role))
        let reversalID = C42.id(35)
        let reversal = try await bundle.workflow.previewReverseSiteRole(
            workspaceID: store.session.workspaceID, siteID: siteID,
            predecessorEventID: roleID, successorEventID: reversalID,
            effectiveFrom: C42.now, effectiveUntil: C42.now.addingTimeInterval(120),
            recordedAt: C42.now.addingTimeInterval(121),
            expectedRevision: store.expected(bundle.writer, kind: .sitePartyRoleEvent,
                                             id: reversalID, revision: 0),
            mutationID: C42.mutation(48))
        _ = try await bundle.workflow.execute(.commitSiteRole(reversal))
        let queriedParty = try await store.query.currentParty(
            workspaceID: store.session.workspaceID, partyID: partyID)
        let party = try XCTUnwrap(queriedParty)
        let contacts = try await store.query.currentContactPoints(
            workspaceID: store.session.workspaceID, partyID: partyID, kind: .email)
        let roles = try await store.query.siteRoleHistory(
            workspaceID: store.session.workspaceID, siteID: siteID, partyID: partyID)
        let history = try bundle.workflow.history(workspaceID: store.session.workspaceID,
            partyRevisions: [party], contactRevisions: contacts, siteRoleEvents: roles)
        XCTAssertEqual(history.customerPresentationLabel, "Customer")
        XCTAssertEqual(history.sitePresentationLabel, "Site")
        XCTAssertEqual(history.siteRoleEvents.count, 2)
        XCTAssertEqual(history.contactRevisions.first { $0.contactPointID == firstID }?.lifecycle,
                       .effective)
    }

    @MainActor
    func testV23P04C42H01IdentityHostilityStalenessAndDivergenceHaveNoEffect() async throws {
        let store = try C42Store("hostile")
        let bundle = try store.make()
        let partyIDs = [C42.id(50), C42.id(51)]
        for (index, partyID) in partyIDs.enumerated() {
            let preview = try await bundle.workflow.previewCreateParty(
                workspaceID: store.session.workspaceID, partyID: partyID, kind: .person,
                displayName: "Equal Name", effectiveAt: C42.now,
                expectedRevision: store.expected(bundle.writer, kind: .serviceParty,
                                                 id: partyID, revision: 0),
                mutationID: C42.mutation(60 + index))
            _ = try await bundle.workflow.execute(.commitParty(preview))
        }
        XCTAssertEqual(try store.rows(ServicePartyRow.self).count, 2)
        let contactIDs = [C42.id(52), C42.id(53)]
        for index in 0..<2 {
            let preview = try await bundle.workflow.previewCreateContact(
                workspaceID: store.session.workspaceID, contactPointID: contactIDs[index],
                partyID: partyIDs[index], kind: .email, label: .work,
                displayValue: "equal@example.test", preferred: true, effectiveAt: C42.now,
                expectedRevision: store.expected(bundle.writer, kind: .serviceContactPoint,
                                                 id: contactIDs[index], revision: 0),
                mutationID: C42.mutation(62 + index))
            _ = try await bundle.workflow.execute(.commitContact(preview))
        }
        XCTAssertEqual(try store.rows(ServiceContactPointRow.self).count, 2)
        let phoneIDs = [C42.id(54), C42.id(55)]
        for index in 0..<2 {
            let preview = try await bundle.workflow.previewCreateContact(
                workspaceID: store.session.workspaceID, contactPointID: phoneIDs[index],
                partyID: partyIDs[index], kind: .phone, label: .work,
                displayValue: "+12125550142", preferred: true, effectiveAt: C42.now,
                expectedRevision: store.expected(bundle.writer, kind: .serviceContactPoint,
                                                 id: phoneIDs[index], revision: 0),
                mutationID: C42.mutation(70 + index))
            _ = try await bundle.workflow.execute(.commitContact(preview))
        }
        XCTAssertEqual(try store.rows(ServiceContactPointRow.self).count, 4)
        let baseline = try store.rows(MutationReceiptRow.self).count
        do {
            _ = try await bundle.workflow.previewEditParty(workspaceID: store.session.workspaceID,
                partyID: partyIDs[0], displayName: "Stale",
                expectedRevision: store.expected(bundle.writer, kind: .serviceParty,
                                                 id: partyIDs[0], revision: 0),
                mutationID: C42.mutation(64))
            XCTFail("stale preview")
        } catch { XCTAssertNotNil(error as? PartyAccountabilityCoordinatorFailureV1) }
        do {
            _ = try await bundle.workflow.previewCreateContact(workspaceID: WorkspaceID(rawValue: C42.id(99)),
                contactPointID: C42.id(56), partyID: partyIDs[0], kind: .phone, label: .work,
                displayValue: "+12125550142", preferred: false, effectiveAt: C42.now,
                expectedRevision: store.expected(bundle.writer, kind: .serviceContactPoint,
                                                 id: C42.id(56), revision: 0),
                mutationID: C42.mutation(65))
            XCTFail("wrong workspace")
        } catch { XCTAssertEqual(error as? PartyContactSiteRoleWorkflowFailureV1, .identityMismatch) }
        XCTAssertThrowsError(try PartyContactSiteRoleImpactV1(operation: .createParty,
            affectedPartyIDs: [partyIDs[0]], affectedContactPointIDs: [contactIDs[0]]))
        let accepted = try await bundle.workflow.previewEditParty(workspaceID: store.session.workspaceID,
            partyID: partyIDs[0], displayName: "Accepted",
            expectedRevision: store.expected(bundle.writer, kind: .serviceParty,
                                             id: partyIDs[0], revision: 1),
            mutationID: C42.mutation(66))
        XCTAssertTrue(accepted.impact.warnings.contains(.operationalPurposeOnly))
        XCTAssertThrowsError(try PartyWorkflowPreviewV1(plan: accepted.plan,
            impact: .init(operation: .retireParty, affectedPartyIDs: [partyIDs[0]]))) {
            XCTAssertEqual($0 as? PartyContactSiteRoleWorkflowFailureV1, .invalidContext)
        }
        _ = try await bundle.workflow.execute(.commitParty(accepted))
        let current = try bundle.writer.currentRevision()
        let identity = try WorkspaceEntityIdentityV1(kind: .serviceParty, id: partyIDs[0])
        let expected = try WorkspaceExpectedRevisionV1(workspaceID: current.workspaceID,
            generationID: current.generationID, writerInstanceID: current.writerInstanceID,
            workspaceRevision: accepted.plan.basis.expectedRevision.workspaceRevision,
            entityRevisions: accepted.plan.basis.expectedRevision.entityRevisions)
        let divergentParty = try ServicePartyReferenceV1(partyID: partyIDs[0],
            workspaceID: store.session.workspaceID, kind: .person, displayName: "Divergent",
            provenance: .locallyRecorded, state: .effective, effectiveAt: C42.now,
            revision: 2, mutationID: C42.mutation(66))
        let divergentPlan = try PartyAccountabilityChangePlanV1(operationID: accepted.plan.operationID,
            mutationID: C42.mutation(66), basis: .init(workspaceID: store.session.workspaceID,
                expectedRevision: expected, mutation: .recordParty(divergentParty)))
        let divergentPreview = try PartyWorkflowPreviewV1(plan: divergentPlan,
            impact: .init(operation: .editParty, affectedPartyIDs: [partyIDs[0]]))
        do {
            _ = try await bundle.workflow.execute(.recoverParty(divergentPreview))
            XCTFail("divergent replay")
        } catch { XCTAssertNotNil(error) }
        XCTAssertEqual(try store.rows(MutationReceiptRow.self).count, baseline + 1)
        XCTAssertEqual(try bundle.writer.currentRevision().entityRevisions.first {
            $0.identity == identity
        }?.revision, 2)
        let retire = try await bundle.workflow.previewRetireParty(
            workspaceID: store.session.workspaceID, partyID: partyIDs[0],
            retiredAt: C42.now.addingTimeInterval(600),
            expectedRevision: store.expected(bundle.writer, kind: .serviceParty,
                                             id: partyIDs[0], revision: 2),
            mutationID: C42.mutation(67))
        _ = try await bundle.workflow.execute(.commitParty(retire))
        let afterRetirement = try store.rows(MutationReceiptRow.self).count
        do {
            _ = try await bundle.workflow.previewEditParty(
                workspaceID: store.session.workspaceID, partyID: partyIDs[0],
                displayName: "Forbidden Reactivation",
                expectedRevision: store.expected(bundle.writer, kind: .serviceParty,
                                                 id: partyIDs[0], revision: 3),
                mutationID: C42.mutation(68))
            XCTFail("retired Party cannot be reactivated")
        } catch {
            XCTAssertEqual(error as? PartyContactSiteRoleWorkflowFailureV1, .retiredParty)
        }
        XCTAssertEqual(try store.rows(MutationReceiptRow.self).count, afterRetirement)
        XCTAssertEqual(try store.rows(ServiceContactPointRow.self).count, 4)
    }

    @MainActor
    func testV23P04C42I01EffectBeforeReceiptRecoveryIsReceiptFirstAndExactlyOnce() async throws {
        let store = try C42Store("interrupt")
        let faulted = try store.make(failure: .init(failOnceAt: .afterEffectBeforeReceipt))
        let partyID = C42.id(70)
        let preview = try await faulted.workflow.previewCreateParty(
            workspaceID: store.session.workspaceID, partyID: partyID, kind: .organization,
            displayName: "Interrupted Party", effectiveAt: C42.now,
            expectedRevision: store.expected(faulted.writer, kind: .serviceParty,
                                             id: partyID, revision: 0),
            mutationID: C42.mutation(71))
        do {
            _ = try await faulted.workflow.execute(.commitParty(preview))
            XCTFail("interrupt")
        } catch {
            XCTAssertEqual(error as? MutationJournalFailureV1,
                           .injected(.afterEffectBeforeReceipt))
        }
        let recovered = try store.make()
        let first = try await recovered.workflow.execute(.recoverParty(preview))
        let replay = try await recovered.workflow.execute(.recoverParty(preview))
        XCTAssertEqual(first, replay)
        XCTAssertEqual(try store.rows(ServicePartyRow.self).count, 1)
        XCTAssertEqual(try store.rows(MutationReceiptRow.self).filter {
            $0.mutationID == C42.id(71)
        }.count, 1)

        let contactID = C42.id(72)
        let contactFaulted = try store.make(
            failure: .init(failOnceAt: .afterEffectBeforeReceipt))
        let contactPreview = try await contactFaulted.workflow.previewCreateContact(
            workspaceID: store.session.workspaceID, contactPointID: contactID,
            partyID: partyID, kind: .email, label: .work,
            displayValue: "interrupt@example.test", preferred: true, effectiveAt: C42.now,
            expectedRevision: store.expected(contactFaulted.writer, kind: .serviceContactPoint,
                                             id: contactID, revision: 0),
            mutationID: C42.mutation(73))
        do {
            _ = try await contactFaulted.workflow.execute(.commitContact(contactPreview))
            XCTFail("contact interrupt")
        } catch {
            XCTAssertEqual(error as? MutationJournalFailureV1,
                           .injected(.afterEffectBeforeReceipt))
        }
        let contactRecovered = try store.make()
        let contactFirst = try await contactRecovered.workflow.execute(
            .recoverContact(contactPreview))
        let contactReplay = try await contactRecovered.workflow.execute(
            .recoverContact(contactPreview))
        XCTAssertEqual(contactFirst, contactReplay)

        let siteID = C42.id(74), roleID = C42.id(75)
        let roleFaulted = try store.make(failure: .init(failOnceAt: .afterEffectBeforeReceipt))
        let rolePreview = try await roleFaulted.workflow.previewAppendSiteRole(
            workspaceID: store.session.workspaceID, eventID: roleID, siteID: siteID,
            partyID: partyID, role: .operator, effectiveFrom: C42.now, recordedAt: C42.now,
            expectedRevision: store.expected(roleFaulted.writer, kind: .sitePartyRoleEvent,
                                             id: roleID, revision: 0),
            mutationID: C42.mutation(76))
        do {
            _ = try await roleFaulted.workflow.execute(.commitSiteRole(rolePreview))
            XCTFail("role interrupt")
        } catch {
            XCTAssertEqual(error as? MutationJournalFailureV1,
                           .injected(.afterEffectBeforeReceipt))
        }
        let roleRecovered = try store.make()
        let roleFirst = try await roleRecovered.workflow.execute(.recoverSiteRole(rolePreview))
        let roleReplay = try await roleRecovered.workflow.execute(.recoverSiteRole(rolePreview))
        XCTAssertEqual(roleFirst, roleReplay)

        let reversalID = C42.id(77)
        let reversalFaulted = try store.make(
            failure: .init(failOnceAt: .afterEffectBeforeReceipt))
        let reversalPreview = try await reversalFaulted.workflow.previewReverseSiteRole(
            workspaceID: store.session.workspaceID, siteID: siteID,
            predecessorEventID: roleID, successorEventID: reversalID,
            effectiveFrom: C42.now, effectiveUntil: C42.now.addingTimeInterval(300),
            recordedAt: C42.now.addingTimeInterval(301),
            expectedRevision: store.expected(reversalFaulted.writer,
                                             kind: .sitePartyRoleEvent,
                                             id: reversalID, revision: 0),
            mutationID: C42.mutation(78))
        do {
            _ = try await reversalFaulted.workflow.execute(
                .commitSiteRole(reversalPreview))
            XCTFail("role reversal interrupt")
        } catch {
            XCTAssertEqual(error as? MutationJournalFailureV1,
                           .injected(.afterEffectBeforeReceipt))
        }
        let reversalRecovered = try store.make()
        let reversalFirst = try await reversalRecovered.workflow.execute(
            .recoverSiteRole(reversalPreview))
        let reversalReplay = try await reversalRecovered.workflow.execute(
            .recoverSiteRole(reversalPreview))
        XCTAssertEqual(reversalFirst, reversalReplay)
        XCTAssertEqual(try store.rows(ServiceContactPointRow.self).count, 1)
        XCTAssertEqual(try store.rows(SitePartyRoleEventRow.self).count, 2)
        XCTAssertEqual(try store.rows(MutationReceiptRow.self).filter {
            [C42.id(71), C42.id(73), C42.id(76), C42.id(78)].contains($0.mutationID)
        }.count, 4)
    }

    @MainActor
    func testV23P04C42R01RebuildHistoryFreezesEmbeddedSnapshotsAndPreservesNamespaces() async throws {
        let store = try C42Store("rebuild")
        let bundle = try store.make()
        let partyID = C42.id(80), contactID = C42.id(81), siteID = C42.id(82), roleID = C42.id(83)
        let create = try await bundle.workflow.previewCreateParty(workspaceID: store.session.workspaceID,
            partyID: partyID, kind: .person, displayName: "Historic Name", effectiveAt: C42.now,
            expectedRevision: store.expected(bundle.writer, kind: .serviceParty, id: partyID, revision: 0),
            mutationID: C42.mutation(84))
        _ = try await bundle.workflow.execute(.commitParty(create))
        let contact = try await bundle.workflow.previewCreateContact(workspaceID: store.session.workspaceID,
            contactPointID: contactID, partyID: partyID, kind: .phone, label: .mobile,
            displayValue: "+12125550143", preferred: true, effectiveAt: C42.now,
            expectedRevision: store.expected(bundle.writer, kind: .serviceContactPoint,
                                             id: contactID, revision: 0),
            mutationID: C42.mutation(85))
        _ = try await bundle.workflow.execute(.commitContact(contact))
        let frozenCandidates = try await store.query.currentContactPoints(
            workspaceID: store.session.workspaceID, partyID: partyID, kind: .phone)
        let frozen = try XCTUnwrap(frozenCandidates.first)
        let role = try await bundle.workflow.previewAppendSiteRole(workspaceID: store.session.workspaceID,
            eventID: roleID, siteID: siteID, partyID: partyID, role: .contact,
            effectiveFrom: C42.now, recordedAt: C42.now,
            expectedRevision: store.expected(bundle.writer, kind: .sitePartyRoleEvent,
                                             id: roleID, revision: 0),
            mutationID: C42.mutation(86))
        _ = try await bundle.workflow.execute(.commitSiteRole(role))
        let rename = try await bundle.workflow.previewEditParty(workspaceID: store.session.workspaceID,
            partyID: partyID, displayName: "Current Name",
            expectedRevision: store.expected(bundle.writer, kind: .serviceParty, id: partyID, revision: 1),
            mutationID: C42.mutation(87))
        _ = try await bundle.workflow.execute(.commitParty(rename))
        let queriedCurrent = try await store.query.currentParty(
            workspaceID: store.session.workspaceID, partyID: partyID)
        let current = try XCTUnwrap(queriedCurrent)
        XCTAssertEqual(current.displayName, "Current Name")
        XCTAssertEqual(frozen.party.displayName, "Historic Name")
        guard case let .recordParty(original) = create.plan.basis.mutation else {
            return XCTFail("original party")
        }
        let events = try await store.query.siteRoleHistory(workspaceID: store.session.workspaceID,
                                                           siteID: siteID, partyID: partyID)
        let first = try bundle.workflow.history(workspaceID: store.session.workspaceID,
            partyRevisions: [current, original], contactRevisions: [frozen], siteRoleEvents: events)
        let rebuilt = try bundle.workflow.history(workspaceID: store.session.workspaceID,
            partyRevisions: [current, original], contactRevisions: [frozen], siteRoleEvents: events)
        XCTAssertEqual(first, rebuilt)
        XCTAssertEqual(first.partyRevisions.map(\.revision), [1, 2])
        XCTAssertEqual(Set(first.partyRevisions.map {
            "\($0.partyID.uuidString)|\($0.revision)"
        }).count, 2)
        XCTAssertTrue(first.partyAndContactHistoryIsCallerBounded)
        XCTAssertTrue(first.siteRoleHistoryIsAppendOnly)
        XCTAssertTrue(first.contactRevisions.allSatisfy { $0.party.displayName == "Historic Name" })
        XCTAssertEqual(try store.rows(ServiceContactPointRow.self).count, 1)
        XCTAssertEqual(try store.rows(SitePartyRoleEventRow.self).count, 1)
        let commandKinds = Set(try store.rows(MutationReceiptRow.self).map(\.commandKind))
        XCTAssertTrue(commandKinds.contains(WorkspaceCommandKindV1.applyPartyAccountability.rawValue))
        XCTAssertTrue(commandKinds.contains(WorkspaceCommandKindV1.applyOperationalContact.rawValue))
    }
}

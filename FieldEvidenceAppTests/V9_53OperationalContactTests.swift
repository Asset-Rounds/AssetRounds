import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

private enum C52ServiceRequestBoundary_V9_53OperationalContactTests {
    static let typedAnchor: C52ServiceRequestBoundaryTokenV1.Type = C52ServiceRequestBoundaryTokenV1.self
}

@MainActor
final class V9_53OperationalContactTests: XCTestCase {
    func testV23P03C46G01CanonicalOperationalContactAndExplicitHandoffUseOneWorkspaceMutation() throws {
        let contact = try C46OperationalContactTestSupport.contact(
            slot: 10,
            kind: .email,
            label: .work,
            displayValue: "Ops+Night@Example.COM",
            preferred: true
        )
        let intent = try C46OperationalContactTestSupport.intent(
            slot: 30,
            kind: .email,
            contact: contact
        )
        let expected = try C46OperationalContactTestSupport.expectedRevision(
            contact: contact,
            intent: intent,
            revision: 0,
            slot: 20
        )
        let mutation = try OperationalContactMutationV1(
            workspaceID: contact.workspaceID,
            mutationID: contact.mutationID,
            expectedRevision: expected,
            predecessors: [],
            successors: [contact],
            preferredScopes: [
                ServiceContactPreferredScopeV1(
                    partyID: contact.party.partyID,
                    kind: .email,
                    activeContactPointIDs: [contact.contactPointID],
                    preferredContactPointID: contact.contactPointID
                )
            ],
            handoffIntents: [intent]
        )

        let request = try mutation.canonicalWorkspaceMutationRequest()
        XCTAssertEqual(request.mutationID, contact.mutationID)
        XCTAssertEqual(try mutation.affectedIdentities.count, 2)
        XCTAssertEqual(try mutation.concurrencyIdentities.count, 3)
        XCTAssertEqual(
            try mutation.expectedRevision(
                for: WorkspaceEntityIdentityV1(kind: .serviceParty, id: contact.party.partyID)
            ),
            contact.party.revision
        )
        XCTAssertEqual(
            try OperationalContactCanonicalCodecV1.decode(
                ServiceContactPointV1.self,
                from: OperationalContactCanonicalCodecV1.data(contact)
            ),
            contact
        )
        XCTAssertEqual(contact.displayValue, "Ops+Night@Example.COM")
        XCTAssertEqual(contact.privacyClass, .workspaceCustomerData)

        XCTAssertEqual(intent.target.targetID, contact.contactPointID)
        XCTAssertEqual(intent.target.expectedRevision, contact.revision)
        XCTAssertEqual(intent.target.expectedSHA256, contact.contactPointSHA256)
        XCTAssertEqual(intent.kind, .email)
        XCTAssertEqual(try ServiceContactPointRow(contact).value(), contact)
        XCTAssertEqual(try SystemHandoffIntentRow(intent).value(), intent)
        XCTAssertFalse(OperationalContactPersistenceEnrollmentV1.handoffOutcomeIsPersistent)
    }

    func testV23P03C46A01CSVImportPreviewPurposeSeparationAndCancelRemainBounded() async throws {
        let exactValues = [
            "Team+West@Example.COM",
            "δοκιμή@παράδειγμα.δοκιμή",
            "+44 20 7946 0958 ext. 42"
        ]
        let rows = try exactValues.enumerated().map { index, value in
            try PartyContactCSVRowV1(
                rowIndex: index + 1,
                contactPointID: C46OperationalContactTestSupport.id(100 + index),
                partyID: C46OperationalContactTestSupport.id(110 + index),
                kind: index == 2 ? .phone : .email,
                label: index == 2 ? .office : .work,
                displayValue: value,
                preferred: index == 0,
                effectiveAt: C46OperationalContactTestSupport.date(100),
                revision: 1
            )
        }
        XCTAssertEqual(rows.map(\.displayValue), exactValues)
        XCTAssertEqual(PartyContactsCSVContractV1.schemaID, "PARTY_CONTACTS_V1")
        XCTAssertEqual(PartyContactsCSVContractV1.valuePrivacyClass, .restrictedContactValue)
        XCTAssertFalse(PartyContactsCSVContractV1.defaultExportEnabled)

        let source = try ImportSourceSetV1(
            workspaceID: C46OperationalContactTestSupport.workspace(120),
            files: [
                ImportSourceFileV1(
                    schemaID: PartyContactsCSVContractV1.schemaID,
                    schemaVersion: PartyContactsCSVContractV1.schemaVersion,
                    fileName: "party-contacts.csv",
                    orderIndex: 0,
                    byteCount: 512,
                    sha256: String(repeating: "a", count: 64)
                )
            ]
        )
        XCTAssertEqual(source.files.map(\.orderIndex), [0])
        XCTAssertFalse(OperationalContactPersistenceEnrollmentV1.importSourceBytesArePersistent)

        let route = OperationalContactHandoffRouteV1.email(contactPointID: rows[0].contactPointID)
        let routeData = try JSONEncoder().encode(route)
        XCTAssertEqual(try JSONDecoder().decode(OperationalContactHandoffRouteV1.self, from: routeData), route)
        let routeText = String(decoding: routeData, as: UTF8.self)
        for exactValue in exactValues {
            XCTAssertFalse(routeText.contains(exactValue))
        }

        let siteTarget = try SystemHandoffTargetReferenceV1(
            workspaceID: source.workspaceID,
            kind: .site,
            targetID: C46OperationalContactTestSupport.id(125),
            expectedRevision: 1,
            expectedSHA256: String(repeating: "b", count: 64)
        )
        let coordinate = SiteDirectionsCoordinateV1(
            latitudeMicrodegrees: 40_712_800,
            longitudeMicrodegrees: -74_006_000
        )
        let both = try SiteDirectionsTargetSnapshotV1(
            currentTarget: siteTarget,
            coordinate: coordinate,
            exactAddress: "11 Broadway, New York, NY"
        )
        XCTAssertEqual(
            try both.preferredDestination(),
            .geographicCoordinate(
                latitudeMicrodegrees: coordinate.latitudeMicrodegrees,
                longitudeMicrodegrees: coordinate.longitudeMicrodegrees
            )
        )
        let addressOnly = try SiteDirectionsTargetSnapshotV1(
            currentTarget: siteTarget,
            exactAddress: "11 Broadway, New York, NY"
        )
        XCTAssertEqual(try addressOnly.preferredDestination(), .exactAddress("11 Broadway, New York, NY"))
        let neither = try SiteDirectionsTargetSnapshotV1(currentTarget: siteTarget)
        XCTAssertThrowsError(try neither.preferredDestination())
        XCTAssertFalse(C46DirectionsLocationAuthorityBoundaryV1.derivesFromSolarLocation)

        let importSupport = try C46OperationalContactTestSupport.temporaryDirectory("party-import")
        defer { try? FileManager.default.removeItem(at: importSupport) }
        let session = try StoreGenerationFactory(applicationSupportURL: importSupport)
            .openOrBootstrapCurrent()
        let importParties = try [130, 132].map {
            try C46OperationalContactTestSupport.party(slot: $0, workspaceID: session.workspaceID)
        }
        for party in importParties {
            session.modelContext.insert(try ServicePartyRow(party))
            session.modelContext.insert(EntityMutationRevisionRow(
                identity: try WorkspaceEntityIdentityV1(kind: .serviceParty, id: party.partyID),
                revision: party.revision,
                externalProjectionSHA256: party.receiptSHA256
            ))
        }
        try session.modelContext.save()

        let contactIDs = [
            C46OperationalContactTestSupport.id(134),
            C46OperationalContactTestSupport.id(135),
        ]
        let instant = "2036-07-18T13:20:00.000Z"
        let csvLines = [
            PartyContactsImportPreviewV1.csvHeader.joined(separator: ","),
            [
                "1", contactIDs[0].uuidString.lowercased(),
                importParties[0].partyID.uuidString.lowercased(), "EMAIL", "WORK",
                "import.one@example.com", "TRUE", instant, "", "1",
            ].joined(separator: ","),
            [
                "2", contactIDs[1].uuidString.lowercased(),
                importParties[1].partyID.uuidString.lowercased(), "EMAIL", "OTHER",
                "δοκιμή@παράδειγμα.δοκιμή", "TRUE", instant, "", "1",
            ].joined(separator: ","),
        ]
        let csvData = Data((csvLines.joined(separator: "\n") + "\n").utf8)
        let importSource = try ImportSourceSetV1(
            workspaceID: session.workspaceID,
            files: [
                ImportSourceFileV1(
                    schemaID: PartyContactsCSVContractV1.schemaID,
                    schemaVersion: PartyContactsCSVContractV1.schemaVersion,
                    fileName: "party-contacts.csv",
                    orderIndex: 0,
                    byteCount: Int64(csvData.count),
                    sha256: KernelCanonicalHashV1.sha256(csvData)
                )
            ]
        )
        let writerInstanceID = C46OperationalContactTestSupport.id(136)
        let journal = try MutationJournalStoreV1(
            modelContext: session.modelContext,
            identity: session.workspaceIdentity,
            generationID: session.generationID
        )
        let current = try journal.currentRevision(writerInstanceID: writerInstanceID)
        let importMutationID = try C46OperationalContactTestSupport.mutation(137)
        let importedContactRevisions = try contactIDs.map {
            WorkspaceEntityRevisionV1(
                identity: try WorkspaceEntityIdentityV1(
                    kind: .serviceContactPoint,
                    id: $0
                ),
                revision: 0
            )
        }
        let expected = try WorkspaceExpectedRevisionV1(
            workspaceID: current.workspaceID,
            generationID: current.generationID,
            writerInstanceID: current.writerInstanceID,
            workspaceRevision: current.revision,
            entityRevisions: current.entityRevisions + importedContactRevisions
        )
        let writer = try WorkspaceWriterV1(
            identity: session.workspaceIdentity,
            generationID: session.generationID,
            initialRevision: current,
            clock: C46OperationalContactClock(value: C46OperationalContactTestSupport.date(138)),
            idSource: C46OperationalContactIDSource(value: writerInstanceID),
            fileAuthority: C46OperationalContactFileAuthority(),
            adapter: WorkspaceWriterAdapterV1(modelContext: session.modelContext),
            journalStore: journal
        )
        let query = OperationalContactRowQueryV1(
            modelContext: session.modelContext,
            workspaceID: session.workspaceID
        )
        let coordinator = OperationalContactCoordinatorV1(
            query: query,
            writer: writer,
            system: SystemHandoffAdapterV1(
                opener: C46SystemHandoffOpener(canPresent: true, accepts: true),
                clock: C46OperationalContactClock(value: C46OperationalContactTestSupport.date(139))
            ),
            clock: C46OperationalContactClock(value: C46OperationalContactTestSupport.date(139)),
            idSource: C46OperationalContactIDSource(value: C46OperationalContactTestSupport.id(139)),
            importQuery: query
        )

        XCTAssertTrue(
            try session.modelContext.fetch(FetchDescriptor<ServiceContactPointRow>()).isEmpty
        )
        XCTAssertNil(try journal.operationalContactReceipt(mutationID: importMutationID))
        let firstPreview = try await coordinator.previewPartyContacts(
            sourceSet: importSource,
            fileBytesByName: ["party-contacts.csv": csvData]
        )
        let secondPreview = try await coordinator.previewPartyContacts(
            sourceSet: importSource,
            fileBytesByName: ["party-contacts.csv": csvData]
        )
        XCTAssertEqual(firstPreview, secondPreview)
        XCTAssertEqual(firstPreview.rows.map(\.rowIndex), [1, 2])
        XCTAssertEqual(firstPreview.rows.map(\.displayValue), [
            "import.one@example.com", "δοκιμή@παράδειγμα.δοκιμή",
        ])
        XCTAssertEqual(try coordinator.cancelPartyContactsImport(firstPreview), .cancelledNoMutation)
        XCTAssertTrue(
            try session.modelContext.fetch(FetchDescriptor<ServiceContactPointRow>()).isEmpty
        )
        XCTAssertNil(try journal.operationalContactReceipt(mutationID: importMutationID))

        let importReceipt = try await coordinator.acceptPartyContactsImport(
            preview: secondPreview,
            expectedRevision: expected,
            mutationID: importMutationID
        )
        let imported = try session.modelContext.fetch(FetchDescriptor<ServiceContactPointRow>())
            .map { try $0.value() }
            .sorted { $0.contactPointID.uuidString < $1.contactPointID.uuidString }
        XCTAssertEqual(imported.map(\.contactPointID), contactIDs)
        XCTAssertEqual(imported.map(\.displayValue), [
            "import.one@example.com", "δοκιμή@παράδειγμα.δοκιμή",
        ])
        XCTAssertTrue(imported.allSatisfy {
            $0.provenance == .importedExternalEvidence
                && $0.importSourceSetSHA256 == importSource.sourceSetSHA256
        })
        XCTAssertEqual(importReceipt.affectedIdentities.count, 2)
        XCTAssertEqual(
            try session.modelContext.fetch(FetchDescriptor<MutationReceiptRow>())
                .filter { $0.commandKind == WorkspaceCommandKindV1.applyOperationalContact.rawValue }
                .count,
            1
        )
        XCTAssertEqual(try writer.currentRevision().revision, current.revision + 1)
        try journal.validateAll()
    }

    func testV23P03C46H01StaleMalformedDuplicateAndMarketingIdentityInputsFailClosed() throws {
        let zeroWorkspace = C46OperationalContactTestSupport.workspace(190)
        XCTAssertThrowsError(try ServiceContactPointV1(
            contactPointID: C46OperationalContactTestSupport.id(191),
            workspaceID: zeroWorkspace,
            party: C46OperationalContactTestSupport.party(slot: 192, workspaceID: zeroWorkspace),
            kind: .email,
            label: .work,
            displayValue: "zero@example.com",
            preferred: false,
            provenance: .manual,
            lifecycle: .effective,
            effectiveAt: C46OperationalContactTestSupport.date(190),
            revision: 0,
            mutationID: C46OperationalContactTestSupport.mutation(193)
        ))

        let malformed: [(SystemHandoffDestinationV1, SystemHandoffKindV1)] = [
            (.email("ops@example.com\r\nBcc: hidden@example.com"), .email),
            (.email("ops@example.com?subject=automatic"), .email),
            (.email("one@example.com,two@example.com"), .email),
            (.phone("+1 212 555 0199;ext=*42#"), .call),
            (.phone("+١ ٢١٢ ٥٥٥ ٠١٩٩"), .text),
            (.phone("+12125550199,,42"), .call)
        ]
        for (destination, kind) in malformed {
            XCTAssertThrowsError(try destination.validate(for: kind))
        }

        let first = try C46OperationalContactTestSupport.contact(
            slot: 240,
            kind: .email,
            label: .work,
            displayValue: "same@example.com"
        )
        let second = try C46OperationalContactTestSupport.contact(
            slot: 250,
            kind: .email,
            label: .work,
            displayValue: "same@example.com"
        )
        XCTAssertEqual(first.displayValue, second.displayValue)
        XCTAssertNotEqual(first.party.partyID, second.party.partyID)
        XCTAssertNotEqual(first.contactPointID, second.contactPointID)
        XCTAssertFalse(PartyContactsCSVContractV1.defaultExportEnabled)

        let intent = try C46OperationalContactTestSupport.intent(slot: 260, kind: .email, contact: first)
        let staleTarget = try SystemHandoffTargetReferenceV1(
            workspaceID: first.workspaceID,
            kind: .serviceContactPoint,
            targetID: first.contactPointID,
            expectedRevision: first.revision + 1,
            expectedSHA256: String(repeating: "c", count: 64)
        )
        XCTAssertThrowsError(
            try SystemHandoffRequestV1(
                intent: intent,
                currentTarget: staleTarget,
                destination: .email(first.displayValue)
            )
        )

        let overflowWorkspace = C46OperationalContactTestSupport.workspace(280)
        let overflowParty = try C46OperationalContactTestSupport.party(
            slot: 281,
            workspaceID: overflowWorkspace
        )
        let overflowMutationID = try C46OperationalContactTestSupport.mutation(282)
        let overflowContactID = C46OperationalContactTestSupport.id(283)
        let overflowPredecessor = try ServiceContactPointV1(
            contactPointID: overflowContactID,
            workspaceID: overflowWorkspace,
            party: overflowParty,
            kind: .email,
            label: .work,
            displayValue: "overflow@example.com",
            preferred: true,
            provenance: .manual,
            lifecycle: .effective,
            effectiveAt: C46OperationalContactTestSupport.date(280),
            revision: .max,
            supersedes: ServiceContactRevisionReferenceV1(
                contactPointID: overflowContactID,
                revision: UInt64.max - 1,
                contactPointSHA256: String(repeating: "e", count: 64)
            ),
            mutationID: overflowMutationID
        )
        let overflowExpected = try WorkspaceExpectedRevisionV1(
            workspaceID: overflowWorkspace,
            generationID: C46OperationalContactTestSupport.id(284),
            writerInstanceID: C46OperationalContactTestSupport.id(285),
            workspaceRevision: 1,
            entityRevisions: [
                WorkspaceEntityRevisionV1(
                    identity: try WorkspaceEntityIdentityV1(
                        kind: .serviceContactPoint,
                        id: overflowContactID
                    ),
                    revision: .max
                ),
                WorkspaceEntityRevisionV1(
                    identity: try WorkspaceEntityIdentityV1(
                        kind: .serviceParty,
                        id: overflowParty.partyID
                    ),
                    revision: overflowParty.revision
                )
            ]
        )
        XCTAssertThrowsError(try OperationalContactMutationV1(
            workspaceID: overflowWorkspace,
            mutationID: overflowMutationID,
            expectedRevision: overflowExpected,
            predecessors: [overflowPredecessor],
            successors: [overflowPredecessor],
            preferredScopes: [
                ServiceContactPreferredScopeV1(
                    partyID: overflowParty.partyID,
                    kind: .email,
                    activeContactPointIDs: [overflowContactID],
                    preferredContactPointID: overflowContactID
                )
            ]
        ))
        XCTAssertThrowsError(try OperationalContactMutationV1(
            workspaceID: overflowWorkspace,
            mutationID: overflowMutationID,
            expectedRevision: overflowExpected,
            predecessors: [overflowPredecessor, overflowPredecessor],
            successors: [overflowPredecessor, first],
            preferredScopes: []
        )) {
            XCTAssertEqual($0 as? OperationalContactFailureV1, .limitExceeded)
        }

        let mismatchedOuterMutationID = try C46OperationalContactTestSupport.mutation(286)
        let mismatchExpected = try WorkspaceExpectedRevisionV1(
            workspaceID: first.workspaceID,
            generationID: C46OperationalContactTestSupport.id(287),
            writerInstanceID: C46OperationalContactTestSupport.id(288),
            workspaceRevision: 0,
            entityRevisions: [
                WorkspaceEntityRevisionV1(
                    identity: try WorkspaceEntityIdentityV1(
                        kind: .serviceContactPoint,
                        id: first.contactPointID
                    ),
                    revision: 0
                ),
                WorkspaceEntityRevisionV1(
                    identity: try WorkspaceEntityIdentityV1(
                        kind: .serviceParty,
                        id: first.party.partyID
                    ),
                    revision: first.party.revision
                )
            ]
        )
        XCTAssertThrowsError(try OperationalContactMutationV1(
            workspaceID: first.workspaceID,
            mutationID: mismatchedOuterMutationID,
            expectedRevision: mismatchExpected,
            successors: [first],
            preferredScopes: [
                ServiceContactPreferredScopeV1(
                    partyID: first.party.partyID,
                    kind: .email,
                    activeContactPointIDs: [first.contactPointID],
                    preferredContactPointID: nil
                )
            ]
        )) {
            XCTAssertEqual($0 as? OperationalContactFailureV1, .invalidValue)
        }

        let multiKindWorkspace = C46OperationalContactTestSupport.workspace(291)
        let multiKindParty = try C46OperationalContactTestSupport.party(
            slot: 292,
            workspaceID: multiKindWorkspace
        )
        let multiKindMutationID = try C46OperationalContactTestSupport.mutation(293)
        let multiKindEmail = try ServiceContactPointV1(
            contactPointID: C46OperationalContactTestSupport.id(294),
            workspaceID: multiKindWorkspace,
            party: multiKindParty,
            kind: .email,
            label: .work,
            displayValue: "preferred@example.com",
            preferred: true,
            provenance: .manual,
            lifecycle: .effective,
            effectiveAt: C46OperationalContactTestSupport.date(294),
            revision: 1,
            mutationID: multiKindMutationID
        )
        let multiKindPhone = try ServiceContactPointV1(
            contactPointID: C46OperationalContactTestSupport.id(295),
            workspaceID: multiKindWorkspace,
            party: multiKindParty,
            kind: .phone,
            label: .mobile,
            displayValue: "+49 30 901820 ext. 7",
            preferred: true,
            provenance: .manual,
            lifecycle: .effective,
            effectiveAt: C46OperationalContactTestSupport.date(295),
            revision: 1,
            mutationID: multiKindMutationID
        )
        let multiKindExpected = try WorkspaceExpectedRevisionV1(
            workspaceID: multiKindWorkspace,
            generationID: C46OperationalContactTestSupport.id(296),
            writerInstanceID: C46OperationalContactTestSupport.id(297),
            workspaceRevision: 0,
            entityRevisions: [
                WorkspaceEntityRevisionV1(
                    identity: try WorkspaceEntityIdentityV1(kind: .serviceParty, id: multiKindParty.partyID),
                    revision: multiKindParty.revision
                ),
                WorkspaceEntityRevisionV1(
                    identity: try WorkspaceEntityIdentityV1(kind: .serviceContactPoint, id: multiKindEmail.contactPointID),
                    revision: 0
                ),
                WorkspaceEntityRevisionV1(
                    identity: try WorkspaceEntityIdentityV1(kind: .serviceContactPoint, id: multiKindPhone.contactPointID),
                    revision: 0
                )
            ]
        )
        let multiKindMutation = try OperationalContactMutationV1(
            workspaceID: multiKindWorkspace,
            mutationID: multiKindMutationID,
            expectedRevision: multiKindExpected,
            successors: [multiKindEmail, multiKindPhone],
            preferredScopes: [
                ServiceContactPreferredScopeV1(
                    partyID: multiKindParty.partyID,
                    kind: .email,
                    activeContactPointIDs: [multiKindEmail.contactPointID],
                    preferredContactPointID: multiKindEmail.contactPointID
                ),
                ServiceContactPreferredScopeV1(
                    partyID: multiKindParty.partyID,
                    kind: .phone,
                    activeContactPointIDs: [multiKindPhone.contactPointID],
                    preferredContactPointID: multiKindPhone.contactPointID
                )
            ]
        )
        let multiKindPartyIdentity = try WorkspaceEntityIdentityV1(
            kind: .serviceParty,
            id: multiKindParty.partyID
        )
        XCTAssertEqual(
            try multiKindMutation.concurrencyIdentities.filter { $0.kind == .serviceParty },
            [multiKindPartyIdentity]
        )
        let communicationSource = try ContactSourceV1(
            sourceID: C46OperationalContactTestSupport.id(290),
            revision: 1,
            kind: .controlledBackendAffirmativeEnrollment,
            releaseID: "source.c46.no-bridge.v1",
            ownerReadableDescription: "Operational support source remains nonmarketing",
            effectiveAt: C46OperationalContactTestSupport.date(290)
        )
        XCTAssertTrue(communicationSource.prohibitsOperationalContactImport)
        XCTAssertTrue(communicationSource.requiresIndependentAffirmativeEnrollment)
        XCTAssertFalse(C46SystemHandoffRuntimeBoundaryV1.usesContactsPermission)
        XCTAssertFalse(C46SystemHandoffRuntimeBoundaryV1.usesCurrentLocationPermission)
        XCTAssertFalse(C46DirectionsLocationAuthorityBoundaryV1.requestsCurrentLocationPermission)
        let historic = try intent.reboundForHistoricRestore(
            to: C46OperationalContactTestSupport.workspace(270),
            mutationID: C46OperationalContactTestSupport.mutation(271)
        )
        XCTAssertEqual(historic.disposition, .historicReferenceOnly)
        XCTAssertThrowsError(
            try SystemHandoffRequestV1(
                intent: historic,
                currentTarget: historic.target,
                destination: .email(first.displayValue)
            )
        )
    }

    func testV23P03C46I01InterruptedContactWriteAndHandoffRecoverIdempotently() async throws {
        let contact = try C46OperationalContactTestSupport.contact(
            slot: 300,
            kind: .email,
            label: .work,
            displayValue: "Ops+Recovery@Example.COM",
            preferred: true
        )
        let intent = try C46OperationalContactTestSupport.intent(slot: 310, kind: .email, contact: contact)
        let request = try SystemHandoffRequestV1(
            intent: intent,
            currentTarget: intent.target,
            destination: .email(contact.displayValue)
        )
        let url = try SystemHandoffURLBuilderV1.url(for: request)
        XCTAssertEqual(url.scheme, "mailto")
        XCTAssertNil(URLComponents(url: url, resolvingAgainstBaseURL: false)?.query)
        XCTAssertEqual(url.path.removingPercentEncoding, contact.displayValue)

        let rejectingOpener = C46SystemHandoffOpener(canPresent: true, accepts: false)
        let adapter = SystemHandoffAdapterV1(
            opener: rejectingOpener,
            clock: C46OperationalContactClock(value: C46OperationalContactTestSupport.date(311))
        )
        let rejected = await adapter.handOff(request)
        XCTAssertEqual(rejected.disposition, .systemRejected)
        XCTAssertEqual(rejectingOpener.openedURLs, [url])

        let unavailableOpener = C46SystemHandoffOpener(canPresent: false, accepts: true)
        let unavailable = await SystemHandoffAdapterV1(
            opener: unavailableOpener,
            clock: C46OperationalContactClock(value: C46OperationalContactTestSupport.date(312))
        ).handOff(request)
        XCTAssertEqual(unavailable.disposition, .systemUnavailable)
        XCTAssertTrue(unavailableOpener.openedURLs.isEmpty)
        XCTAssertFalse(OperationalContactPersistenceEnrollmentV1.handoffOutcomeIsPersistent)

        let unicodeContact = try C46OperationalContactTestSupport.contact(
            slot: 320,
            kind: .email,
            label: .work,
            displayValue: "δοκιμή@παράδειγμα.δοκιμή",
            preferred: true
        )
        let unicodeIntent = try C46OperationalContactTestSupport.intent(
            slot: 321,
            kind: .email,
            contact: unicodeContact
        )
        let unicodeRequest = try SystemHandoffRequestV1(
            intent: unicodeIntent,
            currentTarget: unicodeIntent.target,
            destination: .email(unicodeContact.displayValue)
        )
        let unicodeURL = try SystemHandoffURLBuilderV1.url(for: unicodeRequest)
        XCTAssertEqual(unicodeURL.scheme, "mailto")
        XCTAssertEqual(unicodeURL.path.removingPercentEncoding, unicodeContact.displayValue)
        XCTAssertNil(unicodeURL.query)
        XCTAssertNil(unicodeURL.fragment)
        XCTAssertFalse(unicodeURL.absoluteString.contains("?"))
        XCTAssertFalse(unicodeURL.absoluteString.contains("#"))
        let unicodeOpener = C46SystemHandoffOpener(canPresent: true, accepts: true)
        let unicodeResult = await SystemHandoffAdapterV1(
            opener: unicodeOpener,
            clock: C46OperationalContactClock(value: C46OperationalContactTestSupport.date(322))
        ).handOff(unicodeRequest)
        XCTAssertEqual(unicodeResult.disposition, .handedOffToSystem)
        XCTAssertEqual(unicodeOpener.openedURLs, [unicodeURL])

        let applicationSupport = try C46OperationalContactTestSupport.temporaryDirectory("writer-recovery")
        defer { try? FileManager.default.removeItem(at: applicationSupport) }
        let session = try StoreGenerationFactory(applicationSupportURL: applicationSupport)
            .openOrBootstrapCurrent()
        let durableParty = try C46OperationalContactTestSupport.party(
            slot: 330,
            workspaceID: session.workspaceID
        )
        session.modelContext.insert(try ServicePartyRow(durableParty))
        session.modelContext.insert(EntityMutationRevisionRow(
            identity: try WorkspaceEntityIdentityV1(kind: .serviceParty, id: durableParty.partyID),
            revision: durableParty.revision
        ))
        try session.modelContext.save()

        let writerInstanceID = C46OperationalContactTestSupport.id(331)
        let failure = MutationJournalFailureInjectionV1(failOnceAt: .afterEffectBeforeReceipt)
        let failingJournal = try MutationJournalStoreV1(
            modelContext: session.modelContext,
            identity: session.workspaceIdentity,
            generationID: session.generationID,
            failureInjection: failure
        )
        let initial = try failingJournal.currentRevision(writerInstanceID: writerInstanceID)
        let durableMutationID = try C46OperationalContactTestSupport.mutation(332)
        let durableContact = try ServiceContactPointV1(
            contactPointID: C46OperationalContactTestSupport.id(333),
            workspaceID: session.workspaceID,
            party: durableParty,
            kind: .phone,
            label: .mobile,
            displayValue: "+1 212 555 0199 ext. 42",
            preferred: true,
            provenance: .manual,
            lifecycle: .effective,
            effectiveAt: C46OperationalContactTestSupport.date(333),
            revision: 1,
            mutationID: durableMutationID
        )
        let durableIntent = try C46OperationalContactTestSupport.intent(
            slot: 334,
            kind: .call,
            contact: durableContact
        )
        let expected = try WorkspaceExpectedRevisionV1(
            workspaceID: initial.workspaceID,
            generationID: initial.generationID,
            writerInstanceID: initial.writerInstanceID,
            workspaceRevision: initial.revision,
            entityRevisions: initial.entityRevisions + [
                WorkspaceEntityRevisionV1(
                    identity: try WorkspaceEntityIdentityV1(
                        kind: .serviceContactPoint,
                        id: durableContact.contactPointID
                    ),
                    revision: 0
                ),
                WorkspaceEntityRevisionV1(
                    identity: try WorkspaceEntityIdentityV1(
                        kind: .systemHandoffIntent,
                        id: durableIntent.intentID
                    ),
                    revision: 0
                )
            ]
        )
        let durableMutation = try OperationalContactMutationV1(
            workspaceID: session.workspaceID,
            mutationID: durableMutationID,
            expectedRevision: expected,
            successors: [durableContact],
            preferredScopes: [
                ServiceContactPreferredScopeV1(
                    partyID: durableParty.partyID,
                    kind: .phone,
                    activeContactPointIDs: [durableContact.contactPointID],
                    preferredContactPointID: durableContact.contactPointID
                )
            ],
            handoffIntents: [durableIntent]
        )
        func writer(_ journal: MutationJournalStoreV1) throws -> WorkspaceWriterV1 {
            try WorkspaceWriterV1(
                identity: session.workspaceIdentity,
                generationID: session.generationID,
                initialRevision: journal.currentRevision(writerInstanceID: writerInstanceID),
                clock: C46OperationalContactClock(value: C46OperationalContactTestSupport.date(335)),
                idSource: C46OperationalContactIDSource(value: writerInstanceID),
                fileAuthority: C46OperationalContactFileAuthority(),
                adapter: WorkspaceWriterAdapterV1(modelContext: session.modelContext),
                journalStore: journal
            )
        }
        do {
            _ = try await writer(failingJournal).commitOperationalContact(durableMutation)
            XCTFail("Effect-before-receipt interruption must fail the first attempt")
        } catch {
            XCTAssertEqual(
                error as? MutationJournalFailureV1,
                .injected(.afterEffectBeforeReceipt)
            )
        }

        let recoveryJournal = try MutationJournalStoreV1(
            modelContext: session.modelContext,
            identity: session.workspaceIdentity,
            generationID: session.generationID
        )
        let recovered = try await writer(recoveryJournal).commitOperationalContact(durableMutation)
        let replayed = try await writer(recoveryJournal).commitOperationalContact(durableMutation)
        XCTAssertEqual(replayed, recovered)
        XCTAssertEqual(recovered.mutationSHA256, try OperationalContactCanonicalCodecV1.sha256(durableMutation))
        let query = OperationalContactRowQueryV1(
            modelContext: session.modelContext,
            workspaceID: session.workspaceID
        )
        let queriedContact = try await query.currentServiceContactPoint(
            workspaceID: session.workspaceID,
            contactPointID: durableContact.contactPointID
        )
        let queriedIntent = try await query.handoffIntent(
            workspaceID: session.workspaceID,
            intentID: durableIntent.intentID
        )
        XCTAssertEqual(queriedContact, durableContact)
        XCTAssertEqual(queriedIntent, durableIntent)
        XCTAssertEqual(try session.modelContext.fetch(FetchDescriptor<ServiceContactPointRow>()).count, 1)
        XCTAssertEqual(try session.modelContext.fetch(FetchDescriptor<SystemHandoffIntentRow>()).count, 1)
    }

    func testV23P03C46R01BackupRestoreCloneForkDeleteEraseExportSearchAndReplayRemainExact() async throws {
        let root = try C46OperationalContactTestSupport.temporaryDirectory("lifecycle")
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceSupport = root.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceSupport, withIntermediateDirectories: true)
        let source = try StoreGenerationFactory(applicationSupportURL: sourceSupport)
            .openOrBootstrapCurrent()
        let party = try C46OperationalContactTestSupport.party(slot: 400, workspaceID: source.workspaceID)
        let unrelatedSiteID = C46OperationalContactTestSupport.id(408)
        let unrelatedAssetID = C46OperationalContactTestSupport.id(409)
        source.modelContext.insert(try ServicePartyRow(party))
        source.modelContext.insert(Site(
            id: unrelatedSiteID,
            label: "C46 unrelated deletion site",
            address: "12 Broadway, New York, NY",
            timeZoneID: "America/New_York",
            createdAt: C46OperationalContactTestSupport.date(408)
        ))
        source.modelContext.insert(Asset(
            id: unrelatedAssetID,
            siteID: unrelatedSiteID,
            packID: "c46.unrelated.asset",
            packSchemaVersion: 1,
            packContentVersion: 1,
            label: "C46 unrelated asset",
            createdAt: C46OperationalContactTestSupport.date(409)
        ))
        source.modelContext.insert(EntityMutationRevisionRow(
            identity: try WorkspaceEntityIdentityV1(kind: .serviceParty, id: party.partyID),
            revision: party.revision
        ))
        try source.modelContext.save()

        let writerInstanceID = C46OperationalContactTestSupport.id(401)
        let journal = try MutationJournalStoreV1(
            modelContext: source.modelContext,
            identity: source.workspaceIdentity,
            generationID: source.generationID
        )
        let current = try journal.currentRevision(writerInstanceID: writerInstanceID)
        let mutationID = try C46OperationalContactTestSupport.mutation(402)
        let contact = try ServiceContactPointV1(
            contactPointID: C46OperationalContactTestSupport.id(403),
            workspaceID: source.workspaceID,
            party: party,
            kind: .email,
            label: .office,
            displayValue: "Lifecycle+Private@Example.COM",
            preferred: true,
            provenance: .manual,
            lifecycle: .effective,
            effectiveAt: C46OperationalContactTestSupport.date(403),
            revision: 1,
            mutationID: mutationID
        )
        let intent = try C46OperationalContactTestSupport.intent(slot: 404, kind: .email, contact: contact)
        let expected = try WorkspaceExpectedRevisionV1(
            workspaceID: current.workspaceID,
            generationID: current.generationID,
            writerInstanceID: current.writerInstanceID,
            workspaceRevision: current.revision,
            entityRevisions: current.entityRevisions + [
                WorkspaceEntityRevisionV1(
                    identity: try WorkspaceEntityIdentityV1(
                        kind: .serviceContactPoint,
                        id: contact.contactPointID
                    ),
                    revision: 0
                ),
                WorkspaceEntityRevisionV1(
                    identity: try WorkspaceEntityIdentityV1(
                        kind: .systemHandoffIntent,
                        id: intent.intentID
                    ),
                    revision: 0
                )
            ]
        )
        let mutation = try OperationalContactMutationV1(
            workspaceID: source.workspaceID,
            mutationID: mutationID,
            expectedRevision: expected,
            successors: [contact],
            preferredScopes: [
                ServiceContactPreferredScopeV1(
                    partyID: party.partyID,
                    kind: .email,
                    activeContactPointIDs: [contact.contactPointID],
                    preferredContactPointID: contact.contactPointID
                )
            ],
            handoffIntents: [intent]
        )
        let writer = try WorkspaceWriterV1(
            identity: source.workspaceIdentity,
            generationID: source.generationID,
            initialRevision: current,
            clock: C46OperationalContactClock(value: C46OperationalContactTestSupport.date(405)),
            idSource: C46OperationalContactIDSource(value: writerInstanceID),
            fileAuthority: C46OperationalContactFileAuthority(),
            adapter: WorkspaceWriterAdapterV1(modelContext: source.modelContext),
            journalStore: journal
        )
        let receipt = try await writer.commitOperationalContact(mutation)
        let receiptReplay = try await writer.commitOperationalContact(mutation)
        XCTAssertEqual(receiptReplay, receipt)
        let successorMutationID = try C46OperationalContactTestSupport.mutation(410)
        let successor = try ServiceContactPointV1(
            contactPointID: contact.contactPointID,
            workspaceID: contact.workspaceID,
            party: contact.party,
            kind: contact.kind,
            label: .work,
            displayValue: "Lifecycle+Private@Example.COM",
            preferred: true,
            provenance: .manual,
            lifecycle: .effective,
            effectiveAt: contact.effectiveAt,
            revision: contact.revision + 1,
            supersedes: contact.revisionReference,
            mutationID: successorMutationID
        )
        let successorMutation = try OperationalContactMutationV1(
            workspaceID: source.workspaceID,
            mutationID: successorMutationID,
            expectedRevision: WorkspaceExpectedRevisionV1(snapshot: try writer.currentRevision()),
            predecessors: [contact],
            successors: [successor],
            preferredScopes: [
                ServiceContactPreferredScopeV1(
                    partyID: party.partyID,
                    kind: .email,
                    activeContactPointIDs: [successor.contactPointID],
                    preferredContactPointID: successor.contactPointID
                )
            ]
        )
        let successorReceipt = try await writer.commitOperationalContact(successorMutation)
        let successorReceiptReplay = try await writer.commitOperationalContact(successorMutation)
        XCTAssertEqual(successorReceiptReplay, successorReceipt)
        try journal.validateAll()

        let sourceOperationalRows = try source.modelContext.fetch(
            FetchDescriptor<MutationReceiptRow>()
        )
        .filter { $0.commandKind == WorkspaceCommandKindV1.applyOperationalContact.rawValue }
        .sorted { $0.localSequence < $1.localSequence }
        XCTAssertEqual(sourceOperationalRows.count, 2)
        let sourceCreateEnvelope = try MutationEnvelopeV1.decodeCanonical(
            from: sourceOperationalRows[0].envelopeData
        )
        let sourceSuccessorEnvelope = try MutationEnvelopeV1.decodeCanonical(
            from: sourceOperationalRows[1].envelopeData
        )
        guard case let .applyOperationalContact(sourceCreateMutation) =
                sourceCreateEnvelope.command,
              case let .applyOperationalContact(sourceSuccessorMutation) =
                sourceSuccessorEnvelope.command else {
            XCTFail("Expected both source C46 receipts to carry operational contact mutations")
            return
        }
        XCTAssertEqual(sourceCreateMutation.mutationID, mutationID)
        XCTAssertEqual(sourceCreateMutation.predecessors, [])
        XCTAssertEqual(sourceCreateMutation.successors, [contact])
        XCTAssertEqual(sourceCreateMutation.handoffIntents, [intent])
        XCTAssertEqual(sourceSuccessorMutation.mutationID, successorMutationID)
        XCTAssertEqual(sourceSuccessorMutation.predecessors, [contact])
        XCTAssertEqual(sourceSuccessorMutation.successors, [successor])
        let sourceOperationalMutations = [sourceCreateMutation, sourceSuccessorMutation]

        let sourceContactRow = try XCTUnwrap(
            source.modelContext.fetch(FetchDescriptor<ServiceContactPointRow>()).first
        )
        let sourceIntentRow = try XCTUnwrap(
            source.modelContext.fetch(FetchDescriptor<SystemHandoffIntentRow>()).first
        )
        let sourceContactBytes = sourceContactRow.canonicalData
        let sourceIntentBytes = sourceIntentRow.canonicalData

        let searchRevision = try SearchSourceRevisionV1(
            workspaceID: source.workspaceID.rawValue,
            generationID: source.generationID,
            commitRevision: try writer.currentRevision().revision
        )
        let searchSource = try SwiftDataSearchCanonicalProjectionSourceV1(
            modelContext: source.modelContext,
            workspaceID: source.workspaceID.rawValue,
            generationID: source.generationID,
            revisionProvider: { searchRevision },
            includeAccountability: true
        )
        let searchStore = try LocalSearchIndexStoreV1(
            applicationSupportURL: root.appendingPathComponent("search", isDirectory: true)
        )
        let rebuild = try SearchIndexRebuildCoordinatorV1(
            store: searchStore,
            source: searchSource,
            registry: searchSource.registry,
            makeOperationID: { C46OperationalContactTestSupport.id(406) }
        )
        _ = try await rebuild.rebuildIfNeeded()
        let search = SearchCoordinatorV1(index: searchStore)
        let rawPlan = try search.makePlan(
            query: successor.displayValue,
            scope: .parties,
            sourceRevision: searchRevision.commitRevision
        )
        let rawResponse = try await search.search(
            rawPlan,
            source: searchRevision,
            registry: searchSource.registry
        )
        XCTAssertTrue(rawResponse.results.isEmpty)
        XCTAssertFalse(OperationalContactProjectionPolicyV1.reportProjectionCarriesContactValue)
        XCTAssertFalse(OperationalContactProjectionPolicyV1.includedInDiagnostics)
        XCTAssertFalse(OperationalContactProjectionPolicyV1.includedInMeasurement)
        XCTAssertFalse(OperationalContactProjectionPolicyV1.includedInMarketing)

        let exportRoot = root.appendingPathComponent("export", isDirectory: true)
        try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: true)
        let exporter = BackupExportService(
            modelContext: source.modelContext,
            generationRootURL: source.generationRootURL,
            now: { C46OperationalContactTestSupport.date(407) }
        )
        let preview = try exporter.prepare()
        let package = try exporter.export(previewID: preview.id, to: exportRoot)

        for (index, mode) in [BackupRestoreMode.emptyInstall, .clone, .fork].enumerated() {
            let support = root.appendingPathComponent("restore-\(index)", isDirectory: true)
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            let currentSession = try StoreGenerationFactory(applicationSupportURL: support)
                .openOrBootstrapCurrent()
            let validated = try BackupImportService(
                generationRootURL: currentSession.generationRootURL,
                makeUUID: { C46OperationalContactTestSupport.id(420 + index) },
                scopedAccess: .alreadyAuthorized
            ).stageAndValidate(selectedPackageURL: package)
            let packageValues = try validated.records.validateC46OperationalContacts()
            XCTAssertEqual(packageValues.contacts, [successor])
            XCTAssertEqual(packageValues.intents, [intent])
            let restored = try await BackupRestoreService(
                applicationSupportURL: support,
                storagePreflight: StoragePreflightService(capacityProvider: { _ in .max })
            ).restore(
                validatedPackage: validated,
                currentModelContext: currentSession.modelContext,
                currentGenerationID: currentSession.generationID,
                currentGenerationRootURL: currentSession.generationRootURL,
                mode: mode
            )
            let restoredContactRow = try XCTUnwrap(
                restored.modelContext.fetch(FetchDescriptor<ServiceContactPointRow>()).first
            )
            let restoredIntentRow = try XCTUnwrap(
                restored.modelContext.fetch(FetchDescriptor<SystemHandoffIntentRow>()).first
            )
            let restoredContact = try restoredContactRow.value()
            let restoredIntent = try restoredIntentRow.value()
            let restoredQuery = OperationalContactRowQueryV1(
                modelContext: restored.modelContext,
                workspaceID: restored.workspaceID
            )
            let queriedRestoredContact = try await restoredQuery.currentServiceContactPoint(
                workspaceID: restored.workspaceID,
                contactPointID: restoredContact.contactPointID
            )
            XCTAssertEqual(queriedRestoredContact, restoredContact)
            if mode == .emptyInstall {
                XCTAssertEqual(restoredContactRow.canonicalData, sourceContactBytes)
                XCTAssertEqual(restoredIntentRow.canonicalData, sourceIntentBytes)
                XCTAssertEqual(restoredContact, successor)
                XCTAssertEqual(restoredIntent, intent)
            } else {
                XCTAssertEqual(restoredContact.workspaceID, restored.workspaceID)
                XCTAssertEqual(restoredContact.party.workspaceID, restored.workspaceID)
                XCTAssertEqual(restoredContact.displayValue, successor.displayValue)
                XCTAssertNotEqual(restoredContact.contactPointSHA256, successor.contactPointSHA256)
                XCTAssertEqual(restoredIntent.workspaceID, restored.workspaceID)
                XCTAssertEqual(restoredIntent.disposition, .historicReferenceOnly)
                XCTAssertEqual(restoredIntent.target, intent.target)
                let historicResolution = await restoredQuery.resolveForHandoff(restoredIntent)
                XCTAssertEqual(historicResolution, .targetInvalid)
            }
            let restoredJournal = try MutationJournalStoreV1(
                modelContext: restored.modelContext,
                identity: restored.workspaceIdentity,
                generationID: restored.generationID,
                allowStateBootstrap: false
            )
            try restoredJournal.validateAll()
        }

        let distinctTargetSupport = root.appendingPathComponent(
            "replace-distinct-target",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: distinctTargetSupport,
            withIntermediateDirectories: true
        )
        let distinctTarget = try StoreGenerationFactory(
            applicationSupportURL: distinctTargetSupport
        ).openOrBootstrapCurrent()
        let distinctTargetWorkspaceID = distinctTarget.workspaceID
        XCTAssertNotEqual(distinctTargetWorkspaceID, source.workspaceID)

        let targetOriginalParty = try C46OperationalContactTestSupport.party(
            slot: 442,
            workspaceID: distinctTargetWorkspaceID
        )
        distinctTarget.modelContext.insert(try ServicePartyRow(targetOriginalParty))
        distinctTarget.modelContext.insert(EntityMutationRevisionRow(
            identity: try WorkspaceEntityIdentityV1(
                kind: .serviceParty,
                id: targetOriginalParty.partyID
            ),
            revision: targetOriginalParty.revision,
            externalProjectionSHA256: targetOriginalParty.receiptSHA256
        ))
        try distinctTarget.modelContext.save()
        let targetOriginalWriterInstanceID = C46OperationalContactTestSupport.id(443)
        let targetOriginalJournal = try MutationJournalStoreV1(
            modelContext: distinctTarget.modelContext,
            identity: distinctTarget.workspaceIdentity,
            generationID: distinctTarget.generationID
        )
        let targetOriginalRevision = try targetOriginalJournal.currentRevision(
            writerInstanceID: targetOriginalWriterInstanceID
        )
        let targetOriginalMutationID = try C46OperationalContactTestSupport.mutation(444)
        let targetOriginalContact = try ServiceContactPointV1(
            contactPointID: C46OperationalContactTestSupport.id(445),
            workspaceID: distinctTargetWorkspaceID,
            party: targetOriginalParty,
            kind: .email,
            label: .work,
            displayValue: "target-a-original@example.com",
            preferred: true,
            provenance: .manual,
            lifecycle: .effective,
            effectiveAt: C46OperationalContactTestSupport.date(445),
            revision: 1,
            mutationID: targetOriginalMutationID
        )
        let targetOriginalExpected = try WorkspaceExpectedRevisionV1(
            workspaceID: targetOriginalRevision.workspaceID,
            generationID: targetOriginalRevision.generationID,
            writerInstanceID: targetOriginalRevision.writerInstanceID,
            workspaceRevision: targetOriginalRevision.revision,
            entityRevisions: targetOriginalRevision.entityRevisions + [
                WorkspaceEntityRevisionV1(
                    identity: try WorkspaceEntityIdentityV1(
                        kind: .serviceContactPoint,
                        id: targetOriginalContact.contactPointID
                    ),
                    revision: 0
                )
            ]
        )
        let targetOriginalMutation = try OperationalContactMutationV1(
            workspaceID: distinctTargetWorkspaceID,
            mutationID: targetOriginalMutationID,
            expectedRevision: targetOriginalExpected,
            successors: [targetOriginalContact],
            preferredScopes: [
                ServiceContactPreferredScopeV1(
                    partyID: targetOriginalParty.partyID,
                    kind: .email,
                    activeContactPointIDs: [targetOriginalContact.contactPointID],
                    preferredContactPointID: targetOriginalContact.contactPointID
                )
            ]
        )
        let targetOriginalWriter = try WorkspaceWriterV1(
            identity: distinctTarget.workspaceIdentity,
            generationID: distinctTarget.generationID,
            initialRevision: targetOriginalRevision,
            clock: C46OperationalContactClock(value: C46OperationalContactTestSupport.date(446)),
            idSource: C46OperationalContactIDSource(value: targetOriginalWriterInstanceID),
            fileAuthority: C46OperationalContactFileAuthority(),
            adapter: WorkspaceWriterAdapterV1(modelContext: distinctTarget.modelContext),
            journalStore: targetOriginalJournal
        )
        let targetOriginalReceipt = try await targetOriginalWriter.commitOperationalContact(
            targetOriginalMutation
        )
        XCTAssertEqual(
            targetOriginalReceipt.mutationReceipt.identity.workspaceID,
            distinctTargetWorkspaceID
        )
        try targetOriginalJournal.validateAll()
        let targetOriginalMutationRow = try XCTUnwrap(
            distinctTarget.modelContext.fetch(FetchDescriptor<MutationReceiptRow>()).first {
                $0.mutationID == targetOriginalMutationID.rawValue
            }
        )
        let targetOriginalEnvelopeBytes = targetOriginalMutationRow.envelopeData
        let targetOriginalReceiptBytes = targetOriginalMutationRow.receiptData

        let distinctValidated = try BackupImportService(
            generationRootURL: distinctTarget.generationRootURL,
            makeUUID: { C46OperationalContactTestSupport.id(440) },
            scopedAccess: .alreadyAuthorized
        ).stageAndValidate(selectedPackageURL: package)
        let distinctReplaced = try await BackupRestoreService(
            applicationSupportURL: distinctTargetSupport,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in .max })
        ).restore(
            validatedPackage: distinctValidated,
            currentModelContext: distinctTarget.modelContext,
            currentGenerationID: distinctTarget.generationID,
            currentGenerationRootURL: distinctTarget.generationRootURL,
            mode: .replaceExisting
        )
        XCTAssertEqual(distinctReplaced.workspaceID, distinctTargetWorkspaceID)
        let distinctContactRow = try XCTUnwrap(
            distinctReplaced.modelContext.fetch(FetchDescriptor<ServiceContactPointRow>()).first
        )
        let distinctContact = try distinctContactRow.value()
        XCTAssertEqual(distinctContact.contactPointID, successor.contactPointID)
        XCTAssertEqual(distinctContact.workspaceID, distinctTargetWorkspaceID)
        XCTAssertEqual(distinctContact.party.partyID, successor.party.partyID)
        XCTAssertEqual(distinctContact.party.workspaceID, distinctTargetWorkspaceID)
        XCTAssertEqual(distinctContact.revision, 2)
        XCTAssertNotNil(distinctContact.supersedes)
        XCTAssertNotEqual(distinctContact.mutationID, successor.mutationID)
        XCTAssertNotEqual(distinctContact.contactPointSHA256, successor.contactPointSHA256)
        XCTAssertEqual(
            distinctContactRow.canonicalData,
            try OperationalContactCanonicalCodecV1.data(distinctContact)
        )
        XCTAssertEqual(
            try OperationalContactCanonicalCodecV1.decode(
                ServiceContactPointV1.self,
                from: distinctContactRow.canonicalData
            ),
            distinctContact
        )

        let distinctIntent = try XCTUnwrap(
            distinctReplaced.modelContext.fetch(FetchDescriptor<SystemHandoffIntentRow>())
                .first?.value()
        )
        XCTAssertEqual(distinctIntent.workspaceID, distinctTargetWorkspaceID)
        XCTAssertEqual(distinctIntent.disposition, .activeSourceWorkspace)
        XCTAssertEqual(distinctIntent.target.workspaceID, distinctTargetWorkspaceID)
        XCTAssertEqual(distinctIntent.target.targetID, distinctContact.contactPointID)
        XCTAssertEqual(distinctIntent.target.expectedRevision, contact.revision)
        XCTAssertNotEqual(distinctIntent.target.expectedSHA256, distinctContact.contactPointSHA256)

        let distinctMutationRows = try distinctReplaced.modelContext.fetch(
            FetchDescriptor<MutationReceiptRow>()
        )
        .filter { $0.commandKind == WorkspaceCommandKindV1.applyOperationalContact.rawValue }
        .sorted { $0.localSequence < $1.localSequence }
        XCTAssertEqual(distinctMutationRows.count, 1 + sourceOperationalRows.count)

        let retainedTargetRow = try XCTUnwrap(distinctMutationRows.first {
            $0.mutationID == targetOriginalMutationID.rawValue
        })
        XCTAssertEqual(retainedTargetRow.envelopeData, targetOriginalEnvelopeBytes)
        XCTAssertEqual(retainedTargetRow.receiptData, targetOriginalReceiptBytes)

        let distinctDecodedRows = try distinctMutationRows.map { row in
            (row, try MutationEnvelopeV1.decodeCanonical(from: row.envelopeData))
        }
        let importedDecodedRows = distinctDecodedRows.filter {
            $0.1.sourceKind == .importedHistory
        }
        XCTAssertEqual(importedDecodedRows.count, sourceOperationalMutations.count)
        var importedMutations: [OperationalContactMutationV1] = []
        for (_, envelope) in importedDecodedRows {
            guard case let .applyOperationalContact(value) = envelope.command else {
                XCTFail("Expected an imported operational contact mutation")
                return
            }
            XCTAssertEqual(envelope.workspaceID, distinctTargetWorkspaceID)
            XCTAssertEqual(value.workspaceID, distinctTargetWorkspaceID)
            XCTAssertEqual(value.expectedRevision.workspaceID, distinctTargetWorkspaceID)
            importedMutations.append(value)
        }
        XCTAssertEqual(importedMutations.count, 2)
        let importedCreate = importedMutations[0]
        let importedSuccessor = importedMutations[1]
        XCTAssertEqual(importedCreate.predecessors, [])
        XCTAssertEqual(importedCreate.successors.count, 1)
        XCTAssertEqual(importedCreate.handoffIntents.count, 1)
        let importedRevisionOne = try XCTUnwrap(importedCreate.successors.first)
        XCTAssertEqual(importedRevisionOne.contactPointID, contact.contactPointID)
        XCTAssertEqual(importedRevisionOne.workspaceID, distinctTargetWorkspaceID)
        XCTAssertEqual(importedRevisionOne.revision, 1)
        XCTAssertNil(importedRevisionOne.supersedes)
        XCTAssertEqual(importedRevisionOne.mutationID, importedCreate.mutationID)
        XCTAssertEqual(importedRevisionOne.displayValue, contact.displayValue)
        XCTAssertNotEqual(importedRevisionOne.contactPointSHA256, contact.contactPointSHA256)
        let importedIntent = try XCTUnwrap(importedCreate.handoffIntents.first)
        XCTAssertEqual(importedIntent.workspaceID, distinctTargetWorkspaceID)
        XCTAssertEqual(importedIntent.mutationID, importedCreate.mutationID)
        XCTAssertEqual(importedIntent.target.targetID, importedRevisionOne.contactPointID)
        XCTAssertEqual(importedIntent.target.expectedRevision, importedRevisionOne.revision)
        XCTAssertEqual(importedIntent.target.expectedSHA256, importedRevisionOne.contactPointSHA256)
        XCTAssertEqual(distinctIntent, importedIntent)

        XCTAssertEqual(importedSuccessor.predecessors, [importedRevisionOne])
        XCTAssertEqual(importedSuccessor.successors.count, 1)
        XCTAssertTrue(importedSuccessor.handoffIntents.isEmpty)
        let importedRevisionTwo = try XCTUnwrap(importedSuccessor.successors.first)
        XCTAssertEqual(importedRevisionTwo.contactPointID, successor.contactPointID)
        XCTAssertEqual(importedRevisionTwo.workspaceID, distinctTargetWorkspaceID)
        XCTAssertEqual(importedRevisionTwo.revision, 2)
        XCTAssertEqual(
            importedRevisionTwo.supersedes,
            try importedRevisionOne.revisionReference
        )
        XCTAssertEqual(importedRevisionTwo.mutationID, importedSuccessor.mutationID)
        XCTAssertEqual(importedRevisionTwo.displayValue, successor.displayValue)
        XCTAssertNotEqual(importedRevisionTwo.contactPointSHA256, successor.contactPointSHA256)
        XCTAssertEqual(distinctContact, importedRevisionTwo)
        XCTAssertEqual(
            distinctContact.supersedes,
            try importedRevisionOne.revisionReference
        )

        let deterministicPointer = RestorePointerIdentityV1(
            generationID: distinctReplaced.generationID,
            generationManifestSHA256: String(repeating: "a", count: 64),
            workspaceID: distinctTargetWorkspaceID.rawValue,
            replicaID: distinctReplaced.replicaID.rawValue
        )
        let deterministicIdentity = RestoreIdentityV1(
            mode: .replaceExisting,
            source: RestoreSourceIdentityV1(
                workspaceID: source.workspaceID.rawValue,
                replicaID: source.replicaID.rawValue
            ),
            oldPointer: deterministicPointer,
            targetPointer: deterministicPointer,
            recordIdentityDisposition: .preserve
        )
        XCTAssertEqual(
            importedCreate.mutationID,
            try deterministicIdentity.destinationOperationalContactMutationID(for: mutationID)
        )
        XCTAssertEqual(
            importedSuccessor.mutationID,
            try deterministicIdentity.destinationOperationalContactMutationID(
                for: successorMutationID
            )
        )
        XCTAssertEqual(
            Set(importedMutations.map(\.mutationID)).count,
            sourceOperationalMutations.count
        )
        XCTAssertTrue(
            Set(importedMutations.map(\.mutationID)).isDisjoint(
                with: Set(sourceOperationalMutations.map(\.mutationID))
            )
        )

        let distinctJournal = try MutationJournalStoreV1(
            modelContext: distinctReplaced.modelContext,
            identity: distinctReplaced.workspaceIdentity,
            generationID: distinctReplaced.generationID,
            allowStateBootstrap: false
        )
        try distinctJournal.validateAll()
        let distinctWriterInstanceID = C46OperationalContactTestSupport.id(441)
        let distinctWriterRevision = try distinctJournal.currentRevision(
            writerInstanceID: distinctWriterInstanceID
        )
        let distinctWriter = try WorkspaceWriterV1(
            identity: distinctReplaced.workspaceIdentity,
            generationID: distinctReplaced.generationID,
            initialRevision: distinctWriterRevision,
            clock: C46OperationalContactClock(value: C46OperationalContactTestSupport.date(441)),
            idSource: C46OperationalContactIDSource(value: distinctWriterInstanceID),
            fileAuthority: C46OperationalContactFileAuthority(),
            adapter: WorkspaceWriterAdapterV1(modelContext: distinctReplaced.modelContext),
            journalStore: distinctJournal
        )
        let retainedDurableReceiptValue = try await distinctWriter.durableOperationalContactReceipt(
            workspaceID: distinctTargetWorkspaceID,
            mutationID: targetOriginalMutationID
        )
        let retainedDurableReceipt = try XCTUnwrap(retainedDurableReceiptValue)
        XCTAssertEqual(retainedDurableReceipt, targetOriginalReceipt)

        var importedDurableReceipts: [OperationalContactMutationReceiptV1] = []
        for importedMutation in importedMutations {
            let durableValue = try await distinctWriter.durableOperationalContactReceipt(
                workspaceID: distinctTargetWorkspaceID,
                mutationID: importedMutation.mutationID
            )
            let durableReceipt = try XCTUnwrap(durableValue)
            XCTAssertEqual(
                durableReceipt.mutationSHA256,
                try OperationalContactCanonicalCodecV1.sha256(importedMutation)
            )
            XCTAssertEqual(
                durableReceipt.mutationReceipt.identity.workspaceID,
                distinctTargetWorkspaceID
            )
            XCTAssertEqual(
                durableReceipt.mutationReceipt.mutationID,
                importedMutation.mutationID
            )
            importedDurableReceipts.append(durableReceipt)
        }
        XCTAssertEqual(importedDurableReceipts.count, sourceOperationalMutations.count)

        let distinctDurableReceiptValue = try await distinctWriter.durableOperationalContactReceipt(
            workspaceID: distinctTargetWorkspaceID,
            mutationID: distinctContact.mutationID
        )
        let distinctDurableReceipt = try XCTUnwrap(distinctDurableReceiptValue)
        XCTAssertEqual(
            distinctDurableReceipt.mutationSHA256,
            try OperationalContactCanonicalCodecV1.sha256(importedSuccessor)
        )
        XCTAssertEqual(
            distinctDurableReceipt.mutationReceipt.identity.workspaceID,
            distinctTargetWorkspaceID
        )
        XCTAssertEqual(
            distinctDurableReceipt.mutationReceipt.mutationID,
            distinctContact.mutationID
        )
        let distinctContactIdentity = try WorkspaceEntityIdentityV1(
            kind: .serviceContactPoint,
            id: distinctContact.contactPointID
        )
        XCTAssertTrue(
            distinctDurableReceipt.affectedIdentities.contains(distinctContactIdentity)
        )

        let replaceValidated = try BackupImportService(
            generationRootURL: source.generationRootURL,
            makeUUID: { C46OperationalContactTestSupport.id(450) },
            scopedAccess: .alreadyAuthorized
        ).stageAndValidate(selectedPackageURL: package)
        let replaced = try await BackupRestoreService(
            applicationSupportURL: sourceSupport,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in .max })
        ).restore(
            validatedPackage: replaceValidated,
            currentModelContext: source.modelContext,
            currentGenerationID: source.generationID,
            currentGenerationRootURL: source.generationRootURL,
            mode: .replaceExisting
        )
        let replacedContactRow = try XCTUnwrap(
            replaced.modelContext.fetch(FetchDescriptor<ServiceContactPointRow>()).first
        )
        let replacedIntentRow = try XCTUnwrap(
            replaced.modelContext.fetch(FetchDescriptor<SystemHandoffIntentRow>()).first
        )
        let replacedContact = try replacedContactRow.value()
        XCTAssertEqual(replacedContactRow.canonicalData, sourceContactBytes)
        XCTAssertEqual(replacedIntentRow.canonicalData, sourceIntentBytes)
        XCTAssertEqual(replacedContact, successor)
        XCTAssertEqual(replacedContact.contactPointID, successor.contactPointID)
        XCTAssertEqual(replacedContact.workspaceID, successor.workspaceID)
        XCTAssertEqual(replacedContact.revision, successor.revision)
        XCTAssertEqual(replacedContact.supersedes, successor.supersedes)
        XCTAssertEqual(replacedContact.mutationID, successor.mutationID)
        XCTAssertEqual(replacedContact.contactPointSHA256, successor.contactPointSHA256)
        let replacedJournal = try MutationJournalStoreV1(
            modelContext: replaced.modelContext,
            identity: replaced.workspaceIdentity,
            generationID: replaced.generationID,
            allowStateBootstrap: false
        )
        try replacedJournal.validateAll()

        try C46OperationalContactKernelDeletionEnrollmentV1.validate()
        XCTAssertEqual(
            C46OperationalContactKernelDeletionEnrollmentV1.durableFamilies,
            OperationalContactPersistenceEnrollmentV1.persistentFamilies
        )
        let deletion = try await WholeSignDeletionService(
            modelContext: replaced.modelContext,
            generationRootURL: replaced.generationRootURL
        ).delete(assetID: unrelatedAssetID)
        XCTAssertEqual(deletion.assetID, unrelatedAssetID)
        XCTAssertEqual(
            try replaced.modelContext.fetch(FetchDescriptor<ServiceContactPointRow>()).map { try $0.value() },
            [successor]
        )
        XCTAssertEqual(
            try replaced.modelContext.fetch(FetchDescriptor<SystemHandoffIntentRow>()).map { try $0.value() },
            [intent]
        )
        XCTAssertEqual(
            try replaced.modelContext.fetch(FetchDescriptor<Site>()).map(\.id),
            [unrelatedSiteID]
        )
        XCTAssertTrue(try replaced.modelContext.fetch(FetchDescriptor<Asset>()).isEmpty)

        let caches = root.appendingPathComponent("caches", isDirectory: true)
        let temporary = root.appendingPathComponent("temporary", isDirectory: true)
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        let coordinator = StoreSessionCoordinator(session: replaced)
        let diagnostics = DiagnosticsStore(applicationSupportURL: sourceSupport)
        await diagnostics.prepare()
        let suiteName = "C46-R01-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let erase = EraseAllService(
            applicationSupportURL: sourceSupport,
            cachesDirectoryURL: caches,
            temporaryDirectoryURL: temporary,
            userDefaults: defaults,
            bundleIdentifier: suiteName
        )
        let erased = try await erase.erase(
            confirmation: EraseAllService.requiredConfirmation,
            coordinator: coordinator,
            diagnosticsStore: diagnostics
        ) { replacement in
            coordinator.activate(session: replacement)
        }
        try erase.validateOperationalContactEraseClosure(session: erased.session)
        XCTAssertTrue(
            try erased.session.modelContext.fetch(FetchDescriptor<ServiceContactPointRow>()).isEmpty
        )
        XCTAssertTrue(
            try erased.session.modelContext.fetch(FetchDescriptor<SystemHandoffIntentRow>()).isEmpty
        )
    }
}

private final class C32OperationalContactRestoreBoundaryTests: XCTestCase {
    @MainActor
    func testV23P04C32RestoreRebindsOneAggregateReceiptWithoutContactFanout() async throws {
        let root = try C46OperationalContactTestSupport.temporaryDirectory("c32-restore")
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceSupport = root.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceSupport, withIntermediateDirectories: true)
        let source = try StoreGenerationFactory(applicationSupportURL: sourceSupport)
            .openOrBootstrapCurrent()
        let sourceWriterInstanceID = C46OperationalContactTestSupport.id(32_001)
        let sourceJournal = try MutationJournalStoreV1(
            modelContext: source.modelContext,
            identity: source.workspaceIdentity,
            generationID: source.generationID
        )
        let sourceWriter = try WorkspaceWriterV1(
            identity: source.workspaceIdentity,
            generationID: source.generationID,
            initialRevision: try sourceJournal.currentRevision(writerInstanceID: sourceWriterInstanceID),
            clock: C46OperationalContactClock(value: C46OperationalContactTestSupport.date(32_001)),
            idSource: C46OperationalContactIDSource(value: sourceWriterInstanceID),
            fileAuthority: C46OperationalContactFileAuthority(),
            adapter: WorkspaceWriterAdapterV1(modelContext: source.modelContext),
            journalStore: sourceJournal
        )
        let siteID = C46OperationalContactTestSupport.id(32_002)
        _ = try sourceWriter.execute(WorkspaceMutationRequestV1(
            mutationID: try C46OperationalContactTestSupport.mutation(32_003),
            expectedRevision: .init(snapshot: try sourceWriter.currentRevision()),
            command: .createFirstSign(.init(
                siteID: siteID,
                newSite: .init(
                    id: siteID,
                    label: "C32 restore site",
                    address: nil,
                    timeZoneID: "UTC"
                ),
                assetID: C46OperationalContactTestSupport.id(32_004),
                assetLabel: "C32 restore seed",
                packID: "c32.restore.seed",
                packSchemaVersion: 1,
                packContentVersion: 1,
                createdAt: C46OperationalContactTestSupport.date(32_004)
            ))
        ))

        let sourceSnapshot = try sourceWriter.currentRevision()
        let mutationID = try C46OperationalContactTestSupport.mutation(32_010)
        let partyID = C46OperationalContactTestSupport.id(32_011)
        let contactID = C46OperationalContactTestSupport.id(32_012)
        let roleID = C46OperationalContactTestSupport.id(32_013)
        let expected = try WorkspaceExpectedRevisionV1(
            workspaceID: sourceSnapshot.workspaceID,
            generationID: sourceSnapshot.generationID,
            writerInstanceID: sourceSnapshot.writerInstanceID,
            workspaceRevision: sourceSnapshot.revision,
            entityRevisions: sourceSnapshot.entityRevisions + [
                .init(identity: try .init(kind: .serviceParty, id: partyID), revision: 0),
                .init(identity: try .init(kind: .serviceContactPoint, id: contactID), revision: 0),
                .init(identity: try .init(kind: .sitePartyRoleEvent, id: roleID), revision: 0),
            ]
        )
        let party = try ServicePartyReferenceV1(
            partyID: partyID,
            workspaceID: source.workspaceID,
            kind: .organization,
            displayName: "C32 restore contractor",
            profileDescriptor: "Operational restore coverage",
            provenance: .importedExternalEvidence,
            state: .effective,
            effectiveAt: C46OperationalContactTestSupport.date(32_010),
            revision: 1,
            mutationID: mutationID
        )
        let importSourceSet = try ImportSourceSetV1(
            workspaceID: source.workspaceID,
            files: [try .init(
                schemaID: PartyContactCSVRowV1.schemaID,
                schemaVersion: PartyContactCSVRowV1.schemaVersion,
                fileName: "party-contacts.csv",
                orderIndex: 0,
                byteCount: 1,
                sha256: String(repeating: "a", count: 64)
            )]
        )
        let contact = try ServiceContactPointV1(
            contactPointID: contactID,
            workspaceID: source.workspaceID,
            party: party,
            kind: .email,
            label: .work,
            displayValue: "restore.operator@example.test",
            preferred: true,
            provenance: .importedExternalEvidence,
            importSourceSetSHA256: importSourceSet.sourceSetSHA256,
            lifecycle: .effective,
            effectiveAt: C46OperationalContactTestSupport.date(32_010),
            revision: 1,
            mutationID: mutationID
        )
        let contactMutation = try OperationalContactMutationV1(
            workspaceID: source.workspaceID,
            mutationID: mutationID,
            expectedRevision: expected,
            successors: [contact],
            preferredScopes: [try .init(
                partyID: partyID,
                kind: .email,
                activeContactPointIDs: [contactID],
                preferredContactPointID: contactID
            )],
            importSourceSet: importSourceSet
        )
        let role = try SitePartyRoleEventV1(
            eventID: roleID,
            workspaceID: source.workspaceID,
            siteID: siteID,
            partyID: partyID,
            role: .serviceProvider,
            effectiveFrom: C46OperationalContactTestSupport.date(32_010),
            source: .importedExternalEvidence,
            revision: 1,
            mutationID: mutationID,
            recordedAt: C46OperationalContactTestSupport.date(32_010)
        )
        let sourceMutation = try PartyContactSiteRoleImportMutationV1(
            workspaceID: source.workspaceID,
            mutationID: mutationID,
            expectedRevision: expected,
            partyMutations: [.recordParty(party)],
            operationalContactMutation: contactMutation,
            siteRoleMutations: [.appendSiteRole(role)]
        )
        let sourceOutcome = try sourceWriter.execute(
            sourceMutation.canonicalWorkspaceMutationRequest()
        )
        XCTAssertEqual(sourceOutcome.after.revision, sourceSnapshot.revision + 1)
        let sourceReceipt = try XCTUnwrap(
            try sourceWriter.durableReceipt(mutationID: mutationID)
        )
        _ = try PartyContactSiteRoleImportMutationReceiptV1(
            mutation: sourceMutation,
            mutationReceipt: sourceReceipt
        )
        try sourceJournal.validateAll()

        let exportRoot = root.appendingPathComponent("export", isDirectory: true)
        try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: true)
        let exporter = BackupExportService(
            modelContext: source.modelContext,
            generationRootURL: source.generationRootURL,
            now: { C46OperationalContactTestSupport.date(32_020) }
        )
        let package = try exporter.export(previewID: exporter.prepare().id, to: exportRoot)

        let targetSupport = root.appendingPathComponent("target", isDirectory: true)
        try FileManager.default.createDirectory(at: targetSupport, withIntermediateDirectories: true)
        let target = try StoreGenerationFactory(applicationSupportURL: targetSupport)
            .openOrBootstrapCurrent()
        XCTAssertNotEqual(target.workspaceID, source.workspaceID)
        let retainedParty = try C46OperationalContactTestSupport.party(
            slot: 32_030,
            workspaceID: target.workspaceID
        )
        target.modelContext.insert(try ServicePartyRow(retainedParty))
        target.modelContext.insert(EntityMutationRevisionRow(
            identity: try .init(kind: .serviceParty, id: retainedParty.partyID),
            revision: retainedParty.revision,
            externalProjectionSHA256: retainedParty.receiptSHA256
        ))
        try target.modelContext.save()
        let retainedWriterInstanceID = C46OperationalContactTestSupport.id(32_031)
        let retainedJournal = try MutationJournalStoreV1(
            modelContext: target.modelContext,
            identity: target.workspaceIdentity,
            generationID: target.generationID
        )
        let retainedRevision = try retainedJournal.currentRevision(
            writerInstanceID: retainedWriterInstanceID
        )
        let retainedMutationID = try C46OperationalContactTestSupport.mutation(32_032)
        let retainedContact = try ServiceContactPointV1(
            contactPointID: C46OperationalContactTestSupport.id(32_033),
            workspaceID: target.workspaceID,
            party: retainedParty,
            kind: .email,
            label: .work,
            displayValue: "target.retained@example.test",
            preferred: true,
            provenance: .manual,
            lifecycle: .effective,
            effectiveAt: C46OperationalContactTestSupport.date(32_033),
            revision: 1,
            mutationID: retainedMutationID
        )
        let retainedExpected = try WorkspaceExpectedRevisionV1(
            workspaceID: retainedRevision.workspaceID,
            generationID: retainedRevision.generationID,
            writerInstanceID: retainedRevision.writerInstanceID,
            workspaceRevision: retainedRevision.revision,
            entityRevisions: retainedRevision.entityRevisions + [
                .init(
                    identity: try .init(kind: .serviceContactPoint, id: retainedContact.contactPointID),
                    revision: 0
                )
            ]
        )
        let retainedMutation = try OperationalContactMutationV1(
            workspaceID: target.workspaceID,
            mutationID: retainedMutationID,
            expectedRevision: retainedExpected,
            successors: [retainedContact],
            preferredScopes: [try .init(
                partyID: retainedParty.partyID,
                kind: .email,
                activeContactPointIDs: [retainedContact.contactPointID],
                preferredContactPointID: retainedContact.contactPointID
            )]
        )
        let retainedWriter = try WorkspaceWriterV1(
            identity: target.workspaceIdentity,
            generationID: target.generationID,
            initialRevision: retainedRevision,
            clock: C46OperationalContactClock(value: C46OperationalContactTestSupport.date(32_034)),
            idSource: C46OperationalContactIDSource(value: retainedWriterInstanceID),
            fileAuthority: C46OperationalContactFileAuthority(),
            adapter: WorkspaceWriterAdapterV1(modelContext: target.modelContext),
            journalStore: retainedJournal
        )
        _ = try await retainedWriter.commitOperationalContact(retainedMutation)

        let validated = try BackupImportService(
            generationRootURL: target.generationRootURL,
            makeUUID: { C46OperationalContactTestSupport.id(32_040) },
            scopedAccess: .alreadyAuthorized
        ).stageAndValidate(selectedPackageURL: package)
        XCTAssertEqual(
            try validated.records.validateC32PartyContactSiteRoleImportClosure(),
            [sourceMutation]
        )
        let interruptedRestore = try BackupRestoreService(
            applicationSupportURL: targetSupport,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in .max }),
            failureInjection: BackupRestoreFailureInjection(failOnceAt: .beforePointerSwitch)
        )
        do {
            _ = try await interruptedRestore.restore(
                validatedPackage: validated,
                currentModelContext: target.modelContext,
                currentGenerationID: target.generationID,
                currentGenerationRootURL: target.generationRootURL,
                mode: .replaceExisting
            )
            XCTFail("Injected restore interruption must not report success")
        } catch {
            XCTAssertEqual(error as? BackupRestoreServiceError, .injectedFailure)
        }
        let restored = try XCTUnwrap(
            try BackupRestoreService(
                applicationSupportURL: targetSupport,
                storagePreflight: StoragePreflightService(capacityProvider: { _ in .max })
            ).reconcileAtStartup()
        )
        XCTAssertEqual(restored.workspaceID, target.workspaceID)

        let restoredRows = try restored.modelContext.fetch(FetchDescriptor<MutationReceiptRow>())
        let decodedRows = try restoredRows.map { row in
            (row, try MutationEnvelopeV1.decodeCanonical(from: row.envelopeData))
        }
        let importedCompounds = decodedRows.filter { row, envelope in
            envelope.sourceKind == .importedHistory
                && envelope.command.kind == .applyPartyContactSiteRoleImport
        }
        XCTAssertEqual(importedCompounds.count, 1)
        let (compoundRow, compoundEnvelope) = try XCTUnwrap(importedCompounds.first)
        guard case let .applyPartyContactSiteRoleImport(rebound) = compoundEnvelope.command else {
            XCTFail("Expected the restored C32 aggregate envelope")
            return
        }
        let compoundReceipt = try MutationReceiptV1.decodeCanonical(from: compoundRow.receiptData)
        let typedReceipt = try PartyContactSiteRoleImportMutationReceiptV1(
            mutation: rebound,
            mutationReceipt: compoundReceipt
        )
        XCTAssertEqual(typedReceipt.mutationReceipt, compoundReceipt)
        XCTAssertEqual(rebound.workspaceID, target.workspaceID)
        XCTAssertNotEqual(rebound.mutationID, sourceMutation.mutationID)
        XCTAssertEqual(rebound.partyMutations.count, 1)
        XCTAssertEqual(rebound.operationalContactMutation.successors.count, 1)
        XCTAssertEqual(rebound.siteRoleMutations.count, 1)

        let orderedRows = decodedRows.sorted { lhs, rhs in lhs.0.localSequence < rhs.0.localSequence }
        let compoundIndex = try XCTUnwrap(orderedRows.firstIndex { $0.0.mutationID == rebound.mutationID.rawValue })
        XCTAssertGreaterThan(compoundIndex, 0)
        let previousReceipt = try MutationReceiptV1.decodeCanonical(
            from: orderedRows[compoundIndex - 1].0.receiptData
        )
        XCTAssertEqual(compoundReceipt.identity.localSequence, previousReceipt.identity.localSequence + 1)
        XCTAssertEqual(
            compoundReceipt.resultingRevision.workspaceRevision,
            previousReceipt.resultingRevision.workspaceRevision + 1
        )
        XCTAssertEqual(
            compoundReceipt.resultingRevision.workspaceRevision,
            rebound.expectedRevision.workspaceRevision + 1
        )
        XCTAssertEqual(
            decodedRows.filter { row, envelope in
                row.mutationID == rebound.mutationID.rawValue
                    && envelope.command.kind != .applyPartyContactSiteRoleImport
            }.count,
            0
        )
        XCTAssertEqual(
            decodedRows.filter { _, envelope in
                envelope.sourceKind == .importedHistory
                    && (envelope.command.kind == .applyOperationalContact
                        || envelope.command.kind == .applyPartyAccountability)
            }.count,
            0
        )

        let reboundParty = try XCTUnwrap(
            restored.modelContext.fetch(FetchDescriptor<ServicePartyRow>())
                .first(where: { $0.partyID == partyID })?.value()
        )
        let reboundContact = try XCTUnwrap(
            restored.modelContext.fetch(FetchDescriptor<ServiceContactPointRow>())
                .first(where: { $0.contactPointID == contactID })?.value()
        )
        let reboundRole = try XCTUnwrap(
            restored.modelContext.fetch(FetchDescriptor<SitePartyRoleEventRow>())
                .first(where: { $0.eventID == roleID })?.value()
        )
        XCTAssertEqual(reboundParty.workspaceID, target.workspaceID)
        XCTAssertEqual(reboundParty.mutationID, rebound.mutationID)
        XCTAssertEqual(reboundContact.workspaceID, target.workspaceID)
        XCTAssertEqual(reboundContact.party, reboundParty)
        XCTAssertEqual(reboundContact.mutationID, rebound.mutationID)
        XCTAssertEqual(reboundContact.displayValue, "restore.operator@example.test")
        XCTAssertEqual(reboundRole.workspaceID, target.workspaceID)
        XCTAssertEqual(reboundRole.siteID, siteID)
        XCTAssertEqual(reboundRole.partyID, reboundParty.partyID)
        XCTAssertEqual(reboundRole.mutationID, rebound.mutationID)
        XCTAssertFalse(PartyContactsCSVContractV1.defaultExportEnabled)
        XCTAssertFalse(OperationalContactPersistenceEnrollmentV1.importSourceBytesArePersistent)
        try MutationJournalStoreV1(
            modelContext: restored.modelContext,
            identity: restored.workspaceIdentity,
            generationID: restored.generationID,
            allowStateBootstrap: false
        ).validateAll()
    }
}

private struct C46OperationalContactClock: ApplicationClock {
    let value: Date
    func now() -> Date { value }
}

private struct C46OperationalContactIDSource: ApplicationIDSource {
    let value: UUID
    func makeID() -> UUID { value }
}

private struct C46OperationalContactFileAuthority: ApplicationFileAuthorityV1 {
    func temporaryRelativePath(
        mutationID: MutationIDV1,
        component: String
    ) throws -> String {
        "c46/\(mutationID.rawValue.uuidString.lowercased())/\(component)"
    }
}

@MainActor
private final class C46SystemHandoffOpener: SystemURLHandoffOpeningV1 {
    let canPresentSystemHandoff: Bool
    private let accepts: Bool
    private(set) var openedURLs: [URL] = []

    init(canPresent: Bool, accepts: Bool) {
        canPresentSystemHandoff = canPresent
        self.accepts = accepts
    }

    func openOnce(_ url: URL) async -> Bool {
        openedURLs.append(url)
        return accepts
    }
}

enum C46OperationalContactTestSupport {
    static func id(_ slot: Int) -> UUID {
        UUID(uuidString: String(format: "46000000-0000-0000-0000-%012d", slot))!
    }

    static func date(_ offset: Double) -> Date {
        Date(timeIntervalSince1970: 2_100_000_000 + offset)
    }

    static func workspace(_ slot: Int) -> WorkspaceID {
        WorkspaceID(rawValue: id(slot))
    }

    static func mutation(_ slot: Int) throws -> MutationIDV1 {
        try MutationIDV1(rawValue: id(slot))
    }

    static func temporaryDirectory(_ component: String) throws -> URL {
        let value = FileManager.default.temporaryDirectory
            .appendingPathComponent("c46-\(component)-\(UUID().uuidString.lowercased())", isDirectory: true)
        try FileManager.default.createDirectory(at: value, withIntermediateDirectories: true)
        return value
    }

    static func party(slot: Int, workspaceID: WorkspaceID) throws -> ServicePartyReferenceV1 {
        try ServicePartyReferenceV1(
            partyID: id(slot),
            workspaceID: workspaceID,
            kind: slot.isMultiple(of: 2) ? .organization : .person,
            displayName: "C46 service party \(slot)",
            profileDescriptor: "Operational relationship only",
            provenance: .locallyRecorded,
            state: .effective,
            effectiveAt: date(Double(slot)),
            revision: 1,
            mutationID: mutation(slot + 1)
        )
    }

    static func contact(
        slot: Int,
        kind: ServiceContactKindV1,
        label: ServiceContactLabelV1,
        displayValue: String,
        preferred: Bool = false
    ) throws -> ServiceContactPointV1 {
        let workspaceID = workspace(slot + 1_000)
        return try ServiceContactPointV1(
            contactPointID: id(slot),
            workspaceID: workspaceID,
            party: party(slot: slot + 1, workspaceID: workspaceID),
            kind: kind,
            label: label,
            displayValue: displayValue,
            preferred: preferred,
            provenance: .manual,
            lifecycle: .effective,
            effectiveAt: date(Double(slot)),
            revision: 1,
            mutationID: mutation(slot + 2)
        )
    }

    static func intent(
        slot: Int,
        kind: SystemHandoffKindV1,
        contact: ServiceContactPointV1
    ) throws -> SystemHandoffIntentV1 {
        let target = try SystemHandoffTargetReferenceV1(
            workspaceID: contact.workspaceID,
            kind: .serviceContactPoint,
            targetID: contact.contactPointID,
            expectedRevision: contact.revision,
            expectedSHA256: contact.contactPointSHA256
        )
        return try SystemHandoffIntentV1(
            intentID: id(slot),
            workspaceID: contact.workspaceID,
            kind: kind,
            target: target,
            reviewedAt: date(Double(slot)),
            revision: 1,
            mutationID: contact.mutationID
        )
    }

    static func expectedRevision(
        contact: ServiceContactPointV1,
        intent: SystemHandoffIntentV1,
        revision: UInt64,
        slot: Int
    ) throws -> WorkspaceExpectedRevisionV1 {
        try WorkspaceExpectedRevisionV1(
            workspaceID: contact.workspaceID,
            generationID: id(slot),
            writerInstanceID: id(slot + 1),
            workspaceRevision: revision,
            entityRevisions: [
                WorkspaceEntityRevisionV1(
                    identity: WorkspaceEntityIdentityV1(
                        kind: .serviceContactPoint,
                        id: contact.contactPointID
                    ),
                    revision: revision
                ),
                WorkspaceEntityRevisionV1(
                    identity: WorkspaceEntityIdentityV1(
                        kind: .serviceParty,
                        id: contact.party.partyID
                    ),
                    revision: contact.party.revision
                ),
                WorkspaceEntityRevisionV1(
                    identity: WorkspaceEntityIdentityV1(
                        kind: .systemHandoffIntent,
                        id: intent.intentID
                    ),
                    revision: revision
                )
            ]
        )
    }

    static func assertOwnerBoundary(
        owner: String,
        kind: ServiceContactKindV1,
        handoff: SystemHandoffKindV1,
        slot: Int
    ) throws {
        let contact = try self.contact(
            slot: slot,
            kind: kind,
            label: kind == .email ? .work : .office,
            displayValue: kind == .email ? "\(owner)+ops@Example.COM" : "+44 20 7946 \(String(format: "%04d", slot % 10_000)) ext. 9"
        )
        XCTAssertEqual(contact.kind, kind)
        XCTAssertEqual(contact.privacyClass, .workspaceCustomerData)
        XCTAssertEqual(contact.party.workspaceID, contact.workspaceID)
        XCTAssertFalse(PartyContactsCSVContractV1.defaultExportEnabled)
        if handoff != .directions {
            let intent = try self.intent(slot: slot + 10_000, kind: handoff, contact: contact)
            XCTAssertEqual(intent.target.targetID, contact.contactPointID)
            XCTAssertEqual(intent.target.expectedSHA256, contact.contactPointSHA256)
        } else {
            let target = try SystemHandoffTargetReferenceV1(
                workspaceID: contact.workspaceID,
                kind: .site,
                targetID: id(slot + 20_000),
                expectedRevision: 1,
                expectedSHA256: String(repeating: "d", count: 64)
            )
            let intent = try SystemHandoffIntentV1(
                intentID: id(slot + 30_000),
                workspaceID: contact.workspaceID,
                kind: .directions,
                target: target,
                reviewedAt: date(Double(slot)),
                revision: 1,
                mutationID: contact.mutationID
            )
            XCTAssertEqual(intent.target.kind, .site)
            XCTAssertEqual(intent.kind, .directions)
        }
    }
}

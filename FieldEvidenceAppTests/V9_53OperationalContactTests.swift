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
        for party in importParties {
            _ = try writer.execute(.applyPartyAccountability(.recordParty(party)),
                mutationID: party.mutationID)
            XCTAssertNotNil(try writer.durableReceipt(mutationID: party.mutationID))
        }
        let partySeedRevision = try writer.currentRevision()
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
            workspaceID: partySeedRevision.workspaceID,
            generationID: partySeedRevision.generationID,
            writerInstanceID: partySeedRevision.writerInstanceID,
            workspaceRevision: partySeedRevision.revision,
            entityRevisions: partySeedRevision.entityRevisions + importedContactRevisions
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
        XCTAssertEqual(try writer.currentRevision().revision, partySeedRevision.revision + 1)
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
        let writerInstanceID = C46OperationalContactTestSupport.id(331)
        do {
            let seedJournal = try MutationJournalStoreV1(
                modelContext: session.modelContext,
                identity: session.workspaceIdentity,
                generationID: session.generationID
            )
            let seedWriter = try WorkspaceWriterV1(
                identity: session.workspaceIdentity,
                generationID: session.generationID,
                initialRevision: seedJournal.currentRevision(writerInstanceID: writerInstanceID),
                clock: C46OperationalContactClock(value: C46OperationalContactTestSupport.date(331)),
                idSource: C46OperationalContactIDSource(value: writerInstanceID),
                fileAuthority: C46OperationalContactFileAuthority(),
                adapter: WorkspaceWriterAdapterV1(modelContext: session.modelContext),
                journalStore: seedJournal
            )
            _ = try seedWriter.execute(.applyPartyAccountability(.recordParty(durableParty)),
                mutationID: durableParty.mutationID)
            XCTAssertNotNil(try seedWriter.durableReceipt(mutationID: durableParty.mutationID))
        }
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
        // Preserve the root on all failures; the actual Erase owner retains it.
        weak var seededSession: StoreGenerationSession?
        weak var seededContext: ModelContext?
        weak var seededContainer: ModelContainer?
        weak var restoredSession: StoreGenerationSession?
        weak var restoredContext: ModelContext?
        weak var restoredContainer: ModelContainer?
        let target = try await { () async throws -> (support: URL, generationID: UUID) in
        let sourceSupport = root.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceSupport, withIntermediateDirectories: true)
        let source = try StoreGenerationFactory(applicationSupportURL: sourceSupport)
            .openOrBootstrapCurrent()
        seededSession = source
        seededContext = source.modelContext
        seededContainer = source.modelContext.container
        let party = try C46OperationalContactTestSupport.party(slot: 400, workspaceID: source.workspaceID)
        let unrelatedSiteID = C46OperationalContactTestSupport.id(408)
        let unrelatedAssetID = C46OperationalContactTestSupport.id(409)
        let writerInstanceID = C46OperationalContactTestSupport.id(401)
        let journal = try MutationJournalStoreV1(
            modelContext: source.modelContext,
            identity: source.workspaceIdentity,
            generationID: source.generationID
        )
        let current = try journal.currentRevision(writerInstanceID: writerInstanceID)
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
        _ = try writer.execute(.applyPartyAccountability(.recordParty(party)),
            mutationID: party.mutationID)
        let unrelatedAssetMutationID = try C46OperationalContactTestSupport.mutation(411)
        _ = try writer.execute(.createFirstSign(.init(
            siteID: unrelatedSiteID,
            newSite: .init(id: unrelatedSiteID, label: "C46 unrelated deletion site",
                address: "12 Broadway, New York, NY", timeZoneID: "America/New_York"),
            assetID: unrelatedAssetID,
            assetLabel: "C46 unrelated asset",
            packID: SignPack.illuminatedSignV1.packID,
            packSchemaVersion: SignPack.illuminatedSignV1.schemaVersion,
            packContentVersion: SignPack.illuminatedSignV1.contentVersion,
            createdAt: C46OperationalContactTestSupport.date(409),
            initialPlacementMutationID: unrelatedAssetMutationID,
            initialPlacementEventID: C46OperationalContactTestSupport.id(412),
            initialPhysicalEpisodeID: try PhysicalPlacementEpisodeIDV1(
                rawValue: C46OperationalContactTestSupport.id(413))
        )), mutationID: unrelatedAssetMutationID)
        XCTAssertNotNil(try writer.durableReceipt(mutationID: party.mutationID))
        XCTAssertNotNil(try writer.durableReceipt(mutationID: unrelatedAssetMutationID))
        let contactCurrent = try writer.currentRevision()
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
            workspaceID: contactCurrent.workspaceID,
            generationID: contactCurrent.generationID,
            writerInstanceID: contactCurrent.writerInstanceID,
            workspaceRevision: contactCurrent.revision,
            entityRevisions: contactCurrent.entityRevisions + [
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
            throw V23EraseOperationHarnessV1.Failure.admission
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
            if index == 0 {
                // Hostiles begin with the genuinely exported R01 package. Do
                // not mint or reseal a receipt to make altered history appear
                // authorized: removal and duplication must fail closed.
                let history = try XCTUnwrap(validated.records.mutationHistory)
                func withHistory(_ replacement: MutationHistorySnapshotV1) throws
                    -> V4BackupRecordsV1 {
                    let encoder = JSONEncoder()
                    encoder.dateEncodingStrategy = .millisecondsSince1970
                    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
                    var object = try XCTUnwrap(JSONSerialization.jsonObject(
                        with: encoder.encode(validated.records)) as? [String: Any])
                    object["mutationHistory"] = try JSONSerialization.jsonObject(
                        with: encoder.encode(replacement))
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .millisecondsSince1970
                    return try decoder.decode(V4BackupRecordsV1.self,
                        from: JSONSerialization.data(withJSONObject: object,
                            options: [.sortedKeys, .fragmentsAllowed]))
                }
                var removedOriginal = false
                let missingOriginal = try history.receipts.filter { record in
                    let envelope = try MutationEnvelopeV1.decodeCanonical(from: record.envelopeData)
                    if envelope.mutationID == mutationID {
                        removedOriginal = true
                        return false
                    }
                    return true
                }
                XCTAssertTrue(removedOriginal)
                let missingHistory = MutationHistorySnapshotV1(
                    workspaceRevision: history.workspaceRevision,
                    lastLocalSequence: history.lastLocalSequence,
                    receipts: missingOriginal,
                    quarantines: history.quarantines,
                    entityRevisions: history.entityRevisions)
                let missingRecords = try withHistory(missingHistory)
                XCTAssertThrowsError(try missingRecords.validateC46OperationalContacts())

                let duplicatedHistory = MutationHistorySnapshotV1(
                    workspaceRevision: history.workspaceRevision,
                    lastLocalSequence: history.lastLocalSequence,
                    receipts: history.receipts + [try XCTUnwrap(history.receipts.first {
                        record in
                        let envelope = try? MutationEnvelopeV1.decodeCanonical(from: record.envelopeData)
                        return envelope?.mutationID == successorMutationID
                    })],
                    quarantines: history.quarantines,
                    entityRevisions: history.entityRevisions)
                let duplicatedRecords = try withHistory(duplicatedHistory)
                XCTAssertThrowsError(try duplicatedRecords.validateC46OperationalContacts())

                let wrongTarget = try SystemHandoffTargetReferenceV1(
                    workspaceID: intent.workspaceID, kind: .serviceContactPoint,
                    targetID: contact.contactPointID, expectedRevision: contact.revision,
                    expectedSHA256: String(repeating: "f", count: 64))
                let retargeted = try SystemHandoffIntentV1(
                    intentID: intent.intentID, workspaceID: intent.workspaceID,
                    kind: intent.kind, target: wrongTarget,
                    reviewedAt: intent.reviewedAt, revision: intent.revision,
                    mutationID: intent.mutationID, disposition: intent.disposition)
                let changedRows = try validated.records.operationalContacts.map { row in
                    row.kind == .systemHandoffIntent && row.id == intent.intentID
                        ? try V35BackupOperationalContactRecordV1(retargeted) : row
                }
                let changedRecords = validated.records.replacingOperationalContacts(changedRows)
                XCTAssertThrowsError(try changedRecords.validateC46OperationalContacts())
            }
            let restoreService = try BackupRestoreService(
                applicationSupportURL: support,
                storagePreflight: StoragePreflightService(capacityProvider: { _ in .max })
            )
#if DEBUG
            restoreService.restorePhaseDiagnosticForTesting = { phase in
                // The service hook has some dynamic recovery messages. Only
                // these five fixed restore-stage labels may reach this trace.
                switch phase {
                case "records-for-materialization", "parts-stock-lifecycle",
                     "accessible-documents", "photo-and-clone-plan", "materialize":
                    FileHandle.standardError.write(Data(
                        "C46_R01_RESTORE_DIAGNOSTIC_V1 modeIndex=\(index) phase=\(phase)\n".utf8
                    ))
                default:
                    break
                }
            }
#endif
            let restored = try await restoreService.restore(
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
            if mode == .clone || mode == .fork {
                let sourceHistory = try XCTUnwrap(validated.records.mutationHistory)
                let restoredHistory = try restoredJournal.exportSnapshot()
                let originalC46 = try sourceHistory.receipts.filter { record in
                    let envelope = try MutationEnvelopeV1.decodeCanonical(
                        from: record.envelopeData
                    )
                    return envelope.workspaceID == source.workspaceIdentity.workspaceID
                        && envelope.command.kind == .applyOperationalContact
                }
                let retainedOriginalC46 = try restoredHistory.receipts.filter { record in
                    let envelope = try MutationEnvelopeV1.decodeCanonical(
                        from: record.envelopeData
                    )
                    return envelope.workspaceID == source.workspaceIdentity.workspaceID
                        && envelope.command.kind == .applyOperationalContact
                }
                XCTAssertEqual(retainedOriginalC46, originalC46)
                let projectedC46 = try restoredHistory.receipts.compactMap {
                    record -> OperationalContactMutationV1? in
                    let envelope = try MutationEnvelopeV1.decodeCanonical(
                        from: record.envelopeData
                    )
                    guard envelope.workspaceID == restored.workspaceIdentity.workspaceID,
                          case let .applyOperationalContact(mutation) = envelope.command else {
                        return nil
                    }
                    let receipt = try MutationReceiptV1.decodeCanonical(
                        from: record.receiptData
                    )
                    _ = try OperationalContactMutationReceiptV1(
                        mutation: mutation, mutationReceipt: receipt
                    )
                    XCTAssertEqual(envelope.sourceKind, .importedHistory)
                    XCTAssertNotEqual(receipt.identity.replicaID,
                        restored.workspaceIdentity.replicaID)
                    return mutation
                }
                XCTAssertEqual(projectedC46.count, originalC46.count)
                XCTAssertTrue(projectedC46.contains {
                    $0.successors.contains(restoredContact)
                })
                XCTAssertTrue(projectedC46.contains {
                    $0.handoffIntents.contains(restoredIntent)
                })
                XCTAssertTrue(projectedC46.flatMap(\.handoffIntents).allSatisfy {
                    $0.disposition == .historicReferenceOnly
                        && $0.target == intent.target
                })
            }
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
        let targetOriginalWriterInstanceID = C46OperationalContactTestSupport.id(443)
        let targetOriginalJournal = try MutationJournalStoreV1(
            modelContext: distinctTarget.modelContext,
            identity: distinctTarget.workspaceIdentity,
            generationID: distinctTarget.generationID
        )
        let targetOriginalRevision = try targetOriginalJournal.currentRevision(
            writerInstanceID: targetOriginalWriterInstanceID
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
        _ = try targetOriginalWriter.execute(
            .applyPartyAccountability(.recordParty(targetOriginalParty)),
            mutationID: targetOriginalParty.mutationID
        )
        XCTAssertNotNil(try targetOriginalWriter.durableReceipt(
            mutationID: targetOriginalParty.mutationID
        ))
        let targetContactCurrent = try targetOriginalWriter.currentRevision()
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
            workspaceID: targetContactCurrent.workspaceID,
            generationID: targetContactCurrent.generationID,
            writerInstanceID: targetContactCurrent.writerInstanceID,
            workspaceRevision: targetContactCurrent.revision,
            entityRevisions: targetContactCurrent.entityRevisions + [
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
                throw V23EraseOperationHarnessV1.Failure.admission
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
        restoredSession = replaced
        restoredContext = replaced.modelContext
        restoredContainer = replaced.modelContext.container
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

        return (sourceSupport, replaced.generationID)
        }()
        guard seededSession == nil, seededContext == nil, seededContainer == nil,
              restoredSession == nil, restoredContext == nil, restoredContainer == nil else {
            XCTFail("Restore and seed store aliases must drain before genuine Router startup")
            throw V23EraseOperationHarnessV1.Failure.drainPending
        }
        let owner = V23EraseOperationHarnessV1(retainingRoot: root, applicationSupportURL: target.support,
            runtime: StoreKitEntitlementRuntimeV1(initialEvents: { [] },
                transactionUpdates: { AsyncStream { $0.finish() } },
                statusUpdates: { AsyncStream { $0.finish() } }),
            profileRegistry: try WorkspacePackageLifecycleCompatibilityV1.shippingRegistry())
        let caches = root.appendingPathComponent("caches", isDirectory: true)
        let temporary = root.appendingPathComponent("temporary", isDirectory: true)
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { owner.router.entitlementProcessor?.stop() }
        let suiteName = "C46-R01-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var admittedReservation: AppAccessGateV1.EraseAdoptionToken?
        var completedReceipts: [CompletedEraseReceiptV1] = []
        weak var originalCoordinator: StoreSessionCoordinator?
        weak var originalContext: ModelContext?
        weak var originalContainer: ModelContainer?
        let erase = try await { () async throws -> EraseAllService in
            let (coordinator, diagnostics) = try await owner.startOriginalOwner()
            originalCoordinator = coordinator
            originalContext = coordinator.modelContext
            originalContainer = coordinator.modelContext.container
            XCTAssertEqual(coordinator.generationID, target.generationID)
            guard coordinator.generationID == target.generationID else {
                throw V23EraseOperationHarnessV1.Failure.admission
            }
            try await owner.admit(coordinator: coordinator)
        let erase = try owner.configure(EraseAllService(
            applicationSupportURL: target.support,
            cachesDirectoryURL: caches,
            temporaryDirectoryURL: temporary,
            userDefaults: defaults,
            bundleIdentifier: "com.palatis3.fieldrecord",
            defaultsDomainName: suiteName,
            admitErase: { subject in
                let reservation = try await owner.admitSubject(subject)
                admittedReservation = reservation
                return reservation
            },
            didCompleteErase: { completedReceipts.append($0) }
        ))
        try await owner.prepareCompatibility(service: erase,
            confirmation: EraseAllService.requiredConfirmation, coordinator: coordinator, diagnostics: diagnostics)
        return erase
        }()
        guard originalCoordinator == nil, originalContext == nil, originalContainer == nil else {
            XCTFail("Original contact Erase readers must drain before cleanup")
            throw V23EraseOperationHarnessV1.Failure.drainPending
        }
        XCTAssertTrue(completedReceipts.isEmpty)
        try await owner.completeCleanup()
        XCTAssertEqual(completedReceipts.count, 1)
        let deliveredReceipt = try XCTUnwrap(completedReceipts.first)
        let reservation = try XCTUnwrap(admittedReservation)
        XCTAssertEqual(deliveredReceipt.reservation, reservation)
        XCTAssertEqual(deliveredReceipt.subject, reservation.subject)
        try await owner.adoptCompletedReceipt()
        let token = try await owner.accessGate.beginContentRead(for: .startupRecovery)
        try token.withContentRead(for: .startupRecovery) {
        let erasedSession = try StoreGenerationFactory(applicationSupportURL: target.support).openOrBootstrapCurrent()
        try erase.validateOperationalContactEraseClosure(session: erasedSession)
        XCTAssertTrue(
            try erasedSession.modelContext.fetch(FetchDescriptor<ServiceContactPointRow>()).isEmpty
        )
        XCTAssertTrue(
            try erasedSession.modelContext.fetch(FetchDescriptor<SystemHandoffIntentRow>()).isEmpty
        )
        }
    }
}

final class C32OperationalContactRestoreBoundaryTests: XCTestCase {
    @MainActor
    func testV23P03C46HistoricalIntentAcceptsGenuineC32SuccessorAndRejectsMissingReceipt() async throws {
        let root = try C46OperationalContactTestSupport.temporaryDirectory("c46-c32-history")
        let lifetime = C32RestoreFixtureRetentionV1(root: root)
        let sourceSupport = root.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceSupport, withIntermediateDirectories: true)
        let source = try StoreGenerationFactory(applicationSupportURL: sourceSupport)
            .openOrBootstrapCurrent()
        lifetime.retain(source)
        let writerID = C46OperationalContactTestSupport.id(33_001)
        let journal = try MutationJournalStoreV1(
            modelContext: source.modelContext, identity: source.workspaceIdentity,
            generationID: source.generationID)
        lifetime.retain(journal)
        let writer = try WorkspaceWriterV1(
            identity: source.workspaceIdentity, generationID: source.generationID,
            initialRevision: try journal.currentRevision(writerInstanceID: writerID),
            clock: C46OperationalContactClock(value: C46OperationalContactTestSupport.date(33_001)),
            idSource: C46OperationalContactIDSource(value: writerID),
            fileAuthority: C46OperationalContactFileAuthority(),
            adapter: WorkspaceWriterAdapterV1(modelContext: source.modelContext),
            journalStore: journal)
        lifetime.retain(writer)
        let siteID = C46OperationalContactTestSupport.id(33_002)
        let firstSignID = try C46OperationalContactTestSupport.mutation(33_003)
        _ = try writer.execute(.createFirstSign(.init(
            siteID: siteID,
            newSite: .init(id: siteID, label: "Historical C32 site",
                           address: nil, timeZoneID: "UTC"),
            assetID: C46OperationalContactTestSupport.id(33_004),
            assetLabel: "Historical C32 asset",
            packID: SignPack.illuminatedSignV1.packID,
            packSchemaVersion: SignPack.illuminatedSignV1.schemaVersion,
            packContentVersion: SignPack.illuminatedSignV1.contentVersion,
            createdAt: C46OperationalContactTestSupport.date(33_004),
            initialPlacementMutationID: firstSignID,
            initialPlacementEventID: C46OperationalContactTestSupport.id(33_005),
            initialPhysicalEpisodeID: try PhysicalPlacementEpisodeIDV1(
                rawValue: C46OperationalContactTestSupport.id(33_006))
        )), mutationID: firstSignID)

        let party = try C46OperationalContactTestSupport.party(
            slot: 33_010, workspaceID: source.workspaceID)
        _ = try writer.execute(.applyPartyAccountability(.recordParty(party)),
                               mutationID: party.mutationID)
        let contactMutationID = try C46OperationalContactTestSupport.mutation(33_020)
        let contactID = C46OperationalContactTestSupport.id(33_022)
        let contact = try ServiceContactPointV1(
            contactPointID: contactID, workspaceID: source.workspaceID,
            party: party, kind: .email, label: .office,
            displayValue: "historical.c32@example.test", preferred: true,
            provenance: .manual, lifecycle: .effective,
            effectiveAt: C46OperationalContactTestSupport.date(33_020),
            revision: 1, mutationID: contactMutationID)
        let intent = try C46OperationalContactTestSupport.intent(
            slot: 33_021, kind: .email, contact: contact)
        let beforeContact = try writer.currentRevision()
        let contactExpected = try WorkspaceExpectedRevisionV1(
            workspaceID: beforeContact.workspaceID,
            generationID: beforeContact.generationID,
            writerInstanceID: beforeContact.writerInstanceID,
            workspaceRevision: beforeContact.revision,
            entityRevisions: beforeContact.entityRevisions + [
                .init(identity: try .init(kind: .serviceContactPoint, id: contactID), revision: 0),
                .init(identity: try .init(kind: .systemHandoffIntent, id: intent.intentID), revision: 0),
            ])
        let direct = try OperationalContactMutationV1(
            workspaceID: source.workspaceID, mutationID: contactMutationID,
            expectedRevision: contactExpected, successors: [contact],
            preferredScopes: [try .init(
                partyID: party.partyID, kind: .email,
                activeContactPointIDs: [contactID], preferredContactPointID: contactID)],
            handoffIntents: [intent])
        _ = try await writer.commitOperationalContact(direct)

        let aggregateID = try C46OperationalContactTestSupport.mutation(33_030)
        let partySuccessor = try ServicePartyReferenceV1(
            partyID: party.partyID, workspaceID: party.workspaceID,
            kind: party.kind, displayName: "Historical C32 successor party",
            profileDescriptor: party.profileDescriptor,
            provenance: .importedExternalEvidence, state: .effective,
            effectiveAt: party.effectiveAt, revision: 2, mutationID: aggregateID)
        try partySuccessor.validateSuccessor(of: party)
        let importedSet = try ImportSourceSetV1(
            workspaceID: source.workspaceID, files: [try .init(
                schemaID: PartyContactCSVRowV1.schemaID,
                schemaVersion: PartyContactCSVRowV1.schemaVersion,
                fileName: "party-contacts.csv", orderIndex: 0,
                byteCount: 1, sha256: String(repeating: "a", count: 64))])
        let successor = try ServiceContactPointV1(
            contactPointID: contactID, workspaceID: source.workspaceID,
            party: partySuccessor, kind: contact.kind, label: .work,
            displayValue: contact.displayValue, preferred: true,
            provenance: .importedExternalEvidence,
            importSourceSetSHA256: importedSet.sourceSetSHA256,
            lifecycle: .effective, effectiveAt: contact.effectiveAt,
            revision: 2, supersedes: contact.revisionReference,
            mutationID: aggregateID)
        let roleID = C46OperationalContactTestSupport.id(33_031)
        let role = try SitePartyRoleEventV1(
            eventID: roleID, workspaceID: source.workspaceID,
            siteID: siteID, partyID: party.partyID,
            role: .serviceProvider,
            effectiveFrom: C46OperationalContactTestSupport.date(33_030),
            source: .importedExternalEvidence, revision: 1,
            mutationID: aggregateID,
            recordedAt: C46OperationalContactTestSupport.date(33_030))
        let beforeAggregate = try writer.currentRevision()
        let aggregateExpected = try WorkspaceExpectedRevisionV1(
            workspaceID: beforeAggregate.workspaceID,
            generationID: beforeAggregate.generationID,
            writerInstanceID: beforeAggregate.writerInstanceID,
            workspaceRevision: beforeAggregate.revision,
            entityRevisions: beforeAggregate.entityRevisions + [
                .init(identity: try .init(kind: .sitePartyRoleEvent, id: roleID), revision: 0),
            ])
        let contactSuccessorMutation = try OperationalContactMutationV1(
            workspaceID: source.workspaceID, mutationID: aggregateID,
            expectedRevision: aggregateExpected,
            predecessors: [contact], successors: [successor],
            preferredScopes: [try .init(
                partyID: party.partyID, kind: .email,
                activeContactPointIDs: [contactID], preferredContactPointID: contactID)],
            importSourceSet: importedSet)
        let aggregate = try PartyContactSiteRoleImportMutationV1(
            workspaceID: source.workspaceID, mutationID: aggregateID,
            expectedRevision: aggregateExpected,
            partyMutations: [.recordParty(partySuccessor)],
            operationalContactMutation: contactSuccessorMutation,
            siteRoleMutations: [.appendSiteRole(role)])
        _ = try writer.execute(aggregate.canonicalWorkspaceMutationRequest())
        let aggregateReceipt = try XCTUnwrap(try writer.durableReceipt(mutationID: aggregateID))
        _ = try PartyContactSiteRoleImportMutationReceiptV1(
            mutation: aggregate, mutationReceipt: aggregateReceipt)
        try journal.validateAll()
        let sourceHistory = try journal.exportSnapshot()
        let sourceContactBytes = try XCTUnwrap(source.modelContext.fetch(
            FetchDescriptor<ServiceContactPointRow>()).first).canonicalData
        let sourceIntentBytes = try XCTUnwrap(source.modelContext.fetch(
            FetchDescriptor<SystemHandoffIntentRow>()).first).canonicalData

        let exportRoot = root.appendingPathComponent("export", isDirectory: true)
        try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: true)
        let exporter = BackupExportService(
            modelContext: source.modelContext,
            generationRootURL: source.generationRootURL,
            now: { C46OperationalContactTestSupport.date(33_040) })
        lifetime.retain(exporter)
        let package = try exporter.export(previewID: exporter.prepare().id, to: exportRoot)
        let targetSupport = root.appendingPathComponent("target", isDirectory: true)
        try FileManager.default.createDirectory(at: targetSupport, withIntermediateDirectories: true)
        let target = try StoreGenerationFactory(applicationSupportURL: targetSupport)
            .openOrBootstrapCurrent()
        lifetime.retain(target)
        let validated = try BackupImportService(
            generationRootURL: target.generationRootURL,
            makeUUID: { C46OperationalContactTestSupport.id(33_041) },
            scopedAccess: .alreadyAuthorized
        ).stageAndValidate(selectedPackageURL: package)
        lifetime.retain(validated)
        let values = try validated.records.validateC46OperationalContacts()
        XCTAssertEqual(values.contacts, [successor])
        XCTAssertEqual(values.intents, [intent])
        XCTAssertEqual(try validated.records.validateC32PartyContactSiteRoleImportClosure(),
                       [aggregate])
        XCTAssertEqual(intent.target.expectedRevision, 1)
        XCTAssertEqual(successor.revision, 2)

        let history = try XCTUnwrap(validated.records.mutationHistory)
        let withoutAggregate = MutationHistorySnapshotV1(
            workspaceRevision: history.workspaceRevision,
            lastLocalSequence: history.lastLocalSequence,
            receipts: try history.receipts.filter { record in
                let envelope = try MutationEnvelopeV1.decodeCanonical(from: record.envelopeData)
                return envelope.mutationID != aggregateID
            },
            quarantines: history.quarantines,
            entityRevisions: history.entityRevisions)
        XCTAssertEqual(withoutAggregate.receipts.count + 1, history.receipts.count)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var hostileObject = try XCTUnwrap(JSONSerialization.jsonObject(
            with: encoder.encode(validated.records)) as? [String: Any])
        hostileObject["mutationHistory"] = try JSONSerialization.jsonObject(
            with: encoder.encode(withoutAggregate))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let hostile = try decoder.decode(V4BackupRecordsV1.self,
            from: JSONSerialization.data(withJSONObject: hostileObject,
                options: [.sortedKeys, .fragmentsAllowed]))
        XCTAssertEqual(hostile.mutationHistory, withoutAggregate)
        XCTAssertThrowsError(try hostile.validateC46OperationalContacts())

        let restore = try BackupRestoreService(
            applicationSupportURL: targetSupport,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in .max }))
        lifetime.retain(restore)
        let restored = try await restore.restore(
            validatedPackage: validated,
            currentModelContext: target.modelContext,
            currentGenerationID: target.generationID,
            currentGenerationRootURL: target.generationRootURL,
            mode: .emptyInstall)
        lifetime.retain(restored)
        let restoredContact = try XCTUnwrap(restored.modelContext.fetch(
            FetchDescriptor<ServiceContactPointRow>()).first)
        let restoredIntent = try XCTUnwrap(restored.modelContext.fetch(
            FetchDescriptor<SystemHandoffIntentRow>()).first)
        XCTAssertEqual(restoredContact.canonicalData, sourceContactBytes)
        XCTAssertEqual(restoredIntent.canonicalData, sourceIntentBytes)
        XCTAssertEqual(try restoredContact.value(), successor)
        XCTAssertEqual(try restoredIntent.value(), intent)
        let restoredJournal = try MutationJournalStoreV1(
            modelContext: restored.modelContext,
            identity: restored.workspaceIdentity,
            generationID: restored.generationID,
            allowStateBootstrap: false)
        lifetime.retain(restoredJournal)
        let restoredHistory = try restoredJournal.exportSnapshot()
        XCTAssertGreaterThan(sourceHistory.lastLocalSequence, 0)
        XCTAssertEqual(restoredHistory.schemaVersion, sourceHistory.schemaVersion)
        XCTAssertEqual(restoredHistory.workspaceRevision, sourceHistory.workspaceRevision)
        XCTAssertEqual(restoredHistory.lastLocalSequence, 0)
        XCTAssertEqual(restoredHistory.receipts, sourceHistory.receipts)
        XCTAssertEqual(restoredHistory.quarantines, sourceHistory.quarantines)
        XCTAssertEqual(restoredHistory.entityRevisions, sourceHistory.entityRevisions)

        // The same authentic direct rev1 -> C32 aggregate rev2 history must
        // close over destination rows on clone while the source receipts stay
        // byte-identical historical provenance. Removing the source aggregate
        // above remains a fail-closed hostile input for either restore mode.
        let cloneSupport = root.appendingPathComponent("clone", isDirectory: true)
        try FileManager.default.createDirectory(
            at: cloneSupport, withIntermediateDirectories: true
        )
        let cloneCurrent = try StoreGenerationFactory(
            applicationSupportURL: cloneSupport
        ).openOrBootstrapCurrent()
        lifetime.retain(cloneCurrent)
        let clonePackage = try BackupImportService(
            generationRootURL: cloneCurrent.generationRootURL,
            makeUUID: { C46OperationalContactTestSupport.id(33_042) },
            scopedAccess: .alreadyAuthorized
        ).stageAndValidate(selectedPackageURL: package)
        lifetime.retain(clonePackage)
        let cloneService = try BackupRestoreService(
            applicationSupportURL: cloneSupport,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in .max })
        )
        lifetime.retain(cloneService)
        let clone = try await cloneService.restore(
            validatedPackage: clonePackage,
            currentModelContext: cloneCurrent.modelContext,
            currentGenerationID: cloneCurrent.generationID,
            currentGenerationRootURL: cloneCurrent.generationRootURL,
            mode: .clone
        )
        lifetime.retain(clone)
        let clonedContact = try XCTUnwrap(clone.modelContext.fetch(
            FetchDescriptor<ServiceContactPointRow>()).first).value()
        let clonedIntent = try XCTUnwrap(clone.modelContext.fetch(
            FetchDescriptor<SystemHandoffIntentRow>()).first).value()
        XCTAssertEqual(clonedContact.workspaceID, clone.workspaceID)
        XCTAssertEqual(clonedContact.revision, successor.revision)
        XCTAssertEqual(clonedContact.displayValue, successor.displayValue)
        XCTAssertNotEqual(clonedContact.contactPointSHA256, successor.contactPointSHA256)
        XCTAssertEqual(clonedIntent.workspaceID, clone.workspaceID)
        XCTAssertEqual(clonedIntent.disposition, .historicReferenceOnly)
        XCTAssertEqual(clonedIntent.target, intent.target)
        let cloneQuery = OperationalContactRowQueryV1(
            modelContext: clone.modelContext, workspaceID: clone.workspaceID
        )
        let cloneHandoff = await cloneQuery.resolveForHandoff(clonedIntent)
        XCTAssertEqual(cloneHandoff, .targetInvalid)
        let cloneJournal = try MutationJournalStoreV1(
            modelContext: clone.modelContext,
            identity: clone.workspaceIdentity,
            generationID: clone.generationID,
            allowStateBootstrap: false
        )
        lifetime.retain(cloneJournal)
        try cloneJournal.validateAll()
        var cloneHistory = try cloneJournal.exportSnapshot()
        let retainedSource = try cloneHistory.receipts.filter { record in
            let envelope = try MutationEnvelopeV1.decodeCanonical(
                from: record.envelopeData
            )
            return envelope.workspaceID == source.workspaceIdentity.workspaceID
        }
        XCTAssertEqual(retainedSource, sourceHistory.receipts)
        let targetContactReceipts = try cloneHistory.receipts.compactMap {
            record -> MutationReceiptV1? in
            let envelope = try MutationEnvelopeV1.decodeCanonical(
                from: record.envelopeData
            )
            guard envelope.workspaceID == clone.workspaceIdentity.workspaceID else {
                return nil
            }
            switch envelope.command {
            case let .applyOperationalContact(mutation):
                let receipt = try MutationReceiptV1.decodeCanonical(
                    from: record.receiptData
                )
                _ = try OperationalContactMutationReceiptV1(
                    mutation: mutation, mutationReceipt: receipt
                )
                return receipt
            case let .applyPartyContactSiteRoleImport(mutation):
                let receipt = try MutationReceiptV1.decodeCanonical(
                    from: record.receiptData
                )
                _ = try PartyContactSiteRoleImportMutationReceiptV1(
                    mutation: mutation, mutationReceipt: receipt
                )
                XCTAssertEqual(mutation.operationalContactMutation.successors,
                    [clonedContact])
                return receipt
            default:
                return nil
            }
        }
        XCTAssertEqual(targetContactReceipts.count, 2)
        XCTAssertTrue(targetContactReceipts.allSatisfy {
            $0.sourceKind == .importedHistory
                && $0.identity.replicaID != clone.workspaceIdentity.replicaID
        })
        // A genuine imported aggregate from a foreign workspace is not row
        // authority in the original source workspace. It has no projection
        // successor leading back to those current rows and must be refused.
        hostileObject["mutationHistory"] = try JSONSerialization.jsonObject(
            with: encoder.encode(cloneHistory)
        )
        let foreignAggregate = try decoder.decode(V4BackupRecordsV1.self,
            from: JSONSerialization.data(withJSONObject: hostileObject,
                options: [.sortedKeys, .fragmentsAllowed]))
        XCTAssertThrowsError(try foreignAggregate.validateC32PartyContactSiteRoleImportClosure())

        // A genuine direct command after the C32 aggregate retains the
        // aggregate-produced Party. The next clone must map that Party's
        // mutation provenance to the next imported aggregate, rather than
        // restoring a stale source-workspace Party ID.
        let cloneWriterID = C46OperationalContactTestSupport.id(33_060)
        let cloneWriter = try WorkspaceWriterV1(
            identity: clone.workspaceIdentity,
            generationID: clone.generationID,
            initialRevision: try cloneJournal.currentRevision(
                writerInstanceID: cloneWriterID),
            clock: C46OperationalContactClock(
                value: C46OperationalContactTestSupport.date(33_060)),
            idSource: C46OperationalContactIDSource(value: cloneWriterID),
            fileAuthority: C46OperationalContactFileAuthority(),
            adapter: WorkspaceWriterAdapterV1(modelContext: clone.modelContext),
            journalStore: cloneJournal)
        lifetime.retain(cloneWriter)
        let afterAggregateMutationID = try C46OperationalContactTestSupport.mutation(33_061)
        let afterAggregateContact = try ServiceContactPointV1(
            contactPointID: clonedContact.contactPointID,
            workspaceID: clone.workspaceID,
            party: clonedContact.party,
            kind: clonedContact.kind,
            label: .office,
            displayValue: "after.c32@example.test",
            preferred: true,
            provenance: .manual,
            lifecycle: .effective,
            effectiveAt: C46OperationalContactTestSupport.date(33_061),
            revision: clonedContact.revision + 1,
            supersedes: clonedContact.revisionReference,
            mutationID: afterAggregateMutationID)
        let beforeAfterAggregate = try cloneWriter.currentRevision()
        let afterAggregateExpected = try WorkspaceExpectedRevisionV1(
            workspaceID: beforeAfterAggregate.workspaceID,
            generationID: beforeAfterAggregate.generationID,
            writerInstanceID: beforeAfterAggregate.writerInstanceID,
            workspaceRevision: beforeAfterAggregate.revision,
            entityRevisions: beforeAfterAggregate.entityRevisions)
        let afterAggregateCommand = try OperationalContactMutationV1(
            workspaceID: clone.workspaceID,
            mutationID: afterAggregateMutationID,
            expectedRevision: afterAggregateExpected,
            predecessors: [clonedContact],
            successors: [afterAggregateContact],
            preferredScopes: [try .init(
                partyID: clonedContact.party.partyID,
                kind: clonedContact.kind,
                activeContactPointIDs: [clonedContact.contactPointID],
                preferredContactPointID: clonedContact.contactPointID)])
        _ = try await cloneWriter.commitOperationalContact(afterAggregateCommand)
        try cloneJournal.validateAll()
        cloneHistory = try cloneJournal.exportSnapshot()

        // A second real clone makes the first imported C32 projection a
        // historical source. It must remain valid through an exact second
        // projection rather than gaining row authority by workspace alone.
        let secondExportRoot = root.appendingPathComponent(
            "second-export", isDirectory: true)
        try FileManager.default.createDirectory(
            at: secondExportRoot, withIntermediateDirectories: true)
        let secondExporter = BackupExportService(
            modelContext: clone.modelContext,
            generationRootURL: clone.generationRootURL,
            now: { C46OperationalContactTestSupport.date(33_050) })
        lifetime.retain(secondExporter)
        let secondPackage = try secondExporter.export(
            previewID: secondExporter.prepare().id, to: secondExportRoot)
        let secondCloneSupport = root.appendingPathComponent(
            "second-clone", isDirectory: true)
        try FileManager.default.createDirectory(
            at: secondCloneSupport, withIntermediateDirectories: true)
        let secondCurrent = try StoreGenerationFactory(
            applicationSupportURL: secondCloneSupport).openOrBootstrapCurrent()
        lifetime.retain(secondCurrent)
        let secondValidated = try BackupImportService(
            generationRootURL: secondCurrent.generationRootURL,
            makeUUID: { C46OperationalContactTestSupport.id(33_051) },
            scopedAccess: .alreadyAuthorized
        ).stageAndValidate(selectedPackageURL: secondPackage)
        lifetime.retain(secondValidated)
        let secondService = try BackupRestoreService(
            applicationSupportURL: secondCloneSupport,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in .max }))
        lifetime.retain(secondService)
        let secondClone = try await secondService.restore(
            validatedPackage: secondValidated,
            currentModelContext: secondCurrent.modelContext,
            currentGenerationID: secondCurrent.generationID,
            currentGenerationRootURL: secondCurrent.generationRootURL,
            mode: .clone)
        lifetime.retain(secondClone)
        let secondCloneJournal = try MutationJournalStoreV1(
            modelContext: secondClone.modelContext,
            identity: secondClone.workspaceIdentity,
            generationID: secondClone.generationID,
            allowStateBootstrap: false)
        lifetime.retain(secondCloneJournal)
        try secondCloneJournal.validateAll()
        let secondCloneHistory = try secondCloneJournal.exportSnapshot()
        let secondClonedContact = try XCTUnwrap(secondClone.modelContext.fetch(
            FetchDescriptor<ServiceContactPointRow>()).first).value()
        XCTAssertEqual(secondClonedContact.revision, afterAggregateContact.revision)
        XCTAssertEqual(secondClonedContact.displayValue,
                       afterAggregateContact.displayValue)
        XCTAssertNotEqual(secondClonedContact.party.mutationID,
                          afterAggregateContact.party.mutationID)
        let retainedFirstCloneReceipts = try secondCloneHistory.receipts.filter { record in
            try MutationEnvelopeV1.decodeCanonical(
                from: record.envelopeData).workspaceID == clone.workspaceID
        }
        let firstCloneReceipts = try cloneHistory.receipts.filter { record in
            try MutationEnvelopeV1.decodeCanonical(
                from: record.envelopeData).workspaceID == clone.workspaceID
        }
        XCTAssertEqual(retainedFirstCloneReceipts, firstCloneReceipts)
        let secondClonedIntent = try XCTUnwrap(secondClone.modelContext.fetch(
            FetchDescriptor<SystemHandoffIntentRow>()).first).value()
        XCTAssertEqual(secondClonedIntent.disposition, .historicReferenceOnly)
        XCTAssertEqual(secondClonedIntent.target, intent.target)
        let secondCloneHandoff = await OperationalContactRowQueryV1(
            modelContext: secondClone.modelContext,
            workspaceID: secondClone.workspaceID
        ).resolveForHandoff(secondClonedIntent)
        XCTAssertEqual(secondCloneHandoff, .targetInvalid)

        // Reissue one internally typed, canonical *historical* imported C32
        // receipt with a successor Party mutation ID unrelated to its Party
        // child. Its bytes and receipt digest are self-consistent; the exact
        // source-to-target Party producer chain must still refuse it.
        let secondArchiveRoot = root.appendingPathComponent(
            "second-archive", isDirectory: true)
        try FileManager.default.createDirectory(
            at: secondArchiveRoot, withIntermediateDirectories: true)
        let secondArchiveExporter = BackupExportService(
            modelContext: secondClone.modelContext,
            generationRootURL: secondClone.generationRootURL,
            now: { C46OperationalContactTestSupport.date(33_052) })
        lifetime.retain(secondArchiveExporter)
        let secondArchive = try secondArchiveExporter.export(
            previewID: secondArchiveExporter.prepare().id, to: secondArchiveRoot)
        let archiveStaging = try BackupImportService(
            generationRootURL: secondClone.generationRootURL,
            makeUUID: { C46OperationalContactTestSupport.id(33_053) },
            scopedAccess: .alreadyAuthorized
        ).stageAndValidate(selectedPackageURL: secondArchive)
        lifetime.retain(archiveStaging)
        let historicalIndex = try XCTUnwrap(secondCloneHistory.receipts.firstIndex {
            let envelope = try MutationEnvelopeV1.decodeCanonical(
                from: $0.envelopeData)
            return envelope.workspaceID == clone.workspaceID
                && envelope.sourceKind == .importedHistory
                && envelope.command.kind == .applyPartyContactSiteRoleImport
        })
        let historicalRecord = secondCloneHistory.receipts[historicalIndex]
        let historicalEnvelope = try MutationEnvelopeV1.decodeCanonical(
            from: historicalRecord.envelopeData)
        let historicalReceipt = try MutationReceiptV1.decodeCanonical(
            from: historicalRecord.receiptData)
        guard case let .applyPartyContactSiteRoleImport(historicalMutation)
                = historicalEnvelope.command else {
            throw OperationalContactFailureV1.digestMismatch
        }
        let historicalContact = historicalMutation.operationalContactMutation
        let priorSuccessor = try XCTUnwrap(historicalContact.successors.first)
        let priorParty = priorSuccessor.party
        let falseParty = try ServicePartyReferenceV1(
            partyID: priorParty.partyID,
            workspaceID: priorParty.workspaceID,
            kind: priorParty.kind,
            displayName: priorParty.displayName,
            profileDescriptor: priorParty.profileDescriptor,
            provenance: priorParty.provenance,
            privacyClass: priorParty.privacyClass,
            state: priorParty.state,
            effectiveAt: priorParty.effectiveAt,
            retiredAt: priorParty.retiredAt,
            revision: priorParty.revision,
            mutationID: C46OperationalContactTestSupport.mutation(33_054))
        let falseSuccessor = try ServiceContactPointV1(
            contactPointID: priorSuccessor.contactPointID,
            workspaceID: priorSuccessor.workspaceID,
            party: falseParty,
            kind: priorSuccessor.kind,
            label: priorSuccessor.label,
            displayValue: priorSuccessor.displayValue,
            preferred: priorSuccessor.preferred,
            provenance: priorSuccessor.provenance,
            importSourceSetSHA256: priorSuccessor.importSourceSetSHA256,
            privacyClass: priorSuccessor.privacyClass,
            lifecycle: priorSuccessor.lifecycle,
            effectiveAt: priorSuccessor.effectiveAt,
            retiredAt: priorSuccessor.retiredAt,
            revision: priorSuccessor.revision,
            supersedes: priorSuccessor.supersedes,
            mutationID: priorSuccessor.mutationID)
        let falseContactMutation = try OperationalContactMutationV1(
            workspaceID: historicalContact.workspaceID,
            mutationID: historicalContact.mutationID,
            expectedRevision: historicalContact.expectedRevision,
            predecessors: historicalContact.predecessors,
            successors: [falseSuccessor],
            preferredScopes: historicalContact.preferredScopes,
            handoffIntents: historicalContact.handoffIntents,
            importSourceSet: historicalContact.importSourceSet)
        let falseAggregate = try PartyContactSiteRoleImportMutationV1(
            workspaceID: historicalMutation.workspaceID,
            mutationID: historicalMutation.mutationID,
            expectedRevision: historicalMutation.expectedRevision,
            partyMutations: historicalMutation.partyMutations,
            operationalContactMutation: falseContactMutation,
            siteRoleMutations: historicalMutation.siteRoleMutations)
        let falseEnvelope = try MutationEnvelopeV1(
            request: falseAggregate.canonicalWorkspaceMutationRequest(),
            identity: WorkspaceReplicaIdentityV1(
                workspaceID: historicalEnvelope.workspaceID,
                replicaID: historicalEnvelope.replicaID),
            sourceKind: historicalEnvelope.sourceKind,
            contentDependencyIDs: historicalEnvelope.contentDependencyIDs,
            causationMutationID: historicalEnvelope.causationMutationID,
            correlationID: historicalEnvelope.correlationID)
        let falseReceipt = try MutationReceiptV1(
            identity: historicalReceipt.identity,
            envelope: falseEnvelope,
            resultingRevision: historicalReceipt.resultingRevision,
            postImages: falseAggregate.mutationPostImages,
            committedAt: historicalReceipt.committedAt)
        _ = try PartyContactSiteRoleImportMutationReceiptV1(
            mutation: falseAggregate, mutationReceipt: falseReceipt)
        var falseReceipts = secondCloneHistory.receipts
        falseReceipts[historicalIndex] = .init(
            envelopeData: try falseEnvelope.canonicalData(),
            receiptData: try falseReceipt.canonicalData(),
            reversalBasisData: nil,
            semanticReversalData: nil)
        let falseHistory = MutationHistorySnapshotV1(
            workspaceRevision: secondCloneHistory.workspaceRevision,
            lastLocalSequence: secondCloneHistory.lastLocalSequence,
            receipts: falseReceipts,
            quarantines: secondCloneHistory.quarantines,
            entityRevisions: secondCloneHistory.entityRevisions)
        var falseObject = try XCTUnwrap(JSONSerialization.jsonObject(
            with: encoder.encode(archiveStaging.records)) as? [String: Any])
        falseObject["mutationHistory"] = try JSONSerialization.jsonObject(
            with: encoder.encode(falseHistory))
        let falseArchive = try decoder.decode(V4BackupRecordsV1.self,
            from: JSONSerialization.data(withJSONObject: falseObject,
                options: [.sortedKeys, .fragmentsAllowed]))
        XCTAssertThrowsError(try falseArchive.validateC32PartyContactSiteRoleImportClosure())
    }

    @MainActor
    func testV23P04C32RestoreRebindsOneAggregateReceiptWithoutContactFanout() async throws {
        let root = try C46OperationalContactTestSupport.temporaryDirectory("c32-restore")
        // The interrupted restore and its sessions may retain pinned controls.
        // Preserve their real owners and root until the test host terminates.
        let fixtureLifetime = C32RestoreFixtureRetentionV1(root: root)

        let sourceSupport = root.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceSupport, withIntermediateDirectories: true)
        let source = try StoreGenerationFactory(applicationSupportURL: sourceSupport)
            .openOrBootstrapCurrent()
        fixtureLifetime.retain(source)
        let sourceWriterInstanceID = C46OperationalContactTestSupport.id(32_001)
        let sourceJournal = try MutationJournalStoreV1(
            modelContext: source.modelContext,
            identity: source.workspaceIdentity,
            generationID: source.generationID
        )
        fixtureLifetime.retain(sourceJournal)
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
        fixtureLifetime.retain(sourceWriter)
        let siteID = C46OperationalContactTestSupport.id(32_002)
        let firstSignMutationID = try C46OperationalContactTestSupport.mutation(32_003)
        _ = try sourceWriter.execute(.createFirstSign(.init(
                siteID: siteID,
                newSite: .init(
                    id: siteID,
                    label: "C32 restore site",
                    address: nil,
                    timeZoneID: "UTC"
                ),
                assetID: C46OperationalContactTestSupport.id(32_004),
                assetLabel: "C32 restore seed",
                packID: SignPack.illuminatedSignV1.packID,
                packSchemaVersion: SignPack.illuminatedSignV1.schemaVersion,
                packContentVersion: SignPack.illuminatedSignV1.contentVersion,
                createdAt: C46OperationalContactTestSupport.date(32_004),
                initialPlacementMutationID: firstSignMutationID,
                initialPlacementEventID: C46OperationalContactTestSupport.id(32_005),
                initialPhysicalEpisodeID: try PhysicalPlacementEpisodeIDV1(
                    rawValue: C46OperationalContactTestSupport.id(32_006))
            )), mutationID: firstSignMutationID)

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
        fixtureLifetime.retain(target)
        XCTAssertNotEqual(target.workspaceID, source.workspaceID)
        let retainedParty = try C46OperationalContactTestSupport.party(
            slot: 32_030,
            workspaceID: target.workspaceID
        )
        let retainedWriterInstanceID = C46OperationalContactTestSupport.id(32_031)
        let retainedJournal = try MutationJournalStoreV1(
            modelContext: target.modelContext,
            identity: target.workspaceIdentity,
            generationID: target.generationID
        )
        fixtureLifetime.retain(retainedJournal)
        let retainedRevision = try retainedJournal.currentRevision(
            writerInstanceID: retainedWriterInstanceID
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
        fixtureLifetime.retain(retainedWriter)
        _ = try retainedWriter.execute(.applyPartyAccountability(.recordParty(retainedParty)),
            mutationID: retainedParty.mutationID)
        XCTAssertNotNil(try retainedWriter.durableReceipt(mutationID: retainedParty.mutationID))
        let retainedContactRevision = try retainedWriter.currentRevision()
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
            workspaceID: retainedContactRevision.workspaceID,
            generationID: retainedContactRevision.generationID,
            writerInstanceID: retainedContactRevision.writerInstanceID,
            workspaceRevision: retainedContactRevision.revision,
            entityRevisions: retainedContactRevision.entityRevisions + [
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
        _ = try await retainedWriter.commitOperationalContact(retainedMutation)
        let originalTargetHistory = try retainedJournal.exportSnapshot()
        try MutationJournalStoreV1.validateImportedSnapshot(originalTargetHistory)
        let originalTargetParties = try target.modelContext
            .fetch(FetchDescriptor<ServicePartyRow>()).map { try $0.value() }
        let originalTargetContacts = try target.modelContext
            .fetch(FetchDescriptor<ServiceContactPointRow>()).map { try $0.value() }
        let pointerURL = targetSupport.appendingPathComponent("FieldEvidenceData/current.json")
        let originalPointerBytes = try Data(contentsOf: pointerURL)
        XCTAssertEqual(try CurrentPointerCodecV1.decode(originalPointerBytes).generationID,
                       target.generationID.uuidString.lowercased())
        let intentStore = try RestoreIntentStore(applicationSupportURL: targetSupport)
        fixtureLifetime.retain(intentStore)
        XCTAssertNil(try intentStore.load())
        let originalRetainedPartyRecord = try XCTUnwrap(originalTargetHistory.receipts.first {
            guard let envelope = try? MutationEnvelopeV1.decodeCanonical(
                from: $0.envelopeData
            ) else { return false }
            return envelope.workspaceID == target.workspaceID
                && envelope.command.kind == .applyPartyAccountability
        })
        let originalRetainedContactRecord = try XCTUnwrap(originalTargetHistory.receipts.first {
            guard let envelope = try? MutationEnvelopeV1.decodeCanonical(
                from: $0.envelopeData
            ) else { return false }
            return envelope.workspaceID == target.workspaceID
                && envelope.command.kind == .applyOperationalContact
        })

        let validated = try BackupImportService(
            generationRootURL: target.generationRootURL,
            makeUUID: { C46OperationalContactTestSupport.id(32_040) },
            scopedAccess: .alreadyAuthorized
        ).stageAndValidate(selectedPackageURL: package)
        XCTAssertEqual(
            try validated.records.validateC32PartyContactSiteRoleImportClosure(),
            [sourceMutation]
        )
        fixtureLifetime.retain(validated)
        let firstGenerationID = C46OperationalContactTestSupport.id(32_050)
        let firstRestoreID = C46OperationalContactTestSupport.id(32_051)
        var firstRestoreIDs = [firstGenerationID, firstRestoreID]
        let interruptedRestore = try BackupRestoreService(
            applicationSupportURL: targetSupport,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in .max }),
            makeUUID: {
                guard !firstRestoreIDs.isEmpty else {
                    XCTFail("The first restore requested an unexpected additional identity")
                    return UUID()
                }
                return firstRestoreIDs.removeFirst()
            },
            failureInjection: BackupRestoreFailureInjection(failOnceAt: .beforePointerSwitch)
        )
        fixtureLifetime.retain(interruptedRestore)
        interruptedRestore.restorePhaseDiagnosticForTesting = { phase in
            FileHandle.standardError.write(Data("C32_RESTORE_PHASE_V1 \(phase)\n".utf8))
        }
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
        let firstIntent = try XCTUnwrap(try intentStore.load())
        XCTAssertEqual(firstIntent.phase, .generationInstalled)
        XCTAssertEqual(firstIntent.oldGenerationID, target.generationID)
        XCTAssertEqual(firstIntent.newGenerationID, firstGenerationID)
        XCTAssertEqual(firstIntent.restoreID, firstRestoreID)
        XCTAssertEqual(try Data(contentsOf: pointerURL), originalPointerBytes)
        let discardedGenerationURL = targetSupport
            .appendingPathComponent(firstIntent.newGenerationRelativePath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: discardedGenerationURL.path))
        let firstRecovery = try BackupRestoreService(
            applicationSupportURL: targetSupport,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in .max })
        )
        fixtureLifetime.retain(firstRecovery)
        XCTAssertNil(try firstRecovery.reconcileAtStartup(),
                     "Pre-publication recovery discards the replacement and keeps the old canonical store")
        XCTAssertNil(try intentStore.load())
        XCTAssertEqual(try Data(contentsOf: pointerURL), originalPointerBytes)
        XCTAssertEqual(try retainedJournal.exportSnapshot(), originalTargetHistory)
        XCTAssertEqual(try target.modelContext.fetch(FetchDescriptor<ServicePartyRow>())
            .map { try $0.value() }, originalTargetParties)
        XCTAssertEqual(try target.modelContext.fetch(FetchDescriptor<ServiceContactPointRow>())
            .map { try $0.value() }, originalTargetContacts)
        XCTAssertFalse(FileManager.default.fileExists(atPath: discardedGenerationURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: targetSupport
            .appendingPathComponent(firstIntent.stagingGenerationRelativePath).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: targetSupport
            .appendingPathComponent("FieldEvidenceRestore/portable-exchange-restore.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: targetSupport
            .appendingPathComponent("FieldEvidenceRestore/draft-publication-\(firstRestoreID.uuidString.lowercased()).json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: validated.stagedPackageURL.path))

        // The first import staging package was consumed by the interrupted
        // operation. Revalidate the same exported package as a new operation.
        let secondValidated = try BackupImportService(
            generationRootURL: target.generationRootURL,
            makeUUID: { C46OperationalContactTestSupport.id(32_041) },
            scopedAccess: .alreadyAuthorized
        ).stageAndValidate(selectedPackageURL: package)
        fixtureLifetime.retain(secondValidated)
        XCTAssertNotEqual(secondValidated.stagedPackageURL, validated.stagedPackageURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondValidated.stagedPackageURL.path))
        XCTAssertEqual(try secondValidated.records.validateC32PartyContactSiteRoleImportClosure(),
                       [sourceMutation])
        let secondGenerationID = C46OperationalContactTestSupport.id(32_052)
        let secondRestoreID = C46OperationalContactTestSupport.id(32_053)
        var secondRestoreIDs = [secondGenerationID, secondRestoreID]
        let publishedRestore = try BackupRestoreService(
            applicationSupportURL: targetSupport,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in .max }),
            makeUUID: {
                guard !secondRestoreIDs.isEmpty else {
                    XCTFail("The second restore requested an unexpected additional identity")
                    return UUID()
                }
                return secondRestoreIDs.removeFirst()
            },
            failureInjection: BackupRestoreFailureInjection(failOnceAt: .afterPointerSwitch)
        )
        fixtureLifetime.retain(publishedRestore)
        do {
            _ = try await publishedRestore.restore(
                validatedPackage: secondValidated,
                currentModelContext: target.modelContext,
                currentGenerationID: target.generationID,
                currentGenerationRootURL: target.generationRootURL,
                mode: .replaceExisting
            )
            XCTFail("Post-publication injected interruption must not report success")
        } catch {
            XCTAssertEqual(error as? BackupRestoreServiceError, .injectedFailure)
        }
        let secondIntent = try XCTUnwrap(try intentStore.load())
        XCTAssertEqual(secondIntent.phase, .pointerSwitched)
        XCTAssertEqual(secondIntent.oldGenerationID, target.generationID)
        XCTAssertEqual(secondIntent.newGenerationID, secondGenerationID)
        XCTAssertEqual(secondIntent.restoreID, secondRestoreID)
        XCTAssertNotEqual(secondIntent.restoreID, firstIntent.restoreID)
        XCTAssertNotEqual(secondIntent.newGenerationID, firstIntent.newGenerationID)
        XCTAssertEqual(try CurrentPointerCodecV1.decode(Data(contentsOf: pointerURL)).generationID,
                       secondGenerationID.uuidString.lowercased())
        let publishedRecovery = try BackupRestoreService(
            applicationSupportURL: targetSupport,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in .max })
        )
        fixtureLifetime.retain(publishedRecovery)
        let recoveredSession = try await publishedRecovery
            .reconcileRestoreAndPrivateSystemDiscoveryAtStartup()
        let restored = try XCTUnwrap(recoveredSession)
        fixtureLifetime.retain(restored)
        XCTAssertNil(try intentStore.load())
        XCTAssertEqual(try CurrentPointerCodecV1.decode(Data(contentsOf: pointerURL)).generationID,
                       restored.generationID.uuidString.lowercased())
        XCTAssertFalse(FileManager.default.fileExists(atPath: targetSupport
            .appendingPathComponent("FieldEvidenceRestore/portable-exchange-restore.json").path))
        XCTAssertEqual(restored.workspaceID, target.workspaceID)

        let restoredRows = try restored.modelContext.fetch(FetchDescriptor<MutationReceiptRow>())
        let decodedRows = try restoredRows.map { row in
            (row, try MutationEnvelopeV1.decodeCanonical(from: row.envelopeData))
        }
        let destinationChronology = try decodedRows
            .filter { $0.1.workspaceID == target.workspaceID }
            .map { row, envelope in
                (envelope, try MutationReceiptV1.decodeCanonical(from: row.receiptData))
            }
            .sorted {
                $0.1.expectedRevision.workspaceRevision
                    < $1.1.expectedRevision.workspaceRevision
            }
        XCTAssertEqual(destinationChronology.map { $0.0.sourceKind },
                       [.localUser, .localUser, .importedHistory])
        XCTAssertEqual(destinationChronology.count, 3)
        if destinationChronology.count == 3 {
            XCTAssertEqual(
                destinationChronology[2].1.expectedRevision.workspaceRevision,
                destinationChronology[1].1.resultingRevision.workspaceRevision
            )
        }
        let restoredJournal = try MutationJournalStoreV1(
            modelContext: restored.modelContext,
            identity: restored.workspaceIdentity,
            generationID: restored.generationID
        )
        let authenticatedHistory = try restoredJournal.exportSnapshot()
        try MutationJournalStoreV1.validateImportedSnapshot(authenticatedHistory)
        // Real exported mixed history is the oracle; ordering preserves every
        // envelope, receipt and optional reversal-sidecar byte.
        XCTAssertEqual(
            try MutationJournalStoreV1.canonicalArchiveReceiptOrder(
                Array(authenticatedHistory.receipts.reversed())),
            authenticatedHistory.receipts
        )
        let receiptToDuplicate = try XCTUnwrap(authenticatedHistory.receipts.first)
        XCTAssertThrowsError(try MutationJournalStoreV1.canonicalArchiveReceiptOrder(
            authenticatedHistory.receipts + [receiptToDuplicate]
        ))
        let retainedPartyRecord = try XCTUnwrap(authenticatedHistory.receipts.first {
            guard let envelope = try? MutationEnvelopeV1.decodeCanonical(
                from: $0.envelopeData
            ) else { return false }
            return envelope.command.kind == .applyPartyAccountability
                && envelope.workspaceID == target.workspaceID
        })
        XCTAssertEqual(retainedPartyRecord, originalRetainedPartyRecord,
                       "Replacement must retain the incumbent party envelope, receipt, and sidecars byte-for-byte")
        let retainedPartyIdentity = try WorkspaceEntityIdentityV1(
            kind: .serviceParty, id: retainedParty.partyID
        )
        let retainedContactIdentity = try WorkspaceEntityIdentityV1(
            kind: .serviceContactPoint, id: retainedContact.contactPointID
        )
        let retainedPartyTerminal = try XCTUnwrap(authenticatedHistory.entityRevisions.first {
            $0.identity == retainedPartyIdentity
        })
        let retainedContactTerminal = try XCTUnwrap(authenticatedHistory.entityRevisions.first {
            $0.identity == retainedContactIdentity
        })
        XCTAssertEqual(retainedPartyTerminal.revision, retainedParty.revision)
        XCTAssertEqual(retainedContactTerminal.revision, retainedContact.revision)
        XCTAssertEqual(retainedPartyTerminal.externalProjectionSHA256,
                       try MutationJournalStoreV1.restoreTombstoneSHA256(
                           identity: retainedPartyIdentity, revision: retainedParty.revision
                       ))
        XCTAssertEqual(retainedContactTerminal.externalProjectionSHA256,
                       try MutationJournalStoreV1.restoreTombstoneSHA256(
                           identity: retainedContactIdentity, revision: retainedContact.revision
                       ))
        let retainedPartyEnvelope = try MutationEnvelopeV1.decodeCanonical(
            from: retainedPartyRecord.envelopeData
        )
        let retainedPartyReceipt = try MutationReceiptV1.decodeCanonical(
            from: retainedPartyRecord.receiptData
        )
        func reissuedPartyHistory(
            expectedWorkspaceRevision: UInt64,
            resultingWorkspaceRevision: UInt64
        ) throws -> MutationHistorySnapshotV1 {
            let expected = try WorkspaceExpectedRevisionV1(
                workspaceID: retainedPartyEnvelope.workspaceID,
                generationID: retainedPartyEnvelope.generationID,
                writerInstanceID: retainedWriterInstanceID,
                workspaceRevision: expectedWorkspaceRevision,
                entityRevisions: retainedPartyEnvelope.expectedRevision.entityRevisions
            )
            let request = WorkspaceMutationRequestV1(
                mutationID: retainedPartyEnvelope.mutationID,
                expectedRevision: expected,
                command: retainedPartyEnvelope.command
            )
            let envelope = try MutationEnvelopeV1(
                request: request,
                identity: WorkspaceReplicaIdentityV1(
                    workspaceID: retainedPartyEnvelope.workspaceID,
                    replicaID: retainedPartyEnvelope.replicaID
                ),
                sourceKind: retainedPartyEnvelope.sourceKind,
                contentDependencyIDs: retainedPartyEnvelope.contentDependencyIDs,
                causationMutationID: retainedPartyEnvelope.causationMutationID,
                correlationID: retainedPartyEnvelope.correlationID
            )
            let resulting = try MutationPortableExpectedRevisionV1(
                WorkspaceExpectedRevisionV1(
                    workspaceID: retainedPartyReceipt.resultingRevision.workspaceID,
                    generationID: retainedPartyReceipt.resultingRevision.generationID,
                    writerInstanceID: retainedWriterInstanceID,
                    workspaceRevision: resultingWorkspaceRevision,
                    entityRevisions: retainedPartyReceipt.resultingRevision.entityRevisions
                )
            )
            let receipt = try MutationReceiptV1(
                identity: retainedPartyReceipt.identity,
                envelope: envelope,
                resultingRevision: resulting,
                postImages: retainedPartyReceipt.postImages,
                committedAt: retainedPartyReceipt.committedAt
            )
            let record = MutationHistoryReceiptRecordV1(
                envelopeData: try envelope.canonicalData(),
                receiptData: try receipt.canonicalData(),
                reversalBasisData: retainedPartyRecord.reversalBasisData,
                semanticReversalData: retainedPartyRecord.semanticReversalData
            )
            return MutationHistorySnapshotV1(
                workspaceRevision: max(
                    authenticatedHistory.workspaceRevision,
                    resultingWorkspaceRevision
                ),
                lastLocalSequence: authenticatedHistory.lastLocalSequence,
                receipts: authenticatedHistory.receipts.map {
                    $0 == retainedPartyRecord ? record : $0
                },
                quarantines: authenticatedHistory.quarantines,
                entityRevisions: authenticatedHistory.entityRevisions
            )
        }
        let rehashedDuplicate = try reissuedPartyHistory(
            expectedWorkspaceRevision: 1, resultingWorkspaceRevision: 2
        )
        let rehashedGap = try reissuedPartyHistory(
            expectedWorkspaceRevision: 4, resultingWorkspaceRevision: 5
        )
        XCTAssertThrowsError(try MutationJournalStoreV1.validateImportedSnapshot(rehashedDuplicate))
        XCTAssertThrowsError(try MutationJournalStoreV1.validateImportedSnapshot(rehashedGap))
        let duplicateHistory = MutationHistorySnapshotV1(
            workspaceRevision: authenticatedHistory.workspaceRevision,
            lastLocalSequence: authenticatedHistory.lastLocalSequence,
            receipts: authenticatedHistory.receipts
                + [try XCTUnwrap(authenticatedHistory.receipts.last)],
            quarantines: authenticatedHistory.quarantines,
            entityRevisions: authenticatedHistory.entityRevisions
        )
        XCTAssertThrowsError(try MutationJournalStoreV1.validateImportedSnapshot(duplicateHistory))
        let retainedContactRecord = try XCTUnwrap(authenticatedHistory.receipts.first {
            guard let envelope = try? MutationEnvelopeV1.decodeCanonical(
                from: $0.envelopeData
            ) else { return false }
            return envelope.command.kind == .applyOperationalContact
                && envelope.workspaceID == target.workspaceID
        })
        XCTAssertEqual(retainedContactRecord, originalRetainedContactRecord,
                       "Replacement must retain the incumbent contact envelope, receipt, and sidecars byte-for-byte")
        let gappedHistory = MutationHistorySnapshotV1(
            workspaceRevision: authenticatedHistory.workspaceRevision,
            lastLocalSequence: authenticatedHistory.lastLocalSequence,
            receipts: authenticatedHistory.receipts.filter { $0 != retainedContactRecord },
            quarantines: authenticatedHistory.quarantines,
            entityRevisions: authenticatedHistory.entityRevisions
        )
        XCTAssertThrowsError(try MutationJournalStoreV1.validateImportedSnapshot(gappedHistory))
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
        XCTAssertTrue(try restored.modelContext.fetch(FetchDescriptor<ServicePartyRow>())
            .filter { $0.partyID == retainedParty.partyID }.isEmpty)
        XCTAssertTrue(try restored.modelContext.fetch(FetchDescriptor<ServiceContactPointRow>())
            .filter { $0.contactPointID == retainedContact.contactPointID }.isEmpty)
        let restoredReceiptImages = try MutationJournalStoreV1.receiptTerminalImages(
            in: authenticatedHistory, workspaceID: target.workspaceID
        )
        let reboundPartyIdentity = try WorkspaceEntityIdentityV1(
            kind: .serviceParty, id: reboundParty.partyID
        )
        let reboundContactIdentity = try WorkspaceEntityIdentityV1(
            kind: .serviceContactPoint, id: reboundContact.contactPointID
        )
        let reboundPartyTerminal = try XCTUnwrap(authenticatedHistory.entityRevisions.first {
            $0.identity == reboundPartyIdentity
        })
        let reboundContactTerminal = try XCTUnwrap(authenticatedHistory.entityRevisions.first {
            $0.identity == reboundContactIdentity
        })
        let reboundPartyDigest = try PersistedMutationPostImageDigestV1.sha256(
            identity: reboundPartyIdentity, revision: reboundParty.revision,
            value: reboundParty
        )
        XCTAssertEqual(
            reboundPartyTerminal.externalProjectionSHA256
                ?? restoredReceiptImages[reboundPartyIdentity]?.semanticSHA256,
            reboundPartyDigest
        )
        XCTAssertEqual(
            reboundContactTerminal.externalProjectionSHA256
                ?? restoredReceiptImages[reboundContactIdentity]?.semanticSHA256,
            reboundContact.contactPointSHA256
        )
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

/// Retains actual interrupted restore owners and their private root; a
/// pre-publication discard proves canonical state, not descriptor closure.
@MainActor
private final class C32RestoreFixtureRetentionV1 {
    private static var retainedUntilHostTermination: [C32RestoreFixtureRetentionV1] = []
    let root: URL
    private var owners: [Any] = []

    init(root: URL) {
        self.root = root
        Self.retainedUntilHostTermination.append(self)
    }

    func retain(_ owner: Any) {
        owners.append(owner)
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

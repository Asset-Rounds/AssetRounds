import Foundation
import XCTest
@testable import FieldEvidenceApp

@MainActor
final class V9_94OperationalHandoffExperienceTests: XCTestCase {
    func testDirectionsAndPartyChannelChooserUseExactCurrentTargetsWithoutPersistence() async throws {
        let corpus = try loadCorpus()
        XCTAssertEqual(corpus["schema"] as? String, "V23P04C31OperationalHandoffExperienceCorpusV1")
        XCTAssertEqual(corpus["cardID"] as? String, "V23-P04-C31")
        XCTAssertEqual(corpus["actions"] as? [String], ["DIRECTIONS", "CALL", "TEXT", "EMAIL"])

        let workspaceID = C31TestSupport.workspace(1)
        let siteID = C31TestSupport.id(10)
        let partyID = C31TestSupport.id(20)
        let party = try C31TestSupport.party(slot: 20, workspaceID: workspaceID)
        let preferredPhone = try C31TestSupport.contact(
            slot: 30,
            party: party,
            kind: .phone,
            label: .mobile,
            displayValue: "+1 (415) 555-0100",
            preferred: true
        )
        let alternatePhone = try C31TestSupport.contact(
            slot: 31,
            party: party,
            kind: .phone,
            label: .office,
            displayValue: "+1 415 555 0199"
        )
        let email = try C31TestSupport.contact(
            slot: 32,
            party: party,
            kind: .email,
            label: .work,
            displayValue: "Ops+Night@Example.COM",
            preferred: true
        )
        let site = try C31TestSupport.siteSnapshot(
            workspaceID: workspaceID,
            siteID: siteID,
            coordinate: SiteDirectionsCoordinateV1(
                latitudeMicrodegrees: 40_712_800,
                longitudeMicrodegrees: -74_006_000
            )
        )
        let query = C31HandoffQuery(
            workspaceID: workspaceID,
            sites: [siteID: site],
            siteNames: [siteID: "C31 exact site"],
            parties: [partyID: party],
            contacts: [
                preferredPhone.contactPointID: preferredPhone,
                alternatePhone.contactPointID: alternatePhone,
                email.contactPointID: email,
            ]
        )
        let opener = C31URLHandoffOpener(canPresent: true, accepts: true)
        let directions = C31DirectionsPresenter(canPresent: true, accepts: true)
        let session = OperationalContactHandoffSessionV1(
            workspaceID: workspaceID,
            query: query,
            system: SystemHandoffAdapterV1(
                opener: opener,
                directionsPresenter: directions,
                clock: C31TestClock(value: C31TestSupport.date(1))
            ),
            clock: C31TestClock(value: C31TestSupport.date(1)),
            idSource: C31SequentialIDSource(start: 100),
            clipboard: C31Clipboard()
        )

        let siteToken = OperationalContactHandoffRestorationTokenV1(
            subject: .site(siteID: siteID),
            selectedStableID: siteID,
            scrollAnchorID: "site.row.10",
            focusIdentifier: "site.directions"
        )
        guard case let .ready(sitePresentation) = await session.prepare(
            subject: .site(siteID: siteID),
            restorationToken: siteToken
        ) else {
            return XCTFail("The exact current Site must produce one directions action")
        }
        XCTAssertEqual(sitePresentation.snapshot.subject, .site(siteID: siteID))
        XCTAssertEqual(sitePresentation.snapshot.displayName, "C31 exact site")
        let directionsAction = try XCTUnwrap(sitePresentation.actions.first)
        XCTAssertEqual(directionsAction.route, .directions(siteID: siteID))
        XCTAssertEqual(directionsAction.kind, .directions)
        XCTAssertEqual(directionsAction.displayValue, "40712800,-74006000")
        XCTAssertEqual(directionsAction.preferred, true)
        let siteExecution = try await session.perform(
            sessionID: sitePresentation.sessionID,
            actionID: directionsAction.actionID
        )
        XCTAssertEqual(siteExecution.result.disposition, .handedOffToSystem)
        XCTAssertEqual(directions.calls, [
            C31Coordinate(latitudeMicrodegrees: 40_712_800, longitudeMicrodegrees: -74_006_000)
        ])
        XCTAssertTrue(opener.openedURLs.isEmpty)

        let partyToken = OperationalContactHandoffRestorationTokenV1(
            subject: .party(partyID: partyID),
            selectedStableID: partyID,
            scrollAnchorID: "party.row.20",
            focusIdentifier: "party.contact.chooser"
        )
        guard case let .ready(partyPresentation) = await session.prepare(
            subject: .party(partyID: partyID),
            restorationToken: partyToken
        ) else {
            return XCTFail("The exact current Party must produce channel actions")
        }
        XCTAssertEqual(partyPresentation.snapshot.subject, .party(partyID: partyID))
        XCTAssertEqual(partyPresentation.snapshot.contacts.map(\.displayValue), [
            email.displayValue,
            preferredPhone.displayValue,
            alternatePhone.displayValue,
        ])
        XCTAssertEqual(partyPresentation.actions.count, 5)
        XCTAssertEqual(
            partyPresentation.actions.filter { $0.kind == .call }.map(\.displayValue),
            [preferredPhone.displayValue, alternatePhone.displayValue]
        )
        XCTAssertEqual(
            partyPresentation.actions.filter { $0.kind == .text }.map(\.displayValue),
            [preferredPhone.displayValue, alternatePhone.displayValue]
        )
        XCTAssertEqual(
            partyPresentation.actions.filter { $0.kind == .email }.map(\.displayValue),
            [email.displayValue]
        )
        XCTAssertEqual(
            Set(partyPresentation.actions.map { $0.route.targetID }),
            Set([preferredPhone.contactPointID, alternatePhone.contactPointID, email.contactPointID])
        )

        for action in partyPresentation.actions {
            let execution = try await session.perform(
                sessionID: partyPresentation.sessionID,
                actionID: action.actionID
            )
            XCTAssertEqual(execution.result.disposition, .handedOffToSystem)
            XCTAssertFalse(execution.copyFallbackAvailable)
        }
        XCTAssertEqual(opener.openedURLs.count, 5)
        XCTAssertTrue(opener.openedURLs.contains { $0.absoluteString == "tel:+14155550100" })
        XCTAssertTrue(opener.openedURLs.contains { $0.absoluteString == "tel:+14155550199" })
        XCTAssertTrue(opener.openedURLs.contains { $0.absoluteString == "sms:+14155550100" })
        XCTAssertTrue(opener.openedURLs.contains { $0.absoluteString == "sms:+14155550199" })
        XCTAssertTrue(opener.openedURLs.contains { $0.scheme == "mailto" && $0.query == nil && $0.fragment == nil })
        XCTAssertEqual(query.mutationCalls, 0)
        XCTAssertFalse(OperationalContactPersistenceEnrollmentV1.handoffOutcomeIsPersistent)
    }

    func testSystemAcceptanceIsTruthfullyBoundedAndCopyFallbackIsEphemeral() async throws {
        let workspaceID = C31TestSupport.workspace(101)
        let partyID = C31TestSupport.id(102)
        let party = try C31TestSupport.party(slot: 102, workspaceID: workspaceID)
        let contact = try C31TestSupport.contact(
            slot: 103,
            party: party,
            kind: .phone,
            label: .mobile,
            displayValue: "+1 212 555 0100",
            preferred: true
        )
        let query = C31HandoffQuery(
            workspaceID: workspaceID,
            parties: [partyID: party],
            contacts: [contact.contactPointID: contact]
        )
        let unavailableOpener = C31URLHandoffOpener(canPresent: false, accepts: true)
        let unavailableClipboard = C31Clipboard()
        let unavailableSession = OperationalContactHandoffSessionV1(
            workspaceID: workspaceID,
            query: query,
            system: SystemHandoffAdapterV1(
                opener: unavailableOpener,
                directionsPresenter: C31DirectionsPresenter(canPresent: false, accepts: true),
                clock: C31TestClock(value: C31TestSupport.date(101))
            ),
            clock: C31TestClock(value: C31TestSupport.date(101)),
            idSource: C31SequentialIDSource(start: 200),
            clipboard: unavailableClipboard
        )
        let token = OperationalContactHandoffRestorationTokenV1(
            subject: .party(partyID: partyID),
            selectedStableID: partyID,
            scrollAnchorID: "party.row.102",
            focusIdentifier: "party.call"
        )
        guard case let .ready(unavailablePresentation) = await unavailableSession.prepare(
            subject: .party(partyID: partyID),
            restorationToken: token
        ) else {
            return XCTFail("A valid phone must be reviewable before capability fallback")
        }
        let unavailableAction = try XCTUnwrap(unavailablePresentation.actions.first { $0.kind == .call })
        XCTAssertEqual(
            unavailableSession.copyFallback(
                sessionID: unavailablePresentation.sessionID,
                actionID: unavailableAction.actionID
            ),
            .unavailable
        )
        let unavailableExecution = try await unavailableSession.perform(
            sessionID: unavailablePresentation.sessionID,
            actionID: unavailableAction.actionID
        )
        XCTAssertEqual(unavailableExecution.result.disposition, .systemUnavailable)
        XCTAssertTrue(unavailableExecution.copyFallbackAvailable)
        XCTAssertEqual(unavailableOpener.openedURLs.count, 0)
        XCTAssertEqual(
            unavailableSession.copyFallback(
                sessionID: unavailablePresentation.sessionID,
                actionID: unavailableAction.actionID
            ),
            .copied
        )
        XCTAssertEqual(unavailableClipboard.values, [contact.displayValue])

        let rejectedOpener = C31URLHandoffOpener(canPresent: true, accepts: false)
        let rejectedClipboard = C31Clipboard()
        let rejectedSession = OperationalContactHandoffSessionV1(
            workspaceID: workspaceID,
            query: query,
            system: SystemHandoffAdapterV1(
                opener: rejectedOpener,
                directionsPresenter: C31DirectionsPresenter(canPresent: false, accepts: true),
                clock: C31TestClock(value: C31TestSupport.date(102))
            ),
            clock: C31TestClock(value: C31TestSupport.date(102)),
            idSource: C31SequentialIDSource(start: 300),
            clipboard: rejectedClipboard
        )
        guard case let .ready(rejectedPresentation) = await rejectedSession.prepare(
            subject: .party(partyID: partyID),
            restorationToken: token
        ) else {
            return XCTFail("The same current value must remain reviewable")
        }
        let rejectedAction = try XCTUnwrap(rejectedPresentation.actions.first { $0.kind == .email || $0.kind == .call })
        let rejectedExecution = try await rejectedSession.perform(
            sessionID: rejectedPresentation.sessionID,
            actionID: rejectedAction.actionID
        )
        XCTAssertEqual(rejectedExecution.result.disposition, .systemRejected)
        XCTAssertTrue(rejectedExecution.copyFallbackAvailable)
        XCTAssertEqual(rejectedOpener.openedURLs.count, 1)
        XCTAssertEqual(
            rejectedSession.copyFallback(
                sessionID: rejectedPresentation.sessionID,
                actionID: rejectedAction.actionID
            ),
            .copied
        )
        XCTAssertEqual(rejectedClipboard.values, [contact.displayValue])

        let acceptedOpener = C31URLHandoffOpener(canPresent: true, accepts: true)
        let acceptedClipboard = C31Clipboard()
        let acceptedSession = OperationalContactHandoffSessionV1(
            workspaceID: workspaceID,
            query: query,
            system: SystemHandoffAdapterV1(
                opener: acceptedOpener,
                directionsPresenter: C31DirectionsPresenter(canPresent: false, accepts: true),
                clock: C31TestClock(value: C31TestSupport.date(103))
            ),
            clock: C31TestClock(value: C31TestSupport.date(103)),
            idSource: C31SequentialIDSource(start: 400),
            clipboard: acceptedClipboard
        )
        guard case let .ready(acceptedPresentation) = await acceptedSession.prepare(
            subject: .party(partyID: partyID),
            restorationToken: token
        ) else {
            return XCTFail("The accepted path must use the same current snapshot")
        }
        let acceptedAction = try XCTUnwrap(acceptedPresentation.actions.first { $0.kind == .call })
        let acceptedExecution = try await acceptedSession.perform(
            sessionID: acceptedPresentation.sessionID,
            actionID: acceptedAction.actionID
        )
        XCTAssertEqual(acceptedExecution.result.disposition, .handedOffToSystem)
        XCTAssertFalse(acceptedExecution.copyFallbackAvailable)
        XCTAssertEqual(
            acceptedSession.copyFallback(
                sessionID: acceptedPresentation.sessionID,
                actionID: acceptedAction.actionID
            ),
            .unavailable
        )
        XCTAssertTrue(acceptedClipboard.values.isEmpty)
        XCTAssertEqual(query.mutationCalls, 0)

        let forbiddenClaims = ["sent", "delivered", "called", "answered", "routed", "arrived", "verified", "consented"]
        for execution in [unavailableExecution, rejectedExecution, acceptedExecution] {
            let text = execution.truthfulText.lowercased()
            for claim in forbiddenClaims {
                XCTAssertFalse(text.contains(claim), "Truthful presentation text must not claim \(claim)")
            }
        }
        XCTAssertFalse(OperationalContactPersistenceEnrollmentV1.handoffOutcomeIsPersistent)
        XCTAssertFalse(C46SystemHandoffPlatformBoundaryV1.outcomeIsCanonicalHistory)
    }

    func testHostileTargetsAndStaleDeletedSourcesFailClosed() async throws {
        let corpus = try loadCorpus()
        let hostileCases = try XCTUnwrap(corpus["hostileCases"] as? [String])
        XCTAssertTrue(hostileCases.contains("BIDI_OR_CONTROL_TEXT"))
        XCTAssertTrue(hostileCases.contains("URL_QUERY_FRAGMENT_INJECTION"))
        XCTAssertTrue(hostileCases.contains("AMBIGUOUS_MULTIPLE_PREFERRED_VALUES"))
        XCTAssertTrue(hostileCases.contains("STALE_PARTY_CONTACT_REVISION_OR_DIGEST"))
        XCTAssertTrue(hostileCases.contains("DELETED_SITE_OR_PARTY"))

        let workspaceID = C31TestSupport.workspace(501)
        let partyID = C31TestSupport.id(502)
        let party = try C31TestSupport.party(slot: 502, workspaceID: workspaceID)
        let contact = try C31TestSupport.contact(
            slot: 503,
            party: party,
            kind: .phone,
            label: .mobile,
            displayValue: "+1 646 555 0100",
            preferred: true
        )
        let opener = C31URLHandoffOpener(canPresent: true, accepts: true)
        let query = C31HandoffQuery(
            workspaceID: workspaceID,
            parties: [partyID: party],
            contacts: [contact.contactPointID: contact]
        )
        let session = OperationalContactHandoffSessionV1(
            workspaceID: workspaceID,
            query: query,
            system: SystemHandoffAdapterV1(
                opener: opener,
                directionsPresenter: C31DirectionsPresenter(canPresent: true, accepts: true),
                clock: C31TestClock(value: C31TestSupport.date(501))
            ),
            clock: C31TestClock(value: C31TestSupport.date(501)),
            idSource: C31SequentialIDSource(start: 600),
            clipboard: C31Clipboard()
        )
        let token = OperationalContactHandoffRestorationTokenV1(
            subject: .party(partyID: partyID),
            selectedStableID: partyID,
            scrollAnchorID: "party.row.502",
            focusIdentifier: "party.phone"
        )
        guard case let .ready(presentation) = await session.prepare(
            subject: .party(partyID: partyID),
            restorationToken: token
        ) else {
            return XCTFail("The valid baseline must prepare")
        }
        let action = try XCTUnwrap(presentation.actions.first { $0.kind == .call })
        query.contactsByID.removeValue(forKey: contact.contactPointID)
        let deleted = try await session.perform(
            sessionID: presentation.sessionID,
            actionID: action.actionID
        )
        XCTAssertEqual(deleted.result.disposition, .targetMissing)
        XCTAssertTrue(opener.openedURLs.isEmpty)

        let replacement = try C31TestSupport.contact(
            slot: 504,
            party: party,
            kind: .phone,
            label: .mobile,
            displayValue: "+1 646 555 0199",
            preferred: true,
            contactPointID: contact.contactPointID,
            revision: 2,
            supersedes: try contact.revisionReference
        )
        let staleQuery = C31HandoffQuery(
            workspaceID: workspaceID,
            parties: [partyID: party],
            contacts: [contact.contactPointID: contact]
        )
        let staleSession = OperationalContactHandoffSessionV1(
            workspaceID: workspaceID,
            query: staleQuery,
            system: SystemHandoffAdapterV1(
                opener: opener,
                directionsPresenter: C31DirectionsPresenter(canPresent: true, accepts: true),
                clock: C31TestClock(value: C31TestSupport.date(502))
            ),
            clock: C31TestClock(value: C31TestSupport.date(502)),
            idSource: C31SequentialIDSource(start: 700),
            clipboard: C31Clipboard()
        )
        guard case let .ready(stalePresentation) = await staleSession.prepare(
            subject: .party(partyID: partyID),
            restorationToken: token
        ) else {
            return XCTFail("A replacement remains reviewable, but must not be reused by an old draft")
        }
        let staleAction = try XCTUnwrap(stalePresentation.actions.first { $0.kind == .call })
        staleQuery.contactsByID[contact.contactPointID] = replacement
        let stale = try await staleSession.perform(
            sessionID: stalePresentation.sessionID,
            actionID: staleAction.actionID
        )
        XCTAssertEqual(stale.result.disposition, .targetStale)
        XCTAssertTrue(opener.openedURLs.isEmpty)

        let partyDeletedQuery = C31HandoffQuery(
            workspaceID: workspaceID,
            parties: [partyID: party],
            contacts: [contact.contactPointID: contact]
        )
        let partyDeletedSession = OperationalContactHandoffSessionV1(
            workspaceID: workspaceID,
            query: partyDeletedQuery,
            system: SystemHandoffAdapterV1(
                opener: opener,
                directionsPresenter: C31DirectionsPresenter(canPresent: true, accepts: true),
                clock: C31TestClock(value: C31TestSupport.date(502.5))
            ),
            clock: C31TestClock(value: C31TestSupport.date(502.5)),
            idSource: C31SequentialIDSource(start: 750),
            clipboard: C31Clipboard()
        )
        guard case let .ready(partyDeletedPresentation) = await partyDeletedSession.prepare(
            subject: .party(partyID: partyID),
            restorationToken: token
        ) else {
            return XCTFail("The Party must be current when its chooser is prepared")
        }
        let partyDeletedAction = try XCTUnwrap(
            partyDeletedPresentation.actions.first { $0.kind == .call }
        )
        partyDeletedQuery.partiesByID.removeValue(forKey: partyID)
        XCTAssertNotNil(partyDeletedQuery.contactsByID[contact.contactPointID])
        let deletedParty = try await partyDeletedSession.perform(
            sessionID: partyDeletedPresentation.sessionID,
            actionID: partyDeletedAction.actionID
        )
        XCTAssertEqual(deletedParty.result.disposition, .targetMissing)
        XCTAssertTrue(opener.openedURLs.isEmpty)

        let retired = try C31TestSupport.contact(
            slot: 505,
            party: party,
            kind: .phone,
            label: .mobile,
            displayValue: "+1 646 555 0177",
            lifecycle: .retired,
            retiredAt: C31TestSupport.date(506)
        )
        XCTAssertThrowsError(try OperationalContactHandoffContactPresentationV1(contact: retired))
        let retiredQuery = C31HandoffQuery(
            workspaceID: workspaceID,
            parties: [partyID: party],
            contacts: [retired.contactPointID: retired]
        )
        let retiredSession = OperationalContactHandoffSessionV1(
            workspaceID: workspaceID,
            query: retiredQuery,
            system: SystemHandoffAdapterV1(
                opener: opener,
                directionsPresenter: C31DirectionsPresenter(canPresent: true, accepts: true),
                clock: C31TestClock(value: C31TestSupport.date(503))
            ),
            clock: C31TestClock(value: C31TestSupport.date(503)),
            idSource: C31SequentialIDSource(start: 800),
            clipboard: C31Clipboard()
        )
        guard case let .unavailable(retiredUnavailable) = await retiredSession.prepare(
            subject: .party(partyID: partyID),
            restorationToken: token
        ) else {
            return XCTFail("Retired contact values must not enter the chooser")
        }
        XCTAssertEqual(retiredUnavailable.disposition, .targetMissing)

        let blank = SystemHandoffDestinationV1.exactAddress("")
        XCTAssertThrowsError(try blank.validate(for: .directions))
        let bidi = SystemHandoffDestinationV1.exactAddress("12 Main\u{202E} St")
        XCTAssertThrowsError(try bidi.validate(for: .directions))
        let addressInjection = SystemHandoffDestinationV1.exactAddress("12 Main St?daddr=elsewhere")
        XCTAssertThrowsError(try addressInjection.validate(for: .directions))
        let phoneInjection = SystemHandoffDestinationV1.phone("+1 646 555 0100#123")
        XCTAssertThrowsError(try phoneInjection.validate(for: .call))
        let emailInjection = SystemHandoffDestinationV1.email("ops@example.com?subject=secret")
        XCTAssertThrowsError(try emailInjection.validate(for: .email))

        let ambiguousPhoneA = try C31TestSupport.contact(
            slot: 507,
            party: party,
            kind: .phone,
            label: .mobile,
            displayValue: "+1 646 555 0111",
            preferred: true
        )
        let ambiguousPhoneB = try C31TestSupport.contact(
            slot: 508,
            party: party,
            kind: .phone,
            label: .office,
            displayValue: "+1 646 555 0112",
            preferred: true
        )
        let ambiguousQuery = C31HandoffQuery(
            workspaceID: workspaceID,
            parties: [partyID: party],
            contacts: [
                ambiguousPhoneA.contactPointID: ambiguousPhoneA,
                ambiguousPhoneB.contactPointID: ambiguousPhoneB,
            ]
        )
        let ambiguousSession = OperationalContactHandoffSessionV1(
            workspaceID: workspaceID,
            query: ambiguousQuery,
            system: SystemHandoffAdapterV1(
                opener: opener,
                directionsPresenter: C31DirectionsPresenter(canPresent: true, accepts: true),
                clock: C31TestClock(value: C31TestSupport.date(504))
            ),
            clock: C31TestClock(value: C31TestSupport.date(504)),
            idSource: C31SequentialIDSource(start: 900),
            clipboard: C31Clipboard()
        )
        guard case let .unavailable(ambiguousUnavailable) = await ambiguousSession.prepare(
            subject: .party(partyID: partyID),
            restorationToken: token
        ) else {
            return XCTFail("Ambiguous preferred values must fail closed")
        }
        XCTAssertEqual(ambiguousUnavailable.disposition, .targetInvalid)

        let foreignWorkspace = C31TestSupport.workspace(509)
        let foreignTarget = try C31TestSupport.target(
            workspaceID: foreignWorkspace,
            kind: .serviceContactPoint,
            targetID: contact.contactPointID,
            revision: contact.revision,
            digest: "d"
        )
        XCTAssertThrowsError(try SystemHandoffIntentV1(
            intentID: C31TestSupport.id(510),
            workspaceID: workspaceID,
            kind: .call,
            target: foreignTarget,
            reviewedAt: C31TestSupport.date(510),
            revision: 1,
            mutationID: try C31TestSupport.mutation(511)
        ))

        let mismatchTarget = try C31TestSupport.target(
            workspaceID: workspaceID,
            kind: .serviceContactPoint,
            targetID: contact.contactPointID,
            revision: contact.revision,
            digest: "e"
        )
        let emailIntent = try C31TestSupport.intent(
            slot: 512,
            workspaceID: workspaceID,
            kind: .email,
            target: mismatchTarget
        )
        XCTAssertThrowsError(try SystemHandoffRequestV1(
            intent: emailIntent,
            currentTarget: mismatchTarget,
            destination: .phone("+1 646 555 0100")
        ))
        XCTAssertEqual(query.mutationCalls, 0)
    }

    func testCancellationAndSystemRefusalRestoreRouteSelectionScrollAndFocus() async throws {
        let workspaceID = C31TestSupport.workspace(601)
        let partyID = C31TestSupport.id(602)
        let party = try C31TestSupport.party(slot: 602, workspaceID: workspaceID)
        let contact = try C31TestSupport.contact(
            slot: 603,
            party: party,
            kind: .phone,
            label: .mobile,
            displayValue: "+1 718 555 0100",
            preferred: true
        )
        let token = OperationalContactHandoffRestorationTokenV1(
            subject: .party(partyID: partyID),
            selectedStableID: contact.contactPointID,
            scrollAnchorID: "party.row.602",
            focusIdentifier: "party.call"
        )
        let query = C31HandoffQuery(
            workspaceID: workspaceID,
            parties: [partyID: party],
            contacts: [contact.contactPointID: contact]
        )
        let opener = C31URLHandoffOpener(canPresent: true, accepts: true)
        let session = OperationalContactHandoffSessionV1(
            workspaceID: workspaceID,
            query: query,
            system: SystemHandoffAdapterV1(
                opener: opener,
                directionsPresenter: C31DirectionsPresenter(canPresent: true, accepts: true),
                clock: C31TestClock(value: C31TestSupport.date(601))
            ),
            clock: C31TestClock(value: C31TestSupport.date(601)),
            idSource: C31SequentialIDSource(start: 1_000),
            clipboard: C31Clipboard()
        )
        let mismatched = await session.prepare(
            subject: .party(partyID: partyID),
            restorationToken: OperationalContactHandoffRestorationTokenV1(
                subject: .site(siteID: C31TestSupport.id(604)),
                selectedStableID: nil,
                scrollAnchorID: "wrong.route",
                focusIdentifier: "wrong.focus"
            )
        )
        guard case let .unavailable(unavailable) = mismatched else {
            return XCTFail("A route token for another subject must fail closed")
        }
        XCTAssertEqual(unavailable.disposition, .targetInvalid)
        XCTAssertNil(session.cancel(sessionID: C31TestSupport.id(605)))

        guard case let .ready(presentation) = await session.prepare(
            subject: .party(partyID: partyID),
            restorationToken: token
        ) else {
            return XCTFail("The valid route token must prepare")
        }
        let action = try XCTUnwrap(presentation.actions.first { $0.kind == .call })
        let cancellationTask = Task { @MainActor in
            await Task.yield()
            return try await session.perform(
                sessionID: presentation.sessionID,
                actionID: action.actionID
            )
        }
        cancellationTask.cancel()
        let cancellation = try await cancellationTask.value
        XCTAssertEqual(cancellation.result.disposition, .cancelledBeforeHandoff)
        XCTAssertTrue(opener.openedURLs.isEmpty)

        let refusalOpener = C31URLHandoffOpener(canPresent: true, accepts: false)
        let refusalSession = OperationalContactHandoffSessionV1(
            workspaceID: workspaceID,
            query: query,
            system: SystemHandoffAdapterV1(
                opener: refusalOpener,
                directionsPresenter: C31DirectionsPresenter(canPresent: true, accepts: true),
                clock: C31TestClock(value: C31TestSupport.date(602))
            ),
            clock: C31TestClock(value: C31TestSupport.date(602)),
            idSource: C31SequentialIDSource(start: 1_100),
            clipboard: C31Clipboard()
        )
        guard case let .ready(refusalPresentation) = await refusalSession.prepare(
            subject: .party(partyID: partyID),
            restorationToken: token
        ) else {
            return XCTFail("The refusal path must begin with the same chooser")
        }
        let refusalAction = try XCTUnwrap(refusalPresentation.actions.first { $0.kind == .call })
        let refusal = try await refusalSession.perform(
            sessionID: refusalPresentation.sessionID,
            actionID: refusalAction.actionID
        )
        XCTAssertEqual(refusal.result.disposition, .systemRejected)
        XCTAssertTrue(refusal.copyFallbackAvailable)
        XCTAssertEqual(refusalOpener.openedURLs.count, 1)
        XCTAssertEqual(refusalSession.cancel(sessionID: refusalPresentation.sessionID), token)
        do {
            _ = try await refusalSession.perform(
                sessionID: refusalPresentation.sessionID,
                actionID: refusalAction.actionID
            )
            XCTFail("Dismissal must erase the ephemeral draft")
        } catch {
            XCTAssertEqual(error as? OperationalContactHandoffSessionFailureV1, .sessionUnavailable)
        }

        let repeatedOpener = C31URLHandoffOpener(canPresent: true, accepts: true)
        let repeatedSession = OperationalContactHandoffSessionV1(
            workspaceID: workspaceID,
            query: query,
            system: SystemHandoffAdapterV1(
                opener: repeatedOpener,
                directionsPresenter: C31DirectionsPresenter(canPresent: true, accepts: true),
                clock: C31TestClock(value: C31TestSupport.date(603))
            ),
            clock: C31TestClock(value: C31TestSupport.date(603)),
            idSource: C31SequentialIDSource(start: 1_200),
            clipboard: C31Clipboard()
        )
        guard case let .ready(repeatedPresentation) = await repeatedSession.prepare(
            subject: .party(partyID: partyID),
            restorationToken: token
        ) else {
            return XCTFail("The repeated-tap path must prepare")
        }
        let repeatedAction = try XCTUnwrap(repeatedPresentation.actions.first { $0.kind == .call })
        let firstTap = try await repeatedSession.perform(
            sessionID: repeatedPresentation.sessionID,
            actionID: repeatedAction.actionID
        )
        let secondTap = try await repeatedSession.perform(
            sessionID: repeatedPresentation.sessionID,
            actionID: repeatedAction.actionID
        )
        XCTAssertEqual(firstTap.result.disposition, .handedOffToSystem)
        XCTAssertEqual(secondTap.result.disposition, .handedOffToSystem)
        XCTAssertEqual(repeatedOpener.openedURLs.count, 2)

        let restored = repeatedSession.dismiss(sessionID: repeatedPresentation.sessionID)
        XCTAssertEqual(restored, token)
        XCTAssertFalse(String(describing: restored as Any).contains(contact.displayValue))
        XCTAssertNil(repeatedSession.dismiss(sessionID: repeatedPresentation.sessionID))
        XCTAssertEqual(
            repeatedSession.copyFallback(
                sessionID: repeatedPresentation.sessionID,
                actionID: repeatedAction.actionID
            ),
            .unavailable
        )
    }

    func testProductionCompositionRequiresAccessAndUsesInjectableNativeBoundary() async throws {
        XCTAssertEqual(
            ProductionCompositionRoot.c16AccessGateProductionAdoptionComplete,
            WorkspaceExperienceAppAccessAdoptionBoundaryV1.productionCallerAdoptionComplete
        )
        XCTAssertFalse(WorkspaceExperienceAppAccessAdoptionBoundaryV1.productionCallerAdoptionComplete)
        XCTAssertTrue(WorkspaceExperienceAppAccessAdoptionBoundaryV1.postS10_6ReconciliationRequired)

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "C31-production-composition-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let factory = StoreGenerationFactory(applicationSupportURL: root)
        let storeSession = try factory.openOrBootstrapCurrent()
        let coordinator = StoreSessionCoordinator(session: storeSession)
        let composition = try ProductionCompositionRoot(
            storeSession: coordinator,
            diagnosticsStore: DiagnosticsStore(applicationSupportURL: root),
            profileRegistry: try WorkspacePackageLifecycleCompatibilityV1.shippingRegistry()
        )
        let access = C31AccessGate()
        do {
            _ = try await composition.makeOperationalContactHandoffSession(
                accessGate: access,
                clipboard: C31Clipboard()
            )
            XCTFail("Production composition must stop at the injected content-access gate")
        } catch {
            XCTAssertEqual(error as? C31AccessFailure, .denied)
        }
        XCTAssertEqual(access.renderRequests, 1)

        let workspaceID = C31TestSupport.workspace(801)
        let target = try C31TestSupport.target(
            workspaceID: workspaceID,
            kind: .site,
            targetID: C31TestSupport.id(802),
            revision: 1,
            digest: "f"
        )
        let intent = try C31TestSupport.intent(
            slot: 803,
            workspaceID: workspaceID,
            kind: .directions,
            target: target
        )
        let request = try SystemHandoffRequestV1(
            intent: intent,
            currentTarget: target,
            destination: .geographicCoordinate(
                latitudeMicrodegrees: 40_712_800,
                longitudeMicrodegrees: -74_006_000
            )
        )
        let opener = C31URLHandoffOpener(canPresent: true, accepts: true)
        let directions = C31DirectionsPresenter(canPresent: true, accepts: true)
        let result = await SystemHandoffAdapterV1(
            opener: opener,
            directionsPresenter: directions,
            clock: C31TestClock(value: C31TestSupport.date(801))
        ).handOff(request)
        XCTAssertEqual(result.disposition, .handedOffToSystem)
        XCTAssertEqual(
            directions.calls,
            [C31Coordinate(latitudeMicrodegrees: 40_712_800, longitudeMicrodegrees: -74_006_000)]
        )
        XCTAssertTrue(opener.openedURLs.isEmpty)
        XCTAssertEqual(C46SystemHandoffPlatformBoundaryV1.systemCallCountPerExplicitTap, 1)
        XCTAssertFalse(C46SystemHandoffPlatformBoundaryV1.outcomeIsCanonicalHistory)
        XCTAssertFalse(OperationalContactPersistenceEnrollmentV1.handoffOutcomeIsPersistent)
    }

    private func loadCorpus() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/V23/Contacts/V23P04C31OperationalHandoffExperienceCorpusV1.json")
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
    }
}

private struct C31Coordinate: Equatable, Sendable {
    let latitudeMicrodegrees: Int32
    let longitudeMicrodegrees: Int32
}

private struct C31TestClock: ApplicationClock {
    let value: Date
    func now() -> Date { value }
}

private final class C31SequentialIDSource: ApplicationIDSource, @unchecked Sendable {
    private var next: Int

    init(start: Int) { next = start }

    func makeID() -> UUID {
        defer { next += 1 }
        return C31TestSupport.id(next)
    }
}

@MainActor
private final class C31Clipboard: OperationalContactHandoffValueCopyingV1 {
    private(set) var values: [String] = []

    func copyHandoffValue(_ value: String) {
        values.append(value)
    }
}

@MainActor
private final class C31URLHandoffOpener: SystemURLHandoffOpeningV1 {
    var canPresentSystemHandoff: Bool
    let accepts: Bool
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

@MainActor
private final class C31DirectionsPresenter: SystemDirectionsHandoffPresentingV1 {
    var canPresentSystemDirections: Bool
    let accepts: Bool
    private(set) var calls: [C31Coordinate] = []

    init(canPresent: Bool, accepts: Bool) {
        canPresentSystemDirections = canPresent
        self.accepts = accepts
    }

    func presentOnce(latitudeMicrodegrees: Int32, longitudeMicrodegrees: Int32) async -> Bool {
        calls.append(C31Coordinate(
            latitudeMicrodegrees: latitudeMicrodegrees,
            longitudeMicrodegrees: longitudeMicrodegrees
        ))
        return accepts
    }
}

@MainActor
private final class C31HandoffQuery: OperationalContactHandoffQueryingV1 {
    let workspaceID: WorkspaceID
    var sites: [UUID: SiteDirectionsTargetSnapshotV1]
    let siteNames: [UUID: String]
    var partiesByID: [UUID: ServicePartyReferenceV1]
    var contactsByID: [UUID: ServiceContactPointV1]
    private(set) var mutationCalls = 0

    init(
        workspaceID: WorkspaceID,
        sites: [UUID: SiteDirectionsTargetSnapshotV1] = [:],
        siteNames: [UUID: String] = [:],
        parties: [UUID: ServicePartyReferenceV1] = [:],
        contacts: [UUID: ServiceContactPointV1] = [:]
    ) {
        self.workspaceID = workspaceID
        self.sites = sites
        self.siteNames = siteNames
        partiesByID = parties
        contactsByID = contacts
    }

    func currentHandoffPresentationSnapshot(
        workspaceID: WorkspaceID,
        subject: OperationalContactHandoffSubjectV1
    ) async throws -> OperationalContactHandoffPresentationSnapshotV1? {
        guard workspaceID == self.workspaceID else { return nil }
        switch subject {
        case let .site(siteID):
            guard let directions = sites[siteID] else { return nil }
            return try OperationalContactHandoffPresentationSnapshotV1(
                subject: subject,
                displayName: siteNames[siteID] ?? "C31 Site",
                directions: directions
            )
        case let .party(partyID):
            guard let party = partiesByID[partyID], party.state == .effective else { return nil }
            let contacts = contactsByID.values.filter {
                $0.workspaceID == self.workspaceID
                    && $0.party.partyID == partyID
                    && $0.lifecycle == .effective
            }
            return try OperationalContactHandoffPresentationSnapshotV1(
                subject: subject,
                displayName: party.displayName,
                contacts: try contacts.map {
                    try OperationalContactHandoffContactPresentationV1(contact: $0)
                }
            )
        }
    }

    func currentSiteDirectionsSnapshot(
        workspaceID: WorkspaceID,
        siteID: UUID
    ) async throws -> SiteDirectionsTargetSnapshotV1? {
        guard workspaceID == self.workspaceID else { return nil }
        return sites[siteID]
    }

    func currentServiceContactPoint(
        workspaceID: WorkspaceID,
        contactPointID: UUID
    ) async throws -> ServiceContactPointV1? {
        guard workspaceID == self.workspaceID else { return nil }
        return contactsByID[contactPointID]
    }

    func handoffIntent(
        workspaceID: WorkspaceID,
        intentID: UUID
    ) async throws -> SystemHandoffIntentV1? {
        _ = workspaceID
        _ = intentID
        return nil
    }
}

private enum C31AccessFailure: Error, Equatable {
    case denied
}

private final class C31AccessGate: AppAccessGatePortV1, @unchecked Sendable {
    private(set) var renderRequests = 0

    func currentState() async -> AppAccessStateV1 {
        .locked(reason: .lockNow)
    }

    func lock(reason: AppLockReasonV1) async {
        _ = reason
    }

    func authenticate(
        trigger: LocalAuthenticationTriggerV1
    ) async -> LocalAuthenticationOutcomeV1 {
        _ = trigger
        return .userCancelled
    }

    func requireContentAccess() async throws {
        throw C31AccessFailure.denied
    }

    func requireContentAccess(
        for surface: AppAccessContentReadSurfaceV1
    ) async throws -> AppAccessContentPermitV1 {
        if surface == .render { renderRequests += 1 }
        throw C31AccessFailure.denied
    }
}

private enum C31TestSupport {
    static func id(_ slot: Int) -> UUID {
        UUID(uuidString: String(format: "31000000-0000-0000-0000-%012d", slot))!
    }

    static func date(_ offset: Double) -> Date {
        Date(timeIntervalSince1970: 2_200_000_000 + offset)
    }

    static func workspace(_ slot: Int) -> WorkspaceID {
        WorkspaceID(rawValue: id(slot))
    }

    static func mutation(_ slot: Int) throws -> MutationIDV1 {
        try MutationIDV1(rawValue: id(slot))
    }

    static func party(slot: Int, workspaceID: WorkspaceID) throws -> ServicePartyReferenceV1 {
        try ServicePartyReferenceV1(
            partyID: id(slot),
            workspaceID: workspaceID,
            kind: slot.isMultiple(of: 2) ? .organization : .person,
            displayName: "C31 service party \(slot)",
            profileDescriptor: "Operational relationship only",
            provenance: .locallyRecorded,
            state: .effective,
            effectiveAt: date(Double(slot)),
            revision: 1,
            mutationID: mutation(slot + 10_000)
        )
    }

    static func contact(
        slot: Int,
        party: ServicePartyReferenceV1,
        kind: ServiceContactKindV1,
        label: ServiceContactLabelV1,
        displayValue: String,
        preferred: Bool = false,
        contactPointID: UUID? = nil,
        revision: UInt64 = 1,
        supersedes: ServiceContactRevisionReferenceV1? = nil,
        lifecycle: ServiceContactLifecycleV1 = .effective,
        retiredAt: Date? = nil
    ) throws -> ServiceContactPointV1 {
        try ServiceContactPointV1(
            contactPointID: contactPointID ?? id(slot),
            workspaceID: party.workspaceID,
            party: party,
            kind: kind,
            label: label,
            displayValue: displayValue,
            preferred: preferred,
            provenance: .manual,
            lifecycle: lifecycle,
            effectiveAt: date(Double(slot)),
            retiredAt: retiredAt,
            revision: revision,
            supersedes: supersedes,
            mutationID: mutation(slot + 11_000)
        )
    }

    static func target(
        workspaceID: WorkspaceID,
        kind: SystemHandoffTargetKindV1,
        targetID: UUID,
        revision: UInt64,
        digest: Character
    ) throws -> SystemHandoffTargetReferenceV1 {
        try SystemHandoffTargetReferenceV1(
            workspaceID: workspaceID,
            kind: kind,
            targetID: targetID,
            expectedRevision: revision,
            expectedSHA256: String(repeating: digest, count: 64)
        )
    }

    static func siteSnapshot(
        workspaceID: WorkspaceID,
        siteID: UUID,
        revision: UInt64 = 1,
        digest: Character = "b",
        coordinate: SiteDirectionsCoordinateV1? = nil,
        exactAddress: String? = nil
    ) throws -> SiteDirectionsTargetSnapshotV1 {
        try SiteDirectionsTargetSnapshotV1(
            currentTarget: target(
                workspaceID: workspaceID,
                kind: .site,
                targetID: siteID,
                revision: revision,
                digest: digest
            ),
            coordinate: coordinate,
            exactAddress: exactAddress
        )
    }

    static func intent(
        slot: Int,
        workspaceID: WorkspaceID,
        kind: SystemHandoffKindV1,
        target: SystemHandoffTargetReferenceV1
    ) throws -> SystemHandoffIntentV1 {
        try SystemHandoffIntentV1(
            intentID: id(slot),
            workspaceID: workspaceID,
            kind: kind,
            target: target,
            reviewedAt: date(Double(slot)),
            revision: 1,
            mutationID: mutation(slot + 12_000)
        )
    }
}

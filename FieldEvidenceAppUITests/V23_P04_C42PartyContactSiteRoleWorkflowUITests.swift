import Foundation
import XCTest
@testable import FieldEvidenceApp

final class V23_P04_C42PartyContactSiteRoleWorkflowUITests: XCTestCase {
    private enum SemanticSelector {
        static let screen = "v23.p04.c42.party-contact-site-role.screen"
        static let party = "v23.p04.c42.party-contact-site-role.party"
        static let contacts = "v23.p04.c42.party-contact-site-role.contacts"
        static let preferred = "v23.p04.c42.party-contact-site-role.preferred"
        static let siteRole = "v23.p04.c42.party-contact-site-role.site-role"
        static let impactWarnings = "v23.p04.c42.party-contact-site-role.impact-warnings"
        static let history = "v23.p04.c42.party-contact-site-role.history"
        static let reversal = "v23.p04.c42.party-contact-site-role.reversal"
        static let boundaries = "v23.p04.c42.party-contact-site-role.boundaries"

        static let all = [screen, party, contacts, preferred, siteRole, impactWarnings, history, reversal, boundaries]
    }

    private static let containedPartyContactSurfaceOnly = true
    private static let rootAdoptionEnabled = false
    private static let nativeLaunchAdoptionEnabled = false

    @MainActor
    func testV23P04C42SemanticSelectorContractIsClosedAndUnique() {
        let viewIdentifiers = [
            PartyContactSiteRoleWorkflowView.screenAccessibilityIdentifier,
            PartyContactSiteRoleWorkflowView.partyAccessibilityIdentifier,
            PartyContactSiteRoleWorkflowView.contactsAccessibilityIdentifier,
            PartyContactSiteRoleWorkflowView.preferredAccessibilityIdentifier,
            PartyContactSiteRoleWorkflowView.siteRoleAccessibilityIdentifier,
            PartyContactSiteRoleWorkflowView.impactWarningsAccessibilityIdentifier,
            PartyContactSiteRoleWorkflowView.historyAccessibilityIdentifier,
            PartyContactSiteRoleWorkflowView.reversalAccessibilityIdentifier,
            PartyContactSiteRoleWorkflowView.boundariesAccessibilityIdentifier
        ]

        XCTAssertEqual(SemanticSelector.all.count, 9)
        XCTAssertEqual(Set(SemanticSelector.all).count, SemanticSelector.all.count)
        XCTAssertEqual(viewIdentifiers, SemanticSelector.all)
        XCTAssertTrue(SemanticSelector.all.allSatisfy {
            $0.hasPrefix("v23.p04.c42.party-contact-site-role.")
                && $0 == $0.lowercased()
                && !$0.contains(where: { $0.isWhitespace })
        })
    }

    @MainActor
    func testV23P04C42WorkflowInitializerBindsCoreContractShapes() {
        let impact: (PartyContactSiteRoleOperationV1) -> PartyContactSiteRoleOperationV1 = { $0 }
        let partyCommand: (PartyWorkflowPreviewV1) -> PartyContactSiteRoleWorkflowCommandV1 = { .commitParty($0) }
        let contactCommand: (OperationalContactWorkflowPreviewV1) -> PartyContactSiteRoleWorkflowCommandV1 = { .commitContact($0) }
        let siteRoleCommand: (SiteRoleWorkflowPreviewV1) -> PartyContactSiteRoleWorkflowCommandV1 = { .commitSiteRole($0) }
        let coordinator = PartyContactSiteRoleWorkflowCoordinatorV1.self
        let initializeSurface: (
            PartyWorkflowPreviewV1?,
            OperationalContactWorkflowPreviewV1?,
            SiteRoleWorkflowPreviewV1?,
            PartyContactSiteRoleHistoryProjectionV1?
        ) -> PartyContactSiteRoleWorkflowView = { party, contact, siteRole, history in
            PartyContactSiteRoleWorkflowView(
                partyPreview: party,
                contactPreview: contact,
                siteRolePreview: siteRole,
                history: history,
                onRequestPreview: { _ in },
                onConfirmPartyRetirement: { _ in },
                onConfirmContactRetirement: { _ in },
                onConfirmSiteRoleReversal: { _ in }
            )
        }

        XCTAssertNotNil(impact)
        XCTAssertNotNil(partyCommand)
        XCTAssertNotNil(contactCommand)
        XCTAssertNotNil(siteRoleCommand)
        XCTAssertNotNil(coordinator)
        XCTAssertNotNil(initializeSurface)
    }

    func testV23P04C42WorkflowRemainsContainedBeforeS10() throws {
        XCTAssertTrue(Self.containedPartyContactSurfaceOnly)
        XCTAssertFalse(Self.rootAdoptionEnabled)
        XCTAssertFalse(Self.nativeLaunchAdoptionEnabled)
        throw XCTSkip(
            "V23-P04-C42 remains a contained Party/contact/Site-role surface pending accepted S10.6 route adoption; "
                + "this no-launch declaration makes no contact permission, Party creation, canonical write, communication, marketing, route, telemetry, or accessibility activation claim."
        )
    }
}

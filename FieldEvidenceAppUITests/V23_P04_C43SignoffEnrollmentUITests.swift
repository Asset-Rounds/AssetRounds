import XCTest
@testable import FieldEvidenceApp

final class V23_P04_C43SignoffEnrollmentUITests: XCTestCase {
    @MainActor
    func testV23P04C43JourneyIdentifiersAreClosedAndOrdered() {
        let journey = [
            SignoffEnrollmentView.workRootAccessibilityIdentifier,
            SignoffEnrollmentView.immutableDetailAccessibilityIdentifier,
            SignoffEnrollmentView.moreAccessibilityIdentifier,
            SignoffEnrollmentView.recordResponseAccessibilityIdentifier,
            SignoffEnrollmentView.editorAccessibilityIdentifier,
            SignoffEnrollmentView.historyAccessibilityIdentifier
        ]
        XCTAssertEqual(journey, [
            "v23.p04.c43.signoff-enrollment.work-root",
            "v23.p04.c43.signoff-enrollment.immutable-work-detail",
            "v23.p04.c43.signoff-enrollment.more",
            "v23.p04.c43.signoff-enrollment.record-approval-response",
            "v23.p04.c43.signoff-enrollment.editor",
            "v23.p04.c43.signoff-enrollment.history"
        ])
        XCTAssertEqual(Set(journey).count, journey.count)
        let finalViewIdentifiers = [
            SignoffEnrollmentView.screenAccessibilityIdentifier,
            SignoffEnrollmentView.disclosureAccessibilityIdentifier,
            SignoffEnrollmentView.typedNameAccessibilityIdentifier,
            SignoffEnrollmentView.confirmAccessibilityIdentifier
        ]
        XCTAssertEqual(finalViewIdentifiers, [
            "v23.p04.c43.signoff-enrollment.screen",
            "v23.p04.c43.signoff-enrollment.disclosure",
            "v23.p04.c43.signoff-enrollment.typed-name",
            "v23.p04.c43.signoff-enrollment.confirm"
        ])
        XCTAssertTrue((journey + finalViewIdentifiers).allSatisfy {
            $0.hasPrefix("v23.p04.c43.signoff-enrollment.") && $0 == $0.lowercased()
        })
    }

    func testV23P04C43RequiresVisibleWorkJourneyBeforeLaunchAdoption() throws {
        throw XCTSkip("Pending post-S10 launch adoption: this C43 contract requires the visible Work-root -> immutable detail -> More -> Record approval response -> editor -> history journey. A deep-link-only route is not an adoption path, and this test does not claim a live root or executed UI flow.")
    }
}

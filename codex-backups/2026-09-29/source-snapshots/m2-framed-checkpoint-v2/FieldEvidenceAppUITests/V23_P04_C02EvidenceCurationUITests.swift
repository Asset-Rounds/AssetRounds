import XCTest

final class V23_P04_C02EvidenceCurationUITests: XCTestCase {
    private static let uiAdoptionEnabled = false
    private static let uiAcceptanceCredit = false

    private enum SemanticSelector {
        static let screen = "v23.p04.c02.evidence-curation.screen"
        static let detailPreview = "v23.p04.c02.evidence-curation.detail-preview"
        static let original = "v23.p04.c02.evidence-curation.original"
        static let reference = "v23.p04.c02.evidence-curation.reference"
        static let comparison = "v23.p04.c02.evidence-curation.comparison"
        static let overlayAdvisory = "v23.p04.c02.evidence-curation.overlay-advisory"
        static let markupControls = "v23.p04.c02.evidence-curation.markup-controls"
        static let removeMarkup = "v23.p04.c02.evidence-curation.remove-markup"
        static let retake = "v23.p04.c02.evidence-curation.retake"
        static let removeFromWork = "v23.p04.c02.evidence-curation.remove-from-work"
        static let moveEarlier = "v23.p04.c02.evidence-curation.move-earlier"
        static let moveLater = "v23.p04.c02.evidence-curation.move-later"
        static let sequence = "v23.p04.c02.evidence-curation.sequence"
        static let contactSheet = "v23.p04.c02.evidence-curation.contact-sheet"
        static let reducedMotion = "v23.p04.c02.evidence-curation.reduced-motion"
        static let reviewOrder = "v23.p04.c02.evidence-curation.review-order"
        static let role = "v23.p04.c02.evidence-curation.role"
        static let caption = "v23.p04.c02.evidence-curation.caption"
        static let accessibilityDescription = "v23.p04.c02.evidence-curation.accessibility-description"
        static let visualDerivativeReadiness = "v23.p04.c02.evidence-curation.visual-derivative-readiness"

        static let all = [
            screen,
            detailPreview,
            original,
            reference,
            comparison,
            overlayAdvisory,
            markupControls,
            removeMarkup,
            retake,
            removeFromWork,
            moveEarlier,
            moveLater,
            sequence,
            contactSheet,
            reducedMotion,
            reviewOrder,
            role,
            caption,
            accessibilityDescription,
            visualDerivativeReadiness,
        ]
    }

    func testV23P04C02SemanticSelectorContractIsClosedAndUnique() {
        XCTAssertEqual(SemanticSelector.all.count, 20)
        XCTAssertEqual(Set(SemanticSelector.all).count, SemanticSelector.all.count)
        XCTAssertTrue(
            SemanticSelector.all.allSatisfy {
                $0.hasPrefix("v23.p04.c02.evidence-curation.")
                    && $0 == $0.lowercased()
                    && !$0.contains(where: { $0.isWhitespace })
            }
        )
    }

    func testV23P04C02EvidenceCurationUIAdoptionPendingPostS10() throws {
        XCTAssertFalse(Self.uiAdoptionEnabled)
        XCTAssertFalse(Self.uiAcceptanceCredit)
        throw XCTSkip(
            "V23-P04-C02 UI adoption is intentionally deferred until accepted S10.6 reconciliation. "
                + "The active zero-overlap fence does not authorize a production entry-point or app-composition edit, "
                + "so this test does not launch the unreachable Evidence Curation surface and earns no UI acceptance credit."
        )
    }
}

import XCTest

final class V23_P04_C06OfflineReadinessPreflightUITests: XCTestCase {
    private static let uiAdoptionEnabled = false
    private static let uiAcceptanceCredit = false

    private enum SemanticSelector {
        static let screen = "v23.p04.c06.offline-readiness-preflight.screen"
        static let summary = "v23.p04.c06.offline-readiness-preflight.summary"
        static let blocked = "v23.p04.c06.offline-readiness-preflight.blocked"
        static let warning = "v23.p04.c06.offline-readiness-preflight.warning"
        static let remediation = "v23.p04.c06.offline-readiness-preflight.remediation"
        static let manualFallback = "v23.p04.c06.offline-readiness-preflight.manual-fallback"

        static let all = [screen, summary, blocked, warning, remediation, manualFallback]
    }

    func testV23P04C06SemanticSelectorContractIsClosedAndUnique() {
        XCTAssertEqual(SemanticSelector.all.count, 6)
        XCTAssertEqual(Set(SemanticSelector.all).count, SemanticSelector.all.count)
        XCTAssertTrue(
            SemanticSelector.all.allSatisfy {
                $0.hasPrefix("v23.p04.c06.offline-readiness-preflight.")
                    && $0 == $0.lowercased()
                    && !$0.contains(where: { $0.isWhitespace })
            }
        )
    }

    func testV23P04C06OfflineReadinessPreflightUIAdoptionPendingPostS10() throws {
        XCTAssertFalse(Self.uiAdoptionEnabled)
        XCTAssertFalse(Self.uiAcceptanceCredit)
        throw XCTSkip(
            "V23-P04-C06 UI adoption is intentionally deferred until accepted S10.6 reconciliation. "
                + "The active zero-overlap fence does not authorize an app-shell, launch route, or production entry-point edit, "
                + "so this test does not launch an isolated readiness preflight surface and earns no UI acceptance credit."
        )
    }
}

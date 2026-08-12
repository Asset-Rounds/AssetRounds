import XCTest
@testable import FieldEvidenceApp

final class S0LaunchTests: XCTestCase {
    @MainActor
    func testLaunchViewUsesExactBaselineContract() {
        XCTAssertEqual(LaunchView.titleText, "AssetRounds")
        XCTAssertEqual(LaunchView.subtitleText, "Sign Inspection")
        XCTAssertEqual(LaunchView.screenAccessibilityIdentifier, "s0.launch.screen")
        XCTAssertEqual(LaunchView.titleAccessibilityIdentifier, "s0.launch.title")
    }
}

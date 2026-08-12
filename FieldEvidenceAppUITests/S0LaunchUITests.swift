import XCTest

final class S0LaunchUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchScreenRemainsVisibleAfterInertTapAtAccessibilityXXXL() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()

        let window = app.windows.firstMatch
        let screen = app.descendants(matching: .any)
            .matching(identifier: "s0.launch.screen")
            .firstMatch
        let title = app.staticTexts
            .matching(identifier: "s0.launch.title")
            .firstMatch
        let subtitle = app.staticTexts["Sign Inspection"]

        XCTAssertTrue(window.waitForExistence(timeout: 10))
        XCTAssertTrue(screen.waitForExistence(timeout: 10))
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertTrue(subtitle.waitForExistence(timeout: 10))
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertEqual(title.label, "AssetRounds")
        XCTAssertEqual(subtitle.label, "Sign Inspection")
        XCTAssertFalse(title.frame.isEmpty)
        XCTAssertFalse(subtitle.frame.isEmpty)
        XCTAssertTrue(window.frame.insetBy(dx: -1, dy: -1).contains(title.frame))
        XCTAssertTrue(window.frame.insetBy(dx: -1, dy: -1).contains(subtitle.frame))
        XCTAssertLessThan(title.frame.minY, subtitle.frame.minY)
        XCTAssertEqual(app.buttons.count, 0)
        XCTAssertEqual(app.navigationBars.count, 0)

        let initialScreenFrame = screen.frame
        let initialTitleFrame = title.frame
        let initialSubtitleFrame = subtitle.frame
        screen.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)
        ).tap()

        XCTAssertTrue(screen.exists)
        XCTAssertTrue(title.exists)
        XCTAssertTrue(subtitle.exists)
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertEqual(title.label, "AssetRounds")
        XCTAssertEqual(subtitle.label, "Sign Inspection")
        XCTAssertEqual(screen.frame, initialScreenFrame)
        XCTAssertEqual(title.frame, initialTitleFrame)
        XCTAssertEqual(subtitle.frame, initialSubtitleFrame)
    }
}

import Foundation
import XCTest

final class S6_2BackupExportUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testConfirmedBackupShowsExactCountsAndWarningAtXXXL() throws {
        let app = try launch()
        createReadyReport(in: app)

        app.terminate()
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()

        XCTAssertTrue(element("s2.sign-detail.screen", in: app).waitForExistence(timeout: 30))
        tap("s1.settings.button", in: app)
        tap("s6.2.backup.settings-entry", in: app)

        XCTAssertTrue(element("s6.2.backup.screen", in: app).waitForExistence(timeout: 30))
        XCTAssertEqual(element("s6.2.backup.sign-count", in: app).label, "1 sign")
        XCTAssertEqual(element("s6.2.backup.report-count", in: app).label, "1 report")
        XCTAssertEqual(element("s6.2.backup.photo-count", in: app).label, "2 photos")
        XCTAssertEqual(
            element("s6.2.backup.warning", in: app).label,
            "This backup contains sign details, notes, photos, and reports. It does not contain your subscription. Store and share it securely."
        )

        let action = element("s6.2.backup.action", in: app)
        scroll(action, in: app)
        assertButton(action, label: "Back up current data")
        action.doubleTap()

        let exported = element("s6.2.backup.exported", in: app)
        XCTAssertTrue(exported.waitForExistence(timeout: 40))
        XCTAssertEqual(exported.label, "AssetRounds.fieldrecordbackup")
        XCTAssertFalse(action.isEnabled)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "S6.2 confirmed deterministic backup at Accessibility XXXL"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    private func createReadyReport(in app: XCUIApplication) {
        XCTAssertTrue(element("s2.welcome.screen", in: app).waitForExistence(timeout: 25))
        tap("s2.welcome.add-first-sign", in: app)
        enter("North Campus", into: "s2.new-sign.site-label", in: app)
        enter("Monument Sign", into: "s2.new-sign.sign-label", in: app)
        dismissKeyboard(in: app)
        tap("s2.new-sign.save", in: app)
        tap("s2.sign-detail.start-check", in: app)
        enter("America/New_York", into: "s3.preflight.time-zone", in: app)
        dismissKeyboard(in: app)
        toggle("s3.preflight.time-zone-confirmed", in: app)
        toggle("s3.preflight.after-dark", in: app)
        toggle("s3.preflight.safe-position", in: app)
        tap("s3.preflight.begin", in: app)
        capture("1 of 2 · Wide view", in: app)
        capture("2 of 2 · Close view", in: app)
        tap("s3.outcome.no-visible-issue", in: app)
        tap("s3.outcome.continue", in: app)
        tap("s3.review.save-report", in: app)
        XCTAssertTrue(element("s3.receipt.screen", in: app).waitForExistence(timeout: 40))
        tap("s3.receipt.done", in: app)
        XCTAssertTrue(element("s2.sign-detail.screen", in: app).waitForExistence(timeout: 25))
    }

    @MainActor
    private func capture(_ heading: String, in app: XCUIApplication) {
        let value = element("s3.capture.heading", in: app)
        XCTAssertTrue(value.waitForExistence(timeout: 20))
        XCTAssertEqual(
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "label == %@", heading), object: value
            )], timeout: 20),
            .completed
        )
        tap("s3.capture.import-fixture", in: app)
        XCTAssertTrue(element("s3.capture.preview", in: app).waitForExistence(timeout: 20))
        tap("s3.capture.use-photo", in: app)
    }

    @MainActor
    private func launch() throws -> XCUIApplication {
        let bundle = Bundle(for: Self.self)
        let wide = try XCTUnwrap(bundle.url(
            forResource: "S3_2WideInput",
            withExtension: "png",
            subdirectory: "Fixtures"
        ) ?? bundle.url(forResource: "S3_2WideInput", withExtension: "png"))
        let close = try XCTUnwrap(bundle.url(
            forResource: "S3_2CloseInput",
            withExtension: "png",
            subdirectory: "Fixtures"
        ) ?? bundle.url(forResource: "S3_2CloseInput", withExtension: "png"))
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleInterfaceStyle", "Light", "--s1-ui-test-light-mode",
            "--s3-2-ui-test-imported-fixtures",
            "--s6-2-ui-test-confirmed-destination",
        ]
        app.launchEnvironment["S3_2_WIDE_FIXTURE_BASE64"] = try Data(
            contentsOf: wide
        ).base64EncodedString()
        app.launchEnvironment["S3_2_CLOSE_FIXTURE_BASE64"] = try Data(
            contentsOf: close
        ).base64EncodedString()
        app.launch()
        return app
    }

    @MainActor private func element(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    @MainActor private func tap(_ id: String, in app: XCUIApplication) {
        let value = element(id, in: app)
        scroll(value, in: app)
        XCTAssertTrue(value.isEnabled)
        value.tap()
    }

    @MainActor private func enter(_ text: String, into id: String, in app: XCUIApplication) {
        let value = element(id, in: app)
        scroll(value, in: app)
        XCTAssertTrue(value.waitForExistence(timeout: 15))
        value.tap()
        value.typeText(text)
    }

    @MainActor private func toggle(_ id: String, in app: XCUIApplication) {
        let value = element(id, in: app)
        scroll(value, in: app)
        value.tap()
        XCTAssertEqual(
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "value == %@", "1"), object: value
            )], timeout: 10),
            .completed
        )
    }

    @MainActor private func scroll(_ value: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(value.waitForExistence(timeout: 20))
        for _ in 0..<18 { if value.isHittable { return }; app.swipeUp() }
        for _ in 0..<18 { if value.isHittable { return }; app.swipeDown() }
        XCTAssertTrue(value.isHittable)
    }

    @MainActor private func dismissKeyboard(in app: XCUIApplication) {
        guard app.keyboards.firstMatch.exists else { return }
        let key = app.keyboards.buttons["Return"]
        key.exists ? key.tap() : app.swipeDown()
    }

    @MainActor private func assertButton(_ value: XCUIElement, label: String) {
        XCTAssertTrue(value.waitForExistence(timeout: 20))
        XCTAssertEqual(value.label, label)
        XCTAssertTrue(value.isEnabled)
        XCTAssertTrue(value.isHittable)
        XCTAssertEqual(value.elementType, .button)
        XCTAssertGreaterThanOrEqual(value.frame.width + 0.001, 44)
        XCTAssertGreaterThanOrEqual(value.frame.height + 0.001, 44)
    }
}

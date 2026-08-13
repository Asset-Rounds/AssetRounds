import Foundation
import XCTest

final class S4_2PDFRetryUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testInjectedPDFFailureKeepsSavedReportUntilOneExplicitRetrySucceeds() throws {
        let app = try launch()
        createCompletedReport(in: app)

        let receipt = element(in: app, identifier: "s3.receipt.screen")
        XCTAssertTrue(receipt.waitForExistence(timeout: 20))
        XCTAssertEqual(
            element(in: app, identifier: "s3.receipt.saved").label,
            "Report saved on this device."
        )

        // The test-only launch posture is inert until startup sees this saved
        // pending report. Its one injected render failure is consumed there.
        app.terminate()
        app.launch()

        let failureScreen = element(in: app, identifier: "s4.pdf-failure.screen")
        XCTAssertTrue(failureScreen.waitForExistence(timeout: 20))
        let headline = element(in: app, identifier: "s4.pdf-failure.headline")
        XCTAssertTrue(headline.waitForExistence(timeout: 10))
        XCTAssertEqual(
            headline.label,
            "This report was saved, but its PDF is not available."
        )
        let retry = element(in: app, identifier: "s4.pdf-failure.retry")
        XCTAssertTrue(retry.waitForExistence(timeout: 10))
        XCTAssertEqual(retry.label, "Retry report")
        XCTAssertTrue(retry.isHittable)
        XCTAssertTrue(retry.isEnabled)
        XCTAssertGreaterThanOrEqual(retry.frame.width, 44)
        XCTAssertGreaterThanOrEqual(retry.frame.height, 44)

        // The view pins this report ID and disables the primary action before
        // invoking recovery, so a double tap still creates just one retry.
        retry.doubleTap()
        let startCheck = element(in: app, identifier: "s2.sign-detail.start-check")
        XCTAssertTrue(
            failureScreen.waitForNonExistence(timeout: 20),
            "The failure surface clears only after the one explicit retry succeeds."
        )
        XCTAssertTrue(
            startCheck.waitForExistence(timeout: 10),
            "The retained sign remains available after its PDF retry."
        )
        XCTAssertTrue(startCheck.isHittable)

        app.terminate()
        app.launch()
        XCTAssertTrue(startCheck.waitForExistence(timeout: 20))
        XCTAssertFalse(failureScreen.exists)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "S4.2 PDF retry completed"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    private func createCompletedReport(in app: XCUIApplication) {
        XCTAssertTrue(
            element(in: app, identifier: "s2.welcome.screen")
                .waitForExistence(timeout: 15)
        )
        element(in: app, identifier: "s2.welcome.add-first-sign").tap()

        let site = element(in: app, identifier: "s2.new-sign.site-label")
        let sign = element(in: app, identifier: "s2.new-sign.sign-label")
        XCTAssertTrue(site.waitForExistence(timeout: 10))
        site.tap()
        site.typeText("North Campus")
        sign.tap()
        sign.typeText("Monument Sign")
        dismissKeyboard(in: app)
        let saveSign = element(in: app, identifier: "s2.new-sign.save")
        scrollUntilHittable(saveSign, in: app)
        saveSign.tap()

        let start = element(in: app, identifier: "s2.sign-detail.start-check")
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        start.tap()

        let zone = element(in: app, identifier: "s3.preflight.time-zone")
        XCTAssertTrue(zone.waitForExistence(timeout: 10))
        zone.tap()
        zone.typeText("America/New_York")
        dismissKeyboard(in: app)
        toggle("s3.preflight.time-zone-confirmed", in: app)
        toggle("s3.preflight.after-dark", in: app)
        toggle("s3.preflight.safe-position", in: app)
        let begin = element(in: app, identifier: "s3.preflight.begin")
        scrollUntilHittable(begin, in: app)
        begin.tap()

        acceptFixture(in: app, heading: "1 of 2 · Wide view")
        acceptFixture(in: app, heading: "2 of 2 · Close view")

        let noVisibleIssue = element(in: app, identifier: "s3.outcome.no-visible-issue")
        XCTAssertTrue(noVisibleIssue.waitForExistence(timeout: 15))
        noVisibleIssue.tap()
        let continueButton = element(in: app, identifier: "s3.outcome.continue")
        scrollUntilHittable(continueButton, in: app)
        continueButton.tap()

        let saveReport = element(in: app, identifier: "s3.review.save-report")
        XCTAssertTrue(saveReport.waitForExistence(timeout: 15))
        scrollUntilHittable(saveReport, in: app)
        saveReport.tap()
    }

    @MainActor
    private func acceptFixture(in app: XCUIApplication, heading: String) {
        let captureHeading = element(in: app, identifier: "s3.capture.heading")
        XCTAssertTrue(captureHeading.waitForExistence(timeout: 15))
        XCTAssertEqual(captureHeading.label, heading)

        let importFixture = element(in: app, identifier: "s3.capture.import-fixture")
        scrollUntilHittable(importFixture, in: app)
        importFixture.tap()
        XCTAssertTrue(
            element(in: app, identifier: "s3.capture.preview")
                .waitForExistence(timeout: 15)
        )
        let usePhoto = element(in: app, identifier: "s3.capture.use-photo")
        scrollUntilHittable(usePhoto, in: app)
        usePhoto.tap()
    }

    @MainActor
    private func launch() throws -> XCUIApplication {
        let bundle = Bundle(for: S4_2PDFRetryUITests.self)
        let wideURL = try XCTUnwrap(
            bundle.url(
                forResource: "S3_2WideInput",
                withExtension: "png",
                subdirectory: "Fixtures"
            ) ?? bundle.url(forResource: "S3_2WideInput", withExtension: "png")
        )
        let closeURL = try XCTUnwrap(
            bundle.url(
                forResource: "S3_2CloseInput",
                withExtension: "png",
                subdirectory: "Fixtures"
            ) ?? bundle.url(forResource: "S3_2CloseInput", withExtension: "png")
        )

        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleInterfaceStyle", "Light",
            "--s1-ui-test-light-mode",
            "--s3-2-ui-test-imported-fixtures",
            "--s4-2-ui-test-render-failure-once",
        ]
        app.launchEnvironment["S3_2_WIDE_FIXTURE_BASE64"] = try Data(
            contentsOf: wideURL
        ).base64EncodedString()
        app.launchEnvironment["S3_2_CLOSE_FIXTURE_BASE64"] = try Data(
            contentsOf: closeURL
        ).base64EncodedString()
        app.launch()
        return app
    }

    @MainActor
    private func toggle(_ identifier: String, in app: XCUIApplication) {
        let control = element(in: app, identifier: identifier)
        scrollUntilHittable(control, in: app)
        control.tap()
        XCTAssertEqual(control.value as? String, "1")
    }

    @MainActor
    private func dismissKeyboard(in app: XCUIApplication) {
        guard app.keyboards.firstMatch.exists else { return }
        let returnKey = app.keyboards.buttons["Return"]
        if returnKey.exists { returnKey.tap() } else { app.swipeDown() }
    }

    @MainActor
    private func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 {
            if element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }

    @MainActor
    private func element(in app: XCUIApplication, identifier: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch
    }
}

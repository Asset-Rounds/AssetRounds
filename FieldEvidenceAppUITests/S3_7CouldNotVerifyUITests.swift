import Foundation
import XCTest

final class S3_7CouldNotVerifyUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testOneWideCouldNotVerifySavesHonestIncompleteReportAndRelaunches() throws {
        let app = try launch()
        createDraft(in: app)
        acceptWideFixture(in: app)

        let closeHeading = element(in: app, identifier: "s3.capture.heading")
        XCTAssertTrue(closeHeading.waitForExistence(timeout: 15))
        XCTAssertEqual(closeHeading.label, "2 of 2 · Close view")
        let cannotComplete = element(in: app, identifier: "s3.capture.cannot-complete")
        XCTAssertTrue(cannotComplete.exists)
        XCTAssertEqual(cannotComplete.label, "Cannot complete")
        cannotComplete.tap()

        XCTAssertTrue(
            element(in: app, identifier: "s3.outcome.screen")
                .waitForExistence(timeout: 15)
        )
        let couldNotVerify = element(
            in: app,
            identifier: "s3.outcome.could-not-verify"
        )
        XCTAssertTrue(couldNotVerify.exists)
        XCTAssertEqual(couldNotVerify.label, "Could not verify")
        XCTAssertEqual(couldNotVerify.value as? String, "Selected")
        let reason = element(
            in: app,
            identifier: "s3.outcome.cnv.reason.required_view_obstructed"
        )
        scrollUntilHittable(reason, in: app)
        XCTAssertEqual(reason.label, "Required view is blocked")
        reason.tap()
        XCTAssertEqual(reason.value as? String, "Selected")

        let note = element(in: app, identifier: "s3.outcome.cnv.note")
        XCTAssertTrue(note.waitForExistence(timeout: 10))
        note.tap()
        note.typeText("Close view blocked by branches.")
        dismissKeyboard(in: app)
        let outcomeContinue = element(in: app, identifier: "s3.outcome.continue")
        scrollUntilHittable(outcomeContinue, in: app)
        XCTAssertTrue(outcomeContinue.isEnabled)
        outcomeContinue.tap()

        XCTAssertTrue(
            element(in: app, identifier: "s3.review.screen")
                .waitForExistence(timeout: 15)
        )
        XCTAssertTrue(
            element(in: app, identifier: "s3.review.could-not-verify").exists
        )
        XCTAssertTrue(app.staticTexts["Required view is blocked"].exists)
        XCTAssertTrue(app.staticTexts["Close view blocked by branches."].exists)
        let wide = element(in: app, identifier: "s3.review.evidence.wide")
        let close = element(in: app, identifier: "s3.review.evidence.close")
        XCTAssertTrue(wide.exists)
        XCTAssertTrue(close.exists)
        XCTAssertTrue(app.staticTexts["Photo saved for this check"].exists)
        XCTAssertTrue(app.staticTexts["Not captured — Could not verify"].exists)
        let back = element(in: app, identifier: "s3.review.back")
        XCTAssertTrue(back.exists)
        XCTAssertEqual(back.label, "Back")

        let save = element(in: app, identifier: "s3.review.save-report")
        scrollUntilHittable(save, in: app)
        XCTAssertEqual(save.label, "Save and finish")
        save.doubleTap()
        XCTAssertTrue(
            element(in: app, identifier: "s3.receipt.screen")
                .waitForExistence(timeout: 20)
        )
        XCTAssertEqual(
            element(in: app, identifier: "s3.receipt.saved").label,
            "Report saved on this device."
        )
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "S3.7 honest incomplete value receipt"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.terminate()
        app.launch()
        XCTAssertTrue(
            element(in: app, identifier: "s2.sign-detail.start-check")
                .waitForExistence(timeout: 20)
        )
        XCTAssertFalse(element(in: app, identifier: "s3.capture.screen").exists)
    }

    @MainActor
    private func acceptWideFixture(in app: XCUIApplication) {
        let heading = element(in: app, identifier: "s3.capture.heading")
        XCTAssertTrue(heading.waitForExistence(timeout: 15))
        XCTAssertEqual(heading.label, "1 of 2 · Wide view")
        let importButton = element(in: app, identifier: "s3.capture.import-fixture")
        scrollUntilHittable(importButton, in: app)
        importButton.tap()
        XCTAssertTrue(
            element(in: app, identifier: "s3.capture.preview")
                .waitForExistence(timeout: 15)
        )
        let usePhoto = element(in: app, identifier: "s3.capture.use-photo")
        XCTAssertEqual(usePhoto.label, "Use Photo")
        scrollUntilHittable(usePhoto, in: app)
        usePhoto.tap()
    }

    @MainActor
    private func createDraft(in app: XCUIApplication) {
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
        let save = element(in: app, identifier: "s2.new-sign.save")
        scrollUntilHittable(save, in: app)
        save.tap()
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
        XCTAssertTrue(
            element(in: app, identifier: "s3.capture.screen")
                .waitForExistence(timeout: 15)
        )
    }

    @MainActor
    private func toggle(_ identifier: String, in app: XCUIApplication) {
        let control = element(in: app, identifier: identifier)
        scrollUntilHittable(control, in: app)
        control.tap()
        XCTAssertEqual(control.value as? String, "1")
    }

    @MainActor
    private func launch() throws -> XCUIApplication {
        let bundle = Bundle(for: S3_7CouldNotVerifyUITests.self)
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
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}

import Foundation
import XCTest

final class S3_6CameraRecoveryUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testDeniedCameraRecoversThroughResumableExitAndAuthorizedFixturePath() throws {
        let app = try launch()
        createDraft(in: app)

        XCTAssertFalse(app.alerts.firstMatch.exists)
        let takePhoto = element(in: app, identifier: "s3.capture.take-photo")
        let choosePhotos = element(in: app, identifier: "s3.capture.choose-photos")
        let cannotComplete = element(in: app, identifier: "s3.capture.cannot-complete")
        XCTAssertTrue(takePhoto.waitForExistence(timeout: 15))
        XCTAssertEqual(takePhoto.label, "Take photo")
        XCTAssertEqual(choosePhotos.label, "Choose from Photos")
        XCTAssertEqual(cannotComplete.label, "Cannot complete")
        XCTAssertFalse(element(in: app, identifier: "s3.capture.open-settings").exists)

        takePhoto.tap()
        let settings = element(in: app, identifier: "s3.capture.open-settings")
        XCTAssertTrue(settings.waitForExistence(timeout: 15))
        XCTAssertEqual(settings.label, "Open Settings")
        XCTAssertTrue(choosePhotos.exists)
        XCTAssertTrue(choosePhotos.isEnabled)
        XCTAssertTrue(cannotComplete.isEnabled)
        XCTAssertTrue(
            app.staticTexts[
                "Choose a photo, open Settings, or leave this check incomplete and return later."
            ].exists
        )

        scrollUntilHittable(cannotComplete, in: app)
        cannotComplete.tap()
        let startCheck = element(in: app, identifier: "s2.sign-detail.start-check")
        XCTAssertTrue(startCheck.waitForExistence(timeout: 15))
        startCheck.tap()

        let resumedHeading = element(in: app, identifier: "s3.capture.heading")
        XCTAssertTrue(resumedHeading.waitForExistence(timeout: 15))
        XCTAssertEqual(resumedHeading.label, "1 of 2 · Wide view")
        XCTAssertTrue(element(in: app, identifier: "s3.capture.take-photo").isEnabled)
        XCTAssertTrue(element(in: app, identifier: "s3.capture.choose-photos").isEnabled)
        XCTAssertFalse(element(in: app, identifier: "s3.capture.open-settings").exists)

        acceptAuthorizedCameraFixture(in: app, heading: "1 of 2 · Wide view")
        acceptAuthorizedCameraFixture(in: app, heading: "2 of 2 · Close view")

        XCTAssertTrue(
            element(in: app, identifier: "s3.outcome.screen")
                .waitForExistence(timeout: 15)
        )
        element(in: app, identifier: "s3.outcome.no-visible-issue").tap()
        let outcomeContinue = element(in: app, identifier: "s3.outcome.continue")
        scrollUntilHittable(outcomeContinue, in: app)
        outcomeContinue.tap()
        let save = element(in: app, identifier: "s3.review.save-report")
        XCTAssertTrue(save.waitForExistence(timeout: 15))
        scrollUntilHittable(save, in: app)
        save.tap()

        XCTAssertTrue(
            element(in: app, identifier: "s3.receipt.screen")
                .waitForExistence(timeout: 20)
        )
        XCTAssertEqual(
            element(in: app, identifier: "s3.receipt.saved").label,
            "Report saved on this device."
        )
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "S3.6 camera denial recovered check"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    private func acceptAuthorizedCameraFixture(in app: XCUIApplication, heading: String) {
        let headingElement = element(in: app, identifier: "s3.capture.heading")
        XCTAssertTrue(headingElement.waitForExistence(timeout: 15))
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", heading),
            object: headingElement
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed)
        let takePhoto = element(in: app, identifier: "s3.capture.take-photo")
        XCTAssertTrue(takePhoto.waitForExistence(timeout: 10))
        scrollUntilHittable(takePhoto, in: app)
        takePhoto.tap()
        XCTAssertFalse(app.alerts.firstMatch.exists)
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
        let bundle = Bundle(for: S3_6CameraRecoveryUITests.self)
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
            "--s3-6-ui-test-camera-denied-once",
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

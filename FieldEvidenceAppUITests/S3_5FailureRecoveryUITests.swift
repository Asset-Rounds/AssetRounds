import Foundation
import XCTest

final class S3_5FailureRecoveryUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLowStorageFailureIsActionableAndRetryFinishesTheCheck() throws {
        let app = try launch()
        createDraft(in: app)

        let importButton = element(in: app, identifier: "s3.capture.import-fixture")
        XCTAssertTrue(importButton.waitForExistence(timeout: 15))
        XCTAssertEqual(importButton.label, "Import test photo")
        scrollUntilHittable(importButton, in: app)
        importButton.tap()

        let recoveryCopy = app.staticTexts[
            "Free space is too low. Free space, then try again."
        ]
        XCTAssertTrue(recoveryCopy.waitForExistence(timeout: 15))
        XCTAssertTrue(importButton.isEnabled)
        XCTAssertFalse(element(in: app, identifier: "s3.capture.preview").exists)

        importButton.tap()
        XCTAssertTrue(
            element(in: app, identifier: "s3.capture.preview")
                .waitForExistence(timeout: 15)
        )
        usePhoto(in: app)

        acceptFixture(in: app, heading: "2 of 2 · Close view")
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
        XCTAssertEqual(save.label, "Save and finish")
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
        screenshot.name = "S3.5 low-storage retry value receipt"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    private func acceptFixture(in app: XCUIApplication, heading: String) {
        let headingElement = element(in: app, identifier: "s3.capture.heading")
        XCTAssertTrue(headingElement.waitForExistence(timeout: 15))
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", heading),
            object: headingElement
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed)
        let importButton = element(in: app, identifier: "s3.capture.import-fixture")
        scrollUntilHittable(importButton, in: app)
        importButton.tap()
        XCTAssertTrue(
            element(in: app, identifier: "s3.capture.preview")
                .waitForExistence(timeout: 15)
        )
        usePhoto(in: app)
    }

    @MainActor
    private func usePhoto(in app: XCUIApplication) {
        let usePhoto = element(in: app, identifier: "s3.capture.use-photo")
        XCTAssertTrue(usePhoto.waitForExistence(timeout: 10))
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
        let bundle = Bundle(for: S3_5FailureRecoveryUITests.self)
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
            "--s3-5-ui-test-low-storage-once",
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

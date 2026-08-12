import Foundation
import XCTest

final class S3_2ImportedCaptureUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testImportedWideRetakeCloseAndRelaunchPreserveCommittedProgress() throws {
        let app = try launch()
        createDraft(in: app)

        assertCaptureStep(
            in: app,
            heading: "1 of 2 · Wide view"
        )
        importFixture(in: app)
        usePhoto(in: app)
        assertCaptureStep(
            in: app,
            heading: "2 of 2 · Close view"
        )

        importFixture(in: app)
        let retake = element(in: app, identifier: "s3.capture.retake")
        XCTAssertTrue(retake.waitForExistence(timeout: 10))
        XCTAssertEqual(retake.label, "Retake")
        retake.tap()
        assertCaptureStep(
            in: app,
            heading: "2 of 2 · Close view"
        )

        app.terminate()
        app.launch()
        assertCaptureStep(
            in: app,
            heading: "2 of 2 · Close view"
        )

        importFixture(in: app)
        usePhoto(in: app)
        assertOutcomeUnavailable(in: app)

        app.terminate()
        app.launch()
        assertOutcomeUnavailable(in: app)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "S3.2 imported evidence resumed"
        screenshot.lifetime = .keepAlways
        add(screenshot)
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
        XCTAssertTrue(begin.isEnabled)
        begin.tap()
    }

    @MainActor
    private func assertCaptureStep(
        in app: XCUIApplication,
        heading: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            element(in: app, identifier: "s3.capture.screen")
                .waitForExistence(timeout: 15),
            file: file,
            line: line
        )
        let headingElement = element(in: app, identifier: "s3.capture.heading")
        XCTAssertTrue(headingElement.waitForExistence(timeout: 5), file: file, line: line)
        let headingExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", heading),
            object: headingElement
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [headingExpectation], timeout: 10),
            .completed,
            file: file,
            line: line
        )
        XCTAssertTrue(
            element(in: app, identifier: "s3.capture.import-fixture")
                .waitForExistence(timeout: 10),
            file: file,
            line: line
        )
        XCTAssertFalse(
            element(in: app, identifier: "s3.capture.preview").exists,
            file: file,
            line: line
        )
    }

    @MainActor
    private func importFixture(in app: XCUIApplication) {
        let importButton = element(in: app, identifier: "s3.capture.import-fixture")
        scrollUntilHittable(importButton, in: app)
        importButton.tap()
        XCTAssertTrue(
            element(in: app, identifier: "s3.capture.preview")
                .waitForExistence(timeout: 15)
        )
    }

    @MainActor
    private func usePhoto(in app: XCUIApplication) {
        let usePhoto = element(in: app, identifier: "s3.capture.use-photo")
        scrollUntilHittable(usePhoto, in: app)
        XCTAssertEqual(usePhoto.label, "Use Photo")
        usePhoto.tap()
    }

    @MainActor
    private func assertOutcomeUnavailable(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let unavailable = element(
            in: app,
            identifier: "s3.runner.outcome-unavailable"
        )
        XCTAssertTrue(unavailable.waitForExistence(timeout: 15), file: file, line: line)
        XCTAssertEqual(
            unavailable.label,
            "Outcome is unavailable until S3.3.",
            file: file,
            line: line
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
        let fixtureBundle = Bundle(for: S3_2ImportedCaptureUITests.self)
        let wideURL = try XCTUnwrap(
            fixtureBundle.url(
                forResource: "S3_2WideInput",
                withExtension: "png",
                subdirectory: "Fixtures"
            ) ?? fixtureBundle.url(forResource: "S3_2WideInput", withExtension: "png")
        )
        let closeURL = try XCTUnwrap(
            fixtureBundle.url(
                forResource: "S3_2CloseInput",
                withExtension: "png",
                subdirectory: "Fixtures"
            ) ?? fixtureBundle.url(forResource: "S3_2CloseInput", withExtension: "png")
        )

        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleInterfaceStyle",
            "Light",
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
        if returnKey.exists {
            returnKey.tap()
        } else {
            app.swipeDown()
        }
    }

    @MainActor
    private func scrollUntilHittable(
        _ element: XCUIElement,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for _ in 0..<12 {
            if element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable, file: file, line: line)
    }

    @MainActor
    private func element(in app: XCUIApplication, identifier: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch
    }
}

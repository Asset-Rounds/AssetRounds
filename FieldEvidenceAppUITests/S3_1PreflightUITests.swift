import XCTest

final class S3_1PreflightUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCancelThenBeginAndRelaunchResumeTheSoleDraft() {
        let app = launch()
        createFirstSignWithoutTimeZone(in: app)

        let startCheck = element(in: app, identifier: "s2.sign-detail.start-check")
        XCTAssertTrue(startCheck.waitForExistence(timeout: 10))
        XCTAssertTrue(startCheck.isEnabled)
        XCTAssertEqual(startCheck.label, "Start Check")
        startCheck.tap()

        assertInitialPreflight(in: app)
        let enteredZone = element(in: app, identifier: "s3.preflight.time-zone")
        enteredZone.tap()
        enteredZone.typeText("America/New_York")
        dismissKeyboard(in: app)
        toggle("s3.preflight.time-zone-confirmed", in: app)
        toggle("s3.preflight.after-dark", in: app)

        let cancel = element(in: app, identifier: "s3.preflight.cancel")
        scrollUntilHittable(cancel, in: app)
        XCTAssertEqual(cancel.label, "Cancel — no check started")
        cancel.tap()

        XCTAssertTrue(
            element(in: app, identifier: "s2.sign-detail.screen")
                .waitForExistence(timeout: 10)
        )
        let cancelledMessage = element(
            in: app,
            identifier: "s3.sign-detail.no-check-started"
        )
        XCTAssertTrue(cancelledMessage.waitForExistence(timeout: 5))
        XCTAssertEqual(cancelledMessage.label, "No check was started.")

        app.terminate()
        app.launch()
        XCTAssertTrue(
            element(in: app, identifier: "s2.sign-detail.screen")
                .waitForExistence(timeout: 15)
        )
        XCTAssertFalse(
            element(in: app, identifier: "s3.runner.capture-unavailable").exists
        )

        element(in: app, identifier: "s2.sign-detail.start-check").tap()
        assertInitialPreflight(in: app)

        let timeZone = element(in: app, identifier: "s3.preflight.time-zone")
        timeZone.tap()
        timeZone.typeText("America/New_York")
        dismissKeyboard(in: app)
        toggle("s3.preflight.time-zone-confirmed", in: app)
        toggle("s3.preflight.after-dark", in: app)
        toggle("s3.preflight.safe-position", in: app)

        let begin = element(in: app, identifier: "s3.preflight.begin")
        scrollUntilHittable(begin, in: app)
        XCTAssertTrue(begin.isEnabled)
        XCTAssertEqual(begin.label, "Begin check")
        begin.tap()
        assertCaptureUnavailable(in: app)

        app.terminate()
        app.launch()
        assertCaptureUnavailable(in: app)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "S3.1 sole draft resumed"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    private func createFirstSignWithoutTimeZone(in app: XCUIApplication) {
        let welcome = element(in: app, identifier: "s2.welcome.screen")
        XCTAssertTrue(welcome.waitForExistence(timeout: 15))
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
        XCTAssertTrue(
            element(in: app, identifier: "s2.sign-detail.screen")
                .waitForExistence(timeout: 15)
        )
    }

    @MainActor
    private func assertInitialPreflight(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            element(in: app, identifier: "s3.preflight.screen")
                .waitForExistence(timeout: 10),
            file: file,
            line: line
        )
        XCTAssertTrue(app.staticTexts["Ready for night check"].exists, file: file, line: line)

        let zone = element(in: app, identifier: "s3.preflight.time-zone")
        let confirmation = element(
            in: app,
            identifier: "s3.preflight.time-zone-confirmed"
        )
        XCTAssertTrue(zone.exists, file: file, line: line)
        XCTAssertTrue(confirmation.exists, file: file, line: line)

        let afterDark = element(in: app, identifier: "s3.preflight.after-dark")
        let safePosition = element(in: app, identifier: "s3.preflight.safe-position")
        XCTAssertTrue(afterDark.waitForExistence(timeout: 10), file: file, line: line)
        XCTAssertTrue(safePosition.waitForExistence(timeout: 10), file: file, line: line)
        XCTAssertEqual(
            afterDark.label,
            "It is dark enough to observe the sign's visible illumination.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            safePosition.label,
            "I am in a safe, authorized position to take these photos.",
            file: file,
            line: line
        )
        XCTAssertEqual(afterDark.value as? String, "0", file: file, line: line)
        XCTAssertEqual(safePosition.value as? String, "0", file: file, line: line)

        let begin = element(in: app, identifier: "s3.preflight.begin")
        scrollUntilHittable(begin, in: app, file: file, line: line)
        XCTAssertFalse(begin.isEnabled, file: file, line: line)
        XCTAssertEqual(begin.label, "Begin check", file: file, line: line)
    }

    @MainActor
    private func assertCaptureUnavailable(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let unavailable = element(
            in: app,
            identifier: "s3.runner.capture-unavailable"
        )
        XCTAssertTrue(unavailable.waitForExistence(timeout: 15), file: file, line: line)
        XCTAssertEqual(
            unavailable.label,
            "Capture is unavailable until S3.2.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            app.descendants(matching: .any)
                .matching(identifier: "s3.runner.capture-unavailable").count,
            1,
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
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleInterfaceStyle", "Light", "--s1-ui-test-light-mode"]
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

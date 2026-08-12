import XCTest

final class S2SignSetupUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testWelcomeCreateDetailAndRelaunchTheExactFirstSign() {
        let app = launch()

        let welcome = element(in: app, identifier: "s2.welcome.screen")
        XCTAssertTrue(welcome.waitForExistence(timeout: 15))
        XCTAssertEqual(
            element(in: app, identifier: "s2.welcome.title").label,
            "Turn tonight's sign check into a clear report."
        )
        let restoreData = element(
            in: app,
            identifier: "s2.welcome.restore-data-backup"
        )
        let restorePurchases = element(
            in: app,
            identifier: "s2.welcome.restore-purchases"
        )
        XCTAssertTrue(restoreData.exists)
        XCTAssertTrue(restorePurchases.exists)
        XCTAssertEqual(restoreData.label, "Restore data backup")
        XCTAssertEqual(restorePurchases.label, "Restore Purchases")
        XCTAssertFalse(restoreData.isEnabled)
        XCTAssertFalse(restorePurchases.isEnabled)

        element(in: app, identifier: "s2.welcome.view-sample").tap()
        XCTAssertTrue(
            element(in: app, identifier: "s2.sample.screen")
                .waitForExistence(timeout: 10)
        )
        XCTAssertTrue(app.staticTexts["Illuminated sign pack"].exists)
        element(in: app, identifier: "s2.sample.back").tap()
        XCTAssertTrue(welcome.waitForExistence(timeout: 10))

        element(in: app, identifier: "s2.welcome.add-first-sign").tap()
        XCTAssertTrue(
            element(in: app, identifier: "s2.new-sign.screen")
                .waitForExistence(timeout: 10)
        )

        let siteField = element(in: app, identifier: "s2.new-sign.site-label")
        let signField = element(in: app, identifier: "s2.new-sign.sign-label")
        element(in: app, identifier: "s2.new-sign.save").tap()
        let validation = element(in: app, identifier: "s2.new-sign.error")
        XCTAssertTrue(validation.waitForExistence(timeout: 5))
        waitForLabel(
            "Enter a customer or site name.",
            in: validation
        )
        siteField.typeText("North Campus")
        XCTAssertEqual(siteField.value as? String, "North Campus")
        XCTAssertNotEqual(signField.value as? String, "North Campus")
        signField.tap()
        signField.typeText("Monument Sign")
        dismissKeyboard(in: app)

        let optionalToggle = element(
            in: app,
            identifier: "s2.new-sign.optional-toggle"
        )
        scrollUntilHittable(optionalToggle, in: app)
        optionalToggle.tap()

        let addressField = element(in: app, identifier: "s2.new-sign.address")
        scrollUntilHittable(addressField, in: app)
        addressField.tap()
        addressField.typeText("10 Main Street")

        let timeZoneField = element(in: app, identifier: "s2.new-sign.time-zone")
        scrollUntilHittable(timeZoneField, in: app)
        timeZoneField.tap()
        timeZoneField.typeText("Mars/Olympus_Mons")
        dismissKeyboard(in: app)

        let invalidZoneSave = element(in: app, identifier: "s2.new-sign.save")
        scrollUntilHittable(invalidZoneSave, in: app)
        invalidZoneSave.tap()
        waitForLabel(
            "Enter an exact IANA time-zone identifier.",
            in: validation
        )
        XCTAssertEqual(
            app.descendants(matching: .any)
                .matching(identifier: "s2.new-sign.error").count,
            1
        )
        replaceText(in: timeZoneField, with: "America/New_York")
        XCTAssertEqual(timeZoneField.value as? String, "America/New_York")
        XCTAssertEqual(siteField.value as? String, "North Campus")
        XCTAssertEqual(signField.value as? String, "Monument Sign")
        dismissKeyboard(in: app)

        let confirmation = element(
            in: app,
            identifier: "s2.new-sign.time-zone-confirm"
        )
        scrollUntilHittable(confirmation, in: app)
        confirmation.tap()

        let save = element(in: app, identifier: "s2.new-sign.save")
        scrollUntilHittable(save, in: app)
        save.tap()
        assertExactDetail(in: app)

        let startCheck = element(
            in: app,
            identifier: "s2.sign-detail.start-check"
        )
        XCTAssertTrue(startCheck.exists)
        XCTAssertFalse(startCheck.isEnabled)
        XCTAssertEqual(startCheck.label, "Start Check")
        let unavailable = element(
            in: app,
            identifier: "s2.sign-detail.unavailable"
        )
        XCTAssertTrue(unavailable.exists)
        XCTAssertTrue(unavailable.label.contains("unavailable until the next setup step"))

        app.terminate()
        app.launch()
        assertExactDetail(in: app)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "S2 First sign reopened"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleInterfaceStyle", "Light", "--s1-ui-test-light-mode"]
        app.launch()
        return app
    }

    @MainActor
    private func assertExactDetail(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            element(in: app, identifier: "s2.sign-detail.screen")
                .waitForExistence(timeout: 15),
            file: file,
            line: line
        )
        assertLabel(
            "North Campus",
            identifier: "s2.sign-detail.site-label",
            in: app,
            file: file,
            line: line
        )
        assertLabel(
            "Monument Sign",
            identifier: "s2.sign-detail.sign-label",
            in: app,
            file: file,
            line: line
        )
        assertLabel(
            "10 Main Street",
            identifier: "s2.sign-detail.address",
            in: app,
            file: file,
            line: line
        )
        assertLabel(
            "America/New_York",
            identifier: "s2.sign-detail.time-zone",
            in: app,
            file: file,
            line: line
        )
    }

    @MainActor
    private func assertLabel(
        _ expected: String,
        identifier: String,
        in app: XCUIApplication,
        file: StaticString,
        line: UInt
    ) {
        let value = element(in: app, identifier: identifier)
        XCTAssertTrue(value.waitForExistence(timeout: 10), file: file, line: line)
        XCTAssertTrue(value.label.contains(expected), file: file, line: line)
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
    private func replaceText(in element: XCUIElement, with replacement: String) {
        let existingCount = (element.value as? String)?.count ?? 0
        if existingCount > 0 {
            element.typeText(
                String(repeating: XCUIKeyboardKey.delete.rawValue, count: existingCount)
            )
        }
        element.typeText(replacement)
    }

    @MainActor
    private func waitForLabel(
        _ expectedSubstring: String,
        in element: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", expectedSubstring),
            object: element
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 5),
            .completed,
            file: file,
            line: line
        )
    }

    @MainActor
    private func scrollUntilHittable(
        _ element: XCUIElement,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for _ in 0..<12 {
            if element.isHittable {
                return
            }
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

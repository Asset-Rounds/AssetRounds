import Foundation
import XCTest

final class S9_1FinalRCUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testFinalRCReportAndDataRightsRemainReachableAtXXXL() throws {
        XCUIDevice.shared.appearance = .light
        let app = try configuredApplication(
            appearance: "Light",
            appearanceFlag: "--s1-ui-test-light-mode",
            usesAccessibilityXXXL: false
        )
        app.launch()
        createReadyReport(in: app)

        app.terminate()
        XCUIDevice.shared.appearance = .dark
        configure(
            app,
            appearance: "Dark",
            appearanceFlag: "--s1-ui-test-dark-mode",
            usesAccessibilityXXXL: true
        )
        app.launch()

        reopenReportAtXXXL(in: app)
        proveSettingsAndDataRightsAtXXXL(in: app)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "S9.1 final RC settings and data rights at Accessibility XXXL"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    private func createReadyReport(in app: XCUIApplication) {
        XCTAssertTrue(
            element("s2.welcome.screen", in: app)
                .waitForExistence(timeout: 30)
        )
        tap("s2.welcome.add-first-sign", label: "Add first sign", in: app)
        enter("North Campus", into: "s2.new-sign.site-label", in: app)
        enter("Monument Sign", into: "s2.new-sign.sign-label", in: app)
        dismissKeyboard(in: app)
        tap("s2.new-sign.save", label: "Save and start check", in: app)

        XCTAssertTrue(
            element("s2.sign-detail.screen", in: app)
                .waitForExistence(timeout: 30)
        )
        tap("s2.sign-detail.start-check", label: "Start Check", in: app)
        enter("America/New_York", into: "s3.preflight.time-zone", in: app)
        dismissKeyboard(in: app)
        setToggle("s3.preflight.time-zone-confirmed", in: app)
        setToggle("s3.preflight.after-dark", in: app)
        setToggle("s3.preflight.safe-position", in: app)
        tap("s3.preflight.begin", label: "Begin check", in: app)

        capture("1 of 2 · Wide view", in: app)
        capture("2 of 2 · Close view", in: app)
        tap(
            "s3.outcome.no-visible-issue",
            label: "No visible issue",
            in: app
        )
        tap("s3.outcome.continue", label: "Continue", in: app)

        XCTAssertTrue(
            element("s3.review.screen", in: app)
                .waitForExistence(timeout: 30)
        )
        XCTAssertTrue(element("s3.review.evidence.wide", in: app).exists)
        XCTAssertTrue(element("s3.review.evidence.close", in: app).exists)
        tap("s3.review.save-report", label: "Save and finish", in: app)

        XCTAssertTrue(
            element("s3.receipt.screen", in: app)
                .waitForExistence(timeout: 45)
        )
        XCTAssertEqual(
            element("s3.receipt.saved", in: app).label,
            "Report saved on this device."
        )
        tap("s3.receipt.done", label: "Done", in: app)
        XCTAssertTrue(
            element("s2.sign-detail.screen", in: app)
                .waitForExistence(timeout: 30)
        )
    }

    @MainActor
    private func reopenReportAtXXXL(in app: XCUIApplication) {
        let shell = element("s1.shell.screen", in: app)
        XCTAssertTrue(shell.waitForExistence(timeout: 30))
        XCTAssertEqual(shell.value as? String, "Dark")
        XCTAssertTrue(
            element("s2.sign-detail.screen", in: app)
                .waitForExistence(timeout: 30)
        )

        tap(
            "s4.4.sign-detail.report-history",
            label: "Report history",
            in: app
        )
        XCTAssertTrue(
            element("s4.4.history.screen", in: app)
                .waitForExistence(timeout: 30)
        )
        waitForCount(1, identifier: "s4.4.reports.visit", in: app)
        tap("s4.4.reports.view-report", label: "View report", in: app)

        XCTAssertTrue(
            element("s4.3.report-detail.screen", in: app)
                .waitForExistence(timeout: 30)
        )
        let preview = element("s4.3.report-detail.preview", in: app)
        XCTAssertTrue(preview.waitForExistence(timeout: 20))
        XCTAssertEqual(preview.label, "Report PDF preview")
        XCTAssertFalse(preview.frame.isEmpty)
        for (identifier, label) in [
            ("s4.3.report-detail.share", "Share PDF"),
            ("s4.3.report-detail.save-to-files", "Save to Files"),
            ("s4.5.report-detail.correct", "Correct report"),
        ] {
            let control = element(identifier, in: app)
            scroll(control, in: app)
            assertButton(control, label: label, in: app)
        }
        tap("s4.3.report-detail.close", label: "Close", in: app)
        XCTAssertTrue(
            element("s4.4.history.screen", in: app)
                .waitForExistence(timeout: 20)
        )
        navigateBack(in: app)
        XCTAssertTrue(
            element("s2.sign-detail.screen", in: app)
                .waitForExistence(timeout: 20)
        )
    }

    @MainActor
    private func proveSettingsAndDataRightsAtXXXL(in app: XCUIApplication) {
        tap("s1.settings.button", label: "Settings", in: app)
        XCTAssertTrue(
            element("s1.settings.screen", in: app)
                .waitForExistence(timeout: 30)
        )

        for (identifier, label) in [
            ("s6.2.backup.settings-entry", "Back up current data"),
            ("s6.5.restore.settings-entry", "Restore data backup"),
            ("s8.3.diagnostics.settings-entry", "View diagnostics"),
            ("s8.4.feedback.settings-entry", "Send feedback"),
            ("s6.6.settings.erase-all", "Erase All"),
        ] {
            let control = element(identifier, in: app)
            scroll(control, in: app)
            assertButton(control, label: label, in: app)
        }

        tap(
            "s6.2.backup.settings-entry",
            label: "Back up current data",
            in: app
        )
        XCTAssertTrue(
            element("s6.2.backup.screen", in: app)
                .waitForExistence(timeout: 30)
        )
        XCTAssertEqual(element("s6.2.backup.sign-count", in: app).label, "1 sign")
        XCTAssertEqual(
            element("s6.2.backup.report-count", in: app).label,
            "1 report"
        )
        XCTAssertEqual(
            element("s6.2.backup.photo-count", in: app).label,
            "2 photos"
        )
        XCTAssertEqual(
            element("s6.2.backup.warning", in: app).label,
            "This backup contains sign details, notes, photos, and reports. It does not contain your subscription. Store and share it securely."
        )
        let backup = element("s6.2.backup.action", in: app)
        scroll(backup, in: app)
        assertButton(backup, label: "Back up current data", in: app)
        navigateBack(in: app)

        XCTAssertTrue(
            element("s1.settings.screen", in: app)
                .waitForExistence(timeout: 20)
        )
        tap("s6.6.settings.erase-all", label: "Erase All", in: app)
        XCTAssertTrue(
            element("s6.6.erase.screen", in: app)
                .waitForExistence(timeout: 30)
        )
        XCTAssertTrue(
            app.staticTexts[
                "Erase all local sign details, notes, photos, reports, and the anonymous free-report count from this app. This cannot be undone."
            ].waitForExistence(timeout: 15)
        )
        XCTAssertTrue(
            app.staticTexts[
                "This does not cancel your Apple subscription. Backups saved outside this app are not deleted."
            ].waitForExistence(timeout: 15)
        )
        tap("s6.6.erase.cancel", label: "Cancel", in: app)
        XCTAssertTrue(
            element("s1.settings.screen", in: app)
                .waitForExistence(timeout: 20)
        )
        let terminalErase = element("s6.6.settings.erase-all", in: app)
        scroll(terminalErase, in: app)
        assertButton(terminalErase, label: "Erase All", in: app)
    }

    @MainActor
    private func capture(_ heading: String, in app: XCUIApplication) {
        let value = element("s3.capture.heading", in: app)
        XCTAssertTrue(value.waitForExistence(timeout: 25))
        XCTAssertTrue(
            wait(
                for: value,
                predicate: "label == %@",
                argument: heading,
                timeout: 20
            )
        )
        tap(
            "s3.capture.import-fixture",
            label: "Import test photo",
            in: app
        )
        let preview = element("s3.capture.preview", in: app)
        XCTAssertTrue(preview.waitForExistence(timeout: 20))
        XCTAssertEqual(preview.label, "Imported photo preview")
        tap("s3.capture.use-photo", label: "Use Photo", in: app)
    }

    @MainActor
    private func configuredApplication(
        appearance: String,
        appearanceFlag: String,
        usesAccessibilityXXXL: Bool
    ) throws -> XCUIApplication {
        let bundle = Bundle(for: Self.self)
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
        app.launchEnvironment["S3_2_WIDE_FIXTURE_BASE64"] = try Data(
            contentsOf: wideURL
        ).base64EncodedString()
        app.launchEnvironment["S3_2_CLOSE_FIXTURE_BASE64"] = try Data(
            contentsOf: closeURL
        ).base64EncodedString()
        configure(
            app,
            appearance: appearance,
            appearanceFlag: appearanceFlag,
            usesAccessibilityXXXL: usesAccessibilityXXXL
        )
        return app
    }

    @MainActor
    private func configure(
        _ app: XCUIApplication,
        appearance: String,
        appearanceFlag: String,
        usesAccessibilityXXXL: Bool
    ) {
        app.launchArguments = [
            "-AppleInterfaceStyle", appearance,
            appearanceFlag,
            "--s3-2-ui-test-imported-fixtures",
        ]
        if usesAccessibilityXXXL {
            app.launchArguments += [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXXXL",
            ]
        }
    }

    @MainActor
    private func enter(
        _ text: String,
        into identifier: String,
        in app: XCUIApplication
    ) {
        let value = element(identifier, in: app)
        scroll(value, in: app)
        XCTAssertTrue(value.isEnabled)
        value.tap()
        value.typeText(text)
    }

    @MainActor
    private func setToggle(_ identifier: String, in app: XCUIApplication) {
        let value = element(identifier, in: app)
        scroll(value, in: app)
        XCTAssertEqual(value.elementType, .switch)
        assertMinimumGeometry(value)
        if (value.value as? String) != "1" {
            value.tap()
        }
        XCTAssertTrue(
            wait(
                for: value,
                predicate: "value == %@",
                argument: "1",
                timeout: 10
            )
        )
    }

    @MainActor
    private func tap(
        _ identifier: String,
        label: String,
        in app: XCUIApplication
    ) {
        let value = element(identifier, in: app)
        scroll(value, in: app)
        assertButton(value, label: label, in: app)
        value.tap()
    }

    @MainActor
    private func assertButton(
        _ value: XCUIElement,
        label: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(value.waitForExistence(timeout: 20), file: file, line: line)
        XCTAssertEqual(value.label, label, file: file, line: line)
        XCTAssertEqual(value.elementType, .button, file: file, line: line)
        XCTAssertTrue(value.isEnabled, file: file, line: line)
        if !value.isHittable {
            scroll(value, in: app)
        }
        XCTAssertTrue(value.isHittable, file: file, line: line)
        assertMinimumGeometry(value, file: file, line: line)
    }

    @MainActor
    private func assertMinimumGeometry(
        _ value: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertGreaterThanOrEqual(
            value.frame.width + 0.001,
            44,
            file: file,
            line: line
        )
        XCTAssertGreaterThanOrEqual(
            value.frame.height + 0.001,
            44,
            file: file,
            line: line
        )
    }

    @MainActor
    private func waitForCount(
        _ count: Int,
        identifier: String,
        in app: XCUIApplication
    ) {
        let values = app.descendants(matching: .any)
            .matching(identifier: identifier)
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count == %d", count),
            object: values
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 30),
            .completed
        )
    }

    @MainActor
    private func wait(
        for value: XCUIElement,
        predicate format: String,
        argument: String,
        timeout: TimeInterval
    ) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: format, argument),
            object: value
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private func dismissKeyboard(in app: XCUIApplication) {
        guard app.keyboards.firstMatch.exists else { return }
        for keyName in ["Return", "Done"] {
            let key = app.keyboards.buttons[keyName]
            if key.exists {
                key.tap()
                return
            }
        }
        app.swipeDown()
    }

    @MainActor
    private func navigateBack(in app: XCUIApplication) {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(back.waitForExistence(timeout: 15))
        XCTAssertTrue(back.isHittable)
        back.tap()
    }

    @MainActor
    private func scroll(_ value: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<24 {
            if value.exists && value.isHittable { return }
            app.swipeUp()
        }
        for _ in 0..<24 {
            if value.exists && value.isHittable { return }
            app.swipeDown()
        }
        XCTAssertTrue(value.waitForExistence(timeout: 2))
        XCTAssertTrue(value.isHittable)
    }

    @MainActor
    private func element(
        _ identifier: String,
        in app: XCUIApplication
    ) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch
    }
}

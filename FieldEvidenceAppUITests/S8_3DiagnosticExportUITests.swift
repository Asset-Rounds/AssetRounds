import XCTest

final class S8_3DiagnosticExportUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testOwnerReviewsMinimalDiagnosticsThenOpensFilesAtXXXL() {
        XCUIDevice.shared.appearance = .dark
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleInterfaceStyle", "Dark",
            "--s1-ui-test-dark-mode",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()

        XCTAssertTrue(element("s2.welcome.screen", in: app)
            .waitForExistence(timeout: 30))
        tap("s1.settings.button", in: app)
        XCTAssertTrue(element("s1.settings.screen", in: app)
            .waitForExistence(timeout: 20))

        let entry = element("s8.3.diagnostics.settings-entry", in: app)
        scroll(entry, in: app)
        assertControl(entry, label: "View diagnostics")
        entry.tap()

        XCTAssertTrue(element("s8.3.diagnostics.screen", in: app)
            .waitForExistence(timeout: 20))
        XCTAssertEqual(
            element("s8.3.diagnostics.heading", in: app).label,
            "Diagnostics preview"
        )
        XCTAssertEqual(
            element("s8.3.diagnostics.authority", in: app).label,
            "These counters are best-effort lower-bound signals. They may be incomplete and are not payment, access, or cohort authority."
        )
        XCTAssertEqual(
            element("s8.3.diagnostics.privacy", in: app).label,
            "The export includes only app and device versions, local counters, and bounded system metrics when available. It never includes customer or sign details, addresses, notes, photos, reports, backups, paths, hashes, StoreKit details, credentials, or logs."
        )

        let counters = element("s8.3.diagnostics.counters", in: app)
        scroll(counters, in: app)
        XCTAssertTrue(counters.label.contains("Local counters"))
        XCTAssertTrue(counters.label.contains("Reports saved: 0"))

        let metricKit = element("s8.3.diagnostics.metrickit", in: app)
        scroll(metricKit, in: app)
        XCTAssertEqual(
            metricKit.label,
            "No recent bounded system summary is available."
        )

        let export = element("s8.3.diagnostics.export", in: app)
        scroll(export, in: app)
        assertControl(export, label: "Save diagnostics to Files")
        export.tap()

        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 20))
        cancel.tap()
        XCTAssertTrue(element("s8.3.diagnostics.screen", in: app)
            .waitForExistence(timeout: 15))

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "S8.3 reviewed minimal diagnostic export at Accessibility XXXL"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    private func assertControl(_ value: XCUIElement, label: String) {
        XCTAssertTrue(value.exists)
        XCTAssertEqual(value.label, label)
        XCTAssertEqual(value.elementType, .button)
        XCTAssertTrue(value.isEnabled)
        XCTAssertTrue(value.isHittable)
        XCTAssertGreaterThanOrEqual(value.frame.width + 0.001, 44)
        XCTAssertGreaterThanOrEqual(value.frame.height + 0.001, 44)
    }

    @MainActor
    private func tap(_ identifier: String, in app: XCUIApplication) {
        let value = element(identifier, in: app)
        scroll(value, in: app)
        XCTAssertTrue(value.isEnabled)
        value.tap()
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

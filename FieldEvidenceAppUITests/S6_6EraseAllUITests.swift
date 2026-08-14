import CoreGraphics
import Foundation
import XCTest

final class S6_6EraseAllUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testTypedEraseCancelsThenRebuildsEmptyGenerationAtXXXL() throws {
        let app = try launch()
        createOneCountedReport(in: app)

        app.terminate()
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()
        XCTAssertTrue(element("s2.sign-detail.screen", in: app)
            .waitForExistence(timeout: 30))
        assertReportCount(1, in: app)

        openErase(in: app)
        XCTAssertTrue(app.staticTexts[
            "Erase all local sign details, notes, photos, reports, and the anonymous free-report count from this app. This cannot be undone."
        ]
            .waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts[
            "This does not cancel your Apple subscription. Backups saved outside this app are not deleted."
        ].exists)
        let cancel = element("s6.6.erase.cancel", in: app)
        assertButton(cancel, label: "Cancel", in: app)
        cancel.tap()
        XCTAssertTrue(element("s1.settings.screen", in: app)
            .waitForExistence(timeout: 20))
        navigateBack(in: app)
        assertReportCount(1, in: app)

        openErase(in: app)
        enter(
            "ERASE",
            into: "s6.6.erase.confirmation",
            in: app
        )
        dismissKeyboard(in: app)
        let confirm = element("s6.6.erase.confirm", in: app)
        scroll(confirm, in: app)
        XCTAssertEqual(
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "enabled == true"),
                object: confirm
            )], timeout: 10),
            .completed
        )
        assertButton(confirm, label: "Erase All", in: app)
        confirm.tap()

        let welcome = element("s2.welcome.screen", in: app)
        XCTAssertTrue(welcome.waitForExistence(timeout: 90))
        XCTAssertFalse(element("s2.sign-detail.screen", in: app).exists)
        XCTAssertFalse(element("s4.4.history.screen", in: app).exists)
        XCTAssertFalse(element("s6.6.erase.screen", in: app).exists)

        app.terminate()
        app.launch()
        XCTAssertTrue(welcome.waitForExistence(timeout: 45))
        tap("s2.welcome.add-first-sign", in: app)
        enter("Fresh Campus", into: "s2.new-sign.site-label", in: app)
        enter("Fresh Sign", into: "s2.new-sign.sign-label", in: app)
        dismissKeyboard(in: app)
        tap("s2.new-sign.save", in: app)
        XCTAssertTrue(element("s2.sign-detail.screen", in: app)
            .waitForExistence(timeout: 30))
        XCTAssertEqual(
            element("s2.sign-detail.sign-label", in: app).label,
            "Fresh Sign"
        )

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "S6.6 fresh generation after typed Erase All"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}

private extension S6_6EraseAllUITests {
    @MainActor
    func createOneCountedReport(in app: XCUIApplication) {
        XCTAssertTrue(element("s2.welcome.screen", in: app)
            .waitForExistence(timeout: 25))
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
        XCTAssertTrue(element("s3.receipt.screen", in: app)
            .waitForExistence(timeout: 35))
        tap("s3.receipt.done", in: app)
        XCTAssertTrue(element("s2.sign-detail.screen", in: app)
            .waitForExistence(timeout: 30))
    }

    @MainActor
    func openErase(in app: XCUIApplication) {
        tap("s1.settings.button", in: app)
        XCTAssertTrue(element("s1.settings.screen", in: app)
            .waitForExistence(timeout: 20))
        tap("s6.6.settings.erase-all", in: app)
        XCTAssertTrue(element("s6.6.erase.screen", in: app)
            .waitForExistence(timeout: 20))
    }

    @MainActor
    func assertReportCount(_ count: Int, in app: XCUIApplication) {
        tap("s4.4.sign-detail.report-history", in: app)
        XCTAssertTrue(element("s4.4.history.screen", in: app)
            .waitForExistence(timeout: 25))
        waitForCount(count, identifier: "s4.4.reports.visit", in: app)
        navigateBack(in: app)
    }

    @MainActor
    func capture(_ heading: String, in app: XCUIApplication) {
        let value = element("s3.capture.heading", in: app)
        XCTAssertTrue(value.waitForExistence(timeout: 20))
        XCTAssertEqual(
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "label == %@", heading),
                object: value
            )], timeout: 20),
            .completed
        )
        tap("s3.capture.import-fixture", in: app)
        XCTAssertTrue(element("s3.capture.preview", in: app)
            .waitForExistence(timeout: 20))
        tap("s3.capture.use-photo", in: app)
    }

    @MainActor
    func launch() throws -> XCUIApplication {
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
            "-AppleInterfaceStyle", "Light",
            "--s1-ui-test-light-mode",
            "--s3-2-ui-test-imported-fixtures",
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

    @MainActor
    func element(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    @MainActor
    func tap(_ id: String, in app: XCUIApplication) {
        let value = element(id, in: app)
        scroll(value, in: app)
        XCTAssertTrue(value.isEnabled)
        value.tap()
    }

    @MainActor
    func enter(_ text: String, into id: String, in app: XCUIApplication) {
        let value = element(id, in: app)
        scroll(value, in: app)
        value.tap()
        value.typeText(text)
    }

    @MainActor
    func toggle(_ id: String, in app: XCUIApplication) {
        let value = element(id, in: app)
        scroll(value, in: app)
        value.coordinate(
            withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)
        ).tap()
        if XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "1"),
            object: value
        )], timeout: 10) == .completed {
            return
        }
        let retry = element(id, in: app)
        scroll(retry, in: app)
        if retry.value as? String != "1" {
            retry.coordinate(
                withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)
            ).tap()
        }
        XCTAssertEqual(
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "value == %@", "1"),
                object: retry
            )], timeout: 10),
            .completed
        )
    }

    @MainActor
    func scroll(_ value: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(value.waitForExistence(timeout: 20))
        for _ in 0..<18 {
            if value.isHittable { return }
            app.swipeUp()
        }
        for _ in 0..<18 {
            if value.isHittable { return }
            app.swipeDown()
        }
        XCTAssertTrue(value.isHittable)
    }

    @MainActor
    func navigateBack(in app: XCUIApplication) {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(back.waitForExistence(timeout: 10))
        XCTAssertTrue(back.isHittable)
        back.tap()
    }

    @MainActor
    func dismissKeyboard(in app: XCUIApplication) {
        guard app.keyboards.firstMatch.exists else { return }
        let key = app.keyboards.buttons["Return"]
        key.exists ? key.tap() : app.swipeDown()
    }

    @MainActor
    func assertButton(
        _ value: XCUIElement,
        label: String,
        in app: XCUIApplication
    ) {
        scroll(value, in: app)
        XCTAssertEqual(value.label, label)
        XCTAssertEqual(value.elementType, .button)
        XCTAssertTrue(value.isEnabled)
        XCTAssertTrue(value.isHittable)
        XCTAssertGreaterThanOrEqual(value.frame.width + 0.001, 44)
        XCTAssertGreaterThanOrEqual(value.frame.height + 0.001, 44)
    }

    @MainActor
    func waitForCount(
        _ count: Int,
        identifier: String,
        in app: XCUIApplication
    ) {
        let query = app.descendants(matching: .any).matching(identifier: identifier)
        XCTAssertEqual(
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "count == %d", count),
                object: query
            )], timeout: 30),
            .completed
        )
    }
}

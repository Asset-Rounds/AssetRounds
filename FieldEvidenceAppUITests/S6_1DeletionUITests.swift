import Foundation
import XCTest

final class S6_1DeletionUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testWholeSignDeletionCancelsThenDeletesAndAllowsReplacementAtXXXL() throws {
        let app = try launch()
        createIssueWorkAndRecheck(in: app)

        app.terminate()
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()

        let detail = element("s2.sign-detail.screen", in: app)
        XCTAssertTrue(detail.waitForExistence(timeout: 30))
        assertReportCount(2, in: app)

        openDeletion(in: app)
        let message = element("s6.1.delete.message", in: app)
        XCTAssertTrue(message.waitForExistence(timeout: 15))
        XCTAssertEqual(
            message.label,
            "Delete this sign, its photos, and its reports from this app? This cannot be undone. Your free-report count will not reset. Erase All removes the remaining anonymous count."
        )
        let cancel = element("s6.1.delete.cancel", in: app)
        scroll(cancel, in: app)
        assertButton(cancel, label: "Cancel")
        cancel.tap()
        XCTAssertTrue(detail.waitForExistence(timeout: 20))
        assertReportCount(2, in: app)
        let resolved = element("s5.2.sign-detail.resolved", in: app)
        scroll(resolved, in: app)
        XCTAssertTrue(resolved.exists)

        openDeletion(in: app)
        let confirm = element("s6.1.delete.confirm", in: app)
        scroll(confirm, in: app)
        assertButton(confirm, label: "Delete sign")
        confirm.tap()

        let welcome = element("s2.welcome.screen", in: app)
        XCTAssertTrue(welcome.waitForExistence(timeout: 35))
        XCTAssertFalse(detail.exists)
        XCTAssertFalse(element("s4.4.history.screen", in: app).exists)
        XCTAssertFalse(element("s5.1.issue.screen", in: app).exists)

        tap("s2.welcome.add-first-sign", in: app)
        enter("Replacement Campus", into: "s2.new-sign.site-label", in: app)
        enter("Replacement Sign", into: "s2.new-sign.sign-label", in: app)
        dismissKeyboard(in: app)
        tap("s2.new-sign.save", in: app)
        XCTAssertTrue(detail.waitForExistence(timeout: 25))
        XCTAssertEqual(element("s2.sign-detail.sign-label", in: app).label, "Replacement Sign")

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "S6.1 deleted lineage and replacement live sign"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    private func createIssueWorkAndRecheck(in app: XCUIApplication) {
        XCTAssertTrue(element("s2.welcome.screen", in: app).waitForExistence(timeout: 25))
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
        tap("s3.outcome.visible-issue", in: app)
        tap("s3.outcome.issue.dark_section", in: app)
        tap("s3.outcome.continue", in: app)
        tap("s3.review.save-report", in: app)
        XCTAssertTrue(element("s3.receipt.screen", in: app).waitForExistence(timeout: 35))
        tap("s3.receipt.done", in: app)

        tap("s5.1.sign-detail.record-work", in: app)
        enter("Replaced failed power supply", into: "s5.1.work.description", in: app)
        dismissKeyboard(in: app)
        tap("s5.1.work.import-fixture", in: app)
        XCTAssertTrue(element("s5.1.work.photo", in: app).waitForExistence(timeout: 20))
        tap("s5.1.work.save", in: app)
        XCTAssertTrue(element("s5.1.issue.screen", in: app).waitForExistence(timeout: 35))
        back(in: app)
        tap("s5.1.sign-detail.recheck-due", in: app)
        tap("s5.2.issue.start-recheck", in: app)
        toggle("s3.preflight.after-dark", in: app)
        app.swipeUp()
        toggle("s3.preflight.safe-position", in: app)
        tap("s3.preflight.begin", in: app)
        capture("1 of 2 · Wide view", in: app)
        capture("2 of 2 · Close view", in: app)
        tap("s5.2.outcome.resolved", in: app)
        tap("s3.outcome.continue", in: app)
        tap("s3.review.save-report", in: app)
        XCTAssertTrue(element("s3.receipt.screen", in: app).waitForExistence(timeout: 35))
        tap("s3.receipt.done", in: app)
        XCTAssertTrue(element("s5.1.issue.screen", in: app).waitForExistence(timeout: 25))
        back(in: app)
        XCTAssertTrue(element("s2.sign-detail.screen", in: app).waitForExistence(timeout: 25))
    }

    @MainActor
    private func openDeletion(in app: XCUIApplication) {
        let action = element("s6.1.delete.action", in: app)
        scroll(action, in: app)
        assertButton(action, label: "Delete sign")
        action.tap()
        XCTAssertTrue(element("s6.1.delete.screen", in: app).waitForExistence(timeout: 15))
    }

    @MainActor
    private func assertReportCount(_ count: Int, in app: XCUIApplication) {
        tap("s4.4.sign-detail.report-history", in: app)
        XCTAssertTrue(element("s4.4.history.screen", in: app).waitForExistence(timeout: 25))
        let query = app.descendants(matching: .any).matching(identifier: "s4.4.reports.visit")
        XCTAssertEqual(
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "count == %d", count), object: query
            )], timeout: 20),
            .completed
        )
        back(in: app)
    }

    @MainActor
    private func capture(_ heading: String, in app: XCUIApplication) {
        let value = element("s3.capture.heading", in: app)
        XCTAssertTrue(value.waitForExistence(timeout: 20))
        XCTAssertEqual(
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "label == %@", heading), object: value
            )], timeout: 20), .completed
        )
        tap("s3.capture.import-fixture", in: app)
        XCTAssertTrue(element("s3.capture.preview", in: app).waitForExistence(timeout: 20))
        tap("s3.capture.use-photo", in: app)
    }

    @MainActor
    private func launch() throws -> XCUIApplication {
        let bundle = Bundle(for: Self.self)
        let wide = try XCTUnwrap(bundle.url(
            forResource: "S3_2WideInput", withExtension: "png", subdirectory: "Fixtures"
        ) ?? bundle.url(forResource: "S3_2WideInput", withExtension: "png"))
        let close = try XCTUnwrap(bundle.url(
            forResource: "S3_2CloseInput", withExtension: "png", subdirectory: "Fixtures"
        ) ?? bundle.url(forResource: "S3_2CloseInput", withExtension: "png"))
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleInterfaceStyle", "Light", "--s1-ui-test-light-mode",
            "--s3-2-ui-test-imported-fixtures",
        ]
        app.launchEnvironment["S3_2_WIDE_FIXTURE_BASE64"] = try Data(contentsOf: wide).base64EncodedString()
        let closeData = try Data(contentsOf: close)
        app.launchEnvironment["S3_2_CLOSE_FIXTURE_BASE64"] = closeData.base64EncodedString()
        app.launchEnvironment["S5_1_WORK_FIXTURE_BASE64"] = closeData.base64EncodedString()
        app.launch()
        return app
    }

    @MainActor private func element(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }
    @MainActor private func tap(_ id: String, in app: XCUIApplication) {
        let value = element(id, in: app); scroll(value, in: app); value.tap()
    }
    @MainActor private func enter(_ text: String, into id: String, in app: XCUIApplication) {
        let value = element(id, in: app); scroll(value, in: app)
        XCTAssertTrue(value.waitForExistence(timeout: 15)); value.tap(); value.typeText(text)
    }
    @MainActor private func toggle(_ id: String, in app: XCUIApplication) {
        let value = element(id, in: app); scroll(value, in: app); value.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "1"), object: value
        )], timeout: 10), .completed)
    }
    @MainActor private func scroll(_ value: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<18 { if value.isHittable { return }; app.swipeUp() }
        for _ in 0..<18 { if value.isHittable { return }; app.swipeDown() }
        XCTAssertTrue(value.isHittable)
    }
    @MainActor private func dismissKeyboard(in app: XCUIApplication) {
        guard app.keyboards.firstMatch.exists else { return }
        let key = app.keyboards.buttons["Return"]; key.exists ? key.tap() : app.swipeDown()
    }
    @MainActor private func back(in app: XCUIApplication) {
        let value = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(value.waitForExistence(timeout: 10)); value.tap()
    }
    @MainActor private func assertButton(_ value: XCUIElement, label: String) {
        XCTAssertTrue(value.waitForExistence(timeout: 15)); XCTAssertEqual(value.label, label)
        XCTAssertTrue(value.isEnabled); XCTAssertTrue(value.isHittable)
        XCTAssertEqual(value.elementType, .button)
        XCTAssertGreaterThanOrEqual(value.frame.width + 0.001, 44)
        XCTAssertGreaterThanOrEqual(value.frame.height + 0.001, 44)
    }
}

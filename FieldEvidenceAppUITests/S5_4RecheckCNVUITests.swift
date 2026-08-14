import Foundation
import XCTest

final class S5_4RecheckCNVUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testPartialRecheckCouldNotVerifyPreservesOriginalIssueAndAddsOneReport() throws {
        let app = try launch()
        createVisibleIssueReport(in: app)
        finishInitialReceipt(in: app)
        recordWork(in: app)

        app.terminate()
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()

        let signDetail = element(in: app, identifier: "s2.sign-detail.screen")
        XCTAssertTrue(signDetail.waitForExistence(timeout: 30))
        assertReportVisitCount(1, in: app)

        let recheckDue = element(in: app, identifier: "s5.1.sign-detail.recheck-due")
        scrollUntilHittable(recheckDue, in: app)
        assertControl(recheckDue, label: "Recheck due")
        recheckDue.tap()
        let issueScreen = element(in: app, identifier: "s5.1.issue.screen")
        XCTAssertTrue(issueScreen.waitForExistence(timeout: 20))
        let originalHeader = element(in: app, identifier: "s5.1.issue.header")
        XCTAssertTrue(originalHeader.waitForExistence(timeout: 10))
        XCTAssertEqual(originalHeader.label, "Section appears dark")
        let originalStatus = element(in: app, identifier: "s5.1.issue.status")
        XCTAssertTrue(waitForElement(
            originalStatus,
            matching: "label CONTAINS %@",
            argument: "Recheck due",
            timeout: 15
        ))
        let startRecheck = element(in: app, identifier: "s5.2.issue.start-recheck")
        scrollUntilHittable(startRecheck, in: app)
        assertControl(startRecheck, label: "Start recheck")
        startRecheck.tap()

        beginRecheckPreflight(in: app)
        acceptFixture(in: app, heading: "1 of 2 · Wide view")

        let closeHeading = element(in: app, identifier: "s3.capture.heading")
        XCTAssertTrue(waitForElement(
            closeHeading,
            matching: "label == %@",
            argument: "2 of 2 · Close view",
            timeout: 20
        ))
        let cannotComplete = element(in: app, identifier: "s3.capture.cannot-complete")
        scrollUntilHittable(cannotComplete, in: app)
        assertControl(cannotComplete, label: "Cannot complete")
        cannotComplete.tap()

        let outcome = element(in: app, identifier: "s3.outcome.screen")
        XCTAssertTrue(outcome.waitForExistence(timeout: 20))
        let couldNotVerify = element(in: app, identifier: "s3.outcome.could-not-verify")
        XCTAssertTrue(couldNotVerify.waitForExistence(timeout: 10))
        XCTAssertEqual(couldNotVerify.label, "Could not verify")
        XCTAssertEqual(couldNotVerify.value as? String, "Selected")
        let reason = element(
            in: app,
            identifier: "s3.outcome.cnv.reason.conditions_changed"
        )
        scrollUntilHittable(reason, in: app)
        assertControl(reason, label: "Conditions changed")
        reason.tap()
        XCTAssertTrue(waitForElement(
            reason,
            matching: "value == %@",
            argument: "Selected",
            timeout: 10
        ))
        let outcomeContinue = element(in: app, identifier: "s3.outcome.continue")
        scrollUntilHittable(outcomeContinue, in: app)
        XCTAssertTrue(outcomeContinue.isEnabled)
        outcomeContinue.tap()

        let review = element(in: app, identifier: "s3.review.screen")
        XCTAssertTrue(review.waitForExistence(timeout: 20))
        XCTAssertTrue(element(in: app, identifier: "s3.review.could-not-verify").exists)
        XCTAssertTrue(app.staticTexts["Conditions changed"].exists)
        XCTAssertTrue(app.staticTexts["Photo saved for this check"].exists)
        XCTAssertTrue(app.staticTexts["Not captured — Could not verify"].exists)
        let save = element(in: app, identifier: "s3.review.save-report")
        scrollUntilHittable(save, in: app)
        assertControl(save, label: "Save and finish")
        save.tap()

        let receipt = element(in: app, identifier: "s3.receipt.screen")
        XCTAssertTrue(receipt.waitForExistence(timeout: 35))
        let saved = element(in: app, identifier: "s3.receipt.saved")
        XCTAssertTrue(saved.waitForExistence(timeout: 15))
        XCTAssertEqual(saved.label, "Report saved on this device.")
        let viewReport = element(in: app, identifier: "s3.receipt.view-report")
        scrollUntilHittable(viewReport, in: app)
        viewReport.tap()
        XCTAssertTrue(element(in: app, identifier: "s4.3.report-detail.screen")
            .waitForExistence(timeout: 30))
        XCTAssertTrue(element(in: app, identifier: "s4.3.report-detail.preview")
            .waitForExistence(timeout: 20))
        navigateBack(in: app)
        XCTAssertTrue(receipt.waitForExistence(timeout: 15))
        finishRecheckReceipt(in: app)

        XCTAssertTrue(signDetail.waitForExistence(timeout: 25))
        assertReportVisitCount(2, in: app)
        XCTAssertTrue(waitForQueryCount(
            elements(in: app, identifier: "s5.1.sign-detail.recheck-due"),
            count: 1,
            timeout: 20
        ))
        XCTAssertEqual(elements(in: app, identifier: "s5.2.sign-detail.resolved").count, 0)
        let preservedIssue = element(in: app, identifier: "s5.1.sign-detail.recheck-due")
        scrollUntilHittable(preservedIssue, in: app)
        preservedIssue.tap()
        XCTAssertTrue(issueScreen.waitForExistence(timeout: 20))
        XCTAssertEqual(originalHeader.label, "Section appears dark")
        XCTAssertTrue(waitForElement(
            originalStatus,
            matching: "label CONTAINS %@",
            argument: "Recheck due",
            timeout: 15
        ))
        let nextRecheck = element(in: app, identifier: "s5.2.issue.start-recheck")
        scrollUntilHittable(nextRecheck, in: app)
        assertControl(nextRecheck, label: "Start recheck")
        XCTAssertEqual(elements(in: app, identifier: "s5.2.issue.start-recheck").count, 1)
        XCTAssertEqual(elements(in: app, identifier: "s5.1.issue.record-work").count, 0)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "S5.4 recheck could not verify preserves original recheck due issue"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    private func createVisibleIssueReport(in app: XCUIApplication) {
        XCTAssertTrue(element(in: app, identifier: "s2.welcome.screen")
            .waitForExistence(timeout: 25))
        tap("s2.welcome.add-first-sign", in: app)
        let site = element(in: app, identifier: "s2.new-sign.site-label")
        let sign = element(in: app, identifier: "s2.new-sign.sign-label")
        XCTAssertTrue(site.waitForExistence(timeout: 15))
        scrollUntilHittable(site, in: app)
        site.tap()
        site.typeText("North Campus")
        scrollUntilHittable(sign, in: app)
        sign.tap()
        sign.typeText("Monument Sign")
        dismissKeyboard(in: app)
        tap("s2.new-sign.save", in: app)
        tap("s2.sign-detail.start-check", in: app)

        let zone = element(in: app, identifier: "s3.preflight.time-zone")
        XCTAssertTrue(zone.waitForExistence(timeout: 15))
        scrollUntilHittable(zone, in: app)
        zone.tap()
        zone.typeText("America/New_York")
        dismissKeyboard(in: app)
        toggle("s3.preflight.time-zone-confirmed", in: app)
        toggle("s3.preflight.after-dark", in: app)
        toggle("s3.preflight.safe-position", in: app)
        tap("s3.preflight.begin", in: app)
        acceptFixture(in: app, heading: "1 of 2 · Wide view")
        acceptFixture(in: app, heading: "2 of 2 · Close view")
        tap("s3.outcome.visible-issue", in: app)
        tap("s3.outcome.issue.dark_section", in: app)
        tap("s3.outcome.continue", in: app)
        let save = element(in: app, identifier: "s3.review.save-report")
        XCTAssertTrue(save.waitForExistence(timeout: 20))
        scrollUntilHittable(save, in: app)
        save.tap()
    }

    @MainActor
    private func finishInitialReceipt(in app: XCUIApplication) {
        XCTAssertTrue(element(in: app, identifier: "s3.receipt.screen")
            .waitForExistence(timeout: 35))
        tap("s3.receipt.done", in: app)
        XCTAssertTrue(element(in: app, identifier: "s2.sign-detail.screen")
            .waitForExistence(timeout: 25))
    }

    @MainActor
    private func recordWork(in app: XCUIApplication) {
        tap("s5.1.sign-detail.record-work", in: app)
        let description = element(in: app, identifier: "s5.1.work.description")
        XCTAssertTrue(description.waitForExistence(timeout: 20))
        scrollUntilHittable(description, in: app)
        description.tap()
        description.typeText("Replaced failed power supply")
        dismissKeyboard(in: app)
        tap("s5.1.work.import-fixture", in: app)
        XCTAssertTrue(element(in: app, identifier: "s5.1.work.photo")
            .waitForExistence(timeout: 20))
        tap("s5.1.work.save", in: app)
        XCTAssertTrue(element(in: app, identifier: "s5.1.issue.screen")
            .waitForExistence(timeout: 35))
        let status = element(in: app, identifier: "s5.1.issue.status")
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertTrue(status.label.contains("Recheck due"))
    }

    @MainActor
    private func beginRecheckPreflight(in app: XCUIApplication) {
        XCTAssertTrue(element(in: app, identifier: "s3.preflight.screen")
            .waitForExistence(timeout: 20))
        toggle("s3.preflight.after-dark", in: app)
        app.swipeUp()
        toggle("s3.preflight.safe-position", in: app)
        let begin = element(in: app, identifier: "s3.preflight.begin")
        scrollUntilHittable(begin, in: app)
        assertControl(begin, label: "Begin check")
        begin.tap()
    }

    @MainActor
    private func finishRecheckReceipt(in app: XCUIApplication) {
        tap("s3.receipt.done", in: app)
        XCTAssertTrue(element(in: app, identifier: "s5.1.issue.screen")
            .waitForExistence(timeout: 25))
        navigateBack(in: app)
        XCTAssertTrue(element(in: app, identifier: "s2.sign-detail.screen")
            .waitForExistence(timeout: 25))
    }

    @MainActor
    private func acceptFixture(in app: XCUIApplication, heading: String) {
        let value = element(in: app, identifier: "s3.capture.heading")
        XCTAssertTrue(value.waitForExistence(timeout: 20))
        XCTAssertTrue(waitForElement(
            value,
            matching: "label == %@",
            argument: heading,
            timeout: 20
        ))
        tap("s3.capture.import-fixture", in: app)
        XCTAssertTrue(element(in: app, identifier: "s3.capture.preview")
            .waitForExistence(timeout: 20))
        tap("s3.capture.use-photo", in: app)
    }

    @MainActor
    private func assertReportVisitCount(_ count: Int, in app: XCUIApplication) {
        let history = element(in: app, identifier: "s4.4.sign-detail.report-history")
        scrollUntilHittable(history, in: app)
        assertControl(history, label: "Report history")
        history.tap()
        XCTAssertTrue(element(in: app, identifier: "s4.4.history.screen")
            .waitForExistence(timeout: 25))
        XCTAssertTrue(waitForQueryCount(
            elements(in: app, identifier: "s4.4.reports.visit"),
            count: count,
            timeout: 25
        ))
        navigateBack(in: app)
        XCTAssertTrue(element(in: app, identifier: "s2.sign-detail.screen")
            .waitForExistence(timeout: 20))
    }

    @MainActor
    private func launch() throws -> XCUIApplication {
        let bundle = Bundle(for: S5_4RecheckCNVUITests.self)
        let wideURL = try XCTUnwrap(
            bundle.url(forResource: "S3_2WideInput", withExtension: "png", subdirectory: "Fixtures")
                ?? bundle.url(forResource: "S3_2WideInput", withExtension: "png")
        )
        let closeURL = try XCTUnwrap(
            bundle.url(forResource: "S3_2CloseInput", withExtension: "png", subdirectory: "Fixtures")
                ?? bundle.url(forResource: "S3_2CloseInput", withExtension: "png")
        )
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleInterfaceStyle", "Light",
            "--s1-ui-test-light-mode",
            "--s3-2-ui-test-imported-fixtures",
        ]
        app.launchEnvironment["S3_2_WIDE_FIXTURE_BASE64"] = try Data(contentsOf: wideURL)
            .base64EncodedString()
        let close = try Data(contentsOf: closeURL)
        app.launchEnvironment["S3_2_CLOSE_FIXTURE_BASE64"] = close.base64EncodedString()
        app.launchEnvironment["S5_1_WORK_FIXTURE_BASE64"] = close.base64EncodedString()
        app.launch()
        return app
    }

    @MainActor
    private func tap(_ identifier: String, in app: XCUIApplication) {
        let control = element(in: app, identifier: identifier)
        scrollUntilHittable(control, in: app)
        control.tap()
    }

    @MainActor
    private func toggle(_ identifier: String, in app: XCUIApplication) {
        let control = element(in: app, identifier: identifier)
        scrollUntilHittable(control, in: app)
        control.tap()
        XCTAssertTrue(waitForElement(
            control,
            matching: "value == %@",
            argument: "1",
            timeout: 10
        ))
    }

    @MainActor
    private func assertControl(_ control: XCUIElement, label: String) {
        XCTAssertTrue(control.exists)
        XCTAssertTrue(control.isEnabled)
        XCTAssertEqual(control.label, label)
        XCTAssertTrue(control.isHittable)
        XCTAssertTrue(control.frame.width >= 44)
        XCTAssertTrue(control.frame.height >= 44)
    }

    @MainActor
    private func dismissKeyboard(in app: XCUIApplication) {
        guard app.keyboards.firstMatch.exists else { return }
        let returnKey = app.keyboards.buttons["Return"]
        if returnKey.exists { returnKey.tap() } else { app.swipeDown() }
    }

    @MainActor
    private func navigateBack(in app: XCUIApplication) {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(back.waitForExistence(timeout: 10))
        back.tap()
    }

    @MainActor
    private func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<16 {
            if element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }

    @MainActor
    private func waitForElement(
        _ element: XCUIElement,
        matching format: String,
        argument: String,
        timeout: TimeInterval
    ) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: format, argument),
            object: element
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private func waitForQueryCount(
        _ query: XCUIElementQuery,
        count: Int,
        timeout: TimeInterval
    ) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count == %d", count),
            object: query
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private func element(in app: XCUIApplication, identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    private func elements(in app: XCUIApplication, identifier: String) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: identifier)
    }
}

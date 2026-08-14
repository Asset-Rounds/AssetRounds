import Foundation
import XCTest

final class S5_3DifferentIssueUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testDifferentIssueResolvesOriginalAndLeavesOneFreshIssueOpen() throws {
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
        let startRecheck = element(in: app, identifier: "s5.2.issue.start-recheck")
        scrollUntilHittable(startRecheck, in: app)
        startRecheck.tap()

        beginRecheckPreflight(in: app)
        acceptFixture(in: app, heading: "1 of 2 · Wide view")
        acceptFixture(in: app, heading: "2 of 2 · Close view")

        let different = element(
            in: app,
            identifier: "s5.3.outcome.original-resolved-different-issue"
        )
        XCTAssertTrue(different.waitForExistence(timeout: 20))
        scrollUntilHittable(different, in: app)
        assertControl(different, label: "Original resolved, different visible issue")
        different.tap()
        let newLabel = element(in: app, identifier: "s3.outcome.issue.physical_damage")
        scrollUntilHittable(newLabel, in: app)
        assertControl(newLabel, label: "Visible physical damage")
        newLabel.tap()
        let outcomeContinue = element(in: app, identifier: "s3.outcome.continue")
        scrollUntilHittable(outcomeContinue, in: app)
        outcomeContinue.tap()

        let review = element(in: app, identifier: "s3.review.screen")
        XCTAssertTrue(review.waitForExistence(timeout: 20))
        let reviewOutcome = element(in: app, identifier: "s3.review.outcome")
        XCTAssertTrue(reviewOutcome.waitForExistence(timeout: 10))
        XCTAssertTrue(
            reviewOutcome.label.contains("Original resolved, different visible issue")
        )
        let reviewLabel = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", "Visible physical damage")
        ).firstMatch
        XCTAssertTrue(reviewLabel.waitForExistence(timeout: 10))
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
        let resolvedOriginal = element(in: app, identifier: "s5.2.sign-detail.resolved")
        scrollUntilHittable(resolvedOriginal, in: app)
        assertControl(resolvedOriginal, label: "Resolved")
        resolvedOriginal.tap()
        XCTAssertTrue(issueScreen.waitForExistence(timeout: 20))
        let resolvedStatus = element(in: app, identifier: "s5.1.issue.status")
        XCTAssertTrue(waitForElement(
            resolvedStatus,
            matching: "label CONTAINS %@",
            argument: "Resolved",
            timeout: 15
        ))
        XCTAssertEqual(originalHeader.label, "Section appears dark")

        navigateBack(in: app)
        XCTAssertTrue(issueScreen.waitForExistence(timeout: 20))
        let freshHeader = element(in: app, identifier: "s5.1.issue.header")
        XCTAssertTrue(waitForElement(
            freshHeader,
            matching: "label == %@",
            argument: "Visible physical damage",
            timeout: 20
        ))
        let openStatus = element(in: app, identifier: "s5.1.issue.status")
        XCTAssertTrue(waitForElement(
            openStatus,
            matching: "label CONTAINS %@",
            argument: "Record work",
            timeout: 15
        ))
        let recordWork = element(in: app, identifier: "s5.1.issue.record-work")
        assertControl(recordWork, label: "Record work")
        XCTAssertEqual(elements(in: app, identifier: "s5.1.issue.record-work").count, 1)
        XCTAssertFalse(element(in: app, identifier: "s5.2.issue.start-recheck").exists)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "S5.3 original resolved and one fresh selected-label issue open"
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
        let bundle = Bundle(for: S5_3DifferentIssueUITests.self)
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
        XCTAssertTrue(control.waitForExistence(timeout: 15))
        XCTAssertEqual(control.label, label)
        XCTAssertTrue(control.isEnabled)
        XCTAssertTrue(control.isHittable)
        XCTAssertEqual(control.elementType, .button)
        XCTAssertGreaterThanOrEqual(control.frame.width + 0.001, 44)
        XCTAssertGreaterThanOrEqual(control.frame.height + 0.001, 44)
    }

    @MainActor
    private func dismissKeyboard(in app: XCUIApplication) {
        guard app.keyboards.firstMatch.exists else { return }
        let returnKey = app.keyboards.buttons["Return"]
        returnKey.exists ? returnKey.tap() : app.swipeDown()
    }

    @MainActor
    private func navigateBack(in app: XCUIApplication) {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(back.waitForExistence(timeout: 10))
        XCTAssertTrue(back.isHittable)
        back.tap()
    }

    @MainActor
    private func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<18 {
            if element.isHittable { return }
            app.swipeUp()
        }
        for _ in 0..<18 {
            if element.isHittable { return }
            app.swipeDown()
        }
        XCTAssertTrue(element.isHittable)
    }

    @MainActor
    private func waitForElement(
        _ element: XCUIElement,
        matching format: String,
        argument: String? = nil,
        timeout: TimeInterval
    ) -> Bool {
        let predicate = argument.map { NSPredicate(format: format, $0) }
            ?? NSPredicate(format: format)
        return XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: predicate, object: element)],
            timeout: timeout
        ) == .completed
    }

    @MainActor
    private func waitForQueryCount(
        _ query: XCUIElementQuery,
        count: Int,
        timeout: TimeInterval
    ) -> Bool {
        XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "count == %d", count),
                object: query
            )],
            timeout: timeout
        ) == .completed
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

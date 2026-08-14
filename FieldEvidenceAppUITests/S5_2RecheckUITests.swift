import Foundation
import XCTest

final class S5_2RecheckUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testPersistedWorkStartsResolvedRecheckAndAddsExactlyOneReportRoot() throws {
        let app = try launch()
        createVisibleIssueReport(in: app)
        finishReceipt(in: app)
        recordWorkWithPhoto(in: app)

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
        let dueStatus = element(in: app, identifier: "s5.1.issue.status")
        XCTAssertTrue(dueStatus.waitForExistence(timeout: 10))
        XCTAssertTrue(dueStatus.label.contains("Recheck due"))
        let startRecheck = element(in: app, identifier: "s5.2.issue.start-recheck")
        scrollUntilHittable(startRecheck, in: app)
        assertControl(startRecheck, label: "Start recheck")
        startRecheck.tap()

        beginRecheckPreflight(in: app)
        acceptFixture(in: app, heading: "1 of 2 · Wide view")
        acceptFixture(in: app, heading: "2 of 2 · Close view")

        let resolved = element(in: app, identifier: "s5.2.outcome.resolved")
        XCTAssertTrue(resolved.waitForExistence(timeout: 20))
        scrollUntilHittable(resolved, in: app)
        assertControl(resolved, label: "Resolved")
        resolved.tap()
        let outcomeContinue = element(in: app, identifier: "s3.outcome.continue")
        scrollUntilHittable(outcomeContinue, in: app)
        outcomeContinue.tap()

        let review = element(in: app, identifier: "s3.review.screen")
        XCTAssertTrue(review.waitForExistence(timeout: 20))
        let reviewOutcome = element(in: app, identifier: "s3.review.outcome")
        XCTAssertTrue(reviewOutcome.waitForExistence(timeout: 10))
        XCTAssertTrue(reviewOutcome.label.contains("Resolved"))
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
        assertControl(viewReport, label: "View report")
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
        let resolvedIssue = element(in: app, identifier: "s5.2.sign-detail.resolved")
        scrollUntilHittable(resolvedIssue, in: app)
        assertControl(resolvedIssue, label: "Resolved")
        resolvedIssue.tap()

        XCTAssertTrue(issueScreen.waitForExistence(timeout: 20))
        let resolvedStatus = element(in: app, identifier: "s5.1.issue.status")
        XCTAssertTrue(resolvedStatus.waitForExistence(timeout: 10))
        XCTAssertTrue(resolvedStatus.label.contains("Resolved"))
        XCTAssertFalse(element(in: app, identifier: "s5.2.issue.start-recheck").exists)
        XCTAssertFalse(element(in: app, identifier: "s5.1.issue.record-work").exists)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "S5.2 original issue resolved after one new recheck report root"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    private func createVisibleIssueReport(in app: XCUIApplication) {
        XCTAssertTrue(element(in: app, identifier: "s2.welcome.screen")
            .waitForExistence(timeout: 25))
        let addSign = element(in: app, identifier: "s2.welcome.add-first-sign")
        scrollUntilHittable(addSign, in: app)
        addSign.tap()

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
        let saveSign = element(in: app, identifier: "s2.new-sign.save")
        scrollUntilHittable(saveSign, in: app)
        saveSign.tap()

        let start = element(in: app, identifier: "s2.sign-detail.start-check")
        XCTAssertTrue(start.waitForExistence(timeout: 20))
        scrollUntilHittable(start, in: app)
        start.tap()
        let zone = element(in: app, identifier: "s3.preflight.time-zone")
        XCTAssertTrue(zone.waitForExistence(timeout: 15))
        scrollUntilHittable(zone, in: app)
        zone.tap()
        zone.typeText("America/New_York")
        dismissKeyboard(in: app)
        toggle("s3.preflight.time-zone-confirmed", in: app)
        toggle("s3.preflight.after-dark", in: app)
        toggle("s3.preflight.safe-position", in: app)
        let begin = element(in: app, identifier: "s3.preflight.begin")
        scrollUntilHittable(begin, in: app)
        begin.tap()
        acceptFixture(in: app, heading: "1 of 2 · Wide view")
        acceptFixture(in: app, heading: "2 of 2 · Close view")

        let visible = element(in: app, identifier: "s3.outcome.visible-issue")
        XCTAssertTrue(visible.waitForExistence(timeout: 20))
        scrollUntilHittable(visible, in: app)
        visible.tap()
        let label = element(in: app, identifier: "s3.outcome.issue.dark_section")
        scrollUntilHittable(label, in: app)
        label.tap()
        let outcomeContinue = element(in: app, identifier: "s3.outcome.continue")
        scrollUntilHittable(outcomeContinue, in: app)
        outcomeContinue.tap()
        let saveReport = element(in: app, identifier: "s3.review.save-report")
        XCTAssertTrue(saveReport.waitForExistence(timeout: 20))
        scrollUntilHittable(saveReport, in: app)
        saveReport.tap()
    }

    @MainActor
    private func finishReceipt(in app: XCUIApplication) {
        let receipt = element(in: app, identifier: "s3.receipt.screen")
        XCTAssertTrue(receipt.waitForExistence(timeout: 35))
        let done = element(in: app, identifier: "s3.receipt.done")
        scrollUntilHittable(done, in: app)
        assertControl(done, label: "Done")
        done.tap()
        XCTAssertTrue(element(in: app, identifier: "s2.sign-detail.screen")
            .waitForExistence(timeout: 25))
    }

    @MainActor
    private func finishRecheckReceipt(in app: XCUIApplication) {
        let done = element(in: app, identifier: "s3.receipt.done")
        scrollUntilHittable(done, in: app)
        assertControl(done, label: "Done")
        done.tap()
        XCTAssertTrue(element(in: app, identifier: "s5.1.issue.screen")
            .waitForExistence(timeout: 25))
        navigateBack(in: app)
        XCTAssertTrue(element(in: app, identifier: "s2.sign-detail.screen")
            .waitForExistence(timeout: 25))
    }

    @MainActor
    private func recordWorkWithPhoto(in app: XCUIApplication) {
        let recordWork = element(in: app, identifier: "s5.1.sign-detail.record-work")
        XCTAssertTrue(recordWork.waitForExistence(timeout: 20))
        scrollUntilHittable(recordWork, in: app)
        recordWork.tap()

        let description = element(in: app, identifier: "s5.1.work.description")
        XCTAssertTrue(description.waitForExistence(timeout: 20))
        scrollUntilHittable(description, in: app)
        description.tap()
        description.typeText("Replaced failed power supply")
        dismissKeyboard(in: app)
        let importPhoto = element(in: app, identifier: "s5.1.work.import-fixture")
        scrollUntilHittable(importPhoto, in: app)
        importPhoto.tap()
        XCTAssertTrue(element(in: app, identifier: "s5.1.work.photo")
            .waitForExistence(timeout: 20))
        let save = element(in: app, identifier: "s5.1.work.save")
        scrollUntilHittable(save, in: app)
        save.tap()
        XCTAssertTrue(element(in: app, identifier: "s5.1.issue.screen")
            .waitForExistence(timeout: 35))
        let status = element(in: app, identifier: "s5.1.issue.status")
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertTrue(status.label.contains("Recheck due"))
    }

    @MainActor
    private func beginRecheckPreflight(in app: XCUIApplication) {
        let preflight = element(in: app, identifier: "s3.preflight.screen")
        XCTAssertTrue(preflight.waitForExistence(timeout: 20))
        toggle("s3.preflight.after-dark", in: app)
        toggle("s3.preflight.safe-position", in: app)
        let begin = element(in: app, identifier: "s3.preflight.begin")
        scrollUntilHittable(begin, in: app)
        assertControl(begin, label: "Begin check")
        begin.tap()
    }

    @MainActor
    private func acceptFixture(in app: XCUIApplication, heading: String) {
        let headingElement = element(in: app, identifier: "s3.capture.heading")
        XCTAssertTrue(headingElement.waitForExistence(timeout: 20))
        XCTAssertTrue(waitForElement(
            headingElement,
            matching: "label == %@",
            argument: heading,
            timeout: 20
        ))
        let importButton = element(in: app, identifier: "s3.capture.import-fixture")
        scrollUntilHittable(importButton, in: app)
        importButton.tap()
        XCTAssertTrue(element(in: app, identifier: "s3.capture.preview")
            .waitForExistence(timeout: 20))
        let usePhoto = element(in: app, identifier: "s3.capture.use-photo")
        scrollUntilHittable(usePhoto, in: app)
        usePhoto.tap()
    }

    @MainActor
    private func assertReportVisitCount(_ count: Int, in app: XCUIApplication) {
        let history = element(in: app, identifier: "s4.4.sign-detail.report-history")
        scrollUntilHittable(history, in: app)
        assertControl(history, label: "Report history")
        history.tap()
        XCTAssertTrue(element(in: app, identifier: "s4.4.history.screen")
            .waitForExistence(timeout: 25))
        let visits = elements(in: app, identifier: "s4.4.reports.visit")
        XCTAssertTrue(waitForQueryCount(visits, count: count, timeout: 25))
        navigateBack(in: app)
        XCTAssertTrue(element(in: app, identifier: "s2.sign-detail.screen")
            .waitForExistence(timeout: 20))
    }

    @MainActor
    private func launch() throws -> XCUIApplication {
        let bundle = Bundle(for: S5_2RecheckUITests.self)
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
        let wide = try Data(contentsOf: wideURL)
        let close = try Data(contentsOf: closeURL)
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleInterfaceStyle", "Light",
            "--s1-ui-test-light-mode",
            "--s3-2-ui-test-imported-fixtures",
        ]
        app.launchEnvironment["S3_2_WIDE_FIXTURE_BASE64"] = wide.base64EncodedString()
        app.launchEnvironment["S3_2_CLOSE_FIXTURE_BASE64"] = close.base64EncodedString()
        app.launchEnvironment["S5_1_WORK_FIXTURE_BASE64"] = close.base64EncodedString()
        app.launch()
        return app
    }

    @MainActor
    private func assertControl(
        _ control: XCUIElement,
        label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(control.waitForExistence(timeout: 15), file: file, line: line)
        XCTAssertEqual(control.label, label, file: file, line: line)
        XCTAssertTrue(control.isEnabled, file: file, line: line)
        XCTAssertTrue(control.isHittable, file: file, line: line)
        XCTAssertEqual(control.elementType, .button, file: file, line: line)
        assertMinimumGeometry(control, file: file, line: line)
    }

    @MainActor
    private func assertMinimumGeometry(
        _ element: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let tolerance: CGFloat = 0.001
        XCTAssertGreaterThanOrEqual(element.frame.width + tolerance, 44, file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.height + tolerance, 44, file: file, line: line)
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
        let expectation = XCTNSPredicateExpectation(
            predicate: argument.map { NSPredicate(format: format, $0) }
                ?? NSPredicate(format: format),
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

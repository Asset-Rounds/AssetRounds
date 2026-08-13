import Foundation
import XCTest

final class S4_4ReportsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testReportsFiltersHistoryDetailAndStrictPreviousVisitComparison() throws {
        let app = try launch()
        createSign(in: app)
        completeCouldNotVerifyCheck(in: app)
        finishReceipt(in: app)

        let signDetail = element(in: app, identifier: "s2.sign-detail.screen")
        XCTAssertTrue(signDetail.waitForExistence(timeout: 20))
        let history = element(in: app, identifier: "s4.4.sign-detail.report-history")
        scrollUntilHittable(history, in: app)
        assertPrimaryControl(history, label: "Report history")
        history.tap()

        let historyScreen = element(in: app, identifier: "s4.4.history.screen")
        XCTAssertTrue(historyScreen.waitForExistence(timeout: 20))
        waitForCount(1, identifier: "s4.4.reports.visit", in: app)
        XCTAssertFalse(element(in: app, identifier: "s4.4.reports.compare").exists)
        XCTAssertFalse(element(in: app, identifier: "s4.4.comparison.screen").exists)
        navigateBack(in: app)

        let reportsTab = element(in: app, identifier: "s1.tab.reports")
        assertPrimaryControl(reportsTab, label: "Reports")
        reportsTab.tap()
        let reportsScreen = element(in: app, identifier: "s4.4.reports.screen")
        XCTAssertTrue(reportsScreen.waitForExistence(timeout: 20))

        let siteFilter = element(in: app, identifier: "s4.4.reports.site-filter")
        let signFilter = element(in: app, identifier: "s4.4.reports.sign-filter")
        scrollUntilHittable(siteFilter, in: app)
        assertPrimaryControl(siteFilter, label: "All sites")
        selectFilter(siteFilter, value: "North Campus", in: app)
        XCTAssertTrue(
            waitForElement(
                siteFilter,
                matching: "label == %@",
                argument: "North Campus"
            )
        )
        scrollUntilHittable(signFilter, in: app)
        assertPrimaryControl(signFilter, label: "All signs")
        selectFilter(signFilter, value: "Monument Sign", in: app)
        XCTAssertTrue(
            waitForElement(
                signFilter,
                matching: "label == %@",
                argument: "Monument Sign"
            )
        )
        waitForCount(1, identifier: "s4.4.reports.visit", in: app)

        let viewReport = element(in: app, identifier: "s4.4.reports.view-report")
        scrollUntilHittable(viewReport, in: app)
        assertPrimaryControl(viewReport, label: "View report")
        viewReport.tap()
        let detail = element(in: app, identifier: "s4.3.report-detail.screen")
        XCTAssertTrue(detail.waitForExistence(timeout: 20))
        XCTAssertTrue(
            element(in: app, identifier: "s4.3.report-detail.preview")
                .waitForExistence(timeout: 20)
        )
        let close = element(in: app, identifier: "s4.3.report-detail.close")
        scrollUntilHittable(close, in: app)
        assertPrimaryControl(close, label: "Close")
        close.tap()
        XCTAssertTrue(reportsScreen.waitForExistence(timeout: 15))

        let signsTab = element(in: app, identifier: "s1.tab.signs")
        assertPrimaryControl(signsTab, label: "Signs")
        signsTab.tap()
        XCTAssertTrue(signDetail.waitForExistence(timeout: 15))
        let startSecond = element(in: app, identifier: "s2.sign-detail.start-check")
        scrollUntilHittable(startSecond, in: app)
        assertPrimaryControl(startSecond, label: "Start Check")
        startSecond.tap()
        completeCheck(in: app)
        finishReceipt(in: app)
        XCTAssertTrue(signDetail.waitForExistence(timeout: 20))

        scrollUntilHittable(history, in: app)
        assertPrimaryControl(history, label: "Report history")
        history.tap()
        XCTAssertTrue(historyScreen.waitForExistence(timeout: 20))
        waitForCount(2, identifier: "s4.4.reports.visit", in: app)
        XCTAssertFalse(
            element(in: app, identifier: "s4.4.reports.compare").exists,
            "The immediate prior visit lacks Close evidence, so comparison must be omitted."
        )
        XCTAssertFalse(element(in: app, identifier: "s4.4.comparison.screen").exists)
        XCTAssertTrue(element(in: app, identifier: "s4.4.reports.view-report").exists)
        navigateBack(in: app)

        let startThird = element(in: app, identifier: "s2.sign-detail.start-check")
        scrollUntilHittable(startThird, in: app)
        assertPrimaryControl(startThird, label: "Start Check")
        startThird.tap()
        completeCheck(in: app)
        finishReceipt(in: app)
        XCTAssertTrue(signDetail.waitForExistence(timeout: 20))
        scrollUntilHittable(history, in: app)
        assertPrimaryControl(history, label: "Report history")
        history.tap()
        XCTAssertTrue(historyScreen.waitForExistence(timeout: 20))
        waitForCount(3, identifier: "s4.4.reports.visit", in: app)

        let standardCompare = element(in: app, identifier: "s4.4.reports.compare")
        scrollUntilHittable(standardCompare, in: app)
        assertPrimaryControl(standardCompare, label: "Compare with previous")

        app.terminate()
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()

        let accessibilitySignDetail = element(
            in: app,
            identifier: "s2.sign-detail.screen"
        )
        XCTAssertTrue(accessibilitySignDetail.waitForExistence(timeout: 20))
        let accessibilityHistory = element(
            in: app,
            identifier: "s4.4.sign-detail.report-history"
        )
        scrollUntilHittable(accessibilityHistory, in: app)
        assertPrimaryControl(accessibilityHistory, label: "Report history")
        accessibilityHistory.tap()
        XCTAssertTrue(
            element(in: app, identifier: "s4.4.history.screen")
                .waitForExistence(timeout: 20)
        )
        waitForCount(3, identifier: "s4.4.reports.visit", in: app)
        navigateBack(in: app)

        let accessibilityReportsTab = element(in: app, identifier: "s1.tab.reports")
        assertPrimaryControl(accessibilityReportsTab, label: "Reports")
        accessibilityReportsTab.tap()
        XCTAssertTrue(
            element(in: app, identifier: "s4.4.reports.screen")
                .waitForExistence(timeout: 20)
        )
        let accessibilityHeader = element(
            in: app,
            identifier: "s4.4.reports.header"
        )
        scrollUntilHittable(accessibilityHeader, in: app)
        XCTAssertEqual(accessibilityHeader.label, "Filter reports")
        let accessibilitySiteFilter = element(
            in: app,
            identifier: "s4.4.reports.site-filter"
        )
        let accessibilitySignFilter = element(
            in: app,
            identifier: "s4.4.reports.sign-filter"
        )
        scrollUntilHittable(accessibilitySiteFilter, in: app)
        assertPrimaryControl(accessibilitySiteFilter, label: "All sites")
        selectFilter(accessibilitySiteFilter, value: "North Campus", in: app)
        XCTAssertTrue(
            waitForElement(
                accessibilitySiteFilter,
                matching: "label == %@",
                argument: "North Campus"
            )
        )
        scrollUntilHittable(accessibilitySignFilter, in: app)
        assertPrimaryControl(accessibilitySignFilter, label: "All signs")
        selectFilter(accessibilitySignFilter, value: "Monument Sign", in: app)
        XCTAssertTrue(
            waitForElement(
                accessibilitySignFilter,
                matching: "label == %@",
                argument: "Monument Sign"
            )
        )
        waitForCount(3, identifier: "s4.4.reports.visit", in: app)

        let compare = element(in: app, identifier: "s4.4.reports.compare")
        scrollUntilHittable(compare, in: app)
        assertPrimaryControl(compare, label: "Compare with previous")
        compare.tap()

        let comparison = element(in: app, identifier: "s4.4.comparison.screen")
        XCTAssertTrue(comparison.waitForExistence(timeout: 20))
        for identifier in ["s4.4.comparison.then.wide",
                           "s4.4.comparison.then.close",
                           "s4.4.comparison.now.wide",
                           "s4.4.comparison.now.close"] {
            let image = element(in: app, identifier: identifier)
            XCTAssertTrue(image.waitForExistence(timeout: 15))
            scrollUntilHittable(image, in: app)
        }
        XCTAssertFalse(element(in: app, identifier: "s4.4.comparison.unavailable").exists)
        XCTAssertTrue(
            element(in: app, identifier: "s4.4.comparison.then.heading").exists
        )
        XCTAssertTrue(
            element(in: app, identifier: "s4.4.comparison.now.heading").exists
        )

        let comparisonTitle = app.navigationBars["Then and Now"]
        XCTAssertTrue(comparisonTitle.waitForExistence(timeout: 10))
        let thenHeading = element(in: app, identifier: "s4.4.comparison.then.heading")
        let nowHeading = element(in: app, identifier: "s4.4.comparison.now.heading")
        let thenClose = element(in: app, identifier: "s4.4.comparison.then.close")
        for _ in 0..<16 {
            if thenClose.isHittable && nowHeading.isHittable { break }
            app.swipeDown()
        }
        XCTAssertTrue(thenHeading.exists)
        XCTAssertTrue(thenClose.isHittable)
        XCTAssertTrue(nowHeading.isHittable)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "S4.4 strict previous-visit comparison"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    private func createSign(in app: XCUIApplication) {
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
        scrollUntilHittable(start, in: app)
        start.tap()
    }

    @MainActor
    private func completeCheck(in app: XCUIApplication) {
        beginCheck(in: app)
        acceptFixture(in: app, heading: "1 of 2 · Wide view")
        acceptFixture(in: app, heading: "2 of 2 · Close view")
        let noVisibleIssue = element(in: app, identifier: "s3.outcome.no-visible-issue")
        XCTAssertTrue(noVisibleIssue.waitForExistence(timeout: 15))
        noVisibleIssue.tap()
        continueAndSaveReport(in: app)
    }

    @MainActor
    private func completeCouldNotVerifyCheck(in app: XCUIApplication) {
        beginCheck(in: app)
        acceptFixture(in: app, heading: "1 of 2 · Wide view")
        let closeHeading = element(in: app, identifier: "s3.capture.heading")
        XCTAssertTrue(closeHeading.waitForExistence(timeout: 15))
        XCTAssertTrue(
            waitForElement(
                closeHeading,
                matching: "label == %@",
                argument: "2 of 2 · Close view"
            )
        )
        let cannotComplete = element(in: app, identifier: "s3.capture.cannot-complete")
        scrollUntilHittable(cannotComplete, in: app)
        assertPrimaryControl(cannotComplete, label: "Cannot complete")
        cannotComplete.tap()
        let couldNotVerify = element(in: app, identifier: "s3.outcome.could-not-verify")
        XCTAssertTrue(couldNotVerify.waitForExistence(timeout: 15))
        scrollUntilHittable(couldNotVerify, in: app)
        XCTAssertEqual(couldNotVerify.label, "Could not verify")
        let reason = element(
            in: app,
            identifier: "s3.outcome.cnv.reason.required_view_obstructed"
        )
        scrollUntilHittable(reason, in: app)
        XCTAssertEqual(reason.label, "Required view is blocked")
        reason.tap()
        continueAndSaveReport(in: app)
    }

    @MainActor
    private func beginCheck(in app: XCUIApplication) {
        let preflight = element(in: app, identifier: "s3.preflight.screen")
        XCTAssertTrue(preflight.waitForExistence(timeout: 15))
        let zone = element(in: app, identifier: "s3.preflight.time-zone")
        if zone.waitForExistence(timeout: 2) {
            zone.tap()
            zone.typeText("America/New_York")
            dismissKeyboard(in: app)
            toggle("s3.preflight.time-zone-confirmed", in: app)
        }
        toggle("s3.preflight.after-dark", in: app)
        toggle("s3.preflight.safe-position", in: app)
        let begin = element(in: app, identifier: "s3.preflight.begin")
        scrollUntilHittable(begin, in: app)
        begin.tap()
    }

    @MainActor
    private func continueAndSaveReport(in app: XCUIApplication) {
        let outcomeContinue = element(in: app, identifier: "s3.outcome.continue")
        scrollUntilHittable(outcomeContinue, in: app)
        XCTAssertTrue(outcomeContinue.isEnabled)
        outcomeContinue.tap()
        let save = element(in: app, identifier: "s3.review.save-report")
        XCTAssertTrue(save.waitForExistence(timeout: 15))
        scrollUntilHittable(save, in: app)
        save.tap()
    }

    @MainActor
    private func finishReceipt(in app: XCUIApplication) {
        let receipt = element(in: app, identifier: "s3.receipt.screen")
        XCTAssertTrue(receipt.waitForExistence(timeout: 25))
        let viewReport = element(in: app, identifier: "s3.receipt.view-report")
        XCTAssertTrue(
            waitForElement(
                viewReport,
                matching: "exists == true AND enabled == true"
            )
        )
        let done = element(in: app, identifier: "s3.receipt.done")
        scrollUntilHittable(done, in: app)
        assertPrimaryControl(done, label: "Done")
        done.tap()
    }

    @MainActor
    private func acceptFixture(in app: XCUIApplication, heading: String) {
        let headingElement = element(in: app, identifier: "s3.capture.heading")
        XCTAssertTrue(headingElement.waitForExistence(timeout: 15))
        XCTAssertTrue(waitForElement(headingElement, matching: "label == %@", argument: heading))
        let importButton = element(in: app, identifier: "s3.capture.import-fixture")
        scrollUntilHittable(importButton, in: app)
        XCTAssertTrue(
            waitForElement(
                importButton,
                matching: "exists == true AND enabled == true AND hittable == true"
            )
        )
        importButton.tap()
        XCTAssertTrue(
            element(in: app, identifier: "s3.capture.preview")
                .waitForExistence(timeout: 20)
        )
        let usePhoto = element(in: app, identifier: "s3.capture.use-photo")
        scrollUntilHittable(usePhoto, in: app)
        XCTAssertTrue(
            waitForElement(
                usePhoto,
                matching: "exists == true AND enabled == true AND hittable == true"
            )
        )
        usePhoto.tap()
    }

    @MainActor
    private func selectFilter(
        _ filter: XCUIElement,
        value: String,
        in app: XCUIApplication
    ) {
        filter.tap()
        let choice = app.buttons[value]
        XCTAssertTrue(choice.waitForExistence(timeout: 10))
        XCTAssertTrue(choice.isHittable)
        choice.tap()
    }

    @MainActor
    private func navigateBack(in app: XCUIApplication) {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(back.waitForExistence(timeout: 10))
        XCTAssertTrue(back.isHittable)
        back.tap()
    }

    @MainActor
    private func assertPrimaryControl(
        _ control: XCUIElement,
        label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(control.waitForExistence(timeout: 15), file: file, line: line)
        XCTAssertEqual(control.label, label, file: file, line: line)
        XCTAssertTrue(control.isEnabled, file: file, line: line)
        XCTAssertTrue(control.isHittable, file: file, line: line)
        XCTAssertGreaterThanOrEqual(control.frame.width, 44, file: file, line: line)
        XCTAssertGreaterThanOrEqual(control.frame.height, 44, file: file, line: line)
    }

    @MainActor
    private func toggle(_ identifier: String, in app: XCUIApplication) {
        let control = element(in: app, identifier: identifier)
        scrollUntilHittable(control, in: app)
        control.tap()
        XCTAssertEqual(control.value as? String, "1")
    }

    @MainActor
    private func dismissKeyboard(in app: XCUIApplication) {
        guard app.keyboards.firstMatch.exists else { return }
        let returnKey = app.keyboards.buttons["Return"]
        if returnKey.exists { returnKey.tap() } else { app.swipeDown() }
    }

    @MainActor
    private func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 {
            if element.isHittable { return }
            app.swipeUp()
        }
        for _ in 0..<12 {
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
        timeout: TimeInterval = 15
    ) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: argument.map { NSPredicate(format: format, $0) }
                ?? NSPredicate(format: format),
            object: element
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private func element(in app: XCUIApplication, identifier: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch
    }

    @MainActor
    private func elements(
        in app: XCUIApplication,
        identifier: String
    ) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: identifier)
    }

    @MainActor
    private func waitForCount(
        _ expected: Int,
        identifier: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let query = elements(in: app, identifier: identifier)
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count == %d", expected),
            object: query
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 20),
            .completed,
            file: file,
            line: line
        )
    }

    @MainActor
    private func launch() throws -> XCUIApplication {
        let bundle = Bundle(for: S4_4ReportsUITests.self)
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
        app.launchEnvironment["S3_2_CLOSE_FIXTURE_BASE64"] = try Data(contentsOf: closeURL)
            .base64EncodedString()
        app.launch()
        return app
    }
}

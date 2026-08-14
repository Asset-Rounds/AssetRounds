import Foundation
import XCTest

final class S6_4AtomicRestoreUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testEmptyRestoreRebuildsPersistedMixedGenerationAtXXXL() throws {
        let expected = try loadExpectedFixture()
        let app = try launch()
        createVisibleIssueReport(in: app)
        finishReceiptToSign(in: app)
        recordWorkWithPhoto(in: app)
        completeResolvedRecheckAndCorrection(in: app)

        app.terminate()
        app.launch()
        XCTAssertTrue(element("s2.sign-detail.screen", in: app)
            .waitForExistence(timeout: 30))
        createSeparateNoVisibleReport(in: app)

        app.terminate()
        app.launchArguments += ["--s6-4-ui-test-export-source"]
        app.launch()
        XCTAssertTrue(element("s6.3.backup-validation.screen", in: app)
            .waitForExistence(timeout: 90))
        XCTAssertEqual(
            element("s6.3.backup-validation.report-count", in: app).label,
            "\(expected.incomingReportCount) reports"
        )

        app.terminate()
        app.launchArguments.removeAll { $0 == "--s6-4-ui-test-export-source" }
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL",
            "--s6-4-ui-test-empty-restore",
        ]
        app.launch()

        XCTAssertTrue(element("s2.welcome.screen", in: app)
            .waitForExistence(timeout: 40))
        tap("s2.welcome.restore-data-backup", in: app)
        XCTAssertTrue(element("s6.4.restore.screen", in: app)
            .waitForExistence(timeout: 60))
        XCTAssertEqual(
            element("s6.4.restore.sign-count", in: app).label,
            "\(expected.incomingSignCount) sign"
        )
        XCTAssertEqual(
            element("s6.4.restore.report-count", in: app).label,
            "\(expected.incomingReportCount) reports"
        )
        XCTAssertEqual(
            element("s6.4.restore.photo-count", in: app).label,
            "\(expected.incomingPhotoCount) photos"
        )
        let confirm = element("s6.4.restore.confirm", in: app)
        scroll(confirm, in: app)
        XCTAssertGreaterThanOrEqual(confirm.frame.width, 44)
        XCTAssertGreaterThanOrEqual(confirm.frame.height, 44)
        confirm.tap()

        let failed = element("s4.pdf-failure.screen", in: app)
        XCTAssertTrue(failed.waitForExistence(timeout: 180))
        XCTAssertEqual(
            element("s4.pdf-failure.headline", in: app).label,
            "This report was saved, but its PDF is not available."
        )
        tap("s4.pdf-failure.retry", in: app)
        XCTAssertTrue(element("s2.sign-detail.screen", in: app)
            .waitForExistence(timeout: 180))
        XCTAssertEqual(
            element("s2.sign-detail.sign-label", in: app).label,
            "Monument Sign"
        )

        app.terminate()
        app.launchArguments.removeAll { $0 == "--s6-4-ui-test-empty-restore" }
        app.launch()
        XCTAssertTrue(element("s2.sign-detail.screen", in: app)
            .waitForExistence(timeout: 60))
        XCTAssertEqual(
            element("s2.sign-detail.sign-label", in: app).label,
            "Monument Sign"
        )
        tap("s4.4.sign-detail.report-history", in: app)
        XCTAssertTrue(element("s4.4.history.screen", in: app)
            .waitForExistence(timeout: 40))
        waitForCount(3, identifier: "s4.4.reports.visit", in: app)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "S6.4 restored report history at Accessibility XXXL"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}

private extension S6_4AtomicRestoreUITests {
    @MainActor
    func createVisibleIssueReport(in app: XCUIApplication) {
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
        tap("s3.outcome.visible-issue", in: app)
        tap("s3.outcome.issue.dark_section", in: app)
        tap("s3.outcome.continue", in: app)
        tap("s3.review.save-report", in: app)
        XCTAssertTrue(element("s3.receipt.screen", in: app)
            .waitForExistence(timeout: 40))
    }

    @MainActor
    func finishReceiptToSign(in app: XCUIApplication) {
        tap("s3.receipt.done", in: app)
        XCTAssertTrue(element("s2.sign-detail.screen", in: app)
            .waitForExistence(timeout: 25))
    }

    @MainActor
    func recordWorkWithPhoto(in app: XCUIApplication) {
        tap("s5.1.sign-detail.record-work", in: app)
        enter(
            "Replaced failed power supply",
            into: "s5.1.work.description",
            in: app
        )
        dismissKeyboard(in: app)
        tap("s5.1.work.import-fixture", in: app)
        XCTAssertTrue(element("s5.1.work.photo", in: app)
            .waitForExistence(timeout: 20))
        tap("s5.1.work.save", in: app)
        XCTAssertTrue(element("s5.1.issue.screen", in: app)
            .waitForExistence(timeout: 35))
        XCTAssertTrue(element("s5.1.issue.status", in: app).label
            .contains("Recheck due"))
    }

    @MainActor
    func completeResolvedRecheckAndCorrection(in app: XCUIApplication) {
        tap("s5.2.issue.start-recheck", in: app)
        XCTAssertTrue(element("s3.preflight.screen", in: app)
            .waitForExistence(timeout: 20))
        toggle("s3.preflight.after-dark", in: app)
        app.swipeUp()
        toggle("s3.preflight.safe-position", in: app)
        tap("s3.preflight.begin", in: app)
        capture("1 of 2 · Wide view", in: app)
        capture("2 of 2 · Close view", in: app)
        tap("s5.2.outcome.resolved", in: app)
        tap("s3.outcome.continue", in: app)
        tap("s3.review.save-report", in: app)
        XCTAssertTrue(element("s3.receipt.screen", in: app)
            .waitForExistence(timeout: 40))
        tap("s3.receipt.view-report", in: app)
        XCTAssertTrue(element("s4.3.report-detail.screen", in: app)
            .waitForExistence(timeout: 30))
        XCTAssertTrue(element("s4.3.report-detail.preview", in: app)
            .waitForExistence(timeout: 20))
        tap("s4.5.report-detail.correct", in: app)
        XCTAssertTrue(element("s4.5.correction.screen", in: app)
            .waitForExistence(timeout: 20))
        enter("Clerical note corrected.", into: "s4.5.correction.note", in: app)
        dismissKeyboard(in: app)
        tap("s4.5.correction.save", in: app)
        XCTAssertTrue(element("s4.5.correction.ready", in: app)
            .waitForExistence(timeout: 40))
        tap("s4.5.correction.prior-report", in: app)
        XCTAssertTrue(element("s4.3.report-detail.screen", in: app)
            .waitForExistence(timeout: 25))
        tap("s4.3.report-detail.close", in: app)
        XCTAssertTrue(element("s3.receipt.screen", in: app)
            .waitForExistence(timeout: 20))
        tap("s3.receipt.done", in: app)
        XCTAssertTrue(element("s5.1.issue.screen", in: app)
            .waitForExistence(timeout: 25))
        navigateBack(in: app)
        XCTAssertTrue(element("s2.sign-detail.screen", in: app)
            .waitForExistence(timeout: 25))
    }

    @MainActor
    func createSeparateNoVisibleReport(in app: XCUIApplication) {
        tap("s2.sign-detail.start-check", in: app)
        XCTAssertTrue(element("s3.preflight.screen", in: app)
            .waitForExistence(timeout: 20))
        toggle("s3.preflight.after-dark", in: app)
        app.swipeUp()
        toggle("s3.preflight.safe-position", in: app)
        tap("s3.preflight.begin", in: app)
        capture("1 of 2 · Wide view", in: app)
        capture("2 of 2 · Close view", in: app)
        tap("s3.outcome.no-visible-issue", in: app)
        tap("s3.outcome.continue", in: app)
        tap("s3.review.save-report", in: app)
        XCTAssertTrue(element("s3.receipt.screen", in: app)
            .waitForExistence(timeout: 40))
        finishReceiptToSign(in: app)
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

    struct Fixture: Decodable {
        struct Expected: Decodable {
            let incomingPhotoCount: Int
            let incomingReportCount: Int
            let incomingSignCount: Int
        }
        let expected: Expected
        let fixtureSchemaVersion: Int
    }

    func loadExpectedFixture() throws -> Fixture.Expected {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(
            forResource: "S6_3V4BackupPackageV1",
            withExtension: "json",
            subdirectory: "Fixtures"
        ) ?? bundle.url(
            forResource: "S6_3V4BackupPackageV1",
            withExtension: "json"
        ))
        let fixture = try JSONDecoder().decode(
            Fixture.self,
            from: Data(contentsOf: url)
        )
        XCTAssertEqual(fixture.fixtureSchemaVersion, 1)
        return fixture.expected
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
        app.launchEnvironment["S5_1_WORK_FIXTURE_BASE64"] = try Data(
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
        value.tap()
        XCTAssertEqual(
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "value == %@", "1"),
                object: value
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

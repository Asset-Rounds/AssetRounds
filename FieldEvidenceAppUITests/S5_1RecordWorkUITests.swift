import Foundation
import XCTest

final class S5_1RecordWorkUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testVisibleIssueRecordsWorkPhotoReopensDueWithoutNewReportVisit() throws {
        let app = try launch()
        createVisibleIssueReport(in: app)

        let receipt = element(in: app, identifier: "s3.receipt.screen")
        XCTAssertTrue(receipt.waitForExistence(timeout: 30))
        let done = element(in: app, identifier: "s3.receipt.done")
        scrollUntilHittable(done, in: app)
        assertControl(done, label: "Done")
        done.tap()
        XCTAssertTrue(element(in: app, identifier: "s2.sign-detail.screen")
            .waitForExistence(timeout: 20))

        app.terminate()
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()

        let signDetail = element(in: app, identifier: "s2.sign-detail.screen")
        XCTAssertTrue(signDetail.waitForExistence(timeout: 30))
        let recordWork = element(in: app, identifier: "s5.1.sign-detail.record-work")
        XCTAssertTrue(recordWork.waitForExistence(timeout: 20))
        scrollUntilHittable(recordWork, in: app)
        assertControl(recordWork, label: "Record work")
        recordWork.tap()

        let workScreen = element(in: app, identifier: "s5.1.work.screen")
        let header = element(in: app, identifier: "s5.1.work.header")
        let date = element(in: app, identifier: "s5.1.work.date")
        let description = element(in: app, identifier: "s5.1.work.description")
        let note = element(in: app, identifier: "s5.1.work.note")
        let save = element(in: app, identifier: "s5.1.work.save")
        XCTAssertTrue(workScreen.waitForExistence(timeout: 20))
        XCTAssertTrue(header.waitForExistence(timeout: 15))
        XCTAssertEqual(header.label, "Record work")
        XCTAssertTrue(date.exists)
        XCTAssertEqual(date.label, "Date")
        assertMinimumGeometry(date)

        scrollUntilHittable(save, in: app)
        save.tap()
        let validation = element(in: app, identifier: "s5.1.work.validation")
        XCTAssertTrue(validation.waitForExistence(timeout: 10))
        XCTAssertEqual(validation.label, "Short description")
        XCTAssertTrue(waitForElement(
            description,
            matching: "hasKeyboardFocus == true",
            timeout: 10
        ))

        scrollUntilHittable(description, in: app)
        description.typeText("Replaced failed power supply")
        dismissKeyboard(in: app)
        scrollUntilHittable(note, in: app)
        note.tap()
        note.typeText("Observed steady illumination after the work.")
        XCTAssertEqual(note.value as? String, "Observed steady illumination after the work.")
        dismissKeyboard(in: app)
        XCTAssertEqual(note.label, "Note")
        assertMinimumGeometry(description)
        assertMinimumGeometry(note)

        let importPhoto = element(
            in: app,
            identifier: "s5.1.work.import-fixture"
        )
        scrollUntilHittable(importPhoto, in: app)
        assertControl(
            importPhoto,
            label: "Add one optional photo showing the work performed."
        )
        importPhoto.tap()
        let preview = element(in: app, identifier: "s5.1.work.photo")
        XCTAssertTrue(preview.waitForExistence(timeout: 20))

        let expectedLocalDate = localDateFormatter.string(from: Date())
        scrollUntilHittable(save, in: app)
        assertControl(save, label: "Record work")
        save.tap()
        XCTAssertTrue(element(in: app, identifier: "s5.1.work.saving")
            .waitForExistence(timeout: 10))

        assertReopenedIssue(
            in: app,
            expectedLocalDate: expectedLocalDate,
            timeout: 35
        )

        navigateBack(in: app)
        XCTAssertTrue(signDetail.waitForExistence(timeout: 20))
        let history = element(in: app, identifier: "s4.4.sign-detail.report-history")
        scrollUntilHittable(history, in: app)
        assertControl(history, label: "Report history")
        history.tap()
        XCTAssertTrue(element(in: app, identifier: "s4.4.history.screen")
            .waitForExistence(timeout: 20))
        let visits = elements(in: app, identifier: "s4.4.reports.visit")
        XCTAssertTrue(waitForQueryCount(visits, count: 1, timeout: 20))

        navigateBack(in: app)
        XCTAssertTrue(signDetail.waitForExistence(timeout: 20))
        let recheckDue = element(in: app, identifier: "s5.1.sign-detail.recheck-due")
        scrollUntilHittable(recheckDue, in: app)
        assertControl(recheckDue, label: "Recheck due")
        recheckDue.tap()
        assertReopenedIssue(
            in: app,
            expectedLocalDate: expectedLocalDate,
            timeout: 20
        )

        let reopenedPhoto = element(in: app, identifier: "s5.1.issue.work-photo")
        scrollUntilHittable(reopenedPhoto, in: app)
        XCTAssertTrue(reopenedPhoto.isHittable)
        XCTAssertFalse(element(in: app, identifier: "s5.1.issue.record-work").exists)
        XCTAssertFalse(element(in: app, identifier: "s5.1.work.failure").exists)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "S5.1 reopened work record and Recheck due issue"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    private func assertReopenedIssue(
        in app: XCUIApplication,
        expectedLocalDate: String,
        timeout: TimeInterval
    ) {
        let screen = element(in: app, identifier: "s5.1.issue.screen")
        XCTAssertTrue(screen.waitForExistence(timeout: timeout))
        let status = element(in: app, identifier: "s5.1.issue.status")
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertTrue(status.label.contains("Recheck due"))
        let header = element(in: app, identifier: "s5.1.issue.header")
        XCTAssertTrue(header.waitForExistence(timeout: 10))
        XCTAssertEqual(header.label, "Section appears dark")

        let record = element(in: app, identifier: "s5.1.issue.work-record")
        XCTAssertTrue(record.waitForExistence(timeout: 15))
        let workDate = element(in: app, identifier: "s5.1.issue.work-date")
        let workDescription = element(
            in: app,
            identifier: "s5.1.issue.work-description"
        )
        let workNote = element(in: app, identifier: "s5.1.issue.work-note")
        scrollUntilHittable(workDate, in: app)
        XCTAssertTrue(workDate.label.contains("Date"))
        XCTAssertTrue(workDate.label.contains(expectedLocalDate))
        scrollUntilHittable(workDescription, in: app)
        XCTAssertTrue(workDescription.label.contains("Short description"))
        XCTAssertTrue(workDescription.label.contains("Replaced failed power supply"))
        scrollUntilHittable(workNote, in: app)
        XCTAssertTrue(workNote.label.contains("Note"))
        XCTAssertTrue(
            workNote.label.contains("Observed steady illumination after the work.")
        )
        XCTAssertTrue(element(in: app, identifier: "s5.1.issue.work-photo")
            .waitForExistence(timeout: 15))
    }

    @MainActor
    private func createVisibleIssueReport(in app: XCUIApplication) {
        XCTAssertTrue(element(in: app, identifier: "s2.welcome.screen")
            .waitForExistence(timeout: 20))
        let addSign = element(in: app, identifier: "s2.welcome.add-first-sign")
        scrollUntilHittable(addSign, in: app)
        addSign.tap()
        let site = element(in: app, identifier: "s2.new-sign.site-label")
        let sign = element(in: app, identifier: "s2.new-sign.sign-label")
        XCTAssertTrue(site.waitForExistence(timeout: 10))
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
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        scrollUntilHittable(start, in: app)
        start.tap()
        let zone = element(in: app, identifier: "s3.preflight.time-zone")
        XCTAssertTrue(zone.waitForExistence(timeout: 10))
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
        XCTAssertTrue(visible.waitForExistence(timeout: 15))
        scrollUntilHittable(visible, in: app)
        visible.tap()
        let label = element(in: app, identifier: "s3.outcome.issue.dark_section")
        scrollUntilHittable(label, in: app)
        label.tap()
        let outcomeContinue = element(in: app, identifier: "s3.outcome.continue")
        scrollUntilHittable(outcomeContinue, in: app)
        outcomeContinue.tap()
        let saveReport = element(in: app, identifier: "s3.review.save-report")
        XCTAssertTrue(saveReport.waitForExistence(timeout: 15))
        scrollUntilHittable(saveReport, in: app)
        saveReport.tap()
    }

    @MainActor
    private func acceptFixture(in app: XCUIApplication, heading: String) {
        let headingElement = element(in: app, identifier: "s3.capture.heading")
        XCTAssertTrue(headingElement.waitForExistence(timeout: 15))
        XCTAssertEqual(headingElement.label, heading)
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
    private func launch() throws -> XCUIApplication {
        let bundle = Bundle(for: S5_1RecordWorkUITests.self)
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
        XCTAssertGreaterThanOrEqual(
            element.frame.width + tolerance,
            44,
            file: file,
            line: line
        )
        XCTAssertGreaterThanOrEqual(
            element.frame.height + tolerance,
            44,
            file: file,
            line: line
        )
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
        app.descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch
    }

    @MainActor
    private func elements(in app: XCUIApplication, identifier: String) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: identifier)
    }

    private var localDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}

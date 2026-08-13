import Foundation
import XCTest

final class S4_5CorrectionUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testFirstAndSecondCorrectionReopenPriorAndCurrentAtAccessibilityXXXL() throws {
        let app = try launch()
        createCompletedReport(in: app)

        let receipt = element(in: app, identifier: "s3.receipt.screen")
        XCTAssertTrue(receipt.waitForExistence(timeout: 25))
        let viewReport = element(in: app, identifier: "s3.receipt.view-report")
        scrollUntilHittable(viewReport, in: app)
        XCTAssertTrue(waitForElement(
            viewReport,
            matching: "exists == true AND enabled == true AND hittable == true",
            timeout: 25
        ))
        viewReport.tap()
        assertReportDetail(in: app, revision: "Current revision", canCorrect: true)

        let firstNote = "First clerical correction"
        openCorrection(in: app)
        assertCorrectionForm(in: app)
        let firstSave = element(in: app, identifier: "s4.5.correction.save")
        scrollUntilHittable(firstSave, in: app)
        firstSave.tap()
        let validation = element(in: app, identifier: "s4.5.correction.validation")
        XCTAssertTrue(validation.waitForExistence(timeout: 10))
        XCTAssertTrue(validation.label.contains("Change the note before saving."))
        let note = element(in: app, identifier: "s4.5.correction.note")
        XCTAssertTrue(waitForElement(note, matching: "hasKeyboardFocus == true", timeout: 10))
        scrollUntilHittable(note, in: app)
        XCTAssertTrue(note.isHittable)
        note.typeText(firstNote)
        XCTAssertTrue(waitForElement(
            element(in: app, identifier: "s4.5.correction.count"),
            matching: "label == %@",
            argument: "\(firstNote.count) of 1,000 characters"
        ))
        dismissKeyboard(in: app)
        scrollUntilHittable(firstSave, in: app)
        firstSave.tap()
        assertSavingThenReady(in: app)

        let priorFromFirst = element(in: app, identifier: "s4.5.correction.prior-report")
        scrollUntilHittable(priorFromFirst, in: app)
        assertControl(priorFromFirst, label: "View prior report")
        priorFromFirst.tap()
        assertReportDetail(in: app, revision: "Prior revision", canCorrect: false)

        let closePrior = element(in: app, identifier: "s4.3.report-detail.close")
        assertControl(closePrior, label: "Close")
        closePrior.tap()
        XCTAssertTrue(receipt.waitForExistence(timeout: 15))
        scrollUntilHittable(viewReport, in: app)
        assertControl(viewReport, label: "View report")
        viewReport.tap()
        assertReportDetail(in: app, revision: "Prior revision", canCorrect: false)

        let currentFromOriginal = element(
            in: app,
            identifier: "s4.5.correction.current-report"
        )
        scrollUntilHittable(currentFromOriginal, in: app)
        assertControl(currentFromOriginal, label: "View corrected report")
        currentFromOriginal.tap()
        assertReportDetail(in: app, revision: "Current revision", canCorrect: true)

        let closeCurrent = element(in: app, identifier: "s4.3.report-detail.close")
        assertControl(closeCurrent, label: "Close")
        closeCurrent.tap()
        XCTAssertTrue(receipt.waitForExistence(timeout: 15))
        let done = element(in: app, identifier: "s3.receipt.done")
        scrollUntilHittable(done, in: app)
        assertControl(done, label: "Done")
        done.tap()
        XCTAssertTrue(element(in: app, identifier: "s2.sign-detail.screen")
            .waitForExistence(timeout: 15))

        app.terminate()
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()

        let signDetail = element(in: app, identifier: "s2.sign-detail.screen")
        XCTAssertTrue(signDetail.waitForExistence(timeout: 25))
        let reopen = element(in: app, identifier: "s4.3.sign-detail.view-report")
        scrollUntilHittable(reopen, in: app)
        assertControl(reopen, label: "View report")
        reopen.tap()
        assertReportDetail(in: app, revision: "Current revision", canCorrect: true)

        openCorrection(in: app)
        let secondNote = "Second clerical correction"
        let secondField = element(in: app, identifier: "s4.5.correction.note")
        XCTAssertTrue(secondField.waitForExistence(timeout: 15))
        scrollUntilHittable(secondField, in: app)
        XCTAssertTrue(secondField.isHittable)
        secondField.tap()
        replaceText(in: secondField, with: secondNote, app: app)
        dismissKeyboard(in: app)
        let secondSave = element(in: app, identifier: "s4.5.correction.save")
        scrollUntilHittable(secondSave, in: app)
        secondSave.doubleTap()
        let saving = element(in: app, identifier: "s4.5.correction.saving")
        XCTAssertTrue(waitForElement(
            saving,
            matching: "exists == true AND label CONTAINS %@",
            argument: "Saving correction",
            timeout: 10
        ))
        XCTAssertFalse(secondSave.isEnabled)
        XCTAssertTrue(element(in: app, identifier: "s4.5.correction.ready")
            .waitForExistence(timeout: 35))
        XCTAssertEqual(
            elements(in: app, identifier: "s4.5.correction.ready").count,
            1
        )

        let secondPrior = element(in: app, identifier: "s4.5.correction.prior-report")
        scrollUntilHittable(secondPrior, in: app)
        secondPrior.tap()
        assertReportDetail(in: app, revision: "Prior revision", canCorrect: false)

        let originalPrior = element(in: app, identifier: "s4.5.correction.prior-report")
        scrollUntilHittable(originalPrior, in: app)
        originalPrior.tap()
        assertReportDetail(in: app, revision: "Prior revision", canCorrect: false)

        let current = element(in: app, identifier: "s4.5.correction.current-report")
        scrollUntilHittable(current, in: app)
        assertControl(current, label: "View corrected report")
        current.tap()
        assertReportDetail(in: app, revision: "Current revision", canCorrect: true)

        let preview = element(in: app, identifier: "s4.3.report-detail.preview")
        scrollUntilHittable(preview, in: app)
        XCTAssertTrue(preview.isHittable)
        let revision = element(in: app, identifier: "s4.5.report-detail.revision-state")
        XCTAssertTrue(revision.exists)
        XCTAssertEqual(revision.label, "Complete: Current revision")
        XCTAssertFalse(element(in: app, identifier: "s4.5.correction.failure").exists)
        let correct = element(in: app, identifier: "s4.5.report-detail.correct")
        scrollReportDetailUntilHittable(correct, in: app)
        assertControl(correct, label: "Correct report")
        XCTAssertTrue(preview.exists)
        scrollUntilHittable(revision, in: app)
        XCTAssertTrue(revision.isHittable)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "S4.5 second corrected report and preserved revision chain"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    private func openCorrection(in app: XCUIApplication) {
        let correct = element(in: app, identifier: "s4.5.report-detail.correct")
        scrollReportDetailUntilHittable(correct, in: app)
        assertControl(correct, label: "Correct report")
        correct.tap()
        XCTAssertTrue(element(in: app, identifier: "s4.5.correction.screen")
            .waitForExistence(timeout: 15))
    }

    @MainActor
    private func assertCorrectionForm(in app: XCUIApplication) {
        let header = element(in: app, identifier: "s4.5.correction.header")
        let note = element(in: app, identifier: "s4.5.correction.note")
        let count = element(in: app, identifier: "s4.5.correction.count")
        let save = element(in: app, identifier: "s4.5.correction.save")
        XCTAssertTrue(header.waitForExistence(timeout: 15))
        XCTAssertEqual(header.label, "Correct report")
        XCTAssertTrue(app.staticTexts[
            "Change the note only. Evidence, outcome, time, and report history stay unchanged."
        ].waitForExistence(timeout: 10))
        XCTAssertTrue(note.waitForExistence(timeout: 10))
        XCTAssertEqual(note.label, "Correction note")
        XCTAssertTrue([XCUIElement.ElementType.textField, .textView]
            .contains(note.elementType))
        XCTAssertEqual(count.label, "0 of 1,000 characters")
        scrollUntilHittable(save, in: app)
        assertControl(save, label: "Save correction")
        assertMinimumGeometry(note)
        XCTAssertLessThan(header.frame.minY, note.frame.minY)
        XCTAssertLessThan(note.frame.minY, count.frame.minY)
    }

    @MainActor
    private func assertSavingThenReady(in app: XCUIApplication) {
        let saving = element(in: app, identifier: "s4.5.correction.saving")
        XCTAssertTrue(waitForElement(
            saving,
            matching: "exists == true AND label CONTAINS %@",
            argument: "Saving correction",
            timeout: 10
        ))
        let ready = element(in: app, identifier: "s4.5.correction.ready")
        XCTAssertTrue(ready.waitForExistence(timeout: 35))
        XCTAssertTrue(app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", "Complete: Correction saved")
        ).firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(ready.label, "The prior report and evidence remain unchanged.")
        XCTAssertFalse(element(in: app, identifier: "s4.5.correction.failure").exists)
    }

    @MainActor
    private func assertReportDetail(
        in app: XCUIApplication,
        revision expectedRevision: String,
        canCorrect: Bool
    ) {
        XCTAssertTrue(element(in: app, identifier: "s4.3.report-detail.screen")
            .waitForExistence(timeout: 20))
        XCTAssertTrue(element(in: app, identifier: "s4.3.report-detail.preview")
            .waitForExistence(timeout: 20))
        let revision = element(in: app, identifier: "s4.5.report-detail.revision-state")
        XCTAssertTrue(revision.waitForExistence(timeout: 15))
        XCTAssertEqual(revision.label, "\(expectedRevision == "Current revision" ? "Complete" : "Information"): \(expectedRevision)")
        let correct = element(in: app, identifier: "s4.5.report-detail.correct")
        if canCorrect {
            scrollReportDetailUntilHittable(correct, in: app)
            assertControl(correct, label: "Correct report")
        } else {
            XCTAssertFalse(correct.exists)
        }
    }

    @MainActor
    private func createCompletedReport(in app: XCUIApplication) {
        XCTAssertTrue(element(in: app, identifier: "s2.welcome.screen")
            .waitForExistence(timeout: 15))
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
        let save = element(in: app, identifier: "s2.new-sign.save")
        scrollUntilHittable(save, in: app)
        save.tap()
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
        let outcome = element(in: app, identifier: "s3.outcome.no-visible-issue")
        XCTAssertTrue(outcome.waitForExistence(timeout: 15))
        scrollUntilHittable(outcome, in: app)
        outcome.tap()
        let continueButton = element(in: app, identifier: "s3.outcome.continue")
        scrollUntilHittable(continueButton, in: app)
        continueButton.tap()
        let saveReport = element(in: app, identifier: "s3.review.save-report")
        XCTAssertTrue(saveReport.waitForExistence(timeout: 15))
        scrollUntilHittable(saveReport, in: app)
        saveReport.tap()
    }

    @MainActor
    private func acceptFixture(in app: XCUIApplication, heading: String) {
        let headingElement = element(in: app, identifier: "s3.capture.heading")
        XCTAssertTrue(headingElement.waitForExistence(timeout: 15))
        XCTAssertTrue(waitForElement(
            headingElement,
            matching: "label == %@",
            argument: heading
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
    private func launch() throws -> XCUIApplication {
        let bundle = Bundle(for: S4_5CorrectionUITests.self)
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
        let geometryTolerance: CGFloat = 0.001
        XCTAssertGreaterThanOrEqual(
            element.frame.width + geometryTolerance,
            44,
            file: file,
            line: line
        )
        XCTAssertGreaterThanOrEqual(
            element.frame.height + geometryTolerance,
            44,
            file: file,
            line: line
        )
    }

    @MainActor
    private func replaceText(
        in field: XCUIElement,
        with text: String,
        app: XCUIApplication
    ) {
        field.tap()
        field.press(forDuration: 1.0)
        let selectAll = app.menuItems["Select All"]
        if selectAll.waitForExistence(timeout: 3) {
            selectAll.tap()
        } else {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 80))
        }
        field.typeText(text)
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
        for _ in 0..<16 {
            if element.isHittable { return }
            app.swipeUp()
        }
        for _ in 0..<16 {
            if element.isHittable { return }
            app.swipeDown()
        }
        XCTAssertTrue(element.isHittable)
    }

    @MainActor
    private func scrollReportDetailUntilHittable(
        _ target: XCUIElement,
        in app: XCUIApplication
    ) {
        let upperPadding = app.coordinate(
            withNormalizedOffset: CGVector(dx: 0.01, dy: 0.25)
        )
        let lowerPadding = app.coordinate(
            withNormalizedOffset: CGVector(dx: 0.01, dy: 0.65)
        )
        for _ in 0..<8 {
            if target.isHittable { return }
            upperPadding.press(forDuration: 0.05, thenDragTo: lowerPadding)
        }
        for _ in 0..<8 {
            if target.isHittable { return }
            lowerPadding.press(forDuration: 0.05, thenDragTo: upperPadding)
        }
        XCTAssertTrue(target.isHittable)
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
    private func elements(in app: XCUIApplication, identifier: String) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: identifier)
    }
}

import Foundation
import XCTest

final class S4_3ValueReceiptUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testValueReceiptPreviewsSharesExportsAndColdReopensExactReport() throws {
        let app = try launch()
        createCompletedReport(in: app)

        let receipt = element(in: app, identifier: "s3.receipt.screen")
        XCTAssertTrue(receipt.waitForExistence(timeout: 20))
        XCTAssertEqual(
            element(in: app, identifier: "s3.receipt.saved").label,
            "Report saved on this device."
        )

        let viewReport = element(in: app, identifier: "s3.receipt.view-report")
        let receiptShare = element(in: app, identifier: "s3.receipt.share")
        let done = element(in: app, identifier: "s3.receipt.done")
        assertPrimaryControl(viewReport, label: "View report")
        assertPrimaryControl(receiptShare, label: "Share PDF")
        assertPrimaryControl(done, label: "Done")

        viewReport.tap()
        let detail = element(in: app, identifier: "s4.3.report-detail.screen")
        XCTAssertTrue(detail.waitForExistence(timeout: 20))
        XCTAssertTrue(
            element(in: app, identifier: "s4.3.report-detail.preview")
                .waitForExistence(timeout: 20)
        )
        XCTAssertFalse(
            element(in: app, identifier: "s4.3.report-detail.delivery-error").exists
        )

        let detailShare = element(in: app, identifier: "s4.3.report-detail.share")
        assertPrimaryControl(detailShare, label: "Share PDF")
        detailShare.tap()
        dismissPresentedSystemSurface(
            in: app,
            purpose: "Share PDF",
            returningTo: detailShare
        )
        XCTAssertTrue(detail.waitForExistence(timeout: 10))

        let saveToFiles = element(
            in: app,
            identifier: "s4.3.report-detail.save-to-files"
        )
        assertPrimaryControl(saveToFiles, label: "Save to Files")
        saveToFiles.tap()
        dismissPresentedSystemSurface(
            in: app,
            purpose: "Save to Files",
            returningTo: saveToFiles
        )
        XCTAssertTrue(detail.waitForExistence(timeout: 10))
        XCTAssertFalse(
            element(in: app, identifier: "s4.3.report-detail.delivery-error").exists,
            "Files cancellation must not create delivery-error state."
        )
        XCTAssertFalse(
            app.staticTexts.matching(
                NSPredicate(
                    format: "label CONTAINS[c] %@",
                    "sent"
                )
            ).firstMatch.exists
        )
        XCTAssertFalse(
            app.staticTexts.matching(
                NSPredicate(
                    format: "label CONTAINS[c] %@",
                    "delivered"
                )
            ).firstMatch.exists
        )

        let close = element(in: app, identifier: "s4.3.report-detail.close")
        assertPrimaryControl(close, label: "Close")
        close.tap()
        XCTAssertTrue(receipt.waitForExistence(timeout: 10))
        done.tap()

        let signDetail = element(in: app, identifier: "s2.sign-detail.screen")
        XCTAssertTrue(signDetail.waitForExistence(timeout: 15))
        let reopen = element(in: app, identifier: "s4.3.sign-detail.view-report")
        assertPrimaryControl(reopen, label: "View report")

        app.terminate()
        app.launch()

        XCTAssertTrue(signDetail.waitForExistence(timeout: 20))
        XCTAssertTrue(reopen.waitForExistence(timeout: 15))
        XCTAssertEqual(reopen.label, "View report")
        reopen.tap()
        XCTAssertTrue(detail.waitForExistence(timeout: 20))
        XCTAssertTrue(
            element(in: app, identifier: "s4.3.report-detail.preview")
                .waitForExistence(timeout: 20)
        )
        XCTAssertFalse(
            element(in: app, identifier: "s4.3.report-detail.delivery-error").exists
        )

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "S4.3 exact cached report reopened"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    private func createCompletedReport(in app: XCUIApplication) {
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
        let saveSign = element(in: app, identifier: "s2.new-sign.save")
        scrollUntilHittable(saveSign, in: app)
        saveSign.tap()

        let start = element(in: app, identifier: "s2.sign-detail.start-check")
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        start.tap()

        let zone = element(in: app, identifier: "s3.preflight.time-zone")
        XCTAssertTrue(zone.waitForExistence(timeout: 10))
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

        let noVisibleIssue = element(in: app, identifier: "s3.outcome.no-visible-issue")
        XCTAssertTrue(noVisibleIssue.waitForExistence(timeout: 15))
        noVisibleIssue.tap()
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
        let captureHeading = element(in: app, identifier: "s3.capture.heading")
        XCTAssertTrue(captureHeading.waitForExistence(timeout: 15))
        XCTAssertEqual(captureHeading.label, heading)
        let importFixture = element(in: app, identifier: "s3.capture.import-fixture")
        scrollUntilHittable(importFixture, in: app)
        importFixture.tap()
        XCTAssertTrue(
            element(in: app, identifier: "s3.capture.preview")
                .waitForExistence(timeout: 15)
        )
        let usePhoto = element(in: app, identifier: "s3.capture.use-photo")
        scrollUntilHittable(usePhoto, in: app)
        usePhoto.tap()
    }

    @MainActor
    private func launch() throws -> XCUIApplication {
        let bundle = Bundle(for: S4_3ValueReceiptUITests.self)
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

        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleInterfaceStyle", "Light",
            "--s1-ui-test-light-mode",
            "--s3-2-ui-test-imported-fixtures",
        ]
        app.launchEnvironment["S3_2_WIDE_FIXTURE_BASE64"] = try Data(
            contentsOf: wideURL
        ).base64EncodedString()
        app.launchEnvironment["S3_2_CLOSE_FIXTURE_BASE64"] = try Data(
            contentsOf: closeURL
        ).base64EncodedString()
        app.launch()
        return app
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
    private func dismissPresentedSystemSurface(
        in app: XCUIApplication,
        purpose: String,
        returningTo returnControl: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard waitForElement(
            returnControl,
            matching: "exists == true AND hittable == false",
            timeout: 15
        ) else {
            return XCTFail(
                "\(purpose) system surface did not obscure report detail",
                file: file,
                line: line
            )
        }

        if purpose == "Share PDF" {
            let close = app.buttons.matching(
                identifier: "header.closeButton"
            ).firstMatch
            guard waitForElement(
                close,
                matching: "exists == true AND enabled == true AND hittable == true",
                timeout: 20
            ) else {
                return XCTFail(
                    "Share PDF system close control did not become hittable",
                    file: file,
                    line: line
                )
            }
            close.tap()
        } else {
            for _ in 0..<4 {
                app.swipeDown()
                if waitForElement(
                    returnControl,
                    matching: "exists == true AND enabled == true AND hittable == true",
                    timeout: 4
                ) {
                    return
                }
            }
        }

        XCTAssertTrue(
            waitForElement(
                returnControl,
                matching: "exists == true AND enabled == true AND hittable == true",
                timeout: 15
            ),
            "Report detail did not become interactive after dismissing \(purpose)",
            file: file,
            line: line
        )
    }

    @MainActor
    private func waitForElement(
        _ element: XCUIElement,
        matching format: String,
        timeout: TimeInterval
    ) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: format),
            object: element
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
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
        XCTAssertTrue(element.isHittable)
    }

    @MainActor
    private func element(in app: XCUIApplication, identifier: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch
    }
}

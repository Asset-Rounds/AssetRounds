import XCTest

final class S8_4FeedbackUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testExplicitAttachmentConsentAndUnavailableFallbackAtXXXL() {
        XCUIDevice.shared.appearance = .dark

        var app = launch(feedbackFlag: "--s8-4-ui-test-mail-available")
        openFeedback(in: app)

        XCTAssertEqual(
            element("s8.4.feedback.heading", in: app).label,
            "Send feedback"
        )
        XCTAssertEqual(
            element("s8.4.feedback.privacy", in: app).label,
            "Your message stays editable. Only app version, build, device model, and iOS version are prefilled; customer and inspection content is never prefilled."
        )

        let review = element("s8.4.feedback.review", in: app)
        scroll(review, in: app)
        XCTAssertTrue(review.label.contains("Review diagnostics before choosing"))
        XCTAssertTrue(review.label.contains("File: field-record-diagnostics.json"))
        XCTAssertTrue(review.label.contains("Reports saved: 0"))
        XCTAssertTrue(
            review.label.contains(
                "No recent bounded system summary is available."
            )
        )

        let consent = element("s8.4.feedback.consent", in: app)
        scroll(consent, in: app)
        XCTAssertEqual(
            consent.label,
            "Choose Attach to include exactly this reviewed JSON, or Don't Attach to open the same editable composer without it."
        )

        let attach = element("s8.4.feedback.attach", in: app)
        scroll(attach, in: app)
        assertControl(attach, label: "Attach")
        attach.tap()
        assertComposer(in: app, attachmentCount: "1")
        closeComposer(in: app)
        XCTAssertTrue(
            element("s8.4.feedback.screen", in: app)
                .waitForExistence(timeout: 20)
        )

        let doNotAttach = element("s8.4.feedback.do-not-attach", in: app)
        scroll(doNotAttach, in: app)
        assertControl(doNotAttach, label: "Don't Attach")
        doNotAttach.tap()
        assertComposer(in: app, attachmentCount: "0")
        closeComposer(in: app)

        app.terminate()
        app = launch(feedbackFlag: "--s8-4-ui-test-mail-unavailable")
        openFeedback(in: app)

        let copy = element("s8.4.feedback.copy-address", in: app)
        scroll(copy, in: app)
        assertControl(copy, label: "Copy support address")
        copy.tap()
        let copied = element("s8.4.feedback.status", in: app)
        scroll(copied, in: app)
        XCTAssertEqual(copied.label, "Complete: Support address copied.")

        let save = element("s8.4.feedback.save-diagnostics", in: app)
        scroll(save, in: app)
        assertControl(save, label: "Save diagnostics to Files")
        save.tap()
        dismissFiles(in: app)
        let terminalCopy = element("s8.4.feedback.copy-address", in: app)
        scroll(terminalCopy, in: app)
        assertControl(terminalCopy, label: "Copy support address")

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "S8.4 explicit feedback consent and fallback at Accessibility XXXL"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    private func dismissFiles(in app: XCUIApplication) {
        let feedbackScreen = element("s8.4.feedback.screen", in: app)
        for _ in 0..<3 where !feedbackScreen.exists {
            let dismissal = app.buttons.matching(
                NSPredicate(
                    format: "(label == %@ OR label == %@) AND hittable == true",
                    "Cancel",
                    "Back"
                )
            ).firstMatch
            XCTAssertTrue(dismissal.waitForExistence(timeout: 10))
            dismissal.tap()
            if feedbackScreen.waitForExistence(timeout: 3) {
                break
            }
        }
        XCTAssertTrue(feedbackScreen.waitForExistence(timeout: 20))
        XCTAssertTrue(element("s8.4.feedback.review", in: app).exists)
    }

    @MainActor
    private func launch(feedbackFlag: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleInterfaceStyle", "Dark",
            "--s1-ui-test-dark-mode",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL",
            feedbackFlag,
        ]
        app.launch()
        XCTAssertTrue(
            element("s2.welcome.screen", in: app)
                .waitForExistence(timeout: 30)
        )
        return app
    }

    @MainActor
    private func openFeedback(in app: XCUIApplication) {
        let settings = element("s1.settings.button", in: app)
        scroll(settings, in: app)
        settings.tap()
        XCTAssertTrue(
            element("s1.settings.screen", in: app)
                .waitForExistence(timeout: 20)
        )
        let entry = element("s8.4.feedback.settings-entry", in: app)
        scroll(entry, in: app)
        assertControl(entry, label: "Send feedback")
        entry.tap()
        XCTAssertTrue(
            element("s8.4.feedback.screen", in: app)
                .waitForExistence(timeout: 20)
        )
        XCTAssertTrue(
            element("s8.4.feedback.review", in: app)
                .waitForExistence(timeout: 20)
        )
    }

    @MainActor
    private func assertComposer(
        in app: XCUIApplication,
        attachmentCount: String
    ) {
        XCTAssertTrue(
            element("s8.4.mail.screen", in: app)
                .waitForExistence(timeout: 20)
        )
        XCTAssertEqual(
            element("s8.4.mail.recipient", in: app).label,
            "To: support@example.invalid"
        )
        let attachment = element("s8.4.mail.attachment-count", in: app)
        XCTAssertEqual(attachment.value as? String, attachmentCount)
        let body = element("s8.4.mail.body", in: app)
        XCTAssertEqual(body.elementType, .textView)
        XCTAssertTrue(body.isEnabled)
        let value = body.value as? String ?? ""
        XCTAssertTrue(value.contains("Feedback:"))
        XCTAssertTrue(value.contains("Device: iPhone"))
        XCTAssertFalse(value.contains("customer"))
        XCTAssertFalse(value.contains("transaction"))
    }

    @MainActor
    private func closeComposer(in app: XCUIApplication) {
        let done = element("s8.4.mail.done", in: app)
        scroll(done, in: app)
        assertControl(done, label: "Done")
        done.tap()
        XCTAssertFalse(
            element("s8.4.mail.screen", in: app)
                .waitForExistence(timeout: 10)
        )
    }

    @MainActor
    private func assertControl(_ value: XCUIElement, label: String) {
        XCTAssertTrue(value.exists)
        XCTAssertEqual(value.label, label)
        XCTAssertEqual(value.elementType, .button)
        XCTAssertTrue(value.isEnabled)
        XCTAssertTrue(value.isHittable)
        XCTAssertGreaterThanOrEqual(value.frame.width + 0.001, 44)
        XCTAssertGreaterThanOrEqual(value.frame.height + 0.001, 44)
    }

    @MainActor
    private func scroll(_ value: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<30 {
            if value.exists && value.isHittable { return }
            app.swipeUp()
        }
        for _ in 0..<30 {
            if value.exists && value.isHittable { return }
            app.swipeDown()
        }
        XCTAssertTrue(value.waitForExistence(timeout: 2))
        XCTAssertTrue(value.isHittable)
    }

    @MainActor
    private func element(
        _ identifier: String,
        in app: XCUIApplication
    ) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch
    }
}

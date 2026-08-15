import CoreGraphics
import Foundation
import StoreKitTest
import XCTest

final class S8_2GoldenAccessibilityUITests: XCTestCase {
    private var storeKitSession: SKTestSession?

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testFreshGoldenFlowIsAccessibleInDefaultLightAndXXXLDark() throws {
        let fixtureURL = try XCTUnwrap(Bundle(for: Self.self).url(
            forResource: "FieldEvidence",
            withExtension: "storekit"
        ))
        let session = try SKTestSession(contentsOf: fixtureURL)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        storeKitSession = session

        XCUIDevice.shared.appearance = .light
        let app = try configuredApplication(
            appearance: "Light",
            appearanceFlag: "--s1-ui-test-light-mode",
            usesAccessibilityXXXL: false
        )
        app.launch()

        try assertLightFirstSignValidationAndCreation(in: app)
        completeVisibleIssueCheck(in: app)
        assertFirstReceiptAndReport(in: app)

        app.terminate()
        XCUIDevice.shared.appearance = .dark
        configure(
            app,
            appearance: "Dark",
            appearanceFlag: "--s1-ui-test-dark-mode",
            usesAccessibilityXXXL: true
        )
        app.launch()

        try completeWorkAndResolvedRecheckAtXXXL(in: app)
        assertMonthlyPaywallAtXXXL(in: app)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "S8.2 golden flow terminal monthly paywall at XXXL Dark"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    private func assertLightFirstSignValidationAndCreation(
        in app: XCUIApplication
    ) throws {
        let shell = element("s1.shell.screen", in: app)
        XCTAssertTrue(shell.waitForExistence(timeout: 30))
        XCTAssertEqual(shell.value as? String, "Light")
        XCTAssertTrue(element("s2.welcome.screen", in: app)
            .waitForExistence(timeout: 30))

        let addSign = element("s2.welcome.add-first-sign", in: app)
        scroll(addSign, in: app)
        assertControl(addSign, label: "Add first sign")
        addSign.tap()

        XCTAssertTrue(element("s2.new-sign.screen", in: app)
            .waitForExistence(timeout: 20))
        let site = element("s2.new-sign.site-label", in: app)
        let sign = element("s2.new-sign.sign-label", in: app)
        XCTAssertTrue(site.waitForExistence(timeout: 15))
        XCTAssertTrue(sign.waitForExistence(timeout: 15))
        XCTAssertLessThan(site.frame.minY, sign.frame.minY)

        let save = element("s2.new-sign.save", in: app)
        scroll(save, in: app)
        assertControl(save, label: "Save and start check")
        save.tap()

        let error = element("s2.new-sign.error", in: app)
        XCTAssertTrue(error.waitForExistence(timeout: 15))
        XCTAssertEqual(error.label, "Blocked: Enter a customer or site name.")
        XCTAssertTrue(wait(
            for: site,
            predicate: "hasKeyboardFocus == true",
            timeout: 10
        ))
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertFalse(element("s2.sign-detail.screen", in: app).exists)
        try assertVoiceOverFocus(
            on: site,
            speechContains: ["Customer", "site name", "text field"]
        )

        site.tap()
        site.typeText("North Campus")
        dismissKeyboard(in: app)
        scroll(sign, in: app)
        sign.tap()
        sign.typeText("Monument Sign")
        dismissKeyboard(in: app)
        scroll(save, in: app)
        save.tap()

        let detail = element("s2.sign-detail.screen", in: app)
        XCTAssertTrue(detail.waitForExistence(timeout: 30))
        XCTAssertEqual(element("s2.sign-detail.sign-label", in: app).label, "Monument Sign")
        XCTAssertTrue(labelledElement("Complete: Sign saved", in: app)
            .waitForExistence(timeout: 10))
    }

    @MainActor
    private func completeVisibleIssueCheck(in app: XCUIApplication) {
        let start = element("s2.sign-detail.start-check", in: app)
        scroll(start, in: app)
        assertControl(start, label: "Start Check")
        start.tap()

        let preflight = element("s3.preflight.screen", in: app)
        XCTAssertTrue(preflight.waitForExistence(timeout: 20))
        XCTAssertTrue(labelledElement("Information: Ready for night check", in: app)
            .waitForExistence(timeout: 10))

        let zone = element("s3.preflight.time-zone", in: app)
        scroll(zone, in: app)
        zone.tap()
        zone.typeText("America/New_York")
        dismissKeyboard(in: app)
        setToggle("s3.preflight.time-zone-confirmed", in: app)
        setToggle("s3.preflight.after-dark", in: app)
        setToggle("s3.preflight.safe-position", in: app)

        let begin = element("s3.preflight.begin", in: app)
        scroll(begin, in: app)
        assertControl(begin, label: "Begin check")
        begin.tap()

        acceptImportedPhoto(in: app, heading: "1 of 2 · Wide view")
        acceptImportedPhoto(in: app, heading: "2 of 2 · Close view")

        let visible = element("s3.outcome.visible-issue", in: app)
        scroll(visible, in: app)
        assertControl(visible, label: "Visible issue")
        XCTAssertEqual(visible.value as? String, "Not selected")
        visible.tap()
        XCTAssertTrue(wait(for: visible, predicate: "value == 'Selected'", timeout: 10))

        let issue = element("s3.outcome.issue.dark_section", in: app)
        scroll(issue, in: app)
        assertControl(issue, label: "Section appears dark")
        issue.tap()
        XCTAssertTrue(wait(for: issue, predicate: "value == 'Selected'", timeout: 10))

        let continueButton = element("s3.outcome.continue", in: app)
        scroll(continueButton, in: app)
        assertControl(continueButton, label: "Continue")
        continueButton.tap()

        XCTAssertTrue(element("s3.review.screen", in: app)
            .waitForExistence(timeout: 20))
        let reviewOutcome = element("s3.review.outcome", in: app)
        XCTAssertTrue(reviewOutcome.waitForExistence(timeout: 10))
        XCTAssertTrue(reviewOutcome.label.contains("Visible issue"))
        XCTAssertTrue(element("s3.review.evidence.wide", in: app)
            .waitForExistence(timeout: 10))
        XCTAssertTrue(element("s3.review.evidence.close", in: app)
            .waitForExistence(timeout: 10))

        let save = element("s3.review.save-report", in: app)
        scroll(save, in: app)
        assertControl(save, label: "Save and finish")
        save.tap()
    }

    @MainActor
    private func assertFirstReceiptAndReport(in app: XCUIApplication) {
        XCTAssertTrue(element("s3.receipt.screen", in: app)
            .waitForExistence(timeout: 40))
        XCTAssertTrue(labelledElement("Complete: Check complete", in: app)
            .waitForExistence(timeout: 15))
        let saved = element("s3.receipt.saved", in: app)
        XCTAssertTrue(saved.waitForExistence(timeout: 15))
        XCTAssertEqual(saved.label, "Report saved on this device.")

        let viewReport = element("s3.receipt.view-report", in: app)
        scroll(viewReport, in: app)
        assertControl(viewReport, label: "View report")
        viewReport.tap()
        XCTAssertTrue(element("s4.3.report-detail.screen", in: app)
            .waitForExistence(timeout: 30))
        let preview = element("s4.3.report-detail.preview", in: app)
        XCTAssertTrue(preview.waitForExistence(timeout: 20))
        XCTAssertTrue(preview.isHittable)
        navigateBack(in: app)

        let done = element("s3.receipt.done", in: app)
        scroll(done, in: app)
        assertControl(done, label: "Done")
        done.tap()
        XCTAssertTrue(element("s2.sign-detail.screen", in: app)
            .waitForExistence(timeout: 25))
    }

    @MainActor
    private func completeWorkAndResolvedRecheckAtXXXL(
        in app: XCUIApplication
    ) throws {
        let shell = element("s1.shell.screen", in: app)
        XCTAssertTrue(shell.waitForExistence(timeout: 30))
        XCTAssertEqual(shell.value as? String, "Dark")
        let signDetail = element("s2.sign-detail.screen", in: app)
        XCTAssertTrue(signDetail.waitForExistence(timeout: 30))

        let recordWork = element("s5.1.sign-detail.record-work", in: app)
        scroll(recordWork, in: app)
        assertControl(recordWork, label: "Record work")
        recordWork.tap()

        XCTAssertTrue(element("s5.1.work.screen", in: app)
            .waitForExistence(timeout: 20))
        let description = element("s5.1.work.description", in: app)
        scroll(description, in: app)
        assertMinimumGeometry(description)
        description.tap()
        description.typeText("Replaced failed power supply")
        dismissKeyboard(in: app)

        let importPhoto = element("s5.1.work.import-fixture", in: app)
        scroll(importPhoto, in: app)
        assertControl(
            importPhoto,
            label: "Add one optional photo showing the work performed."
        )
        importPhoto.tap()
        let workPreview = element("s5.1.work.photo", in: app)
        XCTAssertTrue(workPreview.waitForExistence(timeout: 20))
        XCTAssertTrue(workPreview.isHittable)

        let saveWork = element("s5.1.work.save", in: app)
        scroll(saveWork, in: app)
        assertControl(saveWork, label: "Record work")
        saveWork.tap()
        let progress = element("s5.1.work.saving", in: app)
        XCTAssertTrue(progress.waitForExistence(timeout: 10))
        XCTAssertEqual(progress.label, "Record work")

        let issueScreen = element("s5.1.issue.screen", in: app)
        XCTAssertTrue(issueScreen.waitForExistence(timeout: 40))
        let dueStatus = element("s5.1.issue.status", in: app)
        XCTAssertTrue(dueStatus.waitForExistence(timeout: 10))
        XCTAssertEqual(dueStatus.label, "Attention: Recheck due")
        navigateBack(in: app)

        XCTAssertTrue(signDetail.waitForExistence(timeout: 20))
        let due = element("s5.1.sign-detail.recheck-due", in: app)
        scroll(due, in: app)
        assertControl(due, label: "Recheck due")
        due.tap()
        XCTAssertTrue(issueScreen.waitForExistence(timeout: 20))
        let issueHeader = element("s5.1.issue.header", in: app)
        let reopenedStatus = element("s5.1.issue.status", in: app)
        let startRecheck = element("s5.2.issue.start-recheck", in: app)
        XCTAssertTrue(issueHeader.waitForExistence(timeout: 10))
        try assertXXXLVoiceOverIssueOrder(
            status: reopenedStatus,
            header: issueHeader,
            action: startRecheck
        )

        scroll(startRecheck, in: app)
        assertControl(startRecheck, label: "Start recheck")
        startRecheck.tap()
        XCTAssertTrue(element("s3.preflight.screen", in: app)
            .waitForExistence(timeout: 20))
        setToggle("s3.preflight.after-dark", in: app)
        setToggle("s3.preflight.safe-position", in: app)
        let begin = element("s3.preflight.begin", in: app)
        scroll(begin, in: app)
        assertControl(begin, label: "Begin check")
        begin.tap()

        acceptImportedPhoto(in: app, heading: "1 of 2 · Wide view")
        acceptImportedPhoto(in: app, heading: "2 of 2 · Close view")

        let resolved = element("s5.2.outcome.resolved", in: app)
        scroll(resolved, in: app)
        assertControl(resolved, label: "Resolved")
        XCTAssertEqual(resolved.value as? String, "Not selected")
        resolved.tap()
        XCTAssertTrue(wait(for: resolved, predicate: "value == 'Selected'", timeout: 10))

        let continueButton = element("s3.outcome.continue", in: app)
        scroll(continueButton, in: app)
        assertControl(continueButton, label: "Continue")
        continueButton.tap()

        XCTAssertTrue(element("s3.review.screen", in: app)
            .waitForExistence(timeout: 20))
        let reviewOutcome = element("s3.review.outcome", in: app)
        XCTAssertTrue(reviewOutcome.waitForExistence(timeout: 10))
        XCTAssertTrue(reviewOutcome.label.contains("Resolved"))
        let save = element("s3.review.save-report", in: app)
        scroll(save, in: app)
        assertControl(save, label: "Save and finish")
        save.tap()

        XCTAssertTrue(element("s3.receipt.screen", in: app)
            .waitForExistence(timeout: 40))
        let saved = element("s3.receipt.saved", in: app)
        XCTAssertTrue(saved.waitForExistence(timeout: 15))
        XCTAssertEqual(saved.label, "Report saved on this device.")
        let viewReport = element("s3.receipt.view-report", in: app)
        scroll(viewReport, in: app)
        assertControl(viewReport, label: "View report")
        viewReport.tap()
        XCTAssertTrue(element("s4.3.report-detail.preview", in: app)
            .waitForExistence(timeout: 25))
        navigateBack(in: app)

        let done = element("s3.receipt.done", in: app)
        scroll(done, in: app)
        assertControl(done, label: "Done")
        done.tap()
        XCTAssertTrue(issueScreen.waitForExistence(timeout: 25))
        navigateBack(in: app)
        XCTAssertTrue(signDetail.waitForExistence(timeout: 25))

        let resolvedIssue = element("s5.2.sign-detail.resolved", in: app)
        scroll(resolvedIssue, in: app)
        assertControl(resolvedIssue, label: "Resolved")
        resolvedIssue.tap()
        XCTAssertTrue(issueScreen.waitForExistence(timeout: 20))
        let resolvedStatus = element("s5.1.issue.status", in: app)
        XCTAssertTrue(resolvedStatus.waitForExistence(timeout: 10))
        XCTAssertEqual(resolvedStatus.label, "Complete: Resolved")
        XCTAssertFalse(element("s5.2.issue.start-recheck", in: app).exists)
        navigateBack(in: app)
        XCTAssertTrue(signDetail.waitForExistence(timeout: 20))
    }

    @MainActor
    private func assertMonthlyPaywallAtXXXL(in app: XCUIApplication) {
        let settings = element("s1.settings.button", in: app)
        assertControl(settings, label: "Settings")
        settings.tap()
        XCTAssertTrue(element("s1.settings.screen", in: app)
            .waitForExistence(timeout: 20))

        let entry = element("s7.2.settings.paywall", in: app)
        scroll(entry, in: app)
        assertControl(entry, label: "View subscription")
        entry.tap()
        XCTAssertTrue(element("s7.2.paywall.screen", in: app)
            .waitForExistence(timeout: 30))

        let productName = element("s7.2.paywall.product-name", in: app)
        let duration = element("s7.2.paywall.duration", in: app)
        let price = element("s7.2.paywall.price", in: app)
        let trial = element("s7.2.paywall.trial", in: app)
        for value in [productName, duration, price, trial] {
            XCTAssertTrue(value.waitForExistence(timeout: 30))
        }
        scroll(productName, in: app)
        XCTAssertLessThan(productName.frame.minY, duration.frame.minY)
        XCTAssertLessThan(duration.frame.minY, price.frame.minY)
        XCTAssertLessThan(price.frame.minY, trial.frame.minY)

        assertText("s7.2.paywall.product-name", equals: "Solo Access Monthly", in: app)
        assertText("s7.2.paywall.duration", equals: "one month", in: app)
        assertText("s7.2.paywall.price", equals: "$59.99", in: app)
        assertText("s7.2.paywall.trial", equals: "14 days free", in: app)
        let renewal = element("s7.2.paywall.renewal", in: app)
        scroll(renewal, in: app)
        XCTAssertTrue(renewal.label.contains("$59.99"))
        let noSync = element("s7.2.paywall.no-sync", in: app)
        scroll(noSync, in: app)
        XCTAssertTrue(noSync.label.contains("do not sync"))

        let store = element("s7.2.paywall.store", in: app)
        XCTAssertTrue(store.waitForExistence(timeout: 30))
        XCTAssertTrue(wait(for: store, predicate: "value == 'Ready'", timeout: 20))
        XCTAssertTrue(store.isEnabled)

        for identifier in [
            "s7.2.paywall.close",
            "s7.2.paywall.terms",
            "s7.2.paywall.privacy",
            "s7.2.paywall.support",
        ] {
            let control = element(identifier, in: app)
            scroll(control, in: app)
            assertMinimumGeometry(control)
            XCTAssertTrue(control.isEnabled)
        }

        let close = element("s7.2.paywall.close", in: app)
        scroll(close, in: app)
        assertControl(close, label: "Close")
    }

    @MainActor
    private func acceptImportedPhoto(in app: XCUIApplication, heading: String) {
        let headingElement = element("s3.capture.heading", in: app)
        XCTAssertTrue(headingElement.waitForExistence(timeout: 25))
        XCTAssertTrue(wait(
            for: headingElement,
            predicate: "label == %@",
            argument: heading,
            timeout: 20
        ))

        let importPhoto = element("s3.capture.import-fixture", in: app)
        scroll(importPhoto, in: app)
        assertControl(importPhoto, label: "Import test photo")
        importPhoto.tap()

        let preview = element("s3.capture.preview", in: app)
        XCTAssertTrue(preview.waitForExistence(timeout: 20))
        XCTAssertEqual(preview.label, "Imported photo preview")
        let usePhoto = element("s3.capture.use-photo", in: app)
        scroll(usePhoto, in: app)
        assertControl(usePhoto, label: "Use Photo")
        usePhoto.tap()
    }

    @MainActor
    private func configuredApplication(
        appearance: String,
        appearanceFlag: String,
        usesAccessibilityXXXL: Bool
    ) throws -> XCUIApplication {
        let bundle = Bundle(for: Self.self)
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
        app.launchEnvironment["S3_2_WIDE_FIXTURE_BASE64"] = wide.base64EncodedString()
        app.launchEnvironment["S3_2_CLOSE_FIXTURE_BASE64"] = close.base64EncodedString()
        app.launchEnvironment["S5_1_WORK_FIXTURE_BASE64"] = close.base64EncodedString()
        configure(
            app,
            appearance: appearance,
            appearanceFlag: appearanceFlag,
            usesAccessibilityXXXL: usesAccessibilityXXXL
        )
        return app
    }

    @MainActor
    private func configure(
        _ app: XCUIApplication,
        appearance: String,
        appearanceFlag: String,
        usesAccessibilityXXXL: Bool
    ) {
        app.launchArguments = [
            "-AppleInterfaceStyle", appearance,
            appearanceFlag,
            "--s3-2-ui-test-imported-fixtures",
            "--s7-2-ui-test-paywall",
        ]
        if usesAccessibilityXXXL {
            app.launchArguments += [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXXXL",
            ]
        }
    }

    @MainActor
    private func setToggle(_ identifier: String, in app: XCUIApplication) {
        let toggle = element(identifier, in: app)
        scroll(toggle, in: app)
        XCTAssertEqual(toggle.elementType, .switch)
        assertMinimumGeometry(toggle)
        if (toggle.value as? String) != "1" {
            toggle.tap()
        }
        XCTAssertTrue(wait(for: toggle, predicate: "value == '1'", timeout: 10))
    }

    @MainActor
    private func assertText(
        _ identifier: String,
        equals expected: String,
        in app: XCUIApplication
    ) {
        let value = element(identifier, in: app)
        scroll(value, in: app)
        XCTAssertEqual(value.label, expected)
    }

    @MainActor
    private func assertControl(
        _ control: XCUIElement,
        label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(control.waitForExistence(timeout: 20), file: file, line: line)
        XCTAssertEqual(control.label, label, file: file, line: line)
        XCTAssertEqual(control.elementType, .button, file: file, line: line)
        XCTAssertTrue(control.isEnabled, file: file, line: line)
        XCTAssertTrue(control.isHittable, file: file, line: line)
        assertMinimumGeometry(control, file: file, line: line)
    }

    @MainActor
    private func assertMinimumGeometry(
        _ value: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let tolerance: CGFloat = 0.001
        XCTAssertGreaterThanOrEqual(value.frame.width + tolerance, 44, file: file, line: line)
        XCTAssertGreaterThanOrEqual(value.frame.height + tolerance, 44, file: file, line: line)
    }

    @MainActor
    private func assertVoiceOverFocus(
        on value: XCUIElement,
        speechContains fragments: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        guard #available(iOS 26.0, *) else {
            XCTFail("The pinned S8.2 runtime must expose VoiceOver UI testing", file: file, line: line)
            return
        }
        let voiceOver = XCUIDevice.shared.voiceOverService
        if voiceOver.isEnabled {
            try voiceOver.disable()
        }
        try voiceOver.enable()
        defer { try? voiceOver.disable() }

        XCTAssertTrue(value.waitForExistence(timeout: 10), file: file, line: line)
        XCTAssertTrue(
            wait(for: value, predicate: "hasFocus == true", timeout: 10),
            file: file,
            line: line
        )
        XCTAssertTrue(value.hasFocus, file: file, line: line)
        let utterance = try voiceOver.currentSpeech().utterance.lowercased()
        for fragment in fragments {
            XCTAssertTrue(
                utterance.contains(fragment.lowercased()),
                "VoiceOver utterance \(utterance) did not contain \(fragment)",
                file: file,
                line: line
            )
        }
    }

    @MainActor
    private func assertXXXLVoiceOverIssueOrder(
        status: XCUIElement,
        header: XCUIElement,
        action: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        guard #available(iOS 26.0, *) else {
            XCTFail("The pinned S8.2 runtime must expose VoiceOver UI testing", file: file, line: line)
            return
        }
        let voiceOver = XCUIDevice.shared.voiceOverService
        if voiceOver.isEnabled {
            try voiceOver.disable()
        }
        try voiceOver.enable()
        defer { try? voiceOver.disable() }

        for value in [status, header, action] {
            XCTAssertTrue(value.waitForExistence(timeout: 10), file: file, line: line)
        }
        XCTAssertTrue(
            wait(for: header, predicate: "hasFocus == true", timeout: 10),
            file: file,
            line: line
        )
        let initial = try voiceOver.currentSpeech().utterance.lowercased()
        XCTAssertTrue(initial.contains("section appears dark"), file: file, line: line)
        XCTAssertTrue(initial.contains("heading"), file: file, line: line)

        let prior = try voiceOver.moveBackward().utterance.lowercased()
        XCTAssertTrue(status.hasFocus, file: file, line: line)
        XCTAssertTrue(prior.contains("attention"), file: file, line: line)
        XCTAssertTrue(prior.contains("recheck due"), file: file, line: line)

        let centered = try voiceOver.moveForward().utterance.lowercased()
        XCTAssertTrue(header.hasFocus, file: file, line: line)
        XCTAssertTrue(centered.contains("section appears dark"), file: file, line: line)
        XCTAssertTrue(centered.contains("heading"), file: file, line: line)

        let next = try voiceOver.moveForward().utterance.lowercased()
        XCTAssertTrue(action.hasFocus, file: file, line: line)
        XCTAssertTrue(next.contains("start recheck"), file: file, line: line)
        XCTAssertTrue(next.contains("button"), file: file, line: line)
    }

    @MainActor
    private func dismissKeyboard(in app: XCUIApplication) {
        guard app.keyboards.firstMatch.exists else { return }
        let key = app.keyboards.buttons["Return"]
        key.exists ? key.tap() : app.swipeDown()
    }

    @MainActor
    private func navigateBack(in app: XCUIApplication) {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(back.waitForExistence(timeout: 15))
        XCTAssertTrue(back.isHittable)
        back.tap()
    }

    @MainActor
    private func scroll(_ value: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(value.waitForExistence(timeout: 30))
        for _ in 0..<22 {
            if value.isHittable { return }
            app.swipeUp()
        }
        for _ in 0..<22 {
            if value.isHittable { return }
            app.swipeDown()
        }
        XCTAssertTrue(value.isHittable)
    }

    @MainActor
    private func wait(
        for value: XCUIElement,
        predicate format: String,
        argument: String? = nil,
        timeout: TimeInterval
    ) -> Bool {
        let predicate = argument.map { NSPredicate(format: format, $0) }
            ?? NSPredicate(format: format)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: value)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private func labelledElement(_ label: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", label))
            .firstMatch
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}

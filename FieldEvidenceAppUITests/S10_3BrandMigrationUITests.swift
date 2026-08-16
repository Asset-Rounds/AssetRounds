import CoreGraphics
import CryptoKit
import Foundation
import StoreKitTest
import XCTest

final class S10_3BrandMigrationUITests: XCTestCase {
    private enum AlternativeRecheckOutcome: Equatable {
        case couldNotVerify
        case issueStillVisible
        case differentIssue
    }

    private var storeKitSession: SKTestSession?
    private var migratedStateIDs: [String] = []

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAllFrozenReleasedStatesUseTheBrandSystemWithoutBehaviorDrift() throws {
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
        let unavailableApp = try configuredApplication(
            appearance: "Light",
            appearanceFlag: "--s1-ui-test-light-mode",
            usesAccessibilityXXXL: false
        )
        unavailableApp.launchArguments.append("--s1-invalid-pack")
        unavailableApp.launch()
        XCTAssertTrue(element("s1.pack.unavailable", in: unavailableApp)
            .waitForExistence(timeout: 30))
        captureBaseline("state.pack.unavailable", in: unavailableApp)
        unavailableApp.terminate()

        let app = try configuredApplication(
            appearance: "Light",
            appearanceFlag: "--s1-ui-test-light-mode",
            usesAccessibilityXXXL: false
        )
        app.launchArguments += [
            "--s3-5-ui-test-low-storage-once",
            "--s3-6-ui-test-camera-denied-once",
        ]
        let coldLaunchStartedAt = Date()
        app.launch()
        XCTAssertTrue(element("s2.welcome.screen", in: app)
            .waitForExistence(timeout: 30))
        recordMetric("cold_launch_to_welcome", since: coldLaunchStartedAt)

        assertLightFirstSignValidationAndCreation(in: app)
        completeVisibleIssueCheck(in: app)
        assertFirstReceiptAndReport(in: app)
        assertReportsIndex(in: app)

        app.terminate()
        app.launchArguments.removeAll {
            $0 == "--s3-5-ui-test-low-storage-once"
                || $0 == "--s3-6-ui-test-camera-denied-once"
        }
        XCUIDevice.shared.appearance = .dark
        configure(
            app,
            appearance: "Dark",
            appearanceFlag: "--s1-ui-test-dark-mode",
            usesAccessibilityXXXL: true
        )
        app.launch()

        completeWorkAndResolvedRecheckAtXXXL(in: app)
        captureAlternativeCompletedCheckStates(in: app)
        captureDifferentIssueStatesBeforeRecovery(in: app)
        app.terminate()
        app.launch()
        recoverInjectedPDFFailureAtXXXL(in: app)
        captureReportComparisonAndCorrectionStates(in: app)
        captureUnavailablePaywallAndFeedbackReview(in: app)
        assertMonthlyPaywallAtXXXL(in: app)
        eraseLocalDataAndCaptureNoEntitlement(in: app)
    }

    @MainActor
    private func assertLightFirstSignValidationAndCreation(
        in app: XCUIApplication
    ) {
        let shell = element("s1.shell.screen", in: app)
        XCTAssertTrue(shell.waitForExistence(timeout: 30))
        XCTAssertEqual(shell.value as? String, "Light")
        XCTAssertTrue(element("s2.welcome.screen", in: app)
            .waitForExistence(timeout: 30))
        captureBaseline("state.welcome.empty", in: app)

        let reportsTab = element("s1.tab.reports", in: app)
        assertControl(reportsTab, label: "Reports")
        reportsTab.tap()
        XCTAssertTrue(element("s4.4.reports.screen", in: app)
            .waitForExistence(timeout: 20))
        XCTAssertTrue(element("s1.reports.placeholder", in: app)
            .waitForExistence(timeout: 10))
        captureBaseline("state.reports-index.empty", in: app)
        let signsTab = element("s1.tab.signs", in: app)
        assertControl(signsTab, label: "Signs")
        signsTab.tap()
        XCTAssertTrue(element("s2.welcome.screen", in: app)
            .waitForExistence(timeout: 20))

        let sample = element("s2.welcome.view-sample", in: app)
        scroll(sample, in: app)
        assertControl(sample, label: "View sample")
        sample.tap()
        XCTAssertTrue(element("s2.sample.screen", in: app)
            .waitForExistence(timeout: 20))
        captureBaseline("state.sample-report.ready", in: app)
        let sampleBack = element("s2.sample.back", in: app)
        XCTAssertTrue(sampleBack.waitForExistence(timeout: 20))
        XCTAssertEqual(sampleBack.label, "Back")
        XCTAssertEqual(sampleBack.elementType, .button)
        XCTAssertTrue(sampleBack.isHittable)
        sampleBack.tap()
        XCTAssertTrue(element("s2.welcome.screen", in: app)
            .waitForExistence(timeout: 20))

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

        scroll(sign, in: app)
        sign.tap()
        sign.typeText("Monument Sign")
        dismissKeyboard(in: app)
        captureBaseline("state.new-sign.editing", in: app)

        let save = element("s2.new-sign.save", in: app)
        scroll(save, in: app)
        assertControl(save, label: "Save and start check")
        save.tap()

        let error = element("s2.new-sign.error", in: app)
        XCTAssertTrue(error.waitForExistence(timeout: 15))
        XCTAssertEqual(error.label, "Blocked: Enter a customer or site name.")
        XCTAssertEqual(site.label, "Customer / site name")
        XCTAssertEqual(site.elementType, .textField)
        XCTAssertTrue(
            wait(for: site, predicate: "hasKeyboardFocus == true", timeout: 10)
        )
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(sign.value as? String, "Monument Sign")
        XCTAssertFalse(element("s2.sign-detail.screen", in: app).exists)
        captureBaseline("state.new-sign.validation-error", in: app)

        site.typeText("North Campus")
        dismissKeyboard(in: app)
        scroll(save, in: app)
        save.tap()

        let detail = element("s2.sign-detail.screen", in: app)
        XCTAssertTrue(detail.waitForExistence(timeout: 30))
        XCTAssertEqual(element("s2.sign-detail.sign-label", in: app).label, "Monument Sign")
        XCTAssertTrue(labelledElement("Complete: Sign saved", in: app)
            .waitForExistence(timeout: 10))
        captureBaseline("state.sign-detail.ready", in: app)

        let delete = element("s6.1.delete.action", in: app)
        scroll(delete, in: app)
        assertControl(delete, label: "Delete sign")
        delete.tap()
        XCTAssertTrue(element("s6.1.delete.screen", in: app)
            .waitForExistence(timeout: 15))
        captureBaseline("state.sign-detail.delete-confirmation", in: app)
        let cancelDelete = element("s6.1.delete.cancel", in: app)
        scroll(cancelDelete, in: app)
        assertControl(cancelDelete, label: "Cancel")
        cancelDelete.tap()
        XCTAssertTrue(detail.waitForExistence(timeout: 20))
    }

    @MainActor
    private func completeVisibleIssueCheck(in app: XCUIApplication) {
        let start = element("s2.sign-detail.start-check", in: app)
        scroll(start, in: app)
        assertControl(start, label: "Start Check")
        let startCheckAt = Date()
        start.tap()

        let preflight = element("s3.preflight.screen", in: app)
        XCTAssertTrue(preflight.waitForExistence(timeout: 20))
        recordMetric("start_check_to_preflight", since: startCheckAt)
        XCTAssertTrue(labelledElement("Information: Ready for night check", in: app)
            .waitForExistence(timeout: 10))
        captureBaseline("state.check-preflight.ready", in: app)

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

        XCTAssertTrue(element("s3.capture.screen", in: app)
            .waitForExistence(timeout: 20))
        captureBaseline("state.capture.wide-ready", in: app)
        recoverCameraDenialAndResume(in: app)

        acceptImportedPhoto(
            in: app,
            heading: "1 of 2 · Wide view",
            stateID: "state.capture.wide-preview",
            capturesLowStorageFailure: true
        )
        captureBaseline("state.capture.close-ready", in: app)
        acceptImportedPhoto(
            in: app,
            heading: "2 of 2 · Close view",
            stateID: "state.capture.close-preview"
        )

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
        captureBaseline("state.check-outcome.visible-issue", in: app)

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
        captureBaseline("state.check-review.visible-issue", in: app)

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
        captureBaseline("state.receipt.report-saved", in: app)

        let viewReport = element("s3.receipt.view-report", in: app)
        scroll(viewReport, in: app)
        assertControl(viewReport, label: "View report")
        let reportOpenAt = Date()
        viewReport.tap()
        XCTAssertTrue(element("s4.3.report-detail.screen", in: app)
            .waitForExistence(timeout: 30))
        recordMetric("report_open_to_preview", since: reportOpenAt)
        let preview = element("s4.3.report-detail.preview", in: app)
        XCTAssertTrue(preview.waitForExistence(timeout: 20))
        XCTAssertTrue(preview.isHittable)
        captureBaseline("state.report-detail.ready", in: app)
        navigateBack(in: app)

        let done = element("s3.receipt.done", in: app)
        scroll(done, in: app)
        assertControl(done, label: "Done")
        done.tap()
        XCTAssertTrue(element("s2.sign-detail.screen", in: app)
            .waitForExistence(timeout: 25))
    }

    @MainActor
    private func assertReportsIndex(in app: XCUIApplication) {
        let history = element("s4.4.sign-detail.report-history", in: app)
        scroll(history, in: app)
        assertControl(history, label: "Report history")
        let historyOpenAt = Date()
        history.tap()
        XCTAssertTrue(element("s4.4.history.screen", in: app)
            .waitForExistence(timeout: 30))
        recordMetric("report_history_open", since: historyOpenAt)
        XCTAssertTrue(element("s4.4.reports.view-report", in: app)
            .waitForExistence(timeout: 20))
        captureBaseline("state.report-history.ready", in: app)
        navigateBack(in: app)

        let reportsTab = element("s1.tab.reports", in: app)
        XCTAssertTrue(reportsTab.waitForExistence(timeout: 20))
        reportsTab.tap()
        XCTAssertTrue(element("s4.4.reports.screen", in: app)
            .waitForExistence(timeout: 30))
        captureBaseline("state.reports-index.ready", in: app)

        let signsTab = element("s1.tab.signs", in: app)
        XCTAssertTrue(signsTab.waitForExistence(timeout: 20))
        signsTab.tap()
        XCTAssertTrue(element("s2.sign-detail.screen", in: app)
            .waitForExistence(timeout: 30))
    }

    @MainActor
    private func completeWorkAndResolvedRecheckAtXXXL(
        in app: XCUIApplication
    ) {
        let shell = element("s1.shell.screen", in: app)
        XCTAssertTrue(shell.waitForExistence(timeout: 30))
        XCTAssertEqual(shell.value as? String, "Dark")
        let signDetail = element("s2.sign-detail.screen", in: app)
        XCTAssertTrue(signDetail.waitForExistence(timeout: 30))
        captureBaseline("state.sign-detail.open-issue", in: app)

        let recordWork = element("s5.1.sign-detail.record-work", in: app)
        scroll(recordWork, in: app)
        assertControl(recordWork, label: "Record work")
        recordWork.tap()

        XCTAssertTrue(element("s5.1.work.screen", in: app)
            .waitForExistence(timeout: 20))
        let description = element("s5.1.work.description", in: app)
        let saveWork = element("s5.1.work.save", in: app)
        scroll(saveWork, in: app)
        assertControl(saveWork, label: "Record work")
        saveWork.tap()
        let validation = element("s5.1.work.validation", in: app)
        XCTAssertTrue(validation.waitForExistence(timeout: 10))
        XCTAssertEqual(validation.label, "Short description")
        captureBaseline("state.work.validation-error", in: app)
        scroll(description, in: app)
        assertMinimumGeometry(description)
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
        scroll(workPreview, in: app)
        XCTAssertTrue(workPreview.isHittable)
        captureBaseline("state.work.editing", in: app)

        scroll(saveWork, in: app)
        assertControl(saveWork, label: "Record work")
        saveWork.tap()
        let progress = element("s5.1.work.saving", in: app)
        XCTAssertTrue(progress.waitForExistence(timeout: 10))
        XCTAssertEqual(progress.label, "Record work")
        captureBaseline("state.work.saving", in: app)

        let issueScreen = element("s5.1.issue.screen", in: app)
        XCTAssertTrue(issueScreen.waitForExistence(timeout: 40))
        let dueStatus = element("s5.1.issue.status", in: app)
        XCTAssertTrue(dueStatus.waitForExistence(timeout: 10))
        XCTAssertEqual(dueStatus.label, "Attention: Recheck due")
        captureBaseline("state.issue.recheck-due", in: app)
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
        assertXXXLAccessibilityIssueOrder(
            status: reopenedStatus,
            header: issueHeader,
            action: startRecheck,
            in: app
        )

        scroll(startRecheck, in: app)
        assertControl(startRecheck, label: "Start recheck")
        startRecheck.tap()
        XCTAssertTrue(element("s3.preflight.screen", in: app)
            .waitForExistence(timeout: 20))
        captureBaseline("state.recheck-preflight.ready", in: app)
        setToggle("s3.preflight.after-dark", in: app)
        app.swipeUp()
        setToggle("s3.preflight.safe-position", in: app)
        let begin = element("s3.preflight.begin", in: app)
        scroll(begin, in: app)
        assertControl(begin, label: "Begin check")
        begin.tap()

        XCTAssertTrue(element("s3.capture.screen", in: app)
            .waitForExistence(timeout: 20))
        captureBaseline("state.recheck-capture.wide-ready", in: app)
        acceptImportedPhoto(
            in: app,
            heading: "1 of 2 · Wide view",
            stateID: "state.recheck-capture.wide-preview"
        )
        captureBaseline("state.recheck-capture.close-ready", in: app)
        acceptImportedPhoto(
            in: app,
            heading: "2 of 2 · Close view",
            stateID: "state.recheck-capture.close-preview"
        )

        let resolved = element("s5.2.outcome.resolved", in: app)
        scroll(resolved, in: app)
        assertControl(resolved, label: "Resolved")
        XCTAssertEqual(resolved.value as? String, "Not selected")
        resolved.tap()
        XCTAssertTrue(wait(for: resolved, predicate: "value == 'Selected'", timeout: 10))
        captureBaseline("state.recheck-outcome.resolved", in: app)

        let continueButton = element("s3.outcome.continue", in: app)
        scroll(continueButton, in: app)
        assertControl(continueButton, label: "Continue")
        continueButton.tap()

        XCTAssertTrue(element("s3.review.screen", in: app)
            .waitForExistence(timeout: 20))
        let reviewOutcome = element("s3.review.outcome", in: app)
        XCTAssertTrue(reviewOutcome.waitForExistence(timeout: 10))
        XCTAssertTrue(reviewOutcome.label.contains("Resolved"))
        captureBaseline("state.recheck-review.resolved", in: app)
        let save = element("s3.review.save-report", in: app)
        scroll(save, in: app)
        assertControl(save, label: "Save and finish")
        save.tap()

        XCTAssertTrue(element("s3.receipt.screen", in: app)
            .waitForExistence(timeout: 40))
        let saved = element("s3.receipt.saved", in: app)
        XCTAssertTrue(saved.waitForExistence(timeout: 15))
        XCTAssertEqual(saved.label, "Report saved on this device.")
        captureBaseline("state.recheck-receipt.saved", in: app)
        let viewReport = element("s3.receipt.view-report", in: app)
        scroll(viewReport, in: app)
        assertControl(viewReport, label: "View report")
        viewReport.tap()
        XCTAssertTrue(element("s4.3.report-detail.preview", in: app)
            .waitForExistence(timeout: 25))
        captureBaseline("state.recheck-report-detail.ready", in: app)
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
        captureBaseline("state.issue.resolved", in: app)
        navigateBack(in: app)
        XCTAssertTrue(signDetail.waitForExistence(timeout: 20))
    }

    @MainActor
    private func captureAlternativeCompletedCheckStates(
        in app: XCUIApplication
    ) {
        beginFreshCheck(in: app)
        acceptImportedPhotoWithoutBaseline(
            in: app,
            heading: "1 of 2 · Wide view"
        )
        acceptImportedPhotoWithoutBaseline(
            in: app,
            heading: "2 of 2 · Close view"
        )
        let noVisible = element("s3.outcome.no-visible-issue", in: app)
        scroll(noVisible, in: app)
        assertControl(noVisible, label: "No visible issue")
        noVisible.tap()
        captureBaseline("state.check-outcome.no-visible-issue", in: app)
        continueToReview(in: app)
        XCTAssertTrue(element("s3.review.screen", in: app)
            .waitForExistence(timeout: 20))
        captureBaseline("state.check-review.no-visible-issue", in: app)
        saveCheckAndReturnToSign(in: app)

        purchaseBlockedEvaluationAndBeginFreshCheck(in: app)
        acceptImportedPhotoWithoutBaseline(
            in: app,
            heading: "1 of 2 · Wide view"
        )
        let closeHeading = element("s3.capture.heading", in: app)
        XCTAssertTrue(wait(
            for: closeHeading,
            predicate: "label == %@",
            argument: "2 of 2 · Close view",
            timeout: 20
        ))
        let cannotComplete = element("s3.capture.cannot-complete", in: app)
        scroll(cannotComplete, in: app)
        assertControl(cannotComplete, label: "Cannot complete")
        cannotComplete.tap()
        selectCouldNotVerifyReason(in: app)
        captureBaseline("state.check-outcome.could-not-verify", in: app)
        continueToReview(in: app)
        XCTAssertTrue(element("s3.review.could-not-verify", in: app)
            .waitForExistence(timeout: 20))
        captureBaseline("state.check-review.could-not-verify", in: app)
        saveCheckAndReturnToSign(in: app)

        createVisibleIssueWithoutBaseline(in: app)
        recordWorkWithoutBaseline(in: app)
        performAlternativeRecheck(.couldNotVerify, in: app)
        performAlternativeRecheck(.issueStillVisible, in: app)
        recordWorkWithoutBaseline(in: app)
        app.terminate()
        app.launchArguments.append("--s4-2-ui-test-render-failure-once")
        app.launch()
        XCTAssertTrue(element("s2.sign-detail.screen", in: app)
            .waitForExistence(timeout: 30))
        performAlternativeRecheck(
            .differentIssue,
            leavesPendingReceipt: true,
            in: app
        )
    }

    @MainActor
    private func beginFreshCheck(in app: XCUIApplication) {
        let start = element("s2.sign-detail.start-check", in: app)
        scroll(start, in: app)
        assertControl(start, label: "Start Check")
        start.tap()
        XCTAssertTrue(element("s3.preflight.screen", in: app)
            .waitForExistence(timeout: 20))
        let confirmation = element("s3.preflight.time-zone-confirmed", in: app)
        if confirmation.exists && (confirmation.value as? String) != "1" {
            setToggle("s3.preflight.time-zone-confirmed", in: app)
        }
        setToggle("s3.preflight.after-dark", in: app)
        app.swipeUp()
        setToggle("s3.preflight.safe-position", in: app)
        let begin = element("s3.preflight.begin", in: app)
        scroll(begin, in: app)
        assertControl(begin, label: "Begin check")
        begin.tap()
        XCTAssertTrue(element("s3.capture.screen", in: app)
            .waitForExistence(timeout: 20))
    }

    @MainActor
    private func purchaseBlockedEvaluationAndBeginFreshCheck(
        in app: XCUIApplication
    ) {
        let start = element("s2.sign-detail.start-check", in: app)
        scroll(start, in: app)
        assertControl(start, label: "Start Check")
        start.tap()
        XCTAssertTrue(element("s7.2.paywall.screen", in: app)
            .waitForExistence(timeout: 30))
        captureAvailablePaywallAndPurchase(in: app)

        let close = element("s7.2.paywall.close", in: app)
        scrollDown(close, in: app)
        assertControl(close, label: "Close")
        close.tap()
        XCTAssertTrue(element("s2.sign-detail.screen", in: app)
            .waitForExistence(timeout: 20))
        beginFreshCheck(in: app)
    }

    @MainActor
    private func acceptImportedPhotoWithoutBaseline(
        in app: XCUIApplication,
        heading: String
    ) {
        let headingElement = element("s3.capture.heading", in: app)
        XCTAssertTrue(headingElement.waitForExistence(timeout: 20))
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
        XCTAssertTrue(element("s3.capture.preview", in: app)
            .waitForExistence(timeout: 20))
        let usePhoto = element("s3.capture.use-photo", in: app)
        scroll(usePhoto, in: app)
        assertControl(usePhoto, label: "Use Photo")
        usePhoto.tap()
    }

    @MainActor
    private func continueToReview(in app: XCUIApplication) {
        let value = element("s3.outcome.continue", in: app)
        scroll(value, in: app)
        assertControl(value, label: "Continue")
        value.tap()
    }

    @MainActor
    private func saveCheckAndReturnToSign(in app: XCUIApplication) {
        let save = element("s3.review.save-report", in: app)
        scroll(save, in: app)
        assertControl(save, label: "Save and finish")
        save.tap()
        XCTAssertTrue(element("s3.receipt.screen", in: app)
            .waitForExistence(timeout: 40))
        XCTAssertTrue(element("s3.receipt.view-report", in: app)
            .waitForExistence(timeout: 30))
        let done = element("s3.receipt.done", in: app)
        scroll(done, in: app)
        assertControl(done, label: "Done")
        done.tap()
        XCTAssertTrue(element("s2.sign-detail.screen", in: app)
            .waitForExistence(timeout: 25))
    }

    @MainActor
    private func selectCouldNotVerifyReason(in app: XCUIApplication) {
        let couldNotVerify = element("s3.outcome.could-not-verify", in: app)
        XCTAssertTrue(couldNotVerify.waitForExistence(timeout: 20))
        XCTAssertEqual(couldNotVerify.label, "Could not verify")
        let reason = element(
            "s3.outcome.cnv.reason.conditions_changed",
            in: app
        )
        scroll(reason, in: app)
        assertControl(reason, label: "Conditions changed")
        reason.tap()
        XCTAssertTrue(wait(
            for: reason,
            predicate: "value == 'Selected'",
            timeout: 10
        ))
    }

    @MainActor
    private func createVisibleIssueWithoutBaseline(in app: XCUIApplication) {
        beginFreshCheck(in: app)
        acceptImportedPhotoWithoutBaseline(
            in: app,
            heading: "1 of 2 · Wide view"
        )
        acceptImportedPhotoWithoutBaseline(
            in: app,
            heading: "2 of 2 · Close view"
        )
        let visible = element("s3.outcome.visible-issue", in: app)
        scroll(visible, in: app)
        visible.tap()
        let issue = element("s3.outcome.issue.dark_section", in: app)
        scroll(issue, in: app)
        issue.tap()
        continueToReview(in: app)
        saveCheckAndReturnToSign(in: app)
    }

    @MainActor
    private func recordWorkWithoutBaseline(in app: XCUIApplication) {
        let recordWork = element("s5.1.sign-detail.record-work", in: app)
        scroll(recordWork, in: app)
        assertControl(recordWork, label: "Record work")
        recordWork.tap()
        let description = element("s5.1.work.description", in: app)
        XCTAssertTrue(description.waitForExistence(timeout: 20))
        scroll(description, in: app)
        description.tap()
        description.typeText("Replaced damaged component")
        dismissKeyboard(in: app)
        let save = element("s5.1.work.save", in: app)
        scroll(save, in: app)
        assertControl(save, label: "Record work")
        save.tap()
        XCTAssertTrue(element("s5.1.issue.screen", in: app)
            .waitForExistence(timeout: 35))
        navigateBack(in: app)
        XCTAssertTrue(element("s2.sign-detail.screen", in: app)
            .waitForExistence(timeout: 20))
    }

    @MainActor
    private func performAlternativeRecheck(
        _ outcome: AlternativeRecheckOutcome,
        leavesPendingReceipt: Bool = false,
        in app: XCUIApplication
    ) {
        let due = element("s5.1.sign-detail.recheck-due", in: app)
        scroll(due, in: app)
        assertControl(due, label: "Recheck due")
        due.tap()
        XCTAssertTrue(element("s5.1.issue.screen", in: app)
            .waitForExistence(timeout: 20))
        let start = element("s5.2.issue.start-recheck", in: app)
        scroll(start, in: app)
        assertControl(start, label: "Start recheck")
        start.tap()
        XCTAssertTrue(element("s3.preflight.screen", in: app)
            .waitForExistence(timeout: 20))
        setToggle("s3.preflight.after-dark", in: app)
        app.swipeUp()
        setToggle("s3.preflight.safe-position", in: app)
        let begin = element("s3.preflight.begin", in: app)
        scroll(begin, in: app)
        assertControl(begin, label: "Begin check")
        begin.tap()
        acceptImportedPhotoWithoutBaseline(
            in: app,
            heading: "1 of 2 · Wide view"
        )

        if outcome == .couldNotVerify {
            let cannotComplete = element("s3.capture.cannot-complete", in: app)
            scroll(cannotComplete, in: app)
            assertControl(cannotComplete, label: "Cannot complete")
            cannotComplete.tap()
            selectCouldNotVerifyReason(in: app)
            captureBaseline("state.recheck-outcome.could-not-verify", in: app)
        } else {
            acceptImportedPhotoWithoutBaseline(
                in: app,
                heading: "2 of 2 · Close view"
            )
            switch outcome {
            case .issueStillVisible:
                let value = element("s5.2.outcome.issue-still-visible", in: app)
                scroll(value, in: app)
                assertControl(value, label: "Issue still visible")
                value.tap()
                captureBaseline("state.recheck-outcome.issue-still-visible", in: app)
            case .differentIssue:
                let value = element(
                    "s5.3.outcome.original-resolved-different-issue",
                    in: app
                )
                scroll(value, in: app)
                assertControl(
                    value,
                    label: "Original resolved, different visible issue"
                )
                value.tap()
                let label = element("s3.outcome.issue.physical_damage", in: app)
                scroll(label, in: app)
                assertControl(label, label: "Visible physical damage")
                label.tap()
                captureBaseline("state.recheck-outcome.different-issue", in: app)
            case .couldNotVerify:
                XCTFail("Handled by the partial-evidence branch")
            }
        }

        continueToReview(in: app)
        XCTAssertTrue(element("s3.review.screen", in: app)
            .waitForExistence(timeout: 20))
        switch outcome {
        case .couldNotVerify:
            captureBaseline("state.recheck-review.could-not-verify", in: app)
        case .issueStillVisible:
            captureBaseline("state.recheck-review.issue-still-visible", in: app)
        case .differentIssue:
            captureBaseline("state.recheck-review.different-issue", in: app)
        }
        let save = element("s3.review.save-report", in: app)
        scroll(save, in: app)
        assertControl(save, label: "Save and finish")
        save.tap()
        XCTAssertTrue(element("s3.receipt.screen", in: app)
            .waitForExistence(timeout: 40))
        if leavesPendingReceipt {
            let saved = element("s3.receipt.saved", in: app)
            XCTAssertTrue(saved.waitForExistence(timeout: 15))
            XCTAssertEqual(saved.label, "Report saved on this device.")
            XCTAssertTrue(element("s4.3.receipt.preparing", in: app)
                .waitForExistence(timeout: 10))
            XCTAssertFalse(element("s3.receipt.view-report", in: app).exists)
            let done = element("s3.receipt.done", in: app)
            scroll(done, in: app)
            assertControl(done, label: "Done")
            done.tap()
            XCTAssertTrue(element("s5.1.issue.screen", in: app)
                .waitForExistence(timeout: 25))
            navigateBack(in: app)
            XCTAssertTrue(element("s2.sign-detail.screen", in: app)
                .waitForExistence(timeout: 25))
            return
        }
        XCTAssertTrue(element("s3.receipt.view-report", in: app)
            .waitForExistence(timeout: 30))
        let done = element("s3.receipt.done", in: app)
        scroll(done, in: app)
        assertControl(done, label: "Done")
        done.tap()
        XCTAssertTrue(element("s5.1.issue.screen", in: app)
            .waitForExistence(timeout: 25))
        if outcome == .issueStillVisible {
            captureBaseline("state.issue.open", in: app)
        }
        navigateBack(in: app)
        XCTAssertTrue(element("s2.sign-detail.screen", in: app)
            .waitForExistence(timeout: 25))
    }

    @MainActor
    private func captureDifferentIssueStatesBeforeRecovery(
        in app: XCUIApplication
    ) {
        let resolvedOriginal = element("s5.2.sign-detail.resolved", in: app)
        scroll(resolvedOriginal, in: app)
        assertControl(resolvedOriginal, label: "Resolved")
        resolvedOriginal.tap()
        XCTAssertTrue(element("s5.1.issue.screen", in: app)
            .waitForExistence(timeout: 20))
        navigateBack(in: app)
        let freshHeader = element("s5.1.issue.header", in: app)
        XCTAssertTrue(wait(
            for: freshHeader,
            predicate: "label == %@",
            argument: "Visible physical damage",
            timeout: 20
        ))
        captureBaseline("state.issue.different-open", in: app)
        navigateBack(in: app)
        XCTAssertTrue(element("s2.sign-detail.screen", in: app)
            .waitForExistence(timeout: 20))
    }

    @MainActor
    private func captureReportComparisonAndCorrectionStates(
        in app: XCUIApplication
    ) {
        let history = element("s4.4.sign-detail.report-history", in: app)
        scroll(history, in: app)
        assertControl(history, label: "Report history")
        history.tap()
        XCTAssertTrue(element("s4.4.history.screen", in: app)
            .waitForExistence(timeout: 25))
        let compare = element("s4.4.reports.compare", in: app)
        scroll(compare, in: app)
        assertControl(compare, label: "Compare with previous")
        compare.tap()
        XCTAssertTrue(element("s4.4.comparison.screen", in: app)
            .waitForExistence(timeout: 20))
        XCTAssertTrue(element("s4.4.comparison.then.wide", in: app)
            .waitForExistence(timeout: 15))
        XCTAssertTrue(element("s4.4.comparison.now.wide", in: app)
            .waitForExistence(timeout: 15))
        captureBaseline("state.report-comparison.ready", in: app)
        navigateBack(in: app)
        XCTAssertTrue(element("s4.4.history.screen", in: app)
            .waitForExistence(timeout: 20))

        let viewReport = element("s4.4.reports.view-report", in: app)
        scroll(viewReport, in: app)
        assertControl(viewReport, label: "View report")
        viewReport.tap()
        XCTAssertTrue(element("s4.3.report-detail.screen", in: app)
            .waitForExistence(timeout: 25))
        let correct = element("s4.5.report-detail.correct", in: app)
        scroll(correct, in: app)
        assertControl(correct, label: "Correct report")
        correct.tap()
        XCTAssertTrue(element("s4.5.correction.screen", in: app)
            .waitForExistence(timeout: 20))
        captureBaseline("state.report-correction.editing", in: app)

        let save = element("s4.5.correction.save", in: app)
        scroll(save, in: app)
        assertControl(save, label: "Save correction")
        save.tap()
        let validation = element("s4.5.correction.validation", in: app)
        XCTAssertTrue(validation.waitForExistence(timeout: 10))
        XCTAssertTrue(validation.label.contains("Change the note before saving."))
        captureBaseline("state.report-correction.validation-error", in: app)

        let note = element("s4.5.correction.note", in: app)
        XCTAssertTrue(note.waitForExistence(timeout: 10))
        note.typeText("Verified connector label")
        dismissKeyboard(in: app)
        scroll(save, in: app)
        assertControl(save, label: "Save correction")
        save.tap()
        let saving = element("s4.5.correction.saving", in: app)
        XCTAssertTrue(saving.waitForExistence(timeout: 10))
        captureBaseline("state.report-correction.saving", in: app)
        XCTAssertTrue(element("s4.5.correction.ready", in: app)
            .waitForExistence(timeout: 40))
        captureBaseline("state.report-correction.completed", in: app)
        let currentReport = element("s4.5.correction.current-report", in: app)
        scroll(currentReport, in: app)
        assertControl(currentReport, label: "View corrected report")
        currentReport.tap()
        XCTAssertTrue(element("s4.3.report-detail.screen", in: app)
            .waitForExistence(timeout: 20))
        let close = element("s4.3.report-detail.close", in: app)
        scroll(close, in: app)
        assertControl(close, label: "Close")
        close.tap()
        XCTAssertTrue(element("s4.4.history.screen", in: app)
            .waitForExistence(timeout: 20))
        navigateBack(in: app)
        XCTAssertTrue(element("s2.sign-detail.screen", in: app)
            .waitForExistence(timeout: 20))
    }

    @MainActor
    private func captureUnavailablePaywallAndFeedbackReview(
        in app: XCUIApplication
    ) {
        app.terminate()
        app.launchArguments.removeAll { $0 == "--s7-2-ui-test-paywall" }
        app.launch()
        XCTAssertTrue(element("s2.sign-detail.screen", in: app)
            .waitForExistence(timeout: 30))
        let settings = element("s1.settings.button", in: app)
        assertControl(settings, label: "Settings")
        settings.tap()
        XCTAssertTrue(element("s1.settings.screen", in: app)
            .waitForExistence(timeout: 20))
        let paywall = element("s7.2.settings.paywall", in: app)
        scroll(paywall, in: app)
        assertControl(paywall, label: "View subscription")
        paywall.tap()
        XCTAssertTrue(element("s7.2.paywall.unavailable", in: app)
            .waitForExistence(timeout: 30))
        captureBaseline("state.paywall.unavailable", in: app)
        let close = element("s7.2.paywall.close", in: app)
        scroll(close, in: app)
        assertControl(close, label: "Close")
        close.tap()
        XCTAssertTrue(element("s1.settings.screen", in: app)
            .waitForExistence(timeout: 20))
        navigateBack(in: app)
        XCTAssertTrue(element("s2.sign-detail.screen", in: app)
            .waitForExistence(timeout: 20))

        app.terminate()
        app.launchArguments.append("--s8-4-ui-test-mail-unavailable")
        app.launch()
        XCTAssertTrue(element("s2.sign-detail.screen", in: app)
            .waitForExistence(timeout: 30))
        element("s1.settings.button", in: app).tap()
        XCTAssertTrue(element("s1.settings.screen", in: app)
            .waitForExistence(timeout: 20))
        let feedback = element("s8.4.feedback.settings-entry", in: app)
        scroll(feedback, in: app)
        assertControl(feedback, label: "Send feedback")
        feedback.tap()
        XCTAssertTrue(element("s8.4.feedback.review", in: app)
            .waitForExistence(timeout: 30))
        XCTAssertTrue(element("s8.4.feedback.copy-address", in: app).exists)
        captureBaseline("state.feedback.review-ready", in: app)
        navigateBack(in: app)
        XCTAssertTrue(element("s1.settings.screen", in: app)
            .waitForExistence(timeout: 20))
        navigateBack(in: app)

        app.terminate()
        app.launchArguments.removeAll {
            $0 == "--s8-4-ui-test-mail-unavailable"
        }
        app.launchArguments.append("--s7-2-ui-test-paywall")
        app.launch()
        XCTAssertTrue(element("s2.sign-detail.screen", in: app)
            .waitForExistence(timeout: 30))
    }

    @MainActor
    private func captureAvailablePaywallAndPurchase(
        in app: XCUIApplication
    ) {
        let productName = element("s7.2.paywall.product-name", in: app)
        let duration = element("s7.2.paywall.duration", in: app)
        let price = element("s7.2.paywall.price", in: app)
        let trial = element("s7.2.paywall.trial", in: app)
        for value in [productName, duration, price, trial] {
            XCTAssertTrue(value.waitForExistence(timeout: 30))
        }
        assertAccessibilityOrder(
            [
                "s7.2.paywall.product-name",
                "s7.2.paywall.duration",
                "s7.2.paywall.price",
                "s7.2.paywall.trial",
            ],
            in: app
        )
        scroll(productName, in: app)
        XCTAssertLessThan(productName.frame.minY, duration.frame.minY)
        XCTAssertLessThan(duration.frame.minY, price.frame.minY)
        XCTAssertLessThan(price.frame.minY, trial.frame.minY)

        assertText("s7.2.paywall.product-name", equals: "Solo Access Monthly", in: app)
        assertText("s7.2.paywall.duration", equals: "one month", in: app)
        assertText("s7.2.paywall.price", equals: "$59.99", in: app)
        assertText("s7.2.paywall.trial", equals: "14 days free", in: app)
        captureBaseline("state.paywall.available", in: app)
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
            if identifier == "s7.2.paywall.close" {
                scrollDown(control, in: app)
            } else {
                scroll(control, in: app)
            }
            assertMinimumGeometry(control)
            XCTAssertTrue(control.isEnabled)
        }

        let purchase = firstPurchaseButton(in: app)
        scroll(purchase, in: app)
        purchase.tap()
        let purchaseState = element("s7.2.paywall.purchase-state", in: app)
        XCTAssertTrue(wait(
            for: purchaseState,
            predicate: "label CONTAINS %@",
            argument: "Purchase verified. Subscription access is ready.",
            timeout: 45
        ))
        captureBaseline("state.paywall.purchase-complete", in: app)
    }

    @MainActor
    private func assertMonthlyPaywallAtXXXL(in app: XCUIApplication) {
        let settings = element("s1.settings.button", in: app)
        assertControl(settings, label: "Settings")
        settings.tap()
        XCTAssertTrue(element("s1.settings.screen", in: app)
            .waitForExistence(timeout: 20))
        captureBaseline("state.settings.hub", in: app)

        captureSettingsDataSurfaces(in: app)

        let lifecycle = element("s7.3.settings.restore-purchases", in: app)
        scroll(lifecycle, in: app)
        assertControl(lifecycle, label: "Restore Purchases")
        lifecycle.tap()
        let restored = element("s7.3.lifecycle.restore-result", in: app)
        XCTAssertTrue(wait(
            for: restored,
            predicate: "label CONTAINS %@",
            argument: "Purchases restored. Subscription access is updated.",
            timeout: 45
        ))
        XCTAssertTrue(wait(
            for: element("s7.3.lifecycle.status-title", in: app),
            predicate: "label BEGINSWITH %@",
            argument: "Active until",
            timeout: 20
        ))
        captureBaseline("state.subscription.active", in: app)
        let closeLifecycle = element("s7.3.lifecycle.close", in: app)
        scroll(closeLifecycle, in: app)
        assertControl(closeLifecycle, label: "Close")
        closeLifecycle.tap()
        XCTAssertTrue(element("s1.settings.screen", in: app)
            .waitForExistence(timeout: 20))
        navigateBack(in: app)
        XCTAssertTrue(element("s2.sign-detail.screen", in: app)
            .waitForExistence(timeout: 20))

        let addSign = element("s7.4.sign-detail.add-sign", in: app)
        scroll(addSign, in: app)
        assertControl(addSign, label: "Add sign")
        addSign.tap()
        XCTAssertTrue(element("s2.new-sign.screen", in: app)
            .waitForExistence(timeout: 25))
        XCTAssertTrue(element("s7.4.new-sign.site-choice", in: app).exists)
        let sign = element("s2.new-sign.sign-label", in: app)
        scroll(sign, in: app)
        sign.tap()
        sign.typeText("Loading Dock Sign")
        dismissKeyboard(in: app)
        let save = element("s2.new-sign.save", in: app)
        scroll(save, in: app)
        assertControl(save, label: "Save and start check")
        save.tap()
        XCTAssertTrue(element("s2.sign-detail.screen", in: app)
            .waitForExistence(timeout: 30))
        let allSigns = element("s7.4.sign-detail.all-signs", in: app)
        scroll(allSigns, in: app)
        assertControl(allSigns, label: "All signs")
        allSigns.tap()
        XCTAssertTrue(element("s7.4.signs.selection", in: app)
            .waitForExistence(timeout: 25))
        captureBaseline("state.sign-selection.ready", in: app)
    }

    @MainActor
    private func eraseLocalDataAndCaptureNoEntitlement(
        in app: XCUIApplication
    ) {
        guard let session = storeKitSession else {
            XCTFail("The retained StoreKit test session is required")
            return
        }
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true

        let settings = element("s1.settings.button", in: app)
        assertControl(settings, label: "Settings")
        settings.tap()
        XCTAssertTrue(element("s1.settings.screen", in: app)
            .waitForExistence(timeout: 20))
        let erase = element("s6.6.settings.erase-all", in: app)
        scroll(erase, in: app)
        assertControl(erase, label: "Erase All")
        erase.tap()
        XCTAssertTrue(element("s6.6.erase.screen", in: app)
            .waitForExistence(timeout: 30))

        let confirmation = element("s6.6.erase.confirmation", in: app)
        scroll(confirmation, in: app)
        confirmation.tap()
        confirmation.typeText("ERASE")
        dismissKeyboard(in: app)
        let confirm = element("s6.6.erase.confirm", in: app)
        scroll(confirm, in: app)
        XCTAssertTrue(wait(for: confirm, predicate: "enabled == true", timeout: 10))
        assertControl(confirm, label: "Erase All")
        confirm.tap()

        let welcome = element("s2.welcome.screen", in: app)
        XCTAssertTrue(welcome.waitForExistence(timeout: 90))
        XCTAssertFalse(element("s2.sign-detail.screen", in: app).exists)
        app.terminate()
        app.launch()
        XCTAssertTrue(welcome.waitForExistence(timeout: 45))

        let restore = element("s2.welcome.restore-purchases", in: app)
        scroll(restore, in: app)
        assertControl(restore, label: "Restore Purchases")
        restore.tap()
        XCTAssertTrue(element("s7.3.lifecycle.screen", in: app)
            .waitForExistence(timeout: 30))
        XCTAssertTrue(element("s7.3.lifecycle.restore-result", in: app)
            .waitForExistence(timeout: 60))
        XCTAssertTrue(wait(
            for: element("s7.3.lifecycle.status-title", in: app),
            predicate: "label == %@",
            argument: "No subscription found",
            timeout: 20
        ))
        captureBaseline("state.subscription.no-entitlement", in: app)
        assertMigrationStateCoverage()

        let terminal = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        terminal.name = "S10.3 terminal migrated no-entitlement at XXXL Dark"
        terminal.lifetime = .keepAlways
        add(terminal)
    }

    @MainActor
    private func captureSettingsDataSurfaces(in app: XCUIApplication) {
        let backupEntry = element("s6.2.backup.settings-entry", in: app)
        scroll(backupEntry, in: app)
        assertControl(backupEntry, label: "Back up current data")
        backupEntry.tap()
        XCTAssertTrue(element("s6.2.backup.screen", in: app)
            .waitForExistence(timeout: 30))
        XCTAssertTrue(element("s6.2.backup.sign-count", in: app)
            .waitForExistence(timeout: 20))
        captureBaseline("state.backup.ready", in: app)
        navigateBack(in: app)
        XCTAssertTrue(element("s1.settings.screen", in: app)
            .waitForExistence(timeout: 20))

        let diagnosticsEntry = element("s8.3.diagnostics.settings-entry", in: app)
        scroll(diagnosticsEntry, in: app)
        assertControl(diagnosticsEntry, label: "View diagnostics")
        diagnosticsEntry.tap()
        XCTAssertTrue(element("s8.3.diagnostics.screen", in: app)
            .waitForExistence(timeout: 30))
        XCTAssertTrue(element("s8.3.diagnostics.counters", in: app)
            .waitForExistence(timeout: 20))
        captureBaseline("state.diagnostics.ready", in: app)
        navigateBack(in: app)
        XCTAssertTrue(element("s1.settings.screen", in: app)
            .waitForExistence(timeout: 20))

        let feedbackEntry = element("s8.4.feedback.settings-entry", in: app)
        scroll(feedbackEntry, in: app)
        assertControl(feedbackEntry, label: "Send feedback")
        feedbackEntry.tap()
        XCTAssertTrue(element("s8.4.feedback.screen", in: app)
            .waitForExistence(timeout: 30))
        XCTAssertTrue(element("s8.4.feedback.heading", in: app)
            .waitForExistence(timeout: 20))
        XCTAssertTrue(element("s8.4.feedback.retry", in: app)
            .waitForExistence(timeout: 20))
        captureBaseline("state.feedback.blocked", in: app)
        navigateBack(in: app)
        XCTAssertTrue(element("s1.settings.screen", in: app)
            .waitForExistence(timeout: 20))

        let erase = element("s6.6.settings.erase-all", in: app)
        scroll(erase, in: app)
        assertControl(erase, label: "Erase All")
        erase.tap()
        XCTAssertTrue(element("s6.6.erase.screen", in: app)
            .waitForExistence(timeout: 30))
        captureBaseline("state.erase.confirmation", in: app)
        let cancelErase = element("s6.6.erase.cancel", in: app)
        scroll(cancelErase, in: app)
        assertControl(cancelErase, label: "Cancel")
        cancelErase.tap()
        XCTAssertTrue(element("s1.settings.screen", in: app)
            .waitForExistence(timeout: 20))

        let restore = element("s6.5.restore.settings-entry", in: app)
        scrollDown(restore, in: app)
        assertControl(restore, label: "Restore data backup")
        restore.tap()
        XCTAssertTrue(element("s6.4.restore.screen", in: app)
            .waitForExistence(timeout: 30))
        captureBaseline("state.restore.choose-backup", in: app)
        let cancelRestore = element("s6.4.restore.cancel", in: app)
        scroll(cancelRestore, in: app)
        assertControl(cancelRestore, label: "Cancel")
        cancelRestore.tap()
        XCTAssertTrue(element("s1.settings.screen", in: app)
            .waitForExistence(timeout: 30))
    }

    @MainActor
    private func acceptImportedPhoto(
        in app: XCUIApplication,
        heading: String,
        stateID: String,
        capturesLowStorageFailure: Bool = false
    ) {
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

        if capturesLowStorageFailure {
            let recovery = app.staticTexts[
                "Free space is too low. Free space, then try again."
            ]
            XCTAssertTrue(recovery.waitForExistence(timeout: 15))
            XCTAssertFalse(element("s3.capture.preview", in: app).exists)
            captureBaseline("state.capture.low-storage-error", in: app)
            importPhoto.tap()
        }

        let preview = element("s3.capture.preview", in: app)
        XCTAssertTrue(preview.waitForExistence(timeout: 20))
        XCTAssertEqual(preview.label, "Imported photo preview")
        captureBaseline(stateID, in: app)
        let usePhoto = element("s3.capture.use-photo", in: app)
        scroll(usePhoto, in: app)
        assertControl(usePhoto, label: "Use Photo")
        let durableAdvanceAt = Date()
        usePhoto.tap()
        if heading.contains("Wide") {
            XCTAssertTrue(wait(
                for: headingElement,
                predicate: "label == %@",
                argument: "2 of 2 · Close view",
                timeout: 30
            ))
        } else if stateID.contains("recheck") {
            XCTAssertTrue(element("s5.2.outcome.resolved", in: app)
                .waitForExistence(timeout: 30))
        } else {
            XCTAssertTrue(element("s3.outcome.visible-issue", in: app)
                .waitForExistence(timeout: 30))
        }
        recordMetric(
            "evidence_use_photo_to_durable_next_state_\(stateID)",
            since: durableAdvanceAt
        )
    }

    @MainActor
    private func recoverCameraDenialAndResume(in app: XCUIApplication) {
        let takePhoto = element("s3.capture.take-photo", in: app)
        scroll(takePhoto, in: app)
        assertControl(takePhoto, label: "Take photo")
        takePhoto.tap()

        let settings = element("s3.capture.open-settings", in: app)
        XCTAssertTrue(settings.waitForExistence(timeout: 15))
        XCTAssertEqual(settings.label, "Open Settings")
        XCTAssertTrue(app.staticTexts[
            "Choose a photo, open Settings, or leave this check incomplete and return later."
        ].exists)
        captureBaseline("state.capture.camera-denied", in: app)

        let cannotComplete = element("s3.capture.cannot-complete", in: app)
        scroll(cannotComplete, in: app)
        assertControl(cannotComplete, label: "Cannot complete")
        cannotComplete.tap()

        XCTAssertTrue(element("s3.outcome.screen", in: app)
            .waitForExistence(timeout: 20))
        let couldNotVerify = element("s3.outcome.could-not-verify", in: app)
        XCTAssertTrue(couldNotVerify.waitForExistence(timeout: 10))
        XCTAssertEqual(couldNotVerify.value as? String, "Selected")

        app.terminate()
        app.launch()
        XCTAssertTrue(element("s3.capture.screen", in: app)
            .waitForExistence(timeout: 30))
        let heading = element("s3.capture.heading", in: app)
        XCTAssertTrue(wait(
            for: heading,
            predicate: "label == %@",
            argument: "1 of 2 · Wide view",
            timeout: 20
        ))
    }

    @MainActor
    private func recoverInjectedPDFFailureAtXXXL(in app: XCUIApplication) {
        let failure = element("s4.pdf-failure.screen", in: app)
        XCTAssertTrue(failure.waitForExistence(timeout: 30))
        let headline = element("s4.pdf-failure.headline", in: app)
        XCTAssertTrue(headline.waitForExistence(timeout: 10))
        XCTAssertEqual(
            headline.label,
            "This report was saved, but its PDF is not available."
        )
        captureBaseline("state.report-pdf.failed", in: app)
        let retry = element("s4.pdf-failure.retry", in: app)
        scroll(retry, in: app)
        assertControl(retry, label: "Retry report")
        retry.tap()
        XCTAssertTrue(failure.waitForNonExistence(timeout: 30))
        XCTAssertTrue(element("s2.sign-detail.screen", in: app)
            .waitForExistence(timeout: 30))
    }

    @MainActor
    private func captureBaseline(
        _ stateID: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(stateID.isEmpty, file: file, line: line)
        XCTAssertEqual(
            stateID,
            stateID.lowercased(),
            "Migration state IDs must remain canonical lowercase values",
            file: file,
            line: line
        )
        XCTAssertFalse(
            migratedStateIDs.contains(stateID),
            "Migration state was visited more than once: \(stateID)",
            file: file,
            line: line
        )
        XCTAssertTrue(app.state == .runningForeground, file: file, line: line)
        migratedStateIDs.append(stateID)
        print("S10_MIGRATION_STATE state=\(stateID)")
    }

    private func assertMigrationStateCoverage(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(migratedStateIDs.count, 67, file: file, line: line)
        XCTAssertEqual(Set(migratedStateIDs).count, 67, file: file, line: line)
        let canonical = migratedStateIDs.sorted().joined(separator: "\n")
        let digest = SHA256.hash(data: Data(canonical.utf8))
            .map { String(format: "%02X", $0) }
            .joined()
        XCTAssertEqual(
            digest,
            "5F704F0ED4510CFFC24E162EFFE1D85A536686473E6B23FED2965D864AEC87A3",
            "The visited released-state set drifted from the frozen 67-state inventory",
            file: file,
            line: line
        )
    }

    private func recordMetric(_ metricID: String, since startedAt: Date) {
        let seconds = max(0, Date().timeIntervalSince(startedAt))
        print(String(format: "S10_METRIC metric=%@ seconds=%.6f", metricID, seconds))
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
    private func firstPurchaseButton(in app: XCUIApplication) -> XCUIElement {
        let candidates = app.buttons.matching(NSPredicate(
            format: "label CONTAINS[c] 'Subscribe' OR label CONTAINS[c] 'Trial' OR label CONTAINS[c] '$59.99'"
        ))
        for index in 0..<candidates.count {
            let candidate = candidates.element(boundBy: index)
            if candidate.identifier != "s7.2.paywall.close" {
                return candidate
            }
        }
        return candidates.firstMatch
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
    private func assertXXXLAccessibilityIssueOrder(
        status: XCUIElement,
        header: XCUIElement,
        action: XCUIElement,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for value in [status, header, action] {
            XCTAssertTrue(value.waitForExistence(timeout: 10), file: file, line: line)
        }
        XCTAssertEqual(status.label, "Attention: Recheck due", file: file, line: line)
        XCTAssertEqual(header.label, "Section appears dark", file: file, line: line)
        XCTAssertEqual(header.elementType, .staticText, file: file, line: line)
        XCTAssertEqual(action.label, "Start recheck", file: file, line: line)
        XCTAssertEqual(action.elementType, .button, file: file, line: line)
        assertAccessibilityOrder(
            [
                "s5.1.issue.status",
                "s5.1.issue.header",
                "s5.2.issue.start-recheck",
            ],
            in: app,
            file: file,
            line: line
        )
        XCTAssertLessThan(status.frame.minY, header.frame.minY, file: file, line: line)
        XCTAssertLessThan(header.frame.minY, action.frame.minY, file: file, line: line)
    }

    @MainActor
    private func assertAccessibilityOrder(
        _ expectedIdentifiers: [String],
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let identifiers = app.descendants(matching: .any)
            .allElementsBoundByIndex
            .map(\.identifier)
        let indices = expectedIdentifiers.map { expected -> Int in
            let matches = identifiers.indices.filter { identifiers[$0] == expected }
            XCTAssertEqual(
                matches.count,
                1,
                "Expected one accessibility element for \(expected)",
                file: file,
                line: line
            )
            return matches.first ?? Int.max
        }
        XCTAssertEqual(
            indices,
            indices.sorted(),
            "Accessibility elements are not in the expected reading order",
            file: file,
            line: line
        )
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
        for _ in 0..<22 {
            if value.exists && value.isHittable { return }
            app.swipeUp()
        }
        for _ in 0..<22 {
            if value.exists && value.isHittable { return }
            app.swipeDown()
        }
        XCTAssertTrue(value.waitForExistence(timeout: 2))
        XCTAssertTrue(value.isHittable)
    }

    @MainActor
    private func scrollDown(_ value: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<22 {
            if value.exists && value.isHittable { return }
            app.swipeDown()
        }
        for _ in 0..<22 {
            if value.exists && value.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(value.waitForExistence(timeout: 2))
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

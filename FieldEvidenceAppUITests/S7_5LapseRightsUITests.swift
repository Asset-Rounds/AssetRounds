import CoreGraphics
import StoreKitTest
import XCTest

final class S7_5LapseRightsUITests: XCTestCase {
    private static let productID =
        "com.palatis3.fieldrecord.sub.solo.monthly.v1"

    private var storeKitSession: SKTestSession?

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLapseKeepsExistingRightsAndDraftThenShowsEraseIndependenceAtXXXL()
        throws {
        let fixtureURL = try XCTUnwrap(Bundle(for: Self.self).url(
            forResource: "FieldEvidence",
            withExtension: "storekit"
        ))
        let session = try SKTestSession(contentsOf: fixtureURL)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        storeKitSession = session

        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleInterfaceStyle", "Light",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL",
            "--s1-ui-test-light-mode",
            "--s7-2-ui-test-paywall",
        ]
        app.launch()

        createSign(in: app)
        purchaseThroughBlockedAddSign(in: app)
        beginPersistedCheckDraft(in: app)

        app.terminate()
        try session.expireSubscription(productIdentifier: Self.productID)
        app.launch()

        XCTAssertTrue(element("s3.capture.screen", in: app)
            .waitForExistence(timeout: 45))
        completeExistingDraft(in: app)
        proveReportRights(in: app)

        tap("s3.receipt.done", in: app)
        XCTAssertTrue(element("s2.sign-detail.screen", in: app)
            .waitForExistence(timeout: 30))
        proveDeletionCancelAndHistory(in: app)
        proveNewValueIsBlocked(in: app)
        proveBackupAndEraseCopy(in: app)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name =
            "S7.5 lapse-safe local rights and subscription-independent Erase"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}

private extension S7_5LapseRightsUITests {
    @MainActor
    func createSign(in app: XCUIApplication) {
        XCTAssertTrue(element("s2.welcome.screen", in: app)
            .waitForExistence(timeout: 30))
        tap("s2.welcome.add-first-sign", in: app)
        enter("Rights Site", into: "s2.new-sign.site-label", in: app)
        dismissKeyboard(in: app)
        enter("Rights Sign", into: "s2.new-sign.sign-label", in: app)
        dismissKeyboard(in: app)
        tap("s2.new-sign.save", in: app)
        XCTAssertTrue(element("s2.sign-detail.screen", in: app)
            .waitForExistence(timeout: 30))
        XCTAssertEqual(
            element("s2.sign-detail.sign-label", in: app).label,
            "Rights Sign"
        )
    }

    @MainActor
    func purchaseThroughBlockedAddSign(in app: XCUIApplication) {
        tap("s7.4.sign-detail.add-sign", in: app)
        assertPaywall(in: app)
        let store = element("s7.2.paywall.store", in: app)
        waitForValue("Ready", element: store, timeout: 30)
        let purchase = firstPurchaseButton(in: app)
        scroll(purchase, in: app)
        purchase.tap()

        let state = element("s7.2.paywall.purchase-state", in: app)
        XCTAssertEqual(
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(
                predicate: NSPredicate(
                    format: "label CONTAINS %@",
                    "Purchase verified. Subscription access is ready."
                ),
                object: state
            )], timeout: 45),
            .completed
        )
        tap("s7.2.paywall.close", in: app)
        XCTAssertTrue(element("s2.sign-detail.screen", in: app)
            .waitForExistence(timeout: 30))
    }

    @MainActor
    func beginPersistedCheckDraft(in app: XCUIApplication) {
        tap("s2.sign-detail.start-check", in: app)
        XCTAssertTrue(element("s3.preflight.screen", in: app)
            .waitForExistence(timeout: 30))
        enter("America/New_York", into: "s3.preflight.time-zone", in: app)
        dismissKeyboard(in: app)
        toggle("s3.preflight.time-zone-confirmed", in: app)
        toggle("s3.preflight.after-dark", in: app)
        toggle("s3.preflight.safe-position", in: app)
        tap("s3.preflight.begin", in: app)
        XCTAssertTrue(element("s3.capture.screen", in: app)
            .waitForExistence(timeout: 30))
    }

    @MainActor
    func completeExistingDraft(in app: XCUIApplication) {
        tap("s3.capture.cannot-complete", in: app)
        XCTAssertTrue(element("s3.outcome.screen", in: app)
            .waitForExistence(timeout: 30))
        tap("s3.outcome.cnv.reason.required_view_obstructed", in: app)
        tap("s3.outcome.continue", in: app)
        XCTAssertTrue(element("s3.review.screen", in: app)
            .waitForExistence(timeout: 30))
        tap("s3.review.save-report", in: app)
        XCTAssertTrue(element("s3.receipt.screen", in: app)
            .waitForExistence(timeout: 45))
        XCTAssertEqual(
            element("s3.receipt.saved", in: app).label,
            "Report saved on this device."
        )
    }

    @MainActor
    func proveReportRights(in app: XCUIApplication) {
        let view = element("s3.receipt.view-report", in: app)
        assertButton(view, label: "View report", in: app)
        view.tap()
        XCTAssertTrue(element("s4.3.report-detail.screen", in: app)
            .waitForExistence(timeout: 30))
        XCTAssertTrue(element("s4.3.report-detail.preview", in: app)
            .waitForExistence(timeout: 30))

        for (id, label) in [
            ("s4.3.report-detail.share", "Share PDF"),
            ("s4.3.report-detail.save-to-files", "Save to Files"),
            ("s4.5.report-detail.correct", "Correct report"),
        ] {
            assertButton(element(id, in: app), label: label, in: app)
        }

        let close = element("s4.3.report-detail.close", in: app)
        assertButton(close, label: "Close", in: app)
        close.tap()
        XCTAssertTrue(element("s3.receipt.screen", in: app)
            .waitForExistence(timeout: 20))
    }

    @MainActor
    func proveDeletionCancelAndHistory(in app: XCUIApplication) {
        tap("s4.4.sign-detail.report-history", in: app)
        XCTAssertTrue(element("s4.4.history.screen", in: app)
            .waitForExistence(timeout: 30))
        waitForCount(1, identifier: "s4.4.reports.visit", in: app)
        navigateBack(in: app)

        tap("s6.1.delete.action", in: app)
        XCTAssertTrue(element("s6.1.delete.screen", in: app)
            .waitForExistence(timeout: 20))
        let cancel = element("s6.1.delete.cancel", in: app)
        let confirm = element("s6.1.delete.confirm", in: app)
        assertButton(cancel, label: "Cancel", in: app)
        assertButton(confirm, label: "Delete sign", in: app)
        cancel.tap()
        XCTAssertTrue(element("s2.sign-detail.screen", in: app)
            .waitForExistence(timeout: 20))
    }

    @MainActor
    func proveNewValueIsBlocked(in app: XCUIApplication) {
        tap("s2.sign-detail.start-check", in: app)
        assertPaywall(in: app)
        tap("s7.2.paywall.close", in: app)
        XCTAssertTrue(element("s2.sign-detail.screen", in: app)
            .waitForExistence(timeout: 20))

        tap("s7.4.sign-detail.add-sign", in: app)
        assertPaywall(in: app)
        tap("s7.2.paywall.close", in: app)
        XCTAssertTrue(element("s2.sign-detail.screen", in: app)
            .waitForExistence(timeout: 20))
    }

    @MainActor
    func proveBackupAndEraseCopy(in app: XCUIApplication) {
        tap("s1.settings.button", in: app)
        XCTAssertTrue(element("s1.settings.screen", in: app)
            .waitForExistence(timeout: 30))
        tap("s6.2.backup.settings-entry", in: app)
        XCTAssertTrue(element("s6.2.backup.screen", in: app)
            .waitForExistence(timeout: 30))
        XCTAssertEqual(element("s6.2.backup.sign-count", in: app).label, "1 sign")
        XCTAssertEqual(element("s6.2.backup.report-count", in: app).label, "1 report")
        XCTAssertEqual(
            element("s6.2.backup.warning", in: app).label,
            "This backup contains sign details, notes, photos, and reports. It does not contain your subscription. Store and share it securely."
        )
        assertButton(
            element("s6.2.backup.action", in: app),
            label: "Back up current data",
            in: app
        )
        navigateBack(in: app)

        tap("s6.6.settings.erase-all", in: app)
        XCTAssertTrue(element("s6.6.erase.screen", in: app)
            .waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts[
            "Erase all local sign details, notes, photos, reports, and the anonymous free-report count from this app. This cannot be undone."
        ].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts[
            "This does not cancel your Apple subscription. Backups saved outside this app are not deleted."
        ].waitForExistence(timeout: 15))
        assertButton(
            element("s6.6.erase.cancel", in: app),
            label: "Cancel",
            in: app
        )
    }

    @MainActor
    func assertPaywall(in app: XCUIApplication) {
        XCTAssertTrue(element("s7.2.paywall.screen", in: app)
            .waitForExistence(timeout: 30))
        let close = element("s7.2.paywall.close", in: app)
        assertButton(close, label: "Close", in: app)
    }

    @MainActor
    func firstPurchaseButton(in app: XCUIApplication) -> XCUIElement {
        let candidates = app.buttons.matching(NSPredicate(
            format: "label CONTAINS[c] 'Subscribe' OR label CONTAINS[c] 'Trial' OR label CONTAINS[c] '$59.99'"
        ))
        let value = candidates.firstMatch
        XCTAssertTrue(value.waitForExistence(timeout: 30))
        return value
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
        value.coordinate(
            withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)
        ).tap()
        if XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "1"),
            object: value
        )], timeout: 10) == .completed {
            return
        }
        let retry = element(id, in: app)
        scroll(retry, in: app)
        if retry.value as? String != "1" {
            retry.coordinate(
                withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)
            ).tap()
        }
        waitForValue("1", element: retry, timeout: 10)
    }

    @MainActor
    func assertButton(
        _ value: XCUIElement,
        label: String,
        in app: XCUIApplication
    ) {
        scroll(value, in: app)
        XCTAssertEqual(value.label, label)
        XCTAssertEqual(value.elementType, .button)
        XCTAssertTrue(value.isEnabled)
        XCTAssertTrue(value.isHittable)
        XCTAssertGreaterThanOrEqual(value.frame.width + 0.001, 44)
        XCTAssertGreaterThanOrEqual(value.frame.height + 0.001, 44)
    }

    @MainActor
    func waitForValue(
        _ value: String,
        element: XCUIElement,
        timeout: TimeInterval
    ) {
        XCTAssertEqual(
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "value == %@", value),
                object: element
            )], timeout: timeout),
            .completed
        )
    }

    @MainActor
    func waitForCount(
        _ count: Int,
        identifier: String,
        in app: XCUIApplication
    ) {
        let values = app.descendants(matching: .any)
            .matching(identifier: identifier)
        XCTAssertEqual(
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "count == %d", count),
                object: values
            )], timeout: 30),
            .completed
        )
    }

    @MainActor
    func scroll(_ value: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(value.waitForExistence(timeout: 30))
        for _ in 0..<24 {
            if value.isHittable { return }
            app.swipeUp()
        }
        for _ in 0..<24 {
            if value.isHittable { return }
            app.swipeDown()
        }
        XCTAssertTrue(value.isHittable)
    }

    @MainActor
    func navigateBack(in app: XCUIApplication) {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(back.waitForExistence(timeout: 15))
        XCTAssertTrue(back.isHittable)
        back.tap()
    }

    @MainActor
    func dismissKeyboard(in app: XCUIApplication) {
        let keyboard = app.keyboards.firstMatch
        guard keyboard.exists else { return }
        let key = keyboard.buttons.matching(NSPredicate(
            format: "label ==[c] 'Done' OR label ==[c] 'Return'"
        )).firstMatch
        if key.exists {
            key.tap()
        } else {
            app.swipeDown()
        }
        XCTAssertEqual(
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == false"),
                object: keyboard
            )], timeout: 5),
            .completed
        )
    }
}

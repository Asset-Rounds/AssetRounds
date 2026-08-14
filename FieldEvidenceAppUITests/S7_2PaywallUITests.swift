import CoreGraphics
import XCTest

final class S7_2PaywallUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testMonthlyPaywallPurchasePreservesLocalHistoryAtXXXL() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleInterfaceStyle", "Light",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL",
            "--s1-ui-test-light-mode",
            "--s7-2-ui-test-paywall",
        ]
        app.launch()

        XCTAssertTrue(element("s2.welcome.screen", in: app)
            .waitForExistence(timeout: 30))
        tap("s2.welcome.add-first-sign", in: app)
        enter("Paywall Site", into: "s2.new-sign.site-label", in: app)
        enter("Paywall Sign", into: "s2.new-sign.sign-label", in: app)
        dismissKeyboard(in: app)
        tap("s2.new-sign.save", in: app)
        XCTAssertTrue(element("s2.sign-detail.screen", in: app)
            .waitForExistence(timeout: 30))
        XCTAssertEqual(element("s2.sign-detail.sign-label", in: app).label,
                       "Paywall Sign")

        tap("s1.settings.button", in: app)
        tap("s7.2.settings.paywall", in: app)
        XCTAssertTrue(element("s7.2.paywall.screen", in: app)
            .waitForExistence(timeout: 30))
        assertText("s7.2.paywall.product-name", "Solo Access Monthly", in: app)
        assertText("s7.2.paywall.price", "$59.99", in: app)
        assertText("s7.2.paywall.duration", "1 month", in: app)
        assertText("s7.2.paywall.trial", "14 days free", in: app)
        XCTAssertTrue(element("s7.2.paywall.renewal", in: app).label
            .contains("$59.99"))
        XCTAssertTrue(element("s7.2.paywall.no-sync", in: app).label
            .contains("do not sync"))

        for id in ["s7.2.paywall.close", "s7.2.paywall.terms",
                   "s7.2.paywall.privacy", "s7.2.paywall.support"] {
            let control = element(id, in: app)
            scroll(control, in: app)
            XCTAssertGreaterThanOrEqual(control.frame.width, 44)
            XCTAssertGreaterThanOrEqual(control.frame.height, 44)
        }

        let store = element("s7.2.paywall.store", in: app)
        let cancelledPurchase = firstPurchaseButton(in: app)
        scroll(cancelledPurchase, in: app)
        cancelledPurchase.tap()
        waitForStoreValue("Purchasing", store: store)
        cancelStoreKitPurchase(in: app)

        let cancelled = element("s7.2.paywall.purchase-state", in: app)
        XCTAssertEqual(
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(
                predicate: NSPredicate(
                    format: "label == %@",
                    "Purchase canceled. Nothing changed. You can try again when you’re ready."
                ), object: cancelled
            )], timeout: 30),
            .completed
        )
        waitForStoreValue("Ready", store: store)
        XCTAssertTrue(store.isEnabled)

        let purchase = firstPurchaseButton(in: app)
        scroll(purchase, in: app)
        purchase.tap()
        waitForStoreValue("Purchasing", store: store)
        confirmStoreKitPurchase(in: app)
        let verified = element("s7.2.paywall.purchase-state", in: app)
        XCTAssertEqual(
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(
                predicate: NSPredicate(
                    format: "label CONTAINS %@",
                    "Purchase verified. Subscription access is ready."
                ), object: verified
            )], timeout: 45),
            .completed
        )

        let close = element("s7.2.paywall.close", in: app)
        scroll(close, in: app)
        close.tap()
        XCTAssertTrue(element("s1.settings.screen", in: app)
            .waitForExistence(timeout: 20))
        navigateBack(in: app)
        XCTAssertTrue(element("s2.sign-detail.screen", in: app)
            .waitForExistence(timeout: 20))
        XCTAssertEqual(element("s2.sign-detail.sign-label", in: app).label,
                       "Paywall Sign")

        // Production has no configured public links yet and must fail closed.
        app.terminate()
        app.launchArguments.removeAll { $0 == "--s7-2-ui-test-paywall" }
        app.launch()
        XCTAssertTrue(element("s2.sign-detail.screen", in: app)
            .waitForExistence(timeout: 30))
        tap("s1.settings.button", in: app)
        tap("s7.2.settings.paywall", in: app)
        XCTAssertTrue(element("s7.2.paywall.screen", in: app)
            .waitForExistence(timeout: 30))
        XCTAssertTrue(element("s7.2.paywall.unavailable", in: app)
            .waitForExistence(timeout: 30))
        let retry = element("s7.2.paywall.retry", in: app)
        scroll(retry, in: app)
        XCTAssertGreaterThanOrEqual(retry.frame.width, 44)
        XCTAssertGreaterThanOrEqual(retry.frame.height, 44)
        retry.tap()
        XCTAssertTrue(element("s7.2.paywall.unavailable", in: app)
            .waitForExistence(timeout: 15))
        let unavailableClose = element("s7.2.paywall.close", in: app)
        scroll(unavailableClose, in: app)
        XCTAssertGreaterThanOrEqual(unavailableClose.frame.width, 44)
        XCTAssertGreaterThanOrEqual(unavailableClose.frame.height, 44)
        unavailableClose.tap()
        XCTAssertTrue(element("s1.settings.screen", in: app)
            .waitForExistence(timeout: 20))
        navigateBack(in: app)
        XCTAssertTrue(element("s2.sign-detail.screen", in: app)
            .waitForExistence(timeout: 20))
        XCTAssertEqual(element("s2.sign-detail.sign-label", in: app).label,
                       "Paywall Sign")

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "S7.2 purchase and unavailable links preserve sign history"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}

private extension S7_2PaywallUITests {
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
    func assertText(
        _ id: String, _ expected: String, in app: XCUIApplication
    ) {
        let value = element(id, in: app)
        scroll(value, in: app)
        XCTAssertEqual(value.label, expected)
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
    func confirmStoreKitPurchase(in app: XCUIApplication) {
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 20))
        let confirm = sheet.buttons.matching(NSPredicate(
            format: "label CONTAINS[c] 'Subscribe' OR label CONTAINS[c] 'Confirm'"
        )).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 20))
        XCTAssertTrue(confirm.isHittable)
        confirm.tap()
    }

    @MainActor
    func cancelStoreKitPurchase(in app: XCUIApplication) {
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 20))
        let cancel = sheet.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 20))
        XCTAssertTrue(cancel.isHittable)
        cancel.tap()
    }

    @MainActor
    func waitForStoreValue(_ value: String, store: XCUIElement) {
        XCTAssertEqual(
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "value == %@", value),
                object: store
            )], timeout: 15),
            .completed
        )
    }

    @MainActor
    func scroll(_ value: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(value.waitForExistence(timeout: 30))
        for _ in 0..<20 {
            if value.isHittable { return }
            app.swipeUp()
        }
        for _ in 0..<20 {
            if value.isHittable { return }
            app.swipeDown()
        }
        XCTAssertTrue(value.isHittable)
    }

    @MainActor
    func navigateBack(in app: XCUIApplication) {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(back.waitForExistence(timeout: 15))
        back.tap()
    }

    @MainActor
    func dismissKeyboard(in app: XCUIApplication) {
        guard app.keyboards.firstMatch.exists else { return }
        let key = app.keyboards.buttons["Return"]
        key.exists ? key.tap() : app.swipeDown()
    }
}

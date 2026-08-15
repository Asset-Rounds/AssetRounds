import CoreGraphics
import StoreKitTest
import XCTest

final class S7_3LifecycleUITests: XCTestCase {
    private var storeKitSession: SKTestSession?

    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testRestoreLifecycleAndManageRoutesPreserveHistoryAtXXXL() throws {
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

        XCTAssertTrue(element("s2.welcome.screen", in: app)
            .waitForExistence(timeout: 30))

        // Establish one real verified StoreKit transaction without creating
        // local customer data first.
        tap("s1.settings.button", in: app)
        tap("s7.2.settings.paywall", in: app)
        XCTAssertTrue(element("s7.2.paywall.screen", in: app)
            .waitForExistence(timeout: 30))
        let store = element("s7.2.paywall.store", in: app)
        XCTAssertTrue(store.waitForExistence(timeout: 30))
        XCTAssertEqual(
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "value == %@", "Ready"),
                object: store
            )], timeout: 30),
            .completed
        )
        XCTAssertTrue(store.isEnabled)
        let purchase = firstPurchaseButton(in: app)
        scroll(purchase, in: app)
        purchase.tap()
        let purchaseState = element("s7.2.paywall.purchase-state", in: app)
        XCTAssertEqual(
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(
                predicate: NSPredicate(
                    format: "label CONTAINS %@",
                    "Purchase verified. Subscription access is ready."
                ),
                object: purchaseState
            )], timeout: 45),
            .completed
        )
        tap("s7.2.paywall.close", in: app)
        XCTAssertTrue(element("s1.settings.screen", in: app)
            .waitForExistence(timeout: 20))

        // A cold reopen must rediscover ordinary verified StoreKit authority
        // without an automatic Restore Purchases call.
        app.terminate()
        app.launch()
        XCTAssertTrue(element("s2.welcome.screen", in: app)
            .waitForExistence(timeout: 30))

        tap("s2.welcome.restore-purchases", in: app)
        assertRestoredLifecycle(in: app)
        tap("s7.3.lifecycle.close", in: app)
        XCTAssertTrue(element("s2.welcome.screen", in: app)
            .waitForExistence(timeout: 20))

        tap("s2.welcome.add-first-sign", in: app)
        enter("Lifecycle Site", into: "s2.new-sign.site-label", in: app)
        dismissKeyboard(in: app)
        enter("Lifecycle Sign", into: "s2.new-sign.sign-label", in: app)
        dismissKeyboard(in: app)
        tap("s2.new-sign.save", in: app)
        XCTAssertTrue(element("s2.sign-detail.screen", in: app)
            .waitForExistence(timeout: 30))
        XCTAssertEqual(
            element("s2.sign-detail.sign-label", in: app).label,
            "Lifecycle Sign"
        )

        tap("s1.settings.button", in: app)
        tap("s7.3.settings.restore-purchases", in: app)
        assertRestoredLifecycle(in: app)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "S7.3 restored active lifecycle at Accessibility XXXL"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}

private extension S7_3LifecycleUITests {
    @MainActor
    func assertRestoredLifecycle(in app: XCUIApplication) {
        XCTAssertTrue(element("s7.3.lifecycle.screen", in: app)
            .waitForExistence(timeout: 30))
        let restored = element("s7.3.lifecycle.restore-result", in: app)
        XCTAssertEqual(
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(
                predicate: NSPredicate(
                    format: "label CONTAINS %@",
                    "Purchases restored. Subscription access is updated."
                ),
                object: restored
            )], timeout: 45),
            .completed
        )
        let statusTitle = element("s7.3.lifecycle.status-title", in: app)
        XCTAssertEqual(
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(
                predicate: NSPredicate(
                    format: "label BEGINSWITH %@",
                    "Active until"
                ),
                object: statusTitle
            )], timeout: 20),
            .completed
        )
        for id in [
            "s7.3.lifecycle.restore",
            "s7.3.lifecycle.manage",
            "s7.3.lifecycle.close",
        ] {
            let control = element(id, in: app)
            scroll(control, in: app)
            XCTAssertGreaterThanOrEqual(control.frame.width, 44)
            XCTAssertGreaterThanOrEqual(control.frame.height, 44)
        }
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
    func firstPurchaseButton(in app: XCUIApplication) -> XCUIElement {
        let candidates = app.buttons.matching(NSPredicate(
            format: "label CONTAINS[c] 'Subscribe' OR label CONTAINS[c] 'Trial' OR label CONTAINS[c] '$59.99'"
        ))
        let value = candidates.firstMatch
        XCTAssertTrue(value.waitForExistence(timeout: 30))
        return value
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
    func dismissKeyboard(in app: XCUIApplication) {
        guard app.keyboards.firstMatch.exists else { return }
        let key = app.keyboards.buttons["Return"]
        key.exists ? key.tap() : app.swipeDown()
    }
}

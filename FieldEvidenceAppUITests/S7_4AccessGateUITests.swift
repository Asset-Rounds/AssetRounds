import CoreGraphics
import StoreKitTest
import XCTest

final class S7_4AccessGateUITests: XCTestCase {
    private var storeKitSession: SKTestSession?

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSharedGatePurchasesAddsAndResumesSecondSignAtXXXL() throws {
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
        tap("s2.welcome.add-first-sign", in: app)
        enter("Gate Site", into: "s2.new-sign.site-label", in: app)
        dismissKeyboard(in: app)
        enter("Evaluation Sign", into: "s2.new-sign.sign-label", in: app)
        dismissKeyboard(in: app)
        tap("s2.new-sign.save", in: app)
        assertSign("Evaluation Sign", in: app)

        let addSign = element("s7.4.sign-detail.add-sign", in: app)
        scroll(addSign, in: app)
        XCTAssertGreaterThanOrEqual(addSign.frame.width, 44)
        XCTAssertGreaterThanOrEqual(addSign.frame.height, 44)
        addSign.tap()
        assertPaywall(in: app)
        let store = element("s7.2.paywall.store", in: app)
        waitForValue("Ready", element: store, timeout: 30)
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
        assertSign("Evaluation Sign", in: app)

        tap("s7.4.sign-detail.add-sign", in: app)
        XCTAssertTrue(element("s2.new-sign.screen", in: app)
            .waitForExistence(timeout: 30))
        XCTAssertTrue(element("s7.4.new-sign.site-choice", in: app).exists)
        XCTAssertFalse(element("s2.new-sign.site-label", in: app).exists)
        enter("Paid Sign", into: "s2.new-sign.sign-label", in: app)
        dismissKeyboard(in: app)
        tap("s2.new-sign.save", in: app)
        assertSign("Paid Sign", in: app)

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

        app.terminate()
        app.launch()
        assertSignSelection(in: app)
        let paidRow = app.buttons["Paid Sign, Gate Site"]
        scroll(paidRow, in: app)
        paidRow.tap()
        XCTAssertTrue(element("s3.capture.screen", in: app)
            .waitForExistence(timeout: 30))

        tap("s3.capture.cannot-complete", in: app)
        XCTAssertTrue(element("s3.outcome.screen", in: app)
            .waitForExistence(timeout: 20))
        tap("s3.outcome.cnv.reason.required_view_obstructed", in: app)
        tap("s3.outcome.continue", in: app)
        XCTAssertTrue(element("s3.review.screen", in: app)
            .waitForExistence(timeout: 20))
        tap("s3.review.save-report", in: app)
        XCTAssertTrue(element("s3.receipt.screen", in: app)
            .waitForExistence(timeout: 30))
        tap("s3.receipt.done", in: app)
        assertSign("Paid Sign", in: app)

        tap("s7.4.sign-detail.all-signs", in: app)
        assertSignSelection(in: app)
        for label in ["Evaluation Sign, Gate Site", "Paid Sign, Gate Site"] {
            let row = app.buttons[label]
            XCTAssertTrue(row.exists)
            XCTAssertGreaterThanOrEqual(row.frame.width, 44)
            XCTAssertGreaterThanOrEqual(row.frame.height, 44)
        }

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "S7.4 paid multi-sign selection at Accessibility XXXL"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}

private extension S7_4AccessGateUITests {
    @MainActor
    func assertPaywall(in app: XCUIApplication) {
        XCTAssertTrue(element("s7.2.paywall.screen", in: app)
            .waitForExistence(timeout: 30))
        let close = element("s7.2.paywall.close", in: app)
        scroll(close, in: app)
        XCTAssertGreaterThanOrEqual(close.frame.width, 44)
        XCTAssertGreaterThanOrEqual(close.frame.height, 44)
    }

    @MainActor
    func assertSign(_ label: String, in app: XCUIApplication) {
        XCTAssertTrue(element("s2.sign-detail.screen", in: app)
            .waitForExistence(timeout: 30))
        XCTAssertEqual(element("s2.sign-detail.sign-label", in: app).label, label)
    }

    @MainActor
    func assertSignSelection(in app: XCUIApplication) {
        XCTAssertTrue(element("s7.4.signs.selection", in: app)
            .waitForExistence(timeout: 30))
        let add = element("s7.4.signs.add-sign", in: app)
        scroll(add, in: app)
        XCTAssertGreaterThanOrEqual(add.frame.width, 44)
        XCTAssertGreaterThanOrEqual(add.frame.height, 44)
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
    func dismissKeyboard(in app: XCUIApplication) {
        let keyboard = app.keyboards.firstMatch
        guard keyboard.exists else { return }
        let key = keyboard.buttons.matching(NSPredicate(
            format: "label ==[c] 'Done' OR label ==[c] 'Return'"
        )).firstMatch
        XCTAssertTrue(key.exists)
        key.tap()
        XCTAssertEqual(
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == false"),
                object: keyboard
            )], timeout: 5),
            .completed
        )
    }
}

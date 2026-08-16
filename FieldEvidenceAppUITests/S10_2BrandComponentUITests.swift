import CoreGraphics
import XCTest

final class S10_2BrandComponentUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSharedComponentsRemainBaselineEquivalentAndAccessibleBeforeMigration() {
        XCUIDevice.shared.appearance = .light
        let app = launch(
            appearance: "Light",
            appearanceFlag: "--s1-ui-test-light-mode",
            accessibilityEnvironment: false
        )

        let lightShell = element("s1.shell.screen", in: app)
        let lightWelcome = element("s2.welcome.screen", in: app)
        let lightTitle = element("s2.welcome.title", in: app)
        XCTAssertTrue(lightShell.waitForExistence(timeout: 60))
        XCTAssertEqual(lightShell.value as? String, "Light")
        XCTAssertTrue(lightWelcome.waitForExistence(timeout: 30))
        XCTAssertTrue(lightTitle.waitForExistence(timeout: 20))
        XCTAssertEqual(lightTitle.label, "Turn tonight's sign check into a clear report.")
        let ordinaryTitleHeight = lightTitle.frame.height

        let information = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Information: Field Evidence"))
            .firstMatch
        XCTAssertTrue(information.waitForExistence(timeout: 20))
        XCTAssertEqual(information.label, "Information: Field Evidence")

        let addFirstSign = element("s2.welcome.add-first-sign", in: app)
        let viewSample = element("s2.welcome.view-sample", in: app)
        scrollUntilHittable(addFirstSign, in: app)
        assertNativeButton(addFirstSign, label: "Add first sign")
        scrollUntilHittable(viewSample, in: app)
        assertNativeButton(viewSample, label: "View sample")
        viewSample.tap()

        XCTAssertTrue(element("s2.sample.screen", in: app).waitForExistence(timeout: 20))
        XCTAssertTrue(element("s1.sample.scroll", in: app).waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Illuminated sign pack"].waitForExistence(timeout: 20))
        let sampleBack = element("s2.sample.back", in: app)
        XCTAssertTrue(sampleBack.waitForExistence(timeout: 20))
        XCTAssertEqual(sampleBack.elementType, .button)
        XCTAssertEqual(sampleBack.label, "Back")
        sampleBack.tap()
        XCTAssertTrue(lightWelcome.waitForExistence(timeout: 20))
        app.terminate()

        XCUIDevice.shared.appearance = .dark
        let accessibleApp = launch(
            appearance: "Dark",
            appearanceFlag: "--s1-ui-test-dark-mode",
            accessibilityEnvironment: true
        )
        let darkShell = element("s1.shell.screen", in: accessibleApp)
        let darkWelcome = element("s2.welcome.screen", in: accessibleApp)
        let darkTitle = element("s2.welcome.title", in: accessibleApp)
        XCTAssertTrue(darkShell.waitForExistence(timeout: 60))
        XCTAssertEqual(darkShell.value as? String, "Dark")
        XCTAssertTrue(darkWelcome.waitForExistence(timeout: 30))
        XCTAssertTrue(darkTitle.waitForExistence(timeout: 20))
        XCTAssertEqual(darkTitle.label, "Turn tonight's sign check into a clear report.")
        XCTAssertGreaterThan(darkTitle.frame.height, ordinaryTitleHeight)

        let darkInformation = accessibleApp.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Information: Field Evidence"))
            .firstMatch
        XCTAssertTrue(darkInformation.waitForExistence(timeout: 20))
        XCTAssertEqual(darkInformation.label, "Information: Field Evidence")
        let darkAdd = element("s2.welcome.add-first-sign", in: accessibleApp)
        let darkSample = element("s2.welcome.view-sample", in: accessibleApp)
        scrollUntilHittable(darkAdd, in: accessibleApp)
        assertNativeButton(darkAdd, label: "Add first sign")
        scrollUntilHittable(darkSample, in: accessibleApp)
        assertNativeButton(darkSample, label: "View sample")

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "S10.2 isolated shared components — Dark Increased Contrast AX XXXL"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    private func launch(
        appearance: String,
        appearanceFlag: String,
        accessibilityEnvironment: Bool
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleInterfaceStyle", appearance,
            appearanceFlag,
        ]
        if accessibilityEnvironment {
            app.launchArguments += [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXXXL",
                "-UIAccessibilityDarkerSystemColorsEnabled", "YES",
                "-UIAccessibilityDifferentiateWithoutColor", "YES",
                "-UIAccessibilityReduceMotionEnabled", "YES",
                "-UIAccessibilityReduceTransparencyEnabled", "YES",
            ]
        }
        app.launch()
        return app
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch
    }

    @MainActor
    private func assertNativeButton(
        _ button: XCUIElement,
        label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(button.exists, file: file, line: line)
        XCTAssertEqual(button.elementType, .button, file: file, line: line)
        XCTAssertEqual(button.label, label, file: file, line: line)
        XCTAssertTrue(button.isEnabled, file: file, line: line)
        XCTAssertTrue(button.isHittable, file: file, line: line)
        XCTAssertGreaterThanOrEqual(button.frame.width + 0.001, 44, file: file, line: line)
        XCTAssertGreaterThanOrEqual(button.frame.height + 0.001, 44, file: file, line: line)
    }

    @MainActor
    private func scrollUntilHittable(
        _ element: XCUIElement,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for _ in 0..<12 {
            if element.exists && element.isHittable {
                return
            }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists, file: file, line: line)
        XCTAssertTrue(element.isHittable, file: file, line: line)
    }
}

import XCTest

final class S1ShellUITests: XCTestCase {
    private let contentSizeArguments = [
        "-UIPreferredContentSizeCategoryName",
        "UICTContentSizeCategoryAccessibilityXXXL",
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testExactShellAtAccessibilityXXXLAndInvalidPackFailClosed() {
        XCUIDevice.shared.appearance = .light
        let lightApp = launch(
            arguments: contentSizeArguments
                + ["-AppleInterfaceStyle", "Light", "--s1-ui-test-light-mode"]
        )

        let shell = element(in: lightApp, identifier: "s1.shell.screen")
        let tabBar = lightApp.tabBars.firstMatch
        // V23 four-tab shell: Today, Work, Assets (formerly Signs) and Reports. Launch
        // selects Today; the S1 shell container and pack sample live on Assets.
        let todayTab = tabBar.buttons["Today"]
        let workTab = tabBar.buttons["Work"]
        let assetsTab = tabBar.buttons["Assets"]
        let reportsTab = tabBar.buttons["Reports"]
        let settingsButton = lightApp.buttons
            .matching(identifier: "s1.settings.button")
            .firstMatch
        let sampleScroll = lightApp.scrollViews
            .matching(identifier: "s1.sample.scroll")
            .firstMatch

        XCTAssertTrue(lightApp.windows.firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10))
        for tab in [todayTab, workTab, assetsTab, reportsTab] {
            XCTAssertTrue(tab.waitForExistence(timeout: 10))
        }
        XCTAssertEqual(tabBar.buttons.count, 4)
        XCTAssertEqual(todayTab.label, "Today")
        XCTAssertEqual(workTab.label, "Work")
        XCTAssertEqual(assetsTab.label, "Assets")
        XCTAssertEqual(reportsTab.label, "Reports")
        XCTAssertFalse(tabBar.buttons["Signs"].exists)
        assetsTab.tap()
        XCTAssertTrue(shell.waitForExistence(timeout: 10))
        XCTAssertEqual(shell.value as? String, "Light")
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 10))
        XCTAssertEqual(settingsButton.label, "Settings")
        XCTAssertFalse(tabBar.buttons["Settings"].exists)
        XCTAssertFalse(
            tabBar.buttons
                .matching(identifier: "s1.settings.button")
                .firstMatch.exists
        )

        XCTAssertTrue(sampleScroll.waitForExistence(timeout: 10))
        let exactRenderedGroups = [
            ["Pack ID", "field.evidence.illuminated_sign.v1"],
            ["Schema version", "1"],
            ["Content version", "1"],
            ["Asset", "sign / signs"],
            ["Check", "check / checks"],
            ["Issue", "visible issue / visible issues"],
            [
                "wide_context",
                "Wide view",
                "Take one wide photo showing the full sign and its surroundings.",
            ],
            [
                "close_detail",
                "Close view",
                "Take one close photo showing the sign face clearly.",
            ],
            [
                "work_context",
                "Work photo",
                "Add one optional photo showing the work performed.",
            ],
            [
                "after_dark",
                "It is dark enough to observe the sign's visible illumination.",
                "preflight.ack.en-US.v1",
            ],
            [
                "safe_authorized_position",
                "I am in a safe, authorized position to take these photos.",
                "preflight.ack.en-US.v1",
            ],
            ["dark_section", "Section appears dark"],
            ["dim_or_uneven", "Illumination appears dim or uneven"],
            ["flicker_or_intermittent", "Flicker or intermittent light"],
            ["color_mismatch", "Visible color mismatch"],
            ["physical_damage", "Visible physical damage"],
            ["other_visible_condition", "Other visible condition"],
            ["Registry version", "cnv.reason.en-US.v1"],
            ["conditions_changed", "Conditions changed"],
            ["access_lost", "I lost safe access"],
            ["unsafe_to_continue", "It became unsafe to continue"],
            ["required_view_obstructed", "Required view is blocked"],
            ["capture_unavailable", "Camera or photo capture is unavailable"],
            ["other", "Another reason"],
            ["check", "Check"],
            ["recheck", "Recheck"],
            ["no_visible_issue", "No visible issue"],
            ["visible_issue", "Visible issue"],
            ["could_not_verify", "Could not verify"],
            ["resolved", "Resolved"],
            ["issue_still_visible", "Issue still visible"],
            [
                "original_resolved_different_issue",
                "Original resolved, different visible issue",
            ],
            [
                "This report records visible conditions from the listed photos and time. It is not an electrical, code, safety, or professional certification.",
            ],
        ]
        for renderedGroup in exactRenderedGroups {
            assertRendered(
                renderedGroup,
                in: lightApp
            )
        }

        let disclaimer = lightApp.staticTexts
            .matching(identifier: "s1.sample.disclaimer")
            .firstMatch
        scroll(
            sampleScroll,
            untilVisible: disclaimer,
            description: "terminal report disclaimer"
        )
        XCTAssertTrue(disclaimer.exists)
        XCTAssertEqual(
            disclaimer.label,
            "This report records visible conditions from the listed photos and time. It is not an electrical, code, safety, or professional certification."
        )
        XCTAssertTrue(disclaimer.isHittable)

        reportsTab.tap()
        let reportsPlaceholder = element(
            in: lightApp,
            identifier: "s1.reports.placeholder"
        )
        XCTAssertTrue(reportsPlaceholder.waitForExistence(timeout: 10))
        XCTAssertTrue(lightApp.staticTexts["Saved reports will appear here."].exists)
        XCTAssertEqual(tabBar.buttons.count, 4)

        let reportsSettingsButton = lightApp.buttons
            .matching(identifier: "s1.settings.button")
            .firstMatch
        XCTAssertTrue(reportsSettingsButton.waitForExistence(timeout: 10))
        XCTAssertTrue(reportsSettingsButton.isHittable)
        XCTAssertGreaterThanOrEqual(reportsSettingsButton.frame.width, 44)
        XCTAssertGreaterThanOrEqual(reportsSettingsButton.frame.height, 44)
        reportsSettingsButton.tap()
        let settingsScreen = element(in: lightApp, identifier: "s1.settings.screen")
        XCTAssertTrue(settingsScreen.waitForExistence(timeout: 10))
        // S6.2 (e38f495) replaced the S1 sample notice with real Settings entries;
        // its accepted backup entry proves Settings is live from the shell.
        let backupEntry = element(in: lightApp, identifier: "s6.2.backup.settings-entry")
        XCTAssertTrue(backupEntry.waitForExistence(timeout: 10))
        XCTAssertEqual(backupEntry.label, "Back up current data")
        lightApp.terminate()

        XCUIDevice.shared.appearance = .dark
        let invalidApp = launch(
            arguments: contentSizeArguments
                + [
                    "-AppleInterfaceStyle",
                    "Dark",
                    "--s1-ui-test-dark-mode",
                    "--s1-invalid-pack",
                ]
        )
        let unavailable = element(in: invalidApp, identifier: "s1.pack.unavailable")
        XCTAssertTrue(unavailable.waitForExistence(timeout: 10))
        XCTAssertTrue(invalidApp.staticTexts["Content unavailable"].exists)
        XCTAssertTrue(
            invalidApp.staticTexts["No partial or guessed content is shown."].exists
        )
        XCTAssertFalse(invalidApp.tabBars.firstMatch.exists)
        XCTAssertFalse(element(in: invalidApp, identifier: "s1.sample.scroll").exists)
        invalidApp.terminate()

        let darkApp = launch(
            arguments: contentSizeArguments
                + ["-AppleInterfaceStyle", "Dark", "--s1-ui-test-dark-mode"]
        )
        let darkShell = element(in: darkApp, identifier: "s1.shell.screen")
        let darkTabBar = darkApp.tabBars.firstMatch
        let darkAssetsTab = darkTabBar.buttons["Assets"]
        let darkReportsTab = darkTabBar.buttons["Reports"]
        XCTAssertTrue(darkAssetsTab.waitForExistence(timeout: 10))
        XCTAssertTrue(darkAssetsTab.isHittable)
        XCTAssertTrue(darkReportsTab.waitForExistence(timeout: 10))
        XCTAssertTrue(darkReportsTab.isHittable)
        XCTAssertEqual(darkTabBar.buttons.count, 4)
        darkAssetsTab.tap()
        XCTAssertTrue(darkShell.waitForExistence(timeout: 10))
        XCTAssertEqual(darkShell.value as? String, "Dark")
        XCTAssertTrue(
            darkApp.staticTexts["Illuminated sign pack"]
                .waitForExistence(timeout: 10)
        )
        let darkSettingsButton = darkApp.buttons
            .matching(identifier: "s1.settings.button")
            .firstMatch
        XCTAssertTrue(darkSettingsButton.waitForExistence(timeout: 10))
        XCTAssertTrue(darkSettingsButton.isHittable)
        XCTAssertGreaterThanOrEqual(darkSettingsButton.frame.width, 44)
        XCTAssertGreaterThanOrEqual(darkSettingsButton.frame.height, 44)

        darkReportsTab.tap()
        XCTAssertTrue(
            element(in: darkApp, identifier: "s1.reports.placeholder")
                .waitForExistence(timeout: 10)
        )
        darkAssetsTab.tap()
        XCTAssertTrue(
            darkApp.staticTexts["Illuminated sign pack"]
                .waitForExistence(timeout: 10)
        )

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "S1 Worklight shell — Dark accessibility XXXL"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    private func launch(arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += arguments
        app.launch()
        return app
    }

    @MainActor
    private func element(in app: XCUIApplication, identifier: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch
    }

    @MainActor
    private func assertRendered(
        _ exactStrings: [String],
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let predicates = exactStrings.map {
            NSPredicate(format: "label CONTAINS %@", $0)
        }
        let renderedElement = app.descendants(matching: .any)
            .matching(NSCompoundPredicate(andPredicateWithSubpredicates: predicates))
            .firstMatch
        let description = exactStrings.joined(separator: " | ")

        XCTAssertTrue(
            renderedElement.waitForExistence(timeout: 3),
            "Missing rendered content: \(description)",
            file: file,
            line: line
        )
        for exactString in exactStrings {
            XCTAssertTrue(
                renderedElement.label.contains(exactString),
                "Rendered element must contain exact content: \(exactString)",
                file: file,
                line: line
            )
        }
    }

    @MainActor
    private func scroll(
        _ scrollView: XCUIElement,
        untilVisible element: XCUIElement,
        description: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for _ in 0..<50 {
            if element.isHittable {
                return
            }
            scrollView.swipeUp()
        }
        XCTAssertTrue(
            element.isHittable,
            "Could not scroll to rendered content: \(description)",
            file: file,
            line: line
        )
    }
}

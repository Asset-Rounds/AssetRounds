import CoreGraphics
import CryptoKit
import Foundation
import XCTest

/// Phase 1 critical-state UI evidence for human review.
///
/// Every method seeds its own isolated, empty S10-format store through the
/// DEBUG `--v23-ui-test-legacy-migration` hook with a fresh
/// `V23_MIGRATION_TEST_ID`, so no method depends on another. Each captured
/// state adds a keepAlways PNG attachment named `P1 state <id>` and an
/// accessibility-audit record named `P1 ax <id>`. Audit issues never fail a
/// test by default; they are recorded for human review. Setting
/// `V23_P1_AX_AUDIT_STRICT=1` in the test-runner environment reports them as
/// failures instead. State ids, order and review checks are catalogued in
/// `docs/design/v23/integration/phase1-critical-states.json`.
final class V23Phase1CriticalStatesUITests: XCTestCase {
    static let test1StateIDs = [
        "p1.migration.pending.light",
        "p1.today.empty.light",
        "p1.work.empty.light",
        "p1.assets.welcome.light",
        "p1.reports.empty.light",
        "p1.today.empty.dark-axxxl",
        "p1.assets.welcome.dark-axxxl",
    ]
    static let test2StateIDs = [
        "p1.check.receipt.light",
        "p1.assets.sign-detail.light",
        "p1.reports.report-detail.light",
        "p1.work.completed-list.light",
        "p1.work.completed-detail.light",
        "p1.signoff.editor.light",
        "p1.signoff.editor-fields.light",
        "p1.reports.signoff-history.light",
        "p1.reports.signoff-history.dark-axxxl",
        "p1.work.completed-list.dark-axxxl",
        "p1.work.completed-detail.dark-axxxl",
        "p1.signoff.editor.dark-axxxl",
    ]
    static let test3StateIDs = [
        "p1.settings.app-lock-off.light",
        "p1.settings.app-lock-on.light",
        "p1.app-lock.lock-now-cover.light",
        "p1.app-lock.background-cover.light",
        "p1.app-lock.launch-cover.dark-axxxl",
        "p1.settings.app-lock-on.dark-axxxl",
        "p1.settings.app-lock-on-lock-now.dark-axxxl",
        "p1.settings.app-lock-off.dark-axxxl",
    ]

    private enum Variant {
        case light
        case darkAccessibilityXXXL
    }

    private enum Timeout {
        static let firstLaunch: TimeInterval = 120
        static let relaunch: TimeInterval = 90
        static let save: TimeInterval = 45
        static let navigation: TimeInterval = 30
        static let short: TimeInterval = 10
    }

    private enum ID {
        static let migrationPending = "v23.migration.awaiting-validation.screen"
        static let migrationRetry = "v23.migration.awaiting-validation.retry"
        static let todayTab = "v23.tab.today"
        static let workTab = "v23.tab.work"
        static let assetsTab = "s1.tab.signs"
        static let reportsTab = "s1.tab.reports"
        static let todayEmpty = "v23.shell.today.phase-one-empty"
        static let planEntry = "v23.my-day.open-planning"
        static let settingsButton = "s1.settings.button"
        static let welcome = "s2.welcome.screen"
        static let welcomeTitle = "s2.welcome.title"
        static let addFirstSign = "s2.welcome.add-first-sign"
        static let reportsScreen = "s4.4.reports.screen"
        static let reportsPlaceholder = "s1.reports.placeholder"
        static let reportsVisit = "s4.4.reports.visit"
        static let reportsViewReport = "s4.4.reports.view-report"
        static let reportDetail = "s4.3.report-detail.screen"
        static let reportPreview = "s4.3.report-detail.preview"
        static let reportClose = "s4.3.report-detail.close"
        static let signDetail = "s2.sign-detail.screen"
        static let signReportHistory = "s4.4.sign-detail.report-history"
        static let receipt = "s3.receipt.screen"
        static let receiptSaved = "s3.receipt.saved"
        static let receiptViewReport = "s3.receipt.view-report"
        static let receiptDone = "s3.receipt.done"
        static let completedRowPrefix = "v23.work.completed."
        static let completedHeader = "v23.p04.c43.signoff-enrollment.work-root"
        static let signoffMore = "v23.p04.c43.signoff-enrollment.more"
        static let signoffRecord = "v23.p04.c43.signoff-enrollment.record-approval-response"
        static let signoffHeader = "v23.p04.c43.signoff-enrollment.header"
        static let signoffTypedName = "v23.p04.c43.signoff-enrollment.typed-name"
        static let signoffClaimedRole = "v23.p04.c43.signoff-enrollment.claimed-role"
        static let signoffClaimedRelationship = "v23.p04.c43.signoff-enrollment.claimed-relationship"
        static let signoffConfirm = "v23.p04.c43.signoff-enrollment.confirm"
        static let signoffCancel = "v23.p04.c43.signoff-enrollment.cancel"
        static let signoffHistoryEntry = "v23.p04.c43.signoff-enrollment.history.entry"
        static let signDetailStartCheck = "s2.sign-detail.start-check"
        static let appLockSettings = "v23.appLock.settings"
        static let appLockToggle = "v23.appLock.toggle"
        static let appLockLockNow = "v23.appLock.lockNow"
        static let appLockUnlock = "v23.appLock.unlock"
        static let remindersSettings = "v23.reminders.settings"
        static let remindersEnabled = "v23.reminders.enabled"
    }

    private enum Copy {
        static let nothingPlanned = "Nothing planned"
        static let todayMessage = "Signs you inspect appear in Assets and Reports."
        static let completedEmpty = "Completed reports will appear here."
        static let welcomeTitle = "Turn tonight's sign check into a clear report."
        static let reportsEmpty = "Saved reports will appear here."
        static let reportSaved = "Report saved on this device."
        static let recordAction = "Record approval response"
        static let notVerified = "Not verified by AssetRounds"
        static let appLockSetting = "Require Face ID, Touch ID, or your iPhone passcode whenever AssetRounds launches or returns from the background."
        static let appLockLocked = "AssetRounds is locked. Authenticate with Face ID, Touch ID, or your iPhone passcode to view local work records."
        static let typedNamePrompt = "Type your name"
        static let claimedRolePrompt = "Type your claimed role"
        static let drawnMarkOptional = "A drawn mark is not required"
    }

    private static let localAuthenticationSuccessArgument = "--v23-ui-test-local-auth-success"
    private static let importedFixturesArgument = "--s3-2-ui-test-imported-fixtures"
    private static let auditTypes: XCUIAccessibilityAuditType = [.contrast, .dynamicType, .textClipped]
    private static let auditTypeNames = ["contrast", "dynamicType", "textClipped"]
    private static let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    private var capturedStateIDs: [String] = []
    /// Set from the App Lock enable tap until it is turned off again, so the
    /// teardown knows the app's own preferences may still hold it on.
    private var appLockMayBeOn = false

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - 1. Migrated S10 store opens the four-tab shell

    @MainActor
    func test1MigratedS10StoreOpensFourTabShell() throws {
        let storeID = UUID().uuidString.lowercased()
        registerDeviceStateRestore(storeID: storeID)
        let app = XCUIApplication()
        configure(app, variant: .light, storeID: storeID)
        app.launch()

        let pending = element(ID.migrationPending, in: app)
        XCTAssertTrue(
            pending.waitForExistence(timeout: Timeout.firstLaunch),
            "The seeded S10 store did not stop at migration validation"
        )
        XCTAssertTrue(element(ID.migrationRetry, in: app).exists)
        XCTAssertFalse(element(ID.welcome, in: app).exists)
        XCTAssertFalse(element(ID.todayTab, in: app).exists)
        capture("p1.migration.pending.light", in: app)

        app.terminate()
        XCTAssertEqual(app.state, .notRunning)
        app.launch()
        waitForShell(in: app, timeout: Timeout.relaunch)
        XCTAssertFalse(pending.exists)
        assertFourTabShell(in: app)
        // Opens on Today without a tab tap.
        assertTodayPhaseOneEmpty(in: app)
        capture("p1.today.empty.light", in: app)

        openTab(ID.workTab, in: app)
        assertWorkPhaseOneEmpty(in: app)
        capture("p1.work.empty.light", in: app)

        openTab(ID.assetsTab, in: app)
        assertAssetsWelcome(in: app)
        capture("p1.assets.welcome.light", in: app)

        openTab(ID.reportsTab, in: app)
        assertReportsEmpty(in: app)
        capture("p1.reports.empty.light", in: app)

        relaunch(app, variant: .darkAccessibilityXXXL, storeID: storeID)
        waitForShell(in: app, timeout: Timeout.relaunch)
        assertFourTabShell(in: app)
        openTab(ID.todayTab, in: app)
        assertTodayPhaseOneEmpty(in: app)
        capture("p1.today.empty.dark-axxxl", in: app)

        openTab(ID.assetsTab, in: app)
        assertAssetsWelcome(in: app)
        capture("p1.assets.welcome.dark-axxxl", in: app)

        XCTAssertEqual(capturedStateIDs, Self.test1StateIDs)
    }

    // MARK: - 2. Sign, report and approval response inside the shell

    @MainActor
    func test2SignReportAndApprovalResponseInShell() throws {
        let storeID = UUID().uuidString.lowercased()
        registerDeviceStateRestore(storeID: storeID)
        let app = XCUIApplication()
        try installImportedPhotoFixtures(in: app)
        let extraArguments = [Self.importedFixturesArgument]
        configure(app, variant: .light, storeID: storeID, extraArguments: extraArguments)
        launchMigratedStore(app)

        openTab(ID.assetsTab, in: app)
        assertAssetsWelcome(in: app)
        createSign(in: app)
        completeNoVisibleIssueCheck(in: app)

        XCTAssertTrue(element(ID.receipt, in: app).waitForExistence(timeout: Timeout.save))
        let saved = element(ID.receiptSaved, in: app)
        XCTAssertTrue(saved.waitForExistence(timeout: Timeout.short))
        XCTAssertEqual(saved.label, Copy.reportSaved)
        let receiptViewReport = element(ID.receiptViewReport, in: app)
        XCTAssertTrue(
            waitUntil(timeout: Timeout.save) { receiptViewReport.exists && receiptViewReport.isEnabled },
            "The saved report PDF did not become available on the receipt"
        )
        capture("p1.check.receipt.light", in: app)

        let done = element(ID.receiptDone, in: app)
        scrollUntilHittable(done, in: app)
        done.tap()
        XCTAssertTrue(element(ID.signDetail, in: app).waitForExistence(timeout: Timeout.navigation))
        XCTAssertTrue(element(ID.signReportHistory, in: app).waitForExistence(timeout: Timeout.short))
        XCTAssertTrue(element(ID.signDetailStartCheck, in: app).exists)
        XCTAssertTrue(labelContaining("Monument Sign", in: app).exists)
        capture("p1.assets.sign-detail.light", in: app)

        openTab(ID.reportsTab, in: app)
        XCTAssertTrue(element(ID.reportsScreen, in: app).waitForExistence(timeout: Timeout.navigation))
        waitForCount(1, identifier: ID.reportsVisit, in: app)
        let viewReport = element(ID.reportsViewReport, in: app)
        scrollUntilHittable(viewReport, in: app)
        viewReport.tap()
        XCTAssertTrue(element(ID.reportDetail, in: app).waitForExistence(timeout: Timeout.navigation))
        XCTAssertTrue(element(ID.reportPreview, in: app).waitForExistence(timeout: Timeout.save))
        capture("p1.reports.report-detail.light", in: app)
        let close = element(ID.reportClose, in: app)
        scrollUntilHittable(close, in: app)
        close.tap()
        XCTAssertTrue(element(ID.reportsScreen, in: app).waitForExistence(timeout: Timeout.navigation))

        openTab(ID.workTab, in: app)
        let row = completedWorkRow(in: app)
        XCTAssertTrue(row.waitForExistence(timeout: Timeout.navigation), "Completed work did not list the saved report")
        XCTAssertTrue(row.label.contains("Monument Sign"))
        XCTAssertTrue(row.label.contains("No responses recorded"))
        capture("p1.work.completed-list.light", in: app)

        openCompletedWorkDetail(row, in: app)
        XCTAssertTrue(labelContaining("No responses recorded", in: app).exists)
        scrollUntilHittable(element(ID.signoffMore, in: app), in: app)
        capture("p1.work.completed-detail.light", in: app)

        openRecordEditor(in: app)
        assertResponseFieldsEmpty(in: app)
        capture("p1.signoff.editor.light", in: app)

        // Part capture: the response fields sit below the subject card.
        scrollEditorUntilHittable(element(ID.signoffClaimedRelationship, in: app), towardTop: false, in: app)
        XCTAssertTrue(element(ID.signoffClaimedRole, in: app).isHittable)
        XCTAssertTrue(element(ID.signoffTypedName, in: app).isHittable)
        XCTAssertTrue(labelContaining(Copy.drawnMarkOptional, in: app).exists)
        capture("p1.signoff.editor-fields.light", in: app)

        recordApprovalResponse(typedName: "Pat Rivera", claimedRole: "Site supervisor", in: app)
        let entry = element(ID.signoffHistoryEntry, in: app)
        XCTAssertTrue(
            entry.waitForExistence(timeout: Timeout.navigation),
            "Recording did not open the focused Reports response history"
        )
        XCTAssertTrue(app.navigationBars["Responses"].waitForExistence(timeout: Timeout.short))
        XCTAssertTrue(labelContaining("Pat Rivera", in: app).exists)
        XCTAssertTrue(labelContaining("Site supervisor", in: app).exists)
        XCTAssertTrue(labelContaining(Copy.notVerified, in: app).exists)
        XCTAssertFalse(
            app.buttons.matching(NSPredicate(format: "label == %@", Copy.recordAction)).firstMatch.exists
        )
        capture("p1.reports.signoff-history.light", in: app)

        relaunch(app, variant: .darkAccessibilityXXXL, storeID: storeID, extraArguments: extraArguments)
        XCTAssertTrue(
            entry.waitForExistence(timeout: Timeout.relaunch),
            "Relaunch did not restore the focused Reports response history"
        )
        let restoredName = labelContaining("Pat Rivera", in: app)
        XCTAssertTrue(restoredName.waitForExistence(timeout: Timeout.short))
        XCTAssertTrue(labelContaining(Copy.notVerified, in: app).exists)
        scrollUntilHittable(restoredName, in: app)
        capture("p1.reports.signoff-history.dark-axxxl", in: app)

        openTab(ID.workTab, in: app)
        let restoredRow = completedWorkRow(in: app)
        XCTAssertTrue(restoredRow.waitForExistence(timeout: Timeout.navigation))
        XCTAssertTrue(restoredRow.label.contains("1 response recorded"))
        scrollUntilHittable(restoredRow, in: app)
        capture("p1.work.completed-list.dark-axxxl", in: app)

        openCompletedWorkDetail(restoredRow, in: app)
        XCTAssertTrue(labelContaining("1 response recorded", in: app).exists)
        // Responses is the last fact, directly above More.
        scrollUntilHittable(element(ID.signoffMore, in: app), in: app)
        capture("p1.work.completed-detail.dark-axxxl", in: app)

        openRecordEditor(in: app)
        assertResponseFieldsEmpty(in: app)
        capture("p1.signoff.editor.dark-axxxl", in: app)

        XCTAssertEqual(capturedStateIDs, Self.test2StateIDs)
    }

    // MARK: - 3. Settings, App Lock and its covers

    @MainActor
    func test3SettingsAppLockAndCover() throws {
        let storeID = UUID().uuidString.lowercased()
        registerDeviceStateRestore(storeID: storeID)
        let app = XCUIApplication()
        let extraArguments = [Self.localAuthenticationSuccessArgument]
        configure(app, variant: .light, storeID: storeID, extraArguments: extraArguments)
        launchMigratedStore(app)

        openSettings(in: app)
        let toggle = appLockToggle(in: app)
        XCTAssertEqual(
            toggle.value as? String, "0",
            "App Lock must start off. It lives in the app's own UserDefaults, which the isolated store does not reset."
        )
        assertAppLockSettings(enabled: false, in: app)
        capture("p1.settings.app-lock-off.light", in: app)

        appLockMayBeOn = true
        tapAppLockToggle(in: app)
        waitForLockedCover(in: app, timeout: Timeout.navigation)
        settle(1.0)
        unlock(in: app)
        openSettings(in: app)
        XCTAssertEqual(appLockToggle(in: app).value as? String, "1")
        assertAppLockSettings(enabled: true, in: app)
        capture("p1.settings.app-lock-on.light", in: app)

        let lockNow = element(ID.appLockLockNow, in: app)
        scrollUntilHittable(lockNow, in: app)
        lockNow.tap()
        waitForLockedCover(in: app, timeout: Timeout.navigation)
        XCTAssertFalse(element(ID.todayTab, in: app).exists)
        capture("p1.app-lock.lock-now-cover.light", in: app)
        unlock(in: app)

        XCUIDevice.shared.press(.home)
        XCTAssertTrue(
            waitUntil(timeout: Timeout.navigation) { app.state != .runningForeground },
            "The app did not leave the foreground"
        )
        app.activate()
        XCTAssertTrue(waitUntil(timeout: Timeout.navigation) { app.state == .runningForeground })
        waitForLockedCover(in: app, timeout: Timeout.navigation)
        XCTAssertFalse(element(ID.todayTab, in: app).exists)
        capture("p1.app-lock.background-cover.light", in: app)
        unlock(in: app)

        relaunch(app, variant: .darkAccessibilityXXXL, storeID: storeID, extraArguments: extraArguments)
        waitForLockedCover(in: app, timeout: Timeout.relaunch)
        settle(2.0)
        XCTAssertTrue(unlockButton(in: app).exists, "The cold-launch App Lock cover did not persist")
        XCTAssertFalse(element(ID.todayTab, in: app).exists)
        capture("p1.app-lock.launch-cover.dark-axxxl", in: app)
        unlock(in: app)

        openSettings(in: app)
        XCTAssertEqual(appLockToggle(in: app).value as? String, "1")
        assertAppLockSettings(enabled: true, in: app)
        capture("p1.settings.app-lock-on.dark-axxxl", in: app)

        // Part capture: at this size the disclosure and Lock Now are below.
        let lockNowLarge = element(ID.appLockLockNow, in: app)
        scrollUntilHittable(lockNowLarge, in: app)
        XCTAssertTrue(lockNowLarge.isEnabled)
        capture("p1.settings.app-lock-on-lock-now.dark-axxxl", in: app)

        // Leave App Lock off in the app's own preferences (UserDefaults).
        turnAppLockOff(in: app)
        appLockMayBeOn = false
        assertAppLockSettings(enabled: false, in: app)
        capture("p1.settings.app-lock-off.dark-axxxl", in: app)

        XCTAssertEqual(capturedStateIDs, Self.test3StateIDs)
    }

    // MARK: - Evidence capture

    /// Attaches the current screen as `P1 state <id>` and the accessibility
    /// audit (contrast, Dynamic Type, clipped text) as `P1 ax <id>`. Issues
    /// are recorded for human review and do not fail the test by default.
    @MainActor
    private func capture(
        _ stateID: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(
            capturedStateIDs.contains(stateID),
            "Duplicate Phase 1 state \(stateID)",
            file: file,
            line: line
        )
        capturedStateIDs.append(stateID)
        dismissHostedSystemNotificationIfPresent()
        settle(1.0)

        let pngData = XCUIScreen.main.screenshot().pngRepresentation
        XCTAssertTrue(pngData.starts(with: Self.pngSignature), file: file, line: line)
        let pngSHA256 = SHA256.hash(data: pngData)
            .map { String(format: "%02x", $0) }
            .joined()
        let state = XCTAttachment(data: pngData, uniformTypeIdentifier: "public.png")
        state.name = "P1 state \(stateID)"
        state.lifetime = .keepAlways
        add(state)

        // Same issue fields as the S10_3 contrast diagnostics. Returning true
        // records an issue without failing the test; strict mode fails it.
        let strict = ProcessInfo.processInfo.environment["V23_P1_AX_AUDIT_STRICT"] == "1"
        let issueObject: (XCUIAccessibilityAuditIssue, Int) -> [String: Any] = { issue, ordinal in
            var object: [String: Any] = [
                "issueOrdinal": ordinal,
                "auditType": self.auditTypeName(issue.auditType),
                "auditTypeRawValue": String(issue.auditType.rawValue),
                "compactDescription": issue.compactDescription,
                "detailedDescription": issue.detailedDescription,
                "elementIdentifier": NSNull(),
                "elementLabel": NSNull(),
                "elementType": NSNull(),
                "elementFrame": NSNull(),
            ]
            if let auditedElement = issue.element, auditedElement.exists {
                object["elementIdentifier"] = auditedElement.identifier
                object["elementLabel"] = auditedElement.label
                object["elementType"] = String(describing: auditedElement.elementType)
                object["elementFrame"] = self.frameObject(auditedElement.frame)
            }
            return object
        }
        var issues: [[String: Any]] = []
        var auditError: String?
        do {
            try app.performAccessibilityAudit(for: Self.auditTypes) { issue in
                let ordinal = issues.count + 1
                issues.append(issueObject(issue, ordinal))
                return !strict
            }
        } catch {
            auditError = String(describing: error)
        }

        let record: [String: Any] = [
            "schemaVersion": 1,
            "stateID": stateID,
            "testName": name,
            "ordinalInMethod": capturedStateIDs.count,
            "pngSHA256": pngSHA256,
            "pngByteCount": pngData.count,
            "auditTypes": Self.auditTypeNames,
            "issuesFailTest": strict,
            "humanReviewRequired": true,
            "issueCount": issues.count,
            "issues": issues,
            "auditError": auditError.map { $0 as Any } ?? NSNull(),
            "applicationFrame": frameObject(app.frame),
        ]
        do {
            let data = try JSONSerialization.data(
                withJSONObject: record,
                options: [.prettyPrinted, .sortedKeys]
            )
            let audit = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            audit.name = "P1 ax \(stateID)"
            audit.lifetime = .keepAlways
            add(audit)
        } catch {
            XCTFail("P1 ax \(stateID) could not be encoded: \(error)", file: file, line: line)
        }
        print(
            "V23_P1_STATE id=\(stateID) ordinal=\(capturedStateIDs.count) "
                + "png_sha256=\(pngSHA256) ax_issues=\(issues.count)"
        )
        if let auditError {
            // An audit that could not run leaves the state unreviewable.
            XCTFail("P1 ax \(stateID) audit did not run: \(auditError)", file: file, line: line)
        }
    }

    private func auditTypeName(_ type: XCUIAccessibilityAuditType) -> String {
        if type == .contrast { return "contrast" }
        if type == .dynamicType { return "dynamicType" }
        if type == .textClipped { return "textClipped" }
        return "other"
    }

    private func frameObject(_ frame: CGRect) -> [String: Double] {
        [
            "x": Double(frame.origin.x),
            "y": Double(frame.origin.y),
            "width": Double(frame.size.width),
            "height": Double(frame.size.height),
        ]
    }

    /// Hosted Simulator images can show this banner over the navigation bar.
    @MainActor
    private func dismissHostedSystemNotificationIfPresent() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let notification = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Ready for Apple Intelligence"))
            .firstMatch
        guard notification.exists else { return }
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
            .press(
                forDuration: 0.05,
                thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.01))
            )
        XCTAssertTrue(notification.waitForNonExistence(timeout: 5))
    }

    // MARK: - Launch

    @MainActor
    private func configure(
        _ app: XCUIApplication,
        variant: Variant,
        storeID: String,
        extraArguments: [String] = []
    ) {
        var arguments = ["--v23-ui-test-legacy-migration"]
        switch variant {
        case .light:
            XCUIDevice.shared.appearance = .light
            arguments += ["-AppleInterfaceStyle", "Light", "--s1-ui-test-light-mode"]
        case .darkAccessibilityXXXL:
            XCUIDevice.shared.appearance = .dark
            arguments += [
                "-AppleInterfaceStyle", "Dark", "--s1-ui-test-dark-mode",
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXXXL",
            ]
        }
        app.launchArguments = arguments + extraArguments
        app.launchEnvironment["V23_MIGRATION_TEST_ID"] = storeID
    }

    /// Seeds the isolated S10 store, then performs the real cold launch that
    /// finishes its validation, ending on the four-tab shell.
    @MainActor
    private func launchMigratedStore(_ app: XCUIApplication) {
        app.launch()
        XCTAssertTrue(
            element(ID.migrationPending, in: app).waitForExistence(timeout: Timeout.firstLaunch),
            "The seeded S10 store did not stop at migration validation"
        )
        app.terminate()
        XCTAssertEqual(app.state, .notRunning)
        app.launch()
        waitForShell(in: app, timeout: Timeout.relaunch)
    }

    @MainActor
    private func relaunch(
        _ app: XCUIApplication,
        variant: Variant,
        storeID: String,
        extraArguments: [String] = []
    ) {
        app.terminate()
        XCTAssertEqual(app.state, .notRunning)
        configure(app, variant: variant, storeID: storeID, extraArguments: extraArguments)
        app.launch()
    }

    @MainActor
    private func installImportedPhotoFixtures(in app: XCUIApplication) throws {
        let bundle = Bundle(for: V23Phase1CriticalStatesUITests.self)
        let wideURL = try XCTUnwrap(
            bundle.url(forResource: "S3_2WideInput", withExtension: "png", subdirectory: "Fixtures")
                ?? bundle.url(forResource: "S3_2WideInput", withExtension: "png")
        )
        let closeURL = try XCTUnwrap(
            bundle.url(forResource: "S3_2CloseInput", withExtension: "png", subdirectory: "Fixtures")
                ?? bundle.url(forResource: "S3_2CloseInput", withExtension: "png")
        )
        app.launchEnvironment["S3_2_WIDE_FIXTURE_BASE64"] = try Data(contentsOf: wideURL)
            .base64EncodedString()
        app.launchEnvironment["S3_2_CLOSE_FIXTURE_BASE64"] = try Data(contentsOf: closeURL)
            .base64EncodedString()
    }

    // MARK: - Shell

    @MainActor
    private func waitForShell(in app: XCUIApplication, timeout: TimeInterval) {
        let today = element(ID.todayTab, in: app)
        XCTAssertTrue(today.waitForExistence(timeout: timeout), "The four-tab shell did not open")
        XCTAssertTrue(waitUntil(timeout: Timeout.navigation) { today.isHittable })
    }

    /// The tab identifiers are bound only when the native tab bar has exactly
    /// four items, so finding all four also proves the tab count.
    @MainActor
    private func assertFourTabShell(in app: XCUIApplication) {
        let tabs = [
            (ID.todayTab, "Today"),
            (ID.workTab, "Work"),
            (ID.assetsTab, "Assets"),
            (ID.reportsTab, "Reports"),
        ]
        for (identifier, label) in tabs {
            let tab = element(identifier, in: app)
            XCTAssertTrue(tab.waitForExistence(timeout: Timeout.navigation), "Missing tab \(label)")
            XCTAssertEqual(tab.label, label)
        }
        let tabBar = app.tabBars.firstMatch
        XCTAssertFalse(tabBar.buttons.matching(NSPredicate(format: "label == %@", "Signs")).firstMatch.exists)
        XCTAssertFalse(tabBar.buttons.matching(NSPredicate(format: "label == %@", "Settings")).firstMatch.exists)
    }

    @MainActor
    private func openTab(_ identifier: String, in app: XCUIApplication) {
        let tab = element(identifier, in: app)
        XCTAssertTrue(tab.waitForExistence(timeout: Timeout.navigation), "Missing tab \(identifier)")
        XCTAssertTrue(waitUntil(timeout: Timeout.navigation) { tab.isHittable })
        tab.tap()
    }

    @MainActor
    private func assertTodayPhaseOneEmpty(in app: XCUIApplication) {
        let empty = app.descendants(matching: .any)
            .matching(NSPredicate(
                format: "identifier == %@ OR label == %@",
                ID.todayEmpty, Copy.nothingPlanned
            ))
            .firstMatch
        XCTAssertTrue(empty.waitForExistence(timeout: Timeout.navigation), "Today did not show the Phase 1 empty state")
        XCTAssertTrue(text(Copy.nothingPlanned, in: app).waitForExistence(timeout: Timeout.short))
        XCTAssertTrue(text(Copy.todayMessage, in: app).exists)
        XCTAssertTrue(app.navigationBars["Today"].exists)
        XCTAssertFalse(element(ID.planEntry, in: app).exists)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label == %@", "Plan")).firstMatch.exists)
    }

    @MainActor
    private func assertWorkPhaseOneEmpty(in app: XCUIApplication) {
        let header = app.descendants(matching: .any)
            .matching(NSPredicate(
                format: "identifier == %@ OR label ==[c] %@",
                ID.completedHeader, "Completed work"
            ))
            .firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: Timeout.navigation), "Work did not show Completed work")
        XCTAssertTrue(text(Copy.completedEmpty, in: app).waitForExistence(timeout: Timeout.navigation))
        XCTAssertTrue(app.navigationBars["Work"].exists)
        XCTAssertFalse(text("No current work", in: app).exists)
        XCTAssertFalse(completedWorkRow(in: app).exists)
    }

    @MainActor
    private func assertAssetsWelcome(in app: XCUIApplication) {
        XCTAssertTrue(element(ID.welcome, in: app).waitForExistence(timeout: Timeout.navigation))
        let title = element(ID.welcomeTitle, in: app)
        XCTAssertTrue(title.waitForExistence(timeout: Timeout.short))
        XCTAssertEqual(title.label, Copy.welcomeTitle)
        XCTAssertTrue(element(ID.addFirstSign, in: app).exists)
    }

    @MainActor
    private func assertReportsEmpty(in app: XCUIApplication) {
        XCTAssertTrue(element(ID.reportsScreen, in: app).waitForExistence(timeout: Timeout.navigation))
        XCTAssertTrue(element(ID.reportsPlaceholder, in: app).waitForExistence(timeout: Timeout.navigation))
        XCTAssertTrue(text(Copy.reportsEmpty, in: app).waitForExistence(timeout: Timeout.short))
        XCTAssertFalse(element(ID.reportsVisit, in: app).exists)
    }

    // MARK: - Sign, check and report (S3_3 / S4_4 steps)

    @MainActor
    private func createSign(in app: XCUIApplication) {
        let add = element(ID.addFirstSign, in: app)
        scrollUntilHittable(add, in: app)
        add.tap()
        let site = element("s2.new-sign.site-label", in: app)
        let sign = element("s2.new-sign.sign-label", in: app)
        XCTAssertTrue(site.waitForExistence(timeout: Timeout.navigation))
        site.tap()
        site.typeText("North Campus")
        sign.tap()
        sign.typeText("Monument Sign")
        dismissKeyboard(in: app)
        let save = element("s2.new-sign.save", in: app)
        scrollUntilHittable(save, in: app)
        save.tap()
        XCTAssertTrue(element(ID.signDetail, in: app).waitForExistence(timeout: Timeout.navigation))
    }

    @MainActor
    private func completeNoVisibleIssueCheck(in app: XCUIApplication) {
        let start = element("s2.sign-detail.start-check", in: app)
        XCTAssertTrue(start.waitForExistence(timeout: Timeout.navigation))
        scrollUntilHittable(start, in: app)
        start.tap()

        XCTAssertTrue(element("s3.preflight.screen", in: app).waitForExistence(timeout: Timeout.navigation))
        let zone = element("s3.preflight.time-zone", in: app)
        if zone.waitForExistence(timeout: 2) {
            zone.tap()
            zone.typeText("America/New_York")
            dismissKeyboard(in: app)
            turnOnSwitch("s3.preflight.time-zone-confirmed", in: app)
        }
        turnOnSwitch("s3.preflight.after-dark", in: app)
        turnOnSwitch("s3.preflight.safe-position", in: app)
        let begin = element("s3.preflight.begin", in: app)
        scrollUntilHittable(begin, in: app)
        begin.tap()

        acceptFixture(in: app, heading: "1 of 2 · Wide view")
        acceptFixture(in: app, heading: "2 of 2 · Close view")

        let noVisibleIssue = element("s3.outcome.no-visible-issue", in: app)
        XCTAssertTrue(noVisibleIssue.waitForExistence(timeout: Timeout.navigation))
        scrollUntilHittable(noVisibleIssue, in: app)
        noVisibleIssue.tap()
        let outcomeContinue = element("s3.outcome.continue", in: app)
        scrollUntilHittable(outcomeContinue, in: app)
        XCTAssertTrue(outcomeContinue.isEnabled)
        outcomeContinue.tap()
        let save = element("s3.review.save-report", in: app)
        XCTAssertTrue(save.waitForExistence(timeout: Timeout.navigation))
        scrollUntilHittable(save, in: app)
        save.tap()
    }

    @MainActor
    private func acceptFixture(in app: XCUIApplication, heading: String) {
        let headingElement = element("s3.capture.heading", in: app)
        XCTAssertTrue(headingElement.waitForExistence(timeout: Timeout.navigation))
        XCTAssertTrue(
            waitUntil(timeout: Timeout.navigation) { headingElement.label == heading },
            "Capture did not reach \(heading)"
        )
        let importButton = element("s3.capture.import-fixture", in: app)
        scrollUntilHittable(importButton, in: app)
        XCTAssertTrue(waitUntil(timeout: Timeout.navigation) {
            importButton.exists && importButton.isEnabled && importButton.isHittable
        })
        importButton.tap()
        XCTAssertTrue(element("s3.capture.preview", in: app).waitForExistence(timeout: Timeout.navigation))
        let usePhoto = element("s3.capture.use-photo", in: app)
        scrollUntilHittable(usePhoto, in: app)
        XCTAssertTrue(waitUntil(timeout: Timeout.navigation) {
            usePhoto.exists && usePhoto.isEnabled && usePhoto.isHittable
        })
        usePhoto.tap()
    }

    // MARK: - Completed work and approval response

    @MainActor
    private func completedWorkRow(in app: XCUIApplication) -> XCUIElement {
        app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", ID.completedRowPrefix))
            .firstMatch
    }

    @MainActor
    private func openCompletedWorkDetail(_ row: XCUIElement, in app: XCUIApplication) {
        scrollUntilHittable(row, in: app)
        row.tap()
        let more = element(ID.signoffMore, in: app)
        XCTAssertTrue(more.waitForExistence(timeout: Timeout.navigation), "Completed-work detail did not open")
        XCTAssertTrue(app.navigationBars["Completed work"].waitForExistence(timeout: Timeout.short))
        XCTAssertTrue(labelContaining("Monument Sign", in: app).exists)
    }

    @MainActor
    private func openRecordEditor(in app: XCUIApplication) {
        let more = element(ID.signoffMore, in: app)
        scrollUntilHittable(more, in: app)
        more.tap()
        let record = app.buttons
            .matching(NSPredicate(
                format: "identifier == %@ OR label == %@",
                ID.signoffRecord, Copy.recordAction
            ))
            .firstMatch
        XCTAssertTrue(record.waitForExistence(timeout: Timeout.navigation), "More did not offer Record approval response")
        XCTAssertTrue(record.isEnabled)
        record.tap()
        let header = element(ID.signoffHeader, in: app)
        XCTAssertTrue(header.waitForExistence(timeout: Timeout.navigation), "The response editor did not open")
        XCTAssertEqual(header.label, Copy.recordAction)
        XCTAssertTrue(element(ID.signoffConfirm, in: app).exists)
        XCTAssertTrue(element(ID.signoffCancel, in: app).exists)
    }

    /// Claimed role is filled first so Typed name, directly above it, stays
    /// visible over the keyboard. Both fields are vertical text fields, so
    /// their return key inserts a line rather than dismissing the keyboard.
    @MainActor
    private func recordApprovalResponse(
        typedName: String,
        claimedRole: String,
        in app: XCUIApplication
    ) {
        let role = element(ID.signoffClaimedRole, in: app)
        XCTAssertTrue(role.waitForExistence(timeout: Timeout.navigation))
        scrollEditorUntilHittable(role, towardTop: false, in: app)
        role.tap()
        role.typeText(claimedRole)
        let name = element(ID.signoffTypedName, in: app)
        scrollEditorUntilHittable(name, towardTop: true, in: app)
        name.tap()
        name.typeText(typedName)
        let confirm = element(ID.signoffConfirm, in: app)
        scrollEditorUntilHittable(confirm, towardTop: false, in: app)
        XCTAssertTrue(confirm.isEnabled)
        confirm.tap()
    }

    /// The editor's optional drawn-mark Canvas takes any drag, so a centre
    /// swipe could draw a mark instead of scrolling. Drag in the left margin,
    /// outside every card, and above the keyboard.
    @MainActor
    private func scrollEditorUntilHittable(
        _ target: XCUIElement,
        towardTop: Bool,
        in app: XCUIApplication
    ) {
        let upper = app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.15))
        let lower = app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.45))
        let passes: [Bool] = [towardTop, !towardTop]
        for revealsEarlierContent in passes {
            for _ in 0..<12 {
                if target.isHittable { return }
                if revealsEarlierContent {
                    upper.press(forDuration: 0.05, thenDragTo: lower)
                } else {
                    lower.press(forDuration: 0.05, thenDragTo: upper)
                }
            }
        }
        XCTAssertTrue(target.isHittable, "Could not scroll the response editor to the control")
    }

    // MARK: - Settings and App Lock

    @MainActor
    private func openSettings(in app: XCUIApplication) {
        openTab(ID.todayTab, in: app)
        dismissHostedSystemNotificationIfPresent()
        let button = app.buttons.matching(identifier: ID.settingsButton).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: Timeout.navigation))
        XCTAssertTrue(waitUntil(timeout: Timeout.navigation) { button.isHittable })
        button.tap()
        let toggle = appLockToggle(in: app)
        XCTAssertTrue(toggle.waitForExistence(timeout: Timeout.navigation), "Settings did not show App Lock")
        XCTAssertTrue(
            waitUntil(timeout: Timeout.navigation) { toggle.isEnabled },
            "The App Lock setting did not become available"
        )
    }

    @MainActor
    private func assertAppLockSettings(enabled: Bool, in app: XCUIApplication) {
        XCTAssertTrue(element(ID.appLockSettings, in: app).exists)
        XCTAssertTrue(labelContaining(Copy.appLockSetting, in: app).exists)
        let lockNow = element(ID.appLockLockNow, in: app)
        XCTAssertTrue(lockNow.exists)
        XCTAssertEqual(lockNow.isEnabled, enabled)
        XCTAssertFalse(element(ID.remindersSettings, in: app).exists)
        XCTAssertFalse(element(ID.remindersEnabled, in: app).exists)
        XCTAssertFalse(text("Reminders", in: app).exists)
    }

    @MainActor
    private func appLockToggle(in app: XCUIApplication) -> XCUIElement {
        app.switches.matching(identifier: ID.appLockToggle).firstMatch
    }

    private enum ToggleTap {
        case nativeSwitch
        case trailingEdge
        case elementCentre
    }

    /// A SwiftUI Toggle outside a Form toggles only on its switch, so tap the
    /// native switch, else the trailing edge. If the first tap changes
    /// nothing, try the next path once before failing.
    @MainActor
    private func tapAppLockToggle(in app: XCUIApplication) {
        let toggle = appLockToggle(in: app)
        scrollUntilHittable(toggle, in: app, towardTop: true)
        XCTAssertTrue(waitUntil(timeout: Timeout.navigation) { toggle.isEnabled })
        let before = toggle.value as? String
        let nativeSwitch = toggle.switches.firstMatch
        var taps: [ToggleTap] = []
        if nativeSwitch.exists && nativeSwitch.isHittable { taps.append(.nativeSwitch) }
        taps += [.trailingEdge, .elementCentre]
        // Enabling covers the app; either path disables the toggle while busy.
        let responded: () -> Bool = {
            !toggle.exists || !toggle.isEnabled || (toggle.value as? String) != before
        }
        for path in taps.prefix(2) {
            switch path {
            case .nativeSwitch:
                nativeSwitch.tap()
            case .trailingEdge:
                toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            case .elementCentre:
                toggle.tap()
            }
            if waitUntil(timeout: 5, responded) { return }
        }
        XCTFail("The App Lock toggle did not respond to either tap path")
    }

    /// Turning App Lock off republishes content access, which can rebuild the
    /// shell at its root; reopen Settings when that happens.
    @MainActor
    private func turnAppLockOff(in app: XCUIApplication) {
        tapAppLockToggle(in: app)
        let toggle = appLockToggle(in: app)
        let today = element(ID.todayTab, in: app)
        XCTAssertTrue(
            waitUntil(timeout: Timeout.navigation) {
                (toggle.exists && (toggle.value as? String) == "0" && toggle.isEnabled)
                    || (!toggle.exists && today.exists)
            },
            "App Lock did not turn off"
        )
        settle(1.5)
        if !toggle.exists {
            openSettings(in: app)
        }
        XCTAssertTrue(toggle.waitForExistence(timeout: Timeout.navigation))
        XCTAssertEqual(toggle.value as? String, "0")
    }

    @MainActor
    private func unlockButton(in app: XCUIApplication) -> XCUIElement {
        app.buttons
            .matching(NSPredicate(
                format: "identifier == %@ OR label == %@",
                ID.appLockUnlock, "Unlock"
            ))
            .firstMatch
    }

    @MainActor
    private func waitForLockedCover(in app: XCUIApplication, timeout: TimeInterval) {
        let button = unlockButton(in: app)
        XCTAssertTrue(
            waitUntil(timeout: timeout) { button.exists && button.isEnabled },
            "The App Lock cover did not appear"
        )
        XCTAssertTrue(text(Copy.appLockLocked, in: app).waitForExistence(timeout: Timeout.short))
        XCTAssertFalse(text("Unavailable", in: app).exists)
    }

    @MainActor
    private func unlock(in app: XCUIApplication) {
        let button = unlockButton(in: app)
        XCTAssertTrue(waitUntil(timeout: Timeout.navigation) {
            button.exists && button.isEnabled && button.isHittable
        })
        button.tap()
        waitForShell(in: app, timeout: Timeout.relaunch)
    }

    /// Both response fields start empty; an empty field may report its prompt.
    @MainActor
    private func assertResponseFieldsEmpty(in app: XCUIApplication) {
        for (identifier, prompt) in [
            (ID.signoffTypedName, Copy.typedNamePrompt),
            (ID.signoffClaimedRole, Copy.claimedRolePrompt),
        ] {
            let field = element(identifier, in: app)
            XCTAssertTrue(field.waitForExistence(timeout: Timeout.short))
            let value = field.value as? String ?? ""
            XCTAssertTrue(value.isEmpty || value == prompt, "\(identifier) is not empty")
        }
    }

    // MARK: - Teardown

    /// Runs after every method, including after a failure.
    @MainActor
    private func registerDeviceStateRestore(storeID: String) {
        addTeardownBlock { @MainActor in
            await self.restoreDeviceState(storeID: storeID)
        }
    }

    /// Best effort and assertion-free: appearance back to light, and App Lock
    /// back off. App Lock lives in the app's own UserDefaults, which the
    /// isolated store does not reset, so a failure between the enable tap and
    /// the final disable would otherwise lock every later launch.
    @MainActor
    private func restoreDeviceState(storeID: String) async {
        XCUIDevice.shared.appearance = .light
        guard appLockMayBeOn else { return }
        let app = XCUIApplication()
        configure(
            app,
            variant: .light,
            storeID: storeID,
            extraArguments: [Self.localAuthenticationSuccessArgument]
        )
        app.launch()
        let today = element(ID.todayTab, in: app)
        let unlock = unlockButton(in: app)
        _ = waitUntil(timeout: Timeout.relaunch) {
            today.exists || (unlock.exists && unlock.isEnabled)
        }
        if !waitUntil(timeout: 5, { today.exists }), unlock.exists, unlock.isEnabled {
            unlock.tap()
        }
        guard waitUntil(timeout: Timeout.relaunch, { today.exists && today.isHittable }) else { return }
        today.tap()
        let settings = app.buttons.matching(identifier: ID.settingsButton).firstMatch
        guard waitUntil(timeout: Timeout.navigation, { settings.exists && settings.isHittable }) else { return }
        settings.tap()
        let toggle = appLockToggle(in: app)
        guard waitUntil(timeout: Timeout.navigation, { toggle.exists && toggle.isEnabled }) else { return }
        if (toggle.value as? String) == "1" {
            let nativeSwitch = toggle.switches.firstMatch
            if nativeSwitch.exists && nativeSwitch.isHittable {
                nativeSwitch.tap()
            } else {
                toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            }
            guard waitUntil(timeout: Timeout.navigation, {
                !toggle.exists || (toggle.value as? String) == "0"
            }) else { return }
        }
        appLockMayBeOn = false
        app.terminate()
    }

    // MARK: - Queries and waits

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    private func text(_ label: String, in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    @MainActor
    private func labelContaining(_ value: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", value))
            .firstMatch
    }

    @MainActor
    private func turnOnSwitch(_ identifier: String, in app: XCUIApplication) {
        let control = element(identifier, in: app)
        scrollUntilHittable(control, in: app)
        control.tap()
        XCTAssertEqual(control.value as? String, "1")
    }

    @MainActor
    private func dismissKeyboard(in app: XCUIApplication) {
        guard app.keyboards.firstMatch.exists else { return }
        for key in ["Return", "return", "Done", "done"] {
            let button = app.keyboards.buttons[key]
            if button.exists {
                button.tap()
                break
            }
        }
        if app.keyboards.firstMatch.exists { app.swipeDown() }
    }

    @MainActor
    private func scrollUntilHittable(
        _ element: XCUIElement,
        in app: XCUIApplication,
        towardTop: Bool = false
    ) {
        for revealsEarlierContent in [towardTop, !towardTop] {
            for _ in 0..<16 {
                if element.isHittable { return }
                if revealsEarlierContent { app.swipeDown() } else { app.swipeUp() }
            }
        }
        XCTAssertTrue(element.isHittable)
    }

    @MainActor
    private func waitForCount(_ expected: Int, identifier: String, in app: XCUIApplication) {
        let query = app.descendants(matching: .any).matching(identifier: identifier)
        XCTAssertTrue(
            waitUntil(timeout: Timeout.navigation) { query.count == expected },
            "Expected \(expected) \(identifier)"
        )
    }

    /// Polls on the main actor so the condition may read XCUIElement state.
    @MainActor
    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if condition() { return true }
            settle(0.5)
        } while Date() < deadline
        return condition()
    }

    @MainActor
    private func settle(_ seconds: TimeInterval) {
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "settle")], timeout: seconds)
    }
}

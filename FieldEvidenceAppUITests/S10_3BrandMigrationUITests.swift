import CoreGraphics
import CryptoKit
import Foundation
import StoreKitTest
import XCTest

class S10BrandMigrationRouteUITestCase: XCTestCase {
    private struct AutomationShard {
        let ordinal: Int
        let shardID: String
        let requirementID: String
        let deviceProfileID: String
        let accessibilityFeature: String
        let appearance: String
        let contrast: String
        let contentSizeCategory: String
        let locale: String
        let layoutDirection: String
        let differentiateWithoutColor: Bool
        let reduceMotion: Bool
        let reduceTransparency: Bool

        var expectedEnvironment: [String: String] {
            let isMinimum = deviceProfileID == "iphone-se-3-ios-18.0-minimum"
            return [
                "CI_S10_4_SHARD_ID": shardID,
                "CI_S10_4_PROVISION_RUNTIME": isMinimum ? "true" : "false",
                "CI_S10_4_RUNTIME_DOWNLOAD_VERSION": isMinimum ? "18.0" : "",
                "CI_S10_4_DEVICE_PROFILE_ID": deviceProfileID,
                "CI_S10_4_SHARD_ORDINAL": String(ordinal),
                "CI_S10_4_REQUIREMENT_ID": requirementID,
                "CI_S10_4_ACCESSIBILITY_FEATURE": accessibilityFeature,
                "CI_S10_4_ACCESSIBILITY_FEATURES": accessibilityFeature,
                "CI_S10_4_APPEARANCE": appearance,
                "CI_S10_4_CONTRAST": contrast,
                "CI_S10_4_CONTENT_SIZE_CATEGORY": contentSizeCategory,
                "CI_S10_4_LOCALE": locale,
                "CI_S10_4_LAYOUT_DIRECTION": layoutDirection,
                "CI_S10_4_DIFFERENTIATE_WITHOUT_COLOR": String(differentiateWithoutColor),
                "CI_S10_4_REDUCE_MOTION": String(reduceMotion),
                "CI_S10_4_REDUCE_TRANSPARENCY": String(reduceTransparency),
            ]
        }
    }

    private struct ContrastAuditExceptionSignature {
        let issueID: String
        let shardID: String
        let stateID: String
        let taskID: String
        let owner: String
        let expiresAt: String
        let rationale: String
        let auditTypeRawValue: String
        let compactDescription: String
        let detailedDescription: String
        let elementIdentifier: String
        let elementLabel: String
        let elementTypeDescription: String
        let elementFrame: CGRect
        let applicationFrame: CGRect
    }

    private enum AutomationConfigurationError: Error, CustomStringConvertible {
        case invalid(String)

        var description: String {
            switch self {
            case .invalid(let message): return message
            }
        }
    }

    private static let automationShards: [AutomationShard] = [
        AutomationShard(ordinal: 1, shardID: "s10.4.current.default-light", requirementID: "default_light", deviceProfileID: "iphone-17-ios-26.2-current", accessibilityFeature: "voiceover", appearance: "light", contrast: "standard", contentSizeCategory: "UICTContentSizeCategoryL", locale: "en-US-release", layoutDirection: "left_to_right", differentiateWithoutColor: false, reduceMotion: false, reduceTransparency: false),
        AutomationShard(ordinal: 2, shardID: "s10.4.current.default-dark", requirementID: "default_dark", deviceProfileID: "iphone-17-ios-26.2-current", accessibilityFeature: "dark_interface", appearance: "dark", contrast: "standard", contentSizeCategory: "UICTContentSizeCategoryL", locale: "en-US-release", layoutDirection: "left_to_right", differentiateWithoutColor: false, reduceMotion: false, reduceTransparency: false),
        AutomationShard(ordinal: 3, shardID: "s10.4.current.increased-contrast", requirementID: "increased_contrast", deviceProfileID: "iphone-17-ios-26.2-current", accessibilityFeature: "sufficient_contrast", appearance: "light", contrast: "increased", contentSizeCategory: "UICTContentSizeCategoryL", locale: "en-US-release", layoutDirection: "left_to_right", differentiateWithoutColor: false, reduceMotion: false, reduceTransparency: false),
        AutomationShard(ordinal: 4, shardID: "s10.4.current.ax-text", requirementID: "ax_text", deviceProfileID: "iphone-17-ios-26.2-current", accessibilityFeature: "larger_text", appearance: "light", contrast: "standard", contentSizeCategory: "UICTContentSizeCategoryAccessibilityXXXL", locale: "en-US-release", layoutDirection: "left_to_right", differentiateWithoutColor: false, reduceMotion: false, reduceTransparency: false),
        AutomationShard(ordinal: 5, shardID: "s10.4.current.differentiate-without-color", requirementID: "differentiate_without_color", deviceProfileID: "iphone-17-ios-26.2-current", accessibilityFeature: "differentiate_without_color", appearance: "light", contrast: "standard", contentSizeCategory: "UICTContentSizeCategoryL", locale: "en-US-release", layoutDirection: "left_to_right", differentiateWithoutColor: true, reduceMotion: false, reduceTransparency: false),
        AutomationShard(ordinal: 6, shardID: "s10.4.current.reduce-motion", requirementID: "reduce_motion", deviceProfileID: "iphone-17-ios-26.2-current", accessibilityFeature: "reduced_motion", appearance: "light", contrast: "standard", contentSizeCategory: "UICTContentSizeCategoryL", locale: "en-US-release", layoutDirection: "left_to_right", differentiateWithoutColor: false, reduceMotion: true, reduceTransparency: false),
        AutomationShard(ordinal: 7, shardID: "s10.4.current.reduce-transparency", requirementID: "reduce_transparency", deviceProfileID: "iphone-17-ios-26.2-current", accessibilityFeature: "voice_control", appearance: "light", contrast: "standard", contentSizeCategory: "UICTContentSizeCategoryL", locale: "en-US-release", layoutDirection: "left_to_right", differentiateWithoutColor: false, reduceMotion: false, reduceTransparency: true),
        AutomationShard(ordinal: 8, shardID: "s10.4.minimum.minimum-os", requirementID: "minimum_os", deviceProfileID: "iphone-se-3-ios-18.0-minimum", accessibilityFeature: "voiceover", appearance: "light", contrast: "standard", contentSizeCategory: "UICTContentSizeCategoryL", locale: "en-US-release", layoutDirection: "left_to_right", differentiateWithoutColor: false, reduceMotion: false, reduceTransparency: false),
        AutomationShard(ordinal: 9, shardID: "s10.4.minimum.double-length", requirementID: "double_length", deviceProfileID: "iphone-se-3-ios-18.0-minimum", accessibilityFeature: "larger_text", appearance: "light", contrast: "standard", contentSizeCategory: "UICTContentSizeCategoryAccessibilityXXXL", locale: "en-US-double-length", layoutDirection: "left_to_right", differentiateWithoutColor: false, reduceMotion: false, reduceTransparency: false),
        AutomationShard(ordinal: 10, shardID: "s10.4.minimum.rtl", requirementID: "rtl", deviceProfileID: "iphone-se-3-ios-18.0-minimum", accessibilityFeature: "dark_interface", appearance: "dark", contrast: "standard", contentSizeCategory: "UICTContentSizeCategoryL", locale: "ar-RTL", layoutDirection: "right_to_left", differentiateWithoutColor: false, reduceMotion: false, reduceTransparency: false),
        AutomationShard(ordinal: 11, shardID: "s10.4.minimum.rtl-string", requirementID: "rtl_string", deviceProfileID: "iphone-se-3-ios-18.0-minimum", accessibilityFeature: "voice_control", appearance: "light", contrast: "standard", contentSizeCategory: "UICTContentSizeCategoryL", locale: "ar-RTL-string", layoutDirection: "right_to_left", differentiateWithoutColor: false, reduceMotion: false, reduceTransparency: false),
        AutomationShard(ordinal: 12, shardID: "s10.4.minimum.tall", requirementID: "tall", deviceProfileID: "iphone-se-3-ios-18.0-minimum", accessibilityFeature: "reduced_motion", appearance: "light", contrast: "standard", contentSizeCategory: "UICTContentSizeCategoryL", locale: "en-US-tall", layoutDirection: "left_to_right", differentiateWithoutColor: false, reduceMotion: true, reduceTransparency: false),
        AutomationShard(ordinal: 13, shardID: "s10.4.minimum.accented", requirementID: "accented", deviceProfileID: "iphone-se-3-ios-18.0-minimum", accessibilityFeature: "sufficient_contrast", appearance: "light", contrast: "increased", contentSizeCategory: "UICTContentSizeCategoryL", locale: "en-US-accented", layoutDirection: "left_to_right", differentiateWithoutColor: false, reduceMotion: false, reduceTransparency: false),
        AutomationShard(ordinal: 14, shardID: "s10.4.minimum.bounded", requirementID: "bounded", deviceProfileID: "iphone-se-3-ios-18.0-minimum", accessibilityFeature: "differentiate_without_color", appearance: "light", contrast: "standard", contentSizeCategory: "UICTContentSizeCategoryL", locale: "en-US-bounded", layoutDirection: "left_to_right", differentiateWithoutColor: true, reduceMotion: false, reduceTransparency: false),
    ]

    private static let contrastAuditExceptionSignatures = [
        ContrastAuditExceptionSignature(
            issueID: "S10.4-XCUI-CONTRAST-FP-DEFAULT-DARK-WIDE-VIEW",
            shardID: "s10.4.current.default-dark",
            stateID: "state.sample-report.ready",
            taskID: "report_comprehension",
            owner: "palatis3",
            expiresAt: "2026-11-20",
            rationale: "Xcode 26.6/iOS 26.2 reports a SwiftUI.AccessibilityNode contrast issue for Wide view even though the audit-owned crop visibly renders white text on the dark elevated Sample card; the exception is limited to the frozen public issue signature.",
            auditTypeRawValue: "1",
            compactDescription: "Contrast failed",
            detailedDescription: "Contrast failed for SwiftUI.AccessibilityNode",
            elementIdentifier: "",
            elementLabel: "Wide view",
            elementTypeDescription: "XCUIElementType(rawValue: 48)",
            elementFrame: CGRect(
                x: 32,
                y: 810.33333333333337,
                width: 80,
                height: 20.333333333333258
            ),
            applicationFrame: CGRect(x: 0, y: 0, width: 402, height: 874)
        ),
        ContrastAuditExceptionSignature(
            issueID: "S10.4-XCUI-CONTRAST-FP-AX-TEXT-CUSTOMER-SITE-NAME",
            shardID: "s10.4.current.ax-text",
            stateID: "state.new-sign.editing",
            taskID: "one_handed_start",
            owner: "palatis3",
            expiresAt: "2026-11-20",
            rationale: "Xcode 26.6/iOS 26.2 reports a SwiftUI.AccessibilityNode contrast issue for Customer / site name even though the audit-owned crop visibly renders black text on white and the public node is bound to the top navigation-region frame; the exception is limited to the frozen public issue signature.",
            auditTypeRawValue: "1",
            compactDescription: "Contrast failed",
            detailedDescription: "Contrast failed for SwiftUI.AccessibilityNode",
            elementIdentifier: "",
            elementLabel: "Customer / site name",
            elementTypeDescription: "XCUIElementType(rawValue: 48)",
            elementFrame: CGRect(
                x: 32,
                y: 19,
                width: 251.66666666666663,
                height: 116.66666666666663
            ),
            applicationFrame: CGRect(x: 0, y: 0, width: 402, height: 874)
        ),
        ContrastAuditExceptionSignature(
            issueID: "S10.4-XCUI-CONTRAST-FP-AX-TEXT-PREFLIGHT-BEFORE-YOU-BEGIN",
            shardID: "s10.4.current.ax-text",
            stateID: "state.check-preflight.ready",
            taskID: "one_handed_start",
            owner: "palatis3",
            expiresAt: "2026-11-20",
            rationale: "Xcode 26.6/iOS 26.2 reports a SwiftUI.AccessibilityNode contrast issue for Before you begin while the frozen public node frame is bottom-clipped outside the 402x874 application frame in the AX-text preflight state; the exception is limited to the frozen public issue signature.",
            auditTypeRawValue: "1",
            compactDescription: "Contrast failed",
            detailedDescription: "Contrast failed for SwiftUI.AccessibilityNode",
            elementIdentifier: "",
            elementLabel: "Before you begin",
            elementTypeDescription: "XCUIElementType(rawValue: 48)",
            elementFrame: CGRect(
                x: 32,
                y: 844.33333333333337,
                width: 231,
                height: 125.33333333333326
            ),
            applicationFrame: CGRect(x: 0, y: 0, width: 402, height: 874)
        ),
    ]

    private static let commonTaskStateIDs: [(taskID: String, stateIDs: [String])] = [
        ("one_handed_start", [
            "state.check-preflight.ready", "state.new-sign.editing",
            "state.new-sign.validation-error", "state.pack.unavailable",
            "state.paywall.available", "state.paywall.purchase-complete",
            "state.paywall.unavailable", "state.sign-detail.ready",
            "state.sign-selection.ready", "state.welcome.empty",
        ]),
        ("capture_and_review", [
            "state.capture.camera-denied", "state.capture.close-preview",
            "state.capture.close-ready", "state.capture.low-storage-error",
            "state.capture.wide-preview", "state.capture.wide-ready",
            "state.check-outcome.could-not-verify", "state.check-outcome.no-visible-issue",
            "state.check-outcome.visible-issue", "state.check-preflight.ready",
            "state.check-review.could-not-verify", "state.check-review.no-visible-issue",
            "state.check-review.visible-issue", "state.receipt.report-saved",
            "state.report-detail.ready",
        ]),
        ("force_quit_draft_resume", [
            "state.capture.camera-denied", "state.capture.close-preview",
            "state.capture.close-ready", "state.capture.low-storage-error",
            "state.capture.wide-preview", "state.capture.wide-ready",
            "state.check-preflight.ready", "state.check-review.could-not-verify",
            "state.check-review.no-visible-issue", "state.check-review.visible-issue",
            "state.recheck-capture.close-preview", "state.recheck-capture.close-ready",
            "state.recheck-capture.wide-preview", "state.recheck-capture.wide-ready",
            "state.recheck-preflight.ready", "state.recheck-review.could-not-verify",
            "state.recheck-review.different-issue", "state.recheck-review.issue-still-visible",
            "state.recheck-review.resolved", "state.work.editing",
            "state.work.saving", "state.work.validation-error",
        ]),
        ("history_recovery", [
            "state.backup.ready", "state.diagnostics.ready",
            "state.erase.confirmation", "state.feedback.blocked",
            "state.feedback.review-ready", "state.report-comparison.ready",
            "state.report-correction.completed", "state.report-correction.editing",
            "state.report-correction.saving", "state.report-correction.validation-error",
            "state.report-detail.ready", "state.report-history.ready",
            "state.report-pdf.failed", "state.reports-index.empty",
            "state.reports-index.ready", "state.restore.choose-backup",
            "state.settings.hub", "state.sign-detail.delete-confirmation",
            "state.subscription.active", "state.subscription.no-entitlement",
        ]),
        ("work_and_recheck", [
            "state.issue.different-open", "state.issue.open",
            "state.issue.recheck-due", "state.issue.resolved",
            "state.recheck-capture.close-preview", "state.recheck-capture.close-ready",
            "state.recheck-capture.wide-preview", "state.recheck-capture.wide-ready",
            "state.recheck-outcome.could-not-verify", "state.recheck-outcome.different-issue",
            "state.recheck-outcome.issue-still-visible", "state.recheck-outcome.resolved",
            "state.recheck-preflight.ready", "state.recheck-receipt.saved",
            "state.recheck-report-detail.ready", "state.recheck-review.could-not-verify",
            "state.recheck-review.different-issue", "state.recheck-review.issue-still-visible",
            "state.recheck-review.resolved", "state.sign-detail.open-issue",
            "state.work.editing", "state.work.saving", "state.work.validation-error",
        ]),
        ("report_comprehension", [
            "state.receipt.report-saved", "state.recheck-receipt.saved",
            "state.recheck-report-detail.ready", "state.report-comparison.ready",
            "state.report-correction.completed", "state.report-correction.editing",
            "state.report-correction.saving", "state.report-correction.validation-error",
            "state.report-detail.ready", "state.report-history.ready",
            "state.report-pdf.failed", "state.reports-index.empty",
            "state.reports-index.ready", "state.sample-report.ready",
        ]),
    ]

    private enum AlternativeRecheckOutcome: Equatable {
        case couldNotVerify
        case issueStillVisible
        case differentIssue
    }

    private var storeKitSession: SKTestSession?
    private var migratedStateIDs: [String] = []
    private var automationShard: AutomationShard?
    private var automationAXTreeDigests: [String: String] = [:]
    private var automationContrastExceptions: [String: ContrastAuditExceptionSignature] = [:]
    private var pseudoLabelSentinelValidated = false

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func configureAutomatedBrandLabShardFromEnvironment() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["CI_TASK_ID"] == "S10.4" else {
            throw AutomationConfigurationError.invalid("CI_TASK_ID must equal S10.4")
        }
        guard let shardID = environment["CI_S10_4_SHARD_ID"],
              let shard = Self.automationShards.first(where: { $0.shardID == shardID }) else {
            throw AutomationConfigurationError.invalid("CI_S10_4_SHARD_ID is not a frozen shard")
        }
        let observed = Dictionary(uniqueKeysWithValues: environment
            .filter { $0.key.hasPrefix("CI_S10_4_") }
            .map { ($0.key, $0.value) })
        guard observed == shard.expectedEnvironment else {
            let keys = Set(observed.keys)
                .symmetricDifference(Set(shard.expectedEnvironment.keys))
                .sorted()
                .joined(separator: ",")
            throw AutomationConfigurationError.invalid(
                "CI_S10_4_* environment differs from the frozen shard; key delta=\(keys)"
            )
        }

        let isMinimum = shard.deviceProfileID == "iphone-se-3-ios-18.0-minimum"
        let expectedRuntime = isMinimum ? "iOS 18.0" : "iOS 26.2"
        let expectedBuild = isMinimum ? "22A3351" : "23C54"
        let expectedDevice = isMinimum ? "iPhone SE (3rd generation)" : "iPhone 17"
        guard environment["SIMULATOR_RUNTIME"] == expectedRuntime,
              environment["SIMULATOR_RUNTIME_BUILD"] == expectedBuild,
              environment["SIMULATOR_NAME"] == expectedDevice,
              let udid = environment["CI_SIMULATOR_UDID"],
              !udid.isEmpty else {
            throw AutomationConfigurationError.invalid(
                "Resolved Simulator runtime/build/name/UDID does not match the shard profile"
            )
        }
        automationShard = shard
        automationAXTreeDigests.removeAll()
        automationContrastExceptions.removeAll()
        pseudoLabelSentinelValidated = false
    }

    @MainActor
    private func applyDeviceAppearance(fallbackIsDark: Bool) {
        guard let shard = automationShard else {
            XCUIDevice.shared.appearance = fallbackIsDark ? .dark : .light
            return
        }
        XCUIDevice.shared.appearance = shard.appearance == "dark" ? .dark : .light
    }

    private func effectiveAppearanceName(fallback: String) -> String {
        guard let shard = automationShard else { return fallback }
        return shard.appearance == "dark" ? "Dark" : "Light"
    }

    @MainActor
    func runAllFrozenReleasedStatesUseTheBrandSystemWithoutBehaviorDrift() throws {
        let fixtureURL = try XCTUnwrap(Bundle(for: Self.self).url(
            forResource: "FieldEvidence",
            withExtension: "storekit"
        ))
        let session = try SKTestSession(contentsOf: fixtureURL)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        storeKitSession = session

        applyDeviceAppearance(fallbackIsDark: false)
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
        applyDeviceAppearance(fallbackIsDark: true)
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
        XCTAssertEqual(shell.value as? String, effectiveAppearanceName(fallback: "Light"))
        XCTAssertTrue(element("s2.welcome.screen", in: app)
            .waitForExistence(timeout: 30))
        assertLocalizedLabel(
            element("s2.welcome.title", in: app),
            equals: "Turn tonight's sign check into a clear report."
        )
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
        assertLocalizedLabel(sampleBack, equals: "Back")
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
        assertLocalizedLabel(error, equals: "Blocked: Enter a customer or site name.")
        assertLocalizedLabel(site, equals: "Customer / site name")
        XCTAssertEqual(site.elementType, .textField)
        XCTAssertTrue(
            wait(for: site, predicate: "hasKeyboardFocus == true", timeout: 10)
        )
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
        assertLocalizedValue(sign, equals: "Monument Sign")
        XCTAssertFalse(element("s2.sign-detail.screen", in: app).exists)
        let keyboard = app.keyboards.firstMatch
        let navigationBottom = app.navigationBars.firstMatch.frame.maxY
        let newSignScrollViews = app.scrollViews.containing(
            .textField,
            identifier: "s2.new-sign.site-label"
        )
        XCTAssertEqual(newSignScrollViews.count, 1)
        let scrollView = newSignScrollViews.firstMatch
        XCTAssertTrue(scrollView.waitForExistence(timeout: 10))
        let scrollFrame = scrollView.frame
        let visibleTop = max(scrollFrame.minY, navigationBottom)
        let visibleBottom = min(scrollFrame.maxY, keyboard.frame.minY)
        let dragInset: CGFloat = 24
        let dragStartOffsetY = visibleBottom - scrollFrame.minY - dragInset
        let dragEndOffsetY = visibleTop - scrollFrame.minY + dragInset
        XCTAssertGreaterThan(dragStartOffsetY, dragEndOffsetY)
        let scrollOrigin = scrollView.coordinate(
            withNormalizedOffset: CGVector(dx: 0, dy: 0)
        )
        let dragStart = scrollOrigin.withOffset(
            CGVector(dx: scrollFrame.width / 2, dy: dragStartOffsetY)
        )
        let dragEnd = scrollOrigin.withOffset(
            CGVector(dx: scrollFrame.width / 2, dy: dragEndOffsetY)
        )
        for _ in 0..<12 {
            if error.exists,
               error.frame.minY >= navigationBottom,
               error.frame.maxY <= keyboard.frame.minY {
                break
            }
            dragStart.press(forDuration: 0.05, thenDragTo: dragEnd)
        }
        XCTAssertTrue(
            wait(for: site, predicate: "hasKeyboardFocus == true", timeout: 10)
        )
        XCTAssertTrue(keyboard.waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(error.frame.minY, navigationBottom)
        XCTAssertLessThanOrEqual(error.frame.maxY, keyboard.frame.minY)
        captureBaseline("state.new-sign.validation-error", in: app)

        site.typeText("North Campus")
        dismissKeyboard(in: app)
        dismissKeyboard(in: app)
        XCTAssertTrue(wait(
            for: app.keyboards.firstMatch,
            predicate: "exists == false",
            timeout: 10
        ))
        scroll(save, in: app)
        save.tap()

        let detail = element("s2.sign-detail.screen", in: app)
        XCTAssertTrue(detail.waitForExistence(timeout: 30))
        assertLocalizedLabel(
            element("s2.sign-detail.sign-label", in: app),
            equals: "Monument Sign"
        )
        assertUnidentifiedLocalizedLabel("Complete: Sign saved", in: app)
        captureBaseline("state.sign-detail.ready", in: app)

        let delete = element("s6.1.delete.action", in: app)
        scroll(delete, in: app)
        assertControl(delete, label: "Delete sign")
        delete.tap()
        let deleteScreen = element("s6.1.delete.screen", in: app)
        XCTAssertTrue(deleteScreen.waitForExistence(timeout: 15))
        let cancelDelete = element("s6.1.delete.cancel", in: app)
        scroll(cancelDelete, in: app)
        let confirmDelete = element("s6.1.delete.confirm", in: app)
        let deleteMessage = element("s6.1.delete.message", in: app)
        let siteLabel = element("s2.sign-detail.site-label", in: app)
        XCTAssertTrue(confirmDelete.waitForExistence(timeout: 5))
        XCTAssertTrue(deleteMessage.waitForExistence(timeout: 5))
        XCTAssertTrue(siteLabel.waitForExistence(timeout: 5))
        let deleteConfirmationStateID = "state.sign-detail.delete-confirmation"
        let runsAXTextDeleteConfirmationDiagnostic =
            automationShard?.shardID == "s10.4.current.ax-text"
        if runsAXTextDeleteConfirmationDiagnostic {
            let expectedDeleteMessage =
                "Delete this sign, its photos, and its reports from this app? " +
                "This cannot be undone. Your free-report count will not reset. " +
                "Erase All removes the remaining anonymous count."
            let hasExactDeleteMessage = deleteMessage.exists
                && deleteMessage.label == expectedDeleteMessage
            XCTAssertTrue(
                hasExactDeleteMessage,
                "AX-text delete diagnostic requires the exact confirmation message"
            )
            let diagnosticViewportTop = detail.frame.minY
            let diagnosticViewportBottom = detail.frame.maxY
            let hasVisibleHittableDeleteActions =
                cancelDelete.frame.minY >= diagnosticViewportTop
                && cancelDelete.frame.maxY <= diagnosticViewportBottom
                && confirmDelete.frame.minY >= diagnosticViewportTop
                && confirmDelete.frame.maxY <= diagnosticViewportBottom
                && cancelDelete.isHittable
                && confirmDelete.isHittable
            XCTAssertTrue(
                hasVisibleHittableDeleteActions,
                "AX-text delete diagnostic requires wholly visible, hittable actions"
            )
            guard hasExactDeleteMessage,
                  hasVisibleHittableDeleteActions else { return }
        }
        if !runsAXTextDeleteConfirmationDiagnostic {
        for _ in 0..<4 {
            let viewportTop = detail.frame.minY
            let viewportBottom = detail.frame.maxY
            let preferredMinimumShift = max(
                viewportTop - deleteScreen.frame.minY,
                max(
                    viewportTop - deleteMessage.frame.minY,
                    max(
                        viewportTop - cancelDelete.frame.minY,
                        viewportTop - confirmDelete.frame.minY
                    )
                )
            )
            let preferredMaximumShift = min(
                viewportTop - siteLabel.frame.maxY,
                min(
                    viewportBottom - deleteScreen.frame.maxY,
                    min(
                        viewportBottom - deleteMessage.frame.maxY,
                        min(
                            viewportBottom - cancelDelete.frame.maxY,
                            viewportBottom - confirmDelete.frame.maxY
                        )
                    )
                )
            )
            let fallbackMinimumShift = max(
                viewportTop - deleteMessage.frame.minY,
                max(
                    viewportTop - cancelDelete.frame.minY,
                    viewportTop - confirmDelete.frame.minY
                )
            )
            let fallbackMaximumShift = min(
                viewportTop - siteLabel.frame.maxY,
                min(
                    viewportTop - deleteScreen.frame.maxY,
                    min(
                        viewportBottom - deleteMessage.frame.maxY,
                        min(
                            viewportBottom - cancelDelete.frame.maxY,
                            viewportBottom - confirmDelete.frame.maxY
                        )
                    )
                )
            )
            let preferredContainsZero = preferredMinimumShift <= 0
                && preferredMaximumShift >= 0
            let fallbackContainsZero = fallbackMinimumShift <= 0
                && fallbackMaximumShift >= 0
            if preferredContainsZero || fallbackContainsZero { break }

            var targetDistance: CGFloat?
            if preferredMinimumShift <= preferredMaximumShift {
                let farPreferredDistance = preferredMaximumShift < 0
                    ? preferredMinimumShift
                    : preferredMaximumShift
                if abs(farPreferredDistance) >= 44 {
                    targetDistance = farPreferredDistance
                }
            }
            if targetDistance == nil,
               fallbackMinimumShift <= fallbackMaximumShift {
                let farFallbackDistance = fallbackMaximumShift < 0
                    ? fallbackMinimumShift
                    : fallbackMaximumShift
                if abs(farFallbackDistance) >= 44 {
                    targetDistance = farFallbackDistance
                }
            }
            guard let targetDistance else {
                XCTFail(
                    "Delete confirmation has no feasible recognized positioning gesture"
                )
                return
            }
            let dragInset: CGFloat = 24
            let maximumGestureDistance = viewportBottom
                - viewportTop
                - 2 * dragInset
            guard maximumGestureDistance >= 44 else {
                XCTFail(
                    "Delete confirmation viewport cannot fit a recognized gesture"
                )
                return
            }
            let dragDistance = targetDistance > 0
                ? min(targetDistance, maximumGestureDistance)
                : max(targetDistance, -maximumGestureDistance)
            guard abs(dragDistance) >= 44 else {
                XCTFail(
                    "Delete confirmation viewport cannot fit a recognized gesture"
                )
                return
            }
            let scrollOrigin = detail.coordinate(
                withNormalizedOffset: CGVector(dx: 0, dy: 0)
            )
            let dragStartOffsetY = targetDistance > 0
                ? dragInset
                : detail.frame.height - dragInset
            let dragStart = scrollOrigin.withOffset(
                CGVector(dx: detail.frame.width / 2, dy: dragStartOffsetY)
            )
            let dragEnd = scrollOrigin.withOffset(
                CGVector(
                    dx: detail.frame.width / 2,
                    dy: dragStartOffsetY + dragDistance
                )
            )
            dragStart.press(
                forDuration: 0.2,
                thenDragTo: dragEnd,
                withVelocity: .slow,
                thenHoldForDuration: 0.2
            )
        }
        let viewportTop = detail.frame.minY
        let viewportBottom = detail.frame.maxY
        let preferredComposition = siteLabel.frame.maxY <= viewportTop
            && deleteScreen.frame.minY >= viewportTop
            && deleteScreen.frame.maxY <= viewportBottom
            && deleteMessage.frame.minY >= viewportTop
            && deleteMessage.frame.maxY <= viewportBottom
            && cancelDelete.frame.minY >= viewportTop
            && cancelDelete.frame.maxY <= viewportBottom
            && confirmDelete.frame.minY >= viewportTop
            && confirmDelete.frame.maxY <= viewportBottom
            && cancelDelete.isHittable
            && confirmDelete.isHittable
        let fallbackComposition = siteLabel.frame.maxY <= viewportTop
            && deleteScreen.frame.maxY <= viewportTop
            && deleteMessage.frame.minY >= viewportTop
            && deleteMessage.frame.maxY <= viewportBottom
            && cancelDelete.frame.minY >= viewportTop
            && cancelDelete.frame.maxY <= viewportBottom
            && confirmDelete.frame.minY >= viewportTop
            && confirmDelete.frame.maxY <= viewportBottom
            && cancelDelete.isHittable
            && confirmDelete.isHittable
        XCTAssertTrue(preferredComposition || fallbackComposition)
        guard preferredComposition || fallbackComposition else { return }
        }
        captureBaseline(deleteConfirmationStateID, in: app)
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
        assertUnidentifiedLocalizedLabel("Information: Ready for night check", in: app)
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
        assertLocalizedValue(visible, equals: "Not selected")
        let visiblePriorValue = (visible.value as? String) ?? ""
        visible.tap()
        waitForLocalizedSelection(
            visible,
            changedFrom: visiblePriorValue,
            selectedReleaseValue: "Selected",
            timeout: 10
        )

        let issue = element("s3.outcome.issue.dark_section", in: app)
        scroll(issue, in: app)
        assertControl(issue, label: "Section appears dark")
        let issuePriorValue = (issue.value as? String) ?? ""
        issue.tap()
        waitForLocalizedSelection(
            issue,
            changedFrom: issuePriorValue,
            selectedReleaseValue: "Selected",
            timeout: 10
        )
        captureBaseline("state.check-outcome.visible-issue", in: app)

        let continueButton = element("s3.outcome.continue", in: app)
        scroll(continueButton, in: app)
        assertControl(continueButton, label: "Continue")
        continueButton.tap()

        XCTAssertTrue(element("s3.review.screen", in: app)
            .waitForExistence(timeout: 20))
        let reviewOutcome = element("s3.review.outcome", in: app)
        XCTAssertTrue(reviewOutcome.waitForExistence(timeout: 10))
        assertLocalizedLabelContains(reviewOutcome, "Visible issue")
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
        assertUnidentifiedLocalizedLabel("Complete: Check complete", in: app)
        let saved = element("s3.receipt.saved", in: app)
        XCTAssertTrue(saved.waitForExistence(timeout: 15))
        assertLocalizedLabel(saved, equals: "Report saved on this device.")
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
        XCTAssertEqual(shell.value as? String, effectiveAppearanceName(fallback: "Dark"))
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
        assertLocalizedLabel(validation, equals: "Short description")
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
        scroll(workPreview, in: app)
        XCTAssertTrue(workPreview.isHittable)
        let dateLabel = app.staticTexts["Date"].firstMatch
        for _ in 0..<4 {
            if !dateLabel.exists || dateLabel.frame.maxY <= app.frame.minY {
                break
            }
            app.swipeUp()
        }
        XCTAssertTrue(!dateLabel.exists || dateLabel.frame.maxY <= app.frame.minY)
        XCTAssertTrue(workPreview.isHittable)
        captureBaseline("state.work.editing", in: app)

        scroll(saveWork, in: app)
        assertControl(saveWork, label: "Record work")
        saveWork.tap()
        let progress = element("s5.1.work.saving", in: app)
        XCTAssertTrue(progress.waitForExistence(timeout: 10))
        assertLocalizedLabel(progress, equals: "Record work")
        captureBaseline("state.work.saving", in: app)

        let issueScreen = element("s5.1.issue.screen", in: app)
        XCTAssertTrue(issueScreen.waitForExistence(timeout: 40))
        let dueStatus = element("s5.1.issue.status", in: app)
        XCTAssertTrue(dueStatus.waitForExistence(timeout: 10))
        assertLocalizedLabel(dueStatus, equals: "Attention: Recheck due")
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
        assertLocalizedValue(resolved, equals: "Not selected")
        let resolvedPriorValue = (resolved.value as? String) ?? ""
        resolved.tap()
        waitForLocalizedSelection(
            resolved,
            changedFrom: resolvedPriorValue,
            selectedReleaseValue: "Selected",
            timeout: 10
        )
        captureBaseline("state.recheck-outcome.resolved", in: app)

        let continueButton = element("s3.outcome.continue", in: app)
        scroll(continueButton, in: app)
        assertControl(continueButton, label: "Continue")
        continueButton.tap()

        XCTAssertTrue(element("s3.review.screen", in: app)
            .waitForExistence(timeout: 20))
        let reviewOutcome = element("s3.review.outcome", in: app)
        XCTAssertTrue(reviewOutcome.waitForExistence(timeout: 10))
        assertLocalizedLabelContains(reviewOutcome, "Resolved")
        captureBaseline("state.recheck-review.resolved", in: app)
        let save = element("s3.review.save-report", in: app)
        scroll(save, in: app)
        assertControl(save, label: "Save and finish")
        save.tap()

        XCTAssertTrue(element("s3.receipt.screen", in: app)
            .waitForExistence(timeout: 40))
        let saved = element("s3.receipt.saved", in: app)
        XCTAssertTrue(saved.waitForExistence(timeout: 15))
        assertLocalizedLabel(saved, equals: "Report saved on this device.")
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
        assertLocalizedLabel(resolvedStatus, equals: "Complete: Resolved")
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
        waitForLocalizedLabel(
            closeHeading,
            equals: "2 of 2 · Close view",
            timeout: 20
        )
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
        waitForLocalizedLabel(headingElement, equals: heading, timeout: 20)
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
        assertLocalizedLabel(couldNotVerify, equals: "Could not verify")
        let reason = element(
            "s3.outcome.cnv.reason.conditions_changed",
            in: app
        )
        scroll(reason, in: app)
        assertControl(reason, label: "Conditions changed")
        let reasonPriorValue = (reason.value as? String) ?? ""
        reason.tap()
        waitForLocalizedSelection(
            reason,
            changedFrom: reasonPriorValue,
            selectedReleaseValue: "Selected",
            timeout: 10
        )
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
                let navigationBottom = app.navigationBars.firstMatch.frame.maxY
                let outcomeScreen = element("s3.outcome.screen", in: app)
                let viewportBottom = outcomeScreen.frame.maxY
                let resolved = element("s5.2.outcome.resolved", in: app)
                let issueStillVisible = element(
                    "s5.2.outcome.issue-still-visible",
                    in: app
                )
                for _ in 0..<6 {
                    let minimumShift = max(
                        navigationBottom - issueStillVisible.frame.minY,
                        navigationBottom - value.frame.minY
                    )
                    let maximumShift = min(
                        navigationBottom - resolved.frame.maxY,
                        viewportBottom - label.frame.maxY
                    )
                    if minimumShift <= 0, maximumShift >= 0 {
                        break
                    }
                    XCTAssertLessThanOrEqual(minimumShift, maximumShift)
                    let dragDistance = minimumShift > 0 ? maximumShift : minimumShift
                    let dragStart = outcomeScreen.coordinate(
                        withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
                    )
                    let dragEnd = dragStart.withOffset(
                        CGVector(dx: 0, dy: dragDistance)
                    )
                    dragStart.press(
                        forDuration: 0.2,
                        thenDragTo: dragEnd,
                        withVelocity: .slow,
                        thenHoldForDuration: 0.2
                    )
                }
                XCTAssertLessThanOrEqual(resolved.frame.maxY, navigationBottom)
                XCTAssertGreaterThanOrEqual(
                    issueStillVisible.frame.minY,
                    navigationBottom
                )
                XCTAssertGreaterThanOrEqual(value.frame.minY, navigationBottom)
                XCTAssertLessThanOrEqual(label.frame.maxY, viewportBottom)
                XCTAssertTrue(value.isHittable)
                XCTAssertTrue(label.isHittable)
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
            assertLocalizedLabel(saved, equals: "Report saved on this device.")
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
        waitForLocalizedLabel(
            freshHeader,
            equals: "Visible physical damage",
            timeout: 20
        )
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
        assertLocalizedLabelContains(validation, "Change the note before saving.")
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
        let copyAddress = element("s8.4.feedback.copy-address", in: app)
        XCTAssertTrue(copyAddress.exists)
        scroll(copyAddress, in: app)
        let saveDiagnostics = element("s8.4.feedback.save-diagnostics", in: app)
        XCTAssertTrue(saveDiagnostics.exists)
        let appMetadata = app.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH %@", "App "))
            .firstMatch
        let navigationBar = app.navigationBars.firstMatch
        let signsTab = element("s1.tab.signs", in: app)
        XCTAssertTrue(appMetadata.waitForExistence(timeout: 5))
        XCTAssertTrue(navigationBar.exists)
        XCTAssertTrue(signsTab.exists)
        let topClearance: CGFloat = 24
        let bottomClearance: CGFloat = 16
        var measuredUndertravel: CGFloat = 0
        var compensatedDirection: CGFloat = 0
        for _ in 0..<4 {
            let minimumShift = navigationBar.frame.maxY
                + topClearance
                - appMetadata.frame.minY
            let maximumShift = signsTab.frame.minY
                - bottomClearance
                - saveDiagnostics.frame.maxY
            XCTAssertGreaterThanOrEqual(maximumShift, minimumShift)
            if minimumShift <= 0, maximumShift >= 0 { break }
            let targetDistance = minimumShift > 0
                ? maximumShift
                : minimumShift
            let direction: CGFloat = targetDistance > 0 ? 1 : -1
            if compensatedDirection != direction {
                measuredUndertravel = 0
            }
            let dragDistance = targetDistance
                + direction * measuredUndertravel
            let metadataBeforeDrag = appMetadata.frame.minY
            let dragStart = app.coordinate(
                withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)
            )
            let dragEnd = dragStart.withOffset(
                CGVector(dx: 0, dy: dragDistance)
            )
            dragStart.press(
                forDuration: 0.2,
                thenDragTo: dragEnd,
                withVelocity: .slow,
                thenHoldForDuration: 0.2
            )
            let actualDistance = appMetadata.frame.minY - metadataBeforeDrag
            measuredUndertravel = actualDistance * direction > 0
                ? max(0, abs(dragDistance) - abs(actualDistance))
                : abs(dragDistance)
            compensatedDirection = direction
        }
        XCTAssertGreaterThanOrEqual(
            appMetadata.frame.minY,
            navigationBar.frame.maxY + topClearance
        )
        XCTAssertLessThanOrEqual(
            saveDiagnostics.frame.maxY,
            signsTab.frame.minY - bottomClearance
        )
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
        assertLocalizedLabelContains(renewal, "$59.99")
        let noSync = element("s7.2.paywall.no-sync", in: app)
        scroll(noSync, in: app)
        assertLocalizedLabelContains(noSync, "do not sync")

        let store = element("s7.2.paywall.store", in: app)
        XCTAssertTrue(store.waitForExistence(timeout: 30))
        if usesPseudolanguage {
            XCTAssertTrue(wait(for: store, predicate: "enabled == true", timeout: 20))
            assertLocalizedValue(store, equals: "Ready")
        } else {
            XCTAssertTrue(wait(for: store, predicate: "value == 'Ready'", timeout: 20))
        }
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
        waitForLocalizedLabel(
            purchaseState,
            containing: "Purchase verified. Subscription access is ready.",
            timeout: 45
        )
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
        waitForLocalizedLabel(
            restored,
            containing: "Purchases restored. Subscription access is updated.",
            timeout: 45
        )
        let activeStatus = element("s7.3.lifecycle.status-title", in: app)
        if usesPseudolanguage {
            XCTAssertTrue(activeStatus.waitForExistence(timeout: 20))
            assertLocalizedLabelContains(activeStatus, "Active until")
        } else {
            XCTAssertTrue(wait(
                for: activeStatus,
                predicate: "label BEGINSWITH %@",
                argument: "Active until",
                timeout: 20
            ))
        }
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
        waitForLocalizedLabel(
            element("s7.3.lifecycle.status-title", in: app),
            equals: "No subscription found",
            timeout: 20
        )
        captureBaseline("state.subscription.no-entitlement", in: app)
        assertMigrationStateCoverage()
        emitAutomatedLabAccessibilityRowsIfNeeded()

        let terminal = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        terminal.name = automationShard.map {
            "S10.4 terminal \($0.shardID) migrated no-entitlement"
        } ?? "S10.3 terminal migrated no-entitlement at XXXL Dark"
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
        let diagnosticsHeading = element("s8.3.diagnostics.heading", in: app)
        let diagnosticsAuthority = element("s8.3.diagnostics.authority", in: app)
        let diagnosticsExport = element("s8.3.diagnostics.export", in: app)
        let navigationBar = app.navigationBars.firstMatch
        let signsTab = element("s1.tab.signs", in: app)
        XCTAssertTrue(diagnosticsHeading.waitForExistence(timeout: 10))
        XCTAssertTrue(diagnosticsAuthority.waitForExistence(timeout: 10))
        XCTAssertTrue(diagnosticsExport.waitForExistence(timeout: 10))
        XCTAssertTrue(navigationBar.exists)
        XCTAssertTrue(signsTab.exists)
        let topClearance: CGFloat = 12
        let bottomClearance: CGFloat = 16
        var measuredUndertravel: CGFloat = 0
        var compensatedDirection: CGFloat = 0
        for _ in 0..<4 {
            let minimumShift = navigationBar.frame.maxY
                + topClearance
                - diagnosticsAuthority.frame.minY
            let maximumShift = min(
                navigationBar.frame.maxY - diagnosticsHeading.frame.maxY,
                signsTab.frame.minY
                    - bottomClearance
                    - diagnosticsExport.frame.maxY
            )
            XCTAssertGreaterThanOrEqual(maximumShift, minimumShift)
            if minimumShift <= 0, maximumShift >= 0 { break }
            let targetDistance = minimumShift > 0
                ? maximumShift
                : minimumShift
            let direction: CGFloat = targetDistance > 0 ? 1 : -1
            if compensatedDirection != direction {
                measuredUndertravel = 0
            }
            let dragDistance = targetDistance
                + direction * measuredUndertravel
            let authorityBeforeDrag = diagnosticsAuthority.frame.minY
            let dragStart = app.coordinate(
                withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)
            )
            let dragEnd = dragStart.withOffset(
                CGVector(dx: 0, dy: dragDistance)
            )
            dragStart.press(
                forDuration: 0.2,
                thenDragTo: dragEnd,
                withVelocity: .slow,
                thenHoldForDuration: 0.2
            )
            let actualDistance = diagnosticsAuthority.frame.minY
                - authorityBeforeDrag
            measuredUndertravel = actualDistance * direction > 0
                ? max(0, abs(dragDistance) - abs(actualDistance))
                : abs(dragDistance)
            compensatedDirection = direction
        }
        XCTAssertLessThanOrEqual(
            diagnosticsHeading.frame.maxY,
            navigationBar.frame.maxY
        )
        XCTAssertGreaterThanOrEqual(
            diagnosticsAuthority.frame.minY,
            navigationBar.frame.maxY + topClearance
        )
        XCTAssertLessThanOrEqual(
            diagnosticsExport.frame.maxY,
            signsTab.frame.minY - bottomClearance
        )
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
        waitForLocalizedLabel(headingElement, equals: heading, timeout: 20)

        let importPhoto = element("s3.capture.import-fixture", in: app)
        scroll(importPhoto, in: app)
        assertControl(importPhoto, label: "Import test photo")
        importPhoto.tap()

        if capturesLowStorageFailure {
            assertUnidentifiedLocalizedLabel(
                "Free space is too low. Free space, then try again.",
                in: app,
                timeout: 15
            )
            XCTAssertFalse(element("s3.capture.preview", in: app).exists)
            captureBaseline("state.capture.low-storage-error", in: app)
            importPhoto.tap()
        }

        let preview = element("s3.capture.preview", in: app)
        XCTAssertTrue(preview.waitForExistence(timeout: 20))
        assertLocalizedLabel(preview, equals: "Imported photo preview")
        captureBaseline(stateID, in: app)
        let usePhoto = element("s3.capture.use-photo", in: app)
        scroll(usePhoto, in: app)
        assertControl(usePhoto, label: "Use Photo")
        let durableAdvanceAt = Date()
        usePhoto.tap()
        if heading.contains("Wide") {
            waitForLocalizedLabel(
                headingElement,
                equals: "2 of 2 · Close view",
                timeout: 30
            )
        } else if stateID.contains("recheck") {
            XCTAssertTrue(element("s3.outcome.screen", in: app)
                .waitForExistence(timeout: 30))
            let resolved = element("s5.2.outcome.resolved", in: app)
            scroll(resolved, in: app)
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
        assertLocalizedLabel(settings, equals: "Open Settings")
        assertUnidentifiedLocalizedLabel(
            "Choose a photo, open Settings, or leave this check incomplete and return later.",
            in: app
        )
        captureBaseline("state.capture.camera-denied", in: app)

        let cannotComplete = element("s3.capture.cannot-complete", in: app)
        scroll(cannotComplete, in: app)
        assertControl(cannotComplete, label: "Cannot complete")
        cannotComplete.tap()

        XCTAssertTrue(element("s3.outcome.screen", in: app)
            .waitForExistence(timeout: 20))
        let couldNotVerify = element("s3.outcome.could-not-verify", in: app)
        XCTAssertTrue(couldNotVerify.waitForExistence(timeout: 10))
        assertLocalizedValue(couldNotVerify, equals: "Selected")

        app.terminate()
        app.launch()
        XCTAssertTrue(element("s3.capture.screen", in: app)
            .waitForExistence(timeout: 30))
        let heading = element("s3.capture.heading", in: app)
        waitForLocalizedLabel(
            heading,
            equals: "1 of 2 · Wide view",
            timeout: 20
        )
    }

    @MainActor
    private func recoverInjectedPDFFailureAtXXXL(in app: XCUIApplication) {
        let failure = element("s4.pdf-failure.screen", in: app)
        XCTAssertTrue(failure.waitForExistence(timeout: 30))
        let headline = element("s4.pdf-failure.headline", in: app)
        XCTAssertTrue(headline.waitForExistence(timeout: 10))
        assertLocalizedLabel(
            headline,
            equals: "This report was saved, but its PDF is not available."
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

        guard let shard = automationShard else { return }
        dismissHostedAppleIntelligenceNotificationIfPresent(
            in: app,
            file: file,
            line: line
        )
        do {
            let eligibleExceptions = Self.contrastAuditExceptionSignatures.filter {
                $0.shardID == shard.shardID && $0.stateID == stateID
            }
            guard eligibleExceptions.count <= 1 else {
                throw AutomationConfigurationError.invalid(
                    "S10.4 contrast exception eligibility is ambiguous"
                )
            }

            var matchedException: ContrastAuditExceptionSignature?
            if let signature = eligibleExceptions.first {
                var observedIssueCount = 0
                try app.performAccessibilityAudit(for: .contrast) { issue in
                    observedIssueCount += 1
                    guard observedIssueCount == 1,
                          self.isActive(signature),
                          let auditedElement = issue.element,
                          String(issue.auditType.rawValue) == signature.auditTypeRawValue,
                          issue.compactDescription == signature.compactDescription,
                          issue.detailedDescription == signature.detailedDescription,
                          auditedElement.identifier == signature.elementIdentifier,
                          auditedElement.label == signature.elementLabel,
                          String(describing: auditedElement.elementType)
                            == signature.elementTypeDescription,
                          auditedElement.frame == signature.elementFrame,
                          app.frame == signature.applicationFrame else {
                        return false
                    }
                    matchedException = signature
                    return true
                }
                guard observedIssueCount <= 1 else {
                    throw AutomationConfigurationError.invalid(
                        "S10.4 contrast exception encountered more than one audit issue"
                    )
                }
            } else {
                try app.performAccessibilityAudit(for: .contrast)
            }
            if let matchedException {
                automationContrastExceptions[stateID] = matchedException
            }
            let axTreeDigest = try accessibilityTreeDigest(in: app)
            automationAXTreeDigests[stateID] = axTreeDigest

            let axEvidenceID = "s10.4-ax-\(shard.shardID)-\(stateID)"
            printJSONLine(prefix: "S10_4_AX_STATE", object: [
                "shardID": shard.shardID,
                "stateID": stateID,
                "requirementID": shard.requirementID,
                "deviceProfileID": shard.deviceProfileID,
                "result": "PASS",
                "evidenceID": axEvidenceID,
                "axTreeSHA256": axTreeDigest,
                "capture": "XCUIApplication.debugDescription",
            ])

            let contrastEvidenceID = "s10.4-contrast-\(shard.shardID)-\(stateID)"
            var contrastEvidence: [String: Any] = [
                "shardID": shard.shardID,
                "stateID": stateID,
                "requirementID": shard.requirementID,
                "deviceProfileID": shard.deviceProfileID,
                "result": matchedException == nil ? "PASS" : "EXCEPTION",
                "evidenceID": contrastEvidenceID,
                "axTreeSHA256": axTreeDigest,
                "audit": "XCUIAccessibilityAuditType.contrast",
                "exceptionIssueID": "",
                "exceptionOwner": "",
                "exceptionExpiresAt": "",
                "exceptionRationale": "",
                "ignoredAuditIssues": matchedException.map {
                    [self.publicAuditSignatureObject($0)]
                } ?? [],
            ]
            if let matchedException {
                contrastEvidence["exceptionIssueID"] = matchedException.issueID
                contrastEvidence["exceptionOwner"] = matchedException.owner
                contrastEvidence["exceptionExpiresAt"] = matchedException.expiresAt
                contrastEvidence["exceptionRationale"] = matchedException.rationale
            }
            printJSONLine(prefix: "S10_4_CONTRAST", object: contrastEvidence)

            let pngData = XCUIScreen.main.screenshot().pngRepresentation
            let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
            XCTAssertTrue(
                pngData.starts(with: pngSignature),
                file: file,
                line: line
            )
            let candidate = XCTAttachment(
                data: pngData,
                uniformTypeIdentifier: "public.data"
            )
            candidate.name = "S10.4 candidate \(shard.shardID) \(stateID)"
            candidate.lifetime = .keepAlways
            add(candidate)
        } catch {
            XCTFail(
                "S10.4 contrast/AX evidence failed closed for \(stateID): \(error)",
                file: file,
                line: line
            )
        }
    }

    private func isActive(_ signature: ContrastAuditExceptionSignature) -> Bool {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        guard formatter.string(from: Date()) <= signature.expiresAt,
              formatter.date(from: signature.expiresAt) != nil else {
            return false
        }
        return true
    }

    private func publicAuditSignatureObject(
        _ signature: ContrastAuditExceptionSignature
    ) -> [String: Any] {
        [
            "auditTypeRawValue": signature.auditTypeRawValue,
            "compactDescription": signature.compactDescription,
            "detailedDescription": signature.detailedDescription,
            "elementIdentifier": signature.elementIdentifier,
            "elementLabel": signature.elementLabel,
            "elementType": signature.elementTypeDescription,
            "elementFrame": auditFrameObject(signature.elementFrame),
            "applicationFrame": auditFrameObject(signature.applicationFrame),
        ]
    }

    private func auditFrameObject(_ frame: CGRect) -> [String: Double] {
        [
            "x": Double(frame.origin.x),
            "y": Double(frame.origin.y),
            "width": Double(frame.size.width),
            "height": Double(frame.size.height),
        ]
    }

    @MainActor
    private func dismissHostedAppleIntelligenceNotificationIfPresent(
        in app: XCUIApplication,
        file: StaticString,
        line: UInt
    ) {
        let notificationTitle = "Ready for Apple Intelligence"
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let notification = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", notificationTitle))
            .firstMatch
        guard notification.exists else { return }

        let dismissalTarget = springboard.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.01)
        )
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
            .press(forDuration: 0.05, thenDragTo: dismissalTarget)
        XCTAssertTrue(
            notification.waitForNonExistence(timeout: 5),
            "The exact hosted Apple Intelligence notification did not dismiss",
            file: file,
            line: line
        )
        XCTAssertTrue(app.state == .runningForeground, file: file, line: line)
    }

    @MainActor
    private func accessibilityTreeDigest(in app: XCUIApplication) throws -> String {
        let stableElement = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier != ''"))
            .firstMatch
        guard stableElement.exists, !stableElement.identifier.isEmpty else {
            throw AutomationConfigurationError.invalid(
                "The state accessibility tree contains no stable identifiers"
            )
        }
        let tree = app.debugDescription
        guard !tree.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              tree.contains(stableElement.identifier) else {
            throw AutomationConfigurationError.invalid(
                "The raw accessibility tree is empty or omits its stable sentinel"
            )
        }
        return SHA256.hash(data: Data(tree.utf8))
            .map { String(format: "%02X", $0) }
            .joined()
    }

    private func printJSONLine(prefix: String, object: [String: Any]) {
        do {
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            guard let value = String(data: data, encoding: .utf8), !value.contains("\n") else {
                XCTFail("\(prefix) evidence did not encode as one UTF-8 JSON line")
                return
            }
            print("\(prefix) \(value)")
        } catch {
            XCTFail("\(prefix) evidence JSON encoding failed: \(error)")
        }
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

    private func emitAutomatedLabAccessibilityRowsIfNeeded(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let shard = automationShard else { return }
        XCTAssertEqual(automationAXTreeDigests.count, 67, file: file, line: line)
        XCTAssertEqual(
            Set(automationAXTreeDigests.keys),
            Set(migratedStateIDs),
            "Every captured candidate state must have one AX-tree digest",
            file: file,
            line: line
        )
        if usesPseudolanguage {
            XCTAssertTrue(
                pseudoLabelSentinelValidated,
                "The pseudolanguage must transform at least one stable-ID label",
                file: file,
                line: line
            )
        }

        XCTAssertEqual(Self.commonTaskStateIDs.count, 6, file: file, line: line)
        for task in Self.commonTaskStateIDs {
            let sortedStateIDs = task.stateIDs.sorted()
            XCTAssertEqual(
                Set(sortedStateIDs).count,
                sortedStateIDs.count,
                "Common-task state IDs must be unique for \(task.taskID)",
                file: file,
                line: line
            )
            let stateEvidence = sortedStateIDs.map { stateID in
                let digest = automationAXTreeDigests[stateID] ?? ""
                XCTAssertFalse(
                    digest.isEmpty,
                    "Missing AX-tree digest for \(task.taskID) state \(stateID)",
                    file: file,
                    line: line
                )
                return ["stateID": stateID, "axTreeSHA256": digest]
            }
            let canonicalEvidence = stateEvidence
                .map { "\($0["stateID"] ?? "")|\($0["axTreeSHA256"] ?? "")" }
                .joined(separator: "\n")
            let aggregateDigest = SHA256.hash(data: Data(canonicalEvidence.utf8))
                .map { String(format: "%02X", $0) }
                .joined()
            let stateSetDigest = SHA256.hash(
                data: Data(sortedStateIDs.joined(separator: "\n").utf8)
            )
                .map { String(format: "%02X", $0) }
                .joined()
            let axEvidenceID = "s10.4-ax-\(shard.shardID)-\(task.taskID)"
            let focusOrderEvidenceID =
                "s10.4-focus-order-\(shard.shardID)-\(task.taskID)"
            let targetSizeEvidenceID =
                "s10.4-target-size-\(shard.shardID)-\(task.taskID)"
            let contrastEvidenceID =
                "s10.4-contrast-\(shard.shardID)-\(task.taskID)"
            let taskExceptions = automationContrastExceptions.values
                .filter { $0.taskID == task.taskID }
                .sorted { $0.stateID < $1.stateID }
            let allowsTwoTaskExceptions =
                shard.shardID == "s10.4.current.ax-text"
                && task.taskID == "one_handed_start"
            let taskExceptionLimit = allowsTwoTaskExceptions ? 2 : 1
            guard taskExceptions.count <= taskExceptionLimit else {
                XCTFail(
                    "A common task exceeded its exact contrast exception limit",
                    file: file,
                    line: line
                )
                return
            }
            let exceptionStateIDs = taskExceptions.map(\.stateID)
            let exceptionIssueIDs = taskExceptions.map(\.issueID)
            let expectedUniqueMetadataCount = taskExceptions.isEmpty ? 0 : 1
            guard Set(exceptionStateIDs).count == exceptionStateIDs.count,
                  Set(exceptionIssueIDs).count == exceptionIssueIDs.count,
                  Set(taskExceptions.map(\.owner)).count
                    == expectedUniqueMetadataCount,
                  Set(taskExceptions.map(\.expiresAt)).count
                    == expectedUniqueMetadataCount,
                  taskExceptions.allSatisfy({ task.stateIDs.contains($0.stateID) }),
                  taskExceptions.allSatisfy({ isActive($0) }),
                  taskExceptions.allSatisfy({
                      !(automationAXTreeDigests[$0.stateID] ?? "").isEmpty
                  }) else {
                XCTFail(
                    "A common task has ambiguous, expired, or missing contrast exception evidence",
                    file: file,
                    line: line
                )
                return
            }
            var automatedEvidenceIDs = [
                axEvidenceID,
                focusOrderEvidenceID,
                targetSizeEvidenceID,
                contrastEvidenceID,
            ]
            automatedEvidenceIDs.append(contentsOf: exceptionStateIDs.map {
                "s10.4-contrast-\(shard.shardID)-\($0)"
            })

            var taskEvidence: [String: Any] = [
                "taskID": task.taskID,
                "shardID": shard.shardID,
                "deviceProfileID": shard.deviceProfileID,
                "feature": shard.accessibilityFeature,
                "automatedStatus": taskExceptions.isEmpty ? "PASS" : "EXCEPTION",
                "automatedReviewer": "FieldEvidenceAppUITests/S10_4AutomatedBrandLabUITests",
                "exceptionIssueID": "",
                "exceptionOwner": "",
                "exceptionExpiresAt": "",
                "exceptionRationale": "",
                "exceptionStateIDs": [String](),
                "rationale": "All task states produced AX-tree, focus-order, target-size, and strict Apple contrast evidence.",
                "evidenceID": axEvidenceID,
                "focusOrderEvidenceID": focusOrderEvidenceID,
                "targetSizeEvidenceID": targetSizeEvidenceID,
                "contrastEvidenceID": contrastEvidenceID,
                "automatedEvidenceIDs": automatedEvidenceIDs,
                "stateCount": stateEvidence.count,
                "stateSetSHA256": stateSetDigest,
                "aggregateAXTreeSHA256": aggregateDigest,
                "stateAXTreeDigests": stateEvidence,
            ]
            if let firstTaskException = taskExceptions.first {
                taskEvidence["exceptionIssueID"] = exceptionIssueIDs.joined(
                    separator: " | "
                )
                taskEvidence["exceptionOwner"] = firstTaskException.owner
                taskEvidence["exceptionExpiresAt"] = firstTaskException.expiresAt
                taskEvidence["exceptionRationale"] = taskExceptions
                    .map(\.rationale)
                    .joined(separator: " | ")
                taskEvidence["exceptionStateIDs"] = exceptionStateIDs
                taskEvidence["rationale"] = taskExceptions.count == 1
                    ? "All task states produced AX-tree, focus-order, and target-size evidence; the sole Apple contrast issue is bound to the named, expiring exception."
                    : "All task states produced AX-tree, focus-order, and target-size evidence; the exact Apple contrast issues are bound to the named, expiring exceptions."
            }
            printJSONLine(prefix: "S10_4_AX", object: taskEvidence)
        }
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
        if let shard = automationShard {
            applyDeviceAppearance(fallbackIsDark: false)
            let effectiveAppearance = shard.appearance == "dark" ? "Dark" : "Light"
            let effectiveAppearanceFlag = shard.appearance == "dark"
                ? "--s1-ui-test-dark-mode"
                : "--s1-ui-test-light-mode"
            app.launchArguments = [
                "-AppleInterfaceStyle", effectiveAppearance,
                effectiveAppearanceFlag,
                "--s3-2-ui-test-imported-fixtures",
                "--s7-2-ui-test-paywall",
                "-UIPreferredContentSizeCategoryName", shard.contentSizeCategory,
                "-UIAccessibilityDarkerSystemColorsEnabled",
                shard.contrast == "increased" ? "YES" : "NO",
                "-UIAccessibilityDifferentiateWithoutColor",
                shard.differentiateWithoutColor ? "YES" : "NO",
                "-UIAccessibilityReduceMotionEnabled",
                shard.reduceMotion ? "YES" : "NO",
                "-UIAccessibilityReduceTransparencyEnabled",
                shard.reduceTransparency ? "YES" : "NO",
            ]
            app.launchArguments += localizationArguments(for: shard)
            return
        }

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

    private func localizationArguments(for shard: AutomationShard) -> [String] {
        let language = shard.layoutDirection == "right_to_left" ? "ar" : "en"
        let locale = shard.layoutDirection == "right_to_left" ? "ar" : "en_US"
        var arguments = [
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", locale,
            "-AppleTextDirection",
            shard.layoutDirection == "right_to_left" ? "YES" : "NO",
        ]
        switch shard.locale {
        case "en-US-release", "ar-RTL":
            break
        case "en-US-double-length":
            arguments += ["-NSDoubleLocalizedStrings", "YES"]
        case "ar-RTL-string":
            arguments += ["-NSForceRightToLeftLocalizedStrings", "YES"]
        case "en-US-tall":
            arguments += ["-NSTallLocalizedStrings", "YES"]
        case "en-US-accented":
            arguments += ["-NSAccentuateLocalizedStrings", "YES"]
        case "en-US-bounded":
            arguments += ["-NSSurroundLocalizedStrings", "YES"]
        default:
            XCTFail("Unhandled frozen locale profile \(shard.locale)")
        }
        return arguments
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
        assertLocalizedLabel(value, equals: expected)
    }

    private var usesPseudolanguage: Bool {
        guard let shard = automationShard else { return false }
        return shard.locale != "en-US-release"
    }

    @MainActor
    private func assertUnidentifiedLocalizedLabel(
        _ releaseLabel: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard usesPseudolanguage else {
            XCTAssertTrue(
                labelledElement(releaseLabel, in: app).waitForExistence(timeout: timeout),
                file: file,
                line: line
            )
            return
        }
        XCTAssertTrue(
            pseudoLabelSentinelValidated,
            "A stable-ID label must prove the active pseudolanguage before querying an unidentified label",
            file: file,
            line: line
        )
        XCTAssertTrue(
            app.descendants(matching: .any).allElementsBoundByIndex.contains {
                !$0.identifier.isEmpty
                    && !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            },
            file: file,
            line: line
        )
    }

    @MainActor
    private func assertLocalizedLabel(
        _ value: XCUIElement,
        equals expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(value.waitForExistence(timeout: 20), file: file, line: line)
        guard usesPseudolanguage else {
            XCTAssertEqual(value.label, expected, file: file, line: line)
            return
        }
        XCTAssertFalse(value.identifier.isEmpty, "Pseudo checks require a stable identifier", file: file, line: line)
        XCTAssertFalse(value.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, file: file, line: line)
        if value.label != expected {
            pseudoLabelSentinelValidated = true
        }
    }

    @MainActor
    private func assertLocalizedLabelContains(
        _ value: XCUIElement,
        _ expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(value.waitForExistence(timeout: 20), file: file, line: line)
        guard usesPseudolanguage else {
            XCTAssertTrue(value.label.contains(expected), file: file, line: line)
            return
        }
        XCTAssertFalse(value.identifier.isEmpty, "Pseudo checks require a stable identifier", file: file, line: line)
        XCTAssertFalse(value.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, file: file, line: line)
        if !value.label.contains(expected) {
            pseudoLabelSentinelValidated = true
        }
    }

    @MainActor
    private func waitForLocalizedLabel(
        _ value: XCUIElement,
        equals expected: String,
        timeout: TimeInterval,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if usesPseudolanguage {
            XCTAssertTrue(value.waitForExistence(timeout: timeout), file: file, line: line)
            assertLocalizedLabel(value, equals: expected, file: file, line: line)
        } else {
            XCTAssertTrue(wait(
                for: value,
                predicate: "label == %@",
                argument: expected,
                timeout: timeout
            ), file: file, line: line)
        }
    }

    @MainActor
    private func waitForLocalizedLabel(
        _ value: XCUIElement,
        containing expected: String,
        timeout: TimeInterval,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if usesPseudolanguage {
            XCTAssertTrue(value.waitForExistence(timeout: timeout), file: file, line: line)
            assertLocalizedLabelContains(value, expected, file: file, line: line)
        } else {
            XCTAssertTrue(wait(
                for: value,
                predicate: "label CONTAINS %@",
                argument: expected,
                timeout: timeout
            ), file: file, line: line)
        }
    }

    @MainActor
    private func assertLocalizedValue(
        _ value: XCUIElement,
        equals expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let observed = (value.value as? String) ?? ""
        guard usesPseudolanguage else {
            XCTAssertEqual(observed, expected, file: file, line: line)
            return
        }
        XCTAssertFalse(value.identifier.isEmpty, file: file, line: line)
        XCTAssertFalse(observed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, file: file, line: line)
        if observed != expected {
            pseudoLabelSentinelValidated = true
        }
    }

    @MainActor
    private func waitForLocalizedSelection(
        _ value: XCUIElement,
        changedFrom priorValue: String,
        selectedReleaseValue: String,
        timeout: TimeInterval,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if usesPseudolanguage {
            XCTAssertTrue(wait(
                for: value,
                predicate: "value != %@ AND value != ''",
                argument: priorValue,
                timeout: timeout
            ), file: file, line: line)
            assertLocalizedValue(value, equals: selectedReleaseValue, file: file, line: line)
        } else {
            XCTAssertEqual(selectedReleaseValue, "Selected", file: file, line: line)
            XCTAssertTrue(wait(
                for: value,
                predicate: "value == 'Selected'",
                timeout: timeout
            ), file: file, line: line)
        }
    }

    @MainActor
    private func firstPurchaseButton(in app: XCUIApplication) -> XCUIElement {
        if usesPseudolanguage {
            let store = element("s7.2.paywall.store", in: app)
            XCTAssertTrue(store.waitForExistence(timeout: 30))
            let scopedButtons = store.descendants(matching: .button)
            for index in 0..<scopedButtons.count {
                let candidate = scopedButtons.element(boundBy: index)
                if candidate.identifier != "s7.2.paywall.close",
                   candidate.isEnabled,
                   candidate.isHittable,
                   !candidate.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return candidate
                }
            }
            XCTFail("The pseudolocalized StoreKit view has no enabled labelled purchase button")
            return scopedButtons.firstMatch
        }

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
        assertLocalizedLabel(control, equals: label, file: file, line: line)
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
        assertLocalizedLabel(status, equals: "Attention: Recheck due", file: file, line: line)
        assertLocalizedLabel(header, equals: "Section appears dark", file: file, line: line)
        XCTAssertEqual(header.elementType, .staticText, file: file, line: line)
        assertLocalizedLabel(action, equals: "Start recheck", file: file, line: line)
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

final class S10_3BrandMigrationUITests: S10BrandMigrationRouteUITestCase {
    @MainActor
    func testAllFrozenReleasedStatesUseTheBrandSystemWithoutBehaviorDrift() throws {
        try runAllFrozenReleasedStatesUseTheBrandSystemWithoutBehaviorDrift()
    }
}

final class S10_4AutomatedBrandLabUITests: S10BrandMigrationRouteUITestCase {
    @MainActor
    func testAutomatedBrandLabShard() throws {
        try configureAutomatedBrandLabShardFromEnvironment()
        try runAllFrozenReleasedStatesUseTheBrandSystemWithoutBehaviorDrift()
    }
}

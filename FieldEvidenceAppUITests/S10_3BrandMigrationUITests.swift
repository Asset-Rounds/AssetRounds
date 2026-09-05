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

    private enum DiagnosticProbe: String {
        case minimumNewSign = "minimum-new-sign"
        case minimumPreflight = "minimum-preflight"

        static let environmentKeys: Set<String> = [
            "CI_S10_4_DIAGNOSTIC_PROBE_ID",
            "CI_S10_4_DIAGNOSTIC_EXECUTION_LANE",
            "CI_S10_4_DIAGNOSTIC_PROBE_TIMEOUT_SECONDS",
            "CI_S10_4_EXECUTION_LANE",
            "CI_S10_4_RUNNER_PROVIDER",
            "CI_S10_4_HEAD",
            "CI_S10_4_REF",
        ]
    }

    private enum FocusedDiagnosticProbeStop: Error {
        case completed
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

    private enum AutomationSegment: String {
        case none
        case segment1 = "segment-1"
        case segment2 = "segment-2"
        case segment3 = "segment-3"

        var replayCount: Int {
            switch self {
            case .none, .segment1: return 0
            case .segment2: return 22
            case .segment3: return 22
            }
        }

        var ownedStartOrdinal: Int {
            switch self {
            case .none, .segment1: return 1
            case .segment2: return 23
            case .segment3: return 51
            }
        }

        var ownedCount: Int {
            switch self {
            case .none: return 67
            case .segment1: return 22
            case .segment2: return 28
            case .segment3: return 17
            }
        }

        var finalOrdinal: Int {
            ownedStartOrdinal + ownedCount - 1
        }
    }

    private static let segmentedRouteStateIDs = [
        "state.pack.unavailable",
        "state.welcome.empty",
        "state.reports-index.empty",
        "state.sample-report.ready",
        "state.new-sign.editing",
        "state.new-sign.validation-error",
        "state.sign-detail.ready",
        "state.sign-detail.delete-confirmation",
        "state.check-preflight.ready",
        "state.capture.wide-ready",
        "state.capture.camera-denied",
        "state.capture.low-storage-error",
        "state.capture.wide-preview",
        "state.capture.close-ready",
        "state.capture.close-preview",
        "state.check-outcome.visible-issue",
        "state.check-review.visible-issue",
        "state.receipt.report-saved",
        "state.report-detail.ready",
        "state.report-history.ready",
        "state.reports-index.ready",
        "state.sign-detail.open-issue",
        "state.work.validation-error",
        "state.work.editing",
        "state.work.saving",
        "state.issue.recheck-due",
        "state.recheck-preflight.ready",
        "state.recheck-capture.wide-ready",
        "state.recheck-capture.wide-preview",
        "state.recheck-capture.close-ready",
        "state.recheck-capture.close-preview",
        "state.recheck-outcome.resolved",
        "state.recheck-review.resolved",
        "state.recheck-receipt.saved",
        "state.recheck-report-detail.ready",
        "state.issue.resolved",
        "state.check-outcome.no-visible-issue",
        "state.check-review.no-visible-issue",
        "state.paywall.available",
        "state.paywall.purchase-complete",
        "state.check-outcome.could-not-verify",
        "state.check-review.could-not-verify",
        "state.recheck-outcome.could-not-verify",
        "state.recheck-review.could-not-verify",
        "state.recheck-outcome.issue-still-visible",
        "state.recheck-review.issue-still-visible",
        "state.issue.open",
        "state.recheck-outcome.different-issue",
        "state.recheck-review.different-issue",
        "state.issue.different-open",
        "state.report-pdf.failed",
        "state.report-comparison.ready",
        "state.report-correction.editing",
        "state.report-correction.validation-error",
        "state.report-correction.saving",
        "state.report-correction.completed",
        "state.paywall.unavailable",
        "state.feedback.review-ready",
        "state.settings.hub",
        "state.backup.ready",
        "state.diagnostics.ready",
        "state.feedback.blocked",
        "state.erase.confirmation",
        "state.restore.choose-backup",
        "state.subscription.active",
        "state.sign-selection.ready",
        "state.subscription.no-entitlement",
    ]

    private static let contrastAuditExceptionSignatures = [
        ContrastAuditExceptionSignature(
            issueID: "S10.4-XCUI-CONTRAST-FP-AX-TEXT-PAYWALL-PURCHASE-COMPLETE-NO-SYNC",
            shardID: "s10.4.current.ax-text",
            stateID: "state.paywall.purchase-complete",
            taskID: "one_handed_start",
            owner: "palatis3",
            expiresAt: "2026-11-20",
            rationale: "Xcode 26.6/iOS 26.2 reports a SwiftUI.AccessibilityNode contrast issue for the identified no-sync disclosure whose frozen public frame starts 526.66666666666629 points above the application, is 745.33333333333303 points tall, and therefore exceeds the 704-point paywall Store viewport; the audit-owned crop visibly binds the issue to black text clipped beneath native Subscription/status chrome, and the exception is limited to the frozen public issue signature.",
            auditTypeRawValue: "1",
            compactDescription: "Contrast failed",
            detailedDescription: "Contrast failed for SwiftUI.AccessibilityNode",
            elementIdentifier: "s7.2.paywall.no-sync",
            elementLabel: "Inspection data and photos stay on this device and do not sync with the subscription. Use a data backup to move them to another device.",
            elementTypeDescription: "XCUIElementType(rawValue: 48)",
            elementFrame: CGRect(
                x: 32,
                y: -526.66666666666629,
                width: 338,
                height: 745.33333333333303
            ),
            applicationFrame: CGRect(x: 0, y: 0, width: 402, height: 874)
        ),
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
        ContrastAuditExceptionSignature(
            issueID: "S10.4-XCUI-CONTRAST-FP-AX-TEXT-PREFLIGHT-TIME-ZONE-CONFIRMATION",
            shardID: "s10.4.current.ax-text",
            stateID: "state.check-preflight.ready",
            taskID: "one_handed_start",
            owner: "palatis3",
            expiresAt: "2026-11-20",
            rationale: "Xcode 26.6/iOS 26.2 reports a SwiftUI.AccessibilityNode contrast issue for the I confirm this is the site's time zone label even though the audit-owned crop contains only the iOS keyboard and the frozen public node frame is fully keyboard-occluded in the AX-text preflight state; the exception is limited to the frozen public issue signature.",
            auditTypeRawValue: "1",
            compactDescription: "Contrast failed",
            detailedDescription: "Contrast failed for SwiftUI.AccessibilityNode",
            elementIdentifier: "",
            elementLabel: "I confirm this is the site's time zone.",
            elementTypeDescription: "XCUIElementType(rawValue: 48)",
            elementFrame: CGRect(
                x: 32,
                y: 547,
                width: 238.33333333333331,
                height: 249.33333333333337
            ),
            applicationFrame: CGRect(x: 0, y: 0, width: 402, height: 874)
        ),
        ContrastAuditExceptionSignature(
            issueID: "S10.4-XCUI-CONTRAST-FP-AX-TEXT-ISSUE-RESOLVED-WORK-DESCRIPTION",
            shardID: "s10.4.current.ax-text",
            stateID: "state.issue.resolved",
            taskID: "work_and_recheck",
            owner: "palatis3",
            expiresAt: "2026-11-20",
            rationale: "Xcode 26.6/iOS 26.2 reports a SwiftUI.AccessibilityNode contrast issue for the empty-identifier Replaced failed power supply value whose frozen public frame is wholly inside the application but overlaps 14.7375488281249 points of native bottom tab chrome in the AX-text issue-resolved state; the audit-owned crop and serialized tree bind the issue to that exact native-chrome composition, and the exception is limited to the frozen public issue signature.",
            auditTypeRawValue: "1",
            compactDescription: "Contrast failed",
            detailedDescription: "Contrast failed for SwiftUI.AccessibilityNode",
            elementIdentifier: "",
            elementLabel: "Replaced failed power supply",
            elementTypeDescription: "XCUIElementType(rawValue: 48)",
            elementFrame: CGRect(
                x: 32,
                y: 618.40421549479152,
                width: 284,
                height: 187.33333333333337
            ),
            applicationFrame: CGRect(x: 0, y: 0, width: 402, height: 874)
        ),
        ContrastAuditExceptionSignature(
            issueID: "S10.4-XCUI-CONTRAST-FP-AX-TEXT-ISSUE-OPEN-WORK-DESCRIPTION",
            shardID: "s10.4.current.ax-text",
            stateID: "state.issue.open",
            taskID: "work_and_recheck",
            owner: "palatis3",
            expiresAt: "2026-11-20",
            rationale: "Xcode 26.6/iOS 26.2 reports a SwiftUI.AccessibilityNode contrast issue for the empty-identifier Replaced damaged component value whose frozen public frame begins inside native bottom tab chrome and extends below the 402x874 application frame in the AX-text issue-open state; the exact unfiltered audit callback and audit-owned crop bind the issue to that chrome-clipped composition, and the exception is limited to the frozen public issue signature.",
            auditTypeRawValue: "1",
            compactDescription: "Contrast failed",
            detailedDescription: "Contrast failed for SwiftUI.AccessibilityNode",
            elementIdentifier: "",
            elementLabel: "Replaced damaged component",
            elementTypeDescription: "XCUIElementType(rawValue: 48)",
            elementFrame: CGRect(
                x: 32,
                y: 813.66666666666663,
                width: 256.33333333333331,
                height: 187.33333333333337
            ),
            applicationFrame: CGRect(x: 0, y: 0, width: 402, height: 874)
        ),
        ContrastAuditExceptionSignature(
            issueID: "S10.4-XCUI-CONTRAST-FP-AX-TEXT-ISSUE-RECHECK-DUE-SECTION-APPEARS-DARK",
            shardID: "s10.4.current.ax-text",
            stateID: "state.issue.recheck-due",
            taskID: "work_and_recheck",
            owner: "palatis3",
            expiresAt: "2026-11-20",
            rationale: "Xcode 26.6/iOS 26.2 reports a SwiftUI.AccessibilityNode contrast issue for the identified Section appears dark header whose frozen public frame intersects the native Recheck due navigation material in the AX-text issue-recheck-due state even though IssueDetailView renders it with primaryText; exact live geometry proves no rigid ScrollView shift can simultaneously place that header and the required Start recheck and saved-work composition clear of native top and bottom chrome, and the exception is limited to the frozen public issue signature.",
            auditTypeRawValue: "1",
            compactDescription: "Contrast failed",
            detailedDescription: "Contrast failed for SwiftUI.AccessibilityNode",
            elementIdentifier: "s5.1.issue.header",
            elementLabel: "Section appears dark",
            elementTypeDescription: "XCUIElementType(rawValue: 48)",
            elementFrame: CGRect(
                x: 32,
                y: 42.666666666666657,
                width: 330,
                height: 141.66666666666669
            ),
            applicationFrame: CGRect(x: 0, y: 0, width: 402, height: 874)
        ),
        ContrastAuditExceptionSignature(
            issueID: "S10.4-XCUI-CONTRAST-FP-AX-TEXT-RECHECK-PREFLIGHT-SAFE-POSITION-CONFIRMATION",
            shardID: "s10.4.current.ax-text",
            stateID: "state.recheck-preflight.ready",
            taskID: "work_and_recheck",
            owner: "palatis3",
            expiresAt: "2026-11-20",
            rationale: "Xcode 26.6/iOS 26.2 reports a SwiftUI.AccessibilityNode contrast issue for the empty-identifier safe-position confirmation whose frozen public frame extends below the native tab-safe viewport in the AX-text recheck-preflight state; exact live geometry proves its ordered composition with Before you begin spans 896 points and cannot fit within the 643-point navigation/tab-safe interval, and the exception is limited to the frozen public issue signature.",
            auditTypeRawValue: "1",
            compactDescription: "Contrast failed",
            detailedDescription: "Contrast failed for SwiftUI.AccessibilityNode",
            elementIdentifier: "",
            elementLabel: "I am in a safe, authorized position to take these photos.",
            elementTypeDescription: "XCUIElementType(rawValue: 48)",
            elementFrame: CGRect(
                x: 32,
                y: 763,
                width: 249,
                height: 373.33333333333326
            ),
            applicationFrame: CGRect(x: 0, y: 0, width: 402, height: 874)
        ),
        ContrastAuditExceptionSignature(
            issueID: "S10.4-XCUI-CONTRAST-FP-AX-TEXT-RECHECK-CAPTURE-WIDE-READY-CANNOT-COMPLETE",
            shardID: "s10.4.current.ax-text",
            stateID: "state.recheck-capture.wide-ready",
            taskID: "work_and_recheck",
            owner: "palatis3",
            expiresAt: "2026-11-20",
            rationale: "Xcode 26.6/iOS 26.2 reports a SwiftUI.AccessibilityNode contrast issue for the identified Cannot complete button whose frozen public frame begins in the final 4.33333333333337 points of the 874-point application viewport and extends almost entirely below it in the AX-text recheck-capture wide-ready state; the live capture composition already places Take photo and Choose from Photos above it while Import test photo continues below it, so the required ordered controls cannot fit simultaneously within the visible application composition under rigid translation, and the exception is limited to the frozen public issue signature.",
            auditTypeRawValue: "1",
            compactDescription: "Contrast failed",
            detailedDescription: "Contrast failed for SwiftUI.AccessibilityNode",
            elementIdentifier: "s3.capture.cannot-complete",
            elementLabel: "Cannot complete",
            elementTypeDescription: "XCUIElementType(rawValue: 9)",
            elementFrame: CGRect(
                x: 28,
                y: 869.66666666666663,
                width: 254,
                height: 125.33333333333337
            ),
            applicationFrame: CGRect(x: 0, y: 0, width: 402, height: 874)
        ),
        ContrastAuditExceptionSignature(
            issueID: "S10.4-XCUI-CONTRAST-FP-AX-TEXT-REPORT-HISTORY-LOWER-NORTH-CAMPUS",
            shardID: "s10.4.current.ax-text",
            stateID: "state.report-history.ready",
            taskID: "report_comprehension",
            owner: "palatis3",
            expiresAt: "2026-11-20",
            rationale: "Xcode 26.6/iOS 26.2 reports a SwiftUI.AccessibilityNode contrast issue for the lower North Campus label whose frozen public node frame intersects native bottom chrome after bounded positioning makes the header safe and hittable and moves the Visit composite below the application; an exact remaining positive ScrollView drag is unrecognized with zero measured header, lower-label, and Visit movement, while ReportsRootView already renders the label with primaryText; the exception is limited to the frozen public issue signature.",
            auditTypeRawValue: "1",
            compactDescription: "Contrast failed",
            detailedDescription: "Contrast failed for SwiftUI.AccessibilityNode",
            elementIdentifier: "",
            elementLabel: "North Campus",
            elementTypeDescription: "XCUIElementType(rawValue: 48)",
            elementFrame: CGRect(
                x: 32,
                y: 823.66666666666663,
                width: 329.33333333333331,
                height: 63.333333333333371
            ),
            applicationFrame: CGRect(x: 0, y: 0, width: 402, height: 874)
        ),
        ContrastAuditExceptionSignature(
            issueID: "S10.4-XCUI-CONTRAST-FP-AX-TEXT-REPORTS-INDEX-NORTH-CAMPUS",
            shardID: "s10.4.current.ax-text",
            stateID: "state.reports-index.ready",
            taskID: "report_comprehension",
            owner: "palatis3",
            expiresAt: "2026-11-20",
            rationale: "Xcode 26.6/iOS 26.2 reports a SwiftUI.AccessibilityNode contrast issue for the Reports-index North Campus label whose frozen public frame intersects native bottom tab chrome even though ReportsRootView already renders it with primaryText; the audit-owned crop confirms the issue is limited to that chrome-overlapped composition, and the exception is limited to the frozen public issue signature.",
            auditTypeRawValue: "1",
            compactDescription: "Contrast failed",
            detailedDescription: "Contrast failed for SwiftUI.AccessibilityNode",
            elementIdentifier: "",
            elementLabel: "North Campus",
            elementTypeDescription: "XCUIElementType(rawValue: 48)",
            elementFrame: CGRect(
                x: 32,
                y: 775.33333333333337,
                width: 329.33333333333331,
                height: 63.333333333333258
            ),
            applicationFrame: CGRect(x: 0, y: 0, width: 402, height: 874)
        ),
        ContrastAuditExceptionSignature(
            issueID: "S10.4-XCUI-CONTRAST-FP-AX-TEXT-REPORTS-INDEX-VISIT",
            shardID: "s10.4.current.ax-text",
            stateID: "state.reports-index.ready",
            taskID: "report_comprehension",
            owner: "palatis3",
            expiresAt: "2026-11-20",
            rationale: "Xcode 26.6/iOS 26.2 reports a SwiftUI.AccessibilityNode contrast issue for the Reports-index Visit label whose frozen public frame begins inside native bottom tab chrome, extends below the 402x874 application frame, and is not hittable even though ReportsRootView already renders it with primaryText; the audit-owned crop confirms the issue is limited to that chrome-clipped composition, and the exception is limited to the frozen public issue signature.",
            auditTypeRawValue: "1",
            compactDescription: "Contrast failed",
            detailedDescription: "Contrast failed for SwiftUI.AccessibilityNode",
            elementIdentifier: "",
            elementLabel: "Visit",
            elementTypeDescription: "XCUIElementType(rawValue: 48)",
            elementFrame: CGRect(
                x: 32,
                y: 850.66666666666663,
                width: 85.333333333333329,
                height: 51.333333333333485
            ),
            applicationFrame: CGRect(x: 0, y: 0, width: 402, height: 874)
        ),
        ContrastAuditExceptionSignature(
            issueID: "S10.4-XCUI-CONTRAST-FP-DEFAULT-DARK-FEEDBACK-PRIVACY",
            shardID: "s10.4.current.default-dark",
            stateID: "state.feedback.review-ready",
            taskID: "history_recovery",
            owner: "palatis3",
            expiresAt: "2026-11-20",
            rationale: "Xcode 26.6/iOS 26.2 reports a SwiftUI.AccessibilityNode contrast issue for the identified Feedback privacy copy while the frozen public node frame is top-clipped outside the 402x874 application frame and its remaining slice is bound to native status/navigation chrome; the live Feedback composition simultaneously preserves the frozen App-metadata and Save-diagnostics clearances, and the audit-owned crop confirms that unobscured primaryText renders white on the dark elevated surface; the exception is limited to the frozen public issue signature.",
            auditTypeRawValue: "1",
            compactDescription: "Contrast failed",
            detailedDescription: "Contrast failed for SwiftUI.AccessibilityNode",
            elementIdentifier: "s8.4.feedback.privacy",
            elementLabel: "Your message stays editable. Only app version, build, device model, and iOS version are prefilled; customer and inspection content is never prefilled.",
            elementTypeDescription: "XCUIElementType(rawValue: 48)",
            elementFrame: CGRect(
                x: 32,
                y: -34.333333333333343,
                width: 298.33333333333331,
                height: 86.333333333333343
            ),
            applicationFrame: CGRect(x: 0, y: 0, width: 402, height: 874)
        ),
        ContrastAuditExceptionSignature(
            issueID: "S10.4-XCUI-CONTRAST-FP-AX-TEXT-REPORT-CORRECTION-COUNT",
            shardID: "s10.4.current.ax-text",
            stateID: "state.report-correction.validation-error",
            taskID: "report_comprehension",
            owner: "palatis3",
            expiresAt: "2026-11-20",
            rationale: "Xcode 26.6/iOS 26.2 reports a SwiftUI.AccessibilityNode contrast issue for the identified 0 of 1,000 characters count whose audit-owned crop visibly renders black primary text partially under blurred native Correct report navigation material at y 62 with height 54; exact live geometry requires a downward shift of at least 59.418619791666742 points to clear navigation maxY 116, while Save maxY 523 and inputView minY 539 leave only 16 points, so the simultaneous feasible interval is empty and no rigid ScrollView shift can preserve the validation, Save, keyboard, and inputView composition; the exception is limited to the frozen public issue signature.",
            auditTypeRawValue: "1",
            compactDescription: "Contrast failed",
            detailedDescription: "Contrast failed for SwiftUI.AccessibilityNode",
            elementIdentifier: "s4.5.correction.count",
            elementLabel: "0 of 1,000 characters",
            elementTypeDescription: "XCUIElementType(rawValue: 48)",
            elementFrame: CGRect(
                x: 32,
                y: 56.581380208333258,
                width: 198,
                height: 102.33333333333326
            ),
            applicationFrame: CGRect(x: 0, y: 0, width: 402, height: 874)
        ),
        ContrastAuditExceptionSignature(
            issueID: "S10.4-XCUI-CONTRAST-FP-AX-TEXT-SIGN-SELECTION-MONUMENT-SIGN",
            shardID: "s10.4.current.ax-text",
            stateID: "state.sign-selection.ready",
            taskID: "one_handed_start",
            owner: "palatis3",
            expiresAt: "2026-11-20",
            rationale: "Xcode 26.6/iOS 26.2 reports a SwiftUI.AccessibilityNode contrast issue for the empty-identifier Monument Sign label whose frozen public frame begins below the native tab-safe viewport and is not hittable; the live sign-selection context proves the first sign row remains visible and selectable while the second row is below native tab chrome, and the exception is limited to the frozen public issue signature.",
            auditTypeRawValue: "1",
            compactDescription: "Contrast failed",
            detailedDescription: "Contrast failed for SwiftUI.AccessibilityNode",
            elementIdentifier: "",
            elementLabel: "Monument Sign",
            elementTypeDescription: "XCUIElementType(rawValue: 48)",
            elementFrame: CGRect(
                x: 32,
                y: 803.33333333333337,
                width: 268,
                height: 125.33333333333326
            ),
            applicationFrame: CGRect(x: 0, y: 0, width: 402, height: 874)
        ),
        ContrastAuditExceptionSignature(
            issueID: "S10.4-XCUI-CONTRAST-FP-DEFAULT-LIGHT-REPORT-CORRECTION-HEADER",
            shardID: "s10.4.current.default-light",
            stateID: "state.report-correction.validation-error",
            taskID: "report_comprehension",
            owner: "palatis3",
            expiresAt: "2026-11-20",
            rationale: "Xcode 26.6/iOS 26.2 reports a SwiftUI.AccessibilityNode contrast issue for the identified Correct report header in default light even though the audit-owned crop visibly renders the complete header unobscured and wholly above the keyboard; the exception is limited to the frozen public issue signature.",
            auditTypeRawValue: "1",
            compactDescription: "Contrast failed",
            detailedDescription: "Contrast failed for SwiftUI.AccessibilityNode",
            elementIdentifier: "s4.5.correction.header",
            elementLabel: "Correct report",
            elementTypeDescription: "XCUIElementType(rawValue: 48)",
            elementFrame: CGRect(
                x: 32,
                y: 111.33333587646484,
                width: 248,
                height: 40.666664123535156
            ),
            applicationFrame: CGRect(x: 0, y: 0, width: 402, height: 874)
        ),
        ContrastAuditExceptionSignature(
            issueID: "S10.4-XCUI-CONTRAST-FP-DEFAULT-DARK-REPORT-CORRECTION-HEADER",
            shardID: "s10.4.current.default-dark",
            stateID: "state.report-correction.validation-error",
            taskID: "report_comprehension",
            owner: "palatis3",
            expiresAt: "2026-11-20",
            rationale: "Xcode 26.6/iOS 26.2 reports a SwiftUI.AccessibilityNode contrast issue for the identified Correct report header in default dark even though the audit-owned crop visibly renders the complete header unobscured and wholly above the keyboard; the exception is limited to the frozen public issue signature.",
            auditTypeRawValue: "1",
            compactDescription: "Contrast failed",
            detailedDescription: "Contrast failed for SwiftUI.AccessibilityNode",
            elementIdentifier: "s4.5.correction.header",
            elementLabel: "Correct report",
            elementTypeDescription: "XCUIElementType(rawValue: 48)",
            elementFrame: CGRect(
                x: 32,
                y: 111.33333587646484,
                width: 248,
                height: 40.666664123535156
            ),
            applicationFrame: CGRect(x: 0, y: 0, width: 402, height: 874)
        ),
        ContrastAuditExceptionSignature(
            issueID: "S10.4-XCUI-CONTRAST-FP-INCREASED-CONTRAST-REPORT-CORRECTION-HEADER",
            shardID: "s10.4.current.increased-contrast",
            stateID: "state.report-correction.validation-error",
            taskID: "report_comprehension",
            owner: "palatis3",
            expiresAt: "2026-11-20",
            rationale: "Xcode 26.6/iOS 26.2 reports a SwiftUI.AccessibilityNode contrast issue for the identified Correct report header in increased contrast even though the audit-owned crop visibly renders the complete header unobscured and wholly above the keyboard; the exception is limited to the frozen public issue signature.",
            auditTypeRawValue: "1",
            compactDescription: "Contrast failed",
            detailedDescription: "Contrast failed for SwiftUI.AccessibilityNode",
            elementIdentifier: "s4.5.correction.header",
            elementLabel: "Correct report",
            elementTypeDescription: "XCUIElementType(rawValue: 48)",
            elementFrame: CGRect(
                x: 32,
                y: 111.33333587646484,
                width: 248,
                height: 40.666664123535156
            ),
            applicationFrame: CGRect(x: 0, y: 0, width: 402, height: 874)
        ),
        ContrastAuditExceptionSignature(
            issueID: "S10.4-XCUI-CONTRAST-FP-REDUCE-MOTION-REPORT-CORRECTION-HEADER",
            shardID: "s10.4.current.reduce-motion",
            stateID: "state.report-correction.validation-error",
            taskID: "report_comprehension",
            owner: "palatis3",
            expiresAt: "2026-11-20",
            rationale: "Xcode 26.6/iOS 26.2 reports a SwiftUI.AccessibilityNode contrast issue for the identified Correct report header in reduce motion even though the audit-owned crop visibly renders the complete header unobscured and wholly above the keyboard; the exception is limited to the frozen public issue signature.",
            auditTypeRawValue: "1",
            compactDescription: "Contrast failed",
            detailedDescription: "Contrast failed for SwiftUI.AccessibilityNode",
            elementIdentifier: "s4.5.correction.header",
            elementLabel: "Correct report",
            elementTypeDescription: "XCUIElementType(rawValue: 48)",
            elementFrame: CGRect(
                x: 32,
                y: 111.33333587646484,
                width: 248,
                height: 40.666664123535156
            ),
            applicationFrame: CGRect(x: 0, y: 0, width: 402, height: 874)
        ),
        ContrastAuditExceptionSignature(
            issueID: "S10.4-XCUI-CONTRAST-FP-DIFFERENTIATE-WITHOUT-COLOR-REPORT-CORRECTION-HEADER",
            shardID: "s10.4.current.differentiate-without-color",
            stateID: "state.report-correction.validation-error",
            taskID: "report_comprehension",
            owner: "palatis3",
            expiresAt: "2026-11-20",
            rationale: "Xcode 26.6/iOS 26.2 reports a SwiftUI.AccessibilityNode contrast issue for the identified Correct report header with Differentiate Without Color enabled even though the audit-owned crop visibly renders the complete header unobscured and wholly above the keyboard; the exception is limited to the frozen public issue signature.",
            auditTypeRawValue: "1",
            compactDescription: "Contrast failed",
            detailedDescription: "Contrast failed for SwiftUI.AccessibilityNode",
            elementIdentifier: "s4.5.correction.header",
            elementLabel: "Correct report",
            elementTypeDescription: "XCUIElementType(rawValue: 48)",
            elementFrame: CGRect(
                x: 32,
                y: 111.33333587646484,
                width: 248,
                height: 40.666664123535156
            ),
            applicationFrame: CGRect(x: 0, y: 0, width: 402, height: 874)
        ),
        ContrastAuditExceptionSignature(
            issueID: "S10.4-XCUI-CONTRAST-FP-REDUCE-TRANSPARENCY-REPORT-CORRECTION-HEADER",
            shardID: "s10.4.current.reduce-transparency",
            stateID: "state.report-correction.validation-error",
            taskID: "report_comprehension",
            owner: "palatis3",
            expiresAt: "2026-11-20",
            rationale: "Xcode 26.6/iOS 26.2 reports a SwiftUI.AccessibilityNode contrast issue for the identified Correct report header with Reduce Transparency enabled even though the audit-owned crop visibly renders the complete header unobscured and wholly above the keyboard; the exception is limited to the frozen public issue signature.",
            auditTypeRawValue: "1",
            compactDescription: "Contrast failed",
            detailedDescription: "Contrast failed for SwiftUI.AccessibilityNode",
            elementIdentifier: "s4.5.correction.header",
            elementLabel: "Correct report",
            elementTypeDescription: "XCUIElementType(rawValue: 48)",
            elementFrame: CGRect(
                x: 32,
                y: 111.33333587646484,
                width: 248,
                height: 40.666664123535156
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
    private var automationContrastExceptions: [String: [ContrastAuditExceptionSignature]] = [:]
    private var pseudoLabelSentinelValidated = false
    private var automationSegment = AutomationSegment.none
    private var segmentedRouteStateCursor = 0
    private var automatedSegmentFinished = false
    private var segment3ResumePrepared = false
    private var diagnosticProbe: DiagnosticProbe?
    private var diagnosticVisitedSetupCaptureStateIDs: [String] = []

    override func setUpWithError() throws {
        continueAfterFailure = false
        if !(self is S10_4DevelopmentProbeUITests) {
            let environment = ProcessInfo.processInfo.environment
            guard DiagnosticProbe.environmentKeys.allSatisfy({ environment[$0] == nil }) else {
                throw AutomationConfigurationError.invalid(
                    "Ordinary UI tests must reject diagnostic probe environment keys"
                )
            }
        }
    }

    func configureAutomatedBrandLabShardFromEnvironment() throws {
        let environment = ProcessInfo.processInfo.environment
        guard DiagnosticProbe.environmentKeys.allSatisfy({ environment[$0] == nil }) else {
            throw AutomationConfigurationError.invalid(
                "Ordinary S10.4 automation must reject diagnostic probe environment keys"
            )
        }
        try configureAutomatedBrandLabShard(
            from: environment,
            diagnosticProbe: nil
        )
    }

    func configureFocusedDiagnosticProbeFromEnvironment() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let rawProbeID = environment["CI_S10_4_DIAGNOSTIC_PROBE_ID"],
              let probe = DiagnosticProbe(rawValue: rawProbeID),
              environment["CI_S10_4_EXECUTION_LANE"]
                == "s10-4-focused-diagnostics-development-only",
              environment["CI_S10_4_RUNNER_PROVIDER"] == "github",
              environment["CI_S10_4_REF"]
                == "refs/heads/phase/s10-brand-refresh",
              let head = environment["CI_S10_4_HEAD"],
              head.count == 40,
              head.allSatisfy({
                  ("0"..."9").contains($0) || ("a"..."f").contains($0)
              }) else {
            throw AutomationConfigurationError.invalid(
                "Focused S10.4 diagnostic provenance is not the closed GitHub minimum tuple"
            )
        }
        try configureAutomatedBrandLabShard(from: environment, diagnosticProbe: probe)
    }

    private func configureAutomatedBrandLabShard(
        from environment: [String: String],
        diagnosticProbe: DiagnosticProbe?
    ) throws {
        guard environment["CI_TASK_ID"] == "S10.4" else {
            throw AutomationConfigurationError.invalid("CI_TASK_ID must equal S10.4")
        }
        guard let shardID = environment["CI_S10_4_SHARD_ID"],
              let shard = Self.automationShards.first(where: { $0.shardID == shardID }) else {
            throw AutomationConfigurationError.invalid("CI_S10_4_SHARD_ID is not a frozen shard")
        }
        guard let segmentValue = environment["CI_S10_4_SEGMENT_ID"],
              let segment = AutomationSegment(rawValue: segmentValue) else {
            throw AutomationConfigurationError.invalid(
                "CI_S10_4_SEGMENT_ID must equal none, segment-1, segment-2, or segment-3"
            )
        }
        guard segment == .none || shard.shardID == "s10.4.current.ax-text" else {
            throw AutomationConfigurationError.invalid(
                "Only the frozen AX-text shard may use a segmented route"
            )
        }
        guard diagnosticProbe == nil
                || (shard.shardID == "s10.4.minimum.minimum-os" && segment == .none) else {
            throw AutomationConfigurationError.invalid(
                "Focused diagnostics require the frozen minimum shard and no segment"
            )
        }
        var expectedEnvironment = shard.expectedEnvironment
        expectedEnvironment["CI_S10_4_SEGMENT_ID"] = segment.rawValue
        if let diagnosticProbe {
            expectedEnvironment["CI_S10_4_DIAGNOSTIC_PROBE_ID"] = diagnosticProbe.rawValue
            expectedEnvironment["CI_S10_4_DIAGNOSTIC_EXECUTION_LANE"] =
                "s10-4-focused-diagnostics-development-only"
            expectedEnvironment["CI_S10_4_DIAGNOSTIC_PROBE_TIMEOUT_SECONDS"] = "600"
            expectedEnvironment["CI_S10_4_EXECUTION_LANE"] =
                "s10-4-focused-diagnostics-development-only"
            expectedEnvironment["CI_S10_4_RUNNER_PROVIDER"] = "github"
            expectedEnvironment["CI_S10_4_HEAD"] = environment["CI_S10_4_HEAD"] ?? ""
            expectedEnvironment["CI_S10_4_REF"] =
                "refs/heads/phase/s10-brand-refresh"
        }
        let observed = Dictionary(uniqueKeysWithValues: environment
            .filter { $0.key.hasPrefix("CI_S10_4_") }
            .map { ($0.key, $0.value) })
        guard observed == expectedEnvironment else {
            let keys = Set(observed.keys)
                .symmetricDifference(Set(expectedEnvironment.keys))
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
        automationSegment = segment
        self.diagnosticProbe = diagnosticProbe
        diagnosticVisitedSetupCaptureStateIDs.removeAll()
        migratedStateIDs.removeAll()
        automationAXTreeDigests.removeAll()
        automationContrastExceptions.removeAll()
        pseudoLabelSentinelValidated = false
        segmentedRouteStateCursor = 0
        automatedSegmentFinished = false
        segment3ResumePrepared = false
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
        storeKitSession = try SKTestSession(contentsOf: fixtureURL)
        storeKitSession?.resetToDefaultState()
        storeKitSession?.clearTransactions()
        storeKitSession?.disableDialogs = true

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

        try assertLightFirstSignValidationAndCreation(in: app)
        try completeVisibleIssueCheck(in: app)
        assertFirstReceiptAndReport(in: app)
        try assertReportsIndex(in: app)

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
        app.launchArguments.removeAll {
            $0 == "--s3-5-ui-test-low-storage-once"
                || $0 == "--s3-6-ui-test-camera-denied-once"
        }
        app.launch()

        try completeWorkAndResolvedRecheckAtXXXL(in: app)
        if automatedSegmentFinished { return }
        if !segment3ResumePrepared {
            try captureAlternativeCompletedCheckStates(in: app)
            captureDifferentIssueStatesBeforeRecovery(in: app)
            if automatedSegmentFinished { return }
            app.terminate()
            app.launch()
        }
        recoverInjectedPDFFailureAtXXXL(in: app)
        captureReportComparisonAndCorrectionStates(in: app)
        captureUnavailablePaywallAndFeedbackReview(in: app)
        try assertMonthlyPaywallAtXXXL(in: app)
        eraseLocalDataAndCaptureNoEntitlement(in: app)
    }

    @MainActor
    func runFocusedDiagnosticProbe() throws {
        guard let diagnosticProbe else {
            throw AutomationConfigurationError.invalid(
                "Focused diagnostic execution requires a configured probe"
            )
        }
        let plannedTarget: (stateID: String, setupTarget: String)
        switch diagnosticProbe {
        case .minimumNewSign:
            plannedTarget = ("state.new-sign.editing", "s2.new-sign.site-label")
        case .minimumPreflight:
            plannedTarget = ("state.check-preflight.ready", "s3.preflight.time-zone")
        }
        printJSONLine(prefix: "S10_4_DIAGNOSTIC", object: [
            "diagnosticOnly": true,
            "equivalenceEstablished": false,
            "event": "probe-start",
            "feedsAcceptanceAssembler": false,
            "finalAcceptanceEligible": false,
            "omittedCaptureStateIDs": Self.segmentedRouteStateIDs,
            "plannedSetupTarget": plannedTarget.setupTarget,
            "plannedTargetAnchorStateID": plannedTarget.stateID,
            "probeID": diagnosticProbe.rawValue,
        ])
        let fixtureURL = try XCTUnwrap(Bundle(for: Self.self).url(
            forResource: "FieldEvidence",
            withExtension: "storekit"
        ))
        storeKitSession = try SKTestSession(contentsOf: fixtureURL)
        storeKitSession?.resetToDefaultState()
        storeKitSession?.clearTransactions()
        storeKitSession?.disableDialogs = true

        applyDeviceAppearance(fallbackIsDark: false)
        let app = try configuredApplication(
            appearance: "Light",
            appearanceFlag: "--s1-ui-test-light-mode",
            usesAccessibilityXXXL: false
        )
        app.launchArguments += [
            "--s3-5-ui-test-low-storage-once",
            "--s3-6-ui-test-camera-denied-once",
        ]
        app.launch()
        XCTAssertTrue(element("s2.welcome.screen", in: app)
            .waitForExistence(timeout: 30))

        switch diagnosticProbe {
        case .minimumNewSign:
            try assertLightFirstSignValidationAndCreation(in: app)
        case .minimumPreflight:
            try assertLightFirstSignValidationAndCreation(in: app)
            try completeVisibleIssueCheck(in: app)
        }
        throw AutomationConfigurationError.invalid(
            "Focused diagnostic route did not stop at its closed target"
        )
    }

    @MainActor
    func runFocusedDiagnosticProbeFromEnvironment() throws {
        try configureFocusedDiagnosticProbeFromEnvironment()
        do {
            try runFocusedDiagnosticProbe()
        } catch FocusedDiagnosticProbeStop.completed {
            return
        }
    }

    @MainActor
    private func assertLightFirstSignValidationAndCreation(
        in app: XCUIApplication
    ) throws {
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
        let signHasKeyboardFocus = wait(
            for: sign,
            predicate: "hasKeyboardFocus == true",
            timeout: 10
        )
        let keyboardIsVisible = app.keyboards.firstMatch.waitForExistence(timeout: 10)
        if diagnosticProbe == .minimumNewSign {
            completeFocusedDiagnosticProbe(
                targetStateID: "state.new-sign.editing",
                setupTarget: "s2.new-sign.sign-label",
                observationPhase: "pre-focus-native-audit",
                observedStateID: "state.new-sign.editing",
                in: app
            )
            dismissKeyboard(in: app)
            printJSONLine(prefix: "S10_4_DIAGNOSTIC_NATIVE_AUDIT", object: [
                "diagnosticOnly": true,
                "equivalenceEstablished": false,
                "event": "new-sign-native-audit-start",
                "feedsAcceptanceAssembler": false,
                "finalAcceptanceEligible": false,
                "probeID": DiagnosticProbe.minimumNewSign.rawValue,
                "targetAnchorStateID": "state.new-sign.editing",
                "focusObserved": signHasKeyboardFocus,
                "keyboardObserved": keyboardIsVisible,
            ])
            var observedIssueCount = 0
            do {
                try app.performAccessibilityAudit(for: .contrast) { issue in
                    observedIssueCount += 1
                    if observedIssueCount <= 3 {
                        self.printJSONLine(prefix: "S10_4_DIAGNOSTIC_NATIVE_AUDIT", object: [
                            "diagnosticOnly": true,
                            "equivalenceEstablished": false,
                            "event": "new-sign-native-audit-issue-observed",
                            "feedsAcceptanceAssembler": false,
                            "finalAcceptanceEligible": false,
                            "probeID": DiagnosticProbe.minimumNewSign.rawValue,
                            "targetAnchorStateID": "state.new-sign.editing",
                            "issueOrdinal": observedIssueCount,
                            "auditTypeRawValue": String(issue.auditType.rawValue),
                            "compactDescription": issue.compactDescription,
                            "detailedDescription": issue.detailedDescription,
                            "elementIdentifier": issue.element?.identifier ?? "",
                            "elementTypeDescription": issue.element.map {
                                String(describing: $0.elementType)
                            } ?? "",
                        ])
                    }
                    return true
                }
                printJSONLine(prefix: "S10_4_DIAGNOSTIC_NATIVE_AUDIT", object: [
                    "diagnosticOnly": true,
                    "equivalenceEstablished": false,
                    "event": "new-sign-native-audit-completed",
                    "feedsAcceptanceAssembler": false,
                    "finalAcceptanceEligible": false,
                    "probeID": DiagnosticProbe.minimumNewSign.rawValue,
                    "targetAnchorStateID": "state.new-sign.editing",
                    "observedIssueCount": observedIssueCount,
                ])
            } catch {
                printJSONLine(prefix: "S10_4_DIAGNOSTIC_NATIVE_AUDIT", object: [
                    "diagnosticOnly": true,
                    "equivalenceEstablished": false,
                    "event": "new-sign-native-audit-error",
                    "feedsAcceptanceAssembler": false,
                    "finalAcceptanceEligible": false,
                    "probeID": DiagnosticProbe.minimumNewSign.rawValue,
                    "targetAnchorStateID": "state.new-sign.editing",
                    "observedIssueCount": observedIssueCount,
                    "error": String(describing: error),
                ])
                throw error
            }
            throw FocusedDiagnosticProbeStop.completed
        }
        if diagnosticProbe == .minimumNewSign &&
            (!signHasKeyboardFocus || !keyboardIsVisible) {
            printJSONLine(prefix: "S10_4_DIAGNOSTIC", object: [
                "diagnosticOnly": true,
                "event": "new-sign-focus-observation",
                "focusObserved": signHasKeyboardFocus,
                "keyboardObserved": keyboardIsVisible,
                "elementExists": sign.exists,
                "elementHittable": sign.isHittable,
                "observedStateID": "state.new-sign.editing",
                "targetAnchorStateID": "state.new-sign.editing",
                "probeID": DiagnosticProbe.minimumNewSign.rawValue,
                "feedsAcceptanceAssembler": false,
                "finalAcceptanceEligible": false,
                "equivalenceEstablished": false,
            ])
            completeFocusedDiagnosticProbe(
                targetStateID: "state.new-sign.editing",
                setupTarget: "s2.new-sign.sign-label",
                observationPhase: "post-tap-focus-observation",
                observedStateID: "state.new-sign.editing",
                in: app
            )
            throw FocusedDiagnosticProbeStop.completed
        }
        XCTAssertTrue(signHasKeyboardFocus)
        XCTAssertTrue(keyboardIsVisible)
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
        if diagnosticProbe == .minimumNewSign {
            completeFocusedDiagnosticProbe(
                targetStateID: "state.new-sign.editing",
                setupTarget: "s2.new-sign.site-label",
                observationPhase: "post-save-required-site-validation",
                observedStateID: "state.new-sign.validation-error",
                in: app
            )
            throw FocusedDiagnosticProbeStop.completed
        }
        let validationDetailRoute = element("s2.sign-detail.screen", in: app)
        if shouldPrepareNormalEvidence(
            for: "state.new-sign.validation-error",
            in: app
        ) {
        let keyboard = app.keyboards.firstMatch
        let navigationBottom = app.navigationBars.firstMatch.frame.maxY
        let newSignScrollViews = app.scrollViews.containing(
            .textField,
            identifier: "s2.new-sign.site-label"
        )
        XCTAssertEqual(newSignScrollViews.count, 1)
        let scrollView = newSignScrollViews.firstMatch
        XCTAssertTrue(scrollView.waitForExistence(timeout: 10))
        let prePositionSiteValue = site.value as? String
        let prePositionSignValue = sign.value as? String
        let prePositionErrorLabel = error.label
        let prePositionErrorValue = error.value as? String
        let prePositionDetailRouteExists = validationDetailRoute.exists
        let dragInset: CGFloat = 24
        let minimumGestureDistance: CGFloat = 44
        for _ in 0..<12 {
            let liveScrollFrame = scrollView.frame
            let liveVisibleTop = max(liveScrollFrame.minY, navigationBottom)
            let liveVisibleBottom = min(
                liveScrollFrame.maxY,
                keyboard.frame.minY
            )
            guard liveVisibleBottom > liveVisibleTop else {
                XCTFail("New-sign validation has no visible keyboard-safe interval.")
                return
            }

            let errorFrame = error.frame
            if errorFrame.minY >= liveVisibleTop,
               errorFrame.maxY <= liveVisibleBottom {
                break
            }

            let minimumShift = liveVisibleTop - errorFrame.minY
            let maximumShift = liveVisibleBottom - errorFrame.maxY
            guard minimumShift <= maximumShift else {
                XCTFail("New-sign validation error cannot fit the keyboard-safe viewport.")
                return
            }

            let farFeasibleShift = abs(minimumShift) >= abs(maximumShift)
                ? minimumShift
                : maximumShift
            let maximumGestureDistance =
                liveVisibleBottom - liveVisibleTop - (2 * dragInset)
            guard maximumGestureDistance >= minimumGestureDistance else {
                XCTFail("New-sign validation viewport cannot recognize a safe gesture.")
                return
            }
            let dragDistance = max(
                -maximumGestureDistance,
                min(farFeasibleShift, maximumGestureDistance)
            )
            guard abs(dragDistance) >= minimumGestureDistance else {
                XCTFail("New-sign validation feasible shift is below gesture recognition.")
                return
            }

            let scrollOrigin = scrollView.coordinate(
                withNormalizedOffset: CGVector(dx: 0, dy: 0)
            )
            let dragStartOffsetY = dragDistance > 0
                ? liveVisibleTop - liveScrollFrame.minY + dragInset
                : liveVisibleBottom - liveScrollFrame.minY - dragInset
            let dragStart = scrollOrigin.withOffset(
                CGVector(
                    dx: liveScrollFrame.width / 2,
                    dy: dragStartOffsetY
                )
            )
            let dragEnd = dragStart.withOffset(
                CGVector(dx: 0, dy: dragDistance)
            )
            let errorBeforeDrag = error.frame.minY
            dragStart.press(forDuration: 0.05, thenDragTo: dragEnd)
            let observedShift = error.frame.minY - errorBeforeDrag
            guard observedShift * dragDistance > 0 else {
                XCTFail("New-sign validation positioning gesture was not recognized.")
                return
            }
        }
        let finalFocusPreserved = wait(
            for: site,
            predicate: "hasKeyboardFocus == true",
            timeout: 10
        )
        let finalKeyboardExists = keyboard.waitForExistence(timeout: 10)
        let finalErrorExists = error.waitForExistence(timeout: 10)
        let finalScrollFrame = scrollView.frame
        let finalVisibleTop = max(finalScrollFrame.minY, navigationBottom)
        let finalVisibleBottom = finalKeyboardExists
            ? min(finalScrollFrame.maxY, keyboard.frame.minY)
            : -CGFloat.greatestFiniteMagnitude
        let finalErrorContained = finalErrorExists
            && error.frame.minY >= finalVisibleTop
            && error.frame.maxY <= finalVisibleBottom
        let finalContentPreserved = finalErrorExists
            && (site.value as? String) == prePositionSiteValue
            && (sign.value as? String) == prePositionSignValue
            && error.label == prePositionErrorLabel
            && (error.value as? String) == prePositionErrorValue
        let finalDetailRoutePreserved =
            validationDetailRoute.exists == prePositionDetailRouteExists
        guard finalFocusPreserved,
              finalKeyboardExists,
              finalErrorContained,
              finalContentPreserved,
              finalDetailRoutePreserved,
              app.state == .runningForeground else {
            XCTFail("New-sign validation did not remain focused, unchanged, and fully visible above the keyboard.")
            return
        }
        if automationShard?.deviceProfileID == "iphone-se-3-ios-18.0-minimum" {
            let preActionSiteValue = site.value as? String
            let preActionSignValue = sign.value as? String
            let preActionErrorLabel = error.label
            let preActionErrorValue = error.value as? String
            let newSignRoute = element("s2.new-sign.screen", in: app)
            let preActionNewSignRouteExists = newSignRoute.exists
            let preActionDetailRouteExists = validationDetailRoute.exists
            let returnKey = app.keyboards.buttons["Return"]
            if !returnKey.waitForExistence(timeout: 1) || !returnKey.isHittable {
                let applicationFrame = app.frame
                let observedKeyboardFrame = keyboard.frame
                guard !applicationFrame.isNull,
                      !applicationFrame.isEmpty,
                      !observedKeyboardFrame.isNull,
                      !observedKeyboardFrame.isEmpty else {
                    XCTFail("The minimum-profile application or keyboard frame is empty.")
                    return
                }

                let keyboardIsOffApp =
                    observedKeyboardFrame.minY >= applicationFrame.maxY
                let keyboardIsVisibleInApp =
                    observedKeyboardFrame.minY < applicationFrame.maxY
                guard keyboardIsOffApp != keyboardIsVisibleInApp else {
                    XCTFail("The minimum-profile keyboard geometry is not classifiable.")
                    return
                }

                if keyboardIsOffApp {
                    let inputAssistantViews = app.descendants(
                        matching: .other
                    ).matching(identifier: "SystemInputAssistantView")
                    let inputAssistantView = inputAssistantViews.firstMatch
                    guard inputAssistantViews.count == 1,
                          inputAssistantView.exists,
                          !inputAssistantView.frame.isNull,
                          !inputAssistantView.frame.isEmpty,
                          inputAssistantView.frame.minY
                            >= applicationFrame.maxY,
                          keyboardIsAbsentOrInertOffApp(in: app),
                          newSignRoute.exists
                            == preActionNewSignRouteExists,
                          validationDetailRoute.exists
                            == preActionDetailRouteExists,
                          (site.value as? String) == preActionSiteValue,
                          (sign.value as? String) == preActionSignValue,
                          error.label == preActionErrorLabel,
                          (error.value as? String) == preActionErrorValue,
                          app.state == .runningForeground else {
                        XCTFail("The minimum-profile off-app new-sign keyboard is not inert with preserved state.")
                        return
                    }
                } else {
                    let expectedKeyboardFrame = CGRect(
                        x: 0,
                        y: 451,
                        width: 375,
                        height: 216
                    )
                    guard observedKeyboardFrame == expectedKeyboardFrame else {
                        XCTFail("The iOS 18 keyboard frame does not match the frozen QuickPath tutorial evidence.")
                        return
                    }
                    keyboard.coordinate(
                        withNormalizedOffset: CGVector(
                            dx: 0.5,
                            dy: 0.8425925925925926
                        )
                    ).tap()
                    let restoredKeyboard = app.keyboards.firstMatch
                    let expectedReturnFrame = CGRect(
                        x: 281.5,
                        y: 620,
                        width: 93.5,
                        height: 46
                    )
                    guard returnKey.waitForExistence(timeout: 10),
                          returnKey.elementType == .button,
                          returnKey.identifier == "Return",
                          returnKey.label.lowercased() == "return",
                          returnKey.frame == expectedReturnFrame,
                          returnKey.isHittable,
                          restoredKeyboard.waitForExistence(timeout: 10),
                          restoredKeyboard.frame == observedKeyboardFrame,
                          wait(
                              for: site,
                              predicate: "hasKeyboardFocus == true",
                              timeout: 10
                          ),
                          error.waitForExistence(timeout: 10),
                          newSignRoute.exists
                            == preActionNewSignRouteExists,
                          validationDetailRoute.exists
                            == preActionDetailRouteExists,
                          (site.value as? String) == preActionSiteValue,
                          (sign.value as? String) == preActionSignValue,
                          error.label == preActionErrorLabel,
                          (error.value as? String) == preActionErrorValue,
                          app.state == .runningForeground else {
                        XCTFail("The new-sign validation state or content was not restored after dismissing the QuickPath tutorial.")
                        return
                    }
                }
            }
        }
        }
        captureBaseline("state.new-sign.validation-error", in: app)

        site.typeText("North Campus")
        if automationShard?.deviceProfileID == "iphone-17-ios-26.2-current" {
            let currentQuickPathTutorialLabel =
                "Speed up your typing by sliding your finger across the letters to compose a word."
            let currentQuickPathContinueLabel = "Continue"
            let currentQuickPathTutorialTexts = app.staticTexts.matching(
                NSPredicate(
                    format: "label == %@",
                    currentQuickPathTutorialLabel
                )
            )
            let currentQuickPathContinueButtons = app.buttons.matching(
                NSPredicate(
                    format: "label == %@",
                    currentQuickPathContinueLabel
                )
            )
            let currentQuickPathTutorialCount =
                currentQuickPathTutorialTexts.count
            let currentQuickPathContinueCount =
                currentQuickPathContinueButtons.count
            if currentQuickPathTutorialCount > 0
                || currentQuickPathContinueCount > 0 {
                let applicationFrame = app.frame
                let currentQuickPathTutorialText =
                    currentQuickPathTutorialTexts.firstMatch
                let currentQuickPathContinueButton =
                    currentQuickPathContinueButtons.firstMatch
                let currentQuickPathKeyboard = app.keyboards.firstMatch
                let currentQuickPathReturnKey =
                    currentQuickPathKeyboard.buttons["Return"]
                let currentQuickPathNewSignRoute =
                    element("s2.new-sign.screen", in: app)
                guard currentQuickPathTutorialCount == 1,
                      currentQuickPathContinueCount == 1,
                      currentQuickPathTutorialText.exists,
                      currentQuickPathTutorialText.elementType == .staticText,
                      currentQuickPathTutorialText.identifier.isEmpty,
                      currentQuickPathTutorialText.label
                        == currentQuickPathTutorialLabel,
                      currentQuickPathContinueButton.exists,
                      currentQuickPathContinueButton.elementType == .button,
                      currentQuickPathContinueButton.identifier.isEmpty,
                      currentQuickPathContinueButton.label
                        == currentQuickPathContinueLabel,
                      currentQuickPathContinueButton.isEnabled,
                      currentQuickPathContinueButton.isHittable,
                      !applicationFrame.isNull,
                      !applicationFrame.isEmpty,
                      !currentQuickPathTutorialText.frame.isNull,
                      !currentQuickPathTutorialText.frame.isEmpty,
                      applicationFrame.contains(
                          currentQuickPathTutorialText.frame
                      ),
                      !currentQuickPathContinueButton.frame.isNull,
                      !currentQuickPathContinueButton.frame.isEmpty,
                      applicationFrame.contains(
                          currentQuickPathContinueButton.frame
                      ),
                      currentQuickPathKeyboard.exists,
                      currentQuickPathReturnKey.exists,
                      currentQuickPathReturnKey.elementType == .button,
                      currentQuickPathReturnKey.identifier == "Return",
                      currentQuickPathReturnKey.label.lowercased() == "return",
                      !currentQuickPathReturnKey.isHittable,
                      currentQuickPathNewSignRoute.exists,
                      !validationDetailRoute.exists,
                      wait(
                          for: site,
                          predicate: "hasKeyboardFocus == true",
                          timeout: 10
                      ),
                      (site.value as? String) == "North Campus",
                      (sign.value as? String) == "Monument Sign",
                      app.state == .runningForeground else {
                    XCTFail("The current-profile QuickPath tutorial is incomplete or the new-sign state changed before dismissal.")
                    return
                }

                currentQuickPathContinueButton.tap()
                guard currentQuickPathTutorialText.waitForNonExistence(
                    timeout: 10
                ),
                      currentQuickPathContinueButton.waitForNonExistence(
                          timeout: 10
                      ),
                      currentQuickPathReturnKey.waitForExistence(timeout: 10),
                      currentQuickPathReturnKey.elementType == .button,
                      currentQuickPathReturnKey.identifier == "Return",
                      currentQuickPathReturnKey.label.lowercased() == "return",
                      currentQuickPathReturnKey.isHittable,
                      currentQuickPathKeyboard.exists,
                      currentQuickPathNewSignRoute.exists,
                      !validationDetailRoute.exists,
                      wait(
                          for: site,
                          predicate: "hasKeyboardFocus == true",
                          timeout: 10
                      ),
                      (site.value as? String) == "North Campus",
                      (sign.value as? String) == "Monument Sign",
                      app.state == .runningForeground else {
                    XCTFail("The current-profile QuickPath tutorial did not dismiss with the new-sign state preserved.")
                    return
                }
            }
        }
        dismissKeyboard(in: app)
        dismissKeyboard(in: app)
        XCTAssertTrue(keyboardIsAbsentOrInertOffApp(in: app))
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
        let runsMinimumDoubleLengthDeleteComposition =
            automationShard?.shardID == "s10.4.minimum.double-length"
        if runsMinimumDoubleLengthDeleteComposition {
            let messageScrollViews = app.scrollViews.containing(
                .staticText,
                identifier: "s6.1.delete.message"
            )
            let cancelScrollViews = app.scrollViews.containing(
                .button,
                identifier: "s6.1.delete.cancel"
            )
            let confirmScrollViews = app.scrollViews.containing(
                .button,
                identifier: "s6.1.delete.confirm"
            )
            let siteScrollViews = app.scrollViews.containing(
                .staticText,
                identifier: "s2.sign-detail.site-label"
            )
            guard app.state == .runningForeground,
                  messageScrollViews.count == 1,
                  cancelScrollViews.count == 1,
                  confirmScrollViews.count == 1,
                  siteScrollViews.count == 1,
                  messageScrollViews.firstMatch.identifier == detail.identifier,
                  cancelScrollViews.firstMatch.identifier == detail.identifier,
                  confirmScrollViews.firstMatch.identifier == detail.identifier,
                  siteScrollViews.firstMatch.identifier == detail.identifier else {
                XCTFail(
                    "Minimum double-length delete confirmation lost its sole ScrollView owner."
                )
                return
            }
            let dragInset: CGFloat = 24
            let minimumVisibleIntersection: CGFloat = 44
            for _ in 0..<4 {
                let viewportTop = detail.frame.minY
                let viewportBottom = detail.frame.maxY
                let messageFrame = deleteMessage.frame
                let cancelFrame = cancelDelete.frame
                let confirmFrame = confirmDelete.frame
                let minimumShift = max(
                    viewportTop + minimumVisibleIntersection - messageFrame.maxY,
                    max(
                        viewportTop - cancelFrame.minY,
                        max(
                            viewportTop + minimumVisibleIntersection
                                - confirmFrame.maxY,
                            viewportTop - confirmFrame.midY
                        )
                    )
                )
                let maximumShift = min(
                    viewportBottom - minimumVisibleIntersection - messageFrame.minY,
                    min(
                        viewportBottom - cancelFrame.maxY,
                        min(
                            viewportBottom - minimumVisibleIntersection
                                - confirmFrame.minY,
                            viewportBottom - confirmFrame.midY
                        )
                    )
                )
                guard app.state == .runningForeground,
                      minimumShift <= maximumShift else {
                    XCTFail(
                        "Minimum double-length delete composition has no feasible interval."
                    )
                    return
                }
                if minimumShift <= 0 && maximumShift >= 0 { break }

                let targetDistance = maximumShift < 0
                    ? minimumShift
                    : maximumShift
                let maximumGestureDistance = viewportBottom
                    - viewportTop
                    - 2 * dragInset
                guard maximumGestureDistance >= minimumVisibleIntersection,
                      abs(targetDistance) >= minimumVisibleIntersection else {
                    XCTFail(
                        "Minimum double-length delete composition cannot use a recognized gesture."
                    )
                    return
                }
                let dragDistance = targetDistance > 0
                    ? min(targetDistance, maximumGestureDistance)
                    : max(targetDistance, -maximumGestureDistance)
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
        }
        let preparesDeleteConfirmationEvidence = shouldPrepareNormalEvidence(
            for: "state.sign-detail.delete-confirmation",
            in: app
        )
        let runsAXTextDeleteConfirmationDiagnostic =
            automationShard?.shardID == "s10.4.current.ax-text"
                && preparesDeleteConfirmationEvidence
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
        if preparesDeleteConfirmationEvidence
            && !runsAXTextDeleteConfirmationDiagnostic
            && !runsMinimumDoubleLengthDeleteComposition {
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
        if runsMinimumDoubleLengthDeleteComposition {
            let finalViewportFrame = detail.frame
            let finalMessageIntersection = deleteMessage.frame.intersection(
                finalViewportFrame
            )
            let finalCancelFrame = cancelDelete.frame
            let finalConfirmFrame = confirmDelete.frame
            let finalConfirmIntersection = finalConfirmFrame.intersection(
                finalViewportFrame
            )
            guard app.state == .runningForeground,
                  app.scrollViews.containing(
                    .staticText,
                    identifier: "s6.1.delete.message"
                  ).count == 1,
                  app.scrollViews.containing(
                    .button,
                    identifier: "s6.1.delete.cancel"
                  ).count == 1,
                  app.scrollViews.containing(
                    .button,
                    identifier: "s6.1.delete.confirm"
                  ).count == 1,
                  app.scrollViews.containing(
                    .staticText,
                    identifier: "s2.sign-detail.site-label"
                  ).count == 1,
                  !finalMessageIntersection.isNull,
                  finalMessageIntersection.height >= 44,
                  finalCancelFrame.minY >= finalViewportFrame.minY,
                  finalCancelFrame.maxY <= finalViewportFrame.maxY,
                  finalConfirmFrame.midY >= finalViewportFrame.minY,
                  finalConfirmFrame.midY <= finalViewportFrame.maxY,
                  !finalConfirmIntersection.isNull,
                  finalConfirmIntersection.height >= 44,
                  cancelDelete.isHittable,
                  confirmDelete.isHittable else {
                XCTFail(
                    "Minimum double-length delete composition is not usable."
                )
                return
            }
        }
        captureBaseline(deleteConfirmationStateID, in: app)
        assertControl(cancelDelete, label: "Cancel")
        cancelDelete.tap()
        XCTAssertTrue(detail.waitForExistence(timeout: 20))
    }

    @MainActor
    private func completeVisibleIssueCheck(in app: XCUIApplication) throws {
        let start = element("s2.sign-detail.start-check", in: app)
        scroll(start, in: app)
        assertControl(start, label: "Start Check")
        let startCheckAt = Date()
        start.tap()

        let preflight = element("s3.preflight.screen", in: app)
        XCTAssertTrue(preflight.waitForExistence(timeout: 20))
        if diagnosticProbe == nil {
            recordMetric("start_check_to_preflight", since: startCheckAt)
        }
        assertUnidentifiedLocalizedLabel("Information: Ready for night check", in: app)
        let zone = element("s3.preflight.time-zone", in: app)
        if automationShard?.deviceProfileID == "iphone-se-3-ios-18.0-minimum" {
            let returnKey = app.keyboards.buttons["Return"]
            if !returnKey.waitForExistence(timeout: 1) || !returnKey.isHittable {
                let preActionZoneLabel = zone.label
                let preActionZoneValue = zone.value as? String
                let preActionPreflightExists = preflight.exists
                let detailRoute = element("s2.sign-detail.screen", in: app)
                let preActionDetailRouteExists = detailRoute.exists
                let keyboard = app.keyboards.firstMatch
                let preflightScrollViews = app.scrollViews.containing(
                    .textField,
                    identifier: "s3.preflight.time-zone"
                )
                let preflightNavigationBars = app.navigationBars
                let inputAssistantViews = app.descendants(
                    matching: .other
                ).matching(identifier: "SystemInputAssistantView")
                let afterDarkToggles = app.switches.matching(
                    identifier: "s3.preflight.after-dark"
                )
                let safePositionToggles = app.switches.matching(
                    identifier: "s3.preflight.safe-position"
                )
                let preflightScrollView = preflightScrollViews.firstMatch
                let preflightNavigationBar = preflightNavigationBars.firstMatch
                let inputAssistantView = inputAssistantViews.firstMatch
                let afterDark = afterDarkToggles.firstMatch
                let safePosition = safePositionToggles.firstMatch
                let preActionAfterDarkLabel = afterDark.label
                let preActionAfterDarkValue = afterDark.value as? String
                let preActionSafePositionLabel = safePosition.label
                let preActionSafePositionValue = safePosition.value as? String
                guard keyboard.waitForExistence(timeout: 10),
                      preflightScrollViews.count == 1,
                      preflightNavigationBars.count == 1,
                      inputAssistantViews.count == 1,
                      afterDarkToggles.count == 1,
                      safePositionToggles.count == 1,
                      preflightScrollView.exists,
                      preflightNavigationBar.exists,
                      inputAssistantView.exists,
                      afterDark.exists,
                      safePosition.exists,
                      wait(
                          for: zone,
                          predicate: "hasKeyboardFocus == true",
                          timeout: 10
                      ),
                      preActionPreflightExists,
                      !preActionDetailRouteExists,
                      app.state == .runningForeground else {
                    XCTFail("The iOS 18 preflight QuickPath state is incomplete.")
                    return
                }
                let applicationFrame = app.frame
                let observedKeyboardFrame = keyboard.frame
                guard !applicationFrame.isNull,
                      !applicationFrame.isEmpty,
                      !observedKeyboardFrame.isNull,
                      !observedKeyboardFrame.isEmpty else {
                    XCTFail("The minimum-profile preflight application or keyboard frame is empty.")
                    return
                }

                let keyboardIsOffApp =
                    observedKeyboardFrame.minY >= applicationFrame.maxY
                let keyboardIsVisibleInApp =
                    observedKeyboardFrame.minY < applicationFrame.maxY
                guard keyboardIsOffApp != keyboardIsVisibleInApp else {
                    XCTFail("The minimum-profile preflight keyboard geometry is not classifiable.")
                    return
                }

                if keyboardIsOffApp {
                    let inputAssistantFrame = inputAssistantView.frame
                    guard inputAssistantViews.count == 1,
                          !inputAssistantFrame.isNull,
                          !inputAssistantFrame.isEmpty,
                          inputAssistantFrame.minY
                            >= applicationFrame.maxY,
                          keyboardIsAbsentOrInertOffApp(in: app),
                          preflight.exists
                            == preActionPreflightExists,
                          detailRoute.exists
                            == preActionDetailRouteExists,
                          zone.label == preActionZoneLabel,
                          (zone.value as? String) == preActionZoneValue,
                          afterDark.label == preActionAfterDarkLabel,
                          (afterDark.value as? String)
                            == preActionAfterDarkValue,
                          safePosition.label
                            == preActionSafePositionLabel,
                          (safePosition.value as? String)
                            == preActionSafePositionValue,
                          app.state == .runningForeground else {
                        XCTFail("The minimum-profile off-app preflight keyboard is not inert with preserved state.")
                        return
                    }
                    if automationShard?.shardID
                        == "s10.4.minimum.double-length" {
                        let preflightTabBars = app.tabBars
                        let confirmationLabel =
                            "I confirm this is the site's time zone. " +
                            "I confirm this is the site's time zone."
                        let confirmationTexts = app.staticTexts.matching(
                            NSPredicate(
                                format: "label == %@",
                                confirmationLabel
                            )
                        )
                        let preflightTabBar = preflightTabBars.firstMatch
                        let confirmationText = confirmationTexts.firstMatch
                        let observedAssistantFrame = inputAssistantFrame
                        let verticalInset: CGFloat = 16
                        let receiverInset: CGFloat = 24
                        let minimumGestureDistance: CGFloat = 44
                        var preflightPositioningDirection: CGFloat?
                        var previousCommandedDragDistance: CGFloat?
                        var previousConfirmationMinYBeforeDrag: CGFloat?
                        var previousConfirmationMinYAfterDrag: CGFloat?
                        var previousObservedMovement: CGFloat?
                        for attemptIndex in 0..<4 {
                            guard app.state == .runningForeground,
                                  preflightScrollViews.count == 1,
                                  preflightNavigationBars.count == 1,
                                  preflightTabBars.count == 1,
                                  confirmationTexts.count == 1,
                                  preflightScrollView.exists,
                                  preflightNavigationBar.exists,
                                  preflightTabBar.exists,
                                  confirmationText.exists,
                                  confirmationText.identifier.isEmpty,
                                  confirmationText.elementType == .staticText,
                                  confirmationText.label == confirmationLabel,
                                  keyboard.exists,
                                  keyboard.frame == observedKeyboardFrame,
                                  inputAssistantViews.count == 1,
                                  inputAssistantView.exists,
                                  inputAssistantView.frame
                                    == observedAssistantFrame,
                                  keyboardIsAbsentOrInertOffApp(in: app) else {
                                XCTFail(
                                    "The minimum double-length preflight positioning route changed."
                                )
                                return
                            }
                            let liveApplicationFrame = app.frame
                            let scrollFrame = preflightScrollView.frame
                            let liveScrollFrame = scrollFrame.intersection(
                                liveApplicationFrame
                            )
                            let navigationFrame = preflightNavigationBar.frame
                            let tabBarFrame = preflightTabBar.frame
                            let confirmationFrame = confirmationText.frame
                            let liveBottom = min(
                                liveScrollFrame.maxY,
                                min(
                                    liveApplicationFrame.maxY,
                                    tabBarFrame.minY
                                )
                            )
                            let safeTop = max(
                                liveScrollFrame.minY,
                                navigationFrame.maxY
                            ) + verticalInset
                            let safeBottom = liveBottom - verticalInset
                            let receiverTop = max(
                                liveScrollFrame.minY,
                                navigationFrame.maxY
                            ) + receiverInset
                            let receiverBottom = liveBottom - receiverInset
                            let minimumShift =
                                safeTop - confirmationFrame.minY
                            let maximumShift =
                                safeBottom - confirmationFrame.maxY
                            guard !liveApplicationFrame.isNull,
                                  !liveApplicationFrame.isEmpty,
                                  !scrollFrame.isNull,
                                  !scrollFrame.isEmpty,
                                  !liveScrollFrame.isNull,
                                  !liveScrollFrame.isEmpty,
                                  !navigationFrame.isNull,
                                  !navigationFrame.isEmpty,
                                  !tabBarFrame.isNull,
                                  !tabBarFrame.isEmpty,
                                  !confirmationFrame.isNull,
                                  !confirmationFrame.isEmpty,
                                  safeBottom > safeTop,
                                  receiverBottom > receiverTop,
                                  confirmationFrame.height
                                    <= safeBottom - safeTop,
                                  minimumShift <= maximumShift else {
                                XCTFail(
                                    "The minimum double-length preflight positioning geometry is invalid."
                                )
                                return
                            }
                            if confirmationFrame.minY >= safeTop,
                               confirmationFrame.maxY <= safeBottom {
                                break
                            }
                            guard maximumShift < 0 else {
                                XCTFail(
                                    "The minimum double-length preflight confirmation requires a non-upward shift."
                                )
                                return
                            }
                            let receiverCapacity = receiverBottom - receiverTop
                            guard receiverCapacity >= minimumGestureDistance else {
                                XCTFail(
                                    "The minimum double-length preflight confirmation has no recognized upward shift."
                                )
                                return
                            }
                            let dragDistance: CGFloat
                            if maximumShift > -minimumGestureDistance {
                                let recognizedResidualDistance =
                                    -minimumGestureDistance
                                let previousCommandMinusObservedResidual =
                                    previousCommandedDragDistance.flatMap {
                                        command in
                                        previousObservedMovement.map { movement in
                                            command - movement
                                        }
                                    }
                                let predictedRecognizedMovement =
                                    previousCommandMinusObservedResidual.map {
                                        residual in
                                        recognizedResidualDistance - residual
                                    }
                                if minimumShift > recognizedResidualDistance {
                                    guard let previousCommandedDragDistance,
                                          let previousObservedMovement,
                                          let previousCommandMinusObservedResidual,
                                          let predictedRecognizedMovement,
                                          previousCommandedDragDistance
                                            <= -minimumGestureDistance,
                                          previousObservedMovement < 0,
                                          previousCommandMinusObservedResidual < 0,
                                          predictedRecognizedMovement
                                            >= minimumShift,
                                          predictedRecognizedMovement
                                            <= maximumShift else {
                                        let optionalNumber: (CGFloat?) -> Any = {
                                            value in
                                            value.map { Double($0) } ?? NSNull()
                                        }
                                        let optionalString: (String?) -> Any = {
                                            value in
                                            value.map { $0 as Any } ?? NSNull()
                                        }
                                        let diagnosticContext: [String: Any] = [
                                        "schemaVersion": 1,
                                        "acceptanceEligible": false,
                                        "shardID": optionalString(
                                            automationShard?.shardID
                                        ),
                                        "requirementID": optionalString(
                                            automationShard?.requirementID
                                        ),
                                        "deviceProfileID": optionalString(
                                            automationShard?.deviceProfileID
                                        ),
                                        "attemptOrdinal": attemptIndex + 1,
                                        "applicationState": String(describing: app.state),
                                        "applicationStateRawValue": app.state.rawValue,
                                        "applicationForeground": app.state
                                            == .runningForeground,
                                        "applicationFrame": auditFrameObject(
                                            liveApplicationFrame
                                        ),
                                        "scrollFrame": auditFrameObject(scrollFrame),
                                        "liveScrollFrame": auditFrameObject(
                                            liveScrollFrame
                                        ),
                                        "navigationFrame": auditFrameObject(
                                            navigationFrame
                                        ),
                                        "tabBarFrame": auditFrameObject(tabBarFrame),
                                        "confirmationFrame": auditFrameObject(
                                            confirmationFrame
                                        ),
                                        "safeTop": Double(safeTop),
                                        "safeBottom": Double(safeBottom),
                                        "receiverTop": Double(receiverTop),
                                        "receiverBottom": Double(receiverBottom),
                                        "receiverCapacity": Double(receiverCapacity),
                                        "minimumGestureDistance": Double(
                                            minimumGestureDistance
                                        ),
                                        "recognizedResidualDistance": Double(
                                            recognizedResidualDistance
                                        ),
                                        "minimumShift": Double(minimumShift),
                                        "maximumShift": Double(maximumShift),
                                        "intervalWidth": Double(
                                            maximumShift - minimumShift
                                        ),
                                        "previousCommandedDragDistance":
                                            optionalNumber(
                                                previousCommandedDragDistance
                                            ),
                                        "previousConfirmationMinYBeforeDrag":
                                            optionalNumber(
                                                previousConfirmationMinYBeforeDrag
                                            ),
                                        "previousConfirmationMinYAfterDrag":
                                            optionalNumber(
                                                previousConfirmationMinYAfterDrag
                                            ),
                                        "previousObservedMovement":
                                            optionalNumber(previousObservedMovement),
                                        "previousCommandMinusObservedResidual":
                                            optionalNumber(
                                                previousCommandMinusObservedResidual
                                            ),
                                        "predictedRecognizedMovement": optionalNumber(
                                            predictedRecognizedMovement
                                        ),
                                        "positioningDirection": optionalNumber(
                                            preflightPositioningDirection
                                        ),
                                        "route": [
                                            "preflightExists": preflight.exists,
                                            "detailRouteExists": detailRoute.exists,
                                            "zoneExists": zone.exists,
                                            "zoneIdentifier": zone.identifier,
                                            "zoneLabel": zone.label,
                                            "zoneValue": optionalString(
                                                zone.value as? String
                                            ),
                                            "zoneFrame": auditFrameObject(zone.frame),
                                            "afterDarkExists": afterDark.exists,
                                            "afterDarkIdentifier": afterDark.identifier,
                                            "afterDarkLabel": afterDark.label,
                                            "afterDarkValue": optionalString(
                                                afterDark.value as? String
                                            ),
                                            "afterDarkFrame": auditFrameObject(
                                                afterDark.frame
                                            ),
                                            "safePositionExists": safePosition.exists,
                                            "safePositionIdentifier":
                                                safePosition.identifier,
                                            "safePositionLabel": safePosition.label,
                                            "safePositionValue": optionalString(
                                                safePosition.value as? String
                                            ),
                                            "safePositionFrame": auditFrameObject(
                                                safePosition.frame
                                            ),
                                            "confirmationExists":
                                                confirmationText.exists,
                                            "confirmationIdentifier":
                                                confirmationText.identifier,
                                            "confirmationLabel":
                                                confirmationText.label,
                                            "confirmationTypeRawValue":
                                                confirmationText.elementType.rawValue,
                                            "keyboardFrame": auditFrameObject(
                                                keyboard.frame
                                            ),
                                            "inputAssistantFrame": auditFrameObject(
                                                inputAssistantView.frame
                                            ),
                                        ],
                                        "queryCounts": [
                                            "preflightScrollViews":
                                                preflightScrollViews.count,
                                            "preflightNavigationBars":
                                                preflightNavigationBars.count,
                                            "preflightTabBars": preflightTabBars.count,
                                            "confirmationTexts": confirmationTexts.count,
                                            "inputAssistantViews":
                                                inputAssistantViews.count,
                                        ],
                                        ]
                                        printJSONLine(
                                        prefix:
                                            "S10_4_MINIMUM_DOUBLE_LENGTH_PREFLIGHT_RESIDUAL_DIAGNOSTIC",
                                        object: diagnosticContext
                                    )
                                    let appAttachment = XCTAttachment(
                                        screenshot: app.screenshot()
                                    )
                                    appAttachment.name =
                                        "S10.4 minimum double-length preflight residual diagnostic app"
                                    appAttachment.lifetime = .keepAlways
                                    add(appAttachment)
                                    let treeAttachment = XCTAttachment(
                                        string: app.debugDescription
                                    )
                                    treeAttachment.name =
                                        "S10.4 minimum double-length preflight residual diagnostic tree"
                                    treeAttachment.lifetime = .keepAlways
                                    add(treeAttachment)
                                    let contextData = try? JSONSerialization.data(
                                        withJSONObject: diagnosticContext,
                                        options: [.prettyPrinted, .sortedKeys]
                                    )
                                    let contextAttachment = XCTAttachment(
                                        string: contextData.map {
                                            String(decoding: $0, as: UTF8.self)
                                        } ?? "S10.4 minimum double-length preflight residual diagnostic context encoding failed"
                                    )
                                    contextAttachment.name =
                                        "S10.4 minimum double-length preflight residual diagnostic context"
                                    contextAttachment.lifetime = .keepAlways
                                    add(contextAttachment)
                                    XCTFail(
                                        "S10.4 minimum double-length preflight residual diagnostic completed nonaccepting"
                                    )
                                        return
                                    }
                                }
                                dragDistance = recognizedResidualDistance
                            } else if abs(maximumShift) <= receiverCapacity {
                                dragDistance = maximumShift
                            } else {
                                let stagedDistance = max(
                                    -receiverCapacity,
                                    maximumShift + minimumGestureDistance
                                )
                                guard stagedDistance
                                    <= -minimumGestureDistance else {
                                    XCTFail(
                                        "The minimum double-length preflight confirmation cannot reserve a recognized final shift."
                                    )
                                    return
                                }
                                dragDistance = stagedDistance
                            }
                            let dragDirection: CGFloat = dragDistance > 0
                                ? 1
                                : -1
                            if let preflightPositioningDirection {
                                guard dragDirection
                                    == preflightPositioningDirection else {
                                    XCTFail(
                                        "The minimum double-length preflight correction would reverse direction."
                                    )
                                    return
                                }
                            } else {
                                preflightPositioningDirection = dragDirection
                            }
                            let dragStartPoint = CGPoint(
                                x: liveScrollFrame.minX + receiverInset,
                                y: receiverBottom
                            )
                            guard liveScrollFrame.contains(dragStartPoint),
                                  !zone.frame.contains(dragStartPoint) else {
                                XCTFail(
                                    "The minimum double-length preflight drag receiver overlaps the focused time-zone field."
                                )
                                return
                            }
                            let scrollOrigin = preflightScrollView.coordinate(
                                withNormalizedOffset: CGVector(dx: 0, dy: 0)
                            )
                            let dragStart = scrollOrigin.withOffset(
                                CGVector(
                                    dx: dragStartPoint.x - scrollFrame.minX,
                                    dy: receiverBottom - scrollFrame.minY
                                )
                            )
                            let dragEnd = dragStart.withOffset(
                                CGVector(dx: 0, dy: dragDistance)
                            )
                            let confirmationMinYBeforeDrag =
                                confirmationFrame.minY
                            dragStart.press(
                                forDuration: 0.2,
                                thenDragTo: dragEnd,
                                withVelocity: .slow,
                                thenHoldForDuration: 0.2
                            )
                            guard app.state == .runningForeground,
                                  preflightScrollViews.count == 1,
                                  preflightNavigationBars.count == 1,
                                  preflightTabBars.count == 1,
                                  confirmationTexts.count == 1,
                                  preflightScrollView.exists,
                                  preflightNavigationBar.exists,
                                  preflightTabBar.exists,
                                  confirmationText.exists,
                                  confirmationText.identifier.isEmpty,
                                  confirmationText.elementType == .staticText,
                                  confirmationText.label == confirmationLabel,
                                  keyboard.exists,
                                  keyboard.frame == observedKeyboardFrame,
                                  inputAssistantViews.count == 1,
                                  inputAssistantView.exists,
                                  inputAssistantView.frame
                                    == observedAssistantFrame,
                                  keyboardIsAbsentOrInertOffApp(in: app) else {
                                XCTFail(
                                    "The minimum double-length preflight positioning route changed after the gesture."
                                )
                                return
                            }
                            let confirmationMovement =
                                confirmationText.frame.minY
                                    - confirmationMinYBeforeDrag
                            guard confirmationMovement * dragDistance > 0 else {
                                XCTFail(
                                    "The minimum double-length preflight positioning gesture did not make signed progress."
                                )
                                return
                            }
                            previousCommandedDragDistance = dragDistance
                            previousConfirmationMinYBeforeDrag =
                                confirmationMinYBeforeDrag
                            previousConfirmationMinYAfterDrag =
                                confirmationText.frame.minY
                            previousObservedMovement = confirmationMovement
                        }
                        let finalApplicationFrame = app.frame
                        let finalScrollFrame = preflightScrollView.frame.intersection(
                            finalApplicationFrame
                        )
                        let finalNavigationFrame = preflightNavigationBar.frame
                        let finalTabBarFrame = preflightTabBar.frame
                        let finalConfirmationFrame = confirmationText.frame
                        let finalSafeTop = max(
                            finalScrollFrame.minY,
                            finalNavigationFrame.maxY
                        ) + verticalInset
                        let finalSafeBottom = min(
                            finalScrollFrame.maxY,
                            min(
                                finalApplicationFrame.maxY,
                                finalTabBarFrame.minY
                            )
                        ) - verticalInset
                        guard app.state == .runningForeground,
                              preflightScrollViews.count == 1,
                              preflightNavigationBars.count == 1,
                              preflightTabBars.count == 1,
                              confirmationTexts.count == 1,
                              preflightScrollView.exists,
                              preflightNavigationBar.exists,
                              preflightTabBar.exists,
                              confirmationText.exists,
                              confirmationText.identifier.isEmpty,
                              confirmationText.elementType == .staticText,
                              confirmationText.label == confirmationLabel,
                              keyboard.exists,
                              keyboard.frame == observedKeyboardFrame,
                              inputAssistantViews.count == 1,
                              inputAssistantView.exists,
                              inputAssistantView.frame
                                == observedAssistantFrame,
                              keyboardIsAbsentOrInertOffApp(in: app),
                              preflight.exists
                                == preActionPreflightExists,
                              detailRoute.exists
                                == preActionDetailRouteExists,
                              zone.label == preActionZoneLabel,
                              (zone.value as? String)
                                == preActionZoneValue,
                              afterDark.label == preActionAfterDarkLabel,
                              (afterDark.value as? String)
                                == preActionAfterDarkValue,
                              safePosition.label
                                == preActionSafePositionLabel,
                              (safePosition.value as? String)
                                == preActionSafePositionValue,
                              !finalApplicationFrame.isNull,
                              !finalApplicationFrame.isEmpty,
                              !finalScrollFrame.isNull,
                              !finalScrollFrame.isEmpty,
                              !finalNavigationFrame.isNull,
                              !finalNavigationFrame.isEmpty,
                              !finalTabBarFrame.isNull,
                              !finalTabBarFrame.isEmpty,
                              !finalConfirmationFrame.isNull,
                              !finalConfirmationFrame.isEmpty,
                              finalSafeBottom > finalSafeTop,
                              finalConfirmationFrame.minY >= finalSafeTop,
                              finalConfirmationFrame.maxY <= finalSafeBottom else {
                            XCTFail(
                                "The minimum double-length preflight confirmation was not fully contained before capture."
                            )
                            return
                        }
                    }
                } else {
                    let expectedKeyboardFrame = CGRect(
                        x: 0,
                        y: 451,
                        width: 375,
                        height: 216
                    )
                    let observedAssistantFrame = inputAssistantView.frame
                    guard observedKeyboardFrame == expectedKeyboardFrame,
                          !observedAssistantFrame.isNull,
                          !observedAssistantFrame.isEmpty,
                          observedAssistantFrame.minY
                            < applicationFrame.maxY,
                          observedAssistantFrame.maxY
                            <= applicationFrame.maxY else {
                        XCTFail("The iOS 18 preflight keyboard or assistant does not match the visible QuickPath evidence.")
                        return
                    }
                    let minimumPreflightQuickPathIntroductionViews =
                        app.descendants(matching: .other).matching(
                            identifier: "UIContinuousPathIntroductionView"
                        )
                    let minimumPreflightQuickPathIntroductionCount =
                        minimumPreflightQuickPathIntroductionViews.count
                    if minimumPreflightQuickPathIntroductionCount > 0 {
                        let minimumPreflightQuickPathIntroductionView =
                            minimumPreflightQuickPathIntroductionViews.firstMatch
                        let minimumPreflightQuickPathButtons =
                            minimumPreflightQuickPathIntroductionView.descendants(
                                matching: .button
                            )
                        let minimumPreflightQuickPathStaticTexts =
                            minimumPreflightQuickPathIntroductionView.descendants(
                                matching: .staticText
                            )
                        let minimumPreflightQuickPathButton =
                            minimumPreflightQuickPathButtons.firstMatch
                        let minimumPreflightQuickPathFirstStaticText =
                            minimumPreflightQuickPathStaticTexts.element(
                                boundBy: 0
                            )
                        let minimumPreflightQuickPathSecondStaticText =
                            minimumPreflightQuickPathStaticTexts.element(
                                boundBy: 1
                            )
                        let minimumPreflightQuickPathFrameIsValid:
                            (CGRect) -> Bool = { frame in
                                !frame.isNull
                                    && !frame.isEmpty
                                    && !frame.isInfinite
                                    && frame.origin.x.isFinite
                                    && frame.origin.y.isFinite
                                    && frame.size.width.isFinite
                                    && frame.size.height.isFinite
                            }
                        guard minimumPreflightQuickPathIntroductionCount == 1,
                              minimumPreflightQuickPathButtons.count == 1,
                              minimumPreflightQuickPathStaticTexts.count == 2,
                              minimumPreflightQuickPathIntroductionView.exists,
                              minimumPreflightQuickPathIntroductionView
                                .elementType == .other,
                              minimumPreflightQuickPathIntroductionView
                                .identifier
                                == "UIContinuousPathIntroductionView",
                              minimumPreflightQuickPathButton.exists,
                              minimumPreflightQuickPathButton.elementType
                                == .button,
                              minimumPreflightQuickPathButton.identifier.isEmpty,
                              !minimumPreflightQuickPathButton.label
                                .trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                ).isEmpty,
                              minimumPreflightQuickPathButton.isEnabled,
                              minimumPreflightQuickPathButton.isHittable,
                              minimumPreflightQuickPathFirstStaticText.exists,
                              minimumPreflightQuickPathFirstStaticText
                                .elementType == .staticText,
                              minimumPreflightQuickPathFirstStaticText
                                .identifier.isEmpty,
                              !minimumPreflightQuickPathFirstStaticText.label
                                .trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                ).isEmpty,
                              minimumPreflightQuickPathSecondStaticText.exists,
                              minimumPreflightQuickPathSecondStaticText
                                .elementType == .staticText,
                              minimumPreflightQuickPathSecondStaticText
                                .identifier.isEmpty,
                              !minimumPreflightQuickPathSecondStaticText.label
                                .trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                ).isEmpty,
                              minimumPreflightQuickPathFrameIsValid(
                                  applicationFrame
                              ),
                              minimumPreflightQuickPathFrameIsValid(
                                  observedKeyboardFrame
                              ),
                              minimumPreflightQuickPathFrameIsValid(
                                  observedAssistantFrame
                              ),
                              minimumPreflightQuickPathFrameIsValid(
                                  minimumPreflightQuickPathIntroductionView.frame
                              ),
                              minimumPreflightQuickPathFrameIsValid(
                                  minimumPreflightQuickPathButton.frame
                              ),
                              minimumPreflightQuickPathFrameIsValid(
                                  minimumPreflightQuickPathFirstStaticText.frame
                              ),
                              minimumPreflightQuickPathFrameIsValid(
                                  minimumPreflightQuickPathSecondStaticText.frame
                              ),
                              applicationFrame.contains(
                                  observedKeyboardFrame
                              ),
                              applicationFrame.contains(
                                  observedAssistantFrame
                              ),
                              applicationFrame.contains(
                                  minimumPreflightQuickPathIntroductionView.frame
                              ),
                              minimumPreflightQuickPathIntroductionView.frame
                                .contains(minimumPreflightQuickPathButton.frame),
                              minimumPreflightQuickPathIntroductionView.frame
                                .contains(
                                    minimumPreflightQuickPathFirstStaticText.frame
                                ),
                              minimumPreflightQuickPathIntroductionView.frame
                                .contains(
                                    minimumPreflightQuickPathSecondStaticText.frame
                                ),
                              minimumPreflightQuickPathIntroductionView.frame
                                .intersects(observedKeyboardFrame),
                              (minimumPreflightQuickPathFirstStaticText.label
                                == minimumPreflightQuickPathButton.label
                                && minimumPreflightQuickPathFirstStaticText.frame
                                    .intersects(
                                        minimumPreflightQuickPathButton.frame
                                    ))
                                != (minimumPreflightQuickPathSecondStaticText.label
                                    == minimumPreflightQuickPathButton.label
                                    && minimumPreflightQuickPathSecondStaticText
                                        .frame.intersects(
                                            minimumPreflightQuickPathButton.frame
                                        )),
                              (minimumPreflightQuickPathFirstStaticText.label
                                == minimumPreflightQuickPathButton.label
                                    ? minimumPreflightQuickPathSecondStaticText
                                        .label
                                    : minimumPreflightQuickPathFirstStaticText
                                        .label)
                                != minimumPreflightQuickPathButton.label,
                              (minimumPreflightQuickPathFirstStaticText.label
                                == minimumPreflightQuickPathButton.label
                                    ? minimumPreflightQuickPathSecondStaticText
                                        .frame
                                    : minimumPreflightQuickPathFirstStaticText
                                        .frame).maxY
                                <= min(
                                    (minimumPreflightQuickPathFirstStaticText.label
                                        == minimumPreflightQuickPathButton.label
                                            ? minimumPreflightQuickPathFirstStaticText
                                                .frame
                                            : minimumPreflightQuickPathSecondStaticText
                                                .frame).minY,
                                    minimumPreflightQuickPathButton.frame.minY
                                ),
                              !(minimumPreflightQuickPathFirstStaticText.label
                                == minimumPreflightQuickPathButton.label
                                    ? minimumPreflightQuickPathSecondStaticText
                                        .frame
                                    : minimumPreflightQuickPathFirstStaticText
                                        .frame).intersects(
                                    minimumPreflightQuickPathButton.frame
                                ),
                              !(minimumPreflightQuickPathFirstStaticText.label
                                == minimumPreflightQuickPathButton.label
                                    ? minimumPreflightQuickPathSecondStaticText
                                        .frame
                                    : minimumPreflightQuickPathFirstStaticText
                                        .frame).intersects(
                                    minimumPreflightQuickPathFirstStaticText.label
                                        == minimumPreflightQuickPathButton.label
                                            ? minimumPreflightQuickPathFirstStaticText
                                                .frame
                                            : minimumPreflightQuickPathSecondStaticText
                                                .frame
                                ),
                              observedKeyboardFrame.contains(
                                  CGPoint(
                                      x: observedKeyboardFrame.midX,
                                      y: observedKeyboardFrame.minY
                                        + observedKeyboardFrame.height
                                            * 0.8425925925925926
                                  )
                              ),
                              minimumPreflightQuickPathIntroductionView.frame
                                .contains(
                                    CGPoint(
                                        x: observedKeyboardFrame.midX,
                                        y: observedKeyboardFrame.minY
                                            + observedKeyboardFrame.height
                                                * 0.8425925925925926
                                    )
                                ),
                              minimumPreflightQuickPathButton.frame.contains(
                                  CGPoint(
                                      x: observedKeyboardFrame.midX,
                                      y: observedKeyboardFrame.minY
                                        + observedKeyboardFrame.height
                                            * 0.8425925925925926
                                  )
                              ),
                              !(minimumPreflightQuickPathFirstStaticText.label
                                == minimumPreflightQuickPathButton.label
                                    ? minimumPreflightQuickPathSecondStaticText
                                        .frame
                                    : minimumPreflightQuickPathFirstStaticText
                                        .frame).contains(
                                    CGPoint(
                                        x: observedKeyboardFrame.midX,
                                        y: observedKeyboardFrame.minY
                                            + observedKeyboardFrame.height
                                                * 0.8425925925925926
                                    )
                                ) else {
                            XCTFail("The minimum-profile preflight QuickPath tutorial is incomplete or state changed before dismissal.")
                            return
                        }
                        keyboard.coordinate(
                            withNormalizedOffset: CGVector(
                                dx: 0.5,
                                dy: 0.8425925925925926
                            )
                        ).tap()
                        guard minimumPreflightQuickPathIntroductionView
                                .waitForNonExistence(timeout: 10),
                              minimumPreflightQuickPathIntroductionViews.count
                                == 0,
                              minimumPreflightQuickPathButtons.count == 0,
                              minimumPreflightQuickPathStaticTexts.count == 0
                        else {
                            XCTFail("The minimum-profile preflight QuickPath tutorial did not dismiss with state preserved.")
                            return
                        }
                    }
                    let restoredKeyboard = app.keyboards.firstMatch
                    let restoredDoneKey = app.keyboards.buttons["Done"]
                    let expectedDoneFrame = CGRect(
                        x: 281.5,
                        y: 620,
                        width: 93.5,
                        height: 46
                    )
                    guard restoredDoneKey.waitForExistence(timeout: 10),
                          restoredDoneKey.elementType == .button,
                          restoredDoneKey.identifier == "Done",
                          !restoredDoneKey.label
                            .trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).isEmpty,
                          restoredDoneKey.frame == expectedDoneFrame,
                          restoredDoneKey.isHittable,
                          restoredKeyboard.waitForExistence(timeout: 10),
                          restoredKeyboard.frame == observedKeyboardFrame,
                          inputAssistantViews.count == 1,
                          inputAssistantView.exists,
                          inputAssistantView.frame
                            == observedAssistantFrame,
                          wait(
                              for: zone,
                              predicate: "hasKeyboardFocus == true",
                              timeout: 10
                          ),
                          preflight.waitForExistence(timeout: 10),
                          preflight.exists
                            == preActionPreflightExists,
                          detailRoute.exists
                            == preActionDetailRouteExists,
                          zone.label == preActionZoneLabel,
                          (zone.value as? String) == preActionZoneValue,
                          afterDark.label == preActionAfterDarkLabel,
                          (afterDark.value as? String)
                            == preActionAfterDarkValue,
                          safePosition.label
                            == preActionSafePositionLabel,
                          (safePosition.value as? String)
                            == preActionSafePositionValue,
                          app.state == .runningForeground else {
                        XCTFail("The preflight state or content was not restored after dismissing the QuickPath tutorial.")
                        return
                    }

                    if automationShard?.shardID
                        == "s10.4.minimum.double-length" {
                        let verticalInset: CGFloat = 16
                        let receiverInset: CGFloat = 24
                        let minimumGestureDistance: CGFloat = 44
                        var serialPositioningDirection: CGFloat?
                        let positionVisiblePreflightControl:
                            (XCUIElement, String, String?) -> Bool = {
                                control, expectedLabel, expectedValue in
                                for _ in 0..<4 {
                                    guard app.state == .runningForeground,
                                          preflightScrollViews.count == 1,
                                          preflightNavigationBars.count == 1,
                                          inputAssistantViews.count == 1,
                                          afterDarkToggles.count == 1,
                                          safePositionToggles.count == 1,
                                          preflightScrollView.exists,
                                          preflightNavigationBar.exists,
                                          inputAssistantView.exists,
                                          control.exists,
                                          control.elementType == .switch,
                                          control.isEnabled,
                                          control.label == expectedLabel,
                                          (control.value as? String) == expectedValue,
                                          restoredKeyboard.exists,
                                          restoredDoneKey.exists else {
                                        XCTFail("The serial visible preflight positioning route changed.")
                                        return false
                                    }
                                    let interactiveSwitches = control.descendants(
                                        matching: .switch
                                    )
                                    let interactiveSwitch =
                                        interactiveSwitches.firstMatch
                                    guard interactiveSwitches.count == 1,
                                          interactiveSwitch.exists,
                                          interactiveSwitch.elementType == .switch,
                                          interactiveSwitch.isEnabled else {
                                        XCTFail("The serial visible preflight interactive switch changed.")
                                        return false
                                    }
                                    let liveApplicationFrame = app.frame
                                    let scrollFrame = preflightScrollView.frame
                                    let liveScrollFrame = scrollFrame.intersection(
                                        liveApplicationFrame
                                    )
                                    let navigationFrame = preflightNavigationBar.frame
                                    let assistantFrame = inputAssistantView.frame
                                    let interactiveSwitchFrame =
                                        interactiveSwitch.frame
                                    let safeTop = max(
                                        liveScrollFrame.minY,
                                        navigationFrame.maxY
                                    ) + verticalInset
                                    let safeBottom = min(
                                        liveScrollFrame.maxY,
                                        assistantFrame.minY
                                    ) - verticalInset
                                    let receiverTop = max(
                                        liveScrollFrame.minY,
                                        navigationFrame.maxY
                                    ) + receiverInset
                                    let receiverBottom = min(
                                        liveScrollFrame.maxY,
                                        assistantFrame.minY
                                    ) - receiverInset
                                    let minimumShift =
                                        safeTop - interactiveSwitchFrame.minY
                                    let maximumShift =
                                        safeBottom - interactiveSwitchFrame.maxY
                                    let receiverCapacity = receiverBottom - receiverTop
                                    guard !liveApplicationFrame.isNull,
                                          !liveApplicationFrame.isEmpty,
                                          !scrollFrame.isNull,
                                          !scrollFrame.isEmpty,
                                          !liveScrollFrame.isNull,
                                          !liveScrollFrame.isEmpty,
                                          !navigationFrame.isNull,
                                          !navigationFrame.isEmpty,
                                          !assistantFrame.isNull,
                                          !assistantFrame.isEmpty,
                                          !interactiveSwitchFrame.isNull,
                                          !interactiveSwitchFrame.isEmpty,
                                          assistantFrame == observedAssistantFrame,
                                          restoredKeyboard.frame
                                            == observedKeyboardFrame,
                                          safeBottom > safeTop,
                                          receiverCapacity
                                            >= minimumGestureDistance,
                                          interactiveSwitchFrame.height
                                            <= safeBottom - safeTop,
                                          minimumShift <= maximumShift else {
                                        XCTFail("The serial visible preflight keyboard-safe geometry is invalid.")
                                        return false
                                    }
                                    if interactiveSwitchFrame.minY >= safeTop,
                                       interactiveSwitchFrame.maxY <= safeBottom,
                                       interactiveSwitch.isHittable {
                                        return true
                                    }
                                    let dragDistance: CGFloat
                                    if maximumShift < 0 {
                                        let recognizedMinimum = max(
                                            minimumShift,
                                            -receiverCapacity
                                        )
                                        let recognizedMaximum = min(
                                            maximumShift,
                                            -minimumGestureDistance
                                        )
                                        if recognizedMinimum <= recognizedMaximum {
                                            dragDistance = recognizedMaximum
                                        } else if maximumShift < -receiverCapacity {
                                            dragDistance = -receiverCapacity
                                        } else {
                                            XCTFail("The serial visible preflight upward shift is not recognizable.")
                                            return false
                                        }
                                    } else if minimumShift > 0 {
                                        let recognizedMinimum = max(
                                            minimumShift,
                                            minimumGestureDistance
                                        )
                                        let recognizedMaximum = min(
                                            maximumShift,
                                            receiverCapacity
                                        )
                                        if recognizedMinimum <= recognizedMaximum {
                                            dragDistance = recognizedMinimum
                                        } else if minimumShift > receiverCapacity {
                                            dragDistance = receiverCapacity
                                        } else {
                                            XCTFail("The serial visible preflight downward shift is not recognizable.")
                                            return false
                                        }
                                    } else {
                                        XCTFail("The serial visible preflight control is contained but not hittable.")
                                        return false
                                    }
                                    let dragDirection: CGFloat = dragDistance > 0
                                        ? 1
                                        : -1
                                    if let serialPositioningDirection {
                                        guard dragDirection
                                            == serialPositioningDirection else {
                                            XCTFail("The serial visible preflight correction would reverse direction.")
                                            return false
                                        }
                                    } else {
                                        serialPositioningDirection = dragDirection
                                    }
                                    let scrollOrigin = preflightScrollView.coordinate(
                                        withNormalizedOffset: CGVector(dx: 0, dy: 0)
                                    )
                                    let dragStartOffsetY = dragDistance > 0
                                        ? receiverTop - scrollFrame.minY
                                        : receiverBottom - scrollFrame.minY
                                    let dragStart = scrollOrigin.withOffset(
                                        CGVector(
                                            dx: scrollFrame.width / 2,
                                            dy: dragStartOffsetY
                                        )
                                    )
                                    let dragEnd = dragStart.withOffset(
                                        CGVector(dx: 0, dy: dragDistance)
                                    )
                                    let interactiveSwitchMinYBeforeDrag =
                                        interactiveSwitchFrame.minY
                                    dragStart.press(
                                        forDuration: 0.2,
                                        thenDragTo: dragEnd,
                                        withVelocity: .slow,
                                        thenHoldForDuration: 0.2
                                    )
                                    guard (interactiveSwitch.frame.minY
                                        - interactiveSwitchMinYBeforeDrag)
                                        * dragDistance > 0 else {
                                        XCTFail("The serial visible preflight positioning gesture did not make signed progress.")
                                        return false
                                    }
                                }
                                XCTFail("The serial visible preflight control was not positioned within four attempts.")
                                return false
                            }
                        let serialAfterDarkPositioned =
                            positionVisiblePreflightControl(
                            afterDark,
                            preActionAfterDarkLabel,
                            preActionAfterDarkValue
                        )
                        guard serialAfterDarkPositioned,
                           afterDark.label == preActionAfterDarkLabel,
                           (afterDark.value as? String) == preActionAfterDarkValue,
                           afterDark.isEnabled,
                           app.state == .runningForeground else {
                            XCTFail("The serial visible preflight after-dark state was not preserved.")
                            return
                        }
                        let serialSafePositionPositioned =
                            positionVisiblePreflightControl(
                            safePosition,
                            preActionSafePositionLabel,
                            preActionSafePositionValue
                        )
                        guard serialSafePositionPositioned,
                           safePosition.label == preActionSafePositionLabel,
                           (safePosition.value as? String)
                            == preActionSafePositionValue,
                           safePosition.isEnabled,
                           app.state == .runningForeground,
                           wait(
                            for: zone,
                            predicate: "hasKeyboardFocus == true",
                            timeout: 10
                           ), restoredKeyboard.frame == observedKeyboardFrame,
                           inputAssistantView.frame == observedAssistantFrame else {
                            XCTFail("The serial visible preflight state was not restored and positioned before capture.")
                            return
                        }
                        let serialAfterDarkSwitches = afterDark.descendants(
                            matching: .switch
                        )
                        let serialSafePositionSwitches =
                            safePosition.descendants(matching: .switch)
                        let serialAfterDarkSwitch = serialAfterDarkSwitches
                            .firstMatch
                        let serialSafePositionSwitch =
                            serialSafePositionSwitches.firstMatch
                        let serialApplicationFrame = app.frame
                        let serialScrollFrame = preflightScrollView.frame
                            .intersection(serialApplicationFrame)
                        let serialNavigationFrame = preflightNavigationBar.frame
                        let serialAssistantFrame = inputAssistantView.frame
                        let serialSafeTop = max(
                            serialScrollFrame.minY,
                            serialNavigationFrame.maxY
                        ) + verticalInset
                        let serialSafeBottom = min(
                            serialScrollFrame.maxY,
                            serialAssistantFrame.minY
                        ) - verticalInset
                        guard serialAfterDarkSwitches.count == 1,
                              serialSafePositionSwitches.count == 1,
                              serialAfterDarkSwitch.exists,
                              serialSafePositionSwitch.exists,
                              serialAfterDarkSwitch.elementType == .switch,
                              serialSafePositionSwitch.elementType == .switch,
                              serialAfterDarkSwitch.isEnabled,
                              serialSafePositionSwitch.isEnabled,
                              serialSafePositionSwitch.isHittable,
                              serialAfterDarkPositioned,
                              serialSafePositionPositioned,
                              serialSafePositionSwitch.frame.minY
                                >= serialSafeTop,
                              serialSafePositionSwitch.frame.maxY
                                <= serialSafeBottom,
                              !serialApplicationFrame.isNull,
                              !serialApplicationFrame.isEmpty,
                              !serialScrollFrame.isNull,
                              !serialScrollFrame.isEmpty,
                              !serialNavigationFrame.isNull,
                              !serialNavigationFrame.isEmpty,
                              !serialAssistantFrame.isNull,
                              !serialAssistantFrame.isEmpty,
                              serialSafeBottom > serialSafeTop else {
                            XCTFail("The serial visible preflight safe-position state was not fully contained before capture.")
                            return
                        }
                    } else {
                    let verticalInset: CGFloat = 16
                    let receiverInset: CGFloat = 24
                    let minimumGestureDistance: CGFloat = 44
                    var preflightPositioningDirection: CGFloat?
                    for _ in 0..<4 {
                        guard app.state == .runningForeground,
                              preflightScrollViews.count == 1,
                              preflightNavigationBars.count == 1,
                              inputAssistantViews.count == 1,
                              afterDarkToggles.count == 1,
                              safePositionToggles.count == 1,
                              preflightScrollView.exists,
                              preflightNavigationBar.exists,
                              inputAssistantView.exists,
                              afterDark.exists,
                              safePosition.exists,
                              restoredKeyboard.exists,
                              restoredDoneKey.exists else {
                            XCTFail("The visible preflight positioning route changed.")
                            return
                        }
                        let liveApplicationFrame = app.frame
                        let scrollFrame = preflightScrollView.frame
                        let liveScrollFrame = scrollFrame.intersection(
                            liveApplicationFrame
                        )
                        let navigationFrame = preflightNavigationBar.frame
                        let assistantFrame = inputAssistantView.frame
                        let safeTop = max(
                            liveScrollFrame.minY,
                            navigationFrame.maxY
                        ) + verticalInset
                        let safeBottom = min(
                            liveScrollFrame.maxY,
                            assistantFrame.minY
                        ) - verticalInset
                        let receiverTop = max(
                            liveScrollFrame.minY,
                            navigationFrame.maxY
                        ) + receiverInset
                        let receiverBottom = min(
                            liveScrollFrame.maxY,
                            assistantFrame.minY
                        ) - receiverInset
                        let afterDarkFrame = afterDark.frame
                        let safePositionFrame = safePosition.frame
                        let targetTop = min(
                            afterDarkFrame.minY,
                            safePositionFrame.minY
                        )
                        let targetBottom = max(
                            afterDarkFrame.maxY,
                            safePositionFrame.maxY
                        )
                        guard !liveApplicationFrame.isNull,
                              !liveApplicationFrame.isEmpty,
                              !scrollFrame.isNull,
                              !scrollFrame.isEmpty,
                              !liveScrollFrame.isNull,
                              !liveScrollFrame.isEmpty,
                              !navigationFrame.isNull,
                              !navigationFrame.isEmpty,
                              !assistantFrame.isNull,
                              !assistantFrame.isEmpty,
                              !afterDarkFrame.isNull,
                              !afterDarkFrame.isEmpty,
                              !safePositionFrame.isNull,
                              !safePositionFrame.isEmpty,
                              assistantFrame == observedAssistantFrame,
                              restoredKeyboard.frame
                                == observedKeyboardFrame,
                              safeBottom > safeTop,
                              receiverBottom > receiverTop,
                              targetBottom - targetTop
                                <= safeBottom - safeTop else {
                            XCTFail("The visible preflight keyboard-safe geometry is invalid.")
                            return
                        }
                        if afterDarkFrame.minY >= safeTop,
                           afterDarkFrame.maxY <= safeBottom,
                           safePositionFrame.minY >= safeTop,
                           safePositionFrame.maxY <= safeBottom,
                           afterDark.isHittable,
                           safePosition.isHittable {
                            break
                        }

                        let minimumShift = max(
                            safeTop - afterDarkFrame.minY,
                            safeTop - safePositionFrame.minY
                        )
                        let maximumShift = min(
                            safeBottom - afterDarkFrame.maxY,
                            safeBottom - safePositionFrame.maxY
                        )
                        let receiverCapacity = receiverBottom - receiverTop
                        guard minimumShift <= maximumShift,
                              receiverCapacity
                                >= minimumGestureDistance else {
                            XCTFail("The visible preflight controls have no common feasible interval.")
                            return
                        }
                        let dragDistance: CGFloat
                        if maximumShift < 0 {
                            let recognizedMinimum = max(
                                minimumShift,
                                -receiverCapacity
                            )
                            let recognizedMaximum = min(
                                maximumShift,
                                -minimumGestureDistance
                            )
                            if recognizedMinimum <= recognizedMaximum {
                                dragDistance = recognizedMaximum
                            } else if maximumShift < -receiverCapacity {
                                dragDistance = -receiverCapacity
                            } else {
                                XCTFail("The visible preflight upward shift is not recognizable.")
                                return
                            }
                        } else if minimumShift > 0 {
                            let recognizedMinimum = max(
                                minimumShift,
                                minimumGestureDistance
                            )
                            let recognizedMaximum = min(
                                maximumShift,
                                receiverCapacity
                            )
                            if recognizedMinimum <= recognizedMaximum {
                                dragDistance = recognizedMinimum
                            } else if minimumShift > receiverCapacity {
                                dragDistance = receiverCapacity
                            } else {
                                XCTFail("The visible preflight downward shift is not recognizable.")
                                return
                            }
                        } else {
                            XCTFail("The visible preflight controls are contained but not hittable.")
                            return
                        }

                        let dragDirection: CGFloat = dragDistance > 0
                            ? 1
                            : -1
                        if let preflightPositioningDirection {
                            guard dragDirection
                                == preflightPositioningDirection else {
                                XCTFail("The visible preflight correction would reverse direction.")
                                return
                            }
                        } else {
                            preflightPositioningDirection = dragDirection
                        }

                        let scrollOrigin = preflightScrollView.coordinate(
                            withNormalizedOffset: CGVector(dx: 0, dy: 0)
                        )
                        let dragStartOffsetY = dragDistance > 0
                            ? receiverTop - scrollFrame.minY
                            : receiverBottom - scrollFrame.minY
                        let dragStart = scrollOrigin.withOffset(
                            CGVector(
                                dx: scrollFrame.width / 2,
                                dy: dragStartOffsetY
                            )
                        )
                        let dragEnd = dragStart.withOffset(
                            CGVector(dx: 0, dy: dragDistance)
                        )
                        let afterDarkMinYBeforeDrag = afterDarkFrame.minY
                        let safePositionMinYBeforeDrag =
                            safePositionFrame.minY
                        dragStart.press(
                            forDuration: 0.2,
                            thenDragTo: dragEnd,
                            withVelocity: .slow,
                            thenHoldForDuration: 0.2
                        )
                        let afterDarkMovement =
                            afterDark.frame.minY - afterDarkMinYBeforeDrag
                        let safePositionMovement =
                            safePosition.frame.minY
                                - safePositionMinYBeforeDrag
                        guard afterDarkMovement * dragDistance > 0,
                              safePositionMovement * dragDistance > 0 else {
                            XCTFail("The visible preflight positioning gesture did not make signed progress.")
                            return
                        }
                    }

                    let finalApplicationFrame = app.frame
                    let finalScrollFrame = preflightScrollView.frame
                        .intersection(finalApplicationFrame)
                    let finalNavigationFrame =
                        preflightNavigationBar.frame
                    let finalAssistantFrame = inputAssistantView.frame
                    let finalSafeTop = max(
                        finalScrollFrame.minY,
                        finalNavigationFrame.maxY
                    ) + verticalInset
                    let finalSafeBottom = min(
                        finalScrollFrame.maxY,
                        finalAssistantFrame.minY
                    ) - verticalInset
                    let finalAfterDarkFrame = afterDark.frame
                    let finalSafePositionFrame = safePosition.frame
                    guard app.state == .runningForeground,
                          preflightScrollViews.count == 1,
                          preflightNavigationBars.count == 1,
                          inputAssistantViews.count == 1,
                          afterDarkToggles.count == 1,
                          safePositionToggles.count == 1,
                          preflightScrollView.exists,
                          preflightNavigationBar.exists,
                          inputAssistantView.exists,
                          afterDark.exists,
                          safePosition.exists,
                          restoredKeyboard.exists,
                          restoredKeyboard.frame
                            == observedKeyboardFrame,
                          restoredDoneKey.exists,
                          restoredDoneKey.elementType == .button,
                          restoredDoneKey.identifier == "Done",
                           !restoredDoneKey.label
                             .trimmingCharacters(
                                 in: .whitespacesAndNewlines
                             ).isEmpty,
                          restoredDoneKey.frame == expectedDoneFrame,
                          restoredDoneKey.isHittable,
                          finalAssistantFrame == observedAssistantFrame,
                          wait(
                              for: zone,
                              predicate: "hasKeyboardFocus == true",
                              timeout: 10
                          ),
                          preflight.exists
                            == preActionPreflightExists,
                          detailRoute.exists
                            == preActionDetailRouteExists,
                          zone.label == preActionZoneLabel,
                          (zone.value as? String) == preActionZoneValue,
                          afterDark.label == preActionAfterDarkLabel,
                          (afterDark.value as? String)
                            == preActionAfterDarkValue,
                          safePosition.label
                            == preActionSafePositionLabel,
                          (safePosition.value as? String)
                            == preActionSafePositionValue,
                          !finalApplicationFrame.isNull,
                          !finalApplicationFrame.isEmpty,
                          !finalScrollFrame.isNull,
                          !finalScrollFrame.isEmpty,
                          !finalNavigationFrame.isNull,
                          !finalNavigationFrame.isEmpty,
                          !finalAssistantFrame.isNull,
                          !finalAssistantFrame.isEmpty,
                          finalAfterDarkFrame.minY >= finalSafeTop,
                          finalAfterDarkFrame.maxY
                            <= finalSafeBottom,
                          finalSafePositionFrame.minY >= finalSafeTop,
                          finalSafePositionFrame.maxY
                            <= finalSafeBottom,
                          afterDark.isHittable,
                          safePosition.isHittable else {
                        XCTFail("The visible preflight state was not fully restored and positioned before capture.")
                        return
                    }
                    }
                }
            }
        }
        if automationShard?.deviceProfileID
            == "iphone-17-ios-26.2-current" {
            let currentPreflightQuickPathIntroductionViews =
                app.descendants(matching: .other).matching(
                    identifier: "UIContinuousPathIntroductionView"
                )
            let currentPreflightQuickPathIntroductionCount =
                currentPreflightQuickPathIntroductionViews.count
            if currentPreflightQuickPathIntroductionCount > 0 {
                let currentPreflightQuickPathIntroductionView =
                    currentPreflightQuickPathIntroductionViews.firstMatch
                let currentPreflightQuickPathButtons =
                    currentPreflightQuickPathIntroductionView.descendants(
                        matching: .button
                    )
                let currentPreflightQuickPathStaticTexts =
                    currentPreflightQuickPathIntroductionView.descendants(
                        matching: .staticText
                    )
                let currentPreflightQuickPathButton =
                    currentPreflightQuickPathButtons.firstMatch
                let currentPreflightQuickPathFirstStaticText =
                    currentPreflightQuickPathStaticTexts.element(boundBy: 0)
                let currentPreflightQuickPathSecondStaticText =
                    currentPreflightQuickPathStaticTexts.element(boundBy: 1)

                let currentPreflightQuickPathPreflightScreens =
                    app.scrollViews.matching(
                        identifier: "s3.preflight.screen"
                    )
                let currentPreflightQuickPathScrollViews =
                    app.scrollViews.containing(
                        .textField,
                        identifier: "s3.preflight.time-zone"
                    )
                let currentPreflightQuickPathZoneFields =
                    app.textFields.matching(
                        identifier: "s3.preflight.time-zone"
                    )
                let currentPreflightQuickPathSignDetailScreens =
                    app.scrollViews.matching(
                        identifier: "s2.sign-detail.screen"
                    )
                let currentPreflightQuickPathKeyboards = app.keyboards
                let currentPreflightQuickPathPreflightScreen =
                    currentPreflightQuickPathPreflightScreens.firstMatch
                let currentPreflightQuickPathScrollView =
                    currentPreflightQuickPathScrollViews.firstMatch
                let currentPreflightQuickPathZoneField =
                    currentPreflightQuickPathZoneFields.firstMatch
                let currentPreflightQuickPathKeyboard =
                    currentPreflightQuickPathKeyboards.firstMatch
                let currentPreflightQuickPathDoneKeys =
                    currentPreflightQuickPathKeyboard.buttons.matching(
                        identifier: "Done"
                    )
                let currentPreflightQuickPathDoneKey =
                    currentPreflightQuickPathDoneKeys.firstMatch

                let currentPreflightQuickPathConfirmationSwitches =
                    app.switches.matching(
                        identifier: "s3.preflight.time-zone-confirmed"
                    )
                let currentPreflightQuickPathAfterDarkSwitches =
                    app.switches.matching(
                        identifier: "s3.preflight.after-dark"
                    )
                let currentPreflightQuickPathSafePositionSwitches =
                    app.switches.matching(
                        identifier: "s3.preflight.safe-position"
                    )
                let currentPreflightQuickPathConfirmationSwitch =
                    currentPreflightQuickPathConfirmationSwitches.firstMatch
                let currentPreflightQuickPathAfterDarkSwitch =
                    currentPreflightQuickPathAfterDarkSwitches.firstMatch
                let currentPreflightQuickPathSafePositionSwitch =
                    currentPreflightQuickPathSafePositionSwitches.firstMatch

                let currentPreflightQuickPathFrameIsValid:
                    (CGRect) -> Bool = { frame in
                        !frame.isNull
                            && !frame.isEmpty
                            && !frame.isInfinite
                            && frame.origin.x.isFinite
                            && frame.origin.y.isFinite
                            && frame.size.width.isFinite
                            && frame.size.height.isFinite
                    }
                let currentPreflightQuickPathZoneFocus = NSPredicate(
                    format: "hasKeyboardFocus == true"
                )

                guard currentPreflightQuickPathIntroductionCount == 1,
                      currentPreflightQuickPathButtons.count == 1,
                      currentPreflightQuickPathStaticTexts.count == 2,
                      currentPreflightQuickPathPreflightScreens.count == 1,
                      currentPreflightQuickPathScrollViews.count == 1,
                      currentPreflightQuickPathZoneFields.count == 1,
                      currentPreflightQuickPathSignDetailScreens.count == 0,
                      currentPreflightQuickPathKeyboards.count == 1,
                      currentPreflightQuickPathDoneKeys.count == 1,
                      currentPreflightQuickPathConfirmationSwitches.count
                        == 1,
                      currentPreflightQuickPathAfterDarkSwitches.count == 1,
                      currentPreflightQuickPathSafePositionSwitches.count
                        == 1,
                      currentPreflightQuickPathIntroductionView.exists,
                      currentPreflightQuickPathIntroductionView.elementType
                        == .other,
                      currentPreflightQuickPathIntroductionView.identifier
                        == "UIContinuousPathIntroductionView",
                      currentPreflightQuickPathButton.exists,
                      currentPreflightQuickPathButton.elementType == .button,
                      currentPreflightQuickPathButton.identifier.isEmpty,
                      !currentPreflightQuickPathButton.label
                        .trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty,
                      currentPreflightQuickPathButton.isEnabled,
                      currentPreflightQuickPathButton.isHittable,
                      currentPreflightQuickPathFirstStaticText.exists,
                      currentPreflightQuickPathFirstStaticText.elementType
                        == .staticText,
                      currentPreflightQuickPathFirstStaticText.identifier
                        .isEmpty,
                      !currentPreflightQuickPathFirstStaticText.label
                        .trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty,
                      currentPreflightQuickPathSecondStaticText.exists,
                      currentPreflightQuickPathSecondStaticText.elementType
                        == .staticText,
                      currentPreflightQuickPathSecondStaticText.identifier
                        .isEmpty,
                      !currentPreflightQuickPathSecondStaticText.label
                        .trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty,
                      currentPreflightQuickPathPreflightScreen.exists,
                      currentPreflightQuickPathPreflightScreen.elementType
                        == .scrollView,
                      currentPreflightQuickPathPreflightScreen.identifier
                        == "s3.preflight.screen",
                      currentPreflightQuickPathScrollView.exists,
                      currentPreflightQuickPathScrollView.elementType
                        == .scrollView,
                      currentPreflightQuickPathScrollView.identifier
                        == "s3.preflight.screen",
                      currentPreflightQuickPathZoneField.exists,
                      currentPreflightQuickPathZoneField.elementType
                        == .textField,
                      currentPreflightQuickPathZoneField.identifier
                        == "s3.preflight.time-zone",
                      !currentPreflightQuickPathZoneField.label
                        .trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty,
                      (currentPreflightQuickPathZoneField.value as? String)
                        == nil
                        || (currentPreflightQuickPathZoneField.value
                            as? String)?.isEmpty == true,
                      currentPreflightQuickPathZoneField.placeholderValue?
                        .trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty == false,
                      currentPreflightQuickPathZoneFocus.evaluate(
                          with: currentPreflightQuickPathZoneField
                      ),
                      currentPreflightQuickPathKeyboard.exists,
                      currentPreflightQuickPathKeyboard.elementType
                        == .keyboard,
                      currentPreflightQuickPathDoneKey.exists,
                      currentPreflightQuickPathDoneKey.elementType == .button,
                      currentPreflightQuickPathDoneKey.identifier == "Done",
                      currentPreflightQuickPathDoneKey.label.lowercased()
                        == "done",
                      currentPreflightQuickPathDoneKey.isEnabled,
                      !currentPreflightQuickPathDoneKey.isHittable,
                      currentPreflightQuickPathConfirmationSwitch.exists,
                      currentPreflightQuickPathConfirmationSwitch.elementType
                        == .switch,
                      currentPreflightQuickPathConfirmationSwitch.identifier
                        == "s3.preflight.time-zone-confirmed",
                      !currentPreflightQuickPathConfirmationSwitch.label
                        .trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty,
                      currentPreflightQuickPathAfterDarkSwitch.exists,
                      currentPreflightQuickPathAfterDarkSwitch.elementType
                        == .switch,
                      currentPreflightQuickPathAfterDarkSwitch.identifier
                        == "s3.preflight.after-dark",
                      !currentPreflightQuickPathAfterDarkSwitch.label
                        .trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty,
                      currentPreflightQuickPathSafePositionSwitch.exists,
                      currentPreflightQuickPathSafePositionSwitch.elementType
                        == .switch,
                      currentPreflightQuickPathSafePositionSwitch.identifier
                        == "s3.preflight.safe-position",
                      !currentPreflightQuickPathSafePositionSwitch.label
                        .trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty,
                      currentPreflightQuickPathFrameIsValid(app.frame),
                      currentPreflightQuickPathFrameIsValid(
                          currentPreflightQuickPathPreflightScreen.frame
                      ),
                      currentPreflightQuickPathFrameIsValid(
                          currentPreflightQuickPathScrollView.frame
                      ),
                      currentPreflightQuickPathFrameIsValid(
                          currentPreflightQuickPathZoneField.frame
                      ),
                      currentPreflightQuickPathFrameIsValid(
                          currentPreflightQuickPathKeyboard.frame
                      ),
                      currentPreflightQuickPathFrameIsValid(
                          currentPreflightQuickPathDoneKey.frame
                      ),
                      currentPreflightQuickPathFrameIsValid(
                          currentPreflightQuickPathIntroductionView.frame
                      ),
                      currentPreflightQuickPathFrameIsValid(
                          currentPreflightQuickPathButton.frame
                      ),
                      currentPreflightQuickPathFrameIsValid(
                          currentPreflightQuickPathFirstStaticText.frame
                      ),
                      currentPreflightQuickPathFrameIsValid(
                          currentPreflightQuickPathSecondStaticText.frame
                      ),
                      currentPreflightQuickPathFrameIsValid(
                          currentPreflightQuickPathConfirmationSwitch.frame
                      ),
                      currentPreflightQuickPathFrameIsValid(
                          currentPreflightQuickPathAfterDarkSwitch.frame
                      ),
                      currentPreflightQuickPathFrameIsValid(
                          currentPreflightQuickPathSafePositionSwitch.frame
                      ),
                      (currentPreflightQuickPathFirstStaticText.label
                        == currentPreflightQuickPathButton.label)
                        != (currentPreflightQuickPathSecondStaticText.label
                            == currentPreflightQuickPathButton.label),
                      currentPreflightQuickPathFirstStaticText.frame
                        .intersects(
                            currentPreflightQuickPathButton.frame
                        )
                        == (currentPreflightQuickPathFirstStaticText.label
                            == currentPreflightQuickPathButton.label),
                      currentPreflightQuickPathSecondStaticText.frame
                        .intersects(
                            currentPreflightQuickPathButton.frame
                        )
                        == (currentPreflightQuickPathSecondStaticText.label
                            == currentPreflightQuickPathButton.label),
                      !currentPreflightQuickPathFirstStaticText.frame
                        .intersects(
                            currentPreflightQuickPathSecondStaticText.frame
                        ),
                      (
                          currentPreflightQuickPathFirstStaticText.label
                            == currentPreflightQuickPathButton.label
                              ? currentPreflightQuickPathSecondStaticText
                                  .frame.maxY
                              : currentPreflightQuickPathFirstStaticText
                                  .frame.maxY
                      ) <= (
                          currentPreflightQuickPathFirstStaticText.label
                            == currentPreflightQuickPathButton.label
                              ? currentPreflightQuickPathFirstStaticText
                                  .frame.minY
                              : currentPreflightQuickPathSecondStaticText
                                  .frame.minY
                      ),
                      (
                          currentPreflightQuickPathFirstStaticText.label
                            == currentPreflightQuickPathButton.label
                              ? currentPreflightQuickPathSecondStaticText
                                  .frame.maxY
                              : currentPreflightQuickPathFirstStaticText
                                  .frame.maxY
                      ) <= currentPreflightQuickPathButton.frame.minY,
                      app.frame.contains(
                          currentPreflightQuickPathPreflightScreen.frame
                      ),
                      app.frame.contains(
                          currentPreflightQuickPathScrollView.frame
                      ),
                      app.frame.contains(
                          currentPreflightQuickPathZoneField.frame
                      ),
                      app.frame.contains(
                          currentPreflightQuickPathKeyboard.frame
                      ),
                      app.frame.contains(
                          currentPreflightQuickPathIntroductionView.frame
                      ),
                      currentPreflightQuickPathPreflightScreen.frame.contains(
                          currentPreflightQuickPathZoneField.frame
                      ),
                      currentPreflightQuickPathScrollView.frame.contains(
                          currentPreflightQuickPathZoneField.frame
                      ),
                      currentPreflightQuickPathKeyboard.frame.contains(
                          currentPreflightQuickPathDoneKey.frame
                      ),
                      currentPreflightQuickPathIntroductionView.frame.contains(
                          currentPreflightQuickPathButton.frame
                      ),
                      currentPreflightQuickPathIntroductionView.frame.contains(
                          currentPreflightQuickPathFirstStaticText.frame
                      ),
                      currentPreflightQuickPathIntroductionView.frame.contains(
                          currentPreflightQuickPathSecondStaticText.frame
                      ),
                      currentPreflightQuickPathIntroductionView.frame.contains(
                          currentPreflightQuickPathDoneKey.frame
                      ),
                      currentPreflightQuickPathIntroductionView.frame
                        .intersects(
                            currentPreflightQuickPathKeyboard.frame
                        ),
                      app.state == .runningForeground else {
                    XCTFail(
                        "The current-profile preflight QuickPath tutorial is incomplete or state changed before dismissal."
                    )
                    return
                }

                let expectedCurrentPreflightQuickPathApplicationFrame =
                    app.frame
                let expectedCurrentPreflightQuickPathPreflightFrame =
                    currentPreflightQuickPathPreflightScreen.frame
                let expectedCurrentPreflightQuickPathScrollFrame =
                    currentPreflightQuickPathScrollView.frame
                let expectedCurrentPreflightQuickPathZoneFrame =
                    currentPreflightQuickPathZoneField.frame
                let expectedCurrentPreflightQuickPathKeyboardFrame =
                    currentPreflightQuickPathKeyboard.frame
                let expectedCurrentPreflightQuickPathDoneFrame =
                    currentPreflightQuickPathDoneKey.frame
                let expectedCurrentPreflightQuickPathZoneLabel =
                    currentPreflightQuickPathZoneField.label
                let expectedCurrentPreflightQuickPathZoneValue =
                    currentPreflightQuickPathZoneField.value as? String
                let expectedCurrentPreflightQuickPathZonePlaceholder =
                    currentPreflightQuickPathZoneField.placeholderValue
                let expectedCurrentPreflightQuickPathZoneHasFocus =
                    currentPreflightQuickPathZoneFocus.evaluate(
                        with: currentPreflightQuickPathZoneField
                    )
                let expectedCurrentPreflightQuickPathDoneLabel =
                    currentPreflightQuickPathDoneKey.label
                let expectedCurrentPreflightQuickPathConfirmationLabel =
                    currentPreflightQuickPathConfirmationSwitch.label
                let expectedCurrentPreflightQuickPathConfirmationValue =
                    currentPreflightQuickPathConfirmationSwitch.value
                        as? String
                let expectedCurrentPreflightQuickPathConfirmationEnabled =
                    currentPreflightQuickPathConfirmationSwitch.isEnabled
                let expectedCurrentPreflightQuickPathConfirmationHittable =
                    currentPreflightQuickPathConfirmationSwitch.isHittable
                let expectedCurrentPreflightQuickPathConfirmationFrame =
                    currentPreflightQuickPathConfirmationSwitch.frame
                let expectedCurrentPreflightQuickPathAfterDarkLabel =
                    currentPreflightQuickPathAfterDarkSwitch.label
                let expectedCurrentPreflightQuickPathAfterDarkValue =
                    currentPreflightQuickPathAfterDarkSwitch.value as? String
                let expectedCurrentPreflightQuickPathAfterDarkEnabled =
                    currentPreflightQuickPathAfterDarkSwitch.isEnabled
                let expectedCurrentPreflightQuickPathAfterDarkHittable =
                    currentPreflightQuickPathAfterDarkSwitch.isHittable
                let expectedCurrentPreflightQuickPathAfterDarkFrame =
                    currentPreflightQuickPathAfterDarkSwitch.frame
                let expectedCurrentPreflightQuickPathSafePositionLabel =
                    currentPreflightQuickPathSafePositionSwitch.label
                let expectedCurrentPreflightQuickPathSafePositionValue =
                    currentPreflightQuickPathSafePositionSwitch.value
                        as? String
                let expectedCurrentPreflightQuickPathSafePositionEnabled =
                    currentPreflightQuickPathSafePositionSwitch.isEnabled
                let expectedCurrentPreflightQuickPathSafePositionHittable =
                    currentPreflightQuickPathSafePositionSwitch.isHittable
                let expectedCurrentPreflightQuickPathSafePositionFrame =
                    currentPreflightQuickPathSafePositionSwitch.frame

                currentPreflightQuickPathButton.tap()
                guard currentPreflightQuickPathIntroductionView
                        .waitForNonExistence(timeout: 10),
                      currentPreflightQuickPathIntroductionViews.count == 0,
                      currentPreflightQuickPathButtons.count == 0,
                      currentPreflightQuickPathStaticTexts.count == 0,
                      currentPreflightQuickPathPreflightScreens.count == 1,
                      currentPreflightQuickPathScrollViews.count == 1,
                      currentPreflightQuickPathZoneFields.count == 1,
                      currentPreflightQuickPathSignDetailScreens.count == 0,
                      currentPreflightQuickPathKeyboards.count == 1,
                      currentPreflightQuickPathDoneKeys.count == 1,
                      currentPreflightQuickPathConfirmationSwitches.count
                        == 1,
                      currentPreflightQuickPathAfterDarkSwitches.count == 1,
                      currentPreflightQuickPathSafePositionSwitches.count
                        == 1,
                      currentPreflightQuickPathPreflightScreen.exists,
                      currentPreflightQuickPathPreflightScreen.elementType
                        == .scrollView,
                      currentPreflightQuickPathPreflightScreen.identifier
                        == "s3.preflight.screen",
                      currentPreflightQuickPathScrollView.exists,
                      currentPreflightQuickPathScrollView.elementType
                        == .scrollView,
                      currentPreflightQuickPathScrollView.identifier
                        == "s3.preflight.screen",
                      currentPreflightQuickPathZoneField.exists,
                      currentPreflightQuickPathZoneField.elementType
                        == .textField,
                      currentPreflightQuickPathZoneField.identifier
                        == "s3.preflight.time-zone",
                      currentPreflightQuickPathZoneField.label
                        == expectedCurrentPreflightQuickPathZoneLabel,
                      (currentPreflightQuickPathZoneField.value as? String)
                        == expectedCurrentPreflightQuickPathZoneValue,
                      currentPreflightQuickPathZoneField.placeholderValue
                        == expectedCurrentPreflightQuickPathZonePlaceholder,
                      currentPreflightQuickPathZoneFocus.evaluate(
                          with: currentPreflightQuickPathZoneField
                      ) == expectedCurrentPreflightQuickPathZoneHasFocus,
                      currentPreflightQuickPathKeyboard.exists,
                      currentPreflightQuickPathKeyboard.elementType
                        == .keyboard,
                      currentPreflightQuickPathDoneKey.exists,
                      currentPreflightQuickPathDoneKey.elementType == .button,
                      currentPreflightQuickPathDoneKey.identifier == "Done",
                      currentPreflightQuickPathDoneKey.label
                        == expectedCurrentPreflightQuickPathDoneLabel,
                      currentPreflightQuickPathDoneKey.label.lowercased()
                        == "done",
                      currentPreflightQuickPathDoneKey.isEnabled,
                      currentPreflightQuickPathDoneKey.isHittable,
                      currentPreflightQuickPathConfirmationSwitch.exists,
                      currentPreflightQuickPathConfirmationSwitch.elementType
                        == .switch,
                      currentPreflightQuickPathConfirmationSwitch.identifier
                        == "s3.preflight.time-zone-confirmed",
                      currentPreflightQuickPathConfirmationSwitch.label
                        == expectedCurrentPreflightQuickPathConfirmationLabel,
                      (currentPreflightQuickPathConfirmationSwitch.value
                        as? String)
                        == expectedCurrentPreflightQuickPathConfirmationValue,
                      currentPreflightQuickPathConfirmationSwitch.isEnabled
                        == expectedCurrentPreflightQuickPathConfirmationEnabled,
                      currentPreflightQuickPathConfirmationSwitch.isHittable
                        == expectedCurrentPreflightQuickPathConfirmationHittable,
                      currentPreflightQuickPathAfterDarkSwitch.exists,
                      currentPreflightQuickPathAfterDarkSwitch.elementType
                        == .switch,
                      currentPreflightQuickPathAfterDarkSwitch.identifier
                        == "s3.preflight.after-dark",
                      currentPreflightQuickPathAfterDarkSwitch.label
                        == expectedCurrentPreflightQuickPathAfterDarkLabel,
                      (currentPreflightQuickPathAfterDarkSwitch.value
                        as? String)
                        == expectedCurrentPreflightQuickPathAfterDarkValue,
                      currentPreflightQuickPathAfterDarkSwitch.isEnabled
                        == expectedCurrentPreflightQuickPathAfterDarkEnabled,
                      currentPreflightQuickPathAfterDarkSwitch.isHittable
                        == expectedCurrentPreflightQuickPathAfterDarkHittable,
                      currentPreflightQuickPathSafePositionSwitch.exists,
                      currentPreflightQuickPathSafePositionSwitch.elementType
                        == .switch,
                      currentPreflightQuickPathSafePositionSwitch.identifier
                        == "s3.preflight.safe-position",
                      currentPreflightQuickPathSafePositionSwitch.label
                        == expectedCurrentPreflightQuickPathSafePositionLabel,
                      (currentPreflightQuickPathSafePositionSwitch.value
                        as? String)
                        == expectedCurrentPreflightQuickPathSafePositionValue,
                      currentPreflightQuickPathSafePositionSwitch.isEnabled
                        == expectedCurrentPreflightQuickPathSafePositionEnabled,
                      currentPreflightQuickPathSafePositionSwitch.isHittable
                        == expectedCurrentPreflightQuickPathSafePositionHittable,
                      app.frame
                        == expectedCurrentPreflightQuickPathApplicationFrame,
                      currentPreflightQuickPathPreflightScreen.frame
                        == expectedCurrentPreflightQuickPathPreflightFrame,
                      currentPreflightQuickPathScrollView.frame
                        == expectedCurrentPreflightQuickPathScrollFrame,
                      currentPreflightQuickPathZoneField.frame
                        == expectedCurrentPreflightQuickPathZoneFrame,
                      currentPreflightQuickPathKeyboard.frame
                        == expectedCurrentPreflightQuickPathKeyboardFrame,
                      currentPreflightQuickPathDoneKey.frame
                        == expectedCurrentPreflightQuickPathDoneFrame,
                      currentPreflightQuickPathConfirmationSwitch.frame
                        == expectedCurrentPreflightQuickPathConfirmationFrame,
                      currentPreflightQuickPathAfterDarkSwitch.frame
                        == expectedCurrentPreflightQuickPathAfterDarkFrame,
                      currentPreflightQuickPathSafePositionSwitch.frame
                        == expectedCurrentPreflightQuickPathSafePositionFrame,
                      app.state == .runningForeground else {
                    XCTFail(
                        "The current-profile preflight QuickPath tutorial did not dismiss with state preserved."
                    )
                    return
                }
            }
        }
        if diagnosticProbe == .minimumPreflight {
            try completeFocusedDiagnosticPreflight(in: app)
            throw FocusedDiagnosticProbeStop.completed
        }
        captureBaseline("state.check-preflight.ready", in: app)

        scroll(zone, in: app)
        zone.tap()
        zone.typeText("America/New_York")
        let doneKey = app.keyboards.buttons["Done"]
        if doneKey.exists && doneKey.isHittable {
            doneKey.tap()
        } else {
            dismissKeyboard(in: app)
        }
        XCTAssertTrue(
            wait(
                for: app.keyboards.firstMatch,
                predicate: "exists == false",
                timeout: 10
            )
        )
        setToggle("s3.preflight.time-zone-confirmed", in: app)
        if automationShard?.shardID == "s10.4.current.ax-text" {
            guard positionPreflightAfterDarkForAXText(in: app) else {
                XCTFail(
                    "S10.4 AX-text Preflight after-dark positioning failed"
                )
                return
            }
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
        if automationShard?.shardID == "s10.4.current.ax-text",
           shouldPrepareNormalEvidence(
               for: "state.capture.wide-ready",
               in: app
           ) {
            let captureScrollViews = app.scrollViews.matching(
                identifier: "s3.capture.screen"
            )
            let captureNavigationBars = app.navigationBars
            let captureTabBars = app.tabBars
            let captureInputViews = app.otherElements.matching(
                NSPredicate(format: "identifier == %@", "inputView")
            )
            let captureScroll = captureScrollViews.firstMatch
            let captureNavigationBar = captureNavigationBars.firstMatch
            let captureHeadingQuery = app.descendants(matching: .any).matching(
                identifier: "s3.capture.heading"
            )
            let takePhotoQuery = app.descendants(matching: .any).matching(
                identifier: "s3.capture.take-photo"
            )
            let choosePhotosQuery = app.descendants(matching: .any).matching(
                identifier: "s3.capture.choose-photos"
            )
            let cannotCompleteQuery = app.descendants(matching: .any).matching(
                identifier: "s3.capture.cannot-complete"
            )
            let importFixtureQuery = app.descendants(matching: .any).matching(
                identifier: "s3.capture.import-fixture"
            )
            let capturePreviewQuery = app.descendants(matching: .any).matching(
                identifier: "s3.capture.preview"
            )
            let captureHeading = captureHeadingQuery.firstMatch
            let takePhoto = takePhotoQuery.firstMatch
            let choosePhotos = choosePhotosQuery.firstMatch
            let cannotComplete = cannotCompleteQuery.firstMatch
            let importFixture = importFixtureQuery.firstMatch
            let capturePreview = capturePreviewQuery.firstMatch
            let frozenCaptureElements = [
                captureScroll,
                captureNavigationBar,
                captureHeading,
                takePhoto,
                choosePhotos,
                cannotComplete,
                importFixture,
            ]
            guard captureScrollViews.count == 1,
                  captureNavigationBars.count == 1,
                  captureTabBars.count <= 1,
                  captureHeadingQuery.count == 1,
                  takePhotoQuery.count == 1,
                  choosePhotosQuery.count == 1,
                  cannotCompleteQuery.count == 1,
                  importFixtureQuery.count == 1,
                  capturePreviewQuery.count == 0,
                  app.keyboards.count == 0,
                  captureInputViews.count == 0,
                  frozenCaptureElements.allSatisfy({
                      $0.waitForExistence(timeout: 10)
                  }),
                  captureHeading.label == "1 of 2 · Wide view",
                  takePhoto.label == "Take photo",
                  choosePhotos.label == "Choose from Photos",
                  cannotComplete.label == "Cannot complete",
                  importFixture.label == "Import test photo",
                  !capturePreview.exists,
                  app.state == .runningForeground else {
                XCTFail(
                    "AX-text capture-wide positioning preconditions are incomplete."
                )
                return
            }
            let prePositionTabBarCount = captureTabBars.count
            let prePositionCaptureRouteExists = captureScroll.exists
            let prePositionHeadingLabel = captureHeading.label
            let prePositionTakePhotoLabel = takePhoto.label
            let prePositionChoosePhotosLabel = choosePhotos.label
            let prePositionCannotCompleteLabel = cannotComplete.label
            let prePositionImportFixtureLabel = importFixture.label
            let prePositionPreviewExists = capturePreview.exists
            let horizontalInset: CGFloat = 24
            let verticalInset: CGFloat = 16
            let minimumGestureDistance: CGFloat = 44

            for _ in 0..<4 {
                guard captureScrollViews.count == 1,
                      captureNavigationBars.count == 1,
                      captureTabBars.count == prePositionTabBarCount,
                      captureHeadingQuery.count == 1,
                      takePhotoQuery.count == 1,
                      choosePhotosQuery.count == 1,
                      cannotCompleteQuery.count == 1,
                      importFixtureQuery.count == 1,
                      capturePreviewQuery.count == 0,
                      captureScroll.exists,
                      captureNavigationBar.exists,
                      cannotComplete.exists,
                      importFixture.exists,
                      app.keyboards.count == 0,
                      captureInputViews.count == 0,
                      app.state == .runningForeground else {
                    XCTFail("AX-text capture-wide live route geometry changed.")
                    return
                }
                let liveTabBarTop: CGFloat
                if prePositionTabBarCount == 1 {
                    let tabBar = captureTabBars.firstMatch
                    guard tabBar.exists else {
                        XCTFail("AX-text capture-wide TabBar disappeared.")
                        return
                    }
                    liveTabBarTop = tabBar.frame.minY
                } else {
                    liveTabBarTop = app.frame.maxY
                }
                let scrollFrame = captureScroll.frame
                let liveLeft = max(scrollFrame.minX, app.frame.minX)
                let liveRight = min(scrollFrame.maxX, app.frame.maxX)
                let liveTop = max(
                    scrollFrame.minY,
                    max(app.frame.minY, captureNavigationBar.frame.maxY)
                )
                let liveBottom = min(
                    scrollFrame.maxY,
                    min(app.frame.maxY, liveTabBarTop)
                )
                let safeLeft = liveLeft + horizontalInset
                let safeRight = liveRight - horizontalInset
                let safeTop = liveTop + verticalInset
                let safeBottom = liveBottom - verticalInset
                guard safeRight > safeLeft,
                      safeBottom > safeTop else {
                    XCTFail("AX-text capture-wide has no inset live viewport.")
                    return
                }

                let cannotFrame = cannotComplete.frame
                let importFrame = importFixture.frame
                let targetLeft = min(cannotFrame.minX, importFrame.minX)
                let targetRight = max(cannotFrame.maxX, importFrame.maxX)
                let targetTop = min(cannotFrame.minY, importFrame.minY)
                let targetBottom = max(cannotFrame.maxY, importFrame.maxY)
                guard targetLeft >= safeLeft,
                      targetRight <= safeRight,
                      targetBottom - targetTop <= safeBottom - safeTop else {
                    XCTFail(
                        "AX-text capture-wide lower actions cannot fit the inset viewport."
                    )
                    return
                }
                let cannotContained = cannotFrame.minY >= safeTop
                    && cannotFrame.maxY <= safeBottom
                let importContained = importFrame.minY >= safeTop
                    && importFrame.maxY <= safeBottom
                if cannotContained && importContained {
                    break
                }

                let minimumShift = max(
                    safeTop - cannotFrame.minY,
                    safeTop - importFrame.minY
                )
                let maximumShift = min(
                    safeBottom - cannotFrame.maxY,
                    safeBottom - importFrame.maxY
                )
                let maximumGestureDistance = liveBottom
                    - liveTop
                    - (2 * verticalInset)
                guard minimumShift <= maximumShift,
                      maximumGestureDistance >= minimumGestureDistance else {
                    XCTFail(
                        "AX-text capture-wide has no feasible recognized shift."
                    )
                    return
                }
                let dragDistance: CGFloat
                if maximumShift < 0 {
                    let recognizedMinimum = max(
                        minimumShift,
                        -maximumGestureDistance
                    )
                    let recognizedMaximum = min(
                        maximumShift,
                        -minimumGestureDistance
                    )
                    guard recognizedMinimum <= recognizedMaximum else {
                        XCTFail(
                            "AX-text capture-wide upward shift is not recognizable."
                        )
                        return
                    }
                    dragDistance = recognizedMaximum
                } else if minimumShift > 0 {
                    let recognizedMinimum = max(
                        minimumShift,
                        minimumGestureDistance
                    )
                    let recognizedMaximum = min(
                        maximumShift,
                        maximumGestureDistance
                    )
                    guard recognizedMinimum <= recognizedMaximum else {
                        XCTFail(
                            "AX-text capture-wide downward shift is not recognizable."
                        )
                        return
                    }
                    dragDistance = recognizedMinimum
                } else {
                    XCTFail(
                        "AX-text capture-wide feasible shift is directionless."
                    )
                    return
                }

                let scrollOrigin = captureScroll.coordinate(
                    withNormalizedOffset: CGVector(dx: 0, dy: 0)
                )
                let dragStartOffsetY = dragDistance > 0
                    ? liveTop - scrollFrame.minY + verticalInset
                    : liveBottom - scrollFrame.minY - verticalInset
                let dragStart = scrollOrigin.withOffset(
                    CGVector(
                        dx: scrollFrame.width / 2,
                        dy: dragStartOffsetY
                    )
                )
                let dragEnd = dragStart.withOffset(
                    CGVector(dx: 0, dy: dragDistance)
                )
                let cannotBeforeDrag = cannotFrame.minY
                let importBeforeDrag = importFrame.minY
                dragStart.press(forDuration: 0.05, thenDragTo: dragEnd)
                let observedCannotShift = cannotComplete.frame.minY
                    - cannotBeforeDrag
                let observedImportShift = importFixture.frame.minY
                    - importBeforeDrag
                guard observedCannotShift * dragDistance > 0,
                      observedImportShift * dragDistance > 0 else {
                    XCTFail(
                        "AX-text capture-wide positioning gesture was not recognized."
                    )
                    return
                }
            }

            let finalTabBarExists = prePositionTabBarCount == 0
                || captureTabBars.firstMatch.waitForExistence(timeout: 10)
            let finalTabBarTop = prePositionTabBarCount == 1
                && finalTabBarExists
                ? captureTabBars.firstMatch.frame.minY
                : app.frame.maxY
            let finalScrollFrame = captureScroll.frame
            let finalSafeLeft = max(
                finalScrollFrame.minX,
                app.frame.minX
            ) + horizontalInset
            let finalSafeRight = min(
                finalScrollFrame.maxX,
                app.frame.maxX
            ) - horizontalInset
            let finalSafeTop = max(
                finalScrollFrame.minY,
                max(app.frame.minY, captureNavigationBar.frame.maxY)
            ) + verticalInset
            let finalSafeBottom = min(
                finalScrollFrame.maxY,
                min(app.frame.maxY, finalTabBarTop)
            ) - verticalInset
            let finalCannotFrame = cannotComplete.frame
            let finalImportFrame = importFixture.frame
            let finalCannotContained = finalCannotFrame.minX >= finalSafeLeft
                && finalCannotFrame.maxX <= finalSafeRight
                && finalCannotFrame.minY >= finalSafeTop
                && finalCannotFrame.maxY <= finalSafeBottom
            let finalImportContained = finalImportFrame.minX >= finalSafeLeft
                && finalImportFrame.maxX <= finalSafeRight
                && finalImportFrame.minY >= finalSafeTop
                && finalImportFrame.maxY <= finalSafeBottom
            guard captureScrollViews.count == 1,
                  captureNavigationBars.count == 1,
                  captureTabBars.count == prePositionTabBarCount,
                  captureHeadingQuery.count == 1,
                  takePhotoQuery.count == 1,
                  choosePhotosQuery.count == 1,
                  cannotCompleteQuery.count == 1,
                  importFixtureQuery.count == 1,
                  capturePreviewQuery.count == 0,
                  finalTabBarExists,
                  frozenCaptureElements.allSatisfy({ $0.exists }),
                  captureScroll.exists == prePositionCaptureRouteExists,
                  app.keyboards.count == 0,
                  captureInputViews.count == 0,
                  captureHeading.label == prePositionHeadingLabel,
                  takePhoto.label == prePositionTakePhotoLabel,
                  choosePhotos.label == prePositionChoosePhotosLabel,
                  cannotComplete.label == prePositionCannotCompleteLabel,
                  importFixture.label == prePositionImportFixtureLabel,
                  capturePreview.exists == prePositionPreviewExists,
                  !capturePreview.exists,
                  finalCannotContained,
                  finalImportContained,
                  cannotComplete.isHittable,
                  importFixture.isHittable,
                  app.state == .runningForeground else {
                XCTFail(
                    "AX-text capture-wide lower actions were not restored fully visible and unchanged."
                )
                return
            }
        }
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
        let preparesReportDetailEvidence = shouldPrepareNormalEvidence(
            for: "state.report-detail.ready",
            in: app
        )
        if automationShard?.shardID == "s10.4.current.ax-text" {
            if preparesReportDetailEvidence {
                guard scrollReportPreviewForAXText(preview, in: app) else { return }
            }
        } else {
            scroll(preview, in: app)
        }
        if preparesReportDetailEvidence {
            XCTAssertTrue(preview.isHittable)
        }
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
    private func assertReportsIndex(in app: XCUIApplication) throws {
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
        if automationShard?.shardID == "s10.4.current.ax-text",
           shouldPrepareNormalEvidence(
               for: "state.report-history.ready",
               in: app
           ) {
            guard positionLowerNorthCampusForAXText(in: app) else { return }
            guard positionReportHistoryHeaderAndVisitForAXTextDiagnostic(
                in: app
            ) else { return }
        }
        captureBaseline("state.report-history.ready", in: app)
        navigateBack(in: app)

        let reportsTab = element("s1.tab.reports", in: app)
        XCTAssertTrue(reportsTab.waitForExistence(timeout: 20))
        reportsTab.tap()
        XCTAssertTrue(element("s4.4.reports.screen", in: app)
            .waitForExistence(timeout: 30))
        if automationShard?.shardID == "s10.4.minimum.rtl" {
            guard positionMinimumRTLReportsViewReport(in: app) else {
                throw AutomationConfigurationError.invalid(
                    "S10.4 minimum RTL reports-index positioning failed"
                )
            }
        }
        captureBaseline("state.reports-index.ready", in: app)

        let signsTab = element("s1.tab.signs", in: app)
        XCTAssertTrue(signsTab.waitForExistence(timeout: 20))
        signsTab.tap()
        XCTAssertTrue(element("s2.sign-detail.screen", in: app)
            .waitForExistence(timeout: 30))
    }

    @MainActor
    private func positionLowerNorthCampusForAXText(
        in app: XCUIApplication
    ) -> Bool {
        let historyScreens = app.descendants(matching: .any).matching(
            identifier: "s4.4.history.screen"
        )
        let historyHeaders = app.staticTexts.matching(
            identifier: "s4.4.history.header"
        )
        let northCampusTexts = app.staticTexts.matching(
            NSPredicate(format: "label == %@", "North Campus")
        )
        let viewReportControls = app.buttons.matching(
            identifier: "s4.4.reports.view-report"
        )
        let historyScrollViews = app.scrollViews.containing(
            .button,
            identifier: "s4.4.reports.view-report"
        )
        let historyNavigationBars = app.navigationBars.matching(
            identifier: "Report history"
        )
        let historyTabBars = app.tabBars
        let historyScreen = historyScreens.firstMatch
        let historyHeader = historyHeaders.firstMatch
        let viewReportControl = viewReportControls.firstMatch
        let historyScrollView = historyScrollViews.firstMatch
        let historyNavigationBar = historyNavigationBars.firstMatch
        let historyTabBar = historyTabBars.firstMatch

        func lowerNorthCampus() -> XCUIElement? {
            guard northCampusTexts.count == 2 else {
                XCTFail("Report-history North Campus cardinality is ambiguous.")
                return nil
            }
            let first = northCampusTexts.element(boundBy: 0)
            let second = northCampusTexts.element(boundBy: 1)
            let firstFrame = first.frame
            let secondFrame = second.frame
            guard first.exists,
                  second.exists,
                  first.identifier.isEmpty,
                  second.identifier.isEmpty,
                  first.label == "North Campus",
                  second.label == "North Campus",
                  first.elementType == .staticText,
                  second.elementType == .staticText,
                  !firstFrame.isNull,
                  !firstFrame.isEmpty,
                  !secondFrame.isNull,
                  !secondFrame.isEmpty,
                  firstFrame != secondFrame,
                  (
                    firstFrame.maxY < secondFrame.minY
                        || secondFrame.maxY < firstFrame.minY
                  ) else {
                XCTFail("Report-history North Campus frames are not strictly ordered.")
                return nil
            }
            return firstFrame.minY > secondFrame.minY ? first : second
        }

        let contentInset: CGFloat = 16
        let receiverInset: CGFloat = 24
        let minimumGestureDistance: CGFloat = 44
        for _ in 0..<4 {
            guard app.state == .runningForeground,
                  historyScreens.count == 1,
                  historyHeaders.count == 1,
                  viewReportControls.count == 1,
                  historyScrollViews.count == 1,
                  historyNavigationBars.count == 1,
                  historyTabBars.count == 1,
                  historyScreen.exists,
                  historyHeader.exists,
                  viewReportControl.exists,
                  viewReportControl.label == "View report",
                  viewReportControl.elementType == .button,
                  historyScrollView.exists,
                  historyNavigationBar.exists,
                  historyTabBar.exists,
                  let lowerSite = lowerNorthCampus() else {
                XCTFail("Report-history AX-text positioning route changed.")
                return false
            }
            let scrollFrame = historyScrollView.frame
            let applicationFrame = app.frame
            let navigationFrame = historyNavigationBar.frame
            let tabBarFrame = historyTabBar.frame
            let liveScrollFrame = scrollFrame.intersection(applicationFrame)
            let liveTop = max(liveScrollFrame.minY, navigationFrame.maxY)
            let liveBottom = min(
                liveScrollFrame.maxY,
                min(applicationFrame.maxY, tabBarFrame.minY)
            )
            let safeTop = liveTop + contentInset
            let safeBottom = liveBottom - contentInset
            let receiverTop = liveTop + receiverInset
            let receiverBottom = liveBottom - receiverInset
            let lowerFrame = lowerSite.frame
            guard !applicationFrame.isNull,
                  !applicationFrame.isEmpty,
                  !navigationFrame.isNull,
                  !navigationFrame.isEmpty,
                  !tabBarFrame.isNull,
                  !tabBarFrame.isEmpty,
                  !scrollFrame.isNull,
                  !scrollFrame.isEmpty,
                  !liveScrollFrame.isNull,
                  !liveScrollFrame.isEmpty,
                  !lowerFrame.isNull,
                  !lowerFrame.isEmpty,
                  safeBottom > safeTop,
                  receiverBottom > receiverTop,
                  lowerFrame.height <= safeBottom - safeTop else {
                XCTFail("Report-history AX-text viewport geometry is invalid.")
                return false
            }
            if lowerFrame.minY >= safeTop,
               lowerFrame.maxY <= safeBottom,
               lowerSite.isHittable {
                return true
            }

            let minimumShift = safeTop - lowerFrame.minY
            let maximumShift = safeBottom - lowerFrame.maxY
            let receiverCapacity = receiverBottom - receiverTop
            guard minimumShift <= maximumShift,
                  maximumShift < 0,
                  receiverCapacity >= minimumGestureDistance else {
                XCTFail("Report-history AX-text requires no feasible negative shift.")
                return false
            }
            let recognizedMinimum = max(
                minimumShift,
                -receiverCapacity
            )
            let recognizedMaximum = min(
                maximumShift,
                -minimumGestureDistance
            )
            guard recognizedMinimum <= recognizedMaximum,
                  recognizedMaximum < 0 else {
                XCTFail("Report-history AX-text upward shift is not recognizable.")
                return false
            }
            let dragDistance = recognizedMaximum
            guard abs(dragDistance) >= minimumGestureDistance else {
                XCTFail("Report-history AX-text positioning gesture undertravels.")
                return false
            }
            let scrollOrigin = historyScrollView.coordinate(
                withNormalizedOffset: CGVector(dx: 0, dy: 0)
            )
            let dragStart = scrollOrigin.withOffset(
                CGVector(
                    dx: scrollFrame.width / 2,
                    dy: receiverBottom - scrollFrame.minY
                )
            )
            let dragEnd = dragStart.withOffset(
                CGVector(dx: 0, dy: dragDistance)
            )
            let lowerMinYBeforeDrag = lowerFrame.minY
            dragStart.press(
                forDuration: 0.2,
                thenDragTo: dragEnd,
                withVelocity: .slow,
                thenHoldForDuration: 0.2
            )
            guard app.state == .runningForeground,
                  historyScreens.count == 1,
                  historyHeaders.count == 1,
                  viewReportControls.count == 1,
                  historyScrollViews.count == 1,
                  historyNavigationBars.count == 1,
                  historyTabBars.count == 1,
                  historyScreen.exists,
                  historyHeader.exists,
                  viewReportControl.exists,
                  historyScrollView.exists,
                  historyNavigationBar.exists,
                  historyTabBar.exists,
                  let movedLowerSite = lowerNorthCampus() else {
                XCTFail("Report-history AX-text route changed after positioning.")
                return false
            }
            let observedShift = movedLowerSite.frame.minY - lowerMinYBeforeDrag
            guard observedShift < 0,
                  observedShift * dragDistance > 0 else {
                XCTFail("Report-history AX-text positioning gesture was not recognized.")
                return false
            }
        }

        guard app.state == .runningForeground,
              historyScreens.count == 1,
              historyHeaders.count == 1,
              viewReportControls.count == 1,
              historyScrollViews.count == 1,
              historyNavigationBars.count == 1,
              historyTabBars.count == 1,
              historyScreen.exists,
              historyHeader.exists,
              viewReportControl.exists,
              historyScrollView.exists,
              historyNavigationBar.exists,
              historyTabBar.exists,
              let finalLowerSite = lowerNorthCampus() else {
            XCTFail("Report-history AX-text final route changed.")
            return false
        }
        let finalApplicationFrame = app.frame
        let finalNavigationFrame = historyNavigationBar.frame
        let finalTabBarFrame = historyTabBar.frame
        let finalScrollFrame = historyScrollView.frame.intersection(
            finalApplicationFrame
        )
        let finalSafeTop = max(
            finalScrollFrame.minY,
            finalNavigationFrame.maxY
        ) + contentInset
        let finalSafeBottom = min(
            finalScrollFrame.maxY,
            min(finalApplicationFrame.maxY, finalTabBarFrame.minY)
        ) - contentInset
        let finalLowerFrame = finalLowerSite.frame
        guard !finalApplicationFrame.isNull,
              !finalApplicationFrame.isEmpty,
              !finalNavigationFrame.isNull,
              !finalNavigationFrame.isEmpty,
              !finalTabBarFrame.isNull,
              !finalTabBarFrame.isEmpty,
              !finalScrollFrame.isNull,
              !finalScrollFrame.isEmpty,
              !finalLowerFrame.isNull,
              !finalLowerFrame.isEmpty,
              finalSafeBottom > finalSafeTop,
              finalLowerFrame.minY >= finalSafeTop,
              finalLowerFrame.maxY <= finalSafeBottom,
              finalLowerSite.isHittable else {
            XCTFail("Report-history lower North Campus is outside the safe viewport.")
            return false
        }
        return true
    }

    @MainActor
    private func positionReportHistoryHeaderAndVisitForAXTextDiagnostic(
        in app: XCUIApplication
    ) -> Bool {
        let historyScreens = app.descendants(matching: .any).matching(
            identifier: "s4.4.history.screen"
        )
        let historyHeaders = app.staticTexts.matching(
            identifier: "s4.4.history.header"
        )
        let northCampusTexts = app.staticTexts.matching(
            NSPredicate(format: "label == %@", "North Campus")
        )
        let viewReportControls = app.buttons.matching(
            identifier: "s4.4.reports.view-report"
        )
        let historyScrollViews = app.scrollViews.containing(
            .button,
            identifier: "s4.4.reports.view-report"
        )
        let historyNavigationBars = app.navigationBars.matching(
            identifier: "Report history"
        )
        let historyTabBars = app.tabBars
        let reportHistoryVisits = app.descendants(matching: .any).matching(
            identifier: "s4.4.reports.visit"
        )
        let reportHistoryVisit = reportHistoryVisits.firstMatch
        let visitComposites = reportHistoryVisit.descendants(
            matching: .staticText
        ).matching(
            NSPredicate(format: "label BEGINSWITH %@", "Visit, ")
        )
        let historyScreen = historyScreens.firstMatch
        let historyHeader = historyHeaders.firstMatch
        let viewReportControl = viewReportControls.firstMatch
        let historyScrollView = historyScrollViews.firstMatch
        let historyNavigationBar = historyNavigationBars.firstMatch
        let historyTabBar = historyTabBars.firstMatch
        let visitComposite = visitComposites.firstMatch

        func hasExactNorthCampusTexts() -> Bool {
            guard northCampusTexts.count == 2 else { return false }
            let first = northCampusTexts.element(boundBy: 0)
            let second = northCampusTexts.element(boundBy: 1)
            let firstFrame = first.frame
            let secondFrame = second.frame
            return first.exists
                && second.exists
                && first.identifier.isEmpty
                && second.identifier.isEmpty
                && first.label == "North Campus"
                && second.label == "North Campus"
                && first.elementType == .staticText
                && second.elementType == .staticText
                && !firstFrame.isNull
                && !firstFrame.isEmpty
                && !secondFrame.isNull
                && !secondFrame.isEmpty
                && firstFrame != secondFrame
                && (
                    firstFrame.maxY < secondFrame.minY
                        || secondFrame.maxY < firstFrame.minY
                )
        }

        func hasExactRoute() -> Bool {
            let applicationFrame = app.frame
            let historyScreenFrame = historyScreen.frame
            let historyHeaderFrame = historyHeader.frame
            let viewReportFrame = viewReportControl.frame
            let historyScrollFrame = historyScrollView.frame
            let historyNavigationFrame = historyNavigationBar.frame
            let historyTabFrame = historyTabBar.frame
            let reportHistoryVisitFrame = reportHistoryVisit.frame
            let visitCompositeFrame = visitComposite.frame
            return app.state == .runningForeground
                && historyScreens.count == 1
                && historyHeaders.count == 1
                && northCampusTexts.count == 2
                && viewReportControls.count == 1
                && historyScrollViews.count == 1
                && historyNavigationBars.count == 1
                && historyTabBars.count == 1
                && reportHistoryVisits.count == 1
                && visitComposites.count == 1
                && historyScreen.exists
                && historyScreen.identifier == "s4.4.history.screen"
                && historyScreen.elementType == .scrollView
                && historyHeader.exists
                && historyHeader.identifier == "s4.4.history.header"
                && historyHeader.label == "Monument Sign"
                && historyHeader.elementType == .staticText
                && hasExactNorthCampusTexts()
                && viewReportControl.exists
                && viewReportControl.identifier == "s4.4.reports.view-report"
                && viewReportControl.label == "View report"
                && viewReportControl.elementType == .button
                && historyScrollView.exists
                && historyScrollView.identifier == "s4.4.history.screen"
                && historyScrollView.elementType == .scrollView
                && historyNavigationBar.exists
                && historyNavigationBar.identifier == "Report history"
                && historyNavigationBar.elementType == .navigationBar
                && historyTabBar.exists
                && historyTabBar.label == "Tab Bar"
                && historyTabBar.elementType == .tabBar
                && reportHistoryVisit.exists
                && reportHistoryVisit.identifier == "s4.4.reports.visit"
                && reportHistoryVisit.elementType == .other
                && visitComposite.exists
                && visitComposite.identifier.isEmpty
                && visitComposite.label.hasPrefix("Visit, ")
                && visitComposite.elementType == .staticText
                && !applicationFrame.isNull
                && !applicationFrame.isEmpty
                && !historyScreenFrame.isNull
                && !historyScreenFrame.isEmpty
                && !historyHeaderFrame.isNull
                && !historyHeaderFrame.isEmpty
                && !viewReportFrame.isNull
                && !viewReportFrame.isEmpty
                && !historyScrollFrame.isNull
                && !historyScrollFrame.isEmpty
                && !historyNavigationFrame.isNull
                && !historyNavigationFrame.isEmpty
                && !historyTabFrame.isNull
                && !historyTabFrame.isEmpty
                && !reportHistoryVisitFrame.isNull
                && !reportHistoryVisitFrame.isEmpty
                && !visitCompositeFrame.isNull
                && !visitCompositeFrame.isEmpty
        }

        let contentInset: CGFloat = 16
        let receiverInset: CGFloat = 24
        let minimumGestureDistance: CGFloat = 44
        for _ in 0..<4 {
            guard hasExactRoute() else {
                XCTFail("Report-history AX-text positioned diagnostic route changed.")
                return false
            }
            let applicationFrame = app.frame
            let scrollFrame = historyScrollView.frame
            let navigationFrame = historyNavigationBar.frame
            let tabBarFrame = historyTabBar.frame
            let liveScrollFrame = scrollFrame.intersection(applicationFrame)
            let liveTop = max(liveScrollFrame.minY, navigationFrame.maxY)
            let liveBottom = min(
                liveScrollFrame.maxY,
                min(applicationFrame.maxY, tabBarFrame.minY)
            )
            let safeTop = liveTop + contentInset
            let safeBottom = liveBottom - contentInset
            let receiverTop = liveTop + receiverInset
            let receiverBottom = liveBottom - receiverInset
            let headerFrame = historyHeader.frame
            let visitCompositeFrame = visitComposite.frame
            guard !applicationFrame.isNull,
                  !applicationFrame.isEmpty,
                  !scrollFrame.isNull,
                  !scrollFrame.isEmpty,
                  !navigationFrame.isNull,
                  !navigationFrame.isEmpty,
                  !tabBarFrame.isNull,
                  !tabBarFrame.isEmpty,
                  !liveScrollFrame.isNull,
                  !liveScrollFrame.isEmpty,
                  !headerFrame.isNull,
                  !headerFrame.isEmpty,
                  !visitCompositeFrame.isNull,
                  !visitCompositeFrame.isEmpty,
                  headerFrame.maxY < visitCompositeFrame.minY,
                  safeBottom > safeTop,
                  receiverBottom > receiverTop,
                  headerFrame.height <= safeBottom - safeTop else {
                XCTFail("Report-history AX-text positioned diagnostic geometry is invalid.")
                return false
            }
            if headerFrame.minY >= safeTop,
               headerFrame.maxY <= safeBottom,
               historyHeader.isHittable,
               visitCompositeFrame.minY >= applicationFrame.maxY,
               !visitComposite.isHittable {
                return true
            }

            let minimumShift = max(
                safeTop - headerFrame.minY,
                applicationFrame.maxY - visitCompositeFrame.minY
            )
            let maximumShift = safeBottom - headerFrame.maxY
            let receiverCapacity = receiverBottom - receiverTop
            guard minimumShift <= maximumShift,
                  minimumShift > 0,
                  receiverCapacity >= minimumGestureDistance else {
                XCTFail("Report-history AX-text positioned diagnostic has no positive interval.")
                return false
            }
            let recognizedMinimum = max(
                minimumShift,
                minimumGestureDistance
            )
            let recognizedMaximum = min(
                maximumShift,
                receiverCapacity
            )
            guard recognizedMinimum <= recognizedMaximum,
                  recognizedMinimum > 0 else {
                XCTFail("Report-history AX-text positive shift is not recognizable.")
                return false
            }
            let dragDistance = recognizedMinimum
            let scrollOrigin = historyScrollView.coordinate(
                withNormalizedOffset: CGVector(dx: 0, dy: 0)
            )
            let dragStart = scrollOrigin.withOffset(
                CGVector(
                    dx: scrollFrame.width / 2,
                    dy: receiverTop - scrollFrame.minY
                )
            )
            let dragEnd = dragStart.withOffset(
                CGVector(dx: 0, dy: dragDistance)
            )
            let headerMinYBeforeDrag = headerFrame.minY
            let visitMinYBeforeDrag = visitCompositeFrame.minY
            dragStart.press(
                forDuration: 0.2,
                thenDragTo: dragEnd,
                withVelocity: .slow,
                thenHoldForDuration: 0.2
            )
            guard hasExactRoute() else {
                XCTFail("Report-history AX-text positioned diagnostic route changed after drag.")
                return false
            }
            let observedHeaderShift = historyHeader.frame.minY - headerMinYBeforeDrag
            let observedVisitShift = visitComposite.frame.minY - visitMinYBeforeDrag
            guard observedHeaderShift > 0,
                  observedVisitShift > 0,
                  observedHeaderShift * dragDistance > 0,
                  observedVisitShift * dragDistance > 0 else {
                XCTFail("Report-history AX-text positioned diagnostic drag was not recognized.")
                return false
            }
        }

        guard hasExactRoute() else {
            XCTFail("Report-history AX-text positioned diagnostic final route changed.")
            return false
        }
        let finalApplicationFrame = app.frame
        let finalScrollFrame = historyScrollView.frame.intersection(
            finalApplicationFrame
        )
        let finalNavigationFrame = historyNavigationBar.frame
        let finalTabBarFrame = historyTabBar.frame
        let finalSafeTop = max(
            finalScrollFrame.minY,
            finalNavigationFrame.maxY
        ) + contentInset
        let finalSafeBottom = min(
            finalScrollFrame.maxY,
            min(finalApplicationFrame.maxY, finalTabBarFrame.minY)
        ) - contentInset
        let finalHeaderFrame = historyHeader.frame
        let finalVisitCompositeFrame = visitComposite.frame
        guard !finalApplicationFrame.isNull,
              !finalApplicationFrame.isEmpty,
              !finalScrollFrame.isNull,
              !finalScrollFrame.isEmpty,
              !finalNavigationFrame.isNull,
              !finalNavigationFrame.isEmpty,
              !finalTabBarFrame.isNull,
              !finalTabBarFrame.isEmpty,
              !finalHeaderFrame.isNull,
              !finalHeaderFrame.isEmpty,
              !finalVisitCompositeFrame.isNull,
              !finalVisitCompositeFrame.isEmpty,
              finalSafeBottom > finalSafeTop,
              finalHeaderFrame.minY >= finalSafeTop,
              finalHeaderFrame.maxY <= finalSafeBottom,
              historyHeader.isHittable,
              finalVisitCompositeFrame.minY >= finalApplicationFrame.maxY,
              !visitComposite.isHittable else {
            XCTFail("Report-history AX-text positioned diagnostic final geometry is unsafe.")
            return false
        }
        return true
    }

    @MainActor
    private func positionSignDetailTimeZoneForAXText(
        in app: XCUIApplication
    ) -> Bool {
        let timeZonePredicate = NSPredicate(
            format: "label == %@",
            "America/New_York"
        )
        let signDetailScreens = app.descendants(matching: .any).matching(
            identifier: "s2.sign-detail.screen"
        )
        let timeZoneRows = app.descendants(matching: .any).matching(
            identifier: "s2.sign-detail.time-zone"
        )
        let timeZoneStaticTexts = app.staticTexts.matching(timeZonePredicate)
        let timeZoneScrollViews = app.scrollViews.containing(timeZonePredicate)
        let navigationBars = app.navigationBars.matching(
            identifier: "Sign detail"
        )
        let tabBars = app.tabBars
        let signDetailScreen = signDetailScreens.firstMatch
        let timeZoneRow = timeZoneRows.firstMatch
        let timeZoneStaticText = timeZoneStaticTexts.firstMatch
        let timeZoneScrollView = timeZoneScrollViews.firstMatch
        let navigationBar = navigationBars.firstMatch
        let tabBar = tabBars.firstMatch
        let isValidFrame: (CGRect) -> Bool = { frame in
            !frame.isNull
                && !frame.isEmpty
                && !frame.isInfinite
                && frame.origin.x.isFinite
                && frame.origin.y.isFinite
                && frame.size.width.isFinite
                && frame.size.height.isFinite
        }
        let hasExactRoute: () -> Bool = {
            app.state == .runningForeground
                && signDetailScreens.count == 1
                && timeZoneRows.count == 1
                && timeZoneStaticTexts.count == 1
                && timeZoneScrollViews.count == 1
                && navigationBars.count == 1
                && tabBars.count == 1
                && signDetailScreen.exists
                && signDetailScreen.elementType == .scrollView
                && signDetailScreen.identifier == "s2.sign-detail.screen"
                && (signDetailScreen.value as? String) == ""
                && signDetailScreen.isHittable
                && timeZoneRow.exists
                && timeZoneRow.elementType == .staticText
                && timeZoneRow.identifier == "s2.sign-detail.time-zone"
                && timeZoneRow.label == "Time zone, America/New_York"
                && (timeZoneRow.value as? String) == ""
                && timeZoneRow.isHittable
                && timeZoneStaticText.exists
                && timeZoneStaticText.elementType == .staticText
                && timeZoneStaticText.identifier.isEmpty
                && timeZoneStaticText.label == "America/New_York"
                && (timeZoneStaticText.value as? String) == ""
                && timeZoneStaticText.isHittable
                && timeZoneScrollView.exists
                && timeZoneScrollView.elementType == .scrollView
                && timeZoneScrollView.identifier == "s2.sign-detail.screen"
                && (timeZoneScrollView.value as? String) == ""
                && timeZoneScrollView.isHittable
                && navigationBar.exists
                && navigationBar.elementType == .navigationBar
                && navigationBar.identifier == "Sign detail"
                && (navigationBar.value as? String) == ""
                && navigationBar.isHittable
                && tabBar.exists
                && tabBar.elementType == .tabBar
                && tabBar.identifier.isEmpty
                && tabBar.label == "Tab Bar"
                && (tabBar.value as? String) == ""
                && tabBar.isHittable
                && isValidFrame(app.frame)
                && isValidFrame(signDetailScreen.frame)
                && isValidFrame(timeZoneRow.frame)
                && isValidFrame(timeZoneStaticText.frame)
                && isValidFrame(timeZoneScrollView.frame)
                && isValidFrame(navigationBar.frame)
                && isValidFrame(tabBar.frame)
        }
        guard hasExactRoute() else {
            XCTFail("AX-text sign-detail time-zone positioning bindings are ambiguous.")
            return false
        }

        let verticalInset: CGFloat = 16
        let receiverInset: CGFloat = 24
        let minimumGestureDistance: CGFloat = 44
        var previousRowMinYAfterDrag: CGFloat?
        var previousTargetMinYAfterDrag: CGFloat?
        for _ in 0..<4 {
            guard hasExactRoute() else {
                XCTFail("AX-text sign-detail time-zone positioning route changed.")
                return false
            }
            let applicationFrame = app.frame
            let screenFrame = signDetailScreen.frame
            let rowFrame = timeZoneRow.frame
            let targetFrame = timeZoneStaticText.frame
            let scrollFrame = timeZoneScrollView.frame
            let navigationFrame = navigationBar.frame
            let tabFrame = tabBar.frame
            let liveFramesAreValid = isValidFrame(applicationFrame)
                && isValidFrame(screenFrame)
                && isValidFrame(rowFrame)
                && isValidFrame(targetFrame)
                && isValidFrame(scrollFrame)
                && isValidFrame(navigationFrame)
                && isValidFrame(tabFrame)
            var liveScrollFrame = CGRect.null
            if liveFramesAreValid {
                liveScrollFrame = scrollFrame.intersection(applicationFrame)
            }
            guard liveFramesAreValid,
                  isValidFrame(liveScrollFrame),
                  screenFrame == scrollFrame else {
                XCTFail("AX-text sign-detail time-zone positioning geometry is invalid.")
                return false
            }
            let liveTop = max(liveScrollFrame.minY, navigationFrame.maxY)
            let liveBottom = min(
                liveScrollFrame.maxY,
                min(applicationFrame.maxY, tabFrame.minY)
            )
            let safeTop = liveTop + verticalInset
            let safeBottom = liveBottom - verticalInset
            let receiverTop = liveTop + receiverInset
            let receiverBottom = liveBottom - receiverInset
            let receiverLeft = liveScrollFrame.minX + receiverInset
            let receiverRight = liveScrollFrame.maxX - receiverInset
            let receiverCapacity = receiverBottom - receiverTop
            let minimumShift = max(
                safeTop - rowFrame.minY,
                safeTop - targetFrame.minY
            )
            let maximumShift = min(
                safeBottom - rowFrame.maxY,
                safeBottom - targetFrame.maxY
            )
            let rowIsContained = rowFrame.minY >= safeTop
                && rowFrame.maxY <= safeBottom
            let targetIsContained = targetFrame.minY >= safeTop
                && targetFrame.maxY <= safeBottom
            guard liveTop.isFinite,
                  liveBottom.isFinite,
                  safeTop.isFinite,
                  safeBottom.isFinite,
                  receiverTop.isFinite,
                  receiverBottom.isFinite,
                  receiverLeft.isFinite,
                  receiverRight.isFinite,
                  receiverCapacity.isFinite,
                  minimumShift.isFinite,
                  maximumShift.isFinite,
                  liveTop <= liveBottom,
                  safeTop <= safeBottom,
                  receiverTop <= receiverBottom,
                  receiverLeft <= receiverRight,
                  receiverCapacity >= minimumGestureDistance,
                  rowFrame.height <= safeBottom - safeTop,
                  targetFrame.height <= safeBottom - safeTop,
                  minimumShift <= maximumShift,
                  (rowIsContained && targetIsContained) || maximumShift < 0 else {
                XCTFail("AX-text sign-detail time-zone composition has no supported upward interval.")
                return false
            }
            if rowIsContained && targetIsContained { break }

            let dragDistance: CGFloat
            if maximumShift >= -receiverCapacity {
                let recognizedMinimum = max(
                    minimumShift,
                    -receiverCapacity
                )
                let recognizedMaximum = min(
                    maximumShift,
                    -minimumGestureDistance
                )
                guard recognizedMinimum <= recognizedMaximum else {
                    XCTFail("AX-text sign-detail time-zone direct interval is not recognizable.")
                    return false
                }
                dragDistance = recognizedMaximum
            } else {
                let stagedDistance = max(
                    -receiverCapacity,
                    maximumShift + minimumGestureDistance
                )
                guard stagedDistance <= -minimumGestureDistance else {
                    XCTFail("AX-text sign-detail time-zone staged remainder is not recognizable.")
                    return false
                }
                dragDistance = stagedDistance
            }
            guard dragDistance.isFinite,
                  dragDistance < 0,
                  abs(dragDistance) >= minimumGestureDistance else {
                XCTFail("AX-text sign-detail time-zone drag direction is invalid.")
                return false
            }

            let receiverFrame = CGRect(
                x: receiverLeft,
                y: receiverTop,
                width: receiverRight - receiverLeft,
                height: receiverBottom - receiverTop
            )
            let startPoint = CGPoint(
                x: receiverRight,
                y: receiverBottom
            )
            let endPoint = CGPoint(
                x: startPoint.x,
                y: startPoint.y + dragDistance
            )
            guard startPoint.x.isFinite,
                  startPoint.y.isFinite,
                  endPoint.x.isFinite,
                  endPoint.y.isFinite,
                  isValidFrame(receiverFrame),
                  startPoint.x >= receiverFrame.minX,
                  startPoint.x <= receiverFrame.maxX,
                  startPoint.y >= receiverFrame.minY,
                  startPoint.y <= receiverFrame.maxY,
                  endPoint.x >= receiverFrame.minX,
                  endPoint.x <= receiverFrame.maxX,
                  endPoint.y >= receiverFrame.minY,
                  endPoint.y <= receiverFrame.maxY,
                  liveScrollFrame.contains(startPoint),
                  liveScrollFrame.contains(endPoint),
                  !rowFrame.contains(startPoint),
                  !rowFrame.contains(endPoint),
                  !targetFrame.contains(startPoint),
                  !targetFrame.contains(endPoint) else {
                XCTFail("AX-text sign-detail time-zone drag receiver is obstructed.")
                return false
            }
            let scrollOrigin = timeZoneScrollView.coordinate(
                withNormalizedOffset: CGVector(dx: 0, dy: 0)
            )
            let dragStart = scrollOrigin.withOffset(
                CGVector(
                    dx: startPoint.x - scrollFrame.minX,
                    dy: startPoint.y - scrollFrame.minY
                )
            )
            let dragEnd = scrollOrigin.withOffset(
                CGVector(
                    dx: endPoint.x - scrollFrame.minX,
                    dy: endPoint.y - scrollFrame.minY
                )
            )
            let rowBeforeDrag = rowFrame.minY
            let targetBeforeDrag = targetFrame.minY
            dragStart.press(
                forDuration: 0.2,
                thenDragTo: dragEnd,
                withVelocity: .slow,
                thenHoldForDuration: 0.2
            )
            guard hasExactRoute() else {
                XCTFail("AX-text sign-detail time-zone route changed after positioning.")
                return false
            }
            let rowAfterDrag = timeZoneRow.frame
            let targetAfterDrag = timeZoneStaticText.frame
            var observedRowShift: CGFloat?
            var observedTargetShift: CGFloat?
            if isValidFrame(rowAfterDrag), isValidFrame(targetAfterDrag) {
                observedRowShift = rowAfterDrag.minY - rowBeforeDrag
                observedTargetShift = targetAfterDrag.minY - targetBeforeDrag
            }
            guard let observedRowShift,
                  let observedTargetShift,
                  observedRowShift * dragDistance > 0,
                  observedTargetShift * dragDistance > 0 else {
                XCTFail("AX-text sign-detail time-zone gesture made no signed progress.")
                return false
            }
            if let previousRowMinYAfterDrag,
               let previousTargetMinYAfterDrag {
                guard rowAfterDrag.minY < previousRowMinYAfterDrag,
                      targetAfterDrag.minY < previousTargetMinYAfterDrag else {
                    XCTFail("AX-text sign-detail time-zone positioning reversed direction.")
                    return false
                }
            }
            previousRowMinYAfterDrag = rowAfterDrag.minY
            previousTargetMinYAfterDrag = targetAfterDrag.minY
        }

        guard hasExactRoute() else {
            XCTFail("AX-text sign-detail time-zone final route is invalid.")
            return false
        }
        let finalApplicationFrame = app.frame
        let finalScreenFrame = signDetailScreen.frame
        let finalRowFrame = timeZoneRow.frame
        let finalTargetFrame = timeZoneStaticText.frame
        let finalScrollFrame = timeZoneScrollView.frame
        let finalNavigationFrame = navigationBar.frame
        let finalTabFrame = tabBar.frame
        let finalFramesAreValid = isValidFrame(finalApplicationFrame)
            && isValidFrame(finalScreenFrame)
            && isValidFrame(finalRowFrame)
            && isValidFrame(finalTargetFrame)
            && isValidFrame(finalScrollFrame)
            && isValidFrame(finalNavigationFrame)
            && isValidFrame(finalTabFrame)
            && finalScreenFrame == finalScrollFrame
        var finalCompositionIsSafe = false
        if finalFramesAreValid {
            let finalLiveScrollFrame = finalScrollFrame.intersection(
                finalApplicationFrame
            )
            if isValidFrame(finalLiveScrollFrame) {
                let finalSafeTop = max(
                    finalLiveScrollFrame.minY,
                    finalNavigationFrame.maxY
                ) + verticalInset
                let finalSafeBottom = min(
                    finalLiveScrollFrame.maxY,
                    min(finalApplicationFrame.maxY, finalTabFrame.minY)
                ) - verticalInset
                finalCompositionIsSafe = finalSafeTop.isFinite
                    && finalSafeBottom.isFinite
                    && finalSafeTop <= finalSafeBottom
                    && finalRowFrame.minY >= finalSafeTop
                    && finalRowFrame.maxY <= finalSafeBottom
                    && finalTargetFrame.minY >= finalSafeTop
                    && finalTargetFrame.maxY <= finalSafeBottom
                    && timeZoneRow.isHittable
                    && timeZoneStaticText.isHittable
            }
        }
        guard finalCompositionIsSafe else {
            XCTFail("AX-text sign-detail time-zone final composition is unsafe.")
            return false
        }
        return true
    }

    @MainActor
    private func completeWorkAndResolvedRecheckAtXXXL(
        in app: XCUIApplication
    ) throws {
        let shell = element("s1.shell.screen", in: app)
        XCTAssertTrue(shell.waitForExistence(timeout: 30))
        XCTAssertEqual(shell.value as? String, effectiveAppearanceName(fallback: "Dark"))
        let signDetail = element("s2.sign-detail.screen", in: app)
        XCTAssertTrue(signDetail.waitForExistence(timeout: 30))
        if automationShard?.shardID == "s10.4.current.ax-text",
           shouldPrepareNormalEvidence(
               for: "state.sign-detail.open-issue",
               in: app
           ) {
            guard positionSignDetailTimeZoneForAXText(in: app) else {
                throw AutomationConfigurationError.invalid(
                    "S10.4 AX-text sign-detail time-zone positioning failed"
                )
            }
        }
        captureBaseline("state.sign-detail.open-issue", in: app)
        if finishAutomatedSegmentIfNeeded(after: 22, in: app) { return }
        if try prepareSegment3ResumeAtReportFailureIfNeeded(in: app) {
            segment3ResumePrepared = true
            return
        }

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
        let observedRecordWorkTitle = saveWork.label
        saveWork.tap()
        let validation = element("s5.1.work.validation", in: app)
        XCTAssertTrue(validation.waitForExistence(timeout: 10))
        assertLocalizedLabel(validation, equals: "Short description")
        if automationShard?.shardID == "s10.4.current.ax-text",
           shouldPrepareNormalEvidence(
               for: "state.work.validation-error",
               in: app
           ) {
            let focusedPredicate = NSPredicate(
                format: "hasKeyboardFocus == true"
            )
            let preDescriptionFields = app.descendants(matching: .any).matching(
                identifier: "s5.1.work.description"
            )
            let preFocusedDescriptionFields = preDescriptionFields.matching(
                focusedPredicate
            )
            let preValidationLabels = app.descendants(matching: .any).matching(
                identifier: "s5.1.work.validation"
            )
            let preKeyboards = app.keyboards
            let preInputViews = app.otherElements.matching(
                identifier: "inputView"
            )
            let preGlobalDoneButtons = app.buttons.matching(
                identifier: "s5.1.work.keyboard-done"
            )
            guard preDescriptionFields.count == 1,
                  preFocusedDescriptionFields.count == 1,
                  preValidationLabels.count == 1,
                  preKeyboards.count == 1,
                  preInputViews.count == 1,
                  preGlobalDoneButtons.count == 1 else {
                throw AutomationConfigurationError.invalid(
                    "S10.4 AX-text work-validation keyboard Done preconditions are invalid"
                )
            }
            let preDescriptionField = preDescriptionFields.element(boundBy: 0)
            let preValidationLabel = preValidationLabels.element(boundBy: 0)
            let globalDoneButton = preGlobalDoneButtons.element(boundBy: 0)
            let preDescriptionValue = preDescriptionField.value as? String
            let preValidationIdentifier = preValidationLabel.identifier
            let preValidationLabelText = preValidationLabel.label
            guard preDescriptionField.exists,
                  preDescriptionField.isEnabled,
                  preDescriptionField.isHittable,
                  preDescriptionValue == "Short description",
                  preValidationLabel.exists,
                  preValidationLabel.isEnabled,
                  preValidationIdentifier == "s5.1.work.validation",
                  preValidationLabelText == "Short description",
                  globalDoneButton.exists,
                  globalDoneButton.isEnabled,
                  globalDoneButton.isHittable,
                  globalDoneButton.identifier == "s5.1.work.keyboard-done",
                  globalDoneButton.label == "Done" else {
                throw AutomationConfigurationError.invalid(
                    "S10.4 AX-text work-validation keyboard Done semantic preconditions are invalid"
                )
            }
            globalDoneButton.tap()
            XCTAssertTrue(preKeyboards.firstMatch.waitForNonExistence(timeout: 10))

            let postWorkScreens = app.descendants(matching: .any).matching(
                identifier: "s5.1.work.screen"
            )
            let postDescriptionFields = app.descendants(matching: .any).matching(
                identifier: "s5.1.work.description"
            )
            let postFocusedDescriptionFields = postDescriptionFields.matching(
                focusedPredicate
            )
            let postValidationLabels = app.descendants(matching: .any).matching(
                identifier: "s5.1.work.validation"
            )
            let postWorkScreen = postWorkScreens.firstMatch
            let postDescriptionField = postDescriptionFields.firstMatch
            let postValidationLabel = postValidationLabels.firstMatch
            let postDescriptionValue = postDescriptionField.value as? String
            let postValidationIdentifier = postValidationLabel.identifier
            let postValidationLabelText = postValidationLabel.label
            let postAppState = app.state
            let postKeyboardCount = app.keyboards.count
            let postWorkScreenCount = postWorkScreens.count
            let postWorkScreenExists = postWorkScreen.exists
            let postWorkScreenEnabled = postWorkScreen.isEnabled
            let postWorkScreenHittable = postWorkScreen.isHittable
            let postDescriptionCount = postDescriptionFields.count
            let postDescriptionExists = postDescriptionField.exists
            let postDescriptionEnabled = postDescriptionField.isEnabled
            let postFocusedDescriptionCount = postFocusedDescriptionFields.count
            let postValidationCount = postValidationLabels.count
            let postValidationExists = postValidationLabel.exists
            let postValidationEnabled = postValidationLabel.isEnabled
            guard postAppState == .runningForeground,
                  postWorkScreenCount == 1,
                  postWorkScreenExists,
                  postWorkScreenEnabled,
                  postWorkScreenHittable,
                  postDescriptionCount == 1,
                  postDescriptionExists,
                  postDescriptionEnabled,
                  postDescriptionValue == "",
                  postFocusedDescriptionCount == 0,
                  postValidationCount == 1,
                  postValidationExists,
                  postValidationEnabled,
                  postValidationIdentifier == preValidationIdentifier,
                  postValidationLabelText == preValidationLabelText,
                  postKeyboardCount == 0 else {
                throw AutomationConfigurationError.invalid(
                    "S10.4 AX-text work-validation keyboard Done postconditions are invalid"
                )
            }
        }
        if automationShard?.deviceProfileID
            == "iphone-se-3-ios-18.0-minimum" {
            let workQuickPathIntroductionViews =
                app.descendants(matching: .other).matching(
                    identifier: "UIContinuousPathIntroductionView"
                )
            let workQuickPathIntroductionCount =
                workQuickPathIntroductionViews.count
            if workQuickPathIntroductionCount > 0 {
                let workQuickPathIntroductionView =
                    workQuickPathIntroductionViews.firstMatch
                let workQuickPathButtons =
                    workQuickPathIntroductionView.descendants(
                        matching: .button
                    )
                let workQuickPathStaticTexts =
                    workQuickPathIntroductionView.descendants(
                        matching: .staticText
                    )
                let workScreens = app.descendants(matching: .any).matching(
                    identifier: "s5.1.work.screen"
                )
                let workDescriptionFields =
                    app.descendants(matching: .any).matching(
                        identifier: "s5.1.work.description"
                    )
                let focusedPredicate = NSPredicate(
                    format: "hasKeyboardFocus == true"
                )
                let focusedWorkDescriptionFields =
                    workDescriptionFields.matching(focusedPredicate)
                let workValidationLabels =
                    app.descendants(matching: .any).matching(
                        identifier: "s5.1.work.validation"
                )
                let workKeyboards = app.keyboards
                let workQuickPathButtonCount = workQuickPathButtons.count
                let workQuickPathStaticTextCount = workQuickPathStaticTexts.count
                let preDismissWorkScreenCount = workScreens.count
                let workDescriptionCount = workDescriptionFields.count
                let focusedWorkDescriptionCount =
                    focusedWorkDescriptionFields.count
                let workValidationCount = workValidationLabels.count
                let workKeyboardCount = workKeyboards.count
                guard workQuickPathIntroductionCount == 1,
                      workQuickPathButtonCount == 1,
                      workQuickPathStaticTextCount == 2,
                      preDismissWorkScreenCount == 1,
                      workDescriptionCount == 1,
                      focusedWorkDescriptionCount == 1,
                      workValidationCount == 1,
                      workKeyboardCount == 1 else {
                    throw AutomationConfigurationError.invalid(
                        "S10.4 minimum work-validation QuickPath structure is invalid"
                    )
                }

                let workQuickPathButton = workQuickPathButtons.firstMatch
                let workQuickPathFirstStaticText =
                    workQuickPathStaticTexts.element(boundBy: 0)
                let workQuickPathSecondStaticText =
                    workQuickPathStaticTexts.element(boundBy: 1)
                let workScreen = workScreens.firstMatch
                let workDescriptionField = workDescriptionFields.firstMatch
                let workValidationLabel = workValidationLabels.firstMatch
                let workKeyboard = workKeyboards.firstMatch
                let workQuickPathFrameIsValid: (CGRect) -> Bool = { frame in
                    !frame.isNull
                        && !frame.isEmpty
                        && !frame.isInfinite
                        && frame.origin.x.isFinite
                        && frame.origin.y.isFinite
                        && frame.size.width.isFinite
                        && frame.size.height.isFinite
                }
                let applicationFrame = app.frame
                let workQuickPathIntroductionFrame =
                    workQuickPathIntroductionView.frame
                let workQuickPathButtonFrame = workQuickPathButton.frame
                let workQuickPathFirstStaticTextFrame =
                    workQuickPathFirstStaticText.frame
                let workQuickPathSecondStaticTextFrame =
                    workQuickPathSecondStaticText.frame
                let workKeyboardFrame = workKeyboard.frame
                let workScreenFrame = workScreen.frame
                let workDescriptionFrame = workDescriptionField.frame
                let workValidationFrame = workValidationLabel.frame
                guard workQuickPathFrameIsValid(applicationFrame),
                      workQuickPathFrameIsValid(workQuickPathIntroductionFrame),
                      workQuickPathFrameIsValid(workQuickPathButtonFrame),
                      workQuickPathFrameIsValid(
                        workQuickPathFirstStaticTextFrame
                      ),
                      workQuickPathFrameIsValid(
                        workQuickPathSecondStaticTextFrame
                      ),
                      workQuickPathFrameIsValid(workKeyboardFrame),
                      workQuickPathFrameIsValid(workScreenFrame),
                      workQuickPathFrameIsValid(workDescriptionFrame),
                      workQuickPathFrameIsValid(workValidationFrame) else {
                    throw AutomationConfigurationError.invalid(
                        "S10.4 minimum work-validation QuickPath frames are invalid"
                    )
                }
                let preActionButtonLabel = workQuickPathButton.label
                let preActionFirstTextLabel = workQuickPathFirstStaticText.label
                let preActionSecondTextLabel = workQuickPathSecondStaticText.label
                let firstTextIsActionTitle =
                    preActionFirstTextLabel == preActionButtonLabel
                    && workQuickPathFirstStaticTextFrame.intersects(
                        workQuickPathButtonFrame
                    )
                let secondTextIsActionTitle =
                    preActionSecondTextLabel == preActionButtonLabel
                    && workQuickPathSecondStaticTextFrame.intersects(
                        workQuickPathButtonFrame
                    )
                let workQuickPathTutorialFrame = firstTextIsActionTitle
                    ? workQuickPathSecondStaticTextFrame
                    : workQuickPathFirstStaticTextFrame
                let workQuickPathActionTitleFrame = firstTextIsActionTitle
                    ? workQuickPathFirstStaticTextFrame
                    : workQuickPathSecondStaticTextFrame
                let preActionAppState = app.state
                let preActionWorkScreenExists = workScreen.exists
                let preActionWorkScreenEnabled = workScreen.isEnabled
                let preActionDescriptionExists = workDescriptionField.exists
                let preActionDescriptionEnabled = workDescriptionField.isEnabled
                let preActionDescriptionHittable = workDescriptionField.isHittable
                let preActionDescriptionIdentifier = workDescriptionField.identifier
                let preActionDescriptionLabel = workDescriptionField.label
                let preActionDescriptionValue = workDescriptionField.value as? String
                let preActionValidationExists = workValidationLabel.exists
                let preActionValidationEnabled = workValidationLabel.isEnabled
                let preActionValidationIdentifier = workValidationLabel.identifier
                let preActionValidationLabel = workValidationLabel.label
                let preActionValidationValue = workValidationLabel.value as? String
                let preActionAppForeground =
                    preActionAppState == .runningForeground
                let preActionIntroductionExists =
                    workQuickPathIntroductionView.exists
                let preActionIntroductionType =
                    workQuickPathIntroductionView.elementType
                let preActionIntroductionIdentifier =
                    workQuickPathIntroductionView.identifier
                let preActionIntroductionTypeIsOther =
                    preActionIntroductionType == .other
                let preActionIntroductionIdentifierMatches =
                    preActionIntroductionIdentifier
                        == "UIContinuousPathIntroductionView"
                let preActionButtonExists = workQuickPathButton.exists
                let preActionButtonType = workQuickPathButton.elementType
                let preActionButtonIdentifier = workQuickPathButton.identifier
                let preActionButtonTypeIsButton =
                    preActionButtonType == .button
                let preActionButtonIdentifierIsEmpty =
                    preActionButtonIdentifier.isEmpty
                let preActionButtonLabelIsNonempty =
                    !preActionButtonLabel.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
                let preActionButtonEnabled = workQuickPathButton.isEnabled
                let preActionButtonHittable = workQuickPathButton.isHittable
                let preActionFirstTextExists =
                    workQuickPathFirstStaticText.exists
                let preActionFirstTextType =
                    workQuickPathFirstStaticText.elementType
                let preActionFirstTextIdentifier =
                    workQuickPathFirstStaticText.identifier
                let preActionFirstTextTypeIsStaticText =
                    preActionFirstTextType == .staticText
                let preActionFirstTextIdentifierIsEmpty =
                    preActionFirstTextIdentifier.isEmpty
                let preActionFirstTextLabelIsNonempty =
                    !preActionFirstTextLabel.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
                let preActionSecondTextExists =
                    workQuickPathSecondStaticText.exists
                let preActionSecondTextType =
                    workQuickPathSecondStaticText.elementType
                let preActionSecondTextIdentifier =
                    workQuickPathSecondStaticText.identifier
                let preActionSecondTextTypeIsStaticText =
                    preActionSecondTextType == .staticText
                let preActionSecondTextIdentifierIsEmpty =
                    preActionSecondTextIdentifier.isEmpty
                let preActionSecondTextLabelIsNonempty =
                    !preActionSecondTextLabel.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
                let preActionRoleIsExclusive =
                    firstTextIsActionTitle != secondTextIsActionTitle
                let preActionTutorialLabel = firstTextIsActionTitle
                    ? preActionSecondTextLabel
                    : preActionFirstTextLabel
                let preActionTutorialLabelDiffersFromButton =
                    preActionTutorialLabel != preActionButtonLabel
                let preActionApplicationContainsIntroduction =
                    applicationFrame.contains(workQuickPathIntroductionFrame)
                let preActionApplicationContainsKeyboard =
                    applicationFrame.contains(workKeyboardFrame)
                let preActionIntroductionContainsButton =
                    workQuickPathIntroductionFrame.contains(
                        workQuickPathButtonFrame
                    )
                let preActionIntroductionContainsFirstText =
                    workQuickPathIntroductionFrame.contains(
                        workQuickPathFirstStaticTextFrame
                    )
                let preActionIntroductionContainsSecondText =
                    workQuickPathIntroductionFrame.contains(
                        workQuickPathSecondStaticTextFrame
                    )
                let preActionIntroductionIntersectsKeyboard =
                    workQuickPathIntroductionFrame.intersects(
                        workKeyboardFrame
                    )
                let preActionTutorialPrecedesAction =
                    workQuickPathTutorialFrame.maxY
                        <= min(
                            workQuickPathActionTitleFrame.minY,
                            workQuickPathButtonFrame.minY
                        )
                let preActionTutorialAvoidsButton =
                    !workQuickPathTutorialFrame.intersects(
                        workQuickPathButtonFrame
                    )
                let preActionTutorialAvoidsActionTitle =
                    !workQuickPathTutorialFrame.intersects(
                        workQuickPathActionTitleFrame
                    )
                let preActionDescriptionIdentifierMatches =
                    preActionDescriptionIdentifier == "s5.1.work.description"
                let preActionDescriptionValueMatches =
                    preActionDescriptionValue == ""
                let preActionValidationIdentifierMatches =
                    preActionValidationIdentifier == "s5.1.work.validation"
                let preActionValidationLabelMatches =
                    preActionValidationLabel == "Short description"
                guard preActionAppForeground,
                      preActionIntroductionExists,
                      preActionIntroductionTypeIsOther,
                      preActionIntroductionIdentifierMatches,
                      preActionButtonExists,
                      preActionButtonTypeIsButton,
                      preActionButtonIdentifierIsEmpty,
                      preActionButtonLabelIsNonempty,
                      preActionButtonEnabled,
                      preActionButtonHittable,
                      preActionFirstTextExists,
                      preActionFirstTextTypeIsStaticText,
                      preActionFirstTextIdentifierIsEmpty,
                      preActionFirstTextLabelIsNonempty,
                      preActionSecondTextExists,
                      preActionSecondTextTypeIsStaticText,
                      preActionSecondTextIdentifierIsEmpty,
                      preActionSecondTextLabelIsNonempty,
                      preActionRoleIsExclusive,
                      preActionTutorialLabelDiffersFromButton,
                      preActionApplicationContainsIntroduction,
                      preActionApplicationContainsKeyboard,
                      preActionIntroductionContainsButton,
                      preActionIntroductionContainsFirstText,
                      preActionIntroductionContainsSecondText,
                      preActionIntroductionIntersectsKeyboard,
                      preActionTutorialPrecedesAction,
                      preActionTutorialAvoidsButton,
                      preActionTutorialAvoidsActionTitle,
                      preActionWorkScreenExists,
                      preActionWorkScreenEnabled,
                      preActionDescriptionExists,
                      preActionDescriptionEnabled,
                      preActionDescriptionHittable,
                      preActionDescriptionIdentifierMatches,
                      preActionDescriptionValueMatches,
                      preActionValidationExists,
                      preActionValidationEnabled,
                      preActionValidationIdentifierMatches,
                      preActionValidationLabelMatches else {
                    if let shard = automationShard,
                       shard.shardID == "s10.4.minimum.bounded"
                        || shard.shardID == "s10.4.minimum.accented" {
                        // Failure-only evidence: all inputs below were cached before this guard.
                        let failedGuardPredicates: [String: Bool] = [
                            "preActionAppForeground": preActionAppForeground,
                            "preActionIntroductionExists": preActionIntroductionExists,
                            "preActionIntroductionTypeIsOther": preActionIntroductionTypeIsOther,
                            "preActionIntroductionIdentifierMatches": preActionIntroductionIdentifierMatches,
                            "preActionButtonExists": preActionButtonExists,
                            "preActionButtonTypeIsButton": preActionButtonTypeIsButton,
                            "preActionButtonIdentifierIsEmpty": preActionButtonIdentifierIsEmpty,
                            "preActionButtonLabelIsNonempty": preActionButtonLabelIsNonempty,
                            "preActionButtonEnabled": preActionButtonEnabled,
                            "preActionButtonHittable": preActionButtonHittable,
                            "preActionFirstTextExists": preActionFirstTextExists,
                            "preActionFirstTextTypeIsStaticText": preActionFirstTextTypeIsStaticText,
                            "preActionFirstTextIdentifierIsEmpty": preActionFirstTextIdentifierIsEmpty,
                            "preActionFirstTextLabelIsNonempty": preActionFirstTextLabelIsNonempty,
                            "preActionSecondTextExists": preActionSecondTextExists,
                            "preActionSecondTextTypeIsStaticText": preActionSecondTextTypeIsStaticText,
                            "preActionSecondTextIdentifierIsEmpty": preActionSecondTextIdentifierIsEmpty,
                            "preActionSecondTextLabelIsNonempty": preActionSecondTextLabelIsNonempty,
                            "preActionRoleIsExclusive": preActionRoleIsExclusive,
                            "preActionTutorialLabelDiffersFromButton": preActionTutorialLabelDiffersFromButton,
                            "preActionApplicationContainsIntroduction": preActionApplicationContainsIntroduction,
                            "preActionApplicationContainsKeyboard": preActionApplicationContainsKeyboard,
                            "preActionIntroductionContainsButton": preActionIntroductionContainsButton,
                            "preActionIntroductionContainsFirstText": preActionIntroductionContainsFirstText,
                            "preActionIntroductionContainsSecondText": preActionIntroductionContainsSecondText,
                            "preActionIntroductionIntersectsKeyboard": preActionIntroductionIntersectsKeyboard,
                            "preActionTutorialPrecedesAction": preActionTutorialPrecedesAction,
                            "preActionTutorialAvoidsButton": preActionTutorialAvoidsButton,
                            "preActionTutorialAvoidsActionTitle": preActionTutorialAvoidsActionTitle,
                            "preActionWorkScreenExists": preActionWorkScreenExists,
                            "preActionWorkScreenEnabled": preActionWorkScreenEnabled,
                            "preActionDescriptionExists": preActionDescriptionExists,
                            "preActionDescriptionEnabled": preActionDescriptionEnabled,
                            "preActionDescriptionHittable": preActionDescriptionHittable,
                            "preActionDescriptionIdentifierMatches": preActionDescriptionIdentifierMatches,
                            "preActionDescriptionValueMatches": preActionDescriptionValueMatches,
                            "preActionValidationExists": preActionValidationExists,
                            "preActionValidationEnabled": preActionValidationEnabled,
                            "preActionValidationIdentifierMatches": preActionValidationIdentifierMatches,
                            "preActionValidationLabelMatches": preActionValidationLabelMatches,
                        ]
                        let cachedStrings: [String: String?] = [
                            "preActionIntroductionIdentifier": preActionIntroductionIdentifier,
                            "preActionButtonIdentifier": preActionButtonIdentifier,
                            "preActionButtonLabel": preActionButtonLabel,
                            "preActionFirstTextIdentifier": preActionFirstTextIdentifier,
                            "preActionFirstTextLabel": preActionFirstTextLabel,
                            "preActionSecondTextIdentifier": preActionSecondTextIdentifier,
                            "preActionSecondTextLabel": preActionSecondTextLabel,
                            "preActionDescriptionIdentifier": preActionDescriptionIdentifier,
                            "preActionDescriptionLabel": preActionDescriptionLabel,
                            "preActionDescriptionValue": preActionDescriptionValue,
                            "preActionValidationIdentifier": preActionValidationIdentifier,
                            "preActionValidationLabel": preActionValidationLabel,
                            "preActionValidationValue": preActionValidationValue,
                        ]
                        var boundedCachedStrings: [String: Any] = [:]
                        for (name, value) in cachedStrings {
                            if let value {
                                boundedCachedStrings[name] = [
                                    "value": String(value.prefix(4096)),
                                    "truncated": value.count > 4096,
                                ]
                            } else {
                                boundedCachedStrings[name] = NSNull()
                            }
                        }
                        // These frames already passed the finite/nonempty validation above.
                        let cachedFrames: [String: [String: Double]] = [
                            "applicationFrame": auditFrameObject(applicationFrame),
                            "workQuickPathIntroductionFrame": auditFrameObject(workQuickPathIntroductionFrame),
                            "workQuickPathButtonFrame": auditFrameObject(workQuickPathButtonFrame),
                            "workQuickPathFirstStaticTextFrame": auditFrameObject(workQuickPathFirstStaticTextFrame),
                            "workQuickPathSecondStaticTextFrame": auditFrameObject(workQuickPathSecondStaticTextFrame),
                            "workKeyboardFrame": auditFrameObject(workKeyboardFrame),
                            "workScreenFrame": auditFrameObject(workScreenFrame),
                            "workDescriptionFrame": auditFrameObject(workDescriptionFrame),
                            "workValidationFrame": auditFrameObject(workValidationFrame),
                            "workQuickPathTutorialFrame": auditFrameObject(workQuickPathTutorialFrame),
                            "workQuickPathActionTitleFrame": auditFrameObject(workQuickPathActionTitleFrame),
                        ]
                        printJSONLine(
                            prefix: "S10_4_WORK_VALIDATION_QUICKPATH_GUARD_FAILURE",
                            object: [
                                "acceptanceEligible": false,
                                "shardID": shard.shardID,
                                "targetStateID": "state.work.validation-error",
                                "predicates": failedGuardPredicates,
                                "falsePredicates": failedGuardPredicates
                                    .filter { !$0.value }.map { $0.key }.sorted(),
                                "cachedStrings": boundedCachedStrings,
                                "expectedDescriptionIdentifier": "s5.1.work.description",
                                "expectedDescriptionValue": "",
                                "expectedValidationIdentifier": "s5.1.work.validation",
                                "expectedValidationLabel": "Short description",
                                "cachedFrames": cachedFrames,
                            ]
                        )
                    }
                    throw AutomationConfigurationError.invalid(
                        "S10.4 minimum work-validation QuickPath state changed before dismissal"
                    )
                }

                workQuickPathButton.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
                ).tap()
                guard workQuickPathIntroductionView.waitForNonExistence(
                    timeout: 10
                ),
                      workQuickPathIntroductionViews.count == 0,
                      workQuickPathButtons.count == 0,
                      workQuickPathStaticTexts.count == 0 else {
                    throw AutomationConfigurationError.invalid(
                        "S10.4 minimum work-validation QuickPath did not dismiss"
                    )
                }

                let restoredWorkScreens =
                    app.descendants(matching: .any).matching(
                        identifier: "s5.1.work.screen"
                    )
                let restoredWorkDescriptionFields =
                    app.descendants(matching: .any).matching(
                        identifier: "s5.1.work.description"
                    )
                let restoredFocusedWorkDescriptionFields =
                    restoredWorkDescriptionFields.matching(focusedPredicate)
                let restoredWorkValidationLabels =
                    app.descendants(matching: .any).matching(
                        identifier: "s5.1.work.validation"
                    )
                let restoredWorkKeyboards = app.keyboards
                guard restoredWorkScreens.count == 1,
                      restoredWorkDescriptionFields.count == 1,
                      restoredFocusedWorkDescriptionFields.count == 1,
                      restoredWorkValidationLabels.count == 1,
                      restoredWorkKeyboards.count == 1 else {
                    throw AutomationConfigurationError.invalid(
                        "S10.4 minimum work-validation QuickPath restoration is incomplete"
                    )
                }
                let restoredWorkScreen = restoredWorkScreens.firstMatch
                let restoredWorkDescriptionField =
                    restoredWorkDescriptionFields.firstMatch
                let restoredWorkValidationLabel =
                    restoredWorkValidationLabels.firstMatch
                let restoredWorkKeyboard = restoredWorkKeyboards.firstMatch
                guard app.state == preActionAppState,
                      app.frame == applicationFrame,
                      restoredWorkScreen.exists
                        == preActionWorkScreenExists,
                      restoredWorkScreen.isEnabled
                        == preActionWorkScreenEnabled,
                      restoredWorkScreen.frame == workScreenFrame,
                      restoredWorkDescriptionField.exists
                        == preActionDescriptionExists,
                      restoredWorkDescriptionField.isEnabled
                        == preActionDescriptionEnabled,
                      restoredWorkDescriptionField.isHittable
                        == preActionDescriptionHittable,
                      restoredWorkDescriptionField.identifier
                        == preActionDescriptionIdentifier,
                      restoredWorkDescriptionField.label
                        == preActionDescriptionLabel,
                      (restoredWorkDescriptionField.value as? String)
                        == preActionDescriptionValue,
                      restoredWorkDescriptionField.frame
                        == workDescriptionFrame,
                      restoredWorkValidationLabel.exists
                        == preActionValidationExists,
                      restoredWorkValidationLabel.isEnabled
                        == preActionValidationEnabled,
                      restoredWorkValidationLabel.identifier
                        == preActionValidationIdentifier,
                      restoredWorkValidationLabel.label
                        == preActionValidationLabel,
                      (restoredWorkValidationLabel.value as? String)
                        == preActionValidationValue,
                      restoredWorkValidationLabel.frame == workValidationFrame,
                      restoredWorkKeyboard.exists,
                      restoredWorkKeyboard.frame == workKeyboardFrame else {
                    throw AutomationConfigurationError.invalid(
                        "S10.4 minimum work-validation state was not restored after QuickPath dismissal"
                    )
                }
            }
        }
        if automationShard?.shardID == "s10.4.minimum.minimum-os" {
            try dismissMinimumWorkValidationKeyboardAccessory(in: app)
            scroll(saveWork, in: app)
            assertControl(saveWork, label: "Record work")
        }
        captureBaseline("state.work.validation-error", in: app)
        scroll(description, in: app)
        assertMinimumGeometry(description)
        description.tap()
        description.typeText("Replaced failed power supply")
        dismissMultilineKeyboard(
            afterEditing: description,
            on: element("s5.1.work.screen", in: app),
            clearedValidation: validation,
            in: app
        )

        let workHelperLabel = "Add one optional photo showing the work performed."
        let importPhoto = element("s5.1.work.import-fixture", in: app)
        scroll(importPhoto, in: app)
        assertControl(
            importPhoto,
            label: workHelperLabel
        )
        importPhoto.tap()
        let workPreview = element("s5.1.work.photo", in: app)
        scroll(workPreview, in: app)
        XCTAssertTrue(workPreview.isHittable)
        let preparesWorkEditingEvidence = shouldPrepareNormalEvidence(
            for: "state.work.editing",
            in: app
        )
        let observedWorkHelperLabel = workPreview.label
        let workHelperTexts = app.staticTexts.matching(
            NSPredicate(format: "label == %@", observedWorkHelperLabel)
        )
        let minimumOSWorkHelperDuplicateExpected =
            automationShard?.deviceProfileID
                == "iphone-se-3-ios-18.0-minimum"
        let expectedWorkHelperTextCount =
            minimumOSWorkHelperDuplicateExpected ? 2 : 1
        let workScrollViews = app.scrollViews.containing(
            .image,
            identifier: "s5.1.work.photo"
        )
        let workNavigationBars = app.navigationBars.matching(
            identifier: observedRecordWorkTitle
        )
        let workHelper = workHelperTexts.firstMatch
        let minimumOSWorkImportFixtureLabel = workHelperTexts.element(boundBy: 1)
        let workScrollView = workScrollViews.firstMatch
        let workNavigationBar = workNavigationBars.firstMatch
        let verticalInset: CGFloat = 16
        let receiverInset: CGFloat = 24
        let minimumGestureDistance: CGFloat = 44
        var workEditingAXTextEnabled =
            automationShard?.shardID == "s10.4.current.ax-text"
                && preparesWorkEditingEvidence
        let workPreviewImages = app.images.matching(
            NSPredicate(format: "identifier == %@", "s5.1.work.photo")
        )
        let workEditingTabBars = app.tabBars
        let workPreviewImage = workPreviewImages.firstMatch
        let workEditingFrameIsValid: (CGRect) -> Bool = { frame in
            !frame.isNull
                && !frame.isEmpty
                && frame.origin.x.isFinite
                && frame.origin.y.isFinite
                && frame.size.width.isFinite
                && frame.size.height.isFinite
        }
        let workHelperTextBindingsAreValid: () -> Bool = {
            guard workHelperTexts.count == expectedWorkHelperTextCount else {
                return false
            }
            guard minimumOSWorkHelperDuplicateExpected else {
                return true
            }
            guard workHelper.exists,
                  importPhoto.exists,
                  minimumOSWorkImportFixtureLabel.exists else {
                return false
            }
            let helperFrame = workHelper.frame
            let importFixtureFrame = importPhoto.frame
            let nestedLabelFrame = minimumOSWorkImportFixtureLabel.frame
            return importPhoto.elementType == .button
                && importPhoto.identifier == "s5.1.work.import-fixture"
                && importPhoto.label == observedWorkHelperLabel
                && minimumOSWorkImportFixtureLabel.elementType == .staticText
                && minimumOSWorkImportFixtureLabel.identifier.isEmpty
                && minimumOSWorkImportFixtureLabel.label == observedWorkHelperLabel
                && (minimumOSWorkImportFixtureLabel.value as? String) == ""
                && workEditingFrameIsValid(helperFrame)
                && workEditingFrameIsValid(importFixtureFrame)
                && workEditingFrameIsValid(nestedLabelFrame)
                && nestedLabelFrame == importFixtureFrame
                && helperFrame != nestedLabelFrame
                && helperFrame.maxY < nestedLabelFrame.minY
        }
        let workEditingComposition: () -> Bool = {
            app.state == .runningForeground
                && workHelperTextBindingsAreValid()
                && workPreviewImages.count == 1
                && workScrollViews.count == 1
                && workNavigationBars.count == 1
                && workEditingTabBars.count == 0
                && workHelper.exists
                && workPreviewImage.exists
                && workScrollView.exists
                && workNavigationBar.exists
                && workHelper.elementType == .staticText
                && workHelper.identifier.isEmpty
                && workHelper.label == observedWorkHelperLabel
                && (workHelper.value as? String) == ""
                && workPreviewImage.elementType == .image
                && workPreviewImage.identifier == "s5.1.work.photo"
                && workPreviewImage.label == observedWorkHelperLabel
                && (workPreviewImage.value as? String) == ""
                && workScrollView.elementType == .scrollView
                && workScrollView.identifier == "s5.1.work.screen"
                && workScrollView.label == ""
                && (workScrollView.value as? String) == ""
                && workNavigationBar.elementType == .navigationBar
                && workNavigationBar.identifier == observedRecordWorkTitle
                && workNavigationBar.label == ""
                && (workNavigationBar.value as? String) == ""
                && workEditingFrameIsValid(app.frame)
                && workEditingFrameIsValid(workHelper.frame)
                && workEditingFrameIsValid(workPreviewImage.frame)
                && workEditingFrameIsValid(workScrollView.frame)
                && workEditingFrameIsValid(workNavigationBar.frame)
        }
        let workEditingGeometryFixedPointScale: CGFloat = 1_048_576
        let workEditingGeometryFixedPoint: (CGFloat?) -> Int64? = { value in
            guard let value, value.isFinite else { return nil }
            let scaledValue = (value * workEditingGeometryFixedPointScale)
                .rounded(.toNearestOrAwayFromZero)
            guard scaledValue.isFinite else { return nil }
            return Int64(exactly: scaledValue)
        }
        var initialHelperToPreviewSeparation: CGFloat?
        var initialHelperToPreviewSeparationFixedPoint: Int64?
        var workEditingAXTextFallbackAccepted = false
        if preparesWorkEditingEvidence {
        guard workHelperTextBindingsAreValid(),
              workScrollViews.count == 1,
              workNavigationBars.count == 1 else {
            XCTFail("Record-work editing positioning bindings are ambiguous.")
            return
        }
        guard workHelper.exists,
              workScrollView.exists,
              workNavigationBar.exists else {
            XCTFail("Record-work editing positioning bindings are missing.")
            return
        }
        var workEditingInitialSeparation = false
        var workEditingInitialProof = !workEditingAXTextEnabled
        if workEditingAXTextEnabled {
            let initialApplicationFrame = app.frame
            let initialNavigationFrame = workNavigationBar.frame
            let initialScrollRawFrame = workScrollView.frame
            let initialHelperFrame = workHelper.frame
            let initialPreviewFrame = workPreviewImage.frame
            let initialCommonFramesAreValid =
                workEditingFrameIsValid(initialApplicationFrame)
                    && workEditingFrameIsValid(initialNavigationFrame)
                    && workEditingFrameIsValid(initialScrollRawFrame)
                    && workEditingFrameIsValid(initialHelperFrame)
            let initialAXFramesAreValid =
                workEditingFrameIsValid(initialPreviewFrame)
            let initialCompositionIsValid =
                initialCommonFramesAreValid
                    && initialAXFramesAreValid
                    && workEditingComposition()
            if initialCompositionIsValid {
                let initialScrollFrame = initialScrollRawFrame.intersection(
                    initialApplicationFrame
                )
                if workEditingFrameIsValid(initialScrollFrame) {
                    let initialSafeTop = max(
                        initialScrollFrame.minY,
                        initialNavigationFrame.maxY
                    ) + verticalInset
                    let initialSafeBottom =
                        initialScrollFrame.maxY - verticalInset
                    let requiredHelperDownwardMovement =
                        initialSafeTop - initialHelperFrame.minY
                    let requiredPreviewBelowViewportMovement =
                        initialScrollFrame.maxY + verticalInset
                            - initialPreviewFrame.minY
                    let requiredRigidDownwardMovement = max(
                        requiredHelperDownwardMovement,
                        requiredPreviewBelowViewportMovement
                    )
                    let helperRoomToSafeBottom =
                        initialSafeBottom - initialHelperFrame.maxY
                    let exactSeparation =
                        initialPreviewFrame.minY - initialHelperFrame.maxY
                    initialHelperToPreviewSeparation = exactSeparation
                    initialHelperToPreviewSeparationFixedPoint =
                        workEditingGeometryFixedPoint(exactSeparation)
                    workEditingInitialSeparation =
                        requiredHelperDownwardMovement > 0
                            && requiredPreviewBelowViewportMovement > 0
                            && requiredRigidDownwardMovement
                                <= helperRoomToSafeBottom
                            && exactSeparation > 0
                    workEditingInitialProof =
                        workEditingInitialSeparation
                }
            }
            guard workEditingInitialProof else {
                XCTFail("Record-work editing AX-text rigid composition proof failed.")
                return
            }
        }
        var provenGestureCount = 0
        for _ in 0..<4 {
            guard app.state == .runningForeground,
                  workHelperTextBindingsAreValid(),
                  workScrollViews.count == 1,
                  workNavigationBars.count == 1,
                  workHelper.exists,
                  workScrollView.exists,
                  workNavigationBar.exists,
                  workPreview.exists else {
                XCTFail("Record-work editing positioning route changed.")
                return
            }
            let scrollFrame = workScrollView.frame
            let applicationFrame = app.frame
            let navigationFrame = workNavigationBar.frame
            let helperFrame = workHelper.frame
            let previewFrame = workPreviewImage.frame
            let commonFramesAreValid =
                workEditingFrameIsValid(applicationFrame)
                    && workEditingFrameIsValid(scrollFrame)
                    && workEditingFrameIsValid(navigationFrame)
                    && workEditingFrameIsValid(helperFrame)
            let axFramesAreValid =
                workEditingFrameIsValid(previewFrame)
            let rawFramesAreValid =
                commonFramesAreValid
                    && (!workEditingAXTextEnabled || axFramesAreValid)
            var liveScrollFrame = CGRect.null
            if rawFramesAreValid {
                liveScrollFrame = scrollFrame.intersection(applicationFrame)
            }
            let liveFramesAreValid =
                rawFramesAreValid && workEditingFrameIsValid(liveScrollFrame)
            var safeTop: CGFloat?
            var safeBottom: CGFloat?
            var receiverTop: CGFloat?
            var receiverBottom: CGFloat?
            if liveFramesAreValid {
                safeTop = max(
                    liveScrollFrame.minY,
                    navigationFrame.maxY
                ) + verticalInset
                safeBottom = liveScrollFrame.maxY - verticalInset
                receiverTop = max(
                    liveScrollFrame.minY,
                    navigationFrame.maxY
                ) + receiverInset
                receiverBottom = liveScrollFrame.maxY - receiverInset
            }
            guard let safeTop = safeTop,
                  let safeBottom = safeBottom,
                  let receiverTop = receiverTop,
                  let receiverBottom = receiverBottom,
                  safeBottom > safeTop,
                  helperFrame.height <= safeBottom - safeTop else {
                XCTFail("Record-work editing viewport geometry is invalid.")
                return
            }
            let previewPlacementAccepted =
                !workEditingAXTextEnabled
                    || workPreviewImage.isHittable
                    || previewFrame.minY > liveScrollFrame.maxY
            if helperFrame.minY >= safeTop,
               helperFrame.maxY <= safeBottom,
               workHelper.isHittable,
               previewPlacementAccepted {
                break
            }

            let minimumShift = safeTop - helperFrame.minY
            let maximumShift = safeBottom - helperFrame.maxY
            let requiredPreviewBelowViewportMovement =
                liveScrollFrame.maxY + verticalInset - previewFrame.minY
            let requiredRigidDownwardMovement = workEditingAXTextEnabled
                ? max(minimumShift, requiredPreviewBelowViewportMovement)
                : minimumShift
            let receiverCapacity = receiverBottom - receiverTop
            let recognizedMinimum = max(
                requiredRigidDownwardMovement,
                minimumGestureDistance
            )
            let recognizedMaximum = min(
                maximumShift,
                receiverCapacity
            )
            guard requiredRigidDownwardMovement > 0,
                  requiredRigidDownwardMovement <= maximumShift,
                  receiverCapacity >= minimumGestureDistance,
                  recognizedMinimum <= recognizedMaximum else {
                XCTFail("Record-work editing has no feasible downward correction.")
                return
            }
            let dragDistance = recognizedMinimum
            let scrollOrigin = workScrollView.coordinate(
                withNormalizedOffset: CGVector(dx: 0, dy: 0)
            )
            let dragStart = scrollOrigin.withOffset(
                CGVector(
                    dx: scrollFrame.width / 2,
                    dy: receiverTop - scrollFrame.minY
                )
            )
            let dragEnd = dragStart.withOffset(
                CGVector(dx: 0, dy: dragDistance)
            )
            let helperMinYBeforeDrag = helperFrame.minY
            let previewMinYBeforeDrag = previewFrame.minY
            dragStart.press(
                forDuration: 0.2,
                thenDragTo: dragEnd,
                withVelocity: .slow,
                thenHoldForDuration: 0.2
            )
            let observedHelperFrame = workHelper.frame
            let observedPreviewFrame = workPreviewImage.frame
            let observedCommonFramesAreValid =
                workEditingFrameIsValid(observedHelperFrame)
            let observedAXFramesAreValid =
                workEditingFrameIsValid(observedPreviewFrame)
            let observedFramesAreValid =
                observedCommonFramesAreValid
                    && (!workEditingAXTextEnabled || observedAXFramesAreValid)
            if workEditingAXTextEnabled {
                var observedHelperDownwardMovement: CGFloat?
                var observedPreviewDownwardMovement: CGFloat?
                if observedFramesAreValid {
                    observedHelperDownwardMovement =
                        observedHelperFrame.minY - helperMinYBeforeDrag
                    observedPreviewDownwardMovement =
                        observedPreviewFrame.minY - previewMinYBeforeDrag
                }
                guard let observedHelperDownwardMovement =
                        observedHelperDownwardMovement,
                      let observedPreviewDownwardMovement =
                        observedPreviewDownwardMovement,
                      observedHelperDownwardMovement > 0,
                      observedPreviewDownwardMovement > 0,
                      observedHelperDownwardMovement
                        == observedPreviewDownwardMovement else {
                    XCTFail(
                        "Record-work editing AX-text rigid co-movement proof failed."
                    )
                    return
                }
                provenGestureCount += 1
            }
            guard workHelperTextBindingsAreValid(),
                  workScrollViews.count == 1,
                  workNavigationBars.count == 1,
                  workHelper.exists,
                  observedFramesAreValid,
                  observedHelperFrame.minY > helperMinYBeforeDrag else {
                XCTFail("Record-work helper did not move downward.")
                return
            }
        }
        let finalApplicationFrame = app.frame
        let finalNavigationFrame = workNavigationBar.frame
        let finalScrollRawFrame = workScrollView.frame
        let finalHelperFrame = workHelper.frame
        let finalPreviewFrame = workPreviewImage.frame
        let finalCommonFramesAreValid =
            workEditingFrameIsValid(finalApplicationFrame)
                && workEditingFrameIsValid(finalNavigationFrame)
                && workEditingFrameIsValid(finalScrollRawFrame)
                && workEditingFrameIsValid(finalHelperFrame)
        let finalAXFramesAreValid =
            workEditingFrameIsValid(finalPreviewFrame)
        let finalFramesAreValid =
            finalCommonFramesAreValid
                && (!workEditingAXTextEnabled || finalAXFramesAreValid)
        var finalScrollFrame = CGRect.null
        var finalSafeTop: CGFloat?
        var finalSafeBottom: CGFloat?
        var finalHelperToPreviewSeparation: CGFloat?
        if finalFramesAreValid {
            finalScrollFrame = finalScrollRawFrame.intersection(
                finalApplicationFrame
            )
            if workEditingFrameIsValid(finalScrollFrame) {
                finalSafeTop = max(
                    finalScrollFrame.minY,
                    finalNavigationFrame.maxY
                ) + verticalInset
                finalSafeBottom = finalScrollFrame.maxY - verticalInset
                if workEditingAXTextEnabled && finalAXFramesAreValid {
                    finalHelperToPreviewSeparation =
                        finalPreviewFrame.minY - finalHelperFrame.maxY
                }
            }
        }
        let finalScrollFrameIsValid = workEditingFrameIsValid(finalScrollFrame)
        let finalWorkEditingCompositionIsValid =
            !workEditingAXTextEnabled
                || (finalFramesAreValid
                    && finalScrollFrameIsValid
                    && workEditingComposition())
        let finalHelperToPreviewSeparationFixedPoint =
            workEditingGeometryFixedPoint(finalHelperToPreviewSeparation)
        let finalHelperIsHittable = workHelper.isHittable
        let finalExactPreviewIsHittable = workPreviewImage.isHittable
        let finalWorkPreviewIsHittable = workPreview.isHittable
        workEditingAXTextFallbackAccepted =
            workEditingAXTextEnabled
                && !finalExactPreviewIsHittable
                && !finalWorkPreviewIsHittable
                && workEditingInitialProof
                && initialHelperToPreviewSeparationFixedPoint != nil
                && provenGestureCount >= 1
                && provenGestureCount <= 4
                && finalFramesAreValid
                && finalScrollFrameIsValid
                && finalWorkEditingCompositionIsValid
                && finalHelperToPreviewSeparationFixedPoint
                    == initialHelperToPreviewSeparationFixedPoint
                && finalHelperFrame.maxY < finalPreviewFrame.minY
                && finalPreviewFrame.minY > finalScrollFrame.maxY
        let workPreviewHittabilityAccepted: Bool
        if workEditingAXTextEnabled {
            workPreviewHittabilityAccepted =
                finalExactPreviewIsHittable
                    || finalWorkPreviewIsHittable
                    || workEditingAXTextFallbackAccepted
        } else {
            workPreviewHittabilityAccepted = finalWorkPreviewIsHittable
        }
        guard app.state == .runningForeground,
              workHelperTextBindingsAreValid(),
              workScrollViews.count == 1,
              workNavigationBars.count == 1,
              workHelper.exists,
              workScrollView.exists,
              workNavigationBar.exists,
              workPreview.exists,
              finalFramesAreValid,
              finalScrollFrameIsValid,
              finalWorkEditingCompositionIsValid,
              let finalSafeTop = finalSafeTop,
              let finalSafeBottom = finalSafeBottom,
              workEditingFrameIsValid(finalApplicationFrame),
              workEditingFrameIsValid(finalNavigationFrame),
              workEditingFrameIsValid(finalScrollFrame),
              workEditingFrameIsValid(finalHelperFrame),
              finalHelperFrame.minY >= finalSafeTop,
              finalHelperFrame.maxY <= finalSafeBottom,
              finalHelperIsHittable,
              workPreviewHittabilityAccepted else {
            XCTFail("Record-work editing composition is outside the safe viewport.")
            return
        }
        }
        captureBaseline("state.work.editing", in: app)

        scroll(saveWork, in: app)
        assertControl(saveWork, label: "Record work")
        saveWork.tap()
        let progress = element("s5.1.work.saving", in: app)
        XCTAssertTrue(progress.waitForExistence(timeout: 10))
        assertLocalizedLabel(progress, equals: "Record work")
        let preparesWorkSavingEvidence = shouldPrepareNormalEvidence(
            for: "state.work.saving",
            in: app
        )
        workEditingAXTextEnabled =
            automationShard?.shardID == "s10.4.current.ax-text"
                && preparesWorkSavingEvidence
        if preparesWorkSavingEvidence {
        let workNoteHeadings = app.staticTexts.matching(
            NSPredicate(format: "label == %@", "Note")
        )
        let workTabBars = app.tabBars
        let expectedWorkSavingTabBarCount: Int
        if #available(iOS 26.0, *) {
            expectedWorkSavingTabBarCount = 0
        } else {
            expectedWorkSavingTabBarCount = 1
        }
        let workNoteHeading = workNoteHeadings.firstMatch
        let workImportFixtureButtons: XCUIElementQuery? = workEditingAXTextEnabled
            ? app.buttons.matching(identifier: "s5.1.work.import-fixture")
            : nil
        let workImportFixtureButton = workImportFixtureButtons?.firstMatch
        let workSavingHelperTextBindingsAreValid: () -> Bool = {
            guard minimumOSWorkHelperDuplicateExpected else {
                return workHelperTexts.count == expectedWorkHelperTextCount
            }
            guard workHelperTexts.count == 1,
                  workHelper.exists else {
                return false
            }
            return workHelper.elementType == .staticText
                && workHelper.identifier.isEmpty
                && workHelper.label == observedWorkHelperLabel
                && (workHelper.value as? String) == ""
                && workEditingFrameIsValid(workHelper.frame)
        }
        var savingInitialAXTextCompositionIsValid = !workEditingAXTextEnabled
        if workEditingAXTextEnabled {
            let savingInitialHelperFrame = workHelper.frame
            let savingInitialPreviewFrame = workPreviewImage.frame
            let savingInitialSeparation =
                savingInitialPreviewFrame.minY - savingInitialHelperFrame.maxY
            savingInitialAXTextCompositionIsValid =
                workImportFixtureButtons?.count == 1
                    && workImportFixtureButton?.exists == true
                    && workImportFixtureButton?.elementType == .button
                    && workImportFixtureButton?.identifier
                        == "s5.1.work.import-fixture"
                    && workImportFixtureButton?.label == observedWorkHelperLabel
                    && (workImportFixtureButton?.value as? String) == ""
                    && workImportFixtureButton?.isEnabled == false
                    && workEditingAXTextFallbackAccepted
                    && initialHelperToPreviewSeparation != nil
                    && workEditingComposition()
                    && workEditingFrameIsValid(savingInitialHelperFrame)
                    && workEditingFrameIsValid(savingInitialPreviewFrame)
                    && savingInitialSeparation
                        == initialHelperToPreviewSeparation
        }
        guard app.state == .runningForeground,
              workNoteHeadings.count == 1,
              workTabBars.count == expectedWorkSavingTabBarCount,
              workSavingHelperTextBindingsAreValid(),
              workScrollViews.count == 1,
              workNavigationBars.count == 1,
              workNoteHeading.exists,
              workNoteHeading.identifier.isEmpty,
              workNoteHeading.label == "Note",
              workNoteHeading.elementType == .staticText,
              workHelper.exists,
              workScrollView.exists,
              workNavigationBar.exists,
              workPreview.exists,
              progress.exists,
              savingInitialAXTextCompositionIsValid else {
            XCTFail("Record-work saving positioning route changed.")
            return
        }
        var provenSavingGestureCount = 0
        var savingAXTextGestureDirection: CGFloat?
        for _ in 0..<4 {
            guard app.state == .runningForeground,
                  workNoteHeadings.count == 1,
                  workTabBars.count == expectedWorkSavingTabBarCount,
                  workSavingHelperTextBindingsAreValid(),
                  workScrollViews.count == 1,
                  workNavigationBars.count == 1,
                  (!workEditingAXTextEnabled
                    || workImportFixtureButtons?.count == 1),
                  (!workEditingAXTextEnabled
                    || workPreviewImages.count == 1),
                  workNoteHeading.exists,
                  workHelper.exists,
                  workScrollView.exists,
                  workNavigationBar.exists,
                  workPreview.exists,
                  (!workEditingAXTextEnabled
                    || workImportFixtureButton?.exists == true),
                  (!workEditingAXTextEnabled
                    || (workImportFixtureButton?.elementType == .button
                        && workImportFixtureButton?.identifier
                            == "s5.1.work.import-fixture"
                        && workImportFixtureButton?.label == observedWorkHelperLabel
                        && (workImportFixtureButton?.value as? String) == ""
                        && workImportFixtureButton?.isEnabled == false)),
                  progress.exists else {
                XCTFail("Record-work saving positioning route changed.")
                return
            }
            let scrollFrame = workScrollView.frame
            let applicationFrame = app.frame
            let navigationFrame = workNavigationBar.frame
            let noteFrame = workNoteHeading.frame
            let helperFrame = workHelper.frame
            var buttonFrame = CGRect.null
            var photoFrame = CGRect.null
            if workEditingAXTextEnabled {
                buttonFrame = workImportFixtureButton?.frame ?? .null
                photoFrame = workPreviewImage.frame
            }
            let ordinaryCommonFramesAreValid =
                !applicationFrame.isNull
                    && !applicationFrame.isEmpty
                    && !navigationFrame.isNull
                    && !navigationFrame.isEmpty
                    && !scrollFrame.isNull
                    && !scrollFrame.isEmpty
                    && !noteFrame.isNull
                    && !noteFrame.isEmpty
                    && !helperFrame.isNull
                    && !helperFrame.isEmpty
            let savingAXTextCommonFramesAreValid =
                workEditingFrameIsValid(applicationFrame)
                    && workEditingFrameIsValid(navigationFrame)
                    && workEditingFrameIsValid(scrollFrame)
                    && workEditingFrameIsValid(noteFrame)
                    && workEditingFrameIsValid(helperFrame)
            let commonFramesAreValid = workEditingAXTextEnabled
                ? savingAXTextCommonFramesAreValid
                : ordinaryCommonFramesAreValid
            let savingAXTextFramesAreValid =
                !workEditingAXTextEnabled
                    || (workEditingFrameIsValid(buttonFrame)
                        && workEditingFrameIsValid(photoFrame))
            let savingAXTextOrderingIsValid =
                !workEditingAXTextEnabled
                    || (noteFrame.maxY < helperFrame.minY
                        && helperFrame.maxY < buttonFrame.minY
                        && buttonFrame.maxY < photoFrame.minY)
            guard commonFramesAreValid,
                  savingAXTextFramesAreValid,
                  savingAXTextOrderingIsValid else {
                XCTFail("Record-work saving viewport geometry is invalid.")
                return
            }
            let liveScrollFrame = scrollFrame.intersection(applicationFrame)
            let liveScrollFrameIsValid = workEditingAXTextEnabled
                ? workEditingFrameIsValid(liveScrollFrame)
                : (!liveScrollFrame.isNull && !liveScrollFrame.isEmpty)
            guard liveScrollFrameIsValid else {
                XCTFail("Record-work saving viewport geometry is invalid.")
                return
            }
            let liveBottom = liveScrollFrame.maxY
            let safeTop = max(
                liveScrollFrame.minY,
                navigationFrame.maxY
            ) + verticalInset
            let safeBottom = liveBottom - verticalInset
            let receiverTop = max(
                liveScrollFrame.minY,
                navigationFrame.maxY
            ) + receiverInset
            let receiverBottom = liveBottom - receiverInset
            let targetTop = min(noteFrame.minY, helperFrame.minY)
            let targetBottom = max(noteFrame.maxY, helperFrame.maxY)
            let ordinaryTargetFits =
                targetBottom - targetTop <= safeBottom - safeTop
            guard safeBottom > safeTop,
                  (workEditingAXTextEnabled || ordinaryTargetFits) else {
                XCTFail("Record-work saving viewport geometry is invalid.")
                return
            }
            let ordinaryCompositionIsComplete =
                noteFrame.minY >= safeTop
                    && noteFrame.maxY <= safeBottom
                    && helperFrame.minY >= safeTop
                    && helperFrame.maxY <= safeBottom
                    && workNoteHeading.isHittable
                    && workHelper.isHittable
            let savingAXTextCompositionIsComplete =
                workEditingAXTextEnabled
                    && noteFrame.maxY <= safeTop
                    && helperFrame.maxY <= safeTop
                    && buttonFrame.minY >= safeTop
                    && buttonFrame.maxY <= safeBottom
                    && workImportFixtureButton?.isHittable == true
                    && noteFrame.maxY < helperFrame.minY
                    && helperFrame.maxY < buttonFrame.minY
                    && buttonFrame.maxY < photoFrame.minY
            if (!workEditingAXTextEnabled && ordinaryCompositionIsComplete)
                || savingAXTextCompositionIsComplete {
                break
            }

            var previewMinYBeforeDrag: CGFloat?
            var buttonMinYBeforeDrag: CGFloat?
            var savingAXTextPreviewFrameIsValid = !workEditingAXTextEnabled
            if workEditingAXTextEnabled {
                previewMinYBeforeDrag = photoFrame.minY
                buttonMinYBeforeDrag = buttonFrame.minY
                savingAXTextPreviewFrameIsValid =
                    workEditingFrameIsValid(photoFrame)
                        && workEditingFrameIsValid(buttonFrame)
            }
            let minimumShift: CGFloat
            let maximumShift: CGFloat
            if workEditingAXTextEnabled {
                minimumShift = safeTop - buttonFrame.minY
                maximumShift = min(
                    safeTop - noteFrame.maxY,
                    min(
                        safeTop - helperFrame.maxY,
                        safeBottom - buttonFrame.maxY
                    )
                )
            } else {
                minimumShift = max(
                    safeTop - noteFrame.minY,
                    safeTop - helperFrame.minY
                )
                maximumShift = min(
                    safeBottom - noteFrame.maxY,
                    safeBottom - helperFrame.maxY
                )
            }
            let receiverCapacity = receiverBottom - receiverTop
            guard minimumShift <= maximumShift,
                  receiverCapacity >= minimumGestureDistance,
                  savingAXTextPreviewFrameIsValid else {
                XCTFail("Record-work saving has no feasible recognized shift.")
                return
            }
            let dragDistance: CGFloat
            if maximumShift < 0 {
                if workEditingAXTextEnabled,
                   maximumShift < -receiverCapacity {
                    dragDistance = -receiverCapacity
                } else {
                    let recognizedMinimum = max(
                        minimumShift,
                        -receiverCapacity
                    )
                    let recognizedMaximum = min(
                        maximumShift,
                        -minimumGestureDistance
                    )
                    guard recognizedMinimum <= recognizedMaximum else {
                        XCTFail("Record-work saving upward shift is not recognizable.")
                        return
                    }
                    dragDistance = workEditingAXTextEnabled
                        ? recognizedMinimum
                        : recognizedMaximum
                }
            } else if minimumShift > 0 {
                let recognizedMinimum = max(
                    minimumShift,
                    minimumGestureDistance
                )
                let recognizedMaximum = min(
                    maximumShift,
                    receiverCapacity
                )
                if recognizedMinimum <= recognizedMaximum {
                    dragDistance = workEditingAXTextEnabled
                        ? recognizedMaximum
                        : recognizedMinimum
                } else if workEditingAXTextEnabled,
                          minimumShift > receiverCapacity {
                    dragDistance = receiverCapacity
                } else {
                    XCTFail("Record-work saving downward shift is not recognizable.")
                    return
                }
            } else {
                XCTFail("Record-work saving feasible shift is directionless.")
                return
            }
            if workEditingAXTextEnabled {
                let gestureDirection: CGFloat = dragDistance > 0 ? 1 : -1
                if let savingAXTextGestureDirection {
                    guard gestureDirection == savingAXTextGestureDirection else {
                        XCTFail("Record-work saving AX-text gesture reversed direction.")
                        return
                    }
                } else {
                    savingAXTextGestureDirection = gestureDirection
                }
            }
            let scrollOrigin = workScrollView.coordinate(
                withNormalizedOffset: CGVector(dx: 0, dy: 0)
            )
            let dragStartY = dragDistance > 0 ? receiverTop : receiverBottom
            let dragStart = scrollOrigin.withOffset(
                CGVector(
                    dx: scrollFrame.width / 2,
                    dy: dragStartY - scrollFrame.minY
                )
            )
            let dragEnd = dragStart.withOffset(
                CGVector(dx: 0, dy: dragDistance)
            )
            let noteMinYBeforeDrag = noteFrame.minY
            let helperMinYBeforeDrag = helperFrame.minY
            dragStart.press(
                forDuration: 0.2,
                thenDragTo: dragEnd,
                withVelocity: .slow,
                thenHoldForDuration: 0.2
            )
            guard workNoteHeadings.count == 1,
                  workTabBars.count == expectedWorkSavingTabBarCount,
                  workSavingHelperTextBindingsAreValid(),
                  workScrollViews.count == 1,
                  workNavigationBars.count == 1,
                  (!workEditingAXTextEnabled
                    || workImportFixtureButtons?.count == 1),
                  (!workEditingAXTextEnabled
                    || workPreviewImages.count == 1),
                  workNoteHeading.exists,
                  workHelper.exists,
                  (!workEditingAXTextEnabled || workPreview.exists),
                  (!workEditingAXTextEnabled
                    || workImportFixtureButton?.exists == true),
                  (!workEditingAXTextEnabled
                    || (workImportFixtureButton?.elementType == .button
                        && workImportFixtureButton?.identifier
                            == "s5.1.work.import-fixture"
                        && workImportFixtureButton?.label == observedWorkHelperLabel
                        && (workImportFixtureButton?.value as? String) == ""
                        && workImportFixtureButton?.isEnabled == false)),
                  progress.exists else {
                XCTFail("Record-work saving positioning gesture was not recognized.")
                return
            }
            let observedNoteFrame = workNoteHeading.frame
            let observedHelperFrame = workHelper.frame
            let observedNoteShift = observedNoteFrame.minY - noteMinYBeforeDrag
            let observedHelperShift = observedHelperFrame.minY - helperMinYBeforeDrag
            let savingAXTextPrimaryFramesAreValid =
                !workEditingAXTextEnabled
                    || (workEditingFrameIsValid(observedNoteFrame)
                        && workEditingFrameIsValid(observedHelperFrame))
            var savingAXTextCoMovementIsValid = !workEditingAXTextEnabled
            var savingAXTextObservedOrderingIsValid = !workEditingAXTextEnabled
            if workEditingAXTextEnabled,
               let previewMinYBeforeDrag,
               let buttonMinYBeforeDrag {
                let observedPreviewFrame = workPreviewImage.frame
                let observedButtonFrame = workImportFixtureButton?.frame ?? .null
                let observedPreviewShift =
                    observedPreviewFrame.minY - previewMinYBeforeDrag
                let observedButtonShift =
                    observedButtonFrame.minY - buttonMinYBeforeDrag
                let observedAXTextFramesAreValid =
                    workEditingFrameIsValid(observedNoteFrame)
                        && workEditingFrameIsValid(observedHelperFrame)
                        && workEditingFrameIsValid(observedPreviewFrame)
                        && workEditingFrameIsValid(observedButtonFrame)
                savingAXTextCoMovementIsValid =
                    observedAXTextFramesAreValid
                        && observedPreviewShift * dragDistance > 0
                        && observedButtonShift * dragDistance > 0
                savingAXTextObservedOrderingIsValid =
                    observedAXTextFramesAreValid
                        && observedNoteFrame.maxY < observedHelperFrame.minY
                        && observedHelperFrame.maxY < observedButtonFrame.minY
                        && observedButtonFrame.maxY < observedPreviewFrame.minY
            }
            guard observedNoteShift * dragDistance > 0,
                  observedHelperShift * dragDistance > 0,
                  savingAXTextPrimaryFramesAreValid,
                  savingAXTextCoMovementIsValid,
                  savingAXTextObservedOrderingIsValid else {
                XCTFail("Record-work saving positioning gesture was not recognized.")
                return
            }
            if workEditingAXTextEnabled {
                provenSavingGestureCount += 1
            }
        }
        let savingFinalApplicationFrame = app.frame
        let savingFinalNavigationFrame = workNavigationBar.frame
        let savingFinalScrollRawFrame = workScrollView.frame
        let savingFinalNoteFrame = workNoteHeading.frame
        let savingFinalHelperFrame = workHelper.frame
        var savingFinalButtonFrame = CGRect.null
        var savingFinalPhotoFrame = CGRect.null
        if workEditingAXTextEnabled {
            savingFinalButtonFrame = workImportFixtureButton?.frame ?? .null
            savingFinalPhotoFrame = workPreviewImage.frame
        }
        let savingFinalOrdinaryCommonFramesAreValid =
            !savingFinalApplicationFrame.isNull
                && !savingFinalApplicationFrame.isEmpty
                && !savingFinalNavigationFrame.isNull
                && !savingFinalNavigationFrame.isEmpty
                && !savingFinalScrollRawFrame.isNull
                && !savingFinalScrollRawFrame.isEmpty
                && !savingFinalNoteFrame.isNull
                && !savingFinalNoteFrame.isEmpty
                && !savingFinalHelperFrame.isNull
                && !savingFinalHelperFrame.isEmpty
        let savingFinalAXTextCommonFramesAreValid =
            workEditingFrameIsValid(savingFinalApplicationFrame)
                && workEditingFrameIsValid(savingFinalNavigationFrame)
                && workEditingFrameIsValid(savingFinalScrollRawFrame)
                && workEditingFrameIsValid(savingFinalNoteFrame)
                && workEditingFrameIsValid(savingFinalHelperFrame)
        let savingFinalCommonFramesAreValid = workEditingAXTextEnabled
            ? savingFinalAXTextCommonFramesAreValid
            : savingFinalOrdinaryCommonFramesAreValid
        let savingFinalAXTextFramesAreValid =
            !workEditingAXTextEnabled
                || (workEditingFrameIsValid(savingFinalButtonFrame)
                    && workEditingFrameIsValid(savingFinalPhotoFrame))
        guard savingFinalCommonFramesAreValid,
              savingFinalAXTextFramesAreValid else {
            XCTFail("Record-work saving composition is outside the safe viewport.")
            return
        }
        let savingFinalScrollFrame = savingFinalScrollRawFrame.intersection(
            savingFinalApplicationFrame
        )
        let savingFinalScrollFrameIsValid = workEditingAXTextEnabled
            ? workEditingFrameIsValid(savingFinalScrollFrame)
            : (!savingFinalScrollFrame.isNull && !savingFinalScrollFrame.isEmpty)
        guard savingFinalScrollFrameIsValid else {
            XCTFail("Record-work saving composition is outside the safe viewport.")
            return
        }
        let savingFinalSafeTop = max(
            savingFinalScrollFrame.minY,
            savingFinalNavigationFrame.maxY
        ) + verticalInset
        let savingFinalLiveBottom = savingFinalScrollFrame.maxY
        let savingFinalSafeBottom = savingFinalLiveBottom - verticalInset
        let workSavingOrdinaryCompositionAccepted =
            !workEditingAXTextEnabled
                && savingFinalNoteFrame.minY >= savingFinalSafeTop
                && savingFinalNoteFrame.maxY <= savingFinalSafeBottom
                && savingFinalHelperFrame.minY >= savingFinalSafeTop
                && savingFinalHelperFrame.maxY <= savingFinalSafeBottom
                && workNoteHeading.isHittable
                && workHelper.isHittable
                && workPreview.isHittable
        let workSavingAXTextAlternateCompositionAccepted =
            workEditingAXTextEnabled
                && workImportFixtureButtons?.count == 1
                && workImportFixtureButton?.exists == true
                && workImportFixtureButton?.elementType == .button
                && workImportFixtureButton?.identifier
                    == "s5.1.work.import-fixture"
                && workImportFixtureButton?.label == observedWorkHelperLabel
                && (workImportFixtureButton?.value as? String) == ""
                && workImportFixtureButton?.isEnabled == false
                && workImportFixtureButton?.isHittable == true
                && workEditingAXTextFallbackAccepted
                && savingInitialAXTextCompositionIsValid
                && provenSavingGestureCount >= 1
                && provenSavingGestureCount <= 4
                && savingAXTextGestureDirection != nil
                && workEditingComposition()
                && savingFinalNoteFrame.maxY <= savingFinalSafeTop
                && savingFinalHelperFrame.maxY <= savingFinalSafeTop
                && savingFinalButtonFrame.minY >= savingFinalSafeTop
                && savingFinalButtonFrame.maxY <= savingFinalSafeBottom
                && savingFinalNoteFrame.maxY < savingFinalHelperFrame.minY
                && savingFinalHelperFrame.maxY < savingFinalButtonFrame.minY
                && savingFinalButtonFrame.maxY < savingFinalPhotoFrame.minY
        guard app.state == .runningForeground,
              workNoteHeadings.count == 1,
              workTabBars.count == expectedWorkSavingTabBarCount,
              workSavingHelperTextBindingsAreValid(),
              workScrollViews.count == 1,
              workNavigationBars.count == 1,
              (!workEditingAXTextEnabled
                || workImportFixtureButtons?.count == 1),
              (!workEditingAXTextEnabled
                || workPreviewImages.count == 1),
              workNoteHeading.exists,
              workNoteHeading.identifier.isEmpty,
              workNoteHeading.label == "Note",
              workNoteHeading.elementType == .staticText,
              workHelper.exists,
              workScrollView.exists,
              workNavigationBar.exists,
              workPreview.exists,
              progress.exists,
              savingFinalSafeBottom > savingFinalSafeTop,
              (workSavingOrdinaryCompositionAccepted
                || workSavingAXTextAlternateCompositionAccepted) else {
            XCTFail("Record-work saving composition is outside the safe viewport.")
            return
        }
        }
        captureBaseline("state.work.saving", in: app)

        let issueScreen = element("s5.1.issue.screen", in: app)
        XCTAssertTrue(issueScreen.waitForExistence(timeout: 85))
        let dueStatus = element("s5.1.issue.status", in: app)
        XCTAssertTrue(dueStatus.waitForExistence(timeout: 10))
        assertLocalizedLabel(dueStatus, equals: "Attention: Recheck due")
        if automationShard?.shardID == "s10.4.current.ax-text",
           shouldPrepareNormalEvidence(
               for: "state.issue.recheck-due",
               in: app
           ) {
            guard positionIssueRecheckDueDescriptionForAXText(in: app) else {
                throw AutomationConfigurationError.invalid(
                    "S10.4 AX-text issue recheck-due positioning failed"
                )
            }
        }
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
        if automationShard?.shardID == "s10.4.current.ax-text",
           shouldPrepareNormalEvidence(
               for: "state.recheck-preflight.ready",
               in: app
           ) {
            guard positionRecheckPreflightContrastTargetsForAXText(in: app) else {
                throw AutomationConfigurationError.invalid(
                    "S10.4 AX-text recheck-preflight positioning failed"
                )
            }
        }
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
    ) throws {
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
        try performAlternativeRecheck(.couldNotVerify, in: app)
        try performAlternativeRecheck(.issueStillVisible, in: app)
        recordWorkWithoutBaseline(in: app)
        app.terminate()
        app.launchArguments.append("--s4-2-ui-test-render-failure-once")
        app.launch()
        XCTAssertTrue(element("s2.sign-detail.screen", in: app)
            .waitForExistence(timeout: 30))
        try performAlternativeRecheck(
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
        let usedSettingsRetry = captureAvailablePaywallAndPurchase(in: app)

        let close = element("s7.2.paywall.close", in: app)
        scrollDown(close, in: app)
        assertControl(close, label: "Close")
        close.tap()
        if usedSettingsRetry {
            XCTAssertTrue(element("s1.settings.screen", in: app)
                .waitForExistence(timeout: 20))
            navigateBack(in: app)
        }
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
        dismissMultilineKeyboard(
            afterEditing: description,
            on: element("s5.1.work.screen", in: app),
            in: app
        )
        let save = element("s5.1.work.save", in: app)
        scroll(save, in: app)
        assertControl(save, label: "Record work")
        save.tap()
        XCTAssertTrue(element("s5.1.issue.screen", in: app)
            .waitForExistence(timeout: 55))
        navigateBack(in: app)
        XCTAssertTrue(element("s2.sign-detail.screen", in: app)
            .waitForExistence(timeout: 20))
    }

    @MainActor
    private func purchaseSubscriptionWithoutBaseline(
        in app: XCUIApplication
    ) throws {
        let settings = element("s1.settings.button", in: app)
        assertControl(settings, label: "Settings")
        settings.tap()
        guard element("s1.settings.screen", in: app)
            .waitForExistence(timeout: 20) else {
            throw AutomationConfigurationError.invalid(
                "Segment-3 resume could not open Settings for purchase setup"
            )
        }
        let paywall = element("s7.2.settings.paywall", in: app)
        scroll(paywall, in: app)
        assertControl(paywall, label: "View subscription")
        paywall.tap()
        guard element("s7.2.paywall.screen", in: app)
            .waitForExistence(timeout: 30) else {
            throw AutomationConfigurationError.invalid(
                "Segment-3 resume could not open the purchase route"
            )
        }
        _ = captureAvailablePaywallAndPurchase(
            emitsEvidence: false,
            in: app
        )
        let purchaseState = element("s7.2.paywall.purchase-state", in: app)
        guard purchaseState.exists,
              purchaseState.label.contains(
                "Purchase verified. Subscription access is ready."
              ) else {
            throw AutomationConfigurationError.invalid(
                "Segment-3 resume did not verify the purchase prerequisite"
            )
        }
        let close = element("s7.2.paywall.close", in: app)
        scrollDown(close, in: app)
        assertControl(close, label: "Close")
        close.tap()
        guard element("s1.settings.screen", in: app)
            .waitForExistence(timeout: 20) else {
            throw AutomationConfigurationError.invalid(
                "Segment-3 resume did not return to Settings after purchase"
            )
        }
        navigateBack(in: app)
        guard element("s2.sign-detail.screen", in: app)
            .waitForExistence(timeout: 20) else {
            throw AutomationConfigurationError.invalid(
                "Segment-3 resume did not return to Sign detail after purchase"
            )
        }
    }

    @MainActor
    private func prepareSegment3ResumeAtReportFailureIfNeeded(
        in app: XCUIApplication
    ) throws -> Bool {
        guard automationSegment == .segment3 else { return false }
        guard let shard = automationShard,
              shard.shardID == "s10.4.current.ax-text",
              Self.segmentedRouteStateIDs.count == 67,
              Set(Self.segmentedRouteStateIDs).count == 67,
              automationSegment.replayCount == 22,
              automationSegment.ownedStartOrdinal == 51,
              automationSegment.ownedCount == 17,
              automationSegment.finalOrdinal == 67,
              segmentedRouteStateCursor == 22,
              migratedStateIDs.isEmpty,
              automationAXTreeDigests.isEmpty,
              automationContrastExceptions.isEmpty,
              !automatedSegmentFinished,
              app.state == .runningForeground,
              app.descendants(matching: .any)
                .matching(identifier: "s2.sign-detail.screen").count == 1,
              app.descendants(matching: .any)
                .matching(identifier: "s5.1.sign-detail.record-work").count == 1,
              !app.launchArguments.contains(
                "--s4-2-ui-test-render-failure-once"
              ) else {
            throw AutomationConfigurationError.invalid(
                "Segment-3 resume did not begin at the exact state-22 boundary"
            )
        }

        recordWorkWithoutBaseline(in: app)
        guard segmentedRouteStateCursor == 22,
              migratedStateIDs.isEmpty,
              app.state == .runningForeground,
              app.descendants(matching: .any)
                .matching(identifier: "s2.sign-detail.screen").count == 1,
              app.descendants(matching: .any)
                .matching(identifier: "s5.1.sign-detail.recheck-due").count == 1 else {
            throw AutomationConfigurationError.invalid(
                "Segment-3 resume did not create the recheck-due prerequisite"
            )
        }

        try purchaseSubscriptionWithoutBaseline(in: app)
        guard segmentedRouteStateCursor == 22,
              migratedStateIDs.isEmpty,
              app.state == .runningForeground,
              app.descendants(matching: .any)
                .matching(identifier: "s2.sign-detail.screen").count == 1,
              app.descendants(matching: .any)
                .matching(identifier: "s5.1.sign-detail.recheck-due").count == 1 else {
            throw AutomationConfigurationError.invalid(
                "Segment-3 resume purchase changed the recheck-due route"
            )
        }

        app.terminate()
        app.launchArguments.append("--s4-2-ui-test-render-failure-once")
        guard app.launchArguments.filter({
            $0 == "--s4-2-ui-test-render-failure-once"
        }).count == 1 else {
            throw AutomationConfigurationError.invalid(
                "Segment-3 resume render-failure argument is not unique"
            )
        }
        app.launch()
        guard element("s2.sign-detail.screen", in: app)
            .waitForExistence(timeout: 30),
              app.state == .runningForeground,
              segmentedRouteStateCursor == 22 else {
            throw AutomationConfigurationError.invalid(
                "Segment-3 resume did not relaunch the recheck-due route"
            )
        }
        let pendingDifferentIssueReceiptVerified = try performAlternativeRecheck(
            .differentIssue,
            leavesPendingReceipt: true,
            emitsEvidence: false,
            in: app
        )

        let signDetailScreens = app.descendants(matching: .any)
            .matching(identifier: "s2.sign-detail.screen")
        let resolvedIssueActions = app.descendants(matching: .any)
            .matching(identifier: "s5.2.sign-detail.resolved")
        let recheckDueActions = app.descendants(matching: .any)
            .matching(identifier: "s5.1.sign-detail.recheck-due")
        guard segmentedRouteStateCursor == 22,
              migratedStateIDs.isEmpty,
              automationAXTreeDigests.isEmpty,
              automationContrastExceptions.isEmpty,
              pendingDifferentIssueReceiptVerified,
              app.state == .runningForeground,
              signDetailScreens.count == 1,
              signDetailScreens.firstMatch.exists,
              signDetailScreens.firstMatch.elementType == .scrollView,
              signDetailScreens.firstMatch.identifier == "s2.sign-detail.screen",
              resolvedIssueActions.count == 1,
              resolvedIssueActions.firstMatch.exists,
              resolvedIssueActions.firstMatch.isEnabled,
              resolvedIssueActions.firstMatch.label == "Resolved",
              recheckDueActions.count == 0 else {
            throw AutomationConfigurationError.invalid(
                "Segment-3 resume did not prove the pending different-issue receipt route"
            )
        }

        let resumedStateIDs = Array(Self.segmentedRouteStateIDs[22..<50])
        let dependencyStateIDs = Array(Self.segmentedRouteStateIDs.prefix(50))
        let dependencyOwnedStateSHA256 = SHA256.hash(
            data: Data(dependencyStateIDs.joined(separator: "\n").utf8)
        ).map { String(format: "%02X", $0) }.joined()
        guard resumedStateIDs.count == 28,
              Set(resumedStateIDs).count == 28,
              resumedStateIDs.first == "state.work.validation-error",
              resumedStateIDs.last == "state.issue.different-open",
              dependencyStateIDs.count == 50,
              Set(dependencyStateIDs).count == 50,
              dependencyOwnedStateSHA256
                == "80397ABF11A3622661E301900B7A23D0398FBF292CEEE29E1E9FA1E7A8EDA0A4" else {
            throw AutomationConfigurationError.invalid(
                "Segment-3 resume state closure differs from the frozen inventory"
            )
        }
        app.terminate()
        app.launch()
        let failureScreens = app.descendants(matching: .any)
            .matching(identifier: "s4.pdf-failure.screen")
        let failureHeadlines = app.descendants(matching: .any)
            .matching(identifier: "s4.pdf-failure.headline")
        let failureRetries = app.descendants(matching: .any)
            .matching(identifier: "s4.pdf-failure.retry")
        guard failureScreens.firstMatch.waitForExistence(timeout: 30),
              failureScreens.count == 1,
              failureScreens.firstMatch.identifier == "s4.pdf-failure.screen",
              failureHeadlines.count == 1,
              failureHeadlines.firstMatch.exists,
              failureHeadlines.firstMatch.label
                == "This report was saved, but its PDF is not available.",
              failureRetries.count == 1,
              failureRetries.firstMatch.exists,
              failureRetries.firstMatch.isEnabled,
              failureRetries.firstMatch.label == "Retry report",
              segmentedRouteStateCursor == 22,
              migratedStateIDs.isEmpty,
              app.launchArguments.filter({
                $0 == "--s4-2-ui-test-render-failure-once"
              }).count == 1,
              app.state == .runningForeground else {
            throw AutomationConfigurationError.invalid(
                "Segment-3 resume did not reach the report-failure route"
            )
        }
        printJSONLine(prefix: "S10_4_SEGMENT_RESUME_SETUP", object: [
            "schemaVersion": 1,
            "acceptanceEligible": false,
            "shardID": shard.shardID,
            "segmentID": automationSegment.rawValue,
            "setupID": "segment-3-report-pdf-failed-v1",
            "sourceOrdinal": 22,
            "sourceStateID": "state.sign-detail.open-issue",
            "skippedStartOrdinal": 23,
            "skippedEndOrdinal": 50,
            "targetOrdinal": 51,
            "targetStateID": "state.report-pdf.failed",
            "cursorBeforeResume": segmentedRouteStateCursor,
            "cursorAfterResume": 50,
            "localReplayCount": automationSegment.replayCount,
            "dependencyOwnedStateSHA256": dependencyOwnedStateSHA256,
            "applicationForeground": true,
            "purchaseVerified": true,
            "pendingDifferentIssueReceiptVerified": true,
            "reportFailureRouteVerified": true,
            "renderFailureArgumentCount": 1,
        ])
        segmentedRouteStateCursor = 50
        guard segmentedRouteStateCursor
                == automationSegment.ownedStartOrdinal - 1 else {
            throw AutomationConfigurationError.invalid(
                "Segment-3 resume cursor did not reach the state-51 frontier"
            )
        }
        return true
    }

    @MainActor
    @discardableResult
    private func performAlternativeRecheck(
        _ outcome: AlternativeRecheckOutcome,
        leavesPendingReceipt: Bool = false,
        emitsEvidence: Bool = true,
        in app: XCUIApplication
    ) throws -> Bool {
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
                if emitsEvidence && shouldPrepareNormalEvidence(
                    for: "state.recheck-outcome.different-issue",
                    in: app
                ) {
                let navigationBottom = app.navigationBars.firstMatch.frame.maxY
                let outcomeScreen = element("s3.outcome.screen", in: app)
                let viewportBottom = outcomeScreen.frame.maxY
                let resolved = element("s5.2.outcome.resolved", in: app)
                let issueStillVisible = element(
                    "s5.2.outcome.issue-still-visible",
                    in: app
                )
                let outcomeScreenQuery = app.descendants(matching: .any).matching(
                    identifier: "s3.outcome.screen"
                )
                let resolvedQuery = app.descendants(matching: .any).matching(
                    identifier: "s5.2.outcome.resolved"
                )
                let issueStillVisibleQuery = app.descendants(matching: .any).matching(
                    identifier: "s5.2.outcome.issue-still-visible"
                )
                let originalResolvedDifferentIssueQuery = app.descendants(
                    matching: .any
                ).matching(
                    identifier: "s5.3.outcome.original-resolved-different-issue"
                )
                let physicalDamageQuery = app.descendants(matching: .any).matching(
                    identifier: "s3.outcome.issue.physical_damage"
                )
                let expectedSegment2MigratedStateIDs = Array(
                    Self.segmentedRouteStateIDs[22..<47]
                )
                let expectedSegment2ContrastExceptionStateIDs = [
                    "state.issue.open",
                    "state.issue.recheck-due",
                    "state.issue.resolved",
                    "state.paywall.purchase-complete",
                    "state.recheck-capture.wide-ready",
                    "state.recheck-preflight.ready",
                ]
                let expectedFullShardMigratedStateIDs = Array(
                    Self.segmentedRouteStateIDs.prefix(47)
                )
                let expectedFullShardContrastExceptionStateIDs = [
                    "state.check-preflight.ready",
                    "state.issue.open",
                    "state.issue.recheck-due",
                    "state.issue.resolved",
                    "state.new-sign.editing",
                    "state.paywall.purchase-complete",
                    "state.recheck-capture.wide-ready",
                    "state.recheck-preflight.ready",
                    "state.report-history.ready",
                    "state.reports-index.ready",
                ]
                let acceptsAXTextLowerSelectionComposition: () -> Bool = {
                    let screenFrameQuantizationAllowance: CGFloat = 0.001
                    let frames = [
                        app.frame,
                        outcomeScreen.frame,
                        app.navigationBars.firstMatch.frame,
                        resolved.frame,
                        issueStillVisible.frame,
                        value.frame,
                        label.frame,
                    ]
                    let allFrameTermsFinite = frames.allSatisfy { frame in
                        [
                            frame.minX,
                            frame.minY,
                            frame.maxX,
                            frame.maxY,
                            frame.width,
                            frame.height,
                        ].allSatisfy(\.isFinite)
                    }
                    let hasExpectedSegment2Provenance =
                        self.automationSegment == .segment2
                        && self.automationSegment.replayCount == 22
                        && self.automationSegment.ownedStartOrdinal == 23
                        && self.automationSegment.ownedCount == 28
                        && self.automationSegment.finalOrdinal == 50
                        && self.segmentedRouteStateCursor == 47
                        && self.migratedStateIDs
                            == expectedSegment2MigratedStateIDs
                        && self.automationAXTreeDigests.keys.sorted()
                            == expectedSegment2MigratedStateIDs.sorted()
                        && self.automationContrastExceptions.keys.sorted()
                            == expectedSegment2ContrastExceptionStateIDs
                    let hasExpectedFullShardProvenance =
                        self.automationSegment == .none
                        && self.segmentedRouteStateCursor == 0
                        && self.migratedStateIDs
                            == expectedFullShardMigratedStateIDs
                        && self.automationAXTreeDigests.keys.sorted()
                            == expectedFullShardMigratedStateIDs.sorted()
                        && self.automationContrastExceptions.keys.sorted()
                            == expectedFullShardContrastExceptionStateIDs
                    return self.automationShard?.shardID == "s10.4.current.ax-text"
                        && (hasExpectedSegment2Provenance
                            || hasExpectedFullShardProvenance)
                        && Self.segmentedRouteStateIDs.count == 67
                        && Set(Self.segmentedRouteStateIDs).count == 67
                        && Self.segmentedRouteStateIDs[47]
                            == "state.recheck-outcome.different-issue"
                        && !self.automatedSegmentFinished
                        && app.state == .runningForeground
                        && outcomeScreenQuery.count == 1
                        && resolvedQuery.count == 1
                        && issueStillVisibleQuery.count == 1
                        && originalResolvedDifferentIssueQuery.count == 1
                        && physicalDamageQuery.count == 1
                        && app.navigationBars.count == 1
                        && app.tabBars.count == 0
                        && app.keyboards.count == 0
                        && app.otherElements.matching(
                            NSPredicate(format: "identifier == %@", "inputView")
                        ).count == 0
                        && outcomeScreen.exists
                        && outcomeScreen.isEnabled
                        && outcomeScreen.isHittable
                        && outcomeScreen.identifier == "s3.outcome.screen"
                        && outcomeScreen.elementType == .scrollView
                        && outcomeScreen.frame.insetBy(
                            dx: -screenFrameQuantizationAllowance,
                            dy: -screenFrameQuantizationAllowance
                        ).contains(app.frame)
                        && app.frame.insetBy(
                            dx: -screenFrameQuantizationAllowance,
                            dy: -screenFrameQuantizationAllowance
                        ).contains(outcomeScreen.frame)
                        && app.navigationBars.firstMatch.exists
                        && app.navigationBars.firstMatch.isEnabled
                        && app.navigationBars.firstMatch.isHittable
                        && app.navigationBars.firstMatch.identifier == "Outcome"
                        && app.navigationBars.firstMatch.elementType == .navigationBar
                        && resolved.exists
                        && resolved.isEnabled
                        && !resolved.isHittable
                        && resolved.identifier == "s5.2.outcome.resolved"
                        && resolved.label == "Resolved"
                        && resolved.value as? String == "Not selected"
                        && resolved.elementType == .button
                        && issueStillVisible.exists
                        && issueStillVisible.isEnabled
                        && !issueStillVisible.isHittable
                        && issueStillVisible.identifier
                            == "s5.2.outcome.issue-still-visible"
                        && issueStillVisible.label == "Issue still visible"
                        && issueStillVisible.value as? String == "Not selected"
                        && issueStillVisible.elementType == .button
                        && value.exists
                        && value.isEnabled
                        && !value.isHittable
                        && value.identifier
                            == "s5.3.outcome.original-resolved-different-issue"
                        && value.label
                            == "Original resolved, different visible issue"
                        && value.value as? String == "Selected"
                        && value.elementType == .button
                        && label.exists
                        && label.isEnabled
                        && label.isHittable
                        && label.identifier == "s3.outcome.issue.physical_damage"
                        && label.label == "Visible physical damage"
                        && label.value as? String == "Selected"
                        && label.elementType == .button
                        && resolved.frame.maxY <= navigationBottom
                        && issueStillVisible.frame.maxY <= navigationBottom
                        && value.frame.maxY <= navigationBottom
                        && label.frame.minY >= navigationBottom
                        && label.frame.maxY <= viewportBottom
                        && resolved.frame.maxY <= issueStillVisible.frame.minY
                        && issueStillVisible.frame.maxY <= value.frame.minY
                        && value.frame.maxY <= label.frame.minY
                        && allFrameTermsFinite
                }
                let usesAXTextLowerSelectionComposition =
                    acceptsAXTextLowerSelectionComposition()
                if !usesAXTextLowerSelectionComposition {
                    for attemptIndex in 0..<6 {
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
                        if minimumShift > maximumShift,
                           emitsEvidence,
                           automationSegment == .segment2,
                           automationShard?.shardID == "s10.4.current.ax-text" {
                            return try diagnoseSegment2AXTextRecheckOutcomeDifferentIssueInterval(
                                in: app,
                                attemptOrdinal: attemptIndex + 1,
                                outcomeScreen: outcomeScreen,
                                resolved: resolved,
                                issueStillVisible: issueStillVisible,
                                originalResolvedDifferentIssue: value,
                                physicalDamage: label,
                                navigationBottom: navigationBottom,
                                viewportBottom: viewportBottom,
                                minimumShift: minimumShift,
                                maximumShift: maximumShift
                            )
                        }
                        XCTAssertLessThanOrEqual(minimumShift, maximumShift)
                        let dragDistance = minimumShift > 0
                            ? maximumShift
                            : minimumShift
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
                }
                if usesAXTextLowerSelectionComposition {
                    XCTAssertTrue(acceptsAXTextLowerSelectionComposition())
                } else {
                    XCTAssertLessThanOrEqual(resolved.frame.maxY, navigationBottom)
                    XCTAssertGreaterThanOrEqual(
                        issueStillVisible.frame.minY,
                        navigationBottom
                    )
                    XCTAssertGreaterThanOrEqual(value.frame.minY, navigationBottom)
                    XCTAssertLessThanOrEqual(label.frame.maxY, viewportBottom)
                    XCTAssertTrue(value.isHittable)
                    XCTAssertTrue(label.isHittable)
                }
                }
                if emitsEvidence {
                    captureBaseline("state.recheck-outcome.different-issue", in: app)
                }
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
            if emitsEvidence {
                captureBaseline("state.recheck-review.different-issue", in: app)
            }
        }
        let save = element("s3.review.save-report", in: app)
        scroll(save, in: app)
        assertControl(save, label: "Save and finish")
        save.tap()
        XCTAssertTrue(element("s3.receipt.screen", in: app)
            .waitForExistence(timeout: 40))
        if leavesPendingReceipt {
            let savedValues = app.descendants(matching: .any)
                .matching(identifier: "s3.receipt.saved")
            let preparingValues = app.descendants(matching: .any)
                .matching(identifier: "s4.3.receipt.preparing")
            let viewReportValues = app.descendants(matching: .any)
                .matching(identifier: "s3.receipt.view-report")
            let saved = savedValues.firstMatch
            guard saved.waitForExistence(timeout: 15),
                  savedValues.count == 1,
                  preparingValues.firstMatch.waitForExistence(timeout: 10),
                  preparingValues.count == 1,
                  viewReportValues.count == 0 else {
                XCTFail(
                    "The pending different-issue receipt prerequisite is ambiguous"
                )
                return false
            }
            assertLocalizedLabel(saved, equals: "Report saved on this device.")
            let done = element("s3.receipt.done", in: app)
            scroll(done, in: app)
            assertControl(done, label: "Done")
            done.tap()
            XCTAssertTrue(element("s5.1.issue.screen", in: app)
                .waitForExistence(timeout: 25))
            navigateBack(in: app)
            XCTAssertTrue(element("s2.sign-detail.screen", in: app)
                .waitForExistence(timeout: 25))
            return true
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
        return false
    }

    @MainActor
    private func diagnoseSegment2AXTextRecheckOutcomeDifferentIssueInterval(
        in app: XCUIApplication,
        attemptOrdinal: Int,
        outcomeScreen: XCUIElement,
        resolved: XCUIElement,
        issueStillVisible: XCUIElement,
        originalResolvedDifferentIssue: XCUIElement,
        physicalDamage: XCUIElement,
        navigationBottom: CGFloat,
        viewportBottom: CGFloat,
        minimumShift: CGFloat,
        maximumShift: CGFloat
    ) throws -> Bool {
        let stateID = "state.recheck-outcome.different-issue"
        let expectedMigratedStateIDs = Array(
            Self.segmentedRouteStateIDs[22..<47]
        )
        let expectedContrastExceptionStateIDs = [
            "state.issue.open",
            "state.issue.recheck-due",
            "state.issue.resolved",
            "state.paywall.purchase-complete",
            "state.recheck-capture.wide-ready",
            "state.recheck-preflight.ready",
        ]
        let issueStillVisibleTopShift =
            navigationBottom - issueStillVisible.frame.minY
        let originalResolvedDifferentIssueTopShift =
            navigationBottom - originalResolvedDifferentIssue.frame.minY
        let resolvedAboveNavigationShift =
            navigationBottom - resolved.frame.maxY
        let physicalDamageBottomShift =
            viewportBottom - physicalDamage.frame.maxY
        let derivedMinimumShift = max(
            issueStillVisibleTopShift,
            originalResolvedDifferentIssueTopShift
        )
        let derivedMaximumShift = min(
            resolvedAboveNavigationShift,
            physicalDamageBottomShift
        )
        guard let shard = automationShard,
              shard.shardID == "s10.4.current.ax-text",
              automationSegment == .segment2,
              automationSegment.replayCount == 22,
              automationSegment.ownedStartOrdinal == 23,
              automationSegment.ownedCount == 28,
              automationSegment.finalOrdinal == 50,
              Self.segmentedRouteStateIDs.count == 67,
              Set(Self.segmentedRouteStateIDs).count == 67,
              Self.segmentedRouteStateIDs[47] == stateID,
              segmentedRouteStateCursor == 47,
              migratedStateIDs == expectedMigratedStateIDs,
              automationAXTreeDigests.keys.sorted()
                == expectedMigratedStateIDs.sorted(),
              automationContrastExceptions.keys.sorted()
                == expectedContrastExceptionStateIDs,
              !automatedSegmentFinished,
              app.state == .runningForeground,
              minimumShift == derivedMinimumShift,
              maximumShift == derivedMaximumShift,
              minimumShift > maximumShift else {
            throw AutomationConfigurationError.invalid(
                "S10.4 AX-text recheck-outcome different-issue interval diagnostic gate is invalid"
            )
        }

        let diagnosticQueryBindings: [(
            name: String,
            query: XCUIElementQuery
        )] = [
            (
                "outcomeScreens",
                app.descendants(matching: .any).matching(
                    identifier: "s3.outcome.screen"
                )
            ),
            (
                "outcomeScrollViews",
                app.scrollViews.matching(identifier: "s3.outcome.screen")
            ),
            (
                "resolvedControls",
                app.descendants(matching: .any).matching(
                    identifier: "s5.2.outcome.resolved"
                )
            ),
            (
                "issueStillVisibleControls",
                app.descendants(matching: .any).matching(
                    identifier: "s5.2.outcome.issue-still-visible"
                )
            ),
            (
                "originalResolvedDifferentIssueControls",
                app.descendants(matching: .any).matching(
                    identifier: "s5.3.outcome.original-resolved-different-issue"
                )
            ),
            (
                "physicalDamageControls",
                app.descendants(matching: .any).matching(
                    identifier: "s3.outcome.issue.physical_damage"
                )
            ),
            ("navigationBars", app.navigationBars),
            ("tabBars", app.tabBars),
            ("keyboards", app.keyboards),
            (
                "inputViews",
                app.otherElements.matching(
                    NSPredicate(format: "identifier == %@", "inputView")
                )
            ),
        ]
        let diagnosticElementObject: (XCUIElement) -> [String: Any] = {
            element in
            [
                "exists": element.exists,
                "isEnabled": element.isEnabled,
                "isHittable": element.isHittable,
                "identifier": element.identifier,
                "label": element.label,
                "value": (element.value as? String).map { $0 as Any }
                    ?? NSNull(),
                "elementTypeRawValue": element.elementType.rawValue,
                "elementTypeDescription": String(describing: element.elementType),
                "frame": self.auditFrameObject(element.frame),
            ]
        }
        let diagnosticQueryObject: (XCUIElementQuery) -> [String: Any] = {
            query in
            let count = query.count
            return [
                "count": count,
                "elements": (0..<count).map { index in
                    diagnosticElementObject(query.element(boundBy: index))
                },
            ]
        }
        var diagnosticQueryObjects: [String: Any] = [:]
        for binding in diagnosticQueryBindings {
            diagnosticQueryObjects[binding.name] = diagnosticQueryObject(binding.query)
        }
        let intervalTerms: [String: Any] = [
            "navigationBottom": Double(navigationBottom),
            "viewportBottom": Double(viewportBottom),
            "issueStillVisibleTopShift": Double(issueStillVisibleTopShift),
            "originalResolvedDifferentIssueTopShift": Double(
                originalResolvedDifferentIssueTopShift
            ),
            "resolvedAboveNavigationShift": Double(resolvedAboveNavigationShift),
            "physicalDamageBottomShift": Double(physicalDamageBottomShift),
            "minimumShift": Double(minimumShift),
            "maximumShift": Double(maximumShift),
            "intervalWidth": Double(maximumShift - minimumShift),
        ]
        let intervalRelations: [String: Bool] = [
            "allTermsFinite": [
                navigationBottom,
                viewportBottom,
                issueStillVisibleTopShift,
                originalResolvedDifferentIssueTopShift,
                resolvedAboveNavigationShift,
                physicalDamageBottomShift,
                minimumShift,
                maximumShift,
            ].allSatisfy(\.isFinite),
            "minimumMatchesMaximumTopRequirement":
                minimumShift == max(
                    issueStillVisibleTopShift,
                    originalResolvedDifferentIssueTopShift
                ),
            "maximumMatchesMinimumBottomAllowance":
                maximumShift == min(
                    resolvedAboveNavigationShift,
                    physicalDamageBottomShift
                ),
            "minimumShiftAtMostMaximumShift": minimumShift <= maximumShift,
        ]
        let diagnosticContext: [String: Any] = [
            "schemaVersion": 1,
            "acceptanceEligible": false,
            "shardID": shard.shardID,
            "requirementID": shard.requirementID,
            "deviceProfileID": shard.deviceProfileID,
            "segmentID": automationSegment.rawValue,
            "segmentReplayCount": automationSegment.replayCount,
            "segmentOwnedStartOrdinal": automationSegment.ownedStartOrdinal,
            "segmentOwnedCount": automationSegment.ownedCount,
            "segmentFinalOrdinal": automationSegment.finalOrdinal,
            "segmentStateCursor": segmentedRouteStateCursor,
            "stateID": stateID,
            "stateOrdinal": 48,
            "predecessorStateID": "state.issue.open",
            "predecessorOrdinal": 47,
            "successorStateID": "state.recheck-review.different-issue",
            "successorOrdinal": 49,
            "attemptOrdinal": attemptOrdinal,
            "migratedStateIDs": migratedStateIDs,
            "axTreeDigestStateIDs": automationAXTreeDigests.keys.sorted(),
            "contrastExceptionStateIDs": automationContrastExceptions.keys.sorted(),
            "applicationState": String(describing: app.state),
            "applicationStateRawValue": app.state.rawValue,
            "applicationForeground": app.state == .runningForeground,
            "applicationFrame": auditFrameObject(app.frame),
            "application": diagnosticElementObject(app),
            "intervalTerms": intervalTerms,
            "intervalRelations": intervalRelations,
            "queries": diagnosticQueryObjects,
            "routeElements": [
                "outcomeScreen": diagnosticElementObject(outcomeScreen),
                "resolved": diagnosticElementObject(resolved),
                "issueStillVisible": diagnosticElementObject(issueStillVisible),
                "originalResolvedDifferentIssue": diagnosticElementObject(
                    originalResolvedDifferentIssue
                ),
                "physicalDamage": diagnosticElementObject(physicalDamage),
            ],
        ]
        printJSONLine(
            prefix:
                "S10_4_AX_TEXT_RECHECK_OUTCOME_DIFFERENT_ISSUE_INTERVAL_CONTEXT_DIAGNOSTIC",
            object: diagnosticContext
        )

        let appAttachment = XCTAttachment(screenshot: app.screenshot())
        appAttachment.name =
            "S10.4 AX-text recheck-outcome different-issue interval diagnostic app"
        appAttachment.lifetime = .keepAlways
        add(appAttachment)
        let treeAttachment = XCTAttachment(string: app.debugDescription)
        treeAttachment.name =
            "S10.4 AX-text recheck-outcome different-issue interval diagnostic tree"
        treeAttachment.lifetime = .keepAlways
        add(treeAttachment)
        let contextData = try JSONSerialization.data(
            withJSONObject: diagnosticContext,
            options: [.prettyPrinted, .sortedKeys]
        )
        let contextAttachment = XCTAttachment(
            string: String(decoding: contextData, as: UTF8.self)
        )
        contextAttachment.name =
            "S10.4 AX-text recheck-outcome different-issue interval diagnostic context"
        contextAttachment.lifetime = .keepAlways
        add(contextAttachment)

        var observedIssueCount = 0
        var auditedElementCount = 0
        try app.performAccessibilityAudit(for: .contrast) { issue in
            observedIssueCount += 1
            let auditedElement = issue.element
            var diagnosticIssue: [String: Any] = [
                "schemaVersion": 1,
                "acceptanceEligible": false,
                "shardID": shard.shardID,
                "requirementID": shard.requirementID,
                "deviceProfileID": shard.deviceProfileID,
                "segmentID": self.automationSegment.rawValue,
                "segmentStateCursor": self.segmentedRouteStateCursor,
                "stateID": stateID,
                "stateOrdinal": 48,
                "issueOrdinal": observedIssueCount,
                "auditTypeRawValue": String(issue.auditType.rawValue),
                "compactDescription": issue.compactDescription,
                "detailedDescription": issue.detailedDescription,
                "elementExists": NSNull(),
                "elementEnabled": NSNull(),
                "elementHittable": NSNull(),
                "elementIdentifier": NSNull(),
                "elementLabel": NSNull(),
                "elementValue": NSNull(),
                "elementTypeRawValue": NSNull(),
                "elementTypeDescription": NSNull(),
                "elementFrame": NSNull(),
                "applicationFrame": self.auditFrameObject(app.frame),
            ]
            if let auditedElement {
                auditedElementCount += 1
                let auditedElementObject = diagnosticElementObject(auditedElement)
                diagnosticIssue["elementExists"] = auditedElementObject["exists"]
                diagnosticIssue["elementEnabled"] = auditedElementObject["isEnabled"]
                diagnosticIssue["elementHittable"] = auditedElementObject["isHittable"]
                diagnosticIssue["elementIdentifier"] = auditedElementObject["identifier"]
                diagnosticIssue["elementLabel"] = auditedElementObject["label"]
                diagnosticIssue["elementValue"] = auditedElementObject["value"]
                diagnosticIssue["elementTypeRawValue"] =
                    auditedElementObject["elementTypeRawValue"]
                diagnosticIssue["elementTypeDescription"] =
                    auditedElementObject["elementTypeDescription"]
                diagnosticIssue["elementFrame"] = auditedElementObject["frame"]
            }
            self.printJSONLine(
                prefix:
                    "S10_4_AX_TEXT_RECHECK_OUTCOME_DIFFERENT_ISSUE_INTERVAL_ISSUE_DIAGNOSTIC",
                object: diagnosticIssue
            )
            if let auditedElement {
                let issueAttachment = XCTAttachment(
                    screenshot: auditedElement.screenshot()
                )
                issueAttachment.name =
                    "S10.4 AX-text recheck-outcome different-issue interval diagnostic audited element "
                        + String(observedIssueCount)
                issueAttachment.lifetime = .keepAlways
                self.add(issueAttachment)
            }
            return true
        }
        printJSONLine(
            prefix:
                "S10_4_AX_TEXT_RECHECK_OUTCOME_DIFFERENT_ISSUE_INTERVAL_COUNT_DIAGNOSTIC",
            object: [
                "schemaVersion": 1,
                "acceptanceEligible": false,
                "shardID": shard.shardID,
                "segmentID": automationSegment.rawValue,
                "stateID": stateID,
                "stateOrdinal": 48,
                "segmentStateCursor": segmentedRouteStateCursor,
                "observedIssueCount": observedIssueCount,
                "auditedElementCount": auditedElementCount,
            ]
        )
        throw AutomationConfigurationError.invalid(
            "S10.4 AX-text recheck-outcome different-issue interval diagnostic completed nonaccepting"
        )
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
        if finishAutomatedSegmentIfNeeded(after: 50, in: app) { return }
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
        let note = element("s4.5.correction.note", in: app)
        guard note.waitForExistence(timeout: 10) else {
            XCTFail("Report correction note did not appear after validation.")
            return
        }
        guard wait(
            for: note,
            predicate: "hasKeyboardFocus == true",
            timeout: 10
        ) else {
            XCTFail("Report correction validation did not retain note focus.")
            return
        }
        let keyboard = app.keyboards.firstMatch
        let navigationBar = app.navigationBars.firstMatch
        guard keyboard.waitForExistence(timeout: 10),
              navigationBar.waitForExistence(timeout: 10) else {
            XCTFail("Report correction keyboard or navigation bar is missing.")
            return
        }
        let correctionScrollViews = app.scrollViews.containing(
            .button,
            identifier: "s4.5.correction.save"
        )
        guard correctionScrollViews.count == 1 else {
            XCTFail("Report correction must have one Save-containing ScrollView.")
            return
        }
        let correctionScrollView = correctionScrollViews.firstMatch
        guard correctionScrollView.waitForExistence(timeout: 10) else {
            XCTFail("Report correction Save-containing ScrollView is missing.")
            return
        }

        let currentProfileInputViews: XCUIElementQuery?
        let keyboardInputView: XCUIElement?
        if automationShard?.deviceProfileID == "iphone-17-ios-26.2-current" {
            let inputViews = app.otherElements.matching(
                NSPredicate(format: "identifier == %@", "inputView")
            )
            guard inputViews.count == 1 else {
                XCTFail("Report correction must have one current-profile input view.")
                return
            }
            let inputView = inputViews.firstMatch
            guard inputView.waitForExistence(timeout: 10) else {
                XCTFail("Report correction current-profile input view is missing.")
                return
            }
            currentProfileInputViews = inputViews
            keyboardInputView = inputView
        } else {
            currentProfileInputViews = nil
            keyboardInputView = nil
        }

        let dragInset: CGFloat = 24
        let minimumGestureDistance: CGFloat = 44
        for _ in 0..<4 {
            let scrollFrame = correctionScrollView.frame
            let visibleTop = max(scrollFrame.minY, navigationBar.frame.maxY)
            let keyboardFrame = keyboard.frame
            let visibleBottom: CGFloat
            if let inputViews = currentProfileInputViews,
               let inputView = keyboardInputView {
                guard inputViews.count == 1,
                      inputView.exists else {
                    XCTFail("Report correction current-profile input view changed.")
                    return
                }
                let inputViewFrame = inputView.frame
                guard inputViewFrame.minX <= keyboardFrame.minX,
                      inputViewFrame.maxX >= keyboardFrame.maxX,
                      inputViewFrame.minY <= keyboardFrame.minY,
                      inputViewFrame.maxY >= keyboardFrame.maxY else {
                    XCTFail("Report correction input view does not contain the keyboard.")
                    return
                }
                visibleBottom = min(
                    scrollFrame.maxY,
                    min(keyboardFrame.minY, inputViewFrame.minY)
                )
            } else {
                visibleBottom = min(scrollFrame.maxY, keyboardFrame.minY)
            }
            guard visibleBottom > visibleTop else {
                XCTFail("Report correction has no visible keyboard-safe interval.")
                return
            }

            let validationFrame = validation.frame
            let saveFrame = save.frame
            if validationFrame.minY >= visibleTop,
               validationFrame.maxY <= visibleBottom,
               saveFrame.minY >= visibleTop,
               saveFrame.maxY <= visibleBottom {
                break
            }

            let minimumShift = max(
                visibleTop - validationFrame.minY,
                visibleTop - saveFrame.minY
            )
            let maximumShift = min(
                visibleBottom - validationFrame.maxY,
                visibleBottom - saveFrame.maxY
            )
            guard minimumShift <= maximumShift else {
                XCTFail("Report correction validation and Save cannot share the viewport.")
                return
            }
            let farFeasibleShift = abs(minimumShift) >= abs(maximumShift)
                ? minimumShift
                : maximumShift
            let maximumGestureDistance = visibleBottom
                - visibleTop
                - (2 * dragInset)
            guard maximumGestureDistance >= minimumGestureDistance else {
                XCTFail("Report correction viewport cannot fit a recognized gesture.")
                return
            }
            let dragDistance = max(
                -maximumGestureDistance,
                min(farFeasibleShift, maximumGestureDistance)
            )
            guard abs(dragDistance) >= minimumGestureDistance else {
                XCTFail("Report correction feasible shift is below gesture recognition.")
                return
            }

            let scrollOrigin = correctionScrollView.coordinate(
                withNormalizedOffset: CGVector(dx: 0, dy: 0)
            )
            let dragStartOffsetY = dragDistance > 0
                ? visibleTop - scrollFrame.minY + dragInset
                : visibleBottom - scrollFrame.minY - dragInset
            let dragStart = scrollOrigin.withOffset(
                CGVector(dx: scrollFrame.width / 2, dy: dragStartOffsetY)
            )
            let dragEnd = dragStart.withOffset(
                CGVector(dx: 0, dy: dragDistance)
            )
            let saveBeforeDrag = save.frame.minY
            dragStart.press(forDuration: 0.05, thenDragTo: dragEnd)
            let observedShift = save.frame.minY - saveBeforeDrag
            guard observedShift * dragDistance > 0 else {
                XCTFail("Report correction positioning gesture was not recognized.")
                return
            }
        }

        let finalFocusPreserved = wait(
            for: note,
            predicate: "hasKeyboardFocus == true",
            timeout: 10
        )
        let finalKeyboardExists = keyboard.waitForExistence(timeout: 10)
        let finalValidationExists = validation.waitForExistence(timeout: 10)
        let finalSaveExists = save.waitForExistence(timeout: 10)
        let finalScrollFrame = correctionScrollView.frame
        let finalVisibleTop = max(finalScrollFrame.minY, navigationBar.frame.maxY)
        let finalKeyboardFrame = keyboard.frame
        let finalKeyboardInputViewExists: Bool
        let finalKeyboardInputViewContainsKeyboard: Bool
        let finalVisibleBottom: CGFloat
        if let inputViews = currentProfileInputViews,
           let inputView = keyboardInputView {
            finalKeyboardInputViewExists = inputViews.count == 1
                && inputView.waitForExistence(timeout: 10)
            let finalInputViewFrame = inputView.frame
            finalKeyboardInputViewContainsKeyboard = finalKeyboardExists
                && finalKeyboardInputViewExists
                && finalInputViewFrame.minX <= finalKeyboardFrame.minX
                && finalInputViewFrame.maxX >= finalKeyboardFrame.maxX
                && finalInputViewFrame.minY <= finalKeyboardFrame.minY
                && finalInputViewFrame.maxY >= finalKeyboardFrame.maxY
            finalVisibleBottom = finalKeyboardInputViewContainsKeyboard
                ? min(
                    finalScrollFrame.maxY,
                    min(finalKeyboardFrame.minY, finalInputViewFrame.minY)
                )
                : -CGFloat.greatestFiniteMagnitude
        } else {
            finalKeyboardInputViewExists = true
            finalKeyboardInputViewContainsKeyboard = true
            finalVisibleBottom = finalKeyboardExists
                ? min(finalScrollFrame.maxY, finalKeyboardFrame.minY)
                : -CGFloat.greatestFiniteMagnitude
        }
        let finalValidationContained = finalValidationExists
            && validation.frame.minY >= finalVisibleTop
            && validation.frame.maxY <= finalVisibleBottom
        let finalSaveContained = finalSaveExists
            && save.frame.minY >= finalVisibleTop
            && save.frame.maxY <= finalVisibleBottom
        guard finalFocusPreserved,
              finalKeyboardExists,
              finalKeyboardInputViewExists,
              finalKeyboardInputViewContainsKeyboard,
              finalValidationExists,
              finalSaveExists,
              finalValidationContained,
              finalSaveContained,
              save.isHittable else {
            XCTFail(
                "Report correction validation and Save did not remain fully actionable."
            )
            return
        }
        captureBaseline("state.report-correction.validation-error", in: app)

        note.typeText("Verified connector label")
        dismissMultilineKeyboard(
            afterEditing: note,
            on: element("s4.5.correction.screen", in: app),
            clearedValidation: validation,
            in: app
        )
        scroll(save, in: app)
        assertControl(save, label: "Save correction")
        save.tap()
        let saving = element("s4.5.correction.saving", in: app)
        XCTAssertTrue(saving.waitForExistence(timeout: 10))
        captureBaseline("state.report-correction.saving", in: app)
        XCTAssertTrue(element("s4.5.correction.ready", in: app)
            .waitForExistence(timeout: 40))
        guard positionReportCorrectionCompletedForAXText(in: app) else { return }
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
        let usesSegment3AXTextFeedbackCorrection =
            (
                automationSegment == .segment3
                    && automationShard?.shardID == "s10.4.current.ax-text"
                    && automationSegment.replayCount == 22
                    && automationSegment.ownedStartOrdinal == 51
                    && automationSegment.ownedCount == 17
                    && automationSegment.finalOrdinal == 67
                    && segmentedRouteStateCursor == 57
                    && migratedStateIDs
                        == Array(Self.segmentedRouteStateIDs[50..<57])
                    && !automatedSegmentFinished
                    && app.state == .runningForeground
            )
            || (
                automationSegment == .none
                    && automationShard?.shardID == "s10.4.current.ax-text"
                    && automationSegment.replayCount == 0
                    && automationSegment.ownedStartOrdinal == 1
                    && automationSegment.ownedCount == 67
                    && automationSegment.finalOrdinal == 67
                    && segmentedRouteStateCursor == 0
                    && migratedStateIDs
                        == Array(Self.segmentedRouteStateIDs[0..<57])
                    && !automatedSegmentFinished
                    && app.state == .runningForeground
            )
        var measuredUndertravel: CGFloat = 0
        var compensatedDirection: CGFloat = 0
        var usedSegment3DisjointFeedbackCorrection = false
        for _ in 0..<4 {
            if usedSegment3DisjointFeedbackCorrection,
               appMetadata.frame.maxY <= navigationBar.frame.minY,
               saveDiagnostics.frame.maxY
                <= signsTab.frame.minY - bottomClearance {
                break
            }
            let minimumShift = navigationBar.frame.maxY
                + topClearance
                - appMetadata.frame.minY
            let maximumShift = signsTab.frame.minY
                - bottomClearance
                - saveDiagnostics.frame.maxY
            let targetDistance: CGFloat
            if maximumShift < minimumShift {
                if usesSegment3AXTextFeedbackCorrection,
                   maximumShift >= 0,
                   appMetadata.frame.maxY <= navigationBar.frame.minY {
                    usedSegment3DisjointFeedbackCorrection = true
                    break
                }
                guard usesSegment3AXTextFeedbackCorrection,
                      maximumShift < 0 else {
                    XCTFail("Feedback review positioning interval is impossible.")
                    return
                }
                usedSegment3DisjointFeedbackCorrection = true
                targetDistance = maximumShift
            } else {
                if minimumShift <= 0, maximumShift >= 0 { break }
                targetDistance = minimumShift > 0
                    ? maximumShift
                    : minimumShift
            }
            let direction: CGFloat = targetDistance > 0 ? 1 : -1
            if usedSegment3DisjointFeedbackCorrection {
                guard direction == -1,
                      compensatedDirection == 0
                        || compensatedDirection == direction else {
                    XCTFail(
                        "AX-text segment-3 Feedback positioning reversed direction."
                    )
                    return
                }
            } else if compensatedDirection != direction {
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
        if usedSegment3DisjointFeedbackCorrection {
            XCTAssertLessThanOrEqual(
                appMetadata.frame.maxY,
                navigationBar.frame.minY
            )
        } else {
            XCTAssertGreaterThanOrEqual(
                appMetadata.frame.minY,
                navigationBar.frame.maxY + topClearance
            )
        }
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
        emitsEvidence: Bool = true,
        in app: XCUIApplication
    ) -> Bool {
        var usedSettingsRetry = false
        let preparesPaywallAvailableEvidence = emitsEvidence
            && shouldPrepareNormalEvidence(
                for: "state.paywall.available",
                in: app
            )
        if preparesPaywallAvailableEvidence {
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
        }
        if emitsEvidence {
            captureBaseline("state.paywall.available", in: app)
        }
        if preparesPaywallAvailableEvidence {
        let renewal = element("s7.2.paywall.renewal", in: app)
        scroll(renewal, in: app)
        assertLocalizedLabelContains(renewal, "$59.99")
        let noSync = element("s7.2.paywall.no-sync", in: app)
        scroll(noSync, in: app)
        assertLocalizedLabelContains(noSync, "do not sync")
        }

        var store = element("s7.2.paywall.store", in: app)
        XCTAssertTrue(store.waitForExistence(timeout: 30))
        if usesPseudolanguage {
            XCTAssertTrue(wait(for: store, predicate: "enabled == true", timeout: 20))
            assertLocalizedValue(store, equals: "Ready")
        } else {
            XCTAssertTrue(wait(for: store, predicate: "value == 'Ready'", timeout: 20))
        }
        XCTAssertTrue(store.isEnabled)

        if preparesPaywallAvailableEvidence {
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
        }

        var purchase = firstPurchaseButton(in: app)
        scroll(purchase, in: app)
        purchase.tap()
        var purchaseState = element("s7.2.paywall.purchase-state", in: app)
        if !usesPseudolanguage {
            let verifiedPurchaseLabel =
                "Complete: Purchase verified. Subscription access is ready."
            let unverifiedPurchaseLabel =
                "Purchase couldn’t be verified. Your existing data is still available. Try again."
            let terminalPurchaseExpectation = XCTNSPredicateExpectation(
                predicate: NSPredicate(
                    format: "label == %@ OR label == %@",
                    verifiedPurchaseLabel,
                    unverifiedPurchaseLabel
                ),
                object: purchaseState
            )
            XCTAssertEqual(
                XCTWaiter.wait(
                    for: [terminalPurchaseExpectation],
                    timeout: 45
                ),
                .completed
            )
            if purchaseState.label == unverifiedPurchaseLabel {
                guard let retainedSession = storeKitSession else {
                    XCTFail("The retained StoreKit test session is required")
                    return usedSettingsRetry
                }
                app.terminate()
                retainedSession.resetToDefaultState()
                retainedSession.clearTransactions()
                retainedSession.disableDialogs = true
                app.launch()
                XCTAssertTrue(element("s2.sign-detail.screen", in: app)
                    .waitForExistence(timeout: 30))
                let retrySettings = element("s1.settings.button", in: app)
                assertControl(retrySettings, label: "Settings")
                retrySettings.tap()
                XCTAssertTrue(element("s1.settings.screen", in: app)
                    .waitForExistence(timeout: 20))
                let retryPaywall = element("s7.2.settings.paywall", in: app)
                scroll(retryPaywall, in: app)
                assertControl(retryPaywall, label: "View subscription")
                retryPaywall.tap()
                XCTAssertTrue(element("s7.2.paywall.screen", in: app)
                    .waitForExistence(timeout: 30))
                usedSettingsRetry = true
                store = element("s7.2.paywall.store", in: app)
                XCTAssertTrue(store.waitForExistence(timeout: 30))
                XCTAssertTrue(wait(
                    for: store,
                    predicate: "value == 'Ready'",
                    timeout: 20
                ))
                XCTAssertTrue(store.isEnabled)
                purchase = firstPurchaseButton(in: app)
                scroll(purchase, in: app)
                XCTAssertTrue(purchase.waitForExistence(timeout: 20))
                XCTAssertTrue(purchase.isEnabled)
                XCTAssertTrue(purchase.isHittable)
                purchase.tap()
                purchaseState = element("s7.2.paywall.purchase-state", in: app)
            }
        }
        waitForLocalizedLabel(
            purchaseState,
            containing: "Purchase verified. Subscription access is ready.",
            timeout: 45
        )
        if !emitsEvidence {
            return usedSettingsRetry
        }
        let terms = element("s7.2.paywall.terms", in: app)
        let privacy = element("s7.2.paywall.privacy", in: app)
        let support = element("s7.2.paywall.support", in: app)
        for control in [terms, privacy, support] {
            XCTAssertTrue(control.waitForExistence(timeout: 20))
            assertMinimumGeometry(control)
            XCTAssertTrue(control.isEnabled)
        }
        XCTAssertLessThanOrEqual(purchaseState.frame.maxY, terms.frame.minY)
        XCTAssertLessThanOrEqual(terms.frame.maxY, privacy.frame.minY)
        XCTAssertLessThanOrEqual(privacy.frame.maxY, support.frame.minY)

        let close = element("s7.2.paywall.close", in: app)
        guard store.waitForExistence(timeout: 20),
              close.waitForExistence(timeout: 20),
              support.waitForExistence(timeout: 20),
              purchase.waitForExistence(timeout: 20) else {
            XCTFail("The purchase-complete viewport controls must exist before positioning.")
            return usedSettingsRetry
        }

        if automationShard?.shardID == "s10.4.current.ax-text" ||
            automationShard?.shardID == "s10.4.minimum.minimum-os" {
            if shouldPrepareNormalEvidence(
                for: "state.paywall.purchase-complete",
                in: app
            ) {
                guard positionAXTextPurchaseCompleteViewport(in: app) else {
                    XCTFail("S10.4 AX-text purchase-complete positioning failed")
                    return usedSettingsRetry
                }
            }
            captureBaseline("state.paywall.purchase-complete", in: app)
            return usedSettingsRetry
        }

        var measuredUndertravel: CGFloat = 0
        for _ in 0..<4 {
            let viewportTop = store.frame.minY
            let viewportBottom = store.frame.maxY
            let minimumShift = max(
                viewportTop - close.frame.minY,
                viewportBottom - purchase.frame.minY
            )
            let maximumShift = viewportBottom - support.frame.maxY
            if minimumShift <= 0, maximumShift >= 0 {
                break
            }
            guard minimumShift <= maximumShift else {
                XCTFail("The purchase-complete viewport has no feasible positioning interval.")
                return usedSettingsRetry
            }
            guard maximumShift > 0 else {
                XCTFail("The purchase-complete viewport requires a non-positive correction.")
                return usedSettingsRetry
            }

            let targetDistance = maximumShift
            let requestedDistance = targetDistance + measuredUndertravel
            let dragInset: CGFloat = 24
            let maximumGestureDistance = store.frame.height - 2 * dragInset
            guard maximumGestureDistance >= 44 else {
                XCTFail("The Store viewport cannot contain a recognized positioning gesture.")
                return usedSettingsRetry
            }
            let dragDistance = min(requestedDistance, maximumGestureDistance)
            guard dragDistance >= 44 else {
                XCTFail("The purchase-complete positioning gesture would not be recognized.")
                return usedSettingsRetry
            }

            let closeBeforeDrag = close.frame.minY
            let storeOrigin = store.coordinate(
                withNormalizedOffset: CGVector(dx: 0, dy: 0)
            )
            let dragStart = storeOrigin.withOffset(
                CGVector(dx: store.frame.width / 2, dy: dragInset)
            )
            let dragEnd = storeOrigin.withOffset(
                CGVector(
                    dx: store.frame.width / 2,
                    dy: dragInset + dragDistance
                )
            )
            dragStart.press(
                forDuration: 0.2,
                thenDragTo: dragEnd,
                withVelocity: .slow,
                thenHoldForDuration: 0.2
            )
            let actualDistance = close.frame.minY - closeBeforeDrag
            guard actualDistance > 0 else {
                XCTFail("The purchase-complete positioning gesture was not recognized.")
                return usedSettingsRetry
            }
            measuredUndertravel = max(0, dragDistance - actualDistance)
        }

        let finalViewportControls = [close, terms, privacy, support]
        guard finalViewportControls.allSatisfy({
            $0.waitForExistence(timeout: 20)
        }) else {
            XCTFail("The purchase-complete viewport controls must remain present.")
            return usedSettingsRetry
        }
        for control in finalViewportControls {
            assertMinimumGeometry(control)
            XCTAssertTrue(control.isEnabled)
            XCTAssertTrue(control.isHittable)
        }
        guard finalViewportControls.allSatisfy({
            $0.frame.width + 0.001 >= 44
                && $0.frame.height + 0.001 >= 44
                && $0.isEnabled
                && $0.isHittable
        }) else {
            XCTFail("The purchase-complete viewport controls must remain actionable.")
            return usedSettingsRetry
        }
        guard close.frame.minY >= store.frame.minY,
              close.frame.maxY <= store.frame.maxY,
              purchaseState.frame.maxY <= terms.frame.minY,
              terms.frame.maxY <= privacy.frame.minY,
              privacy.frame.maxY <= support.frame.minY,
              support.frame.maxY <= store.frame.maxY,
              purchase.frame.minY >= store.frame.maxY else {
            XCTFail("The purchase-complete viewport composition was not reached.")
            return usedSettingsRetry
        }
        captureBaseline("state.paywall.purchase-complete", in: app)
        return usedSettingsRetry
    }

    @MainActor
    private func positionAXTextPurchaseCompleteViewport(
        in app: XCUIApplication
    ) -> Bool {
        let purchasePredicate = NSPredicate(
            format: "label CONTAINS[c] 'Subscribe' OR " +
                "label CONTAINS[c] 'Trial' OR label CONTAINS[c] '$59.99'"
        )
        let screens = app.descendants(matching: .any).matching(
            identifier: "s7.2.paywall.screen"
        )
        let stores = app.descendants(matching: .any).matching(
            identifier: "s7.2.paywall.store"
        )
        let closeButtons = app.buttons.matching(
            identifier: "s7.2.paywall.close"
        )
        let purchaseStates = app.descendants(matching: .any).matching(
            identifier: "s7.2.paywall.purchase-state"
        )
        let termsButtons = app.buttons.matching(
            identifier: "s7.2.paywall.terms"
        )
        let privacyButtons = app.buttons.matching(
            identifier: "s7.2.paywall.privacy"
        )
        let supportButtons = app.buttons.matching(
            identifier: "s7.2.paywall.support"
        )
        let purchaseButtons = app.buttons.matching(purchasePredicate)
        let screen = screens.firstMatch
        let store = stores.firstMatch
        let close = closeButtons.firstMatch
        let purchaseState = purchaseStates.firstMatch
        let terms = termsButtons.firstMatch
        let privacy = privacyButtons.firstMatch
        let support = supportButtons.firstMatch
        let purchase = purchaseButtons.firstMatch
        let routeQueries = [
            screens,
            stores,
            closeButtons,
            purchaseStates,
            termsButtons,
            privacyButtons,
            supportButtons,
            purchaseButtons,
        ]
        let routeElements = [
            screen,
            store,
            close,
            purchaseState,
            terms,
            privacy,
            support,
            purchase,
        ]
        let isValidFrame: (CGRect) -> Bool = { frame in
            !frame.isNull
                && !frame.isEmpty
                && !frame.isInfinite
                && frame.origin.x.isFinite
                && frame.origin.y.isFinite
                && frame.size.width.isFinite
                && frame.size.height.isFinite
        }
        let fail: (String) -> Bool = { message in
            XCTFail(message)
            return false
        }
        let hasStableRoute: () -> Bool = {
            app.state == .runningForeground
                && routeQueries.allSatisfy { $0.count == 1 }
                && routeElements.allSatisfy(\.exists)
                && screen.elementType == .other
                && screen.identifier == "s7.2.paywall.screen"
                && store.elementType == .other
                && store.identifier == "s7.2.paywall.store"
                && store.isEnabled
                && close.elementType == .button
                && close.identifier == "s7.2.paywall.close"
                && purchaseState.elementType == .other
                && purchaseState.identifier == "s7.2.paywall.purchase-state"
                && terms.elementType == .button
                && terms.identifier == "s7.2.paywall.terms"
                && privacy.elementType == .button
                && privacy.identifier == "s7.2.paywall.privacy"
                && support.elementType == .button
                && support.identifier == "s7.2.paywall.support"
                && purchase.elementType == .button
                && purchase.identifier.isEmpty
        }
        let hasExactValues: () -> Bool = {
            hasStableRoute()
                && (store.value as? String) == "Ready"
                && close.label == "Close"
                && (close.value as? String) == ""
                && close.isEnabled
                && purchaseState.label
                    == "Complete: Purchase verified. Subscription access is ready."
                && (purchaseState.value as? String) == ""
                && purchaseState.isEnabled
                && terms.label == "Terms"
                && (terms.value as? String) == ""
                && terms.isEnabled
                && privacy.label == "Privacy"
                && (privacy.value as? String) == ""
                && privacy.isEnabled
                && support.label == "Support"
                && (support.value as? String) == ""
                && support.isEnabled
                && purchase.label == "Subscribe"
                && (purchase.value as? String) == ""
                && purchase.isEnabled
        }
        guard hasStableRoute() else {
            return fail("AX-text purchase-complete route is ambiguous.")
        }

        let usesMinimumOSViewport =
            automationShard?.shardID == "s10.4.minimum.minimum-os"
        let receiverInset: CGFloat = 24
        let minimumGestureDistance: CGFloat = 44
        var completedGestureCount = 0
        var measuredUndertravel: CGFloat = 0

        func positionViewport(
            named stage: String,
            interval: () -> (
                storeFrame: CGRect,
                minimumShift: CGFloat,
                maximumShift: CGFloat
            )?
        ) -> Bool {
            while true {
                guard hasStableRoute() else {
                    return fail(
                        "AX-text purchase-complete \(stage) route changed."
                    )
                }
                guard let geometry = interval(),
                      geometry.minimumShift.isFinite,
                      geometry.maximumShift.isFinite,
                      geometry.minimumShift <= geometry.maximumShift else {
                    return fail(
                        "AX-text purchase-complete \(stage) interval is infeasible."
                    )
                }
                if geometry.minimumShift <= 0,
                   geometry.maximumShift >= 0 {
                    return true
                }
                guard completedGestureCount < 4 else {
                    return fail(
                        "AX-text purchase-complete positioning exceeded four gestures."
                    )
                }

                let receiverCapacity =
                    geometry.storeFrame.height - 2 * receiverInset
                guard receiverCapacity.isFinite,
                      receiverCapacity >= minimumGestureDistance else {
                    return fail(
                        "AX-text Store cannot recognize a \(stage) gesture."
                    )
                }
                let intervalWidth =
                    geometry.maximumShift - geometry.minimumShift
                let interiorMargin = Swift.min(
                    minimumGestureDistance,
                    intervalWidth / 2
                )
                let targetDistance = geometry.minimumShift > 0
                    ? geometry.minimumShift + interiorMargin
                    : geometry.maximumShift - interiorMargin
                let requestedMagnitude = Swift.max(
                    abs(targetDistance) + measuredUndertravel,
                    minimumGestureDistance
                )
                let clampedMagnitude = Swift.min(
                    requestedMagnitude,
                    receiverCapacity
                )
                let dragDistance = targetDistance > 0
                    ? clampedMagnitude
                    : -clampedMagnitude

                let storeOrigin = store.coordinate(
                    withNormalizedOffset: CGVector(dx: 0, dy: 0)
                )
                let dragStartOffsetY = dragDistance > 0
                    ? receiverInset
                    : geometry.storeFrame.height - receiverInset
                let dragStart = usesMinimumOSViewport
                    ? store.coordinate(
                        withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
                    )
                    : storeOrigin.withOffset(
                        CGVector(
                            dx: geometry.storeFrame.width / 2,
                            dy: dragStartOffsetY
                        )
                    )
                let dragEnd = usesMinimumOSViewport
                    ? dragStart.withOffset(CGVector(dx: 0, dy: dragDistance))
                    : storeOrigin.withOffset(
                        CGVector(
                            dx: geometry.storeFrame.width / 2,
                            dy: dragStartOffsetY + dragDistance
                        )
                    )
                let purchaseStateBeforeDrag = purchaseState.frame.minY
                let supportBeforeDrag = support.frame.minY
                guard purchaseStateBeforeDrag.isFinite,
                      supportBeforeDrag.isFinite else {
                    return fail(
                        "AX-text purchase-complete \(stage) progress is invalid."
                    )
                }

                dragStart.press(
                    forDuration: 0.2,
                    thenDragTo: dragEnd,
                    withVelocity: .slow,
                    thenHoldForDuration: 0.2
                )
                completedGestureCount += 1

                guard hasStableRoute() else {
                    return fail(
                        "AX-text purchase-complete \(stage) route changed after positioning."
                    )
                }
                let purchaseStateAfterDrag = purchaseState.frame.minY
                let supportAfterDrag = support.frame.minY
                guard purchaseStateAfterDrag.isFinite,
                      supportAfterDrag.isFinite else {
                    return fail(
                        "AX-text purchase-complete \(stage) post-drag geometry is invalid."
                    )
                }
                let purchaseStateShift =
                    purchaseStateAfterDrag - purchaseStateBeforeDrag
                let supportShift = supportAfterDrag - supportBeforeDrag
                guard purchaseStateShift * dragDistance > 0,
                      supportShift * dragDistance > 0 else {
                    return fail(
                        "AX-text purchase-complete \(stage) gesture made no signed progress."
                    )
                }
                measuredUndertravel = Swift.max(
                    0,
                    abs(dragDistance) - abs(purchaseStateShift)
                )
            }
        }

        let legalInterval: () -> (
            storeFrame: CGRect,
            minimumShift: CGFloat,
            maximumShift: CGFloat
        )? = {
            let storeFrame = store.frame
            let closeFrame = close.frame
            let termsFrame = terms.frame
            let privacyFrame = privacy.frame
            let supportFrame = support.frame
            let purchaseFrame = purchase.frame
            guard [
                storeFrame,
                closeFrame,
                termsFrame,
                privacyFrame,
                supportFrame,
                purchaseFrame,
            ].allSatisfy(isValidFrame),
                  storeFrame.minY <= storeFrame.maxY else {
                return nil
            }
            let minimumShift = Swift.max(
                storeFrame.maxY - purchaseFrame.minY,
                Swift.max(
                    storeFrame.minY - termsFrame.minY,
                    Swift.max(
                        storeFrame.minY - privacyFrame.minY,
                        storeFrame.minY - supportFrame.minY
                    )
                )
            )
            let maximumShift = Swift.min(
                storeFrame.minY - closeFrame.maxY,
                Swift.min(
                    storeFrame.maxY - termsFrame.maxY,
                    Swift.min(
                        storeFrame.maxY - privacyFrame.maxY,
                        storeFrame.maxY - supportFrame.maxY
                    )
                )
            )
            return (storeFrame, minimumShift, maximumShift)
        }
        guard positionViewport(
            named: "legal viewport",
            interval: legalInterval
        ) else {
            return false
        }

        let legalStoreFrame = store.frame
        let legalCloseFrame = close.frame
        let legalTermsFrame = terms.frame
        let legalPrivacyFrame = privacy.frame
        let legalSupportFrame = support.frame
        let legalPurchaseFrame = purchase.frame
        let legalFrames = [
            legalStoreFrame,
            legalCloseFrame,
            purchaseState.frame,
            legalTermsFrame,
            legalPrivacyFrame,
            legalSupportFrame,
            legalPurchaseFrame,
        ]
        let legalControlsMeetMinimumSize =
            legalTermsFrame.width >= minimumGestureDistance
                && legalTermsFrame.height >= minimumGestureDistance
                && legalPrivacyFrame.width >= minimumGestureDistance
                && legalPrivacyFrame.height >= minimumGestureDistance
                && legalSupportFrame.width >= minimumGestureDistance
                && legalSupportFrame.height >= minimumGestureDistance
        guard hasExactValues(),
              legalFrames.allSatisfy(isValidFrame),
              legalCloseFrame.maxY <= legalStoreFrame.minY,
              legalStoreFrame.contains(legalTermsFrame),
              legalStoreFrame.contains(legalPrivacyFrame),
              legalStoreFrame.contains(legalSupportFrame),
              legalTermsFrame.maxY <= legalPrivacyFrame.minY,
              legalPrivacyFrame.maxY <= legalSupportFrame.minY,
              legalPurchaseFrame.minY >= legalStoreFrame.maxY,
              terms.isHittable,
              privacy.isHittable,
              support.isHittable,
              !purchase.isHittable,
              legalControlsMeetMinimumSize else {
            return fail(
                "AX-text purchase-complete legal viewport is unsafe."
            )
        }
        if usesMinimumOSViewport {
            let minimumPurchaseStateFrame = purchaseState.frame
            guard isValidFrame(minimumPurchaseStateFrame),
                  legalStoreFrame.contains(minimumPurchaseStateFrame),
                  purchaseState.isHittable else {
                return fail(
                    "Minimum-OS purchase-complete legal viewport is unsafe."
                )
            }
            return true
        }
        let verifiedInterval: () -> (
            storeFrame: CGRect,
            minimumShift: CGFloat,
            maximumShift: CGFloat
        )? = {
            let storeFrame = store.frame
            let closeFrame = close.frame
            let purchaseStateFrame = purchaseState.frame
            let termsFrame = terms.frame
            let privacyFrame = privacy.frame
            let supportFrame = support.frame
            let purchaseFrame = purchase.frame
            guard [
                storeFrame,
                closeFrame,
                purchaseStateFrame,
                termsFrame,
                privacyFrame,
                supportFrame,
                purchaseFrame,
            ].allSatisfy(isValidFrame),
                  storeFrame.minY <= storeFrame.maxY else {
                return nil
            }
            let minimumShift = Swift.max(
                storeFrame.minY - purchaseStateFrame.minY,
                Swift.max(
                    storeFrame.maxY - termsFrame.minY,
                    Swift.max(
                        storeFrame.maxY - privacyFrame.minY,
                        Swift.max(
                            storeFrame.maxY - supportFrame.minY,
                            storeFrame.maxY - purchaseFrame.minY
                        )
                    )
                )
            )
            let maximumShift = Swift.min(
                storeFrame.maxY - purchaseStateFrame.maxY,
                storeFrame.minY - closeFrame.maxY
            )
            return (storeFrame, minimumShift, maximumShift)
        }
        guard positionViewport(
            named: "verified viewport",
            interval: verifiedInterval
        ) else {
            return false
        }

        let verifiedStoreFrame = store.frame
        let verifiedCloseFrame = close.frame
        let verifiedPurchaseStateFrame = purchaseState.frame
        let verifiedTermsFrame = terms.frame
        let verifiedPrivacyFrame = privacy.frame
        let verifiedSupportFrame = support.frame
        let verifiedPurchaseFrame = purchase.frame
        let verifiedFrames = [
            verifiedStoreFrame,
            verifiedCloseFrame,
            verifiedPurchaseStateFrame,
            verifiedTermsFrame,
            verifiedPrivacyFrame,
            verifiedSupportFrame,
            verifiedPurchaseFrame,
        ]
        guard hasExactValues(),
              verifiedFrames.allSatisfy(isValidFrame),
              verifiedCloseFrame.maxY <= verifiedStoreFrame.minY,
              verifiedStoreFrame.contains(verifiedPurchaseStateFrame),
              purchaseState.isHittable,
              verifiedPurchaseStateFrame.maxY <= verifiedTermsFrame.minY,
              verifiedTermsFrame.minY >= verifiedStoreFrame.maxY,
              verifiedPrivacyFrame.minY >= verifiedStoreFrame.maxY,
              verifiedSupportFrame.minY >= verifiedStoreFrame.maxY,
              verifiedPurchaseFrame.minY >= verifiedStoreFrame.maxY,
              verifiedTermsFrame.maxY <= verifiedPrivacyFrame.minY,
              verifiedPrivacyFrame.maxY <= verifiedSupportFrame.minY,
              verifiedSupportFrame.maxY <= verifiedPurchaseFrame.minY,
              !terms.isHittable,
              !privacy.isHittable,
              !support.isHittable,
              !purchase.isHittable else {
            return fail(
                "AX-text purchase-complete verified viewport is unsafe."
            )
        }
        return true
    }
    @MainActor
    private func assertMonthlyPaywallAtXXXL(in app: XCUIApplication) throws {
        let settings = element("s1.settings.button", in: app)
        assertControl(settings, label: "Settings")
        settings.tap()
        XCTAssertTrue(element("s1.settings.screen", in: app)
            .waitForExistence(timeout: 20))
        if automationShard?.shardID == "s10.4.current.ax-text",
           (automationSegment == .segment3 || automationSegment == .none),
           shouldPrepareNormalEvidence(
               for: "state.settings.hub",
               in: app
           ) {
            guard try positionSettingsHubDiagnosticsEntryForAXText(in: app) else {
                throw AutomationConfigurationError.invalid(
                    "S10.4 AX-text settings-hub positioning failed"
                )
            }
        }
        captureBaseline("state.settings.hub", in: app)

        try captureSettingsDataSurfaces(in: app)

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
        if finishAutomatedSegmentIfNeeded(after: 67, in: app) { return }
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
    private func captureSettingsDataSurfaces(in app: XCUIApplication) throws {
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
        let diagnosticsScrollViews = app.scrollViews.containing(
            .staticText,
            identifier: "s8.3.diagnostics.heading"
        )
        guard diagnosticsScrollViews.count == 1 else {
            XCTFail(
                "Diagnostics route must expose exactly one heading-containing ScrollView."
            )
            return
        }
        let diagnosticsScrollView = diagnosticsScrollViews.firstMatch
        guard diagnosticsScrollView.waitForExistence(timeout: 10) else {
            XCTFail("Diagnostics route ScrollView is missing.")
            return
        }
        let topClearance: CGFloat = 12
        let bottomClearance: CGFloat = 16
        let minimumGestureDistance: CGFloat = 44
        let dragInset: CGFloat = 24
        var upwardUndertravel: CGFloat = 0
        var downwardUndertravel: CGFloat = 0
        var stagingCount = 0
        var stagedFinalDirection: CGFloat?
        var usesProvenAXTextZeroIssueComposition = false
        for _ in 0..<6 {
            let minimumShift = navigationBar.frame.maxY
                + topClearance
                - diagnosticsAuthority.frame.minY
            let maximumShift = min(
                navigationBar.frame.maxY - diagnosticsHeading.frame.maxY,
                signsTab.frame.minY
                    - bottomClearance
                    - diagnosticsExport.frame.maxY
            )
            guard minimumShift <= maximumShift else {
                if let shard = automationShard,
                   shard.shardID == "s10.4.current.ax-text",
                   automationSegment == .segment3 {
                    let stateID = "state.diagnostics.ready"
                    let expectedMigratedStateIDs = Array(
                        Self.segmentedRouteStateIDs[50..<60]
                    )
                    let expectedContrastExceptionStateIDs = [
                        "state.report-correction.validation-error",
                    ]
                    guard automationSegment.replayCount == 22,
                          automationSegment.ownedStartOrdinal == 51,
                          automationSegment.ownedCount == 17,
                          automationSegment.finalOrdinal == 67,
                          Self.segmentedRouteStateIDs.count == 67,
                          Set(Self.segmentedRouteStateIDs).count == 67,
                          Self.segmentedRouteStateIDs[60] == stateID,
                          segmentedRouteStateCursor == 60,
                          migratedStateIDs == expectedMigratedStateIDs,
                          automationAXTreeDigests.keys.sorted()
                            == expectedMigratedStateIDs.sorted(),
                          automationContrastExceptions.keys.sorted()
                            == expectedContrastExceptionStateIDs,
                          !automatedSegmentFinished,
                          app.state == .runningForeground else {
                        throw AutomationConfigurationError.invalid(
                            "S10.4 AX-text diagnostics-ready zero-issue composition gate is invalid"
                        )
                    }
                    usesProvenAXTextZeroIssueComposition = true
                    break
                }
                if let shard = automationShard,
                   shard.shardID == "s10.4.current.ax-text",
                   automationSegment == .none {
                    let stateID = "state.diagnostics.ready"
                    let expectedMigratedStateIDs = Array(
                        Self.segmentedRouteStateIDs.prefix(60)
                    )
                    let expectedContrastExceptionStateIDs = [
                        "state.check-preflight.ready",
                        "state.issue.open",
                        "state.issue.recheck-due",
                        "state.issue.resolved",
                        "state.new-sign.editing",
                        "state.paywall.purchase-complete",
                        "state.recheck-capture.wide-ready",
                        "state.recheck-preflight.ready",
                        "state.report-correction.validation-error",
                        "state.report-history.ready",
                        "state.reports-index.ready",
                    ]
                    guard automationSegment.replayCount == 0,
                          automationSegment.ownedStartOrdinal == 1,
                          automationSegment.ownedCount == 67,
                          automationSegment.finalOrdinal == 67,
                          Self.segmentedRouteStateIDs.count == 67,
                          Set(Self.segmentedRouteStateIDs).count == 67,
                          Self.segmentedRouteStateIDs[60] == stateID,
                          segmentedRouteStateCursor == 0,
                          migratedStateIDs == expectedMigratedStateIDs,
                          automationAXTreeDigests.keys.sorted()
                            == expectedMigratedStateIDs.sorted(),
                          automationContrastExceptions.keys.sorted()
                            == expectedContrastExceptionStateIDs,
                          !automatedSegmentFinished,
                          app.state == .runningForeground else {
                        throw AutomationConfigurationError.invalid(
                            "S10.4 AX-text full-route diagnostics-ready zero-issue composition gate is invalid"
                        )
                    }
                    usesProvenAXTextZeroIssueComposition = true
                    break
                }
                XCTFail("Diagnostics positioning interval is impossible.")
                return
            }
            if minimumShift <= 0, maximumShift >= 0 {
                break
            }
            let requiredFinalDirection: CGFloat
            if maximumShift < 0 {
                requiredFinalDirection = -1
            } else if minimumShift > 0 {
                requiredFinalDirection = 1
            } else {
                XCTFail("Diagnostics positioning interval has no signed correction.")
                return
            }
            if let stagedFinalDirection,
               stagedFinalDirection != requiredFinalDirection {
                XCTFail("Diagnostics staged correction changed direction.")
                return
            }
            let dragStart = diagnosticsScrollView.coordinate(
                withNormalizedOffset: CGVector(dx: 0.01, dy: 0.45)
            )
            let startPoint = dragStart.screenPoint
            let upwardCapacity = startPoint.y
                - (diagnosticsScrollView.frame.minY + dragInset)
            let downwardCapacity = diagnosticsScrollView.frame.maxY
                - dragInset
                - startPoint.y
            guard upwardCapacity >= minimumGestureDistance,
                  downwardCapacity >= minimumGestureDistance else {
                XCTFail("Diagnostics ScrollView cannot contain recognized corrections.")
                return
            }
            let dragDistance: CGFloat
            let isStaging: Bool
            if maximumShift < 0 {
                let requestedMinimum = max(
                    minimumShift - upwardUndertravel,
                    -upwardCapacity
                )
                let requestedMaximum = min(
                    maximumShift - upwardUndertravel,
                    -minimumGestureDistance
                )
                if requestedMinimum <= requestedMaximum {
                    dragDistance = requestedMaximum
                    isStaging = false
                } else {
                    guard minimumShift > -minimumGestureDistance,
                          maximumShift < 0,
                          stagingCount < 2 else {
                        XCTFail("Diagnostics has no bounded upward residual strategy.")
                        return
                    }
                    let stagingDistance = minimumGestureDistance
                        + downwardUndertravel
                    guard stagingDistance.isFinite,
                          downwardCapacity >= stagingDistance else {
                        XCTFail("Diagnostics downward staging is not recognizable.")
                        return
                    }
                    dragDistance = stagingDistance
                    isStaging = true
                }
            } else {
                let requestedMinimum = max(
                    minimumShift + downwardUndertravel,
                    minimumGestureDistance
                )
                let requestedMaximum = min(
                    maximumShift + downwardUndertravel,
                    downwardCapacity
                )
                if requestedMinimum <= requestedMaximum {
                    dragDistance = requestedMinimum
                    isStaging = false
                } else {
                    guard maximumShift < minimumGestureDistance,
                          minimumShift > 0,
                          stagingCount < 2 else {
                        XCTFail("Diagnostics has no bounded downward residual strategy.")
                        return
                    }
                    let stagingDistance = minimumGestureDistance
                        + upwardUndertravel
                    guard stagingDistance.isFinite,
                          upwardCapacity >= stagingDistance else {
                        XCTFail("Diagnostics upward staging is not recognizable.")
                        return
                    }
                    dragDistance = -stagingDistance
                    isStaging = true
                }
            }
            guard (dragDistance < 0 ? upwardCapacity : downwardCapacity)
                >= abs(dragDistance) else {
                XCTFail("Diagnostics positioning request exceeds receiver capacity.")
                return
            }
            if isStaging {
                stagingCount += 1
                if stagedFinalDirection == nil {
                    stagedFinalDirection = requiredFinalDirection
                }
            }
            let dragEnd = dragStart.withOffset(
                CGVector(dx: 0, dy: dragDistance)
            )
            let authorityBeforeDrag = diagnosticsAuthority.frame.minY
            dragStart.press(
                forDuration: 0.2,
                thenDragTo: dragEnd,
                withVelocity: .slow,
                thenHoldForDuration: 0.2
            )
            let actualDistance = diagnosticsAuthority.frame.minY
                - authorityBeforeDrag
            guard actualDistance * dragDistance > 0 else {
                XCTFail("Diagnostics positioning gesture was not recognized.")
                return
            }
            let observedUndertravel = max(
                0,
                abs(dragDistance) - abs(actualDistance)
            )
            if dragDistance < 0 {
                upwardUndertravel = observedUndertravel
            } else {
                downwardUndertravel = observedUndertravel
            }
        }
        let finalMinimumShift = navigationBar.frame.maxY
            + topClearance
            - diagnosticsAuthority.frame.minY
        let finalMaximumShift = min(
            navigationBar.frame.maxY - diagnosticsHeading.frame.maxY,
            signsTab.frame.minY
                - bottomClearance
                - diagnosticsExport.frame.maxY
        )
        if !usesProvenAXTextZeroIssueComposition {
            guard finalMinimumShift <= 0, finalMaximumShift >= 0 else {
                XCTFail("Diagnostics positioning exhausted its bounded strategy.")
                return
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
        }
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
    private func positionRecheckPreflightContrastTargetsForAXText(
        in app: XCUIApplication
    ) -> Bool {
        let beforeYouBeginLabel = "Before you begin"
        let afterDarkLabel =
            "It is dark enough to observe the sign's visible illumination."
        let safePositionLabel =
            "I am in a safe, authorized position to take these photos."
        let focusedPredicate = NSPredicate(format: "hasKeyboardFocus == true")
        let beforeYouBeginPredicate = NSPredicate(
            format: "label == %@",
            beforeYouBeginLabel
        )
        let afterDarkPredicate = NSPredicate(
            format: "label == %@",
            afterDarkLabel
        )
        let preflightScreens = app.descendants(matching: .any).matching(
            identifier: "s3.preflight.screen"
        )
        let preflightScrollViews = app.scrollViews.matching(
            identifier: "s3.preflight.screen"
        )
        let navigationBars = app.navigationBars.matching(
            identifier: "Ready for night check"
        )
        let tabBars = app.tabBars
        let beforeYouBeginStaticTexts = app.staticTexts.matching(
            beforeYouBeginPredicate
        )
        let afterDarkStaticTexts = app.staticTexts.matching(afterDarkPredicate)
        let beginControls = app.buttons.matching(
            identifier: "s3.preflight.begin"
        )
        let afterDarkSwitches = app.switches.matching(
            identifier: "s3.preflight.after-dark"
        )
        let safePositionSwitches = app.switches.matching(
            identifier: "s3.preflight.safe-position"
        )
        let timeZoneFields = app.textFields.matching(
            identifier: "s3.preflight.time-zone"
        )
        let keyboards = app.keyboards
        let focusedElements = app.descendants(matching: .any).matching(
            focusedPredicate
        )
        guard preflightScreens.count == 1,
              preflightScrollViews.count == 1,
              navigationBars.count == 1,
              tabBars.count == 1,
              beforeYouBeginStaticTexts.count == 1,
              afterDarkStaticTexts.count == 1,
              beginControls.count == 1,
              afterDarkSwitches.count == 1,
              safePositionSwitches.count == 1,
              timeZoneFields.count == 0,
              keyboards.count == 0,
              focusedElements.count == 0 else {
            XCTFail("AX-text recheck-Preflight positioning bindings are ambiguous.")
            return false
        }
        let preflightScreen = preflightScreens.firstMatch
        let preflightScrollView = preflightScrollViews.firstMatch
        let navigationBar = navigationBars.firstMatch
        let tabBar = tabBars.firstMatch
        let beforeYouBeginStaticText = beforeYouBeginStaticTexts.firstMatch
        let afterDarkStaticText = afterDarkStaticTexts.firstMatch
        let beginControl = beginControls.firstMatch
        let afterDarkSwitch = afterDarkSwitches.firstMatch
        let safePositionSwitch = safePositionSwitches.firstMatch
        let isValidFrame: (CGRect) -> Bool = { frame in
            !frame.isNull
                && !frame.isEmpty
                && !frame.isInfinite
                && frame.origin.x.isFinite
                && frame.origin.y.isFinite
                && frame.size.width.isFinite
                && frame.size.height.isFinite
        }
        let exactRoute: () -> Bool = {
            app.state == .runningForeground
                && preflightScreens.count == 1
                && preflightScrollViews.count == 1
                && navigationBars.count == 1
                && tabBars.count == 1
                && beforeYouBeginStaticTexts.count == 1
                && afterDarkStaticTexts.count == 1
                && beginControls.count == 1
                && afterDarkSwitches.count == 1
                && safePositionSwitches.count == 1
                && timeZoneFields.count == 0
                && keyboards.count == 0
                && focusedElements.count == 0
                && preflightScreen.exists
                && preflightScreen.elementType == .scrollView
                && preflightScreen.identifier == "s3.preflight.screen"
                && preflightScreen.label.isEmpty
                && (preflightScreen.value as? String) == ""
                && preflightScreen.isEnabled
                && preflightScreen.isHittable
                && preflightScrollView.exists
                && preflightScrollView.elementType == .scrollView
                && preflightScrollView.identifier == "s3.preflight.screen"
                && preflightScrollView.label.isEmpty
                && (preflightScrollView.value as? String) == ""
                && preflightScrollView.isEnabled
                && preflightScrollView.isHittable
                && navigationBar.exists
                && navigationBar.elementType == .navigationBar
                && navigationBar.identifier == "Ready for night check"
                && navigationBar.label.isEmpty
                && (navigationBar.value as? String) == ""
                && navigationBar.isEnabled
                && navigationBar.isHittable
                && tabBar.exists
                && tabBar.elementType == .tabBar
                && tabBar.identifier.isEmpty
                && tabBar.label == "Tab Bar"
                && (tabBar.value as? String) == ""
                && tabBar.isEnabled
                && tabBar.isHittable
                && beforeYouBeginStaticText.exists
                && beforeYouBeginStaticText.elementType == .staticText
                && beforeYouBeginStaticText.identifier.isEmpty
                && beforeYouBeginStaticText.label == beforeYouBeginLabel
                && (beforeYouBeginStaticText.value as? String) == ""
                && beforeYouBeginStaticText.isEnabled
                && afterDarkStaticText.exists
                && afterDarkStaticText.elementType == .staticText
                && afterDarkStaticText.identifier.isEmpty
                && afterDarkStaticText.label == afterDarkLabel
                && (afterDarkStaticText.value as? String) == ""
                && afterDarkStaticText.isEnabled
                && beginControl.exists
                && beginControl.elementType == .button
                && beginControl.identifier == "s3.preflight.begin"
                && beginControl.label == "Begin check"
                && (beginControl.value as? String) == ""
                && !beginControl.isEnabled
                && !beginControl.isHittable
                && afterDarkSwitch.exists
                && afterDarkSwitch.elementType == .switch
                && afterDarkSwitch.identifier == "s3.preflight.after-dark"
                && afterDarkSwitch.label == afterDarkLabel
                && afterDarkSwitch.isEnabled
                && (afterDarkSwitch.value as? String) == "0"
                && safePositionSwitch.exists
                && safePositionSwitch.elementType == .switch
                && safePositionSwitch.identifier == "s3.preflight.safe-position"
                && safePositionSwitch.label == safePositionLabel
                && safePositionSwitch.isEnabled
                && (safePositionSwitch.value as? String) == "0"
        }
        guard exactRoute() else {
            XCTFail("AX-text recheck-Preflight positioning route changed.")
            return false
        }
        let frozenApplicationFrame = app.frame
        let frozenScreenFrame = preflightScreen.frame
        let frozenScrollFrame = preflightScrollView.frame
        let frozenNavigationFrame = navigationBar.frame
        let frozenTabFrame = tabBar.frame
        let initialBeforeYouBeginFrame = beforeYouBeginStaticText.frame
        let initialAfterDarkFrame = afterDarkStaticText.frame
        let initialBeginFrame = beginControl.frame
        let initialAfterDarkSwitchFrame = afterDarkSwitch.frame
        let initialSafePositionSwitchFrame = safePositionSwitch.frame
        guard isValidFrame(frozenApplicationFrame),
              isValidFrame(frozenScreenFrame),
              isValidFrame(frozenScrollFrame),
              isValidFrame(frozenNavigationFrame),
              isValidFrame(frozenTabFrame),
              isValidFrame(initialBeforeYouBeginFrame),
              isValidFrame(initialAfterDarkFrame),
              isValidFrame(initialBeginFrame),
              isValidFrame(initialAfterDarkSwitchFrame),
              isValidFrame(initialSafePositionSwitchFrame),
              initialBeforeYouBeginFrame.maxY < initialAfterDarkFrame.minY,
              frozenScreenFrame == frozenScrollFrame else {
            XCTFail("AX-text recheck-Preflight initial geometry is invalid.")
            return false
        }

        let verticalInset: CGFloat = 16
        let receiverInset: CGFloat = 24
        let minimumGestureDistance: CGFloat = 44
        var previousBeforeYouBeginMinYAfterDrag: CGFloat?
        var previousAfterDarkMinYAfterDrag: CGFloat?
        for _ in 0..<4 {
            guard exactRoute() else {
                XCTFail("AX-text recheck-Preflight route changed before positioning.")
                return false
            }
            let applicationFrame = app.frame
            let screenFrame = preflightScreen.frame
            let scrollFrame = preflightScrollView.frame
            let navigationFrame = navigationBar.frame
            let tabFrame = tabBar.frame
            let beforeYouBeginFrame = beforeYouBeginStaticText.frame
            let afterDarkFrame = afterDarkStaticText.frame
            let beginFrame = beginControl.frame
            let afterDarkSwitchFrame = afterDarkSwitch.frame
            let safePositionSwitchFrame = safePositionSwitch.frame
            let requiredFramesAreValid = isValidFrame(applicationFrame)
                && isValidFrame(screenFrame)
                && isValidFrame(scrollFrame)
                && isValidFrame(navigationFrame)
                && isValidFrame(tabFrame)
                && isValidFrame(beforeYouBeginFrame)
                && isValidFrame(afterDarkFrame)
                && isValidFrame(beginFrame)
                && isValidFrame(afterDarkSwitchFrame)
                && isValidFrame(safePositionSwitchFrame)
            var liveScrollFrame = CGRect.null
            if requiredFramesAreValid {
                liveScrollFrame = scrollFrame.intersection(applicationFrame)
            }
            guard requiredFramesAreValid,
                  isValidFrame(liveScrollFrame),
                  applicationFrame == frozenApplicationFrame,
                  screenFrame == frozenScreenFrame,
                  scrollFrame == frozenScrollFrame,
                  navigationFrame == frozenNavigationFrame,
                  tabFrame == frozenTabFrame,
                  screenFrame == scrollFrame,
                  beforeYouBeginFrame.maxY < afterDarkFrame.minY else {
                XCTFail("AX-text recheck-Preflight live geometry is invalid.")
                return false
            }
            let liveTop = max(liveScrollFrame.minY, navigationFrame.maxY)
            let liveBottom = min(
                liveScrollFrame.maxY,
                min(applicationFrame.maxY, tabFrame.minY)
            )
            let safeTop = liveTop + verticalInset
            let safeBottom = liveBottom - verticalInset
            let receiverTop = liveTop + receiverInset
            let receiverBottom = liveBottom - receiverInset
            let receiverLeft = liveScrollFrame.minX + receiverInset
            let receiverRight = liveScrollFrame.maxX - receiverInset
            let receiverCapacity = receiverBottom - receiverTop
            let targetSpan = afterDarkFrame.maxY - beforeYouBeginFrame.minY
            let minimumShift = max(
                safeTop - beforeYouBeginFrame.minY,
                safeTop - afterDarkFrame.minY
            )
            let maximumShift = min(
                safeBottom - beforeYouBeginFrame.maxY,
                safeBottom - afterDarkFrame.maxY
            )
            let targetsAreContained = beforeYouBeginFrame.minY >= safeTop
                && beforeYouBeginFrame.maxY <= safeBottom
                && afterDarkFrame.minY >= safeTop
                && afterDarkFrame.maxY <= safeBottom
            guard safeTop.isFinite,
                  safeBottom.isFinite,
                  receiverTop.isFinite,
                  receiverBottom.isFinite,
                  receiverLeft.isFinite,
                  receiverRight.isFinite,
                  receiverCapacity.isFinite,
                  targetSpan.isFinite,
                  minimumShift.isFinite,
                  maximumShift.isFinite,
                  safeTop <= safeBottom,
                  receiverLeft <= receiverRight,
                  receiverTop <= receiverBottom,
                  receiverCapacity >= minimumGestureDistance,
                  targetSpan <= safeBottom - safeTop,
                  minimumShift <= maximumShift else {
                XCTFail("AX-text recheck-Preflight has no feasible safe interval.")
                return false
            }
            if targetsAreContained { break }

            guard maximumShift < 0 else {
                XCTFail("AX-text recheck-Preflight requires a non-upward shift.")
                return false
            }
            let dragDistance: CGFloat
            let recognizedMinimum = max(minimumShift, -receiverCapacity)
            let recognizedMaximum = min(
                maximumShift,
                -minimumGestureDistance
            )
            if recognizedMinimum <= recognizedMaximum {
                dragDistance = recognizedMaximum
            } else {
                let stagedDistance = max(
                    -receiverCapacity,
                    maximumShift + minimumGestureDistance
                )
                guard stagedDistance <= -minimumGestureDistance else {
                    XCTFail("AX-text recheck-Preflight staged remainder is not recognizable.")
                    return false
                }
                dragDistance = stagedDistance
            }
            guard dragDistance < 0,
                  dragDistance <= -minimumGestureDistance else {
                XCTFail("AX-text recheck-Preflight drag direction is invalid.")
                return false
            }
            let receiverFrame = CGRect(
                x: receiverLeft,
                y: receiverTop,
                width: receiverRight - receiverLeft,
                height: receiverBottom - receiverTop
            )
            let startPoint = CGPoint(x: receiverRight, y: receiverBottom)
            let endPoint = CGPoint(
                x: startPoint.x,
                y: startPoint.y + dragDistance
            )
            guard isValidFrame(receiverFrame),
                  startPoint.x >= receiverFrame.minX,
                  startPoint.x <= receiverFrame.maxX,
                  startPoint.y >= receiverFrame.minY,
                  startPoint.y <= receiverFrame.maxY,
                  endPoint.x >= receiverFrame.minX,
                  endPoint.x <= receiverFrame.maxX,
                  endPoint.y >= receiverFrame.minY,
                  endPoint.y <= receiverFrame.maxY,
                  liveScrollFrame.contains(startPoint),
                  liveScrollFrame.contains(endPoint),
                  !beforeYouBeginFrame.contains(startPoint),
                  !beforeYouBeginFrame.contains(endPoint),
                  !afterDarkFrame.contains(startPoint),
                  !afterDarkFrame.contains(endPoint) else {
                XCTFail("AX-text recheck-Preflight drag receiver is obstructed.")
                return false
            }
            let scrollOrigin = preflightScrollView.coordinate(
                withNormalizedOffset: CGVector(dx: 0, dy: 0)
            )
            let startCoordinate = scrollOrigin.withOffset(
                CGVector(
                    dx: startPoint.x - scrollFrame.minX,
                    dy: startPoint.y - scrollFrame.minY
                )
            )
            let endCoordinate = scrollOrigin.withOffset(
                CGVector(
                    dx: endPoint.x - scrollFrame.minX,
                    dy: endPoint.y - scrollFrame.minY
                )
            )
            let beforeYouBeginMinYBeforeDrag = beforeYouBeginFrame.minY
            let afterDarkMinYBeforeDrag = afterDarkFrame.minY
            startCoordinate.press(
                forDuration: 0.2,
                thenDragTo: endCoordinate,
                withVelocity: .slow,
                thenHoldForDuration: 0.2
            )
            guard exactRoute() else {
                XCTFail("AX-text recheck-Preflight route changed after positioning.")
                return false
            }
            let beforeYouBeginFrameAfterDrag = beforeYouBeginStaticText.frame
            let afterDarkFrameAfterDrag = afterDarkStaticText.frame
            guard isValidFrame(beforeYouBeginFrameAfterDrag),
                  isValidFrame(afterDarkFrameAfterDrag) else {
                XCTFail("AX-text recheck-Preflight moved target geometry is invalid.")
                return false
            }
            let observedBeforeYouBeginShift =
                beforeYouBeginFrameAfterDrag.minY - beforeYouBeginMinYBeforeDrag
            let observedAfterDarkShift =
                afterDarkFrameAfterDrag.minY - afterDarkMinYBeforeDrag
            guard observedBeforeYouBeginShift < 0,
                  observedAfterDarkShift < 0,
                  observedBeforeYouBeginShift * dragDistance > 0,
                  observedAfterDarkShift * dragDistance > 0 else {
                XCTFail("AX-text recheck-Preflight gesture made no signed progress.")
                return false
            }
            if let previousBeforeYouBeginMinYAfterDrag,
               let previousAfterDarkMinYAfterDrag {
                guard beforeYouBeginFrameAfterDrag.minY
                        < previousBeforeYouBeginMinYAfterDrag,
                      afterDarkFrameAfterDrag.minY
                        < previousAfterDarkMinYAfterDrag else {
                    XCTFail("AX-text recheck-Preflight positioning reversed direction.")
                    return false
                }
            }
            previousBeforeYouBeginMinYAfterDrag =
                beforeYouBeginFrameAfterDrag.minY
            previousAfterDarkMinYAfterDrag = afterDarkFrameAfterDrag.minY
        }

        guard exactRoute() else {
            XCTFail("AX-text recheck-Preflight final route changed.")
            return false
        }
        let finalApplicationFrame = app.frame
        let finalScreenFrame = preflightScreen.frame
        let finalScrollFrame = preflightScrollView.frame
        let finalNavigationFrame = navigationBar.frame
        let finalTabFrame = tabBar.frame
        let finalBeforeYouBeginFrame = beforeYouBeginStaticText.frame
        let finalAfterDarkFrame = afterDarkStaticText.frame
        let finalBeginFrame = beginControl.frame
        let finalAfterDarkSwitchFrame = afterDarkSwitch.frame
        let finalSafePositionSwitchFrame = safePositionSwitch.frame
        let finalFramesAreValid = isValidFrame(finalApplicationFrame)
            && isValidFrame(finalScreenFrame)
            && isValidFrame(finalScrollFrame)
            && isValidFrame(finalNavigationFrame)
            && isValidFrame(finalTabFrame)
            && isValidFrame(finalBeforeYouBeginFrame)
            && isValidFrame(finalAfterDarkFrame)
            && isValidFrame(finalBeginFrame)
            && isValidFrame(finalAfterDarkSwitchFrame)
            && isValidFrame(finalSafePositionSwitchFrame)
            && finalApplicationFrame == frozenApplicationFrame
            && finalScreenFrame == frozenScreenFrame
            && finalScrollFrame == frozenScrollFrame
            && finalNavigationFrame == frozenNavigationFrame
            && finalTabFrame == frozenTabFrame
            && finalScreenFrame == finalScrollFrame
        var finalCompositionIsSafe = false
        if finalFramesAreValid {
            let finalLiveScrollFrame = finalScrollFrame.intersection(
                finalApplicationFrame
            )
            if isValidFrame(finalLiveScrollFrame) {
                let finalSafeTop = max(
                    finalLiveScrollFrame.minY,
                    finalNavigationFrame.maxY
                ) + verticalInset
                let finalSafeBottom = min(
                    finalLiveScrollFrame.maxY,
                    min(finalApplicationFrame.maxY, finalTabFrame.minY)
                ) - verticalInset
                finalCompositionIsSafe = finalSafeTop.isFinite
                    && finalSafeBottom.isFinite
                    && finalSafeTop <= finalSafeBottom
                    && finalBeforeYouBeginFrame.minY >= finalSafeTop
                    && finalBeforeYouBeginFrame.maxY <= finalSafeBottom
                    && finalAfterDarkFrame.minY >= finalSafeTop
                    && finalAfterDarkFrame.maxY <= finalSafeBottom
                    && finalBeforeYouBeginFrame.maxY
                        < finalAfterDarkFrame.minY
                    && beforeYouBeginStaticText.isHittable
                    && afterDarkStaticText.isHittable
            }
        }
        guard finalCompositionIsSafe else {
            XCTFail("AX-text recheck-Preflight final composition is unsafe.")
            return false
        }
        return true
    }

    @MainActor
    private func positionReportCorrectionCompletedForAXText(
        in app: XCUIApplication
    ) -> Bool {
        guard automationShard?.shardID == "s10.4.current.ax-text" else {
            return true
        }
        guard shouldPrepareNormalEvidence(
            for: "state.report-correction.completed",
            in: app
        ) else {
            return true
        }

        let screenElements = app.descendants(matching: .any).matching(
            identifier: "s4.5.correction.screen"
        )
        let readyElements = app.descendants(matching: .any).matching(
            identifier: "s4.5.correction.ready"
        )
        let priorReportButtons = app.buttons.matching(
            identifier: "s4.5.correction.prior-report"
        )
        let currentReportButtons = app.buttons.matching(
            identifier: "s4.5.correction.current-report"
        )
        let currentReportScrollViews = app.scrollViews.containing(
            .button,
            identifier: "s4.5.correction.current-report"
        )
        let navigationBars = app.navigationBars
        let tabBars = app.tabBars
        let keyboards = app.keyboards
        let inputViews = app.otherElements.matching(
            NSPredicate(format: "identifier == %@", "inputView")
        )
        let screen = screenElements.firstMatch
        let ready = readyElements.firstMatch
        let priorReport = priorReportButtons.firstMatch
        let currentReport = currentReportButtons.firstMatch
        let scrollView = currentReportScrollViews.firstMatch
        let navigationBar = navigationBars.firstMatch
        let tabBar = tabBars.firstMatch
        let fail: (String) -> Bool = { message in
            XCTFail(message)
            return false
        }
        let isValidFrame: (CGRect) -> Bool = { frame in
            !frame.isNull
                && !frame.isEmpty
                && !frame.isInfinite
                && frame.origin.x.isFinite
                && frame.origin.y.isFinite
                && frame.size.width.isFinite
                && frame.size.height.isFinite
        }
        let exactRouteRelations: () -> [(String, Bool)] = {
            [
                ("applicationForeground", app.state == .runningForeground),
                ("screenElementsCountOne", screenElements.count == 1),
                ("readyElementsCountOne", readyElements.count == 1),
                ("priorReportButtonsCountOne", priorReportButtons.count == 1),
                ("currentReportButtonsCountOne", currentReportButtons.count == 1),
                (
                    "currentReportScrollViewsCountOne",
                    currentReportScrollViews.count == 1
                ),
                ("navigationBarsCountOne", navigationBars.count == 1),
                ("tabBarsCountOne", tabBars.count == 1),
                ("keyboardsCountZero", keyboards.count == 0),
                ("inputViewsCountZero", inputViews.count == 0),
                ("screenExists", screen.exists),
                ("readyExists", ready.exists),
                ("priorReportExists", priorReport.exists),
                ("currentReportExists", currentReport.exists),
                ("scrollViewExists", scrollView.exists),
                ("navigationBarExists", navigationBar.exists),
                ("tabBarExists", tabBar.exists),
                ("screenTypeScrollView", screen.elementType == .scrollView),
                (
                    "screenIdentifier",
                    screen.identifier == "s4.5.correction.screen"
                ),
                ("screenLabelEmpty", screen.label == ""),
                ("screenValueEmpty", (screen.value as? String) == ""),
                ("screenEnabled", screen.isEnabled),
                ("screenHittable", screen.isHittable),
                (
                    "scrollViewTypeScrollView",
                    scrollView.elementType == .scrollView
                ),
                (
                    "scrollViewIdentifier",
                    scrollView.identifier == "s4.5.correction.screen"
                ),
                ("scrollViewLabelEmpty", scrollView.label == ""),
                ("scrollViewValueEmpty", (scrollView.value as? String) == ""),
                ("scrollViewEnabled", scrollView.isEnabled),
                ("scrollViewHittable", scrollView.isHittable),
                (
                    "navigationBarTypeNavigationBar",
                    navigationBar.elementType == .navigationBar
                ),
                (
                    "navigationBarIdentifier",
                    navigationBar.identifier == "Correct report"
                ),
                ("navigationBarLabelEmpty", navigationBar.label == ""),
                (
                    "navigationBarValueEmpty",
                    (navigationBar.value as? String) == ""
                ),
                ("navigationBarEnabled", navigationBar.isEnabled),
                ("navigationBarHittable", navigationBar.isHittable),
                ("tabBarTypeTabBar", tabBar.elementType == .tabBar),
                ("tabBarIdentifierEmpty", tabBar.identifier == ""),
                ("tabBarLabel", tabBar.label == "Tab Bar"),
                ("tabBarValueEmpty", (tabBar.value as? String) == ""),
                ("tabBarEnabled", tabBar.isEnabled),
                ("tabBarHittable", tabBar.isHittable),
                ("readyTypeStaticText", ready.elementType == .staticText),
                (
                    "readyIdentifier",
                    ready.identifier == "s4.5.correction.ready"
                ),
                (
                    "readyLabel",
                    ready.label
                        == "The prior report and evidence remain unchanged."
                ),
                ("readyValueEmpty", (ready.value as? String) == ""),
                ("readyEnabled", ready.isEnabled),
                ("readyHittable", ready.isHittable),
                ("priorReportTypeButton", priorReport.elementType == .button),
                (
                    "priorReportIdentifier",
                    priorReport.identifier == "s4.5.correction.prior-report"
                ),
                ("priorReportLabel", priorReport.label == "View prior report"),
                (
                    "priorReportValueEmpty",
                    (priorReport.value as? String) == ""
                ),
                ("priorReportEnabled", priorReport.isEnabled),
                (
                    "currentReportTypeButton",
                    currentReport.elementType == .button
                ),
                (
                    "currentReportIdentifier",
                    currentReport.identifier == "s4.5.correction.current-report"
                ),
                (
                    "currentReportLabel",
                    currentReport.label == "View corrected report"
                ),
                (
                    "currentReportValueEmpty",
                    (currentReport.value as? String) == ""
                ),
                ("currentReportEnabled", currentReport.isEnabled),
            ]
        }
        let hasExactRoute: () -> Bool = {
            exactRouteRelations().allSatisfy { relation in relation.1 }
        }
        let hasStableRoute: () -> Bool = {
            app.state == .runningForeground
                && screenElements.count == 1
                && readyElements.count == 1
                && priorReportButtons.count == 1
                && currentReportButtons.count == 1
                && currentReportScrollViews.count == 1
                && navigationBars.count == 1
                && tabBars.count == 1
                && keyboards.count == 0
                && inputViews.count == 0
                && screen.exists
                && ready.exists
                && priorReport.exists
                && currentReport.exists
                && scrollView.exists
                && navigationBar.exists
                && tabBar.exists
                && screen.elementType == .scrollView
                && screen.identifier == "s4.5.correction.screen"
                && screen.isEnabled
                && scrollView.elementType == .scrollView
                && scrollView.identifier == "s4.5.correction.screen"
                && scrollView.isEnabled
                && navigationBar.elementType == .navigationBar
                && navigationBar.identifier == "Correct report"
                && navigationBar.isEnabled
                && tabBar.elementType == .tabBar
                && tabBar.isEnabled
                && ready.elementType == .staticText
                && ready.identifier == "s4.5.correction.ready"
                && ready.isEnabled
                && priorReport.elementType == .button
                && priorReport.identifier == "s4.5.correction.prior-report"
                && priorReport.isEnabled
                && currentReport.elementType == .button
                && currentReport.identifier == "s4.5.correction.current-report"
                && currentReport.isEnabled
        }
        guard hasStableRoute() else {
            return fail("AX-text Report-correction-completed route is ambiguous.")
        }
        let frozenApplicationFrame = app.frame
        let frozenScreenFrame = screen.frame
        let frozenScrollFrame = scrollView.frame
        let frozenNavigationFrame = navigationBar.frame
        let frozenTabFrame = tabBar.frame
        let frozenReadyFrame = ready.frame
        let frozenPriorFrame = priorReport.frame
        let frozenCurrentFrame = currentReport.frame
        guard [
            frozenApplicationFrame,
            frozenScreenFrame,
            frozenScrollFrame,
            frozenNavigationFrame,
            frozenTabFrame,
        ].allSatisfy(isValidFrame) else {
            return fail(
                "AX-text Report-correction-completed container frames are invalid."
            )
        }
        let finalStrictRouteRelations: () -> [(String, Bool)] = {
            exactRouteRelations() + [
                ("applicationFrameFrozen", app.frame == frozenApplicationFrame),
                (
                    "navigationFrameFrozen",
                    navigationBar.frame == frozenNavigationFrame
                ),
                ("tabFrameFrozen", tabBar.frame == frozenTabFrame),
            ]
        }
        let hasFinalStrictRoute: () -> Bool = {
            finalStrictRouteRelations().allSatisfy { relation in relation.1 }
        }

        let visualClearance: CGFloat = 8
        let receiverInset: CGFloat = 24
        let minimumGestureDistance: CGFloat = 44
        let maximumGestureCount = 2
        var measuredUndertravel: CGFloat = 0
        var positioningDirection: CGFloat?
        var completedGestureCount = 0

        func liveComposition() -> (
            scrollFrame: CGRect,
            safeTop: CGFloat,
            safeBottom: CGFloat,
            readyFrame: CGRect,
            priorFrame: CGRect,
            currentFrame: CGRect,
            minimumShift: CGFloat,
            maximumShift: CGFloat
        )? {
            guard hasStableRoute() else { return nil }
            let applicationFrame = app.frame
            let screenFrame = screen.frame
            let scrollFrame = scrollView.frame
            let navigationFrame = navigationBar.frame
            let tabFrame = tabBar.frame
            let readyFrame = ready.frame
            let priorFrame = priorReport.frame
            let currentFrame = currentReport.frame
            guard [
                applicationFrame,
                screenFrame,
                scrollFrame,
                navigationFrame,
                tabFrame,
                readyFrame,
                priorFrame,
                currentFrame,
            ].allSatisfy(isValidFrame),
                  screenFrame == scrollFrame else {
                return nil
            }
            let safeTop = max(scrollFrame.minY, navigationFrame.maxY)
                + visualClearance
            let safeBottom = min(
                scrollFrame.maxY,
                min(applicationFrame.maxY, tabFrame.minY)
            )
                - visualClearance
            let minimumShift = max(
                safeTop - readyFrame.minY,
                safeTop - currentFrame.minY
            )
            let maximumShift = min(
                safeBottom - readyFrame.maxY,
                safeBottom - currentFrame.maxY
            )
            guard safeTop.isFinite,
                  safeBottom.isFinite,
                  safeTop < safeBottom,
                  minimumShift.isFinite,
                  maximumShift.isFinite,
                  minimumShift <= maximumShift,
                  readyFrame.maxY <= priorFrame.minY,
                  priorFrame.maxY <= currentFrame.minY else {
                return nil
            }
            return (
                scrollFrame,
                safeTop,
                safeBottom,
                readyFrame,
                priorFrame,
                currentFrame,
                minimumShift,
                maximumShift
            )
        }

        typealias CompletedComposition = (
            scrollFrame: CGRect,
            safeTop: CGFloat,
            safeBottom: CGFloat,
            readyFrame: CGRect,
            priorFrame: CGRect,
            currentFrame: CGRect,
            minimumShift: CGFloat,
            maximumShift: CGFloat
        )
        func acceptingCompositionRelations(
            _ geometry: CompletedComposition?
        ) -> [(String, Bool)] {
            [
                ("hasFinalStrictRoute", hasFinalStrictRoute()),
                (
                    "readyMinYAtOrBelowSafeTop",
                    geometry.map { $0.readyFrame.minY >= $0.safeTop } ?? false
                ),
                (
                    "readyMaxYAtOrAboveSafeBottom",
                    geometry.map { $0.readyFrame.maxY <= $0.safeBottom } ?? false
                ),
                (
                    "priorMinYAtOrBelowSafeTop",
                    geometry.map { $0.priorFrame.minY >= $0.safeTop } ?? false
                ),
                (
                    "priorMaxYAtOrAboveSafeBottom",
                    geometry.map { $0.priorFrame.maxY <= $0.safeBottom } ?? false
                ),
                (
                    "currentMinYAtOrBelowSafeTop",
                    geometry.map { $0.currentFrame.minY >= $0.safeTop } ?? false
                ),
                (
                    "currentMaxYAtOrAboveSafeBottom",
                    geometry.map { $0.currentFrame.maxY <= $0.safeBottom } ?? false
                ),
                (
                    "readyWhollyAbovePrior",
                    geometry.map { $0.readyFrame.maxY <= $0.priorFrame.minY } ?? false
                ),
                (
                    "priorWhollyAboveCurrent",
                    geometry.map { $0.priorFrame.maxY <= $0.currentFrame.minY } ?? false
                ),
                (
                    "priorWidthAtLeastMinimum",
                    geometry.map {
                        $0.priorFrame.width >= minimumGestureDistance
                    } ?? false
                ),
                (
                    "priorHeightAtLeastMinimum",
                    geometry.map {
                        $0.priorFrame.height >= minimumGestureDistance
                    } ?? false
                ),
                (
                    "currentWidthAtLeastMinimum",
                    geometry.map {
                        $0.currentFrame.width >= minimumGestureDistance
                    } ?? false
                ),
                (
                    "currentHeightAtLeastMinimum",
                    geometry.map {
                        $0.currentFrame.height >= minimumGestureDistance
                    } ?? false
                ),
                ("priorReportEnabled", priorReport.isEnabled),
                ("priorReportHittable", priorReport.isHittable),
                ("currentReportEnabled", currentReport.isEnabled),
                ("currentReportHittable", currentReport.isHittable),
            ]
        }
        func isAcceptingComposition(
            _ geometry: CompletedComposition
        ) -> Bool {
            acceptingCompositionRelations(geometry)
                .allSatisfy { relation in relation.1 }
        }
        func diagnoseSegment3FinalComposition(
            _ geometry: CompletedComposition?
        ) -> Bool {
            guard automationSegment == .segment3,
                  let shard = automationShard,
                  shard.shardID == "s10.4.current.ax-text",
                  automationSegment.replayCount == 22,
                  automationSegment.ownedStartOrdinal == 51,
                  automationSegment.ownedCount == 17,
                  automationSegment.finalOrdinal == 67,
                  segmentedRouteStateCursor == 55,
                  migratedStateIDs
                    == Array(Self.segmentedRouteStateIDs[50..<55]),
                  !automatedSegmentFinished,
                  app.state == .runningForeground else {
                XCTFail(
                    "S10.4 AX-text report-correction completed final-composition diagnostic context drifted"
                )
                return false
            }
            let publicNodeObject: (XCUIElement) -> [String: Any] = { element in
                [
                    "exists": element.exists,
                    "isEnabled": element.isEnabled,
                    "isHittable": element.isHittable,
                    "identifier": element.identifier,
                    "label": element.label,
                    "value": (element.value as? String).map { $0 as Any }
                        ?? NSNull(),
                    "elementTypeRawValue": element.elementType.rawValue,
                    "elementTypeDescription": String(describing: element.elementType),
                    "frame": self.auditFrameObject(element.frame),
                ]
            }
            let publicQueryObject: (XCUIElementQuery) -> [String: Any] = { query in
                let actualCount = query.count
                return [
                    "count": actualCount,
                    "elements": (0..<actualCount).map { index in
                        publicNodeObject(query.element(boundBy: index))
                    },
                ]
            }
            let relationObject: ([(String, Bool)]) -> [String: Bool] = {
                relations in
                Dictionary(uniqueKeysWithValues: relations)
            }
            let nullableScalar: (CGFloat?) -> Any = { value in
                guard let value else { return NSNull() }
                return Double(value)
            }
            let context: [String: Any] = [
                "schemaVersion": 1,
                "acceptanceEligible": false,
                "shardID": shard.shardID,
                "requirementID": shard.requirementID,
                "deviceProfileID": shard.deviceProfileID,
                "segmentID": automationSegment.rawValue,
                "segmentReplayCount": automationSegment.replayCount,
                "segmentOwnedCount": automationSegment.ownedCount,
                "segmentFinalOrdinal": automationSegment.finalOrdinal,
                "segmentStateCursor": segmentedRouteStateCursor,
                "migratedStateIDs": migratedStateIDs,
                "stateID": "state.report-correction.completed",
                "stateOrdinal": 56,
                "predecessorStateID": "state.report-correction.saving",
                "predecessorOrdinal": 55,
                "successorStateID": "state.paywall.unavailable",
                "successorOrdinal": 57,
                "applicationState": String(describing: app.state),
                "applicationStateRawValue": app.state.rawValue,
                "applicationForeground": app.state == .runningForeground,
                "applicationFrame": self.auditFrameObject(app.frame),
                "queries": [
                    "screenElements": publicQueryObject(screenElements),
                    "readyElements": publicQueryObject(readyElements),
                    "priorReportButtons": publicQueryObject(priorReportButtons),
                    "currentReportButtons": publicQueryObject(currentReportButtons),
                    "currentReportScrollViews": publicQueryObject(
                        currentReportScrollViews
                    ),
                    "navigationBars": publicQueryObject(navigationBars),
                    "tabBars": publicQueryObject(tabBars),
                    "keyboards": publicQueryObject(keyboards),
                    "inputViews": publicQueryObject(inputViews),
                ],
                "frozenFrames": [
                    "application": self.auditFrameObject(frozenApplicationFrame),
                    "screen": self.auditFrameObject(frozenScreenFrame),
                    "scrollView": self.auditFrameObject(frozenScrollFrame),
                    "navigationBar": self.auditFrameObject(frozenNavigationFrame),
                    "tabBar": self.auditFrameObject(frozenTabFrame),
                    "ready": self.auditFrameObject(frozenReadyFrame),
                    "priorReport": self.auditFrameObject(frozenPriorFrame),
                    "currentReport": self.auditFrameObject(frozenCurrentFrame),
                ],
                "currentFrames": [
                    "application": self.auditFrameObject(app.frame),
                    "screen": self.auditFrameObject(screen.frame),
                    "scrollView": self.auditFrameObject(scrollView.frame),
                    "navigationBar": self.auditFrameObject(navigationBar.frame),
                    "tabBar": self.auditFrameObject(tabBar.frame),
                    "ready": self.auditFrameObject(ready.frame),
                    "priorReport": self.auditFrameObject(priorReport.frame),
                    "currentReport": self.auditFrameObject(currentReport.frame),
                ],
                "finalRouteRelations": relationObject(
                    finalStrictRouteRelations()
                ),
                "acceptingCompositionRelations": relationObject(
                    acceptingCompositionRelations(geometry)
                ),
                "safeTop": nullableScalar(geometry?.safeTop),
                "safeBottom": nullableScalar(geometry?.safeBottom),
                "minimumShift": nullableScalar(geometry?.minimumShift),
                "maximumShift": nullableScalar(geometry?.maximumShift),
                "completedGestureCount": completedGestureCount,
                "measuredUndertravel": Double(measuredUndertravel),
                "positioningDirection": nullableScalar(positioningDirection),
            ]
            guard JSONSerialization.isValidJSONObject(context),
                  let contextData = try? JSONSerialization.data(
                    withJSONObject: context,
                    options: [.sortedKeys]
                  ),
                  let contextText = String(data: contextData, encoding: .utf8),
                  !contextText.contains("\n") else {
                XCTFail(
                    "S10.4 AX-text report-correction completed final-composition diagnostic JSON is invalid"
                )
                return false
            }
            self.printJSONLine(
                prefix:
                    "S10_4_AX_TEXT_REPORT_CORRECTION_COMPLETED_FINAL_COMPOSITION_DIAGNOSTIC",
                object: context
            )
            let appAttachment = XCTAttachment(
                screenshot: app.screenshot()
            )
            appAttachment.name =
                "S10.4 AX-text report-correction completed final composition diagnostic app"
            appAttachment.lifetime = .keepAlways
            add(appAttachment)
            let treeAttachment = XCTAttachment(string: app.debugDescription)
            treeAttachment.name =
                "S10.4 AX-text report-correction completed final composition diagnostic tree"
            treeAttachment.lifetime = .keepAlways
            add(treeAttachment)
            let contextAttachment = XCTAttachment(string: contextText)
            contextAttachment.name =
                "S10.4 AX-text report-correction completed final composition diagnostic context"
            contextAttachment.lifetime = .keepAlways
            add(contextAttachment)
            XCTFail(
                "S10.4 AX-text report-correction completed final-composition diagnostic is nonaccepting"
            )
            return false
        }

        while completedGestureCount < maximumGestureCount {
            guard let geometry = liveComposition() else {
                return fail(
                    "AX-text Report-correction-completed interval is infeasible."
                )
            }
            if isAcceptingComposition(geometry) {
                return true
            }
            guard !(geometry.minimumShift <= 0
                        && geometry.maximumShift >= 0) else {
                return fail(
                    "AX-text Report-correction-completed composition is incomplete inside its feasible interval."
                )
            }

            let midpointDistance = (
                geometry.minimumShift + geometry.maximumShift
            ) / 2
            let targetDistance = completedGestureCount == 0
                ? (midpointDistance > 0
                    ? geometry.maximumShift
                    : geometry.minimumShift)
                : midpointDistance
            let direction: CGFloat = targetDistance > 0 ? 1 : -1
            if let positioningDirection {
                guard positioningDirection == direction else {
                    return fail(
                        "AX-text Report-correction-completed positioning reversed direction."
                    )
                }
            } else {
                positioningDirection = direction
            }
            let receiverTop = geometry.safeTop + receiverInset
            let receiverBottom = geometry.safeBottom - receiverInset
            let receiverCapacity = receiverBottom - receiverTop
            guard receiverCapacity >= minimumGestureDistance else {
                return fail(
                    "AX-text Report-correction-completed gesture receiver is too small."
                )
            }
            let compensatedMagnitude =
                abs(targetDistance) + measuredUndertravel
            let requestedMagnitude = completedGestureCount == 0
                ? max(compensatedMagnitude, minimumGestureDistance)
                : compensatedMagnitude
            let dragMagnitude = min(requestedMagnitude, receiverCapacity)
            let dragDistance = direction * dragMagnitude
            let dragStartY = direction > 0 ? receiverTop : receiverBottom
            let dragStartPoint = CGPoint(
                x: geometry.scrollFrame.minX + receiverInset,
                y: dragStartY
            )
            let dragEndPoint = CGPoint(
                x: dragStartPoint.x,
                y: dragStartPoint.y + dragDistance
            )
            let isInsideSafeReceiver: (CGPoint) -> Bool = { point in
                geometry.scrollFrame.contains(point)
                    && point.x >= geometry.scrollFrame.minX
                    && point.x <= geometry.scrollFrame.maxX
                    && point.y >= receiverTop
                    && point.y <= receiverBottom
            }
            guard isInsideSafeReceiver(dragStartPoint),
                  isInsideSafeReceiver(dragEndPoint),
                  !geometry.readyFrame.contains(dragStartPoint),
                  !geometry.readyFrame.contains(dragEndPoint),
                  !geometry.priorFrame.contains(dragStartPoint),
                  !geometry.priorFrame.contains(dragEndPoint),
                  !geometry.currentFrame.contains(dragStartPoint),
                  !geometry.currentFrame.contains(dragEndPoint) else {
                return fail(
                    "AX-text Report-correction-completed gesture left the safe receiver or intersected a target."
                )
            }
            let applicationOrigin = app.coordinate(
                withNormalizedOffset: CGVector(dx: 0, dy: 0)
            )
            let dragStart = applicationOrigin.withOffset(
                CGVector(
                    dx: dragStartPoint.x - frozenApplicationFrame.minX,
                    dy: dragStartPoint.y - frozenApplicationFrame.minY
                )
            )
            let dragEnd = applicationOrigin.withOffset(
                CGVector(
                    dx: dragEndPoint.x - frozenApplicationFrame.minX,
                    dy: dragEndPoint.y - frozenApplicationFrame.minY
                )
            )
            let readyBeforeDrag = geometry.readyFrame.minY
            let priorBeforeDrag = geometry.priorFrame.minY
            let currentBeforeDrag = geometry.currentFrame.minY
            dragStart.press(
                forDuration: 0.2,
                thenDragTo: dragEnd,
                withVelocity: .slow,
                thenHoldForDuration: 0.2
            )
            completedGestureCount += 1

            guard let afterDrag = liveComposition() else {
                return fail(
                    "AX-text Report-correction-completed route changed after positioning."
                )
            }
            let readyShift = afterDrag.readyFrame.minY - readyBeforeDrag
            let priorShift = afterDrag.priorFrame.minY - priorBeforeDrag
            let currentShift = afterDrag.currentFrame.minY - currentBeforeDrag
            guard readyShift * dragDistance > 0,
                  priorShift * dragDistance > 0,
                  currentShift * dragDistance > 0,
                  abs(readyShift - priorShift) <= 1,
                  abs(readyShift - currentShift) <= 1 else {
                return fail(
                    "AX-text Report-correction-completed gesture made no rigid signed progress."
                )
            }
            measuredUndertravel = max(
                0,
                abs(dragDistance) - abs(currentShift)
            )
        }

        let terminalGeometry = liveComposition()
        guard let finalGeometry = terminalGeometry,
              isAcceptingComposition(finalGeometry) else {
            if automationSegment == .segment3 {
                return diagnoseSegment3FinalComposition(terminalGeometry)
            }
            return fail(
                "AX-text Report-correction-completed final composition is unsafe."
            )
        }
        return true
    }

    @MainActor
    private func completeFocusedDiagnosticProbe(
        targetStateID: String,
        setupTarget: String,
        observationPhase: String,
        observedStateID: String,
        in app: XCUIApplication
    ) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "S10_4_DIAGNOSTIC screenshot \(targetStateID)"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let rawTree = Data(app.debugDescription.utf8)
        let retainedTree = rawTree.prefix(262_144)
        let tree = XCTAttachment(
            data: Data(retainedTree),
            uniformTypeIdentifier: "public.plain-text"
        )
        tree.name = "S10_4_DIAGNOSTIC tree \(targetStateID)"
        tree.lifetime = .keepAlways
        add(tree)
        printJSONLine(prefix: "S10_4_DIAGNOSTIC", object: [
            "diagnosticOnly": true,
            "equivalenceEstablished": false,
            "event": "observation-complete",
            "feedsAcceptanceAssembler": false,
            "finalAcceptanceEligible": false,
            "observedStateID": observedStateID,
            "observationPhase": observationPhase,
            "omittedCaptureStateIDs": Self.segmentedRouteStateIDs,
            "probeID": diagnosticProbe?.rawValue ?? "",
            "retainedTreeBytes": retainedTree.count,
            "skippedPredecessorCaptureStateIDs":
                diagnosticSkippedPredecessorCaptureStateIDs(
                    excluding: targetStateID
                ),
            "setupTarget": setupTarget,
            "targetAnchorStateID": targetStateID,
            "originalTreeBytes": rawTree.count,
            "treeTruncated": rawTree.count > retainedTree.count,
            "visitedSetupCaptureStateIDs": diagnosticVisitedSetupCaptureStateIDs,
        ])
    }

    @MainActor
    private func completeFocusedDiagnosticPreflight(
        in app: XCUIApplication
    ) throws {
        completeFocusedDiagnosticProbe(
            targetStateID: "state.check-preflight.ready",
            setupTarget: "s3.preflight.time-zone",
            observationPhase: "pre-audit-target-ready",
            observedStateID: "state.check-preflight.ready",
            in: app
        )
        // Keep the captured preflight evidence keyboard-visible, but run the
        // native audit against the app surface after the iOS 18 keyboard is
        // dismissed. The system keyboard/QuickPath window is not app-owned
        // content and can make XCTest's strict audit time out before it emits
        // any app issue.
        dismissKeyboard(in: app)
        printJSONLine(prefix: "S10_4_DIAGNOSTIC", object: [
            "diagnosticOnly": true,
            "equivalenceEstablished": false,
            "event": "strict-native-audit-start",
            "feedsAcceptanceAssembler": false,
            "finalAcceptanceEligible": false,
            "probeID": DiagnosticProbe.minimumPreflight.rawValue,
            "targetAnchorStateID": "state.check-preflight.ready",
        ])
        var observedIssueCount = 0
        do {
            try app.performAccessibilityAudit(for: .contrast) { issue in
                observedIssueCount += 1
                if observedIssueCount <= 3 {
                    self.printJSONLine(prefix: "S10_4_DIAGNOSTIC", object: [
                        "diagnosticOnly": true,
                        "equivalenceEstablished": false,
                        "event": "strict-native-audit-issue-observed",
                        "feedsAcceptanceAssembler": false,
                        "finalAcceptanceEligible": false,
                        "probeID": DiagnosticProbe.minimumPreflight.rawValue,
                        "targetAnchorStateID": "state.check-preflight.ready",
                        "issueOrdinal": observedIssueCount,
                        "auditTypeRawValue": String(issue.auditType.rawValue),
                        "compactDescription": issue.compactDescription,
                        "detailedDescription": issue.detailedDescription,
                        "elementIdentifier": issue.element?.identifier ?? "",
                        "elementTypeDescription": issue.element.map {
                            String(describing: $0.elementType)
                        } ?? "",
                    ])
                }
                return true
            }
            printJSONLine(prefix: "S10_4_DIAGNOSTIC", object: [
                "diagnosticOnly": true,
                "equivalenceEstablished": false,
                "event": "strict-native-audit-completed",
                "feedsAcceptanceAssembler": false,
                "finalAcceptanceEligible": false,
                "probeID": DiagnosticProbe.minimumPreflight.rawValue,
                "targetAnchorStateID": "state.check-preflight.ready",
                "observedIssueCount": observedIssueCount,
            ])
        } catch {
            printJSONLine(prefix: "S10_4_DIAGNOSTIC", object: [
                "diagnosticOnly": true,
                "equivalenceEstablished": false,
                "event": "strict-native-audit-error",
                "feedsAcceptanceAssembler": false,
                "finalAcceptanceEligible": false,
                "probeID": DiagnosticProbe.minimumPreflight.rawValue,
                "targetAnchorStateID": "state.check-preflight.ready",
                "observedIssueCount": observedIssueCount,
                "error": String(describing: error),
            ])
            throw error
        }
        throw AutomationConfigurationError.invalid(
            "S10.4 preflight diagnostic completed nonaccepting"
        )
    }

    private func diagnosticSkippedPredecessorCaptureStateIDs(
        excluding targetStateID: String
    ) -> [String] {
        diagnosticVisitedSetupCaptureStateIDs.filter { $0 != targetStateID }
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
        if diagnosticProbe != nil {
            diagnosticVisitedSetupCaptureStateIDs.append(stateID)
            return
        }
        if replaySegmentPrefixIfNeeded(
            stateID,
            in: app,
            file: file,
            line: line
        ) {
            return
        }
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
            let stateIssueLimit =
                shard.shardID == "s10.4.current.ax-text"
                && (
                    stateID == "state.check-preflight.ready"
                        || stateID == "state.reports-index.ready"
                ) ? 2 : 1
            guard eligibleExceptions.count <= stateIssueLimit else {
                throw AutomationConfigurationError.invalid(
                    "S10.4 contrast exception eligibility is ambiguous"
                )
            }

            var matchedExceptions: [ContrastAuditExceptionSignature] = []
            if !eligibleExceptions.isEmpty {
                var observedIssueCount = 0
                try app.performAccessibilityAudit(for: .contrast) { issue in
                    observedIssueCount += 1
                    guard observedIssueCount <= stateIssueLimit,
                          let auditedElement = issue.element else {
                        return false
                    }
                    let matchingExceptions = eligibleExceptions.filter { signature in
                        self.isActive(signature)
                            && String(issue.auditType.rawValue)
                                == signature.auditTypeRawValue
                            && issue.compactDescription == signature.compactDescription
                            && issue.detailedDescription == signature.detailedDescription
                            && auditedElement.identifier == signature.elementIdentifier
                            && auditedElement.label == signature.elementLabel
                            && String(describing: auditedElement.elementType)
                                == signature.elementTypeDescription
                            && auditedElement.frame == signature.elementFrame
                            && app.frame == signature.applicationFrame
                    }
                    guard matchingExceptions.count == 1,
                          let matchedException = matchingExceptions.first,
                          !matchedExceptions.contains(where: {
                              $0.issueID == matchedException.issueID
                          }) else {
                        return false
                    }
                    matchedExceptions.append(matchedException)
                    return true
                }
                guard observedIssueCount == matchedExceptions.count,
                      observedIssueCount <= stateIssueLimit else {
                    throw AutomationConfigurationError.invalid(
                        "S10.4 contrast exception exceeded its exact state issue limit"
                    )
                }
            } else if (
                shard.shardID == "s10.4.minimum.minimum-os"
                    && stateID == "state.work.validation-error"
            ) || (
                shard.shardID == "s10.4.minimum.rtl"
                    && stateID == "state.check-preflight.ready"
            ) {
                var observedIssueCount = 0
                try app.performAccessibilityAudit(for: .contrast) { issue in
                    observedIssueCount += 1
                    if observedIssueCount <= 3 {
                        let compactDescription = issue.compactDescription
                        let detailedDescription = issue.detailedDescription
                        var observation: [String: Any] = [
                            "schemaVersion": 1,
                            "acceptanceEligible": false,
                            "shardID": shard.shardID,
                            "requirementID": shard.requirementID,
                            "deviceProfileID": shard.deviceProfileID,
                            "stateID": stateID,
                            "issueOrdinal": observedIssueCount,
                            "observationPhase": "issue-metadata",
                            "auditTypeRawValue": String(issue.auditType.rawValue),
                            "compactDescription": String(compactDescription.prefix(4_096)),
                            "compactDescriptionTruncated": compactDescription.count > 4_096,
                            "detailedDescription": String(detailedDescription.prefix(4_096)),
                            "detailedDescriptionTruncated": detailedDescription.count > 4_096,
                            "elementAvailable": NSNull(),
                            "elementIdentifier": NSNull(),
                            "elementIdentifierTruncated": NSNull(),
                            "elementLabel": NSNull(),
                            "elementLabelTruncated": NSNull(),
                            "elementTypeRawValue": NSNull(),
                            "elementTypeDescription": NSNull(),
                            "elementFrame": NSNull(),
                            "elementFrameFinite": NSNull(),
                        ]
                        self.printJSONLine(
                            prefix: "S10_4_NATIVE_CONTRAST_FAILURE_OBSERVATION",
                            object: observation
                        )
                        if let auditedElement = issue.element {
                            let identifier = auditedElement.identifier
                            let label = auditedElement.label
                            let elementType = auditedElement.elementType
                            let elementFrame = auditedElement.frame
                            let frameIsFinite = elementFrame.origin.x.isFinite
                                && elementFrame.origin.y.isFinite
                                && elementFrame.size.width.isFinite
                                && elementFrame.size.height.isFinite
                            observation["elementAvailable"] = true
                            observation["elementIdentifier"] = String(identifier.prefix(4_096))
                            observation["elementIdentifierTruncated"] = identifier.count > 4_096
                            observation["elementLabel"] = String(label.prefix(4_096))
                            observation["elementLabelTruncated"] = label.count > 4_096
                            observation["elementTypeRawValue"] = elementType.rawValue
                            observation["elementTypeDescription"] = String(describing: elementType)
                            observation["elementFrameFinite"] = frameIsFinite
                            if frameIsFinite {
                                observation["elementFrame"] = self.auditFrameObject(elementFrame)
                            }
                        } else {
                            observation["elementAvailable"] = false
                        }
                        observation["observationPhase"] = "element-observation"
                        self.printJSONLine(
                            prefix: "S10_4_NATIVE_CONTRAST_FAILURE_OBSERVATION",
                            object: observation
                        )
                    }
                    return false
                }
            } else {
                try app.performAccessibilityAudit(for: .contrast)
            }
            matchedExceptions.sort { $0.issueID < $1.issueID }
            let expectedUniqueMetadataCount = matchedExceptions.isEmpty ? 0 : 1
            guard Set(matchedExceptions.map(\.issueID)).count == matchedExceptions.count,
                  Set(matchedExceptions.map(\.owner)).count
                    == expectedUniqueMetadataCount,
                  Set(matchedExceptions.map(\.expiresAt)).count
                    == expectedUniqueMetadataCount,
                  matchedExceptions.allSatisfy({ $0.stateID == stateID }),
                  matchedExceptions.allSatisfy({ isActive($0) }) else {
                throw AutomationConfigurationError.invalid(
                    "S10.4 contrast exception aggregation is ambiguous or expired"
                )
            }
            if !matchedExceptions.isEmpty {
                automationContrastExceptions[stateID] = matchedExceptions
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
                "result": matchedExceptions.isEmpty ? "PASS" : "EXCEPTION",
                "evidenceID": contrastEvidenceID,
                "axTreeSHA256": axTreeDigest,
                "audit": "XCUIAccessibilityAuditType.contrast",
                "exceptionIssueID": "",
                "exceptionOwner": "",
                "exceptionExpiresAt": "",
                "exceptionRationale": "",
                "ignoredAuditIssues": matchedExceptions.map {
                    self.publicAuditSignatureObject($0)
                },
            ]
            if let firstMatchedException = matchedExceptions.first {
                contrastEvidence["exceptionIssueID"] = matchedExceptions
                    .map(\.issueID)
                    .joined(separator: " | ")
                contrastEvidence["exceptionOwner"] = firstMatchedException.owner
                contrastEvidence["exceptionExpiresAt"] = firstMatchedException.expiresAt
                contrastEvidence["exceptionRationale"] = matchedExceptions
                    .map(\.rationale)
                    .joined(separator: " | ")
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

    @MainActor
    private func shouldPrepareNormalEvidence(
        for stateID: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        guard automationSegment != .none else { return true }
        guard automationShard?.shardID == "s10.4.current.ax-text" else {
            XCTFail(
                "Only the frozen AX-text shard may prepare segmented evidence",
                file: file,
                line: line
            )
            return false
        }
        guard Self.segmentedRouteStateIDs.count == 67,
              Set(Self.segmentedRouteStateIDs).count == 67,
              segmentedRouteStateCursor < Self.segmentedRouteStateIDs.count else {
            XCTFail(
                "The segmented evidence-preparation cursor is outside the frozen inventory",
                file: file,
                line: line
            )
            return false
        }
        guard Self.segmentedRouteStateIDs[segmentedRouteStateCursor] == stateID else {
            XCTFail(
                "Segmented evidence preparation is out of order at ordinal "
                    + "\(segmentedRouteStateCursor + 1)",
                file: file,
                line: line
            )
            return false
        }
        guard segmentedRouteStateCursor < automationSegment.replayCount
                || segmentedRouteStateCursor
                    >= automationSegment.ownedStartOrdinal - 1 else {
            XCTFail(
                "Segmented evidence preparation entered an unowned resume gap",
                file: file,
                line: line
            )
            return false
        }
        guard app.state == .runningForeground else {
            XCTFail(
                "Segmented evidence preparation requires the foreground route",
                file: file,
                line: line
            )
            return false
        }
        return segmentedRouteStateCursor >= automationSegment.replayCount
    }

    @MainActor
    private func replaySegmentPrefixIfNeeded(
        _ stateID: String,
        in app: XCUIApplication,
        file: StaticString,
        line: UInt
    ) -> Bool {
        guard automationSegment != .none else { return false }
        guard let shard = automationShard,
              shard.shardID == "s10.4.current.ax-text" else {
            XCTFail(
                "Only the frozen AX-text shard may enter a segmented route",
                file: file,
                line: line
            )
            return true
        }
        guard Self.segmentedRouteStateIDs.count == 67,
              Set(Self.segmentedRouteStateIDs).count == 67 else {
            XCTFail(
                "The frozen segmented route must contain 67 unique states",
                file: file,
                line: line
            )
            return true
        }
        guard segmentedRouteStateCursor < Self.segmentedRouteStateIDs.count else {
            XCTFail(
                "The segmented route advanced beyond the frozen state inventory",
                file: file,
                line: line
            )
            return true
        }

        let expectedStateID = Self.segmentedRouteStateIDs[segmentedRouteStateCursor]
        guard stateID == expectedStateID else {
            XCTFail(
                "The segmented route order drifted at ordinal "
                    + "\(segmentedRouteStateCursor + 1): expected "
                    + "\(expectedStateID), observed \(stateID)",
                file: file,
                line: line
            )
            return true
        }
        guard app.state == .runningForeground else {
            XCTFail(
                "The segmented route is not foreground at state \(stateID)",
                file: file,
                line: line
            )
            return true
        }

        segmentedRouteStateCursor += 1
        guard segmentedRouteStateCursor <= automationSegment.finalOrdinal else {
            XCTFail(
                "The segmented route advanced beyond \(automationSegment.rawValue)",
                file: file,
                line: line
            )
            return true
        }
        guard segmentedRouteStateCursor <= automationSegment.replayCount
                || segmentedRouteStateCursor >= automationSegment.ownedStartOrdinal else {
            XCTFail(
                "The segmented route entered an unowned resume gap",
                file: file,
                line: line
            )
            return true
        }
        guard segmentedRouteStateCursor <= automationSegment.replayCount else {
            return false
        }

        dismissHostedAppleIntelligenceNotificationIfPresent(
            in: app,
            file: file,
            line: line
        )
        printJSONLine(prefix: "S10_4_SEGMENT_REPLAY", object: [
            "ordinal": segmentedRouteStateCursor,
            "segmentID": automationSegment.rawValue,
            "shardID": shard.shardID,
            "stateID": stateID,
        ])
        return true
    }

    @MainActor
    private func finishAutomatedSegmentIfNeeded(
        after ordinal: Int,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        guard automationSegment != .none,
              ordinal == automationSegment.finalOrdinal else {
            return false
        }
        automatedSegmentFinished = true
        guard automationShard?.shardID == "s10.4.current.ax-text" else {
            XCTFail(
                "Only the frozen AX-text shard may finish a segmented route",
                file: file,
                line: line
            )
            return true
        }
        guard Self.segmentedRouteStateIDs.count == 67,
              Set(Self.segmentedRouteStateIDs).count == 67,
              segmentedRouteStateCursor == ordinal,
              app.state == .runningForeground else {
            XCTFail(
                "The segmented route did not reach its exact foreground boundary",
                file: file,
                line: line
            )
            return true
        }

        let expectedOwnedStateIDs = Array(
            Self.segmentedRouteStateIDs[
                (automationSegment.ownedStartOrdinal - 1)..<automationSegment.finalOrdinal
            ]
        )
        guard expectedOwnedStateIDs.count == automationSegment.ownedCount,
              Set(expectedOwnedStateIDs).count == automationSegment.ownedCount,
              migratedStateIDs == expectedOwnedStateIDs,
              Set(automationAXTreeDigests.keys) == Set(expectedOwnedStateIDs),
              Set(automationContrastExceptions.keys).isSubset(of: Set(expectedOwnedStateIDs)) else {
            XCTFail(
                "The segmented route owned-state evidence is incomplete or out of order",
                file: file,
                line: line
            )
            return true
        }

        let terminal = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        terminal.name = "S10.4 segment terminal \(automationSegment.rawValue) s10.4.current.ax-text"
        terminal.lifetime = .keepAlways
        add(terminal)

        return true
    }

    @MainActor
    private func positionIssueRecheckDueDescriptionForAXText(
        in app: XCUIApplication
    ) -> Bool {
        let descriptionValuePredicate = NSPredicate(
            format: "label == %@",
            "Replaced failed power supply"
        )
        let issueScreens = app.descendants(matching: .any).matching(
            identifier: "s5.1.issue.screen"
        )
        let issueScrollViews = app.scrollViews.containing(
            descriptionValuePredicate
        )
        let issueNavigationBars = app.navigationBars.matching(
            identifier: "Recheck due"
        )
        let tabBars = app.tabBars
        let startRecheckButtons = app.buttons.matching(
            identifier: "s5.2.issue.start-recheck"
        )
        let workRecords = app.descendants(matching: .any).matching(
            identifier: "s5.1.issue.work-record"
        )
        let workDates = app.descendants(matching: .any).matching(
            identifier: "s5.1.issue.work-date"
        )
        let workDescriptions = app.descendants(matching: .any).matching(
            identifier: "s5.1.issue.work-description"
        )
        let workDescriptionsContainingValue = workDescriptions.containing(
            descriptionValuePredicate
        )
        let descriptionValueTexts = app.staticTexts.matching(
            descriptionValuePredicate
        )
        let workPhotos = app.images.matching(
            identifier: "s5.1.issue.work-photo"
        )
        let issueScreen = issueScreens.firstMatch
        let issueScrollView = issueScrollViews.firstMatch
        let issueNavigationBar = issueNavigationBars.firstMatch
        let tabBar = tabBars.firstMatch
        let startRecheckButton = startRecheckButtons.firstMatch
        let workRecord = workRecords.firstMatch
        let workDate = workDates.firstMatch
        let workDescription = workDescriptions.firstMatch
        let descriptionValueText = descriptionValueTexts.firstMatch
        let workPhoto = workPhotos.firstMatch
        let isValidFrame: (CGRect) -> Bool = { frame in
            !frame.isNull
                && !frame.isEmpty
                && !frame.isInfinite
                && frame.origin.x.isFinite
                && frame.origin.y.isFinite
                && frame.size.width.isFinite
                && frame.size.height.isFinite
        }
        let hasExactIdentity: () -> Bool = {
            app.state == .runningForeground
                && issueScreens.count == 1
                && issueScrollViews.count == 1
                && issueNavigationBars.count == 1
                && tabBars.count == 1
                && startRecheckButtons.count == 1
                && workRecords.count == 1
                && workDates.count == 1
                && workDescriptions.count == 1
                && workDescriptionsContainingValue.count == 1
                && descriptionValueTexts.count == 1
                && workPhotos.count == 1
                && issueScreen.exists
                && issueScreen.elementType == .scrollView
                && issueScreen.identifier == "s5.1.issue.screen"
                && (issueScreen.value as? String) == ""
                && issueScrollView.exists
                && issueScrollView.elementType == .scrollView
                && issueScrollView.identifier == "s5.1.issue.screen"
                && (issueScrollView.value as? String) == ""
                && issueNavigationBar.exists
                && issueNavigationBar.elementType == .navigationBar
                && issueNavigationBar.identifier == "Recheck due"
                && (issueNavigationBar.value as? String) == ""
                && tabBar.exists
                && tabBar.elementType == .tabBar
                && tabBar.identifier.isEmpty
                && tabBar.label == "Tab Bar"
                && (tabBar.value as? String) == ""
                && startRecheckButton.exists
                && startRecheckButton.elementType == .button
                && startRecheckButton.identifier == "s5.2.issue.start-recheck"
                && startRecheckButton.label == "Start recheck"
                && (startRecheckButton.value as? String) == ""
                && workRecord.exists
                && workRecord.elementType == .other
                && workRecord.identifier == "s5.1.issue.work-record"
                && (workRecord.value as? String) == ""
                && workDate.exists
                && workDate.elementType == .staticText
                && workDate.identifier == "s5.1.issue.work-date"
                && !workDate.label.isEmpty
                && (workDate.value as? String) == ""
                && workDescription.exists
                && workDescription.elementType == .staticText
                && workDescription.identifier == "s5.1.issue.work-description"
                && workDescription.label
                    == "Short description, Replaced failed power supply"
                && (workDescription.value as? String) == ""
                && descriptionValueText.exists
                && descriptionValueText.elementType == .staticText
                && descriptionValueText.identifier.isEmpty
                && descriptionValueText.label == "Replaced failed power supply"
                && (descriptionValueText.value as? String) == ""
                && workPhoto.exists
                && workPhoto.elementType == .image
                && workPhoto.identifier == "s5.1.issue.work-photo"
                && workPhoto.label
                    == "Add one optional photo showing the work performed."
                && (workPhoto.value as? String) == ""
        }
        let hasExactRoute: () -> Bool = {
            let screenFrame = issueScreen.frame
            let scrollFrame = issueScrollView.frame
            let startRecheckFrame = startRecheckButton.frame
            let recordFrame = workRecord.frame
            let dateFrame = workDate.frame
            let descriptionFrame = workDescription.frame
            let valueFrame = descriptionValueText.frame
            let photoFrame = workPhoto.frame
            return hasExactIdentity()
                && isValidFrame(app.frame)
                && isValidFrame(screenFrame)
                && isValidFrame(scrollFrame)
                && isValidFrame(issueNavigationBar.frame)
                && isValidFrame(tabBar.frame)
                && isValidFrame(startRecheckFrame)
                && isValidFrame(recordFrame)
                && isValidFrame(dateFrame)
                && isValidFrame(descriptionFrame)
                && isValidFrame(valueFrame)
                && isValidFrame(photoFrame)
                && screenFrame == scrollFrame
                && recordFrame.contains(dateFrame)
                && recordFrame.contains(descriptionFrame)
                && recordFrame.contains(photoFrame)
                && dateFrame.maxY < descriptionFrame.minY
                && descriptionFrame.maxY < photoFrame.minY
        }
        guard hasExactRoute() else {
            XCTFail("AX-text issue recheck-due positioning bindings are ambiguous.")
            return false
        }

        let verticalInset: CGFloat = 16
        let receiverInset: CGFloat = 24
        let minimumGestureDistance: CGFloat = 44
        var previousStartRecheckMinYAfterDrag: CGFloat?
        var previousDateMinYAfterDrag: CGFloat?
        var previousDescriptionMinYAfterDrag: CGFloat?
        var previousValueMinYAfterDrag: CGFloat?
        var previousPhotoMinYAfterDrag: CGFloat?
        for _ in 0..<4 {
            guard hasExactIdentity() else {
                XCTFail("AX-text issue recheck-due positioning route changed.")
                return false
            }
            let applicationFrame = app.frame
            let screenFrame = issueScreen.frame
            let scrollFrame = issueScrollView.frame
            let navigationFrame = issueNavigationBar.frame
            let tabFrame = tabBar.frame
            let startRecheckFrame = startRecheckButton.frame
            let recordFrame = workRecord.frame
            let dateFrame = workDate.frame
            let descriptionFrame = workDescription.frame
            let valueFrame = descriptionValueText.frame
            let photoFrame = workPhoto.frame
            let liveFramesAreValid = isValidFrame(applicationFrame)
                && isValidFrame(screenFrame)
                && isValidFrame(scrollFrame)
                && isValidFrame(navigationFrame)
                && isValidFrame(tabFrame)
                && isValidFrame(startRecheckFrame)
                && isValidFrame(recordFrame)
                && isValidFrame(dateFrame)
                && isValidFrame(descriptionFrame)
                && isValidFrame(valueFrame)
                && isValidFrame(photoFrame)
            var liveScrollFrame = CGRect.null
            if liveFramesAreValid {
                liveScrollFrame = scrollFrame.intersection(applicationFrame)
            }
            guard liveFramesAreValid,
                  isValidFrame(liveScrollFrame),
                  screenFrame == scrollFrame,
                  recordFrame.contains(dateFrame),
                  recordFrame.contains(descriptionFrame),
                  recordFrame.contains(photoFrame),
                  dateFrame.maxY < descriptionFrame.minY,
                  descriptionFrame.maxY < photoFrame.minY else {
                XCTFail("AX-text issue recheck-due positioning geometry is invalid.")
                return false
            }
            let liveTop = max(liveScrollFrame.minY, navigationFrame.maxY)
            let liveBottom = min(
                liveScrollFrame.maxY,
                min(applicationFrame.maxY, tabFrame.minY)
            )
            let safeTop = liveTop + verticalInset
            let safeBottom = liveBottom - verticalInset
            let receiverTop = liveTop + receiverInset
            let receiverBottom = liveBottom - receiverInset
            let receiverLeft = liveScrollFrame.minX + receiverInset
            let receiverRight = liveScrollFrame.maxX - receiverInset
            let receiverCapacity = receiverBottom - receiverTop
            let minimumShift = max(
                safeTop - startRecheckFrame.minY,
                max(
                    safeTop - dateFrame.minY,
                    max(
                        safeTop - descriptionFrame.minY,
                        safeTop - valueFrame.minY
                    )
                )
            )
            let maximumShift = min(
                safeBottom - startRecheckFrame.maxY,
                min(
                    safeBottom - dateFrame.maxY,
                    min(
                        safeBottom - descriptionFrame.maxY,
                        safeBottom - valueFrame.maxY
                    )
                )
            )
            let startRecheckIsContained =
                startRecheckFrame.minY >= safeTop
                && startRecheckFrame.maxY <= safeBottom
            let dateIsContained = dateFrame.minY >= safeTop
                && dateFrame.maxY <= safeBottom
            let descriptionIsContained = descriptionFrame.minY >= safeTop
                && descriptionFrame.maxY <= safeBottom
            let valueIsContained = valueFrame.minY >= safeTop
                && valueFrame.maxY <= safeBottom
            let targetCompositionIsSafe = startRecheckIsContained
                && dateIsContained
                && descriptionIsContained
                && valueIsContained
                && startRecheckButton.isHittable
                && workDate.isHittable
                && workDescription.isHittable
                && descriptionValueText.isHittable
            guard liveTop.isFinite,
                  liveBottom.isFinite,
                  safeTop.isFinite,
                  safeBottom.isFinite,
                  receiverTop.isFinite,
                  receiverBottom.isFinite,
                  receiverLeft.isFinite,
                  receiverRight.isFinite,
                  receiverCapacity.isFinite,
                  minimumShift.isFinite,
                  maximumShift.isFinite,
                  liveTop <= liveBottom,
                  safeTop < safeBottom,
                  receiverTop <= receiverBottom,
                  receiverLeft <= receiverRight,
                  receiverCapacity >= minimumGestureDistance,
                  startRecheckFrame.height <= safeBottom - safeTop,
                  dateFrame.height <= safeBottom - safeTop,
                  descriptionFrame.height <= safeBottom - safeTop,
                  valueFrame.height <= safeBottom - safeTop,
                  minimumShift <= maximumShift,
                  targetCompositionIsSafe || maximumShift < 0 else {
                XCTFail("AX-text issue recheck-due composition has no supported upward interval.")
                return false
            }
            if targetCompositionIsSafe { break }

            let dragDistance: CGFloat
            if maximumShift >= -receiverCapacity {
                let recognizedMinimum = max(
                    minimumShift,
                    -receiverCapacity
                )
                let recognizedMaximum = min(
                    maximumShift,
                    -minimumGestureDistance
                )
                guard recognizedMinimum <= recognizedMaximum else {
                    XCTFail("AX-text issue recheck-due direct interval is not recognizable.")
                    return false
                }
                dragDistance = recognizedMaximum
            } else {
                let stagedDistance = max(
                    -receiverCapacity,
                    maximumShift + minimumGestureDistance
                )
                guard stagedDistance <= -minimumGestureDistance else {
                    XCTFail("AX-text issue recheck-due staged remainder is not recognizable.")
                    return false
                }
                dragDistance = stagedDistance
            }
            guard dragDistance.isFinite,
                  dragDistance < 0,
                  abs(dragDistance) >= minimumGestureDistance else {
                XCTFail("AX-text issue recheck-due drag direction is invalid.")
                return false
            }

            let receiverFrame = CGRect(
                x: receiverLeft,
                y: receiverTop,
                width: receiverRight - receiverLeft,
                height: receiverBottom - receiverTop
            )
            let startPoint = CGPoint(x: receiverRight, y: receiverBottom)
            let endPoint = CGPoint(
                x: receiverRight,
                y: receiverBottom + dragDistance
            )
            guard startPoint.x.isFinite,
                  startPoint.y.isFinite,
                  endPoint.x.isFinite,
                  endPoint.y.isFinite,
                  isValidFrame(receiverFrame),
                  startPoint.x >= receiverFrame.minX,
                  startPoint.x <= receiverFrame.maxX,
                  startPoint.y >= receiverFrame.minY,
                  startPoint.y <= receiverFrame.maxY,
                  endPoint.x >= receiverFrame.minX,
                  endPoint.x <= receiverFrame.maxX,
                  endPoint.y >= receiverFrame.minY,
                  endPoint.y <= receiverFrame.maxY,
                  liveScrollFrame.contains(startPoint),
                  liveScrollFrame.contains(endPoint),
                  !startRecheckFrame.contains(startPoint),
                  !startRecheckFrame.contains(endPoint),
                  !dateFrame.contains(startPoint),
                  !dateFrame.contains(endPoint),
                  !descriptionFrame.contains(startPoint),
                  !descriptionFrame.contains(endPoint),
                  !valueFrame.contains(startPoint),
                  !valueFrame.contains(endPoint),
                  !photoFrame.contains(startPoint),
                  !photoFrame.contains(endPoint) else {
                XCTFail("AX-text issue recheck-due drag receiver is obstructed.")
                return false
            }
            let scrollOrigin = issueScrollView.coordinate(
                withNormalizedOffset: CGVector(dx: 0, dy: 0)
            )
            let dragStart = scrollOrigin.withOffset(
                CGVector(
                    dx: startPoint.x - scrollFrame.minX,
                    dy: startPoint.y - scrollFrame.minY
                )
            )
            let dragEnd = scrollOrigin.withOffset(
                CGVector(
                    dx: endPoint.x - scrollFrame.minX,
                    dy: endPoint.y - scrollFrame.minY
                )
            )
            let startRecheckBeforeDrag = startRecheckFrame.minY
            let dateBeforeDrag = dateFrame.minY
            let descriptionBeforeDrag = descriptionFrame.minY
            let valueBeforeDrag = valueFrame.minY
            let photoBeforeDrag = photoFrame.minY
            dragStart.press(
                forDuration: 0.2,
                thenDragTo: dragEnd,
                withVelocity: .slow,
                thenHoldForDuration: 0.2
            )
            guard hasExactIdentity() else {
                XCTFail("AX-text issue recheck-due route changed after positioning.")
                return false
            }
            let startRecheckAfterDrag = startRecheckButton.frame
            let dateAfterDrag = workDate.frame
            let descriptionAfterDrag = workDescription.frame
            let valueAfterDrag = descriptionValueText.frame
            let photoAfterDrag = workPhoto.frame
            let movedFramesAreValid = isValidFrame(startRecheckAfterDrag)
                && isValidFrame(dateAfterDrag)
                && isValidFrame(descriptionAfterDrag)
                && isValidFrame(valueAfterDrag)
                && isValidFrame(photoAfterDrag)
            var observedStartRecheckShift: CGFloat?
            var observedDateShift: CGFloat?
            var observedDescriptionShift: CGFloat?
            var observedValueShift: CGFloat?
            var observedPhotoShift: CGFloat?
            if movedFramesAreValid {
                observedStartRecheckShift =
                    startRecheckAfterDrag.minY - startRecheckBeforeDrag
                observedDateShift = dateAfterDrag.minY - dateBeforeDrag
                observedDescriptionShift =
                    descriptionAfterDrag.minY - descriptionBeforeDrag
                observedValueShift = valueAfterDrag.minY - valueBeforeDrag
                observedPhotoShift = photoAfterDrag.minY - photoBeforeDrag
            }
            guard let observedStartRecheckShift,
                  let observedDateShift,
                  let observedDescriptionShift,
                  let observedValueShift,
                  let observedPhotoShift,
                  observedStartRecheckShift * dragDistance > 0,
                  observedDateShift * dragDistance > 0,
                  observedDescriptionShift * dragDistance > 0,
                  observedValueShift * dragDistance > 0,
                  observedPhotoShift * dragDistance > 0 else {
                XCTFail("AX-text issue recheck-due gesture made no signed progress.")
                return false
            }
            if let previousStartRecheckMinYAfterDrag,
               let previousDateMinYAfterDrag,
               let previousDescriptionMinYAfterDrag,
               let previousValueMinYAfterDrag,
               let previousPhotoMinYAfterDrag {
                guard startRecheckAfterDrag.minY
                        < previousStartRecheckMinYAfterDrag,
                      dateAfterDrag.minY < previousDateMinYAfterDrag,
                      descriptionAfterDrag.minY
                        < previousDescriptionMinYAfterDrag,
                      valueAfterDrag.minY < previousValueMinYAfterDrag,
                      photoAfterDrag.minY < previousPhotoMinYAfterDrag else {
                    XCTFail("AX-text issue recheck-due positioning reversed direction.")
                    return false
                }
            }
            previousStartRecheckMinYAfterDrag = startRecheckAfterDrag.minY
            previousDateMinYAfterDrag = dateAfterDrag.minY
            previousDescriptionMinYAfterDrag = descriptionAfterDrag.minY
            previousValueMinYAfterDrag = valueAfterDrag.minY
            previousPhotoMinYAfterDrag = photoAfterDrag.minY
        }

        guard hasExactIdentity() else {
            XCTFail("AX-text issue recheck-due final route is invalid.")
            return false
        }
        let finalApplicationFrame = app.frame
        let finalScreenFrame = issueScreen.frame
        let finalScrollFrame = issueScrollView.frame
        let finalNavigationFrame = issueNavigationBar.frame
        let finalTabFrame = tabBar.frame
        let finalStartRecheckFrame = startRecheckButton.frame
        let finalRecordFrame = workRecord.frame
        let finalDateFrame = workDate.frame
        let finalDescriptionFrame = workDescription.frame
        let finalValueFrame = descriptionValueText.frame
        let finalPhotoFrame = workPhoto.frame
        let finalFramesAreValid = isValidFrame(finalApplicationFrame)
            && isValidFrame(finalScreenFrame)
            && isValidFrame(finalScrollFrame)
            && isValidFrame(finalNavigationFrame)
            && isValidFrame(finalTabFrame)
            && isValidFrame(finalStartRecheckFrame)
            && isValidFrame(finalRecordFrame)
            && isValidFrame(finalDateFrame)
            && isValidFrame(finalDescriptionFrame)
            && isValidFrame(finalValueFrame)
            && isValidFrame(finalPhotoFrame)
            && finalScreenFrame == finalScrollFrame
        var finalCompositionIsSafe = false
        if finalFramesAreValid {
            let finalLiveScrollFrame = finalScrollFrame.intersection(
                finalApplicationFrame
            )
            if isValidFrame(finalLiveScrollFrame) {
                let finalSafeTop = max(
                    finalLiveScrollFrame.minY,
                    finalNavigationFrame.maxY
                ) + verticalInset
                let finalSafeBottom = min(
                    finalLiveScrollFrame.maxY,
                    min(finalApplicationFrame.maxY, finalTabFrame.minY)
                ) - verticalInset
                finalCompositionIsSafe = finalSafeTop.isFinite
                    && finalSafeBottom.isFinite
                    && finalSafeTop < finalSafeBottom
                    && finalRecordFrame.contains(finalDateFrame)
                    && finalRecordFrame.contains(finalDescriptionFrame)
                    && finalRecordFrame.contains(finalPhotoFrame)
                    && finalDateFrame.maxY < finalDescriptionFrame.minY
                    && finalDescriptionFrame.maxY < finalPhotoFrame.minY
                    && finalStartRecheckFrame.minY >= finalSafeTop
                    && finalStartRecheckFrame.maxY <= finalSafeBottom
                    && finalDateFrame.minY >= finalSafeTop
                    && finalDateFrame.maxY <= finalSafeBottom
                    && finalDescriptionFrame.minY >= finalSafeTop
                    && finalDescriptionFrame.maxY <= finalSafeBottom
                    && finalValueFrame.minY >= finalSafeTop
                    && finalValueFrame.maxY <= finalSafeBottom
                    && startRecheckButton.isHittable
                    && workDate.isHittable
                    && workDescription.isHittable
                    && descriptionValueText.isHittable
            }
        }
        guard finalCompositionIsSafe else {
            XCTFail("AX-text issue recheck-due final composition is unsafe.")
            return false
        }
        return true
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

    @MainActor
    private func diagnoseSegment2AXTextPaywallPurchaseCompleteNativeContrast(
        in app: XCUIApplication
    ) throws {
        let stateID = "state.paywall.purchase-complete"
        let expectedMigratedStateIDs = Array(
            Self.segmentedRouteStateIDs[22..<39]
        )
        let expectedAXTreeDigestStateIDs = Array(
            Self.segmentedRouteStateIDs[22..<39]
        )
        let expectedContrastExceptionStateIDs = [
            "state.issue.recheck-due",
            "state.issue.resolved",
            "state.recheck-capture.wide-ready",
            "state.recheck-preflight.ready",
        ]
        guard let shard = automationShard,
              shard.shardID == "s10.4.current.ax-text",
              automationSegment == .segment2,
              automationSegment.replayCount == 22,
              automationSegment.ownedStartOrdinal == 23,
              automationSegment.ownedCount == 28,
              automationSegment.finalOrdinal == 50,
              Self.segmentedRouteStateIDs.count == 67,
              Set(Self.segmentedRouteStateIDs).count == 67,
              Self.segmentedRouteStateIDs[39] == stateID,
              segmentedRouteStateCursor == 39,
              migratedStateIDs == expectedMigratedStateIDs,
              automationAXTreeDigests.keys.sorted()
                == expectedAXTreeDigestStateIDs.sorted(),
              automationContrastExceptions.keys.sorted()
                == expectedContrastExceptionStateIDs,
              !automatedSegmentFinished,
              app.state == .runningForeground else {
            throw AutomationConfigurationError.invalid(
                "S10.4 AX-text paywall purchase-complete native contrast diagnostic gate is invalid"
            )
        }

        let purchasePredicate = NSPredicate(
            format: "label CONTAINS[c] 'Subscribe' OR " +
                "label CONTAINS[c] 'Trial' OR label CONTAINS[c] '$59.99'"
        )
        let diagnosticQueryBindings: [(
            name: String,
            query: XCUIElementQuery
        )] = [
            (
                "paywallScreens",
                app.descendants(matching: .any).matching(
                    identifier: "s7.2.paywall.screen"
                )
            ),
            (
                "paywallStores",
                app.descendants(matching: .any).matching(
                    identifier: "s7.2.paywall.store"
                )
            ),
            (
                "closeButtons",
                app.buttons.matching(identifier: "s7.2.paywall.close")
            ),
            (
                "purchaseStateElements",
                app.descendants(matching: .any).matching(
                    identifier: "s7.2.paywall.purchase-state"
                )
            ),
            (
                "termsButtons",
                app.buttons.matching(identifier: "s7.2.paywall.terms")
            ),
            (
                "privacyButtons",
                app.buttons.matching(identifier: "s7.2.paywall.privacy")
            ),
            (
                "supportButtons",
                app.buttons.matching(identifier: "s7.2.paywall.support")
            ),
            (
                "renewalStaticTexts",
                app.staticTexts.matching(identifier: "s7.2.paywall.renewal")
            ),
            (
                "noSyncStaticTexts",
                app.staticTexts.matching(identifier: "s7.2.paywall.no-sync")
            ),
            ("purchaseButtons", app.buttons.matching(purchasePredicate)),
            ("navigationBars", app.navigationBars),
            ("tabBars", app.tabBars),
            ("keyboards", app.keyboards),
            (
                "inputViews",
                app.otherElements.matching(
                    NSPredicate(format: "identifier == %@", "inputView")
                )
            ),
        ]
        let diagnosticElementObject: (XCUIElement) -> [String: Any] = {
            element in
            let valueObject: Any
            if let value = element.value as? String {
                valueObject = value
            } else {
                valueObject = NSNull()
            }
            return [
                "exists": element.exists,
                "isEnabled": element.isEnabled,
                "isHittable": element.isHittable,
                "identifier": element.identifier,
                "label": element.label,
                "value": valueObject,
                "elementTypeRawValue": element.elementType.rawValue,
                "elementTypeDescription": String(describing: element.elementType),
                "frame": self.auditFrameObject(element.frame),
            ]
        }
        let diagnosticQueryObject: (XCUIElementQuery) -> [String: Any] = {
            query in
            let count = query.count
            var elements: [[String: Any]] = []
            for index in 0..<count {
                elements.append(
                    diagnosticElementObject(query.element(boundBy: index))
                )
            }
            return [
                "count": count,
                "elements": elements,
            ]
        }
        var diagnosticQueryObjects: [String: Any] = [:]
        for binding in diagnosticQueryBindings {
            diagnosticQueryObjects[binding.name] = diagnosticQueryObject(binding.query)
        }
        let diagnosticContext: [String: Any] = [
            "schemaVersion": 1,
            "acceptanceEligible": false,
            "shardID": shard.shardID,
            "requirementID": shard.requirementID,
            "deviceProfileID": shard.deviceProfileID,
            "segmentID": automationSegment.rawValue,
            "segmentReplayCount": automationSegment.replayCount,
            "segmentOwnedStartOrdinal": automationSegment.ownedStartOrdinal,
            "segmentOwnedCount": automationSegment.ownedCount,
            "segmentFinalOrdinal": automationSegment.finalOrdinal,
            "segmentStateCursor": segmentedRouteStateCursor,
            "stateID": stateID,
            "stateOrdinal": 40,
            "predecessorStateID": "state.paywall.available",
            "predecessorOrdinal": 39,
            "successorStateID": "state.check-outcome.could-not-verify",
            "successorOrdinal": 41,
            "migratedStateIDs": migratedStateIDs,
            "axTreeDigestStateIDs": automationAXTreeDigests.keys.sorted(),
            "contrastExceptionStateIDs": automationContrastExceptions.keys.sorted(),
            "applicationState": String(describing: app.state),
            "applicationStateRawValue": app.state.rawValue,
            "applicationForeground": app.state == .runningForeground,
            "applicationFrame": auditFrameObject(app.frame),
            "application": diagnosticElementObject(app),
            "queries": diagnosticQueryObjects,
        ]
        printJSONLine(
            prefix:
                "S10_4_AX_TEXT_PAYWALL_PURCHASE_COMPLETE_NATIVE_CONTRAST_CONTEXT_DIAGNOSTIC",
            object: diagnosticContext
        )

        let appAttachment = XCTAttachment(screenshot: app.screenshot())
        appAttachment.name =
            "S10.4 AX-text paywall purchase-complete native contrast diagnostic app"
        appAttachment.lifetime = .keepAlways
        add(appAttachment)
        let treeAttachment = XCTAttachment(string: app.debugDescription)
        treeAttachment.name =
            "S10.4 AX-text paywall purchase-complete native contrast diagnostic tree"
        treeAttachment.lifetime = .keepAlways
        add(treeAttachment)
        let contextData = try JSONSerialization.data(
            withJSONObject: diagnosticContext,
            options: [.prettyPrinted, .sortedKeys]
        )
        let contextAttachment = XCTAttachment(
            string: String(decoding: contextData, as: UTF8.self)
        )
        contextAttachment.name =
            "S10.4 AX-text paywall purchase-complete native contrast diagnostic context"
        contextAttachment.lifetime = .keepAlways
        add(contextAttachment)

        var observedIssueCount = 0
        var auditedElementCount = 0
        try app.performAccessibilityAudit(for: .contrast) { issue in
            observedIssueCount += 1
            let auditedElement = issue.element
            var diagnosticIssue: [String: Any] = [
                "schemaVersion": 1,
                "acceptanceEligible": false,
                "shardID": shard.shardID,
                "requirementID": shard.requirementID,
                "deviceProfileID": shard.deviceProfileID,
                "segmentID": self.automationSegment.rawValue,
                "segmentStateCursor": self.segmentedRouteStateCursor,
                "stateID": stateID,
                "stateOrdinal": 40,
                "issueOrdinal": observedIssueCount,
                "auditTypeRawValue": String(issue.auditType.rawValue),
                "compactDescription": issue.compactDescription,
                "detailedDescription": issue.detailedDescription,
                "elementExists": NSNull(),
                "elementEnabled": NSNull(),
                "elementHittable": NSNull(),
                "elementIdentifier": NSNull(),
                "elementLabel": NSNull(),
                "elementValue": NSNull(),
                "elementTypeRawValue": NSNull(),
                "elementTypeDescription": NSNull(),
                "elementFrame": NSNull(),
                "applicationFrame": self.auditFrameObject(app.frame),
            ]
            if let auditedElement {
                auditedElementCount += 1
                let valueObject: Any
                if let value = auditedElement.value as? String {
                    valueObject = value
                } else {
                    valueObject = NSNull()
                }
                diagnosticIssue["elementExists"] = auditedElement.exists
                diagnosticIssue["elementEnabled"] = auditedElement.isEnabled
                diagnosticIssue["elementHittable"] = auditedElement.isHittable
                diagnosticIssue["elementIdentifier"] = auditedElement.identifier
                diagnosticIssue["elementLabel"] = auditedElement.label
                diagnosticIssue["elementValue"] = valueObject
                diagnosticIssue["elementTypeRawValue"] =
                    auditedElement.elementType.rawValue
                diagnosticIssue["elementTypeDescription"] =
                    String(describing: auditedElement.elementType)
                diagnosticIssue["elementFrame"] =
                    self.auditFrameObject(auditedElement.frame)
            }
            self.printJSONLine(
                prefix:
                    "S10_4_AX_TEXT_PAYWALL_PURCHASE_COMPLETE_NATIVE_CONTRAST_ISSUE_DIAGNOSTIC",
                object: diagnosticIssue
            )
            if let auditedElement {
                let issueAttachment = XCTAttachment(
                    screenshot: auditedElement.screenshot()
                )
                issueAttachment.name =
                    "S10.4 AX-text paywall purchase-complete native contrast diagnostic audited element "
                        + String(observedIssueCount)
                issueAttachment.lifetime = .keepAlways
                self.add(issueAttachment)
            }
            return true
        }
        printJSONLine(
            prefix:
                "S10_4_AX_TEXT_PAYWALL_PURCHASE_COMPLETE_NATIVE_CONTRAST_COUNT_DIAGNOSTIC",
            object: [
                "schemaVersion": 1,
                "acceptanceEligible": false,
                "shardID": shard.shardID,
                "segmentID": automationSegment.rawValue,
                "stateID": stateID,
                "stateOrdinal": 40,
                "segmentStateCursor": segmentedRouteStateCursor,
                "observedIssueCount": observedIssueCount,
                "auditedElementCount": auditedElementCount,
            ]
        )
        throw AutomationConfigurationError.invalid(
            "S10.4 AX-text paywall purchase-complete native contrast diagnostic completed nonaccepting"
        )
    }


    @MainActor
    private func diagnoseSegment2AXTextIssueResolvedNativeContrast(
        in app: XCUIApplication
    ) throws {
        let stateID = "state.issue.resolved"
        let expectedMigratedStateIDs = Array(
            Self.segmentedRouteStateIDs[22..<35]
        )
        let expectedContrastExceptionStateIDs = [
            "state.issue.recheck-due",
            "state.recheck-capture.wide-ready",
            "state.recheck-preflight.ready",
        ]
        guard let shard = automationShard,
              shard.shardID == "s10.4.current.ax-text",
              automationSegment == .segment2,
              automationSegment.replayCount == 22,
              automationSegment.ownedStartOrdinal == 23,
              automationSegment.ownedCount == 28,
              automationSegment.finalOrdinal == 50,
              Self.segmentedRouteStateIDs.count == 67,
              Set(Self.segmentedRouteStateIDs).count == 67,
              Self.segmentedRouteStateIDs[35] == stateID,
              segmentedRouteStateCursor == 36,
              migratedStateIDs == expectedMigratedStateIDs,
              automationAXTreeDigests.keys.sorted()
                == expectedMigratedStateIDs.sorted(),
              automationContrastExceptions.keys.sorted()
                == expectedContrastExceptionStateIDs,
              !automatedSegmentFinished,
              app.state == .runningForeground else {
            throw AutomationConfigurationError.invalid(
                "S10.4 AX-text issue-resolved native contrast diagnostic gate is invalid"
            )
        }

        let descriptionValuePredicate = NSPredicate(
            format: "label == %@",
            "Replaced failed power supply"
        )
        let diagnosticQueryBindings: [(
            name: String,
            query: XCUIElementQuery
        )] = [
            (
                "issueScreens",
                app.descendants(matching: .any).matching(
                    identifier: "s5.1.issue.screen"
                )
            ),
            (
                "issueScrollViews",
                app.scrollViews.matching(identifier: "s5.1.issue.screen")
            ),
            (
                "issueHeaders",
                app.descendants(matching: .any).matching(
                    identifier: "s5.1.issue.header"
                )
            ),
            (
                "issueStatuses",
                app.descendants(matching: .any).matching(
                    identifier: "s5.1.issue.status"
                )
            ),
            (
                "startRecheckControls",
                app.descendants(matching: .any).matching(
                    identifier: "s5.2.issue.start-recheck"
                )
            ),
            (
                "workRecords",
                app.descendants(matching: .any).matching(
                    identifier: "s5.1.issue.work-record"
                )
            ),
            (
                "workDates",
                app.descendants(matching: .any).matching(
                    identifier: "s5.1.issue.work-date"
                )
            ),
            (
                "workDescriptions",
                app.descendants(matching: .any).matching(
                    identifier: "s5.1.issue.work-description"
                )
            ),
            (
                "workNotes",
                app.descendants(matching: .any).matching(
                    identifier: "s5.1.issue.work-note"
                )
            ),
            (
                "workPhotos",
                app.descendants(matching: .any).matching(
                    identifier: "s5.1.issue.work-photo"
                )
            ),
            (
                "descriptionValueTexts",
                app.staticTexts.matching(descriptionValuePredicate)
            ),
            ("navigationBars", app.navigationBars),
            ("tabBars", app.tabBars),
            ("keyboards", app.keyboards),
            (
                "inputViews",
                app.otherElements.matching(
                    NSPredicate(format: "identifier == %@", "inputView")
                )
            ),
        ]
        let diagnosticElementObject: (XCUIElement) -> [String: Any] = {
            element in
            let valueObject: Any
            if let value = element.value as? String {
                valueObject = value
            } else {
                valueObject = NSNull()
            }
            return [
                "exists": element.exists,
                "isEnabled": element.isEnabled,
                "isHittable": element.isHittable,
                "identifier": element.identifier,
                "label": element.label,
                "value": valueObject,
                "elementTypeRawValue": element.elementType.rawValue,
                "elementTypeDescription": String(describing: element.elementType),
                "frame": self.auditFrameObject(element.frame),
            ]
        }
        let diagnosticQueryObject: (XCUIElementQuery) -> [String: Any] = {
            query in
            let count = query.count
            var elements: [[String: Any]] = []
            for index in 0..<count {
                elements.append(
                    diagnosticElementObject(query.element(boundBy: index))
                )
            }
            return [
                "count": count,
                "elements": elements,
            ]
        }
        var diagnosticQueryObjects: [String: Any] = [:]
        for binding in diagnosticQueryBindings {
            diagnosticQueryObjects[binding.name] = diagnosticQueryObject(binding.query)
        }
        let diagnosticContext: [String: Any] = [
            "schemaVersion": 1,
            "acceptanceEligible": false,
            "shardID": shard.shardID,
            "requirementID": shard.requirementID,
            "deviceProfileID": shard.deviceProfileID,
            "segmentID": automationSegment.rawValue,
            "segmentReplayCount": automationSegment.replayCount,
            "segmentOwnedStartOrdinal": automationSegment.ownedStartOrdinal,
            "segmentOwnedCount": automationSegment.ownedCount,
            "segmentFinalOrdinal": automationSegment.finalOrdinal,
            "segmentStateCursor": segmentedRouteStateCursor,
            "stateID": stateID,
            "stateOrdinal": 36,
            "predecessorStateID": "state.recheck-report-detail.ready",
            "predecessorOrdinal": 35,
            "successorStateID": "state.check-outcome.no-visible-issue",
            "successorOrdinal": 37,
            "migratedStateIDs": migratedStateIDs,
            "axTreeDigestStateIDs": automationAXTreeDigests.keys.sorted(),
            "contrastExceptionStateIDs": automationContrastExceptions.keys.sorted(),
            "applicationState": String(describing: app.state),
            "applicationStateRawValue": app.state.rawValue,
            "applicationForeground": app.state == .runningForeground,
            "applicationFrame": auditFrameObject(app.frame),
            "application": diagnosticElementObject(app),
            "queries": diagnosticQueryObjects,
        ]
        printJSONLine(
            prefix:
                "S10_4_AX_TEXT_ISSUE_RESOLVED_NATIVE_CONTRAST_CONTEXT_DIAGNOSTIC",
            object: diagnosticContext
        )

        let appAttachment = XCTAttachment(screenshot: app.screenshot())
        appAttachment.name =
            "S10.4 AX-text issue-resolved native contrast diagnostic app"
        appAttachment.lifetime = .keepAlways
        add(appAttachment)
        let treeAttachment = XCTAttachment(string: app.debugDescription)
        treeAttachment.name =
            "S10.4 AX-text issue-resolved native contrast diagnostic tree"
        treeAttachment.lifetime = .keepAlways
        add(treeAttachment)
        let contextData = try JSONSerialization.data(
            withJSONObject: diagnosticContext,
            options: [.prettyPrinted, .sortedKeys]
        )
        let contextAttachment = XCTAttachment(
            string: String(decoding: contextData, as: UTF8.self)
        )
        contextAttachment.name =
            "S10.4 AX-text issue-resolved native contrast diagnostic context"
        contextAttachment.lifetime = .keepAlways
        add(contextAttachment)

        var observedIssueCount = 0
        var auditedElementCount = 0
        try app.performAccessibilityAudit(for: .contrast) { issue in
            observedIssueCount += 1
            let auditedElement = issue.element
            var diagnosticIssue: [String: Any] = [
                "schemaVersion": 1,
                "acceptanceEligible": false,
                "shardID": shard.shardID,
                "requirementID": shard.requirementID,
                "deviceProfileID": shard.deviceProfileID,
                "segmentID": self.automationSegment.rawValue,
                "segmentStateCursor": self.segmentedRouteStateCursor,
                "stateID": stateID,
                "stateOrdinal": 36,
                "issueOrdinal": observedIssueCount,
                "auditTypeRawValue": String(issue.auditType.rawValue),
                "compactDescription": issue.compactDescription,
                "detailedDescription": issue.detailedDescription,
                "elementExists": NSNull(),
                "elementEnabled": NSNull(),
                "elementHittable": NSNull(),
                "elementIdentifier": NSNull(),
                "elementLabel": NSNull(),
                "elementValue": NSNull(),
                "elementTypeRawValue": NSNull(),
                "elementTypeDescription": NSNull(),
                "elementFrame": NSNull(),
                "applicationFrame": self.auditFrameObject(app.frame),
            ]
            if let auditedElement {
                auditedElementCount += 1
                let valueObject: Any
                if let value = auditedElement.value as? String {
                    valueObject = value
                } else {
                    valueObject = NSNull()
                }
                diagnosticIssue["elementExists"] = auditedElement.exists
                diagnosticIssue["elementEnabled"] = auditedElement.isEnabled
                diagnosticIssue["elementHittable"] = auditedElement.isHittable
                diagnosticIssue["elementIdentifier"] = auditedElement.identifier
                diagnosticIssue["elementLabel"] = auditedElement.label
                diagnosticIssue["elementValue"] = valueObject
                diagnosticIssue["elementTypeRawValue"] =
                    auditedElement.elementType.rawValue
                diagnosticIssue["elementTypeDescription"] =
                    String(describing: auditedElement.elementType)
                diagnosticIssue["elementFrame"] =
                    self.auditFrameObject(auditedElement.frame)
            }
            self.printJSONLine(
                prefix:
                    "S10_4_AX_TEXT_ISSUE_RESOLVED_NATIVE_CONTRAST_ISSUE_DIAGNOSTIC",
                object: diagnosticIssue
            )
            if let auditedElement {
                let issueAttachment = XCTAttachment(
                    screenshot: auditedElement.screenshot()
                )
                issueAttachment.name =
                    "S10.4 AX-text issue-resolved native contrast diagnostic audited element "
                        + String(observedIssueCount)
                issueAttachment.lifetime = .keepAlways
                self.add(issueAttachment)
            }
            return true
        }
        printJSONLine(
            prefix:
                "S10_4_AX_TEXT_ISSUE_RESOLVED_NATIVE_CONTRAST_COUNT_DIAGNOSTIC",
            object: [
                "schemaVersion": 1,
                "acceptanceEligible": false,
                "shardID": shard.shardID,
                "segmentID": automationSegment.rawValue,
                "stateID": stateID,
                "stateOrdinal": 36,
                "segmentStateCursor": segmentedRouteStateCursor,
                "observedIssueCount": observedIssueCount,
                "auditedElementCount": auditedElementCount,
            ]
        )
        throw AutomationConfigurationError.invalid(
            "S10.4 AX-text issue-resolved native contrast diagnostic completed nonaccepting"
        )
    }

    @MainActor
    private func diagnoseSegment2AXTextIssueOpenNativeContrast(
        in app: XCUIApplication
    ) throws {
        let stateID = "state.issue.open"
        let expectedMigratedStateIDs = Array(
            Self.segmentedRouteStateIDs[22..<46]
        )
        let expectedContrastExceptionStateIDs = [
            "state.issue.recheck-due",
            "state.issue.resolved",
            "state.paywall.purchase-complete",
            "state.recheck-capture.wide-ready",
            "state.recheck-preflight.ready",
        ]
        guard let shard = automationShard,
              shard.shardID == "s10.4.current.ax-text",
              automationSegment == .segment2,
              automationSegment.replayCount == 22,
              automationSegment.ownedStartOrdinal == 23,
              automationSegment.ownedCount == 28,
              automationSegment.finalOrdinal == 50,
              Self.segmentedRouteStateIDs.count == 67,
              Set(Self.segmentedRouteStateIDs).count == 67,
              Self.segmentedRouteStateIDs[46] == stateID,
              segmentedRouteStateCursor == 46,
              migratedStateIDs == expectedMigratedStateIDs,
              automationAXTreeDigests.keys.sorted()
                == expectedMigratedStateIDs.sorted(),
              automationContrastExceptions.keys.sorted()
                == expectedContrastExceptionStateIDs,
              !automatedSegmentFinished,
              app.state == .runningForeground else {
            throw AutomationConfigurationError.invalid(
                "S10.4 AX-text issue-open native contrast diagnostic gate is invalid"
            )
        }

        let descriptionValuePredicate = NSPredicate(
            format: "label == %@",
            "Replaced failed power supply"
        )
        let diagnosticQueryBindings: [(
            name: String,
            query: XCUIElementQuery
        )] = [
            (
                "issueScreens",
                app.descendants(matching: .any).matching(
                    identifier: "s5.1.issue.screen"
                )
            ),
            (
                "issueScrollViews",
                app.scrollViews.matching(identifier: "s5.1.issue.screen")
            ),
            (
                "issueHeaders",
                app.descendants(matching: .any).matching(
                    identifier: "s5.1.issue.header"
                )
            ),
            (
                "issueStatuses",
                app.descendants(matching: .any).matching(
                    identifier: "s5.1.issue.status"
                )
            ),
            (
                "startRecheckControls",
                app.descendants(matching: .any).matching(
                    identifier: "s5.2.issue.start-recheck"
                )
            ),
            (
                "workRecords",
                app.descendants(matching: .any).matching(
                    identifier: "s5.1.issue.work-record"
                )
            ),
            (
                "workDates",
                app.descendants(matching: .any).matching(
                    identifier: "s5.1.issue.work-date"
                )
            ),
            (
                "workDescriptions",
                app.descendants(matching: .any).matching(
                    identifier: "s5.1.issue.work-description"
                )
            ),
            (
                "workNotes",
                app.descendants(matching: .any).matching(
                    identifier: "s5.1.issue.work-note"
                )
            ),
            (
                "workPhotos",
                app.descendants(matching: .any).matching(
                    identifier: "s5.1.issue.work-photo"
                )
            ),
            (
                "descriptionValueTexts",
                app.staticTexts.matching(descriptionValuePredicate)
            ),
            ("navigationBars", app.navigationBars),
            ("tabBars", app.tabBars),
            ("keyboards", app.keyboards),
            (
                "inputViews",
                app.otherElements.matching(
                    NSPredicate(format: "identifier == %@", "inputView")
                )
            ),
        ]
        let diagnosticElementObject: (XCUIElement) -> [String: Any] = {
            element in
            let valueObject: Any
            if let value = element.value as? String {
                valueObject = value
            } else {
                valueObject = NSNull()
            }
            return [
                "exists": element.exists,
                "isEnabled": element.isEnabled,
                "isHittable": element.isHittable,
                "identifier": element.identifier,
                "label": element.label,
                "value": valueObject,
                "elementTypeRawValue": element.elementType.rawValue,
                "elementTypeDescription": String(describing: element.elementType),
                "frame": self.auditFrameObject(element.frame),
            ]
        }
        let diagnosticQueryObject: (XCUIElementQuery) -> [String: Any] = {
            query in
            let count = query.count
            var elements: [[String: Any]] = []
            for index in 0..<count {
                elements.append(
                    diagnosticElementObject(query.element(boundBy: index))
                )
            }
            return [
                "count": count,
                "elements": elements,
            ]
        }
        var diagnosticQueryObjects: [String: Any] = [:]
        for binding in diagnosticQueryBindings {
            diagnosticQueryObjects[binding.name] = diagnosticQueryObject(binding.query)
        }
        let diagnosticContext: [String: Any] = [
            "schemaVersion": 1,
            "acceptanceEligible": false,
            "shardID": shard.shardID,
            "requirementID": shard.requirementID,
            "deviceProfileID": shard.deviceProfileID,
            "segmentID": automationSegment.rawValue,
            "segmentReplayCount": automationSegment.replayCount,
            "segmentOwnedStartOrdinal": automationSegment.ownedStartOrdinal,
            "segmentOwnedCount": automationSegment.ownedCount,
            "segmentFinalOrdinal": automationSegment.finalOrdinal,
            "segmentStateCursor": segmentedRouteStateCursor,
            "stateID": stateID,
            "stateOrdinal": 47,
            "predecessorStateID": "state.recheck-review.issue-still-visible",
            "predecessorOrdinal": 46,
            "successorStateID": "state.recheck-outcome.different-issue",
            "successorOrdinal": 48,
            "migratedStateIDs": migratedStateIDs,
            "axTreeDigestStateIDs": automationAXTreeDigests.keys.sorted(),
            "contrastExceptionStateIDs": automationContrastExceptions.keys.sorted(),
            "applicationState": String(describing: app.state),
            "applicationStateRawValue": app.state.rawValue,
            "applicationForeground": app.state == .runningForeground,
            "applicationFrame": auditFrameObject(app.frame),
            "application": diagnosticElementObject(app),
            "queries": diagnosticQueryObjects,
        ]
        printJSONLine(
            prefix:
                "S10_4_AX_TEXT_ISSUE_OPEN_NATIVE_CONTRAST_CONTEXT_DIAGNOSTIC",
            object: diagnosticContext
        )

        let appAttachment = XCTAttachment(screenshot: app.screenshot())
        appAttachment.name =
            "S10.4 AX-text issue-open native contrast diagnostic app"
        appAttachment.lifetime = .keepAlways
        add(appAttachment)
        let treeAttachment = XCTAttachment(string: app.debugDescription)
        treeAttachment.name =
            "S10.4 AX-text issue-open native contrast diagnostic tree"
        treeAttachment.lifetime = .keepAlways
        add(treeAttachment)
        let contextData = try JSONSerialization.data(
            withJSONObject: diagnosticContext,
            options: [.prettyPrinted, .sortedKeys]
        )
        let contextAttachment = XCTAttachment(
            string: String(decoding: contextData, as: UTF8.self)
        )
        contextAttachment.name =
            "S10.4 AX-text issue-open native contrast diagnostic context"
        contextAttachment.lifetime = .keepAlways
        add(contextAttachment)

        var observedIssueCount = 0
        var auditedElementCount = 0
        try app.performAccessibilityAudit(for: .contrast) { issue in
            observedIssueCount += 1
            let auditedElement = issue.element
            var diagnosticIssue: [String: Any] = [
                "schemaVersion": 1,
                "acceptanceEligible": false,
                "shardID": shard.shardID,
                "requirementID": shard.requirementID,
                "deviceProfileID": shard.deviceProfileID,
                "segmentID": self.automationSegment.rawValue,
                "segmentStateCursor": self.segmentedRouteStateCursor,
                "stateID": stateID,
                "stateOrdinal": 47,
                "issueOrdinal": observedIssueCount,
                "auditTypeRawValue": String(issue.auditType.rawValue),
                "compactDescription": issue.compactDescription,
                "detailedDescription": issue.detailedDescription,
                "elementExists": NSNull(),
                "elementEnabled": NSNull(),
                "elementHittable": NSNull(),
                "elementIdentifier": NSNull(),
                "elementLabel": NSNull(),
                "elementValue": NSNull(),
                "elementTypeRawValue": NSNull(),
                "elementTypeDescription": NSNull(),
                "elementFrame": NSNull(),
                "applicationFrame": self.auditFrameObject(app.frame),
            ]
            if let auditedElement {
                auditedElementCount += 1
                let valueObject: Any
                if let value = auditedElement.value as? String {
                    valueObject = value
                } else {
                    valueObject = NSNull()
                }
                diagnosticIssue["elementExists"] = auditedElement.exists
                diagnosticIssue["elementEnabled"] = auditedElement.isEnabled
                diagnosticIssue["elementHittable"] = auditedElement.isHittable
                diagnosticIssue["elementIdentifier"] = auditedElement.identifier
                diagnosticIssue["elementLabel"] = auditedElement.label
                diagnosticIssue["elementValue"] = valueObject
                diagnosticIssue["elementTypeRawValue"] =
                    auditedElement.elementType.rawValue
                diagnosticIssue["elementTypeDescription"] =
                    String(describing: auditedElement.elementType)
                diagnosticIssue["elementFrame"] =
                    self.auditFrameObject(auditedElement.frame)
            }
            self.printJSONLine(
                prefix:
                    "S10_4_AX_TEXT_ISSUE_OPEN_NATIVE_CONTRAST_ISSUE_DIAGNOSTIC",
                object: diagnosticIssue
            )
            if let auditedElement {
                let issueAttachment = XCTAttachment(
                    screenshot: auditedElement.screenshot()
                )
                issueAttachment.name =
                    "S10.4 AX-text issue-open native contrast diagnostic audited element "
                        + String(observedIssueCount)
                issueAttachment.lifetime = .keepAlways
                self.add(issueAttachment)
            }
            return true
        }
        printJSONLine(
            prefix:
                "S10_4_AX_TEXT_ISSUE_OPEN_NATIVE_CONTRAST_COUNT_DIAGNOSTIC",
            object: [
                "schemaVersion": 1,
                "acceptanceEligible": false,
                "shardID": shard.shardID,
                "segmentID": automationSegment.rawValue,
                "stateID": stateID,
                "stateOrdinal": 47,
                "segmentStateCursor": segmentedRouteStateCursor,
                "observedIssueCount": observedIssueCount,
                "auditedElementCount": auditedElementCount,
            ]
        )
        throw AutomationConfigurationError.invalid(
            "S10.4 AX-text issue-open native contrast diagnostic completed nonaccepting"
        )
    }

    @MainActor
    private func positionSettingsHubDiagnosticsEntryForAXText(
        in app: XCUIApplication
    ) throws -> Bool {
        let settingsScreens = app.descendants(matching: .any).matching(
            identifier: "s1.settings.screen"
        )
        let settingsScrollViews = app.scrollViews.matching(
            identifier: "s1.settings.screen"
        )
        let diagnosticsEntries = app.descendants(matching: .any).matching(
            identifier: "s8.3.diagnostics.settings-entry"
        )
        let feedbackEntries = app.descendants(matching: .any).matching(
            identifier: "s8.4.feedback.settings-entry"
        )
        let inspectionStaticTexts = app.staticTexts.matching(
            NSPredicate(
                format: "identifier == '' AND label == %@",
                "Inspection data and photos are device-local and do not sync with the subscription."
            )
        )
        let navigationBars = app.navigationBars
        let tabBars = app.tabBars
        let keyboards = app.keyboards
        let inputViews = app.otherElements.matching(
            NSPredicate(format: "identifier == %@", "inputView")
        )
        let settingsScreen = settingsScreens.firstMatch
        let settingsScrollView = settingsScrollViews.firstMatch
        let diagnosticsEntry = diagnosticsEntries.firstMatch
        let feedbackEntry = feedbackEntries.firstMatch
        let inspectionStaticText = inspectionStaticTexts.firstMatch
        let navigationBar = navigationBars.firstMatch
        let tabBar = tabBars.firstMatch
        let contentInset: CGFloat = 16
        let receiverInset: CGFloat = 24
        let minimumGestureDistance: CGFloat = 44
        let shiftAllowance: CGFloat = 1
        let isValidFrame: (CGRect) -> Bool = { frame in
            !frame.isNull
                && !frame.isEmpty
                && !frame.isInfinite
                && frame.origin.x.isFinite
                && frame.origin.y.isFinite
                && frame.size.width.isFinite
                && frame.size.height.isFinite
        }

        guard app.state == .runningForeground,
              settingsScreens.count == 1,
              settingsScrollViews.count == 1,
              diagnosticsEntries.count == 1,
              feedbackEntries.count == 1,
              inspectionStaticTexts.count == 1,
              navigationBars.count == 1,
              tabBars.count == 1,
              keyboards.count == 0,
              inputViews.count == 0,
              settingsScreen.exists,
              settingsScreen.identifier == "s1.settings.screen",
              settingsScrollView.exists,
              settingsScrollView.identifier == "s1.settings.screen",
              settingsScrollView.elementType == .scrollView,
              diagnosticsEntry.exists,
              diagnosticsEntry.isEnabled,
              diagnosticsEntry.identifier == "s8.3.diagnostics.settings-entry",
              diagnosticsEntry.label == "View diagnostics",
              diagnosticsEntry.elementType == .button,
              feedbackEntry.exists,
              feedbackEntry.isEnabled,
              feedbackEntry.identifier == "s8.4.feedback.settings-entry",
              feedbackEntry.label == "Send feedback",
              feedbackEntry.elementType == .button,
              inspectionStaticText.exists,
              inspectionStaticText.isEnabled,
              inspectionStaticText.identifier.isEmpty,
              inspectionStaticText.label
                == "Inspection data and photos are device-local and do not sync with the subscription.",
              inspectionStaticText.elementType == .staticText,
              navigationBar.exists,
              tabBar.exists else {
            XCTFail("AX-text settings-hub positioning route is invalid.")
            return false
        }

        let frozenApplicationFrame = app.frame
        let frozenScreenFrame = settingsScreen.frame
        let frozenScrollFrame = settingsScrollView.frame
        let frozenNavigationFrame = navigationBar.frame
        let frozenTabBarFrame = tabBar.frame
        guard isValidFrame(frozenApplicationFrame),
              isValidFrame(frozenScreenFrame),
              isValidFrame(frozenScrollFrame),
              isValidFrame(frozenNavigationFrame),
              isValidFrame(frozenTabBarFrame),
              frozenScreenFrame == frozenScrollFrame else {
            XCTFail("AX-text settings-hub positioning geometry is invalid.")
            return false
        }
        var measuredInitialOvertravel: CGFloat?

        for initialAttemptIndex in 0..<4 {
            guard app.state == .runningForeground,
                  settingsScreens.count == 1,
                  settingsScrollViews.count == 1,
                  diagnosticsEntries.count == 1,
                  feedbackEntries.count == 1,
                  inspectionStaticTexts.count == 1,
                  navigationBars.count == 1,
                  tabBars.count == 1,
                  keyboards.count == 0,
                  inputViews.count == 0,
                  settingsScreen.exists,
                  settingsScreen.identifier == "s1.settings.screen",
                  settingsScreen.frame == frozenScreenFrame,
                  settingsScrollView.exists,
                  settingsScrollView.identifier == "s1.settings.screen",
                  settingsScrollView.elementType == .scrollView,
                  settingsScrollView.frame == frozenScrollFrame,
                  diagnosticsEntry.exists,
                  diagnosticsEntry.isEnabled,
                  diagnosticsEntry.identifier == "s8.3.diagnostics.settings-entry",
                  diagnosticsEntry.label == "View diagnostics",
                  diagnosticsEntry.elementType == .button,
                  feedbackEntry.exists,
                  feedbackEntry.isEnabled,
                  feedbackEntry.identifier == "s8.4.feedback.settings-entry",
                  feedbackEntry.label == "Send feedback",
                  feedbackEntry.elementType == .button,
                  inspectionStaticText.exists,
                  inspectionStaticText.isEnabled,
                  inspectionStaticText.identifier.isEmpty,
                  inspectionStaticText.label
                    == "Inspection data and photos are device-local and do not sync with the subscription.",
                  inspectionStaticText.elementType == .staticText,
                  navigationBar.exists,
                  navigationBar.frame == frozenNavigationFrame,
                  tabBar.exists,
                  tabBar.frame == frozenTabBarFrame,
                  app.frame == frozenApplicationFrame else {
                XCTFail("AX-text settings-hub route changed during initial positioning.")
                return false
            }

            let applicationFrame = app.frame
            let scrollFrame = settingsScrollView.frame
            let navigationFrame = navigationBar.frame
            let tabBarFrame = tabBar.frame
            let liveScrollFrame = scrollFrame.intersection(applicationFrame)
            let liveTop = max(liveScrollFrame.minY, navigationFrame.maxY)
            let liveBottom = min(
                liveScrollFrame.maxY,
                min(applicationFrame.maxY, tabBarFrame.minY)
            )
            let safeTop = liveTop + contentInset
            let safeBottom = liveBottom - contentInset
            let receiverTop = liveTop + receiverInset
            let receiverBottom = liveBottom - receiverInset
            let diagnosticsFrame = diagnosticsEntry.frame
            let feedbackFrame = feedbackEntry.frame
            guard isValidFrame(liveScrollFrame),
                  isValidFrame(diagnosticsFrame),
                  isValidFrame(feedbackFrame),
                  safeBottom > safeTop,
                  receiverBottom > receiverTop,
                  diagnosticsFrame.height <= safeBottom - safeTop,
                  feedbackFrame.height <= safeBottom - safeTop else {
                XCTFail("AX-text settings-hub initial live geometry is invalid.")
                return false
            }
            if diagnosticsFrame.minY >= safeTop,
               diagnosticsFrame.maxY <= safeBottom,
               feedbackFrame.minY >= safeTop,
               feedbackFrame.maxY <= safeBottom,
               diagnosticsEntry.isHittable,
               feedbackEntry.isHittable {
                break
            }

            let minimumShift = max(
                safeTop - diagnosticsFrame.minY,
                safeTop - feedbackFrame.minY
            )
            let maximumShift = min(
                safeBottom - diagnosticsFrame.maxY,
                safeBottom - feedbackFrame.maxY
            )
            let receiverCapacity = receiverBottom - receiverTop
            guard minimumShift <= maximumShift,
                  maximumShift < 0,
                  receiverCapacity >= minimumGestureDistance else {
                XCTFail("AX-text settings-hub requires no feasible initial upward shift.")
                return false
            }
            let recognizedMinimum = max(
                minimumShift,
                -receiverCapacity
            )
            let recognizedMaximum = min(
                maximumShift,
                -minimumGestureDistance
            )
            guard recognizedMinimum <= recognizedMaximum,
                  recognizedMaximum < 0 else {
                XCTFail("AX-text settings-hub initial upward shift is not recognizable.")
                return false
            }
            let dragDistance = recognizedMaximum
            let scrollOrigin = settingsScrollView.coordinate(
                withNormalizedOffset: CGVector(dx: 0, dy: 0)
            )
            let dragStart = scrollOrigin.withOffset(
                CGVector(
                    dx: scrollFrame.width / 2,
                    dy: receiverBottom - scrollFrame.minY
                )
            )
            let dragEnd = dragStart.withOffset(
                CGVector(dx: 0, dy: dragDistance)
            )
            let diagnosticsMinYBeforeDrag = diagnosticsFrame.minY
            let feedbackMinYBeforeDrag = feedbackFrame.minY
            dragStart.press(
                forDuration: 0.2,
                thenDragTo: dragEnd,
                withVelocity: .slow,
                thenHoldForDuration: 0.2
            )
            guard app.state == .runningForeground,
                  settingsScreens.count == 1,
                  settingsScrollViews.count == 1,
                  diagnosticsEntries.count == 1,
                  feedbackEntries.count == 1,
                  inspectionStaticTexts.count == 1,
                  navigationBars.count == 1,
                  tabBars.count == 1,
                  keyboards.count == 0,
                  inputViews.count == 0,
                  settingsScreen.exists,
                  settingsScreen.frame == frozenScreenFrame,
                  settingsScrollView.exists,
                  settingsScrollView.frame == frozenScrollFrame,
                  diagnosticsEntry.exists,
                  diagnosticsEntry.isEnabled,
                  diagnosticsEntry.identifier == "s8.3.diagnostics.settings-entry",
                  diagnosticsEntry.label == "View diagnostics",
                  diagnosticsEntry.elementType == .button,
                  feedbackEntry.exists,
                  feedbackEntry.isEnabled,
                  feedbackEntry.identifier == "s8.4.feedback.settings-entry",
                  feedbackEntry.label == "Send feedback",
                  feedbackEntry.elementType == .button,
                  inspectionStaticText.exists,
                  inspectionStaticText.isEnabled,
                  inspectionStaticText.identifier.isEmpty,
                  inspectionStaticText.label
                    == "Inspection data and photos are device-local and do not sync with the subscription.",
                  inspectionStaticText.elementType == .staticText,
                  navigationBar.exists,
                  navigationBar.frame == frozenNavigationFrame,
                  tabBar.exists,
                  tabBar.frame == frozenTabBarFrame,
                  app.frame == frozenApplicationFrame else {
                XCTFail("AX-text settings-hub route changed after initial positioning.")
                return false
            }
            let observedDiagnosticsShift =
                diagnosticsEntry.frame.minY - diagnosticsMinYBeforeDrag
            let observedFeedbackShift = feedbackEntry.frame.minY - feedbackMinYBeforeDrag
            let diagnosticsOvertravel = dragDistance - observedDiagnosticsShift
            let feedbackOvertravel = dragDistance - observedFeedbackShift
            guard observedDiagnosticsShift < 0,
                  observedFeedbackShift < 0,
                  observedDiagnosticsShift * dragDistance > 0,
                  observedFeedbackShift * dragDistance > 0,
                  abs(observedDiagnosticsShift - observedFeedbackShift) <= shiftAllowance,
                  diagnosticsOvertravel.isFinite,
                  feedbackOvertravel.isFinite,
                  abs(diagnosticsOvertravel) <= receiverInset + shiftAllowance,
                  abs(feedbackOvertravel) <= receiverInset + shiftAllowance,
                  abs(diagnosticsOvertravel - feedbackOvertravel) <= shiftAllowance else {
                let stateID = "state.settings.hub"
                let expectedMigratedStateIDs = Array(
                    Self.segmentedRouteStateIDs[50..<58]
                )
                let expectedContrastExceptionStateIDs = [
                    "state.report-correction.validation-error",
                ]
                guard let shard = automationShard,
                      shard.shardID == "s10.4.current.ax-text",
                      automationSegment == .segment3,
                      automationSegment.replayCount == 22,
                      automationSegment.ownedStartOrdinal == 51,
                      automationSegment.ownedCount == 17,
                      automationSegment.finalOrdinal == 67,
                      Self.segmentedRouteStateIDs.count == 67,
                      Set(Self.segmentedRouteStateIDs).count == 67,
                      Self.segmentedRouteStateIDs[58] == stateID,
                      segmentedRouteStateCursor == 58,
                      migratedStateIDs == expectedMigratedStateIDs,
                      automationAXTreeDigests.keys.sorted()
                        == expectedMigratedStateIDs.sorted(),
                      automationContrastExceptions.keys.sorted()
                        == expectedContrastExceptionStateIDs,
                      !automatedSegmentFinished,
                      app.state == .runningForeground else {
                    throw AutomationConfigurationError.invalid(
                        "S10.4 AX-text settings-hub initial-positioning progress diagnostic gate is invalid"
                    )
                }
                let publicNodeObject: (XCUIElement) -> [String: Any] = {
                    element in
                    [
                        "exists": element.exists,
                        "isEnabled": element.isEnabled,
                        "isHittable": element.isHittable,
                        "identifier": element.identifier,
                        "label": element.label,
                        "value": (element.value as? String).map { $0 as Any }
                            ?? NSNull(),
                        "elementTypeRawValue": element.elementType.rawValue,
                        "elementTypeDescription": String(
                            describing: element.elementType
                        ),
                        "frame": self.auditFrameObject(element.frame),
                    ]
                }
                let publicQueryObject: (XCUIElementQuery) -> [String: Any] = {
                    query in
                    let actualCount = query.count
                    return [
                        "count": actualCount,
                        "elements": (0..<actualCount).map { index in
                            publicNodeObject(query.element(boundBy: index))
                        },
                    ]
                }
                let progressRelations: [(String, Bool)] = [
                    (
                        "observedDiagnosticsShiftNegative",
                        observedDiagnosticsShift < 0
                    ),
                    (
                        "observedFeedbackShiftNegative",
                        observedFeedbackShift < 0
                    ),
                    (
                        "diagnosticsSignedProgress",
                        observedDiagnosticsShift * dragDistance > 0
                    ),
                    (
                        "feedbackSignedProgress",
                        observedFeedbackShift * dragDistance > 0
                    ),
                    (
                        "rigidShiftWithinAllowance",
                        abs(observedDiagnosticsShift - observedFeedbackShift)
                            <= shiftAllowance
                    ),
                    (
                        "diagnosticsOvertravelFinite",
                        diagnosticsOvertravel.isFinite
                    ),
                    (
                        "feedbackOvertravelFinite",
                        feedbackOvertravel.isFinite
                    ),
                    (
                        "diagnosticsOvertravelWithinReceiverInset",
                        abs(diagnosticsOvertravel) <= receiverInset + shiftAllowance
                    ),
                    (
                        "feedbackOvertravelWithinReceiverInset",
                        abs(feedbackOvertravel) <= receiverInset + shiftAllowance
                    ),
                    (
                        "rigidOvertravelWithinAllowance",
                        abs(diagnosticsOvertravel - feedbackOvertravel)
                            <= shiftAllowance
                    ),
                ]
                let orderedProgressRelations: [[String: Any]] =
                    progressRelations.map { relation in
                        [
                            "name": relation.0,
                            "passed": relation.1,
                        ]
                    }
                let failedProgressRelations = progressRelations.compactMap {
                    relation in
                    relation.1 ? nil : relation.0
                }
                let diagnosticContext: [String: Any] = [
                    "schemaVersion": 1,
                    "acceptanceEligible": false,
                    "shardID": shard.shardID,
                    "requirementID": shard.requirementID,
                    "deviceProfileID": shard.deviceProfileID,
                    "segmentID": automationSegment.rawValue,
                    "segmentReplayCount": automationSegment.replayCount,
                    "segmentOwnedCount": automationSegment.ownedCount,
                    "segmentFinalOrdinal": automationSegment.finalOrdinal,
                    "segmentStateCursor": segmentedRouteStateCursor,
                    "migratedStateIDs": migratedStateIDs,
                    "stateID": stateID,
                    "stateOrdinal": 59,
                    "predecessorStateID": "state.feedback.review-ready",
                    "predecessorOrdinal": 58,
                    "successorStateID": "state.backup.ready",
                    "successorOrdinal": 60,
                    "applicationState": String(describing: app.state),
                    "applicationStateRawValue": app.state.rawValue,
                    "applicationForeground": app.state == .runningForeground,
                    "applicationFrame": self.auditFrameObject(app.frame),
                    "attemptOrdinal": initialAttemptIndex + 1,
                    "contentInset": Double(contentInset),
                    "receiverInset": Double(receiverInset),
                    "minimumGestureDistance": Double(minimumGestureDistance),
                    "shiftAllowance": Double(shiftAllowance),
                    "liveTop": Double(liveTop),
                    "liveBottom": Double(liveBottom),
                    "safeTop": Double(safeTop),
                    "safeBottom": Double(safeBottom),
                    "receiverTop": Double(receiverTop),
                    "receiverBottom": Double(receiverBottom),
                    "receiverCapacity": Double(receiverCapacity),
                    "minimumShift": Double(minimumShift),
                    "maximumShift": Double(maximumShift),
                    "recognizedMinimum": Double(recognizedMinimum),
                    "recognizedMaximum": Double(recognizedMaximum),
                    "dragDistance": Double(dragDistance),
                    "dragStart": [
                        "x": Double(scrollFrame.midX),
                        "y": Double(receiverBottom),
                    ],
                    "dragEnd": [
                        "x": Double(scrollFrame.midX),
                        "y": Double(receiverBottom + dragDistance),
                    ],
                    "observedDiagnosticsShift": Double(observedDiagnosticsShift),
                    "observedFeedbackShift": Double(observedFeedbackShift),
                    "diagnosticsOvertravel": Double(diagnosticsOvertravel),
                    "feedbackOvertravel": Double(feedbackOvertravel),
                    "orderedProgressRelations": orderedProgressRelations,
                    "failedProgressRelations": failedProgressRelations,
                    "frozenFrames": [
                        "application": self.auditFrameObject(
                            frozenApplicationFrame
                        ),
                        "screen": self.auditFrameObject(frozenScreenFrame),
                        "scrollView": self.auditFrameObject(frozenScrollFrame),
                        "navigationBar": self.auditFrameObject(
                            frozenNavigationFrame
                        ),
                        "tabBar": self.auditFrameObject(frozenTabBarFrame),
                    ],
                    "beforeFrames": [
                        "diagnosticsEntry": self.auditFrameObject(
                            diagnosticsFrame
                        ),
                        "feedbackEntry": self.auditFrameObject(feedbackFrame),
                    ],
                    "afterFrames": [
                        "diagnosticsEntry": self.auditFrameObject(
                            diagnosticsEntry.frame
                        ),
                        "feedbackEntry": self.auditFrameObject(
                            feedbackEntry.frame
                        ),
                        "inspectionText": self.auditFrameObject(
                            inspectionStaticText.frame
                        ),
                    ],
                    "queries": [
                        "settingsScreens": publicQueryObject(settingsScreens),
                        "settingsScrollViews": publicQueryObject(
                            settingsScrollViews
                        ),
                        "diagnosticsEntries": publicQueryObject(
                            diagnosticsEntries
                        ),
                        "feedbackEntries": publicQueryObject(feedbackEntries),
                        "inspectionStaticTexts": publicQueryObject(
                            inspectionStaticTexts
                        ),
                        "navigationBars": publicQueryObject(navigationBars),
                        "tabBars": publicQueryObject(tabBars),
                        "keyboards": publicQueryObject(keyboards),
                        "inputViews": publicQueryObject(inputViews),
                    ],
                ]
                guard JSONSerialization.isValidJSONObject(diagnosticContext),
                      let contextData = try? JSONSerialization.data(
                        withJSONObject: diagnosticContext,
                        options: [.sortedKeys]
                      ),
                      let contextText = String(
                        data: contextData,
                        encoding: .utf8
                      ),
                      !contextText.contains("\n") else {
                    throw AutomationConfigurationError.invalid(
                        "S10.4 AX-text settings-hub initial-positioning progress diagnostic JSON is invalid"
                    )
                }
                self.printJSONLine(
                    prefix:
                        "S10_4_AX_TEXT_SETTINGS_HUB_INITIAL_POSITIONING_PROGRESS_DIAGNOSTIC",
                    object: diagnosticContext
                )
                let appAttachment = XCTAttachment(screenshot: app.screenshot())
                appAttachment.name =
                    "S10.4 AX-text settings-hub initial-positioning progress diagnostic app"
                appAttachment.lifetime = .keepAlways
                add(appAttachment)
                let treeAttachment = XCTAttachment(string: app.debugDescription)
                treeAttachment.name =
                    "S10.4 AX-text settings-hub initial-positioning progress diagnostic tree"
                treeAttachment.lifetime = .keepAlways
                add(treeAttachment)
                let contextAttachment = XCTAttachment(string: contextText)
                contextAttachment.name =
                    "S10.4 AX-text settings-hub initial-positioning progress diagnostic context"
                contextAttachment.lifetime = .keepAlways
                add(contextAttachment)
                throw AutomationConfigurationError.invalid(
                    "S10.4 AX-text settings-hub initial-positioning progress diagnostic completed nonaccepting"
                )
            }
            measuredInitialOvertravel = (
                diagnosticsOvertravel + feedbackOvertravel
            ) / 2
        }

        let initialApplicationFrame = app.frame
        let initialScrollFrame = settingsScrollView.frame.intersection(
            initialApplicationFrame
        )
        let initialSafeTop = max(
            initialScrollFrame.minY,
            navigationBar.frame.maxY
        ) + contentInset
        let initialSafeBottom = min(
            initialScrollFrame.maxY,
            min(initialApplicationFrame.maxY, tabBar.frame.minY)
        ) - contentInset
        let initialDiagnosticsFrame = diagnosticsEntry.frame
        let initialFeedbackFrame = feedbackEntry.frame
        guard app.state == .runningForeground,
              settingsScreens.count == 1,
              settingsScrollViews.count == 1,
              diagnosticsEntries.count == 1,
              feedbackEntries.count == 1,
              inspectionStaticTexts.count == 1,
              navigationBars.count == 1,
              tabBars.count == 1,
              keyboards.count == 0,
              inputViews.count == 0,
              settingsScreen.exists,
              settingsScreen.frame == frozenScreenFrame,
              settingsScrollView.exists,
              settingsScrollView.frame == frozenScrollFrame,
              diagnosticsEntry.exists,
              diagnosticsEntry.isEnabled,
              diagnosticsEntry.identifier == "s8.3.diagnostics.settings-entry",
              diagnosticsEntry.label == "View diagnostics",
              diagnosticsEntry.elementType == .button,
              feedbackEntry.exists,
              feedbackEntry.isEnabled,
              feedbackEntry.identifier == "s8.4.feedback.settings-entry",
              feedbackEntry.label == "Send feedback",
              feedbackEntry.elementType == .button,
              inspectionStaticText.exists,
              inspectionStaticText.isEnabled,
              inspectionStaticText.identifier.isEmpty,
              inspectionStaticText.label
                == "Inspection data and photos are device-local and do not sync with the subscription.",
              inspectionStaticText.elementType == .staticText,
              navigationBar.exists,
              navigationBar.frame == frozenNavigationFrame,
              tabBar.exists,
              tabBar.frame == frozenTabBarFrame,
              app.frame == frozenApplicationFrame,
              isValidFrame(initialScrollFrame),
              isValidFrame(initialDiagnosticsFrame),
              isValidFrame(initialFeedbackFrame),
              initialSafeBottom > initialSafeTop,
              initialDiagnosticsFrame.minY >= initialSafeTop,
              initialDiagnosticsFrame.maxY <= initialSafeBottom,
              initialFeedbackFrame.minY >= initialSafeTop,
              initialFeedbackFrame.maxY <= initialSafeBottom,
              diagnosticsEntry.isHittable,
              feedbackEntry.isHittable else {
            XCTFail("AX-text settings-hub initial composition is unsafe.")
            return false
        }

        for _ in 0..<4 {
            guard app.state == .runningForeground,
                  settingsScreens.count == 1,
                  settingsScrollViews.count == 1,
                  diagnosticsEntries.count == 1,
                  feedbackEntries.count == 1,
                  inspectionStaticTexts.count == 1,
                  navigationBars.count == 1,
                  tabBars.count == 1,
                  keyboards.count == 0,
                  inputViews.count == 0,
                  settingsScreen.exists,
                  settingsScreen.identifier == "s1.settings.screen",
                  settingsScreen.frame == frozenScreenFrame,
                  settingsScrollView.exists,
                  settingsScrollView.identifier == "s1.settings.screen",
                  settingsScrollView.elementType == .scrollView,
                  settingsScrollView.frame == frozenScrollFrame,
                  diagnosticsEntry.exists,
                  diagnosticsEntry.isEnabled,
                  diagnosticsEntry.identifier == "s8.3.diagnostics.settings-entry",
                  diagnosticsEntry.label == "View diagnostics",
                  diagnosticsEntry.elementType == .button,
                  feedbackEntry.exists,
                  feedbackEntry.isEnabled,
                  feedbackEntry.identifier == "s8.4.feedback.settings-entry",
                  feedbackEntry.label == "Send feedback",
                  feedbackEntry.elementType == .button,
                  inspectionStaticText.exists,
                  inspectionStaticText.isEnabled,
                  inspectionStaticText.identifier.isEmpty,
                  inspectionStaticText.label
                    == "Inspection data and photos are device-local and do not sync with the subscription.",
                  inspectionStaticText.elementType == .staticText,
                  navigationBar.exists,
                  navigationBar.frame == frozenNavigationFrame,
                  tabBar.exists,
                  tabBar.frame == frozenTabBarFrame,
                  app.frame == frozenApplicationFrame else {
                XCTFail("AX-text settings-hub route changed during positioning.")
                return false
            }

            let applicationFrame = app.frame
            let scrollFrame = settingsScrollView.frame
            let navigationFrame = navigationBar.frame
            let tabBarFrame = tabBar.frame
            let liveScrollFrame = scrollFrame.intersection(applicationFrame)
            let liveTop = max(liveScrollFrame.minY, navigationFrame.maxY)
            let liveBottom = min(
                liveScrollFrame.maxY,
                min(applicationFrame.maxY, tabBarFrame.minY)
            )
            let safeTop = liveTop + contentInset
            let safeBottom = liveBottom - contentInset
            let receiverTop = liveTop + receiverInset
            let receiverBottom = liveBottom - receiverInset
            let diagnosticsFrame = diagnosticsEntry.frame
            let feedbackFrame = feedbackEntry.frame
            let inspectionFrame = inspectionStaticText.frame
            guard isValidFrame(liveScrollFrame),
                  isValidFrame(diagnosticsFrame),
                  isValidFrame(feedbackFrame),
                  isValidFrame(inspectionFrame),
                  safeBottom > safeTop,
                  receiverBottom > receiverTop,
                  diagnosticsFrame.height <= safeBottom - safeTop,
                  feedbackFrame.height <= safeBottom - safeTop,
                  inspectionFrame.height <= safeBottom - safeTop else {
                XCTFail("AX-text settings-hub live geometry is invalid.")
                return false
            }
            if diagnosticsFrame.minY >= liveTop,
               diagnosticsFrame.maxY <= safeBottom,
               feedbackFrame.minY >= safeTop,
               feedbackFrame.maxY <= safeBottom,
               inspectionFrame.minY >= safeTop,
               inspectionFrame.maxY <= safeBottom,
               diagnosticsEntry.isHittable,
               feedbackEntry.isHittable,
               inspectionStaticText.isHittable {
                return true
            }

            let minimumShift = max(
                liveTop - diagnosticsFrame.minY,
                max(
                    safeTop - feedbackFrame.minY,
                    safeTop - inspectionFrame.minY
                )
            )
            let maximumShift = min(
                safeBottom - diagnosticsFrame.maxY,
                min(
                    safeBottom - feedbackFrame.maxY,
                    safeBottom - inspectionFrame.maxY
                )
            )
            let receiverCapacity = receiverBottom - receiverTop
            guard minimumShift <= maximumShift,
                  maximumShift < 0,
                  receiverCapacity >= minimumGestureDistance else {
                XCTFail("AX-text settings-hub requires no feasible upward shift.")
                return false
            }
            guard let measuredInitialOvertravel,
                  measuredInitialOvertravel.isFinite,
                  abs(measuredInitialOvertravel) <= receiverInset + shiftAllowance else {
                XCTFail("AX-text settings-hub initial overtravel is unavailable.")
                return false
            }
            let recognizedMinimum = max(
                minimumShift + measuredInitialOvertravel,
                -receiverCapacity
            )
            let recognizedMaximum = min(
                maximumShift + measuredInitialOvertravel,
                -minimumGestureDistance
            )
            guard recognizedMinimum <= recognizedMaximum,
                  recognizedMaximum < 0 else {
                XCTFail("AX-text settings-hub upward shift is not recognizable.")
                return false
            }
            let dragDistance = (recognizedMinimum + recognizedMaximum) / 2
            let expectedObservedShift = dragDistance - measuredInitialOvertravel
            guard expectedObservedShift >= minimumShift,
                  expectedObservedShift <= maximumShift else {
                XCTFail("AX-text settings-hub compensated shift is outside its interval.")
                return false
            }
            let scrollOrigin = settingsScrollView.coordinate(
                withNormalizedOffset: CGVector(dx: 0, dy: 0)
            )
            let dragStart = scrollOrigin.withOffset(
                CGVector(
                    dx: scrollFrame.width / 2,
                    dy: receiverBottom - scrollFrame.minY
                )
            )
            let dragEnd = dragStart.withOffset(
                CGVector(dx: 0, dy: dragDistance)
            )
            let diagnosticsMinYBeforeDrag = diagnosticsFrame.minY
            let feedbackMinYBeforeDrag = feedbackFrame.minY
            let inspectionMinYBeforeDrag = inspectionFrame.minY
            dragStart.press(
                forDuration: 0.2,
                thenDragTo: dragEnd,
                withVelocity: .slow,
                thenHoldForDuration: 0.2
            )
            guard app.state == .runningForeground,
                  settingsScreens.count == 1,
                  settingsScrollViews.count == 1,
                  diagnosticsEntries.count == 1,
                  feedbackEntries.count == 1,
                  inspectionStaticTexts.count == 1,
                  navigationBars.count == 1,
                  tabBars.count == 1,
                  keyboards.count == 0,
                  inputViews.count == 0,
                  settingsScreen.exists,
                  settingsScreen.frame == frozenScreenFrame,
                  settingsScrollView.exists,
                  settingsScrollView.frame == frozenScrollFrame,
                  diagnosticsEntry.exists,
                  diagnosticsEntry.isEnabled,
                  diagnosticsEntry.identifier == "s8.3.diagnostics.settings-entry",
                  diagnosticsEntry.label == "View diagnostics",
                  diagnosticsEntry.elementType == .button,
                  feedbackEntry.exists,
                  feedbackEntry.isEnabled,
                  feedbackEntry.identifier == "s8.4.feedback.settings-entry",
                  feedbackEntry.label == "Send feedback",
                  feedbackEntry.elementType == .button,
                  inspectionStaticText.exists,
                  inspectionStaticText.isEnabled,
                  inspectionStaticText.identifier.isEmpty,
                  inspectionStaticText.label
                    == "Inspection data and photos are device-local and do not sync with the subscription.",
                  inspectionStaticText.elementType == .staticText,
                  navigationBar.exists,
                  navigationBar.frame == frozenNavigationFrame,
                  tabBar.exists,
                  tabBar.frame == frozenTabBarFrame,
                  app.frame == frozenApplicationFrame else {
                XCTFail("AX-text settings-hub route changed after positioning.")
                return false
            }
            let observedDiagnosticsShift =
                diagnosticsEntry.frame.minY - diagnosticsMinYBeforeDrag
            let observedFeedbackShift = feedbackEntry.frame.minY - feedbackMinYBeforeDrag
            let observedInspectionShift =
                inspectionStaticText.frame.minY - inspectionMinYBeforeDrag
            guard observedDiagnosticsShift < 0,
                  observedFeedbackShift < 0,
                  observedInspectionShift < 0,
                  observedDiagnosticsShift * dragDistance > 0,
                  observedFeedbackShift * dragDistance > 0,
                  observedInspectionShift * dragDistance > 0,
                  abs(observedDiagnosticsShift - observedFeedbackShift) <= shiftAllowance,
                  abs(observedFeedbackShift - observedInspectionShift) <= shiftAllowance,
                  observedDiagnosticsShift >= minimumShift,
                  observedDiagnosticsShift <= maximumShift else {
                XCTFail("AX-text settings-hub positioning gesture made no signed progress.")
                return false
            }
        }

        guard app.state == .runningForeground,
              settingsScreens.count == 1,
              settingsScrollViews.count == 1,
              diagnosticsEntries.count == 1,
              feedbackEntries.count == 1,
              inspectionStaticTexts.count == 1,
              navigationBars.count == 1,
              tabBars.count == 1,
              keyboards.count == 0,
              inputViews.count == 0,
              settingsScreen.exists,
              settingsScreen.frame == frozenScreenFrame,
              settingsScrollView.exists,
              settingsScrollView.frame == frozenScrollFrame,
              diagnosticsEntry.exists,
              diagnosticsEntry.isEnabled,
              diagnosticsEntry.identifier == "s8.3.diagnostics.settings-entry",
              diagnosticsEntry.label == "View diagnostics",
              diagnosticsEntry.elementType == .button,
              feedbackEntry.exists,
              feedbackEntry.isEnabled,
              feedbackEntry.identifier == "s8.4.feedback.settings-entry",
              feedbackEntry.label == "Send feedback",
              feedbackEntry.elementType == .button,
              inspectionStaticText.exists,
              inspectionStaticText.isEnabled,
              inspectionStaticText.identifier.isEmpty,
              inspectionStaticText.label
                == "Inspection data and photos are device-local and do not sync with the subscription.",
              inspectionStaticText.elementType == .staticText,
              navigationBar.exists,
              navigationBar.frame == frozenNavigationFrame,
              tabBar.exists,
              tabBar.frame == frozenTabBarFrame,
              app.frame == frozenApplicationFrame else {
            XCTFail("AX-text settings-hub final route changed.")
            return false
        }
        let finalApplicationFrame = app.frame
        let finalScrollFrame = settingsScrollView.frame.intersection(
            finalApplicationFrame
        )
        let finalSafeTop = max(
            finalScrollFrame.minY,
            navigationBar.frame.maxY
        ) + contentInset
        let finalSafeBottom = min(
            finalScrollFrame.maxY,
            min(finalApplicationFrame.maxY, tabBar.frame.minY)
        ) - contentInset
        let finalDiagnosticsFrame = diagnosticsEntry.frame
        let finalFeedbackFrame = feedbackEntry.frame
        let finalInspectionFrame = inspectionStaticText.frame
        guard isValidFrame(finalScrollFrame),
              isValidFrame(finalDiagnosticsFrame),
              isValidFrame(finalFeedbackFrame),
              isValidFrame(finalInspectionFrame),
              finalSafeBottom > finalSafeTop,
              finalDiagnosticsFrame.minY >= finalScrollFrame.minY,
              finalDiagnosticsFrame.maxY <= finalSafeBottom,
              finalFeedbackFrame.minY >= finalSafeTop,
              finalFeedbackFrame.maxY <= finalSafeBottom,
              finalInspectionFrame.minY >= finalSafeTop,
              finalInspectionFrame.maxY <= finalSafeBottom,
              diagnosticsEntry.isHittable,
              feedbackEntry.isHittable,
              inspectionStaticText.isHittable else {
            XCTFail("AX-text settings-hub final composition is unsafe.")
            return false
        }
        return true
    }

    @MainActor
    private func diagnoseSegment3AXTextSettingsHubNativeContrast(
        in app: XCUIApplication
    ) throws {
        let stateID = "state.settings.hub"
        let expectedMigratedStateIDs = Array(
            Self.segmentedRouteStateIDs.prefix(59)
        )
        let expectedAXTreeDigestStateIDs = Array(
            Self.segmentedRouteStateIDs.prefix(58)
        )
        let expectedContrastExceptionStateIDs = [
            "state.check-preflight.ready",
            "state.issue.open",
            "state.issue.recheck-due",
            "state.issue.resolved",
            "state.new-sign.editing",
            "state.paywall.purchase-complete",
            "state.recheck-capture.wide-ready",
            "state.recheck-preflight.ready",
            "state.report-correction.validation-error",
            "state.report-history.ready",
            "state.reports-index.ready",
        ]
        guard let shard = automationShard,
              shard.shardID == "s10.4.current.ax-text",
              automationSegment == .none,
              automationSegment.replayCount == 0,
              automationSegment.ownedStartOrdinal == 1,
              automationSegment.ownedCount == 67,
              automationSegment.finalOrdinal == 67,
              Self.segmentedRouteStateIDs.count == 67,
              Set(Self.segmentedRouteStateIDs).count == 67,
              Self.segmentedRouteStateIDs[58] == stateID,
              segmentedRouteStateCursor == 0,
              migratedStateIDs == expectedMigratedStateIDs,
              automationAXTreeDigests.keys.sorted()
                == expectedAXTreeDigestStateIDs.sorted(),
              automationContrastExceptions.keys.sorted()
                == expectedContrastExceptionStateIDs,
              !automatedSegmentFinished,
              app.state == .runningForeground else {
            throw AutomationConfigurationError.invalid(
                "S10.4 AX-text settings-hub native contrast diagnostic gate is invalid"
            )
        }

        let diagnosticQueryBindings: [(
            name: String,
            query: XCUIElementQuery
        )] = [
            (
                "settingsScreens",
                app.descendants(matching: .any).matching(
                    identifier: "s1.settings.screen"
                )
            ),
            (
                "settingsScrollViews",
                app.scrollViews.matching(identifier: "s1.settings.screen")
            ),
            (
                "backupEntries",
                app.descendants(matching: .any).matching(
                    identifier: "s6.2.backup.settings-entry"
                )
            ),
            (
                "diagnosticsEntries",
                app.descendants(matching: .any).matching(
                    identifier: "s8.3.diagnostics.settings-entry"
                )
            ),
            (
                "feedbackEntries",
                app.descendants(matching: .any).matching(
                    identifier: "s8.4.feedback.settings-entry"
                )
            ),
            (
                "restoreEntries",
                app.descendants(matching: .any).matching(
                    identifier: "s6.5.restore.settings-entry"
                )
            ),
            (
                "paywallEntries",
                app.descendants(matching: .any).matching(
                    identifier: "s7.2.settings.paywall"
                )
            ),
            (
                "restorePurchaseEntries",
                app.descendants(matching: .any).matching(
                    identifier: "s7.3.settings.restore-purchases"
                )
            ),
            (
                "eraseEntries",
                app.descendants(matching: .any).matching(
                    identifier: "s6.6.settings.erase-all"
                )
            ),
            ("navigationBars", app.navigationBars),
            ("tabBars", app.tabBars),
            ("keyboards", app.keyboards),
            (
                "inputViews",
                app.otherElements.matching(
                    NSPredicate(format: "identifier == %@", "inputView")
                )
            ),
        ]
        let diagnosticElementObject: (XCUIElement) -> [String: Any] = {
            element in
            let valueObject: Any
            if let value = element.value as? String {
                valueObject = value
            } else {
                valueObject = NSNull()
            }
            return [
                "exists": element.exists,
                "isEnabled": element.isEnabled,
                "isHittable": element.isHittable,
                "identifier": element.identifier,
                "label": element.label,
                "value": valueObject,
                "elementTypeRawValue": element.elementType.rawValue,
                "elementTypeDescription": String(describing: element.elementType),
                "frame": self.auditFrameObject(element.frame),
            ]
        }
        let diagnosticQueryObject: (XCUIElementQuery) -> [String: Any] = {
            query in
            let count = query.count
            var elements: [[String: Any]] = []
            for index in 0..<count {
                elements.append(
                    diagnosticElementObject(query.element(boundBy: index))
                )
            }
            return [
                "count": count,
                "elements": elements,
            ]
        }
        var diagnosticQueryObjects: [String: Any] = [:]
        for binding in diagnosticQueryBindings {
            diagnosticQueryObjects[binding.name] = diagnosticQueryObject(binding.query)
        }
        let diagnosticContext: [String: Any] = [
            "schemaVersion": 1,
            "acceptanceEligible": false,
            "shardID": shard.shardID,
            "requirementID": shard.requirementID,
            "deviceProfileID": shard.deviceProfileID,
            "segmentID": automationSegment.rawValue,
            "segmentReplayCount": automationSegment.replayCount,
            "segmentOwnedStartOrdinal": automationSegment.ownedStartOrdinal,
            "segmentOwnedCount": automationSegment.ownedCount,
            "segmentFinalOrdinal": automationSegment.finalOrdinal,
            "segmentStateCursor": segmentedRouteStateCursor,
            "stateID": stateID,
            "stateOrdinal": 59,
            "predecessorStateID": "state.feedback.review-ready",
            "predecessorOrdinal": 58,
            "successorStateID": "state.backup.ready",
            "successorOrdinal": 60,
            "migratedStateIDs": migratedStateIDs,
            "axTreeDigestStateIDs": automationAXTreeDigests.keys.sorted(),
            "contrastExceptionStateIDs": automationContrastExceptions.keys.sorted(),
            "applicationState": String(describing: app.state),
            "applicationStateRawValue": app.state.rawValue,
            "applicationForeground": app.state == .runningForeground,
            "applicationFrame": auditFrameObject(app.frame),
            "application": diagnosticElementObject(app),
            "queries": diagnosticQueryObjects,
        ]
        printJSONLine(
            prefix:
                "S10_4_AX_TEXT_SETTINGS_HUB_NATIVE_CONTRAST_CONTEXT_DIAGNOSTIC",
            object: diagnosticContext
        )

        let appAttachment = XCTAttachment(screenshot: app.screenshot())
        appAttachment.name =
            "S10.4 AX-text settings-hub native contrast diagnostic app"
        appAttachment.lifetime = .keepAlways
        add(appAttachment)
        let treeAttachment = XCTAttachment(string: app.debugDescription)
        treeAttachment.name =
            "S10.4 AX-text settings-hub native contrast diagnostic tree"
        treeAttachment.lifetime = .keepAlways
        add(treeAttachment)
        let contextData = try JSONSerialization.data(
            withJSONObject: diagnosticContext,
            options: [.prettyPrinted, .sortedKeys]
        )
        let contextAttachment = XCTAttachment(
            string: String(decoding: contextData, as: UTF8.self)
        )
        contextAttachment.name =
            "S10.4 AX-text settings-hub native contrast diagnostic context"
        contextAttachment.lifetime = .keepAlways
        add(contextAttachment)

        var observedIssueCount = 0
        var auditedElementCount = 0
        try app.performAccessibilityAudit(for: .contrast) { issue in
            observedIssueCount += 1
            let auditedElement = issue.element
            var diagnosticIssue: [String: Any] = [
                "schemaVersion": 1,
                "acceptanceEligible": false,
                "shardID": shard.shardID,
                "requirementID": shard.requirementID,
                "deviceProfileID": shard.deviceProfileID,
                "segmentID": self.automationSegment.rawValue,
                "segmentStateCursor": self.segmentedRouteStateCursor,
                "stateID": stateID,
                "stateOrdinal": 59,
                "issueOrdinal": observedIssueCount,
                "auditTypeRawValue": String(issue.auditType.rawValue),
                "compactDescription": issue.compactDescription,
                "detailedDescription": issue.detailedDescription,
                "elementExists": NSNull(),
                "elementEnabled": NSNull(),
                "elementHittable": NSNull(),
                "elementIdentifier": NSNull(),
                "elementLabel": NSNull(),
                "elementValue": NSNull(),
                "elementTypeRawValue": NSNull(),
                "elementTypeDescription": NSNull(),
                "elementFrame": NSNull(),
                "applicationFrame": self.auditFrameObject(app.frame),
            ]
            if let auditedElement {
                auditedElementCount += 1
                let valueObject: Any
                if let value = auditedElement.value as? String {
                    valueObject = value
                } else {
                    valueObject = NSNull()
                }
                diagnosticIssue["elementExists"] = auditedElement.exists
                diagnosticIssue["elementEnabled"] = auditedElement.isEnabled
                diagnosticIssue["elementHittable"] = auditedElement.isHittable
                diagnosticIssue["elementIdentifier"] = auditedElement.identifier
                diagnosticIssue["elementLabel"] = auditedElement.label
                diagnosticIssue["elementValue"] = valueObject
                diagnosticIssue["elementTypeRawValue"] =
                    auditedElement.elementType.rawValue
                diagnosticIssue["elementTypeDescription"] =
                    String(describing: auditedElement.elementType)
                diagnosticIssue["elementFrame"] =
                    self.auditFrameObject(auditedElement.frame)
            }
            self.printJSONLine(
                prefix:
                    "S10_4_AX_TEXT_SETTINGS_HUB_NATIVE_CONTRAST_ISSUE_DIAGNOSTIC",
                object: diagnosticIssue
            )
            if let auditedElement {
                let issueAttachment = XCTAttachment(
                    screenshot: auditedElement.screenshot()
                )
                issueAttachment.name =
                    "S10.4 AX-text settings-hub native contrast diagnostic audited element "
                        + String(observedIssueCount)
                issueAttachment.lifetime = .keepAlways
                self.add(issueAttachment)
            }
            return true
        }
        printJSONLine(
            prefix:
                "S10_4_AX_TEXT_SETTINGS_HUB_NATIVE_CONTRAST_COUNT_DIAGNOSTIC",
            object: [
                "schemaVersion": 1,
                "acceptanceEligible": false,
                "shardID": shard.shardID,
                "segmentID": automationSegment.rawValue,
                "stateID": stateID,
                "stateOrdinal": 59,
                "segmentStateCursor": segmentedRouteStateCursor,
                "observedIssueCount": observedIssueCount,
                "auditedElementCount": auditedElementCount,
            ]
        )
        throw AutomationConfigurationError.invalid(
            "S10.4 AX-text settings-hub native contrast diagnostic completed nonaccepting"
        )
    }

    @MainActor
    private func diagnoseSegment3AXTextSignSelectionNativeContrast(
        in app: XCUIApplication
    ) throws {
        let stateID = "state.sign-selection.ready"
        let expectedMigratedStateIDs = Array(
            Self.segmentedRouteStateIDs[50..<66]
        )
        let expectedAXTreeDigestStateIDs = Array(
            Self.segmentedRouteStateIDs[50..<65]
        )
        let expectedContrastExceptionStateIDs = [
            "state.report-correction.validation-error",
        ]
        guard let shard = automationShard,
              shard.shardID == "s10.4.current.ax-text",
              automationSegment == .segment3,
              automationSegment.replayCount == 22,
              automationSegment.ownedStartOrdinal == 51,
              automationSegment.ownedCount == 17,
              automationSegment.finalOrdinal == 67,
              Self.segmentedRouteStateIDs.count == 67,
              Set(Self.segmentedRouteStateIDs).count == 67,
              Self.segmentedRouteStateIDs[65] == stateID,
              segmentedRouteStateCursor == 66,
              migratedStateIDs == expectedMigratedStateIDs,
              automationAXTreeDigests.keys.sorted()
                == expectedAXTreeDigestStateIDs.sorted(),
              automationContrastExceptions.keys.sorted()
                == expectedContrastExceptionStateIDs,
              !automatedSegmentFinished,
              app.state == .runningForeground else {
            throw AutomationConfigurationError.invalid(
                "S10.4 AX-text sign-selection native contrast diagnostic gate is invalid"
            )
        }

        let diagnosticQueryBindings: [(
            name: String,
            query: XCUIElementQuery
        )] = [
            (
                "selectionScreens",
                app.descendants(matching: .any).matching(
                    identifier: "s7.4.signs.selection"
                )
            ),
            (
                "selectionScrollViews",
                app.scrollViews.matching(identifier: "s7.4.signs.selection")
            ),
            (
                "monumentSignStaticTexts",
                app.staticTexts.matching(
                    NSPredicate(format: "label == %@", "Monument Sign")
                )
            ),
            (
                "northCampusStaticTexts",
                app.staticTexts.matching(
                    NSPredicate(format: "label == %@", "North Campus")
                )
            ),
            (
                "signRowButtons",
                app.buttons.matching(
                    NSPredicate(
                        format: "identifier BEGINSWITH %@",
                        "s7.4.signs.row."
                    )
                )
            ),
            (
                "addSignButtons",
                app.buttons.matching(identifier: "s7.4.signs.add-sign")
            ),
            ("navigationBars", app.navigationBars),
            ("tabBars", app.tabBars),
            ("keyboards", app.keyboards),
            (
                "inputViews",
                app.otherElements.matching(
                    NSPredicate(format: "identifier == %@", "inputView")
                )
            ),
        ]
        let diagnosticElementObject: (XCUIElement) -> [String: Any] = {
            element in
            let valueObject: Any
            if let value = element.value as? String {
                valueObject = value
            } else {
                valueObject = NSNull()
            }
            return [
                "exists": element.exists,
                "isEnabled": element.isEnabled,
                "isHittable": element.isHittable,
                "identifier": element.identifier,
                "label": element.label,
                "value": valueObject,
                "elementTypeRawValue": element.elementType.rawValue,
                "elementTypeDescription": String(describing: element.elementType),
                "frame": self.auditFrameObject(element.frame),
            ]
        }
        let diagnosticQueryObject: (XCUIElementQuery) -> [String: Any] = {
            query in
            let count = query.count
            var elements: [[String: Any]] = []
            for index in 0..<count {
                elements.append(
                    diagnosticElementObject(query.element(boundBy: index))
                )
            }
            return [
                "count": count,
                "elements": elements,
            ]
        }
        var diagnosticQueryObjects: [String: Any] = [:]
        for binding in diagnosticQueryBindings {
            diagnosticQueryObjects[binding.name] = diagnosticQueryObject(binding.query)
        }
        let diagnosticContext: [String: Any] = [
            "schemaVersion": 1,
            "acceptanceEligible": false,
            "shardID": shard.shardID,
            "requirementID": shard.requirementID,
            "deviceProfileID": shard.deviceProfileID,
            "segmentID": automationSegment.rawValue,
            "segmentReplayCount": automationSegment.replayCount,
            "segmentOwnedStartOrdinal": automationSegment.ownedStartOrdinal,
            "segmentOwnedCount": automationSegment.ownedCount,
            "segmentFinalOrdinal": automationSegment.finalOrdinal,
            "segmentStateCursor": segmentedRouteStateCursor,
            "stateID": stateID,
            "stateOrdinal": 66,
            "predecessorStateID": "state.subscription.active",
            "predecessorOrdinal": 65,
            "successorStateID": "state.subscription.no-entitlement",
            "successorOrdinal": 67,
            "migratedStateIDs": migratedStateIDs,
            "axTreeDigestStateIDs": automationAXTreeDigests.keys.sorted(),
            "contrastExceptionStateIDs": automationContrastExceptions.keys.sorted(),
            "applicationState": String(describing: app.state),
            "applicationStateRawValue": app.state.rawValue,
            "applicationForeground": app.state == .runningForeground,
            "applicationFrame": auditFrameObject(app.frame),
            "application": diagnosticElementObject(app),
            "queries": diagnosticQueryObjects,
        ]
        printJSONLine(
            prefix:
                "S10_4_AX_TEXT_SIGN_SELECTION_NATIVE_CONTRAST_CONTEXT_DIAGNOSTIC",
            object: diagnosticContext
        )

        let appAttachment = XCTAttachment(screenshot: app.screenshot())
        appAttachment.name =
            "S10.4 AX-text sign-selection native contrast diagnostic app"
        appAttachment.lifetime = .keepAlways
        add(appAttachment)
        let treeAttachment = XCTAttachment(string: app.debugDescription)
        treeAttachment.name =
            "S10.4 AX-text sign-selection native contrast diagnostic tree"
        treeAttachment.lifetime = .keepAlways
        add(treeAttachment)
        let contextData = try JSONSerialization.data(
            withJSONObject: diagnosticContext,
            options: [.prettyPrinted, .sortedKeys]
        )
        let contextAttachment = XCTAttachment(
            string: String(decoding: contextData, as: UTF8.self)
        )
        contextAttachment.name =
            "S10.4 AX-text sign-selection native contrast diagnostic context"
        contextAttachment.lifetime = .keepAlways
        add(contextAttachment)

        var observedIssueCount = 0
        var auditedElementCount = 0
        try app.performAccessibilityAudit(for: .contrast) { issue in
            observedIssueCount += 1
            let auditedElement = issue.element
            var diagnosticIssue: [String: Any] = [
                "schemaVersion": 1,
                "acceptanceEligible": false,
                "shardID": shard.shardID,
                "requirementID": shard.requirementID,
                "deviceProfileID": shard.deviceProfileID,
                "segmentID": self.automationSegment.rawValue,
                "segmentStateCursor": self.segmentedRouteStateCursor,
                "stateID": stateID,
                "stateOrdinal": 66,
                "issueOrdinal": observedIssueCount,
                "auditTypeRawValue": String(issue.auditType.rawValue),
                "compactDescription": issue.compactDescription,
                "detailedDescription": issue.detailedDescription,
                "elementExists": NSNull(),
                "elementEnabled": NSNull(),
                "elementHittable": NSNull(),
                "elementIdentifier": NSNull(),
                "elementLabel": NSNull(),
                "elementValue": NSNull(),
                "elementTypeRawValue": NSNull(),
                "elementTypeDescription": NSNull(),
                "elementFrame": NSNull(),
                "applicationFrame": self.auditFrameObject(app.frame),
            ]
            if let auditedElement {
                auditedElementCount += 1
                let valueObject: Any
                if let value = auditedElement.value as? String {
                    valueObject = value
                } else {
                    valueObject = NSNull()
                }
                diagnosticIssue["elementExists"] = auditedElement.exists
                diagnosticIssue["elementEnabled"] = auditedElement.isEnabled
                diagnosticIssue["elementHittable"] = auditedElement.isHittable
                diagnosticIssue["elementIdentifier"] = auditedElement.identifier
                diagnosticIssue["elementLabel"] = auditedElement.label
                diagnosticIssue["elementValue"] = valueObject
                diagnosticIssue["elementTypeRawValue"] =
                    auditedElement.elementType.rawValue
                diagnosticIssue["elementTypeDescription"] =
                    String(describing: auditedElement.elementType)
                diagnosticIssue["elementFrame"] =
                    self.auditFrameObject(auditedElement.frame)
            }
            self.printJSONLine(
                prefix:
                    "S10_4_AX_TEXT_SIGN_SELECTION_NATIVE_CONTRAST_ISSUE_DIAGNOSTIC",
                object: diagnosticIssue
            )
            if let auditedElement {
                let issueAttachment = XCTAttachment(
                    screenshot: auditedElement.screenshot()
                )
                issueAttachment.name =
                    "S10.4 AX-text sign-selection native contrast diagnostic audited element "
                        + String(observedIssueCount)
                issueAttachment.lifetime = .keepAlways
                self.add(issueAttachment)
            }
            return true
        }
        printJSONLine(
            prefix:
                "S10_4_AX_TEXT_SIGN_SELECTION_NATIVE_CONTRAST_COUNT_DIAGNOSTIC",
            object: [
                "schemaVersion": 1,
                "acceptanceEligible": false,
                "shardID": shard.shardID,
                "segmentID": automationSegment.rawValue,
                "stateID": stateID,
                "stateOrdinal": 66,
                "segmentStateCursor": segmentedRouteStateCursor,
                "observedIssueCount": observedIssueCount,
                "auditedElementCount": auditedElementCount,
            ]
        )
        throw AutomationConfigurationError.invalid(
            "S10.4 AX-text sign-selection native contrast diagnostic completed nonaccepting"
        )
    }

    @MainActor
    private func positionMinimumRTLReportsViewReport(
        in app: XCUIApplication
    ) -> Bool {
        let stateID = "state.reports-index.ready"
        let expectedMigratedStateIDs = Array(
            Self.segmentedRouteStateIDs.prefix(20)
        )
        guard let shard = automationShard,
              shard.ordinal == 10,
              shard.shardID == "s10.4.minimum.rtl",
              shard.requirementID == "rtl",
              shard.deviceProfileID == "iphone-se-3-ios-18.0-minimum",
              automationSegment == .none,
              Self.segmentedRouteStateIDs.count == 67,
              Set(Self.segmentedRouteStateIDs).count == 67,
              Self.segmentedRouteStateIDs[20] == stateID,
              segmentedRouteStateCursor == 0,
              migratedStateIDs == expectedMigratedStateIDs,
              automationAXTreeDigests.keys.sorted()
                == expectedMigratedStateIDs.sorted(),
              automationContrastExceptions.isEmpty,
              !automatedSegmentFinished,
              app.state == .runningForeground else {
            XCTFail("S10.4 minimum RTL reports-index positioning gate is invalid.")
            return false
        }

        let reportsScreens = app.descendants(matching: .any).matching(
            identifier: "s4.4.reports.screen"
        )
        let viewReportControls = app.buttons.matching(
            identifier: "s4.4.reports.view-report"
        )
        let reportsScrollViews = app.scrollViews.containing(
            .button,
            identifier: "s4.4.reports.view-report"
        )
        let reportsNavigationBars = app.navigationBars.matching(
            identifier: "Reports"
        )
        let reportsTabBars = app.tabBars
        let reportsScreen = reportsScreens.firstMatch
        let viewReportControl = viewReportControls.firstMatch
        let reportsScrollView = reportsScrollViews.firstMatch
        let reportsNavigationBar = reportsNavigationBars.firstMatch
        let reportsTabBar = reportsTabBars.firstMatch

        func validFrame(_ frame: CGRect) -> Bool {
            !frame.isNull
                && !frame.isEmpty
                && frame.origin.x.isFinite
                && frame.origin.y.isFinite
                && frame.size.width.isFinite
                && frame.size.height.isFinite
        }

        let contentInset: CGFloat = 16
        let receiverInset: CGFloat = 24
        let minimumGestureDistance: CGFloat = 44
        for _ in 0..<4 {
            guard app.state == .runningForeground,
                  reportsScreens.count == 1,
                  viewReportControls.count == 1,
                  reportsScrollViews.count == 1,
                  reportsNavigationBars.count == 1,
                  reportsTabBars.count == 1,
                  reportsScreen.exists,
                  viewReportControl.exists,
                  viewReportControl.identifier == "s4.4.reports.view-report",
                  viewReportControl.label == "View report",
                  viewReportControl.elementType == .button,
                  reportsScrollView.exists,
                  reportsNavigationBar.exists,
                  reportsTabBar.exists else {
                XCTFail("Minimum RTL reports-index positioning route changed.")
                return false
            }
            let applicationFrame = app.frame
            let scrollFrame = reportsScrollView.frame
            let navigationFrame = reportsNavigationBar.frame
            let tabBarFrame = reportsTabBar.frame
            let viewReportFrame = viewReportControl.frame
            let liveScrollFrame = scrollFrame.intersection(applicationFrame)
            let liveTop = max(liveScrollFrame.minY, navigationFrame.maxY)
            let liveBottom = min(
                liveScrollFrame.maxY,
                min(applicationFrame.maxY, tabBarFrame.minY)
            )
            let safeTop = liveTop + contentInset
            let safeBottom = liveBottom - contentInset
            let receiverTop = liveTop + receiverInset
            let receiverBottom = liveBottom - receiverInset
            guard validFrame(applicationFrame),
                  validFrame(scrollFrame),
                  validFrame(navigationFrame),
                  validFrame(tabBarFrame),
                  validFrame(viewReportFrame),
                  validFrame(liveScrollFrame),
                  liveTop.isFinite,
                  liveBottom.isFinite,
                  safeTop.isFinite,
                  safeBottom.isFinite,
                  receiverTop.isFinite,
                  receiverBottom.isFinite,
                  safeBottom > safeTop,
                  receiverBottom > receiverTop,
                  viewReportFrame.height <= safeBottom - safeTop else {
                XCTFail("Minimum RTL reports-index viewport geometry is invalid.")
                return false
            }
            if viewReportFrame.minY >= safeTop,
               viewReportFrame.maxY <= safeBottom,
               viewReportControl.isHittable {
                return true
            }

            let minimumShift = safeTop - viewReportFrame.minY
            let maximumShift = safeBottom - viewReportFrame.maxY
            let receiverCapacity = receiverBottom - receiverTop
            guard minimumShift.isFinite,
                  maximumShift.isFinite,
                  receiverCapacity.isFinite,
                  minimumShift <= maximumShift,
                  maximumShift < 0,
                  receiverCapacity >= minimumGestureDistance else {
                XCTFail("Minimum RTL reports-index has no feasible upward shift.")
                return false
            }
            let recognizedMinimum = max(minimumShift, -receiverCapacity)
            let recognizedMaximum = min(
                maximumShift,
                -minimumGestureDistance
            )
            guard recognizedMinimum <= recognizedMaximum,
                  recognizedMaximum < 0 else {
                XCTFail("Minimum RTL reports-index upward shift is not recognizable.")
                return false
            }
            let dragDistance = max(
                recognizedMinimum,
                recognizedMaximum - minimumGestureDistance
            )
            guard dragDistance.isFinite,
                  dragDistance <= recognizedMaximum,
                  abs(dragDistance) >= minimumGestureDistance else {
                XCTFail("Minimum RTL reports-index positioning gesture is invalid.")
                return false
            }
            let scrollOrigin = reportsScrollView.coordinate(
                withNormalizedOffset: CGVector(dx: 0, dy: 0)
            )
            let dragStart = scrollOrigin.withOffset(
                CGVector(
                    dx: scrollFrame.width / 2,
                    dy: receiverBottom - scrollFrame.minY
                )
            )
            let dragEnd = dragStart.withOffset(
                CGVector(dx: 0, dy: dragDistance)
            )
            let viewReportMinYBeforeDrag = viewReportFrame.minY
            dragStart.press(
                forDuration: 0.2,
                thenDragTo: dragEnd,
                withVelocity: .slow,
                thenHoldForDuration: 0.2
            )
            guard app.state == .runningForeground,
                  reportsScreens.count == 1,
                  viewReportControls.count == 1,
                  reportsScrollViews.count == 1,
                  reportsNavigationBars.count == 1,
                  reportsTabBars.count == 1,
                  reportsScreen.exists,
                  viewReportControl.exists,
                  reportsScrollView.exists,
                  reportsNavigationBar.exists,
                  reportsTabBar.exists else {
                XCTFail("Minimum RTL reports-index route changed after positioning.")
                return false
            }
            let observedShift =
                viewReportControl.frame.minY - viewReportMinYBeforeDrag
            guard observedShift.isFinite,
                  observedShift < 0,
                  observedShift * dragDistance > 0 else {
                XCTFail("Minimum RTL reports-index gesture was not recognized.")
                return false
            }
        }

        guard app.state == .runningForeground,
              reportsScreens.count == 1,
              viewReportControls.count == 1,
              reportsScrollViews.count == 1,
              reportsNavigationBars.count == 1,
              reportsTabBars.count == 1,
              reportsScreen.exists,
              viewReportControl.exists,
              viewReportControl.identifier == "s4.4.reports.view-report",
              viewReportControl.label == "View report",
              viewReportControl.elementType == .button,
              reportsScrollView.exists,
              reportsNavigationBar.exists,
              reportsTabBar.exists else {
            XCTFail("Minimum RTL reports-index final route changed.")
            return false
        }
        let finalApplicationFrame = app.frame
        let finalScrollFrame = reportsScrollView.frame.intersection(
            finalApplicationFrame
        )
        let finalNavigationFrame = reportsNavigationBar.frame
        let finalTabBarFrame = reportsTabBar.frame
        let finalViewReportFrame = viewReportControl.frame
        let finalSafeTop = max(
            finalScrollFrame.minY,
            finalNavigationFrame.maxY
        ) + contentInset
        let finalSafeBottom = min(
            finalScrollFrame.maxY,
            min(finalApplicationFrame.maxY, finalTabBarFrame.minY)
        ) - contentInset
        guard validFrame(finalApplicationFrame),
              validFrame(finalScrollFrame),
              validFrame(finalNavigationFrame),
              validFrame(finalTabBarFrame),
              validFrame(finalViewReportFrame),
              finalSafeTop.isFinite,
              finalSafeBottom.isFinite,
              finalSafeBottom > finalSafeTop,
              finalViewReportFrame.minY >= finalSafeTop,
              finalViewReportFrame.maxY <= finalSafeBottom,
              finalViewReportFrame.maxY <= finalTabBarFrame.minY - contentInset,
              viewReportControl.isHittable else {
            XCTFail("Minimum RTL View report is outside the safe viewport.")
            return false
        }
        return true
    }

    @MainActor
    private func dismissMinimumWorkValidationKeyboardAccessory(
        in app: XCUIApplication
    ) throws {
        let stateID = "state.work.validation-error"
        let expectedMigratedStateIDs = Array(
            Self.segmentedRouteStateIDs.prefix(22)
        )
        guard let shard = automationShard,
              shard.ordinal == 8,
              shard.shardID == "s10.4.minimum.minimum-os",
              shard.requirementID == "minimum_os",
              shard.deviceProfileID == "iphone-se-3-ios-18.0-minimum",
              automationSegment == .none,
              Self.segmentedRouteStateIDs.count == 67,
              Set(Self.segmentedRouteStateIDs).count == 67,
              Self.segmentedRouteStateIDs[22] == stateID,
              segmentedRouteStateCursor == 0,
              migratedStateIDs == expectedMigratedStateIDs,
              automationAXTreeDigests.keys.sorted()
                == expectedMigratedStateIDs.sorted(),
              automationContrastExceptions.isEmpty,
              !automatedSegmentFinished else {
            throw AutomationConfigurationError.invalid(
                "S10.4 minimum work-validation keyboard accessory gate is invalid"
            )
        }

        let focusedPredicate = NSPredicate(
            format: "hasKeyboardFocus == true"
        )
        let workScreens = app.descendants(matching: .any).matching(
            identifier: "s5.1.work.screen"
        )
        let descriptionFields = app.descendants(matching: .any).matching(
            identifier: "s5.1.work.description"
        )
        let focusedDescriptionFields = descriptionFields.matching(
            focusedPredicate
        )
        let validationLabels = app.descendants(matching: .any).matching(
            identifier: "s5.1.work.validation"
        )
        let noteHeadings = app.staticTexts.matching(
            NSPredicate(format: "label == %@", "Note")
        )
        let noteFields = app.descendants(matching: .any).matching(
            identifier: "s5.1.work.note"
        )
        let keyboards = app.keyboards
        let doneButtons = app.buttons.matching(
            identifier: "s5.1.work.keyboard-done"
        )
        let quickPathIntroductionViews = app.descendants(
            matching: .other
        ).matching(identifier: "UIContinuousPathIntroductionView")
        let quickPathIntroductionButtons = quickPathIntroductionViews.buttons
        let quickPathIntroductionStaticTexts =
            quickPathIntroductionViews.staticTexts

        let workScreenCount = workScreens.count
        let descriptionFieldCount = descriptionFields.count
        let focusedDescriptionFieldCount = focusedDescriptionFields.count
        let validationLabelCount = validationLabels.count
        let noteHeadingCount = noteHeadings.count
        let noteFieldCount = noteFields.count
        let keyboardCount = keyboards.count
        let doneButtonCount = doneButtons.count
        let quickPathIntroductionCount = quickPathIntroductionViews.count
        let quickPathIntroductionButtonCount =
            quickPathIntroductionButtons.count
        let quickPathIntroductionStaticTextCount =
            quickPathIntroductionStaticTexts.count
        guard workScreenCount == 1,
              descriptionFieldCount == 1,
              focusedDescriptionFieldCount == 1,
              validationLabelCount == 1,
              noteHeadingCount == 1,
              noteFieldCount == 1,
              keyboardCount == 1,
              doneButtonCount == 1,
              quickPathIntroductionCount == 0,
              quickPathIntroductionButtonCount == 0,
              quickPathIntroductionStaticTextCount == 0 else {
            throw AutomationConfigurationError.invalid(
                "S10.4 minimum work-validation keyboard accessory structure is invalid"
            )
        }

        let workScreen = workScreens.element(boundBy: 0)
        let descriptionField = descriptionFields.element(boundBy: 0)
        let validationLabel = validationLabels.element(boundBy: 0)
        let noteHeading = noteHeadings.element(boundBy: 0)
        let noteField = noteFields.element(boundBy: 0)
        let keyboard = keyboards.element(boundBy: 0)
        let doneButton = doneButtons.element(boundBy: 0)
        let frameIsValid: (CGRect) -> Bool = { frame in
            !frame.isNull
                && !frame.isEmpty
                && !frame.isInfinite
                && frame.origin.x.isFinite
                && frame.origin.y.isFinite
                && frame.size.width.isFinite
                && frame.size.height.isFinite
        }
        let applicationFrame = app.frame
        let workScreenFrame = workScreen.frame
        let descriptionFrame = descriptionField.frame
        let validationFrame = validationLabel.frame
        let noteHeadingFrame = noteHeading.frame
        let noteFieldFrame = noteField.frame
        let keyboardFrame = keyboard.frame
        let doneButtonFrame = doneButton.frame
        let preWorkScreenIdentifier = workScreen.identifier
        let preDescriptionIdentifier = descriptionField.identifier
        let preDescriptionLabel = descriptionField.label
        let preDescriptionPlaceholderValue =
            descriptionField.placeholderValue
        let preValidationIdentifier = validationLabel.identifier
        let preValidationLabel = validationLabel.label
        let preNoteHeadingLabel = noteHeading.label
        let preNoteHeadingType = noteHeading.elementType
        let preNoteFieldIdentifier = noteField.identifier
        let noteHeadingOverlapsDoneAccessoryBand =
            noteHeadingFrame.minY < doneButtonFrame.maxY
                && noteHeadingFrame.maxY > doneButtonFrame.minY
        let firstFailedPreTapSemanticLabel: String? = {
            if app.state != .runningForeground { return "app-foreground" }
            if !frameIsValid(applicationFrame) { return "app-frame-valid" }
            if !frameIsValid(workScreenFrame) { return "work-frame-valid" }
            if !frameIsValid(descriptionFrame) { return "description-frame-valid" }
            if !frameIsValid(validationFrame) { return "validation-frame-valid" }
            if !frameIsValid(noteHeadingFrame) { return "note-heading-frame-valid" }
            if !frameIsValid(noteFieldFrame) { return "note-field-frame-valid" }
            if !frameIsValid(keyboardFrame) { return "keyboard-frame-valid" }
            if !frameIsValid(doneButtonFrame) { return "done-frame-valid" }
            if !applicationFrame.contains(workScreenFrame) { return "app-contains-work" }
            if !applicationFrame.contains(descriptionFrame) { return "app-contains-description" }
            if !applicationFrame.contains(validationFrame) { return "app-contains-validation" }
            if !applicationFrame.contains(noteHeadingFrame) { return "app-contains-note-heading" }
            if !applicationFrame.contains(noteFieldFrame) { return "app-contains-note-field" }
            if !applicationFrame.contains(keyboardFrame) { return "app-contains-keyboard" }
            if !applicationFrame.contains(doneButtonFrame) { return "app-contains-done" }
            if !noteHeadingOverlapsDoneAccessoryBand { return "note-heading-overlaps-done-accessory" }
            if !workScreen.exists { return "work-exists" }
            if !workScreen.isEnabled { return "work-enabled" }
            if !workScreen.isHittable { return "work-hittable" }
            if preWorkScreenIdentifier != "s5.1.work.screen" { return "work-identifier" }
            if !descriptionField.exists { return "description-exists" }
            if !descriptionField.isEnabled { return "description-enabled" }
            if !descriptionField.isHittable { return "description-hittable" }
            if preDescriptionIdentifier != "s5.1.work.description" { return "description-identifier" }
            if preDescriptionLabel != "Short description" { return "description-label" }
            if preDescriptionPlaceholderValue != "Short description"
                || (descriptionField.value as? String)
                    != preDescriptionPlaceholderValue {
                return "description-placeholder-value"
            }
            if !validationLabel.exists { return "validation-exists" }
            if !validationLabel.isEnabled { return "validation-enabled" }
            if preValidationIdentifier != "s5.1.work.validation" { return "validation-identifier" }
            if preValidationLabel != "Short description" { return "validation-label" }
            if !noteHeading.exists { return "note-heading-exists" }
            if preNoteHeadingLabel != "Note" { return "note-heading-label" }
            if preNoteHeadingType != .staticText { return "note-heading-type" }
            if !noteField.exists { return "note-field-exists" }
            if preNoteFieldIdentifier != "s5.1.work.note" { return "note-field-identifier" }
            if !keyboard.exists { return "keyboard-exists" }
            if !doneButton.exists { return "done-exists" }
            if !doneButton.isEnabled { return "done-enabled" }
            if !doneButton.isHittable { return "done-hittable" }
            if doneButton.identifier != "s5.1.work.keyboard-done" { return "done-identifier" }
            if doneButton.label != "Done" { return "done-label" }
            if doneButton.elementType != .button { return "done-type" }
            return nil
        }()
        if let firstFailedPreTapSemanticLabel {
            throw AutomationConfigurationError.invalid(
                "S10.4 minimum work-validation keyboard accessory semantics are invalid: "
                    + firstFailedPreTapSemanticLabel
            )
        }

        doneButton.tap()
        guard keyboard.waitForNonExistence(timeout: 10),
              doneButton.waitForNonExistence(timeout: 10) else {
            throw AutomationConfigurationError.invalid(
                "S10.4 minimum work-validation keyboard accessory did not dismiss"
            )
        }

        let postWorkScreens = app.descendants(matching: .any).matching(
            identifier: "s5.1.work.screen"
        )
        let postDescriptionFields = app.descendants(matching: .any).matching(
            identifier: "s5.1.work.description"
        )
        let postFocusedDescriptionFields = postDescriptionFields.matching(
            focusedPredicate
        )
        let postValidationLabels = app.descendants(matching: .any).matching(
            identifier: "s5.1.work.validation"
        )
        let postNoteHeadings = app.staticTexts.matching(
            NSPredicate(format: "label == %@", "Note")
        )
        let postNoteFields = app.descendants(matching: .any).matching(
            identifier: "s5.1.work.note"
        )
        let postKeyboards = app.keyboards
        let postDoneButtons = app.buttons.matching(
            identifier: "s5.1.work.keyboard-done"
        )
        let postQuickPathIntroductionViews = app.descendants(
            matching: .other
        ).matching(identifier: "UIContinuousPathIntroductionView")
        let postQuickPathIntroductionButtons =
            postQuickPathIntroductionViews.buttons
        let postQuickPathIntroductionStaticTexts =
            postQuickPathIntroductionViews.staticTexts

        let postWorkScreenCount = postWorkScreens.count
        let postDescriptionFieldCount = postDescriptionFields.count
        let postFocusedDescriptionFieldCount =
            postFocusedDescriptionFields.count
        let postValidationLabelCount = postValidationLabels.count
        let postNoteHeadingCount = postNoteHeadings.count
        let postNoteFieldCount = postNoteFields.count
        let postKeyboardCount = postKeyboards.count
        let postDoneButtonCount = postDoneButtons.count
        let postQuickPathIntroductionCount =
            postQuickPathIntroductionViews.count
        let postQuickPathIntroductionButtonCount =
            postQuickPathIntroductionButtons.count
        let postQuickPathIntroductionStaticTextCount =
            postQuickPathIntroductionStaticTexts.count
        guard postWorkScreenCount == 1,
              postDescriptionFieldCount == 1,
              postFocusedDescriptionFieldCount == 0,
              postValidationLabelCount == 1,
              postNoteHeadingCount == 1,
              postNoteFieldCount == 1,
              postKeyboardCount == 0,
              postDoneButtonCount == 0,
              postQuickPathIntroductionCount == 0,
              postQuickPathIntroductionButtonCount == 0,
              postQuickPathIntroductionStaticTextCount == 0 else {
            throw AutomationConfigurationError.invalid(
                "S10.4 minimum work-validation post-dismiss structure is invalid"
            )
        }

        let postWorkScreen = postWorkScreens.element(boundBy: 0)
        let postDescriptionField = postDescriptionFields.element(boundBy: 0)
        let postValidationLabel = postValidationLabels.element(boundBy: 0)
        let postNoteHeading = postNoteHeadings.element(boundBy: 0)
        let postNoteField = postNoteFields.element(boundBy: 0)
        let postApplicationFrame = app.frame
        let postWorkScreenFrame = postWorkScreen.frame
        let postDescriptionFrame = postDescriptionField.frame
        let postValidationFrame = postValidationLabel.frame
        let postNoteHeadingFrame = postNoteHeading.frame
        let postNoteFieldFrame = postNoteField.frame
        let firstFailedPostDismissSemanticLabel: String? = {
            if app.state != .runningForeground { return "post-app-foreground" }
            if segmentedRouteStateCursor != 0 { return "post-route-cursor" }
            if migratedStateIDs != expectedMigratedStateIDs {
                return "post-migrated-state-ids"
            }
            if automationAXTreeDigests.keys.sorted()
                != expectedMigratedStateIDs.sorted() {
                return "post-ax-tree-digests"
            }
            if !automationContrastExceptions.isEmpty {
                return "post-contrast-exceptions-empty"
            }
            if automatedSegmentFinished { return "post-segment-unfinished" }
            if !frameIsValid(postApplicationFrame) { return "post-app-frame-valid" }
            if !frameIsValid(postWorkScreenFrame) { return "post-work-frame-valid" }
            if !frameIsValid(postDescriptionFrame) {
                return "post-description-frame-valid"
            }
            if !frameIsValid(postValidationFrame) {
                return "post-validation-frame-valid"
            }
            if !frameIsValid(postNoteHeadingFrame) {
                return "post-note-heading-frame-valid"
            }
            if !frameIsValid(postNoteFieldFrame) {
                return "post-note-field-frame-valid"
            }
            if !postApplicationFrame.contains(postWorkScreenFrame) {
                return "post-app-contains-work"
            }
            if !postApplicationFrame.contains(postDescriptionFrame) {
                return "post-app-contains-description"
            }
            if !postApplicationFrame.contains(postValidationFrame) {
                return "post-app-contains-validation"
            }
            if !postApplicationFrame.contains(postNoteHeadingFrame) {
                return "post-app-contains-note-heading"
            }
            if !postApplicationFrame.contains(postNoteFieldFrame) {
                return "post-app-contains-note-field"
            }
            if postNoteHeadingFrame.maxY > postNoteFieldFrame.minY {
                return "post-note-heading-before-note-field"
            }
            if !postWorkScreen.exists { return "post-work-exists" }
            if !postWorkScreen.isEnabled { return "post-work-enabled" }
            if !postWorkScreen.isHittable { return "post-work-hittable" }
            if postWorkScreen.identifier != preWorkScreenIdentifier {
                return "post-work-identifier"
            }
            if !postDescriptionField.exists { return "post-description-exists" }
            if !postDescriptionField.isEnabled { return "post-description-enabled" }
            if !postDescriptionField.isHittable { return "post-description-hittable" }
            if postDescriptionField.identifier != preDescriptionIdentifier {
                return "post-description-identifier"
            }
            if postDescriptionField.label != preDescriptionLabel {
                return "post-description-label"
            }
            let postDescriptionValue = postDescriptionField.value as? String
            if postDescriptionValue != preDescriptionPlaceholderValue
                || preDescriptionPlaceholderValue != "Short description" {
                if postDescriptionValue == "" {
                    return "post-description-value-empty"
                }
                if postDescriptionValue == nil {
                    return "post-description-value-type-mismatch"
                }
                return "post-description-value-other"
            }
            if !postValidationLabel.exists { return "post-validation-exists" }
            if !postValidationLabel.isEnabled { return "post-validation-enabled" }
            if postValidationLabel.identifier != preValidationIdentifier {
                return "post-validation-identifier"
            }
            if postValidationLabel.label != preValidationLabel {
                return "post-validation-label"
            }
            if !postNoteHeading.exists { return "post-note-heading-exists" }
            if !postNoteHeading.isHittable { return "post-note-heading-hittable" }
            if postNoteHeading.label != preNoteHeadingLabel {
                return "post-note-heading-label"
            }
            if postNoteHeading.elementType != preNoteHeadingType {
                return "post-note-heading-type"
            }
            if !postNoteField.exists { return "post-note-field-exists" }
            if !postNoteField.isHittable { return "post-note-field-hittable" }
            if postNoteField.identifier != preNoteFieldIdentifier {
                return "post-note-field-identifier"
            }
            return nil
        }()
        if let firstFailedPostDismissSemanticLabel {
            throw AutomationConfigurationError.invalid(
                "S10.4 minimum work-validation post-dismiss semantics are invalid: "
                    + firstFailedPostDismissSemanticLabel
            )
        }
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
        let tree = app.debugDescription
        let hasStableIdentifier = tree
            .split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .contains { line in
                guard let marker = line.range(of: "identifier: '") else {
                    return false
                }
                let suffix = line[marker.upperBound...]
                guard let end = suffix.firstIndex(of: "'") else {
                    return false
                }
                return !suffix[..<end].isEmpty
            }
        guard !tree.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              hasStableIdentifier else {
            throw AutomationConfigurationError.invalid(
                "The raw accessibility tree is empty or contains no stable identifiers"
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
                .flatMap { $0 }
                .filter { $0.taskID == task.taskID }
                .sorted {
                    if $0.stateID == $1.stateID {
                        return $0.issueID < $1.issueID
                    }
                    return $0.stateID < $1.stateID
                }
            let taskIssueLimit: Int
            let taskStateLimit: Int
            let permittedExceptionStateIDs: Set<String>
            switch (shard.shardID, task.taskID) {
            case ("s10.4.current.ax-text", "one_handed_start"):
                taskIssueLimit = 5
                taskStateLimit = 4
                permittedExceptionStateIDs = [
                    "state.check-preflight.ready",
                    "state.new-sign.editing",
                    "state.paywall.purchase-complete",
                    "state.sign-selection.ready",
                ]
            case ("s10.4.current.ax-text", "report_comprehension"):
                taskIssueLimit = 4
                taskStateLimit = 3
                permittedExceptionStateIDs = [
                    "state.report-correction.validation-error",
                    "state.report-history.ready",
                    "state.reports-index.ready",
                ]
            case ("s10.4.current.ax-text", "work_and_recheck"):
                taskIssueLimit = 5
                taskStateLimit = 5
                permittedExceptionStateIDs = [
                    "state.issue.open",
                    "state.issue.recheck-due",
                    "state.issue.resolved",
                    "state.recheck-capture.wide-ready",
                    "state.recheck-preflight.ready",
                ]
            case ("s10.4.current.default-light", "report_comprehension"):
                taskIssueLimit = 1
                taskStateLimit = 1
                permittedExceptionStateIDs = [
                    "state.report-correction.validation-error",
                ]
            case ("s10.4.current.default-dark", "report_comprehension"):
                taskIssueLimit = 2
                taskStateLimit = 2
                permittedExceptionStateIDs = [
                    "state.report-correction.validation-error",
                    "state.sample-report.ready",
                ]
            case ("s10.4.current.increased-contrast", "report_comprehension"):
                taskIssueLimit = 1
                taskStateLimit = 1
                permittedExceptionStateIDs = [
                    "state.report-correction.validation-error",
                ]
            case ("s10.4.current.reduce-motion", "report_comprehension"):
                taskIssueLimit = 1
                taskStateLimit = 1
                permittedExceptionStateIDs = [
                    "state.report-correction.validation-error",
                ]
            case ("s10.4.current.reduce-transparency", "report_comprehension"):
                taskIssueLimit = 1
                taskStateLimit = 1
                permittedExceptionStateIDs = [
                    "state.report-correction.validation-error",
                ]
            case ("s10.4.current.differentiate-without-color", "report_comprehension"):
                taskIssueLimit = 1
                taskStateLimit = 1
                permittedExceptionStateIDs = [
                    "state.report-correction.validation-error",
                ]
            case ("s10.4.current.default-dark", "history_recovery"):
                taskIssueLimit = 1
                taskStateLimit = 1
                permittedExceptionStateIDs = ["state.feedback.review-ready"]
            default:
                taskIssueLimit = 0
                taskStateLimit = 0
                permittedExceptionStateIDs = []
            }
            guard taskExceptions.count <= taskIssueLimit else {
                XCTFail(
                    "A common task exceeded its exact contrast exception limit",
                    file: file,
                    line: line
                )
                return
            }
            let exceptionStateIDs = Array(Set(taskExceptions.map(\.stateID))).sorted()
            let exceptionIssueIDs = taskExceptions.map(\.issueID)
            let expectedUniqueMetadataCount = taskExceptions.isEmpty ? 0 : 1
            guard exceptionStateIDs.count <= taskStateLimit,
                  Set(exceptionStateIDs).isSubset(of: permittedExceptionStateIDs),
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
                "--s3-5-ui-test-low-storage-once",
                "--s3-6-ui-test-camera-denied-once",
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
    private func positionPreflightAfterDarkForAXText(
        in app: XCUIApplication
    ) -> Bool {
        let expectedAfterDarkLabel =
            "It is dark enough to observe the sign's visible illumination."
        let focusedPredicate = NSPredicate(
            format: "hasKeyboardFocus == true"
        )
        let preflightScreens = app.scrollViews.matching(
            identifier: "s3.preflight.screen"
        )
        let preflightScrollViews = app.scrollViews.containing(
            .switch,
            identifier: "s3.preflight.after-dark"
        )
        let navigationBars = app.navigationBars
        let tabBars = app.tabBars
        let zoneFields = app.textFields.matching(
            identifier: "s3.preflight.time-zone"
        )
        let confirmationSwitches = app.switches.matching(
            identifier: "s3.preflight.time-zone-confirmed"
        )
        let afterDarkSwitches = app.switches.matching(
            identifier: "s3.preflight.after-dark"
        )
        let keyboards = app.keyboards
        let inputViews = app.otherElements.matching(
            identifier: "inputView"
        )
        guard preflightScreens.count == 1,
              preflightScrollViews.count == 1,
              navigationBars.count == 1,
              tabBars.count == 1,
              zoneFields.count == 1,
              confirmationSwitches.count == 1,
              afterDarkSwitches.count == 1 else {
            XCTFail("AX-text Preflight after-dark positioning bindings are ambiguous.")
            return false
        }
        let preflightScreen = preflightScreens.firstMatch
        let preflightScrollView = preflightScrollViews.firstMatch
        let navigationBar = navigationBars.firstMatch
        let tabBar = tabBars.firstMatch
        let zoneField = zoneFields.firstMatch
        let confirmationSwitch = confirmationSwitches.firstMatch
        let afterDarkSwitch = afterDarkSwitches.firstMatch
        let keyboard = keyboards.firstMatch
        let inputView = inputViews.firstMatch
        let isValidFrame: (CGRect) -> Bool = { frame in
            !frame.isNull
                && !frame.isEmpty
                && !frame.isInfinite
                && frame.origin.x.isFinite
                && frame.origin.y.isFinite
                && frame.size.width.isFinite
                && frame.size.height.isFinite
        }
        let exactInputComposition: () -> Bool = {
            let inputIsAbsent = keyboards.count == 0
                && inputViews.count == 0
            let inputIsPresent = keyboards.count == 1
                && inputViews.count == 1
                && keyboard.exists
                && keyboard.elementType == .keyboard
                && inputView.exists
                && inputView.elementType == .other
                && inputView.identifier == "inputView"
                && focusedPredicate.evaluate(with: zoneField)
                && isValidFrame(keyboard.frame)
                && isValidFrame(inputView.frame)
            return inputIsAbsent || inputIsPresent
        }
        let stablePrePositionRoute: () -> Bool = {
            let applicationFrame = app.frame
            let screenFrame = preflightScreen.frame
            let scrollFrame = preflightScrollView.frame
            let navigationFrame = navigationBar.frame
            let tabFrame = tabBar.frame
            let zoneFrame = zoneField.frame
            let confirmationFrame = confirmationSwitch.frame
            let afterDarkFrame = afterDarkSwitch.frame
            return app.state == .runningForeground
                && preflightScreens.count == 1
                && preflightScrollViews.count == 1
                && navigationBars.count == 1
                && tabBars.count == 1
                && zoneFields.count == 1
                && confirmationSwitches.count == 1
                && afterDarkSwitches.count == 1
                && preflightScreen.exists
                && preflightScreen.elementType == .scrollView
                && preflightScreen.identifier == "s3.preflight.screen"
                && preflightScrollView.exists
                && preflightScrollView.elementType == .scrollView
                && preflightScrollView.identifier == "s3.preflight.screen"
                && navigationBar.exists
                && navigationBar.elementType == .navigationBar
                && tabBar.exists
                && tabBar.elementType == .tabBar
                && zoneField.exists
                && zoneField.elementType == .textField
                && zoneField.identifier == "s3.preflight.time-zone"
                && (zoneField.value as? String) == "America/New_York"
                && confirmationSwitch.exists
                && confirmationSwitch.elementType == .switch
                && confirmationSwitch.identifier
                    == "s3.preflight.time-zone-confirmed"
                && confirmationSwitch.isEnabled
                && (confirmationSwitch.value as? String) == "1"
                && afterDarkSwitch.exists
                && afterDarkSwitch.elementType == .switch
                && afterDarkSwitch.identifier == "s3.preflight.after-dark"
                && afterDarkSwitch.isEnabled
                && isValidFrame(applicationFrame)
                && isValidFrame(screenFrame)
                && isValidFrame(scrollFrame)
                && isValidFrame(navigationFrame)
                && isValidFrame(tabFrame)
                && isValidFrame(zoneFrame)
                && isValidFrame(confirmationFrame)
                && isValidFrame(afterDarkFrame)
                && screenFrame == scrollFrame
                && exactInputComposition()
        }
        let verticalInset: CGFloat = 16
        let receiverInset: CGFloat = 24
        let minimumGestureDistance: CGFloat = 44
        var previousAfterDarkMinYAfterDrag: CGFloat?
        for _ in 0..<4 {
            guard stablePrePositionRoute() else {
                XCTFail("AX-text Preflight after-dark positioning route changed.")
                return false
            }
            let applicationFrame = app.frame
            let screenFrame = preflightScreen.frame
            let scrollFrame = preflightScrollView.frame
            let navigationFrame = navigationBar.frame
            let tabFrame = tabBar.frame
            let zoneFrame = zoneField.frame
            let confirmationFrame = confirmationSwitch.frame
            let afterDarkFrame = afterDarkSwitch.frame
            let mandatoryFramesAreValid = isValidFrame(applicationFrame)
                && isValidFrame(screenFrame)
                && isValidFrame(scrollFrame)
                && isValidFrame(navigationFrame)
                && isValidFrame(tabFrame)
                && isValidFrame(zoneFrame)
                && isValidFrame(confirmationFrame)
                && isValidFrame(afterDarkFrame)
            var liveScrollFrame = CGRect.null
            if mandatoryFramesAreValid {
                liveScrollFrame = scrollFrame.intersection(applicationFrame)
            }
            guard mandatoryFramesAreValid,
                  isValidFrame(liveScrollFrame),
                  screenFrame == scrollFrame else {
                XCTFail("AX-text Preflight after-dark positioning geometry is invalid.")
                return false
            }
            var obstructionTop = min(
                applicationFrame.maxY,
                min(liveScrollFrame.maxY, tabFrame.minY)
            )
            if keyboards.count == 1,
               inputViews.count == 1 {
                let keyboardFrame = keyboard.frame
                let inputViewFrame = inputView.frame
                guard isValidFrame(keyboardFrame),
                      isValidFrame(inputViewFrame) else {
                    XCTFail("AX-text Preflight after-dark input geometry is invalid.")
                    return false
                }
                obstructionTop = min(
                    obstructionTop,
                    min(keyboardFrame.minY, inputViewFrame.minY)
                )
            }
            let liveTop = max(
                liveScrollFrame.minY,
                navigationFrame.maxY
            )
            let safeTop = liveTop + verticalInset
            let safeBottom = obstructionTop - verticalInset
            let receiverTop = liveTop + receiverInset
            let receiverBottom = obstructionTop - receiverInset
            let receiverLeft = liveScrollFrame.minX + receiverInset
            let receiverRight = liveScrollFrame.maxX - receiverInset
            let receiverCapacity = receiverBottom - receiverTop
            let minimumShift = safeTop - afterDarkFrame.minY
            let maximumShift = safeBottom - afterDarkFrame.maxY
            let targetIsContained = afterDarkFrame.minY >= safeTop
                && afterDarkFrame.maxY <= safeBottom
            guard safeTop.isFinite,
                  safeBottom.isFinite,
                  receiverTop.isFinite,
                  receiverBottom.isFinite,
                  receiverLeft.isFinite,
                  receiverRight.isFinite,
                  receiverCapacity.isFinite,
                  minimumShift.isFinite,
                  maximumShift.isFinite,
                  safeTop <= safeBottom,
                  receiverLeft <= receiverRight,
                  receiverTop <= receiverBottom,
                  receiverCapacity >= minimumGestureDistance,
                  afterDarkFrame.height <= safeBottom - safeTop,
                  minimumShift <= maximumShift else {
                XCTFail("AX-text Preflight after-dark has no feasible safe interval.")
                return false
            }
            if targetIsContained {
                break
            }
            guard maximumShift < 0 else {
                XCTFail("AX-text Preflight after-dark requires a non-upward shift.")
                return false
            }
            let dragDistance: CGFloat
            let recognizedMinimum = max(
                minimumShift,
                -receiverCapacity
            )
            let recognizedMaximum = min(
                maximumShift,
                -minimumGestureDistance
            )
            if recognizedMinimum <= recognizedMaximum {
                dragDistance = (recognizedMinimum + recognizedMaximum) / 2
            } else {
                let stagedDistance = max(
                    -receiverCapacity,
                    maximumShift + minimumGestureDistance
                )
                guard stagedDistance <= -minimumGestureDistance else {
                    XCTFail("AX-text Preflight after-dark staged remainder is not recognizable.")
                    return false
                }
                dragDistance = stagedDistance
            }
            guard dragDistance < 0,
                  dragDistance <= -minimumGestureDistance else {
                XCTFail("AX-text Preflight after-dark drag direction is invalid.")
                return false
            }
            let receiverFrame = CGRect(
                x: receiverLeft,
                y: receiverTop,
                width: receiverRight - receiverLeft,
                height: receiverBottom - receiverTop
            )
            let startPoint = CGPoint(
                x: receiverRight,
                y: receiverBottom
            )
            let endPoint = CGPoint(
                x: startPoint.x,
                y: startPoint.y + dragDistance
            )
            guard isValidFrame(receiverFrame),
                  startPoint.x >= receiverFrame.minX,
                  startPoint.x <= receiverFrame.maxX,
                  startPoint.y >= receiverFrame.minY,
                  startPoint.y <= receiverFrame.maxY,
                  endPoint.x >= receiverFrame.minX,
                  endPoint.x <= receiverFrame.maxX,
                  endPoint.y >= receiverFrame.minY,
                  endPoint.y <= receiverFrame.maxY,
                  liveScrollFrame.contains(startPoint),
                  liveScrollFrame.contains(endPoint),
                  !zoneFrame.contains(startPoint),
                  !zoneFrame.contains(endPoint),
                  !confirmationFrame.contains(startPoint),
                  !confirmationFrame.contains(endPoint),
                  !afterDarkFrame.contains(startPoint),
                  !afterDarkFrame.contains(endPoint) else {
                XCTFail("AX-text Preflight after-dark drag receiver is obstructed.")
                return false
            }
            let scrollOrigin = preflightScrollView.coordinate(
                withNormalizedOffset: CGVector(dx: 0, dy: 0)
            )
            let startCoordinate = scrollOrigin.withOffset(
                CGVector(
                    dx: startPoint.x - scrollFrame.minX,
                    dy: startPoint.y - scrollFrame.minY
                )
            )
            let endCoordinate = scrollOrigin.withOffset(
                CGVector(
                    dx: endPoint.x - scrollFrame.minX,
                    dy: endPoint.y - scrollFrame.minY
                )
            )
            let afterDarkMinYBeforeDrag = afterDarkFrame.minY
            startCoordinate.press(
                forDuration: 0.2,
                thenDragTo: endCoordinate,
                withVelocity: .slow,
                thenHoldForDuration: 0.2
            )
            guard stablePrePositionRoute() else {
                XCTFail("AX-text Preflight after-dark route changed after positioning.")
                return false
            }
            let afterDarkFrameAfterDrag = afterDarkSwitch.frame
            guard isValidFrame(afterDarkFrameAfterDrag) else {
                XCTFail("AX-text Preflight after-dark moved frame is invalid.")
                return false
            }
            let observedAfterDarkShift =
                afterDarkFrameAfterDrag.minY - afterDarkMinYBeforeDrag
            guard observedAfterDarkShift < 0,
                  observedAfterDarkShift * dragDistance > 0 else {
                XCTFail("AX-text Preflight after-dark gesture made no signed progress.")
                return false
            }
            if let previousAfterDarkMinYAfterDrag {
                guard afterDarkFrameAfterDrag.minY
                    < previousAfterDarkMinYAfterDrag else {
                    XCTFail("AX-text Preflight after-dark positioning reversed direction.")
                    return false
                }
            }
            previousAfterDarkMinYAfterDrag = afterDarkFrameAfterDrag.minY
        }
        guard stablePrePositionRoute(),
              afterDarkSwitch.label == expectedAfterDarkLabel,
              afterDarkSwitch.isEnabled,
              (afterDarkSwitch.value as? String) == "0" else {
            XCTFail("AX-text Preflight after-dark final identity is invalid.")
            return false
        }
        let finalApplicationFrame = app.frame
        let finalScreenFrame = preflightScreen.frame
        let finalScrollFrame = preflightScrollView.frame
        let finalNavigationFrame = navigationBar.frame
        let finalTabFrame = tabBar.frame
        let finalAfterDarkFrame = afterDarkSwitch.frame
        let finalFramesAreValid = isValidFrame(finalApplicationFrame)
            && isValidFrame(finalScreenFrame)
            && isValidFrame(finalScrollFrame)
            && isValidFrame(finalNavigationFrame)
            && isValidFrame(finalTabFrame)
            && isValidFrame(finalAfterDarkFrame)
            && finalScreenFrame == finalScrollFrame
        var finalCompositionIsSafe = false
        if finalFramesAreValid {
            let finalLiveScrollFrame = finalScrollFrame.intersection(
                finalApplicationFrame
            )
            if isValidFrame(finalLiveScrollFrame) {
                var finalObstructionTop = min(
                    finalApplicationFrame.maxY,
                    min(finalLiveScrollFrame.maxY, finalTabFrame.minY)
                )
                if keyboards.count == 1,
                   inputViews.count == 1,
                   isValidFrame(keyboard.frame),
                   isValidFrame(inputView.frame) {
                    finalObstructionTop = min(
                        finalObstructionTop,
                        min(keyboard.frame.minY, inputView.frame.minY)
                    )
                }
                let finalSafeTop = max(
                    finalLiveScrollFrame.minY,
                    finalNavigationFrame.maxY
                ) + verticalInset
                let finalSafeBottom = finalObstructionTop - verticalInset
                finalCompositionIsSafe = finalSafeTop.isFinite
                    && finalSafeBottom.isFinite
                    && finalSafeTop <= finalSafeBottom
                    && finalAfterDarkFrame.minY >= finalSafeTop
                    && finalAfterDarkFrame.maxY <= finalSafeBottom
                    && afterDarkSwitch.isHittable
            }
        }
        guard finalCompositionIsSafe else {
            XCTFail("AX-text Preflight after-dark final composition is unsafe.")
            return false
        }
        return true
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
        return [
            "en-US-double-length",
            "ar-RTL-string",
            "en-US-tall",
            "en-US-accented",
            "en-US-bounded",
        ].contains(shard.locale)
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
    private func dismissMultilineKeyboard(
        afterEditing field: XCUIElement,
        on route: XCUIElement,
        clearedValidation: XCUIElement? = nil,
        in app: XCUIApplication
    ) {
        if let clearedValidation {
            guard wait(
                for: clearedValidation,
                predicate: "exists == false",
                timeout: 10
            ) else {
                XCTFail("Multiline validation did not clear after valid input.")
                return
            }
        }
        let keyboard = app.keyboards.firstMatch
        let expectedRouteExists = route.exists
        let expectedApplicationState = app.state
        guard keyboard.exists,
              field.exists,
              (field.elementType == .textField || field.elementType == .textView),
              !field.identifier.isEmpty,
              expectedRouteExists,
              expectedApplicationState == .runningForeground else {
            XCTFail("The multiline dismissal preconditions are not satisfied.")
            return
        }
        let expectedValue = String(describing: field.value ?? "")
        let fieldScrollViews = app.scrollViews.containing(
            field.elementType,
            identifier: field.identifier
        )
        guard fieldScrollViews.count == 1 else {
            XCTFail("The multiline field must have exactly one outer ScrollView.")
            return
        }
        let fieldScrollView = fieldScrollViews.firstMatch
        guard fieldScrollView.exists, fieldScrollView.isHittable else {
            XCTFail("The multiline field ScrollView is not actionable.")
            return
        }
        if field.elementType == .textView {
            let quickPathIntroductionViews = app.descendants(
                matching: .other
            ).matching(
                identifier: "UIContinuousPathIntroductionView"
            )
            let quickPathIntroductionCount =
                quickPathIntroductionViews.count

            if quickPathIntroductionCount > 0 {
                let quickPathIntroductionView =
                    quickPathIntroductionViews.firstMatch
                let quickPathButtons =
                    quickPathIntroductionView.descendants(
                        matching: .button
                    )
                let quickPathStaticTexts =
                    quickPathIntroductionView.descendants(
                        matching: .staticText
                    )
                let quickPathButtonCount = quickPathButtons.count
                let quickPathStaticTextCount = quickPathStaticTexts.count
                let quickPathContinueButton =
                    quickPathButtons.firstMatch
                let quickPathFirstStaticText =
                    quickPathStaticTexts.element(boundBy: 0)
                let quickPathSecondStaticText =
                    quickPathStaticTexts.element(boundBy: 1)
                let quickPathDoneKey = keyboard.buttons["Done"]
                let quickPathReturnKey = keyboard.buttons["Return"]
                let quickPathDoneKeyExists = quickPathDoneKey.exists
                let quickPathReturnKeyExists = quickPathReturnKey.exists
                let quickPathCompletionKey = quickPathDoneKeyExists
                    ? quickPathDoneKey
                    : quickPathReturnKey
                let quickPathCompletionKeyIdentifier = quickPathDoneKeyExists
                    ? "Done"
                    : "Return"
                let quickPathCompletionKeyLabel = quickPathDoneKeyExists
                    ? "done"
                    : "return"
                let fieldFocusPredicate = NSPredicate(
                    format: "hasKeyboardFocus == true"
                )
                let expectedApplicationFrame = app.frame
                let expectedRouteFrame = route.frame
                let expectedFieldFrame = field.frame
                let expectedFieldScrollViewFrame = fieldScrollView.frame
                let expectedKeyboardFrame = keyboard.frame
                let expectedClearedValidationExists =
                    clearedValidation?.exists ?? false
                let frameIsValid: (CGRect) -> Bool = { frame in
                    !frame.isNull
                        && !frame.isEmpty
                        && !frame.isInfinite
                        && frame.origin.x.isFinite
                        && frame.origin.y.isFinite
                        && frame.size.width.isFinite
                        && frame.size.height.isFinite
                }
                guard quickPathIntroductionCount == 1,
                      quickPathButtonCount == 1,
                      quickPathStaticTextCount == 2,
                      quickPathIntroductionView.exists,
                      quickPathIntroductionView.elementType == .other,
                      quickPathIntroductionView.identifier
                        == "UIContinuousPathIntroductionView",
                      quickPathContinueButton.exists,
                      quickPathContinueButton.elementType == .button,
                      quickPathContinueButton.identifier.isEmpty,
                      !quickPathContinueButton.label.trimmingCharacters(
                        in: .whitespacesAndNewlines
                      ).isEmpty,
                      quickPathContinueButton.isEnabled,
                      quickPathContinueButton.isHittable,
                      quickPathFirstStaticText.exists,
                      quickPathFirstStaticText.elementType == .staticText,
                      quickPathFirstStaticText.identifier.isEmpty,
                      !quickPathFirstStaticText.label.trimmingCharacters(
                        in: .whitespacesAndNewlines
                      ).isEmpty,
                      quickPathSecondStaticText.exists,
                      quickPathSecondStaticText.elementType == .staticText,
                      quickPathSecondStaticText.identifier.isEmpty,
                      !quickPathSecondStaticText.label.trimmingCharacters(
                        in: .whitespacesAndNewlines
                      ).isEmpty,
                      quickPathDoneKeyExists != quickPathReturnKeyExists,
                      quickPathCompletionKey.exists,
                      quickPathCompletionKey.elementType == .button,
                      quickPathCompletionKey.identifier
                        == quickPathCompletionKeyIdentifier,
                      quickPathCompletionKey.label.lowercased()
                        == quickPathCompletionKeyLabel,
                      !quickPathCompletionKey.isHittable,
                      fieldFocusPredicate.evaluate(with: field),
                      String(describing: field.value ?? "")
                        == expectedValue,
                      route.exists == expectedRouteExists,
                      fieldScrollViews.count == 1,
                      fieldScrollView.exists,
                      fieldScrollView.isHittable,
                      !expectedClearedValidationExists,
                      app.state == expectedApplicationState,
                      frameIsValid(expectedApplicationFrame),
                      frameIsValid(expectedRouteFrame),
                      frameIsValid(expectedFieldFrame),
                      frameIsValid(expectedFieldScrollViewFrame),
                      frameIsValid(expectedKeyboardFrame),
                      frameIsValid(quickPathIntroductionView.frame),
                      frameIsValid(quickPathContinueButton.frame),
                      frameIsValid(quickPathFirstStaticText.frame),
                      frameIsValid(quickPathSecondStaticText.frame),
                      frameIsValid(quickPathCompletionKey.frame),
                      expectedApplicationFrame.contains(
                          expectedRouteFrame
                      ),
                      expectedApplicationFrame.contains(
                          expectedFieldFrame
                      ),
                      expectedApplicationFrame.contains(
                          expectedFieldScrollViewFrame
                      ),
                      expectedApplicationFrame.contains(
                          expectedKeyboardFrame
                      ),
                      expectedApplicationFrame.contains(
                          quickPathIntroductionView.frame
                      ),
                      quickPathIntroductionView.frame.contains(
                          quickPathContinueButton.frame
                      ),
                      quickPathIntroductionView.frame.contains(
                          quickPathFirstStaticText.frame
                      ),
                      quickPathIntroductionView.frame.contains(
                          quickPathSecondStaticText.frame
                      ),
                      expectedKeyboardFrame.contains(
                          quickPathCompletionKey.frame
                      ),
                      {
                          let buttonLabel = quickPathContinueButton.label
                          let firstLabel = quickPathFirstStaticText.label
                          let secondLabel = quickPathSecondStaticText.label
                          let firstIsActionTitle = firstLabel == buttonLabel
                          let secondIsActionTitle = secondLabel == buttonLabel
                          guard firstIsActionTitle != secondIsActionTitle else {
                              return false
                          }
                          let actionTitle = firstIsActionTitle
                              ? quickPathFirstStaticText
                              : quickPathSecondStaticText
                          let tutorialText = firstIsActionTitle
                              ? quickPathSecondStaticText
                              : quickPathFirstStaticText
                          let actionTitleFrame = actionTitle.frame
                          let tutorialFrame = tutorialText.frame
                          let buttonFrame = quickPathContinueButton.frame
                          return actionTitleFrame.intersects(buttonFrame)
                              && tutorialText.label != buttonLabel
                              && tutorialFrame.maxY <= actionTitleFrame.minY
                              && tutorialFrame.maxY <= buttonFrame.minY
                              && !tutorialFrame.intersects(actionTitleFrame)
                              && !tutorialFrame.intersects(buttonFrame)
                      }() else {
                    XCTFail(
                        "The multiline TextView QuickPath tutorial is incomplete or state changed before dismissal."
                    )
                    return
                }

                let expectedCompletionFrame = quickPathCompletionKey.frame
                quickPathContinueButton.tap()
                guard quickPathIntroductionView.waitForNonExistence(
                    timeout: 10
                ),
                      quickPathIntroductionViews.count == 0,
                      quickPathButtons.count == 0,
                      quickPathStaticTexts.count == 0,
                      keyboard.exists,
                      quickPathCompletionKey.exists,
                      quickPathCompletionKey.elementType == .button,
                      quickPathCompletionKey.identifier
                        == quickPathCompletionKeyIdentifier,
                      quickPathCompletionKey.label.lowercased()
                        == quickPathCompletionKeyLabel,
                      quickPathCompletionKey.isHittable,
                      field.exists,
                      field.elementType == .textView,
                      !field.identifier.isEmpty,
                      fieldFocusPredicate.evaluate(with: field),
                      String(describing: field.value ?? "")
                        == expectedValue,
                      route.exists == expectedRouteExists,
                      fieldScrollViews.count == 1,
                      fieldScrollView.exists,
                      fieldScrollView.isHittable,
                      (clearedValidation?.exists ?? false)
                        == expectedClearedValidationExists,
                      app.state == expectedApplicationState,
                      app.frame == expectedApplicationFrame,
                      route.frame == expectedRouteFrame,
                      field.frame == expectedFieldFrame,
                      fieldScrollView.frame
                        == expectedFieldScrollViewFrame,
                      keyboard.frame == expectedKeyboardFrame,
                      quickPathCompletionKey.frame == expectedCompletionFrame else {
                    XCTFail(
                        "The multiline TextView QuickPath tutorial did not dismiss with state preserved."
                    )
                    return
                }
            }
        }
        fieldScrollView.swipeUp()
        let keyboardDismissed =
            keyboard.waitForNonExistence(timeout: 10)
            || keyboardIsAbsentOrInertOffApp(in: app)
        let contentRouteAndForegroundArePreserved =
            field.exists
            && String(describing: field.value ?? "") == expectedValue
            && route.exists == expectedRouteExists
            && app.state == expectedApplicationState
        if keyboardDismissed && contentRouteAndForegroundArePreserved {
            return
        }
        let fieldFocusPredicate = NSPredicate(
            format: "hasKeyboardFocus == true"
        )
        guard !keyboardDismissed,
              automationShard?.deviceProfileID
                == "iphone-se-3-ios-18.0-minimum",
              field.elementType == .textView,
              keyboard.exists,
              field.exists,
              fieldFocusPredicate.evaluate(with: field),
              String(describing: field.value ?? "") == expectedValue,
              route.exists == expectedRouteExists,
              app.state == expectedApplicationState else {
            XCTFail("Multiline dismissal changed content, route, or foreground state.")
            return
        }
        let beforeCandidateAction: [String: Any] = [
            "applicationStateRawValue": app.state.rawValue,
            "applicationFrame": auditFrameObject(app.frame),
            "keyboardCount": app.keyboards.count,
            "keyboardExists": keyboard.exists,
            "keyboardFrame": auditFrameObject(keyboard.frame),
            "fieldExists": field.exists,
            "fieldIdentifier": field.identifier,
            "fieldTypeRawValue": field.elementType.rawValue,
            "fieldLabel": field.label,
            "fieldValue": String(describing: field.value ?? ""),
            "fieldFrame": auditFrameObject(field.frame),
            "fieldHasKeyboardFocus": fieldFocusPredicate.evaluate(with: field),
            "fieldScrollViewCount": fieldScrollViews.count,
            "fieldScrollViewExists": fieldScrollView.exists,
            "fieldScrollViewFrame": auditFrameObject(fieldScrollView.frame),
            "routeExists": route.exists,
            "routeIdentifier": route.identifier,
            "routeLabel": route.label,
            "routeFrame": auditFrameObject(route.frame),
            "clearedValidationExists": clearedValidation?.exists ?? false,
        ]
        fieldScrollView.swipeDown()
        let candidateKeyboardDismissed =
            keyboard.waitForNonExistence(timeout: 10)
            || keyboardIsAbsentOrInertOffApp(in: app)
        let candidateContentRouteAndForegroundArePreserved =
            field.exists
            && String(describing: field.value ?? "") == expectedValue
            && route.exists == expectedRouteExists
            && app.state == expectedApplicationState
        if candidateKeyboardDismissed
            && candidateContentRouteAndForegroundArePreserved {
            return
        }
        let afterCandidateAction: [String: Any] = [
            "applicationStateRawValue": app.state.rawValue,
            "applicationFrame": auditFrameObject(app.frame),
            "keyboardCount": app.keyboards.count,
            "keyboardExists": keyboard.exists,
            "keyboardFrame": keyboard.exists
                ? auditFrameObject(keyboard.frame)
                : NSNull(),
            "keyboardAbsentOrInertOffApp":
                keyboardIsAbsentOrInertOffApp(in: app),
            "fieldExists": field.exists,
            "fieldIdentifier": field.identifier,
            "fieldTypeRawValue": field.elementType.rawValue,
            "fieldLabel": field.label,
            "fieldValue": String(describing: field.value ?? ""),
            "fieldFrame": auditFrameObject(field.frame),
            "fieldHasKeyboardFocus": fieldFocusPredicate.evaluate(with: field),
            "fieldScrollViewCount": fieldScrollViews.count,
            "fieldScrollViewExists": fieldScrollView.exists,
            "fieldScrollViewFrame": auditFrameObject(fieldScrollView.frame),
            "routeExists": route.exists,
            "routeIdentifier": route.identifier,
            "routeLabel": route.label,
            "routeFrame": auditFrameObject(route.frame),
            "clearedValidationExists": clearedValidation?.exists ?? false,
        ]
        let diagnosticContext: [String: Any] = [
            "schemaVersion": 1,
            "acceptanceEligible": false,
            "shardID": automationShard?.shardID ?? "",
            "deviceProfileID": automationShard?.deviceProfileID ?? "",
            "candidateAction": "fieldScrollView.swipeDown",
            "before": beforeCandidateAction,
            "after": afterCandidateAction,
        ]
        printJSONLine(
            prefix: "S10_4_MINIMUM_OS_MULTILINE_SWIPE_DOWN_DIAGNOSTIC",
            object: diagnosticContext
        )
        let appAttachment = XCTAttachment(screenshot: app.screenshot())
        appAttachment.name =
            "S10.4 minimum-OS multiline swipe-down diagnostic app"
        appAttachment.lifetime = .keepAlways
        add(appAttachment)
        let treeAttachment = XCTAttachment(string: app.debugDescription)
        treeAttachment.name =
            "S10.4 minimum-OS multiline swipe-down diagnostic tree"
        treeAttachment.lifetime = .keepAlways
        add(treeAttachment)
        let contextData = try? JSONSerialization.data(
            withJSONObject: diagnosticContext,
            options: [.prettyPrinted, .sortedKeys]
        )
        let contextAttachment = XCTAttachment(
            string: contextData.map {
                String(decoding: $0, as: UTF8.self)
            } ?? "S10.4 minimum-OS multiline swipe-down diagnostic context encoding failed"
        )
        contextAttachment.name =
            "S10.4 minimum-OS multiline swipe-down diagnostic context"
        contextAttachment.lifetime = .keepAlways
        add(contextAttachment)
        XCTFail(
            "S10.4 minimum-OS multiline swipe-down diagnostic completed nonaccepting"
        )
        return
    }

    @MainActor
    private func keyboardSnapshotTreeIsFullyInertOffApp(
        keyboard: XCUIElement,
        descendants: XCUIElementQuery,
        descendantCount: Int,
        keyCount: Int,
        applicationFrame: CGRect
    ) -> Bool {
        guard let keyboardSnapshot = try? keyboard.snapshot() else {
            return false
        }
        var descendantSnapshots: [any XCUIElementSnapshot] = []
        func appendDescendantSnapshots(
            from snapshot: any XCUIElementSnapshot
        ) {
            for child in snapshot.children {
                descendantSnapshots.append(child)
                appendDescendantSnapshots(from: child)
            }
        }
        appendDescendantSnapshots(from: keyboardSnapshot)

        let snapshotKeyCount = descendantSnapshots.filter {
            $0.elementType == .key
        }.count
        let focusedDescendantCount = descendants.matching(
            NSPredicate(
                format: "hasKeyboardFocus == true"
            )
        ).count
        return descendantSnapshots.count == descendantCount
            && snapshotKeyCount == keyCount
            && descendantSnapshots.allSatisfy { snapshot in
                let snapshotFrame = snapshot.frame
                return !snapshotFrame.isEmpty
                    && snapshotFrame.minY >= applicationFrame.maxY
            }
            && focusedDescendantCount == 0
    }

    @MainActor
    private func keyboardIsAbsentOrInertOffApp(
        in app: XCUIApplication
    ) -> Bool {
        let keyboardQuery = app.keyboards
        let keyboardCount = keyboardQuery.count
        if keyboardCount == 0 {
            return app.state == .runningForeground
        }
        guard keyboardCount == 1,
              automationShard?.deviceProfileID == "iphone-se-3-ios-18.0-minimum" else {
            return false
        }

        let keyboard = keyboardQuery.firstMatch
        guard keyboard.exists else { return false }
        let applicationFrame = app.frame
        let keyboardFrame = keyboard.frame
        let keyboardDescendants = keyboard.descendants(
            matching: .any
        )
        let keyboardKeys = keyboard.keys
        let keyboardDescendantCount = keyboardDescendants.count
        let keyboardKeyCount = keyboardKeys.count
        let focusIsAbsent = NSPredicate(
            format: "hasKeyboardFocus == false"
        )
        let keyboardFocusIsAbsent = focusIsAbsent.evaluate(with: keyboard)
        let keyboardTreeIsEmpty =
            keyboardDescendantCount == 0
            && keyboardKeyCount == 0
        let keyboardTreeIsNonemptyAndInert =
            keyboardDescendantCount > 0
            && keyboardKeyCount > 0
            && keyboardKeyCount <= keyboardDescendantCount
            && keyboardSnapshotTreeIsFullyInertOffApp(
                keyboard: keyboard,
                descendants: keyboardDescendants,
                descendantCount: keyboardDescendantCount,
                keyCount: keyboardKeyCount,
                applicationFrame: applicationFrame
            )
        return !applicationFrame.isEmpty
            && !keyboardFrame.isEmpty
            && keyboardFrame.minY >= applicationFrame.maxY
            && keyboardFocusIsAbsent
            && !keyboard.isHittable
            && (keyboardTreeIsEmpty || keyboardTreeIsNonemptyAndInert)
            && app.state == .runningForeground
    }

    @MainActor
    private func dismissKeyboard(in app: XCUIApplication) {
        let keyboard = app.keyboards.firstMatch
        guard keyboard.exists else { return }
        let doneKey = keyboard.buttons["Done"]
        let returnKey = keyboard.buttons["Return"]
        if doneKey.exists && doneKey.isHittable {
            doneKey.tap()
        } else if returnKey.exists && returnKey.isHittable {
            returnKey.tap()
        } else if automationShard?.deviceProfileID == "iphone-se-3-ios-18.0-minimum"
            && returnKey.exists {
            let applicationFrame = app.frame
            let keyboardFrame = keyboard.frame
            guard !applicationFrame.isEmpty,
                  !keyboardFrame.isEmpty else {
                XCTFail("The minimum-profile application or keyboard frame is empty.")
                return
            }
            if keyboardFrame.minY >= applicationFrame.maxY {
                app.swipeDown()
                if wait(
                    for: keyboard,
                    predicate: "exists == false",
                    timeout: 10
                ) {
                    guard app.state == .runningForeground else {
                        XCTFail(
                            "The app left the foreground while dismissing the minimum-profile keyboard."
                        )
                        return
                    }
                    return
                }
                let postSwipeApplicationFrame = app.frame
                let postSwipeKeyboardFrame = keyboard.frame
                let keyboardDescendants = keyboard.descendants(
                    matching: .any
                )
                let keyboardKeys = keyboard.keys
                let keyboardDescendantCount = keyboardDescendants.count
                let keyboardKeyCount = keyboardKeys.count
                let focusIsAbsent = NSPredicate(
                    format: "hasKeyboardFocus == false"
                )
                let keyboardFocusIsAbsent = focusIsAbsent.evaluate(with: keyboard)
                let keyboardTreeIsEmpty =
                    keyboardDescendantCount == 0
                    && keyboardKeyCount == 0
                let keyboardTreeIsNonemptyAndInert =
                    keyboardDescendantCount > 0
                    && keyboardKeyCount > 0
                    && keyboardKeyCount <= keyboardDescendantCount
                    && keyboardSnapshotTreeIsFullyInertOffApp(
                        keyboard: keyboard,
                        descendants: keyboardDescendants,
                        descendantCount: keyboardDescendantCount,
                        keyCount: keyboardKeyCount,
                        applicationFrame: postSwipeApplicationFrame
                    )
                guard !postSwipeApplicationFrame.isEmpty,
                      !postSwipeKeyboardFrame.isEmpty,
                      postSwipeKeyboardFrame.minY >= postSwipeApplicationFrame.maxY,
                      keyboardFocusIsAbsent,
                      keyboardTreeIsEmpty || keyboardTreeIsNonemptyAndInert,
                      app.state == .runningForeground else {
                    XCTFail(
                        "The minimum-profile off-app keyboard wrapper did not become inert."
                    )
                    return
                }
                return
            } else {
                guard returnKey.elementType == .button,
                      returnKey.label.lowercased() == "return" else {
                    XCTFail("The minimum-profile Return key identity is not frozen.")
                    return
                }
                let expectedKeyboardFrame = CGRect(
                    x: 0,
                    y: 451,
                    width: 375,
                    height: 216
                )
                let returnFrame = returnKey.frame
                guard keyboardFrame == expectedKeyboardFrame,
                      returnFrame.minX == 281.5,
                      returnFrame.width == 93.5 else {
                    XCTFail("The minimum-profile keyboard geometry is not frozen.")
                    return
                }
                keyboard.coordinate(
                    withNormalizedOffset: CGVector(
                        dx: 0.8753333333333333,
                        dy: 0.5740740740740741
                    )
                ).tap()
            }
        } else {
            app.swipeDown()
        }
        var keyboardDismissed = wait(
            for: keyboard,
            predicate: "exists == false",
            timeout: 10
        )
        if !keyboardDismissed,
           automationShard?.deviceProfileID == "iphone-se-3-ios-18.0-minimum",
           keyboard.exists {
            app.swipeDown()
            keyboardDismissed = wait(
                for: keyboard,
                predicate: "exists == false",
                timeout: 10
            )
        }
        guard keyboardDismissed, app.state == .runningForeground else {
            XCTFail("The keyboard did not dismiss while the app remained foregrounded.")
            return
        }
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
    private func scrollReportPreviewForAXText(
        _ preview: XCUIElement,
        in app: XCUIApplication
    ) -> Bool {
        let reportScrollViews = app.scrollViews.containing(
            .other,
            identifier: "s4.3.report-detail.preview"
        )
        guard reportScrollViews.count == 1 else {
            XCTFail("AX-text report detail must expose exactly one ScrollView.")
            return false
        }
        let reportScroll = reportScrollViews.firstMatch
        guard reportScroll.waitForExistence(timeout: 10) else {
            XCTFail("AX-text report detail ScrollView is missing.")
            return false
        }
        let navigationBars = app.navigationBars
        guard navigationBars.count == 1 else {
            XCTFail("AX-text report detail must expose exactly one navigation bar.")
            return false
        }
        let navigationBar = navigationBars.firstMatch
        let pageIndicators = app.descendants(matching: .other).matching(
            NSPredicate(
                format: "label == %@",
                "Vertical scroll bar, 4 pages"
            )
        )
        func currentIndicatorGeometry(
            previewFrame: CGRect,
            liveScrollFrame: CGRect
        ) -> (outer: CGRect, inner: CGRect)? {
            guard pageIndicators.count == 2 else { return nil }
            let indicators = (0..<2).map {
                pageIndicators.element(boundBy: $0)
            }
            let frames = indicators.map(\.frame)
            guard pageIndicators.count == 2,
                  indicators.allSatisfy(\.exists),
                  frames.allSatisfy({ !$0.isNull && !$0.isEmpty }) else {
                return nil
            }
            guard frames[0] != frames[1] else { return nil }
            let innerCandidates = frames.indices.filter {
                previewFrame.contains(frames[$0])
            }
            guard innerCandidates.count == 1 else { return nil }
            let innerIndex = innerCandidates[0]
            let outerCandidates = frames.indices.filter {
                $0 != innerIndex
                    && liveScrollFrame.contains(frames[$0])
            }
            guard outerCandidates.count == 1 else { return nil }
            return (frames[outerCandidates[0]], frames[innerIndex])
        }
        let verticalInset: CGFloat = 24
        let horizontalInset: CGFloat = 24
        let minimumGestureDistance: CGFloat = 44
        for _ in 0..<4 {
            let reportScrollFrame = reportScroll.frame
            let liveScrollFrame = reportScrollFrame.intersection(app.frame)
            let previewFrame = preview.frame
            guard app.state == .runningForeground,
                  reportScrollViews.count == 1,
                  navigationBars.count == 1,
                  reportScroll.exists,
                  navigationBar.exists,
                  preview.exists,
                  !liveScrollFrame.isNull,
                  !liveScrollFrame.isEmpty,
                  let indicators = currentIndicatorGeometry(
                      previewFrame: previewFrame,
                      liveScrollFrame: liveScrollFrame
                  ) else {
                XCTFail("AX-text report preview hierarchy is not stable.")
                return false
            }
            if preview.isHittable { return true }
            let safeTop = max(
                liveScrollFrame.minY,
                navigationBar.frame.maxY
            ) + verticalInset
            let safeBottom = min(
                liveScrollFrame.maxY,
                indicators.outer.maxY
            ) - verticalInset
            let safeLeft = liveScrollFrame.minX + horizontalInset
            let safeRight = liveScrollFrame.maxX - horizontalInset
            let maximumGestureDistance = safeBottom - safeTop
            guard safeRight > safeLeft,
                  maximumGestureDistance >= minimumGestureDistance,
                  previewFrame.height <= maximumGestureDistance else {
                XCTFail("AX-text report preview has no stable live scrolling band.")
                return false
            }
            let minimumShift = safeTop - previewFrame.minY
            let maximumShift = safeBottom - previewFrame.maxY
            guard minimumShift <= maximumShift else {
                XCTFail("AX-text report preview cannot fit the live scrolling band.")
                return false
            }
            let recognizedMinimum = max(
                minimumShift,
                -maximumGestureDistance
            )
            let recognizedMaximum = min(
                maximumShift,
                -minimumGestureDistance
            )
            let dragDistance: CGFloat
            if recognizedMinimum <= recognizedMaximum {
                dragDistance = recognizedMaximum
            } else if maximumShift < -maximumGestureDistance {
                dragDistance = -maximumGestureDistance
            } else {
                XCTFail("AX-text report preview has no progressive or final upward shift.")
                return false
            }
            let previousPreviewMinY = previewFrame.minY
            let reportScrollOrigin = reportScroll.coordinate(
                withNormalizedOffset: CGVector(dx: 0, dy: 0)
            )
            let dragStart = reportScrollOrigin.withOffset(
                CGVector(
                    dx: liveScrollFrame.midX - reportScrollFrame.minX,
                    dy: safeBottom - reportScrollFrame.minY
                )
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
            guard app.state == .runningForeground,
                  reportScrollViews.count == 1,
                  navigationBars.count == 1,
                  pageIndicators.count == 2,
                  preview.exists,
                  preview.frame.minY < previousPreviewMinY else {
                XCTFail("AX-text report preview did not move upward with its ScrollView.")
                return false
            }
        }
        let finalLiveScrollFrame = reportScroll.frame.intersection(app.frame)
        guard app.state == .runningForeground,
              reportScrollViews.count == 1,
              navigationBars.count == 1,
              reportScroll.exists,
              navigationBar.exists,
              preview.exists,
              !finalLiveScrollFrame.isNull,
              !finalLiveScrollFrame.isEmpty,
              let _ = currentIndicatorGeometry(
                  previewFrame: preview.frame,
                  liveScrollFrame: finalLiveScrollFrame
              ),
              preview.isHittable else {
            XCTFail("AX-text report preview remained nonhittable after four gestures.")
            return false
        }
        return true
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

final class S10_4DevelopmentProbeUITests: S10BrandMigrationRouteUITestCase {
    @MainActor
    func testFocusedDiagnosticProbe() throws {
        try runFocusedDiagnosticProbeFromEnvironment()
    }
}

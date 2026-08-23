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
            issueID: "S10.4-XCUI-CONTRAST-FP-AX-TEXT-WORK-VALIDATION-SHORT-DESCRIPTION",
            shardID: "s10.4.current.ax-text",
            stateID: "state.work.validation-error",
            taskID: "work_and_recheck",
            owner: "palatis3",
            expiresAt: "2026-11-20",
            rationale: "Xcode 26.6/iOS 26.2 reports a SwiftUI.AccessibilityNode contrast issue for the empty-identifier Short description field label whose frozen public frame intersects native Record work navigation chrome and is not hittable, while the separate identified Short description validation node is fully visible, hittable, and rendered with primaryText; the audit-owned crop confirms the issue is limited to that chrome-overlapped composition, and the exception is limited to the frozen public issue signature.",
            auditTypeRawValue: "1",
            compactDescription: "Contrast failed",
            detailedDescription: "Contrast failed for SwiftUI.AccessibilityNode",
            elementIdentifier: "",
            elementLabel: "Short description",
            elementTypeDescription: "XCUIElementType(rawValue: 48)",
            elementFrame: CGRect(
                x: 30.333333333333332,
                y: 36.666666666666686,
                width: 333.66666666666663,
                height: 51.333333333333314
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

        try completeWorkAndResolvedRecheckAtXXXL(in: app)
        captureAlternativeCompletedCheckStates(in: app)
        captureDifferentIssueStatesBeforeRecovery(in: app)
        app.terminate()
        app.launch()
        recoverInjectedPDFFailureAtXXXL(in: app)
        captureReportComparisonAndCorrectionStates(in: app)
        captureUnavailablePaywallAndFeedbackReview(in: app)
        try assertMonthlyPaywallAtXXXL(in: app)
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
        let prePositionSiteValue = site.value as? String
        let prePositionSignValue = sign.value as? String
        let prePositionErrorLabel = error.label
        let prePositionErrorValue = error.value as? String
        let validationDetailRoute = element("s2.sign-detail.screen", in: app)
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
                          wait(
                              for: site,
                              predicate: "hasKeyboardFocus == true",
                              timeout: 10
                          ),
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
        if !runsAXTextDeleteConfirmationDiagnostic
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
                        for _ in 0..<4 {
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
                            guard receiverCapacity >= minimumGestureDistance,
                                  abs(maximumShift)
                                    >= minimumGestureDistance else {
                                XCTFail(
                                    "The minimum double-length preflight confirmation has no recognized upward shift."
                                )
                                return
                            }
                            let dragDistance: CGFloat
                            if abs(maximumShift) <= receiverCapacity {
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
                              wait(
                                  for: zone,
                                  predicate: "hasKeyboardFocus == true",
                                  timeout: 10
                              ),
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
                    keyboard.coordinate(
                        withNormalizedOffset: CGVector(
                            dx: 0.5,
                            dy: 0.8425925925925926
                        )
                    ).tap()
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
                          restoredDoneKey.label == "done",
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
                          restoredDoneKey.label == "done",
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
        setToggle("s3.preflight.after-dark", in: app)
        app.swipeUp()
        setToggle("s3.preflight.safe-position", in: app)

        let begin = element("s3.preflight.begin", in: app)
        scroll(begin, in: app)
        assertControl(begin, label: "Begin check")
        begin.tap()

        XCTAssertTrue(element("s3.capture.screen", in: app)
            .waitForExistence(timeout: 20))
        if automationShard?.shardID == "s10.4.current.ax-text" {
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
        if automationShard?.shardID == "s10.4.current.ax-text" {
            guard scrollReportPreviewForAXText(preview, in: app) else { return }
        } else {
            scroll(preview, in: app)
        }
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
        if automationShard?.shardID == "s10.4.current.ax-text" {
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
        if automationShard?.shardID == "s10.4.current.ax-text" {
            guard positionSignDetailTimeZoneForAXText(in: app) else {
                throw AutomationConfigurationError.invalid(
                    "S10.4 AX-text sign-detail time-zone positioning failed"
                )
            }
        }
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
        dismissMultilineKeyboard(
            afterEditing: description,
            on: element("s5.1.work.screen", in: app),
            clearedValidation: validation,
            in: app
        )

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
        let workHelperLabel = "Add one optional photo showing the work performed."
        let workHelperTexts = app.staticTexts.matching(
            NSPredicate(format: "label == %@", workHelperLabel)
        )
        let workScrollViews = app.scrollViews.containing(
            .image,
            identifier: "s5.1.work.photo"
        )
        let workNavigationBars = app.navigationBars.matching(
            identifier: "Record work"
        )
        guard workHelperTexts.count == 1,
              workScrollViews.count == 1,
              workNavigationBars.count == 1 else {
            XCTFail("Record-work editing positioning bindings are ambiguous.")
            return
        }
        let workHelper = workHelperTexts.firstMatch
        let workScrollView = workScrollViews.firstMatch
        let workNavigationBar = workNavigationBars.firstMatch
        guard workHelper.exists,
              workScrollView.exists,
              workNavigationBar.exists else {
            XCTFail("Record-work editing positioning bindings are missing.")
            return
        }
        let verticalInset: CGFloat = 16
        let receiverInset: CGFloat = 24
        let minimumGestureDistance: CGFloat = 44
        let workEditingDiagnosticEnabled =
            automationShard?.shardID == "s10.4.current.ax-text"
        let workEditingDiagnosticStartedAt = ProcessInfo.processInfo.systemUptime
        let workEditingDiagnosticWorkScreens = app.descendants(matching: .any).matching(
            identifier: "s5.1.work.screen"
        )
        let workEditingDiagnosticPreviewElements = app.descendants(matching: .any).matching(
            identifier: "s5.1.work.photo"
        )
        let workEditingDiagnosticTabBars = app.tabBars
        let workEditingDiagnosticQueries: [(String, XCUIElementQuery)] = [
            ("workScreens", workEditingDiagnosticWorkScreens),
            ("helperTexts", workHelperTexts),
            ("previewElements", workEditingDiagnosticPreviewElements),
            ("scrollViews", workScrollViews),
            ("navigationBars", workNavigationBars),
            ("tabBars", workEditingDiagnosticTabBars),
        ]
        let workEditingDiagnosticFrameObject: (CGRect) -> Any = { [self] frame in
            frame.origin.x.isFinite
                && frame.origin.y.isFinite
                && frame.size.width.isFinite
                && frame.size.height.isFinite
                ? auditFrameObject(frame) as Any
                : NSNull()
        }
        let workEditingDiagnosticElementObject: (XCUIElement) -> [String: Any] = {
            element in
            [
                "exists": element.exists,
                "isHittable": element.isHittable,
                "identifier": element.identifier,
                "label": element.label,
                "value": ((element.value as? String) as Any?) ?? NSNull(),
                "elementTypeRawValue": element.elementType.rawValue,
                "elementTypeDescription": String(describing: element.elementType),
                "frame": workEditingDiagnosticFrameObject(element.frame),
            ]
        }
        var workEditingDiagnosticSampleCount = 0
        var workEditingDiagnosticCompletedGestureCount = 0
        let emitWorkEditingPositioningDiagnostic:
            (String, Int?, [String: Any]) -> Void = {
                [self] phase, attemptOrdinal, details in
                workEditingDiagnosticSampleCount += 1
                var queryObjects: [String: Any] = [:]
                for (name, query) in workEditingDiagnosticQueries {
                    let count = query.count
                    var elements: [[String: Any]] = []
                    for index in 0..<count {
                        elements.append(
                            workEditingDiagnosticElementObject(
                                query.element(boundBy: index)
                            )
                        )
                    }
                    queryObjects[name] = [
                        "count": count,
                        "elements": elements,
                    ]
                }
                let attemptOrdinalObject: Any
                if let attemptOrdinal = attemptOrdinal {
                    attemptOrdinalObject = attemptOrdinal
                } else {
                    attemptOrdinalObject = NSNull()
                }
                let elapsedMilliseconds = Int(
                    (ProcessInfo.processInfo.systemUptime
                        - workEditingDiagnosticStartedAt) * 1_000
                )
                printJSONLine(
                    prefix: "S10_4_WORK_EDITING_POSITIONING_DIAGNOSTIC",
                    object: [
                        "shardID": automationShard?.shardID ?? "",
                        "deviceProfileID": automationShard?.deviceProfileID ?? "",
                        "stateID": "state.work.editing",
                        "phase": phase,
                        "sampleOrdinal": workEditingDiagnosticSampleCount,
                        "attemptOrdinal": attemptOrdinalObject,
                        "elapsedMilliseconds": elapsedMilliseconds,
                        "applicationStateRawValue": app.state.rawValue,
                        "isRunningForeground": app.state == .runningForeground,
                        "applicationFrame": workEditingDiagnosticFrameObject(app.frame),
                        "queries": queryObjects,
                        "details": details,
                    ]
                )
            }
        if workEditingDiagnosticEnabled {
            emitWorkEditingPositioningDiagnostic(
                "initial",
                nil,
                [
                    "verticalInset": Double(verticalInset),
                    "receiverInset": Double(receiverInset),
                    "minimumGestureDistance": Double(minimumGestureDistance),
                    "helperFrame": workEditingDiagnosticFrameObject(workHelper.frame),
                    "previewFrame": workEditingDiagnosticFrameObject(workPreview.frame),
                    "scrollFrame": workEditingDiagnosticFrameObject(workScrollView.frame),
                    "navigationFrame": workEditingDiagnosticFrameObject(
                        workNavigationBar.frame
                    ),
                ]
            )
            let startScreenshot = XCTAttachment(
                screenshot: XCUIScreen.main.screenshot()
            )
            startScreenshot.name =
                "S10.4 AX-text work-editing positioning diagnostic start screenshot"
            startScreenshot.lifetime = .keepAlways
            add(startScreenshot)
            let startTree = XCTAttachment(string: app.debugDescription)
            startTree.name =
                "S10.4 AX-text work-editing positioning diagnostic start tree"
            startTree.lifetime = .keepAlways
            add(startTree)
        }
        for _ in 0..<4 {
            guard app.state == .runningForeground,
                  workHelperTexts.count == 1,
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
            let liveScrollFrame = scrollFrame.intersection(applicationFrame)
            let safeTop = max(
                liveScrollFrame.minY,
                navigationFrame.maxY
            ) + verticalInset
            let safeBottom = liveScrollFrame.maxY - verticalInset
            let receiverTop = max(
                liveScrollFrame.minY,
                navigationFrame.maxY
            ) + receiverInset
            let receiverBottom = liveScrollFrame.maxY - receiverInset
            let helperFrame = workHelper.frame
            guard !applicationFrame.isNull,
                  !applicationFrame.isEmpty,
                  !navigationFrame.isNull,
                  !navigationFrame.isEmpty,
                  !scrollFrame.isNull,
                  !scrollFrame.isEmpty,
                  !liveScrollFrame.isNull,
                  !liveScrollFrame.isEmpty,
                  !helperFrame.isNull,
                  !helperFrame.isEmpty,
                  safeBottom > safeTop,
                  helperFrame.height <= safeBottom - safeTop else {
                XCTFail("Record-work editing viewport geometry is invalid.")
                return
            }
            if helperFrame.minY >= safeTop,
               helperFrame.maxY <= safeBottom,
               workHelper.isHittable {
                break
            }

            let minimumShift = safeTop - helperFrame.minY
            let maximumShift = safeBottom - helperFrame.maxY
            let receiverCapacity = receiverBottom - receiverTop
            let recognizedMinimum = max(
                minimumShift,
                minimumGestureDistance
            )
            let recognizedMaximum = min(
                maximumShift,
                receiverCapacity
            )
            guard minimumShift > 0,
                  minimumShift <= maximumShift,
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
            var workEditingDiagnosticPreviewFrameBeforeDrag = CGRect.null
            let workEditingDiagnosticGestureOrdinal =
                workEditingDiagnosticCompletedGestureCount + 1
            if workEditingDiagnosticEnabled {
                workEditingDiagnosticPreviewFrameBeforeDrag = workPreview.frame
                emitWorkEditingPositioningDiagnostic(
                    "beforeGesture",
                    workEditingDiagnosticGestureOrdinal,
                    [
                        "geometry": [
                            "applicationFrame": workEditingDiagnosticFrameObject(
                                applicationFrame
                            ),
                            "navigationFrame": workEditingDiagnosticFrameObject(
                                navigationFrame
                            ),
                            "scrollFrame": workEditingDiagnosticFrameObject(scrollFrame),
                            "liveScrollFrame": workEditingDiagnosticFrameObject(
                                liveScrollFrame
                            ),
                            "helperFrame": workEditingDiagnosticFrameObject(helperFrame),
                            "previewFrame": workEditingDiagnosticFrameObject(
                                workEditingDiagnosticPreviewFrameBeforeDrag
                            ),
                            "safeTop": Double(safeTop),
                            "safeBottom": Double(safeBottom),
                            "receiverTop": Double(receiverTop),
                            "receiverBottom": Double(receiverBottom),
                            "minimumShift": Double(minimumShift),
                            "maximumShift": Double(maximumShift),
                            "receiverCapacity": Double(receiverCapacity),
                            "recognizedMinimum": Double(recognizedMinimum),
                            "recognizedMaximum": Double(recognizedMaximum),
                        ],
                        "gesture": [
                            "requestedDistance": Double(dragDistance),
                            "startPoint": [
                                "x": Double(scrollFrame.midX),
                                "y": Double(receiverTop),
                            ],
                            "endPoint": [
                                "x": Double(scrollFrame.midX),
                                "y": Double(receiverTop + dragDistance),
                            ],
                        ],
                    ]
                )
            }
            dragStart.press(
                forDuration: 0.2,
                thenDragTo: dragEnd,
                withVelocity: .slow,
                thenHoldForDuration: 0.2
            )
            if workEditingDiagnosticEnabled {
                workEditingDiagnosticCompletedGestureCount += 1
                let helperFrameAfterDrag = workHelper.frame
                let previewFrameAfterDrag = workPreview.frame
                let observedHelperDistance =
                    helperFrameAfterDrag.minY - helperFrame.minY
                let observedPreviewDistance =
                    previewFrameAfterDrag.minY
                        - workEditingDiagnosticPreviewFrameBeforeDrag.minY
                emitWorkEditingPositioningDiagnostic(
                    "afterGesture",
                    workEditingDiagnosticGestureOrdinal,
                    [
                        "geometry": [
                            "helperFrameBefore": workEditingDiagnosticFrameObject(
                                helperFrame
                            ),
                            "helperFrameAfter": workEditingDiagnosticFrameObject(
                                helperFrameAfterDrag
                            ),
                            "previewFrameBefore": workEditingDiagnosticFrameObject(
                                workEditingDiagnosticPreviewFrameBeforeDrag
                            ),
                            "previewFrameAfter": workEditingDiagnosticFrameObject(
                                previewFrameAfterDrag
                            ),
                        ],
                        "gesture": [
                            "requestedDistance": Double(dragDistance),
                            "observedHelperDistance": Double(observedHelperDistance),
                            "observedPreviewDistance": Double(observedPreviewDistance),
                            "helperMovedDownward": observedHelperDistance > 0,
                            "previewMovedDownward": observedPreviewDistance > 0,
                            "previewMovedUpward": observedPreviewDistance < 0,
                        ],
                    ]
                )
            }
            guard workHelperTexts.count == 1,
                  workScrollViews.count == 1,
                  workNavigationBars.count == 1,
                  workHelper.exists,
                  workHelper.frame.minY > helperMinYBeforeDrag else {
                XCTFail("Record-work helper did not move downward.")
                return
            }
        }
        let finalApplicationFrame = app.frame
        let finalNavigationFrame = workNavigationBar.frame
        let finalScrollFrame = workScrollView.frame.intersection(
            finalApplicationFrame
        )
        let finalSafeTop = max(
            finalScrollFrame.minY,
            finalNavigationFrame.maxY
        ) + verticalInset
        let finalSafeBottom = finalScrollFrame.maxY - verticalInset
        let finalHelperFrame = workHelper.frame
        if workEditingDiagnosticEnabled {
            let finalPreviewFrame = workPreview.frame
            let finalTabBar = workEditingDiagnosticTabBars.firstMatch
            let finalTabBarExists = finalTabBar.exists
            let finalTabBarFrame = finalTabBarExists ? finalTabBar.frame : CGRect.null
            let finalApplicationFrameIsValid =
                !finalApplicationFrame.isNull && !finalApplicationFrame.isEmpty
            let finalNavigationFrameIsValid =
                !finalNavigationFrame.isNull && !finalNavigationFrame.isEmpty
            let finalScrollFrameIsValid =
                !finalScrollFrame.isNull && !finalScrollFrame.isEmpty
            let finalHelperFrameIsValid =
                !finalHelperFrame.isNull && !finalHelperFrame.isEmpty
            let finalPreviewFrameIsValid =
                !finalPreviewFrame.isNull && !finalPreviewFrame.isEmpty
            let finalTabBarFrameIsValid =
                !finalTabBarFrame.isNull && !finalTabBarFrame.isEmpty
            let finalHelperAboveSafeTop = finalHelperFrameIsValid
                && finalHelperFrame.minY >= finalSafeTop
            let finalHelperBelowSafeBottom = finalHelperFrameIsValid
                && finalHelperFrame.maxY <= finalSafeBottom
            let finalHelperIsHittable = workHelper.isHittable
            let finalPreviewIsHittable = workPreview.isHittable
            let finalPreviewContainedInApplication = finalPreviewFrameIsValid
                && finalApplicationFrameIsValid
                && finalApplicationFrame.contains(finalPreviewFrame)
            let finalPreviewContainedInLiveScroll = finalPreviewFrameIsValid
                && finalScrollFrameIsValid
                && finalScrollFrame.contains(finalPreviewFrame)
            let finalPreviewContainedInSafeBand = finalPreviewFrameIsValid
                && finalPreviewFrame.minY >= finalSafeTop
                && finalPreviewFrame.maxY <= finalSafeBottom
            let finalPreviewIntersectsNavigation = finalPreviewFrameIsValid
                && finalNavigationFrameIsValid
                && finalPreviewFrame.intersects(finalNavigationFrame)
            let finalPreviewIntersectsTabBar = finalPreviewFrameIsValid
                && finalTabBarFrameIsValid
                && finalPreviewFrame.intersects(finalTabBarFrame)
            emitWorkEditingPositioningDiagnostic(
                "final",
                nil,
                [
                    "geometry": [
                        "applicationFrame": workEditingDiagnosticFrameObject(
                            finalApplicationFrame
                        ),
                        "navigationFrame": workEditingDiagnosticFrameObject(
                            finalNavigationFrame
                        ),
                        "scrollFrame": workEditingDiagnosticFrameObject(finalScrollFrame),
                        "helperFrame": workEditingDiagnosticFrameObject(finalHelperFrame),
                        "previewFrame": workEditingDiagnosticFrameObject(finalPreviewFrame),
                        "tabBarFrame": workEditingDiagnosticFrameObject(finalTabBarFrame),
                        "safeTop": Double(finalSafeTop),
                        "safeBottom": Double(finalSafeBottom),
                    ],
                    "predicates": [
                        "applicationRunningForeground":
                            app.state == .runningForeground,
                        "helperTextCountIsOne": workHelperTexts.count == 1,
                        "scrollViewCountIsOne": workScrollViews.count == 1,
                        "navigationBarCountIsOne": workNavigationBars.count == 1,
                        "tabBarCountIsOne": workEditingDiagnosticTabBars.count == 1,
                        "helperExists": workHelper.exists,
                        "scrollViewExists": workScrollView.exists,
                        "navigationBarExists": workNavigationBar.exists,
                        "previewExists": workPreview.exists,
                        "tabBarExists": finalTabBarExists,
                        "applicationFrameIsValid": finalApplicationFrameIsValid,
                        "navigationFrameIsValid": finalNavigationFrameIsValid,
                        "scrollFrameIsValid": finalScrollFrameIsValid,
                        "helperFrameIsValid": finalHelperFrameIsValid,
                        "previewFrameIsValid": finalPreviewFrameIsValid,
                        "tabBarFrameIsValid": finalTabBarFrameIsValid,
                        "helperAboveSafeTop": finalHelperAboveSafeTop,
                        "helperBelowSafeBottom": finalHelperBelowSafeBottom,
                        "helperIsHittable": finalHelperIsHittable,
                        "previewIsHittable": finalPreviewIsHittable,
                        "previewContainedInApplication":
                            finalPreviewContainedInApplication,
                        "previewContainedInLiveScroll":
                            finalPreviewContainedInLiveScroll,
                        "previewContainedInSafeBand": finalPreviewContainedInSafeBand,
                        "previewIntersectsNavigation":
                            finalPreviewIntersectsNavigation,
                        "previewIntersectsTabBar": finalPreviewIntersectsTabBar,
                    ],
                ]
            )
            printJSONLine(
                prefix: "S10_4_WORK_EDITING_POSITIONING_DIAGNOSTIC_COUNT",
                object: [
                    "shardID": automationShard?.shardID ?? "",
                    "deviceProfileID": automationShard?.deviceProfileID ?? "",
                    "stateID": "state.work.editing",
                    "sampleCount": workEditingDiagnosticSampleCount,
                    "completedGestureCount":
                        workEditingDiagnosticCompletedGestureCount,
                    "finalHelperIsHittable": finalHelperIsHittable,
                    "finalPreviewIsHittable": finalPreviewIsHittable,
                ]
            )
            let terminalScreenshot = XCTAttachment(
                screenshot: XCUIScreen.main.screenshot()
            )
            terminalScreenshot.name =
                "S10.4 AX-text work-editing positioning diagnostic terminal screenshot"
            terminalScreenshot.lifetime = .keepAlways
            add(terminalScreenshot)
            let terminalTree = XCTAttachment(string: app.debugDescription)
            terminalTree.name =
                "S10.4 AX-text work-editing positioning diagnostic terminal tree"
            terminalTree.lifetime = .keepAlways
            add(terminalTree)
            throw AutomationConfigurationError.invalid(
                "S10.4 AX-text Record-work editing positioning diagnostic"
            )
        }
        guard app.state == .runningForeground,
              workHelperTexts.count == 1,
              workScrollViews.count == 1,
              workNavigationBars.count == 1,
              workHelper.exists,
              workScrollView.exists,
              workNavigationBar.exists,
              workPreview.exists,
              !finalApplicationFrame.isNull,
              !finalApplicationFrame.isEmpty,
              !finalNavigationFrame.isNull,
              !finalNavigationFrame.isEmpty,
              !finalScrollFrame.isNull,
              !finalScrollFrame.isEmpty,
              !finalHelperFrame.isNull,
              !finalHelperFrame.isEmpty,
              finalHelperFrame.minY >= finalSafeTop,
              finalHelperFrame.maxY <= finalSafeBottom,
              workHelper.isHittable,
              workPreview.isHittable else {
            XCTFail("Record-work editing composition is outside the safe viewport.")
            return
        }
        captureBaseline("state.work.editing", in: app)

        scroll(saveWork, in: app)
        assertControl(saveWork, label: "Record work")
        saveWork.tap()
        let progress = element("s5.1.work.saving", in: app)
        XCTAssertTrue(progress.waitForExistence(timeout: 10))
        assertLocalizedLabel(progress, equals: "Record work")
        let workNoteHeadings = app.staticTexts.matching(
            NSPredicate(format: "label == %@", "Note")
        )
        let workTabBars = app.tabBars
        let workNoteHeading = workNoteHeadings.firstMatch
        let workTabBar = workTabBars.firstMatch
        guard app.state == .runningForeground,
              workNoteHeadings.count == 1,
              workTabBars.count == 1,
              workHelperTexts.count == 1,
              workScrollViews.count == 1,
              workNavigationBars.count == 1,
              workNoteHeading.exists,
              workTabBar.exists,
              workNoteHeading.identifier.isEmpty,
              workNoteHeading.label == "Note",
              workNoteHeading.elementType == .staticText,
              workHelper.exists,
              workScrollView.exists,
              workNavigationBar.exists,
              workPreview.exists,
              progress.exists else {
            XCTFail("Record-work saving positioning route changed.")
            return
        }
        for _ in 0..<4 {
            guard app.state == .runningForeground,
                  workNoteHeadings.count == 1,
                  workTabBars.count == 1,
                  workHelperTexts.count == 1,
                  workScrollViews.count == 1,
                  workNavigationBars.count == 1,
                  workNoteHeading.exists,
                  workTabBar.exists,
                  workHelper.exists,
                  workScrollView.exists,
                  workNavigationBar.exists,
                  workPreview.exists,
                  progress.exists else {
                XCTFail("Record-work saving positioning route changed.")
                return
            }
            let scrollFrame = workScrollView.frame
            let applicationFrame = app.frame
            let navigationFrame = workNavigationBar.frame
            let liveScrollFrame = scrollFrame.intersection(applicationFrame)
            let tabBarFrame = workTabBar.frame
            let liveBottom = min(
                liveScrollFrame.maxY,
                min(applicationFrame.maxY, tabBarFrame.minY)
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
            let noteFrame = workNoteHeading.frame
            let helperFrame = workHelper.frame
            let targetTop = min(noteFrame.minY, helperFrame.minY)
            let targetBottom = max(noteFrame.maxY, helperFrame.maxY)
            guard !applicationFrame.isNull,
                  !applicationFrame.isEmpty,
                  !navigationFrame.isNull,
                  !navigationFrame.isEmpty,
                  !scrollFrame.isNull,
                  !scrollFrame.isEmpty,
                  !liveScrollFrame.isNull,
                  !liveScrollFrame.isEmpty,
                  !tabBarFrame.isNull,
                  !tabBarFrame.isEmpty,
                  !noteFrame.isNull,
                  !noteFrame.isEmpty,
                  !helperFrame.isNull,
                  !helperFrame.isEmpty,
                  safeBottom > safeTop,
                  targetBottom - targetTop <= safeBottom - safeTop else {
                XCTFail("Record-work saving viewport geometry is invalid.")
                return
            }
            if noteFrame.minY >= safeTop,
               noteFrame.maxY <= safeBottom,
               helperFrame.minY >= safeTop,
               helperFrame.maxY <= safeBottom,
               workNoteHeading.isHittable,
               workHelper.isHittable {
                break
            }

            let minimumShift = max(
                safeTop - noteFrame.minY,
                safeTop - helperFrame.minY
            )
            let maximumShift = min(
                safeBottom - noteFrame.maxY,
                safeBottom - helperFrame.maxY
            )
            let receiverCapacity = receiverBottom - receiverTop
            guard minimumShift <= maximumShift,
                  receiverCapacity >= minimumGestureDistance else {
                XCTFail("Record-work saving has no feasible recognized shift.")
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
                guard recognizedMinimum <= recognizedMaximum else {
                    XCTFail("Record-work saving upward shift is not recognizable.")
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
                    receiverCapacity
                )
                guard recognizedMinimum <= recognizedMaximum else {
                    XCTFail("Record-work saving downward shift is not recognizable.")
                    return
                }
                dragDistance = recognizedMinimum
            } else {
                XCTFail("Record-work saving feasible shift is directionless.")
                return
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
            let observedNoteShift = workNoteHeading.frame.minY - noteMinYBeforeDrag
            let observedHelperShift = workHelper.frame.minY - helperMinYBeforeDrag
            guard workNoteHeadings.count == 1,
                  workTabBars.count == 1,
                  workHelperTexts.count == 1,
                  workScrollViews.count == 1,
                  workNavigationBars.count == 1,
                  workNoteHeading.exists,
                  workTabBar.exists,
                  workHelper.exists,
                  progress.exists,
                  observedNoteShift * dragDistance > 0,
                  observedHelperShift * dragDistance > 0 else {
                XCTFail("Record-work saving positioning gesture was not recognized.")
                return
            }
        }
        let savingFinalApplicationFrame = app.frame
        let savingFinalNavigationFrame = workNavigationBar.frame
        let savingFinalScrollFrame = workScrollView.frame.intersection(
            savingFinalApplicationFrame
        )
        let savingFinalSafeTop = max(
            savingFinalScrollFrame.minY,
            savingFinalNavigationFrame.maxY
        ) + verticalInset
        let savingFinalTabBarFrame = workTabBar.frame
        let savingFinalLiveBottom = min(
            savingFinalScrollFrame.maxY,
            min(savingFinalApplicationFrame.maxY, savingFinalTabBarFrame.minY)
        )
        let savingFinalSafeBottom = savingFinalLiveBottom - verticalInset
        let savingFinalNoteFrame = workNoteHeading.frame
        let savingFinalHelperFrame = workHelper.frame
        guard app.state == .runningForeground,
              workNoteHeadings.count == 1,
              workTabBars.count == 1,
              workHelperTexts.count == 1,
              workScrollViews.count == 1,
              workNavigationBars.count == 1,
              workNoteHeading.exists,
              workTabBar.exists,
              workNoteHeading.identifier.isEmpty,
              workNoteHeading.label == "Note",
              workNoteHeading.elementType == .staticText,
              workHelper.exists,
              workScrollView.exists,
              workNavigationBar.exists,
              workPreview.exists,
              progress.exists,
              !savingFinalApplicationFrame.isNull,
              !savingFinalApplicationFrame.isEmpty,
              !savingFinalNavigationFrame.isNull,
              !savingFinalNavigationFrame.isEmpty,
              !savingFinalScrollFrame.isNull,
              !savingFinalScrollFrame.isEmpty,
              !savingFinalTabBarFrame.isNull,
              !savingFinalTabBarFrame.isEmpty,
              !savingFinalNoteFrame.isNull,
              !savingFinalNoteFrame.isEmpty,
              !savingFinalHelperFrame.isNull,
              !savingFinalHelperFrame.isEmpty,
              savingFinalSafeBottom > savingFinalSafeTop,
              savingFinalNoteFrame.minY >= savingFinalSafeTop,
              savingFinalNoteFrame.maxY <= savingFinalSafeBottom,
              savingFinalHelperFrame.minY >= savingFinalSafeTop,
              savingFinalHelperFrame.maxY <= savingFinalSafeBottom,
              workNoteHeading.isHittable,
              workHelper.isHittable,
              workPreview.isHittable else {
            XCTFail("Record-work saving composition is outside the safe viewport.")
            return
        }
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
    ) -> Bool {
        var usedSettingsRetry = false
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

        var store = element("s7.2.paywall.store", in: app)
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
    private func assertMonthlyPaywallAtXXXL(in app: XCUIApplication) throws {
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
        var measuredUndertravel: CGFloat = 0
        var correctionDirection: CGFloat?
        var previousResidualMagnitude: CGFloat?
        for _ in 0..<2 {
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
                XCTFail("Diagnostics positioning interval is impossible.")
                return
            }
            if minimumShift <= 0, maximumShift >= 0 {
                break
            }
            let targetDistance: CGFloat
            if maximumShift < 0 {
                targetDistance = maximumShift
            } else if minimumShift > 0 {
                targetDistance = minimumShift
            } else {
                XCTFail("Diagnostics positioning interval has no signed correction.")
                return
            }
            let direction: CGFloat = targetDistance > 0 ? 1 : -1
            if let correctionDirection {
                guard correctionDirection == direction else {
                    XCTFail("Diagnostics positioning changed correction direction.")
                    return
                }
            } else {
                correctionDirection = direction
            }
            let residualMagnitude = abs(targetDistance)
            if let previousResidualMagnitude {
                guard residualMagnitude < previousResidualMagnitude else {
                    XCTFail("Diagnostics positioning residual did not decrease.")
                    return
                }
            }
            previousResidualMagnitude = residualMagnitude
            let requestedDistance = targetDistance
                + direction * measuredUndertravel
            guard abs(requestedDistance) >= minimumGestureDistance else {
                XCTFail("Diagnostics positioning gesture is not recognizable.")
                return
            }
            let dragStart = diagnosticsScrollView.coordinate(
                withNormalizedOffset: CGVector(dx: 0.01, dy: 0.45)
            )
            let startPoint = dragStart.screenPoint
            let availableDistance = direction < 0
                ? startPoint.y - (diagnosticsScrollView.frame.minY + dragInset)
                : diagnosticsScrollView.frame.maxY - dragInset - startPoint.y
            guard availableDistance >= abs(requestedDistance) else {
                XCTFail("Diagnostics positioning request exceeds receiver capacity.")
                return
            }
            let dragEnd = dragStart.withOffset(
                CGVector(dx: 0, dy: requestedDistance)
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
            guard actualDistance * direction > 0 else {
                XCTFail("Diagnostics positioning gesture was not recognized.")
                return
            }
            measuredUndertravel = max(
                0,
                abs(requestedDistance) - abs(actualDistance)
            )
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
                taskIssueLimit = 3
                taskStateLimit = 2
                permittedExceptionStateIDs = [
                    "state.check-preflight.ready",
                    "state.new-sign.editing",
                ]
            case ("s10.4.current.ax-text", "report_comprehension"):
                taskIssueLimit = 3
                taskStateLimit = 2
                permittedExceptionStateIDs = [
                    "state.report-history.ready",
                    "state.reports-index.ready",
                ]
            case ("s10.4.current.ax-text", "work_and_recheck"):
                taskIssueLimit = 1
                taskStateLimit = 1
                permittedExceptionStateIDs = ["state.work.validation-error"]
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
              field.elementType == .textField,
              !field.identifier.isEmpty,
              expectedRouteExists,
              expectedApplicationState == .runningForeground else {
            XCTFail("The multiline dismissal preconditions are not satisfied.")
            return
        }
        let expectedValue = String(describing: field.value ?? "")
        let fieldScrollViews = app.scrollViews.containing(
            .textField,
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
        fieldScrollView.swipeUp()
        guard keyboard.waitForNonExistence(timeout: 10),
              field.exists,
              String(describing: field.value ?? "") == expectedValue,
              route.exists == expectedRouteExists,
              app.state == expectedApplicationState else {
            XCTFail("Multiline dismissal changed content, route, or foreground state.")
            return
        }
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
        let returnKey = keyboard.buttons["Return"]
        if returnKey.exists && returnKey.isHittable {
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
        guard wait(
            for: keyboard,
            predicate: "exists == false",
            timeout: 10
        ), app.state == .runningForeground else {
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

import Foundation
import UIKit
import XCTest
@testable import FieldEvidenceApp

final class S1PackTokenTests: XCTestCase {
    @MainActor
    func testWorklightTokenNamesAssetsAndMetricsAreExact() throws {
        let expectedColors: [(name: String, light: UInt32, dark: UInt32)] = [
            ("WorklightCanvas", 0xF3F5F6, 0x0B1114),
            ("WorklightSurface", 0xFFFFFF, 0x131B1F),
            ("WorklightRaisedSurface", 0xFFFFFF, 0x1A252A),
            ("WorklightPrimaryText", 0x11181C, 0xF5F7F8),
            ("WorklightSecondaryText", 0x47565D, 0xB7C1C6),
            ("WorklightTertiaryText", 0x617077, 0x8F9DA4),
            ("WorklightInteractionAccent", 0x006D75, 0x57CDD0),
            ("WorklightOnAccent", 0xFFFFFF, 0x071B1D),
            ("WorklightAccentContainer", 0xD8F1F2, 0x173B3E),
            ("WorklightOnAccentContainer", 0x0B4E53, 0x9DEBED),
            ("WorklightEssentialControlStroke", 0x74838A, 0x6B7D85),
            ("WorklightCompleteText", 0x125E39, 0x80E0AE),
            ("WorklightCompleteContainer", 0xE2F3EA, 0x153B2A),
            ("WorklightAttentionText", 0x7A4300, 0xFFD08A),
            ("WorklightAttentionContainer", 0xFFF0D6, 0x402D12),
            ("WorklightBlockedText", 0x8A1C14, 0xFFAEA5),
            ("WorklightBlockedContainer", 0xFDE7E5, 0x441E1C),
            ("WorklightInformationText", 0x164E8C, 0xA4CDFF),
            ("WorklightInformationContainer", 0xE4EFFC, 0x193653),
        ]
        let expectedAssetNames = expectedColors.map { $0.name }

        XCTAssertEqual(WorklightColorAsset.allCases.map(\.rawValue), expectedAssetNames)
        XCTAssertEqual(DesignTokens.Colors.assetNames, expectedAssetNames)

        let light = UITraitCollection(userInterfaceStyle: .light)
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        let increasedLight = UITraitCollection(traitsFrom: [
            light,
            UITraitCollection(accessibilityContrast: .high),
        ])
        let increasedDark = UITraitCollection(traitsFrom: [
            dark,
            UITraitCollection(accessibilityContrast: .high),
        ])

        for expected in expectedColors {
            let color = try XCTUnwrap(
                UIColor(named: expected.name),
                "Missing named Color Set \(expected.name)"
            )
            assert(
                color.resolvedColor(with: light),
                equalsRGB: expected.light,
                name: "\(expected.name) Light"
            )
            assert(
                color.resolvedColor(with: dark),
                equalsRGB: expected.dark,
                name: "\(expected.name) Dark"
            )
            assertOpaqueRGB(
                color.resolvedColor(with: increasedLight),
                name: "\(expected.name) increased-contrast Light"
            )
            assertOpaqueRGB(
                color.resolvedColor(with: increasedDark),
                name: "\(expected.name) increased-contrast Dark"
            )
        }

        let semanticPairs = [
            ("WorklightPrimaryText", "WorklightCanvas"),
            ("WorklightSecondaryText", "WorklightCanvas"),
            ("WorklightOnAccent", "WorklightInteractionAccent"),
            ("WorklightOnAccentContainer", "WorklightAccentContainer"),
            ("WorklightCompleteText", "WorklightCompleteContainer"),
            ("WorklightAttentionText", "WorklightAttentionContainer"),
            ("WorklightBlockedText", "WorklightBlockedContainer"),
            ("WorklightInformationText", "WorklightInformationContainer"),
        ]
        for (foreground, background) in semanticPairs {
            try assertHighContrastNotLower(
                foregroundName: foreground,
                backgroundName: background,
                ordinaryTrait: light,
                highContrastTrait: increasedLight,
                appearanceName: "Light"
            )
            try assertHighContrastNotLower(
                foregroundName: foreground,
                backgroundName: background,
                ordinaryTrait: dark,
                highContrastTrait: increasedDark,
                appearanceName: "Dark"
            )
        }
        try assertHighContrastNotLower(
            foregroundName: "WorklightEssentialControlStroke",
            backgroundName: "WorklightCanvas",
            ordinaryTrait: light,
            highContrastTrait: increasedLight,
            appearanceName: "Light"
        )
        try assertHighContrastNotLower(
            foregroundName: "WorklightEssentialControlStroke",
            backgroundName: "WorklightRaisedSurface",
            ordinaryTrait: dark,
            highContrastTrait: increasedDark,
            appearanceName: "Dark"
        )

        XCTAssertEqual(DesignTokens.Spacing.unit, 8)
        XCTAssertEqual(DesignTokens.Spacing.small, 8)
        XCTAssertEqual(DesignTokens.Spacing.medium, 16)
        XCTAssertEqual(DesignTokens.Spacing.large, 24)
        XCTAssertEqual(DesignTokens.Spacing.extraLarge, 32)
        XCTAssertEqual(DesignTokens.Spacing.cardPadding, 16)
        XCTAssertEqual(DesignTokens.Radius.standard, 12)
        XCTAssertEqual(DesignTokens.Control.minimumHitSize, 44)
        XCTAssertEqual(
            WorklightStatusKind.allCases.map(\.rawValue),
            ["complete", "attention", "blocked", "information"]
        )
    }

    func testIlluminatedSignPackContainsTheCompleteExactContractInOrder() {
        let pack = SignPack.illuminatedSignV1

        XCTAssertEqual(pack.schemaVersion, 1)
        XCTAssertEqual(pack.packID, "field.evidence.illuminated_sign.v1")
        XCTAssertEqual(pack.contentVersion, 1)
        XCTAssertEqual(pack.nouns.asset, .init(singular: "sign", plural: "signs"))
        XCTAssertEqual(pack.nouns.check, .init(singular: "check", plural: "checks"))
        XCTAssertEqual(
            pack.nouns.issue,
            .init(singular: "visible issue", plural: "visible issues")
        )

        XCTAssertEqual(
            pack.evidencePurposes,
            [
                .init(
                    key: "wide_context",
                    display: "Wide view",
                    instruction: "Take one wide photo showing the full sign and its surroundings."
                ),
                .init(
                    key: "close_detail",
                    display: "Close view",
                    instruction: "Take one close photo showing the sign face clearly."
                ),
                .init(
                    key: "work_context",
                    display: "Work photo",
                    instruction: "Add one optional photo showing the work performed."
                ),
            ]
        )
        XCTAssertEqual(
            pack.acknowledgements,
            [
                .init(
                    key: "after_dark",
                    copy: "It is dark enough to observe the sign's visible illumination.",
                    version: "preflight.ack.en-US.v1"
                ),
                .init(
                    key: "safe_authorized_position",
                    copy: "I am in a safe, authorized position to take these photos.",
                    version: "preflight.ack.en-US.v1"
                ),
            ]
        )
        XCTAssertEqual(
            pack.issueLabels,
            [
                .init(key: "dark_section", display: "Section appears dark"),
                .init(key: "dim_or_uneven", display: "Illumination appears dim or uneven"),
                .init(key: "flicker_or_intermittent", display: "Flicker or intermittent light"),
                .init(key: "color_mismatch", display: "Visible color mismatch"),
                .init(key: "physical_damage", display: "Visible physical damage"),
                .init(key: "other_visible_condition", display: "Other visible condition"),
            ]
        )
        XCTAssertEqual(pack.couldNotVerifyReasons.version, "cnv.reason.en-US.v1")
        XCTAssertEqual(
            pack.couldNotVerifyReasons.entries,
            [
                .init(key: "conditions_changed", display: "Conditions changed"),
                .init(key: "access_lost", display: "I lost safe access"),
                .init(key: "unsafe_to_continue", display: "It became unsafe to continue"),
                .init(key: "required_view_obstructed", display: "Required view is blocked"),
                .init(
                    key: "capture_unavailable",
                    display: "Camera or photo capture is unavailable"
                ),
                .init(key: "other", display: "Another reason"),
            ]
        )
        XCTAssertEqual(
            pack.stageDisplays,
            [
                .init(key: "check", display: "Check"),
                .init(key: "recheck", display: "Recheck"),
            ]
        )
        XCTAssertEqual(
            pack.outcomeDisplays,
            [
                .init(key: "no_visible_issue", display: "No visible issue"),
                .init(key: "visible_issue", display: "Visible issue"),
                .init(key: "could_not_verify", display: "Could not verify"),
                .init(key: "resolved", display: "Resolved"),
                .init(key: "issue_still_visible", display: "Issue still visible"),
                .init(
                    key: "original_resolved_different_issue",
                    display: "Original resolved, different visible issue"
                ),
            ]
        )
        XCTAssertEqual(
            pack.disclaimer,
            "This report records visible conditions from the listed photos and time. It is not an electrical, code, safety, or professional certification."
        )
    }

    func testBundledManifestLoadsAsTheOneExactPack() throws {
        let result = SignPackLoader.loadBundled()
        let pack = try XCTUnwrap(result.pack)

        XCTAssertEqual(result, .available(.illuminatedSignV1))
        XCTAssertEqual(pack, .illuminatedSignV1)
    }

    func testLoaderRejectsMissingExtraUnknownVersionAndDriftedContent() throws {
        var invalidCandidates: [Data] = []

        var missingKey = try manifestObject()
        missingKey.removeValue(forKey: "packID")
        invalidCandidates.append(try jsonData(missingKey))

        var extraKey = try manifestObject()
        extraKey["unexpected"] = true
        invalidCandidates.append(try jsonData(extraKey))

        var unknownNestedKey = try manifestObject()
        var unknownAcknowledgements = try XCTUnwrap(
            unknownNestedKey["acknowledgements"] as? [[String: Any]]
        )
        unknownAcknowledgements[0]["unknownCopyKey"] = "must fail"
        unknownNestedKey["acknowledgements"] = unknownAcknowledgements
        invalidCandidates.append(try jsonData(unknownNestedKey))

        var unknownSchema = try manifestObject()
        unknownSchema["schemaVersion"] = 2
        invalidCandidates.append(try jsonData(unknownSchema))

        var driftedPackID = try manifestObject()
        driftedPackID["packID"] = "field.evidence.illuminated_sign.v2"
        invalidCandidates.append(try jsonData(driftedPackID))

        var driftedContentVersion = try manifestObject()
        driftedContentVersion["contentVersion"] = 2
        invalidCandidates.append(try jsonData(driftedContentVersion))

        var driftedCopy = try manifestObject()
        driftedCopy["disclaimer"] = "A softer claim is still a drift."
        invalidCandidates.append(try jsonData(driftedCopy))

        var missingRegistryEntry = try manifestObject()
        var issueLabels = try XCTUnwrap(
            missingRegistryEntry["issueLabels"] as? [[String: Any]]
        )
        issueLabels.removeLast()
        missingRegistryEntry["issueLabels"] = issueLabels
        invalidCandidates.append(try jsonData(missingRegistryEntry))

        var extraRegistryEntry = try manifestObject()
        var reasons = try XCTUnwrap(
            extraRegistryEntry["couldNotVerifyReasons"] as? [String: Any]
        )
        var reasonEntries = try XCTUnwrap(reasons["entries"] as? [[String: Any]])
        reasonEntries.append(["key": "unknown", "display": "Unknown"])
        reasons["entries"] = reasonEntries
        extraRegistryEntry["couldNotVerifyReasons"] = reasons
        invalidCandidates.append(try jsonData(extraRegistryEntry))

        var reorderedContent = try manifestObject()
        var stages = try XCTUnwrap(reorderedContent["stageDisplays"] as? [[String: Any]])
        stages.reverse()
        reorderedContent["stageDisplays"] = stages
        invalidCandidates.append(try jsonData(reorderedContent))

        let encodedPack = try JSONEncoder().encode(SignPack.illuminatedSignV1)
        let encodedString = try XCTUnwrap(String(data: encodedPack, encoding: .utf8))
        let packIDMember = #""packID":"field.evidence.illuminated_sign.v1""#
        let duplicateKnownMember = "\(packIDMember),\(packIDMember)"
        let duplicatedKeyString = encodedString.replacingOccurrences(
            of: packIDMember,
            with: duplicateKnownMember
        )
        XCTAssertNotEqual(duplicatedKeyString, encodedString)
        invalidCandidates.append(Data(duplicatedKeyString.utf8))

        invalidCandidates.append(Data("not json".utf8))

        for (index, candidate) in invalidCandidates.enumerated() {
            XCTAssertEqual(
                SignPackLoader.load(data: candidate),
                .unavailable,
                "Invalid candidate \(index) must fail closed"
            )
        }
    }

    private func manifestObject() throws -> [String: Any] {
        let data = try JSONEncoder().encode(SignPack.illuminatedSignV1)
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
    }

    private func jsonData(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    @MainActor
    private func rgba(
        _ color: UIColor
    ) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        XCTAssertTrue(
            color.getRed(&red, green: &green, blue: &blue, alpha: &alpha),
            "Expected an RGB-compatible Color Set"
        )
        return (red, green, blue, alpha)
    }

    @MainActor
    private func assert(
        _ color: UIColor,
        equalsRGB hex: UInt32,
        name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let actual = rgba(color)
        let scale = CGFloat(255)
        let tolerance = CGFloat(1) / 2_550
        let expectedRed = CGFloat((hex >> 16) & 0xFF) / scale
        let expectedGreen = CGFloat((hex >> 8) & 0xFF) / scale
        let expectedBlue = CGFloat(hex & 0xFF) / scale

        XCTAssertEqual(actual.red, expectedRed, accuracy: tolerance, "\(name) red", file: file, line: line)
        XCTAssertEqual(actual.green, expectedGreen, accuracy: tolerance, "\(name) green", file: file, line: line)
        XCTAssertEqual(actual.blue, expectedBlue, accuracy: tolerance, "\(name) blue", file: file, line: line)
        XCTAssertEqual(actual.alpha, 1, accuracy: tolerance, "\(name) alpha", file: file, line: line)
    }

    @MainActor
    private func assertOpaqueRGB(
        _ color: UIColor,
        name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let components = rgba(color)
        XCTAssertTrue((0...1).contains(components.red), "\(name) red", file: file, line: line)
        XCTAssertTrue((0...1).contains(components.green), "\(name) green", file: file, line: line)
        XCTAssertTrue((0...1).contains(components.blue), "\(name) blue", file: file, line: line)
        XCTAssertEqual(components.alpha, 1, accuracy: 1 / 2_550, "\(name) alpha", file: file, line: line)
    }

    @MainActor
    private func assertHighContrastNotLower(
        foregroundName: String,
        backgroundName: String,
        ordinaryTrait: UITraitCollection,
        highContrastTrait: UITraitCollection,
        appearanceName: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let foreground = try XCTUnwrap(
            UIColor(named: foregroundName),
            "Missing named Color Set \(foregroundName)",
            file: file,
            line: line
        )
        let background = try XCTUnwrap(
            UIColor(named: backgroundName),
            "Missing named Color Set \(backgroundName)",
            file: file,
            line: line
        )
        let ordinaryForeground = foreground.resolvedColor(with: ordinaryTrait)
        let ordinaryBackground = background.resolvedColor(with: ordinaryTrait)
        let highForeground = foreground.resolvedColor(with: highContrastTrait)
        let highBackground = background.resolvedColor(with: highContrastTrait)
        let ordinaryRatio = contrastRatio(
            foreground: ordinaryForeground,
            background: ordinaryBackground
        )
        let highRatio = contrastRatio(
            foreground: highForeground,
            background: highBackground
        )
        let pairName = "\(foregroundName)/\(backgroundName) \(appearanceName)"

        XCTAssertGreaterThanOrEqual(
            highRatio + 0.000_001,
            ordinaryRatio,
            "\(pairName) increased contrast must not lower contrast",
            file: file,
            line: line
        )
        XCTAssertTrue(
            colorsDiffer(ordinaryForeground, highForeground)
                || colorsDiffer(ordinaryBackground, highBackground),
            "\(pairName) must resolve an explicit increased-contrast variant",
            file: file,
            line: line
        )
    }

    @MainActor
    private func contrastRatio(foreground: UIColor, background: UIColor) -> CGFloat {
        let foregroundLuminance = relativeLuminance(foreground)
        let backgroundLuminance = relativeLuminance(background)
        let lighter = max(foregroundLuminance, backgroundLuminance)
        let darker = min(foregroundLuminance, backgroundLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    @MainActor
    private func relativeLuminance(_ color: UIColor) -> CGFloat {
        let components = rgba(color)

        func linearize(_ component: CGFloat) -> CGFloat {
            component <= 0.04045
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }

        return (0.2126 * linearize(components.red))
            + (0.7152 * linearize(components.green))
            + (0.0722 * linearize(components.blue))
    }

    @MainActor
    private func colorsDiffer(_ lhs: UIColor, _ rhs: UIColor) -> Bool {
        let left = rgba(lhs)
        let right = rgba(rhs)
        let tolerance = CGFloat(1) / 2_550
        return abs(left.red - right.red) > tolerance
            || abs(left.green - right.green) > tolerance
            || abs(left.blue - right.blue) > tolerance
            || abs(left.alpha - right.alpha) > tolerance
    }
}

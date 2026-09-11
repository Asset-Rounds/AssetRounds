import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import SwiftUI
import UIKit
import XCTest
@testable import FieldEvidenceApp

final class S10_2BrandComponentTests: XCTestCase {
    private struct RuntimeAsset {
        let source: String
        let destination: String
    }

    private let runtimeAssets = [
        RuntimeAsset(
            source: "AppIcon/AppIcon-Default-1024.png",
            destination: "FieldEvidenceApp/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-Default-1024.png"
        ),
        RuntimeAsset(
            source: "AppIcon/AppIcon-Dark-1024.png",
            destination: "FieldEvidenceApp/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-Dark-1024.png"
        ),
        RuntimeAsset(
            source: "AppIcon/AppIcon-Tinted-1024.png",
            destination: "FieldEvidenceApp/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-Tinted-1024.png"
        ),
        RuntimeAsset(
            source: "AppIcon/Contents.json",
            destination: "FieldEvidenceApp/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json"
        ),
        RuntimeAsset(
            source: "Brand/XcodeImagesets/AssetRoundsBrandSymbol.imageset/AssetRoundsBrandSymbol-1x.png",
            destination: "FieldEvidenceApp/Resources/Assets.xcassets/AssetRoundsBrandSymbol.imageset/AssetRoundsBrandSymbol-1x.png"
        ),
        RuntimeAsset(
            source: "Brand/XcodeImagesets/AssetRoundsBrandSymbol.imageset/AssetRoundsBrandSymbol-2x.png",
            destination: "FieldEvidenceApp/Resources/Assets.xcassets/AssetRoundsBrandSymbol.imageset/AssetRoundsBrandSymbol-2x.png"
        ),
        RuntimeAsset(
            source: "Brand/XcodeImagesets/AssetRoundsBrandSymbol.imageset/AssetRoundsBrandSymbol-3x.png",
            destination: "FieldEvidenceApp/Resources/Assets.xcassets/AssetRoundsBrandSymbol.imageset/AssetRoundsBrandSymbol-3x.png"
        ),
        RuntimeAsset(
            source: "Brand/XcodeImagesets/AssetRoundsBrandSymbol.imageset/Contents.json",
            destination: "FieldEvidenceApp/Resources/Assets.xcassets/AssetRoundsBrandSymbol.imageset/Contents.json"
        ),
        RuntimeAsset(
            source: "Brand/XcodeImagesets/AssetRoundsBrandSymbolTemplate.imageset/AssetRoundsBrandSymbolTemplate-1x.png",
            destination: "FieldEvidenceApp/Resources/Assets.xcassets/AssetRoundsBrandSymbolTemplate.imageset/AssetRoundsBrandSymbolTemplate-1x.png"
        ),
        RuntimeAsset(
            source: "Brand/XcodeImagesets/AssetRoundsBrandSymbolTemplate.imageset/AssetRoundsBrandSymbolTemplate-2x.png",
            destination: "FieldEvidenceApp/Resources/Assets.xcassets/AssetRoundsBrandSymbolTemplate.imageset/AssetRoundsBrandSymbolTemplate-2x.png"
        ),
        RuntimeAsset(
            source: "Brand/XcodeImagesets/AssetRoundsBrandSymbolTemplate.imageset/AssetRoundsBrandSymbolTemplate-3x.png",
            destination: "FieldEvidenceApp/Resources/Assets.xcassets/AssetRoundsBrandSymbolTemplate.imageset/AssetRoundsBrandSymbolTemplate-3x.png"
        ),
        RuntimeAsset(
            source: "Brand/XcodeImagesets/AssetRoundsBrandSymbolTemplate.imageset/Contents.json",
            destination: "FieldEvidenceApp/Resources/Assets.xcassets/AssetRoundsBrandSymbolTemplate.imageset/Contents.json"
        ),
    ]

    func testFrozenPackageAndExactTwelveRuntimeAssetsMatch() throws {
        let activation = try json("docs/design/s10/s10-activation.json")
        let integrity = try object(activation, "package_integrity")
        XCTAssertEqual(
            try data("docs/design/s10/authority/assetrounds-brand-assets-v4.1-20260815.zip")
                .sha256.uppercased(),
            try string(integrity, "zip_sha256")
        )
        XCTAssertEqual(
            try data("docs/design/s10/authority/asset-manifest.json")
                .sha256.uppercased(),
            try string(integrity, "asset_manifest_sha256")
        )

        let manifest = try json("docs/design/s10/authority/asset-manifest.json")
        let manifestRows = try rows(manifest, "files")
        var manifestByPath = [String: [String: Any]]()
        for row in manifestRows {
            let path = try string(row, "path")
            XCTAssertNil(manifestByPath.updateValue(row, forKey: path), path)
        }

        XCTAssertEqual(runtimeAssets.count, 12)
        XCTAssertEqual(Set(runtimeAssets.map(\.source)).count, 12)
        XCTAssertEqual(Set(runtimeAssets.map(\.destination)).count, 12)
        for asset in runtimeAssets {
            let fact = try XCTUnwrap(manifestByPath[asset.source], asset.source)
            let destinationBytes = try data(asset.destination)
            XCTAssertEqual(destinationBytes.count, fact["byte_length"] as? Int, asset.destination)
            XCTAssertEqual(
                destinationBytes.sha256.uppercased(),
                try string(fact, "sha256"),
                asset.destination
            )
        }

        try assertDirectory(
            "FieldEvidenceApp/Resources/Assets.xcassets/AppIcon.appiconset",
            hasExactly: [
                "AppIcon-Default-1024.png", "AppIcon-Dark-1024.png",
                "AppIcon-Tinted-1024.png", "Contents.json",
            ]
        )
        try assertDirectory(
            "FieldEvidenceApp/Resources/Assets.xcassets/AssetRoundsBrandSymbol.imageset",
            hasExactly: [
                "AssetRoundsBrandSymbol-1x.png", "AssetRoundsBrandSymbol-2x.png",
                "AssetRoundsBrandSymbol-3x.png", "Contents.json",
            ]
        )
        try assertDirectory(
            "FieldEvidenceApp/Resources/Assets.xcassets/AssetRoundsBrandSymbolTemplate.imageset",
            hasExactly: [
                "AssetRoundsBrandSymbolTemplate-1x.png",
                "AssetRoundsBrandSymbolTemplate-2x.png",
                "AssetRoundsBrandSymbolTemplate-3x.png", "Contents.json",
            ]
        )
    }

    @MainActor
    func testCatalogMetadataPixelsColorsAndPrimaryIconSettingAreExact() throws {
        let appIcon = try json(runtimeAssets[3].destination)
        let appIconRows = try rows(appIcon, "images")
        XCTAssertEqual(appIconRows.compactMap { $0["filename"] as? String }, [
            "AppIcon-Default-1024.png",
            "AppIcon-Dark-1024.png",
            "AppIcon-Tinted-1024.png",
        ])
        XCTAssertNil(appIconRows[0]["appearances"])
        XCTAssertEqual(try appearanceValue(appIconRows[1], named: "luminosity"), "dark")
        XCTAssertEqual(try appearanceValue(appIconRows[2], named: "luminosity"), "tinted")
        for row in appIconRows {
            XCTAssertEqual(row["idiom"] as? String, "universal")
            XCTAssertEqual(row["platform"] as? String, "ios")
            XCTAssertEqual(row["size"] as? String, "1024x1024")
        }

        try assertImageSet(
            runtimeAssets[7].destination,
            filenames: [
                "AssetRoundsBrandSymbol-1x.png",
                "AssetRoundsBrandSymbol-2x.png",
                "AssetRoundsBrandSymbol-3x.png",
            ],
            intent: "original"
        )
        try assertImageSet(
            runtimeAssets[11].destination,
            filenames: [
                "AssetRoundsBrandSymbolTemplate-1x.png",
                "AssetRoundsBrandSymbolTemplate-2x.png",
                "AssetRoundsBrandSymbolTemplate-3x.png",
            ],
            intent: "template"
        )

        let defaultPixels = try decodedPixels(runtimeAssets[0].destination, width: 1_024, height: 1_024)
        let darkPixels = try decodedPixels(runtimeAssets[1].destination, width: 1_024, height: 1_024)
        let tintedPixels = try decodedPixels(runtimeAssets[2].destination, width: 1_024, height: 1_024)
        XCTAssertTrue(defaultPixels.alpha.allSatisfy { $0 == 255 })
        XCTAssertTrue(darkPixels.alpha.contains(0))
        XCTAssertTrue(darkPixels.alpha.contains(255))
        XCTAssertTrue(tintedPixels.alpha.allSatisfy { $0 == 255 })
        XCTAssertTrue(tintedPixels.rgb.allSatisfy { $0.0 == $0.1 && $0.1 == $0.2 })

        for (index, size) in [256, 512, 768].enumerated() {
            let original = try decodedPixels(runtimeAssets[4 + index].destination, width: size, height: size)
            let template = try decodedPixels(runtimeAssets[8 + index].destination, width: size, height: size)
            XCTAssertTrue(original.alpha.contains(0))
            XCTAssertTrue(original.alpha.contains(255))
            XCTAssertTrue(template.alpha.contains(0))
            XCTAssertTrue(template.alpha.contains(255))
        }
        XCTAssertNotNil(UIImage(named: AssetRoundsBrandImageAsset.originalSymbol.rawValue))
        XCTAssertNotNil(UIImage(named: AssetRoundsBrandImageAsset.templateSymbol.rawValue))

        let expectedColors: [(AssetRoundsBrandColorAsset, UInt32, UInt32)] = [
            (.accentTeal, 0x006D75, 0x2BB8C2),
            (.deepTeal, 0x0B4E53, 0x8ADDE3),
            (.checkpointGreen, 0x147D47, 0x53D78B),
            (.brandCanvas, 0xF3F9F9, 0x061E26),
            (.ink, 0x11181C, 0xF7FAFA),
            (.slate, 0x47565D, 0xB8C5C8),
        ]
        let light = UITraitCollection(userInterfaceStyle: .light)
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        let highLight = UITraitCollection(traitsFrom: [
            light, UITraitCollection(accessibilityContrast: .high),
        ])
        let highDark = UITraitCollection(traitsFrom: [
            dark, UITraitCollection(accessibilityContrast: .high),
        ])
        for (asset, expectedLight, expectedDark) in expectedColors {
            let color = try XCTUnwrap(UIColor(named: asset.rawValue), asset.rawValue)
            XCTAssertEqual(rgb(color, traits: light), expectedLight, asset.rawValue)
            XCTAssertEqual(rgb(color, traits: dark), expectedDark, asset.rawValue)
            XCTAssertNotEqual(rgb(color, traits: highLight), expectedLight, asset.rawValue)
            XCTAssertNotEqual(rgb(color, traits: highDark), expectedDark, asset.rawValue)

            let catalog = try json(
                "FieldEvidenceApp/Resources/Assets.xcassets/\(asset.rawValue).colorset/Contents.json"
            )
            XCTAssertEqual(try rows(catalog, "colors").count, 4, asset.rawValue)
            try assertDirectory(
                "FieldEvidenceApp/Resources/Assets.xcassets/\(asset.rawValue).colorset",
                hasExactly: ["Contents.json"]
            )
        }
        for foreground in AssetRoundsBrandColorAsset.allCases
        where foreground.rawValue != AssetRoundsBrandColorAsset.brandCanvas.rawValue {
            let foregroundColor = try XCTUnwrap(UIColor(named: foreground.rawValue))
            let canvas = try XCTUnwrap(UIColor(named: AssetRoundsBrandColorAsset.brandCanvas.rawValue))
            XCTAssertGreaterThanOrEqual(
                contrast(foregroundColor, canvas, traits: highLight) + 0.000_001,
                contrast(foregroundColor, canvas, traits: light),
                foreground.rawValue
            )
            XCTAssertGreaterThanOrEqual(
                contrast(foregroundColor, canvas, traits: highDark) + 0.000_001,
                contrast(foregroundColor, canvas, traits: dark),
                foreground.rawValue
            )
        }

        let project = try text("FieldEvidenceApp.xcodeproj/project.pbxproj")
        XCTAssertEqual(
            project.components(separatedBy: "ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;").count - 1,
            2
        )
        XCTAssertFalse(project.contains("ASSETCATALOG_COMPILER_APPICON_NAME = \"\";"))
    }

    @MainActor
    func testClosedTokenAndNineComponentSystemRendersAcrossEnvironments() throws {
        let expectedTokenIDs = [
            "color.workBackground", "color.groupedBackground", "color.elevatedSurface",
            "color.primaryText", "color.secondaryText", "color.tertiaryText",
            "color.separator", "color.primaryAction", "color.brandHeading",
            "color.completed", "color.warning", "color.error", "color.unavailable",
            "color.selected", "color.disabled", "type.screenTitle", "type.sectionHeading",
            "type.primaryBody", "type.secondaryBody", "type.fieldLabel",
            "type.supportingCaption", "type.numericOrTimestamp", "space.4", "space.8",
            "space.12", "space.16", "space.20", "space.24", "space.32",
            "radius.compact", "radius.standard", "radius.prominent", "stroke.standard",
            "stroke.selected", "target.minimumInteractive", "environment.darkMode",
            "environment.increaseContrast", "environment.differentiateWithoutColor",
            "environment.reduceMotion", "environment.reduceTransparency",
            "environment.largerText", "environment.voiceOver", "environment.voiceControl",
            "environment.currentPlatform", "environment.minimumPlatform",
        ]
        XCTAssertEqual(DesignTokens.tokenIDs, expectedTokenIDs)
        XCTAssertEqual(Set(DesignTokens.tokenIDs).count, 45)
        XCTAssertEqual(DesignTokens.Spacing.roleIDs, [
            "space.4", "space.8", "space.12", "space.16", "space.20", "space.24", "space.32",
        ])
        XCTAssertEqual(DesignTokens.Radius.roleIDs, [
            "radius.compact", "radius.standard", "radius.prominent",
        ])
        XCTAssertEqual(DesignTokens.Stroke.roleIDs, ["stroke.standard", "stroke.selected"])
        XCTAssertEqual(DesignTokens.Target.minimumInteractive, CGSize(width: 44, height: 44))
        XCTAssertEqual(DesignTokens.Environment.minimumSupportedIOSMajorVersion, 18)
        XCTAssertEqual(AssetRoundsComponentContract.roleIDs, [
            "component.screen-foundation", "component.primary-action",
            "component.secondary-action", "component.destructive-action",
            "component.evidence-card", "component.photo-capture", "component.state-label",
            "component.empty-state", "component.report-brand-header",
        ])
        XCTAssertEqual(AssetRoundsComponentContract.evidenceCardContentOrder, [
            "finding", "photo", "status", "work", "recheck",
        ])
        XCTAssertEqual(AssetRoundsComponentContract.photoCaptureFeedback, [
            "thumbnail", "retake", "delete", "durable state",
        ])
        XCTAssertEqual(AssetRoundsComponentContract.maximumPrimaryActionsPerState, 1)
        XCTAssertTrue(AssetRoundsComponentContract.usesNativeControls)
        XCTAssertTrue(AssetRoundsComponentContract.usesSystemSymbolsForFamiliarActions)
        XCTAssertFalse(AssetRoundsComponentContract.usesColorOnlyStatus)
        XCTAssertFalse(AssetRoundsComponentContract.usesNonessentialAnimation)
        XCTAssertFalse(AssetRoundsComponentContract.usesTranslucentMaterial)
        XCTAssertEqual(AssetRoundsStateKind.allCases.map(\.rawValue), [
            "completed", "warning", "error", "unavailable", "selected",
        ])
        XCTAssertEqual(AssetRoundsBrandSymbolRendering.allCases.map(\.rawValue), [
            "original", "template",
        ])

        let tokenDocument = try json("docs/design/s10/s10-token-coverage.json")
        let componentRows = try rows(tokenDocument, "components")
        XCTAssertEqual(
            try componentRows.map { try string($0, "component_id") },
            AssetRoundsComponentContract.roleIDs
        )
        XCTAssertTrue(componentRows.allSatisfy { ($0["status"] as? String) == "NOT_RUN" })

        let componentSource = try text("FieldEvidenceApp/DesignSystem/WorklightComponents.swift")
        let tokenSource = try text("FieldEvidenceApp/DesignSystem/DesignTokens.swift")
        for forbidden in [".animation(", "withAnimation(", "Material.", ".ultraThinMaterial", ".custom("] {
            XCTAssertFalse(componentSource.contains(forbidden), forbidden)
            XCTAssertFalse(tokenSource.contains(forbidden), forbidden)
        }
        let featureSources = try swiftSources(below: "FieldEvidenceApp/Features")
        let rawColor = try NSRegularExpression(
            pattern: #"#[0-9A-Fa-f]{6,8}|Color\s*\(\s*red:|UIColor\s*\(\s*red:|0x[0-9A-Fa-f]{6,8}"#
        )
        for source in featureSources {
            let value = try text(source)
            let range = NSRange(value.startIndex..<value.endIndex, in: value)
            XCTAssertEqual(rawColor.numberOfMatches(in: value, range: range), 0, source)
        }

        let actions: [AnyView] = [
            AnyView(AssetRoundsPrimaryAction("Primary") {}),
            AnyView(AssetRoundsSecondaryAction("Secondary") {}),
            AnyView(AssetRoundsDestructiveAction("Delete") {}),
            AnyView(AssetRoundsPhotoCapture(captureTitle: "Take photo", onCapture: {})),
        ]
        for action in actions {
            let size = measuredSize(action, width: 320)
            XCTAssertGreaterThanOrEqual(size.width, 44)
            XCTAssertGreaterThanOrEqual(size.height, 44)
        }

        let fixture = BrandComponentFixture()
        let variants: [AnyView] = [
            AnyView(fixture.preferredColorScheme(.light)),
            AnyView(fixture.preferredColorScheme(.dark)),
            AnyView(fixture.dynamicTypeSize(.accessibility5)),
        ]
        for variant in variants {
            let size = measuredSize(variant, width: 390, height: 4_000)
            XCTAssertEqual(size.width, 390, accuracy: 0.001)
            XCTAssertGreaterThan(size.height, 400)
            XCTAssertLessThanOrEqual(size.height, 4_000)
        }
    }

    func testExactSelectorEnvelopeAndApprovedBaselinesRemainFrozen() throws {
        let selector = #"{"schemaVersion":1,"taskID":"S10.2","tier":"P12","runUISmoke":true,"setupArtifactTimeoutSeconds":300,"buildTimeoutSeconds":600,"testTimeoutSeconds":900,"uiTimeoutSeconds":900,"totalBudgetSeconds":3300,"unitTestSelectors":["FieldEvidenceAppTests/S10_2BrandComponentTests"],"uiTestSelectors":["FieldEvidenceAppUITests/S10_2BrandComponentUITests"]}"# + "\n"
        XCTAssertEqual(try data("Scripts/ci-selection.json"), Data(selector.utf8))

        let activation = try json("docs/design/s10/s10-activation.json")
        let cards = try rows(activation, "cards")
        let card = try XCTUnwrap(cards.first { ($0["card_id"] as? String) == "S10.2" })
        XCTAssertEqual(card["product_file_cap"] as? Int, 21)
        XCTAssertEqual(card["test_file_cap"] as? Int, 2)
        XCTAssertEqual(try strings(card, "allowed_paths"), runtimeAssets.map(\.destination) + [
            "FieldEvidenceApp/Resources/Assets.xcassets/AssetRoundsAccentTeal.colorset/Contents.json",
            "FieldEvidenceApp/Resources/Assets.xcassets/AssetRoundsDeepTeal.colorset/Contents.json",
            "FieldEvidenceApp/Resources/Assets.xcassets/AssetRoundsCheckpointGreen.colorset/Contents.json",
            "FieldEvidenceApp/Resources/Assets.xcassets/AssetRoundsBrandCanvas.colorset/Contents.json",
            "FieldEvidenceApp/Resources/Assets.xcassets/AssetRoundsInk.colorset/Contents.json",
            "FieldEvidenceApp/Resources/Assets.xcassets/AssetRoundsSlate.colorset/Contents.json",
            "FieldEvidenceApp/DesignSystem/DesignTokens.swift",
            "FieldEvidenceApp/DesignSystem/WorklightComponents.swift",
            "FieldEvidenceApp.xcodeproj/project.pbxproj",
            "FieldEvidenceAppTests/S10_2BrandComponentTests.swift",
            "FieldEvidenceAppUITests/S10_2BrandComponentUITests.swift",
        ])

        let visual = try json("docs/design/s10/s10-visual-regression.json")
        let baselines = try rows(visual, "baselines")
        XCTAssertEqual(baselines.count, 67)
        for baseline in baselines {
            XCTAssertEqual(baseline["baseline_product_head"] as? String, "44e9f9471f8ced9ecdd85f241a79c3750c38412d")
            XCTAssertEqual(baseline["baseline_review_status"] as? String, "APPROVED")
            XCTAssertEqual(baseline["baseline_reviewer"] as? String, "palatis3")
            XCTAssertFalse(try string(baseline, "baseline_sha256").isEmpty)
            XCTAssertEqual(baseline["candidate_product_head"] as? String, "")
            XCTAssertEqual(baseline["candidate_screenshot_path"] as? String, "")
            XCTAssertEqual(baseline["candidate_sha256"] as? String, "")
            XCTAssertEqual(baseline["result"] as? String, "NOT_RUN")
        }
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func data(_ relativePath: String) throws -> Data {
        try Data(contentsOf: repositoryRoot.appendingPathComponent(relativePath))
    }

    private func text(_ relativePath: String) throws -> String {
        String(decoding: try data(relativePath), as: UTF8.self)
    }

    private func json(_ relativePath: String) throws -> [String: Any] {
        let value = try JSONSerialization.jsonObject(with: data(relativePath))
        return try XCTUnwrap(value as? [String: Any], relativePath)
    }

    private func object(_ value: [String: Any], _ key: String) throws -> [String: Any] {
        try XCTUnwrap(value[key] as? [String: Any], key)
    }

    private func rows(_ value: [String: Any], _ key: String) throws -> [[String: Any]] {
        try XCTUnwrap(value[key] as? [[String: Any]], key)
    }

    private func string(_ value: [String: Any], _ key: String) throws -> String {
        try XCTUnwrap(value[key] as? String, key)
    }

    private func strings(_ value: [String: Any], _ key: String) throws -> [String] {
        try XCTUnwrap(value[key] as? [String], key)
    }

    private func assertDirectory(
        _ relativePath: String,
        hasExactly expectedNames: Set<String>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let names = try FileManager.default.contentsOfDirectory(
            atPath: repositoryRoot.appendingPathComponent(relativePath).path
        )
        XCTAssertEqual(Set(names), expectedNames, relativePath, file: file, line: line)
    }

    private func appearanceValue(
        _ row: [String: Any],
        named name: String
    ) throws -> String {
        let appearances = try XCTUnwrap(row["appearances"] as? [[String: Any]])
        let appearance = try XCTUnwrap(appearances.first { ($0["appearance"] as? String) == name })
        return try string(appearance, "value")
    }

    private func assertImageSet(
        _ relativePath: String,
        filenames: [String],
        intent: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let catalog = try json(relativePath)
        let images = try rows(catalog, "images")
        XCTAssertEqual(images.compactMap { $0["filename"] as? String }, filenames, file: file, line: line)
        XCTAssertEqual(images.compactMap { $0["scale"] as? String }, ["1x", "2x", "3x"], file: file, line: line)
        XCTAssertTrue(images.allSatisfy { ($0["idiom"] as? String) == "universal" }, file: file, line: line)
        let properties = try object(catalog, "properties")
        XCTAssertEqual(properties["template-rendering-intent"] as? String, intent, file: file, line: line)
    }

    private func decodedPixels(
        _ relativePath: String,
        width: Int,
        height: Int
    ) throws -> (rgb: [(UInt8, UInt8, UInt8)], alpha: [UInt8]) {
        let url = repositoryRoot.appendingPathComponent(relativePath)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil), relativePath)
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil), relativePath)
        XCTAssertEqual(image.width, width, relativePath)
        XCTAssertEqual(image.height, height, relativePath)

        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drew = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                    | CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        XCTAssertTrue(drew, relativePath)
        var rgb = [(UInt8, UInt8, UInt8)]()
        var alpha = [UInt8]()
        rgb.reserveCapacity(width * height)
        alpha.reserveCapacity(width * height)
        for index in stride(from: 0, to: bytes.count, by: 4) {
            rgb.append((bytes[index], bytes[index + 1], bytes[index + 2]))
            alpha.append(bytes[index + 3])
        }
        return (rgb, alpha)
    }

    private func rgb(_ color: UIColor, traits: UITraitCollection) -> UInt32 {
        let resolved = color.resolvedColor(with: traits)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        XCTAssertTrue(resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        XCTAssertEqual(alpha, 1, accuracy: 0.000_001)
        return UInt32((red * 255).rounded()) << 16
            | UInt32((green * 255).rounded()) << 8
            | UInt32((blue * 255).rounded())
    }

    private func contrast(
        _ foreground: UIColor,
        _ background: UIColor,
        traits: UITraitCollection
    ) -> Double {
        let foregroundLuminance = luminance(rgb(foreground, traits: traits))
        let backgroundLuminance = luminance(rgb(background, traits: traits))
        let lighter = max(foregroundLuminance, backgroundLuminance)
        let darker = min(foregroundLuminance, backgroundLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func luminance(_ rgb: UInt32) -> Double {
        let channels = [16, 8, 0].map { shift -> Double in
            let value = Double((rgb >> UInt32(shift)) & 0xFF) / 255
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
    }

    private func swiftSources(below relativePath: String) throws -> [String] {
        let root = repositoryRoot.appendingPathComponent(relativePath)
        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        )
        var paths = [String]()
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            paths.append(String(url.path.dropFirst(repositoryRoot.path.count + 1)))
        }
        return paths.sorted()
    }

    @MainActor
    private func measuredSize(
        _ view: AnyView,
        width: CGFloat,
        height: CGFloat = 1_000
    ) -> CGSize {
        let controller = UIHostingController(rootView: view)
        controller.loadViewIfNeeded()
        return controller.sizeThatFits(in: CGSize(width: width, height: height))
    }
}

private struct BrandComponentFixture: View {
    var body: some View {
        ScrollView {
            AssetRoundsScreenFoundation(title: Text("AssetRounds components")) {
                AssetRoundsEvidenceCard {
                    Text("Finding")
                    AssetRoundsStateLabel(kind: .completed, "Evidence saved")
                }
                AssetRoundsPhotoCapture(captureTitle: "Take photo", onCapture: {})
                AssetRoundsPrimaryAction("Primary action") {}
                AssetRoundsSecondaryAction("Secondary action") {}
                AssetRoundsDestructiveAction("Delete") {}
                ForEach(
                    Array(AssetRoundsStateKind.allCases.enumerated()),
                    id: \.offset
                ) { item in
                    AssetRoundsStateLabel(
                        kind: item.element,
                        text: Text(item.element.rawValue)
                    )
                }
                AssetRoundsEmptyState(
                    title: Text("No inspections yet"),
                    message: Text("Start when you are ready."),
                    showsBrandSymbol: true,
                    actionLabel: Text("Start"),
                    action: {}
                )
                AssetRoundsReportBrandHeader(
                    title: Text("AssetRounds"),
                    subtitle: Text("Field Inspections"),
                    symbolRendering: .original
                )
            }
        }
        .frame(width: 390)
    }
}

private extension Data {
    var sha256: String {
        SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined()
    }
}

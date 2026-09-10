import Foundation
import XCTest
@testable import FieldEvidenceApp

#if canImport(UIKit)
import CoreText
import SwiftUI
import UIKit
#endif

final class V30P02C04AdaptiveAccessibilityTests: XCTestCase {
    func testExpansionFixturePreservesDeclaredShippingAndDiagnosticSourceBytes() throws {
        let fixture = try expansionFixture()
        XCTAssertEqual(fixture.schemaVersion, 1)
        XCTAssertEqual(fixture.hostWidthPoints, 320)
        XCTAssertEqual(fixture.minimumHitTargetPoints, 44)
        XCTAssertEqual(fixture.dynamicTypeSizes, ["large", "accessibility5"])
        XCTAssertEqual(
            fixture.provenance.translations,
            "Generated accessibility fixture text only; not a shipping localization catalog."
        )
        XCTAssertEqual(
            fixture.provenance.rtlDiagnostic,
            "Generated ar-XB diagnostic case only; it is not a shipping language claim."
        )
        XCTAssertEqual(
            fixture.provenance.professionalOrNativeFontQualification,
            "Not claimed; native font execution is pending."
        )
        XCTAssertEqual(
            fixture.provenance.fontLicensing,
            "No custom font or font licensing claim is made."
        )
        XCTAssertEqual(
            fixture.shippingCases.map(\.languageTag),
            ["en", "es", "zh-Hans", "zh-Hant", "vi", "ko"]
        )

        for item in fixture.shippingCases + [fixture.rtlDiagnostic] {
            let source = item.canonicalSource
            XCTAssertEqual(KernelCanonicalHashV1.sha256(Data(source.utf8)), item.utf8SHA256, item.id)
            XCTAssertEqual(source.utf8.count, item.utf8ByteCount, item.id)
            XCTAssertFalse(item.primaryAction.isEmpty, item.id)
            XCTAssertFalse(item.secondaryAction.isEmpty, item.id)
            XCTAssertFalse(item.statusText.isEmpty, item.id)
            XCTAssertFalse(item.longError.isEmpty, item.id)
        }

        XCTAssertEqual(fixture.rtlDiagnostic.languageTag, "ar-XB")
        XCTAssertFalse(AppLanguageTagV1.supportedRawValues.contains(fixture.rtlDiagnostic.languageTag))
        XCTAssertEqual(
            KernelCanonicalHashV1.sha256(Data(fixture.combiningEmoji.source.utf8)),
            fixture.combiningEmoji.utf8SHA256
        )
        XCTAssertEqual(fixture.combiningEmoji.source.utf8.count, fixture.combiningEmoji.utf8ByteCount)
        XCTAssertNotEqual(
            Array(fixture.combiningEmoji.source.utf8),
            Array(fixture.combiningEmoji.source.precomposedStringWithCanonicalMapping.utf8)
        )
        XCTAssertTrue(fixture.combiningEmoji.source.contains("\u{200D}"))
    }

    #if canImport(UIKit)
    @MainActor
    func testSharedWorklightControlsWrapAndRetain44PointReachabilityAtAccessibilityFive() throws {
        let fixture = try expansionFixture()
        let cases = fixture.shippingCases + [fixture.rtlDiagnostic]
        for item in cases {
            let direction: LayoutDirection = item.id == fixture.rtlDiagnostic.id
                ? .rightToLeft : .leftToRight
            let layout = try hostedWorklightLayout(
                item: item,
                direction: direction,
                dynamicTypeSize: .accessibility5,
                width: CGFloat(fixture.hostWidthPoints)
            )
            XCTAssertLessThanOrEqual(layout.card.maxX, CGFloat(fixture.hostWidthPoints) + 0.5, item.id)
            for frame in [
                layout.error,
                layout.primary,
                layout.primaryLabel,
                layout.secondary,
                layout.secondaryLabel,
                layout.status,
            ] {
                XCTAssertGreaterThanOrEqual(frame.minX, -0.5, item.id)
                XCTAssertLessThanOrEqual(frame.maxX, CGFloat(fixture.hostWidthPoints) + 0.5, item.id)
            }
            XCTAssertGreaterThan(layout.error.height, 44, item.id)
            XCTAssertGreaterThanOrEqual(layout.primary.height, CGFloat(fixture.minimumHitTargetPoints), item.id)
            XCTAssertGreaterThanOrEqual(layout.secondary.height, CGFloat(fixture.minimumHitTargetPoints), item.id)
            XCTAssertGreaterThanOrEqual(layout.status.height, CGFloat(fixture.minimumHitTargetPoints), item.id)
            XCTAssertGreaterThan(layout.primary.height, 0, item.id)
            XCTAssertGreaterThan(layout.secondary.height, 0, item.id)
            XCTAssertGreaterThan(layout.status.height, 0, item.id)
        }
    }

    @MainActor
    func testVietnameseWorklightButtonLabelsOverrideInheritedLineLimitAtAccessibilityFive() throws {
        let fixture = try expansionFixture()
        let item = try fixture.shippingCase(languageTag: "vi")
        let accessibilityFive = try hostedWorklightLayout(
            item: item,
            direction: .leftToRight,
            dynamicTypeSize: .accessibility5,
            width: CGFloat(fixture.hostWidthPoints),
            inheritedLineLimit: true
        )

        let accessibilityTraits = UITraitCollection(
            preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge
        )
        let singleLineHeadlineHeight = UIFont.preferredFont(
            forTextStyle: .headline,
            compatibleWith: accessibilityTraits
        ).lineHeight
        XCTAssertGreaterThan(accessibilityFive.primaryLabel.height, singleLineHeadlineHeight + 0.5)
        XCTAssertGreaterThan(accessibilityFive.secondaryLabel.height, singleLineHeadlineHeight + 0.5)
        XCTAssertGreaterThan(accessibilityFive.status.height, 44)
    }

    @MainActor
    func testScrollableWorklightControlsReachFinalSecondaryAtAccessibilityFive() throws {
        let fixture = try expansionFixture()
        let item = try fixture.shippingCase(languageTag: "vi")
        let layout = try hostedScrollableWorklightLayout(
            item: item,
            direction: .leftToRight,
            dynamicTypeSize: .accessibility5,
            width: CGFloat(fixture.hostWidthPoints),
            height: 568
        )

        XCTAssertGreaterThan(layout.content.height, layout.viewport.height)
        XCTAssertGreaterThanOrEqual(layout.finalSecondary.height, CGFloat(fixture.minimumHitTargetPoints))
        XCTAssertGreaterThanOrEqual(layout.finalSecondary.minY, layout.viewport.minY)
        XCTAssertLessThanOrEqual(layout.finalSecondary.maxY, layout.viewport.maxY)
    }

    @MainActor
    func testSharedWorklightControlsLayOutNFDAndZWJTextAtAccessibilityFive() throws {
        let fixture = try expansionFixture()
        let base = fixture.rtlDiagnostic
        let emojiCase = AdaptiveAccessibilityFixtureV1.Case(
            id: "combining-emoji-hosting",
            languageTag: base.languageTag,
            primaryAction: base.primaryAction,
            secondaryAction: base.secondaryAction,
            statusText: base.statusText,
            longError: base.longError + " " + fixture.combiningEmoji.source,
            utf8SHA256: base.utf8SHA256,
            utf8ByteCount: base.utf8ByteCount
        )
        let layout = try hostedWorklightLayout(
            item: emojiCase,
            direction: .rightToLeft,
            dynamicTypeSize: .accessibility5,
            width: CGFloat(fixture.hostWidthPoints)
        )

        XCTAssertGreaterThan(layout.error.height, 44)
        XCTAssertGreaterThanOrEqual(layout.primary.height, CGFloat(fixture.minimumHitTargetPoints))
        XCTAssertGreaterThanOrEqual(layout.secondary.height, CGFloat(fixture.minimumHitTargetPoints))
        XCTAssertGreaterThanOrEqual(layout.status.height, CGFloat(fixture.minimumHitTargetPoints))
    }

    @MainActor
    func testSystemDynamicTypeFontsResolveWholeFixtureStringsWithoutLastResortRuns() throws {
        let fixture = try expansionFixture()
        let texts = (fixture.shippingCases + [fixture.rtlDiagnostic]).flatMap { item in
            [item.primaryAction, item.secondaryAction, item.statusText, item.longError]
        } + [fixture.combiningEmoji.source]
        let systemFonts = [
            UIFont.preferredFont(
                forTextStyle: .headline,
                compatibleWith: UITraitCollection(
                    preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge
                )
            ),
            UIFont.preferredFont(
                forTextStyle: .subheadline,
                compatibleWith: UITraitCollection(
                    preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge
                )
            ),
        ]

        for source in texts {
            for font in systemFonts {
                let base = CTFontCreateWithName(font.fontName as CFString, font.pointSize, nil)
                let line = CTLineCreateWithAttributedString(
                    NSAttributedString(
                        string: source,
                        attributes: [NSAttributedString.Key(kCTFontAttributeName as String): base]
                    )
                )
                let runs = try XCTUnwrap(CTLineGetGlyphRuns(line) as? [CTRun], source)
                XCTAssertFalse(runs.isEmpty, source)

                for run in runs {
                    let stringRange = CTRunGetStringRange(run)
                    XCTAssertGreaterThanOrEqual(stringRange.length, 0, source)
                    XCTAssertGreaterThanOrEqual(stringRange.location, 0, source)
                    XCTAssertLessThanOrEqual(
                        stringRange.location + stringRange.length,
                        source.utf16.count,
                        source
                    )

                    let attributes = CTRunGetAttributes(run) as NSDictionary
                    let runFont = try XCTUnwrap(
                        attributes[kCTFontAttributeName] as? CTFont,
                        "Core Text run did not resolve a font for \(source)"
                    )
                    XCTAssertFalse(
                        (CTFontCopyPostScriptName(runFont) as String).lowercased().contains("lastresort"),
                        source
                    )

                    let glyphCount = CTRunGetGlyphCount(run)
                    if glyphCount == 0 {
                        let sourceRange = NSRange(
                            location: stringRange.location,
                            length: stringRange.length
                        )
                        let runSource = (source as NSString).substring(with: sourceRange)
                        XCTAssertTrue(
                            runSource.unicodeScalars.allSatisfy {
                                isDefaultIgnorable($0)
                                    || CharacterSet.whitespacesAndNewlines.contains($0)
                            },
                            "Unexpected zero-glyph run for \(source)"
                        )
                        continue
                    }
                    var glyphs = [CGGlyph](repeating: 0, count: glyphCount)
                    var stringIndices = [CFIndex](repeating: kCFNotFound, count: glyphCount)
                    CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
                    CTRunGetStringIndices(run, CFRange(location: 0, length: 0), &stringIndices)

                    for (glyph, stringIndex) in zip(glyphs, stringIndices) where glyph == 0 {
                        let scalar = try XCTUnwrap(source.scalar(atUTF16Offset: Int(stringIndex)), source)
                        XCTAssertTrue(
                            isDefaultIgnorable(scalar)
                                || CharacterSet.whitespacesAndNewlines.contains(scalar),
                            "Unexpected zero glyph for \(itemDescription(scalar)) in \(source)"
                        )
                    }
                }
            }
        }
    }
    #endif

    private func expansionFixture() throws -> AdaptiveAccessibilityFixtureV1 {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/V30/Accessibility/expansion-and-type-cases-v1.json")
        return try JSONDecoder().decode(
            AdaptiveAccessibilityFixtureV1.self,
            from: Data(contentsOf: url)
        )
    }

    #if canImport(UIKit)
    private func isDefaultIgnorable(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.generalCategory == .format
            || (0xFE00...0xFE0F).contains(scalar.value)
            || (0xE0100...0xE01EF).contains(scalar.value)
    }

    private func itemDescription(_ scalar: Unicode.Scalar) -> String {
        String(format: "U+%04X", scalar.value)
    }
    #endif

    #if canImport(UIKit)
    @MainActor
    private func hostedWorklightLayout(
        item: AdaptiveAccessibilityFixtureV1.Case,
        direction: LayoutDirection,
        dynamicTypeSize: DynamicTypeSize,
        width: CGFloat,
        inheritedLineLimit: Bool = false
    ) throws -> HostedWorklightLayoutV1 {
        var frames: [String: CGRect] = [:]
        let host = UIHostingController(
            rootView: AdaptiveWorklightProbeV1(
                item: item,
                direction: direction,
                dynamicTypeSize: dynamicTypeSize,
                inheritedLineLimit: inheritedLineLimit,
                recordFrames: { frames = $0 }
            )
        )
        host.view.frame = CGRect(x: 0, y: 0, width: width, height: 4_096)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        host.view.layoutIfNeeded()

        return HostedWorklightLayoutV1(
            card: try XCTUnwrap(frames["card"], "card frame missing"),
            error: try XCTUnwrap(frames["error"], "error frame missing"),
            primary: try XCTUnwrap(frames["primary"], "primary frame missing"),
            primaryLabel: try XCTUnwrap(frames["primaryLabel"], "primary label frame missing"),
            secondary: try XCTUnwrap(frames["secondary"], "secondary frame missing"),
            secondaryLabel: try XCTUnwrap(frames["secondaryLabel"], "secondary label frame missing"),
            status: try XCTUnwrap(frames["status"], "status frame missing")
        )
    }

    @MainActor
    private func hostedScrollableWorklightLayout(
        item: AdaptiveAccessibilityFixtureV1.Case,
        direction: LayoutDirection,
        dynamicTypeSize: DynamicTypeSize,
        width: CGFloat,
        height: CGFloat
    ) throws -> HostedScrollableWorklightLayoutV1 {
        var frames: [String: CGRect] = [:]
        let host = UIHostingController(
            rootView: AdaptiveScrollableWorklightProbeV1(
                item: item,
                direction: direction,
                dynamicTypeSize: dynamicTypeSize,
                recordFrames: { frames = $0 }
            )
        )
        host.view.frame = CGRect(x: 0, y: 0, width: width, height: height)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        let deadline = Date().addingTimeInterval(1)
        while Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            host.view.layoutIfNeeded()
            if let viewport = frames["viewport"],
               let finalSecondary = frames["finalSecondary"],
               finalSecondary.minY >= viewport.minY,
               finalSecondary.maxY <= viewport.maxY {
                break
            }
        }

        return HostedScrollableWorklightLayoutV1(
            viewport: try XCTUnwrap(frames["viewport"], "viewport frame missing"),
            content: try XCTUnwrap(frames["content"], "content frame missing"),
            finalSecondary: try XCTUnwrap(frames["finalSecondary"], "final secondary frame missing")
        )
    }
    #endif
}

private struct AdaptiveAccessibilityFixtureV1: Decodable {
    let schemaVersion: Int
    let shippingCases: [Case]
    let rtlDiagnostic: Case
    let combiningEmoji: CombiningEmoji
    let dynamicTypeSizes: [String]
    let hostWidthPoints: Int
    let minimumHitTargetPoints: Int
    let provenance: Provenance

    struct Case: Decodable {
        let id: String
        let languageTag: String
        let primaryAction: String
        let secondaryAction: String
        let statusText: String
        let longError: String
        let utf8SHA256: String
        let utf8ByteCount: Int

        var canonicalSource: String {
            [languageTag, primaryAction, secondaryAction, statusText, longError]
                .joined(separator: "\n")
        }

    }

    struct CombiningEmoji: Decodable {
        let source: String
        let utf8SHA256: String
        let utf8ByteCount: Int
    }

    struct Provenance: Decodable {
        let translations: String
        let rtlDiagnostic: String
        let professionalOrNativeFontQualification: String
        let fontLicensing: String
    }

    func shippingCase(languageTag: String) throws -> Case {
        try XCTUnwrap(shippingCases.first { $0.languageTag == languageTag })
    }
}

#if canImport(UIKit)
private struct HostedWorklightLayoutV1 {
    let card: CGRect
    let error: CGRect
    let primary: CGRect
    let primaryLabel: CGRect
    let secondary: CGRect
    let secondaryLabel: CGRect
    let status: CGRect
}

private struct HostedScrollableWorklightLayoutV1 {
    let viewport: CGRect
    let content: CGRect
    let finalSecondary: CGRect
}

private struct AdaptiveWorklightFramePreferenceKeyV1: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private struct AdaptiveWorklightFrameReaderV1: View {
    let name: String

    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: AdaptiveWorklightFramePreferenceKeyV1.self,
                value: [name: proxy.frame(in: .global)]
            )
        }
    }
}

private struct AdaptiveWorklightProbeV1: View {
    let item: AdaptiveAccessibilityFixtureV1.Case
    let direction: LayoutDirection
    let dynamicTypeSize: DynamicTypeSize
    let inheritedLineLimit: Bool
    let recordFrames: ([String: CGRect]) -> Void

    var body: some View {
        WorklightCard {
            Text(item.longError)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .background(AdaptiveWorklightFrameReaderV1(name: "error"))

            Button(action: {}) {
                Text(item.primaryAction)
                    .background(AdaptiveWorklightFrameReaderV1(name: "primaryLabel"))
            }
                .buttonStyle(WorklightPrimaryButtonStyle())
                .background(AdaptiveWorklightFrameReaderV1(name: "primary"))

            Button(action: {}) {
                Text(item.secondaryAction)
                    .background(AdaptiveWorklightFrameReaderV1(name: "secondaryLabel"))
            }
                .buttonStyle(WorklightSecondaryButtonStyle())
                .background(AdaptiveWorklightFrameReaderV1(name: "secondary"))

            WorklightStatusBadge(kind: .blocked, text: item.statusText)
                .background(AdaptiveWorklightFrameReaderV1(name: "status"))
        }
        .lineLimit(inheritedLineLimit ? 1 : nil)
        .background(AdaptiveWorklightFrameReaderV1(name: "card"))
        .frame(width: 320)
        .environment(\.layoutDirection, direction)
        .environment(\.dynamicTypeSize, dynamicTypeSize)
        .onPreferenceChange(AdaptiveWorklightFramePreferenceKeyV1.self, perform: recordFrames)
    }
}

private struct AdaptiveScrollableWorklightProbeV1: View {
    let item: AdaptiveAccessibilityFixtureV1.Case
    let direction: LayoutDirection
    let dynamicTypeSize: DynamicTypeSize
    let recordFrames: ([String: CGRect]) -> Void

    @State private var scrolledToFinalSecondary = false

    var body: some View {
        GeometryReader { _ in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(String(repeating: item.longError + " ", count: 10))
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)

                        WorklightCard {
                            Text(item.longError)
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)

                            WorklightStatusBadge(kind: .blocked, text: item.statusText)

                            Button(item.primaryAction) {}
                                .buttonStyle(WorklightPrimaryButtonStyle())

                            Button(item.secondaryAction) {}
                                .buttonStyle(WorklightSecondaryButtonStyle())
                                .id("final-secondary")
                                .background(AdaptiveWorklightFrameReaderV1(name: "finalSecondary"))
                        }
                    }
                    .frame(width: 320, alignment: .leading)
                    .background(AdaptiveWorklightFrameReaderV1(name: "content"))
                }
                .background(AdaptiveWorklightFrameReaderV1(name: "viewport"))
                .onAppear {
                    guard !scrolledToFinalSecondary else { return }
                    scrolledToFinalSecondary = true
                    DispatchQueue.main.async {
                        proxy.scrollTo("final-secondary", anchor: .bottom)
                    }
                }
            }
        }
        .environment(\.layoutDirection, direction)
        .environment(\.dynamicTypeSize, dynamicTypeSize)
        .onPreferenceChange(AdaptiveWorklightFramePreferenceKeyV1.self, perform: recordFrames)
    }
}

private extension String {
    func scalar(atUTF16Offset offset: Int) -> Unicode.Scalar? {
        guard offset >= 0, offset < utf16.count else { return nil }
        var currentOffset = 0
        for scalar in unicodeScalars {
            let length = String(scalar).utf16.count
            if (currentOffset..<(currentOffset + length)).contains(offset) {
                return scalar
            }
            currentOffset += length
        }
        return nil
    }
}
#endif

import Foundation
import ImageIO
import SwiftData
import UniformTypeIdentifiers
import XCTest
@testable import FieldEvidenceApp
#if canImport(UIKit)
import SwiftUI
import UIKit
#endif
#if canImport(CoreGraphics)
import CoreGraphics
#endif

final class V30P02C03RTLSemanticsTests: XCTestCase {
    func testHostileFixtureHasExactSourceBytesAndDisplayOnlyIsolation() throws {
        let fixture = try rtlFixture()
        XCTAssertEqual(fixture.schemaVersion, 1)
        XCTAssertEqual(fixture.cases.map(\.id), [
            "mixed-arabic-identifiers",
            "all-bidi-controls",
            "c0-c1-controls",
            "paragraph-separators",
            "zwj-emoji",
            "nfd-accent",
        ])

        for item in fixture.cases {
            XCTAssertEqual(
                KernelCanonicalHashV1.sha256(Data(item.source.utf8)),
                item.utf8SHA256,
                item.id
            )
            XCTAssertEqual(item.source.utf8.count, item.utf8ByteCount, item.id)
            assertUTF8Equal(
                BidirectionalTextSafetyV1.visibleControls(item.source),
                item.visibleControls,
                item.id
            )
            assertUTF8Equal(
                BidirectionalTextSafetyV1.naturalText(item.source),
                item.naturalText,
                item.id
            )
            assertUTF8Equal(
                BidirectionalTextSafetyV1.opaqueToken(item.source),
                item.opaqueToken,
                item.id
            )
            assertBalancedIsolates(
                BidirectionalTextSafetyV1.naturalText(item.source),
                opener: 0x2068,
                item.id
            )
            assertBalancedIsolates(
                BidirectionalTextSafetyV1.opaqueToken(item.source),
                opener: 0x2066,
                item.id
            )
        }
    }

    func testBidiControlsBecomePrintableASCIIAndCannotBreakOuterIsolates() throws {
        let item = try rtlFixture().case(named: "all-bidi-controls")
        let visible = BidirectionalTextSafetyV1.visibleControls(item.source)
        XCTAssertTrue(BidirectionalTextSafetyV1.isPrintableASCII(visible))
        XCTAssertEqual(
            visible,
            "[U+061C][U+200E][U+200F][U+202A][U+202B][U+202C]" +
                "[U+202D][U+202E][U+2066][U+2067][U+2068][U+2069]"
        )

        let natural = BidirectionalTextSafetyV1.naturalText(item.source)
        XCTAssertEqual(natural.unicodeScalars.first?.value, 0x2068)
        XCTAssertEqual(natural.unicodeScalars.last?.value, 0x2069)
        let inner = Array(natural.unicodeScalars.dropFirst().dropLast())
        XCTAssertFalse(inner.contains { scalar in
            [0x061C, 0x200E, 0x200F, 0x202A, 0x202B, 0x202C,
             0x202D, 0x202E, 0x2066, 0x2067, 0x2068, 0x2069]
                .contains(scalar.value)
        })
    }

    func testParagraphSeparatorsAndNaturalZWJTextRemainByteExact() throws {
        let fixture = try rtlFixture()
        let paragraphs = try fixture.case(named: "paragraph-separators")
        let expectedSeparators: [UInt32] = [0x000D, 0x000A, 0x000B, 0x000C, 0x0085, 0x2028, 0x2029]
        XCTAssertEqual(
            paragraphs.source.unicodeScalars.compactMap { scalar in
                expectedSeparators.contains(scalar.value) ? scalar.value : nil
            },
            expectedSeparators
        )
        XCTAssertEqual(
            BidirectionalTextSafetyV1.naturalText(paragraphs.source)
                .unicodeScalars.compactMap { scalar in
                    expectedSeparators.contains(scalar.value) ? scalar.value : nil
                },
            expectedSeparators
        )

        let zwj = try fixture.case(named: "zwj-emoji")
        assertUTF8Equal(
            BidirectionalTextSafetyV1.visibleControls(zwj.source),
            zwj.source,
            zwj.id
        )
        assertUTF8Equal(
            BidirectionalTextSafetyV1.naturalText(zwj.source), zwj.naturalText, zwj.id
        )
        assertUTF8Equal(
            BidirectionalTextSafetyV1.opaqueToken(zwj.source), zwj.opaqueToken, zwj.id
        )
        XCTAssertTrue(BidirectionalTextSafetyV1.opaqueToken(zwj.source).contains("[U+200D]"))

        let nfd = try fixture.case(named: "nfd-accent")
        XCTAssertNotEqual(Array(nfd.source.utf8), Array(nfd.source.precomposedStringWithCanonicalMapping.utf8))
        assertUTF8Equal(BidirectionalTextSafetyV1.naturalText(nfd.source), nfd.naturalText, nfd.id)
    }

    func testCanonicalOpenJSONRemainsRawAndReopenableAfterDisplayProjection() throws {
        let permittedMarks = "Label\u{061C}\u{200E}\u{200F}"
        let node = try ReportSemanticNodeV1(
            semanticID: "rtl-node-1",
            sectionID: "rtl-section",
            role: "fact",
            label: permittedMarks,
            value: "موقع AR-42 12.5 m"
        )
        let projection = try ReportSemanticProjectionV1(
            projectionVersion: "rtl-display-v1",
            snapshotID: "rtl-snapshot-1",
            snapshotSHA256: String(repeating: "a", count: 64),
            manifestSHA256: String(repeating: "b", count: 64),
            profileBindingSHA256: String(repeating: "c", count: 64),
            nodes: [node]
        )

        let before = try DeterministicOpenJSONRendererV1.render(projection)
        XCTAssertEqual(try DeterministicOpenJSONRendererV1.reopen(before.data), projection)
        XCTAssertNotNil(before.data.range(of: Data(permittedMarks.utf8)))

        let display = try DeterministicOpenJSONRendererV1.bidiSafeDisplayLines(projection)
        XCTAssertEqual(display.count, 1)
        XCTAssertTrue(display[0].contains("[U+061C][U+200E][U+200F]"))
        XCTAssertTrue(display[0].contains("\u{2068}موقع AR-42 12.5 m\u{2069}"))

        let after = try DeterministicOpenJSONRendererV1.render(projection)
        XCTAssertEqual(after.data, before.data)
        XCTAssertEqual(after.sha256, before.sha256)
        XCTAssertEqual(try DeterministicOpenJSONRendererV1.reopen(after.data), projection)
    }

    func testOpenJSONRejectsOverridesAndIsolateControlsWhileAllowingDirectionalMarks() throws {
        for scalar: UInt32 in [
            0x202A, 0x202B, 0x202C, 0x202D, 0x202E,
            0x2066, 0x2067, 0x2068, 0x2069,
        ] {
            let hostile = "text" + String(UnicodeScalar(scalar)!) + "tail"
            XCTAssertThrowsError(try ReportSemanticNodeV1(
                semanticID: "rtl-node-1",
                sectionID: "rtl-section",
                role: "fact",
                label: hostile,
                value: "value"
            ))
        }
        XCTAssertNoThrow(try ReportSemanticNodeV1(
            semanticID: "rtl-node-1",
            sectionID: "rtl-section",
            role: "fact",
            label: "\u{061C}\u{200E}\u{200F}",
            value: "value"
        ))
    }

    func testGlobalizationRTLDisplayHelpersPreserveLocalizedBytesAndContainFallback() throws {
        let localizedName = "موقع\u{200D} AR-42"
        let identifier = try rtlFixture().case(named: "mixed-arabic-identifiers").source

        let localizedResult = GlobalizationRTLSemanticsV1.opaqueFallback(
            localizedName,
            identifier: identifier
        )
        XCTAssertEqual(Data(localizedResult.utf8), Data(localizedName.utf8))

        let fallback = GlobalizationRTLSemanticsV1.opaqueFallback(nil, identifier: identifier)
        assertUTF8Equal(fallback, BidirectionalTextSafetyV1.opaqueToken(identifier), "opaque fallback")
        XCTAssertEqual(fallback.unicodeScalars.first?.value, 0x2066)
        XCTAssertEqual(fallback.unicodeScalars.last?.value, 0x2069)

        let detail = GlobalizationRTLSemanticsV1.accessibilityDetail(identifier)
        assertUTF8Equal(detail, BidirectionalTextSafetyV1.naturalText(identifier), "accessibility detail")
        XCTAssertEqual(detail.unicodeScalars.first?.value, 0x2068)
        XCTAssertEqual(detail.unicodeScalars.last?.value, 0x2069)
    }

    func testPDFRendererKeepsLegacyASCIITextRouteDeterministicAndReopenable() throws {
        let fixture = try pdfFixture(values: ["Plain ASCII label with AR-42 and 12.5 m"])
        let rawOpenJSON = try DeterministicOpenJSONRendererV1.render(fixture.projection)

        let first = try DeterministicPDFRendererV1.render(
            fixture.projection,
            layoutProfile: fixture.layoutProfile
        )
        let second = try DeterministicPDFRendererV1.render(
            fixture.projection,
            layoutProfile: fixture.layoutProfile
        )
        let asciiPDF = try XCTUnwrap(String(data: first.data, encoding: .ascii))

        XCTAssertEqual(first.data, second.data)
        XCTAssertTrue(asciiPDF.contains(" Tj"))
        XCTAssertFalse(asciiPDF.contains("/Subtype /Image"))
        XCTAssertEqual(try DeterministicPDFRendererV1.reopen(first.data), fixture.projection)
        XCTAssertEqual(first.semanticSHA256, fixture.projection.semanticSHA256)
        XCTAssertEqual(first.orderedSemanticIDs, fixture.projection.nodes.map(\.semanticID))
        XCTAssertEqual(try DeterministicOpenJSONRendererV1.render(fixture.projection).data, rawOpenJSON.data)
    }

    func testPDFRendererThrowsForUnassignedVisibleScalarInsteadOfBlankFallback() throws {
        let fixture = try pdfFixture(values: ["Latin موقع\u{0378} AR-42"])
        XCTAssertThrowsError(try DeterministicPDFRendererV1.render(
            fixture.projection,
            layoutProfile: fixture.layoutProfile
        ))
    }

    #if canImport(CoreGraphics)
    func testPDFRendererRendersArabicLongTextAndZWJAsNonBlankReadableRasterPages() throws {
        let longMixedText = String(repeating: "موقع 👩‍🔧 AR-42 12.5 m ", count: 72)
        let fixture = try pdfFixture(values: Array(repeating: longMixedText, count: 4))
        let rawOpenJSON = try DeterministicOpenJSONRendererV1.render(fixture.projection)

        let first = try DeterministicPDFRendererV1.render(
            fixture.projection,
            layoutProfile: fixture.layoutProfile
        )
        let second = try DeterministicPDFRendererV1.render(
            fixture.projection,
            layoutProfile: fixture.layoutProfile
        )
        let asciiPDF = try XCTUnwrap(String(data: first.data, encoding: .ascii))

        XCTAssertEqual(first.data, second.data)
        XCTAssertTrue(asciiPDF.contains("/Subtype /Image"))
        XCTAssertFalse(asciiPDF.contains("?"))
        XCTAssertFalse(asciiPDF.contains("\\u{"))
        XCTAssertEqual(try DeterministicPDFRendererV1.reopen(first.data), fixture.projection)
        XCTAssertEqual(first.semanticSHA256, fixture.projection.semanticSHA256)
        XCTAssertEqual(first.orderedSemanticIDs, fixture.projection.nodes.map(\.semanticID))
        XCTAssertEqual(try DeterministicOpenJSONRendererV1.render(fixture.projection).data, rawOpenJSON.data)
        try assertReadablePDFHasInk(first.data, minimumPages: 2)
        try assertFinalRasterImageHasInk(first.data)
    }

    @MainActor
    func testWorklightRendererValidatesMultilingualSnapshotAndPaginatesWithoutChangingRawBytes() throws {
        let separator = "\r\n\u{000B}\u{000C}\u{0085}\u{2028}\u{2029}"
        let authoredAddress = String(repeating: "موقع 👩‍🔧 AR-42 12.5 m" + separator, count: 12)
            + "موقع 👩‍🔧 AR-42"
        let harness = try RTLSnapshotHarnessV1.makeHarness(
            label: "multilingual-worklight",
            siteAddress: authoredAddress
        )
        defer {
            try? FileManager.default.removeItem(at: harness.applicationSupportURL)
            withExtendedLifetime(harness.session) {}
        }

        let snapshotURL = harness.session.generationRootURL
            .appendingPathComponent(harness.report.snapshotRelativePath)
        let rawBefore = try Data(contentsOf: snapshotURL)
        XCTAssertEqual(KernelCanonicalHashV1.sha256(rawBefore), harness.report.snapshotSHA256)

        let validated = try SnapshotValidatorV1(
            modelContext: harness.session.modelContext,
            generationRootURL: harness.session.generationRootURL
        ).validate(report: harness.report)
        XCTAssertEqual(Data(try XCTUnwrap(validated.snapshot.site.address).utf8), Data(authoredAddress.utf8))

        let first = try WorklightPDFRendererV1().render(validated)
        let second = try WorklightPDFRendererV1().render(validated)
        XCTAssertEqual(first.data, second.data)
        XCTAssertEqual(first.sha256, second.sha256)
        XCTAssertGreaterThanOrEqual(first.pageCount, 2)
        XCTAssertEqual(first.inspection.pages.count, first.pageCount)
        let logicalIdentity = first.inspection.pages.flatMap { $0 }
            .filter { $0.role == "identity.body" }
            .compactMap(\.text)
            .joined(separator: "\n")
        XCTAssertEqual(logicalIdentity.components(separatedBy: "موقع 👩‍🔧 AR-42 12.5 m").count - 1, 12)
        XCTAssertGreaterThanOrEqual(logicalIdentity.components(separatedBy: "AR-42").count - 1, 13)
        XCTAssertGreaterThanOrEqual(logicalIdentity.components(separatedBy: "12.5 m").count - 1, 12)
        for item in first.inspection.pages.flatMap({ $0 }) {
            XCTAssertTrue(
                first.inspection.contentRect.insetBy(dx: -0.01, dy: -0.01).contains(item.rect),
                "\(item.role) escaped content: \(item.rect)"
            )
        }
        try assertReadablePDFHasInk(first.data, minimumPages: 2)
        XCTAssertEqual(try Data(contentsOf: snapshotURL), rawBefore)
        XCTAssertEqual(KernelCanonicalHashV1.sha256(try Data(contentsOf: snapshotURL)), harness.report.snapshotSHA256)
    }
    #endif

    #if canImport(UIKit)
    @MainActor
    func testWorklightCardMirrorsSemanticLeadingLayoutWithoutChangingLogicalLabels() throws {
        let logicalLabels = ["موقع AR-42", "12.5 m"]
        let ltr = try hostedWorklightCardLayout(
            direction: .leftToRight,
            logicalLabels: logicalLabels
        )
        let rtl = try hostedWorklightCardLayout(
            direction: .rightToLeft,
            logicalLabels: logicalLabels
        )

        XCTAssertEqual(ltr.logicalLabels, logicalLabels)
        XCTAssertEqual(rtl.logicalLabels, logicalLabels)
        XCTAssertLessThan(ltr.firstLogicalChild.minX, ltr.secondLogicalChild.minX)
        XCTAssertGreaterThan(rtl.firstLogicalChild.minX, rtl.secondLogicalChild.minX)
        XCTAssertGreaterThan(rtl.firstLogicalChild.minX, ltr.firstLogicalChild.minX)
        XCTAssertLessThan(rtl.secondLogicalChild.minX, ltr.secondLogicalChild.minX)
    }
    #endif

    func testEmptyDisplayBoundaryAndDeclaredLanguageCohortRemainClosed() {
        XCTAssertEqual(BidirectionalTextSafetyV1.visibleControls(""), "")
        XCTAssertEqual(BidirectionalTextSafetyV1.naturalText(""), "")
        XCTAssertEqual(BidirectionalTextSafetyV1.opaqueToken(""), "")
        XCTAssertTrue(BidirectionalTextSafetyV1.isPrintableASCII(""))

        XCTAssertEqual(
            AppLanguageTagV1.supportedRawValues,
            Set(["en", "es", "zh-Hans", "zh-Hant", "vi", "ko"])
        )
        XCTAssertFalse(AppLanguageTagV1.supportedRawValues.contains("ar"))
    }

    private func rtlFixture() throws -> RTLFixtureV1 {
        try JSONDecoder().decode(
            RTLFixtureV1.self,
            from: Data(contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .appendingPathComponent("Fixtures/V30/RTL/rtl-hostile-cases-v1.json"))
        )
    }

    private func assertUTF8Equal(
        _ actual: String,
        _ expected: String,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(Array(actual.utf8), Array(expected.utf8), message, file: file, line: line)
    }

    private func assertBalancedIsolates(
        _ value: String,
        opener: UInt32,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let openCount = value.unicodeScalars.filter { $0.value == opener }.count
        let closeCount = value.unicodeScalars.filter { $0.value == 0x2069 }.count
        XCTAssertGreaterThan(openCount, 0, message, file: file, line: line)
        XCTAssertEqual(openCount, closeCount, message, file: file, line: line)
    }

    private func pdfFixture(values: [String]) throws -> PDFRendererFixtureV1 {
        let formats: [ReportProjectionFormatV1] = [.openJSON, .pdf, .structuredText]
        let requiredSectionIDs = ["identity", "limitations", "provenance", "supersession", "manifest"]
        let sections = try requiredSectionIDs.enumerated().map { index, sectionID in
            try ReportSectionDefinitionV1(
                sectionID: sectionID,
                version: 1,
                required: true,
                supportedFormats: formats,
                privacyClass: .mandatoryPublicTruth,
                requiresHeading: true,
                requiresTextAlternative: true,
                order: index
            )
        }
        let registry = try ReportSectionRegistryV1(
            registryID: "rtl-pdf-registry-v1",
            registryVersion: 1,
            sections: sections
        )
        let layoutProfile = try ReportLayoutProfileV1(
            profileID: "rtl-pdf-profile-v1",
            profileRelease: 1,
            audience: .customerSafe,
            detail: .complete,
            sectionIDs: requiredSectionIDs,
            mediaLayout: .standardGrid,
            orientation: .portrait,
            localeIdentifier: "en-US",
            unitsProfileID: "units-si-v1",
            displayProfileID: "display-v1",
            registry: registry
        )
        let nodes = try values.enumerated().map { index, value in
            try ReportSemanticNodeV1(
                semanticID: String(format: "rtl-pdf-%02d", index),
                sectionID: "identity",
                role: "fact",
                label: "Reading \(index + 1)",
                value: value
            )
        }
        let projection = try ReportSemanticProjectionV1(
            projectionVersion: "rtl-pdf-projection-v1",
            snapshotID: "rtl-pdf-snapshot-v1",
            snapshotSHA256: String(repeating: "a", count: 64),
            manifestSHA256: String(repeating: "b", count: 64),
            profileBindingSHA256: String(repeating: "c", count: 64),
            nodes: nodes
        )
        return PDFRendererFixtureV1(projection: projection, layoutProfile: layoutProfile)
    }

    #if canImport(CoreGraphics)
    private func assertReadablePDFHasInk(_ data: Data, minimumPages: Int) throws {
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        let document = try XCTUnwrap(CGPDFDocument(provider))
        XCTAssertGreaterThanOrEqual(document.numberOfPages, minimumPages)

        var inkPixels = 0
        for pageIndex in 1...document.numberOfPages {
            let page = try XCTUnwrap(document.page(at: pageIndex))
            let bounds = page.getBoxRect(.mediaBox).integral
            let width = max(1, Int(bounds.width))
            let height = max(1, Int(bounds.height))
            var pixels = [UInt8](repeating: 255, count: width * height)
            let context = try XCTUnwrap(CGContext(
                data: &pixels,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: 0
            ))
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            context.drawPDFPage(page)
            inkPixels += pixels.reduce(into: 0) { count, pixel in
                if pixel < 240 { count += 1 }
            }
        }
        XCTAssertGreaterThan(inkPixels, 256)
    }

    private func assertFinalRasterImageHasInk(_ data: Data) throws {
        let source = try XCTUnwrap(String(data: data, encoding: .ascii))
        let imageMarker = try XCTUnwrap(
            source.range(of: "/Subtype /Image", options: .backwards),
            "Unicode PDF did not contain a raster image"
        )
        let imageTail = source[imageMarker.lowerBound...]
        let streamStart = try XCTUnwrap(imageTail.range(of: "stream\n"))
        let streamEnd = try XCTUnwrap(imageTail.range(of: "\nendstream"))
        let encodedHex = imageTail[streamStart.upperBound..<streamEnd.lowerBound]
            .filter { !$0.isWhitespace && $0 != ">" }
        XCTAssertFalse(encodedHex.isEmpty)
        XCTAssertEqual(encodedHex.count % 2, 0)

        var encoded: [UInt8] = []
        var index = encodedHex.startIndex
        while index < encodedHex.endIndex {
            let next = encodedHex.index(index, offsetBy: 2)
            encoded.append(try XCTUnwrap(UInt8(String(encodedHex[index..<next]), radix: 16)))
            index = next
        }
        let pixels = try decodePDFRunLength(encoded)
        XCTAssertGreaterThan(pixels.filter { $0 < 240 }.count, 8)
    }

    private func decodePDFRunLength(_ encoded: [UInt8]) throws -> [UInt8] {
        var result: [UInt8] = []
        var index = 0
        while index < encoded.count {
            let marker = encoded[index]
            index += 1
            if marker == 128 {
                XCTAssertEqual(index, encoded.count, "Run-length stream has bytes after EOD")
                return result
            }
            if marker <= 127 {
                let count = Int(marker) + 1
                guard index + count <= encoded.count else {
                    throw PDFRasterDecodeFailureV1.truncatedLiteral
                }
                result.append(contentsOf: encoded[index..<(index + count)])
                index += count
            } else {
                guard index < encoded.count else {
                    throw PDFRasterDecodeFailureV1.truncatedRepeat
                }
                let count = 257 - Int(marker)
                result.append(contentsOf: repeatElement(encoded[index], count: count))
                index += 1
            }
        }
        throw PDFRasterDecodeFailureV1.missingEndOfData
    }
    #endif

    #if canImport(UIKit)
    @MainActor
    private func hostedWorklightCardLayout(
        direction: LayoutDirection,
        logicalLabels: [String]
    ) throws -> WorklightCardLayoutV1 {
        var frames: [String: CGRect] = [:]
        let host = UIHostingController(
            rootView: WorklightCardLayoutProbeV1(
                direction: direction,
                logicalLabels: logicalLabels,
                recordFrames: { frames = $0 }
            )
        )
        host.view.frame = CGRect(x: 0, y: 0, width: 320, height: 96)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        host.view.layoutIfNeeded()

        return WorklightCardLayoutV1(
            logicalLabels: logicalLabels,
            firstLogicalChild: try XCTUnwrap(frames["first"], "first child frame missing"),
            secondLogicalChild: try XCTUnwrap(frames["second"], "second child frame missing")
        )
    }
    #endif
}

private struct RTLFixtureV1: Decodable {
    let schemaVersion: Int
    let cases: [Case]

    struct Case: Decodable {
        let id: String
        let source: String
        let utf8SHA256: String
        let utf8ByteCount: Int
        let visibleControls: String
        let naturalText: String
        let opaqueToken: String
    }

    func `case`(named id: String) throws -> Case {
        try XCTUnwrap(cases.first { $0.id == id }, "Missing RTL fixture case: \(id)")
    }
}

private struct PDFRendererFixtureV1 {
    let projection: ReportSemanticProjectionV1
    let layoutProfile: ReportLayoutProfileV1
}

private enum PDFRasterDecodeFailureV1: Error {
    case truncatedLiteral
    case truncatedRepeat
    case missingEndOfData
}

#if canImport(UIKit)
private struct WorklightCardLayoutV1 {
    let logicalLabels: [String]
    let firstLogicalChild: CGRect
    let secondLogicalChild: CGRect
}

private struct WorklightCardFramePreferenceKeyV1: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private struct WorklightCardFrameReaderV1: View {
    let name: String

    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: WorklightCardFramePreferenceKeyV1.self,
                value: [name: proxy.frame(in: .global)]
            )
        }
    }
}

private struct WorklightCardLayoutProbeV1: View {
    let direction: LayoutDirection
    let logicalLabels: [String]
    let recordFrames: ([String: CGRect]) -> Void

    var body: some View {
        WorklightCard {
            HStack(spacing: 16) {
                Text(logicalLabels[0])
                    .lineLimit(1)
                    .frame(width: 108, height: 24)
                    .background(WorklightCardFrameReaderV1(name: "first"))
                Text(logicalLabels[1])
                    .lineLimit(1)
                    .frame(width: 72, height: 24)
                    .background(WorklightCardFrameReaderV1(name: "second"))
            }
        }
        .frame(width: 320)
        .environment(\.layoutDirection, direction)
        .onPreferenceChange(WorklightCardFramePreferenceKeyV1.self, perform: recordFrames)
    }
}
#endif


private struct RTLSnapshotHarnessV1 {
    let applicationSupportURL: URL
    let session: StoreGenerationSession
    let report: Report
}

@MainActor
private struct RTLSnapshotAuthorityV1 {
    let site: Site
    let asset: Asset
    let check: WorkflowRecord
    let work: WorkflowRecord
    let recheck: WorkflowRecord
    let issue: Issue
    let historicalPacket: Packet
    let packet: Packet
    let report: Report
    let rows: [EvidenceFile]
    let snapshot: ReportSnapshotV1
}

private struct RTLSnapshotEvidenceV1 {
    let row: EvidenceFile
    let snapshot: EvidenceSnapshotV1
}

private enum RTLSnapshotFixtureErrorV1: Error { case image }

private enum RTLSnapshotFixtureV1 {
    static let reportID = UUID(uuidString: "41000000-0000-0000-0000-000000000001")!
    static let packetID = UUID(uuidString: "41000000-0000-0000-0000-000000000002")!
    static let stableRootID = UUID(uuidString: "41000000-0000-0000-0000-000000000003")!
    static let siteID = UUID(uuidString: "41000000-0000-0000-0000-000000000004")!
    static let assetID = UUID(uuidString: "41000000-0000-0000-0000-000000000005")!
    static let checkID = UUID(uuidString: "41000000-0000-0000-0000-000000000006")!
    static let workID = UUID(uuidString: "41000000-0000-0000-0000-000000000007")!
    static let recheckID = UUID(uuidString: "41000000-0000-0000-0000-000000000008")!
    static let issueID = UUID(uuidString: "41000000-0000-0000-0000-000000000009")!
    static let currentWideID = UUID(uuidString: "41000000-0000-0000-0000-000000000010")!
    static let historyCloseID = UUID(uuidString: "41000000-0000-0000-0000-000000000011")!
    static let historyWorkID = UUID(uuidString: "41000000-0000-0000-0000-000000000012")!
    static let historyWideID = UUID(uuidString: "41000000-0000-0000-0000-000000000013")!
    static let historicalPacketID = UUID(uuidString: "41000000-0000-0000-0000-000000000014")!
    static let historicalStableRootID = UUID(uuidString: "41000000-0000-0000-0000-000000000015")!
    static let snapshotDate = Date(timeIntervalSince1970: 1_768_420_926)
}

private extension RTLSnapshotHarnessV1 {
    @MainActor
    static func makeHarness(
        label: String,
        siteAddress: String
    ) throws -> RTLSnapshotHarnessV1 {
        let appSupport = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent(
            "V30P02C03RTLSemanticsTests-\(label)-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: false)
        let session = try StoreGenerationFactory(applicationSupportURL: appSupport)
            .openOrBootstrapCurrent()
        let context = session.modelContext
        let snapshot = try fixtureSnapshotAndRows(in: session, siteAddress: siteAddress)
        context.insert(snapshot.site)
        context.insert(snapshot.asset)
        context.insert(snapshot.check)
        context.insert(snapshot.work)
        context.insert(snapshot.recheck)
        context.insert(snapshot.issue)
        context.insert(snapshot.historicalPacket)
        context.insert(snapshot.packet)
        for row in snapshot.rows { context.insert(row) }
        context.insert(snapshot.report)
        try context.save()

        let encoded = try ReportSnapshotEncoderV1().encode(snapshot.snapshot)
        XCTAssertEqual(encoded.sha256, snapshot.report.snapshotSHA256)
        let snapshotURL = session.generationRootURL.appendingPathComponent(
            snapshot.report.snapshotRelativePath
        )
        try FileManager.default.createDirectory(
            at: snapshotURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoded.data.write(to: snapshotURL)

        return RTLSnapshotHarnessV1(
            applicationSupportURL: appSupport,
            session: session,
            report: snapshot.report
        )
    }

    @MainActor
    static func fixtureSnapshotAndRows(
        in session: StoreGenerationSession,
        siteAddress: String? = nil
    ) throws -> RTLSnapshotAuthorityV1 {
        let normalizer = MediaNormalizerV1()
        let currentWide = try normalizer.normalize(makePNG(width: 320, height: 180, seed: 17))
        let historyWide = try normalizer.normalize(makePNG(width: 960, height: 540, seed: 31))
        let historyClose = try normalizer.normalize(makePNG(width: 600, height: 900, seed: 43))
        let historyWork = try normalizer.normalize(makePNG(width: 800, height: 480, seed: 79))
        let evidence = [
            try makeEvidence(
                id: RTLSnapshotFixtureV1.currentWideID,
                recordID: RTLSnapshotFixtureV1.recheckID,
                purpose: "wide_context",
                display: "Wide view",
                media: currentWide,
                createdAt: Date(timeIntervalSince1970: 1_768_420_924),
                root: session.generationRootURL
            ),
            try makeEvidence(
                id: RTLSnapshotFixtureV1.historyWideID,
                recordID: RTLSnapshotFixtureV1.checkID,
                purpose: "wide_context",
                display: "Wide view",
                media: historyWide,
                createdAt: Date(timeIntervalSince1970: 1_768_420_799),
                root: session.generationRootURL
            ),
            try makeEvidence(
                id: RTLSnapshotFixtureV1.historyCloseID,
                recordID: RTLSnapshotFixtureV1.checkID,
                purpose: "close_detail",
                display: "Close view",
                media: historyClose,
                createdAt: Date(timeIntervalSince1970: 1_768_420_800),
                root: session.generationRootURL
            ),
            try makeEvidence(
                id: RTLSnapshotFixtureV1.historyWorkID,
                recordID: RTLSnapshotFixtureV1.workID,
                purpose: "work_context",
                display: "Work photo",
                media: historyWork,
                createdAt: Date(timeIntervalSince1970: 1_768_420_850),
                root: session.generationRootURL
            ),
        ]
        let rows = evidence.map(\.row)
        let site = Site(
            id: RTLSnapshotFixtureV1.siteID,
            label: "North Campus",
            address: siteAddress ?? "10 Main",
            timeZoneID: "America/New_York",
            createdAt: Date(timeIntervalSince1970: 1_768_420_700)
        )
        let asset = Asset(
            id: RTLSnapshotFixtureV1.assetID,
            siteID: site.id,
            packID: "field.evidence.illuminated_sign.v1",
            packSchemaVersion: 1,
            packContentVersion: 1,
            label: "Monument Sign",
            createdAt: Date(timeIntervalSince1970: 1_768_420_701)
        )
        let check = makeRecord(
            id: RTLSnapshotFixtureV1.checkID,
            parentID: nil,
            stage: .check,
            outcome: "visible_issue",
            completedAt: Date(timeIntervalSince1970: 1_768_420_810),
            issueID: RTLSnapshotFixtureV1.issueID,
            workDate: nil,
            workDescription: nil
        )
        let work = makeRecord(
            id: RTLSnapshotFixtureV1.workID,
            parentID: check.id,
            stage: .work,
            outcome: "work_recorded",
            completedAt: Date(timeIntervalSince1970: 1_768_420_860),
            issueID: RTLSnapshotFixtureV1.issueID,
            workDate: "2026-01-14",
            workDescription: "Replaced the sign power supply."
        )
        let recheck = makeRecord(
            id: RTLSnapshotFixtureV1.recheckID,
            parentID: work.id,
            stage: .recheck,
            outcome: "could_not_verify",
            completedAt: RTLSnapshotFixtureV1.snapshotDate,
            issueID: RTLSnapshotFixtureV1.issueID,
            workDate: nil,
            workDescription: nil
        )
        let issue = Issue(
            id: RTLSnapshotFixtureV1.issueID,
            assetID: asset.id,
            openedByRecordID: check.id,
            labelKey: "dark_section",
            labelDisplaySnapshot: "Section appears dark",
            status: .recheckDue,
            resolvedByRecordID: nil,
            createdAt: Date(timeIntervalSince1970: 1_768_420_810),
            updatedAt: Date(timeIntervalSince1970: 1_768_420_860)
        )
        let packet = Packet(
            id: RTLSnapshotFixtureV1.packetID,
            stableRootID: RTLSnapshotFixtureV1.stableRootID,
            currentRecordID: recheck.id,
            evaluationCounted: true,
            contentDeletedAt: nil,
            createdAt: Date(timeIntervalSince1970: 1_768_420_700)
        )
        let historicalPacket = Packet(
            id: RTLSnapshotFixtureV1.historicalPacketID,
            stableRootID: RTLSnapshotFixtureV1.historicalStableRootID,
            currentRecordID: check.id,
            evaluationCounted: true,
            contentDeletedAt: nil,
            createdAt: Date(timeIntervalSince1970: 1_768_420_700)
        )
        let snapshot = ReportSnapshotV1(
            acknowledgements: acknowledgements(),
            asset: AssetSnapshotV1(label: asset.label),
            couldNotVerify: CouldNotVerifySnapshotV1(
                display: "Required view is blocked",
                key: "required_view_obstructed",
                registryVersion: "cnv.reason.en-US.v1"
            ),
            disclaimer: "This report records visible conditions from the listed photos and time. It is not an electrical, code, safety, or professional certification.",
            display: DisplaySnapshotV1(
                assetSingular: "sign",
                checkSingular: "check",
                issueSingular: "visible issue",
                outcome: "Could not verify",
                stage: "Recheck"
            ),
            evidence: evidence.map(\.snapshot),
            evidenceSourceRecordID: recheck.id,
            history: [
                historySnapshot(check, evidenceIDs: [RTLSnapshotFixtureV1.historyWideID, RTLSnapshotFixtureV1.historyCloseID], stageDisplay: "Check", outcomeDisplay: "Visible issue"),
                historySnapshot(work, evidenceIDs: [RTLSnapshotFixtureV1.historyWorkID], stageDisplay: "Work", outcomeDisplay: "Work recorded"),
            ],
            issues: [IssueSnapshotV1(
                createdAt: issue.createdAt,
                display: issue.labelDisplaySnapshot,
                issueID: issue.id,
                key: issue.labelKey,
                openedByRecordID: issue.openedByRecordID,
                resolvedByRecordID: nil,
                status: IssueStatus.recheckDue.rawValue,
                updatedAt: work.completedAt!
            )],
            note: "Access was blocked at the close-view position.",
            outcome: "could_not_verify",
            pack: PackSnapshotV1(contentVersion: 1, id: "field.evidence.illuminated_sign.v1", schemaVersion: 1),
            packetID: packet.id,
            pdfTemplate: PDFTemplateReferenceV1(id: "field.evidence.pdf.worklight.v1", version: 1),
            reportID: RTLSnapshotFixtureV1.reportID,
            site: SiteSnapshotV1(address: site.address, label: site.label),
            snapshotCreatedAt: RTLSnapshotFixtureV1.snapshotDate,
            snapshotSchemaVersion: 1,
            sourceApp: SourceAppSnapshotV1(build: "41", version: "1.0"),
            sourceRecordID: recheck.id,
            stableRootID: packet.stableRootID,
            stage: "recheck",
            timeContext: TimeContextSnapshotV1(
                localDate: "2026-01-14",
                localTime: "15:02:03",
                observedAtUTC: Date(timeIntervalSince1970: 1_768_420_923),
                timeZoneID: "America/New_York",
                utcOffsetMinutes: -300
            )
        )
        let encoded = try ReportSnapshotEncoderV1().encode(snapshot)
        let report = Report(
            id: RTLSnapshotFixtureV1.reportID,
            packetID: packet.id,
            sourceRecordID: recheck.id,
            snapshotSchemaVersion: 1,
            snapshotRelativePath: "snapshots/\(RTLSnapshotFixtureV1.reportID.uuidString.lowercased()).json",
            snapshotSHA256: encoded.sha256,
            pdfState: .pending,
            pdfRelativePath: nil,
            pdfSHA256: nil,
            createdAt: RTLSnapshotFixtureV1.snapshotDate,
            replacesReportID: nil
        )
        return RTLSnapshotAuthorityV1(
            site: site,
            asset: asset,
            check: check,
            work: work,
            recheck: recheck,
            issue: issue,
            historicalPacket: historicalPacket,
            packet: packet,
            report: report,
            rows: rows,
            snapshot: snapshot
        )
    }

    static func makeRecord(
        id: UUID,
        parentID: UUID?,
        stage: WorkflowStage,
        outcome: String,
        completedAt: Date,
        issueID: UUID?,
        workDate: String?,
        workDescription: String?
    ) -> WorkflowRecord {
        let hasPreflight = stage != .work
        let isCurrentCNV = id == RTLSnapshotFixtureV1.recheckID
        return WorkflowRecord(
            id: id,
            assetID: RTLSnapshotFixtureV1.assetID,
            packetID: stage == .work
                ? nil
                : (id == RTLSnapshotFixtureV1.recheckID ? RTLSnapshotFixtureV1.packetID : RTLSnapshotFixtureV1.historicalPacketID),
            issueID: issueID,
            parentRecordID: parentID,
            recordRevisionRootID: id,
            revisesRecordID: nil,
            evidenceSourceRecordID: nil,
            revisionKind: .original,
            stage: stage,
            state: .completed,
            draftStepKey: nil,
            startedAt: completedAt.addingTimeInterval(-120),
            completedAt: completedAt,
            observedAtUTC: hasPreflight ? Date(timeIntervalSince1970: 1_768_420_923) : nil,
            timeZoneID: hasPreflight ? "America/New_York" : nil,
            utcOffsetMinutes: hasPreflight ? -300 : nil,
            localDate: hasPreflight ? "2026-01-14" : nil,
            localTime: hasPreflight ? "15:02:03" : nil,
            afterDarkAcknowledgementKey: hasPreflight ? "after_dark" : nil,
            afterDarkAcknowledgementCopy: hasPreflight ? "It is dark enough to observe the sign's visible illumination." : nil,
            afterDarkAcknowledgementVersion: hasPreflight ? "preflight.ack.en-US.v1" : nil,
            afterDarkAcknowledgementAccepted: hasPreflight ? true : nil,
            safePositionAcknowledgementKey: hasPreflight ? "safe_authorized_position" : nil,
            safePositionAcknowledgementCopy: hasPreflight ? "I am in a safe, authorized position to take these photos." : nil,
            safePositionAcknowledgementVersion: hasPreflight ? "preflight.ack.en-US.v1" : nil,
            safePositionAcknowledgementAccepted: hasPreflight ? true : nil,
            packID: "field.evidence.illuminated_sign.v1",
            packSchemaVersion: 1,
            packContentVersion: 1,
            pdfTemplateID: "field.evidence.pdf.worklight.v1",
            pdfTemplateVersion: 1,
            outcomeKey: outcome,
            couldNotVerifyKey: isCurrentCNV ? "required_view_obstructed" : nil,
            couldNotVerifyDisplaySnapshot: isCurrentCNV ? "Required view is blocked" : nil,
            couldNotVerifyRegistryVersion: isCurrentCNV ? "cnv.reason.en-US.v1" : nil,
            workPerformedLocalDate: workDate,
            workDescription: workDescription,
            note: isCurrentCNV ? "Access was blocked at the close-view position." : nil,
            finalizationMutationID: UUID(uuidString: id.uuidString.replacingOccurrences(of: "41000000", with: "42000000"))!
        )
    }

    static func acknowledgements() -> [AcknowledgementSnapshotV1] {
        [
            AcknowledgementSnapshotV1(
                accepted: true,
                copy: "It is dark enough to observe the sign's visible illumination.",
                key: "after_dark",
                version: "preflight.ack.en-US.v1"
            ),
            AcknowledgementSnapshotV1(
                accepted: true,
                copy: "I am in a safe, authorized position to take these photos.",
                key: "safe_authorized_position",
                version: "preflight.ack.en-US.v1"
            ),
        ]
    }

    static func historySnapshot(
        _ record: WorkflowRecord,
        evidenceIDs: [UUID],
        stageDisplay: String,
        outcomeDisplay: String
    ) -> HistoryEntrySnapshotV1 {
        HistoryEntrySnapshotV1(
            completedAt: record.completedAt!,
            couldNotVerify: nil,
            evidenceIDs: evidenceIDs,
            issueIDs: record.issueID.map { [$0] } ?? [],
            note: record.note,
            outcome: record.outcomeKey!,
            outcomeDisplay: outcomeDisplay,
            recordID: record.id,
            stage: record.stage,
            stageDisplay: stageDisplay,
            workDescription: record.workDescription,
            workPerformedLocalDate: record.workPerformedLocalDate
        )
    }

    static func makeEvidence(
        id: UUID,
        recordID: UUID,
        purpose: String,
        display: String,
        media: NormalizedMediaV1,
        createdAt: Date,
        root: URL
    ) throws -> RTLSnapshotEvidenceV1 {
        let canonicalID = id.uuidString.lowercased()
        let originalPath = "evidence/\(canonicalID)/original.jpg"
        let thumbnailPath = "evidence/\(canonicalID)/thumbnail.jpg"
        let directory = root.appendingPathComponent("evidence/\(canonicalID)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try media.originalJPEG.write(to: root.appendingPathComponent(originalPath))
        try media.thumbnailJPEG.write(to: root.appendingPathComponent(thumbnailPath))
        let row = EvidenceFile(
            id: id,
            recordID: recordID,
            purposeKey: purpose,
            relativePath: originalPath,
            mimeType: "image/jpeg",
            byteCount: media.originalJPEG.count,
            sha256: KernelCanonicalHashV1.sha256(media.originalJPEG),
            createdAt: createdAt,
            thumbnailRelativePath: thumbnailPath,
            thumbnailByteCount: media.thumbnailJPEG.count,
            thumbnailSHA256: KernelCanonicalHashV1.sha256(media.thumbnailJPEG)
        )
        return RTLSnapshotEvidenceV1(
            row: row,
            snapshot: EvidenceSnapshotV1(
                byteCount: row.byteCount,
                createdAt: createdAt,
                evidenceID: id,
                mimeType: row.mimeType,
                purposeDisplay: display,
                purposeKey: purpose,
                recordID: recordID,
                relativePath: originalPath,
                sha256: row.sha256,
                thumbnailByteCount: row.thumbnailByteCount,
                thumbnailRelativePath: thumbnailPath,
                thumbnailSHA256: row.thumbnailSHA256
            )
        )
    }

    static func makePNG(width: Int, height: Int, seed: UInt8) throws -> Data {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                pixels[offset] = seed &+ UInt8(truncatingIfNeeded: x)
                pixels[offset + 1] = seed &+ UInt8(truncatingIfNeeded: y)
                pixels[offset + 2] = seed &+ UInt8(truncatingIfNeeded: x ^ y)
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else { throw RTLSnapshotFixtureErrorV1.image }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { throw RTLSnapshotFixtureErrorV1.image }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw RTLSnapshotFixtureErrorV1.image }
        return output as Data
    }

}

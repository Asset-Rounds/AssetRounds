import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import XCTest
@testable import FieldEvidenceApp

@MainActor
final class V30P03C04GlobalizedAccessibleDocumentTests: XCTestCase {
    func testFixturePreservesSixReportLanguageTagsAndExactUTF8SourceBytes() throws {
        let fixture = try loadFixture()
        XCTAssertEqual(fixture.schemaVersion, 1)
        XCTAssertEqual(fixture.cardID, "V30-P03-C04")
        XCTAssertEqual(fixture.reportLanguages, ["en", "es", "zh-Hans", "zh-Hant", "vi", "ko"])
        XCTAssertEqual(fixture.paperSizes, ["US_LETTER", "A4"])

        for item in fixture.cases {
            XCTAssertEqual(item.text.utf8.count, item.utf8ByteCount, item.id)
        }
        let nfc = try fixture.case(named: "nfc-accent")
        let nfd = try fixture.case(named: "nfd-accent")
        XCTAssertEqual(nfc.text.precomposedStringWithCanonicalMapping, nfd.text.precomposedStringWithCanonicalMapping)
        XCTAssertNotEqual(Data(nfc.text.utf8), Data(nfd.text.utf8))
        XCTAssertNotEqual(KernelCanonicalHashV1.sha256(Data(nfc.text.utf8)), KernelCanonicalHashV1.sha256(Data(nfd.text.utf8)))
        let request = try renderRequest(paper: .usLetter, formattingLocale: "en-US")
        let nfcRender = try render(elements: [try .init(semanticID: "nfc.source", role: .paragraph, text: nfc.text)], request: request, sourceBytes: Data(nfc.text.utf8))
        let nfdRender = try render(elements: [try .init(semanticID: "nfd.source", role: .paragraph, text: nfd.text)], request: request, sourceBytes: Data(nfd.text.utf8))
        XCTAssertNotEqual(nfcRender.receipt.sourceSHA256, nfdRender.receipt.sourceSHA256)
        XCTAssertNotEqual(nfcRender.receipt.sourceContentSHA256, nfdRender.receipt.sourceContentSHA256)
    }

    func testAuthoredMultilingualTextExtractsAsLogicalTextWhileEffectiveReportLanguageRemainsEnglish() throws {
        let fixture = try loadFixture()
        let request = try renderRequest(paper: .usLetter, formattingLocale: "en-US")
        XCTAssertEqual(request.language.effectiveLanguage, .english)
        XCTAssertEqual(request.language.requestedLanguage, .english)

        for item in fixture.cases {
            let result = try render(
                elements: [try .init(semanticID: "paragraph.\(item.id)", role: .paragraph, text: item.text)],
                request: request,
                sourceBytes: Data(item.text.utf8)
            )
            let extracted = try extractedText(result.pdf.data)
            XCTAssertTrue(extracted.contains(item.text), item.id)
            XCTAssertFalse(extracted.contains("?"), item.id)
            XCTAssertEqual(result.receipt.language, request.language)
            XCTAssertEqual(result.receipt.orderedSemanticIDs, ["paragraph.\(item.id)"])
            XCTAssertTrue(try GlobalizedAccessibleDocumentRendererV1.readLogicalText(from: result.pdf.data).contains(item.text), item.id)
            for font in result.receipt.fonts where font.embedding == .outlineSubset {
                XCTAssertEqual(font.os2FsType & 0x0302, 0, item.id)
            }
            if item.id == "arabic-mixed-bidi" {
                XCTAssertTrue(result.receipt.fonts.contains { $0.embedding == .colorGlyphImages })
                XCTAssertTrue(result.receipt.nativeColorGlyphImagesObserved)
            }
            try result.receipt.validate()
        }
    }

    func testLetterAndA4UseExplicitPaperDimensionsIndependentOfFormattingLocale() throws {
        let text = "纸张尺寸 / paper size AR-42"
        let elements = [try GlobalizedDocumentElementV1(semanticID: "paper.body", role: .paragraph, text: text)]
        let source = Data(text.utf8)
        let enLetter = try render(elements: elements, request: renderRequest(paper: .usLetter, formattingLocale: "en-US"), sourceBytes: source)
        let esLetter = try render(elements: elements, request: renderRequest(paper: .usLetter, formattingLocale: "es-ES"), sourceBytes: source)
        let enA4 = try render(elements: elements, request: renderRequest(paper: .a4, formattingLocale: "en-US"), sourceBytes: source)

        XCTAssertEqual(enLetter.receipt.paper, try LocaleFormattingServiceV1(profile: formattingProfile("en-US")).paperLayout(.usLetter))
        XCTAssertEqual(esLetter.receipt.paper, enLetter.receipt.paper)
        XCTAssertEqual(enA4.receipt.paper, try LocaleFormattingServiceV1(profile: formattingProfile("en-US")).paperLayout(.a4))
        XCTAssertNotEqual(enLetter.receipt.paper, enA4.receipt.paper)
        try assertMediaBox(enLetter.pdf.data, width: 612, height: 792)
        try assertMediaBox(enA4.pdf.data, width: 595.28, height: 841.89)
    }

    func testReplayIsByteAndReceiptIdenticalAndRejectsChangedDependencies() throws {
        let text = "重現 / إعادة التشغيل / deterministic replay"
        let elements = [try GlobalizedDocumentElementV1(semanticID: "replay.body", role: .paragraph, text: text)]
        let source = Data(text.utf8)
        let request = try renderRequest(paper: .a4, formattingLocale: "en-US")
        let first = try render(elements: elements, request: request, sourceBytes: source)
        let replay = try GlobalizedAccessibleDocumentRendererV1().render(
            elements: elements,
            sourceSHA256: KernelCanonicalHashV1.sha256(source),
            sourceCreatedAt: sourceCreatedAt,
            request: request,
            expectedReplay: first.receipt
        )
        XCTAssertEqual(replay.pdf.data, first.pdf.data)
        XCTAssertEqual(replay.pdf.sha256, first.pdf.sha256)
        XCTAssertEqual(replay.receipt, first.receipt)
        let outlineFonts = first.receipt.fonts.filter { $0.embedding == .outlineSubset }
        XCTAssertFalse(outlineFonts.isEmpty)
        XCTAssertTrue(first.receipt.nativeFontEmbeddingObserved, "outline-font embedding only")
        XCTAssertTrue(first.receipt.nativeToUnicodeObserved, "outline-font ToUnicode only")
        let attributes = try XCTUnwrap(PDFDocument(data: first.pdf.data)?.documentAttributes)
        XCTAssertEqual(attributes[PDFDocumentAttribute.creationDateAttribute] as? Date, sourceCreatedAt)
        XCTAssertEqual(attributes[PDFDocumentAttribute.modificationDateAttribute] as? Date, sourceCreatedAt)
        XCTAssertTrue(first.receipt.pendingExternalQualification)

        XCTAssertThrowsError(try GlobalizedAccessibleDocumentRendererV1().render(
            elements: elements, sourceSHA256: KernelCanonicalHashV1.sha256(source), sourceCreatedAt: sourceCreatedAt,
            request: try renderRequest(paper: .usLetter, formattingLocale: "en-US"), expectedReplay: first.receipt
        ))
        XCTAssertThrowsError(try GlobalizedAccessibleDocumentRendererV1().render(
            elements: elements, sourceSHA256: KernelCanonicalHashV1.sha256(Data("changed source".utf8)), sourceCreatedAt: sourceCreatedAt,
            request: request, expectedReplay: first.receipt
        ))
        XCTAssertThrowsError(try GlobalizedAccessibleDocumentRendererV1().render(
            elements: elements, sourceSHA256: KernelCanonicalHashV1.sha256(source), sourceCreatedAt: sourceCreatedAt,
            request: try renderRequest(paper: .a4, formattingLocale: "es-ES"), expectedReplay: first.receipt
        ))
    }

    func testLongCJKAndRTLPaginateWithoutClippingAndRemainExtractableInLogicalOrder() throws {
        let cjk = String(repeating: "檢查項目已通過。\n", count: 120)
        let rtl = String(repeating: "تقرير الموقع AR-42 الحالة ناجح. \n", count: 100)
        let emptyParagraphs = "\n\n"
        let elements = [
            try GlobalizedDocumentElementV1(semanticID: "long.cjk", role: .paragraph, text: cjk),
            try GlobalizedDocumentElementV1(semanticID: "long.empty", role: .paragraph, text: emptyParagraphs),
            try GlobalizedDocumentElementV1(semanticID: "long.rtl", role: .paragraph, text: rtl),
        ]
        let result = try render(elements: elements, request: renderRequest(paper: .usLetter, formattingLocale: "en-US"), sourceBytes: Data((cjk + emptyParagraphs + rtl).utf8))
        XCTAssertGreaterThanOrEqual(result.pdf.pageCount, 2)
        let extracted = try extractedText(result.pdf.data)
        XCTAssertTrue(extracted.contains("檢查項目已通過。"))
        XCTAssertTrue(extracted.contains("تقرير الموقع AR-42 الحالة ناجح."))
        let logical = try GlobalizedAccessibleDocumentRendererV1.readLogicalText(from: result.pdf.data)
        XCTAssertTrue(logical.contains(cjk))
        XCTAssertTrue(logical.contains(rtl))
        XCTAssertLessThan(try XCTUnwrap(logical.range(of: cjk)).lowerBound, try XCTUnwrap(logical.range(of: rtl)).lowerBound)
        for item in result.pdf.inspection.pages.flatMap({ $0 }) {
            XCTAssertTrue(result.pdf.inspection.contentRect.insetBy(dx: -0.01, dy: -0.01).contains(item.rect), "clipped \(item.role): \(item.rect)")
        }
    }

    func testVisiblePhotoCaptionStatusAndEvidenceRemainInSemanticOrder() throws {
        let fixture = try loadFixture()
        let image = try generatedPNG()
        let imageSHA = KernelCanonicalHashV1.sha256(image)
        let status = "Status: passed"
        let photo = fixture.photo
        let elements = [
            try GlobalizedDocumentElementV1(semanticID: "evidence.heading", role: .heading, text: "Evidence", headingLevel: 2, keepWithNext: true),
            try GlobalizedDocumentElementV1(semanticID: "evidence.status", role: .paragraph, text: status, keepWithNext: true),
            try GlobalizedDocumentElementV1(semanticID: photo.semanticID, role: .figure, evidenceID: photo.evidenceID, evidenceSHA256: imageSHA, imageData: image, alternateText: photo.alternateText, alternateTextProvenance: .authoredForSource, maximumImageWidthPoints: 180, maximumImageHeightPoints: 120, keepWithNext: true),
            try GlobalizedDocumentElementV1(semanticID: "evidence.caption", role: .note, text: photo.caption, evidenceID: photo.evidenceID, evidenceSHA256: imageSHA),
            try GlobalizedDocumentElementV1(semanticID: "evidence.link", role: .evidenceLink, text: "Evidence: \(photo.evidenceID)", evidenceID: photo.evidenceID, evidenceSHA256: imageSHA),
        ]
        let result = try render(elements: elements, request: renderRequest(paper: .usLetter, formattingLocale: "en-US"), sourceBytes: Data((status + photo.caption).utf8))
        XCTAssertEqual(result.receipt.orderedSemanticIDs, ["evidence.heading", "evidence.status", photo.semanticID, "evidence.caption", "evidence.link"])
        let extracted = try extractedText(result.pdf.data)
        for value in [status, photo.caption, "Evidence: \(photo.evidenceID)"] { XCTAssertTrue(extracted.contains(value)) }
        XCTAssertEqual(extracted.components(separatedBy: photo.caption).count - 1, 1)
        XCTAssertLessThan(try XCTUnwrap(extracted.range(of: status)).lowerBound, try XCTUnwrap(extracted.range(of: photo.caption)).lowerBound)
        let imageItem = try XCTUnwrap(result.pdf.inspection.pages.flatMap({ $0 }).first { $0.kind == .image && $0.role == photo.semanticID })
        XCTAssertLessThanOrEqual(imageItem.rect.width, 180.01)
        XCTAssertLessThanOrEqual(imageItem.rect.height, 120.01)
    }

    func testInvalidImageDigestAndUnassignedGlyphRejectWithoutClaimingExternalQualification() throws {
        let image = try generatedPNG()
        XCTAssertThrowsError(try GlobalizedDocumentElementV1(
            semanticID: "invalid.figure", role: .figure, text: "Invalid image", evidenceID: "invalid-evidence",
            evidenceSHA256: String(repeating: "0", count: 64), imageData: image, alternateText: "Author supplied alt.",
            alternateTextProvenance: .authoredForSource
        ))
        XCTAssertThrowsError(try render(
            elements: [try .init(semanticID: "invalid.glyph", role: .paragraph, text: "Unsupported \u{0378}")],
            request: renderRequest(paper: .usLetter, formattingLocale: "en-US"), sourceBytes: Data("Unsupported \u{0378}".utf8)
        ))
    }

    func testTamperedReplayReceiptAndControlSeparatedSourcesCannotCollide() throws {
        let request = try renderRequest(paper: .usLetter, formattingLocale: "en-US")
        let source = Data("source framing".utf8)
        let firstElements = [try GlobalizedDocumentElementV1(semanticID: "framing.one", role: .paragraph, text: "A\u{001E}B\u{001F}C")]
        let secondElements = [
            try GlobalizedDocumentElementV1(semanticID: "framing.one", role: .paragraph, text: "A"),
            try GlobalizedDocumentElementV1(semanticID: "framing.two", role: .paragraph, text: "B\u{001F}C"),
        ]
        let first = try render(elements: firstElements, request: request, sourceBytes: source)
        let second = try render(elements: secondElements, request: request, sourceBytes: source)
        XCTAssertNotEqual(first.receipt.sourceContentSHA256, second.receipt.sourceContentSHA256)
        XCTAssertNotEqual(first.receipt.orderedSemanticIDs, second.receipt.orderedSemanticIDs)

        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(first.receipt)) as? [String: Any])
        object["outputSHA256"] = String(repeating: "f", count: 64)
        let tampered = try JSONDecoder().decode(GlobalizedDocumentRenderReceiptV1.self, from: JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
        XCTAssertThrowsError(try GlobalizedAccessibleDocumentRendererV1().render(
            elements: firstElements, sourceSHA256: KernelCanonicalHashV1.sha256(source), sourceCreatedAt: sourceCreatedAt,
            request: request, expectedReplay: tampered
        ))
    }
    func testSemanticTableIDTreeResolvesNativeHeaderAndCellDictionaries() throws {
        let elements = [
            try GlobalizedDocumentElementV1(semanticID: "table.root", role: .table),
            try GlobalizedDocumentElementV1(semanticID: "table.row.1", role: .tableRow, parentSemanticID: "table.root"),
            try GlobalizedDocumentElementV1(semanticID: "table.header", role: .tableHeader, text: "Reading", parentSemanticID: "table.row.1", tableHeaderScope: .column),
            try GlobalizedDocumentElementV1(semanticID: "table.header.more", role: .tableHeader, text: "Units", parentSemanticID: "table.row.1", tableHeaderScope: .column),
            try GlobalizedDocumentElementV1(semanticID: "table.cell.reading", role: .tableCell, text: "42", parentSemanticID: "table.row.1", tableHeaderSemanticIDs: ["table.header", "table.header.more"]),
        ]
        let result = try render(elements: elements, request: renderRequest(paper: .usLetter, formattingLocale: "en-US"), sourceBytes: Data("Reading42".utf8))
        let provider = try XCTUnwrap(CGDataProvider(data: result.pdf.data as CFData))
        let document = try XCTUnwrap(CGPDFDocument(provider))
        let catalog = try XCTUnwrap(document.catalog)
        let structure = try XCTUnwrap(pdfDictionary(catalog, key: "StructTreeRoot"))
        let idTree = try XCTUnwrap(pdfDictionary(structure, key: "IDTree"))
        let names = try XCTUnwrap(pdfArray(idTree, key: "Names"))
        let resolved = try resolvedIDTreeNames(names)
        let expectedIDs = ["table.cell.reading", "table.header", "table.header.more"]
        XCTAssertEqual(resolved.map(\.identifier), expectedIDs.sorted { Array($0.utf16).lexicographicallyPrecedes(Array($1.utf16)) })
        let byID = Dictionary(uniqueKeysWithValues: resolved.map { ($0.identifier, $0.node) })
        for semanticID in expectedIDs {
            let node = try XCTUnwrap(byID[semanticID])
            XCTAssertEqual(pdfString(node, key: "ID"), semanticID)
            XCTAssertEqual(pdfString(node, key: "T"), semanticID)
        }
    }
    func testDirectionalControlsPreserveOuterActualTextWhileInspectionUsesVisibleMarkers() throws {
        let source = "abc\u{202E}123\u{200F}"
        let result = try render(
            elements: [try .init(semanticID: "bidi.controls", role: .paragraph, text: source)],
            request: renderRequest(paper: .usLetter, formattingLocale: "en-US"), sourceBytes: Data(source.utf8)
        )
        let logical = try GlobalizedAccessibleDocumentRendererV1.readLogicalText(from: result.pdf.data)
        XCTAssertEqual(Data(logical.utf8), Data(source.utf8))
        let display = try XCTUnwrap(result.pdf.inspection.pages.flatMap({ $0 })
            .first { $0.role == "bidi.controls" }?.text)
        XCTAssertTrue(display.contains("[U+202E]"))
        XCTAssertTrue(display.contains("[U+200F]"))
    }

    func testWeakPrefixArabicUsesRTLSelectionGeometryAndExactLogicalText() throws {
        let source = "123 — تقرير"
        let result = try render(
            elements: [try .init(semanticID: "rtl.weak-prefix", role: .paragraph, text: source)],
            request: renderRequest(paper: .usLetter, formattingLocale: "en-US"), sourceBytes: Data(source.utf8)
        )
        XCTAssertEqual(Data((try GlobalizedAccessibleDocumentRendererV1.readLogicalText(from: result.pdf.data)).utf8), Data(source.utf8))
        let document = try XCTUnwrap(PDFDocument(data: result.pdf.data))
        let page = try XCTUnwrap(document.page(at: 0))
        let selection = try XCTUnwrap(document.findString("تقرير", withOptions: []).first { $0.pages.contains(page) })
        XCTAssertGreaterThan(selection.bounds(for: page).midX, result.pdf.inspection.contentRect.midX)
    }

    func testToUnicodeCMapValidationAcceptsAdobeFormsAndRejectsMalformedTokens() throws {
        XCTAssertTrue(try GlobalizedToUnicodeCMapV1.isValid(Data(validToUnicodeCMap.utf8)))
        let procedural = validToUnicodeCMap.replacingOccurrences(
            of: "/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def",
            with: "/CIDSystemInfo 3 dict dup begin /Registry (Adobe) def /Ordering (UCS) def /Supplement 0 def end def"
        )
        XCTAssertTrue(try GlobalizedToUnicodeCMapV1.isValid(Data(procedural.utf8)))
        for suffix in ["[", "<<", "bogusoperator", "begincmap endcmap"] {
            assertInvalidCMap(Data((validToUnicodeCMap + "\n" + suffix).utf8), suffix)
        }
        let emojiPair = validToUnicodeCMap
            .replacingOccurrences(of: "1 beginbfchar\n<0000> <0020>", with: "2 beginbfchar\n<0000> <0020>\n<0003> <D83DDE00>")
        XCTAssertTrue(try GlobalizedToUnicodeCMapV1.isValid(Data(emojiPair.utf8)))
        let brokenCIDProperties = validToUnicodeCMap.replacingOccurrences(of: "/Supplement 0 >> def", with: "/Supplement 0 >>")
        let brokenBfRangeArray = validToUnicodeCMap.replacingOccurrences(of: "<0001> <0002> <0041>", with: "<0001> <0002> [ <0041> <0042>")
        let unknownProperty = validToUnicodeCMap.replacingOccurrences(of: "endcmap", with: "/BogusName pop def\nendcmap")
        let externalUseCMap = validToUnicodeCMap.replacingOccurrences(of: "endcmap", with: "/External usecmap\nendcmap")
        let invalidSurrogate = validToUnicodeCMap.replacingOccurrences(of: "<0001> <0002> <0041>", with: "<0001> <0002> <D800>")
        let crossingSurrogateRange = validToUnicodeCMap.replacingOccurrences(of: "<0001> <0002> <0041>", with: "<0001> <0002> <D7FF>")
        assertInvalidCMap(Data(brokenCIDProperties.utf8), "broken CID properties")
        assertInvalidCMap(Data(brokenBfRangeArray.utf8), "broken bfrange array")
        assertInvalidCMap(Data(unknownProperty.utf8), "unknown property")
        assertInvalidCMap(Data(externalUseCMap.utf8), "external usecmap")
        assertInvalidCMap(Data(invalidSurrogate.utf8), "invalid surrogate target")
        assertInvalidCMap(Data(crossingSurrogateRange.utf8), "range crossing surrogate")
    }

    private func assertInvalidCMap(_ data: Data, _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        do {
            XCTAssertFalse(try GlobalizedToUnicodeCMapV1.isValid(data), label, file: file, line: line)
        } catch {
            // Invalid tokenization may be reported as a validation failure; it must never pass.
        }
    }

    private let validToUnicodeCMap = """
    /CIDInit /ProcSet findresource begin
    12 dict begin
    begincmap
    /CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def
    /CMapName /Adobe-Identity-UCS def
    /CMapType 2 def
    1 begincodespacerange
    <0000> <FFFF>
    endcodespacerange
    1 beginbfchar
    <0000> <0020>
    endbfchar
    1 beginbfrange
    <0001> <0002> <0041>
    endbfrange
    endcmap
    CMapName currentdict /CMap defineresource pop
    end
    end
    """
    private let sourceCreatedAt = Date(timeIntervalSince1970: 1_800_000_000)

    private func render(elements: [GlobalizedDocumentElementV1], request: GlobalizedDocumentRenderRequestV1, sourceBytes: Data) throws -> GlobalizedDocumentRenderResultV1 {
        try GlobalizedAccessibleDocumentRendererV1().render(elements: elements, sourceSHA256: KernelCanonicalHashV1.sha256(sourceBytes), sourceCreatedAt: sourceCreatedAt, request: request)
    }

    private func renderRequest(paper: LocalePaperSizeV1, formattingLocale: String) throws -> GlobalizedDocumentRenderRequestV1 {
        try .init(language: .init(requestedLanguage: .english, effectiveLanguage: .english, fallback: .exact), formatting: formattingProfile(formattingLocale), paperSize: paper)
    }

    private func formattingProfile(_ locale: String) throws -> FormattingLocaleProfileV1 {
        try .init(localeIdentifier: locale, ianaTimeZoneIdentifier: "UTC", calendar: .gregorian, numberingSystem: .latin, units: .metric)
    }

    private func extractedText(_ data: Data) throws -> String {
        let document = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertGreaterThan(document.pageCount, 0)
        return (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n")
    }

    private func assertMediaBox(_ data: Data, width: CGFloat, height: CGFloat, file: StaticString = #filePath, line: UInt = #line) throws {
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData), file: file, line: line)
        let document = try XCTUnwrap(CGPDFDocument(provider), file: file, line: line)
        let page = try XCTUnwrap(document.page(at: 1), file: file, line: line)
        let box = page.getBoxRect(.mediaBox)
        XCTAssertEqual(box.width, width, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(box.height, height, accuracy: 0.01, file: file, line: line)
    }

    private func pdfDictionary(_ dictionary: CGPDFDictionaryRef, key: String) -> CGPDFDictionaryRef? {
        var value: CGPDFDictionaryRef?
        return key.withCString { CGPDFDictionaryGetDictionary(dictionary, $0, &value) } ? value : nil
    }

    private func pdfArray(_ dictionary: CGPDFDictionaryRef, key: String) -> CGPDFArrayRef? {
        var value: CGPDFArrayRef?
        return key.withCString { CGPDFDictionaryGetArray(dictionary, $0, &value) } ? value : nil
    }

    private func pdfString(_ dictionary: CGPDFDictionaryRef, key: String) -> String? {
        var value: CGPDFStringRef?
        guard key.withCString({ CGPDFDictionaryGetString(dictionary, $0, &value) }), let value,
              let text = CGPDFStringCopyTextString(value) else { return nil }
        return text as String
    }

    private struct PDFIDTreeEntry {
        let identifier: String
        let node: CGPDFDictionaryRef
    }

    private func resolvedIDTreeNames(_ names: CGPDFArrayRef) throws -> [PDFIDTreeEntry] {
        let count = CGPDFArrayGetCount(names)
        XCTAssertEqual(count % 2, 0)
        var values: [PDFIDTreeEntry] = []
        var seen = Set<String>()
        for index in stride(from: 0, to: count, by: 2) {
            var keyObject: CGPDFObjectRef?
            var valueObject: CGPDFObjectRef?
            guard CGPDFArrayGetObject(names, index, &keyObject),
                  CGPDFArrayGetObject(names, index + 1, &valueObject),
                  let keyObject, let valueObject else { throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed }
            var keyString: CGPDFStringRef?
            var dictionary: CGPDFDictionaryRef?
            guard CGPDFObjectGetValue(keyObject, .string, &keyString), let keyString,
                  let keyText = CGPDFStringCopyTextString(keyString),
                  CGPDFObjectGetValue(valueObject, .dictionary, &dictionary), let dictionary else {
                throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed
            }
            let key = keyText as String
            guard seen.insert(key).inserted else {
                throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed
            }
            values.append(.init(identifier: key, node: dictionary))
        }
        return values
    }
    private func generatedPNG() throws -> Data {
        let width = 2
        let height = 2
        var pixels: [UInt8] = [20, 180, 80, 255, 20, 180, 80, 255, 20, 180, 80, 255, 20, 180, 80, 255]
        let context = try XCTUnwrap(CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func loadFixture() throws -> Fixture {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/V30/Reports/globalized-accessible-document-cases-v1.json")
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }
}

private struct Fixture: Decodable {
    struct Case: Decodable { let id: String; let language: String; let text: String; let utf8ByteCount: Int }
    struct Photo: Decodable { let semanticID: String; let caption: String; let alternateText: String; let evidenceID: String }
    let schemaVersion: Int
    let cardID: String
    let reportLanguages: [String]
    let formattingLocales: [String]
    let paperSizes: [String]
    let cases: [Case]
    let photo: Photo

    func `case`(named id: String) throws -> Case {
        try XCTUnwrap(cases.first { $0.id == id })
    }
}

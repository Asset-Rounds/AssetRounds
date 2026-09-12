import CoreGraphics
import CoreText
import CryptoKit
import Darwin
import Foundation
import ImageIO
import PDFKit

/// Versioned Unicode generation. Existing saved PDFs and the explicitly
/// historical Worklight V1 byte renderer retain their original identity.
struct GlobalizedAccessibleDocumentRendererV1 {
    private static let margin: CGFloat = 42
    private static let footerHeight: CGFloat = 22
    private static let baseFont = "ArialMT"

    func render(
        elements: [GlobalizedDocumentElementV1],
        sourceSHA256: String,
        sourceCreatedAt: Date,
        request: GlobalizedDocumentRenderRequestV1,
        expectedReplay: GlobalizedDocumentRenderReceiptV1? = nil
    ) throws -> GlobalizedDocumentRenderResultV1 {
        guard KernelCanonicalHashV1.validSHA256(sourceSHA256), !elements.isEmpty, elements.count <= 10_000 else {
            throw GlobalizedAccessibleDocumentFailureV1.invalidRequest
        }
        try request.validate()
        try expectedReplay?.validate()
        let semantics = elements.map(GlobalizedDocumentSemanticRecordV1.init)
        try GlobalizedDocumentSemanticRecordV1.validateOrder(semantics)
        try validateEvidenceAssociations(elements)
        let sourceMilliseconds = try milliseconds(sourceCreatedAt)
        let layout = try LocaleFormattingServiceV1(profile: request.formatting).paperLayout(request.paperSize)
        let page = CGRect(x: 0, y: 0, width: layout.widthPoints, height: layout.heightPoints)
        let content = page.insetBy(dx: Self.margin, dy: Self.margin + Self.footerHeight)
        guard content.width > 100, content.height > 100 else { throw GlobalizedAccessibleDocumentFailureV1.paginationFailed }
        let sourceContentSHA256 = try GlobalizedDocumentCanonicalV1.sourceContentDigest(elements)
        let environment = try operatingSystemBuild()
        let language = request.language.effectiveLanguage.rawValue
        var fonts = Set<GlobalizedDocumentFontProvenanceV1>()
        let fontCache = FontCache()
        // Shape once. The drawing pass uses these exact lines and decoded
        // images, so its font choices cannot diverge from embedded provenance.
        var prepared: [PreparedElement] = []
        for element in elements {
            let size: CGFloat = element.role == .heading ? (element.headingLevel == 1 ? 20 : 15) : 10
            let lines = try element.text.map {
                try shapedLines(text: $0, size: size, width: content.width - 4, language: language, fonts: &fonts, cache: fontCache)
            } ?? []
            let decoded = try element.imageData.map(decode)
            let imageSize = decoded.map {
                fittedImageRect(image: $0,
                    maximumWidth: min(content.width, CGFloat(element.maximumImageWidthPoints ?? Double(content.width))),
                    maximumHeight: min(content.height * 0.55, CGFloat(element.maximumImageHeightPoints ?? 260))).size
            }
            prepared.append(.init(element: element, lines: lines, image: decoded, imageSize: imageSize))
        }
        fonts.insert(try fontProvenance(CTFontCreateWithName(Self.baseFont as CFString, 7, nil), cache: fontCache))
        let fontList = fonts.sorted { ($0.postScriptName, $0.fontFileSHA256, $0.versionName) < ($1.postScriptName, $1.fontFileSHA256, $1.versionName) }
        let embeddedMetadata = GlobalizedDocumentPDFMetadataV1(
            rendererID: GlobalizedDocumentRenderReceiptV1.rendererID, rendererVersion: GlobalizedDocumentRenderReceiptV1.rendererVersion,
            sourceSHA256: sourceSHA256, sourceCreatedAtMilliseconds: sourceMilliseconds,
            sourceContentSHA256: sourceContentSHA256, paper: layout, language: request.language, formatting: request.formatting,
            orderedSemanticIDs: elements.map(\.semanticID), semantics: semantics,
            fonts: fontList, operatingSystemBuild: environment, sourceTextFormattingApplied: false
        )
        let keyword = try embeddedMetadata.encodedKeyword()
        var inspections: [[PDFRenderInspectionItemV1]] = []
        let pageItems = PageInspection()
        var pageNumber = 0
        let output = NSMutableData()
        var mediaBox = page
        let metadata: [CFString: Any] = [
            kCGPDFContextCreator: GlobalizedDocumentRenderReceiptV1.rendererID,
            kCGPDFContextTitle: "Source-bound globalized document",
            kCGPDFContextKeywords: keyword
        ]
        guard let consumer = CGDataConsumer(data: output as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, metadata as CFDictionary) else {
            throw GlobalizedAccessibleDocumentFailureV1.missingResource
        }
        func startPage() {
            if pageNumber > 0 { inspections.append(pageItems.items); pageItems.items.removeAll(keepingCapacity: true) }
            pageNumber += 1; pageItems.cursor = content.maxY
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(page)
        }
        func finishPage() {
            let footer = "Source SHA-256: \(sourceSHA256) | Page \(pageNumber)"
            // Running furniture is excluded from source reading order.
            CGPDFContextBeginTag(context, .nonStructure, [CGPDFTagProperty.actualText: ""] as CFDictionary)
            drawFooter(footer, rect: CGRect(x: content.minX, y: Self.margin, width: content.width, height: Self.footerHeight), context: context)
            CGPDFContextEndTag(context)
            context.endPDFPage()
        }
        CGPDFContextBeginTag(context, .document, [CGPDFTagProperty.languageText: language] as CFDictionary)
        startPage()
        var openElements: [String] = []
        for (index, item) in prepared.enumerated() {
            let element = item.element
            let parentCount: Int
            if let parent = element.parentSemanticID, let parentIndex = openElements.firstIndex(of: parent) { parentCount = parentIndex + 1 }
            else { parentCount = 0 }
            while openElements.count > parentCount { CGPDFContextEndTag(context); openElements.removeLast() }
            let followingHeight = element.keepWithNext && index + 1 < prepared.count ? prepared[index + 1].firstPartHeight : 0
            let keepHeight = min(item.totalHeight, content.height) + followingHeight
            if keepHeight <= content.height, pageItems.cursor - keepHeight < content.minY { finishPage(); startPage() }
            var properties: [CGPDFTagProperty: Any] = [.titleText: element.semanticID, .languageText: language]
            if let text = element.text { properties[.actualText] = text }
            if let alternateText = element.alternateText { properties[.alternativeText] = alternateText }
            CGPDFContextBeginTag(context, element.decorative ? .nonStructure : tagType(for: element.role, headingLevel: element.headingLevel), properties as CFDictionary)
            openElements.append(element.semanticID)
            if let image = item.image, let imageSize = item.imageSize {
                if pageItems.cursor - imageSize.height < content.minY { finishPage(); startPage() }
                let rect = CGRect(x: content.minX, y: pageItems.cursor - imageSize.height, width: imageSize.width, height: imageSize.height)
                context.draw(image, in: rect)
                pageItems.items.append(.init(kind: .image, role: element.semanticID, rect: rect, text: element.alternateText, fontName: nil, fontSize: nil, lineHeight: nil, evidenceID: element.evidenceID.flatMap(UUID.init(uuidString:))))
                pageItems.cursor = rect.minY - 8
            }
            try draw(lines: item.lines, element: element, content: content, context: context, pageItems: pageItems, startPage: { finishPage(); startPage() })
        }
        while !openElements.isEmpty { CGPDFContextEndTag(context); openElements.removeLast() }
        finishPage(); inspections.append(pageItems.items)
        CGPDFContextEndTag(context); context.closePDF()
        let bytes = try finalizeSemanticPDF(output as Data, elements: elements, language: language, sourceCreatedAt: sourceCreatedAt)
        let digest = KernelCanonicalHashV1.sha256(bytes)
        try verifyPDF(bytes, elements: elements, expectedMetadata: embeddedMetadata)
        let hasColorGlyphs = fontList.contains { $0.embedding == .colorGlyphImages }
        guard hasColorGlyphs == (pageItems.colorGlyphImageRunCount > 0) else { throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed }
        if hasColorGlyphs {
            guard let provider = CGDataProvider(data: bytes as CFData), let native = CGPDFDocument(provider) else { throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed }
            // CoreGraphics may deduplicate repeated glyph images in a resource
            // dictionary. The shaping/drawing pass binds their source; this
            // check observes the resulting nonempty image representation.
            try verifyColorGlyphImageXObjects(in: native, minimumCount: 1)
        }
        let receipt = GlobalizedDocumentRenderReceiptV1(
            rendererID: GlobalizedDocumentRenderReceiptV1.rendererID, rendererVersion: GlobalizedDocumentRenderReceiptV1.rendererVersion,
            sourceSHA256: sourceSHA256, sourceCreatedAtMilliseconds: sourceMilliseconds,
            sourceContentSHA256: sourceContentSHA256, paper: layout, language: request.language, formatting: request.formatting,
            orderedSemanticIDs: elements.map(\.semanticID), fonts: fontList, operatingSystemBuild: environment, outputSHA256: digest,
            outputByteCount: Int64(bytes.count), nativeFontEmbeddingObserved: true,
            nativeToUnicodeObserved: true, nativeColorGlyphImagesObserved: hasColorGlyphs, pendingExternalQualification: true
        )
        try receipt.validate()
        if let expectedReplay, expectedReplay != receipt { throw GlobalizedAccessibleDocumentFailureV1.replayMismatch }
        return .init(pdf: .init(data: bytes, sha256: digest, pageCount: pageNumber, inspection: .init(pageRect: page, contentRect: content, footerRect: CGRect(x: content.minX, y: Self.margin, width: content.width, height: Self.footerHeight), pages: inspections)), receipt: receipt)
    }

    static func readEmbeddedMetadata(from pdf: Data) throws -> GlobalizedDocumentPDFMetadataV1 {
        guard let metadata = try readEmbeddedMetadataIfPresent(from: pdf) else { throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed }
        return metadata
    }

    /// Classification reads decoded PDF attributes, including UTF-16/hex PDF
    /// strings. A malformed current-renderer artifact never becomes "legacy".
    static func readEmbeddedMetadataIfPresent(from pdf: Data) throws -> GlobalizedDocumentPDFMetadataV1? {
        guard let document = PDFDocument(data: pdf) else { throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed }
        let attributes = document.documentAttributes ?? [:]
        let currentCreator = attributes[.creatorAttribute] as? String == GlobalizedDocumentRenderReceiptV1.rendererID
        guard let raw = attributes[.keywordsAttribute] else {
            if currentCreator { throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed }
            return nil
        }
        let values: [String]
        if let value = raw as? String { values = [value] }
        else if let value = raw as? [String] { values = value }
        else { throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed }
        let candidates = values.filter { $0.hasPrefix(GlobalizedDocumentPDFMetadataV1.prefix) }
        if candidates.isEmpty && !currentCreator { return nil }
        guard candidates.count == 1 else { throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed }
        return try GlobalizedDocumentPDFMetadataV1.decodeKeyword(candidates[0])
    }

    /// Extracts source text in the PDF's actual structure-tree order. Soft
    /// wrapping and repeated page furniture never become authored newlines.
    static func readLogicalText(from pdf: Data) throws -> String {
        let metadata = try readEmbeddedMetadata(from: pdf)
        guard let provider = CGDataProvider(data: pdf as CFData), let document = CGPDFDocument(provider) else { throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed }
        let nodes = try GlobalizedPDFStructureReader.read(document)
        guard nodes.map(\.semanticID) == metadata.orderedSemanticIDs else { throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed }
        return nodes.compactMap(\.actualText).joined()
    }

}

private extension GlobalizedAccessibleDocumentRendererV1 {
    final class PageInspection {
        var items: [PDFRenderInspectionItemV1] = []
        var cursor: CGFloat = 0
        var colorGlyphImageRunCount = 0
    }
    final class FontCache {
        var byPath: [String: (digest: String, byteCount: Int)] = [:]
    }
    struct PreparedElement {
        let element: GlobalizedDocumentElementV1
        let lines: [ShapedLine]
        let image: CGImage?
        let imageSize: CGSize?
        var firstPartHeight: CGFloat { imageSize.map { $0.height + 8 } ?? lines.first.map { $0.height + 3 } ?? 0 }
        var totalHeight: CGFloat { (imageSize.map { $0.height + 8 } ?? 0) + lines.reduce(0) { $0 + $1.height + 3 } }
    }
    struct ShapedLine {
        let line: CTLine
        let source: String
        let fullSource: NSString
        let height: CGFloat
        let ascent: CGFloat
        let fontName: String
        let fontSize: CGFloat
        let rightToLeft: Bool
    }

    func shapedLines(text: String, size: CGFloat, width: CGFloat, language: String, fonts: inout Set<GlobalizedDocumentFontProvenanceV1>, cache: FontCache) throws -> [ShapedLine] {
        let base = CTFontCreateWithName(Self.baseFont as CFString, size, nil)
        var direction = CTWritingDirection.natural
        var alignment = CTTextAlignment.natural
        let paragraph = withUnsafePointer(to: &direction) { directionPointer in
            withUnsafePointer(to: &alignment) { alignmentPointer in
                let settings = [
                    CTParagraphStyleSetting(spec: .baseWritingDirection, valueSize: MemoryLayout<CTWritingDirection>.size, value: directionPointer),
                    CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: alignmentPointer)
                ]
                return CTParagraphStyleCreate(settings, settings.count)
            }
        }
        // Each element owns its text layout. Reveal hostile directional
        // controls, and let CoreText shape natural paragraphs without adding
        // invisible control characters to the document's source text.
        let display = BidirectionalTextSafetyV1.visibleControls(text)
        let attributed = NSAttributedString(string: display, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): base,
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraph,
            NSAttributedString.Key(kCTLanguageAttributeName as String): language,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)
        ])
        let typesetter = CTTypesetterCreateWithAttributedString(attributed)
        let string = display as NSString
        var location = 0
        var result: [ShapedLine] = []
        var endsWithSeparator = false
        while location < string.length {
            if paragraphSeparator(string.character(at: location)) {
                result.append(emptyLine(size: size))
                if string.character(at: location) == 13, location + 1 < string.length, string.character(at: location + 1) == 10 { location += 1 }
                location += 1; endsWithSeparator = true
                continue
            }
            var paragraphEnd = location
            while paragraphEnd < string.length, !paragraphSeparator(string.character(at: paragraphEnd)) { paragraphEnd += 1 }
            let rightToLeft = try paragraphIsRightToLeft(attributed, range: NSRange(location: location, length: paragraphEnd - location))
            while location < paragraphEnd {
                let suggested = CTTypesetterSuggestLineBreak(typesetter, location, Double(width))
                guard suggested > 0 else { throw GlobalizedAccessibleDocumentFailureV1.paginationFailed }
                let end = composedBoundary(in: string, from: location, proposedEnd: min(location + suggested, paragraphEnd))
                guard end > location else { throw GlobalizedAccessibleDocumentFailureV1.paginationFailed }
                let line = CTTypesetterCreateLine(typesetter, CFRange(location: location, length: end - location))
                try qualifyRuns(line, source: string, fonts: &fonts, cache: cache)
                var ascent: CGFloat = 0; var descent: CGFloat = 0; var leading: CGFloat = 0
                let lineWidth = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
                guard lineWidth.isFinite, ascent.isFinite, descent.isFinite, leading.isFinite,
                      lineWidth - CTLineGetTrailingWhitespaceWidth(line) <= Double(width) + 0.01 else { throw GlobalizedAccessibleDocumentFailureV1.paginationFailed }
                let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
                let names = Set(runs.compactMap { (CTRunGetAttributes($0) as NSDictionary)[kCTFontAttributeName] as? CTFont }.map { CTFontCopyPostScriptName($0) as String }).sorted().joined(separator: ",")
                result.append(.init(line: line, source: string.substring(with: NSRange(location: location, length: end - location)), fullSource: string, height: max(ceil(ascent + descent + max(0, leading) + 4), size * 1.25), ascent: ascent, fontName: names, fontSize: size, rightToLeft: rightToLeft))
                location = end
            }
            endsWithSeparator = false
            if location < string.length {
                if string.character(at: location) == 13, location + 1 < string.length, string.character(at: location + 1) == 10 { location += 1 }
                location += 1; endsWithSeparator = true
            }
        }
        if endsWithSeparator { result.append(emptyLine(size: size)) }
        return result.isEmpty ? [emptyLine(size: size)] : result
    }

    /// Ask CoreText for natural paragraph alignment in a deliberately wider
    /// frame. A weak leading digit run cannot override the first strong
    /// Arabic/Hebrew character's paragraph direction. This uses the same
    /// native bidi algorithm and paragraph attributes as the drawing pass.
    func paragraphIsRightToLeft(_ text: NSAttributedString, range: NSRange) throws -> Bool {
        let paragraph = text.attributedSubstring(from: range)
        let measured = CTLineCreateWithAttributedString(paragraph)
        let width = CTLineGetTypographicBounds(measured, nil, nil, nil) + 128
        guard width.isFinite, width > 0, width < 100_000_000 else { throw GlobalizedAccessibleDocumentFailureV1.paginationFailed }
        let framesetter = CTFramesetterCreateWithAttributedString(paragraph)
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: width, height: 1_024), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: paragraph.length), path, nil)
        guard CFArrayGetCount(CTFrameGetLines(frame)) > 0 else { throw GlobalizedAccessibleDocumentFailureV1.paginationFailed }
        var origin = CGPoint.zero
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 1), &origin)
        return origin.x > 1
    }

    func paragraphSeparator(_ codeUnit: UInt16) -> Bool {
        [10, 11, 12, 13, 0x85, 0x2028, 0x2029].contains(codeUnit)
    }

    func emptyLine(size: CGFloat) -> ShapedLine {
        let font = CTFontCreateWithName(Self.baseFont as CFString, size, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: " ", attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
        return .init(line: line, source: "", fullSource: " " as NSString, height: size * 1.25, ascent: CTFontGetAscent(font), fontName: Self.baseFont, fontSize: size, rightToLeft: false)
    }

    func composedBoundary(in value: NSString, from start: Int, proposedEnd: Int) -> Int {
        guard proposedEnd < value.length else { return value.length }
        let range = value.rangeOfComposedCharacterSequence(at: max(start, proposedEnd - 1))
        return NSMaxRange(range) > proposedEnd ? range.location : proposedEnd
    }

    func draw(lines: [ShapedLine], element: GlobalizedDocumentElementV1, content: CGRect, context: CGContext, pageItems: PageInspection, startPage: () -> Void) throws {
        for line in lines {
            guard line.height + 3 <= content.height else { throw GlobalizedAccessibleDocumentFailureV1.paginationFailed }
            if pageItems.cursor - line.height < content.minY { startPage() }
            let rect = CGRect(x: content.minX, y: pageItems.cursor - line.height, width: content.width, height: line.height)
            let offset = CTLineGetPenOffsetForFlush(line.line, line.rightToLeft ? 1 : 0, Double(content.width - 4))
            context.saveGState(); context.textMatrix = .identity
            context.textPosition = CGPoint(x: rect.minX + 2 + CGFloat(offset), y: rect.maxY - line.ascent - 2)
            let rendered = try GlobalizedColorGlyphPDFSupportV1.draw(line: line.line, source: line.fullSource, baseline: context.textPosition, context: context)
            pageItems.colorGlyphImageRunCount += rendered.colorGlyphImageRunCount
            context.restoreGState()
            pageItems.items.append(.init(kind: .text, role: element.semanticID, rect: rect, text: line.source, fontName: line.fontName, fontSize: line.fontSize, lineHeight: line.height, evidenceID: element.evidenceID.flatMap(UUID.init(uuidString:))))
            pageItems.cursor = rect.minY - 3
        }
    }

    func drawFooter(_ value: String, rect: CGRect, context: CGContext) {
        let font = CTFontCreateWithName(Self.baseFont as CFString, 7, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: value, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
        context.saveGState(); context.textMatrix = .identity; context.textPosition = CGPoint(x: rect.minX, y: rect.minY + 6); CTLineDraw(line, context); context.restoreGState()
    }

    func qualifyRuns(_ line: CTLine, source: NSString, fonts: inout Set<GlobalizedDocumentFontProvenanceV1>, cache: FontCache) throws {
        guard let runs = CTLineGetGlyphRuns(line) as? [CTRun], !runs.isEmpty else { throw GlobalizedAccessibleDocumentFailureV1.unsupportedGlyph }
        let bridge = source
        for run in runs {
            let attributes = CTRunGetAttributes(run) as NSDictionary
            guard let font = attributes[kCTFontAttributeName] as? CTFont else { throw GlobalizedAccessibleDocumentFailureV1.fontNotQualified }
            let postScript = CTFontCopyPostScriptName(font) as String
            guard !postScript.lowercased().contains("lastresort") else { throw GlobalizedAccessibleDocumentFailureV1.unsupportedGlyph }
            let range = CTRunGetStringRange(run); let count = CTRunGetGlyphCount(run)
            guard range.location >= 0, range.length >= 0, range.location + range.length <= bridge.length else { throw GlobalizedAccessibleDocumentFailureV1.unsupportedGlyph }
            if count == 0 {
                guard try GlobalizedColorGlyphPDFSupportV1.isUndrawnIgnorableRun(run, source: bridge) else { throw GlobalizedAccessibleDocumentFailureV1.unsupportedGlyph }
                continue
            }
            if count > 0 {
                var glyphs = [CGGlyph](repeating: 0, count: count); CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
                var indices = [CFIndex](repeating: kCFNotFound, count: count); CTRunGetStringIndices(run, CFRange(location: 0, length: 0), &indices)
                for (glyph, index) in zip(glyphs, indices) where glyph == 0 {
                    guard index >= 0, index < bridge.length,
                          let scalar = bridge.substring(from: index).unicodeScalars.first,
                          isIgnorable(scalar) || CharacterSet.whitespacesAndNewlines.contains(scalar) else { throw GlobalizedAccessibleDocumentFailureV1.unsupportedGlyph }
                }
            }
            fonts.insert(try fontProvenance(font, cache: cache))
        }
    }

    func fontProvenance(_ font: CTFont, cache: FontCache) throws -> GlobalizedDocumentFontProvenanceV1 {
        guard let url = CTFontCopyAttribute(font, kCTFontURLAttribute) as? URL, url.isFileURL,
              let size = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]).fileSize,
              try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true, size > 0, size <= 256 * 1_024 * 1_024,
              let table = CTFontCopyTable(font, 0x4F532F32, []) as Data?, table.count >= 10 else { throw GlobalizedAccessibleDocumentFailureV1.fontNotQualified }
        let fsType = UInt16(table[8]) << 8 | UInt16(table[9])
        let embedding = GlobalizedColorGlyphPDFSupportV1.embedding(for: font)
        let restricted: UInt16 = 0x0002, noSubsetting: UInt16 = 0x0100, bitmapOnly: UInt16 = 0x0200
        guard fsType & restricted == 0, embedding == .colorGlyphImages || (fsType & bitmapOnly == 0 && fsType & noSubsetting == 0) else { throw GlobalizedAccessibleDocumentFailureV1.fontNotQualified }
        let file: (digest: String, byteCount: Int)
        if let cached = cache.byPath[url.path] { file = cached }
        else {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            guard data.count == size else { throw GlobalizedAccessibleDocumentFailureV1.fontNotQualified }
            file = (KernelCanonicalHashV1.sha256(data), data.count)
            cache.byPath[url.path] = file
        }
        guard file.byteCount == size else { throw GlobalizedAccessibleDocumentFailureV1.fontNotQualified }
        guard let version = CTFontCopyName(font, kCTFontVersionNameKey) as String?, !version.isEmpty else { throw GlobalizedAccessibleDocumentFailureV1.fontNotQualified }
        return .init(postScriptName: CTFontCopyPostScriptName(font) as String, versionName: version, fontFileSHA256: file.digest, os2FsType: fsType, fileByteCount: Int64(size), embedding: embedding)
    }

    func decode(_ data: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) == 1,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw GlobalizedAccessibleDocumentFailureV1.missingResource }
        return image
    }

    func validateEvidenceAssociations(_ elements: [GlobalizedDocumentElementV1]) throws {
        for group in elements where group.role == .figure && group.imageData == nil {
            let children = elements.filter { $0.parentSemanticID == group.semanticID && $0.role == .figure }
            guard group.evidenceID == nil, group.evidenceSHA256 == nil, !children.isEmpty,
                  children.allSatisfy({ $0.imageData != nil }) else { throw GlobalizedAccessibleDocumentFailureV1.missingResource }
        }
        var imageEvidence: [String: Set<String>] = [:]
        for element in elements where element.imageData != nil {
            guard let identifier = element.evidenceID, let digest = element.evidenceSHA256 else { throw GlobalizedAccessibleDocumentFailureV1.invalidElement }
            imageEvidence[identifier, default: []].insert(digest)
        }
        for element in elements where element.imageData == nil {
            guard let identifier = element.evidenceID, let digest = element.evidenceSHA256 else { continue }
            if let images = imageEvidence[identifier] {
                guard images.contains(digest) else { throw GlobalizedAccessibleDocumentFailureV1.invalidElement }
            } else if element.role != .evidenceLink {
                // Standalone source evidence links are valid; a visible image
                // caption must bind an actual figure's exact bytes.
                throw GlobalizedAccessibleDocumentFailureV1.missingResource
            }
        }
    }

    func fittedImageRect(image: CGImage, maximumWidth: CGFloat, maximumHeight: CGFloat) -> CGRect {
        let ratio = CGFloat(image.height) / CGFloat(max(1, image.width))
        let height = min(maximumHeight, maximumWidth * ratio)
        return CGRect(x: 0, y: 0, width: min(maximumWidth, height / ratio), height: height)
    }

    func verifyPDF(_ data: Data, elements: [GlobalizedDocumentElementV1], expectedMetadata: GlobalizedDocumentPDFMetadataV1) throws {
        guard let provider = CGDataProvider(data: data as CFData), let native = CGPDFDocument(provider),
              let document = PDFDocument(data: data), document.pageCount > 0,
              document.pageCount == native.numberOfPages,
              try Self.readEmbeddedMetadata(from: data) == expectedMetadata else { throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed }
        let sourceSecond = floor(Double(expectedMetadata.sourceCreatedAtMilliseconds) / 1_000)
        guard let creationDate = document.documentAttributes?[.creationDateAttribute] as? Date,
              let modificationDate = document.documentAttributes?[.modificationDateAttribute] as? Date,
              creationDate.timeIntervalSince1970 == sourceSecond,
              modificationDate.timeIntervalSince1970 == sourceSecond else { throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed }
        try verifyEmbeddedFonts(in: native, expected: expectedMetadata.fonts.filter { $0.embedding == .outlineSubset })
        let actual = try GlobalizedPDFStructureReader.read(native)
        guard actual.map(\.semanticID) == elements.map(\.semanticID) else { throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed }
        for (node, expected) in zip(actual, elements) {
            let expectedText = expected.text
            let expectedAlt = expected.alternateText
            guard node.parentSemanticID == expected.parentSemanticID,
                  node.tag == String(cString: (expected.decorative ? CGPDFTagType.nonStructure : tagType(for: expected.role, headingLevel: expected.headingLevel)).name),
                  node.language == expectedMetadata.language.effectiveLanguage.rawValue,
                  node.actualText.map({ Data($0.utf8) }) == expectedText.map({ Data($0.utf8) }),
                  node.alternateText.map({ Data($0.utf8) }) == expectedAlt.map({ Data($0.utf8) }) else { throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed }
            if expected.role == .tableHeader {
                let scope: String
                switch expected.tableHeaderScope! { case .row: scope = "Row"; case .column: scope = "Column"; case .rowGroup: scope = "RowGroup"; case .columnGroup: scope = "ColumnGroup" }
                guard node.tableScope == scope, node.structureID == expected.semanticID else { throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed }
            }
            if expected.role == .tableCell {
                guard node.tableHeaders == expected.tableHeaderSemanticIDs else { throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed }
            }
        }
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index), let nativePage = native.page(at: index + 1) else { throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed }
            let rect = page.bounds(for: .mediaBox)
            guard abs(rect.width - expectedMetadata.paper.widthPoints) < 0.01,
                  abs(rect.height - expectedMetadata.paper.heightPoints) < 0.01,
                  nativePage.getBoxRect(.mediaBox) == rect,
                  page.string != nil else { throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed }
        }
    }

    func tagType(for role: AccessibleDocumentRoleV1, headingLevel: Int?) -> CGPDFTagType {
        switch role {
        case .document: return .document
        case .section: return .section
        case .heading:
            switch headingLevel ?? 1 { case 1: return .header1; case 2: return .header2; case 3: return .header3; case 4: return .header4; case 5: return .header5; default: return .header6 }
        case .paragraph: return .paragraph
        case .note: return .note
        case .list: return .list
        case .listItem: return .listItem
        case .table: return .table
        case .tableRow: return .tableRow
        case .tableHeader: return .tableHeaderCell
        case .tableCell: return .tableDataCell
        case .figure: return .figure
        case .evidenceLink: return .link
        }
    }

    func milliseconds(_ date: Date) throws -> Int64 {
        let value = (date.timeIntervalSince1970 * 1_000).rounded()
        guard value.isFinite, value >= Double(Int64.min), value < Double(Int64.max) else { throw GlobalizedAccessibleDocumentFailureV1.invalidRequest }
        return Int64(value.rounded())
    }

    func operatingSystemBuild() throws -> String {
        var count = 0
        guard sysctlbyname("kern.osversion", nil, &count, nil, 0) == 0, count > 1, count <= 256 else { throw GlobalizedAccessibleDocumentFailureV1.missingResource }
        var bytes = [CChar](repeating: 0, count: count)
        guard sysctlbyname("kern.osversion", &bytes, &count, nil, 0) == 0 else { throw GlobalizedAccessibleDocumentFailureV1.missingResource }
        return String(cString: bytes)
    }

    func isIgnorable(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.generalCategory == .format || (0xFE00...0xFE0F).contains(scalar.value) || (0xE0100...0xE01EF).contains(scalar.value)
    }
}

/// Normalizes the native Info dates and xref, then adds an incremental
/// semantic revision. Content, font, and image streams remain byte-identical.
/// Unsupported xref/encryption/object-stream forms fail validation.
func finalizeSemanticPDF(_ data: Data, elements: [GlobalizedDocumentElementV1], language: String, sourceCreatedAt: Date) throws -> Data {
    do {
        let normalized = try GlobalizedPDFSemanticPostprocessor.normalizedNativeMetadata(data, sourceCreatedAt: sourceCreatedAt)
        return try GlobalizedPDFSemanticPostprocessor.finalize(normalized, elements: elements, language: language)
    } catch {
        throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed
    }
}

private enum GlobalizedPDFSemanticPostprocessor {
    private struct XrefEntry { let offset: Int; let generation: Int }
    private struct XrefState {
        let entries: [Int: XrefEntry]
        let freeGenerations: [Int: Int]
        let size: Int
        let root: (number: Int, generation: Int)
        let info: (number: Int, generation: Int)?
        let startOffset: Int
        let trailer: GlobalizedPDFDictionary
    }

    /// Canonicalize only the native Info dictionary and classic xref/trailer.
    /// Every content/font/image byte is copied unchanged. Recomputing offsets
    /// avoids assuming that ambient native date strings have a fixed length.
    static func normalizedNativeMetadata(_ data: Data, sourceCreatedAt: Date) throws -> Data {
        guard !data.isEmpty, data.count <= 128 * 1_024 * 1_024 else { throw GlobalizedPDFParseError.malformed }
        let bytes = [UInt8](data)
        let state = try xref(in: bytes)
        guard let infoReference = state.info else { throw GlobalizedPDFParseError.malformed }
        let info = try dictionaryObject(infoReference, state: state, bytes: bytes)
        let seconds = (sourceCreatedAt.timeIntervalSince1970 * 1_000).rounded() / 1_000
        guard seconds.isFinite, seconds >= -62_135_596_800, seconds < 253_402_300_800 else { throw GlobalizedPDFParseError.malformed }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .gmt
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date(timeIntervalSince1970: floor(seconds)))
        guard let year = components.year, let month = components.month, let day = components.day,
              let hour = components.hour, let minute = components.minute, let second = components.second else { throw GlobalizedPDFParseError.malformed }
        func padded(_ value: Int, _ width: Int) -> String {
            let number = String(value); return String(repeating: "0", count: max(0, width - number.count)) + number
        }
        let dateText = "D:" + padded(year, 4) + padded(month, 2) + padded(day, 2) + padded(hour, 2) + padded(minute, 2) + padded(second, 2) + "Z"
        var canonicalInfo = Data("<<\n".utf8)
        for key in info.fields.keys.sorted() where key != "CreationDate" && key != "ModDate" {
            guard let field = info.fields[key] else { throw GlobalizedPDFParseError.malformed }
            canonicalInfo.append(contentsOf: bytes[field.keyRange.lowerBound..<field.value.range.upperBound]); canonicalInfo.append(10)
        }
        canonicalInfo.append(Data(("/CreationDate (" + dateText + ")\n/ModDate (" + dateText + ")\n>>").utf8))
        var output = Data(bytes[..<state.startOffset])
        output.replaceSubrange(info.range, with: canonicalInfo)
        let delta = canonicalInfo.count - info.range.count
        let canonicalXref = output.count
        output.append(Data("xref\n0 \(state.size)\n".utf8))
        let freeIDs = (0..<state.size).filter { state.entries[$0] == nil }
        var nextFree: [Int: Int] = [:]
        for (index, identifier) in freeIDs.enumerated() { nextFree[identifier] = index + 1 < freeIDs.count ? freeIDs[index + 1] : 0 }
        for number in 0..<state.size {
            if let entry = state.entries[number] {
                let offset = entry.offset + (entry.offset > info.range.lowerBound ? delta : 0)
                output.append(Data((padded(offset, 10) + " " + padded(entry.generation, 5) + " n \n").utf8))
            } else {
                guard let generation = state.freeGenerations[number] else { throw GlobalizedPDFParseError.malformed }
                output.append(Data((padded(nextFree[number] ?? 0, 10) + " " + padded(generation, 5) + " f \n").utf8))
            }
        }
        output.append(Data("trailer\n<< /Size \(state.size) /Root \(state.root.number) \(state.root.generation) R /Info \(infoReference.number) \(infoReference.generation) R >>\nstartxref\n\(canonicalXref)\n%%EOF\n".utf8))
        return output
    }

    static func finalize(_ data: Data, elements: [GlobalizedDocumentElementV1], language: String) throws -> Data {
        guard data.count > 0, data.count <= 128 * 1_024 * 1_024,
              !language.isEmpty, language.utf8.count <= 128 else { throw GlobalizedPDFParseError.malformed }
        let bytes = [UInt8](data)
        let state = try xref(in: bytes)
        var byID: [String: GlobalizedDocumentElementV1] = [:]
        for element in elements where element.role == .tableHeader || element.role == .tableCell {
            guard byID.updateValue(element, forKey: element.semanticID) == nil else { throw GlobalizedPDFParseError.malformed }
        }

        let catalog = try dictionaryObject(state.root, state: state, bytes: bytes)
        var replacements: [(number: Int, generation: Int, dictionary: Data)] = []
        var catalogAdditions: [Data] = []
        if let languageField = catalog.fields["Lang"] {
            guard try text(of: languageField.value) == language else { throw GlobalizedPDFParseError.malformed }
        } else { catalogAdditions.append(field("Lang", textString(language))) }
        if let version = catalog.fields["Version"] {
            guard ["1.7", "2.0"].contains(try name(of: version.value)) else { throw GlobalizedPDFParseError.malformed }
        } else { catalogAdditions.append(field("Version", Data("/1.7".utf8))) }
        if let markInfo = catalog.fields["MarkInfo"] {
            guard case let .dictionary(marked) = markInfo.value, let flag = marked.fields["Marked"], try atom(of: flag.value) == "true" else { throw GlobalizedPDFParseError.malformed }
        } else { catalogAdditions.append(field("MarkInfo", Data("<< /Marked true >>".utf8))) }
        if !catalogAdditions.isEmpty {
            replacements.append((state.root.number, state.root.generation, dictionaryData(catalog, appending: catalogAdditions, bytes: bytes)))
        }
        var identifiedElements: [(identifier: String, number: Int, generation: Int)] = []
        var seen = Set<String>()
        for number in state.entries.keys.sorted() {
            guard let entry = state.entries[number] else { continue }
            guard let object = try optionalDictionaryObject((number, entry.generation), state: state, bytes: bytes) else { continue }
            if let type = object.fields["Type"], try name(of: type.value) == "ObjStm" { throw GlobalizedPDFParseError.malformed }
            guard let titleField = object.fields["T"], let identifier = try? text(of: titleField.value),
                  let element = byID[identifier] else { continue }
            let expectedTag = element.role == .tableHeader ? "TH" : "TD"
            guard let structure = object.fields["S"], try name(of: structure.value) == expectedTag else { throw GlobalizedPDFParseError.malformed }
            let attribute: Data
            if element.role == .tableHeader {
                guard let scope = element.tableHeaderScope else { throw GlobalizedPDFParseError.malformed }
                attribute = tableAttribute(scope: scope)
            } else {
                attribute = tableAttribute(headers: element.tableHeaderSemanticIDs)
            }
            let replaced = try decorate(object, semanticID: identifier, attribute: attribute, bytes: bytes)
            replacements.append((number, entry.generation, replaced))
            guard seen.insert(identifier).inserted else { throw GlobalizedPDFParseError.malformed }
            identifiedElements.append((identifier, number, entry.generation))
        }
        guard seen == Set(byID.keys) else { throw GlobalizedPDFParseError.malformed }
        if !identifiedElements.isEmpty {
            guard let rootField = catalog.fields["StructTreeRoot"] else { throw GlobalizedPDFParseError.malformed }
            let structureReference = try reference(at: rootField.value.range.lowerBound, bytes: bytes)
            let structureRoot = try dictionaryObject(structureReference, state: state, bytes: bytes)
            guard structureRoot.fields["IDTree"] == nil else { throw GlobalizedPDFParseError.malformed }
            var names = Data("<< /Names [\n".utf8)
            for item in identifiedElements.sorted(by: { $0.identifier.utf16.lexicographicallyPrecedes($1.identifier.utf16) }) {
                names.append(textString(item.identifier)); names.append(Data(" \(item.number) \(item.generation) R\n".utf8))
            }
            names.append(Data("] >>".utf8))
            replacements.append((structureReference.number, structureReference.generation, dictionaryData(structureRoot, appending: [field("IDTree", names)], bytes: bytes)))
        }
        guard !replacements.isEmpty else { return data }
        return try incrementalRevision(data, replacements: replacements, state: state)
    }

    private static func decorate(_ dictionary: GlobalizedPDFDictionary, semanticID: String, attribute: Data, bytes: [UInt8]) throws -> Data {
        if let identifier = dictionary.fields["ID"] {
            guard try text(of: identifier.value) == semanticID else { throw GlobalizedPDFParseError.malformed }
        }
        var replacement: (Range<Int>, Data)?
        var additions: [Data] = []
        if let existing = dictionary.fields["A"] {
            guard case let .dictionary(attributes) = existing.value else { throw GlobalizedPDFParseError.malformed }
            replacement = (existing.value.range, try mergedAttribute(attributes, required: attribute, bytes: bytes))
        } else {
            additions.append(field("A", attribute))
        }
        if dictionary.fields["ID"] == nil { additions.append(field("ID", textString(semanticID))) }
        return dictionaryData(dictionary, replacing: replacement, appending: additions, bytes: bytes)
    }

    /// Preserve future attributes verbatim. We only add absent Table keys and
    /// reject a conflicting or already-present `/Headers`, whose array syntax
    /// could otherwise conceal a semantic change.
    private static func mergedAttribute(_ dictionary: GlobalizedPDFDictionary, required: Data, bytes: [UInt8]) throws -> Data {
        if let owner = dictionary.fields["O"] { guard try name(of: owner.value) == "Table" else { throw GlobalizedPDFParseError.malformed } }
        if dictionary.fields["Headers"] != nil || dictionary.fields["Scope"] != nil { throw GlobalizedPDFParseError.malformed }
        var additions: [Data] = []
        if dictionary.fields["O"] == nil { additions.append(field("O", Data("/Table".utf8))) }
        // `required` is a complete Table attribute dictionary. Copy just the
        // relationship keys after the mandatory owner, preserving unknown keys.
        let requiredBytes = [UInt8](required)
        var scanner = GlobalizedPDFScanner(requiredBytes)
        let requiredDictionary = try scanner.dictionary()
        for key in ["Scope", "Headers"] {
            if let value = requiredDictionary.fields[key] {
                additions.append(field(key, Data(requiredBytes[value.value.range])))
            }
        }
        return dictionaryData(dictionary, appending: additions, bytes: bytes)
    }

    private static func tableAttribute(scope: AccessibleTableHeaderScopeV1) -> Data {
        let value: String
        switch scope {
        case .row: value = "Row"
        case .column: value = "Column"
        case .rowGroup: value = "RowGroup"
        case .columnGroup: value = "ColumnGroup"
        }
        return Data("<< /O /Table /Scope /\(value) >>".utf8)
    }

    private static func tableAttribute(headers: [String]) -> Data {
        var separated = Data()
        for (index, header) in headers.enumerated() {
            if index > 0 { separated.append(0x20) }
            separated.append(textString(header))
        }
        return Data("<< /O /Table /Headers [ ".utf8) + separated + Data(" ] >>".utf8)
    }

    private static func field(_ name: String, _ value: Data) -> Data { Data("/\(name) ".utf8) + value }

    private static func dictionaryData(_ dictionary: GlobalizedPDFDictionary, replacing: (Range<Int>, Data)? = nil, appending: [Data], bytes: [UInt8]) -> Data {
        var output = Data(bytes[dictionary.range.lowerBound..<dictionary.closingOffset])
        if let replacing {
            output = Data(bytes[dictionary.range.lowerBound..<replacing.0.lowerBound]) + replacing.1
            output.append(contentsOf: bytes[replacing.0.upperBound..<dictionary.closingOffset])
        }
        for addition in appending { output.append(0x0A); output.append(addition) }
        output.append(contentsOf: bytes[dictionary.closingOffset..<dictionary.range.upperBound])
        return output
    }

    private static func incrementalRevision(_ data: Data, replacements: [(number: Int, generation: Int, dictionary: Data)], state: XrefState) throws -> Data {
        let ordered = replacements.sorted { $0.number < $1.number }
        guard Set(ordered.map(\.number)).count == ordered.count else { throw GlobalizedPDFParseError.malformed }
        var output = data
        if output.last != 0x0A && output.last != 0x0D { output.append(0x0A) }
        var offsets: [(Int, Int, Int)] = []
        for item in ordered {
            guard item.number > 0, item.generation >= 0, item.generation <= 65_535 else { throw GlobalizedPDFParseError.malformed }
            offsets.append((item.number, item.generation, output.count))
            output.append(Data("\(item.number) \(item.generation) obj\n".utf8)); output.append(item.dictionary)
            output.append(Data("\nendobj\n".utf8))
        }
        let xrefOffset = output.count
        output.append(Data("xref\n".utf8))
        for (number, generation, offset) in offsets {
            output.append(Data("\(number) 1\n".utf8))
            let offsetText = String(offset), generationText = String(generation)
            output.append(Data((String(repeating: "0", count: 10 - offsetText.count) + offsetText + " " + String(repeating: "0", count: 5 - generationText.count) + generationText + " n \n").utf8))
        }
        let info = state.info.map { " /Info \($0.number) \($0.generation) R" } ?? ""
        output.append(Data("trailer\n<< /Size \(state.size) /Root \(state.root.number) \(state.root.generation) R\(info) /Prev \(state.startOffset) >>\nstartxref\n\(xrefOffset)\n%%EOF\n".utf8))
        return output
    }

    private static func xref(in bytes: [UInt8]) throws -> XrefState {
        guard bytes.count >= 32 else { throw GlobalizedPDFParseError.malformed }
        let marker = Array("startxref".utf8)
        let tailStart = max(0, bytes.count - 8_192)
        guard let markerIndex = (tailStart...(bytes.count - marker.count)).reversed().first(where: { index in
            bytes[index..<(index + marker.count)].elementsEqual(marker)
        }) else { throw GlobalizedPDFParseError.malformed }
        var scanner = GlobalizedPDFScanner(bytes, index: markerIndex)
        guard try scanner.atom() == "startxref", let offset = Int(try scanner.atom()), offset >= 0, offset < markerIndex else { throw GlobalizedPDFParseError.malformed }
        let suffix = bytes[scanner.index...].filter { ![0, 9, 10, 12, 13, 32].contains($0) }
        guard suffix.elementsEqual(Array("%%EOF".utf8)) else { throw GlobalizedPDFParseError.malformed }
        scanner.index = offset
        guard try scanner.atom() == "xref" else { throw GlobalizedPDFParseError.malformed }
        var entries: [Int: XrefEntry] = [:]
        var freeGenerations: [Int: Int] = [:]
        var covered = Set<Int>()
        while true {
            scanner.skipSpace()
            let word = try scanner.atom()
            if word == "trailer" { break }
            guard let first = Int(word), let count = Int(try scanner.atom()), first >= 0, first <= 100_000, count >= 0, count <= 100_000 - first, entries.count + count <= 100_000 else { throw GlobalizedPDFParseError.malformed }
            for index in 0..<count {
                guard let objectOffset = Int(try scanner.atom()), let generation = Int(try scanner.atom()),
                      objectOffset >= 0, generation >= 0, generation <= 65_535 else { throw GlobalizedPDFParseError.malformed }
                guard covered.insert(first + index).inserted else { throw GlobalizedPDFParseError.malformed }
                switch try scanner.atom() {
                case "n":
                    guard objectOffset < offset, entries[first + index] == nil else { throw GlobalizedPDFParseError.malformed }
                    entries[first + index] = XrefEntry(offset: objectOffset, generation: generation)
                case "f": freeGenerations[first + index] = generation
                default: throw GlobalizedPDFParseError.malformed
                }
            }
        }
        let trailer = try scanner.dictionary()
        guard trailer.fields["Prev"] == nil, trailer.fields["XRefStm"] == nil, trailer.fields["Encrypt"] == nil,
              let sizeField = trailer.fields["Size"], let size = Int(try atom(of: sizeField.value)), size > 0,
              let rootField = trailer.fields["Root"], size <= 100_000 else { throw GlobalizedPDFParseError.malformed }
        let root = try reference(at: rootField.value.range.lowerBound, bytes: bytes)
        guard root.number > 0, root.number < size, entries.keys.allSatisfy({ $0 > 0 && $0 < size }) else { throw GlobalizedPDFParseError.malformed }
        guard covered == Set(0..<size), freeGenerations[0] == 65_535 else { throw GlobalizedPDFParseError.malformed }
        let allowed = Set(["Size", "Root", "Info", "ID"])
        guard Set(trailer.fields.keys).isSubset(of: allowed) else { throw GlobalizedPDFParseError.malformed }
        let info = try trailer.fields["Info"].map { try reference(at: $0.value.range.lowerBound, bytes: bytes) }
        return XrefState(entries: entries, freeGenerations: freeGenerations, size: size, root: root, info: info, startOffset: offset, trailer: trailer)
    }

    private static func dictionaryObject(_ reference: (number: Int, generation: Int), state: XrefState, bytes: [UInt8]) throws -> GlobalizedPDFDictionary {
        guard let value = try optionalDictionaryObject(reference, state: state, bytes: bytes) else { throw GlobalizedPDFParseError.malformed }
        return value
    }

    private static func optionalDictionaryObject(_ reference: (number: Int, generation: Int), state: XrefState, bytes: [UInt8]) throws -> GlobalizedPDFDictionary? {
        guard let entry = state.entries[reference.number], entry.generation == reference.generation else { throw GlobalizedPDFParseError.malformed }
        var scanner = GlobalizedPDFScanner(bytes, index: entry.offset)
        guard Int(try scanner.atom()) == reference.number, Int(try scanner.atom()) == reference.generation, try scanner.atom() == "obj" else { throw GlobalizedPDFParseError.malformed }
        scanner.skipSpace()
        guard scanner.index + 1 < bytes.count, bytes[scanner.index] == 60, bytes[scanner.index + 1] == 60 else { return nil }
        return try scanner.dictionary()
    }

    private static func reference(at offset: Int, bytes: [UInt8]) throws -> (number: Int, generation: Int) {
        var scanner = GlobalizedPDFScanner(bytes, index: offset)
        guard let number = Int(try scanner.atom()), let generation = Int(try scanner.atom()), try scanner.atom() == "R" else { throw GlobalizedPDFParseError.malformed }
        return (number, generation)
    }

    private static func name(of value: GlobalizedPDFValue) throws -> String {
        guard case let .name(value, _) = value else { throw GlobalizedPDFParseError.malformed }; return value
    }
    private static func atom(of value: GlobalizedPDFValue) throws -> String {
        guard case let .atom(value, _) = value else { throw GlobalizedPDFParseError.malformed }; return value
    }
    private static func text(of value: GlobalizedPDFValue) throws -> String {
        guard case let .string(value, _) = value else { throw GlobalizedPDFParseError.malformed }
        if value.starts(with: [0xFE, 0xFF]) {
            guard (value.count - 2).isMultiple(of: 2) else { throw GlobalizedPDFParseError.malformed }
            let units = stride(from: 2, to: value.count, by: 2).map { UInt16(value[$0]) << 8 | UInt16(value[$0 + 1]) }
            return String(decoding: units, as: UTF16.self)
        }
        return String(decoding: value, as: UTF8.self)
    }
    private static func textString(_ value: String) -> Data {
        var output = "<FEFF"
        for unit in value.utf16 {
            let hexadecimal = String(unit, radix: 16, uppercase: true)
            output += String(repeating: "0", count: 4 - hexadecimal.count) + hexadecimal
        }
        return Data((output + ">").utf8)
    }
}

private enum GlobalizedPDFParseError: Error { case malformed }

private struct GlobalizedPDFField { let keyRange: Range<Int>; let value: GlobalizedPDFValue }
private struct GlobalizedPDFDictionary { let range: Range<Int>; let closingOffset: Int; let fields: [String: GlobalizedPDFField] }
private indirect enum GlobalizedPDFValue {
    case name(String, Range<Int>), atom(String, Range<Int>), string([UInt8], Range<Int>)
    case dictionary(GlobalizedPDFDictionary), array(Range<Int>)
    var range: Range<Int> {
        switch self { case let .name(_, r), let .atom(_, r), let .string(_, r), let .array(r): return r; case let .dictionary(d): return d.range }
    }
}

private struct GlobalizedPDFScanner {
    let bytes: [UInt8]; var index: Int
    private var nesting = 0
    private var tokens = 0
    init(_ bytes: [UInt8], index: Int = 0) { self.bytes = bytes; self.index = index }
    mutating func skipSpace() { while index < bytes.count { if [0, 9, 10, 12, 13, 32].contains(bytes[index]) { index += 1; continue }; if bytes[index] == 37 { while index < bytes.count && bytes[index] != 10 && bytes[index] != 13 { index += 1 }; continue }; break } }
    mutating func atom() throws -> String { skipSpace(); let start = index; while index < bytes.count && !delimiter(bytes[index]) { index += 1 }; guard index > start, let value = String(bytes: bytes[start..<index], encoding: .ascii) else { throw GlobalizedPDFParseError.malformed }; return value }
    mutating func dictionary() throws -> GlobalizedPDFDictionary {
        nesting += 1; defer { nesting -= 1 }
        guard nesting <= 128 else { throw GlobalizedPDFParseError.malformed }
        skipSpace(); let start = index; guard take(60), take(60) else { throw GlobalizedPDFParseError.malformed }
        var fields: [String: GlobalizedPDFField] = [:]
        while true { skipSpace(); if take(62) { guard take(62) else { throw GlobalizedPDFParseError.malformed }; return .init(range: start..<index, closingOffset: index - 2, fields: fields) }
            let keyStart = index; guard index < bytes.count, bytes[index] == 47 else { throw GlobalizedPDFParseError.malformed }; index += 1; let key = try atom(); let value = try value(); guard fields[key] == nil else { throw GlobalizedPDFParseError.malformed }; fields[key] = .init(keyRange: keyStart..<index, value: value) }
    }
    mutating func value() throws -> GlobalizedPDFValue {
        tokens += 1; nesting += 1; defer { nesting -= 1 }
        guard tokens <= 100_000, nesting <= 128 else { throw GlobalizedPDFParseError.malformed }
        skipSpace(); let start = index; guard index < bytes.count else { throw GlobalizedPDFParseError.malformed }
        if bytes[index] == 60 { if index + 1 < bytes.count && bytes[index + 1] == 60 { return .dictionary(try dictionary()) }; return try hexString() }
        if bytes[index] == 40 { return try literalString() }
        if bytes[index] == 91 { index += 1; while true { skipSpace(); guard index < bytes.count else { throw GlobalizedPDFParseError.malformed }; if bytes[index] == 93 { index += 1; return .array(start..<index) }; _ = try value() } }
        if bytes[index] == 47 { index += 1; let name = try atom(); return .name(name, start..<index) }
        let first = try atom()
        if Int(first) != nil {
            let afterFirst = index; skipSpace()
            if index < bytes.count && !delimiter(bytes[index]) {
                let second = try atom()
                if Int(second) != nil {
                    skipSpace()
                    if index < bytes.count && !delimiter(bytes[index]), try atom() == "R" { return .atom("\(first) \(second) R", start..<index) }
                }
            }
            index = afterFirst
        }
        return .atom(first, start..<index)
    }
    mutating func literalString() throws -> GlobalizedPDFValue {
        let start = index; index += 1; var depth = 1; var result: [UInt8] = []
        while index < bytes.count { let byte = bytes[index]; index += 1
            if byte == 92 { guard index < bytes.count else { throw GlobalizedPDFParseError.malformed }; let escaped = bytes[index]; index += 1; switch escaped { case 110: result.append(10); case 114: result.append(13); case 116: result.append(9); case 98: result.append(8); case 102: result.append(12); case 10: break; case 13: if index < bytes.count && bytes[index] == 10 { index += 1 }; case 48...55: var number = Int(escaped - 48); for _ in 0..<2 where index < bytes.count && (48...55).contains(bytes[index]) { number = number * 8 + Int(bytes[index] - 48); index += 1 }; result.append(UInt8(truncatingIfNeeded: number)); default: result.append(escaped) }; continue }
            if byte == 40 { depth += 1; result.append(byte); continue }; if byte == 41 { depth -= 1; if depth == 0 { return .string(result, start..<index) }; result.append(byte); continue }; result.append(byte) }
        throw GlobalizedPDFParseError.malformed
    }
    mutating func hexString() throws -> GlobalizedPDFValue { let start = index; index += 1; var digits: [UInt8] = []; while index < bytes.count && bytes[index] != 62 { if ![0, 9, 10, 12, 13, 32].contains(bytes[index]) { digits.append(bytes[index]) }; index += 1 }; guard index < bytes.count, take(62), digits.allSatisfy({ hex($0) != nil }) else { throw GlobalizedPDFParseError.malformed }; if digits.count % 2 == 1 { digits.append(48) }; return .string(stride(from: 0, to: digits.count, by: 2).map { hex(digits[$0])! << 4 | hex(digits[$0 + 1])! }, start..<index) }
    mutating func take(_ byte: UInt8) -> Bool { guard index < bytes.count, bytes[index] == byte else { return false }; index += 1; return true }
    private func delimiter(_ byte: UInt8) -> Bool { [0, 9, 10, 12, 13, 32, 37, 40, 41, 60, 62, 91, 93, 123, 125, 47].contains(byte) }
    private func hex(_ byte: UInt8) -> UInt8? { switch byte { case 48...57: return byte - 48; case 65...70: return byte - 55; case 97...102: return byte - 87; default: return nil } }
}


/// Traverses only structure children, never the cyclic parent/page graph.
/// PDF text strings are decoded by CoreGraphics; no binary stream is searched
/// or reinterpreted as UTF-8 to infer accessibility or font properties.
private enum GlobalizedPDFStructureReader {
    struct Node {
        let semanticID: String
        let parentSemanticID: String?
        let tag: String
        let language: String
        let actualText: String?
        let alternateText: String?
        let structureID: String?
        let tableScope: String?
        let tableHeaders: [String]
    }

    static func read(_ document: CGPDFDocument) throws -> [Node] {
        guard let catalog = document.catalog,
              let root = dictionary(catalog, "StructTreeRoot"),
              let documentLanguage = string(catalog, "Lang"), !documentLanguage.isEmpty else { throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed }
        guard let markInfo = dictionary(catalog, "MarkInfo"), ["1.7", "2.0"].contains(name(catalog, "Version") ?? "") else { throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed }
        var marked: CGPDFBoolean = 0
        guard CGPDFDictionaryGetBoolean(markInfo, "Marked", &marked), marked != 0 else { throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed }
        var nodes: [Node] = []
        var identified: [String: CGPDFDictionaryRef] = [:]
        var visited = 0
        func walk(_ object: CGPDFObjectRef, parent: String?, language: String, depth: Int) throws {
            visited += 1
            guard visited <= 100_000, depth <= 256 else { throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed }
            switch CGPDFObjectGetType(object) {
            case .array:
                var value: CGPDFArrayRef?
                guard CGPDFObjectGetValue(object, .array, &value), let array = value, CGPDFArrayGetCount(array) <= 100_000 else { throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed }
                for index in 0..<CGPDFArrayGetCount(array) {
                    var child: CGPDFObjectRef?
                    guard CGPDFArrayGetObject(array, index, &child), let child else { throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed }
                    try walk(child, parent: parent, language: language, depth: depth + 1)
                }
            case .dictionary:
                var value: CGPDFDictionaryRef?
                guard CGPDFObjectGetValue(object, .dictionary, &value), let element = value else { throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed }
                // Marked-content references and object references are leaves.
                if ["MCR", "OBJR"].contains(name(element, "Type") ?? "") { return }
                guard let tag = name(element, "S") else { throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed }
                let currentLanguage = string(element, "Lang") ?? language
                var currentParent = parent
                if let title = string(element, "T") {
                    guard SnapshotProjectionValidationV1.validID(title) else { throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed }
                    let attributes = dictionary(element, "A")
                    let headers = try attributes.map { try strings($0, "Headers") } ?? []
                    nodes.append(.init(semanticID: title, parentSemanticID: parent, tag: tag, language: currentLanguage,
                                       actualText: string(element, "ActualText"), alternateText: string(element, "Alt"),
                                       structureID: string(element, "ID"), tableScope: attributes.flatMap { name($0, "Scope") }, tableHeaders: headers))
                    if let identifier = string(element, "ID") {
                        guard identifier == title, identified.updateValue(element, forKey: identifier) == nil else { throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed }
                    }
                    currentParent = title
                } else if tag != "Document" && tag != "NonStruct" && tag != "Span" {
                    throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed
                }
                var children: CGPDFObjectRef?
                if CGPDFDictionaryGetObject(element, "K", &children), let children { try walk(children, parent: currentParent, language: currentLanguage, depth: depth + 1) }
            case .integer:
                var mcid: CGPDFInteger = -1
                guard CGPDFObjectGetValue(object, .integer, &mcid), mcid >= 0 else { throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed }
            default: throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed
            }
        }
        var children: CGPDFObjectRef?
        guard CGPDFDictionaryGetObject(root, "K", &children), let children else { throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed }
        try walk(children, parent: nil, language: documentLanguage, depth: 0)
        guard !nodes.isEmpty, Set(nodes.map(\.semanticID)).count == nodes.count else { throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed }
        if !identified.isEmpty {
            guard let idTree = dictionary(root, "IDTree") else { throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed }
            var names: CGPDFArrayRef?
            var kids: CGPDFObjectRef?
            guard !CGPDFDictionaryGetObject(idTree, "Kids", &kids),
                  CGPDFDictionaryGetArray(idTree, "Names", &names), let names,
                  CGPDFArrayGetCount(names) == identified.count * 2 else { throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed }
            var previousBytes: Data?
            var keys = Set<String>()
            for index in stride(from: 0, to: CGPDFArrayGetCount(names), by: 2) {
                var key: CGPDFStringRef?
                var target: CGPDFDictionaryRef?
                guard CGPDFArrayGetString(names, index, &key), let key,
                      let decoded = CGPDFStringCopyTextString(key), let pointer = CGPDFStringGetBytePtr(key),
                      CGPDFArrayGetDictionary(names, index + 1, &target), let target else { throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed }
                let raw = Data(bytes: pointer, count: CGPDFStringGetLength(key))
                if let previousBytes, !previousBytes.lexicographicallyPrecedes(raw) { throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed }
                previousBytes = raw
                let identifier = decoded as String
                guard keys.insert(identifier).inserted, identified[identifier] == target,
                      string(target, "ID") == identifier, string(target, "T") == identifier else { throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed }
            }
            guard keys == Set(identified.keys) else { throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed }
        }
        return nodes
    }

    private static func dictionary(_ source: CGPDFDictionaryRef, _ key: String) -> CGPDFDictionaryRef? {
        var value: CGPDFDictionaryRef?
        return CGPDFDictionaryGetDictionary(source, key, &value) ? value : nil
    }
    private static func name(_ source: CGPDFDictionaryRef, _ key: String) -> String? {
        var value: UnsafePointer<CChar>?
        guard CGPDFDictionaryGetName(source, key, &value), let value else { return nil }
        return String(cString: value)
    }
    private static func string(_ source: CGPDFDictionaryRef, _ key: String) -> String? {
        var value: CGPDFStringRef?
        guard CGPDFDictionaryGetString(source, key, &value), let value, let text = CGPDFStringCopyTextString(value) else { return nil }
        return text as String
    }
    private static func strings(_ source: CGPDFDictionaryRef, _ key: String) throws -> [String] {
        var value: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(source, key, &value) else { return [] }
        guard let value, CGPDFArrayGetCount(value) <= 10_000 else { throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed }
        return try (0..<CGPDFArrayGetCount(value)).map { index in
            var entry: CGPDFStringRef?
            guard CGPDFArrayGetString(value, index, &entry), let entry, let text = CGPDFStringCopyTextString(entry) else { throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed }
            return text as String
        }
    }
}

/// Verifies the actual PDF object graph used by the technical receipt.  This
/// deliberately works from Core Graphics PDF objects; metadata and a bytewise
/// search of the serialized PDF are not evidence of embedding.
func verifyEmbeddedFonts(
    in document: CGPDFDocument,
    expected: [GlobalizedDocumentFontProvenanceV1]
) throws {
    guard document.numberOfPages > 0,
          document.numberOfPages <= _V30EmbeddedFontVerifier.maximumPages,
          !expected.isEmpty,
          expected.count <= _V30EmbeddedFontVerifier.maximumExpectedFonts else {
        throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed
    }

    let expectedNames = try Set(expected.map {
        try _V30EmbeddedFontVerifier.canonicalPostScriptName($0.postScriptName)
    })
    guard expectedNames.count == expected.count else {
        throw GlobalizedAccessibleDocumentFailureV1.fontNotQualified
    }

    let verifier = _V30EmbeddedFontVerifier(expectedNames: expectedNames)
    let context = Unmanaged.passUnretained(verifier).toOpaque()
    for pageNumber in 1...document.numberOfPages {
        guard let page = document.page(at: pageNumber) else {
            throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed
        }
        let resources = try verifier.inheritedResources(for: page)
        try verifier.visitResources(resources, depth: 0, context: context)
    }
    if let failure = verifier.failure { throw failure }

    guard verifier.actualNames == expectedNames else {
        throw GlobalizedAccessibleDocumentFailureV1.fontNotQualified
    }
}

private final class _V30EmbeddedFontVerifier {
    static let maximumExpectedFonts = 128
    static let maximumPages = 1_024
    static let maximumResourceDepth = 32
    static let maximumPageTreeDepth = 64
    static let maximumResourceVisits = 8_192
    static let maximumEntriesPerDictionary = 1_024
    static let maximumDescendantFonts = 32
    static let maximumEncodedStreamBytes = 32 * 1_024 * 1_024
    static let maximumDecodedFontBytes = 64 * 1_024 * 1_024
    static let maximumDecodedCMapBytes = 4 * 1_024 * 1_024

    let expectedNames: Set<String>
    var actualNames = Set<String>()
    var resourceVisits = 0
    var callbackDepth = 0
    var failure: Error?

    init(expectedNames: Set<String>) {
        self.expectedNames = expectedNames
    }

    func inheritedResources(for page: CGPDFPage) throws -> CGPDFDictionaryRef {
        guard documentPageCountIsSane(page) else {
            throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed
        }
        var current = CGPDFPageGetDictionary(page)
        for _ in 0..<Self.maximumPageTreeDepth {
            guard let node = current else {
                throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed
            }
            if let resources = Self.dictionary(node, "Resources") {
                return resources
            }
            current = Self.dictionary(node, "Parent")
        }
        throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed
    }

    func visitResources(
        _ resources: CGPDFDictionaryRef,
        depth: Int,
        context: UnsafeMutableRawPointer
    ) throws {
        guard depth <= Self.maximumResourceDepth,
              CGPDFDictionaryGetCount(resources) <= Self.maximumEntriesPerDictionary else {
            throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed
        }
        resourceVisits += 1
        guard resourceVisits <= Self.maximumResourceVisits else {
            throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed
        }

        if let fonts = Self.dictionary(resources, "Font") {
            guard CGPDFDictionaryGetCount(fonts) <= Self.maximumEntriesPerDictionary else {
                throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed
            }
            CGPDFDictionaryApplyFunction(fonts, _v30ConsumeFontResource, context)
            if let failure { throw failure }
        }

        guard let xObjects = Self.dictionary(resources, "XObject") else { return }
        guard CGPDFDictionaryGetCount(xObjects) <= Self.maximumEntriesPerDictionary else {
            throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed
        }
        let savedDepth = callbackDepth
        callbackDepth = depth
        defer { callbackDepth = savedDepth }
        CGPDFDictionaryApplyFunction(xObjects, _v30ConsumeFormXObject, context)
        if let failure { throw failure }
    }

    func consumeFontResource(_ object: CGPDFObjectRef) throws {
        var font: CGPDFDictionaryRef?
        guard CGPDFObjectGetValue(object, .dictionary, &font), let font else {
            throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed
        }
        try inspectFont(font)
    }

    func consumeFormXObject(_ object: CGPDFObjectRef, context: UnsafeMutableRawPointer) throws {
        var xObject: CGPDFStreamRef?
        guard CGPDFObjectGetValue(object, .stream, &xObject), let xObject else {
            throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed
        }
        guard let dictionary = CGPDFStreamGetDictionary(xObject),
              Self.name(dictionary, "Subtype") == "Form" else {
            return
        }
        // A Form XObject may omit Resources when it has no resource references.
        // If it has a resource dictionary, it must be checked recursively.
        if let resources = Self.dictionary(dictionary, "Resources") {
            try visitResources(resources, depth: callbackDepth + 1, context: context)
        }
    }

    func inspectFont(_ font: CGPDFDictionaryRef) throws {
        guard let subtype = Self.name(font, "Subtype") else {
            throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed
        }
        // Type 3 describes glyphs with page content rather than an embedded
        // font-program stream.  It needs its own qualification model, so it is
        // a strict failure here instead of a quiet exemption.
        guard subtype != "Type3" else {
            throw GlobalizedAccessibleDocumentFailureV1.fontNotQualified
        }

        let baseName = try Self.requiredCanonicalName(in: font, key: "BaseFont")
        try inspectToUnicode(in: font)

        if subtype == "Type0" {
            guard let descendants = Self.array(font, "DescendantFonts"),
                  (1...Self.maximumDescendantFonts).contains(CGPDFArrayGetCount(descendants)) else {
                throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed
            }
            for index in 0..<CGPDFArrayGetCount(descendants) {
                var descendant: CGPDFDictionaryRef?
                guard CGPDFArrayGetDictionary(descendants, index, &descendant),
                      let descendant else {
                    throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed
                }
                let descendantBase = try Self.requiredCanonicalName(in: descendant, key: "BaseFont")
                guard descendantBase == baseName,
                      let descriptor = Self.dictionary(descendant, "FontDescriptor"),
                      try Self.requiredCanonicalName(in: descriptor, key: "FontName") == baseName else {
                    throw GlobalizedAccessibleDocumentFailureV1.fontNotQualified
                }
                try inspectEmbeddedProgram(in: descriptor)
            }
        } else {
            guard let descriptor = Self.dictionary(font, "FontDescriptor"),
                  try Self.requiredCanonicalName(in: descriptor, key: "FontName") == baseName else {
                throw GlobalizedAccessibleDocumentFailureV1.fontNotQualified
            }
            try inspectEmbeddedProgram(in: descriptor)
        }

        guard expectedNames.contains(baseName) else {
            throw GlobalizedAccessibleDocumentFailureV1.fontNotQualified
        }
        actualNames.insert(baseName)
    }

    func inspectToUnicode(in font: CGPDFDictionaryRef) throws {
        guard let toUnicode = Self.stream(font, "ToUnicode") else {
            throw GlobalizedAccessibleDocumentFailureV1.fontNotQualified
        }
        let data = try decodedData(
            from: toUnicode,
            maximumDecodedBytes: Self.maximumDecodedCMapBytes
        )
        guard try GlobalizedToUnicodeCMapV1.isValid(data) else {
            throw GlobalizedAccessibleDocumentFailureV1.fontNotQualified
        }
    }

    func inspectEmbeddedProgram(in descriptor: CGPDFDictionaryRef) throws {
        let keys = ["FontFile", "FontFile2", "FontFile3"]
        let candidates = keys.compactMap { key in Self.stream(descriptor, key).map { (key, $0) } }
        guard candidates.count == 1, let (key, stream) = candidates.first else {
            throw GlobalizedAccessibleDocumentFailureV1.fontNotQualified
        }
        let program = try decodedData(
            from: stream,
            maximumDecodedBytes: Self.maximumDecodedFontBytes
        )
        guard Self.isPlausibleFontProgram(program, descriptorKey: key, stream: stream) else {
            throw GlobalizedAccessibleDocumentFailureV1.fontNotQualified
        }
    }

    func decodedData(
        from stream: CGPDFStreamRef,
        maximumDecodedBytes: Int
    ) throws -> Data {
        guard let dictionary = CGPDFStreamGetDictionary(stream),
              let length = Self.integer(dictionary, "Length"),
              length > 0,
              length <= Self.maximumEncodedStreamBytes else {
            throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed
        }
        var format: CGPDFDataFormat = .raw
        guard let copied = CGPDFStreamCopyData(stream, &format) as Data? else {
            throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed
        }
        guard format == .raw,
              !copied.isEmpty,
              copied.count <= maximumDecodedBytes else {
            throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed
        }
        return copied
    }

    static func isPlausibleFontProgram(
        _ data: Data,
        descriptorKey: String,
        stream: CGPDFStreamRef
    ) -> Bool {
        let bytes = [UInt8](data.prefix(16))
        switch descriptorKey {
        case "FontFile":
            return (bytes.count >= 4 && bytes.starts(with: [0x25, 0x21]))
                || (bytes.count >= 6 && bytes[0] == 0x80 && (bytes[1] == 1 || bytes[1] == 2))
        case "FontFile2":
            return bytes.count >= 12
                && (bytes.starts(with: [0x00, 0x01, 0x00, 0x00])
                    || bytes.starts(with: Array("true".utf8))
                    || bytes.starts(with: Array("typ1".utf8)))
        case "FontFile3":
            guard let dictionary = CGPDFStreamGetDictionary(stream),
                  let subtype = name(dictionary, "Subtype") else { return false }
            switch subtype {
            case "Type1", "MMType1":
                return (bytes.count >= 4 && bytes.starts(with: [0x25, 0x21]))
                    || (bytes.count >= 6 && bytes[0] == 0x80 && (bytes[1] == 1 || bytes[1] == 2))
            case "Type1C", "CIDFontType0C":
                return data.count >= 4
                    && data[0] == 1
                    && data[1] <= 1
                    && data[2] >= 4
                    && Int(data[2]) <= data.count
                    && (1...4).contains(Int(data[3]))
            case "OpenType":
                return bytes.starts(with: Array("OTTO".utf8))
                    || bytes.starts(with: [0x00, 0x01, 0x00, 0x00])
                    || bytes.starts(with: Array("ttcf".utf8))
            default:
                return false
            }
        default:
            return false
        }
    }

    static func canonicalPostScriptName(_ value: String) throws -> String {
        let scalars = Array(value.unicodeScalars)
        guard !scalars.isEmpty, scalars.count <= 255,
              scalars.allSatisfy({ $0.value > 0x20 && $0.value < 0x7F }) else {
            throw GlobalizedAccessibleDocumentFailureV1.fontNotQualified
        }
        let prefixCount = 7
        let isSubsetName = scalars.count > prefixCount
            && scalars[6] == "+"
            && scalars.prefix(6).allSatisfy({ $0.value >= 65 && $0.value <= 90 })
        let result = isSubsetName ? String(value.dropFirst(prefixCount)) : value
        guard !result.isEmpty else {
            throw GlobalizedAccessibleDocumentFailureV1.fontNotQualified
        }
        return result
    }

    static func requiredCanonicalName(in dictionary: CGPDFDictionaryRef, key: String) throws -> String {
        guard let name = name(dictionary, key) else {
            throw GlobalizedAccessibleDocumentFailureV1.fontNotQualified
        }
        return try canonicalPostScriptName(name)
    }

    static func dictionary(_ dictionary: CGPDFDictionaryRef, _ key: String) -> CGPDFDictionaryRef? {
        var result: CGPDFDictionaryRef?
        return CGPDFDictionaryGetDictionary(dictionary, key, &result) ? result : nil
    }

    static func array(_ dictionary: CGPDFDictionaryRef, _ key: String) -> CGPDFArrayRef? {
        var result: CGPDFArrayRef?
        return CGPDFDictionaryGetArray(dictionary, key, &result) ? result : nil
    }

    static func stream(_ dictionary: CGPDFDictionaryRef, _ key: String) -> CGPDFStreamRef? {
        var result: CGPDFStreamRef?
        return CGPDFDictionaryGetStream(dictionary, key, &result) ? result : nil
    }

    static func integer(_ dictionary: CGPDFDictionaryRef, _ key: String) -> Int? {
        var result: CGPDFInteger = 0
        return CGPDFDictionaryGetInteger(dictionary, key, &result) ? Int(result) : nil
    }

    static func name(_ dictionary: CGPDFDictionaryRef, _ key: String) -> String? {
        var result: UnsafePointer<CChar>?
        guard CGPDFDictionaryGetName(dictionary, key, &result), let result else { return nil }
        return String(cString: result)
    }

    private func documentPageCountIsSane(_ page: CGPDFPage) -> Bool {
        // The page reference is already owned by the document.  This small
        // guard keeps inherited-resource traversal from becoming an unbounded
        // page-tree walk on a malformed input.
        CGPDFPageGetDictionary(page) != nil
    }
}

private func _v30ConsumeFontResource(
    _ key: UnsafePointer<CChar>,
    _ object: CGPDFObjectRef,
    _ info: UnsafeMutableRawPointer?
) {
    guard let info else { return }
    let verifier = Unmanaged<_V30EmbeddedFontVerifier>.fromOpaque(info).takeUnretainedValue()
    guard verifier.failure == nil else { return }
    do {
        try verifier.consumeFontResource(object)
    } catch {
        verifier.failure = error
    }
}

private func _v30ConsumeFormXObject(
    _ key: UnsafePointer<CChar>,
    _ object: CGPDFObjectRef,
    _ info: UnsafeMutableRawPointer?
) {
    guard let info else { return }
    let verifier = Unmanaged<_V30EmbeddedFontVerifier>.fromOpaque(info).takeUnretainedValue()
    guard verifier.failure == nil else { return }
    do {
        try verifier.consumeFormXObject(object, context: info)
    } catch {
        verifier.failure = error
    }
}


/// Bounded grammar for the Adobe ToUnicode CMaps emitted by Quartz.  It
/// intentionally accepts the documented prolog/property forms and rejects
/// unparsed tokens before or after the one complete CMap body.
enum GlobalizedToUnicodeCMapV1 {
    private enum Token: Equatable {
        case word(String)
        case hex([UInt8])
        case literal
        case arrayStart
        case arrayEnd
        case dictionaryStart
        case dictionaryEnd
    }

    private static let maximumBytes = 4 * 1_024 * 1_024
    private static let maximumTokens = 262_144
    private static let maximumMappings = 131_072

    static func isValid(_ data: Data) throws -> Bool {
        let tokens = try tokenize(data)
        var cursor = Cursor(tokens: tokens)
        guard cursor.consumeWord("/CIDInit"),
              cursor.consumeWord("/ProcSet"),
              cursor.consumeWord("findresource"),
              cursor.consumeWord("begin"),
              let dictionarySize = cursor.consumeUnsignedInteger(), dictionarySize > 0,
              cursor.consumeWord("dict"),
              cursor.consumeWord("begin"),
              try cursor.parseCMapBody(),
              cursor.consumeWord("CMapName"),
              cursor.consumeWord("currentdict"),
              cursor.consumeWord("/CMap"),
              cursor.consumeWord("defineresource"),
              cursor.consumeWord("pop"),
              cursor.consumeWord("end"),
              cursor.consumeWord("end"),
              cursor.isAtEnd else {
            return false
        }
        return true
    }

    private struct Cursor {
        let tokens: [Token]
        var index = 0

        var isAtEnd: Bool { index == tokens.count }

        mutating func consumeWord(_ expected: String) -> Bool {
            guard index < tokens.count, case let .word(value) = tokens[index], value == expected else { return false }
            index += 1
            return true
        }

        mutating func consumeUnsignedInteger() -> Int? {
            guard index < tokens.count, case let .word(value) = tokens[index],
                  !value.isEmpty, value.allSatisfy({ $0.isNumber }), let result = Int(value) else { return nil }
            index += 1
            return result
        }

        mutating func consumeHex() -> [UInt8]? {
            guard index < tokens.count, case let .hex(value) = tokens[index] else { return nil }
            index += 1
            return value
        }

        mutating func consume(_ expected: Token) -> Bool {
            guard index < tokens.count, tokens[index] == expected else { return false }
            index += 1
            return true
        }

        mutating func parseCMapBody() throws -> Bool {
            guard consumeWord("begincmap") else { return false }
            var codeSpaces: [([UInt8], [UInt8])] = []
            var properties = Set<String>()
            var mappings = 0
            var sawCodeSpace = false
            var sawMapping = false

            while index < tokens.count {
                if consumeWord("endcmap") {
                    return sawCodeSpace && sawMapping && properties.isSuperset(of: ["/CIDSystemInfo", "/CMapName", "/CMapType"])
                }
                if index < tokens.count, case let .word(name) = tokens[index], name.hasPrefix("/") {
                    guard properties.insert(name).inserted, try parsePropertyDefinition() else { return false }
                    continue
                }
                guard let count = consumeUnsignedInteger(), count > 0 else { return false }
                if consumeWord("begincodespacerange") {
                    guard count <= 64 else { return false }
                    for _ in 0..<count {
                        guard let lower = consumeHex(), let upper = consumeHex(),
                              lower.count == upper.count, (1...4).contains(lower.count),
                              lower.lexicographicallyPrecedesOrEquals(upper) else { return false }
                        codeSpaces.append((lower, upper))
                    }
                    guard consumeWord("endcodespacerange") else { return false }
                    sawCodeSpace = true
                    continue
                }
                if consumeWord("beginbfchar") {
                    guard count <= 65_536, !codeSpaces.isEmpty else { return false }
                    for _ in 0..<count {
                        guard let source = consumeHex(), let target = consumeHex(),
                              GlobalizedToUnicodeCMapV1.contains(source, in: codeSpaces), GlobalizedToUnicodeCMapV1.isUTF16BE(target) else { return false }
                        mappings += 1
                    }
                    guard consumeWord("endbfchar"), mappings <= GlobalizedToUnicodeCMapV1.maximumMappings else { return false }
                    sawMapping = true
                    continue
                }
                if consumeWord("beginbfrange") {
                    guard count <= 65_536, !codeSpaces.isEmpty else { return false }
                    for _ in 0..<count {
                        guard let lower = consumeHex(), let upper = consumeHex(),
                              lower.count == upper.count,
                              codeSpaces.contains(where: { GlobalizedToUnicodeCMapV1.contains(lower, in: [$0]) && GlobalizedToUnicodeCMapV1.contains(upper, in: [$0]) }),
                              let span = GlobalizedToUnicodeCMapV1.boundedSpan(from: lower, through: upper) else { return false }
                        if let target = consumeHex() {
                            guard mappings <= GlobalizedToUnicodeCMapV1.maximumMappings - span,
                                  GlobalizedToUnicodeCMapV1.validIncrementingTargets(target, count: span) else { return false }
                            mappings += span
                        } else {
                            guard consume(.arrayStart) else { return false }
                            var targets = 0
                            while let target = consumeHex() {
                                guard GlobalizedToUnicodeCMapV1.isUTF16BE(target) else { return false }
                                targets += 1
                                guard targets <= span, mappings <= GlobalizedToUnicodeCMapV1.maximumMappings - targets else { return false }
                            }
                            guard consume(.arrayEnd), targets == span else { return false }
                            mappings += targets
                        }
                    }
                    guard consumeWord("endbfrange"), mappings <= GlobalizedToUnicodeCMapV1.maximumMappings else { return false }
                    sawMapping = true
                    continue
                }
                return false
            }
            return false
        }

        /// Standard Quartz maps use simple `/Name value def` declarations plus
        /// either a direct CIDSystemInfo dictionary or the PostScript `3 dict
        /// dup begin ... end def` spelling.
        mutating func parsePropertyDefinition() throws -> Bool {
            guard index < tokens.count, case let .word(name) = tokens[index], name.hasPrefix("/") else { return false }
            index += 1
            if name == "/CIDSystemInfo" {
                if consume(.dictionaryStart) {
                    var sawRegistry = false, sawOrdering = false, sawSupplement = false
                    while !consume(.dictionaryEnd) {
                        guard index < tokens.count, case let .word(key) = tokens[index], key.hasPrefix("/") else { return false }
                        index += 1
                        switch key {
                        case "/Registry": guard !sawRegistry, consume(.literal) else { return false }; sawRegistry = true
                        case "/Ordering": guard !sawOrdering, consume(.literal) else { return false }; sawOrdering = true
                        case "/Supplement": guard !sawSupplement, consumeUnsignedInteger() != nil else { return false }; sawSupplement = true
                        default: return false
                        }
                    }
                    return sawRegistry && sawOrdering && sawSupplement && consumeWord("def")
                }
                guard consumeUnsignedInteger() == 3,
                      consumeWord("dict"), consumeWord("dup"), consumeWord("begin") else { return false }
                var sawRegistry = false, sawOrdering = false, sawSupplement = false
                while !consumeWord("end") {
                    guard index < tokens.count, case let .word(key) = tokens[index], key.hasPrefix("/") else { return false }
                    index += 1
                    switch key {
                    case "/Registry": guard !sawRegistry, consume(.literal) else { return false }; sawRegistry = true
                    case "/Ordering": guard !sawOrdering, consume(.literal) else { return false }; sawOrdering = true
                    case "/Supplement": guard !sawSupplement, consumeUnsignedInteger() != nil else { return false }; sawSupplement = true
                    default: return false
                    }
                    guard consumeWord("def") else { return false }
                }
                return sawRegistry && sawOrdering && sawSupplement && consumeWord("def")
            }
            switch name {
            case "/CMapName":
                guard index < tokens.count, case let .word(value) = tokens[index], value.hasPrefix("/"), value.count > 1 else { return false }
                index += 1
            case "/CMapType": guard consumeUnsignedInteger() == 2 else { return false }
            case "/WMode": guard let mode = consumeUnsignedInteger(), mode == 0 || mode == 1 else { return false }
            case "/CMapVersion":
                guard index < tokens.count, case let .word(value) = tokens[index],
                      !value.isEmpty, value.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }),
                      let version = Double(value), version.isFinite, version >= 0 else { return false }
                index += 1
            default: return false
            }
            return consumeWord("def")
        }

    }

    private static func isUTF16BE(_ value: [UInt8]) -> Bool {
        guard value.count >= 2, value.count <= 512, value.count.isMultiple(of: 2) else { return false }
        var index = 0
        while index < value.count {
            let unit = UInt16(value[index]) << 8 | UInt16(value[index + 1])
            index += 2
            if (0xD800...0xDBFF).contains(unit) {
                guard index + 1 < value.count else { return false }
                let low = UInt16(value[index]) << 8 | UInt16(value[index + 1])
                guard (0xDC00...0xDFFF).contains(low) else { return false }
                index += 2
            } else if (0xDC00...0xDFFF).contains(unit) { return false }
        }
        return true
    }

    private static func contains(_ value: [UInt8], in spaces: [([UInt8], [UInt8])]) -> Bool {
        spaces.contains { lower, upper in
            value.count == lower.count && !value.lexicographicallyPrecedes(lower) && !upper.lexicographicallyPrecedes(value)
        }
    }

    private static func validIncrementingTargets(_ first: [UInt8], count: Int) -> Bool {
        var value = first
        for step in 0..<count {
            guard isUTF16BE(value) else { return false }
            if step + 1 == count { return true }
            var carry = true
            for position in value.indices.reversed() {
                if value[position] < 255 { value[position] += 1; carry = false; break }
                value[position] = 0
            }
            if carry { return false }
        }
        return false
    }

    private static func boundedSpan(from lower: [UInt8], through upper: [UInt8]) -> Int? {
        guard lower.count == upper.count, lower.count <= 4 else { return nil }
        var start = 0
        var end = 0
        for (left, right) in zip(lower, upper) {
            start = (start << 8) | Int(left)
            end = (end << 8) | Int(right)
        }
        guard end >= start else { return nil }
        let span = end - start + 1
        return span <= maximumMappings ? span : nil
    }

    private static func tokenize(_ data: Data) throws -> [Token] {
        let bytes = [UInt8](data)
        guard !bytes.isEmpty, bytes.count <= maximumBytes else { throw CMapError.malformed }
        var tokens: [Token] = []
        var index = 0
        while index < bytes.count {
            guard tokens.count < maximumTokens else { throw CMapError.malformed }
            if isWhitespace(bytes[index]) { index += 1; continue }
            if bytes[index] == 0x25 { while index < bytes.count, bytes[index] != 0x0A, bytes[index] != 0x0D { index += 1 }; continue }
            if bytes[index] == 0x5B { tokens.append(.arrayStart); index += 1; continue }
            if bytes[index] == 0x5D { tokens.append(.arrayEnd); index += 1; continue }
            if bytes[index] == 0x3C, index + 1 < bytes.count, bytes[index + 1] == 0x3C { tokens.append(.dictionaryStart); index += 2; continue }
            if bytes[index] == 0x3E, index + 1 < bytes.count, bytes[index + 1] == 0x3E { tokens.append(.dictionaryEnd); index += 2; continue }
            if bytes[index] == 0x3C { tokens.append(.hex(try consumeHex(bytes, &index))); continue }
            if bytes[index] == 0x28 { try consumeLiteral(bytes, &index); tokens.append(.literal); continue }
            let start = index
            while index < bytes.count, !isWhitespace(bytes[index]), !isDelimiter(bytes[index]) { index += 1 }
            guard index > start, let word = String(bytes: bytes[start..<index], encoding: .ascii) else { throw CMapError.malformed }
            tokens.append(.word(word))
            guard tokens.count <= maximumTokens else { throw CMapError.malformed }
        }
        return tokens
    }

    private static func consumeHex(_ bytes: [UInt8], _ index: inout Int) throws -> [UInt8] {
        index += 1
        var digits: [UInt8] = []
        while index < bytes.count, bytes[index] != 0x3E {
            if !isWhitespace(bytes[index]) { digits.append(bytes[index]) }
            index += 1
        }
        guard index < bytes.count, !digits.isEmpty, digits.count.isMultiple(of: 2) else { throw CMapError.malformed }
        index += 1
        var result: [UInt8] = []
        for offset in stride(from: 0, to: digits.count, by: 2) {
            guard let high = nibble(digits[offset]), let low = nibble(digits[offset + 1]) else { throw CMapError.malformed }
            result.append((high << 4) | low)
        }
        return result
    }

    private static func consumeLiteral(_ bytes: [UInt8], _ index: inout Int) throws {
        index += 1
        var nesting = 1
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            if byte == 0x5C {
                guard index < bytes.count else { throw CMapError.malformed }
                index += 1
            } else if byte == 0x28 {
                nesting += 1
            } else if byte == 0x29 {
                nesting -= 1
                if nesting == 0 { return }
            }
            guard nesting <= 64 else { throw CMapError.malformed }
        }
        throw CMapError.malformed
    }

    private static func isWhitespace(_ byte: UInt8) -> Bool { [0, 9, 10, 12, 13, 32].contains(byte) }
    private static func isDelimiter(_ byte: UInt8) -> Bool { [0x28, 0x29, 0x3C, 0x3E, 0x5B, 0x5D, 0x7B, 0x7D, 0x25].contains(byte) }
    private static func nibble(_ byte: UInt8) -> UInt8? {
        switch byte { case 48...57: return byte - 48; case 65...70: return byte - 55; case 97...102: return byte - 87; default: return nil }
    }
    private enum CMapError: Error { case malformed }
}

private extension Array where Element == UInt8 {
    func lexicographicallyPrecedesOrEquals(_ other: [UInt8]) -> Bool { !other.lexicographicallyPrecedes(self) }
}

enum GlobalizedColorGlyphPDFSupportV1 {
    struct DrawResult: Equatable, Sendable {
        let outlineRunCount: Int
        let colorGlyphImageRunCount: Int
    }

    static let rasterScale: CGFloat = 3
    static let maximumRunsPerLine = 256
    static let maximumPixelsPerRun = 16 * 1_024 * 1_024
    static let maximumSourceUTF8BytesPerRun = 16 * 1_024

    static func embedding(for font: CTFont) -> GlobalizedDocumentFontEmbeddingV1 {
        CTFontGetSymbolicTraits(font).contains(.traitColorGlyphs)
            ? .colorGlyphImages
            : .outlineSubset
    }

    @discardableResult
    static func draw(
        line: CTLine,
        source: NSString,
        baseline: CGPoint,
        context: CGContext
    ) throws -> DrawResult {
        guard source.length <= 1_048_576,
              let runs = CTLineGetGlyphRuns(line) as? [CTRun],
              !runs.isEmpty,
              runs.count <= maximumRunsPerLine else {
            throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed
        }

        var outlines = 0
        var colorImages = 0
        context.saveGState()
        context.textMatrix = .identity
        context.textPosition = baseline
        defer { context.restoreGState() }

        for run in runs {
            let glyphCount = CTRunGetGlyphCount(run)
            if glyphCount == 0 {
                guard try isUndrawnIgnorableRun(run, source: source) else { throw GlobalizedAccessibleDocumentFailureV1.unsupportedGlyph }
                continue
            }
            guard glyphCount > 0,
                  let actualText = try actualText(for: run, source: source),
                  !actualText.isEmpty else {
                throw GlobalizedAccessibleDocumentFailureV1.unsupportedGlyph
            }
            let attributes = CTRunGetAttributes(run) as NSDictionary
            guard let font = attributes[kCTFontAttributeName] as? CTFont else {
                throw GlobalizedAccessibleDocumentFailureV1.fontNotQualified
            }

            CGPDFContextBeginTag(
                context,
                .span,
                [CGPDFTagProperty.actualText: actualText] as CFDictionary
            )
            defer { CGPDFContextEndTag(context) }

            if embedding(for: font) == .colorGlyphImages {
                try drawColorGlyphRun(run, baseline: baseline, context: context)
                colorImages += 1
            } else {
                CTRunDraw(run, context, CFRange(location: 0, length: 0))
                outlines += 1
            }
        }
        return .init(outlineRunCount: outlines, colorGlyphImageRunCount: colorImages)
    }

    /// Use during qualifyRuns before PDF creation. The caller records its
    /// result in the existing font provenance fields plus embedding.
    static func qualifyingEmbedding(for run: CTRun) throws -> GlobalizedDocumentFontEmbeddingV1 {
        let attributes = CTRunGetAttributes(run) as NSDictionary
        guard let font = attributes[kCTFontAttributeName] as? CTFont,
              !(CTFontCopyPostScriptName(font) as String).lowercased().contains("lastresort") else {
            throw GlobalizedAccessibleDocumentFailureV1.unsupportedGlyph
        }
        return embedding(for: font)
    }

    /// A source format/variation-control run may carry no drawable glyphs.
    /// Preserve its source in the outer ActualText, but do not claim an unused
    /// font was embedded or require an empty color image to be drawn.
    static func isUndrawnIgnorableRun(_ run: CTRun, source: NSString) throws -> Bool {
        let range = CTRunGetStringRange(run)
        guard range.location >= 0, range.length >= 0, range.length <= source.length,
              range.location <= source.length - range.length else { throw GlobalizedAccessibleDocumentFailureV1.unsupportedGlyph }
        return source.substring(with: NSRange(location: range.location, length: range.length)).unicodeScalars.allSatisfy {
            $0.properties.generalCategory == .format || (0xFE00...0xFE0F).contains($0.value) ||
            (0xE0100...0xE01EF).contains($0.value) || CharacterSet.whitespacesAndNewlines.contains($0)
        }
    }

    private static func actualText(for run: CTRun, source: NSString) throws -> String? {
        let range = CTRunGetStringRange(run)
        guard range.location >= 0, range.length > 0,
              range.location <= source.length - range.length else {
            throw GlobalizedAccessibleDocumentFailureV1.unsupportedGlyph
        }
        let value = source.substring(with: NSRange(location: range.location, length: range.length))
        guard !value.isEmpty, value.utf8.count <= maximumSourceUTF8BytesPerRun else {
            throw GlobalizedAccessibleDocumentFailureV1.unsupportedGlyph
        }
        return value
    }

    /// Rasterizes just one color run. CTRunDraw retains the run's shaped glyph
    /// positions, including ZWJ sequences, regional-indicator flags, variation
    /// selectors, and RTL placement. The outer PDF receives one image XObject.
    private static func drawColorGlyphRun(
        _ run: CTRun,
        baseline: CGPoint,
        context: CGContext
    ) throws {
        let range = CFRange(location: 0, length: 0)
        let imageBounds = CTRunGetImageBounds(run, nil, range)
        guard !imageBounds.isNull, !imageBounds.isInfinite,
              imageBounds.width > 0, imageBounds.height > 0,
              imageBounds.width.isFinite, imageBounds.height.isFinite else {
            throw GlobalizedAccessibleDocumentFailureV1.unsupportedGlyph
        }

        let padding = 1 / rasterScale
        let destinationRect = imageBounds.insetBy(dx: -padding, dy: -padding)
        guard destinationRect.width > 0, destinationRect.height > 0,
              destinationRect.width.isFinite, destinationRect.height.isFinite,
              let width = boundedPixelDimension(destinationRect.width),
              let height = boundedPixelDimension(destinationRect.height),
              width <= Int.max / height,
              width * height <= maximumPixelsPerRun else {
            throw GlobalizedAccessibleDocumentFailureV1.paginationFailed
        }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let bitmap = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            throw GlobalizedAccessibleDocumentFailureV1.missingResource
        }

        bitmap.setAllowsAntialiasing(true)
        bitmap.setShouldAntialias(true)
        bitmap.interpolationQuality = .high
        bitmap.scaleBy(x: rasterScale, y: rasterScale)
        bitmap.translateBy(x: -destinationRect.minX, y: -destinationRect.minY)
        bitmap.textMatrix = .identity
        bitmap.textPosition = .zero
        CTRunDraw(run, bitmap, range)
        bitmap.flush()
        let bitmapByteCount = bitmap.bytesPerRow * bitmap.height
        guard bitmapByteCount > 0,
              let pixels = bitmap.data?.assumingMemoryBound(to: UInt8.self),
              UnsafeBufferPointer(start: pixels, count: bitmapByteCount).contains(where: { $0 != 0 }) else {
            throw GlobalizedAccessibleDocumentFailureV1.unsupportedGlyph
        }
        guard let image = bitmap.makeImage() else {
            throw GlobalizedAccessibleDocumentFailureV1.missingResource
        }

        context.saveGState()
        context.interpolationQuality = .high
        context.draw(image, in: destinationRect.offsetBy(dx: baseline.x, dy: baseline.y))
        context.restoreGState()
    }

    private static func boundedPixelDimension(_ points: CGFloat) -> Int? {
        let pixels = (points * rasterScale).rounded(.up)
        guard pixels.isFinite, pixels >= 1, pixels <= 16_384,
              pixels <= CGFloat(Int.max) else { return nil }
        return Int(pixels)
    }
}

/// A narrow post-write technical observation for the image representation.
/// It proves that at least the requested number of nonempty Image XObjects are
/// present in page/Form resources. It does not assert that every image is an
/// emoji; callers should supply the number returned by DrawResult.
func verifyColorGlyphImageXObjects(
    in document: CGPDFDocument,
    minimumCount: Int
) throws {
    guard minimumCount >= 0, minimumCount <= 4_096,
          document.numberOfPages > 0, document.numberOfPages <= 1_024 else {
        throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed
    }
    guard minimumCount > 0 else { return }

    let audit = _V30ColorGlyphImageAudit(minimumCount: minimumCount)
    let context = Unmanaged.passUnretained(audit).toOpaque()
    for pageNumber in 1...document.numberOfPages {
        guard let page = document.page(at: pageNumber),
              let resources = try audit.inheritedResources(for: page) else {
            throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed
        }
        try audit.visitResources(resources, depth: 0, context: context)
    }
    if let failure = audit.failure { throw failure }
    guard audit.imageCount >= minimumCount else {
        throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed
    }
}

private final class _V30ColorGlyphImageAudit {
    let minimumCount: Int
    var imageCount = 0
    var visits = 0
    var callbackDepth = 0
    var failure: Error?

    init(minimumCount: Int) {
        self.minimumCount = minimumCount
    }

    func inheritedResources(for page: CGPDFPage) throws -> CGPDFDictionaryRef? {
        var current = CGPDFPageGetDictionary(page)
        for _ in 0..<64 {
            guard let dictionary = current else { return nil }
            if let resources = Self.dictionary(dictionary, "Resources") { return resources }
            current = Self.dictionary(dictionary, "Parent")
        }
        throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed
    }

    func visitResources(
        _ resources: CGPDFDictionaryRef,
        depth: Int,
        context: UnsafeMutableRawPointer
    ) throws {
        guard depth <= 32, CGPDFDictionaryGetCount(resources) <= 1_024 else {
            throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed
        }
        visits += 1
        guard visits <= 8_192 else {
            throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed
        }
        guard let xObjects = Self.dictionary(resources, "XObject"),
              CGPDFDictionaryGetCount(xObjects) <= 1_024 else { return }
        let oldDepth = callbackDepth
        callbackDepth = depth
        defer { callbackDepth = oldDepth }
        CGPDFDictionaryApplyFunction(xObjects, _v30AuditColorGlyphXObject, context)
        if let failure { throw failure }
    }

    func consume(_ object: CGPDFObjectRef, context: UnsafeMutableRawPointer) throws {
        var stream: CGPDFStreamRef?
        guard CGPDFObjectGetValue(object, .stream, &stream), let stream,
              let dictionary = CGPDFStreamGetDictionary(stream),
              let subtype = Self.name(dictionary, "Subtype") else {
            throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed
        }
        switch subtype {
        case "Image":
            guard let width = Self.integer(dictionary, "Width"),
                  let height = Self.integer(dictionary, "Height"),
                  width > 0, height > 0, width <= 16_384, height <= 16_384,
                  let length = Self.integer(dictionary, "Length"),
                  length > 0, length <= 32 * 1_024 * 1_024 else {
                throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed
            }
            var format: CGPDFDataFormat = .raw
            guard let data = CGPDFStreamCopyData(stream, &format) as Data?,
                  !data.isEmpty, data.count <= 64 * 1_024 * 1_024 else {
                throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed
            }
            imageCount += 1
        case "Form":
            if let resources = Self.dictionary(dictionary, "Resources") {
                try visitResources(resources, depth: callbackDepth + 1, context: context)
            }
        default:
            return
        }
    }

    static func dictionary(_ dictionary: CGPDFDictionaryRef, _ key: String) -> CGPDFDictionaryRef? {
        var value: CGPDFDictionaryRef?
        return CGPDFDictionaryGetDictionary(dictionary, key, &value) ? value : nil
    }

    static func integer(_ dictionary: CGPDFDictionaryRef, _ key: String) -> Int? {
        var value: CGPDFInteger = 0
        return CGPDFDictionaryGetInteger(dictionary, key, &value) ? Int(value) : nil
    }

    static func name(_ dictionary: CGPDFDictionaryRef, _ key: String) -> String? {
        var value: UnsafePointer<CChar>?
        guard CGPDFDictionaryGetName(dictionary, key, &value), let value else { return nil }
        return String(cString: value)
    }
}

private func _v30AuditColorGlyphXObject(
    _ key: UnsafePointer<CChar>,
    _ object: CGPDFObjectRef,
    _ info: UnsafeMutableRawPointer?
) {
    guard let info else { return }
    let audit = Unmanaged<_V30ColorGlyphImageAudit>.fromOpaque(info).takeUnretainedValue()
    guard audit.failure == nil else { return }
    do {
        try audit.consume(object, context: info)
    } catch {
        audit.failure = error
    }
}

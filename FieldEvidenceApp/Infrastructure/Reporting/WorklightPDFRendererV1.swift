import CoreGraphics
import CoreText
import CryptoKit
import Foundation
import ImageIO

enum WorklightPDFRendererErrorV1: Error, Equatable {
    case invalidValidatedSnapshot
    case invalidImage
    case paginationFailed
    case pdfCreationFailed
}

struct RenderedPDFV1: Sendable {
    let data: Data
    let sha256: String
    let pageCount: Int
    let inspection: PDFRenderInspectionV1
}

struct PDFRenderInspectionV1: Sendable {
    let pageRect: CGRect
    let contentRect: CGRect
    let footerRect: CGRect
    let pages: [[PDFRenderInspectionItemV1]]
}

struct PDFRenderInspectionItemV1: Sendable {
    enum Kind: String, Sendable { case text, image }

    let kind: Kind
    let role: String
    let rect: CGRect
    let text: String?
    let fontName: String?
    let fontSize: CGFloat?
    let lineHeight: CGFloat?
    let evidenceID: UUID?
}

/// The single frozen V1 renderer. It accepts only a validator-issued value, so
/// it has no route to storage, persistence, packs, locale, clock, or time zone.
struct WorklightPDFRendererV1 {
    static let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
    static let contentRect = CGRect(x: 42, y: 72, width: 528, height: 678)
    static let footerRect = CGRect(x: 42, y: 42, width: 528, height: 18)

    private static let accent = CGColor(
        colorSpace: CGColorSpaceCreateDeviceRGB(),
        components: [0, 109.0 / 255.0, 117.0 / 255.0, 1]
    )!
    private static let black = CGColor(gray: 0, alpha: 1)
    private static let white = CGColor(gray: 1, alpha: 1)

    func render(_ validated: ValidatedReportSnapshotV1) throws -> RenderedPDFV1 {
        let snapshot = validated.snapshot
        guard snapshot.pdfTemplate.id == "field.evidence.pdf.worklight.v1",
              snapshot.pdfTemplate.version == 1,
              snapshot.snapshotSchemaVersion == 1,
              snapshot.reportID.uuidString.lowercased().count == 36,
              validated.snapshotSHA256.utf8.count == 64 else {
            throw WorklightPDFRendererErrorV1.invalidValidatedSnapshot
        }

        let blocks = try makeBlocks(validated)
        let pages = try paginate(blocks)
        guard !pages.isEmpty else { throw WorklightPDFRendererErrorV1.paginationFailed }
        let rawData = try draw(pages: pages, snapshot: snapshot, digest: validated.snapshotSHA256)
        let data = try removeVolatileDocumentIdentifier(rawData)
        return RenderedPDFV1(
            data: data,
            sha256: lowercaseSHA256(data),
            pageCount: pages.count,
            inspection: PDFRenderInspectionV1(
                pageRect: Self.pageRect,
                contentRect: Self.contentRect,
                footerRect: Self.footerRect,
                pages: pages.map { $0.flatMap(\.inspectionItems) }
            )
        )
    }
}

private extension WorklightPDFRendererV1 {
    enum Style {
        case title, section, body, caption

        var fontName: String {
            switch self {
            case .title, .section: "Helvetica-Bold"
            case .body, .caption: "Helvetica"
            }
        }
        var fontSize: CGFloat {
            switch self {
            case .title: 22
            case .section: 15
            case .body: 10
            case .caption: 8
            }
        }
        var lineHeight: CGFloat {
            switch self {
            case .title: 27
            case .section: 18
            case .body: 14
            case .caption: 11
            }
        }
        var color: CGColor { self == .section ? WorklightPDFRendererV1.accent : WorklightPDFRendererV1.black }
    }

    struct TextFragment {
        let text: String
        let style: Style
        let lineCount: Int
        let height: CGFloat
    }

    struct ImageFragment {
        let evidenceID: UUID
        let image: CGImage
        let box: CGSize
        let caption: String
        let role: String
    }

    enum BlockContent {
        case text(TextFragment)
        case currentImage(ImageFragment)
        case historyRow([ImageFragment], TextFragment)
    }

    struct Block {
        let role: String
        let content: BlockContent
        let spacingBefore: CGFloat
        let spacingAfter: CGFloat
        let keepWithFollowingBodyLines: Int

        var height: CGFloat {
            switch content {
            case .text(let text): text.height
            case .currentImage(let image): image.box.height + 4 + 11
            case .historyRow(let images, let text):
                (images.map { $0.box.height + 4 + 11 }.max() ?? 0)
                    + (images.isEmpty ? 0 : 6)
                    + text.height
            }
        }
    }

    struct PlacedBlock {
        let block: Block
        let rect: CGRect

        var inspectionItems: [PDFRenderInspectionItemV1] {
            switch block.content {
            case .text(let value):
                [PDFRenderInspectionItemV1(
                    kind: .text,
                    role: block.role,
                    rect: rect,
                    text: value.text,
                    fontName: value.style.fontName,
                    fontSize: value.style.fontSize,
                    lineHeight: value.style.lineHeight,
                    evidenceID: nil
                )]
            case .currentImage(let value):
                imageInspection(value, container: rect, index: 0)
            case .historyRow(let values, let text):
                values.enumerated().flatMap { imageInspection($0.element, container: rect, index: $0.offset) }
                    + [PDFRenderInspectionItemV1(
                        kind: .text,
                        role: block.role + ".summary",
                        rect: CGRect(
                            x: rect.minX,
                            y: rect.minY,
                            width: rect.width,
                            height: text.height
                        ),
                        text: text.text,
                        fontName: text.style.fontName,
                        fontSize: text.style.fontSize,
                        lineHeight: text.style.lineHeight,
                        evidenceID: nil
                    )]
            }
        }

        private func imageInspection(
            _ value: ImageFragment,
            container: CGRect,
            index: Int
        ) -> [PDFRenderInspectionItemV1] {
            let x = container.minX + CGFloat(index) * 172
            let imageRect = CGRect(x: x, y: container.maxY - value.box.height, width: value.box.width, height: value.box.height)
            return [
                PDFRenderInspectionItemV1(
                    kind: .image,
                    role: value.role,
                    rect: imageRect,
                    text: nil,
                    fontName: nil,
                    fontSize: nil,
                    lineHeight: nil,
                    evidenceID: value.evidenceID
                ),
                PDFRenderInspectionItemV1(
                    kind: .text,
                    role: value.role + ".caption",
                    rect: CGRect(x: x, y: imageRect.minY - 15, width: value.box.width, height: 11),
                    text: value.caption,
                    fontName: Style.caption.fontName,
                    fontSize: Style.caption.fontSize,
                    lineHeight: Style.caption.lineHeight,
                    evidenceID: value.evidenceID
                ),
            ]
        }
    }

    func makeBlocks(_ validated: ValidatedReportSnapshotV1) throws -> [Block] {
        let snapshot = validated.snapshot
        var blocks: [Block] = []
        func text(_ value: String, style: Style, role: String, before: CGFloat = 0, after: CGFloat = 6, keep: Int = 0) {
            let fragment = makeText(value, style: style, width: Self.contentRect.width)
            blocks.append(Block(role: role, content: .text(fragment), spacingBefore: before, spacingAfter: after, keepWithFollowingBodyLines: keep))
        }
        func section(_ value: String, role: String) { text(value, style: .section, role: role, before: 12, after: 6, keep: 2) }

        text("\(posixTitle(snapshot.display.checkSingular)) report", style: .title, role: "title", after: 18)
        section("Identity and time", role: "identity.heading")
        let address = snapshot.site.address.map { "\nAddress: \($0)" } ?? ""
        text("Site: \(snapshot.site.label)\(address)\n\(posixTitle(snapshot.display.assetSingular)): \(snapshot.asset.label)\nObserved: \(snapshot.timeContext.localDate) \(snapshot.timeContext.localTime) \(snapshot.timeContext.timeZoneID) (UTC \(signedOffset(snapshot.timeContext.utcOffsetMinutes)))", style: .body, role: "identity.body")

        let current = snapshot.evidence.filter { $0.recordID == snapshot.evidenceSourceRecordID }
        for purpose in ["wide_context", "close_detail"] {
            let role = purpose == "wide_context" ? "current.wide_context" : "current.close_detail"
            let fallback = purpose == "wide_context" ? "Wide view" : "Close view"
            section(current.first(where: { $0.purposeKey == purpose })?.purposeDisplay ?? fallback, role: role + ".heading")
            if let evidence = current.first(where: { $0.purposeKey == purpose }),
               let bytes = validated.originalJPEG(for: evidence.evidenceID) {
                let image = try decode(bytes)
                let fragment = ImageFragment(
                    evidenceID: evidence.evidenceID,
                    image: image,
                    box: aspectFit(image: image, maximum: CGSize(width: 528, height: 288)),
                    caption: "\(evidence.purposeDisplay) — \(timestamp(evidence.createdAt))",
                    role: role
                )
                blocks.append(Block(role: role, content: .currentImage(fragment), spacingBefore: 0, spacingAfter: 6, keepWithFollowingBodyLines: 0))
            } else if snapshot.couldNotVerify != nil {
                text("Not captured — Could not verify", style: .body, role: role + ".missing")
            } else {
                throw WorklightPDFRendererErrorV1.invalidValidatedSnapshot
            }
        }

        section("Result", role: "result.heading")
        var result = "Stage: \(snapshot.display.stage)\nOutcome: \(snapshot.display.outcome)"
        if let reason = snapshot.couldNotVerify { result += "\nCould not verify: \(reason.display)" }
        if let note = snapshot.note { result += "\nNote: \(note)" }
        text(result, style: .body, role: "result.body")

        if !snapshot.issues.isEmpty {
            section(posixTitle(snapshot.display.issueSingular) + (snapshot.issues.count == 1 ? "" : "s"), role: "issues.heading")
            for issue in snapshot.issues {
                text("\(issue.display) — \(statusDisplay(issue.status))", style: .body, role: "issue.\(issue.issueID.uuidString.lowercased())")
            }
        }

        if !snapshot.history.isEmpty {
            section("History", role: "history.heading")
            let evidenceByID = Dictionary(uniqueKeysWithValues: snapshot.evidence.map { ($0.evidenceID, $0) })
            for entry in snapshot.history {
                let images: [ImageFragment] = try entry.evidenceIDs.prefix(3).map { id in
                    guard let evidence = evidenceByID[id], let bytes = validated.thumbnailJPEG(for: id) else {
                        throw WorklightPDFRendererErrorV1.invalidValidatedSnapshot
                    }
                    let image = try decode(bytes)
                    return ImageFragment(
                        evidenceID: id,
                        image: image,
                        box: aspectFit(image: image, maximum: CGSize(width: 160, height: 120)),
                        caption: "\(evidence.purposeDisplay) — \(timestamp(evidence.createdAt))",
                        role: "history.\(entry.recordID.uuidString.lowercased()).\(evidence.purposeKey)"
                    )
                }
                var summary = "\(entry.stageDisplay) — \(entry.outcomeDisplay) — \(timestamp(entry.completedAt))"
                if let reason = entry.couldNotVerify {
                    summary += "\nCould not verify: \(reason.display)"
                }
                if let localDate = entry.workPerformedLocalDate {
                    summary += "\nWork date: \(localDate)"
                }
                if let work = entry.workDescription { summary += "\n\(work)" }
                if let note = entry.note { summary += "\nNote: \(note)" }
                let summaryFragment = makeText(summary, style: .caption, width: 528)
                blocks.append(Block(role: "history.\(entry.recordID.uuidString.lowercased())", content: .historyRow(images, summaryFragment), spacingBefore: 0, spacingAfter: 6, keepWithFollowingBodyLines: 0))
            }
        }

        section("About this report", role: "disclaimer.heading")
        text(snapshot.disclaimer, style: .body, role: "disclaimer.body", after: 0)
        return blocks
    }

    func paginate(_ blocks: [Block]) throws -> [[PlacedBlock]] {
        var pages: [[PlacedBlock]] = [[]]
        var top = Self.contentRect.maxY
        for (index, block) in blocks.enumerated() {
            let minimumFollowing: CGFloat
            if block.keepWithFollowingBodyLines > 0,
               blocks.indices.contains(index + 1) {
                let following = blocks[index + 1]
                switch following.content {
                case .text:
                    minimumFollowing = following.spacingBefore
                        + following.height
                        + following.spacingAfter
                case .currentImage, .historyRow:
                    minimumFollowing = following.spacingBefore
                        + following.height
                        + following.spacingAfter
                }
            } else {
                minimumFollowing = 0
            }
            let required = block.spacingBefore + block.height + block.spacingAfter + minimumFollowing
            if top - required < Self.contentRect.minY, !pages[pages.count - 1].isEmpty {
                pages.append([])
                top = Self.contentRect.maxY
            }
            let available = top - Self.contentRect.minY - block.spacingBefore - block.spacingAfter
            guard block.height <= available else {
                if case .text(let value) = block.content,
                   value.lineCount >= 4,
                   value.style != .title,
                   value.style != .section {
                    let lines = wrappedLines(value.text, style: value.style, width: Self.contentRect.width)
                    let firstCount = min(lines.count - 2, max(2, Int(floor(available / value.style.lineHeight))))
                    guard firstCount >= 2, lines.count - firstCount >= 2 else { throw WorklightPDFRendererErrorV1.paginationFailed }
                    let split = [lines.prefix(firstCount).joined(separator: "\n"), lines.dropFirst(firstCount).joined(separator: "\n")]
                    var expanded = blocks
                    expanded.remove(at: index)
                    let replacements = split.map { piece in
                        Block(role: block.role, content: .text(makeText(piece, style: value.style, width: Self.contentRect.width)), spacingBefore: block.spacingBefore, spacingAfter: block.spacingAfter, keepWithFollowingBodyLines: 0)
                    }
                    expanded.insert(contentsOf: replacements, at: index)
                    return try paginate(expanded)
                }
                throw WorklightPDFRendererErrorV1.paginationFailed
            }
            top -= block.spacingBefore
            let rect = CGRect(x: Self.contentRect.minX, y: top - block.height, width: Self.contentRect.width, height: block.height)
            pages[pages.count - 1].append(PlacedBlock(block: block, rect: rect))
            top = rect.minY - block.spacingAfter
        }
        return pages
    }

    func draw(pages: [[PlacedBlock]], snapshot: ReportSnapshotV1, digest: String) throws -> Data {
        let output = NSMutableData()
        var mediaBox = Self.pageRect
        let metadata: [CFString: Any] = [
            kCGPDFContextCreator: "FieldEvidenceApp PDFTemplateV1",
            kCGPDFContextCreationDate: snapshot.snapshotCreatedAt as CFDate,
            kCGPDFContextModificationDate: snapshot.snapshotCreatedAt as CFDate,
        ]
        guard let context = CGDataConsumer(data: output as CFMutableData).flatMap({ CGPDFContextCreate($0, &mediaBox, metadata as CFDictionary) }) else {
            throw WorklightPDFRendererErrorV1.pdfCreationFailed
        }
        for (pageIndex, page) in pages.enumerated() {
            context.beginPDFPage(nil)
            context.setFillColor(Self.white)
            context.fill(Self.pageRect)
            for placed in page { draw(placed, in: context) }
            try drawFooter(snapshot: snapshot, digest: digest, page: pageIndex + 1, count: pages.count, in: context)
            context.endPDFPage()
        }
        context.closePDF()
        guard output.length > 0 else { throw WorklightPDFRendererErrorV1.pdfCreationFailed }
        return output as Data
    }

    func draw(_ placed: PlacedBlock, in context: CGContext) {
        switch placed.block.content {
        case .text(let value): drawText(value.text, style: value.style, rect: placed.rect, in: context)
        case .currentImage(let value): drawImage(value, x: placed.rect.minX, top: placed.rect.maxY, in: context)
        case .historyRow(let values, let summary):
            for (index, value) in values.enumerated() { drawImage(value, x: placed.rect.minX + CGFloat(index) * 172, top: placed.rect.maxY, in: context) }
            drawText(
                summary.text,
                style: summary.style,
                rect: CGRect(
                    x: placed.rect.minX,
                    y: placed.rect.minY,
                    width: placed.rect.width,
                    height: summary.height
                ),
                in: context
            )
        }
    }

    func drawImage(_ value: ImageFragment, x: CGFloat, top: CGFloat, in context: CGContext) {
        let rect = CGRect(x: x, y: top - value.box.height, width: value.box.width, height: value.box.height)
        context.draw(value.image, in: rect)
        drawText(value.caption, style: .caption, rect: CGRect(x: x, y: rect.minY - 15, width: value.box.width, height: 11), in: context)
    }

    func drawFooter(snapshot: ReportSnapshotV1, digest: String, page: Int, count: Int, in context: CGContext) throws {
        let first = "\(timestamp(snapshot.snapshotCreatedAt))|A\(snapshot.sourceApp.version)/\(snapshot.sourceApp.build)|P\(snapshot.pack.id)/\(snapshot.pack.schemaVersion)/\(snapshot.pack.contentVersion)|T\(snapshot.pdfTemplate.id)/\(snapshot.pdfTemplate.version)"
        let second = "SHA256 \(digest)"
        let pageLabel = "Page \(page) of \(count)"
        guard singleLineWidth(first, fontName: "Courier", size: 7) <= 468,
              singleLineWidth(second, fontName: "Courier", size: 7) <= 468,
              singleLineWidth(pageLabel, fontName: "Courier", size: 7) <= 60 else {
            throw WorklightPDFRendererErrorV1.paginationFailed
        }
        drawText(first, fontName: "Courier", fontSize: 7, lineHeight: 9, color: Self.black, rect: CGRect(x: 42, y: 51, width: 468, height: 9), alignment: .left, in: context)
        drawText(second, fontName: "Courier", fontSize: 7, lineHeight: 9, color: Self.black, rect: CGRect(x: 42, y: 42, width: 468, height: 9), alignment: .left, in: context)
        drawText(pageLabel, fontName: "Courier", fontSize: 7, lineHeight: 9, color: Self.black, rect: CGRect(x: 510, y: 42, width: 60, height: 18), alignment: .right, in: context)
    }

    func drawText(_ text: String, style: Style, rect: CGRect, in context: CGContext) {
        drawText(text, fontName: style.fontName, fontSize: style.fontSize, lineHeight: style.lineHeight, color: style.color, rect: rect, alignment: .left, in: context)
    }

    func singleLineWidth(_ text: String, fontName: String, size: CGFloat) -> CGFloat {
        let font = CTFontCreateWithName(fontName as CFString, size, nil)
        let attributed = NSAttributedString(
            string: text,
            attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]
        )
        let line = CTLineCreateWithAttributedString(attributed)
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    func drawText(_ text: String, fontName: String, fontSize: CGFloat, lineHeight: CGFloat, color: CGColor, rect: CGRect, alignment: CTTextAlignment, in context: CGContext) {
        let font = CTFontCreateWithName(fontName as CFString, fontSize, nil)
        var minimum = lineHeight
        var maximum = lineHeight
        var alignment = alignment
        let settings: [CTParagraphStyleSetting] = [
            CTParagraphStyleSetting(spec: .minimumLineHeight, valueSize: MemoryLayout<CGFloat>.size, value: &minimum),
            CTParagraphStyleSetting(spec: .maximumLineHeight, valueSize: MemoryLayout<CGFloat>.size, value: &maximum),
            CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: &alignment),
        ]
        let paragraph = CTParagraphStyleCreate(settings, settings.count)
        let attributed = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraph,
        ])
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(rect: rect, transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: attributed.length), path, nil)
        context.saveGState()
        context.textMatrix = .identity
        CTFrameDraw(frame, context)
        context.restoreGState()
    }

    func makeText(_ text: String, style: Style, width: CGFloat) -> TextFragment {
        let lines = wrappedLines(text, style: style, width: width)
        return TextFragment(text: lines.joined(separator: "\n"), style: style, lineCount: lines.count, height: CGFloat(lines.count) * style.lineHeight)
    }

    func wrappedLines(_ text: String, style: Style, width: CGFloat) -> [String] {
        let font = CTFontCreateWithName(style.fontName as CFString, style.fontSize, nil)
        return text.split(separator: "\n", omittingEmptySubsequences: false).flatMap { paragraph -> [String] in
            let value = String(paragraph)
            if value.isEmpty { return [""] }
            let attributed = NSAttributedString(string: value, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
            let typesetter = CTTypesetterCreateWithAttributedString(attributed)
            var position = 0
            var result: [String] = []
            while position < attributed.length {
                var count = CTTypesetterSuggestLineBreak(typesetter, position, Double(width))
                if count <= 0 { count = 1 }
                let range = NSRange(location: position, length: count)
                result.append((value as NSString).substring(with: range).trimmingCharacters(in: .whitespaces))
                position += count
            }
            return result
        }
    }

    func decode(_ data: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) == 1,
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else {
            throw WorklightPDFRendererErrorV1.invalidImage
        }
        return image
    }

    /// Core Graphics can add a trailer `/ID` derived from process state. The
    /// trailer dictionary is outside the xref table, so replacing only the
    /// complete key/value clause with equal-length whitespace preserves every
    /// object offset and yields a valid deterministic trailer without an ID.
    func removeVolatileDocumentIdentifier(_ data: Data) throws -> Data {
        var result = data
        let pattern = try NSRegularExpression(
            pattern: #"/ID\s*\[\s*<[^>]*>\s*<[^>]*>\s*\]"#,
            options: []
        )
        guard let source = String(data: data, encoding: .isoLatin1) else {
            throw WorklightPDFRendererErrorV1.pdfCreationFailed
        }
        let full = NSRange(location: 0, length: (source as NSString).length)
        let matches = pattern.matches(in: source, options: [], range: full)
        guard matches.count <= 1 else {
            throw WorklightPDFRendererErrorV1.pdfCreationFailed
        }
        if let match = matches.first {
            guard let byteRange = Range(match.range, in: source),
                  let lower = source[..<byteRange.lowerBound].data(using: .isoLatin1)?.count,
                  let length = source[byteRange].data(using: .isoLatin1)?.count else {
                throw WorklightPDFRendererErrorV1.pdfCreationFailed
            }
            result.replaceSubrange(
                lower..<(lower + length),
                with: repeatElement(UInt8(ascii: " "), count: length)
            )
        }
        guard result.range(of: Data("/ID".utf8)) == nil else {
            throw WorklightPDFRendererErrorV1.pdfCreationFailed
        }
        return result
    }

    func aspectFit(image: CGImage, maximum: CGSize) -> CGSize {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let scale = min(1, maximum.width / width, maximum.height / height)
        return CGSize(width: floor(width * scale * 1_000) / 1_000, height: floor(height * scale * 1_000) / 1_000)
    }

    func signedOffset(_ minutes: Int) -> String {
        let sign = minutes < 0 ? "−" : "+"
        let magnitude = abs(minutes)
        let hours = String(magnitude / 60)
        let minuteValue = String(magnitude % 60)
        return sign
            + String(repeating: "0", count: max(0, 2 - hours.count)) + hours
            + ":"
            + String(repeating: "0", count: max(0, 2 - minuteValue.count)) + minuteValue
    }

    func posixTitle(_ value: String) -> String {
        guard let first = value.first else { return value }
        return String(first).uppercased(with: Locale(identifier: "en_US_POSIX"))
            + value.dropFirst()
    }

    func statusDisplay(_ value: String) -> String {
        switch value {
        case "recheck_due": "Recheck due"
        case "resolved": "Resolved"
        default: "Open"
        }
    }

    func timestamp(_ value: Date) -> String { Self.timestampFormatter.string(from: value) }

    func lowercaseSHA256(_ data: Data) -> String {
        let digits = Array("0123456789abcdef".utf8)
        var bytes: [UInt8] = []
        bytes.reserveCapacity(64)
        for value in SHA256.hash(data: data) {
            bytes.append(digits[Int(value >> 4)])
            bytes.append(digits[Int(value & 0x0f)])
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        return formatter
    }()
}

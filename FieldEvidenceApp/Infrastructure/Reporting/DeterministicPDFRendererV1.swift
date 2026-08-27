import Foundation

enum DeterministicPDFRendererV1 {
    static let rendererVersion = "deterministic-pdf-renderer-v1"

    private static let inventoryBegin = "%AR-SEMANTIC-BEGIN"
    private static let inventoryRow = "%AR-SEMANTIC-ROW:"
    private static let inventoryEnd = "%AR-SEMANTIC-END"
    private static let inventoryChunkBytes = 57
    static func render(
        _ projection: ReportSemanticProjectionV1,
        layoutProfile: ReportLayoutProfileV1
    ) throws -> ReportProjectionOutputV1 {
        let validated = try projection.recursivelyValidated()
        guard layoutProfile.schemaVersion == ReportLayoutProfileV1.schemaVersion else {
            throw SnapshotProjectionFailureV1.incompatibleVersion
        }
        let landscape = layoutProfile.orientation == .landscape
        let pageWidth = landscape ? 792 : 612
        let pageHeight = landscape ? 612 : 792
        let maximumVisibleColumns = landscape ? 116 : 88
        let pageLineCount = landscape ? 36 : 48
        let semanticData = try DeterministicOpenJSONRendererV1.render(validated).data
        let sourceLines = [
            "AssetRounds report",
            "Snapshot: \(validated.snapshotID)",
            "Snapshot SHA-256: \(validated.snapshotSHA256)",
            "Profile: \(layoutProfile.profileID) release \(layoutProfile.profileRelease)",
            "Audience/detail: \(layoutProfile.audience.rawValue) / \(layoutProfile.detail.rawValue)",
            "Locale/units: \(layoutProfile.localeIdentifier) / \(layoutProfile.unitsProfileID)",
            "Orientation/media: \(layoutProfile.orientation.rawValue) / \(layoutProfile.mediaLayout.rawValue)",
        ] + validated.nodes.map {
            "[\($0.semanticID)|\($0.sectionID)|\($0.role)] \($0.label): \($0.value)" +
            ($0.outputReferenceID.map { " [\($0)]" } ?? "")
        }
        let lines = sourceLines.flatMap { wrap(asciiVisible($0), columns: maximumVisibleColumns) }
        let pages = stride(from: 0, to: lines.count, by: pageLineCount).map {
            Array(lines[$0..<min($0 + pageLineCount, lines.count)])
        }
        guard !pages.isEmpty, pages.count <= 64 else { throw SnapshotProjectionFailureV1.limitExceeded }

        let catalogID = 1
        let pagesID = 2
        let fontID = 3
        let firstPageID = 4
        var objects: [Int: Data] = [:]
        var pageIDs: [Int] = []
        for index in pages.indices {
            let pageID = firstPageID + index * 2
            let streamID = pageID + 1
            pageIDs.append(pageID)
            let stream = contentStream(pages[index], pageHeight: pageHeight)
            objects[streamID] = Data("<< /Length \(stream.count) >>\nstream\n".utf8) + stream + Data("\nendstream".utf8)
            objects[pageID] = Data("<< /Type /Page /Parent \(pagesID) 0 R /MediaBox [0 0 \(pageWidth) \(pageHeight)] /Resources << /Font << /F1 \(fontID) 0 R >> >> /Contents \(streamID) 0 R >>".utf8)
        }
        objects[catalogID] = Data("<< /Type /Catalog /Pages \(pagesID) 0 R >>".utf8)
        objects[pagesID] = Data("<< /Type /Pages /Count \(pageIDs.count) /Kids [\(pageIDs.map { "\($0) 0 R" }.joined(separator: " "))] >>".utf8)
        objects[fontID] = Data("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>".utf8)

        var pdf = Data("%PDF-1.4\n%AssetRounds-V23\n".utf8)
        appendSemanticInventory(semanticData, to: &pdf)
        let objectCount = objects.keys.max() ?? 0
        var offsets = Array(repeating: 0, count: objectCount + 1)
        for objectID in 1...objectCount {
            guard let body = objects[objectID] else { throw SnapshotProjectionFailureV1.missingBinding }
            offsets[objectID] = pdf.count
            pdf.append(Data("\(objectID) 0 obj\n".utf8))
            pdf.append(body)
            pdf.append(Data("\nendobj\n".utf8))
        }
        let xrefOffset = pdf.count
        pdf.append(Data("xref\n0 \(objectCount + 1)\n0000000000 65535 f \n".utf8))
        for objectID in 1...objectCount {
            pdf.append(Data(String(format: "%010d 00000 n \n", offsets[objectID]).utf8))
        }
        pdf.append(Data("trailer\n<< /Size \(objectCount + 1) /Root \(catalogID) 0 R >>\nstartxref\n\(xrefOffset)\n%%EOF\n".utf8))
        guard pdf.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes else {
            throw SnapshotProjectionFailureV1.limitExceeded
        }
        guard try reopen(pdf) == validated else {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
        return ReportProjectionOutputV1(
            format: .pdf,
            data: pdf,
            sha256: KernelCanonicalHashV1.sha256(pdf),
            semanticSHA256: projection.semanticSHA256,
            orderedSemanticIDs: projection.nodes.map(\.semanticID),
            taggedPDFAccessibilityEvidence: false
        )
    }

    private static func contentStream(_ lines: [String], pageHeight: Int) -> Data {
        var commands: [String] = []
        for (index, line) in lines.enumerated() {
            let y = pageHeight - 44 - index * 15
            commands.append("BT /F1 9 Tf 42 \(y) Td (\(pdfLiteral(line))) Tj ET")
        }
        return Data(commands.joined(separator: "\n").utf8)
    }

    static func reopen(_ data: Data) throws -> ReportSemanticProjectionV1 {
        guard !data.isEmpty, data.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes,
              data.starts(with: Data("%PDF-1.4\n".utf8)),
              Data(data.suffix(6)) == Data("%%EOF\n".utf8),
              let source = String(data: data, encoding: .ascii) else {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let beginIndex = lines.firstIndex(where: { $0.hasPrefix(inventoryBegin + " ") }),
              let endIndex = lines.firstIndex(of: inventoryEnd), beginIndex < endIndex,
              lines.lastIndex(where: { $0.hasPrefix(inventoryBegin + " ") }) == beginIndex,
              lines.lastIndex(of: inventoryEnd) == endIndex else {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
        let fields = lines[beginIndex].split(separator: " ")
        guard fields.count == 3, let expectedCount = Int(fields[1]), expectedCount > 0,
              expectedCount <= SnapshotProjectionLimitsV1.maximumProjectionBytes,
              KernelCanonicalHashV1.validSHA256(String(fields[2])) else {
            throw SnapshotProjectionFailureV1.projectionDisagreement
        }
        let encodedRows = Array(lines[(beginIndex + 1)..<endIndex])
        guard !encodedRows.isEmpty,
              encodedRows.count <= (SnapshotProjectionLimitsV1.maximumProjectionBytes + inventoryChunkBytes - 1) / inventoryChunkBytes else {
            throw SnapshotProjectionFailureV1.limitExceeded
        }
        var semanticData = Data()
        for (index, row) in encodedRows.enumerated() {
            let expectedPrefix = inventoryRow + String(format: "%06d:", index)
            guard row.hasPrefix(expectedPrefix),
                  let chunk = Data(base64Encoded: String(row.dropFirst(expectedPrefix.count))),
                  !chunk.isEmpty, chunk.count <= inventoryChunkBytes,
                  (index < encodedRows.count - 1 ? chunk.count == inventoryChunkBytes : true) else {
                throw SnapshotProjectionFailureV1.projectionDisagreement
            }
            semanticData.append(chunk)
        }
        guard semanticData.count == expectedCount,
              KernelCanonicalHashV1.sha256(semanticData) == String(fields[2]) else {
            throw SnapshotProjectionFailureV1.digestMismatch
        }
        return try DeterministicOpenJSONRendererV1.reopen(semanticData)
    }

    private static func appendSemanticInventory(_ data: Data, to pdf: inout Data) {
        pdf.append(Data("\(inventoryBegin) \(data.count) \(KernelCanonicalHashV1.sha256(data))\n".utf8))
        var index = 0
        var offset = 0
        while offset < data.count {
            let end = min(offset + inventoryChunkBytes, data.count)
            let encoded = Data(data[offset..<end]).base64EncodedString()
            pdf.append(Data("\(inventoryRow)\(String(format: "%06d", index)):\(encoded)\n".utf8))
            offset = end
            index += 1
        }
        pdf.append(Data("\(inventoryEnd)\n".utf8))
    }

    private static func asciiVisible(_ value: String) -> String {
        value.unicodeScalars.map { scalar in
            if (0x20...0x7E).contains(scalar.value) {
                return String(scalar)
            }
            return "\\u{\(String(scalar.value, radix: 16, uppercase: true))}"
        }.joined()
    }

    private static func wrap(_ value: String, columns: Int) -> [String] {
        guard !value.isEmpty else { return [""] }
        var result: [String] = []
        var remainder = value[...]
        while !remainder.isEmpty {
            let limit = remainder.index(remainder.startIndex, offsetBy: min(columns, remainder.count))
            if limit == remainder.endIndex {
                result.append(String(remainder))
                break
            }
            let candidate = remainder[..<limit]
            let breakIndex = candidate.lastIndex(of: " ").map { remainder.index(after: $0) } ?? limit
            result.append(String(remainder[..<breakIndex]).trimmingCharacters(in: .whitespaces))
            remainder = remainder[breakIndex...].drop(while: { $0 == " " })
        }
        return result
    }

    private static func pdfLiteral(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "(", with: "\\(")
            .replacingOccurrences(of: ")", with: "\\)")
    }
}

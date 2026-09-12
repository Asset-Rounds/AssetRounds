import CryptoKit
import Foundation

enum GlobalizedAccessibleDocumentFailureV1: Error, Equatable, Sendable {
    case invalidRequest, invalidElement, missingResource, fontNotQualified
    case unsupportedGlyph, replayMismatch, pdfValidationFailed, paginationFailed
}

/// An explicit render choice. It records display intent; it does not assert
/// that frozen source text was translated or reformatted.
struct GlobalizedDocumentRenderRequestV1: Equatable, Sendable {
    let language: ReportLanguageSelectionV1
    let formatting: FormattingLocaleProfileV1
    let paperSize: LocalePaperSizeV1

    init(language: ReportLanguageSelectionV1, formatting: FormattingLocaleProfileV1, paperSize: LocalePaperSizeV1) throws {
        self.language = language
        self.formatting = formatting
        self.paperSize = paperSize
        try validate()
    }

    func validate() throws {
        _ = try ReportLanguageSelectionV1(requestedLanguage: language.requestedLanguage, effectiveLanguage: language.effectiveLanguage, fallback: language.fallback)
        _ = try FormattingLocaleProfileV1(localeIdentifier: formatting.localeIdentifier, ianaTimeZoneIdentifier: formatting.ianaTimeZoneIdentifier, calendar: formatting.calendar, numberingSystem: formatting.numberingSystem, units: formatting.units)
    }
}

/// Source-bound display input. The caller supplies ordering and semantics; the
/// renderer never derives a new source meaning, caption, or evidence link.
struct GlobalizedDocumentElementV1: Equatable, Sendable {
    let semanticID: String
    let role: AccessibleDocumentRoleV1
    let text: String?
    let headingLevel: Int?
    let evidenceID: String?
    let evidenceSHA256: String?
    let imageData: Data?
    let alternateText: String?
    let alternateTextProvenance: AccessibleAlternateTextProvenanceV1?
    let maximumImageWidthPoints: Double?
    let maximumImageHeightPoints: Double?
    let keepWithNext: Bool
    let parentSemanticID: String?
    let tableHeaderScope: AccessibleTableHeaderScopeV1?
    let tableHeaderSemanticIDs: [String]
    let decorative: Bool

    init(semanticID: String, role: AccessibleDocumentRoleV1, text: String? = nil, headingLevel: Int? = nil, evidenceID: String? = nil, evidenceSHA256: String? = nil, imageData: Data? = nil, alternateText: String? = nil, alternateTextProvenance: AccessibleAlternateTextProvenanceV1? = nil, maximumImageWidthPoints: Double? = nil, maximumImageHeightPoints: Double? = nil, keepWithNext: Bool = false, parentSemanticID: String? = nil, tableHeaderScope: AccessibleTableHeaderScopeV1? = nil, tableHeaderSemanticIDs: [String] = [], decorative: Bool = false) throws {
        guard SnapshotProjectionValidationV1.validID(semanticID), !semanticID.isEmpty,
              text?.utf8.count ?? 0 <= 1_048_576,
              alternateText?.utf8.count ?? 0 <= 16_384,
              (role == .heading) == (headingLevel != nil),
              headingLevel.map({ (1...6).contains($0) }) ?? true,
              (evidenceID == nil) == (evidenceSHA256 == nil),
              parentSemanticID.map({ $0 != semanticID && SnapshotProjectionValidationV1.validID($0) }) ?? true,
              (role == .tableHeader) == (tableHeaderScope != nil),
              role == .tableCell || tableHeaderSemanticIDs.isEmpty,
              Set(tableHeaderSemanticIDs).count == tableHeaderSemanticIDs.count,
              tableHeaderSemanticIDs.allSatisfy(SnapshotProjectionValidationV1.validID),
              maximumImageWidthPoints.map({ $0 > 0 && $0.isFinite }) ?? true,
              maximumImageHeightPoints.map({ $0 > 0 && $0.isFinite }) ?? true else { throw GlobalizedAccessibleDocumentFailureV1.invalidElement }
        if let evidenceID { guard SnapshotProjectionValidationV1.validID(evidenceID) else { throw GlobalizedAccessibleDocumentFailureV1.invalidElement } }
        if let evidenceSHA256 { guard KernelCanonicalHashV1.validSHA256(evidenceSHA256) else { throw GlobalizedAccessibleDocumentFailureV1.invalidElement } }
        if let imageData {
            guard role == .figure, imageData.count <= 64 * 1_024 * 1_024,
                  KernelCanonicalHashV1.sha256(imageData) == evidenceSHA256 else { throw GlobalizedAccessibleDocumentFailureV1.invalidElement }
        }
        if role == .figure {
            // A figure without bytes is a source figure group. Rendering
            // requires concrete child figures and validates their resources.
            guard imageData != nil || (evidenceID == nil && evidenceSHA256 == nil) else { throw GlobalizedAccessibleDocumentFailureV1.missingResource }
            if decorative {
                guard alternateText == nil, alternateTextProvenance == nil else { throw GlobalizedAccessibleDocumentFailureV1.invalidElement }
            } else {
                guard
                  (alternateText == nil) == (alternateTextProvenance == .notProvided),
                  alternateText == nil || alternateTextProvenance == .authoredForSource || alternateTextProvenance == .sourceCaption else { throw GlobalizedAccessibleDocumentFailureV1.invalidElement }
            }
        } else if decorative || alternateText != nil || alternateTextProvenance != nil { throw GlobalizedAccessibleDocumentFailureV1.invalidElement }
        self.semanticID = semanticID; self.role = role; self.text = text; self.headingLevel = headingLevel
        self.evidenceID = evidenceID; self.evidenceSHA256 = evidenceSHA256; self.imageData = imageData
        self.alternateText = alternateText; self.alternateTextProvenance = alternateTextProvenance
        self.maximumImageWidthPoints = maximumImageWidthPoints; self.maximumImageHeightPoints = maximumImageHeightPoints
        self.keepWithNext = keepWithNext
        self.parentSemanticID = parentSemanticID; self.tableHeaderScope = tableHeaderScope
        self.tableHeaderSemanticIDs = tableHeaderSemanticIDs; self.decorative = decorative
    }
}

enum GlobalizedDocumentFontEmbeddingV1: String, Codable, Equatable, Hashable, Sendable {
    case outlineSubset
    case colorGlyphImages
}

struct GlobalizedDocumentFontProvenanceV1: Codable, Equatable, Hashable, Sendable {
    let postScriptName: String
    let versionName: String
    let fontFileSHA256: String
    let os2FsType: UInt16
    let fileByteCount: Int64
    let embedding: GlobalizedDocumentFontEmbeddingV1

    func validate() throws {
        guard !postScriptName.isEmpty, postScriptName.utf8.count <= 256,
              !postScriptName.lowercased().contains("lastresort"),
              !versionName.isEmpty, versionName.utf8.count <= 2_048,
              KernelCanonicalHashV1.validSHA256(fontFileSHA256),
              fileByteCount > 0, fileByteCount <= 256 * 1_024 * 1_024,
              os2FsType & 0x0002 == 0,
              embedding == .colorGlyphImages || os2FsType & 0x0300 == 0 else { throw GlobalizedAccessibleDocumentFailureV1.fontNotQualified }
    }
}

/// Source-bound structural metadata. Text remains in the PDF's ActualText;
/// original source bytes are bound separately by sourceContentSHA256.
struct GlobalizedDocumentSemanticRecordV1: Codable, Equatable, Sendable {
    let semanticID: String
    let parentSemanticID: String?
    let role: AccessibleDocumentRoleV1
    let headingLevel: Int?
    let tableHeaderScope: AccessibleTableHeaderScopeV1?
    let tableHeaderSemanticIDs: [String]
    let decorative: Bool
    let evidenceID: String?
    let evidenceSHA256: String?
    let alternateTextProvenance: AccessibleAlternateTextProvenanceV1?

    init(_ element: GlobalizedDocumentElementV1) {
        semanticID = element.semanticID; parentSemanticID = element.parentSemanticID; role = element.role
        headingLevel = element.headingLevel; tableHeaderScope = element.tableHeaderScope
        tableHeaderSemanticIDs = element.tableHeaderSemanticIDs; decorative = element.decorative
        evidenceID = element.evidenceID; evidenceSHA256 = element.evidenceSHA256
        alternateTextProvenance = element.alternateTextProvenance
    }

    static func validateOrder(_ values: [Self]) throws {
        guard !values.isEmpty, values.count <= 10_000,
              Set(values.map(\.semanticID)).count == values.count else { throw GlobalizedAccessibleDocumentFailureV1.invalidElement }
        let byID = Dictionary(uniqueKeysWithValues: values.map { ($0.semanticID, $0) })
        var ancestors: [String] = []
        for value in values {
            guard SnapshotProjectionValidationV1.validID(value.semanticID),
                  (value.role == .heading) == (value.headingLevel != nil),
                  value.headingLevel.map({ (1...6).contains($0) }) ?? true,
                  (value.role == .tableHeader) == (value.tableHeaderScope != nil),
                  value.role == .tableCell || value.tableHeaderSemanticIDs.isEmpty,
                  Set(value.tableHeaderSemanticIDs).count == value.tableHeaderSemanticIDs.count,
                  (value.evidenceID == nil) == (value.evidenceSHA256 == nil),
                  value.evidenceID.map(SnapshotProjectionValidationV1.validID) ?? true,
                  value.evidenceSHA256.map(KernelCanonicalHashV1.validSHA256) ?? true,
                  !value.decorative || value.role == .figure else { throw GlobalizedAccessibleDocumentFailureV1.invalidElement }
            if let parent = value.parentSemanticID {
                guard let index = ancestors.firstIndex(of: parent) else { throw GlobalizedAccessibleDocumentFailureV1.invalidElement }
                ancestors.removeSubrange((index + 1)..<ancestors.count)
            } else { ancestors.removeAll(keepingCapacity: true) }
            guard ancestors.count < 128 else { throw GlobalizedAccessibleDocumentFailureV1.invalidElement }
            if value.role == .tableRow, byID[value.parentSemanticID ?? ""]?.role != .table { throw GlobalizedAccessibleDocumentFailureV1.invalidElement }
            if [.tableHeader, .tableCell].contains(value.role), byID[value.parentSemanticID ?? ""]?.role != .tableRow { throw GlobalizedAccessibleDocumentFailureV1.invalidElement }
            for headerID in value.tableHeaderSemanticIDs {
                guard let header = byID[headerID], header.role == .tableHeader,
                      let ownRow = value.parentSemanticID.flatMap({ byID[$0] }),
                      let headerRow = header.parentSemanticID.flatMap({ byID[$0] }),
                      ownRow.parentSemanticID == headerRow.parentSemanticID else { throw GlobalizedAccessibleDocumentFailureV1.invalidElement }
            }
            ancestors.append(value.semanticID)
        }
    }
}

/// Immutable input and environment provenance embedded in the PDF before its
/// output hash exists. It deliberately excludes output identity to avoid a
/// circular PDF metadata dependency.
struct GlobalizedDocumentPDFMetadataV1: Codable, Equatable, Sendable {
    static let prefix = "FE_GLOBALIZED_DOCUMENT_V1:"
    let rendererID: String
    let rendererVersion: String
    let sourceSHA256: String
    let sourceCreatedAtMilliseconds: Int64
    let sourceContentSHA256: String
    let paper: LocalePaperLayoutV1
    let language: ReportLanguageSelectionV1
    let formatting: FormattingLocaleProfileV1
    let orderedSemanticIDs: [String]
    let semantics: [GlobalizedDocumentSemanticRecordV1]
    let fonts: [GlobalizedDocumentFontProvenanceV1]
    let operatingSystemBuild: String
    let sourceTextFormattingApplied: Bool

    func validate() throws {
        guard rendererID == GlobalizedDocumentRenderReceiptV1.rendererID,
              rendererVersion == GlobalizedDocumentRenderReceiptV1.rendererVersion,
              KernelCanonicalHashV1.validSHA256(sourceSHA256), KernelCanonicalHashV1.validSHA256(sourceContentSHA256),
              paper.widthPoints > 0, paper.heightPoints > 0, !orderedSemanticIDs.isEmpty,
              Set(orderedSemanticIDs).count == orderedSemanticIDs.count,
              orderedSemanticIDs.allSatisfy(SnapshotProjectionValidationV1.validID),
              semantics.map(\.semanticID) == orderedSemanticIDs,
              !fonts.isEmpty, Set(fonts).count == fonts.count,
              fonts == fonts.sorted(by: { ($0.postScriptName, $0.fontFileSHA256, $0.versionName) < ($1.postScriptName, $1.fontFileSHA256, $1.versionName) }),
              !operatingSystemBuild.isEmpty, !sourceTextFormattingApplied else { throw GlobalizedAccessibleDocumentFailureV1.invalidRequest }
        _ = try ReportLanguageSelectionV1(requestedLanguage: language.requestedLanguage, effectiveLanguage: language.effectiveLanguage, fallback: language.fallback)
        _ = try FormattingLocaleProfileV1(localeIdentifier: formatting.localeIdentifier, ianaTimeZoneIdentifier: formatting.ianaTimeZoneIdentifier, calendar: formatting.calendar, numberingSystem: formatting.numberingSystem, units: formatting.units)
        try fonts.forEach { try $0.validate() }
        try GlobalizedDocumentSemanticRecordV1.validateOrder(semantics)
        guard paper == (try LocaleFormattingServiceV1(profile: formatting).paperLayout(paper.paperSize)) else { throw GlobalizedAccessibleDocumentFailureV1.invalidRequest }
    }

    func encodedKeyword() throws -> String {
        try validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return Self.prefix + (try encoder.encode(self)).base64EncodedString()
    }

    static func decodeKeyword(_ value: String) throws -> Self {
        guard value.hasPrefix(prefix), let data = Data(base64Encoded: String(value.dropFirst(prefix.count))) else { throw GlobalizedAccessibleDocumentFailureV1.pdfValidationFailed }
        let decoded = try JSONDecoder().decode(Self.self, from: data); try decoded.validate(); return decoded
    }
}

struct GlobalizedDocumentRenderReceiptV1: Codable, Equatable, Sendable {
    static let rendererID = "globalized-accessible-document-renderer"
    static let rendererVersion = "v1"
    let rendererID: String
    let rendererVersion: String
    let sourceSHA256: String
    let sourceCreatedAtMilliseconds: Int64
    let sourceContentSHA256: String
    let paper: LocalePaperLayoutV1
    let language: ReportLanguageSelectionV1
    let formatting: FormattingLocaleProfileV1
    let orderedSemanticIDs: [String]
    let fonts: [GlobalizedDocumentFontProvenanceV1]
    let operatingSystemBuild: String
    let outputSHA256: String
    let outputByteCount: Int64
    /// The first two facts cover outlineSubset fonts only; color-glyph fonts
    /// use embedded images and ActualText, recorded independently below.
    /// Facts below are native technical observations only. They are not a
    /// license opinion, PDF/UA claim, accessibility certification, or proof of
    /// suitability on another OS build.
    let nativeFontEmbeddingObserved: Bool
    let nativeToUnicodeObserved: Bool
    let nativeColorGlyphImagesObserved: Bool
    let pendingExternalQualification: Bool

    func validate() throws {
        guard rendererID == Self.rendererID, rendererVersion == Self.rendererVersion,
              KernelCanonicalHashV1.validSHA256(sourceSHA256), KernelCanonicalHashV1.validSHA256(sourceContentSHA256),
              KernelCanonicalHashV1.validSHA256(outputSHA256), outputByteCount > 0,
              paper.widthPoints > 0, paper.heightPoints > 0,
              !orderedSemanticIDs.isEmpty, Set(orderedSemanticIDs).count == orderedSemanticIDs.count,
              orderedSemanticIDs.allSatisfy(SnapshotProjectionValidationV1.validID),
               !fonts.isEmpty, Set(fonts).count == fonts.count,
               fonts == fonts.sorted(by: { ($0.postScriptName, $0.fontFileSHA256, $0.versionName) < ($1.postScriptName, $1.fontFileSHA256, $1.versionName) }),
              !operatingSystemBuild.isEmpty, nativeFontEmbeddingObserved, nativeToUnicodeObserved,
              nativeColorGlyphImagesObserved == fonts.contains(where: { $0.embedding == .colorGlyphImages }),
              pendingExternalQualification else { throw GlobalizedAccessibleDocumentFailureV1.invalidRequest }
        _ = try ReportLanguageSelectionV1(requestedLanguage: language.requestedLanguage, effectiveLanguage: language.effectiveLanguage, fallback: language.fallback)
        _ = try FormattingLocaleProfileV1(localeIdentifier: formatting.localeIdentifier, ianaTimeZoneIdentifier: formatting.ianaTimeZoneIdentifier, calendar: formatting.calendar, numberingSystem: formatting.numberingSystem, units: formatting.units)
        try fonts.forEach { try $0.validate() }
        guard paper == (try LocaleFormattingServiceV1(profile: formatting).paperLayout(paper.paperSize)) else { throw GlobalizedAccessibleDocumentFailureV1.invalidRequest }
    }
}

struct GlobalizedDocumentRenderResultV1: Sendable {
    let pdf: RenderedPDFV1
    let receipt: GlobalizedDocumentRenderReceiptV1
}

enum GlobalizedDocumentCanonicalV1 {
    static func sourceContentDigest(_ elements: [GlobalizedDocumentElementV1]) throws -> String {
        struct Record: Codable {
            let semanticID: String; let role: AccessibleDocumentRoleV1; let textUTF8: Data?
            let headingLevel: Int?; let evidenceID: String?; let evidenceSHA256: String?
            let imageSHA256: String?; let imageByteCount: Int?; let alternateTextUTF8: Data?
            let alternateTextProvenance: AccessibleAlternateTextProvenanceV1?
            let maximumImageWidthPoints: Double?; let maximumImageHeightPoints: Double?; let keepWithNext: Bool
            let parentSemanticID: String?; let tableHeaderScope: AccessibleTableHeaderScopeV1?
            let tableHeaderSemanticIDs: [String]; let decorative: Bool
        }
        let records = elements.map { element in
            Record(semanticID: element.semanticID, role: element.role, textUTF8: element.text.map { Data($0.utf8) }, headingLevel: element.headingLevel, evidenceID: element.evidenceID, evidenceSHA256: element.evidenceSHA256, imageSHA256: element.imageData.map(KernelCanonicalHashV1.sha256), imageByteCount: element.imageData?.count, alternateTextUTF8: element.alternateText.map { Data($0.utf8) }, alternateTextProvenance: element.alternateTextProvenance, maximumImageWidthPoints: element.maximumImageWidthPoints, maximumImageHeightPoints: element.maximumImageHeightPoints, keepWithNext: element.keepWithNext, parentSemanticID: element.parentSemanticID, tableHeaderScope: element.tableHeaderScope, tableHeaderSemanticIDs: element.tableHeaderSemanticIDs, decorative: element.decorative)
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return KernelCanonicalHashV1.sha256(try encoder.encode(records))
    }
}

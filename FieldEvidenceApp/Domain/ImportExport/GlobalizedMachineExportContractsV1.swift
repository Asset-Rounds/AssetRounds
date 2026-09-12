import Foundation

/// Presentation-independent grammar. Date grammars may refine TEXT columns;
/// no canonical import schema enum or stored record format is changed.
enum GlobalizedMachineScalarGrammarV1: String, Codable, Sendable {
    case text = "TEXT", identifier = "IDENTIFIER", integer = "INTEGER"
    case decimal = "DECIMAL", boolean = "BOOLEAN"
    case gregorianDate = "GREGORIAN_DATE", utcTimestamp = "UTC_TIMESTAMP"
}

enum GlobalizedCSVDelimiterV1: UInt8, Codable, CaseIterable, Sendable {
    case comma = 44, semicolon = 59, tab = 9
}

struct GlobalizedMachineColumnGrammarV1: Codable, Equatable, Sendable {
    let key: String
    let grammar: GlobalizedMachineScalarGrammarV1
}

struct GlobalizedMachineRowV1: Codable, Equatable, Sendable {
    let sourceOrdinal: UInt64
    let stableExternalKey: String
    let fields: [ImportMappedFieldV1]
}

enum GlobalizedMachineReferenceKindV1: String, Codable, Sendable {
    case media = "MEDIA", signature = "SIGNATURE"
}

/// A signature reference identifies source bytes; it makes no verification or
/// signer-identity claim. Bytes are supplied separately under the existing
/// content-reference contract, never inferred from a translated filename.
struct GlobalizedMachineReferenceV1: Codable, Equatable, Sendable {
    let sourceOrdinal: UInt64
    let kind: GlobalizedMachineReferenceKindV1
    let reference: OutputScopedContentReferenceV1
}

struct GlobalizedMachineTableV1: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let workspaceID: WorkspaceID
    let schemaRelease: ImportSchemaReleaseV1
    let columns: [GlobalizedMachineColumnGrammarV1]
    let rows: [GlobalizedMachineRowV1]
    let references: [GlobalizedMachineReferenceV1]

    init(workspaceID: WorkspaceID, schemaRelease: ImportSchemaReleaseV1,
         columns: [GlobalizedMachineColumnGrammarV1], rows: [GlobalizedMachineRowV1],
         references: [GlobalizedMachineReferenceV1] = []) {
        schemaVersion = 1
        self.workspaceID = workspaceID
        self.schemaRelease = schemaRelease
        self.columns = columns
        self.rows = rows
        self.references = references
    }
}

struct GlobalizedHumanCSVHeaderBindingV1: Codable, Equatable, Sendable {
    let columnKey: String
    let localizationKey: LocalizationKeyV1
}

struct GlobalizedHumanCSVRequestV1: Sendable {
    let catalog: V30CatalogResolutionV1
    let formatting: FormattingLocaleProfileV1
    let headers: [GlobalizedHumanCSVHeaderBindingV1]
    let delimiter: GlobalizedCSVDelimiterV1
}

struct GlobalizedHumanCSVHeaderV1: Codable, Equatable, Sendable {
    let binding: GlobalizedHumanCSVHeaderBindingV1
    let value: String
}

struct GlobalizedHumanCSVManifestV1: Codable, Equatable, Sendable {
    let artifactKind: String
    let displayOnly: Bool
    let requestedLanguage: AppLanguageTagV1
    let effectiveLanguage: AppLanguageTagV1
    let fallback: String
    let catalog: V30CatalogReleaseDescriptorV1
    let formatting: FormattingLocaleProfileV1
    let formatterVersion: String
    let formattingEnvironment: String
    let delimiter: GlobalizedCSVDelimiterV1
    let headers: [GlobalizedHumanCSVHeaderV1]
    let csvSHA256: String
}

struct GlobalizedMachineExportManifestV1: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let machineArtifactKind: String
    let machineJSONSHA256: String
    let machineCSVSHA256: String
    let schemaSHA256: String
    let machineDelimiter: GlobalizedCSVDelimiterV1
    let csvDialect: String
    let references: [GlobalizedMachineReferenceV1]
    let human: GlobalizedHumanCSVManifestV1?
}

/// Files are distinct by construction. The required manifest carries every
/// media/signature reference even for consumers displaying only the CSV.
struct GlobalizedMachineExportArtifactsV1: Equatable, Sendable {
    let machineJSON: Data
    let machineCSV: Data
    let manifestJSON: Data
    let humanCSV: Data?
}

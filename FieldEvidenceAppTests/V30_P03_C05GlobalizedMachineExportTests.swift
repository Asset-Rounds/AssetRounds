import Foundation
import XCTest
@testable import FieldEvidenceApp

final class V30P03C05GlobalizedMachineExportTests: XCTestCase {
    func testMachineJSONAndCSVRoundTripPreserveAuthoredUTF8Bytes() throws {
        let fixture = try C05.fixture()
        XCTAssertEqual(fixture.schema, "V30P03C05GlobalizedMachineExportCasesV1")
        XCTAssertEqual(fixture.cardID, "V30-P03-C05")
        XCTAssertEqual(fixture.machineHeaders, ["asset_key", "notes"])
        XCTAssertEqual(fixture.languageMatrixFixtureOnly.count, 6)
        XCTAssertEqual(fixture.qualificationClaim, "NONE")
        let table = try C05.table(notes: fixture.authoredUTF8)
        let artifacts = try GlobalizedMachineExportAdapterV1.export(table)
        let reopened = try GlobalizedMachineExportAdapterV1.importMachine(artifacts)

        XCTAssertEqual(artifacts.machineJSON, try ImportBulkCanonicalCodecV1.encode(reopened))
        XCTAssertEqual(Data(reopened.rows[0].fields[1].value.utf8), Data(table.rows[0].fields[1].value.utf8))
        XCTAssertEqual(try GlobalizedMachineCSVCodecV1.decode(artifacts.machineCSV), [
            ["asset_key", "notes"], ["asset-001", table.rows[0].fields[1].value]
        ])
        XCTAssertEqual(try GlobalizedMachineCSVCodecV1.encode(rows: try GlobalizedMachineCSVCodecV1.decode(artifacts.machineCSV)), artifacts.machineCSV)
        XCTAssertEqual(try GlobalizedMachineExportAdapterV1.parseMachineCSV(
            artifacts.machineCSV, workspaceID: table.workspaceID,
            schemaRelease: table.schemaRelease, columns: table.columns,
            rowOrdinals: table.rows.map(\.sourceOrdinal), references: table.references
        ), table)
    }

    func testMachineHeadersAreIndependentOfOptionalHumanProfile() throws {
        let table = try C05.table(notes: "12.50")
        let machine = try GlobalizedMachineExportAdapterV1.export(table)
        let human = try GlobalizedMachineExportAdapterV1.export(table, human: C05.humanRequest())
        XCTAssertEqual(machine.machineJSON, human.machineJSON)
        XCTAssertEqual(machine.machineCSV, human.machineCSV)
        XCTAssertEqual(try GlobalizedMachineCSVCodecV1.decode(human.machineCSV).first, ["asset_key", "notes"])
        XCTAssertNotNil(human.humanCSV)
        XCTAssertEqual(try GlobalizedMachineExportAdapterV1.importMachine(human), table)
    }

    func testLocalizedHumanDecimalReplayAndEnglishFallbackStaySeparateFromMachine() throws {
        let table = try C05.typedTable()
        let english = try C05.typedHumanRequest(locale: "en-US", requestedLanguage: .english)
        let spanishFallback = try C05.typedHumanRequest(
            locale: "es-ES", requestedLanguage: try .init("es")
        )
        let en = try GlobalizedMachineExportAdapterV1.export(table, human: english)
        let es = try GlobalizedMachineExportAdapterV1.export(table, human: spanishFallback)
        XCTAssertEqual(en.machineJSON, es.machineJSON)
        XCTAssertEqual(en.machineCSV, es.machineCSV)
        XCTAssertNotEqual(en.humanCSV, es.humanCSV)
        let manifest = try ImportBulkCanonicalCodecV1.decode(
            GlobalizedMachineExportManifestV1.self, from: es.manifestJSON)
        let provenance = try XCTUnwrap(manifest.human)
        XCTAssertEqual(provenance.requestedLanguage.rawValue, "es")
        XCTAssertEqual(provenance.effectiveLanguage, .english)
        XCTAssertEqual(provenance.fallback, V30CatalogFallbackReasonV1.englishRequestedLanguageUnavailable.rawValue)
        XCTAssertEqual(provenance.catalog.releaseID, spanishFallback.catalog.archive.descriptor.releaseID)
        XCTAssertEqual(provenance.formatting.localeIdentifier, "es-ES")
        XCTAssertEqual(provenance.formattingEnvironment, ProcessInfo.processInfo.operatingSystemVersionString)
        let humanCells = try GlobalizedMachineCSVCodecV1.decode(try XCTUnwrap(es.humanCSV), delimiter: 59)
        XCTAssertEqual(humanCells[1][0], try LocaleFormattingServiceV1(profile: spanishFallback.formatting)
            .formatDecimal(Decimal(string: "12345.50", locale: Locale(identifier: "en_US_POSIX"))!))
        XCTAssertEqual(try GlobalizedMachineExportAdapterV1.importMachine(es, replayHuman: spanishFallback), table)
        XCTAssertThrowsError(try GlobalizedMachineExportAdapterV1.importMachine(es, replayHuman: english))
        let localizedNumeric = try GlobalizedMachineCSVCodecV1.encode(rows: [["amount", "asset_key", "count", "due"], ["12,50", "asset-002", "12", "2024-02-29"]])
        XCTAssertThrowsError(try GlobalizedMachineExportAdapterV1.parseMachineCSV(
            localizedNumeric, workspaceID: table.workspaceID, schemaRelease: table.schemaRelease,
            columns: table.columns
        ))
        XCTAssertThrowsError(try GlobalizedMachineExportAdapterV1.parseMachineCSV(
            try XCTUnwrap(es.humanCSV), workspaceID: table.workspaceID,
            schemaRelease: table.schemaRelease, columns: table.columns
        ))
    }

    func testCSVWireDialectKeepsNilEmptyAndEscapedPrefixValuesDistinct() throws {
        let values: [[String?]] = [[nil, "", "=x", "+1", "-1", "@command", "\rline", "\t=tab", "\u{2060} -12", "'=x", "\\N", "\\\\N"]]
        let bytes = try GlobalizedMachineCSVCodecV1.encode(rows: values)
        XCTAssertEqual(try GlobalizedMachineCSVCodecV1.decode(bytes), values)
        XCTAssertEqual(try GlobalizedMachineCSVCodecV1.encode(rows: try GlobalizedMachineCSVCodecV1.decode(bytes)), bytes)
        XCTAssertNotNil(bytes.range(of: Data("\"'=x\"".utf8)))
        XCTAssertNotNil(bytes.range(of: Data("\"''=x\"".utf8)))
        XCTAssertNotNil(bytes.range(of: Data("\"\\N\"".utf8)))
        XCTAssertNotNil(bytes.range(of: Data("\"\\\\N\"".utf8)))
    }

    func testStrictMachineScalarGrammarsRejectAmbiguousInputs() throws {
        for value in ["0", "-1", "9223372036854775807", "-9223372036854775808"] {
            XCTAssertNoThrow(try GlobalizedMachineScalarCodecV1.validate(value, grammar: .integer))
        }
        for value in ["+1", "01", "-0", "9223372036854775808"] {
            XCTAssertThrowsError(try GlobalizedMachineScalarCodecV1.validate(value, grammar: .integer))
        }
        for value in ["0", "-0", "12.50", "12345678901234567890123456789012345678"] {
            XCTAssertNoThrow(try GlobalizedMachineScalarCodecV1.validate(value, grammar: .decimal))
        }
        for value in ["1,000", "1.000,0", "1e3", ".5", "01.2", "1.", "123456789012345678901234567890123456789"] {
            XCTAssertThrowsError(try GlobalizedMachineScalarCodecV1.validate(value, grammar: .decimal))
        }
        for value in ["2024-02-29", "2024-02-29T12:34:56.789Z"] {
            XCTAssertNoThrow(try GlobalizedMachineScalarCodecV1.validate(
                value, grammar: value.contains("T") ? .utcTimestamp : .gregorianDate
            ))
        }
        for value in ["02/29/2024", "2024-02-30", "2024-02-29T12:34:56Z", "2024-02-29T23:59:60.000Z"] {
            XCTAssertThrowsError(try GlobalizedMachineScalarCodecV1.validate(
                value, grammar: value.contains("T") ? .utcTimestamp : .gregorianDate
            ))
        }
        XCTAssertNoThrow(try GlobalizedMachineScalarCodecV1.validate("TRUE", grammar: .boolean))
        XCTAssertThrowsError(try GlobalizedMachineScalarCodecV1.validate("true", grammar: .boolean))
    }

    func testManifestReferencesAndMalformedCSVFailClosed() throws {
        let artifacts = try GlobalizedMachineExportAdapterV1.export(try C05.table(notes: "safe"))
        var trailing = artifacts.manifestJSON; trailing.append(0x20)
        XCTAssertThrowsError(try GlobalizedMachineExportAdapterV1.importMachine(.init(
            machineJSON: artifacts.machineJSON, machineCSV: artifacts.machineCSV,
            manifestJSON: trailing, humanCSV: artifacts.humanCSV
        )))
        var changedCSV = artifacts.machineCSV; changedCSV.append(0x20)
        XCTAssertThrowsError(try GlobalizedMachineExportAdapterV1.importMachine(.init(
            machineJSON: artifacts.machineJSON, machineCSV: changedCSV,
            manifestJSON: artifacts.manifestJSON, humanCSV: artifacts.humanCSV
        )))
        XCTAssertThrowsError(try GlobalizedMachineCSVCodecV1.encode(rows: [["\u{0001}"]]))
        XCTAssertThrowsError(try GlobalizedMachineCSVCodecV1.encode(rows: [Array(repeating: "x", count: 129)]))
        let oversizedWire = "\"" + String(repeating: "a", count: ImportBulkLimitsV1.maximumCellBytes + 1) + "\"\r\n"
        XCTAssertThrowsError(try GlobalizedMachineCSVCodecV1.decode(Data(oversizedWire.utf8)))
        XCTAssertThrowsError(try GlobalizedMachineCSVCodecV1.decode(Data("asset_key,notes\nasset-001,x\n".utf8)))
        XCTAssertThrowsError(try GlobalizedMachineCSVCodecV1.decode(Data("\"asset_key\"\r\"x\"".utf8)))
        XCTAssertThrowsError(try GlobalizedMachineExportAdapterV1.export(try C05.table(
            notes: "safe", references: [try C05.reference(sourceOrdinal: 2, ordinal: 0, workspace: C05.workspace)]
        )))
        let otherWorkspace = WorkspaceID(rawValue: UUID(uuidString: "c0500000-0000-4000-8000-000000000099")!)
        XCTAssertThrowsError(try GlobalizedMachineExportAdapterV1.export(try C05.table(
            notes: "safe", references: [try C05.reference(sourceOrdinal: 1, ordinal: 0, workspace: otherWorkspace)]
        )))
        XCTAssertThrowsError(try GlobalizedMachineExportAdapterV1.export(
            try C05.table(notes: String(repeating: "a", count: ImportBulkLimitsV1.maximumCellBytes + 1))
        ))
    }

    func testTableOptionalEmptyAndMediaSignatureReferencesRoundTrip() throws {
        let media = try C05.reference(sourceOrdinal: 1, kind: .media, ordinal: 0, workspace: C05.workspace)
        let signature = try C05.reference(sourceOrdinal: 1, kind: .signature, ordinal: 1, workspace: C05.workspace)
        let table = try C05.table(notes: nil, references: [media, signature].sorted {
            $0.reference.outputReferenceID < $1.reference.outputReferenceID
        })
        let artifacts = try GlobalizedMachineExportAdapterV1.export(table)
        let opened = try GlobalizedMachineExportAdapterV1.importMachine(artifacts)
        XCTAssertNil(opened.rows[0].fields.first { $0.key == "notes" })
        XCTAssertEqual(opened.references, table.references)
        XCTAssertEqual(try ImportBulkCanonicalCodecV1.decode(GlobalizedMachineExportManifestV1.self, from: artifacts.manifestJSON).references, table.references)
        let empty = try GlobalizedMachineExportAdapterV1.importMachine(
            try GlobalizedMachineExportAdapterV1.export(try C05.table(notes: ""))
        )
        XCTAssertEqual(empty.rows[0].fields.first { $0.key == "notes" }?.value, "")
    }
}

private enum C05 {
    struct Fixture: Decodable {
        let schema: String
        let schemaVersion: Int
        let cardID: String
        let languageMatrixFixtureOnly: [String]
        let qualificationClaim: String
        let machineHeaders: [String]
        let authoredUTF8: String
    }

    static let workspace = WorkspaceID(rawValue: UUID(uuidString: "c0500000-0000-4000-8000-000000000001")!)

    static func table(notes: String?, references: [GlobalizedMachineReferenceV1] = []) throws -> GlobalizedMachineTableV1 {
        let schema = try ImportSchemaReleaseV1(
            releaseID: "v30-c05", release: 1, entityKind: .asset,
            externalKeyColumn: "asset_key", columns: [
                try .init(key: "asset_key", scalar: .identifier, required: true, editableOnExactUpdate: false, maximumCellBytes: 128, maximumScalars: 128),
                try .init(key: "notes", scalar: .text, required: false, editableOnExactUpdate: true, maximumCellBytes: 16_384, maximumScalars: 8_192),
            ], budget: try .init(maximumSourceBytes: 64 * 1_024 * 1_024, maximumRows: 100_000, maximumColumns: 128, maximumCellBytes: 16_384, maximumScalarsPerCell: 8_192)
        )
        var fields = [try ImportMappedFieldV1(key: "asset_key", value: "asset-001")]
        if let notes { fields.append(try .init(key: "notes", value: notes)) }
        return .init(workspaceID: workspace, schemaRelease: schema, columns: [
            .init(key: "asset_key", grammar: .identifier), .init(key: "notes", grammar: .text),
        ], rows: [.init(sourceOrdinal: 1, stableExternalKey: "asset-001", fields: fields)], references: references)
    }

    static func reference(sourceOrdinal: UInt64, kind: GlobalizedMachineReferenceKindV1 = .media, ordinal: Int, workspace: WorkspaceID) throws -> GlobalizedMachineReferenceV1 {
        let hex = kind == .media ? "a" : "b"
        let digest = try ContentDigestV1(algorithm: .sha256, hexadecimalValue: String(repeating: hex, count: 64))
        let content = try ContentReferenceV1(workspaceID: workspace.rawValue.uuidString.lowercased(), contentID: "c05-\(kind.rawValue.lowercased())-\(ordinal)", byteLength: 12 + Int64(ordinal), mediaType: "image/jpeg", digests: .init([digest]), byteRole: .derivative, createdAt: "2026-09-12T00:00:00.000Z")
        return try .init(sourceOrdinal: sourceOrdinal, kind: kind, reference: .init(outputScopeID: "c05-output", ordinal: ordinal, reference: content))
    }

    static func humanRequest(locale: String = "en-US", requestedLanguage: AppLanguageTagV1 = .english) throws -> GlobalizedHumanCSVRequestV1 {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try Data(contentsOf: root.appendingPathComponent("FieldEvidenceApp/Resources/Localizable.xcstrings"))
        let registry = try V30EnglishCatalogRegistryV1.registry()
        let locales = LocalizationLocaleManifestV1.shippingV1()
        let archive = try BundledLocalizationCatalogV1.loadInheritedRelease(
            sourceCatalogBytes: source, registryBytes: LocalizationContractCanonicalCodecV1.encode(registry),
            localeManifestBytes: LocalizationContractCanonicalCodecV1.encode(locales)
        ).archive
        let fallback: V30CatalogFallbackReasonV1 = requestedLanguage == .english ? .exact : .englishRequestedLanguageUnavailable
        return .init(catalog: .init(requestedLanguage: requestedLanguage, archive: archive, fallback: fallback),
            formatting: try .init(localeIdentifier: locale, ianaTimeZoneIdentifier: "Etc/UTC", calendar: .gregorian, numberingSystem: .latin, units: .metric),
            headers: [try .init(columnKey: "asset_key", localizationKey: .init("common.done")), try .init(columnKey: "notes", localizationKey: .init("recovery.center.action.cancel"))], delimiter: .semicolon)
    }

    static func typedHumanRequest(locale: String, requestedLanguage: AppLanguageTagV1) throws -> GlobalizedHumanCSVRequestV1 {
        let basic = try humanRequest(locale: locale, requestedLanguage: requestedLanguage)
        return .init(catalog: basic.catalog, formatting: basic.formatting, headers: [
            try .init(columnKey: "amount", localizationKey: .init("common.done")),
            try .init(columnKey: "asset_key", localizationKey: .init("recovery.center.action.cancel")),
            try .init(columnKey: "count", localizationKey: .init("common.done")),
            try .init(columnKey: "due", localizationKey: .init("recovery.center.action.cancel")),
        ], delimiter: basic.delimiter)
    }

    static func typedTable() throws -> GlobalizedMachineTableV1 {
        let schema = try ImportSchemaReleaseV1(releaseID: "v30-c05-typed", release: 1, entityKind: .asset, externalKeyColumn: "asset_key", columns: [
            try .init(key: "amount", scalar: .decimal, required: true, editableOnExactUpdate: true, maximumCellBytes: 128, maximumScalars: 128),
            try .init(key: "asset_key", scalar: .identifier, required: true, editableOnExactUpdate: false, maximumCellBytes: 128, maximumScalars: 128),
            try .init(key: "count", scalar: .integer, required: true, editableOnExactUpdate: true, maximumCellBytes: 128, maximumScalars: 128),
            try .init(key: "due", scalar: .text, required: true, editableOnExactUpdate: true, maximumCellBytes: 128, maximumScalars: 128),
        ], budget: try .init(maximumSourceBytes: 64 * 1_024 * 1_024, maximumRows: 100_000, maximumColumns: 128, maximumCellBytes: 16_384, maximumScalarsPerCell: 8_192))
        return .init(workspaceID: workspace, schemaRelease: schema, columns: [
            .init(key: "amount", grammar: .decimal), .init(key: "asset_key", grammar: .identifier), .init(key: "count", grammar: .integer), .init(key: "due", grammar: .gregorianDate),
        ], rows: [.init(sourceOrdinal: 1, stableExternalKey: "asset-002", fields: [
            try .init(key: "amount", value: "12345.50"), try .init(key: "asset_key", value: "asset-002"), try .init(key: "count", value: "12345"), try .init(key: "due", value: "2024-02-29"),
        ])])
    }

    static func fixture() throws -> Fixture {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/V30/ImportExport/globalized-machine-export-cases-v1.json")
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }
}

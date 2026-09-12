import Foundation

/// Stateless boundary for existing C08 import/export. No locale preferences,
/// source mutation, persistence, file I/O, or new writer live in this adapter.
enum GlobalizedMachineExportAdapterV1 {
    static let csvDialect = "V30_QUOTED_UTF8_CRLF_REVERSIBLE_PREFIX_V1"
    static let formatterVersion = "V30_LOCALE_FORMATTING_V1"

    static func export(
        _ table: GlobalizedMachineTableV1,
        human: GlobalizedHumanCSVRequestV1? = nil
    ) throws -> GlobalizedMachineExportArtifactsV1 {
        try validate(table)
        let json = try ImportBulkCanonicalCodecV1.encode(table)
        try bounded(json, maximum: table.schemaRelease.budget.maximumSourceBytes)
        let csv = try machineCSV(table)
        var humanCSV: Data?
        var humanManifest: GlobalizedHumanCSVManifestV1?
        if let human {
            let rendered = try renderHuman(table, request: human)
            humanCSV = rendered.0
            humanManifest = rendered.1
        }
        let manifest = GlobalizedMachineExportManifestV1(
            schemaVersion: 1, machineArtifactKind: "CANONICAL_MACHINE_TABLE_V1",
            machineJSONSHA256: KernelCanonicalHashV1.sha256(json),
            machineCSVSHA256: KernelCanonicalHashV1.sha256(csv),
            schemaSHA256: table.schemaRelease.schemaSHA256, machineDelimiter: .comma,
            csvDialect: csvDialect, references: table.references, human: humanManifest
        )
        let manifestJSON = try ImportBulkCanonicalCodecV1.encode(manifest)
        try bounded(manifestJSON)
        return .init(machineJSON: json, machineCSV: csv,
                     manifestJSON: manifestJSON, humanCSV: humanCSV)
    }

    /// Parses the declared machine dialect with an explicit schema. Header
    /// labels, dates, decimals and identifiers are never inferred from locale.
    /// A manifest may supply original row ordinals and media associations;
    /// otherwise ordinals describe the records in this particular source file.
    static func parseMachineCSV(
        _ data: Data,
        workspaceID: WorkspaceID,
        schemaRelease: ImportSchemaReleaseV1,
        columns: [GlobalizedMachineColumnGrammarV1],
        rowOrdinals: [UInt64]? = nil,
        references: [GlobalizedMachineReferenceV1] = []
    ) throws -> GlobalizedMachineTableV1 {
        try schemaRelease.validate()
        try bounded(data, maximum: schemaRelease.budget.maximumSourceBytes)
        let cells = try GlobalizedMachineCSVCodecV1.decode(data)
        guard cells.count <= schemaRelease.budget.maximumRows + 1,
              cells.allSatisfy({ $0.count == schemaRelease.columns.count }),
              cells[0] == schemaRelease.columns.map({ Optional($0.key) }),
              try GlobalizedMachineCSVCodecV1.encode(rows: cells) == data else {
            throw ImportBulkFailureV1.invalidValue
        }
        let ordinals = rowOrdinals ?? cells.dropFirst().indices.map { UInt64($0) }
        guard ordinals.count == cells.count - 1 else { throw ImportBulkFailureV1.invalidValue }
        let rows = try zip(ordinals, cells.dropFirst()).map { ordinal, values -> GlobalizedMachineRowV1 in
            let fields = try zip(schemaRelease.columns, values).compactMap { column, value -> ImportMappedFieldV1? in
                guard let value else { return nil }
                return try ImportMappedFieldV1(key: column.key, value: value)
            }
            guard let key = fields.first(where: { $0.key == schemaRelease.externalKeyColumn })?.value else {
                throw ImportBulkFailureV1.invalidValue
            }
            return .init(sourceOrdinal: ordinal, stableExternalKey: key, fields: fields)
        }
        let table = GlobalizedMachineTableV1(workspaceID: workspaceID, schemaRelease: schemaRelease,
            columns: columns, rows: rows, references: references)
        try validate(table)
        return table
    }

    /// Rehydrates only the machine files. A human artifact cannot supply keys,
    /// numbers, dates, identity, or mutation authority. Optional replay proves
    /// its exact catalog/formatting binding against the supplied archive.
    static func importMachine(
        _ artifacts: GlobalizedMachineExportArtifactsV1,
        replayHuman: GlobalizedHumanCSVRequestV1? = nil
    ) throws -> GlobalizedMachineTableV1 {
        try bounded(artifacts.machineJSON)
        try bounded(artifacts.machineCSV)
        try bounded(artifacts.manifestJSON)
        let table = try ImportBulkCanonicalCodecV1.decode(
            GlobalizedMachineTableV1.self, from: artifacts.machineJSON
        )
        let manifest = try ImportBulkCanonicalCodecV1.decode(
            GlobalizedMachineExportManifestV1.self, from: artifacts.manifestJSON
        )
        try validate(table)
        try bounded(artifacts.machineJSON, maximum: table.schemaRelease.budget.maximumSourceBytes)
        guard manifest.schemaVersion == 1,
              manifest.machineArtifactKind == "CANONICAL_MACHINE_TABLE_V1",
              manifest.machineDelimiter == .comma, manifest.csvDialect == csvDialect,
              manifest.machineJSONSHA256 == KernelCanonicalHashV1.sha256(artifacts.machineJSON),
              manifest.machineCSVSHA256 == KernelCanonicalHashV1.sha256(artifacts.machineCSV),
              manifest.schemaSHA256 == table.schemaRelease.schemaSHA256,
              try ImportBulkCanonicalCodecV1.encode(manifest.references)
                == ImportBulkCanonicalCodecV1.encode(table.references) else {
            throw ImportBulkFailureV1.digestMismatch
        }
        // Rebuild all fields from CSV and compare canonical JSON bytes. This
        // proves the parser preserves nil, literal prefixes and Unicode too.
        let parsed = try parseMachineCSV(artifacts.machineCSV, workspaceID: table.workspaceID,
            schemaRelease: table.schemaRelease, columns: table.columns,
            rowOrdinals: table.rows.map(\.sourceOrdinal), references: table.references)
        guard try ImportBulkCanonicalCodecV1.encode(parsed) == artifacts.machineJSON else {
            throw ImportBulkFailureV1.digestMismatch
        }
        switch (manifest.human, artifacts.humanCSV) {
        case (nil, nil):
            guard replayHuman == nil else { throw ImportBulkFailureV1.invalidValue }
        case let (human?, data?):
            try validateHumanManifest(human, table: table)
            try bounded(data, maximum: table.schemaRelease.budget.maximumSourceBytes)
            guard human.csvSHA256 == KernelCanonicalHashV1.sha256(data) else {
                throw ImportBulkFailureV1.digestMismatch
            }
            let cells = try GlobalizedMachineCSVCodecV1.decode(data, delimiter: human.delimiter.rawValue)
            guard cells.count == table.rows.count + 1,
                  cells.allSatisfy({ $0.count == table.columns.count }),
                  try GlobalizedMachineCSVCodecV1.encode(rows: cells, delimiter: human.delimiter.rawValue) == data,
                  try GlobalizedMachineCSVCodecV1.encode(rows: [cells[0]], delimiter: human.delimiter.rawValue)
                    == GlobalizedMachineCSVCodecV1.encode(rows: [human.headers.map { Optional($0.value) }], delimiter: human.delimiter.rawValue) else {
                throw ImportBulkFailureV1.invalidValue
            }
            if let replayHuman {
                let replay = try renderHuman(table, request: replayHuman)
                guard replay.0 == data,
                      try ImportBulkCanonicalCodecV1.encode(replay.1) == ImportBulkCanonicalCodecV1.encode(human) else {
                    throw ImportBulkFailureV1.digestMismatch
                }
            }
        default: throw ImportBulkFailureV1.invalidValue
        }
        return table
    }

    /// This admission guard augments the incumbent preview. ImportPlan still
    /// owns schema, revision, commands, row identity and zero-write semantics.
    static func validateImportPlan(
        _ plan: ImportPlanV1, artifacts: GlobalizedMachineExportArtifactsV1
    ) throws {
        let table = try importMachine(artifacts)
        try plan.validate()
        guard plan.workspaceID == table.workspaceID,
              plan.schemaRelease == table.schemaRelease,
              plan.source.sourceSHA256 == KernelCanonicalHashV1.sha256(artifacts.machineCSV),
              plan.source.byteCount == Int64(artifacts.machineCSV.count),
              plan.rows.count == table.rows.count else {
            throw ImportBulkFailureV1.changedInputQuarantined
        }
        for (row, planned) in zip(table.rows, plan.rows) {
            guard row.sourceOrdinal == planned.identity.sourceOrdinal,
                  Data(row.stableExternalKey.utf8) == Data(planned.identity.stableExternalKey.utf8),
                  try ImportBulkCanonicalCodecV1.encode(row.fields)
                    == ImportBulkCanonicalCodecV1.encode(planned.mappedFields) else {
                throw ImportBulkFailureV1.changedInputQuarantined
            }
        }
    }

    static func validate(_ table: GlobalizedMachineTableV1) throws {
        let schema = table.schemaRelease
        try schema.validate()
        guard table.schemaVersion == 1,
              table.columns.map(\.key) == schema.columns.map(\.key),
              table.rows.count <= schema.budget.maximumRows,
              table.references.count <= 1_000 else { throw ImportBulkFailureV1.invalidValue }
        for (column, declared) in zip(schema.columns, table.columns) {
            // Decoding ImportSchemaColumnV1 is synthesized in the incumbent;
            // re-run its initializer instead of trusting decoded constraints.
            _ = try ImportSchemaColumnV1(key: column.key, scalar: column.scalar,
                required: column.required, editableOnExactUpdate: column.editableOnExactUpdate,
                maximumCellBytes: column.maximumCellBytes, maximumScalars: column.maximumScalars)
            let scalar = column.scalar.rawValue
            guard declared.grammar.rawValue == scalar
                    || (column.scalar == .text && [.gregorianDate, .utcTimestamp].contains(declared.grammar)) else {
                throw ImportBulkFailureV1.unsupportedSchema
            }
        }
        let ordinals = table.rows.map(\.sourceOrdinal)
        try ImportBulkCanonicalCodecV1.requireSortedUnique(ordinals)
        // Byte identities are deliberate: Swift String equality folds NFC/NFD.
        guard Set(table.rows.map { Data($0.stableExternalKey.utf8) }).count == table.rows.count else {
            throw ImportBulkFailureV1.adapterCollision
        }
        var referencesByID: [String: OutputScopedContentReferenceV1] = [:]
        var previousOrdinal: UInt64 = 0
        var previousReferenceID = ""
        let ordinalSet = Set(ordinals)
        for binding in table.references {
            let reference = binding.reference
            try reference.validate()
            guard ordinalSet.contains(binding.sourceOrdinal),
                  binding.sourceOrdinal > previousOrdinal
                    || (binding.sourceOrdinal == previousOrdinal && reference.outputReferenceID > previousReferenceID),
                  reference.workspaceBindingSHA256 == KernelCanonicalHashV1.sha256(
                    Data("\(table.workspaceID.rawValue.uuidString.lowercased())|\(reference.outputScopeID)".utf8)) else {
                throw ImportBulkFailureV1.invalidValue
            }
            let namespace = KernelCanonicalHashV1.sha256(Data(
                "\(table.workspaceID.rawValue.uuidString.lowercased())|\(reference.outputScopeID)|\(reference.contentSHA256)".utf8))
            guard reference.outputReferenceID.hasPrefix("out-\(namespace.prefix(16))-") else {
                throw ImportBulkFailureV1.digestMismatch
            }
            if let prior = referencesByID[reference.outputReferenceID] {
                guard try ImportBulkCanonicalCodecV1.encode(prior)
                    == ImportBulkCanonicalCodecV1.encode(reference) else {
                    throw ImportBulkFailureV1.digestMismatch
                }
            }
            referencesByID[reference.outputReferenceID] = reference
            previousOrdinal = binding.sourceOrdinal
            previousReferenceID = reference.outputReferenceID
        }
        // Bound canonical JSON before serializing the full table. The empty
        // envelope plus each independently encoded row and comma is the exact
        // compact sorted-key JSON byte count; a hostile row cannot make the
        // encoder allocate the entire unbounded table before rejection.
        let envelope = GlobalizedMachineTableV1(workspaceID: table.workspaceID,
            schemaRelease: schema, columns: table.columns, rows: [], references: table.references)
        var canonicalByteCount = Int64(try ImportBulkCanonicalCodecV1.encode(envelope).count)
        guard canonicalByteCount <= schema.budget.maximumSourceBytes else {
            throw ImportBulkFailureV1.limitExceeded
        }
        var seenRows = 0
        for row in table.rows {
            try ImportBulkCanonicalCodecV1.requireText(row.stableExternalKey)
            guard row.sourceOrdinal > 0, row.sourceOrdinal <= UInt64(ImportBulkLimitsV1.maximumRows),
                  row.fields.map(\.key) == row.fields.map(\.key).sorted(),
                  Set(row.fields.map(\.key)).count == row.fields.count,
                  row.fields.count <= schema.columns.count else { throw ImportBulkFailureV1.invalidValue }
            let fields = Dictionary(uniqueKeysWithValues: row.fields.map { ($0.key, $0.value) })
            guard Set(fields.keys).isSubset(of: Set(table.columns.map(\.key))),
                  let externalKey = fields[schema.externalKeyColumn],
                  Data(externalKey.utf8) == Data(row.stableExternalKey.utf8) else {
                throw ImportBulkFailureV1.nonAllowlistedField
            }
            for (column, declared) in zip(schema.columns, table.columns) {
                guard let value = fields[column.key] else {
                    if column.required { throw ImportBulkFailureV1.invalidValue }
                    continue
                }
                guard value.utf8.count <= min(column.maximumCellBytes, schema.budget.maximumCellBytes),
                      value.unicodeScalars.count <= min(column.maximumScalars, schema.budget.maximumScalarsPerCell),
                      !column.required || !value.isEmpty else { throw ImportBulkFailureV1.limitExceeded }
                _ = try ImportMappedFieldV1(key: column.key, value: value)
                try GlobalizedMachineScalarCodecV1.validate(value, grammar: declared.grammar)
                // Shared safety validation also rejects unsupported controls;
                // it never trims or normalizes authored Unicode.
                _ = try GlobalizedMachineCSVCodecV1.encode(rows: [[value]])
            }
            canonicalByteCount += Int64(try ImportBulkCanonicalCodecV1.encode(row).count)
                + (seenRows == 0 ? 0 : 1)
            guard canonicalByteCount <= schema.budget.maximumSourceBytes else {
                throw ImportBulkFailureV1.limitExceeded
            }
            seenRows += 1
        }

    }

    private static func machineCSV(_ table: GlobalizedMachineTableV1) throws -> Data {
        var cells: [[String?]] = [table.columns.map { Optional($0.key) }]
        for row in table.rows {
            let fields = Dictionary(uniqueKeysWithValues: row.fields.map { ($0.key, $0.value) })
            cells.append(table.columns.map { fields[$0.key] })
        }
        let csv = try GlobalizedMachineCSVCodecV1.encode(rows: cells)
        try bounded(csv, maximum: table.schemaRelease.budget.maximumSourceBytes)
        return csv
    }

    private static func renderHuman(
        _ table: GlobalizedMachineTableV1, request: GlobalizedHumanCSVRequestV1
    ) throws -> (Data, GlobalizedHumanCSVManifestV1) {
        let archive = request.catalog.archive
        // Revalidate exact resources and resolution; a caller-created
        // V30CatalogResolution value cannot turn a fallback into an exact match.
        _ = try V30CatalogReleaseArchiveV1(descriptor: archive.descriptor,
            sourceCatalog: archive.sourceCatalog, registry: archive.registry, localeManifest: archive.localeManifest)
        guard request.headers.map(\.columnKey) == table.columns.map(\.key),
              resolutionIsValid(requested: request.catalog.requestedLanguage,
                  effective: request.catalog.effectiveLanguage, fallback: request.catalog.fallback.rawValue) else {
            throw ImportBulkFailureV1.invalidValue
        }
        let registry = try archive.keyRegistry()
        guard let catalog = try JSONSerialization.jsonObject(with: archive.sourceCatalog) as? [String: Any],
              let strings = catalog["strings"] as? [String: Any] else { throw ImportBulkFailureV1.invalidValue }
        var headers: [GlobalizedHumanCSVHeaderV1] = []
        for binding in request.headers {
            let definition = try registry.definition(for: binding.localizationKey)
            guard definition.arguments.isEmpty, definition.requiredEnglishPluralCategories.isEmpty,
                  let entry = strings[binding.localizationKey.rawValue] as? [String: Any],
                  let localizations = entry["localizations"] as? [String: Any],
                  let localized = localizations[request.catalog.effectiveLanguage.rawValue] as? [String: Any],
                  Set(localized.keys) == ["stringUnit"],
                  let unit = localized["stringUnit"] as? [String: Any],
                  let value = unit["value"] as? String, !value.isEmpty else {
                throw ImportBulkFailureV1.invalidValue
            }
            headers.append(.init(binding: binding, value: value))
        }
        let formatter = try LocaleFormattingServiceV1(profile: request.formatting)
        var cells: [[String?]] = [headers.map { Optional($0.value) }]
        for row in table.rows {
            let fields = Dictionary(uniqueKeysWithValues: row.fields.map { ($0.key, $0.value) })
            cells.append(try table.columns.map { column in
                guard let value = fields[column.key] else { return "" }
                return try GlobalizedMachineScalarCodecV1.display(value, grammar: column.grammar, formatter: formatter)
            })
        }
        let csv = try GlobalizedMachineCSVCodecV1.encode(rows: cells, delimiter: request.delimiter.rawValue)
        try bounded(csv, maximum: table.schemaRelease.budget.maximumSourceBytes)
        return (csv, .init(artifactKind: "LOCALIZED_HUMAN_CSV_V1", displayOnly: true,
            requestedLanguage: request.catalog.requestedLanguage, effectiveLanguage: request.catalog.effectiveLanguage,
            fallback: request.catalog.fallback.rawValue, catalog: archive.descriptor,
            formatting: request.formatting, formatterVersion: formatterVersion,
            formattingEnvironment: ProcessInfo.processInfo.operatingSystemVersionString,
            delimiter: request.delimiter,
            headers: headers, csvSHA256: KernelCanonicalHashV1.sha256(csv)))
    }

    private static func validateHumanManifest(
        _ human: GlobalizedHumanCSVManifestV1, table: GlobalizedMachineTableV1
    ) throws {
        try human.catalog.validate()
        _ = try LocaleFormattingServiceV1(profile: human.formatting)
        guard human.artifactKind == "LOCALIZED_HUMAN_CSV_V1", human.displayOnly,
              human.formatterVersion == formatterVersion,
              !human.formattingEnvironment.isEmpty, human.formattingEnvironment.utf8.count <= 256,
              human.effectiveLanguage == human.catalog.language,
              human.headers.map(\.binding.columnKey) == table.columns.map(\.key),
              resolutionIsValid(requested: human.requestedLanguage, effective: human.effectiveLanguage, fallback: human.fallback),
              KernelCanonicalHashV1.validSHA256(human.csvSHA256) else {
            throw ImportBulkFailureV1.invalidValue
        }
    }

    private static func resolutionIsValid(
        requested: AppLanguageTagV1, effective: AppLanguageTagV1, fallback: String
    ) -> Bool {
        (requested == effective && fallback == V30CatalogFallbackReasonV1.exact.rawValue)
            || (requested != effective && effective == .english
                && fallback == V30CatalogFallbackReasonV1.englishRequestedLanguageUnavailable.rawValue)
    }

    private static func bounded(_ data: Data, maximum: Int64 = ImportBulkLimitsV1.maximumSourceBytes) throws {
        guard !data.isEmpty, Int64(data.count) <= maximum else { throw ImportBulkFailureV1.limitExceeded }
    }
}


/// Validates the closed, language-neutral lexical forms carried by a machine
/// CSV/JSON artifact.  Presentation is deliberately a separate operation.
enum GlobalizedMachineScalarCodecV1 {
    static func validate(
        _ value: String,
        grammar: GlobalizedMachineScalarGrammarV1
    ) throws {
        switch grammar {
        case .text, .identifier:
            return // Outer cell/schema validation preserves authored bytes.
        case .integer:
            try validateInteger(value)
        case .decimal:
            _ = try exactDecimal(value)
        case .boolean:
            guard value == "TRUE" || value == "FALSE" else {
                throw ImportBulkFailureV1.invalidValue
            }
        case .gregorianDate:
            _ = try LocaleFormattingServiceV1.decodeCanonicalGregorianDate(value)
        case .utcTimestamp:
            _ = try utcTimestamp(value)
        }
    }

    static func display(
        _ value: String,
        grammar: GlobalizedMachineScalarGrammarV1,
        formatter: LocaleFormattingServiceV1
    ) throws -> String {
        try validate(value, grammar: grammar)
        switch grammar {
        case .text, .identifier, .boolean:
            return value
        case .integer:
            guard let decimal = Decimal(string: value, locale: posixLocale) else {
                throw ImportBulkFailureV1.invalidValue
            }
            return try formatter.formatDecimal(decimal)
        case .decimal:
            return try formatter.formatDecimal(exactDecimal(value))
        case .gregorianDate:
            return formatter.displayGregorianDate(
                try LocaleFormattingServiceV1.decodeCanonicalGregorianDate(value)
            )
        case .utcTimestamp:
            return formatter.displayInstant(try utcTimestamp(value))
        }
    }

    private static func validateInteger(_ value: String) throws {
        let bytes = Array(value.utf8)
        guard !bytes.isEmpty,
              bytes.allSatisfy({ (48...57).contains($0) || $0 == 45 }),
              (bytes[0] == 45 ? bytes.count > 1 : true) else {
            throw ImportBulkFailureV1.invalidValue
        }
        let magnitude = bytes[0] == 45 ? Array(bytes.dropFirst()) : bytes
        guard magnitude.allSatisfy({ (48...57).contains($0) }),
              magnitude.count == 1 || magnitude[0] != 48,
              !(bytes[0] == 45 && magnitude == [48]),
              Int64(value) != nil else {
            throw ImportBulkFailureV1.invalidValue
        }
    }

    private static func exactDecimal(_ value: String) throws -> Decimal {
        let bytes = Array(value.utf8)
        guard !bytes.isEmpty else { throw ImportBulkFailureV1.invalidValue }
        var index = 0
        if bytes[index] == 45 {
            index += 1
            guard index < bytes.count else { throw ImportBulkFailureV1.invalidValue }
        }
        let integerStart = index
        while index < bytes.count, (48...57).contains(bytes[index]) { index += 1 }
        let integer = Array(bytes[integerStart..<index])
        guard !integer.isEmpty,
              integer.count == 1 || integer[0] != 48 else {
            throw ImportBulkFailureV1.invalidValue
        }
        if index < bytes.count {
            guard bytes[index] == 46 else { throw ImportBulkFailureV1.invalidValue }
            index += 1
            let fractionStart = index
            while index < bytes.count, (48...57).contains(bytes[index]) { index += 1 }
            guard index > fractionStart else { throw ImportBulkFailureV1.invalidValue }
        }
        guard index == bytes.count else { throw ImportBulkFailureV1.invalidValue }

        let digits = bytes.filter { (48...57).contains($0) }
        // Bound the complete mantissa and scale. A merely significant-digit
        // cap permits extremely small fractions to underflow in Foundation.
        guard digits.count <= 38,
              let decimal = Decimal(string: value, locale: posixLocale), !decimal.isNaN else {
            throw ImportBulkFailureV1.invalidValue
        }
        return decimal
    }

    private static func utcTimestamp(_ value: String) throws -> Date {
        // Fixed bytes first: Gregorian/POSIX formatting is then used only to
        // validate calendar truth and reject normalized/impossible values.
        let bytes = Array(value.utf8)
        guard bytes.count == 24,
              bytes[4] == 45, bytes[7] == 45, bytes[10] == 84,
              bytes[13] == 58, bytes[16] == 58, bytes[19] == 46,
              bytes[23] == 90,
              [0, 1, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15, 17, 18, 20, 21, 22]
                .allSatisfy({ (48...57).contains(bytes[$0]) }) else {
            throw ImportBulkFailureV1.invalidValue
        }
        _ = try LocaleFormattingServiceV1.decodeCanonicalGregorianDate(String(value.prefix(10)))
        let formatter = DateFormatter()
        formatter.locale = posixLocale
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .gmt
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        formatter.isLenient = false
        guard let date = formatter.date(from: value), formatter.string(from: date) == value else {
            throw ImportBulkFailureV1.invalidValue
        }
        return date
    }

    private static let posixLocale = Locale(identifier: "en_US_POSIX")
}


/// Bounded, deterministic CSV wire codec for machine artifacts.  The caller
/// chooses one of the closed delimiters and owns header/schema validation.
enum GlobalizedMachineCSVCodecV1 {
    private static let nullSentinel = "\\N"
    private static let formulaPrefixes: Set<UnicodeScalar> = ["=", "+", "-", "@"]
    private static let allowedDelimiters: Set<UInt8> = [44, 59, 9]
    private static let maxRecords = ImportBulkLimitsV1.maximumRows + 1
    // Prefix escaping can add at most two bytes before a cell is CSV-quoted.
    private static let maximumWireCellBytes = ImportBulkLimitsV1.maximumCellBytes + 2

    static func encode(rows: [[String?]], delimiter: UInt8 = 44) throws -> Data {
        try validateDelimiter(delimiter)
        guard !rows.isEmpty, rows.count <= maxRecords else {
            throw ImportBulkFailureV1.limitExceeded
        }
        var output = Data()
        for row in rows {
            guard row.count <= ImportBulkLimitsV1.maximumColumns else {
                throw ImportBulkFailureV1.limitExceeded
            }
            for index in row.indices {
                if index != row.startIndex { try append(&output, byte: delimiter) }
                let wire = try wireCell(row[index])
                try append(&output, byte: 34)
                for byte in wire {
                    if byte == 34 {
                        try append(&output, byte: 34)
                        try append(&output, byte: 34)
                    } else {
                        try append(&output, byte: byte)
                    }
                }
                try append(&output, byte: 34)
            }
            try append(&output, byte: 13)
            try append(&output, byte: 10)
        }
        return output
    }

    static func decode(_ data: Data, delimiter: UInt8 = 44) throws -> [[String?]] {
        try validateDelimiter(delimiter)
        guard !data.isEmpty, data.count <= Int(ImportBulkLimitsV1.maximumSourceBytes),
              !data.starts(with: [0xEF, 0xBB, 0xBF]) else {
            throw ImportBulkFailureV1.invalidValue
        }
        let bytes = Array(data)
        var records: [[String?]] = []
        var row: [String?] = []
        var cell = Data()
        var inQuotes = false
        var quoteClosed = false
        var index = 0

        func finishCell() throws {
            guard row.count < ImportBulkLimitsV1.maximumColumns else {
                throw ImportBulkFailureV1.limitExceeded
            }
            let wire = try decodedWire(cell)
            let value = try valueForWire(wire)
            // Validate a reversible encoding for every parsed cell.  Since
            // `encode` also quotes all cells, this detects any ambiguous
            // prefix interpretation before the value leaves this codec.
            let reencoded = try encode(rows: [[value]], delimiter: delimiter)
            let expected = try quotedSingleCell(wire, delimiter: delimiter)
            guard reencoded == expected else { throw ImportBulkFailureV1.invalidValue }
            row.append(value)
            cell.removeAll(keepingCapacity: true)
            quoteClosed = false
        }
        func finishRow() throws {
            try finishCell()
            guard records.count < maxRecords else { throw ImportBulkFailureV1.limitExceeded }
            records.append(row)
            row.removeAll(keepingCapacity: true)
        }

        while index < bytes.count {
            let byte = bytes[index]
            if inQuotes {
                if byte == 34 {
                    if index + 1 < bytes.count, bytes[index + 1] == 34 {
                        try append(&cell, byte: 34, decodedCell: true)
                        index += 2
                        continue
                    }
                    inQuotes = false
                    quoteClosed = true
                } else {
                    try append(&cell, byte: byte, decodedCell: true)
                }
            } else if quoteClosed {
                if byte == delimiter {
                    try finishCell()
                } else if byte == 13 {
                    guard index + 1 < bytes.count, bytes[index + 1] == 10 else {
                        throw ImportBulkFailureV1.invalidValue
                    }
                    try finishRow()
                    index += 1
                } else if byte == 10 {
                    try finishRow()
                } else {
                    throw ImportBulkFailureV1.invalidValue
                }
            } else if byte == 34, cell.isEmpty {
                inQuotes = true
            } else {
                // Machine CSV requires every cell quoted; accepting bare data
                // would make the canonical encode check a lossy normalizer.
                throw ImportBulkFailureV1.invalidValue
            }
            index += 1
        }
        guard !inQuotes else { throw ImportBulkFailureV1.invalidValue }
        // RFC 4180 permits an omitted terminal record delimiter.  The caller
        // may still require CRLF-exact artifact bytes by comparing `encode`.
        if quoteClosed { try finishRow() }
        guard row.isEmpty, cell.isEmpty, !records.isEmpty else { throw ImportBulkFailureV1.invalidValue }
        return records
    }

    private static func wireCell(_ value: String?) throws -> Data {
        guard let value else { return Data(nullSentinel.utf8) }
        try validateAuthored(value)
        var wire = value
        if wire.hasPrefix("\\") { wire = "\\" + wire }
        if wire.hasPrefix("'") { wire = "'" + wire }
        if formulaRisk(wire) { wire = "'" + wire }
        guard let data = wire.data(using: .utf8) else { throw ImportBulkFailureV1.invalidValue }
        try validateWire(data)
        return data
    }

    private static func valueForWire(_ wire: String) throws -> String? {
        if wire == nullSentinel { return nil }
        var value = wire
        if value.hasPrefix("'"), formulaRisk(String(value.dropFirst())) {
            value.removeFirst()
        }
        if value.hasPrefix("'") {
            value.removeFirst()
        }
        if value.hasPrefix("\\") {
            value.removeFirst()
        }
        try validateAuthored(value)
        return value
    }

    private static func formulaRisk(_ value: String) -> Bool {
        guard let first = value.unicodeScalars.first else { return false }
        if first == "\t" || first == "\r" || first == "\n" { return true }
        guard let candidate = value.unicodeScalars.first(where: {
            !CharacterSet.whitespacesAndNewlines.contains($0)
                && $0.properties.generalCategory != .format
        }) else {
            return false
        }
        return formulaPrefixes.contains(candidate)
    }

    private static func decodedWire(_ bytes: Data) throws -> String {
        try validateWire(bytes)
        guard let value = String(data: bytes, encoding: .utf8) else {
            throw ImportBulkFailureV1.invalidValue
        }
        return value
    }

    private static func validateAuthored(_ value: String) throws {
        let bytes = Data(value.utf8)
        guard bytes.count <= ImportBulkLimitsV1.maximumCellBytes,
              value.unicodeScalars.count <= ImportBulkLimitsV1.maximumScalarsPerCell else {
            throw ImportBulkFailureV1.limitExceeded
        }
        try validateControlBytes(bytes)
    }

    private static func validateWire(_ bytes: Data) throws {
        guard bytes.count <= maximumWireCellBytes else {
            throw ImportBulkFailureV1.limitExceeded
        }
        try validateControlBytes(bytes)
    }

    private static func validateControlBytes(_ bytes: Data) throws {
        for byte in bytes where byte == 0 || (byte < 0x20 && byte != 9 && byte != 10 && byte != 13) {
            throw ImportBulkFailureV1.invalidValue
        }
    }

    private static func validateDelimiter(_ delimiter: UInt8) throws {
        guard allowedDelimiters.contains(delimiter) else { throw ImportBulkFailureV1.invalidValue }
    }

    private static func append(_ data: inout Data, byte: UInt8, decodedCell: Bool = false) throws {
        let cap = decodedCell ? maximumWireCellBytes : Int(ImportBulkLimitsV1.maximumSourceBytes)
        guard data.count < cap else { throw ImportBulkFailureV1.limitExceeded }
        data.append(byte)
    }

    private static func quotedSingleCell(_ wire: String, delimiter: UInt8) throws -> Data {
        // A one-cell row's bytes are independent of the delimiter, but keep
        // the parameter explicit to document the same delimiter scope.
        _ = delimiter
        var output = Data([34])
        for byte in wire.utf8 {
            if byte == 34 { output.append(34) }
            output.append(byte)
        }
        output.append(contentsOf: [34, 13, 10])
        return output
    }
}

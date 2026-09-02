import Foundation

/// C44 is a local catalog/workflow facade. It deliberately maps the disabled
/// state to the incumbent read/export/recovery policy instead of inventing a
/// second stock store or feature flag.
enum LocalStockFeaturePolicyV1: String, Codable, CaseIterable, Hashable, Sendable {
    case enabled = "ENABLED"
    case readExportRecoveryOnly = "READ_EXPORT_RECOVERY_ONLY"

    var partsStockPolicy: PartsStockFeaturePolicyV1 {
        self == .enabled ? .enabled : .readExportRecoveryOnly
    }

    var allowsWrites: Bool { self == .enabled }
    var preservesDraftsExportAndRecovery: Bool { true }
}

enum PartsStockWorkflowCatalogV1 {
    static let identifier = "LOCAL_PART_CATALOG_V1"
}

enum PartsStockWorkflowActionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case catalog = "CATALOG"
    case count = "COUNT"
    case adjust = "ADJUST"
    case transfer = "TRANSFER"
    case use = "USE"
    case `return` = "RETURN"
    case archive = "ARCHIVE"
    case importCSV = "IMPORT_CSV"
    case exportCSV = "EXPORT_CSV"
}

enum PartsStockWorkflowLookupV1: Equatable, Hashable, Sendable {
    case manualText(String)
    case scannedIdentity(StockProductIdentityV1)

    func validate() throws {
        switch self {
        case let .manualText(value):
            guard !value.isEmpty, value.utf8.count <= PartsStockLimitsV1.maximumSearchQueryBytes else {
                throw PartsStockFailureV1.invalidValue
            }
        case let .scannedIdentity(value): try value.validate()
        }
    }

    /// Lookup is intentionally only a query plan. Typing or scanning never
    /// creates a movement, a receipt, or a durable scan record.
    var queryText: String {
        switch self { case let .manualText(value): return value; case let .scannedIdentity(value): return value.value }
    }
}

struct PartsStockWorkflowCatalogDetailV1: Equatable, Sendable {
    let catalogID: String
    let part: LocalPartDefinitionV1
    let attention: [StockAttentionProjectionV1]

    init(part: LocalPartDefinitionV1, attention: [StockAttentionProjectionV1]) throws {
        try part.validate()
        guard attention.allSatisfy({ $0.partID == part.partID }) else { throw PartsStockFailureV1.crossWorkspace }
        guard Set(attention.map(\.locationID)).count == attention.count else { throw PartsStockFailureV1.invalidValue }
        for value in attention {
            switch value.balance {
            case .unknown:
                guard !value.isBelowPreferred else { throw PartsStockFailureV1.invalidValue }
            case let .known(quantity):
                try quantity.validate(for: part.canonicalUnit)
                let expected: Bool
                if let minimum = part.preferredMinimum { expected = try quantity.isLessThan(minimum) }
                else { expected = false }
                guard value.isBelowPreferred == expected else { throw PartsStockFailureV1.invalidValue }
            }
        }
        catalogID = PartsStockWorkflowCatalogV1.identifier
        self.part = part
        self.attention = attention.sorted { $0.locationID.uuidString < $1.locationID.uuidString }
    }
}

enum PartsStockWorkflowCSVDispositionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case complete = "COMPLETE"
    case incomplete = "INCOMPLETE"
    case cancelled = "CANCELLED"
}

struct PartsStockWorkflowCSVRowV1: Equatable, Hashable, Sendable {
    let rowIndex: Int
    let partID: UUID
    let displayName: String
    let canonicalUnit: StockUnitV1
    let productIdentities: [StockProductIdentityV1]
    let preferredMinimum: StockQuantityV1?

    init(rowIndex: Int, partID: UUID, displayName: String, canonicalUnit: StockUnitV1, productIdentities: [StockProductIdentityV1] = [], preferredMinimum: StockQuantityV1? = nil) throws {
        guard rowIndex >= 0, partID != UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)), !displayName.isEmpty, displayName.utf8.count <= PartsStockLimitsV1.maximumCatalogNameBytes, productIdentities.count <= 16, Set(productIdentities).count == productIdentities.count else { throw PartsStockFailureV1.invalidValue }
        try productIdentities.forEach { try $0.validate() }
        try preferredMinimum?.validate(for: canonicalUnit)
        self.rowIndex = rowIndex; self.partID = partID; self.displayName = displayName; self.canonicalUnit = canonicalUnit
        self.productIdentities = productIdentities.sorted { ($0.kind.rawValue, $0.value) < ($1.kind.rawValue, $1.value) }
        self.preferredMinimum = preferredMinimum
    }
}

struct PartsStockWorkflowCSVImportRowV1: Equatable, Sendable {
    let row: PartsStockWorkflowCSVRowV1
    let mutationID: MutationIDV1

    init(row: PartsStockWorkflowCSVRowV1, mutationID: MutationIDV1) throws {
        try row.productIdentities.forEach { try $0.validate() }
        self.row = row; self.mutationID = mutationID
    }

    func part(workspaceID: WorkspaceID) throws -> LocalPartDefinitionV1 {
        try LocalPartDefinitionV1(partID: row.partID, workspaceID: workspaceID, displayName: row.displayName, canonicalUnit: row.canonicalUnit, productIdentities: row.productIdentities, preferredMinimum: row.preferredMinimum, revision: 1, mutationID: mutationID)
    }
}

struct PartsStockWorkflowCSVImportPlanV1: Equatable, Sendable {
    let catalogID: String
    let workspaceID: WorkspaceID
    let csvBytes: Data
    let csvSHA256: String
    let rows: [PartsStockWorkflowCSVImportRowV1]

    fileprivate init(workspaceID: WorkspaceID, csvBytes: Data, rows: [PartsStockWorkflowCSVImportRowV1]) throws {
        guard rows.count <= PartsStockLimitsV1.maximumSnapshotRows,
              rows.map(\.row.rowIndex) == Array(0..<rows.count),
              Set(rows.map { $0.row.partID }).count == rows.count,
              Set(rows.map { $0.mutationID.rawValue }).count == rows.count else { throw PartsStockFailureV1.invalidValue }
        let identities = try rows.flatMap { try $0.row.productIdentities.map { try $0.locatorKey } }
        guard identities.count == Set(identities).count else { throw PartsStockFailureV1.duplicateMutation }
        catalogID = PartsStockWorkflowCatalogV1.identifier; self.workspaceID = workspaceID; self.csvBytes = csvBytes
        csvSHA256 = try PartsStockCanonicalCodecV1.sha256(csvBytes.base64EncodedString())
        self.rows = rows
    }
}

struct PartsStockWorkflowCSVImportResultV1: Equatable, Sendable {
    let planSHA256: String
    let disposition: PartsStockWorkflowCSVDispositionV1
    let committedReceipts: [PartsStockMutationReceiptV1]
    let expectedRowCount: Int
    /// The first row without a receipt when a caller records an incomplete
    /// result. It is absent for complete or caller-cancelled work.
    let incompleteAtRowIndex: Int?

    init(plan: PartsStockWorkflowCSVImportPlanV1, disposition: PartsStockWorkflowCSVDispositionV1, committedReceipts: [PartsStockMutationReceiptV1], incompleteAtRowIndex: Int? = nil) throws {
        guard committedReceipts.count <= plan.rows.count,
              Set(committedReceipts.map(\.mutationID)).count == committedReceipts.count,
              committedReceipts.allSatisfy({ $0.workspaceID == plan.workspaceID }),
              committedReceipts.map(\.mutationID) == Array(plan.rows.prefix(committedReceipts.count).map(\.mutationID)) else { throw PartsStockFailureV1.invalidValue }
        switch disposition {
        case .complete:
            guard committedReceipts.count == plan.rows.count, incompleteAtRowIndex == nil else { throw PartsStockFailureV1.invalidTransition }
        case .cancelled:
            guard committedReceipts.count < plan.rows.count, incompleteAtRowIndex == nil else { throw PartsStockFailureV1.invalidTransition }
        case .incomplete:
            guard committedReceipts.count < plan.rows.count, incompleteAtRowIndex == committedReceipts.count else { throw PartsStockFailureV1.invalidTransition }
        }
        planSHA256 = plan.csvSHA256; self.disposition = disposition; self.committedReceipts = committedReceipts; expectedRowCount = plan.rows.count; self.incompleteAtRowIndex = incompleteAtRowIndex
    }
}

enum PartsStockWorkflowCSVCodecV1 {
    static let header = "catalog_id,row_index,part_id,display_name,canonical_unit,identities_b64,minimum_mantissa,minimum_scale\r\n"

    static func export(_ parts: [LocalPartDefinitionV1]) throws -> Data {
        let rows = try parts.sorted { $0.partID.uuidString < $1.partID.uuidString }.enumerated().map { index, part -> String in
            try part.validate()
            let identities = try PartsStockCanonicalCodecV1.encode(part.productIdentities).base64EncodedString()
            let minimum = part.preferredMinimum.map { "\($0.mantissa),\($0.scale)" } ?? ","
            return "\(PartsStockWorkflowCatalogV1.identifier),\(index),\(part.partID.uuidString.lowercased()),\(field(part.displayName)),\(part.canonicalUnit.rawValue),\(field(identities)),\(minimum)\r\n"
        }
        return Data((header + rows.joined()).utf8)
    }

    /// Closed parser for this exact C44 format; it rejects foreign headers,
    /// malformed quotes, duplicate part IDs/SKUs, and noncanonical row order.
    static func preview(workspaceID: WorkspaceID, csvBytes: Data) throws -> PartsStockWorkflowCSVImportPlanV1 {
        guard let text = String(data: csvBytes, encoding: .utf8), text.hasPrefix(header) else { throw PartsStockFailureV1.invalidValue }
        let body = String(text.dropFirst(header.count))
        guard body.isEmpty || body.hasSuffix("\r\n"), !body.replacingOccurrences(of: "\r\n", with: "").contains("\r"), !body.replacingOccurrences(of: "\r\n", with: "").contains("\n") else { throw PartsStockFailureV1.invalidValue }
        let lines = body.isEmpty ? [] : Array(body.components(separatedBy: "\r\n").dropLast())
        let digest = try PartsStockCanonicalCodecV1.sha256(csvBytes.base64EncodedString())
        let rows = try lines.enumerated().map { index, line -> PartsStockWorkflowCSVImportRowV1 in
            let fields = try parse(line)
            guard fields.count == 8, fields[0] == PartsStockWorkflowCatalogV1.identifier, Int(fields[1]) == index, let partID = UUID(uuidString: fields[2]), let unit = StockUnitV1(rawValue: fields[4]), let identitiesData = Data(base64Encoded: fields[5]) else { throw PartsStockFailureV1.invalidValue }
            let identities = try JSONDecoder().decode([StockProductIdentityV1].self, from: identitiesData)
            let minimum: StockQuantityV1?
            if fields[6].isEmpty && fields[7].isEmpty { minimum = nil }
            else if let mantissa = Int64(fields[6]), let scale = Int(fields[7]) { minimum = try StockQuantityV1(mantissa: mantissa, scale: scale, unit: unit) }
            else { throw PartsStockFailureV1.invalidValue }
            let row = try PartsStockWorkflowCSVRowV1(rowIndex: index, partID: partID, displayName: fields[3], canonicalUnit: unit, productIdentities: identities, preferredMinimum: minimum)
            return try PartsStockWorkflowCSVImportRowV1(row: row, mutationID: try stableMutationID(digest: digest, rowIndex: index))
        }
        return try PartsStockWorkflowCSVImportPlanV1(workspaceID: workspaceID, csvBytes: csvBytes, rows: rows)
    }

    private static func field(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
    private static func parse(_ value: String) throws -> [String] {
        var result: [String] = []; var current = ""; var quoted = false; var closedQuote = false; var index = value.startIndex
        while index < value.endIndex {
            let character = value[index]
            if quoted {
                if character == "\"" { let next = value.index(after: index); if next < value.endIndex, value[next] == "\"" { current.append("\""); index = next } else { quoted = false } }
                else { current.append(character) }
            } else if closedQuote {
                guard character == "," else { throw PartsStockFailureV1.invalidValue }
                result.append(current); current = ""; closedQuote = false
            } else if character == "," { result.append(current); current = "" }
            else if character == "\"" && current.isEmpty { quoted = true }
            else if character == "\"" { throw PartsStockFailureV1.invalidValue }
            else { current.append(character) }
            if !quoted, character == "\"" { closedQuote = true }
            index = value.index(after: index)
        }
        guard !quoted else { throw PartsStockFailureV1.invalidValue }; result.append(current); return result
    }
    private static func stableMutationID(digest: String, rowIndex: Int) throws -> MutationIDV1 {
        let rowDigest = try PartsStockCanonicalCodecV1.sha256("\(digest)|\(rowIndex)|UPSERT_PART")
        let uuid = "\(rowDigest.prefix(8))-\(rowDigest.dropFirst(8).prefix(4))-5\(rowDigest.dropFirst(13).prefix(3))-a\(rowDigest.dropFirst(17).prefix(3))-\(rowDigest.dropFirst(20).prefix(12))"
        guard let value = UUID(uuidString: uuid) else { throw PartsStockFailureV1.invalidValue }
        return try MutationIDV1(rawValue: value)
    }
}

enum C44PartsStockWorkflowBoundaryV1 {
    static let cardID = "V23-P04-C44"
    static let catalogID = PartsStockWorkflowCatalogV1.identifier
    static let lookupIsZeroWrite = true
    static let onlyExplicitUseMutatesStock = true
    static let returnsRequireEligibleUseAndOrderedFrontier = true
    static let reportsExcludeBalancesAndInternalLocations = true
    static let featureDisablePreservesDraftExportAndRecovery = true
    static let hasParallelWriter = false
    static let hasNetworkDependency = false
}

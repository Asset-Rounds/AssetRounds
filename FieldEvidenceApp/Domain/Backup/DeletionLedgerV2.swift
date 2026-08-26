import Foundation

enum DeletionLedgerFailureV2: Error, Equatable, Sendable {
    case invalidSchemaVersion
    case invalidIdentity
    case duplicateIdentity
    case unorderedEntries
    case invalidTimestamp
}

struct DeletionLedgerProofV2: Codable, Equatable, Sendable {
    let entryCount: Int
    let canonicalSHA256: String

    init(entryCount: Int, canonicalSHA256: String) throws {
        self.entryCount = entryCount
        self.canonicalSHA256 = canonicalSHA256
        try validate()
    }

    func validate() throws {
        let allowed = CharacterSet(charactersIn: "0123456789abcdef")
        guard entryCount >= 0,
              canonicalSHA256.utf8.count == 64,
              canonicalSHA256.unicodeScalars.allSatisfy(allowed.contains) else {
            throw DeletionLedgerFailureV2.invalidIdentity
        }
    }
}

/// The closed set of persisted content kinds. System rows such as the schema
/// marker and deletion-ledger rows are deliberately outside this registry.
enum DeletionRecordKindV2: String, CaseIterable, Codable, Equatable, Sendable {
    case site = "site"
    case asset = "asset"
    case workflowRecord = "workflowRecord"
    case evidenceFile = "evidenceFile"
    case issue = "issue"
    case packet = "packet"
    case report = "report"
}

struct DeletionIdentityV2: Codable, Comparable, Equatable, Hashable, Sendable {
    static let separator = ":"

    let kind: DeletionRecordKindV2
    let id: UUID

    init(kind: DeletionRecordKindV2, id: UUID) throws {
        guard id.uuidString != "00000000-0000-0000-0000-000000000000" else {
            throw DeletionLedgerFailureV2.invalidIdentity
        }
        self.kind = kind
        self.id = id
    }

    init(typedID: String) throws {
        let pieces = typedID.split(separator: Character(Self.separator), omittingEmptySubsequences: false)
        guard pieces.count == 2,
              let kind = DeletionRecordKindV2(rawValue: String(pieces[0])),
              let id = UUID(uuidString: String(pieces[1])),
              id.uuidString.lowercased() == pieces[1] else {
            throw DeletionLedgerFailureV2.invalidIdentity
        }
        try self.init(kind: kind, id: id)
    }

    var typedID: String {
        kind.rawValue + Self.separator + id.uuidString.lowercased()
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.typedID < rhs.typedID
    }
}

struct DeletionLedgerEntryV2: Codable, Equatable, Hashable, Sendable {
    let schemaVersion: Int
    let identity: DeletionIdentityV2
    let deletedAt: Date

    init(
        identity: DeletionIdentityV2,
        deletedAt: Date,
        schemaVersion: Int = 2
    ) throws {
        self.schemaVersion = schemaVersion
        self.identity = identity
        self.deletedAt = deletedAt
        try validate()
    }

    func validate() throws {
        guard schemaVersion == 2 else {
            throw DeletionLedgerFailureV2.invalidSchemaVersion
        }
        guard deletedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw DeletionLedgerFailureV2.invalidTimestamp
        }
        _ = try DeletionIdentityV2(typedID: identity.typedID)
    }
}

struct DeletionLedgerV2: Codable, Equatable, Sendable {
    static let maximumEntryCount = 100_000

    let schemaVersion: Int
    let entries: [DeletionLedgerEntryV2]

    init(entries: [DeletionLedgerEntryV2], schemaVersion: Int = 2) throws {
        self.schemaVersion = schemaVersion
        self.entries = entries
        try validate()
    }

    static var empty: Self {
        try! Self(entries: [])
    }

    func validate() throws {
        guard schemaVersion == 2 else {
            throw DeletionLedgerFailureV2.invalidSchemaVersion
        }
        guard entries.count <= Self.maximumEntryCount else {
            throw DeletionLedgerFailureV2.invalidIdentity
        }
        try entries.forEach { try $0.validate() }
        let identities = entries.map(\.identity)
        guard Set(identities).count == identities.count else {
            throw DeletionLedgerFailureV2.duplicateIdentity
        }
        guard identities == identities.sorted() else {
            throw DeletionLedgerFailureV2.unorderedEntries
        }
    }

    func union(_ other: Self) throws -> Self {
        try validate()
        try other.validate()
        var byIdentity = Dictionary(uniqueKeysWithValues: entries.map { ($0.identity, $0) })
        for entry in other.entries {
            if let existing = byIdentity[entry.identity] {
                if entry.deletedAt < existing.deletedAt {
                    byIdentity[entry.identity] = entry
                }
            } else {
                byIdentity[entry.identity] = entry
            }
        }
        return try Self(entries: byIdentity.values.sorted { $0.identity < $1.identity })
    }

    func canonicalData() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

import Foundation
import SwiftData

enum ImportBulkPersistenceFailureV1: Error, Equatable, Sendable {
    case corruptRow
    case staleSession
}

/// The import bulk family persists only explicitly saved mappings, recoverable
/// sessions, and immutable receipts. Source bytes, scratch mappings, and
/// derived previews deliberately have no SwiftData representation.
enum ImportBulkPersistenceSchemaV1 {
    static let savedMappingProfileTag = "import-bulk-saved-mapping-profile-v1"
    static let sessionTag = "import-bulk-session-v1"
    static let receiptTag = "import-bulk-receipt-v1"
}

@Model final class ImportMappingProfileRowV1 {
    @Attribute(.unique) private(set) var profileID: UUID
    private(set) var workspaceID: UUID
    private(set) var schemaTag: String
    private(set) var profileSHA256: String
    private(set) var canonicalData: Data

    init(_ value: ImportMappingProfileV1) throws {
        try value.validate()
        profileID = value.profileID
        workspaceID = value.workspaceID.rawValue
        schemaTag = ImportBulkPersistenceSchemaV1.savedMappingProfileTag
        profileSHA256 = value.profileSHA256
        canonicalData = try ImportBulkCanonicalCodecV1.encode(value)
        guard try ImportBulkCanonicalCodecV1.decode(
            ImportMappingProfileV1.self,
            from: canonicalData
        ) == value else {
            throw ImportBulkPersistenceFailureV1.corruptRow
        }
    }

    func value() throws -> ImportMappingProfileV1 {
        let value = try ImportBulkCanonicalCodecV1.decode(
            ImportMappingProfileV1.self,
            from: canonicalData
        )
        try value.validate()
        guard profileID == value.profileID,
              workspaceID == value.workspaceID.rawValue,
              schemaTag == ImportBulkPersistenceSchemaV1.savedMappingProfileTag,
              profileSHA256 == value.profileSHA256 else {
            throw ImportBulkPersistenceFailureV1.corruptRow
        }
        return value
    }

    func replace(with value: ImportMappingProfileV1, expectedProfileSHA256: String) throws {
        let prior = try self.value()
        guard prior.profileSHA256 == expectedProfileSHA256,
              value.profileID == profileID,
              value.workspaceID.rawValue == workspaceID else {
            throw ImportBulkPersistenceFailureV1.staleSession
        }
        try value.validate()
        profileSHA256 = value.profileSHA256
        canonicalData = try ImportBulkCanonicalCodecV1.encode(value)
    }
}

@Model final class BulkSessionRowV1 {
    @Attribute(.unique) private(set) var sessionID: UUID
    private(set) var workspaceID: UUID
    private(set) var bulkPlanID: UUID
    private(set) var stateRawValue: String
    private(set) var schemaTag: String
    private(set) var sessionSHA256: String
    private(set) var canonicalData: Data

    init(_ value: BulkSessionV1) throws {
        try value.validate()
        sessionID = value.sessionID
        workspaceID = value.workspaceID.rawValue
        bulkPlanID = value.bulkPlanID
        stateRawValue = value.state.rawValue
        schemaTag = ImportBulkPersistenceSchemaV1.sessionTag
        sessionSHA256 = value.sessionSHA256
        canonicalData = try ImportBulkCanonicalCodecV1.encode(value)
        guard try ImportBulkCanonicalCodecV1.decode(BulkSessionV1.self, from: canonicalData) == value else {
            throw ImportBulkPersistenceFailureV1.corruptRow
        }
    }

    func value() throws -> BulkSessionV1 {
        let value = try ImportBulkCanonicalCodecV1.decode(BulkSessionV1.self, from: canonicalData)
        try value.validate()
        guard sessionID == value.sessionID,
              workspaceID == value.workspaceID.rawValue,
              bulkPlanID == value.bulkPlanID,
              stateRawValue == value.state.rawValue,
              schemaTag == ImportBulkPersistenceSchemaV1.sessionTag,
              sessionSHA256 == value.sessionSHA256 else {
            throw ImportBulkPersistenceFailureV1.corruptRow
        }
        return value
    }

    func replace(with value: BulkSessionV1, expectedSessionSHA256: String) throws {
        let prior = try self.value()
        guard prior.sessionSHA256 == expectedSessionSHA256,
              value.sessionID == sessionID,
              value.workspaceID.rawValue == workspaceID,
              value.bulkPlanID == bulkPlanID else {
            throw ImportBulkPersistenceFailureV1.staleSession
        }
        try value.validate()
        stateRawValue = value.state.rawValue
        sessionSHA256 = value.sessionSHA256
        canonicalData = try ImportBulkCanonicalCodecV1.encode(value)
    }
}

@Model final class BulkCommitReceiptRowV1 {
    @Attribute(.unique) private(set) var receiptIdentity: String
    private(set) var receiptID: UUID
    private(set) var workspaceID: UUID
    private(set) var bulkPlanID: UUID
    private(set) var chunkIndex: Int
    private(set) var dispositionRawValue: String
    private(set) var schemaTag: String
    private(set) var receiptSHA256: String
    private(set) var canonicalData: Data

    init(_ value: BulkCommitReceiptV1) throws {
        try value.validate()
        receiptIdentity = Self.identity(
            workspaceID: value.workspaceID,
            bulkPlanID: value.bulkPlanID,
            chunkIndex: value.chunkIndex
        )
        receiptID = value.receiptID
        workspaceID = value.workspaceID.rawValue
        bulkPlanID = value.bulkPlanID
        chunkIndex = value.chunkIndex
        dispositionRawValue = value.disposition.rawValue
        schemaTag = ImportBulkPersistenceSchemaV1.receiptTag
        receiptSHA256 = value.receiptSHA256
        canonicalData = try ImportBulkCanonicalCodecV1.encode(value)
        guard try ImportBulkCanonicalCodecV1.decode(BulkCommitReceiptV1.self, from: canonicalData) == value else {
            throw ImportBulkPersistenceFailureV1.corruptRow
        }
    }

    func value() throws -> BulkCommitReceiptV1 {
        let value = try ImportBulkCanonicalCodecV1.decode(BulkCommitReceiptV1.self, from: canonicalData)
        try value.validate()
        guard receiptIdentity == Self.identity(
                workspaceID: value.workspaceID,
                bulkPlanID: value.bulkPlanID,
                chunkIndex: value.chunkIndex
              ),
              receiptID == value.receiptID,
              workspaceID == value.workspaceID.rawValue,
              bulkPlanID == value.bulkPlanID,
              chunkIndex == value.chunkIndex,
              dispositionRawValue == value.disposition.rawValue,
              schemaTag == ImportBulkPersistenceSchemaV1.receiptTag,
              receiptSHA256 == value.receiptSHA256 else {
            throw ImportBulkPersistenceFailureV1.corruptRow
        }
        return value
    }

    private static func identity(
        workspaceID: WorkspaceID,
        bulkPlanID: UUID,
        chunkIndex: Int
    ) -> String {
        "\(workspaceID.rawValue.uuidString.lowercased())|\(bulkPlanID.uuidString.lowercased())|\(String(format: "%020d", chunkIndex))"
    }
}

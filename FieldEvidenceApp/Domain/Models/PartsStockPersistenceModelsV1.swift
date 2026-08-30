import Foundation
import SwiftData

enum PartsStockPersistenceFailureV1: Error, Equatable, Sendable {
    case invalidValue, invalidDigest, duplicateIdentity, crossWorkspace, unsupportedVersion, unavailable
}

enum PartsStockPersistenceCodecV1 {
    static func encode<T: Encodable>(_ value: T) throws -> Data { try PartsStockCanonicalCodecV1.encode(value) }
    static func decode<T: Decodable & PartsStockCanonicalValidatingV1>(_ type: T.Type, from data: Data) throws -> T { try PartsStockCanonicalCodecV1.decode(type, from: data) }
}

@Model final class LocalPartDefinitionRowV1 {
    @Attribute(.unique) var recordKey: String
    var workspaceUUID: UUID; var partID: UUID; var revision: UInt64; var archived: Bool
    var displayName: String; var canonicalData: Data
    init(_ value: LocalPartDefinitionV1) throws {
        try value.validate(); recordKey = "\(value.workspaceID.rawValue.uuidString.lowercased())|\(value.partID.uuidString.lowercased())"
        workspaceUUID = value.workspaceID.rawValue; partID = value.partID; revision = value.revision
        archived = value.archived; displayName = value.displayName; canonicalData = try PartsStockPersistenceCodecV1.encode(value)
    }
    func value() throws -> LocalPartDefinitionV1 {
        let value = try PartsStockPersistenceCodecV1.decode(LocalPartDefinitionV1.self, from: canonicalData)
        guard value.workspaceID.rawValue == workspaceUUID, value.partID == partID, value.revision == revision, value.archived == archived, value.displayName == displayName else { throw PartsStockPersistenceFailureV1.invalidDigest }
        return value
    }
}

@Model final class StockStorageLocationRowV1 {
    @Attribute(.unique) var recordKey: String
    var workspaceUUID: UUID; var locationID: UUID; var revision: UInt64; var archived: Bool
    var label: String; var canonicalData: Data
    init(_ value: StockStorageLocationV1) throws {
        try value.validate(); recordKey = "\(value.workspaceID.rawValue.uuidString.lowercased())|\(value.locationID.uuidString.lowercased())"
        workspaceUUID = value.workspaceID.rawValue; locationID = value.locationID; revision = value.revision
        archived = value.archived; label = value.label; canonicalData = try PartsStockPersistenceCodecV1.encode(value)
    }
    func value() throws -> StockStorageLocationV1 {
        let value = try PartsStockPersistenceCodecV1.decode(StockStorageLocationV1.self, from: canonicalData)
        guard value.workspaceID.rawValue == workspaceUUID, value.locationID == locationID, value.revision == revision, value.archived == archived, value.label == label else { throw PartsStockPersistenceFailureV1.invalidDigest }
        return value
    }
}

@Model final class StockMovementEventRowV1 {
    @Attribute(.unique) var recordKey: String
    var workspaceUUID: UUID; var movementID: UUID; var partID: UUID; var locationID: UUID
    var locationRevision: UInt64; var occurredAt: Date; var canonicalData: Data
    init(_ value: StockMovementEventV1) throws {
        try value.validate(); recordKey = "\(value.workspaceID.rawValue.uuidString.lowercased())|\(value.movementID.uuidString.lowercased())"
        workspaceUUID = value.workspaceID.rawValue; movementID = value.movementID; partID = value.part.partID
        locationID = value.locationID; locationRevision = value.locationRevision; occurredAt = value.occurredAt
        canonicalData = try PartsStockPersistenceCodecV1.encode(value)
    }
    func value() throws -> StockMovementEventV1 {
        let value = try PartsStockPersistenceCodecV1.decode(StockMovementEventV1.self, from: canonicalData)
        guard value.workspaceID.rawValue == workspaceUUID, value.movementID == movementID, value.part.partID == partID, value.locationID == locationID, value.locationRevision == locationRevision, value.occurredAt == occurredAt else { throw PartsStockPersistenceFailureV1.invalidDigest }
        return value
    }
}

@Model final class StockUseReceiptRowV1 {
    @Attribute(.unique) var recordKey: String
    var workspaceUUID: UUID; var receiptID: UUID; var movementID: UUID; var canonicalData: Data
    init(_ value: StockUseOnWorkReceiptV1) throws {
        try value.validate(); recordKey = "\(value.workspaceID.rawValue.uuidString.lowercased())|\(value.receiptID.uuidString.lowercased())"
        workspaceUUID = value.workspaceID.rawValue; receiptID = value.receiptID; movementID = value.movement.movementID
        canonicalData = try PartsStockPersistenceCodecV1.encode(value)
    }
    func value() throws -> StockUseOnWorkReceiptV1 {
        let value = try PartsStockPersistenceCodecV1.decode(StockUseOnWorkReceiptV1.self, from: canonicalData)
        guard value.workspaceID.rawValue == workspaceUUID, value.receiptID == receiptID, value.movement.movementID == movementID else { throw PartsStockPersistenceFailureV1.invalidDigest }
        return value
    }
}

@Model final class StockReturnReceiptRowV1 {
    @Attribute(.unique) var recordKey: String
    var workspaceUUID: UUID; var receiptID: UUID; var sourceUseReceiptID: UUID
    var resultingReturnedMantissa: Int64; var canonicalData: Data
    init(_ value: StockReturnAgainstUseReceiptV1) throws {
        try value.validate(); recordKey = "\(value.workspaceID.rawValue.uuidString.lowercased())|\(value.receiptID.uuidString.lowercased())"
        workspaceUUID = value.workspaceID.rawValue; receiptID = value.receiptID; sourceUseReceiptID = value.sourceUseReceiptID
        resultingReturnedMantissa = value.resultingReturnedMantissa; canonicalData = try PartsStockPersistenceCodecV1.encode(value)
    }
    func value() throws -> StockReturnAgainstUseReceiptV1 {
        let value = try PartsStockPersistenceCodecV1.decode(StockReturnAgainstUseReceiptV1.self, from: canonicalData)
        guard value.workspaceID.rawValue == workspaceUUID, value.receiptID == receiptID, value.sourceUseReceiptID == sourceUseReceiptID, value.resultingReturnedMantissa == resultingReturnedMantissa else { throw PartsStockPersistenceFailureV1.invalidDigest }
        return value
    }
}

@Model final class StockUseReversalReceiptRowV1 {
    @Attribute(.unique) var recordKey: String
    var workspaceUUID: UUID; var receiptID: UUID; var sourceUseReceiptID: UUID; var canonicalData: Data
    init(_ value: StockUseReversalReceiptV1) throws {
        try value.validate(); recordKey = "\(value.workspaceID.rawValue.uuidString.lowercased())|\(value.receiptID.uuidString.lowercased())"
        workspaceUUID = value.workspaceID.rawValue; receiptID = value.receiptID; sourceUseReceiptID = value.sourceUse.receiptID
        canonicalData = try PartsStockPersistenceCodecV1.encode(value)
    }
    func value() throws -> StockUseReversalReceiptV1 {
        let value = try PartsStockPersistenceCodecV1.decode(StockUseReversalReceiptV1.self, from: canonicalData)
        guard value.workspaceID.rawValue == workspaceUUID, value.receiptID == receiptID, value.sourceUse.receiptID == sourceUseReceiptID else { throw PartsStockPersistenceFailureV1.invalidDigest }
        return value
    }
}

@Model final class AbandonUnverifiedStockRowV1 {
    @Attribute(.unique) var recordKey: String
    var workspaceUUID: UUID; var dispositionID: UUID; var partID: UUID; var locationID: UUID
    var recordedAt: Date; var canonicalData: Data
    init(_ value: AbandonUnverifiedStockDispositionV1) throws {
        try value.validate(); recordKey = "\(value.workspaceID.rawValue.uuidString.lowercased())|\(value.dispositionID.uuidString.lowercased())"
        workspaceUUID = value.workspaceID.rawValue; dispositionID = value.dispositionID; partID = value.partID
        locationID = value.locationID; recordedAt = value.recordedAt; canonicalData = try PartsStockPersistenceCodecV1.encode(value)
    }
    func value() throws -> AbandonUnverifiedStockDispositionV1 {
        let value = try PartsStockPersistenceCodecV1.decode(AbandonUnverifiedStockDispositionV1.self, from: canonicalData)
        guard value.workspaceID.rawValue == workspaceUUID, value.dispositionID == dispositionID, value.partID == partID, value.locationID == locationID, value.recordedAt == recordedAt else { throw PartsStockPersistenceFailureV1.invalidDigest }
        return value
    }
}

struct PartsStockBackupSnapshotV1: Codable, Equatable, Sendable, PartsStockCanonicalValidatingV1 {
    static let schemaVersion = 1
    let schemaVersion: Int; let workspaceID: WorkspaceID; let parts: [LocalPartDefinitionV1]
    let locations: [StockStorageLocationV1]; let movements: [StockMovementEventV1]
    let uses: [StockUseOnWorkReceiptV1]; let reversals: [StockUseReversalReceiptV1]; let returns: [StockReturnAgainstUseReceiptV1]
    let abandonments: [AbandonUnverifiedStockDispositionV1]; let snapshotSHA256: String
    init(workspaceID: WorkspaceID, parts: [LocalPartDefinitionV1], locations: [StockStorageLocationV1], movements: [StockMovementEventV1], uses: [StockUseOnWorkReceiptV1], reversals: [StockUseReversalReceiptV1], returns: [StockReturnAgainstUseReceiptV1], abandonments: [AbandonUnverifiedStockDispositionV1]) throws {
        let count = parts.count + locations.count + movements.count + uses.count + reversals.count + returns.count + abandonments.count
        guard count <= PartsStockLimitsV1.maximumSnapshotRows, parts.allSatisfy({ $0.workspaceID == workspaceID }), locations.allSatisfy({ $0.workspaceID == workspaceID }), movements.allSatisfy({ $0.workspaceID == workspaceID }), uses.allSatisfy({ $0.workspaceID == workspaceID }), reversals.allSatisfy({ $0.workspaceID == workspaceID }), returns.allSatisfy({ $0.workspaceID == workspaceID }), abandonments.allSatisfy({ $0.workspaceID == workspaceID }) else { throw PartsStockPersistenceFailureV1.crossWorkspace }
        try parts.forEach { try $0.validate() }; try locations.forEach { try $0.validate() }; try movements.forEach { try $0.validate() }; try uses.forEach { try $0.validate() }; try reversals.forEach { try $0.validate() }; try returns.forEach { try $0.validate() }; try abandonments.forEach { try $0.validate() }
        try PartsStockSnapshotTopologyV1.validate(parts: parts, locations: locations, movements: movements, uses: uses, reversals: reversals, returns: returns, abandonments: abandonments)
        schemaVersion = Self.schemaVersion; self.workspaceID = workspaceID
        self.parts = parts.sorted { $0.partID.uuidString < $1.partID.uuidString }; self.locations = locations.sorted { $0.locationID.uuidString < $1.locationID.uuidString }
        self.movements = movements.sorted { ($0.recordedAt, $0.movementID.uuidString) < ($1.recordedAt, $1.movementID.uuidString) }; self.uses = uses.sorted { $0.receiptID.uuidString < $1.receiptID.uuidString }; self.reversals = reversals.sorted { $0.receiptID.uuidString < $1.receiptID.uuidString }; self.returns = returns.sorted { $0.receiptID.uuidString < $1.receiptID.uuidString }; self.abandonments = abandonments.sorted { $0.dispositionID.uuidString < $1.dispositionID.uuidString }
        snapshotSHA256 = try PartsStockCanonicalCodecV1.sha256(Basis(schemaVersion: Self.schemaVersion, workspaceID: workspaceID, parts: self.parts, locations: self.locations, movements: self.movements, uses: self.uses, reversals: self.reversals, returns: self.returns, abandonments: self.abandonments))
    }
    func validate() throws { guard schemaVersion == Self.schemaVersion else { throw PartsStockFailureV1.incompatibleVersion }; try PartsStockSnapshotTopologyV1.validate(parts: parts, locations: locations, movements: movements, uses: uses, reversals: reversals, returns: returns, abandonments: abandonments); let rebuilt = try Self(workspaceID: workspaceID, parts: parts, locations: locations, movements: movements, uses: uses, reversals: reversals, returns: returns, abandonments: abandonments); guard rebuilt.snapshotSHA256 == snapshotSHA256 else { throw PartsStockFailureV1.invalidDigest } }
    private struct Basis: Codable { let schemaVersion: Int; let workspaceID: WorkspaceID; let parts: [LocalPartDefinitionV1]; let locations: [StockStorageLocationV1]; let movements: [StockMovementEventV1]; let uses: [StockUseOnWorkReceiptV1]; let reversals: [StockUseReversalReceiptV1]; let returns: [StockReturnAgainstUseReceiptV1]; let abandonments: [AbandonUnverifiedStockDispositionV1] }
}

enum C55PartsStockPersistenceBoundaryV1 {
    static let cardID = "V23-P03-C55"
    static let schemaVersion = 1
    static let persistentTypes: [Any.Type] = [LocalPartDefinitionRowV1.self, StockStorageLocationRowV1.self, StockMovementEventRowV1.self, StockUseReceiptRowV1.self, StockUseReversalReceiptRowV1.self, StockReturnReceiptRowV1.self, AbandonUnverifiedStockRowV1.self]
    static let usesExistingWorkspaceWriter = true
    static let parallelPersistenceAuthority = false
}

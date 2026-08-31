import Foundation
import SwiftData

private enum EntityIdentityResolutionPersistenceCodecV1 {
    static func encode<T: Encodable>(_ value: T) throws -> Data { try WorkspaceMutationCanonicalV1.data(value) }

    static func decode<T: Codable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let value = try decoder.decode(T.self, from: data)
        guard try encode(value) == data else { throw EntityIdentityResolutionFailureV1.receiptMismatch }
        return value
    }
}

@Model final class EntityAliasLinkRowV1 {
    @Attribute(.unique) var rowID: String
    var workspaceID: UUID
    var linkEventID: UUID
    var aliasID: UUID
    var canonicalEntityID: UUID
    var revision: UInt64
    var mutationID: UUID
    var linkSHA256: String
    var canonicalData: Data

    init(_ value: EntityAliasLinkV1, command: EntityIdentityResolutionMutationCommandV1, receipt: EntityIdentityResolutionMutationReceiptV1, predecessor: EntityAliasLinkV1?, resolver: any EntityIdentityResolutionCanonicalSourceResolvingV1) throws {
        try command.validateCanonicalSources(by: resolver)
        try receipt.validate(command: command)
        guard value.revision == 1 ? predecessor == nil : predecessor != nil,
              case let .alias(payload, payloadPredecessor) = command.payload, payload == value, payloadPredecessor == predecessor,
              receipt.workspaceID == value.workspaceID, receipt.mutationID == value.mutationID,
              receipt.semanticSHA256s == [value.linkSHA256] else { throw EntityIdentityResolutionFailureV1.receiptMismatch }
        try value.validateResolved(predecessor: predecessor, resolver: resolver)
        rowID = "identity.alias|\(value.workspaceID.rawValue.uuidString)|\(value.linkEventID.uuidString)"
        workspaceID = value.workspaceID.rawValue; linkEventID = value.linkEventID; aliasID = value.alias.identity.id
        canonicalEntityID = value.canonicalEntity.identity.id; revision = value.revision; mutationID = value.mutationID.rawValue
        linkSHA256 = value.linkSHA256; canonicalData = try EntityIdentityResolutionPersistenceCodecV1.encode(value)
    }

    convenience init(restoring value: EntityAliasLinkV1, command: EntityIdentityResolutionMutationCommandV1, receipt: EntityIdentityResolutionMutationReceiptV1, predecessor: EntityAliasLinkV1?, resolver: any EntityIdentityResolutionCanonicalSourceResolvingV1) throws {
        try self.init(value, command: command, receipt: receipt, predecessor: predecessor, resolver: resolver)
    }

    func value() throws -> EntityAliasLinkV1 {
        let value = try EntityIdentityResolutionPersistenceCodecV1.decode(EntityAliasLinkV1.self, from: canonicalData)
        try value.validate()
        guard value.workspaceID.rawValue == workspaceID, value.linkEventID == linkEventID, value.alias.identity.id == aliasID,
              value.canonicalEntity.identity.id == canonicalEntityID, value.revision == revision, value.mutationID.rawValue == mutationID,
              value.linkSHA256 == linkSHA256 else { throw EntityIdentityResolutionFailureV1.receiptMismatch }
        return value
    }
}

@Model final class EntityConsolidationReceiptRowV1 {
    @Attribute(.unique) var rowID: String
    var workspaceID: UUID
    var receiptID: UUID
    var sourceID: UUID
    var survivorID: UUID
    var predecessorReceiptID: UUID?
    var reversal: Bool
    var revision: UInt64
    var mutationID: UUID
    var receiptSHA256: String
    var canonicalData: Data

    init(_ value: EntityConsolidationReceiptV1, command: EntityIdentityResolutionMutationCommandV1, receipt: EntityIdentityResolutionMutationReceiptV1, predecessor: EntityConsolidationReceiptV1?, resolver: any EntityIdentityResolutionCanonicalSourceResolvingV1) throws {
        try command.validateCanonicalSources(by: resolver)
        try receipt.validate(command: command)
        guard value.revision == 1 ? predecessor == nil : predecessor != nil,
              case let .consolidation(payload, payloadPredecessor) = command.payload, payload == value, payloadPredecessor == predecessor,
              receipt.workspaceID == value.workspaceID, receipt.mutationID == value.mutationID,
              receipt.semanticSHA256s == [value.receiptSHA256] else { throw EntityIdentityResolutionFailureV1.receiptMismatch }
        try value.validateResolved(predecessor: predecessor, resolver: resolver)
        rowID = "identity.consolidation|\(value.workspaceID.rawValue.uuidString)|\(value.consolidationReceiptID.uuidString)"
        workspaceID = value.workspaceID.rawValue; receiptID = value.consolidationReceiptID; sourceID = value.source.identity.id
        survivorID = value.survivor.identity.id; predecessorReceiptID = value.supersedesReceiptID; reversal = value.reversal
        revision = value.revision; mutationID = value.mutationID.rawValue; receiptSHA256 = value.receiptSHA256
        canonicalData = try EntityIdentityResolutionPersistenceCodecV1.encode(value)
    }

    convenience init(restoring value: EntityConsolidationReceiptV1, command: EntityIdentityResolutionMutationCommandV1, receipt: EntityIdentityResolutionMutationReceiptV1, predecessor: EntityConsolidationReceiptV1?, resolver: any EntityIdentityResolutionCanonicalSourceResolvingV1) throws {
        try self.init(value, command: command, receipt: receipt, predecessor: predecessor, resolver: resolver)
    }

    func value() throws -> EntityConsolidationReceiptV1 {
        let value = try EntityIdentityResolutionPersistenceCodecV1.decode(EntityConsolidationReceiptV1.self, from: canonicalData)
        try value.validate()
        guard value.workspaceID.rawValue == workspaceID, value.consolidationReceiptID == receiptID, value.source.identity.id == sourceID,
              value.survivor.identity.id == survivorID, value.supersedesReceiptID == predecessorReceiptID, value.reversal == reversal,
              value.revision == revision, value.mutationID.rawValue == mutationID, value.receiptSHA256 == receiptSHA256
        else { throw EntityIdentityResolutionFailureV1.receiptMismatch }
        return value
    }
}

@Model final class EntityIdentityResolutionMutationReceiptRowV1 {
    @Attribute(.unique) var rowID: String
    var workspaceID: UUID
    var receiptID: UUID
    var commandID: UUID
    var generationID: UUID
    var mutationID: UUID
    var resultingWorkspaceRevision: UInt64
    var receiptSHA256: String
    var canonicalData: Data

    init(_ value: EntityIdentityResolutionMutationReceiptV1, command: EntityIdentityResolutionMutationCommandV1) throws {
        try value.validate(command: command)
        rowID = "identity.receipt|\(value.workspaceID.rawValue.uuidString)|\(value.mutationID.rawValue.uuidString)"
        workspaceID = value.workspaceID.rawValue; receiptID = value.receiptID; commandID = value.commandID
        generationID = value.generationID; mutationID = value.mutationID.rawValue; resultingWorkspaceRevision = value.resultingWorkspaceRevision
        receiptSHA256 = value.receiptSHA256; canonicalData = try EntityIdentityResolutionPersistenceCodecV1.encode(value)
    }

    convenience init(restoring value: EntityIdentityResolutionMutationReceiptV1, command: EntityIdentityResolutionMutationCommandV1) throws { try self.init(value, command: command) }

    func value() throws -> EntityIdentityResolutionMutationReceiptV1 {
        let value = try EntityIdentityResolutionPersistenceCodecV1.decode(EntityIdentityResolutionMutationReceiptV1.self, from: canonicalData)
        try value.validate()
        guard value.workspaceID.rawValue == workspaceID, value.receiptID == receiptID, value.commandID == commandID,
              value.generationID == generationID, value.mutationID.rawValue == mutationID,
              value.resultingWorkspaceRevision == resultingWorkspaceRevision, value.receiptSHA256 == receiptSHA256
        else { throw EntityIdentityResolutionFailureV1.receiptMismatch }
        return value
    }
}

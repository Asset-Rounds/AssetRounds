import Foundation
import SwiftData

enum AssistancePersistenceFailureV1: Error, Equatable, Sendable {
    case corruptRow
}

/// The sole C32 durable family. Proposals and every reject/cancel/expire
/// disposition remain memory/scratch-only and never receive a persistence row.
@Model
final class AssistanceAcceptanceReceiptRow {
    @Attribute(.unique) var receiptID: UUID
    var workspaceID: UUID
    var proposalID: UUID
    var mutationID: UUID
    var targetEntityID: UUID
    var targetRevision: UInt64
    var targetMutationSHA256: String
    var acceptedAt: Date
    var receiptSHA256: String
    var canonicalData: Data

    init(_ value: AssistanceAcceptanceReceiptV1) throws {
        try value.validate()
        receiptID = value.receiptID
        workspaceID = value.workspaceID.rawValue
        proposalID = value.proposalID
        mutationID = value.mutationID.rawValue
        targetEntityID = value.target.entity.id
        targetRevision = value.target.revision
        targetMutationSHA256 = value.targetMutationSHA256
        acceptedAt = value.acceptedAt
        receiptSHA256 = value.receiptSHA256
        canonicalData = try AssistanceCanonicalCodecV1.encode(value)
    }

    func value() throws -> AssistanceAcceptanceReceiptV1 {
        let decoded = try AssistanceCanonicalCodecV1.decode(
            AssistanceAcceptanceReceiptV1.self,
            from: canonicalData
        )
        try decoded.validate()
        guard decoded.receiptID == receiptID,
              decoded.workspaceID.rawValue == workspaceID,
              decoded.proposalID == proposalID,
              decoded.mutationID.rawValue == mutationID,
              decoded.target.entity.id == targetEntityID,
              decoded.target.revision == targetRevision,
              decoded.targetMutationSHA256 == targetMutationSHA256,
              decoded.acceptedAt == acceptedAt,
              decoded.receiptSHA256 == receiptSHA256 else {
            throw AssistancePersistenceFailureV1.corruptRow
        }
        return decoded
    }
}

enum AssistancePersistenceEnrollmentV1 {
    static let persistentSchemaVersion = 32
    static let recordsSchemaVersion = 31
    static let durableModelCount = 1
    static let totalModelCount = 110
    static let proposalIsPersistent = false
    static let rejectedProposalCorpusIsPersistent = false
}

import Foundation
import SwiftData

enum FindingOwnerPersistenceFailureV1: Error {
    case corruptRow
}

/// Canonical owner revisions share the existing store. Registry and writer
/// enrollment are required separately before this row can be admitted there.
@Model final class FindingOwnerRevisionRowV1 {
    @Attribute(.unique) var rowID: String
    var workspaceID: UUID
    var ownerKind: String
    var ownerID: UUID
    var ownerRevision: UInt64
    var predecessorSHA256: String?
    var mutationID: UUID
    var recordSHA256: String
    var canonicalData: Data

    init(_ record: FindingOwnerRecordV1) throws {
        let bytes = try FindingOwnerCanonicalCodecV1.encode(record)
        rowID = Self.rowID(workspaceID: record.workspaceID, kind: record.kind,
                           ownerID: record.ownerID, revision: record.ownerRevision)
        workspaceID = record.workspaceID.rawValue
        ownerKind = record.kind.rawValue
        ownerID = record.ownerID
        ownerRevision = record.ownerRevision
        predecessorSHA256 = record.predecessor?.recordSHA256
        mutationID = record.mutationID.rawValue
        recordSHA256 = record.recordSHA256
        canonicalData = bytes
    }

    func value() throws -> FindingOwnerRecordV1 {
        let record = try FindingOwnerCanonicalCodecV1.decode(canonicalData)
        guard record.workspaceID.rawValue == workspaceID,
              record.kind.rawValue == ownerKind,
              record.ownerID == ownerID,
              record.ownerRevision == ownerRevision,
              record.predecessor?.recordSHA256 == predecessorSHA256,
              record.mutationID.rawValue == mutationID,
              record.recordSHA256 == recordSHA256,
              rowID == Self.rowID(workspaceID: record.workspaceID, kind: record.kind,
                                  ownerID: record.ownerID, revision: record.ownerRevision) else {
            throw FindingOwnerPersistenceFailureV1.corruptRow
        }
        return record
    }

    static func rowID(workspaceID: WorkspaceID, kind: FindingOwnerKindV1,
                      ownerID: UUID, revision: UInt64) -> String {
        "\(workspaceID.rawValue.uuidString.lowercased())|\(kind.rawValue)|\(ownerID.uuidString.lowercased())|\(String(format: "%020llu", revision))"
    }
}

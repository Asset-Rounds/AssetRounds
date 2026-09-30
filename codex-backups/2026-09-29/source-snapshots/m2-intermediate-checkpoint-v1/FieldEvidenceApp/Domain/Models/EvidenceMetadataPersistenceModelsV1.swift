import Foundation
import SwiftData

enum EvidenceMetadataPersistenceEnrollmentV1 {
    static let schemaVersion = 43
    static let recordsSchemaVersion = 42
    static let durableModelCount = 2
    static let totalSchemaModelCount = 144
    static let associationEventFamily = "EVIDENCE_ASSOCIATION_EVENT"
    static let sequenceRevisionFamily = "EVIDENCE_SEQUENCE_REVISION"
}

@Model
final class EvidenceAssociationEventRowV1 {
    @Attribute(.unique) var rowID: String
    var workspaceID: String
    var evidenceID: String
    var resultingEvidenceRevision: Int
    var canonicalData: Data

    init(_ value: EvidenceAssociationV1) throws {
        rowID = "\(value.workspaceID)|\(value.associationEventID)"
        workspaceID = value.workspaceID; evidenceID = value.evidenceID
        resultingEvidenceRevision = value.resultingEvidenceRevision
        canonicalData = try EvidenceMetadataCanonicalCodecV1.data(value)
    }

    func value() throws -> EvidenceAssociationV1 {
        let value = try EvidenceMetadataCanonicalCodecV1.decode(EvidenceAssociationV1.self, from: canonicalData)
        guard rowID == "\(value.workspaceID)|\(value.associationEventID)", workspaceID == value.workspaceID,
              evidenceID == value.evidenceID, resultingEvidenceRevision == value.resultingEvidenceRevision else {
            throw EvidenceMetadataFailureV1.invalidDigest
        }
        return value
    }
}

@Model
final class EvidenceSequenceRevisionRowV1 {
    @Attribute(.unique) var rowID: String
    var sequenceID: UUID
    var workspaceID: UUID
    var revision: UInt64
    var canonicalData: Data

    init(_ value: EvidenceSequenceV1) throws {
        rowID = Self.rowID(sequenceID: value.sequenceID, revision: value.revision)
        sequenceID = value.sequenceID; workspaceID = value.workspaceID.rawValue; revision = value.revision
        canonicalData = try EvidenceMetadataCanonicalCodecV1.data(value)
    }

    func value() throws -> EvidenceSequenceV1 {
        let value = try EvidenceMetadataCanonicalCodecV1.decode(EvidenceSequenceV1.self, from: canonicalData)
        guard rowID == Self.rowID(sequenceID: sequenceID, revision: revision), value.sequenceID == sequenceID,
              value.workspaceID.rawValue == workspaceID, value.revision == revision else { throw EvidenceMetadataFailureV1.invalidDigest }
        return value
    }

    static func rowID(sequenceID: UUID, revision: UInt64) -> String {
        "\(sequenceID.uuidString.lowercased())|\(String(format: "%020llu", revision))"
    }
}

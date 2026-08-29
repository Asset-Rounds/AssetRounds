import Foundation
import SwiftData

enum TemporalEvidencePersistenceFailureV1: Error, Equatable {
    case corruptRow
}

@Model final class TemporalEvidenceClipRow {
    @Attribute(.unique) var clipID: UUID
    var workspaceID: UUID
    var sessionID: UUID
    var revision: UInt64
    var mutationID: UUID
    var originalContentID: String
    var originalSHA256: String
    var clipSHA256: String
    var canonicalData: Data

    init(_ value: TemporalEvidenceClipV1) throws {
        try value.validateIntrinsic()
        guard let originalSHA256 = value.original.digests.digest(for: .sha256)?.hexadecimalValue else {
            throw TemporalEvidencePersistenceFailureV1.corruptRow
        }
        clipID = value.clipID
        workspaceID = value.workspaceID.rawValue
        sessionID = value.target.sessionID
        revision = value.revision
        mutationID = value.mutationID.rawValue
        originalContentID = value.original.contentID
        self.originalSHA256 = originalSHA256
        clipSHA256 = value.clipSHA256
        canonicalData = try TemporalEvidenceCanonicalCodecV1.encode(value)
        guard try TemporalEvidenceCanonicalCodecV1.decode(TemporalEvidenceClipV1.self, from: canonicalData) == value else {
            throw TemporalEvidencePersistenceFailureV1.corruptRow
        }
    }

    func value() throws -> TemporalEvidenceClipV1 {
        let value = try TemporalEvidenceCanonicalCodecV1.decode(TemporalEvidenceClipV1.self, from: canonicalData)
        try value.validateIntrinsic()
        guard let decodedSHA256 = value.original.digests.digest(for: .sha256)?.hexadecimalValue,
              value.clipID == clipID,
              value.workspaceID.rawValue == workspaceID,
              value.target.sessionID == sessionID,
              value.revision == revision,
              value.mutationID.rawValue == mutationID,
              value.original.contentID == originalContentID,
              decodedSHA256 == originalSHA256,
              value.clipSHA256 == clipSHA256 else {
            throw TemporalEvidencePersistenceFailureV1.corruptRow
        }
        return value
    }
}

@Model final class TimecodedEvidenceAnchorRow {
    @Attribute(.unique) var anchorID: UUID
    var workspaceID: UUID
    var clipID: UUID
    var clipRevision: UInt64
    var revision: UInt64
    var mutationID: UUID
    var sourceContentID: String
    var sourceSHA256: String
    var anchorSHA256: String
    var canonicalData: Data

    init(_ value: TimecodedEvidenceAnchorV1) throws {
        try value.validateIntrinsic()
        anchorID = value.anchorID
        workspaceID = value.workspaceID.rawValue
        clipID = value.clipID
        clipRevision = value.clipRevision
        revision = value.revision
        mutationID = value.mutationID.rawValue
        sourceContentID = value.sourceContentID
        sourceSHA256 = value.sourceSHA256
        anchorSHA256 = value.anchorSHA256
        canonicalData = try TemporalEvidenceCanonicalCodecV1.encode(value)
        guard try TemporalEvidenceCanonicalCodecV1.decode(TimecodedEvidenceAnchorV1.self, from: canonicalData) == value else {
            throw TemporalEvidencePersistenceFailureV1.corruptRow
        }
    }

    func value() throws -> TimecodedEvidenceAnchorV1 {
        let value = try TemporalEvidenceCanonicalCodecV1.decode(TimecodedEvidenceAnchorV1.self, from: canonicalData)
        try value.validateIntrinsic()
        guard value.anchorID == anchorID,
              value.workspaceID.rawValue == workspaceID,
              value.clipID == clipID,
              value.clipRevision == clipRevision,
              value.revision == revision,
              value.mutationID.rawValue == mutationID,
              value.sourceContentID == sourceContentID,
              value.sourceSHA256 == sourceSHA256,
              value.anchorSHA256 == anchorSHA256 else {
            throw TemporalEvidencePersistenceFailureV1.corruptRow
        }
        return value
    }
}

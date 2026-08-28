import Foundation
import SwiftData

enum RecoverabilityVerificationPersistenceFailureV1: Error {
    case corruptRow
}

@Model
final class RecoverabilityVerificationReceiptRow {
    @Attribute(.unique) var receiptID: UUID
    var workspaceID: UUID
    var verificationID: UUID
    var archiveSHA256: String
    var revision: UInt64
    var mutationID: UUID
    var receiptSHA256: String
    var canonicalData: Data

    init(_ value: RecoverabilityVerificationReceiptV1) throws {
        try value.validate()
        receiptID = value.receiptID
        workspaceID = value.workspaceID.rawValue
        verificationID = value.verificationID
        archiveSHA256 = value.archive.archiveSHA256
        revision = value.revision
        mutationID = value.mutationID.rawValue
        receiptSHA256 = value.receiptSHA256
        canonicalData = try RecoverabilityVerificationCanonicalCodecV1.encode(value)
    }

    func value() throws -> RecoverabilityVerificationReceiptV1 {
        let value = try RecoverabilityVerificationCanonicalCodecV1.decode(
            RecoverabilityVerificationReceiptV1.self,
            from: canonicalData
        )
        try value.validate()
        guard value.schemaVersion == RecoverabilityVerificationReceiptV1.schemaVersion,
              value.receiptID == receiptID,
              value.workspaceID.rawValue == workspaceID,
              value.verificationID == verificationID,
              value.archive.archiveSHA256 == archiveSHA256,
              value.revision == revision,
              value.mutationID.rawValue == mutationID,
              value.receiptSHA256 == receiptSHA256 else {
            throw RecoverabilityVerificationPersistenceFailureV1.corruptRow
        }
        return value
    }
}

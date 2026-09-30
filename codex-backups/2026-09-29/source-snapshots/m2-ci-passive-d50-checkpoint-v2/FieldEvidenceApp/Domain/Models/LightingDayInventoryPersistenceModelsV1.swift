import Foundation
import SwiftData

/// The C17 aggregate is one append-only canonical row.  Safety stops,
/// condition snapshots, and any night follow-up plan remain immutable fields
/// of this one workflow record; they are not independently durable families.
@Model final class LightingDayInventoryWorkflowRowV1 {
    @Attribute(.unique) var recordID: UUID
    var workflowID: UUID
    var workspaceID: UUID
    var systemID: UUID
    var systemRevision: UInt64
    var stateRawValue: String
    var supersedesRecordID: UUID?
    var revision: UInt64
    var mutationID: UUID
    var workflowSHA256: String
    var canonicalData: Data

    init(_ value: LightingDayInventoryWorkflowV1) throws {
        try value.validateIntrinsic()
        recordID = value.recordID
        workflowID = value.workflowID
        workspaceID = value.workspaceID.rawValue
        systemID = value.systemID
        systemRevision = value.systemRevision
        stateRawValue = value.state.rawValue
        supersedesRecordID = value.supersedesRecordID
        revision = value.revision
        mutationID = value.mutationID.rawValue
        workflowSHA256 = value.workflowSHA256
        canonicalData = try LightingDayInventoryCanonicalCodecV1.encode(value)
    }

    func value() throws -> LightingDayInventoryWorkflowV1 {
        let decoded = try LightingDayInventoryCanonicalCodecV1.decode(
            LightingDayInventoryWorkflowV1.self,
            from: canonicalData
        )
        try decoded.validateIntrinsic()
        guard decoded.recordID == recordID,
              decoded.workflowID == workflowID,
              decoded.workspaceID.rawValue == workspaceID,
              decoded.systemID == systemID,
              decoded.systemRevision == systemRevision,
              decoded.state.rawValue == stateRawValue,
              decoded.supersedesRecordID == supersedesRecordID,
              decoded.revision == revision,
              decoded.mutationID.rawValue == mutationID,
              decoded.workflowSHA256 == workflowSHA256 else {
            throw LightingPersistenceFailureV1.corruptRow
        }
        return decoded
    }
}

/// C17 intentionally adds exactly one durable aggregate and reuses the
/// incumbent generic MutationReceiptRow. Offline readiness is derived-only.
enum LightingDayInventoryPersistenceEnrollmentV1 {
    static let persistentSchemaVersion = 52
    static let durableModelCount = 1
    static let totalModelCount = 167
    static let usesGenericMutationReceiptOnly = true
    static let offlineReadinessManifestIsPersistent = false
}

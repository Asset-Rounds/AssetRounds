import Foundation
import SwiftData

/// C18 has one append-only night-workflow aggregate. Incident grouping,
/// repair, recheck, and reopen history remain immutable canonical fields of
/// this row; the repair policy, report, search, and readiness are not rows.
@Model final class LightingNightWorkflowRowV1 {
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

    init(_ value: LightingNightWorkflowV1) throws {
        try value.validateIntrinsic()
        recordID = value.recordID
        workflowID = value.workflowID
        workspaceID = value.workspaceID.rawValue
        systemID = value.system.systemID
        systemRevision = value.system.systemRevision
        stateRawValue = value.state.rawValue
        supersedesRecordID = value.supersedesRecordID
        revision = value.revision
        mutationID = value.mutationID.rawValue
        workflowSHA256 = value.workflowSHA256
        canonicalData = try LightingCanonicalCodecV1.encode(value)
    }

    func value() throws -> LightingNightWorkflowV1 {
        let decoded = try LightingCanonicalCodecV1.decode(
            LightingNightWorkflowV1.self,
            from: canonicalData
        )
        try decoded.validateIntrinsic()
        guard decoded.recordID == recordID,
              decoded.workflowID == workflowID,
              decoded.workspaceID.rawValue == workspaceID,
              decoded.system.systemID == systemID,
              decoded.system.systemRevision == systemRevision,
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

/// C18 adds exactly one durable aggregate and reuses the generic
/// MutationReceiptRow. Derived report/search/readiness and policy values are
/// deliberately not separate persistent families.
enum LightingNightWorkflowPersistenceEnrollmentV1 {
    static let persistentSchemaVersion = 53
    static let durableModelCount = 1
    static let totalModelCount = 168
    static let usesGenericMutationReceiptOnly = true
    static let repairPolicyIsPersistent = false
    static let derivedProjectionIsPersistent = false
    static let offlineReadinessManifestIsPersistent = false
}

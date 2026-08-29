import Foundation

enum SurveySessionDeletionLedgerStoreEnrollmentV1{static let retainedFrozenKind="SurveyPublicationSnapshotRow";static let workspaceEraseKinds=SurveySessionKernelDeletionEnrollmentV1.persistentRowNames}
import SwiftData

enum FieldReferenceDeletionLedgerStorePolicyV1{static func validate()throws{guard FieldReferenceDeletionLedgerPolicyV1.immutableKinds==["FieldReferenceReleaseV1","FieldReferenceBindingV1"],FieldReferenceDeletionLedgerPolicyV1.ordinaryDeletionRetainsBoundAndFinalizedBytes,FieldReferenceDeletionLedgerPolicyV1.workspaceEraseRemovesRowsAndOwnedBytes else{throw DeletionLedgerFailureV2.invalidIdentity}}}
enum AccessibleDocumentDeletionLedgerStorePolicyV1{static func validate()throws{try AccessibleDocumentDeletionLedgerPolicyV1.validate()}}
enum SurveyDefinitionDeletionLedgerStorePolicyV1{static func validate()throws{try SurveyDefinitionDeletionLedgerPolicyV1.validate()}}
enum ScheduleDeletionLedgerStorePolicyV1 {
    static func validate() throws {
        try ScheduleDeletionLedgerPolicyV1.validate()
        guard ScheduleDeletionLedgerPolicyV1.durableKinds.count == 2,
              ScheduleDeletionLedgerPolicyV1.lifecycleEventsRemainInMutationHistory,
              ScheduleDeletionLedgerPolicyV1.ordinaryDeletionPreservesReleaseAndOccurrenceHistory,
              ScheduleDeletionLedgerPolicyV1.workspaceEraseRemovesAll else {
            throw DeletionLedgerFailureV2.invalidIdentity
        }
    }
}
enum PlanDeletionLedgerStorePolicyV1 {
    static let durableRowNames: Set<String> = [
        "PlanDocumentRow", "PlanRevisionRow", "PlanPlacementRow", "RebaseReceiptRow"
    ]
    static let embeddedTransportFamily = "SpatialReferenceFrameV1"
    static let ordinaryDeletionPreservesHistory = true
    static let workspaceEraseRemovesRows = true
    static let previewsAndRegistriesAreDerived = true

    static func validate() throws {
        guard durableRowNames.count == PlanPersistenceEnrollmentV1.durableModelCount,
              embeddedTransportFamily == "SpatialReferenceFrameV1",
              ordinaryDeletionPreservesHistory,
              workspaceEraseRemovesRows,
              previewsAndRegistriesAreDerived else {
            throw DeletionLedgerFailureV2.invalidIdentity
        }
        try PlanDeletionLedgerPolicyV1.validate()
    }
}
enum AssetLocatorDeletionLedgerStorePolicyV1 {
    static let durableRowNames: Set<String> = [
        "AssetLocatorRow", "LocatorBindingReceiptRow"
    ]
    static let noOrphanLookupOrReceiptRows = true
    static let historySource = "MUTATION_HISTORY_ONLY"

    static func validate() throws {
        guard durableRowNames.count == 2,
              noOrphanLookupOrReceiptRows,
              historySource == "MUTATION_HISTORY_ONLY" else {
            throw DeletionLedgerFailureV2.invalidIdentity
        }
        try AssetLocatorDeletionLedgerPolicyV1.validate()
    }
}

@MainActor
final class DeletionLedgerStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func snapshot() throws -> DeletionLedgerV2 {
        try AssetLocatorDeletionLedgerStorePolicyV1.validate()
        try FieldReferenceDeletionLedgerStorePolicyV1.validate()
        try AccessibleDocumentDeletionLedgerStorePolicyV1.validate()
        try SurveyDefinitionDeletionLedgerStorePolicyV1.validate()
        try ScheduleDeletionLedgerStorePolicyV1.validate()
        try PlanDeletionLedgerStorePolicyV1.validate()
        try SurveySessionDeletionLedgerPolicyV1.validate()
        var descriptor = FetchDescriptor<DeletionLedgerRow>()
        descriptor.fetchLimit = DeletionLedgerV2.maximumEntryCount + 1
        let rows = try context.fetch(descriptor)
        guard rows.count <= DeletionLedgerV2.maximumEntryCount else {
            throw DeletionLedgerFailureV2.invalidIdentity
        }
        let entries = try rows.map { row in
            try DeletionLedgerEntryV2(
                identity: DeletionIdentityV2(typedID: row.typedID),
                deletedAt: row.deletedAt,
                schemaVersion: row.schemaVersion
            )
        }.sorted { $0.identity < $1.identity }
        return try DeletionLedgerV2(entries: entries)
    }

    /// Stages an append-only union in the caller's ModelContext. The caller
    /// owns the single save that commits ledger rows with content deletion.
    func stageUnion(_ entries: [DeletionLedgerEntryV2]) throws {
        let incoming = try DeletionLedgerV2(
            entries: entries.sorted { $0.identity < $1.identity }
        )
        var descriptor = FetchDescriptor<DeletionLedgerRow>()
        descriptor.fetchLimit = DeletionLedgerV2.maximumEntryCount + 1
        let existingRows = try context.fetch(descriptor)
        let projectedIDs = Set(existingRows.map(\.typedID))
            .union(incoming.entries.map { $0.identity.typedID })
        guard existingRows.count <= DeletionLedgerV2.maximumEntryCount,
              projectedIDs.count <= DeletionLedgerV2.maximumEntryCount else {
            throw DeletionLedgerFailureV2.invalidIdentity
        }
        var rowsByID: [String: DeletionLedgerRow] = [:]
        for row in existingRows {
            guard rowsByID.updateValue(row, forKey: row.typedID) == nil else {
                throw DeletionLedgerFailureV2.duplicateIdentity
            }
        }
        for entry in incoming.entries {
            if let row = rowsByID[entry.identity.typedID] {
                if entry.deletedAt < row.deletedAt {
                    row.deletedAt = entry.deletedAt
                }
            } else {
                let row = DeletionLedgerRow(
                    typedID: entry.identity.typedID,
                    deletedAt: entry.deletedAt
                )
                context.insert(row)
                rowsByID[row.typedID] = row
            }
        }
    }

    func requireContains(_ identities: Set<DeletionIdentityV2>) throws {
        let actual = Set(try snapshot().entries.map(\.identity))
        guard identities.isSubset(of: actual) else {
            throw DeletionLedgerFailureV2.invalidIdentity
        }
    }
}

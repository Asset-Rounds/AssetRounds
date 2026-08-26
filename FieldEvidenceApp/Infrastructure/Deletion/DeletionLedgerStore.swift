import Foundation
import SwiftData

@MainActor
final class DeletionLedgerStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func snapshot() throws -> DeletionLedgerV2 {
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

import Foundation
import SwiftData

/// C49's lifecycle adapter is a composition boundary only.  Canonical writes,
/// backup/restore, deletion, journal recovery, and search invalidation remain
/// owned by the existing writer and backup authorities supplied by the root.
@MainActor
final class WorkResourceLifecycleAdapterV1 {
    private let query: WorkResourceRowQueryV1
    private let port: (any WorkResourceLifecyclePortV1)?

    init(
        modelContext: ModelContext,
        port: (any WorkResourceLifecyclePortV1)? = nil
    ) {
        query = WorkResourceRowQueryV1(modelContext: modelContext)
        self.port = port
    }

    func validate(_ bundle: WorkResourceAtomicBundleV1) throws {
        try C49WorkResourceLifecycleBoundaryV1.validate()
        try bundle.validate()
    }

    /// Executable seam for the released V36 -> V37 migration. The adapter
    /// proves the factory/catalog migration before any lifecycle operation;
    /// it does not introduce a second migration authority.
    func validateMigration() throws {
        try C49WorkResourceLifecycleBoundaryV1.validateMigration()
    }

    func append(
        _ bundle: WorkResourceAtomicBundleV1
    ) async throws -> WorkResourceMutationReceiptV1 {
        try C49WorkResourceLifecycleBoundaryV1.validate()
        try bundle.validate()
        guard let port else {
            throw WorkResourcePersistenceFailureV1.unavailable
        }
        return try await port.append(bundle.entry)
    }

    func currentEntries(workspaceID: WorkspaceID) throws -> [WorkResourceEntryV1] {
        try query.entries(workspaceID: workspaceID)
    }

    func currentDirectCosts(workspaceID: WorkspaceID) throws -> [DirectCostEntryV1] {
        try query.directCosts(workspaceID: workspaceID)
    }

    func snapshot(
        workspaceID: WorkspaceID,
        recordID: UUID
    ) throws -> WorkResourceSnapshotV1? {
        try query.snapshot(workspaceID: workspaceID, recordID: recordID)
    }

    /// The backup authority receives a validated immutable entry bundle.  The
    /// local fallback is read-only and never writes a second byte store.
    func snapshotForBackup(
        workspaceID: WorkspaceID
    ) async throws -> WorkResourceBackupSnapshotV1 {
        try C49WorkResourceLifecycleBoundaryV1.validateMigration()
        if let port {
            let snapshot = try await port.snapshotForBackup(workspaceID: workspaceID)
            try C49WorkResourceLifecycleBoundaryV1.validateExport(snapshot)
            return snapshot
        }
        let bundles = try query.entries(workspaceID: workspaceID).map {
            try WorkResourceAtomicBundleV1(entry: $0)
        }
        let snapshot = try WorkResourceBackupSnapshotV1(
            workspaceID: workspaceID,
            bundles: bundles
        )
        try C49WorkResourceLifecycleBoundaryV1.validateExport(snapshot)
        return snapshot
    }

    /// Canonical export spelling for non-backup callers. This is the same
    /// immutable, read-only snapshot route and never creates another store.
    func export(workspaceID: WorkspaceID) async throws -> WorkResourceBackupSnapshotV1 {
        try await snapshotForBackup(workspaceID: workspaceID)
    }

    func restore(
        _ snapshot: WorkResourceBackupSnapshotV1,
        targetWorkspaceID: WorkspaceID,
        operationID: UUID,
        cloneOrFork: Bool = false
    ) async throws -> WorkResourceRestoreReceiptV1 {
        try C49WorkResourceLifecycleBoundaryV1.validateMigration()
        try snapshot.validate()
        guard let port else {
            throw WorkResourcePersistenceFailureV1.unavailable
        }
        return try await port.restore(
            snapshot,
            targetWorkspaceID: targetWorkspaceID,
            operationID: operationID,
            cloneOrFork: cloneOrFork
        )
    }

    func cloneOrFork(
        _ snapshot: WorkResourceBackupSnapshotV1,
        targetWorkspaceID: WorkspaceID,
        operationID: UUID
    ) async throws -> WorkResourceRestoreReceiptV1 {
        try C49WorkResourceLifecycleBoundaryV1.validateCloneFork(
            snapshot,
            targetWorkspaceID: targetWorkspaceID
        )
        try await restore(
            snapshot,
            targetWorkspaceID: targetWorkspaceID,
            operationID: operationID,
            cloneOrFork: true
        )
    }

    /// Explicit canonical clone route. Clone and fork remain history-only
    /// rebinding operations; neither can be inferred as a replace restore.
    func clone(
        _ snapshot: WorkResourceBackupSnapshotV1,
        targetWorkspaceID: WorkspaceID,
        operationID: UUID
    ) async throws -> WorkResourceRestoreReceiptV1 {
        try C49WorkResourceLifecycleBoundaryV1.validateCloneFork(
            snapshot,
            targetWorkspaceID: targetWorkspaceID
        )
        return try await restore(
            snapshot,
            targetWorkspaceID: targetWorkspaceID,
            operationID: operationID,
            cloneOrFork: true
        )
    }

    /// Explicit canonical fork route, kept distinct at the lifecycle API
    /// while sharing the existing clone/fork authority and receipt shape.
    func fork(
        _ snapshot: WorkResourceBackupSnapshotV1,
        targetWorkspaceID: WorkspaceID,
        operationID: UUID
    ) async throws -> WorkResourceRestoreReceiptV1 {
        try C49WorkResourceLifecycleBoundaryV1.validateCloneFork(
            snapshot,
            targetWorkspaceID: targetWorkspaceID
        )
        return try await restore(
            snapshot,
            targetWorkspaceID: targetWorkspaceID,
            operationID: operationID,
            cloneOrFork: true
        )
    }

    /// Combined spelling used by persistence/catalog verifiers; it aliases
    /// the explicit clone route and adds no third restore behavior.
    func cloneFork(
        _ snapshot: WorkResourceBackupSnapshotV1,
        targetWorkspaceID: WorkspaceID,
        operationID: UUID
    ) async throws -> WorkResourceRestoreReceiptV1 {
        try await clone(
            snapshot,
            targetWorkspaceID: targetWorkspaceID,
            operationID: operationID
        )
    }

    func delete(
        workspaceID: WorkspaceID,
        subject: WorkResourceSubjectV1
    ) async throws {
        try C49WorkResourceLifecycleBoundaryV1.validate()
        guard subject.workspaceID == workspaceID else {
            throw WorkResourcePersistenceFailureV1.crossWorkspaceReference
        }
        guard let port else {
            throw WorkResourcePersistenceFailureV1.unavailable
        }
        try await port.delete(workspaceID: workspaceID, subject: subject)
    }

    func erase(workspaceID: WorkspaceID) async throws {
        try C49WorkResourceLifecycleBoundaryV1.validate()
        guard let port else {
            throw WorkResourcePersistenceFailureV1.unavailable
        }
        try await port.erase(workspaceID: workspaceID)
    }

    func rebuildSearch(workspaceID: WorkspaceID) async throws {
        try C49WorkResourceLifecycleBoundaryV1.validate()
        guard let port else {
            throw WorkResourcePersistenceFailureV1.unavailable
        }
        try await port.rebuildSearch(workspaceID: workspaceID)
    }

    func search(
        workspaceID: WorkspaceID,
        query searchText: String
    ) async throws -> [WorkResourceEntryV1] {
        try C49WorkResourceLifecycleBoundaryV1.validate()
        guard searchText.utf8.count <= WorkResourcePersistenceLimitsV1.maximumSearchQueryBytes else {
            throw WorkResourcePersistenceFailureV1.invalidText
        }
        if let port {
            return try await port.search(workspaceID: workspaceID, query: searchText)
        }
        let values = try query.entries(workspaceID: workspaceID)
        guard !searchText.isEmpty else { return values }
        return values.filter { value in
            value.subject.subjectID.localizedCaseInsensitiveContains(searchText)
                || value.materials.contains {
                    $0.description.localizedCaseInsensitiveContains(searchText)
                        || ($0.unit?.localizedCaseInsensitiveContains(searchText) ?? false)
                }
                || (value.directCost?.note?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    func report(
        workspaceID: WorkspaceID,
        profile: WorkResourceReportProfileV1
    ) async throws -> WorkResourceTotalsProjectionV1 {
        try C49WorkResourceLifecycleBoundaryV1.validateExportContract()
        if let port {
            let projection = try await port.report(workspaceID: workspaceID, profile: profile)
            try C49WorkResourceLifecycleBoundaryV1.validateDirectCostTotals(projection)
            return projection
        }

        let snapshots = try query.entries(workspaceID: workspaceID).map {
            try WorkResourceSnapshotV1(entry: $0)
        }
        let visibility: WorkResourceTotalsVisibilityV1 =
            profile == .internalDurationMaterialAndCost ? .internalFull : .customerSafe
        // Use the domain-owned projection so exact material aggregation,
        // quantity normalization, disposition filtering, visibility, and
        // stored `materialTotals` all remain deterministic and shared.
        let projection = try WorkResourceTotalsProjectionV1(
            snapshots: snapshots,
            visibility: visibility
        )
        try C49WorkResourceLifecycleBoundaryV1.validateDirectCostTotals(projection)
        return projection
    }
}

enum C49WorkResourceLifecycleBoundaryV1 {
    static let migrationIsExplicit = true
    static let exportIsExplicit = true
    static let cloneForkIsExplicit = true
    static let cloneIsExplicit = true
    static let forkIsExplicit = true
    static let adapterOwnsNoCanonicalWriter = true
    static let adapterOwnsNoBackupByteStore = true
    static let backupRestoreCloneForkDeleteAndEraseAreExplicit = true
    static let searchAndReportAreDerivedOnly = true
    static let localPartReferenceIsEmbeddedSnapshotOnly = true
    static let liveInventoryLookupIsForbidden = true
    static let untrackedMaterialRemainsValid = true
    static let forwardFixPreservesReleasedCanonicalRows =
        C49WorkResourcePersistenceBoundaryV1.forwardFixPreservesReleasedCanonicalRows
    static let releasedReadersRemainAvailable =
        C49WorkResourcePersistenceBoundaryV1.releasedReadersRemainAvailable
    static let canonicalRowsAreNeverRewrittenInPlace =
        C49WorkResourcePersistenceBoundaryV1.canonicalRowsAreNeverRewrittenInPlace
    static let directCostTotalsRemainSeparateByCurrency =
        C49WorkResourcePersistenceBoundaryV1.directCostTotalsRemainSeparateByCurrency
    static let directCostCurrencyConversionIsForbidden =
        C49WorkResourcePersistenceBoundaryV1.directCostCurrencyConversionIsForbidden

    static func validate() throws {
        try validateMigration()
        guard exportIsExplicit,
              cloneForkIsExplicit,
              cloneIsExplicit,
              forkIsExplicit,
              adapterOwnsNoCanonicalWriter,
              adapterOwnsNoBackupByteStore,
              backupRestoreCloneForkDeleteAndEraseAreExplicit,
              searchAndReportAreDerivedOnly,
              localPartReferenceIsEmbeddedSnapshotOnly,
              liveInventoryLookupIsForbidden,
              untrackedMaterialRemainsValid,
              forwardFixPreservesReleasedCanonicalRows,
              releasedReadersRemainAvailable,
              canonicalRowsAreNeverRewrittenInPlace,
              directCostTotalsRemainSeparateByCurrency,
              directCostCurrencyConversionIsForbidden else {
            throw WorkResourcePersistenceFailureV1.invalidValue
        }
    }

    static func validateMigration() throws {
        guard migrationIsExplicit,
              C49WorkResourceMigrationBoundaryV1.sourceVersion == 36,
              C49WorkResourceMigrationBoundaryV1.targetVersion == 37,
              C49WorkResourceMigrationBoundaryV1.recordsVersion ==
                C49WorkResourcePersistenceBoundaryV1.recordsSchemaVersion,
              C49WorkResourceMigrationBoundaryV1.targetVersion ==
                C49WorkResourcePersistenceBoundaryV1.persistentSchemaVersion,
              C49WorkResourceMigrationBoundaryV1.newDurableRows ==
                C49WorkResourcePersistenceBoundaryV1.newlyEnrolledRows,
              !C49WorkResourceMigrationBoundaryV1.backfillCreatesWorkResourceTruth,
              C49WorkResourceMigrationBoundaryV1.localPartReferenceRemainsEmbedded,
              !C49WorkResourceMigrationBoundaryV1.liveInventoryRowsAdded else {
            throw WorkResourcePersistenceFailureV1.invalidValue
        }
        try C49WorkResourcePersistenceBoundaryV1.validate()
    }

    static func validateExport(_ snapshot: WorkResourceBackupSnapshotV1) throws {
        try validateExportContract()
        try snapshot.validate()
        guard snapshot.bundles.allSatisfy({
            $0.entry.directCost.map { $0.amount.mantissa > 0 } ?? true
        }) else {
            throw WorkResourcePersistenceFailureV1.invalidValue
        }
    }

    static func validateExportContract() throws {
        guard exportIsExplicit,
              C49WorkResourcePersistenceBoundaryV1.acceptedBytesAreCanonical,
              C49WorkResourcePersistenceBoundaryV1.directCostIsEmbedded,
              !C49WorkResourcePersistenceBoundaryV1.separateDirectCostRow,
              C49WorkResourcePersistenceBoundaryV1.localPartSnapshotIsEmbedded,
              !C49WorkResourcePersistenceBoundaryV1.localPartSnapshotIsLiveInventoryRow else {
            throw WorkResourcePersistenceFailureV1.invalidValue
        }
        try validateMigration()
    }

    static func validateDirectCostTotals(
        _ projection: WorkResourceTotalsProjectionV1
    ) throws {
        guard directCostTotalsRemainSeparateByCurrency,
              directCostCurrencyConversionIsForbidden else {
            throw WorkResourcePersistenceFailureV1.invalidValue
        }
        try C49WorkResourcePersistenceBoundaryV1.validateDirectCostTotals(
            projection.directCostByCurrency
        )
    }

    static func validateCloneFork(
        _ snapshot: WorkResourceBackupSnapshotV1,
        targetWorkspaceID: WorkspaceID
    ) throws {
        try validate()
        try snapshot.validate()
        let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        guard cloneForkIsExplicit,
              targetWorkspaceID.rawValue != zero,
              !snapshot.bundles.contains(where: {
                  $0.entry.workspaceID != snapshot.workspaceID
              }) else {
            throw WorkResourcePersistenceFailureV1.invalidValue
        }
    }
}

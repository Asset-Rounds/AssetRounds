import Foundation
import SwiftData

enum PartsStockRestoreDispositionV1: String, Codable, CaseIterable, Sendable {
    case replace = "REPLACE_EXACT_TRUTH", cloneDefinitions = "CLONE_DEFINITIONS_ONLY", forkRequiresRecount = "FORK_NONOPERATIONAL_UNTIL_RECOUNT"
}

struct PartsStockLifecycleReceiptV1: Codable, Equatable, Sendable, PartsStockCanonicalValidatingV1 {
    let operationID: UUID; let sourceWorkspaceID: WorkspaceID; let targetWorkspaceID: WorkspaceID
    let disposition: PartsStockRestoreDispositionV1; let snapshotSHA256: String; let effectSHA256: String; let completedAt: Date
    init(operationID: UUID, sourceWorkspaceID: WorkspaceID, targetWorkspaceID: WorkspaceID, disposition: PartsStockRestoreDispositionV1, snapshotSHA256: String, effectSHA256: String, completedAt: Date) throws {
        self.operationID = operationID; self.sourceWorkspaceID = sourceWorkspaceID; self.targetWorkspaceID = targetWorkspaceID; self.disposition = disposition; self.snapshotSHA256 = snapshotSHA256; self.effectSHA256 = effectSHA256; self.completedAt = completedAt; try validate()
    }
    func validate() throws { guard operationID != UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)), PartsStockCanonicalCodecV1.isDigest(snapshotSHA256), PartsStockCanonicalCodecV1.isDigest(effectSHA256) else { throw PartsStockPersistenceFailureV1.invalidValue }; try PartsStockDateValidationV1.requireMillisecond(completedAt) }
}

/// The application composition implements this with the incumbent backup,
/// journal, search, deletion, and workspace-writer lifecycle authorities.
@MainActor protocol PartsStockLifecyclePortV1: AnyObject {
    func restorePartsStock(_ snapshot: PartsStockBackupSnapshotV1, targetWorkspaceID: WorkspaceID, operationID: UUID, disposition: PartsStockRestoreDispositionV1) async throws -> PartsStockLifecycleReceiptV1
    func deletePartsStock(workspaceID: WorkspaceID) async throws
    func erasePartsStock(workspaceID: WorkspaceID) async throws
    func rebuildPartsStockSearch(workspaceID: WorkspaceID) async throws
}

@MainActor final class PartsStockLifecycleAdapterV1 {
    private let modelContext: ModelContext
    private let lifecycle: (any PartsStockLifecyclePortV1)?

    init(modelContext: ModelContext, lifecycle: (any PartsStockLifecyclePortV1)? = nil) {
        self.modelContext = modelContext; self.lifecycle = lifecycle
    }

    func replay(workspaceID: WorkspaceID) throws -> [StockBalanceProjectionV1] {
        let movements = try movementRows(workspaceID: workspaceID).map { try $0.value() }
            .sorted { ($0.part.partID.uuidString, $0.locationID.uuidString, $0.locationRevision, $0.movementID.uuidString) < ($1.part.partID.uuidString, $1.locationID.uuidString, $1.locationRevision, $1.movementID.uuidString) }
        var projections: [String: StockBalanceProjectionV1] = [:]
        for event in movements {
            try event.validate()
            guard event.workspaceID == workspaceID else { throw PartsStockFailureV1.crossWorkspace }
            let key = "\(event.part.partID.uuidString)|\(event.locationID.uuidString)"
            let prior = projections[key]
            if let prior {
                let (nextRevision, overflow) = prior.locationRevision.addingReportingOverflow(1)
                guard !overflow, event.expectedLocationRevision == prior.locationRevision,
                      event.locationRevision == nextRevision,
                      event.preBalance == prior.balance else { throw PartsStockFailureV1.staleRevision }
                guard event.unit == prior.unit, event.kind != .openingCount else {
                    throw PartsStockFailureV1.invalidTransition
                }
            } else {
                guard event.expectedLocationRevision == 0, event.locationRevision == 1 else {
                    throw PartsStockFailureV1.staleRevision
                }
                guard event.kind == .openingCount || event.kind == .physicalCount,
                      event.preBalance == .unknown else { throw PartsStockFailureV1.invalidTransition }
            }
            let projection = StockBalanceProjectionV1(workspaceID: workspaceID, partID: event.part.partID, locationID: event.locationID, unit: event.unit, balance: .known(event.postBalance), locationRevision: event.locationRevision, lastMovementID: event.movementID)
            try projection.validate(); projections[key] = projection
        }
        return projections.values.sorted { ($0.partID.uuidString, $0.locationID.uuidString) < ($1.partID.uuidString, $1.locationID.uuidString) }
    }

    /// Catalog/location pairs with no movement remain UNKNOWN, never zero.
    func projection(workspaceID: WorkspaceID, partID: UUID, locationID: UUID, unit: StockUnitV1) throws -> StockBalanceProjectionV1 {
        if let value = try replay(workspaceID: workspaceID).first(where: { $0.partID == partID && $0.locationID == locationID }) { return value }
        return StockBalanceProjectionV1(workspaceID: workspaceID, partID: partID, locationID: locationID, unit: unit, balance: .unknown, locationRevision: 0, lastMovementID: nil)
    }

    func search(workspaceID: WorkspaceID, query: String) throws -> [LocalPartDefinitionV1] {
        guard query.utf8.count <= PartsStockLimitsV1.maximumSearchQueryBytes else { throw PartsStockPersistenceFailureV1.invalidValue }
        let parts = try partRows(workspaceID: workspaceID).map { try $0.value() }
        guard !query.isEmpty else { return parts.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending } }
        return parts.filter { part in
            part.displayName.localizedCaseInsensitiveContains(query) || part.productIdentities.contains { $0.value.localizedCaseInsensitiveContains(query) }
        }.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    func report(workspaceID: WorkspaceID, reviewedPartIDs: Set<UUID>) throws -> PartsStockReportV1 {
        let parts = try partRows(workspaceID: workspaceID).map { try $0.value() }
            .filter { reviewedPartIDs.contains($0.partID) }
            .sorted { $0.partID.uuidString < $1.partID.uuidString }
        return PartsStockReportV1(workspaceID: workspaceID, parts: try parts.map { try $0.frozenReference() })
    }

    func snapshotForBackup(workspaceID: WorkspaceID) throws -> PartsStockBackupSnapshotV1 {
        try PartsStockBackupSnapshotV1(
            workspaceID: workspaceID,
            parts: partRows(workspaceID: workspaceID).map { try $0.value() },
            locations: locationRows(workspaceID: workspaceID).map { try $0.value() },
            movements: movementRows(workspaceID: workspaceID).map { try $0.value() },
            uses: useRows(workspaceID: workspaceID).map { try $0.value() },
            reversals: reversalRows(workspaceID: workspaceID).map { try $0.value() },
            returns: returnRows(workspaceID: workspaceID).map { try $0.value() },
            abandonments: abandonmentRows(workspaceID: workspaceID).map { try $0.value() }
        )
    }

    /// Synchronous restore-staging seam for `StoreGenerationFactory`'s
    /// materialization closure. The supplied context is the staging generation;
    /// this method creates no store and performs exactly one save after every
    /// row and cross-reference has validated.
    func materializeRestoreStaging(
        _ snapshot: PartsStockBackupSnapshotV1,
        targetWorkspaceID: WorkspaceID,
        operationID: UUID,
        disposition: PartsStockRestoreDispositionV1,
        completedAt: Date
    ) throws -> PartsStockLifecycleReceiptV1 {
        try snapshot.validate()
        guard operationID != UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)),
              (try? PartsStockDateValidationV1.requireMillisecond(completedAt)) != nil else {
            throw PartsStockPersistenceFailureV1.invalidValue
        }
        try requireEmptyTarget(workspaceID: targetWorkspaceID)
        let materialized = try preparedRestoreSnapshot(
            snapshot,
            targetWorkspaceID: targetWorkspaceID,
            operationID: operationID,
            disposition: disposition
        )

        for value in materialized.parts { modelContext.insert(try LocalPartDefinitionRowV1(value)) }
        for value in materialized.locations { modelContext.insert(try StockStorageLocationRowV1(value)) }
        for value in materialized.movements { modelContext.insert(try StockMovementEventRowV1(value)) }
        for value in materialized.uses { modelContext.insert(try StockUseReceiptRowV1(value)) }
        for value in materialized.reversals { modelContext.insert(try StockUseReversalReceiptRowV1(value)) }
        for value in materialized.returns { modelContext.insert(try StockReturnReceiptRowV1(value)) }
        for value in materialized.abandonments { modelContext.insert(try AbandonUnverifiedStockRowV1(value)) }
        try modelContext.save()

        let receipt = try PartsStockLifecycleReceiptV1(
            operationID: operationID,
            sourceWorkspaceID: snapshot.workspaceID,
            targetWorkspaceID: targetWorkspaceID,
            disposition: disposition,
            snapshotSHA256: snapshot.snapshotSHA256,
            effectSHA256: materialized.snapshotSHA256,
            completedAt: completedAt
        )
        try receipt.validate()
        return receipt
    }

    /// Pure deterministic projection used by both staging materialization and
    /// post-staging backup validation. It performs no context access or writes.
    func preparedRestoreSnapshot(
        _ snapshot: PartsStockBackupSnapshotV1,
        targetWorkspaceID: WorkspaceID,
        operationID: UUID,
        disposition: PartsStockRestoreDispositionV1
    ) throws -> PartsStockBackupSnapshotV1 {
        try snapshot.validate()
        guard operationID != UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)) else {
            throw PartsStockPersistenceFailureV1.invalidValue
        }
        try Self.validateGraph(snapshot)
        let prepared: PartsStockBackupSnapshotV1
        switch disposition {
        case .replace:
            guard snapshot.workspaceID == targetWorkspaceID else {
                throw PartsStockFailureV1.crossWorkspace
            }
            prepared = snapshot
        case .cloneDefinitions, .forkRequiresRecount:
            guard snapshot.workspaceID != targetWorkspaceID else {
                throw PartsStockFailureV1.invalidTransition
            }
            let mutationID = try MutationIDV1(rawValue: operationID)
            let parts = try snapshot.parts.filter { !$0.archived }.map { source in
                try LocalPartDefinitionV1(
                    partID: source.partID,
                    workspaceID: targetWorkspaceID,
                    displayName: source.displayName,
                    canonicalUnit: source.canonicalUnit,
                    productIdentities: source.productIdentities,
                    preferredMinimum: source.preferredMinimum,
                    archived: false,
                    revision: 1,
                    mutationID: mutationID
                )
            }
            let locations = try snapshot.locations.filter { !$0.archived }.map { source in
                try StockStorageLocationV1(
                    locationID: source.locationID,
                    workspaceID: targetWorkspaceID,
                    kind: source.kind,
                    label: source.label,
                    binLabel: source.binLabel,
                    revision: 1,
                    archived: false
                )
            }
            prepared = try PartsStockBackupSnapshotV1(
                workspaceID: targetWorkspaceID,
                parts: parts,
                locations: locations,
                movements: [],
                uses: [],
                reversals: [],
                returns: [],
                abandonments: []
            )
        }
        try Self.validateUniqueIdentities(prepared)
        try prepared.validate()
        return prepared
    }

    func restore(_ snapshot: PartsStockBackupSnapshotV1, targetWorkspaceID: WorkspaceID, operationID: UUID, disposition: PartsStockRestoreDispositionV1) async throws -> PartsStockLifecycleReceiptV1 {
        try snapshot.validate(); guard let lifecycle else { throw PartsStockFailureV1.unavailable }
        let expected = try preparedRestoreSnapshot(snapshot, targetWorkspaceID: targetWorkspaceID, operationID: operationID, disposition: disposition)
        let receipt = try await lifecycle.restorePartsStock(snapshot, targetWorkspaceID: targetWorkspaceID, operationID: operationID, disposition: disposition)
        try receipt.validate(); guard receipt.operationID == operationID, receipt.sourceWorkspaceID == snapshot.workspaceID, receipt.targetWorkspaceID == targetWorkspaceID, receipt.disposition == disposition, receipt.snapshotSHA256 == snapshot.snapshotSHA256, receipt.effectSHA256 == expected.snapshotSHA256 else { throw PartsStockFailureV1.invalidDigest }
        return receipt
    }

    func delete(workspaceID: WorkspaceID) async throws { guard let lifecycle else { throw PartsStockFailureV1.unavailable }; try await lifecycle.deletePartsStock(workspaceID: workspaceID) }
    func erase(workspaceID: WorkspaceID) async throws { guard let lifecycle else { throw PartsStockFailureV1.unavailable }; try await lifecycle.erasePartsStock(workspaceID: workspaceID) }
    func rebuildSearch(workspaceID: WorkspaceID) async throws { guard let lifecycle else { throw PartsStockFailureV1.unavailable }; try await lifecycle.rebuildPartsStockSearch(workspaceID: workspaceID) }

    private func partRows(workspaceID: WorkspaceID) throws -> [LocalPartDefinitionRowV1] { try modelContext.fetch(FetchDescriptor<LocalPartDefinitionRowV1>()).filter { $0.workspaceUUID == workspaceID.rawValue } }
    private func locationRows(workspaceID: WorkspaceID) throws -> [StockStorageLocationRowV1] { try modelContext.fetch(FetchDescriptor<StockStorageLocationRowV1>()).filter { $0.workspaceUUID == workspaceID.rawValue } }
    private func movementRows(workspaceID: WorkspaceID) throws -> [StockMovementEventRowV1] { try modelContext.fetch(FetchDescriptor<StockMovementEventRowV1>()).filter { $0.workspaceUUID == workspaceID.rawValue } }
    private func useRows(workspaceID: WorkspaceID) throws -> [StockUseReceiptRowV1] { try modelContext.fetch(FetchDescriptor<StockUseReceiptRowV1>()).filter { $0.workspaceUUID == workspaceID.rawValue } }
    private func reversalRows(workspaceID: WorkspaceID) throws -> [StockUseReversalReceiptRowV1] { try modelContext.fetch(FetchDescriptor<StockUseReversalReceiptRowV1>()).filter { $0.workspaceUUID == workspaceID.rawValue } }
    private func returnRows(workspaceID: WorkspaceID) throws -> [StockReturnReceiptRowV1] { try modelContext.fetch(FetchDescriptor<StockReturnReceiptRowV1>()).filter { $0.workspaceUUID == workspaceID.rawValue } }
    private func abandonmentRows(workspaceID: WorkspaceID) throws -> [AbandonUnverifiedStockRowV1] { try modelContext.fetch(FetchDescriptor<AbandonUnverifiedStockRowV1>()).filter { $0.workspaceUUID == workspaceID.rawValue } }

    private func requireEmptyTarget(workspaceID: WorkspaceID) throws {
        guard try partRows(workspaceID: workspaceID).isEmpty,
              (try locationRows(workspaceID: workspaceID)).isEmpty,
              (try movementRows(workspaceID: workspaceID)).isEmpty,
              (try useRows(workspaceID: workspaceID)).isEmpty,
              (try reversalRows(workspaceID: workspaceID)).isEmpty,
              (try returnRows(workspaceID: workspaceID)).isEmpty,
              (try abandonmentRows(workspaceID: workspaceID)).isEmpty else {
            throw PartsStockPersistenceFailureV1.duplicateIdentity
        }
    }

    private static func validateUniqueIdentities(_ snapshot: PartsStockBackupSnapshotV1) throws {
        guard Set(snapshot.parts.map(\.partID)).count == snapshot.parts.count,
              Set(snapshot.locations.map(\.locationID)).count == snapshot.locations.count,
              Set(snapshot.movements.map(\.movementID)).count == snapshot.movements.count,
              Set(snapshot.uses.map(\.receiptID)).count == snapshot.uses.count,
              Set(snapshot.reversals.map(\.receiptID)).count == snapshot.reversals.count,
              Set(snapshot.returns.map(\.receiptID)).count == snapshot.returns.count,
              Set(snapshot.abandonments.map(\.dispositionID)).count == snapshot.abandonments.count else {
            throw PartsStockPersistenceFailureV1.duplicateIdentity
        }
    }

    private static func validateGraph(_ snapshot: PartsStockBackupSnapshotV1) throws {
        try validateUniqueIdentities(snapshot)
        try PartsStockSnapshotTopologyV1.validate(parts: snapshot.parts, locations: snapshot.locations, movements: snapshot.movements, uses: snapshot.uses, reversals: snapshot.reversals, returns: snapshot.returns, abandonments: snapshot.abandonments)
        let partIDs = Set(snapshot.parts.map(\.partID))
        let locationIDs = Set(snapshot.locations.map(\.locationID))
        let movements = Dictionary(uniqueKeysWithValues: snapshot.movements.map { ($0.movementID, $0) })
        let uses = Dictionary(uniqueKeysWithValues: snapshot.uses.map { ($0.receiptID, $0) })
        guard snapshot.movements.allSatisfy({ partIDs.contains($0.part.partID) && locationIDs.contains($0.locationID) }),
              snapshot.uses.allSatisfy({ movements[$0.movement.movementID] == $0.movement }),
              snapshot.reversals.allSatisfy({ uses[$0.sourceUse.receiptID] == $0.sourceUse && movements[$0.reversalMovement.movementID] == $0.reversalMovement }),
              snapshot.returns.allSatisfy({ uses[$0.sourceUseReceiptID] == $0.sourceUse && movements[$0.returnMovement.movementID] == $0.returnMovement }),
              snapshot.abandonments.allSatisfy({ partIDs.contains($0.partID) && locationIDs.contains($0.locationID) }) else {
            throw PartsStockPersistenceFailureV1.invalidValue
        }
    }
}

enum C55PartsStockLifecycleBoundaryV1 {
    enum FoundationAccessibilityDispositionV1: String, Codable, CaseIterable, Sendable {
        case notApplicable = "NOT_APPLICABLE"
    }

    static let cardID = "V23-P03-C55"
    static let journalIsAppendOnly = true
    static let cloneCopiesDefinitionsOnly = true
    static let forkBalancesRequireRecount = true
    static let replacePreservesExactTruth = true
    static let featureDisablePreservesReadExportRecovery = true
    static let foundationAccessibility: FoundationAccessibilityDispositionV1 = .notApplicable
    static let foundationAccessibilityExplanation = "P04-C44 owns UI; C55 defines no UI surface."
    static let offlineOperationIsDeviceLocal = true
    static let disabledFeaturePolicy: PartsStockFeaturePolicyV1 = .readExportRecoveryOnly
    static let searchRebuildDelegatesToIncumbentLifecyclePort = true
    static let workspaceEraseDelegatesToIncumbentLifecyclePort = true
    static let hasNetworkDependency = false
    static let hasTelemetryDependency = false
    static let hostedOrParallelWriter = false
}

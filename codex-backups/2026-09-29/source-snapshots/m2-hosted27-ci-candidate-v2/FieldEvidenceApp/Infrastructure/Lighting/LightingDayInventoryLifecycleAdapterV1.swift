import Foundation
import SwiftData

/// Narrow bridge to the one incumbent canonical writer.  It owns neither a
/// second store nor a receipt family; physical reads are from the supplied
/// existing ModelContext only.
@MainActor
protocol LightingDayInventoryCanonicalWorkspaceWritingV1: AnyObject {
    func commitLightingDayInventory(
        _ operation: LightingDayInventoryWriteOperationV1
    ) throws -> MutationReceiptV1
}

@MainActor
final class LightingDayInventoryLifecycleAdapterV1:
    LightingDayInventoryMutationAuthorityV1,
    LightingDayInventoryQueryingV1
{
    private let modelContext: ModelContext
    private let writer: any LightingDayInventoryCanonicalWorkspaceWritingV1

    init(
        modelContext: ModelContext,
        writer: any LightingDayInventoryCanonicalWorkspaceWritingV1
    ) {
        self.modelContext = modelContext
        self.writer = writer
    }

    func commit(_ operation: LightingDayInventoryWriteOperationV1) async throws -> MutationReceiptV1 {
        try operation.validate()
        let receipt = try writer.commitLightingDayInventory(operation)
        _ = try LightingDayInventoryMutationReceiptV1(
            operation: operation,
            mutationReceipt: receipt
        )
        return receipt
    }

    func latestWorkflow(
        workspaceID: WorkspaceID,
        workflowID: UUID
    ) async throws -> LightingDayInventoryWorkflowV1? {
        let values = try modelContext.fetch(FetchDescriptor<LightingDayInventoryWorkflowRowV1>())
            .map { try $0.value() }
            .filter { $0.workspaceID == workspaceID && $0.workflowID == workflowID }
        guard Set(values.map(\.recordID)).count == values.count else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        guard !values.isEmpty else { return nil }
        let roots = values.filter { $0.supersedesRecordID == nil }
        guard roots.count == 1, let root = roots.first else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        var current = root
        var visited: Set<UUID> = [root.recordID]
        while let successor = values.first(where: { $0.supersedesRecordID == current.recordID }) {
            guard !visited.contains(successor.recordID) else {
                throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
            }
            try successor.validateSuccessor(of: current)
            visited.insert(successor.recordID)
            current = successor
        }
        guard visited.count == values.count else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        return current
    }

    func projection(
        workspaceID: WorkspaceID,
        workflowID: UUID
    ) async throws -> LightingDayInventoryProjectionV1? {
        guard let value = try await latestWorkflow(workspaceID: workspaceID, workflowID: workflowID) else {
            return nil
        }
        return try LightingDayInventoryProjectionV1(value)
    }
}

/// Clone/fork receives a new generation and therefore must not activate any
/// source-occurrence or source readiness claim.  The canonical backup/restore
/// lane performs the physical rebind; this adapter never synthesizes one.
enum LightingDayInventoryLifecycleDispositionV1 {
    static let cloneAndForkRebindsGeneration = true
    static let cloneAndForkActivatesSourceNightOccurrence = false
    static let cloneAndForkActivatesSourceReadiness = false
    static let offlineReadinessIsDerivedOnly = true
    static let hardSafetyStopIsDurableAuditTruth = true
    static let hardSafetyStopAuthorizesObservation = false
}

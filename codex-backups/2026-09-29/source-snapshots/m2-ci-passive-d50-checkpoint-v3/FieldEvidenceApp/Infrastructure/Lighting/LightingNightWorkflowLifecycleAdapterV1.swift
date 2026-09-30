import Foundation
import SwiftData

/// C18 delegates every write to the incumbent canonical WorkspaceWriter path.
/// This adapter only supplies physical query parity for the one workflow row.
@MainActor
protocol LightingNightWorkflowCanonicalWorkspaceWritingV1: AnyObject {
    func commitLightingNightWorkflow(
        _ operation: LightingNightWorkflowWriteOperationV1
    ) throws -> MutationReceiptV1
}

@MainActor
final class LightingNightWorkflowLifecycleAdapterV1:
    LightingNightWorkflowMutationAuthorityV1,
    LightingNightWorkflowQueryingV1
{
    private let modelContext: ModelContext
    private let writer: any LightingNightWorkflowCanonicalWorkspaceWritingV1

    init(modelContext: ModelContext,
         writer: any LightingNightWorkflowCanonicalWorkspaceWritingV1) {
        self.modelContext = modelContext
        self.writer = writer
    }

    func commit(
        _ operation: LightingNightWorkflowWriteOperationV1
    ) async throws -> MutationReceiptV1 {
        try operation.validate()
        let receipt = try writer.commitLightingNightWorkflow(operation)
        _ = try LightingNightWorkflowMutationReceiptV1(
            operation: operation, mutationReceipt: receipt
        )
        return receipt
    }

    func latestLightingNightWorkflow(
        workspaceID: WorkspaceID,
        workflowID: UUID
    ) async throws -> LightingNightWorkflowV1? {
        let values = try modelContext.fetch(FetchDescriptor<LightingNightWorkflowRowV1>())
            .map { try $0.value() }
            .filter { $0.workspaceID == workspaceID && $0.workflowID == workflowID }
        guard Set(values.map(\.recordID)).count == values.count else {
            throw LightingNightWorkflowFailureV1.duplicateIdentity
        }
        guard !values.isEmpty else { return nil }
        let ordered = values.sorted { $0.revision < $1.revision }
        guard ordered.first?.revision == 1,
              Set(ordered.map(\.revision)).count == ordered.count else {
            throw LightingNightWorkflowFailureV1.invalidSuccessor
        }
        for index in ordered.indices.dropFirst() {
            try ordered[index].validateSuccessor(of: ordered[ordered.index(before: index)])
        }
        return ordered.last
    }
}

enum LightingNightWorkflowLifecycleBoundaryV1 {
    static let persistentSchemaVersion = 53
    static let durableFamilyCount = 1
    static let genericMutationReceiptIsSoleReceiptOwner = true
    static let repairPolicyIsNonRow = true
    static let reportSearchAndReadinessAreDerived = true
    static let downgradeDisposition = "PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_ACTIVATION"
}

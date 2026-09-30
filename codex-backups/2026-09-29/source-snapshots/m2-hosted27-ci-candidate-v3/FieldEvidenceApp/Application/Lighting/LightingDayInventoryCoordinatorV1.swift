import Foundation

protocol LightingDayInventoryQueryingV1: Sendable {
    func latestWorkflow(workspaceID: WorkspaceID, workflowID: UUID) async throws -> LightingDayInventoryWorkflowV1?
}

enum LightingDayInventoryWriteOperationV1: Codable, Equatable, Sendable {
    case appendWorkflow(value: LightingDayInventoryWorkflowV1,
                        predecessor: LightingDayInventoryWorkflowV1?,
                        admission: LightingDayInventoryAdmissionClosureV1)

    var workspaceID: WorkspaceID { switch self { case .appendWorkflow(let value, _, _): value.workspaceID } }
    var mutationID: MutationIDV1 { switch self { case .appendWorkflow(let value, _, _): value.mutationID } }
    var workflow: LightingDayInventoryWorkflowV1 { switch self { case .appendWorkflow(let value, _, _): value } }

    func validate() throws {
        switch self {
        case .appendWorkflow(let value, let predecessor, let admission):
            try admission.validate(value)
            if let predecessor { try value.validateSuccessor(of: predecessor) }
            else if value.revision != 1 { throw LightingDayInventoryFailureV1.invalidSuccessor }
        }
    }
}

@MainActor
protocol LightingDayInventoryMutationAuthorityV1: AnyObject {
    func commit(_ operation: LightingDayInventoryWriteOperationV1) async throws -> MutationReceiptV1
}

struct LightingDayInventoryWriteReceiptV1: Codable, Equatable, Sendable {
    let workflowID: UUID
    let workflowRevision: UInt64
    let workflowSHA256: String
    let mutationReceiptIdentity: MutationReceiptIdentityV1
    let mutationReceiptSHA256: String
    let committedAt: Date

    init(operation: LightingDayInventoryWriteOperationV1, mutationReceipt: MutationReceiptV1) throws {
        try operation.validate(); try mutationReceipt.validate()
        let value = operation.workflow
        guard mutationReceipt.identity.workspaceID == operation.workspaceID,
              mutationReceipt.mutationID == operation.mutationID else {
            throw LightingDayInventoryFailureV1.staleReference
        }
        workflowID=value.workflowID;workflowRevision=value.revision;workflowSHA256=value.workflowSHA256
        mutationReceiptIdentity=mutationReceipt.identity
        mutationReceiptSHA256=try mutationReceipt.canonicalSHA256();committedAt=mutationReceipt.committedAt
    }
}

@MainActor
final class LightingDayInventoryCoordinatorV1 {
    private let query: any LightingDayInventoryQueryingV1
    private let authority: any LightingDayInventoryMutationAuthorityV1
    init(query: any LightingDayInventoryQueryingV1,
         authority: any LightingDayInventoryMutationAuthorityV1) {
        self.query=query;self.authority=authority
    }

    func append(_ value: LightingDayInventoryWorkflowV1,
                admission: LightingDayInventoryAdmissionClosureV1) async throws -> LightingDayInventoryWriteReceiptV1 {
        let predecessor=try await query.latestWorkflow(workspaceID:value.workspaceID,workflowID:value.workflowID)
        let operation=LightingDayInventoryWriteOperationV1.appendWorkflow(value:value,predecessor:predecessor,admission:admission)
        try operation.validate()
        let receipt=try await authority.commit(operation)
        return try .init(operation:operation,mutationReceipt:receipt)
    }

    func projection(for value: LightingDayInventoryWorkflowV1) throws -> LightingDayInventoryProjectionV1 {
        try .init(value)
    }
    func reportProjection(for value:LightingDayInventoryWorkflowV1)throws->LightingDayInventoryReportProjectionV1{try .init(value)}
    func searchProjection(for value:LightingDayInventoryWorkflowV1)throws->LightingDayInventorySearchProjectionV1{try .init(value)}
    func readinessProjection(for value:LightingDayInventoryWorkflowV1)throws->LightingNightReadinessProjectionV1{try .init(value)}
}

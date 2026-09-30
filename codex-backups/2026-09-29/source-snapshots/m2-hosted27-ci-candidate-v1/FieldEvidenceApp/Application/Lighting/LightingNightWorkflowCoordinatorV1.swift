import Foundation

protocol LightingNightWorkflowQueryingV1: Sendable {
    func latestLightingNightWorkflow(workspaceID: WorkspaceID,
                                     workflowID: UUID) async throws -> LightingNightWorkflowV1?
}

enum LightingNightWorkflowWriteOperationV1: Codable, Equatable, Sendable {
    case appendWorkflow(value: LightingNightWorkflowV1,
                        predecessor: LightingNightWorkflowV1?,
                        admission: LightingNightWorkflowAdmissionClosureV1)

    var workflow: LightingNightWorkflowV1 {
        switch self { case .appendWorkflow(let value, _, _): return value }
    }
    var workspaceID: WorkspaceID { workflow.workspaceID }
    var mutationID: MutationIDV1 { workflow.mutationID }

    func validate() throws {
        switch self {
        case .appendWorkflow(let value, let predecessor, let admission):
            try admission.validate(value)
            if let predecessor { try value.validateSuccessor(of: predecessor) }
            else if value.revision != 1 { throw LightingNightWorkflowFailureV1.invalidSuccessor }
        }
    }
}

@MainActor
protocol LightingNightWorkflowMutationAuthorityV1: AnyObject {
    func commit(_ operation: LightingNightWorkflowWriteOperationV1) async throws -> MutationReceiptV1
}

struct LightingNightWorkflowWriteReceiptV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID
    let workflowID: UUID
    let workflowRevision: UInt64
    let workflowSHA256: String
    let mutationReceiptIdentity: MutationReceiptIdentityV1
    let mutationReceiptSHA256: String
    let committedAt: Date

    init(operation: LightingNightWorkflowWriteOperationV1,
         mutationReceipt: MutationReceiptV1) throws {
        try operation.validate(); try mutationReceipt.validate()
        let workflow = operation.workflow
        guard mutationReceipt.identity.workspaceID == workflow.workspaceID,
              mutationReceipt.mutationID == workflow.mutationID else {
            throw LightingNightWorkflowFailureV1.staleReference
        }
        workspaceID = workflow.workspaceID; workflowID = workflow.workflowID
        workflowRevision = workflow.revision; workflowSHA256 = workflow.workflowSHA256
        mutationReceiptIdentity = mutationReceipt.identity
        mutationReceiptSHA256 = try mutationReceipt.canonicalSHA256()
        committedAt = mutationReceipt.committedAt
    }
}

enum LightingNightWorkflowQueryV1: Codable, Equatable, Sendable {
    case workflow(workspaceID: WorkspaceID, workflowID: UUID)
    case report(workspaceID: WorkspaceID, workflowID: UUID)
}

enum LightingNightWorkflowProjectionV1: Codable, Equatable, Sendable {
    case workflow(LightingNightWorkflowV1)
    case report(LightingReportProjectionV1)

    func validate(for query: LightingNightWorkflowQueryV1) throws {
        switch (query, self) {
        case (.workflow(let workspaceID, let workflowID), .workflow(let value)):
            try value.validateIntrinsic()
            guard value.workspaceID == workspaceID, value.workflowID == workflowID else {
                throw LightingNightWorkflowFailureV1.wrongWorkspace
            }
        case (.report(let workspaceID, let workflowID), .report(let value)):
            guard value.workspaceID == workspaceID, value.workflowID == workflowID else {
                throw LightingNightWorkflowFailureV1.wrongWorkspace
            }
        default:
            throw LightingNightWorkflowFailureV1.invalidValue
        }
    }
}

@MainActor
final class LightingNightWorkflowCoordinatorV1 {
    private let query: any LightingNightWorkflowQueryingV1
    private let sourceResolver: any LightingNightWorkflowSourceResolvingV1
    private let authority: any LightingNightWorkflowMutationAuthorityV1

    init(query: any LightingNightWorkflowQueryingV1,
         sourceResolver: any LightingNightWorkflowSourceResolvingV1,
         authority: any LightingNightWorkflowMutationAuthorityV1) {
        self.query = query; self.sourceResolver = sourceResolver; self.authority = authority
    }

    func append(_ value: LightingNightWorkflowV1,
                admission: LightingNightWorkflowAdmissionClosureV1) async throws -> LightingNightWorkflowWriteReceiptV1 {
        guard value.safety.observationIsAuthorized else { throw LightingNightWorkflowFailureV1.safetyStop }
        try await sourceResolver.validateCanonicalSources(for: value, admission: admission)
        let predecessor = try await query.latestLightingNightWorkflow(
            workspaceID: value.workspaceID, workflowID: value.workflowID)
        let operation = LightingNightWorkflowWriteOperationV1.appendWorkflow(
            value: value, predecessor: predecessor, admission: admission)
        try operation.validate()
        let receipt = try await authority.commit(operation)
        return try .init(operation: operation, mutationReceipt: receipt)
    }

    func workflow(workspaceID: WorkspaceID, workflowID: UUID) async throws -> LightingNightWorkflowV1? {
        let value = try await query.latestLightingNightWorkflow(workspaceID: workspaceID, workflowID: workflowID)
        try value?.validateIntrinsic()
        if let value, value.workspaceID != workspaceID || value.workflowID != workflowID {
            throw LightingNightWorkflowFailureV1.wrongWorkspace
        }
        return value
    }

    func reportProjection(for workflow: LightingNightWorkflowV1) throws -> LightingReportProjectionV1 {
        try .init(workflow)
    }
}

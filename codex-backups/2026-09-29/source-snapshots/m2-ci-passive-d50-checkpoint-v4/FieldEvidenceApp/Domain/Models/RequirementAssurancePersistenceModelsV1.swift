import Foundation
import SwiftData

enum RequirementAssurancePersistenceReleaseV1: Int, Codable, CaseIterable, Sendable {
    case v8 = 8
    static let predecessorSchemaVersion = 7
    static let canonicalSemanticLabel = "REQUIREMENT_ASSURANCE_V1"
}

/// The single canonical assurance companion for a WorkflowRecord. Item-level
/// evaluations remain typed values; this is neither an EAV table nor arbitrary
/// JSON authority.
@Model
final class RequirementAssuranceRow {
    @Attribute(.unique) private(set) var workflowRecordID: UUID
    private(set) var schemaVersion: Int
    private(set) var workspaceID: UUID
    private(set) var evaluatedRevision: Int64
    private(set) var policySetSHA256: String
    private(set) var evaluations: [RequirementEvaluationV1]
    private(set) var findings: [IntegrityFindingV1]
    private(set) var decision: CompletionDecisionV1
    private(set) var snapshotSHA256: String
    private(set) var mutationID: UUID
    private(set) var createdAt: Date
    private(set) var updatedAt: Date

    init(
        snapshot: RequirementAssuranceSnapshotV1,
        mutationID: UUID,
        createdAt: Date,
        updatedAt: Date
    ) throws {
        try snapshot.validate()
        guard snapshot.evaluatedRevision <= UInt64(Int64.max),
              mutationID != Self.zero, createdAt <= updatedAt else {
            throw RequirementAssuranceFailureV1.invalidValue
        }
        schemaVersion = RequirementAssuranceSnapshotV1.schemaVersion
        workflowRecordID = snapshot.workflowRecordID
        workspaceID = snapshot.workspaceID
        evaluatedRevision = Int64(snapshot.evaluatedRevision)
        policySetSHA256 = snapshot.policySetSHA256
        evaluations = snapshot.evaluations
        findings = snapshot.findings
        decision = snapshot.decision
        snapshotSHA256 = snapshot.snapshotSHA256
        self.mutationID = mutationID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func snapshot() throws -> RequirementAssuranceSnapshotV1 {
        guard schemaVersion == RequirementAssuranceSnapshotV1.schemaVersion,
              evaluatedRevision > 0, mutationID != Self.zero, createdAt <= updatedAt else {
            throw RequirementAssuranceFailureV1.incompatibleVersion
        }
        let value = try RequirementAssuranceSnapshotV1(
            workflowRecordID: workflowRecordID,
            workspaceID: workspaceID,
            evaluatedRevision: UInt64(evaluatedRevision),
            policySetSHA256: policySetSHA256,
            evaluations: evaluations,
            findings: findings,
            decision: decision
        )
        guard value.snapshotSHA256 == snapshotSHA256 else {
            throw RequirementAssuranceFailureV1.digestMismatch
        }
        return value
    }

    func currentDecision() throws -> CompletionDecisionV1 {
        try snapshot().decision
    }

    /// Called only inside the canonical writer transaction after its expected
    /// workspace revision and MutationID checks have succeeded.
    func replace(
        with snapshot: RequirementAssuranceSnapshotV1,
        expectedRevision: UInt64,
        mutationID: UUID,
        updatedAt: Date
    ) throws {
        let current = try self.snapshot()
        guard current.evaluatedRevision == expectedRevision else {
            throw RequirementAssuranceFailureV1.staleRevision
        }
        guard expectedRevision < UInt64.max else {
            throw RequirementAssuranceFailureV1.revisionOverflow
        }
        guard snapshot.workflowRecordID == workflowRecordID,
              snapshot.workspaceID == workspaceID,
              snapshot.evaluatedRevision == expectedRevision + 1,
              snapshot.evaluatedRevision <= UInt64(Int64.max),
              mutationID != Self.zero,
              updatedAt >= self.updatedAt else {
            throw RequirementAssuranceFailureV1.invalidValue
        }
        try snapshot.validate()
        evaluatedRevision = Int64(snapshot.evaluatedRevision)
        policySetSHA256 = snapshot.policySetSHA256
        evaluations = snapshot.evaluations
        findings = snapshot.findings
        decision = snapshot.decision
        snapshotSHA256 = snapshot.snapshotSHA256
        self.mutationID = mutationID
        self.updatedAt = updatedAt
    }

    /// Migration/backfill posture for a pre-assurance WorkflowRecord. It is
    /// deliberately UNKNOWN and blocking until canonical inputs are evaluated.
    static func blockingUnknownBackfill(
        workflowRecordID: UUID,
        workspaceID: UUID,
        evaluatedRevision: UInt64,
        requirementID: String,
        requirementVersion: Int,
        requirementTypeID: String,
        policySHA256: String,
        mutationID: UUID,
        timestamp: Date
    ) throws -> RequirementAssuranceRow {
        let definition = try RequirementDefinitionV1(
            requirementID: requirementID,
            requirementVersion: requirementVersion,
            requirementTypeID: requirementTypeID,
            policySHA256: policySHA256,
            gateEffect: .hardBlocker,
            allowsNotApplicable: false
        )
        let evaluation = try RequirementEvaluationV1(
            definition: definition,
            evaluatedRevision: evaluatedRevision,
            result: .unknown,
            reasonCodes: [.unansweredRequirement]
        )
        let evaluations = [evaluation]
        let policySetSHA256 = try RequirementEvaluationEngineV1.policySetSHA256(evaluations)
        let decision = try CompletionDecisionV1(
            evaluatedRevision: evaluatedRevision,
            policySetSHA256: policySetSHA256,
            disposition: .blocked,
            hardBlockerRequirementIDs: [requirementID],
            warningRequirementIDs: [],
            notApplicableRequirementIDs: [],
            unknownRequirementIDs: [requirementID],
            waivedRequirementIDs: [],
            evaluationSetSHA256: try RequirementAssuranceCanonicalV1.sha256(evaluations)
        )
        let finding = try IntegrityFindingV1(
            kind: .unansweredRequirement,
            requirementID: requirementID,
            reasonCode: "unanswered_requirement"
        )
        let snapshot = try RequirementAssuranceSnapshotV1(
            workflowRecordID: workflowRecordID,
            workspaceID: workspaceID,
            evaluatedRevision: evaluatedRevision,
            policySetSHA256: policySetSHA256,
            evaluations: evaluations,
            findings: [finding],
            decision: decision
        )
        return try RequirementAssuranceRow(
            snapshot: snapshot,
            mutationID: mutationID,
            createdAt: timestamp,
            updatedAt: timestamp
        )
    }

    private static let zero = UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))
}

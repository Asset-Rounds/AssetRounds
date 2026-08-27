import Foundation

enum AuthorityCriterionCoordinatorFailureV1: Error, Equatable, Sendable {
    case invalidMutation
    case wrongWorkspace
    case staleRevision
    case receiptMismatch
}

struct PreparedAuthorityCriterionMutationV1: Equatable, Sendable {
    let mutation: AuthorityCriterionMutationV1
    let command: WorkspaceCommandV1
    let canonicalSHA256: String

    init(mutation: AuthorityCriterionMutationV1) throws {
        do { try mutation.validate() } catch {
            throw AuthorityCriterionCoordinatorFailureV1.invalidMutation
        }
        self.mutation = mutation
        command = .applyAuthorityCriterion(mutation)
        canonicalSHA256 = try mutation.canonicalSHA256()
    }

    func validate() throws {
        try mutation.validate()
        guard command == .applyAuthorityCriterion(mutation),
              canonicalSHA256 == (try mutation.canonicalSHA256()) else {
            throw AuthorityCriterionCoordinatorFailureV1.invalidMutation
        }
    }
}

enum AuthorityCriterionCoordinatorV1 {
    static func prepare(
        workspaceID: WorkspaceID,
        expectedRevision: UInt64,
        payload: AuthorityCriterionMutationPayloadV1
    ) throws -> PreparedAuthorityCriterionMutationV1 {
        do { try payload.validate() } catch {
            throw AuthorityCriterionCoordinatorFailureV1.invalidMutation
        }
        guard payload.workspaceID == workspaceID else {
            throw AuthorityCriterionCoordinatorFailureV1.wrongWorkspace
        }
        guard expectedRevision < UInt64.max,
              payload.revision == expectedRevision + 1 else {
            throw AuthorityCriterionCoordinatorFailureV1.staleRevision
        }
        return try PreparedAuthorityCriterionMutationV1(mutation: .init(
            workspaceID: workspaceID,
            expectedRevision: expectedRevision,
            mutationID: payload.mutationID,
            postImage: payload
        ))
    }

    static func validate(
        outcome: WorkspaceMutationOutcomeV1,
        for prepared: PreparedAuthorityCriterionMutationV1
    ) throws {
        try prepared.validate()
        let concurrencyIdentity = try prepared.mutation.concurrencyIdentity
        let affectedIdentity = try prepared.mutation.affectedIdentity
        let beforeRevision = outcome.before.entityRevisions
            .first(where: { $0.identity == concurrencyIdentity })?.revision ?? 0
        let afterRevision = outcome.after.entityRevisions
            .first(where: { $0.identity == affectedIdentity })?.revision
        guard outcome.mutationID == prepared.mutation.mutationID,
              beforeRevision == prepared.mutation.expectedRevision,
              afterRevision == prepared.mutation.postImage.revision,
              MutationEnvelopeV1.isSHA256(outcome.commandDigest) else {
            throw AuthorityCriterionCoordinatorFailureV1.receiptMismatch
        }
    }
}

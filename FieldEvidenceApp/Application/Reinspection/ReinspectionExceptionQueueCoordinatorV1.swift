import Foundation

/// Production C12 coordinator. It owns no queue store: plans, attestations,
/// and acknowledgement history pass to the incumbent writer, while the queue
/// is always obtained from the injected canonical projection query.
@MainActor
final class ReinspectionExceptionQueueCoordinatorV1 {
    enum ActionResult: Equatable, Sendable {
        case planSaved(ReinspectionPlanV1, ReinspectionExceptionMutationReceiptV1)
        case attestationSaved(UnchangedAttestationV1, ReinspectionExceptionMutationReceiptV1)
        case acknowledgementSaved(ExceptionQueueAcknowledgementV1, ReinspectionExceptionMutationReceiptV1)
    }

    private let writer: WorkspaceWriterV1

    init(writer: WorkspaceWriterV1) {
        self.writer = writer
    }

    func preview(
        _ request: ReinspectionExceptionQueryV1,
        providers: [any ExceptionQueueCanonicalSourceProvidingV1]
    ) throws -> ReinspectionExceptionQueryResultV1 {
        try request.validate()
        return try writer.reinspectionExceptionQuery(request, providers: providers)
    }

    func savePlan(
        _ plan: ReinspectionPlanV1,
        predecessor: ReinspectionPlanV1?,
        expectedRevision: WorkspaceExpectedRevisionV1,
        mutationID: MutationIDV1,
        submittedAt: Date
    ) throws -> ActionResult {
        let command = try ReinspectionExceptionMutationCommandV1(
            commandID: UUID(), workspaceID: plan.workspaceID, expectedRevision: expectedRevision,
            mutationID: mutationID, payload: .putPlan(plan, predecessor), submittedAt: submittedAt
        )
        let receipt = try writer.commitReinspectionException(command)
        return .planSaved(plan, receipt)
    }

    func saveUnchangedAttestation(
        _ attestation: UnchangedAttestationV1,
        plan: ReinspectionPlanV1,
        expectedRevision: WorkspaceExpectedRevisionV1,
        mutationID: MutationIDV1,
        submittedAt: Date
    ) throws -> ActionResult {
        let command = try ReinspectionExceptionMutationCommandV1(
            commandID: UUID(), workspaceID: attestation.workspaceID, expectedRevision: expectedRevision,
            mutationID: mutationID, payload: .recordAttestation(attestation, plan), submittedAt: submittedAt
        )
        let receipt = try writer.commitReinspectionException(command)
        return .attestationSaved(attestation, receipt)
    }

    func saveAcknowledgement(
        _ acknowledgement: ExceptionQueueAcknowledgementV1,
        source: ExceptionQueueSourceSnapshotV1,
        predecessor: ExceptionQueueAcknowledgementV1?,
        expectedRevision: WorkspaceExpectedRevisionV1,
        mutationID: MutationIDV1,
        submittedAt: Date
    ) throws -> ActionResult {
        let command = try ReinspectionExceptionMutationCommandV1(
            commandID: UUID(), workspaceID: acknowledgement.workspaceID, expectedRevision: expectedRevision,
            mutationID: mutationID, payload: .recordAcknowledgement(acknowledgement, source, predecessor), submittedAt: submittedAt
        )
        let receipt = try writer.commitReinspectionException(command)
        return .acknowledgementSaved(acknowledgement, receipt)
    }
}

import Foundation

@MainActor protocol LocalReminderReconciliationApplyingV1: AnyObject {
    func reconcile(_ projection: ReminderProjectionV1) async throws -> LocalReminderReconciliationV1
    func removeAll(workspaceID: WorkspaceID) async throws
}

/// C22 application composition. Canonical writes remain owned by
/// `ScheduleCoordinatorV1`; reminder reconciliation is disposable device state.
@MainActor final class RecurringRoundExperienceCoordinatorV1 {
    private let schedule: ScheduleCoordinatorV1
    private let reminders: any LocalReminderReconciliationApplyingV1

    init(schedule: ScheduleCoordinatorV1,
         reminders: any LocalReminderReconciliationApplyingV1) {
        self.schedule = schedule; self.reminders = reminders
    }

    func editor(release: ScheduleDefinitionReleaseV1) throws -> ScheduleEditorStateV1 {
        try .init(release: release)
    }

    func publish(_ release: ScheduleDefinitionReleaseV1,
                 predecessor: ScheduleDefinitionReleaseV1?) throws -> ScheduleMutationReceiptV1 {
        try schedule.publish(release, predecessor: predecessor)
    }

    func dueQueue(workspaceID: WorkspaceID,
                  evaluation: ScheduleProjectionEvaluationV1,
                  definitions: [ScheduleDefinitionReleaseV1],
                  history: [OccurrenceHistoryEventV1]) throws -> OccurrenceDueQueueStateV1 {
        try .init(projection: schedule.dueQueue(workspaceID: workspaceID, evaluation: evaluation,
                                               definitions: definitions, history: history))
    }

    func start(_ request: RecurringRoundStartRequestV1,
               readiness: RecurringRoundStartReadinessV1,
               currentRoundSession: RoundSessionV1? = nil,
               exactWorkPacket: WorkPacketManifestV1? = nil) throws -> RecurringRoundStartReceiptV1 {
        try request.validate()
        try RecurringRoundStartFrontierBoundaryV1.validate(request: request,
            currentRoundSession: currentRoundSession, exactWorkPacket: exactWorkPacket)
        try readiness.requireReady()
        guard readiness.workspaceID == request.event.workspaceID,
              readiness.requestSHA256 == request.requestSHA256,
              readiness.workInstance == request.event.workInstance else {
            throw RecurringRoundExperienceFailureV1.staleSource
        }
        let receipt = try schedule.start(request.event, predecessor: request.predecessor,
                                         release: request.release)
        return try .init(request: request, scheduleReceipt: receipt)
    }

    func reconcileReminders(dueQueue: DueQueueProjectionV1,
                            evaluation: ScheduleProjectionEvaluationV1,
                            localizationKey: String) async throws -> LocalReminderReconciliationV1 {
        let projection = try schedule.reminders(dueQueue: dueQueue, evaluation: evaluation,
                                                localizationKey: localizationKey)
        return try await reminders.reconcile(projection)
    }

    func removeDisposableReminders(workspaceID: WorkspaceID) async throws {
        try await reminders.removeAll(workspaceID: workspaceID)
    }
}

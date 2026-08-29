import Foundation

/// Sole-writer application boundary for C28. Generation plans and projections
/// remain derived; only the closed mutation envelope crosses this boundary.
@MainActor protocol ScheduleCanonicalWritingV1: AnyObject {
    func acceptedScheduleMutation(_ mutation: ScheduleMutationV1) throws -> ScheduleMutationReceiptV1?
    func applySchedule(_ mutation: ScheduleMutationV1) throws -> ScheduleMutationReceiptV1
}

@MainActor final class ScheduleCoordinatorV1 {
    private let writer: any ScheduleCanonicalWritingV1

    init(writer: any ScheduleCanonicalWritingV1) { self.writer = writer }

    func publish(_ release: ScheduleDefinitionReleaseV1,
                 predecessor: ScheduleDefinitionReleaseV1?) throws -> ScheduleMutationReceiptV1 {
        try commit(.init(workspaceID: release.workspaceID, mutationID: release.mutationID,
                         payload: .appendRelease(release, predecessor: predecessor)))
    }

    func record(_ event: OccurrenceHistoryEventV1,
                predecessor: OccurrenceHistoryEventV1?,
                release: ScheduleDefinitionReleaseV1) throws -> ScheduleMutationReceiptV1 {
        try commit(.init(workspaceID: event.workspaceID, mutationID: event.mutationID,
                         payload: .appendOccurrenceEvent(event, predecessor: predecessor, release: release)))
    }

    /// The exact one-time work link and occurrence start share one transaction.
    /// Calling this API is explicit user intent; due projection never starts work.
    func start(_ event: OccurrenceHistoryEventV1,
               predecessor: OccurrenceHistoryEventV1,
               release: ScheduleDefinitionReleaseV1) throws -> ScheduleMutationReceiptV1 {
        try commit(.init(workspaceID: event.workspaceID, mutationID: event.mutationID,
                         payload: .startOccurrence(event, predecessor: predecessor, release: release)))
    }

    func generate(definition: ScheduleDefinitionReleaseV1,
                  history: [OccurrenceHistoryEventV1],
                  completionHistory: [OccurrenceHistoryEventV1],
                  window: OccurrenceGenerationWindowV1,
                  resolver: any ScheduleCalendarResolvingV1,
                  event: (OccurrenceGenerationCandidateV1) throws -> OccurrenceHistoryEventV1) throws -> ScheduleMutationReceiptV1? {
        let plan = try ScheduleOccurrenceGeneratorV1.generate(definition: definition, history: history,
                                                               completionHistory: completionHistory,
                                                               window: window, resolver: resolver)
        guard !plan.candidates.isEmpty else { return nil }
        let events = try plan.candidates.map(event)
        guard let mutationID = events.first?.mutationID,
              events.allSatisfy({ $0.mutationID == mutationID }) else {
            throw ScheduleFailureV1.divergentReplay
        }
        return try commit(.init(workspaceID: definition.workspaceID, mutationID: mutationID,
                                payload: .generateOccurrences(release: definition, plan: plan, events: events)))
    }

    func dueQueue(workspaceID: WorkspaceID, evaluatedAt: Date,
                  definitions: [ScheduleDefinitionReleaseV1],
                  history: [OccurrenceHistoryEventV1]) throws -> DueQueueProjectionV1 {
        try .init(workspaceID: workspaceID, evaluatedAt: evaluatedAt,
                  definitions: definitions, history: history)
    }

    func dueQueue(workspaceID: WorkspaceID,
                  evaluation: ScheduleProjectionEvaluationV1,
                  definitions: [ScheduleDefinitionReleaseV1],
                  history: [OccurrenceHistoryEventV1]) throws -> DueQueueProjectionV1 {
        try .init(workspaceID: workspaceID, evaluatedAt: evaluation.evaluatedAt,
                  definitions: definitions, history: history)
    }

    func reminders(dueQueue: DueQueueProjectionV1,
                   localizationKey: String) throws -> ReminderProjectionV1 {
        try .init(dueQueue: dueQueue, localizationKey: localizationKey)
    }

    func reminders(dueQueue: DueQueueProjectionV1,
                   evaluation: ScheduleProjectionEvaluationV1,
                   localizationKey: String) throws -> ReminderProjectionV1 {
        guard evaluation.evaluatedAt == dueQueue.evaluatedAt,
              evaluation.permitsReminderReconciliation else {
            throw ScheduleFailureV1.staleBasis
        }
        return try .init(dueQueue: dueQueue, localizationKey: localizationKey)
    }

    private func commit(_ mutation: ScheduleMutationV1) throws -> ScheduleMutationReceiptV1 {
        try mutation.validate()
        let expected = try WorkspaceMutationCanonicalV1.sha256(mutation)
        if let accepted = try writer.acceptedScheduleMutation(mutation) {
            guard accepted.mutationSHA256 == expected else { throw ScheduleFailureV1.divergentReplay }
            return accepted
        }
        let receipt = try writer.applySchedule(mutation)
        guard receipt.mutationSHA256 == expected else { throw ScheduleFailureV1.divergentReplay }
        return receipt
    }
}
